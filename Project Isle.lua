getgenv().SecureMode = true
local ArrayField = loadstring(game:HttpGet('https://raw.githubusercontent.com/UI-Interface/ArrayField/main/Source.lua'))()
local Sense = loadstring(game:HttpGet('https://sirius.menu/sense'))()
local HookingService = loadstring(game:HttpGet("https://raw.githubusercontent.com/justasleepycat/Roblox/refs/heads/dev/Hooks.lua"))()
local Checks = loadstring(game:HttpGet("https://raw.githubusercontent.com/justasleepycat/Roblox/refs/heads/dev/Checks.lua"))()


local Window = ArrayField:CreateWindow({
    Name = "Project Isle",
    LoadingTitle = "Project Isle",
    LoadingSubtitle = "by justasleepycat",
    ConfigurationSaving = {
       Enabled = true,
       FolderName = nil, -- Create a custom folder for your hub/game
       FileName = "Project_Isle"
    },
    Discord = {
       Enabled = false,
       Invite = "noinvitelink", -- The Discord invite code, do not include discord.gg/. E.g. discord.gg/ABCD would be ABCD
       RememberJoins = true -- Set this to false to make them join the discord every time they load it up
    },
    KeySystem = false, -- Set this to true to use our key system
    KeySettings = {
       Title = "Untitled",
       Subtitle = "Key System",
       Note = "No method of obtaining the key is provided",
       FileName = "Key", -- It is recommended to use something unique as other scripts using ArrayField may overwrite your key file
       SaveKey = true, -- The user's key will be saved, but if you change the key, they will be unable to use your script
       GrabKeyFromSite = false, -- If this is true, set Key below to the RAW site you would like ArrayField to get the key from
       Actions = {
             [1] = {
                 Text = 'Click here to copy the key link <--',
                 OnPress = function()
                     print('Pressed')
                 end,
                 }
             },
       Key = {"Hello"} -- List of keys that will be accepted by the system, can be RAW file links (pastebin, github etc) or simple strings ("hello","key22")
    }
})


local function ShootAtEnemies()
    ArrayField:Notify({
        Title = "Info",
        Content = "Searching for targets",
        Duration = .5,
    })    local Weapon = game.Players.LocalPlayer.Character:FindFirstChildOfClass("Tool") and game.Players.LocalPlayer.Character:FindFirstChildOfClass("Tool"):FindFirstChild("@Kill")
    for i,v in pairs(game.Workspace.AIHunter:GetChildren()) do
        pcall(function()
            local result = Checks:IsVisible(game.Players.LocalPlayer.Character.Head.CFrame.Position, v:GetPivot().Position, 2000, {game.Players.LocalPlayer.Character})
            if result and result.Instance:IsDescendantOf(v) then
                ArrayField:Notify({
                    Title = "Info",
                    Content = "Aiming at "..v.Name,
                    Duration = 1.5,
                })
                Weapon:FireServer(v.Name)
            end
        end)
    end
    
    for i,v in pairs(workspace.Threats:GetChildren()) do
        pcall(function()
            if v.Name == "Bee Buddy" or v.Name == "Fuel Pump" or string.find(v.Name, "Turret") or string.find(v.Name, "glass") or string.find(v.Name, "Serpent") or string.find(v.Name, "Glass") then
                return
            end
            local result = Checks:IsVisible(game.Players.LocalPlayer.Character.Head.CFrame.Position, v:GetPivot().Position, 2000, {game.Players.LocalPlayer.Character})
            if result and result.Instance:IsDescendantOf(v) then
                ArrayField:Notify({
                    Title = "Info",
                    Content = "Aiming at "..v.Name,
                    Duration = 1.5,
                })
                Weapon:FireServer(v.Name)
            end
        end)
    end 
end

local success, err = pcall(function()
    HookingService:HookRemote(workspace.Services.PickupTool, function(namecall, self, ...)
        local args = {...}
        getgenv().PickUpCode = args[1]
        ArrayField:Notify({
            Title = "Info",
            Content = "Pickup Code: "..args[1],
            Duration = 1.5,
        })
        return namecall(self, ...)
    end)
end)
if not success then
    print(err)
end

local function EquipAllTools()
    for i,v in pairs(game:GetService("Players").LocalPlayer.Backpack:GetChildren()) do
        v.Parent = game:GetService("Players").LocalPlayer.Character
    end
end

local function DropTool(tool : Instance)
    pcall(function()
        tool.RequestDrop:FireServer()
    end)
end

local function tpToTool(toolName : string, PickUpBypass : boolean, collectAll : boolean)
    for i,v in pairs(game.Workspace.Map:GetDescendants()) do
        if string.find(string.lower(v.Name), string.lower(toolName)) then
            if not v.ClassName == "Model" then
                print("Isnt a model")
                continue
            end
            if v:FindFirstChild("#Weight", true) or v:FindFirstChild("#Pickup", true) or v:FindFirstChild("Reference", true) then
            else
                print("#Weight or #Pickup not found")
                continue
            end
            local connection; connection = game:GetService("RunService").RenderStepped:Connect(function(deltaTime)
                game:GetService("Workspace").CurrentCamera.CameraSubject = v
                game.Players.LocalPlayer.Character:PivotTo(workspace.CurrentCamera.Focus)
                game.Players.LocalPlayer.Character.HumanoidRootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            end)
            for i = 1,10 do
                if PickUpBypass then
                    EquipAllTools()
                end
                workspace.Services.PickupTool:InvokeServer(getgenv().PickUpCode, v.Name)
                if not v.Parent then
                    break
                end
                task.wait(.1)
            end
            connection:Disconnect()
            if not collectAll or game:GetService("UserInputService"):IsKeyDown(Enum.KeyCode.End) then
                game:GetService("Workspace").CurrentCamera.CameraSubject = game.Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                game.Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid"):UnequipTools()
                break
            end
            game:GetService("Workspace").CurrentCamera.CameraSubject = game.Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            task.wait(.75)
        end
    end
end



local Aimbot = Window:CreateTab("Aimbot", 0)
local Visuals = Window:CreateTab("Visuals", 0)
local Miscelleanous = Window:CreateTab("Miscelleanous", 0)
local Settings = Window:CreateTab("Settings", 0)


local ItemESPObjects = {}
local ItemESP = Visuals:CreateToggle({
    Name = "Item ESP",
    CurrentValue = false,
    Flag = "ItemESP",
    Callback = function(Value)
        for i,v in pairs(ItemESPObjects) do
            pcall(function()
                v.options.enabled = Value
            end)
        end
        if Value then
            for i,v in pairs(game.Workspace.Map.Ignore:GetDescendants()) do
                local isPickUp = v:FindFirstChild("#Weight") or v:FindFirstChild("Tooltip") or v:FindFirstChild("Reference")
                if not isPickUp then
                    continue
                end
                local object = Sense.AddInstance(v, {
                    enabled = true,
                    text = "[{name}] [{distance}]", -- Placeholders: {name}, {distance}, {position}
                    textColor = { Color3.new(1,1,1), 1 },
                    textOutline = false,
                    textOutlineColor = Color3.new(),
                    textSize = 12,
                    textFont = 1,
                    limitDistance = true,
                    maxDistance = 500
                })
                table.insert(ItemESPObjects, object)
            end
        end
    end,
})

local AutoAimKeybind = Aimbot:CreateKeybind({
    Name = "Auto Aim",
    CurrentKeybind = "K",
    HoldToInteract = false,
    Flag = "AutoAimKey", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
    Callback = function(Keybind)
        ShootAtEnemies()
    end,
})

local Input = Miscelleanous:CreateInput({
    Name = "Item Name",
    PlaceholderText = "Enter item name",
    NumbersOnly = false, -- If the user can only type numbers. Remove or set to false if none.
    CharacterLimit = 150, --max character limit. Remove or set to false
    OnEnter = true, -- Will callback only if the user pressed ENTER while being focused on the the box.
    RemoveTextAfterFocusLost = false, -- Speaks for itself.
    Callback = function(Text)
        task.spawn(function()
			tpToTool(Text, true, true)
		end)
        ArrayField:Notify({
            Title = "Info",
            Content = "Teleporting to "..Text.."\nPress End to stop",
            Duration = 1.5,
        })
    end,
})

Miscelleanous:CreateButton({
    Name = "Kill Nearby entities",
    Interact = 'Click',
    Callback = function()
        for i,v in pairs(workspace.AIHunter:GetDescendants()) do
            pcall(function()
                if v.ClassName == "Humanoid" then
                    v.Health = 0
                end
            end)
        end
        
        for i,v in pairs(workspace.Threats:GetDescendants()) do
            pcall(function()
                if workspace:IsDescendantOf(workspace.Threats["Fuel Pump"]) then
                    return
                end
                if v.ClassName == "Humanoid" then
                    v.Health = 0
                end
            end)
        end
    end
})










local ExitButton = Settings:CreateButton({
    Name = "Exit",
    Interact = 'Click',
    Callback = function()
        Sense.Unload()
        ArrayField:Destroy()
    end
})

Sense.Load()
ArrayField:LoadConfiguration()