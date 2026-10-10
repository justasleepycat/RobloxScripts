local Workspace  = game:GetService("Workspace")
local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Every BasePart inside instance, plus instance itself when it is one.
local function CollectBaseParts(instance : Instance) : { BasePart }
    local parts = {}

    if instance:IsA("BasePart") then
        table.insert(parts, instance)
    end

    for _, descendant in ipairs(instance:GetDescendants()) do
        if descendant:IsA("BasePart") then
            table.insert(parts, descendant)
        end
    end

    return parts
end

--[[
    Builds a PostSimulation loop that spoofs the velocity of every BasePart under target,
    leaving the velocity itself to the caller. Reads nothing from script globals.

    Options, all optional:
        Strength : Vector3 -- scales each velocity before it is applied (default Vector3.one)
        OnSpoof  : (velocity : Vector3) -> () -- runs right after a spoof is applied

    Returns a handle:
        .SetVelocity(velocity) -- the velocity the connection re-applies every frame
        .Spoof(velocity)       -- applies velocity for one frame, then restores
        .Connection            -- the RBXScriptConnection, Disconnect() stops the loop
]]
local function CreateVelocitySpoofer(target : Instance, options : { [string] : any }?)
    local settings     = options or {}
    local strength     = settings.Strength or Vector3.one
    local onSpoof      = settings.OnSpoof

    local spoofing     = false
    local wishVelocity = Vector3.zero

    -- Applies velocity to every part for a single frame, then puts each part back as it was.
    local function Spoof(velocity : Vector3)
        local parts    = CollectBaseParts(target)
        local previous = table.create(#parts)

        for index, part in ipairs(parts) do
            previous[index] = part.AssemblyLinearVelocity
        end

        local spoofed = velocity * strength
        for _, part in ipairs(parts) do
            part.AssemblyLinearVelocity = spoofed
        end

        if onSpoof then
            onSpoof(spoofed)
        end

        -- RunService.PreRender is the equivalent function for RunService.RenderStepped
        RunService:BindToRenderStep("go34593485on", 0, function()
            for index, part in ipairs(parts) do
                part.AssemblyLinearVelocity = previous[index]
            end

            RunService:UnbindFromRenderStep("go34593485on")
        end)
    end

    return {
        Connection  = RunService.PostSimulation:Connect(function(deltaTime : double)
            if not spoofing then return end
            Spoof(wishVelocity)
        end),
        SetVelocity = function(velocity : Vector3)
            wishVelocity = velocity
            spoofing     = true
        end,
        Spoof       = Spoof,
    }
end

-- Example usage
local characterSpoofer = CreateVelocitySpoofer(Players.LocalPlayer.Character, {
    Strength = Vector3.new(1e9, 1e9, 1e9),
})

characterSpoofer.SetVelocity(Vector3.new(1e9, 1e9, 1e9)) -- re-applied every frame
task.wait(10)
characterSpoofer.Connection:Disconnect()