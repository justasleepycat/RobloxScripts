local RunService = game:GetService("RunService")
local success, ret = pcall(function()
    local targetName    = "Hak7Mod"
    local target        = game.Players:FindFirstChild(targetName).Character

    local function GetStretcherTool()
        return game.Players.LocalPlayer.Character.Stretcher
    end

    local function GetStretcherSeat()
        return GetStretcherTool().Model:FindFirstChildWhichIsA("Seat")
    end

    local function GetTargetCFrame()
        local velocity = target.HumanoidRootPart.AssemblyLinearVelocity

        return target:GetPivot() + Vector3.new(velocity.x * 0.8, velocity * 0.2, velocity * 0.8)
    end

    local function GetLocalVehicle()
        for i,v in game.Workspace.SessionVehicles:GetChildren() do
            if not string.find(v.Name, game.Players.LocalPlayer.Name) then
                continue
            end

            return v
        end
    end

    local function GetVehicleWheels(vehicle)
        local wheels = {}

        for i,v in vehicle.Wheels:GetChildren() do
            local wheel = v.Parts.Wheels.Wheel

            table.insert(wheels, wheel)
        end
        
        -- vehicle.Wheels.FL.Parts.Wheels.Wheel

        return wheels
    end

    local function SetStretcherClientScriptState(newState : boolean)
        local stretcher     = GetStretcherTool()
        stretcher.ClientTool.Disabled = not newState
    end

    local function TryTeleportStretcherToPlayer(stretcher, stretcherSeat)
        SetStretcherClientScriptState(false)

        local playerFound = false
        for i = 1,333 do task.wait()
            if stretcherSeat.Occupant then
                playerFound = true
                break
            end

            local targetCF = GetTargetCFrame()

            stretcher.Model:PivotTo(targetCF - targetCF.LookVector * 3)
        end

        return playerFound
    end

    local function VoidTarget(stretcher, stretcherSeat)
        if not stretcher or not stretcherSeat then
            SetStretcherClientScriptState(true)
        end

        if TryTeleportStretcherToPlayer(stretcher, stretcherSeat) then
            stretcher.Model:PivotTo(CFrame.new(0, -1e12, 0))
            task.wait(.05)
        end

        SetStretcherClientScriptState(true)
        game.Players.LocalPlayer.Character.Humanoid:UnequipTools()
    end

    local function CreateVelocitySpoofer(target : Instance, options : { [string] : any }?)
        local settings     = options or {}
        local strength     = settings.Strength or Vector3.one
        local onSpoof      = settings.OnSpoof

        local spoofing     = false
        local wishVelocity = Vector3.zero

        -- Applies velocity to every part for a single frame, then puts each part back as it was.
        local function Spoof(velocity : Vector3)
            local parts    = CollectBaseParts(target)
            local previous = table.create(#parts)

            for index, part in ipairs(parts) do
                previous[index] = part.AssemblyLinearVelocity
            end

            local spoofed = velocity * strength
            for _, part in ipairs(parts) do
                part.AssemblyLinearVelocity = spoofed
            end

            if onSpoof then
                onSpoof(spoofed)
            end

            RunService.RenderStepped:Wait()

            for index, part in ipairs(parts) do
                part.AssemblyLinearVelocity = previous[index]
            end
        end

        return {
            Connection  = game:GetService("RunService").PostSimulation:Connect(function(deltaTime : double)
                if not spoofing then return end
                Spoof(wishVelocity)
            end),
            SetVelocity = function(velocity : Vector3)
                wishVelocity = velocity
                spoofing     = true
            end,
            Spoof       = Spoof,
        }
    end

    local function TeleportTargetToPosition(stretcher, stretcherSeat, targetCFrame)
        if not stretcher or not stretcherSeat then
            SetStretcherClientScriptState(true)
        end

        if TryTeleportStretcherToPlayer(stretcher, stretcherSeat) then
            stretcher.Model:PivotTo(targetCFrame)
            task.wait(.2)
        end

        SetStretcherClientScriptState(true)
        game.Players.LocalPlayer.Character.Humanoid:UnequipTools()
    end

    -- local stretcherSeat = GetStretcherSeat()
    -- local stretcher     = GetStretcherTool()

    -- VoidTarget(stretcher, stretcherSeat)
    -- TeleportTargetToPosition(stretcher, stretcherSeat, CFrame.new(1e16, 1e16, 1e16))

    -- [EXAMPLE_INSTANCE] = {CFrame.new()}
    local cachedPivots = {}
    local ownedVehicle = GetLocalVehicle()

    pcall(function()
        for i = 1, 500 do task.wait()
            if ownedVehicle.Body.PrimaryPart.ReceiveAge ~= 0 then
                print("No network ownership")
                break
            end

            ownedVehicle:PivotTo(target:GetPivot())
        end
    end)
end)

if not success then
    rconsoleprint(ret)
end