-- local HookingService = loadstring(game:HttpGet("https://raw.githubusercontent.com/justasleepycat/RobloxScripts/refs/heads/main/Hooking.lua"))()


HookingService:NameCallSpoof("FireServer", false, function(namecall, self, ...)
    if string.find(tostring(self), "Primary") then
        for i = 1,30 do
            namecall(self, ...)
            task.wait(.01)
        end
    end
    return namecall(self, ...)
end)