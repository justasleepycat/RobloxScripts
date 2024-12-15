local GCScanner = loadstring(game:HttpGet("https://raw.githubusercontent.com/justasleepycat/Roblox/refs/heads/dev/GCScanner.lua"))()
local HookingService = loadstring(game:HttpGet("https://raw.githubusercontent.com/justasleepycat/Roblox/refs/heads/dev/Hooks.lua"))()
local Sense = loadstring(game:HttpGet('https://raw.githubusercontent.com/justasleepycat/Roblox/refs/heads/dev/Sense/SenseESP_ReWrittenSource.lua'))()
local VirtualKeyCodes = loadstring(game:HttpGet("https://raw.githubusercontent.com/justasleepycat/Roblox/refs/heads/dev/VirtualKeyCodes.lua"))()

-- Weapon Mods
GCScanner:ModifyValuesByIndex({
    {
        Index = "SwingDistance",
        Type = "number", -- use Any to not filter
        ReturnParent = false,
        NewValues = {index = nil, value = 300}
    },
    {
        Index = "MaxBuildingBlockRange",
        Type = "number", -- use Any to not filter
        ReturnParent = false,
        NewValues = {index = nil, value = 3000}
    },
})

for i,v in pairs(getgc(true)) do
	if typeof(v) == "table" then
		if rawget(v, "SwingDelay") then
			print(v.SwingDelay)
		end
	end
end

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

local CacheCooldown = 5
game:GetService("RunService").RenderStepped:Connect(function(deltaTime : double)
    CacheCooldown -= deltaTime
    if CacheCooldown <= 0 then
		CacheCooldown = 5
        for i,v in pairs(game:GetService("Workspace").LootCrates:GetChildren()) do
            local success, err = pcall(function()        
                return v.PrimaryPart.Color
            end)
            if not success or err == nil then
                continue
            end
            local object = Sense.AddInstance(v, {
                enabled = true,
                text = ("[%s]\n[{distance}]"):format(v.Name), -- Placeholders: {name}, {distance}, {position}
                textColor = { err or Color3.new(1,1,1), 1 },
                textSize = 13,
                textFont = 2,
                limitDistance = true,
                maxDistance = 400
            })
        end

        for i,v in pairs(game:GetService("Workspace").KeyDrops:GetChildren()) do
            local success, err = pcall(function()
                return v.PrimaryPart.Color
            end)
            local object = Sense.AddInstance(v, {
                --enabled = false,
                text = "[{name}]\n[{distance}]", -- Placeholders: {name}, {distance}, {position}
                textColor = { success and err or Color3.new(1,1,1), 1 },
                textSize = 13,
                textFont = 2,
                limitDistance = false,
                maxDistance = 400
            })

            object.options.enabled = true
        end
	end
end)


Sense.Load()
while task.wait() and not table.find(VirtualKeyCodes:GetCurrentPressedKeys(), "VK_HOME") do

end
Sense.Unload()