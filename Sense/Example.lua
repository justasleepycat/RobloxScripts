local Sense = loadstring(game:HttpGet("https://raw.githubusercontent.com/justasleepycat/Roblox/refs/heads/dev/Sense/SenseESP_ReWrittenSource.lua"))
print(Sense)

-- Player ESP
-- Shared Settings
Sense.sharedSettings.limitDistance = true
Sense.sharedSettings.maxDistance = 1000
Sense.sharedSettings.useTeamColor = false

-- Enemy settings
Sense.teamSettings.enemy.enabled = true
Sense.teamSettings.enemy.box3d = true
Sense.teamSettings.enemy.box3dColor[1] = Color3.new(1, 0, 0)
Sense.teamSettings.enemy.distance = true
Sense.teamSettings.enemy.distanceColor[1] = Color3.new(1, 0, 0)
Sense.teamSettings.enemy.chams = true
Sense.teamSettings.enemy.chamsVisibleOnly  = true
Sense.teamSettings.enemy.chamsFillColor = { Color3.new(1, 0, 0), 0.5 }
Sense.teamSettings.enemy.healthBar = true

-- Friendly settings
Sense.teamSettings.friendly.enabled = true
Sense.teamSettings.friendly.box3d = true
Sense.teamSettings.friendly.box3dColor[1] = Color3.new(0, 1, 0)
Sense.teamSettings.friendly.distance = true
Sense.teamSettings.friendly.distanceColor[1] = Color3.new(0, 1, 0)
Sense.teamSettings.friendly.chams = true
Sense.teamSettings.friendly.chamsVisibleOnly  = false
Sense.teamSettings.friendly.chamsFillColor = { Color3.new(0, 1, 0), 0.5 }
Sense.teamSettings.friendly.healthBar = true

Sense.Load()