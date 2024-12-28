local Library = loadstring(game:HttpGet('https://raw.githubusercontent.com/justasleepycat/Roblox-UI-Libraries/refs/heads/main/Shaman/Library.lua'))()
local Flags = Library.Flags

local VirtualKeyCodes = loadstring(game:HttpGet("https://raw.githubusercontent.com/justasleepycat/RobloxScripts/refs/heads/main/VirtualKeyCodes.lua"))()
local Checks = loadstring(game:HttpGet("https://raw.githubusercontent.com/justasleepycat/RobloxScripts/refs/heads/main/Checks.lua"))()

local Players = game:GetService("Players")
local Workspace =  game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local doFling = false;
local clickFling = false;
local VisualizeFling = true;
local AutoFling = {
    Enabled = false,
    Target = nil,
    Prediction = 0.35,
    LastPosition = Vector3.new(0,0,0),
}
local flingConnection;
local flingStrength = {
    X = 1e3,
    Y = 1e3,
    Z = 1e3,
};
local flingOffset = 0;
local FlingHumanoidState = Enum.HumanoidStateType.Landed;
local FlingType = "LookVector"
local FlingVisualizer = Drawing.new("Line")
FlingVisualizer.Thickness = 3
FlingVisualizer.Color = Color3.new(1,0,0)
FlingVisualizer.Visible = false




local function UpdateVelocity(CurrentPosition : Vector3, newVelocity : Vector3)
    local PredictedPosition = CurrentPosition + newVelocity
    local CurrentCamera = Workspace.CurrentCamera
    local Pos2D, OnScreen = CurrentCamera:WorldToViewportPoint(PredictedPosition)
    if OnScreen then
		FlingVisualizer.To = Vector2.new(Pos2D.X, Pos2D.Y)
    else
		FlingVisualizer.To = Vector2.new(-Pos2D.X, -Pos2D.Y)
	end
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


    -- Click to fling player
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
                SetVelocities(CharacterChildren, direction*Vector3.new(flingStrength.X, flingStrength.Y, flingStrength.Z))
                UpdateVelocity(oldPosition.Position + Vector3.new(0, Character:GetModelSize().Y/2.5, 0), direction)
            else
				Character:PivotTo(CFrame.new(Mouse.Hit.Position - Vector3.new(0, Character:GetModelSize().Y/2, 0) + direction.Unit*flingOffset))
                SetVelocities(CharacterChildren,Vector3.new(0,1,0)*Vector3.new(flingStrength.X, flingStrength.Y, flingStrength.Z))
                UpdateVelocity(oldPosition.Position + Vector3.new(0, Character:GetModelSize().Y/2, 0), direction)
            end
            RunService.PreRender:Wait()
            CurrentCamera.CFrame = oldCameraPosition
            SetVelocities(CharacterChildren, oldVelocity)
            Character:PivotTo(oldPosition)
            return
        end
	end

    -- Auto fling
    if AutoFling.Enabled then
        local succes, err = pcall(function()
            local Target = nil
            for i,v in pairs(Players:GetChildren()) do
                if string.find(v.Name, AutoFling.Target) then
                    Target = v.Character
                end
            end
			local TargetPosition = Target:GetPivot()
            if LastPosition == nil then
				LastPosition = TargetPosition.Position
			end
			local Velocity = Target:FindFirstChild("HumanoidRootPart", true).AssemblyLinearVelocity or (TargetPosition.Position - LastPosition)

    		Character:PivotTo(TargetPosition + Velocity*AutoFling.Prediction)
            LastPosition = TargetPosition.Position
    	end)
        if not succes then
			warn(err)
		end
    end

    -- Normal fling
    if doFling then
		FlingVisualizer.Visible = VisualizeFling
        if FlingType == "LookVector" then
            SetVelocities(CharacterChildren, CurrentCamera.CFrame.LookVector * Vector3.new(flingStrength.X, flingStrength.Y, flingStrength.Z))
            UpdateVelocity(oldPosition, HumanoidRootPart.AssemblyLinearVelocity)

            game:GetService("RunService").PreRender:Wait()

            SetVelocities(CharacterChildren, oldVelocity)
        elseif FlingType == "MousePos" then
			local DirectionToMousePos = (game:GetService("Players").LocalPlayer:GetMouse().Hit.Position - HumanoidRootPart:GetPivot().Position).Unit
            SetVelocities(CharacterChildren, DirectionToMousePos * Vector3.new(flingStrength.X, flingStrength.Y, flingStrength.Z))
            UpdateVelocity(oldPosition, DirectionToMousePos * 40)

            game:GetService("RunService").PreRender:Wait()

            SetVelocities(CharacterChildren, oldVelocity)
        elseif FlingType == "Up" then
            SetVelocities(CharacterChildren, Vector3.new(0, 1, 0) * Vector3.new(flingStrength.X, flingStrength.Y, flingStrength.Z))
            UpdateVelocity(oldPosition, Vector3.new(0, 1, 0) * 5)

            game:GetService("RunService").PreRender:Wait()

            SetVelocities(CharacterChildren, oldVelocity)
        elseif FlingType == "Closest" then
			local ClosestPlayer = Checks:GetClosestPlayerToPosition({
                MaxDistance = 5000,
                Origin = HumanoidRootPart.CFrame.Position,
            })
            if ClosestPlayer then
				local ClosestCharacter = ClosestPlayer.Character
                if ClosestCharacter then
					local ClosestHumanoidRootPart = ClosestCharacter:FindFirstChild("HumanoidRootPart", true)
                    if ClosestHumanoidRootPart then
						local Direction = ClosestHumanoidRootPart.CFrame.Position - HumanoidRootPart.CFrame.Position
                        SetVelocities(CharacterChildren, Direction * Vector3.new(flingStrength.X, flingStrength.Y, flingStrength.Z))
                        UpdateVelocity(oldPosition, Direction)

                        game:GetService("RunService").PreRender:Wait()

                        SetVelocities(CharacterChildren, oldVelocity)
					end
				end
			end
        end
	end
end)

local Window = Library:Window({
    Text = "Project Fling"
})

local MainTab = Window:Tab({
    Text = "Main"
})
MainTab:Select()

do -- Features
    local FeaturesSection = MainTab:Section({
        Text = "Features"
    })
    FeaturesSection:Toggle({
        Text = "Enable Fling",
        Callback = function(Value)
            doFling = Value
        end
    })
    FeaturesSection:Toggle({
        Text = "Click to fling",
        Callback = function(Value)
            clickFling = Value
        end
    })
    FeaturesSection:Toggle({
        Text = "Visualize Fling",
        Callback = function(Value)
            VisualizeFling = Value
        end
    })
end

do -- Fling Strength
    local FlingStrengthSection = MainTab:Section({
        Text = "Fling Strength"
    })
    FlingStrengthSection:Input({
        Placeholder = "X Strength",
        Flag = "FlingStrengthX",
        Callback = function(Value)
            if tonumber(Value) then
                flingStrength.X = tonumber(Value)
            end
        end
    })
    FlingStrengthSection:Input({
        Placeholder = "Y Strength",
        Flag = "FlingStrengthY",
        Callback = function(Value)
            if tonumber(Value) then
                flingStrength.Y = tonumber(Value)
            end
        end
    })
    FlingStrengthSection:Input({
        Placeholder = "Z Strength",
        Flag = "FlingStrengthZ",
        Callback = function(Value)
            if tonumber(Value) then
                flingStrength.Z = tonumber(Value)
            end
        end
    })
end

do -- Targeting
    local TargetSection = MainTab:Section({
        Text = "Targeting"
    })
    TargetSection:Toggle({
        Text = "Auto Fling",
        Callback = function(Value)
            AutoFling.Enabled = Value
        end
    })
    TargetSection:Input({
        Placeholder = "Fling Target",
        Flag = "FlingTarget",
        Callback = function(Value)
            AutoFling.Target = Value
        end
    })
    TargetSection:Input({
        Placeholder = "Velocity Prediction",
        Flag = "VeloPrediction",
        Callback = function(Value)
            pcall(function()
                AutoFling.Prediction = tonumber(Value)
            end)
        end
    })
    
end

local SettingsSection = MainTab:Section({
    Text = "Settings"
})
SettingsSection:Dropdown({
    Text = "Fling Mode",
    List = {"LookVector","MousePos", "Up", "Closest", "Custom"},
    Flag = "Choosen",
    Callback = function(v)
        FlingType = v
        for i,v in pairs(Flags) do
            print(i,v)
        end
    end
})
