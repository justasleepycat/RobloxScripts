local Checks = loadstring(game:HttpGet("https://raw.githubusercontent.com/justasleepycat/RobloxScripts/refs/heads/main/Checks.lua"))()
print(Checks:GetClosestPlayerToPosition({
    Origin = Workspace.CurrentCamera.CFrame.Position
}))
print(Checks:GetClosestPlayerToMouse()) 