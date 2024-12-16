local HookingService = loadstring(game:HttpGet("https://raw.githubusercontent.com/justasleepycat/RobloxScripts/refs/heads/main/Hooking.lua"))()
HookingService:NameCallSpoof("FireServer", false, function(namecall, self, ...)
    if string.find(tostring(self), "Damage") then
        warn(self, ...)
        for i = 1,5 do
            namecall(self, ...)
            task.wait(.2)
		end
    end
    return namecall(self, ...)
end)