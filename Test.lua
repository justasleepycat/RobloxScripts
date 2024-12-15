local HookingService = loadstring(game:HttpGet("https://raw.githubusercontent.com/justasleepycat/RobloxScripts/refs/heads/main/Hooking.lua"))()


HookingService:NameCallSpoof("FireServer", false, function(namecall, self, ...)
	print(namecall, self)
    return namecall(self, ...)
end)