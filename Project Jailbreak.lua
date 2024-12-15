local HookingService = loadstring(game:HttpGet("https://raw.githubusercontent.com/justasleepycat/RobloxScripts/refs/heads/main/Hooking.lua"))()
local Checks = loadstring(game:HttpGet("https://raw.githubusercontent.com/justasleepycat/RobloxScripts/refs/heads/main/Checks.lua"))()

local Players = game:GetService("Players")
local Workspace =  game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")


getgenv().RemoteArgs = getgenv().RemoteArgs ~= nil and getgenv().RemoteArgs or {
    Debug = true,
    DefaultRemote = nil,
	DamageVehicle = {},
    TasePlayer = {},
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
        for i = 1,1 do
            getgenv().RemoteArgs.DefaultRemote(unpack(args))
            task.wait(.06)
        end
    end)
end

if #getgenv().RemoteArgs.DamageVehicle == 0 then

end
local old; old = hookfunction(HookingService.methodHooks.RemoteEvent, function(...)
    local Callstack = getcallstack()
    local args = {...}

    if #Callstack > 5 then
        local FuncName = getinfo(Callstack[5]).name
        if getgenv().RemoteArgs.Debug and FuncName ~= "UpdateMousePosition" then
            print("---------------------------------------------------------------------------------------------------")
            print("Script: ", getcallingscript())
            print("Args:")
            print("{")
            for i,v in pairs(args) do
                print("	", i, v, typeof(v))
            end
            print("}")
            print("Function: ", FuncName)
        end
        pcall(function()
            getgenv().RemoteArgs.DefaultRemote = old
            if FuncName == "Tase" then
				warn("Tase found")
				getgenv().RemoteArgs.TasePlayer = args
			end
            if tostring(getfenv(3).script) then
                if typeof(args[3]) == "Instance" and typeof(args[4]) == "string" then
                    warn("DamageVehicle found")
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

Players.LocalPlayer:GetMouse().Button1Down:Connect(function()
    local ClosestPlr = Checks:GetClosestPlayerToMouse({
        MaxDistance = 300,
    })
    if ClosestPlr then
        if getgenv().RemoteArgs.DefaultRemote == nil then return end
        task.spawn(function()
            local args = table.clone(getgenv().RemoteArgs.TasePlayer)
            args[3] = ClosestPlr.Character:FindFirstChildWhichIsA("Humanoid", true)
            args[4] = ClosestPlr.Character:FindFirstChild("HumanoidRootPart", true)
            args[5] = ClosestPlr.Character:FindFirstChild("HumanoidRootPart", true).CFrame.Position
            warn("Tazing "..ClosestPlr.Name)
            getgenv().RemoteArgs.DefaultRemote(unpack(args))
        end)
	end
end)

do  -- Vehicle Damage Aura
    task.spawn(function()
        while #getgenv().RemoteArgs.DamageVehicle == 0 and task.wait() do end
        while task.wait(.1) do
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
end



do  -- Silent Aimbot
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
end