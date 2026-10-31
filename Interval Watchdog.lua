local RunService = game:GetService("RunService")

-- Diagnostics: every line is "[i] [Function] ..." or "[!] [Function] ...", where the
-- scope is the function the line is printed from. Failures that a hot loop can hit
-- repeatedly go through ReportFailure, which prints once until the failure clears.
local LogFormat        = "[%s] [%s] %s"
local ReportedFailures = {}

local function LogInfo(scope, message)
    print(string.format(LogFormat, "i", scope, message))
end

local function LogError(scope, message)
    print(string.format(LogFormat, "!", scope, message))
end

local function ReportFailure(failureKey, scope, message)
    if ReportedFailures[failureKey] == message then
        return
    end

    ReportedFailures[failureKey] = message
    LogError(scope, message)
end

local function ClearFailure(failureKey)
    ReportedFailures[failureKey] = nil
end

local STATE_VERSION   = 2
local BIND_NAME       = "intervalWatchdog"
local FRAME_BUDGET    = 0.004 -- seconds one pass may spend before deferring the rest
local RENDER_PRIORITY = Enum.RenderPriority.Last.Value -- after Input / Camera / Character

local Clock        = os.clock -- monotonic, unlike the deprecated tick()
local Format       = string.format
local Huge         = math.huge
local ProfileBegin = type(debug) == "table" and debug.profilebegin or function() end
local ProfileEnd   = type(debug) == "table" and debug.profileend   or function() end

-- The interval map keeps the v1 key and the v1 field names (Delay / NextTick / Callback),
-- so anything that already reads getgenv().activeIntervals keeps working across a reload.
local Environment = type(getgenv) == "function" and getgenv() or _G

if type(Environment) ~= "table" then
    Environment = _G
end

local Intervals = Environment.activeIntervals

if type(Intervals) ~= "table" or Environment.intervalWatchdogVersion ~= STATE_VERSION then
    if Intervals ~= nil then
        LogError("Startup", Format(
            "Discarding a store written by an incompatible watchdog version (%s)",
            tostring(Environment.intervalWatchdogVersion)
        ))
    end

    Intervals                           = {}
    Environment.activeIntervals         = Intervals
    Environment.intervalWatchdogVersion = STATE_VERSION
end

local Order    = {}
local Sequence = 0

local function IsValidDelay(intervalDelay)
    -- NaN fails every comparison, so it has to be rejected explicitly as well.
    return type(intervalDelay) == "number"
        and intervalDelay == intervalDelay
        and intervalDelay > 0
        and intervalDelay < Huge
end

-- Entries written by an older copy of this script get the fields they are missing, so a
-- hot reload keeps ticking them instead of dropping every interval on the floor.
for intervalName, record in pairs(Intervals) do
    if type(record) ~= "table"
        or type(record.Callback) ~= "function"
        or not IsValidDelay(record.Delay) then
        LogError("Startup", Format("Dropping malformed interval entry '%s'", tostring(intervalName)))

        Intervals[intervalName] = nil
    else
        record.Name       = intervalName
        record.Enabled    = record.Enabled ~= false
        record.Once       = record.Once == true
        record.Sequence   = record.Sequence or 0
        record.FailureKey = record.FailureKey or (BIND_NAME .. "." .. intervalName)
        record.Runs       = record.Runs or 0
        record.Errors     = record.Errors or 0
        record.LastRun    = record.LastRun or ((record.NextTick or 0) - record.Delay)
        record.NextTick   = record.NextTick or (Clock() + record.Delay)

        Sequence = math.max(Sequence, record.Sequence)
    end
end

local function RebuildOrder()
    table.clear(Order)

    for intervalName in pairs(Intervals) do
        Order[#Order + 1] = intervalName
    end

    table.sort(Order, function(leftName, rightName)
        return Intervals[leftName].Sequence < Intervals[rightName].Sequence
    end)
end

RebuildOrder()

local function RemoveFromOrder(intervalName)
    for index = #Order, 1, -1 do
        if Order[index] == intervalName then
            table.remove(Order, index)

            return
        end
    end
end

local function RemoveInterval(record)
    if Intervals[record.Name] == record then
        Intervals[record.Name] = nil

        RemoveFromOrder(record.Name)
    end

    ClearFailure(record.FailureKey)
end

local function ResolveRecord(scope, intervalName)
    local record = Intervals[intervalName]

    if not record then
        LogError(scope, Format("Interval '%s' does not exist", tostring(intervalName)))
    end

    return record
end

local function RejectDelay(scope, intervalName, intervalDelay)
    LogError(scope, Format(
        "Interval '%s' has an invalid delay (%s)",
        tostring(intervalName),
        tostring(intervalDelay)
    ))

    return false
end

local function UnregisterInterval(intervalName)
    local record = ResolveRecord("UnregisterInterval", intervalName)

    if not record then
        return false
    end

    RemoveInterval(record)
    LogInfo("UnregisterInterval", Format("Removed interval '%s'", intervalName))

    return true
end

-- options: Enabled, Immediate, Once, Owner, Replace, DisableAfterErrors
local function RegisterInterval(intervalName, intervalDelay, callback, options)
    if type(intervalName) ~= "string" or intervalName == "" then
        LogError("RegisterInterval", "Interval name must be a non-empty string")

        return false
    end

    if not IsValidDelay(intervalDelay) then
        return RejectDelay("RegisterInterval", intervalName, intervalDelay)
    end

    if type(callback) ~= "function" then
        LogError("RegisterInterval", Format("Interval '%s' has no callback function", intervalName))

        return false
    end

    options = type(options) == "table" and options or {}

    local existing = Intervals[intervalName]

    -- Re-running a script re-registers its intervals. Replacing by default keeps the store
    -- pointed at the new closure instead of silently leaving the stale one ticking.
    if existing and options.Replace == false then
        LogError("RegisterInterval", Format("Interval '%s' already exists", intervalName))

        return false
    end

    local now    = Clock()
    local record = existing
    local isNew  = record == nil

    if isNew then
        Sequence += 1

        record = {
            Name       = intervalName,
            FailureKey = BIND_NAME .. "." .. intervalName,
            Sequence   = Sequence,
            Runs       = 0,
        }

        Intervals[intervalName] = record
        Order[#Order + 1]       = intervalName
    end

    record.Delay              = intervalDelay
    record.Callback           = callback
    record.Enabled            = options.Enabled ~= false
    record.Once               = options.Once == true
    record.Owner              = options.Owner
    record.DisableAfterErrors = options.DisableAfterErrors
    record.Errors             = 0
    record.LastError          = nil
    record.LastRun            = now

    -- { Immediate = true } fires on the next frame instead of waiting one whole delay.
    record.NextTick           = options.Immediate and now or (now + intervalDelay)

    ClearFailure(record.FailureKey)

    LogInfo("RegisterInterval", Format(
        "%s interval '%s' (every %.3fs)",
        isNew and "Created" or "Replaced",
        intervalName,
        intervalDelay
    ))

    return true
end

local function After(intervalName, intervalDelay, callback, options)
    local onceOptions = table.clone(type(options) == "table" and options or {})

    onceOptions.Once = true

    return RegisterInterval(intervalName, intervalDelay, callback, onceOptions)
end

local function SetDelay(intervalName, intervalDelay)
    local record = ResolveRecord("SetDelay", intervalName)

    if not record then
        return false
    end

    if not IsValidDelay(intervalDelay) then
        return RejectDelay("SetDelay", intervalName, intervalDelay)
    end

    record.Delay    = intervalDelay
    record.NextTick = Clock() + intervalDelay

    LogInfo("SetDelay", Format("Interval '%s' now runs every %.3fs", intervalName, intervalDelay))

    return true
end

local function SetCallback(intervalName, callback)
    local record = ResolveRecord("SetCallback", intervalName)

    if not record then
        return false
    end

    if type(callback) ~= "function" then
        LogError("SetCallback", Format("Interval '%s' was given no callback function", intervalName))

        return false
    end

    record.Callback  = callback
    record.Errors    = 0
    record.LastError = nil

    ClearFailure(record.FailureKey)

    LogInfo("SetCallback", Format("Interval '%s' now runs a new callback", intervalName))

    return true
end

local function SetEnabled(intervalName, enabled)
    local record = ResolveRecord("SetEnabled", intervalName)

    if not record then
        return false
    end

    record.Enabled = enabled ~= false

    -- Re-arm from now, so a long pause never turns into an immediate catch-up fire.
    if record.Enabled then
        record.NextTick = Clock() + record.Delay
    end

    LogInfo("SetEnabled", Format(
        "Interval '%s' is now %s",
        intervalName,
        record.Enabled and "running" or "paused"
    ))

    return true
end

local function SetAllEnabled(enabled)
    local changed = 0

    for index = 1, #Order do
        local record = Intervals[Order[index]]

        if record then
            record.Enabled  = enabled
            record.NextTick = Clock() + record.Delay
            changed += 1
        end
    end

    LogInfo("SetAllEnabled", Format("%s %d interval(s)", enabled and "Resumed" or "Paused", changed))

    return changed
end

local function UnregisterOwner(ownerName)
    if type(ownerName) ~= "string" or ownerName == "" then
        LogError("UnregisterOwner", "Owner name must be a non-empty string")

        return 0
    end

    local ownedNames = {}

    for index = 1, #Order do
        local record = Intervals[Order[index]]

        if record and record.Owner == ownerName then
            ownedNames[#ownedNames + 1] = record.Name
        end
    end

    local removed = 0

    for index = 1, #ownedNames do
        local record = Intervals[ownedNames[index]]

        if record then
            RemoveInterval(record)
            removed += 1
        end
    end

    LogInfo("UnregisterOwner", Format("Removed %d interval(s) owned by '%s'", removed, ownerName))

    return removed
end

local function ClearAll()
    local removed = 0

    for intervalName, record in pairs(Intervals) do
        Intervals[intervalName] = nil
        ClearFailure(record.FailureKey)
        removed += 1
    end

    table.clear(Order)

    LogInfo("ClearAll", Format("Removed %d interval(s)", removed))

    return removed
end

local function Trigger(intervalName)
    local record = ResolveRecord("Trigger", intervalName)

    if not record then
        return false
    end

    record.NextTick = 0

    return true
end

local function GetInfo(intervalName)
    local record = Intervals[intervalName]

    if not record then
        return nil
    end

    return {
        Name      = record.Name,
        Delay     = record.Delay,
        Enabled   = record.Enabled,
        Once      = record.Once,
        Owner     = record.Owner,
        Runs      = record.Runs,
        Errors    = record.Errors,
        LastError = record.LastError,
        LastMs    = record.LastMs,
        NextIn    = record.NextTick - Clock(),
    }
end

local function ListIntervals()
    local listed = {}

    for index = 1, #Order do
        local info = GetInfo(Order[index])

        if info then
            listed[#listed + 1] = info
        end
    end

    return listed
end

local function Dump()
    local listed = ListIntervals()

    LogInfo("Dump", Format("%d interval(s) registered", #listed))

    for index = 1, #listed do
        local info = listed[index]

        LogInfo("Dump", Format(
            "%-24s every %6.3fs  next %7.3fs  runs %-6d errors %-4d %s",
            info.Name,
            info.Delay,
            info.NextIn,
            info.Runs,
            info.Errors,
            info.Enabled and "" or "(paused)"
        ))
    end

    return listed
end

local function InvokeRecord(record, elapsedSeconds)
    local started = Clock()

    record.Runs    += 1
    record.LastRun  = started

    local succeeded, failure = pcall(record.Callback, elapsedSeconds, record.Name)

    record.LastMs = (Clock() - started) * 1000

    if succeeded then
        record.Errors    = 0
        record.LastError = nil

        ClearFailure(record.FailureKey)

        return
    end

    record.Errors   += 1
    record.LastError = tostring(failure)

    ReportFailure(record.FailureKey, "RunDueIntervals", Format(
        "Interval '%s' callback failed (%s)",
        record.Name,
        record.LastError
    ))

    if record.DisableAfterErrors and record.Errors >= record.DisableAfterErrors then
        record.Enabled = false

        LogError("RunDueIntervals", Format(
            "Interval '%s' failed %d times in a row and is now paused",
            record.Name,
            record.Errors
        ))
    end
end

local Running    = false
local DueRecords = {}
local DueTicks   = {}

local function RunDueIntervals()
    if Running then
        return
    end

    Running = true

    local now      = Clock()
    local dueCount = 0

    -- Snapshot first: a callback may register or unregister intervals while we run, and
    -- inserting a key into a table that pairs() is walking is undefined behaviour.
    for index = 1, #Order do
        local record = Intervals[Order[index]]

        if record and record.Enabled and now >= record.NextTick then
            dueCount += 1
            DueRecords[dueCount] = record
            DueTicks[dueCount]   = record.NextTick
        end
    end

    if dueCount == 0 then
        Running = false

        return
    end

    ProfileBegin("IntervalWatchdog")

    local deadline = now + FRAME_BUDGET

    for index = 1, dueCount do
        local record        = DueRecords[index]
        local scheduledTick = DueTicks[index]

        DueRecords[index]   = nil
        DueTicks[index]     = nil

        -- Re-check identity and schedule: an earlier callback in this pass may have removed,
        -- paused or re-armed the record, in which case it is no longer due this frame.
        if Intervals[record.Name] == record
            and record.Enabled
            and record.NextTick == scheduledTick then
            local elapsed = now - record.LastRun

            if record.Once then
                RemoveInterval(record)
            else
                record.NextTick += record.Delay

                -- The frame stalled (loading screen, minimised window) or the callback
                -- overran: skip the missed ticks instead of firing them back to back.
                if record.NextTick <= now then
                    record.NextTick = now + record.Delay
                end
            end

            InvokeRecord(record, elapsed)

            -- Out of budget: whatever is left stays due and runs next frame, so one slow
            -- interval cannot eat the whole frame. Not logged, this is a hot path.
            if Clock() >= deadline and index < dueCount then
                for deferred = index + 1, dueCount do
                    DueRecords[deferred] = nil
                    DueTicks[deferred]   = nil
                end

                break
            end
        end
    end

    ProfileEnd()
    Running = false
end

-- Render only ticks while the client renders (a minimised window renders nothing). Work
-- that polls state rather than touches the camera wants Heartbeat or PreSimulation instead.
local Phases = {
    Render = {
        Bind = function(callback)
            -- A reload binds over the previous copy, so drop it first and make sure only
            -- one closure is ever ticking.
            pcall(RunService.UnbindFromRenderStep, RunService, BIND_NAME)
            RunService:BindToRenderStep(BIND_NAME, RENDER_PRIORITY, callback)
        end,
        Unbind = function()
            pcall(RunService.UnbindFromRenderStep, RunService, BIND_NAME)
        end,
    },
    Heartbeat = {
        Bind = function(callback)
            return RunService.Heartbeat:Connect(callback)
        end,
        Unbind = function(connection)
            if connection then
                connection:Disconnect()
            end
        end,
    },
    PreSimulation = {
        Bind = function(callback)
            return RunService.PreSimulation:Connect(callback)
        end,
        Unbind = function(connection)
            if connection then
                connection:Disconnect()
            end
        end,
    },
}

local CurrentPhase    = nil
local PhaseConnection = nil

local function StopBinding()
    if not CurrentPhase then
        return false
    end

    Phases[CurrentPhase].Unbind(PhaseConnection)

    LogInfo("StopBinding", Format("Unbound the interval pass from '%s'", CurrentPhase))

    CurrentPhase    = nil
    PhaseConnection = nil

    return true
end

local function StartBinding(phaseName)
    local phase = Phases[phaseName]

    if not phase then
        LogError("StartBinding", Format(
            "Unknown phase '%s' (expected Render, Heartbeat or PreSimulation)",
            tostring(phaseName)
        ))

        return false
    end

    StopBinding()

    PhaseConnection = phase.Bind(RunDueIntervals)
    CurrentPhase    = phaseName

    LogInfo("StartBinding", Format("Bound the interval pass to '%s'", phaseName))

    return true
end

local function Unload(clearIntervals)
    StopBinding()

    if clearIntervals then
        ClearAll()
    end

    LogInfo("Unload", "Interval watchdog stopped")
end

if #Order > 0 then
    LogInfo("Startup", Format("Restored %d interval(s) from the previous run", #Order))
end

StartBinding("Render")

return table.freeze({
    -- Registration
    RegisterInterval   = RegisterInterval,
    Every              = RegisterInterval,
    After              = After,
    UnregisterInterval = UnregisterInterval,
    UnregisterOwner    = UnregisterOwner,
    Clear              = ClearAll,

    -- Live control
    SetDelay           = SetDelay,
    SetCallback        = SetCallback,
    Pause              = function(intervalName) return SetEnabled(intervalName, false) end,
    Resume             = function(intervalName) return SetEnabled(intervalName, true) end,
    PauseAll           = function() return SetAllEnabled(false) end,
    ResumeAll          = function() return SetAllEnabled(true) end,
    Trigger            = Trigger,

    -- Inspection
    IsRegistered       = function(intervalName) return Intervals[intervalName] ~= nil end,
    GetInfo            = GetInfo,
    List               = ListIntervals,
    Dump               = Dump,

    -- Lifecycle
    SetPhase           = StartBinding,
    Unload             = Unload,
})
