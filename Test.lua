
local function Appraise(TargetWeight)
    local VirtualInputManager = game:GetService("VirtualInputManager")
    local Tool = game.Players.LocalPlayer.Character:FindFirstChildWhichIsA("Tool")
    if Tool then
        for i,v in pairs(game:GetService("Players").LocalPlayer.PlayerGui.hud.safezone.backpack.hotbar:GetChildren()) do
            local success, err = pcall(function()
                if v.tool.Value == Tool then
                    local success, err = pcall(function()
                        if game:GetService("ReplicatedStorage").packages.Net["RF/AppraiseAnywhere/HaveValidFish"]:InvokeServer() then
                            if TargetWeight then
								local CurrentWeight = string.gsub(v.weight.Text, "kg", "")
                                CurrentWeight = tonumber(CurrentWeight)
                                if CurrentWeight > TargetWeight then
                                    print("Weight found. Aborting")
                                    return        
                                end
							end
                            workspace.world.npcs.Appraiser.appraiser.appraise:InvokeServer()
                            local keys = {
                                [1] = Enum.KeyCode.One,
                                [2] = Enum.KeyCode.Two,
                                [3] = Enum.KeyCode.Three,
                                [4] = Enum.KeyCode.Four,
                                [5] = Enum.KeyCode.Five,
                                [6] = Enum.KeyCode.Six,
                                [7] = Enum.KeyCode.Seven,
                                [8] = Enum.KeyCode.Eight,
                                [9] = Enum.KeyCode.Nine,
                            }
                            local key = keys[tonumber(v.Name)]
                            VirtualInputManager:SendKeyEvent(true, key, false, game)
                            VirtualInputManager:SendKeyEvent(false, key, false, game)
                            task.wait(.1)
                            local NewWeight = string.gsub(v.weight.Text, "kg", "")
                            NewWeight = tonumber(NewWeight)
                            if TargetWeight and TargetWeight >= NewWeight then
								print("New Weight: "..NewWeight)
                                print("Re-Appraising")
                                task.wait(.1)
                                Appraise(TargetWeight)
                            else
								print("Target Weight found")
							end
                        end
                    end)
                    if not success then
                        print(err)
                    end
                end
            end)
            if not success then
                --print(err)
            end
        end
    end
end
Appraise(150)