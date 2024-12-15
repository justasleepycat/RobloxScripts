local HookingService = loadstring(game:HttpGet("https://raw.githubusercontent.com/justasleepycat/RobloxScripts/refs/heads/main/Hooking.lua"))()
local Checks = loadstring(game:HttpGet("https://raw.githubusercontent.com/justasleepycat/RobloxScripts/refs/heads/main/Checks.lua"))()

local Players = game:GetService("Players")
local Workspace =  game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")


-- Block error analytics 
HookingService:NameCallSpoof("FireServer", false, function(namecall, self, ...)
	if tostring(self) == "GameAnalyticsError" then
		rconsoleprint("No")
		return
	end
    return namecall(self, ...)
end)

-- Remote handling
if ishooked(HookingService.methodHooks.RemoteEvent) then
	restorefunction(HookingService.methodHooks.RemoteEvent)
end

local RemoteArgs = {
	DamageVehicle = {}
}

local old; old = hookfunction(HookingService.methodHooks.RemoteEvent, function(...)
	local Callstack = getcallstack()
	local args = {...}

	if #Callstack > 5 then
		print("---------------------------------------------------------------------------------------------------")
		pcall(function()
			if tostring(getfenv(3).script) then
				if typeof(args[3]) == "Instance" and typeof(args[4]) == "string" then
					print("DamageVehicle")
				end
			end
		end)
		print("Script: ", getcallingscript())
		print("Args:")
		print("{")
		for i,v in pairs(args) do
			print("	", i, v, typeof(v))
		end
		print("}")
		print("Function: ", getinfo(Callstack[5]).name)

		--for i,v in pairs(Callstack) do
		--	print(i,v, getinfo(v).name)
		--end
	end
	return old(...)
end)


-- Silent Aimbot
local env = require(game:GetService("ReplicatedStorage").Module.RayCast)
for i,v in pairs(env) do
	getgenv()[i] = getgenv()[i] ~= nil and getgenv()[i] or env[i]
	env[i] = function(...)
		local args = {...}
		local name = tostring(args[4])
		if name == Players.LocalPlayer.Name then
		else
			local success, err = pcall(function()

			end)
				if tostring(getfenv(2).script) == "BulletEmitter" or tostring(getfenv(3).script) == "Taser" then
					local closestPlr = Checks:GetClosestPlayerToMouse({
						MaxDistance = 400
					})
					if closestPlr then
						local direction = (closestPlr.Character.Head.CFrame.Position - Workspace.CurrentCamera.CFrame.Position)
						local dist = direction.Magnitude
						args[2] = direction.Unit
					end
				end
		end
		return getgenv()[i](unpack(args))
	end
end