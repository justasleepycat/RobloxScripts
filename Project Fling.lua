getgenv().SecureMode = true
local ArrayField = loadstring(game:HttpGet('https://raw.githubusercontent.com/UI-Interface/ArrayField/main/Source.lua'))()
local VirtualKeyCodes = loadstring(game:HttpGet("https://raw.githubusercontent.com/justasleepycat/Roblox/refs/heads/dev/VirtualKeyCodes.lua"))()

local Players = game:GetService("Players")
local Workspace =  game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local doFling = false;
local clickFling = false;
local VisualizeFling = false;
local flingConnection;
local flingStrength = 100;
local flingOffset = 0;
local FlingHumanoidState = Enum.HumanoidStateType.Landed;
local FlingType = "LookVector"
local FlingVisualizer = Drawing.new("Line")
FlingVisualizer.Thickness = 3
FlingVisualizer.Color = Color3.new(1,0,0)
FlingVisualizer.Visible = false

local Window = ArrayField:CreateWindow({
    Name = "Project Fling",
    LoadingTitle = "Yeet people to mars",
    LoadingSubtitle = "by justasleepycat",
    ConfigurationSaving = {
       Enabled = true,
       FolderName = nil, -- Create a custom folder for your hub/game
       FileName = "Project_Fling"
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
local Tab = Window:CreateTab("Main", 0) 
local FeaturesSection = Tab:CreateSection("Features",false) -- The 2nd argument is to tell if its only a Title and doesnt contain element

local VisualizerToggle = Tab:CreateToggle({
    Name = "Visualize FlingDirection",
    CurrentValue = false,
    Flag = "FlingVisualizer", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
    Callback = function(Value)
        VisualizeFling = Value
    end,
})

local FlingToggle = Tab:CreateToggle({
    Name = "Enable Fling",
    CurrentValue = false,
    Flag = "Fling", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
    Callback = function(Value)
        doFling = Value
    end,
})

local FlingToggle = Tab:CreateToggle({
    Name = "Click to Fling",
    CurrentValue = false,
    Flag = "ClickFling", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
    Callback = function(Value)
        clickFling = Value
    end,
})


local SettingsSection = Tab:CreateSection("Settings",false) -- The 2nd argument is to tell if its only a Title and doesnt contain element
local FlingModes = Tab:CreateDropdown({
    Name = "Fling Mode",
    Options = {"LookVector","MousePos", "Up", "Custom"},
    CurrentOption = "Landed",
    MultiSelection = false, -- If MultiSelections is allowed
    Flag = "FlingType", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
    Callback = function(Option)
        FlingType = Option
    end,
})
local StrengthInput = Tab:CreateInput({
    Name = "Fling Strength",
    PlaceholderText = "ex. 100",
    NumbersOnly = false, -- If the user can only type numbers. Remove or set to false if none.
    CharacterLimit = 15, --max character limit. Remove or set to false
    OnEnter = true, -- Will callback only if the user pressed ENTER while being focused on the the box.
    RemoveTextAfterFocusLost = false, -- Speaks for itself.
    Callback = function(Text)
        if string.find(Text:lower(), "inf") then
			flingStrength = 1e30
		else
            flingStrength = tonumber(Text)
		end
    end,
})

local FlingOffsetInput = Tab:CreateInput({
    Name = "Fling Offset",
    PlaceholderText = "ex. 1",
    NumbersOnly = false, -- If the user can only type numbers. Remove or set to false if none.
    CharacterLimit = 15, --max character limit. Remove or set to false
    OnEnter = true, -- Will callback only if the user pressed ENTER while being focused on the the box.
    RemoveTextAfterFocusLost = false, -- Speaks for itself.
    Callback = function(Text)
        flingOffset = tonumber(Text)
    end,
})


local function UpdateVelocity(CurrentPosition : Vector3, newVelocity : Vector3)
    local PredictedPosition = CurrentPosition + newVelocity
    local CurrentCamera = Workspace.CurrentCamera
    local Pos2D, OnScreen = CurrentCamera:WorldToViewportPoint(PredictedPosition)
    FlingVisualizer.To = Vector2.new(Pos2D.X, Pos2D.Y)
end

local function SetVelocities(instanceTable : table, newVelocity)
    pcall(function()
        for i,v in pairs(instanceTable) do
            pcall(function()
                if v:IsA("Part") or v:IsA("BasePart") or v:IsA("MeshPart") then
					v.AssemblyLinearVelocity = newVelocity
                end
            end)
        end
    end)
end

local LastHumanoidState = nil
local flingFixConnection; flingFixConnection = RunService.PreRender:Connect(function(deltaTime : double)
    if doFling then
        local LocalPlayer = Players.LocalPlayer
        local Character = Players.LocalPlayer.Character
        if not Character then return end
        local HumanoidRootPart =  Character:FindFirstChild("HumanoidRootPart", true)
        if not HumanoidRootPart then return end

        local Humanoid = Character:FindFirstChildWhichIsA("Humanoid", true)
        local CurrentState = Humanoid:GetState()
        if CurrentState == Enum.HumanoidStateType.Freefall then
            Humanoid:ChangeState(LastHumanoidState)
        elseif CurrentState ~= Enum.HumanoidStateType.Jumping then
            LastHumanoidState = CurrentState
        end
	end
end)

flingConnection = RunService.PostSimulation:Connect(function(deltaTime : double)
    FlingVisualizer.Visible = false
    local LocalPlayer = Players.LocalPlayer
    local Mouse = LocalPlayer:GetMouse()
    local CurrentCamera = Workspace.CurrentCamera
    local Character = Players.LocalPlayer.Character
    if not Character then return end
    local HumanoidRootPart =  Character:FindFirstChild("HumanoidRootPart", true)
    if not HumanoidRootPart then return end
    local Humanoid = Character:FindFirstChildWhichIsA("Humanoid", true)
    local oldVelocity = HumanoidRootPart.AssemblyLinearVelocity
    local oldCFrame = HumanoidRootPart.CFrame
    local oldPosition = oldCFrame.Position
    local CharacterChildren = Character:GetDescendants()

    if clickFling or doFling then
        local Pos2D, OnScreen = CurrentCamera:WorldToViewportPoint(oldPosition)
        FlingVisualizer.From = Vector2.new(Pos2D.X, Pos2D.Y)
    end


    if table.find(VirtualKeyCodes:GetCurrentPressedKeys(), "VK_LBUTTON") then
        if clickFling then
            FlingVisualizer.Visible = VisualizeFling
            local LocalPlayer = Players.LocalPlayer
            local Mouse = LocalPlayer:GetMouse()
            local CurrentCamera = Workspace.CurrentCamera
            local Character = Players.LocalPlayer.Character
            if not Character then return end
            local HumanoidRootPart =  Character:FindFirstChild("Head", true)
            if not HumanoidRootPart then return end
            local oldPosition = Character:GetPivot()
            local oldCameraPosition = CurrentCamera.CFrame
            local oldVelocity = HumanoidRootPart.AssemblyLinearVelocity
            local direction = (Mouse.Hit.Position - oldPosition.Position)

            if FlingType ~= "Up" then
                Character:PivotTo(CFrame.new(Mouse.Hit.Position + Vector3.new(0, Character:GetModelSize().Y/2.5, 0) + direction.Unit*flingOffset))
                SetVelocities(CharacterChildren, direction*flingStrength)
                UpdateVelocity(oldPosition.Position + Vector3.new(0, Character:GetModelSize().Y/2.5, 0), direction)
            else
				Character:PivotTo(CFrame.new(Mouse.Hit.Position - Vector3.new(0, Character:GetModelSize().Y/2, 0) + direction.Unit*flingOffset))
                SetVelocities(CharacterChildren,Vector3.new(0,1,0)*flingStrength)
                UpdateVelocity(oldPosition.Position + Vector3.new(0, Character:GetModelSize().Y/2, 0), direction)
            end
            RunService.PreRender:Wait()
            CurrentCamera.CFrame = oldCameraPosition
            SetVelocities(CharacterChildren, oldVelocity)
            Character:PivotTo(oldPosition)
            return
        end
	end

    if doFling then
		FlingVisualizer.Visible = VisualizeFling
        if FlingType == "LookVector" then
            SetVelocities(CharacterChildren, CurrentCamera.CFrame.LookVector * flingStrength)
            UpdateVelocity(oldPosition, HumanoidRootPart.AssemblyLinearVelocity)

            game:GetService("RunService").PreRender:Wait()

            SetVelocities(CharacterChildren, oldVelocity)
        elseif FlingType == "MousePos" then
			local DirectionToMousePos = (game:GetService("Players").LocalPlayer:GetMouse().Hit.Position - HumanoidRootPart:GetPivot().Position).Unit
            SetVelocities(CharacterChildren, DirectionToMousePos * flingStrength)
            UpdateVelocity(oldPosition, DirectionToMousePos * 40)

            game:GetService("RunService").PreRender:Wait()

            SetVelocities(CharacterChildren, oldVelocity)
        elseif FlingType == "Up" then
            SetVelocities(CharacterChildren, Vector3.new(0, 1, 0) * flingStrength)
            UpdateVelocity(oldPosition, Vector3.new(0, 1, 0) * 5)

            game:GetService("RunService").PreRender:Wait()

            SetVelocities(CharacterChildren, oldVelocity)
        end
	end
end)



local ExitButton = Tab:CreateButton({
    Name = "Exit",
    Interact = 'Click',
    Callback = function()
		pcall(function()
			flingConnection:Disconnect()
            flingFixConnection:Disconnect()
            clickConnection:Disconnect()
		end)
        pcall(function()
            local Character = game:GetService("Players").LocalPlayer.Character
            if not Character then return end
            local HumanoidRootPart =  Character:FindFirstChild("Head", true)
            if not HumanoidRootPart then return end
            local Humanoid = Character:FindFirstChildWhichIsA("Humanoid", true)
            Humanoid:ChangeState(Enum.HumanoidStateType.Landed)
            HumanoidRootPart.AssemblyLinearVelocity = Vector3.new(0,0,0)
		end)
        pcall(function()
			FlingVisualizer:Remove()
		end)
        ArrayField:Destroy()
    end
})


ArrayField:LoadConfiguration()