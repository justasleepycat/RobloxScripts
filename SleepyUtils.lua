local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

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

local function GetCurrentVehicle(Position : Vector3)

end

-- Example usage
SetVelocities(Players.LocalPlayer.Character:GetDescendants(), Vector3.new(0,100,0))