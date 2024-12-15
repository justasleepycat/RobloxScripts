local HookingService = loadstring(game:HttpGet("https://raw.githubusercontent.com/justasleepycat/RobloxScripts/refs/heads/main/Hooking.lua"))()


HookingService:NameCallSpoof("GetAttribute", false, function(namecall, self, ...)
	local args = {...}
	print(args[1])
    return namecall(self, ...)
end)


for i,v in pairs(game:GetService("Workspace"):GetDescendants()) do
	if v:GetAttribute("CircleActionDuration") then
		print(v:GetFullName(), v:GetAttribute("CircleActionDuration"))
	end
end