local Checks = {}

local Players = game:GetService("Players")
local Workspace =  game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

function Checks:IsVisible(startPos : Vector3, endPos : Vector3, MaxDistance : number,ignore : table)
    local RayParams = RaycastParams.new()
    RayParams.FilterType = Enum.RaycastFilterType.Exclude
    RayParams.FilterDescendantsInstances = ignore
    RayParams.IgnoreWater = true
    RayParams.RespectCanCollide = true
    local result : RaycastResult = game:GetService("Workspace"):Raycast(startPos, (endPos - startPos).Unit * MaxDistance, RayParams)
    return result
end

function Checks:GetClosestPlayerToMouse()
    local CurrentCamera = Workspace.CurrentCamera
    local Mouse = Players.LocalPlayer:GetMouse()

    local closestPlayer, maxDist = nil, math.huge
    for i,v in pairs(Players:GetChildren()) do
		pcall(function()
			if v == Players.LocalPlayer then
				return
			end
			local Position = v.Character.Head:GetPivot().Position or v.Character:GetPivot().Position
            if Position then
				local Pos2D, OnScreen = CurrentCamera:WorldToViewportPoint(Position)
                local dist = (Vector2.new(Pos2D.X, Pos2D.Y) - Vector2.new(Mouse.X, Mouse.Y)).Magnitude
                if dist < maxDist then
					maxDist = dist
                    closestPlayer = v
				end
			end
		end)
	end
    return closestPlayer
end

--[[ Available Functions
    IsVisible(startPos : Vector3, endPos : Vector3, MaxDistance : number,ignore : table) <-- uses raycasting and returns the raycastresult
    GetClosestPlayerToMouse() <-- returns the player instance not the character
]]
if false then
    for i,v in pairs(game.Workspace.Threats:GetChildren()) do
        local visible = Checks:IsVisible(game.Players.LocalPlayer.Character.Head.CFrame.Position, v:GetPivot().Position, 1000, {game.Players.LocalPlayer.Character})
        if visible.Instance and visible.Instance:IsDescendantOf(v) then
            print(v:GetFullName())
        end
    end

    print(Checks:GetClosestPlayerToMouse()) 
end


return Checks
