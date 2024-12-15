local HookingService = loadstring(game:HttpGet("https://raw.githubusercontent.com/justasleepycat/RobloxScripts/refs/heads/main/Hooking.lua"))()
local GCScanner = loadstring(game:HttpGet("https://raw.githubusercontent.com/justasleepycat/RobloxScripts/refs/heads/main/GCScanner.lua"))()

local function HealSelf()
    if game.PlaceId == 464575687 then
        local ohString1 = "dialogue"
        local ohTable2 = {
            ["NpcName"] = "Dr. Deniski",
            ["NpcModel"] = workspace.Entity["Dr. Deniski"]
        }
        
        game:GetService("ReplicatedStorage").Library.RemotesManager.DialogueHandler:InvokeServer(ohString1, ohTable2)

        local ohString1 = "dialogue"
        local ohTable2 = {
            ["NpcName"] = "Dr. Deniski",
            ["ChoiceTag"] = "heal_request",
            ["NpcModel"] = workspace.Entity["Dr. Deniski"]
        }

        game:GetService("ReplicatedStorage").Library.RemotesManager.DialogueHandler:InvokeServer(ohString1, ohTable2)
    elseif game.PlaceId == 480661072 then
        local ohString1 = "dialogue"
        local ohTable2 = {
            ["NpcName"] = "Carlson",
            ["ChoiceTag"] = "heal_request",
            ["NpcModel"] = workspace.Entity.Carlson
        }

        game:GetService("ReplicatedStorage").Library.RemotesManager.DialogueHandler:InvokeServer(ohString1, ohTable2)
    elseif game.PlaceId == 4413486022 then
        local ohString1 = "dialogue"
        local ohTable2 = {
            ["NpcName"] = "Danny",
            ["ChoiceTag"] = "heal_request",
            ["NpcModel"] = workspace.Entity.Danny
        }

        game:GetService("ReplicatedStorage").Library.RemotesManager.DialogueHandler:InvokeServer(ohString1, ohTable2)
    elseif game.PlaceId == 5001877367 then
        local ohString1 = "dialogue"
        local ohTable2 = {
            ["NpcName"] = "Caitlin",
            ["ChoiceTag"] = "heal_request",
            ["NpcModel"] = workspace.Entity.Caitlin
        }

        game:GetService("ReplicatedStorage").Library.RemotesManager.DialogueHandler:InvokeServer(ohString1, ohTable2)
    end
end

local function MerryChristmas()
	
end

-- Auto merry christmas
task.spawn(function()
	while task.wait(.1) do
		pcall(function()
			MerryChristmas()
		end)
	end
end)

-- Always Headshot
task.spawn(function()
    HookingService:NameCallSpoof("FireServer", false, function(namecall, self, ...)
        if string.find(tostring(self), "Primary") then
			local args = {...}
            pcall(function()
				for i,victim in pairs(args[3]["Victims"]) do
                    pcall(function()
                        local Entity = victim.Humanoid:FindFirstAncestorWhichIsA("Model")
                        local Head = Entity:FindFirstChild("Head", true)
                        args[3]["Victims"][i]["Object"] = Head
                        args[3]["ShotPoint"] = Head:GetPivot().Position
					end)
				end
                args[3]["TracerColor"] = Color3.new(0, 1, 0.93)
			end)
        end
        return self.FireServer(self, ...)
    end)
end)

-- Auto Heal
task.spawn(function()
	while task.wait(.1) do
        pcall(function()
			HealSelf()
		end)
    end
end)

task.spawn(function()
	while task.wait(.1) do
		pcall(function()
			game:GetService("ReplicatedStorage").Library.RemotesManager.ToolHandlerPrimaryFire:FireServer("#13")
		end)
	end
end)

GCScanner:ModifyValuesByIndex({
    {
        Index = "RPM",
        Type = "number", -- use Any to not filter
        ReturnParent = false,
        NewValues = {index = nil, value = 2000}
    },
    {
        Index = "XRecoil",
        Type = "number", -- use Any to not filter
        ReturnParent = false,
        NewValues = {index = nil, value = 0}
    },
    {
        Index = "YRecoil",
        Type = "number", -- use Any to not filter
        ReturnParent = false,
        NewValues = {index = nil, value = 0}
    },
    {
        Index = "BasePiercing",
        Type = "number", -- use Any to not filter
        ReturnParent = false,
        NewValues = {index = nil, value = 10}
    },
    {
        Index = "Penetration",
        Type = "number", -- use Any to not filter
        ReturnParent = false,
        NewValues = {index = nil, value = 100}
    },
    {
        Index = "BulletRange",
        Type = "number", -- use Any to not filter
        ReturnParent = false,
        NewValues = {index = nil, value = 1000}
    },
    {
        Index = "RecoilStregth",
        Type = "number", -- use Any to not filter
        ReturnParent = false,
        NewValues = {index = nil, value = 0}
    },
    {
        Index = "EquipLoadTime",
        Type = "number", -- use Any to not filter
        ReturnParent = false,
        NewValues = {index = nil, value = 0}
    },
    {
        Index = "Inaccuracy",
        Type = "number", -- use Any to not filter
        ReturnParent = false,
        NewValues = {index = nil, value = 0}
    },
    {
        Index = "TriggerMode",
        Type = "number", -- use Any to not filter
        ReturnParent = false,
        NewValues = {index = nil, value = 3}
    },
})

