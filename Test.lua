local HookingService = loadstring(game:HttpGet("https://raw.githubusercontent.com/justasleepycat/RobloxScripts/refs/heads/main/Hooking.lua"))()
local Checks = loadstring(game:HttpGet("https://raw.githubusercontent.com/justasleepycat/RobloxScripts/refs/heads/main/Checks.lua"))()

local Players = game:GetService("Players")
local Workspace =  game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local env = require(game:GetService("ReplicatedStorage").Module.RayCast)
for i,v in pairs(env) do
	getgenv()[i] = getgenv()[i] ~= nil and getgenv()[i] or env[i]
	env[i] = function(...)
		local args = {...}
		local name = tostring(args[4])
		if name == Players.LocalPlayer.Name then
		else
			local fenv = getfenv(3)
			if string.find(tostring(fenv.script), "Local") or string.find(tostring(fenv.script), "Alex") or string.find(tostring(fenv.script), "Item") or string.find(tostring(fenv.script), "Tank") or string.find(tostring(fenv.script), "Wheel") or string.find(tostring(fenv.script), "RobberyCargo") then
			else
				--print(fenv.script)
				--for i,v in pairs(args) do
				--	print(i,v, typeof(v))
				--end
				if tostring(getfenv(2).script) == "BulletEmitter" or tostring(getfenv(3).script) == "Taser" then
					local closestPlr = Checks:GetClosestPlayerToMouse({
						MaxDistance = 200
					})
					if closestPlr then
						local direction = (closestPlr.Character.Head.CFrame.Position - Workspace.CurrentCamera.CFrame.Position)
						local dist = direction.Magnitude
						args[2] = direction.Unit
					end
				end
			end
		end
		return getgenv()[i](unpack(args))
	end
end