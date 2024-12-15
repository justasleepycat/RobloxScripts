local HookingService = loadstring(game:HttpGet("https://raw.githubusercontent.com/justasleepycat/RobloxScripts/refs/heads/main/Hooking.lua"))()

HookingService:SpoofAttribute(nil, "CircleActionDuration", 0.01)


for i,v in pairs(game:GetService("Workspace"):GetDescendants()) do
	if v:GetAttribute("CircleActionDuration") then
		print(v:GetFullName(), v:GetAttribute("CircleActionDuration"))
	end
end