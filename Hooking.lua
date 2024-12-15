-- https://raw.githubusercontent.com/justasleepycat/RobloxScripts/refs/heads/main/Hooking.lua
-- local HookingService = loadstring(game:HttpGet("https://raw.githubusercontent.com/justasleepycat/RobloxScripts/refs/heads/main/Hooking.lua"))()
local HookingService = {}
-- Test
HookingService.methodHooks = {
    RemoteEvent = Instance.new("RemoteEvent").FireServer,
    RemoteFunction = Instance.new("RemoteFunction").InvokeServer,
    BindableEvent = Instance.new("BindableEvent").Fire,
    BindableFunction = Instance.new("BindableFunction").Invoke
}

function HookingService:Hook(a, b)
    hookfunction(a, b)
end

function HookingService:DisableConnection(Signal)
    for _, v in next, getconnections(Signal) do
        v:Disable()
    end
end

function HookingService:IndexSpoof(Object, Property, Value)
    local index
    index = hookmetamethod(Object, "__index", function(self, key, ...)
        if key == Property then
            return Value
        end

        return index(self, key, ...)
    end)
end

function HookingService:NameCallSpoof(CallMethod, IgnoreSelfCaller, Function)
    local namecall
    namecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local caller = checkcaller()
        local method = getnamecallmethod()
        if method ~= CallMethod then
            return namecall(self, ...)
        end

        if IgnoreSelfCaller and caller then
            return namecall(self, ...)
        end

        if Function then
            return Function(namecall, self, ...)
        end
    
        return namecall(self, ...)
	end))
end

function HookingService:SpoofAttribute(Object, Attribute, Value)
    local namecall
    namecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local caller = checkcaller()
        local method = getnamecallmethod()
        local args = {...}
        local result = namecall(self, ...)
        local success, err = pcall(function()
            if method == "GetAttribute" then
				if self == nil then return end
                if typeof(result) ~= typeof(Value) then return end
                if typeof(self) ~= "Instance" then return end
                if self == Object or Object == nil then
                    if tostring(args[1] == Attribute) then
                        result = Value
                    end
                end
            end
		end)
    
        return result
	end))
end

function HookingService:HookRemote(Remote, Function)
    local namecall
    namecall = hookmetamethod(game, "__namecall", function(self, ...)
        local args = {...}

        if not checkcaller() and self == Remote then
            if getnamecallmethod() == "FireServer" or getnamecallmethod() == "InvokeServer" then
                return Function(namecall, self, ...)
            end
        end

        return namecall(self, ...)
    end)
end

function HookingService:ProtectGui(Object)
    Object.Parent = game.CoreGui

    local namecall
    namecall = hookmetamethod(game, "__namecall", function(self, key, ...)
        if not checkcaller() and self == game.CoreGui and getnamecallmethod() == "FindFirstChild" and key == Object.Name then
            return
        end

        return namecall(self, key, ...)
    end)

    local index
    index = hookmetamethod(game, "__index", function(self, key, ...)
        if not checkcaller() and self == game.CoreGui and key == Object.Name then
            return
        end

        return index(self, key, ...)
    end)
end


-- Example usage
if false then
    HookingService:HookRemote(workspace.Services.PickupTool, function(namecall, self, ...)
        local args = {...}
        for i,v in pairs(args) do
            print(i,v)
        end
        return namecall(self, ...)
    end)

    HookingService:NameCallSpoof("FireServer", false, function(namecall, self, ...)
        if string.find(tostring(self), "Primary") then
            for i = 1,30 do
                namecall(self, ...)
                task.wait(.01)
            end
        end
        return namecall(self, ...)
    end)


    HookingService:DisableConnection(game.Players.LocalPlayer.Character.Humanoid.Died)

    HookingService:IndexSpoof(game.Workspace.CurrentCamera, "CFrame", CFrame.new(0,0,0))

    HookingService:SpoofAttribute(nil, "CircleActionDuration", 0.01)
end

return HookingService


