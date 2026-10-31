--[[ RemoteDisablePoC.lua
     Client-side only. Hides the automatic report remotes and raises the client speed-report
     threshold so a collision/speed spike cannot reach the server through those paths.

     Usage:
        local PoC = loadstring(readfile("RemoteDisablePoC.lua"))()
        -- test the collision filters here
        PoC.Restore()          -- or simply rejoin; the server still owns the real remotes

     Targets:
        ReplicatedStorage.Remote.BanMe         -- VirtualUser / Nexus honeypots
        ReplicatedStorage.Remote.RPSpeedCheck  -- old speed-report name
        ReplicatedStorage.Remote.RPSpeed       -- current live speed-report name
        ReplicatedStorage.Remote.Mismatch      -- nametag-spoofing report
        ReplicatedStorage:SetAttribute("FRPSpeedLimit", 1e9)

     Not covered: staff Cmdr :ban/:kick (requires staff privileges) and any server-side
     position/speed validation that is not present in the client dump.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REMOTE_TARGETS = { "BanMe", "RPSpeedCheck", "RPSpeed", "Mismatch" }
local SPEED_LIMIT    = 1e9

local PoC = {
    Hidden            = {},
    Disabled          = false,
    LoopToken         = 0,
    OriginalSpeedLimit = nil,
}

local function LogInfo(message)
    print(string.format("[i] [RemoteDisablePoC] %s", message))
end

local function LogError(message)
    print(string.format("[!] [RemoteDisablePoC] %s", message))
end

local function RemoteFolder()
    return ReplicatedStorage:FindFirstChild("Remote")
end

-- Rename instead of destroying, so Restore() can put the same instances back. A rename is local
-- to this client: the server still owns the real remote for every other player.
local function HideRemote(folder, name)
    local remote = folder:FindFirstChild(name)
    if remote == nil then
        return false
    end
    local hiddenName = name .. "__POC_DISABLED"
    if remote.Name ~= hiddenName then
        remote.Name = hiddenName
        table.insert(PoC.Hidden, {
            Remote       = remote,
            OriginalName = name,
        })
        LogInfo(string.format("Hid remote '%s'", name))
    end
    return true
end

local function ApplyPoC()
    local folder = RemoteFolder()
    if folder == nil then
        LogError("ReplicatedStorage.Remote is missing")
        return
    end
    for _, name in ipairs(REMOTE_TARGETS) do
        HideRemote(folder, name)
    end
    local current = ReplicatedStorage:GetAttribute("FRPSpeedLimit")
    if PoC.OriginalSpeedLimit == nil then
        PoC.OriginalSpeedLimit = current
    end
    if current == nil or current < SPEED_LIMIT then
        ReplicatedStorage:SetAttribute("FRPSpeedLimit", SPEED_LIMIT)
        LogInfo("Raised FRPSpeedLimit")
    end
end

function PoC.Restore()
    PoC.Disabled = false
    PoC.LoopToken = PoC.LoopToken + 1
    local folder = RemoteFolder()
    for _, record in ipairs(PoC.Hidden) do
        if record.Remote.Parent ~= nil then
            if folder ~= nil and folder:FindFirstChild(record.OriginalName) ~= nil then
                -- A fresh server copy is already back; drop the hidden old one.
                record.Remote:Destroy()
            else
                record.Remote.Name = record.OriginalName
            end
        end
    end
    PoC.Hidden = {}
    if PoC.OriginalSpeedLimit ~= nil then
        ReplicatedStorage:SetAttribute("FRPSpeedLimit", PoC.OriginalSpeedLimit)
    else
        ReplicatedStorage:SetAttribute("FRPSpeedLimit", nil)
    end
    LogInfo("Restored the report remotes and speed limit")
end

PoC.Disabled = true
ApplyPoC()
local token = PoC.LoopToken + 1
PoC.LoopToken = token
task.spawn(function()
    while PoC.Disabled and PoC.LoopToken == token do
        task.wait(1)
        if PoC.Disabled and PoC.LoopToken == token then
            ApplyPoC()
        end
    end
end)

LogInfo("PoC active - rejoin or call PoC.Restore() to restore")
return PoC
