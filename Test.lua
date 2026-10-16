-- Latest update: 10/16/2026 11:44 PM

local FLT_MAX = 340282346638528859811704183484516925440
local DBL_MAX = 179769313486231570814527423731704356798070567525844996598917476803157260780028538760589558632766878171540458953514382464234321326889464182768467546703537516986049910576551282076245490090389328944075868508455133942304583236903222948165808559332123348274797826204144723168738177180919299881250404026184124858368

local Players                   = game:GetService("Players")
local me                        = game.Players.LocalPlayer
local ProximityPromptService    = game:GetService("ProximityPromptService")
local ReplicatedStorage         = game:GetService("ReplicatedStorage")
local RunService                = game:GetService("RunService")
local UserInputService          = game:GetService("UserInputService")
local remotes                   = ReplicatedStorage:WaitForChild("Remote")
local chunks                    = remotes:WaitForChild("ChunkLoaded")
local gps                       = remotes:WaitForChild("requestPlayerPosition")

local stretcher, stretcherSeat, stretcherSeatPart, lastTargetPos   = nil, nil, nil, nil

local cachedRemoteLocations = {}
local positions             = {}
local locations             = {
    ["Jail"] = CFrame.new(-489.870941, -106.403572, -2584.94336),
    ["Roadmap"] = CFrame.new(-1481.06, -78.44, -11404.77, -0.19, 0, 0.98, 0, 1, 0, -0.98, 0, -0.19)
}

local RETRY_SECONDS             = 0.1    -- how soon another request may go out
local CHARACTER_RETRY_SECONDS   = 1  -- and how soon the chunk ask may be repeated: the game fires it once per character, not ten times a second
local TIMEOUT                   = 1      -- how long one request may wait before the next is made
local MAX_IN_FLIGHT             = 3      -- every request parks a thread, so this is the real limit on the rate
local FRESH_HOLD                = 1.5    -- how old the server's answer may be before asking the server again
local PROBE_RADIUS              = 60     -- how far around them the readiness check counts
local SELECTED_COLOR            = Color3.fromRGB(65, 65, 65)    -- Jobs.lua:153

local function GetStretcherTool()
    local stretcher = game.Players.LocalPlayer.Character:FindFirstChild("Stretcher")

    if not stretcher then
        stretcher = game.Players.LocalPlayer.Backpack:FindFirstChild("Stretcher")

        if not stretcher then
            print("[!] [GetStretcherTool] Couldn't find Stretcher in either Backpack or Equipped!")

            return nil
        end
    end
    
    print(string.format("[i] [GetStretcherTool] Found Stretcher at: %s", stretcher:GetFullName()))

    return stretcher
end

local function GetStretcherSeat()
    if not stretcher then
        print("[!] [GetStretcherSeat] Couldn't find StretcherSeat!")

        return nil
    end

    return stretcher.Model:FindFirstChildWhichIsA("Seat")
end

local function GetLocalVehicle()
    for i,v in game.Workspace.SessionVehicles:GetChildren() do
        if not string.find(v.Name, game.Players.LocalPlayer.Name) then
            continue
        end
        return v
    end
end

local function GetLocalTrailer()
    for i,v in game.Workspace._SessionTrailers:GetChildren() do
        if not string.find(v.Name, game.Players.LocalPlayer.Name) then
            continue
        end
        return v
    end
end

local function CacheStretcher()
    print("[i] [CacheStretcher] Caching Stretcher & StretcherSeat")

    stretcher       = GetStretcherTool()
    stretcherSeat   = GetStretcherSeat()
    
    for i,v in pairs(stretcher.Model:GetChildren()) do
        if v.Name == "Seat" and not v:IsA("Seat") then
            stretcherSeatPart = v
        end
    end

    return stretcher ~= nil and stretcherSeat ~= nil and stretcherSeatPart ~= nil
end

local function SetStretcherClientScriptState(newState : boolean)
    local stretcher                 = GetStretcherTool()
    if not stretcher then
        print("[!] [SetStretcherClientScriptState] failed to get Stretcher!")

        return false
    end

    stretcher.ClientTool.Disabled   = not newState

    return true
end

local function UpdateRemotePlayerPositions()
    local ret = game:GetService("ReplicatedStorage").Remote.requestPlayerPosition:InvokeServer("__bulk")
    if not ret then
        return false
    end

    for i,v in pairs(ret) do
        cachedRemoteLocations[i] = v
    end

    return true
end

local function CurrentJobOf(player)
    local gui   = player:FindFirstChildOfClass("PlayerGui")
    local phone = gui ~= nil and gui:FindFirstChild("GvOS Mobile") or nil
    if phone == nil then
        return nil
    end

    -- The path the phone builds for the profile card, with a recursive search only as a fallback: another
    -- player's row in the Players list carries a TeamMain of its own, and one of those must never be the
    -- answer to "what job am I".
    local main     = phone:FindFirstChild("Main")
    local screen   = main ~= nil and main:FindFirstChild("Screen") or nil
    local settings = screen ~= nil and screen:FindFirstChild("Settings") or nil
    local card     = settings ~= nil and settings:FindFirstChild("Profile") or nil
    local label    = card ~= nil and card:FindFirstChild("TeamMain") or phone:FindFirstChild("TeamMain", true)
    local text     = label ~= nil and label:IsA("TextLabel") and label.Text or nil

    if text == nil or string.find(text, "^%s*$") ~= nil then
        return nil
    end
    return text
end

local function GetSelectedJobOfPlayer(player)
    local gui = player:FindFirstChildOfClass("PlayerGui")
    if gui == nil then return nil end

    for _, descendant in ipairs(gui:GetDescendants()) do
        if descendant:IsA("GuiObject") and descendant.BackgroundColor3 == SELECTED_COLOR then
            local jobId = descendant:GetAttribute("JobID")
            if jobId ~= nil then return jobId end
        end
    end
    return nil
end

local function ServerPosition(name, fetch)
    local held = positions[name]
    if fetch ~= false and (held == nil or tick() - held.at >= FRESH_HOLD) then
        local ok, answer = pcall(function()
            return gps:InvokeServer(name)
        end)
        local position = (ok and typeof(answer) == "Vector3") and answer or nil
        positions[name] = { position = position, at = tick() }
        return position
    end
    return held ~= nil and held.position or nil
end

local function PositionOf(player, fetch)
    local character = player ~= nil and player.Character or nil
    local root      = character ~= nil and character:FindFirstChild("HumanoidRootPart") or nil
    local held      = ServerPosition(player.Name, fetch)

    if root ~= nil and root:IsA("BasePart") then
        return root.Position, held ~= nil and (root.Position - held).Magnitude <= 120
    end
    return held, false
end

local function VisibleParts(position)
    local ok, parts = pcall(function()
        return workspace:GetPartBoundsInRadius(position, PROBE_RADIUS)
    end)
    if not ok then
        return -1
    end

    local visible = 0
    for _, part in ipairs(parts) do
        if part.Transparency < 1 and part.Size.Magnitude >= 2 then
            visible = visible + 1
        end
    end
    return visible
end

local function LoadWorld(player)
    local running  = true
    local inFlight = {}                                          -- dispatch times, pruned by time
    local lastAsk  = nil
    local lastCharacterAsk = nil

    task.spawn(function()
        while running do
            local at = PositionOf(player)
            if at ~= nil then
                local now = tick()
                for index = #inFlight, 1, -1 do
                    if now - inFlight[index] > RETRY_SECONDS + TIMEOUT then
                        table.remove(inFlight, index)            -- the call may never return, so a slot
                    end                                          -- is freed by time, not by the call
                end

                local due = lastAsk == nil or now - lastAsk >= RETRY_SECONDS
                if due and #inFlight < MAX_IN_FLIGHT then
                    lastAsk = now
                    inFlight[#inFlight + 1] = now

                    -- On its own thread: this yields for as long as the region takes, and a timeout of 0
                    -- waits rather than returning at once, so it must never sit in the caller's path.
                    task.spawn(function()
                        pcall(function()
                            me:RequestStreamAroundAsync(at, TIMEOUT)
                        end)
                    end)
                end

                -- And their character, but only while they are not here: the game's own client fires this
                -- once per character, in response to its own event, so ten times a second is a pattern no
                -- player produces. One a second while absent, and nothing at all once they arrive.
                local character = player.Character
                local present   = character ~= nil and character:IsDescendantOf(workspace)
                    and character:FindFirstChild("HumanoidRootPart") ~= nil
                local characterDue = lastCharacterAsk == nil
                    or now - lastCharacterAsk >= CHARACTER_RETRY_SECONDS
                if not present and characterDue then
                    lastCharacterAsk = now
                    pcall(function()
                        chunks:FireServer("P", true, player)
                    end)
                end
            end
            task.wait(RETRY_SECONDS)
        end
    end)

    local function CharReady()
        local at, agreed = PositionOf(player, false)

        return at ~= nil and agreed
    end

    return {
        Stop = function()
            running = false
        end,

        -- Is the *world* around them here? Geometry only, no character required - which is the point,
        -- since bringing their parts is what the loader exists to do.
        WorldReady = function()
            local at = PositionOf(player, false)                  -- cache only: never fetch in a check
            return at ~= nil and VisibleParts(at) > 0
        end,

        -- And are *they* here? Their parts present and the server agreeing with where they are.
        CharacterReady = CharReady,

        -- Waits for them, up to a deadline. The old Stable asked "are they already here" twice in a row,
        -- which the loader has never had time to make true - a readiness check at the start can only say
        -- no. Stretcher.lua does not gate at all: it keeps asking and acts when the parts turn up.
        Await = function(seconds)
            local deadline = tick() + 15
            while tick() < deadline do
                if CharReady() then
                    return true
                end
                task.wait(0.25)
            end
            return false
        end,
    }
end

local function FixStretcher()
    stretcher.Parent = game.Players.LocalPlayer.Backpack
    SetStretcherClientScriptState(true) 
end

local function RefreshCharacter(timeout)
    local function RefreshJob()
        local remote = ReplicatedStorage:FindFirstChild("Remote")
        local change = remote ~= nil and remote:FindFirstChild("ChangeJob") or nil
        if change == nil or not change:IsA("RemoteFunction") then
            return false, "ChangeJob is not there"
        end

        local jobId = CurrentJobOf(me) or GetSelectedJobOfPlayer(me)
        if jobId == nil then
            return false, "no job found: open the phone, or pass one of the names in DataModule.Jobs"
        end

        local changed, title, message = change:InvokeServer(jobId)
        if not changed then
            return false, string.format("ChangeJob refused: %s %s", tostring(title), tostring(message))
        end

        return true
    end

    local me            = Players.LocalPlayer
    local character     = me.Character
    local humanoid      = character ~= nil and character:FindFirstChildWhichIsA("Humanoid") or nil
    local oldCamCF      = game.Workspace.CurrentCamera.CFrame
    local hasRefreshedJob  = false

    if character == nil or humanoid == nil or humanoid.Health <= 0 then
        return false, "no living character to remember"
    end

    -- Restore the camera rotation
    task.spawn(function()
        RunService:BindToRenderStep("cameraRestore", 0, function()
            game.Workspace.CurrentCamera.CFrame = oldCamCF
        end)

        repeat task.wait()
        until hasRefreshedJob
        task.wait(.2)

        RunService:UnbindFromRenderStep("cameraRestore")
    end)

    if not RefreshJob() then
        print("[!] [RefreshCharacter] Failed to change job!")
    end
    hasRefreshedJob = true

    local where         = character:GetPivot()
    local lastCF        = where
    local deadline      = tick() + (timeout ~= nil and timeout or 5)
    local placed        = 0

    local wasStillRunning, ret = pcall(function() RunService:UnbindFromRenderStep("refreshTpLoop") end)
    if wasStillRunning then
        print("[i] [RefreshCharacter] Previous refreshTpLoop was still running. Unbinding..")
    end

    RunService:BindToRenderStep("refreshTpLoop", 0, function()
        if tick() > deadline then
            RunService:UnbindFromRenderStep("refreshTpLoop")
            
            return
        end

        local fresh = me.Character
        local root  = fresh ~= nil and fresh:FindFirstChild("HumanoidRootPart") or nil
        if fresh == nil or fresh == character or root == nil then
            return
        end

        local nowCF         = fresh:GetPivot()
        local deltaPosition = nowCF.Position - lastCF.Position
        local distance      = deltaPosition.Magnitude
        if (distance > 1) then
            fresh:PivotTo(lastCF)
        else
            lastCF = fresh:GetPivot()
        end
    end)
    task.wait(.2)

    print("[i] [RefreshCharacter] Successfully refreshed character.")
    
    return true
end

local function FindPlayerByAbbreviation(abbv : string)
    for i,v in pairs(Players:GetChildren()) do
        if not string.find(v.Name, abbv) then
            continue
        end

        return v
    end

    return nil
end

local function TrySeatPlayerInStretcher(target : string)
    print(string.format("[i] [TrySeatPlayerInStretcher] Looking for players containing the word: %s", target))

    local player = FindPlayerByAbbreviation(target)
    if not player then
        print("[!] [FindPlayerByAbbreviation] Failed to find player!")

        return false
    end

    local function IsCharacterOfPlayerValid()
        if player.Character then
        else
            print(string.format("[!] [IsCharacterOfPlayerValid] Player %s does not have a valid Character!", player.Name))

            return false
        end

        if not player.Character.Parent then
            return false
        end

        if not player.Character:FindFirstChild("HumanoidRootPart") then
            print(string.format("[!] [IsCharacterOfPlayerValid] Player %s does not have a HumanoidRootPart!", player.Name))

            return false
        end

        return true
    end

    local function FindTargetCharacter()
        local targetCharacter = nil

        if not IsCharacterOfPlayerValid() then
            print("[!] [FindTargetCharacter] targetCharacter=nil; failed to find target character!")

            return nil
        end

        targetCharacter = player.Character
        local cframe = targetCharacter.HumanoidRootPart.CFrame

        print("[i] [FindTargetCharacter] "..targetCharacter:GetFullName())
        print(string.format("[i] [FindTargetCharacter] Found Player: %s at (%.0f, %.0f, %.0f)", player.Name, cframe.Position.X, cframe.Position.Y, cframe.Position.Z))

        return targetCharacter
    end

    local playerFound       = false
    local targetCharacter   = FindTargetCharacter()

    if not targetCharacter then
        return false
    end

    local humanoidValid, humanoid = pcall(function() return targetCharacter.Humanoid end)
    if not humanoidValid then
        print(string.format("[!] [TrySeatPlayerInStretcher] Humanoid of Player %s is not found!", player.Name))

        return false
    end

    local seatPartValid, seatPart = pcall(function() return humanoid.SeatPart end)
    if not seatPartValid or seatPart then
        print(string.format("[!] [TrySeatPlayerInStretcher] SeatPart of Player %s is already occupied!", player.Name))

        return false
    end
    print(string.format("[i] [TrySeatPlayerInStretcher] Player %s is not sitting, attempting to force them on the Stretcher.", player.Name))
    
    lastTargetPos = nil

    for i = 1,333 do task.wait()
        if stretcherSeat.Occupant then
            print(string.format("[i] [TrySeatPlayerInStretcher] Player %s found sitting in Stretcher seat", stretcherSeat.Occupant:FindFirstAncestorWhichIsA("Model", true).Name))
            playerFound = true

            break
        end

        local rootValid, root = pcall(function() return targetCharacter.HumanoidRootPart end)
        if not rootValid then
            continue
        end

        local velocity = root.AssemblyLinearVelocity                    -- the engine's figure, not a delta
        local lead     = velocity * Vector3.new(0.6, 0.2, 0.6)          -- 0.63 sideways, 0.2 vertically
        local targetCF = root.CFrame * CFrame.Angles(math.rad(90), 0, 0) + lead 

        stretcherSeatPart.CFrame = targetCF
    end

    if not playerFound then
        print(string.format("[!] [TrySeatPlayerInStretcher] Failed to force player %s into the Stretcher!", player.Name))
    end

    return playerFound
end

local function VoidPlayer(target : string)
    CacheStretcher()

    if not stretcher or not stretcherSeat then
        SetStretcherClientScriptState(true)

        return false
    end

    if not TrySeatPlayerInStretcher(target) then
        return false
    end

    stretcher.Model:PivotTo(CFrame.new(0, -1e12, 0))
    task.wait(.05)

    SetStretcherClientScriptState(true)
    game.Players.LocalPlayer.Character.Humanoid:UnequipTools()

    return true
end

local function TeleportPlayerToPosition(targetCFrame : CFrame, target : string)
    CacheStretcher()

    if not stretcher or not stretcherSeat then
        print("[!] [TeleportPlayerToPosition] Stretcher or StretcherSeat invalid!")

        SetStretcherClientScriptState(true)
        
        return false
    end

    stretcher.Parent = me.Character

    if not TrySeatPlayerInStretcher(target) then
        print(string.format("[!] [TeleportPlayerToPosition] Failed to teleport Stretcher to Player %s!", target))

        return false
    end
    print(string.format("[i] [TeleportPlayerToPosition] Sucessfully teleported Stretcher to Player %s", target))

    SetStretcherClientScriptState(false)
    stretcher.Model:PivotTo(targetCFrame)
    task.wait(2)
    RefreshCharacter()

    return true
end

local function CrashPlayer(targetName : string)
    print(string.format("[i] [CrashPlayer] Crashing player %s", targetName))

    TeleportPlayerToPosition(CFrame.new(1e20, 1e20, 1e20), targetName)
end

local function KillPlayer(playerName : string)
    return TeleportPlayerToPosition(CFrame.new(0, 1e99, 0), playerName)
end

local function FlingPlayer(playerName : string)
    CacheStretcher()

    if not stretcher or not stretcherSeat or not stretcherSeatPart then
        print("[!] [FlingPlayer] Stretcher, StretcherSeatPart or StretcherSeat invalid!")

        SetStretcherClientScriptState(true)
        
        return false
    end

    stretcher.Parent = me.Character
    if not TrySeatPlayerInStretcher(playerName) then
        print(string.format("[!] [FlingPlayer] Failed to teleport Stretcher to Player %s!", playerName))

        SetStretcherClientScriptState(true)
        
        return false
    end

    print(string.format("[i] [FlingPlayer] Sucessfully teleported Stretcher to Player %s", playerName))
    SetStretcherClientScriptState(false)
    
    local last = tick()
    RunService:BindToRenderStep("flingVelocityLoop", 0, function()
        local now       = tick()
        local deltaT    = now - last

        if (deltaT > 0.75) then
            print("[i] [FlingPlayer] Done flinging stretcher")

            RunService:UnbindFromRenderStep("flingVelocityLoop")
            RefreshCharacter()
            SetStretcherClientScriptState(true)

            if not UpdateRemotePlayerPositions() then
                print("[!] [FlingPlayer] Failed to Update remote player positions!")

                return
            end

            for i,v in pairs(cachedRemoteLocations) do
                if v.X + v.Y + v.Z > 1e9 then
                    print("[i] [ClickToFling] ", i, " Flung")
                end
            end

            return
        end

        stretcher.Model.PrimaryPart.AssemblyLinearVelocity = Vector3.new(1e6, 1e6, 1e6)
    end)
end

local function FlingCar(vehicleName : string)
    local myCar     = GetLocalVehicle()
    local myTrailer = GetLocalTrailer()

    if not myCar then
        print("[!] [FlingCar] LocalPlayer does not have a vehicle spawned in!")

        return false
    end

    if not myTrailer then
        print("[!] [FlingCar] LocalPlayer does not have a trailer spawned in!")

        return false
    end

    local hinge         = myTrailer.PrimaryPart
    local attachment    = hinge:FindFirstChild("TrailerAttachment")

    local cachedWelds           = {}
    local cachedCarPivots       = {}
    local cachedTrailerPivots   = {}
    
    local function SaveCarState()
        for i,v in pairs(myTrailer:GetDescendants()) do
            pcall(function()
                cachedTrailerPivots[v] = myCar.PrimaryPart.CFrame:ToObjectSpace(v:GetPivot())
            end)
        end
        for i,v in pairs(hinge:GetChildren()) do
            if v:IsA("Weld") then
                table.insert(cachedWelds, v)
                v.Parent = nil
            end
        end
    end
    local function RestoreCarState()
        for i,v in pairs(cachedWelds) do
            v.Parent = hinge
        end
        for i,v in pairs(myTrailer:GetDescendants()) do
            pcall(function()
                if cachedTrailerPivots[v] then
                    v:PivotTo(myCar.PrimaryPart.CFrame * cachedTrailerPivots[v])
                end
            end)
        end
    end

    SaveCarState()

    local targetVehicle = game.Workspace.SessionVehicles:FindFirstChild(vehicleName)
    if not targetVehicle then
        print(string.format("[!] [FlingCar] Failed to find vehicle %s!", playerName))

        return false
    end

    local lastTick          = tick()
    local lastTargetCF      = targetVehicle:GetPivot()

    print(string.format("[i] [FlingCar] Flinging %s's car.", targetVehicle.Name))
    local trailerFlingConn; trailerFlingConn = RunService.PostSimulation:Connect(function(deltaTimeSim)
        local deltaPos  = targetVehicle:GetPivot().Position - lastTargetCF.Position
        local drift     = deltaPos.Magnitude

        local hasBeenFlung  = drift > 100
        local timedOut       = (tick() - lastTick) > 7.5
        if timedOut or hasBeenFlung then
            trailerFlingConn:Disconnect()
            
            if timedOut then
                print("[i] [FlingCar] TP timed out.")
            else
                print(string.format("[i] [FlingCar] Vehicle of %s has been successfully flung. (∆P = %.0f %.0f %.0f)", targetVehicle.Name, deltaPos.X, 0, deltaPos.Z))
            end

            task.spawn(function()
                print("[i] [FlingCar] Restoring Car & Trailer..")
                RestoreCarState()
                print("[i] [FlingCar] Restored Car & Trailer.")
            end)

            return
        end
        lastTargetCF = targetVehicle:GetPivot()

        local oldHingeCF        = hinge.CFrame
        local oldHingeVelocity  = hinge.AssemblyLinearVelocity

        local lead      = Vector3.new(deltaPos.X * 100, 0, deltaPos.Z * 100)
        local offset    = targetVehicle:GetPivot().LookVector * 10

        hinge.CFrame = targetVehicle:GetPivot() + lead + offset
        hinge.AssemblyLinearVelocity = Vector3.new(1000, 250, 1000)

        -- game.Workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
        -- game.Workspace.CurrentCamera.CFrame = CFrame.new(targetVehicle:GetPivot().Position + lead + offset + Vector3.new(0, 100, 0), targetVehicle:GetPivot().Position + lead + offset)

        RunService:BindToRenderStep("restoreHingeProperties", 0, function()
            RunService:UnbindFromRenderStep("restoreHingeProperties")

            hinge.CFrame                    = oldHingeCF
            hinge.AssemblyLinearVelocity    = oldHingeVelocity
        end)
    end)
end

local function ForceClearStretcher()
    if not CacheStretcher() then
        print("[!] [ForceClearStretcher] Failed to cache Stretcher!")

        return false
    end

    stretcher.Model:PivotTo(CFrame.new(0, 1e999, 0))
    task.wait(.3)
    stretcher.Parent = game.Players.LocalPlayer.Backpack
    RefreshCharacter()
    print("[i] [ForceClearStretcher] Successfully cleared Stretcher")

    return true
end

local function DupeInventory()
    repeat task.wait()
        local done = 0
        for i = 1,3 do
            task.spawn(function()
                game.ReplicatedStorage:FindFirstChild("Remote"):FindFirstChild("ChangeJob"):InvokeServer("Greenville Fire Rescue")
                done += 1
            end)
        end

        local start = tick()
        repeat task.wait()
            local now = tick()
            if (now - start) > 1 then
                print("[!] [DupeInventory] InvokeServer timed out!")

                break
            end
        until done == 3
    until #game.Players.LocalPlayer.Backpack:GetChildren() > 14

    print("[i] [DupeInventory] Total size of backpack has exceeded 14.")

    return true
end

-- callback is called with parameter 1 being the MODEL of the player
local function OnCtrlClickOnPlayer(callback)
    local conn; conn = Players.LocalPlayer:GetMouse().Button1Up:Connect(function()
        if not UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) then
            return
        end

        local hit   = Players.LocalPlayer:GetMouse().Target
        local model = hit:FindFirstAncestorWhichIsA("Model", true)

        print("[i] [OnCtrlClickOnPlayer] Looking for player at mouse..")
        if not Players:FindFirstChild(model.Name) then
            return
        end

        callback(model)
    end)

    return conn
end

-- callback is called with parameter 1 being the NAME of the player
local function OnCtrlClickOnVehicle(callback)
    local conn; conn = Players.LocalPlayer:GetMouse().Button1Up:Connect(function()
        if not UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) then
            return
        end

        local vehicles  = game.Workspace.SessionVehicles
        local vehicle   = nil
        local hit       = Players.LocalPlayer:GetMouse().Target

        print(string.format("[i] [OnCtrlClickOnVehicle] Hit: %s", hit:GetFullName()))
        for i,v in pairs(vehicles:GetChildren()) do
            if not hit:FindFirstAncestor(v.Name) then
                continue
            end

            print(string.format("[i] [OnCtrlClickOnVehicle] Hit is descendant of vehicle %s", v:GetFullName()))
            vehicle = v
            
            break
        end

        if not vehicle then
            return
        end

        callback(vehicle.Name)
    end)

    return conn
end

local function ClickToCrash()
    local crashConn; crashConn = OnCtrlClickOnPlayer(function(model)
        print(string.format("[i] [ClickToCrash] Crashing %s", model.Name))
        CrashPlayer(model.Name)

        if not UpdateRemotePlayerPositions() then
            print("[!] [ClickToCrash] Failed to Update remote player positions!")

            return
        end

        for i,v in pairs(cachedRemoteLocations) do
            if v.X + v.Y + v.Z > 1e9 then
                print("[i] [ClickToCrash] ", i, " Crashed")
            end
        end
    end)

    repeat task.wait()
    until UserInputService:IsKeyDown(Enum.KeyCode.F13)

    crashConn:Disconnect()
    print("[i] [ClickToCrash] Stopped.")
end

local function ClickToFling()
    local flingPlayerConn; flingPlayerConn = OnCtrlClickOnPlayer(function(model)
        FlingPlayer(model.Name)
    end)
    local flingVehicleConn; flingVehicleConn = OnCtrlClickOnVehicle(function(playerName)
        FlingCar(playerName)
    end)

    repeat task.wait()
    until UserInputService:IsKeyDown(Enum.KeyCode.F13)

    flingPlayerConn:Disconnect()
    flingVehicleConn:Disconnect()
end

local function ClickToFlingCars()
    local flingVehicleConn; flingVehicleConn = OnCtrlClickOnVehicle(function(playerName)
        FlingCar(playerName)
    end)

    repeat task.wait()
    until UserInputService:IsKeyDown(Enum.KeyCode.F13)

    flingVehicleConn:Disconnect()
    print("[i] [ClickToFlingCars] Stopped.")
end

local function ClickToJail()
    print("[i] [ClickToJail] Started.")

    local jailConn; jailConn = OnCtrlClickOnPlayer(function(model)
        print(string.format("[i] [ClickToJail] Jailing %s", model.Name))
        
        TeleportPlayerToPosition(locations.Jail, model.Name)

        if not UpdateRemotePlayerPositions() then
            print("[!] [ClickToJail] Failed to Update remote player positions!")

            return
        end

        for i,v in pairs(cachedRemoteLocations) do
            local deltaPos = locations.Jail.Position - v
            local distance = deltaPos.Magnitude

            if distance < 50 then
                print("[i] [ClickToJail] ", i, " Jailed")
            end
        end
    end)

    repeat task.wait()
    until UserInputService:IsKeyDown(Enum.KeyCode.F13)

    jailConn:Disconnect()
    print("[i] [ClickToJail] Stopped.")
end

local function ClickToKill()
    local killConn; killConn = OnCtrlClickOnPlayer(function(model)
        print(string.format("[i] [ClickToKill] killing %s", model.Name))
        KillPlayer(model.Name)
    end)

    repeat task.wait()
    until UserInputService:IsKeyDown(Enum.KeyCode.F13)

    killConn:Disconnect()
end

print("")
me.Character:PivotTo(locations.Roadmap)
-- RefreshCharacter()

task.spawn(ClickToJail)
task.spawn(ClickToFlingCars)

SetStretcherClientScriptState(true)
