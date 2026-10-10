-- Decompiled with Medal in Seliware

local v1 = require(game.ReplicatedStorage:WaitForChild("Library"))
local v_u_2 = v1:Load("Utility")
v1:Load("Events")
local v_u_3 = v1:Load("SoundFX")
local v_u_4 = v1:Load("CameraUtil")
local v_u_5 = v1:Load("Network")
local v_u_6 = require(game.ReplicatedStorage:WaitForChild("Enums"))
local v7 = game:GetService("UserInputService")
local v_u_8 = game.Players.LocalPlayer
local v_u_9 = v_u_8:GetMouse()
local v_u_10 = Instance.new("HapticEffect")
v_u_10.Position = Vector3.new(0, 0, 0)
v_u_10.Radius = 1
v_u_10.Type = Enum.HapticEffectType.UIHover
v_u_10.Parent = workspace
local v11 = game.Players.LocalPlayer:WaitForChild("PlayerGui")
v11:WaitForChild("MainGui")
local v_u_12 = require(v11:WaitForChild("GuiManager"))
local v_u_13 = v_u_8:WaitForChild("PlayerGui"):WaitForChild("MainGui")
local v14 = workspace.GameService
local v_u_15 = nil
local v_u_16 = nil
local v_u_17 = false
local v_u_18 = nil
local v_u_19 = nil
local v_u_20 = nil
local v_u_21 = nil
local v_u_22 = v_u_2:SendData("GetJobsCompleted", "PlayerChannel", 10) or {
    ["Cook"] = 0,
    ["Cashier"] = 0,
    ["Pizza Boxer"] = 0,
    ["Delivery"] = 0,
    ["Supplier"] = 0
}
workspace.Main.RefreshJobsCompleted.OnClientEvent:connect(function(p23)
    -- upvalues: (ref) v_u_22
    v_u_22 = p23
end)
local v_u_24 = false
workspace.TutorialService.TutorialEnabled.OnClientEvent:connect(function(p25)
    -- upvalues: (ref) v_u_24
    _G.TutorialEnabled = p25
    v_u_24 = p25
end)
local v_u_26 = v_u_22
local v_u_27 = v_u_24
while v_u_8.Character == nil or v_u_8.Character:FindFirstChild("Humanoid") == nil do
    wait(0.1)
end
local v_u_28 = {
    ["Cook"] = 5,
    ["Pizza Boxer"] = 5,
    ["Delivery"] = 5,
    ["Supplier"] = 10
}
v14.RecivedCustomerOrder.OnClientEvent:connect(function(p29, p30)
    -- upvalues: (ref) v_u_18, (ref) v_u_19
    v_u_18 = p29
    v_u_19 = p30
end)
v14.NofityFoodOrderComplete.OnClientEvent:connect(function(p31, p32)
    if p32 ~= nil then
        flashRegisterButton(p32, p31)
    end
end)
function flashRegisterButton(p_u_33, p34)
    if p_u_33:FindFirstChild("SG") then
        local v_u_35 = p_u_33.SG.Frame
        if p34 then
            v_u_35.Check.Image = "http://www.roblox.com/asset/?id=168397389"
        else
            v_u_35.Check.Image = "http://www.roblox.com/asset/?id=168401336"
            p_u_33.Sparkles.Enabled = true
        end
        delay(1.5, function()
            -- upvalues: (copy) p_u_33, (copy) v_u_35
            p_u_33.Sparkles.Enabled = false
            v_u_35.Check.Image = ""
        end)
    end
end
function changeJob(p36)
    -- upvalues: (copy) v_u_8, (copy) v_u_2
    local v37 = v_u_8.Team.Name
    if v37 and (v37 ~= p36 and v37 ~= "Manager") then
        v_u_2:SendData("ChangeJob", "PlayerChannel", nil, p36)
    end
end
v_u_8.Changed:connect(function(p38)
    -- upvalues: (copy) v_u_13, (copy) v_u_8, (copy) v_u_6
    if p38 == "TeamColor" then
        local v_u_39 = v_u_13.Notifications.JobChange
        v_u_39.JobName.TextColor3 = v_u_8.TeamColor.Color
        v_u_39.JobName.Text = v_u_6.BrickColorToTeamName[v_u_8.TeamColor.Number]
        v_u_39:TweenPosition(UDim2.new(1, 0, 0.8, 0), Enum.EasingDirection.InOut, Enum.EasingStyle.Sine, 1, true)
        delay(3, function()
            -- upvalues: (copy) v_u_39
            v_u_39:TweenPosition(UDim2.new(1, v_u_39.AbsoluteSize.X + 1, 0.8, 0), Enum.EasingDirection.InOut, Enum.EasingStyle.Sine, 1, true)
            wait(1)
        end)
    end
end)
local v_u_40 = Instance.new("SelectionBox")
v_u_40.Parent = script
local v_u_41 = Instance.new("FloorWire")
v_u_41.Transparency = 0.5
v_u_41.WireRadius = 0
v_u_41.TextureSize = Vector2.new(2, 2)
v_u_41.Texture = "http://www.roblox.com/asset/?id=168194931"
v_u_41.Parent = script
local_parts = workspace.Spots
local_parts.Parent = game.ReplicatedStorage
local v_u_42 = nil
local v_u_43 = nil
local v_u_44 = Vector3.new(0, 0, 0)
local v_u_45 = 0
local v_u_46 = 0
local v_u_47 = Instance.new("Dragger")
function displayGuideArrows(p48)
    -- upvalues: (copy) v_u_41
    v_u_41.To = p48
    if p48.Name ~= "Bottom" and script:FindFirstChild(p48.Name) then
        script[p48.Name].Enabled = true
    end
    script.ArrowBillboardGui.Enabled = true
    script.ArrowBillboardGui.Adornee = p48
end
local v_u_49 = game:GetService("UserInputService").TouchEnabled and not game:GetService("UserInputService").MouseEnabled
if v_u_49 then
    v_u_49 = not game:GetService("UserInputService").KeyboardEnabled
end
local v_u_50 = game:GetService("UserInputService")
function workspace.TutorialService.IsTouchEnabled.OnClientInvoke()
    -- upvalues: (copy) v_u_49
    return v_u_49
end
local v_u_51 = workspace.CurrentCamera
local v_u_52 = nil
local v_u_53 = v_u_13.AbsoluteSize.X
local _ = v_u_13.AbsoluteSize.Y
local v_u_54 = nil
game:GetService("RunService")
function cameraLock(p55)
    -- upvalues: (copy) v_u_49, (copy) v_u_51, (copy) v_u_8, (ref) v_u_52, (copy) v_u_4, (copy) v_u_50, (copy) v_u_53
    if v_u_49 and _G.StartedPlaying then
        if p55 then
            script.CameraLock.Value = true
            v_u_51.CameraType = "Scriptable"
            v_u_8.Character.Humanoid.WalkSpeed = 0
            if v_u_52 then
                v_u_52:disconnect()
                v_u_4:EndTweenPan()
                v_u_52 = nil
            end
            v_u_52 = v_u_50.InputChanged:connect(function(p56, _)
                -- upvalues: (ref) v_u_53, (ref) v_u_4, (ref) v_u_8
                if p56.UserInputType == Enum.UserInputType.Touch then
                    local v57 = p56.Position
                    if v57.X < v_u_53 / 8 then
                        v_u_4:TweenPan(v_u_8, -1.5)
                        return
                    end
                    if v57.X > v_u_53 - v_u_53 / 8 then
                        v_u_4:TweenPan(v_u_8, 1.5)
                        return
                    end
                    v_u_4:EndTweenPan()
                end
            end)
            return
        end
        script.CameraLock.Value = false
        v_u_51.CameraType = "Custom"
        if v_u_52 then
            v_u_52:disconnect()
            v_u_4:EndTweenPan()
            v_u_52 = nil
        end
        v_u_8.Character.Humanoid.WalkSpeed = game.ReplicatedStorage.GlobalData.DoubleTime.Value and 23 or (game.ReplicatedStorage.GlobalData.NeonTime.Value and 23 or game.StarterPlayer.CharacterWalkSpeed)
    end
end
function SurfaceGuisEnabled(p58, p59)
    for _, v60 in ipairs(p58:GetChildren()) do
        if v60:IsA("SurfaceGui") then
            v60.Enabled = p59
        end
    end
end
local v_u_61 = nil
function copyLocal(p62)
    -- upvalues: (ref) v_u_16, (ref) v_u_61
    v_u_16 = p62:clone()
    v_u_16.Parent = p62.Parent
    v_u_16.CFrame = p62.CFrame
    v_u_16.Name = "LocalCopy"
    v_u_16.CanCollide = false
    v_u_16.Anchored = true
    v_u_61 = p62
    p62.Parent = game.ReplicatedStorage
end
local function v_u_68(p_u_63, p64)
    local v_u_65 = p64 and p64:GetAttribute("InstanceId") or math.random(1, 50000)
    task.spawn(function()
        -- upvalues: (copy) p_u_63, (copy) v_u_65
        p_u_63.Name = "PlaceHolder"
        if p_u_63:IsA("BasePart") then
            p_u_63.CanCollide = false
            p_u_63.Anchored = true
        end
        local v_u_66 = nil
        v_u_66 = game:GetService("CollectionService"):GetInstanceAddedSignal("MakesLocalCopies"):Connect(function(p67)
            -- upvalues: (ref) v_u_65, (ref) v_u_66, (ref) p_u_63
            if p67:GetAttribute("InstanceId") == v_u_65 then
                v_u_66:Disconnect()
                p_u_63:Destroy()
            end
        end)
    end)
    return v_u_65
end
local v_u_69 = nil
local v_u_70 = false
function onUp()
    -- upvalues: (copy) v_u_9, (ref) v_u_16, (ref) v_u_43, (ref) v_u_21, (ref) v_u_42, (copy) v_u_5, (copy) v_u_41, (copy) v_u_3, (ref) v_u_17, (ref) v_u_27, (ref) v_u_15, (ref) v_u_54, (copy) v_u_68, (copy) v_u_6, (copy) v_u_47, (ref) v_u_20, (ref) v_u_70
    if script.CameraLock.Value then
        cameraLock(false)
    end
    local v_u_71 = v_u_9.Target
    local v72
    if v_u_16 then
        v72 = v_u_16.Position
    else
        v72 = nil
    end
    if v_u_43 and v_u_71.Parent.Name ~= "Ingredients" then
        if v_u_71.Name == "Dough" and not v_u_21.SG.Frame:FindFirstChild("ImageLabel") then
            if v_u_42.Parent ~= v_u_71.SG.Frame then
                v_u_42.Parent = v_u_71.SG.Frame
            end
            v_u_21:Destroy()
            local v_u_73 = v_u_42
            v_u_42 = nil
            task.spawn(function()
                -- upvalues: (copy) v_u_71, (copy) v_u_73
                v_u_71.SG.Frame.ChildAdded:Wait()
                if v_u_73 and v_u_73.Parent then
                    v_u_73:Destroy()
                end
            end)
            v_u_5:FireServer("AddIngredientToPizza", v_u_71, v_u_43)
        else
            local v_u_74 = v_u_21
            spawn(function()
                -- upvalues: (copy) v_u_74
                wait(10)
                if v_u_74 and v_u_74.Parent then
                    v_u_74:Destroy()
                end
            end)
        end
        v_u_41.To = nil
        v_u_41.From = nil
        v_u_9.TargetFilter = nil
        v_u_3:PlaySound("Drop", v_u_21)
        v_u_9.Icon = ""
        v_u_43 = nil
        v_u_21 = nil
        v_u_42 = nil
        return
    elseif v_u_43 and v_u_71.Parent.Name == "Ingredients" then
        v_u_3:PlaySound("Drop", v_u_71)
        v_u_21:Destroy()
        v_u_21 = nil
        v_u_42 = nil
        v_u_43 = nil
        v_u_9.Icon = ""
    elseif v_u_17 then
        cameraLock(false)
        local v75 = true
        if v_u_27 and (v_u_15 and v_u_15.Parent) then
            if v_u_15.Name == "Dough" and (v_u_15.Position - workspace.CookTable.Position).magnitude < 10 then
                workspace.TutorialService.PlayerAction:FireServer("DraggedToTable", true)
            elseif v_u_15.Name == "Dough" and (v_u_15.Position - workspace.DoughLock.Position).magnitude < 3 then
                workspace.TutorialService.PlayerAction:FireServer("DraggedToConvayer", true)
            elseif v_u_15.Name == "Dough" and v_u_71.Parent.Name == "Oven" then
                workspace.TutorialService.PlayerAction:FireServer("DraggedToOven", v_u_71.Parent)
            elseif v_u_15.Name == "BoxClosed" and (v_u_15.Position - local_parts.BoxSpot.Position).magnitude < 18 then
                local v_u_76 = v_u_15
                spawn(function()
                    -- upvalues: (copy) v_u_76
                    wait(0.5)
                    local v77 = v_u_76.Position.Y - 5
                    if math.abs(v77) < 1 then
                        workspace.TutorialService.PlayerAction:FireServer("DraggedToDelivery", true)
                    end
                end)
            elseif v_u_15.Name == "SupplyBox" then
                if (v_u_15.Position - workspace.SupplyBelt.Position).magnitude < 18 and v_u_15.Position.Z > -13 then
                    workspace.TutorialService.PlayerAction:FireServer("DraggedToSupplyBelt", true)
                else
                    for _, v78 in ipairs(workspace.Trucks:GetChildren()) do
                        if v78 and (v78:FindFirstChild("Bottom") and (v78.Bottom.Position - v_u_15.Position).magnitude < 13) then
                            workspace.TutorialService.PlayerAction:FireServer("DraggedToTruck", true)
                        end
                    end
                end
            end
            v_u_54 = v_u_15
        end
        if v_u_15.Name == "Dough" and v_u_15.Size.Y == 1 then
            changeJob("Cook")
            v75 = false
            local v79 = v_u_16
            local v80 = v_u_16:clone()
            local v81 = v79.Position
            local v82 = v79.Size.Y / 2 - 0.1
            local v83 = v81 - Vector3.new(0, v82, 0)
            v80.Size = Vector3.new(5, 0.2, 5)
            v80.Mesh:Destroy()
            Instance.new("CylinderMesh").Parent = v80
            v80.Position = v83
            v80.Parent = workspace.AllDough
            v_u_3:PlaySound("DoughPlop")
            v_u_16.Parent = nil
            v_u_68(v80, v_u_15)
            if v_u_6.IsStudio then
                wait()
            end
            v_u_5:FireServer("SquishDough", v_u_15)
            v_u_15.Parent = nil
        else
            v_u_3:PlaySound("Drop", v_u_15)
        end
        if v_u_15.Name == "Dough" and (v_u_71.Parent.Name == "Trash" and v_u_15:FindFirstChild("Fire") == nil) then
            v_u_3:PlaySound("Trash", v_u_15)
            v_u_15.CanCollide = false
        end
        if v_u_15.Name == "BoxClosed" and (v_u_15:FindFirstChild("Logo") and not (v_u_15.HasPizzaInside.Value or v_u_15:GetAttribute("WasClosed"))) then
            changeJob("Pizza Boxer")
            v75 = false
            local v84 = game.ReplicatedStorage.Supplies.BoxOpen:clone()
            v84.CFrame = v_u_16.CFrame + Vector3.new(0, 1.874, 0)
            v84.Parent = workspace.AllBox
            v_u_3:PlaySound("BoxOpen", workspace.BoxingTable)
            v_u_16.Parent = nil
            v_u_68(v84, v_u_15)
            if v_u_6.IsStudio then
                wait()
            end
            v_u_5:FireServer("OpenBox", v_u_15)
            v_u_15.Parent = nil
            if v_u_27 then
                workspace.TutorialService.PlayerAction:FireServer("BoxOpened", true)
            end
        end
        if v_u_27 and (v_u_15 and (v_u_15.Name == "Pizza" and (v_u_71.Name == "BoxOpen" and v_u_71.Pizza.Value == v_u_15))) then
            workspace.TutorialService.PlayerAction:FireServer("PizzaPlacedInsideBox", v_u_71)
        end
        v_u_9.Icon = ""
        v_u_9.TargetFilter = nil
        v_u_17 = false
        v_u_47:MouseUp()
        v_u_41.To = nil
        v_u_41.From = nil
        script.TableSpot.Enabled = false
        script.OvenSpot.Enabled = false
        script.DewSpot.Enabled = false
        script.DewSpot2.Enabled = false
        script.SupplyBoxSpot.Enabled = false
        script.BoxSpot.Enabled = false
        script.ArrowBillboardGui.Enabled = false
        local v85 = v_u_15
        local v86 = v_u_16
        v_u_15 = nil
        if v75 then
            if v86.Parent ~= game.ReplicatedStorage then
                local v87 = 30
                while (v72 - v85.Position).magnitude > 0.0005 and v87 > 0 do
                    wait()
                    v87 = v87 - 1
                end
            end
            if v85.Name ~= "Pizza" or v_u_71.Name ~= "BoxOpen" then
                v_u_5:FireServer("UpdateProperty", v85, "Anchored", false)
            end
            v86:Destroy()
            if v85.Parent == game.ReplicatedStorage then
                v85.Parent = v_u_20
            end
        end
        v_u_70 = false
    end
end
local v_u_88 = not v_u_6.IsPartyServer
if v_u_88 then
    v_u_88 = workspace.Drawer["Pizza Slicer"].Center.ArrowBillboardGui
end
function AnimateSlicerArrow()
    -- upvalues: (copy) v_u_88
    if v_u_88 then
        if not v_u_88.Enabled then
            v_u_88.Enabled = true
            task.spawn(function()
                -- upvalues: (ref) v_u_88
                while v_u_88.Enabled do
                    local v89 = {
                        ["StudsOffset"] = Vector3.new(0, 2, 0)
                    }
                    game:GetService("TweenService"):Create(v_u_88, TweenInfo.new(0.5, Enum.EasingStyle.Sine), v89):Play()
                    task.wait(0.5)
                    local v90 = {
                        ["StudsOffset"] = Vector3.new(0, 1.5, 0)
                    }
                    game:GetService("TweenService"):Create(v_u_88, TweenInfo.new(0.5, Enum.EasingStyle.Sine), v90):Play()
                    task.wait(0.5)
                end
            end)
            task.delay(2, function()
                -- upvalues: (ref) v_u_88
                v_u_88.Enabled = false
            end)
        end
    else
        return
    end
end
function onDown(p91)
    -- upvalues: (copy) v_u_9, (copy) v_u_51, (copy) v_u_8, (ref) v_u_69, (ref) v_u_26, (copy) v_u_3, (ref) v_u_44, (ref) v_u_45, (ref) v_u_17, (ref) v_u_43, (copy) v_u_49, (ref) v_u_46, (copy) v_u_40, (copy) v_u_10, (ref) v_u_18, (ref) v_u_19, (copy) v_u_5, (ref) v_u_27, (ref) v_u_21, (ref) v_u_42, (copy) v_u_6, (ref) v_u_70, (ref) v_u_54, (copy) v_u_41, (ref) v_u_16, (copy) v_u_2, (copy) v_u_68, (ref) v_u_20, (ref) v_u_15, (copy) v_u_47, (copy) v_u_28, (copy) v_u_13, (copy) v_u_12
    local v92 = _G.GamepadEnabled and Vector2.new(v_u_9.X, v_u_9.Y) or Vector2.new(p91.Position.X, p91.Position.Y)
    local v93 = v_u_51:ScreenPointToRay(v92.X, v92.Y)
    local v94 = Ray.new(v93.Origin, v93.Direction * 60)
    local v95 = workspace
    local v96 = {}
    local v97 = v_u_8.Character
    local v98 = v_u_9.TargetFilter
    local v99 = game.CollectionService
    __set_list(v96, 1, {v97, v98, table.unpack(v99:GetTagged("RaycastBlacklist"))})
    local v_u_100, v101, _ = v95:FindPartOnRayWithIgnoreList(v94, v96)
    if v_u_100 and v_u_100.Parent then
        if v_u_8.Character:FindFirstChild("FireExtinguisher") then
            return
        end
        if script.CameraLock.Value then
            cameraLock(false)
        end
        if v_u_100 == nil or v_u_100.Parent == nil then
            return
        end
        v_u_69 = nil
        if v_u_100.Name == "PlaceHolder" then
            print("LOCAL PLACEHOLDER")
            return
        end
        if v_u_26 == nil then
            print("ERROR jobcomplted null")
            return
        end
        if v_u_100:FindFirstChild("Tutorial") and (v_u_100.Tutorial.Value ~= nil and v_u_100.Tutorial.Value ~= game.Players.LocalPlayer) then
            v_u_3:PlaySound("Invalid")
            print("NOT ALLOWED")
            return
        end
        if v_u_8:DistanceFromCharacter(v101) > 120 then
            return
        end
        v_u_44 = tick()
        v_u_45 = v101
        if v_u_17 or v_u_43 then
            if v_u_49 then
                onMove()
            end
            onUp()
            return
        end
        v_u_46 = 0
        if (v_u_100.Parent.Name == "Register1" or (v_u_100.Parent.Name == "Register2" or v_u_100.Parent.Name == "Register3")) and v_u_100:FindFirstChild("Pressed") then
            v_u_40.Adornee = nil
            changeJob("Cashier")
            if not v_u_100.Pressed.Value then
                v_u_10:Play()
                v_u_3:PlaySound("RegisterButtonDown", v_u_100)
                local v_u_102 = v_u_100.CFrame
                v_u_100.CFrame = v_u_100.CFrame + v_u_100.CFrame.upVector / -5.3
                v_u_100.Pressed.Value = true
                delay(0.1, function()
                    -- upvalues: (copy) v_u_100, (copy) v_u_102, (ref) v_u_3
                    v_u_100.CFrame = v_u_102
                    v_u_100.Pressed.Value = false
                    v_u_3:PlaySound("RegisterButtonUp", v_u_100)
                end)
            end
            local v103 = v_u_100.Name
            local v104 = string.sub(v103, 7)
            if v_u_18 ~= nil and v_u_19 ~= nil then
                if v104 == v_u_18 then
                    flashRegisterButton(v_u_100, false)
                else
                    flashRegisterButton(v_u_100, true)
                end
                v_u_5:FireServer("OrderComplete", v_u_19, v104, v_u_100.Parent)
                v_u_18 = nil
                v_u_19 = nil
                return
            end
            workspace.GameService.RegisterButtonPressedNoCustomer:FireServer(v104, v_u_100)
        elseif v_u_100.Parent.Name == "Ingredients" and (not v_u_43 and (v_u_100.Transparency == 0 or v_u_100:FindFirstChild("Dragger"))) then
            if v_u_27 and v_u_100.Name == "Sausage" then
                return
            elseif ({
                ["Cheese"] = true,
                ["Pepperoni"] = true,
                ["Sausage"] = true,
                ["TomatoSauce"] = true
            })[v_u_100.Name] then
                if v_u_100:FindFirstChild("CurrentDragger") then
                    local v105 = v_u_100.CurrentDragger.Value
                    if v105 and (v105 ~= v_u_8 and v105.Parent ~= nil) then
                        print("Another player already dragging")
                        v_u_3:PlaySound("Invalid")
                        return
                    end
                end
                v_u_3:PlaySound("PickUp", v_u_100)
                changeJob("Cook")
                v_u_9.Icon = "http://www.roblox.com/asset/?id=168756505"
                v_u_21 = game.ReplicatedStorage.Supplies.Dragger:clone()
                v_u_21.Name = v_u_100.Name
                v_u_21.Locked = false
                v_u_21.LastDragger.Value = v_u_8
                v_u_21.CurrentDragger.Value = v_u_8
                v_u_21.LastDrag.Value = game.Workspace.DistributedGameTime
                v_u_42 = v_u_21.SG.Frame.ImageLabel
                v_u_42.Image = v_u_6.IngredientImages[v_u_100.Name]
                v_u_42.ZIndex = ({
                    ["Cheese"] = 2,
                    ["Pepperoni"] = 3,
                    ["Sausage"] = 3,
                    ["TomatoSauce"] = 1
                })[v_u_100.Name]
                if v_u_100:FindFirstChild("Dragger") then
                    v_u_100:Destroy()
                end
                v_u_70 = true
                cameraLock(true)
                v_u_21.Parent = workspace.Ingredients
                v_u_9.TargetFilter = v_u_21
                v_u_43 = v_u_21.Name
                if v_u_27 then
                    workspace.TutorialService.PlayerAction:FireServer(v_u_100.Name, true)
                    if v_u_54 then
                        v_u_41.To = v_u_54
                        v_u_41.From = v_u_16
                    end
                end
            end
        end
        if v_u_100.Name == "BoxOpen" and (v_u_8.Character:FindFirstChild("Pizza Slicer") and (v_u_100.Pizza.Value and v_u_100.IsSliced.Value == false)) then
            v_u_3:PlaySound("CutPizza")
            v_u_3:PlaySound("CutObject")
            workspace.Animation.PlayAnimation.PlayAnimation:Fire("PizzaSlice")
            v_u_100.IsSliced.Value = true
            local v106 = game.ReplicatedStorage.SliceSeams:Clone()
            v106:PivotTo(v_u_100.Pizza.Value.CFrame)
            v106.Parent = v_u_100
            v_u_2:Weld(v_u_100.Pizza.Value, v106.Base)
            local v107 = v_u_68(v106)
            if v_u_6.IsStudio then
                wait()
            end
            v_u_5:FireServer("SlicePizza", v_u_100, v107)
            local v108 = game.ReplicatedStorage.SliceSplat:Clone()
            v108.Enabled = false
            v108.Parent = v_u_100.Pizza.Value
            v108:Emit(10)
            if v_u_8.Character:FindFirstChild("Pizza Slicer"):GetAttribute("IsGolden") then
                local v109 = game.ReplicatedStorage.PlusTenPercent:Clone()
                v109.Parent = v_u_100
                game:GetService("Debris"):AddItem(v109, 1)
            end
            return
        end
        if v_u_100.Name == "BoxOpen" and (not v_u_8.Character:FindFirstChild("Pizza Slicer") and (v_u_100.Pizza.Value and v_u_100.IsSliced.Value == false)) then
            v_u_3:PlaySound("Invalid")
            if v_u_100:FindFirstChild("NeedSlicer") then
                v_u_100.NeedSlicer:Destroy()
            end
            local v110 = game.ReplicatedStorage.NeedSlicer:Clone()
            v110.Parent = v_u_100
            game:GetService("Debris"):AddItem(v110, 1)
            AnimateSlicerArrow()
            v_u_5:FireServer("OpenDrawer")
            return
        end
        if v_u_100.Name == "BoxOpen" and (v_u_100.Pizza.Value ~= nil or not v_u_8.Character:FindFirstChild("Pizza Slicer")) then
            changeJob("Pizza Boxer")
            if v_u_100.Pizza.Value then
                v_u_100.Pizza.Value.Parent = nil
            end
            local v111 = game.ReplicatedStorage.Supplies.BoxClosed:clone()
            v111.CFrame = v_u_100.CFrame - Vector3.new(0, 2, 0)
            v111.Parent = workspace.AllBox
            v_u_3:PlaySound("BoxClose", workspace.BoxingTable)
            v_u_68(v111, v_u_100)
            if v_u_6.IsStudio then
                wait()
            end
            v_u_5:FireServer("CloseBox", v_u_100)
            v_u_100:Destroy()
            if v_u_27 then
                workspace.TutorialService.PlayerAction:FireServer("ClosedBox", true)
            end
            return
        end
        if not v_u_100.Locked and (v_u_100.Name == "Handle" and v_u_100.Parent:IsA("Tool")) then
            if v_u_27 and v_u_100.Parent.Name == "PizzaTool" then
                workspace.TutorialService.PlayerAction:FireServer("GrabbedPizza", true)
            end
            v_u_5:FireServer("AddPizzaToBackpack", v_u_100.Parent)
        end
        if v_u_6.Cutables[v_u_100.Name] and (v_u_8.Character:FindFirstChild("Pizza Slicer") and (v_u_2:ProxyCheck(v_u_8, v_u_100.Position, 25) and v_u_8.Character["Pizza Slicer"]:GetAttribute("IsGolden"))) then
            v_u_3:PlaySound("CutObject")
            v_u_5:FireServer("SliceObject", v_u_100)
            workspace.Animation.PlayAnimation.PlayAnimation:Fire("PizzaSlice")
            return
        end
        if v_u_6.Dragables[v_u_100.Name] then
            local v112 = v_u_100.CurrentDragger.Value
            if v112 and (v112 ~= v_u_8 and v112.Parent ~= nil) then
                v_u_3:PlaySound("Invalid")
                print("Another player already dragging")
                return
            end
            v_u_3:PlaySound("PickUp", v_u_100)
            v_u_20 = v_u_100.Parent
            v_u_100.Transparency = 0
            copyLocal(v_u_100)
            v_u_15 = v_u_100
            workspace.GameService.DraggingStarted:FireServer(v_u_15)
            if v_u_17 then
                v_u_47:MouseUp()
            end
            cameraLock(true)
            v_u_70 = true
            v_u_9.Icon = "http://www.roblox.com/asset/?id=168756505"
            v_u_17 = true
            local v113 = v_u_47
            local v114 = v_u_16
            local v115 = -v_u_100.Size.Y / 2
            local v116 = { v_u_16 }
            v113:MouseDown(v114, Vector3.new(0, v115, 0), v116)
            v_u_5:FireServer("UpdateProperty", v_u_15, "Anchored", true)
            v_u_16.Rotation = Vector3.new(0, 0, 0)
            v_u_41.To = nil
            v_u_41.From = v_u_16
            v_u_40.Adornee = v_u_16
            v_u_40.Color = v_u_8.TeamColor
            if v_u_100.Name == "MountainDew" then
                changeJob("Cook")
                if v_u_26.Cook < v_u_28.Cook then
                    displayGuideArrows(local_parts.DewSpot)
                end
            elseif v_u_100.Name == "Dough" then
                if v_u_27 and not v_u_100:FindFirstChild("Tutorial") then
                    workspace.TutorialService.NewDough:FireServer(v_u_100)
                end
                changeJob("Cook")
                if v_u_26.Cook < v_u_28.Cook then
                    if (v_u_100.HasBugs.Value or (v_u_100.IsBurned.Value or v_u_100.Cold.Value)) and v_u_100:FindFirstChild("Fire") == nil then
                        displayGuideArrows(workspace.Trash.Flap)
                    elseif v_u_100.SG.Frame:FindFirstChild("TomatoSauce") and v_u_100.SG.Frame:FindFirstChild("Cheese") then
                        local v117 = 100
                        local v118 = nil
                        for _, v119 in ipairs(workspace.Ovens:GetChildren()) do
                            if v119 and (v119.IsOpen.Value and v_u_8:DistanceFromCharacter(v119.Bottom.Position) < v117) then
                                v117 = v_u_8:DistanceFromCharacter(v119.Bottom.Position)
                                v118 = v119
                            end
                        end
                        if v118 then
                            displayGuideArrows(v118.Bottom)
                        else
                            for _, v120 in ipairs(workspace.Ovens:GetChildren()) do
                                if v120 and not v120.IsCooking.Value then
                                    displayGuideArrows(v120.Bottom)
                                    break
                                end
                            end
                        end
                    elseif v_u_100.SG.Frame:FindFirstChild("TomatoSauce") and v_u_100.SG.Frame:FindFirstChild("MeltedCheese") then
                        displayGuideArrows(local_parts.PizzaEndSpot)
                    else
                        local v121 = v_u_100.Size.X
                        if math.floor(v121) == 3 then
                            displayGuideArrows(local_parts.TableSpot)
                        end
                    end
                end
            elseif v_u_100.Name == "BoxClosed" then
                changeJob("Pizza Boxer")
                if v_u_26["Pizza Boxer"] < v_u_28["Pizza Boxer"] and v_u_100:FindFirstChild("Logo") then
                    if v_u_100.HasPizzaInside.Value then
                        displayGuideArrows(workspace.BoxingRoomBelts.BoxBelt)
                    else
                        displayGuideArrows(local_parts.BoxSpot)
                    end
                end
            elseif v_u_100.Name == "Pizza" then
                if v_u_27 then
                    for _, v122 in ipairs(v_u_13:GetChildren()) do
                        if v122:IsA("BillboardGui") and v122.Adornee == v_u_100 then
                            v122:Destroy()
                        end
                    end
                    workspace.TutorialService.NewPizza:FireServer(v_u_100)
                end
                changeJob("Pizza Boxer")
                if v_u_26["Pizza Boxer"] < v_u_28["Pizza Boxer"] then
                    v_u_41.To = workspace.AllBox:FindFirstChild("BoxOpen")
                end
            elseif v_u_100.Name == "Dew" then
                changeJob("Pizza Boxer")
                if v_u_26["Pizza Boxer"] < v_u_28["Pizza Boxer"] then
                    displayGuideArrows(workspace.BoxingRoomBelts.DewBelt)
                end
            elseif v_u_100.Name == "SupplyBox" then
                changeJob("Supplier")
                if v_u_26.Supplier < v_u_28.Supplier then
                    local v123 = workspace.Trucks:GetChildren()
                    local v124
                    if v_u_27 and (v123[1]:FindFirstChild("Driver") and (v123[1].Driver:FindFirstChild("TutorialPlayerOnly") and v123[1].Driver.TutorialPlayerOnly.Player.Value == game.Players.LocalPlayer)) then
                        v124 = v123[1].Bottom
                    elseif v_u_27 and (#v123 == 2 and (v123[2]:FindFirstChild("Driver") and (v123[2].Driver:FindFirstChild("TutorialPlayerOnly") and v123[2].Driver.TutorialPlayerOnly.Player.Value == game.Players.LocalPlayer))) then
                        v124 = v123[2].Bottom
                    elseif #v123 == 2 and v_u_8:DistanceFromCharacter(v123[1].Bottom.Position) > v_u_8:DistanceFromCharacter(v123[2].Bottom.Position) then
                        v124 = v123[2].Bottom
                    elseif #v123 == 0 then
                        v124 = workspace.Border
                    else
                        v124 = v123[1].Bottom
                    end
                    displayGuideArrows(v124)
                end
            end
            v_u_9.TargetFilter = v_u_16
        end
        if v_u_100.Parent:FindFirstChild("Humanoid") and (game.Players:GetPlayerFromCharacter(v_u_100.Parent) ~= nil and v_u_8.TeamColor == BrickColor.new(37)) then
            local v125 = game.Players:GetPlayerFromCharacter(v_u_100.Parent)
            if v125 ~= v_u_8 then
                game.Players.LocalPlayer.PlayerGui.Gui.ManagerPowers.Current_Player.Value = v125
                v_u_12:GetWindowDataByName("ManagerPowers"):SetVisible(true)
            end
        end
    end
end
local v_u_126 = nil
if v_u_6.PlaceSettings.CustomCodeIndex == "ChallengeEvent" then
    local v127 = game.ReplicatedStorage._v6FiRE_Additions.ClassicPt2Event.Difficulty
    if v127.Value == "" then
        v127.Changed:Wait()
    end
    if v127.Value == "Medium" then
        v_u_126 = workspace:WaitForChild("SpaceModels", 999)
    end
end
function onButton1Up()
    -- upvalues: (ref) v_u_126, (ref) v_u_46, (ref) v_u_70
    if v_u_126 then
        v_u_126.Parent = workspace
    end
    if v_u_46 > 5 then
        onUp(true)
    elseif v_u_70 then
        cameraLock(false)
    end
end
function Weld(p128, p129)
    local v130 = Instance.new("Weld")
    v130.Name = "PizzaWeld"
    v130.Part0 = p128
    v130.Part1 = p129
    local v131 = CFrame.new(p128.Position)
    local v132 = p128.CFrame:inverse() * v131
    local v133 = p129.CFrame:inverse() * v131
    v130.C0 = v132
    v130.C1 = v133
    v130.Parent = p128
end
local v_u_134 = workspace.CurrentCamera
local v_u_135 = nil
local v_u_136 = nil
local v_u_137 = Vector3.new(0, 0, 0)
local v_u_138 = nil
function onMove()
    -- upvalues: (copy) v_u_9, (ref) v_u_17, (ref) v_u_43, (ref) v_u_46, (ref) v_u_135, (ref) v_u_126, (copy) v_u_8, (ref) v_u_69, (ref) v_u_16, (copy) v_u_5, (ref) v_u_15, (copy) v_u_3, (copy) v_u_10, (copy) v_u_47, (ref) v_u_137, (ref) v_u_136, (copy) v_u_134, (copy) v_u_40, (ref) v_u_138, (ref) v_u_42, (ref) v_u_21
    if v_u_9 and (v_u_9.Target and v_u_9.Target.Parent) then
        if v_u_9.Target.Name == "PlaceHolder" then
            return
        end
        if v_u_17 or v_u_43 then
            v_u_46 = v_u_46 + 1
        end
        v_u_135 = v_u_9.Target
        if v_u_135 == nil then
            return
        end
        if v_u_17 then
            if v_u_126 then
                v_u_126.Parent = nil
            end
            if v_u_8:DistanceFromCharacter(v_u_9.Hit.p) > 120 then
                return
            end
            if v_u_69 == v_u_135 or v_u_69 == v_u_135.Parent then
                if v_u_69 == v_u_135 or v_u_69 == v_u_135.Parent then
                    return
                end
            else
                if v_u_135.Parent.Name == "Spots" and script[v_u_135.Name].Enabled then
                    v_u_69 = v_u_135
                    v_u_16.Position = v_u_135.Position
                    v_u_5:FireServer("UpdateProperty", v_u_15, "CFrame", v_u_16.CFrame)
                    v_u_3:PlaySound("Pop2", v_u_15)
                    v_u_10:Play()
                    return
                end
                if v_u_135.Name == "DewBelt" and (v_u_15.Name == "Dew" or v_u_15.Name == "MountainDew") then
                    v_u_69 = v_u_135
                    local v139 = v_u_16
                    local v140 = v_u_135.CFrame
                    local v141 = (v_u_135.Size.Y + v_u_15.Size.Y) / 2
                    v139.CFrame = v140 + Vector3.new(0, v141, 0)
                    v_u_5:FireServer("UpdateProperty", v_u_15, "CFrame", v_u_16.CFrame)
                    v_u_3:PlaySound("Pop2", v_u_15)
                    v_u_10:Play()
                    return
                end
                if v_u_135.Name == "BoxBelt" and v_u_15.Name == "BoxClosed" then
                    v_u_69 = v_u_135
                    local v142 = v_u_16
                    local v143 = v_u_135.CFrame
                    local v144 = (v_u_135.Size.Y + v_u_15.Size.Y) / 2
                    v142.CFrame = v143 + Vector3.new(0, v144, 0)
                    v_u_5:FireServer("UpdateProperty", v_u_15, "CFrame", v_u_16.CFrame)
                    v_u_3:PlaySound("Pop2", v_u_15)
                    v_u_10:Play()
                    return
                end
                if v_u_135.Parent.Name == "Oven" and (v_u_135.Parent.IsOpen.Value and v_u_15.Name == "Dough") then
                    v_u_69 = v_u_135.Parent
                    local v145 = v_u_16
                    local v146 = v_u_135.Parent.Bottom.CFrame
                    local v147 = (v_u_135.Parent.Bottom.Size.Y + v_u_15.Size.Y) / 2
                    v145.CFrame = v146 + Vector3.new(0, v147, 0)
                    v_u_5:FireServer("UpdateProperty", v_u_15, "CFrame", v_u_16.CFrame)
                    v_u_3:PlaySound("Pop2", v_u_15)
                    v_u_10:Play()
                    return
                end
                if v_u_135.Name == "DoughLock" and v_u_15.Name == "Dough" then
                    v_u_69 = v_u_135
                    local v148 = v_u_16
                    local v149 = v_u_135.CFrame
                    local v150 = (v_u_135.Size.Y + v_u_15.Size.Y) / 2
                    v148.CFrame = v149 + Vector3.new(0, v150, 0)
                    v_u_5:FireServer("UpdateProperty", v_u_15, "CFrame", v_u_16.CFrame)
                    v_u_3:PlaySound("Pop2", v_u_15)
                    v_u_10:Play()
                    return
                end
                if v_u_135.Parent.Name == "Trash" and (v_u_15.Name == "Dough" and (v_u_15:FindFirstChild("Fire") == nil and (v_u_15.HasBugs.Value or (v_u_15.IsBurned.Value or v_u_15.Cold.Value)))) then
                    v_u_69 = v_u_135.Parent
                    v_u_16.CFrame = workspace.Trash.DoughCFrameLock.CFrame
                    v_u_5:FireServer("UpdateProperty", v_u_15, "CFrame", v_u_16.CFrame)
                    v_u_3:PlaySound("Pop2", v_u_15)
                    v_u_10:Play()
                    return
                end
                if v_u_135.Name == "BoxOpen" and (v_u_15.Name == "Pizza" and (v_u_135:FindFirstChild("Tutorial") == nil or v_u_135.Tutorial.Value == v_u_8)) and (v_u_135.Pizza.Value == nil or v_u_135.Pizza.Value == v_u_15) then
                    if v_u_69 ~= nil and v_u_135.Name == "BoxOpen" then
                        v_u_69.Anchored = false
                        v_u_5:FireServer("UpdateProperty", v_u_69, "Anchored", false)
                        v_u_69.Pizza.Value = nil
                        v_u_5:FireServer("AssignPizzaToBox", v_u_69, nil)
                    end
                    v_u_10:Play()
                    v_u_69 = v_u_135
                    v_u_135.Anchored = true
                    v_u_135.Pizza.Value = v_u_15
                    v_u_16.CFrame = v_u_135.CFrame:toWorldSpace(CFrame.new(Vector3.new(0, -2, 0)))
                    v_u_5:FireServer("UpdateProperty", v_u_15, "CFrame", v_u_16.CFrame)
                    v_u_5:FireServer("UpdateProperty", v_u_135, "Anchored", true)
                    v_u_5:FireServer("AssignPizzaToBox", v_u_135, v_u_15)
                    v_u_3:PlaySound("Pop2", v_u_15)
                    return
                end
            end
            if v_u_69 and (v_u_69.Name == "BoxOpen" and v_u_15.Name == "Pizza") then
                v_u_69.Anchored = false
                v_u_5:FireServer("UpdateProperty", v_u_69, "Anchored", false)
                if v_u_69:FindFirstChild("Pizza") then
                    v_u_69.Pizza.Value = nil
                end
                v_u_5:FireServer("AssignPizzaToBox", v_u_69, nil)
            end
            v_u_69 = nil
            v_u_47:MouseMove(v_u_9.UnitRay)
            if v_u_137 ~= v_u_16.Position then
                v_u_5:FireServer("UpdateProperty", v_u_15, "CFrame", v_u_16.CFrame)
                v_u_137 = v_u_16.Position
            end
        end
        v_u_136 = nil
        if not v_u_17 then
            local v151 = v_u_135:FindFirstChild("ClickDetector") or v_u_135:FindFirstChild("Hand") or (v_u_135.Parent:FindFirstChild("ClickDetector") or v_u_135.Parent.Parent:FindFirstChild("ClickDetector"))
            if v151 and v_u_8:DistanceFromCharacter(v_u_9.Hit.p) <= v151.Value then
                v_u_9.Icon = "rbxassetid://2102101333"
            elseif v_u_135.Name ~= "Body" then
                v_u_9.Icon = _G.MouseIcon
            end
        end
        if v_u_135 == nil or (v_u_135.Locked or (v_u_17 or (v_u_43 ~= nil or (not v_u_134 or v_u_134.CameraType == Enum.CameraType.Scriptable)))) then
            if v_u_135.Parent:FindFirstChild("Register") and (v_u_135.BrickColor == BrickColor.new("Medium stone grey") and v_u_135 ~= v_u_138) then
                if v_u_138 then
                    v_u_138.BrickColor = BrickColor.new("Medium stone grey")
                end
                v_u_135.BrickColor = BrickColor.new("Lily white")
                v_u_138 = v_u_135
            elseif v_u_8.TeamColor == BrickColor.new(37) and (v_u_135.Parent:FindFirstChild("Humanoid") and game.Players:GetPlayerFromCharacter(v_u_135.Parent)) then
                v_u_40.Adornee = v_u_135.Parent
                v_u_40.Color = v_u_8.TeamColor
            else
                v_u_40.Adornee = nil
                if v_u_138 and v_u_135 ~= v_u_138 then
                    v_u_138.BrickColor = BrickColor.new("Medium stone grey")
                    v_u_138 = nil
                end
            end
        else
            v_u_40.Adornee = v_u_135
            v_u_40.Color = v_u_8.TeamColor
        end
        if v_u_43 ~= nil then
            if v_u_135:FindFirstChild("Tutorial") and (v_u_135.Tutorial.Value ~= nil and v_u_135.Tutorial.Value ~= game.Players.LocalPlayer) then
                return
            end
            if v_u_135.Name == "Dough" and (v_u_135.SG.Frame:FindFirstChild(v_u_43) == nil and (v_u_135.Size.Y ~= 1 and (v_u_43 ~= "Sausage" or not v_u_135.SG.Frame:FindFirstChild("Pepperoni")))) and (v_u_43 ~= "Pepperoni" or not v_u_135.SG.Frame:FindFirstChild("Sausage")) then
                if v_u_42.Parent ~= v_u_135.SG.Frame then
                    v_u_3:PlaySound("IngredientSplat", v_u_135)
                    v_u_10:Play()
                    v_u_42.Parent = v_u_135.SG.Frame
                    return
                end
            elseif v_u_21 then
                if v_u_42.Parent ~= v_u_21.SG.Frame then
                    v_u_42.Parent = v_u_21.SG.Frame
                end
                if v_u_21 and v_u_21.Parent then
                    v_u_21.CFrame = CFrame.new(v_u_9.Hit.p)
                end
            end
        end
    end
end
v7.InputBegan:connect(function(p152, p153)
    if not p153 and (p152.UserInputType == Enum.UserInputType.MouseButton1 or (p152.UserInputType == Enum.UserInputType.Touch or p152.UserInputType == Enum.UserInputType.Gamepad1 and (p152.KeyCode == Enum.KeyCode.ButtonR2 and not game:GetService("VRService").VREnabled))) then
        onDown(p152)
    end
end)
v_u_9.Button1Up:connect(onButton1Up)
v_u_9.Move:connect(onMove)
local v_u_154 = false
if _G.GamepadEnabled then
    v_u_50.InputBegan:connect(function(p155, p156)
        -- upvalues: (ref) v_u_154
        if not p156 and (not v_u_154 and (p155.UserInputState == Enum.UserInputState.Begin and p155.KeyCode == Enum.KeyCode.ButtonR2)) then
            game:GetService("RunService"):BindToRenderStep("CameraMovement", Enum.RenderPriority.Camera.Value, function()
                onMove()
            end)
            v_u_154 = true
        end
    end)
    v_u_50.InputEnded:connect(function(p157, p158)
        -- upvalues: (ref) v_u_154
        if not p158 and (v_u_154 and (p157.UserInputState == Enum.UserInputState.End and p157.KeyCode == Enum.KeyCode.ButtonR2)) then
            game:GetService("RunService"):UnbindFromRenderStep("CameraMovement")
            v_u_154 = false
        end
    end)
end
