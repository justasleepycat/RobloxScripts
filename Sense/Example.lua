local Sense = loadstring(game:HttpGet("https://raw.githubusercontent.com/justasleepycat/RobloxScripts/refs/heads/main/Sense/SenseESP_ReWrittenSource.lua"))
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

local object = Sense.AddInstance(workspace.Part, {
    --enabled = false,
    text = "{name}", -- Placeholders: {name}, {distance}, {position}
    textColor = { Color3.new(1,1,1), 1 },
    textOutline = true,
    textOutlineColor = Color3.new(),
    textSize = 13,
    textFont = 2,
    limitDistance = false,
    maxDistance = 150
})

Sense.Load()

