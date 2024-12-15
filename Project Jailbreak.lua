local HookingService = loadstring(game:HttpGet("https://raw.githubusercontent.com/justasleepycat/RobloxScripts/refs/heads/main/Hooking.lua"))()
local Checks = loadstring(game:HttpGet("https://raw.githubusercontent.com/justasleepycat/RobloxScripts/refs/heads/main/Checks.lua"))()

local Players = game:GetService("Players")
local Workspace =  game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")


getgenv().RemoteArgs = getgenv().RemoteArgs ~= nil and getgenv().RemoteArgs or {
    Debug = true,
    DefaultRemote = nil,
	DamageVehicle = DamageVehicle,
}

do  -- Block error analytics 
    HookingService:NameCallSpoof("FireServer", false, function(namecall, self, ...)
        if tostring(self) == "GameAnalyticsError" then
            rconsoleprint("No")
            return
        end
        return namecall(self, ...)
    end)
end

do  -- Remote handling
    if ishooked(HookingService.methodHooks.RemoteEvent) then
        restorefunction(HookingService.methodHooks.RemoteEvent)
    end
end

local function DamageVehicle(vehicle : Instance)
    if getgenv().RemoteArgs.DefaultRemote == nil then return end
    task.spawn(function()
        local args = table.clone(getgenv().RemoteArgs.DamageVehicle)
        args[3] = vehicle
        args[4] = "Sniper"
        for i = 1,30 do
            getgenv().RemoteArgs.DefaultRemote(unpack(args))
            task.wait(.06)
        end
    end)
end

if #getgenv().RemoteArgs.DamageVehicle == 0 then
    local old; old = hookfunction(HookingService.methodHooks.RemoteEvent, function(...)
        local Callstack = getcallstack()
        local args = {...}

        if #Callstack > 5 then
            if getgenv().RemoteArgs.Debug and getinfo(Callstack[5]).name ~= "UpdateMousePosition" then
                print("---------------------------------------------------------------------------------------------------")
                print("Script: ", getcallingscript())
                print("Args:")
                print("{")
                for i,v in pairs(args) do
                    print("	", i, v, typeof(v))
                end
                print("}")
                print("Function: ", getinfo(Callstack[5]).name)
            end
            pcall(function()
                getgenv().RemoteArgs.DefaultRemote = old
                if tostring(getfenv(3).script) then
                    if typeof(args[3]) == "Instance" and typeof(args[4]) == "string" then
                        print("DamageVehicle")
                        getgenv().RemoteArgs.DamageVehicle = args
                    end
                end
            end)

            --for i,v in pairs(Callstack) do
            --	print(i,v, getinfo(v).name)
            --end
        end
        return old(...)
    end)
end

while #getgenv().RemoteArgs.DamageVehicle == 0 and task.wait() do end
task.spawn(function()
    while task.wait(4) do
        for i,v in pairs(Workspace.Vehicles:GetChildren()) do
            pcall(function()
                local dist = (v:GetPivot().Position - Workspace.CurrentCamera.CFrame.Position).Magnitude
                if dist < 300 then
                
                end
                DamageVehicle(v)
            end)
        end
    end
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