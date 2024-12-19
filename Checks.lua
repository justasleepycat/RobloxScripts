-- local Checks = loadstring(game:HttpGet("https://raw.githubusercontent.com/justasleepycat/RobloxScripts/refs/heads/main/Checks.lua"))()
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

function Checks:GetClosestPlayerToMouse(config)
    config = config or {}
    config.MaxDistance = config.MaxDistance or math.huge

    local CurrentCamera = Workspace.CurrentCamera
    local Mouse = Players.LocalPlayer:GetMouse()

    local closestPlayer, maxDist = nil, config.MaxDistance or math.huge
    for i,v in pairs(Players:GetChildren()) do
		pcall(function()
			if v == Players.LocalPlayer then
				return
			end
			local Position = v.Character.Head:GetPivot().Position or v.Character:GetPivot().Position
            if Position then
				local Pos2D, OnScreen = CurrentCamera:WorldToViewportPoint(Position)
                if OnScreen then
                    local dist = (Vector2.new(Pos2D.X, Pos2D.Y) - Vector2.new(Mouse.X, Mouse.Y)).Magnitude
                    if dist < maxDist then
                        maxDist = dist
                        closestPlayer = v
                    end
				end
			end
		end)
	end
    return closestPlayer
end

function Checks:GetClosestPlayerToPosition(config)
    config = config or {}
    config.MaxDistance = config.MaxDistance or math.huge
    local closestPlayer, maxDist = nil, config.MaxDistance or math.huge
    for i,v in pairs(Players:GetChildren()) do
		pcall(function()
			if v == Players.LocalPlayer then
				return
			end
			local Position = v.Character.Head:GetPivot().Position or v.Character:GetPivot().Position
            if Position then
                local dist = (config.Origin - Position).Magnitude
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
    GetClosestPlayerToMouse({
        MaxDistance = 100,
    }) <-- returns the player instance not the character
    GetClosestPlayerToPosition({
        MaxDistance = 500,
        Origin = Vector3.new(0,0,0),
    }) <-- returns the player instance
]]
if true then
    for i,v in pairs(game:GetService("Players"):GetChildren()) do
        pcall(function()
            local visible = Checks:IsVisible(game.Players.LocalPlayer.Character.Head.CFrame.Position, v.Character:GetPivot().Position, 1000, {game.Players.LocalPlayer.Character})
            if visible.Instance and visible.Instance:IsDescendantOf(v) then
                print(v:GetFullName())
            end
		end)
    end
    print(Checks:GetClosestPlayerToPosition({
        MaxDistance = 500,
        Origin = Workspace.CurrentCamera.CFrame.Position
    }))
    print(Checks:GetClosestPlayerToMouse()) 
end


return Checks
