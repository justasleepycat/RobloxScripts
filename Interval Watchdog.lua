--[[
    Interval Watchdog
    =================

    One render-step pass that drives every named interval a script registers. Instead of
    each feature spawning its own `while task.wait(x) do ... end` loop, or a RenderStepped
    connection with a hand-rolled cooldown accumulator, features register a callback and the
    watchdog runs whatever is due, once per frame, from a single binding.

    What it buys over ad-hoc loops
    ------------------------------
      * One binding instead of N. A callback that throws is caught and reported once, not
        once per frame, and every other interval keeps running.
      * Drift-free periods: a 0.5s interval stays 0.5s instead of 0.5s plus one frame per
        tick. After a stall (loading screen, minimised window) the missed ticks are skipped
        rather than fired back to back.
      * Deterministic order: intervals run in registration order, not pairs() order.
      * A frame budget (FRAME_BUDGET) caps one pass at about 4ms; whatever is left stays due
        and runs on the next frame, so one slow callback cannot eat the frame.
      * Lifecycle: pause, resume, retime, retarget, inspect and unregister by name.

    Loading
    -------
    The module is fetched from this repository and cached in getgenv(), so any number of
    scripts can share one copy:

        local WATCHDOG_URL = "https://raw.githubusercontent.com/justasleepycat/RobloxScripts/refs/heads/main/Interval%20Watchdog.lua"

        local Watchdog = getgenv().IntervalWatchdog

        if not Watchdog then
            local loaded, loadedWatchdog = pcall(function()
                return loadstring(game:HttpGet(WATCHDOG_URL))()
            end)

            if not loaded then
                error("[!] [Bootstrap] Failed to load the Interval Watchdog (" .. tostring(loadedWatchdog) .. ")")
            end

            Watchdog                   = loadedWatchdog
            getgenv().IntervalWatchdog = Watchdog
        end

    raw.githubusercontent serves through a CDN with a five minute cache, so a push to this
    file can take that long to reach a running client.

    Usage
    -----
        Watchdog.Every("AutoFarm", 0.5, function(elapsedSeconds, intervalName)
            -- runs every 0.5s; elapsedSeconds is real time since its previous run
        end)

        Watchdog.After("RestoreCamera", 0.2, function()
            -- one-shot: dropped as soon as it has run once
        end)

        Watchdog.UnregisterInterval("AutoFarm")

    Callbacks receive (elapsedSeconds, intervalName) and must not yield: the pass holds a
    re-entrancy guard while a callback runs. Start long work with task.spawn instead.

    Timing model
    ------------
      * Clocked with os.clock() (monotonic), not the deprecated tick().
      * A delay of 0 runs the callback on every pass, exactly like a BindToRenderStep
        callback bound to the same phase. Any positive delay fires at most once per frame.
      * Late ticks are dropped, not squeezed in: if the next tick would already be in the
        past, the interval is re-armed one whole delay from now.

    Per-frame intervals
    -------------------
    A delay of 0 is legal and means "run on every pass", which is what you would get by
    binding the callback to the render step yourself: it runs once per frame, in
    registration order, inside the same pcall as every timed interval and never deferred by
    the frame budget.

        Watchdog.Every("Crosshair", 0, function()
            -- every frame, like a BindToRenderStep callback
        end)

    After(name, 0, fn) therefore means "on the next frame", and SetDelay(name, 0) turns a
    timed interval into a per-frame one. Per-frame intervals are exempt from the frame
    budget, exactly like the callback they replace, so a slow per-frame callback pushes timed
    work to the next frame rather than being skipped itself. The budget still guarantees that
    at least one timed interval runs per pass, so a permanently slow per-frame callback
    cannot starve them completely.

    Phases
    ------
    The pass binds to the render step at Enum.RenderPriority.Last.Value by default, which
    runs after Input / Camera / Character. RenderStepped stops firing when the client stops
    rendering (a minimised window renders nothing), so work that polls state rather than
    touches the camera should switch phase:

        Watchdog.SetPhase("Heartbeat")      -- game loop, ticks while the client is alive
        Watchdog.SetPhase("PreSimulation")
        Watchdog.SetPhase("Render")         -- back to the default

    State
    -----
    The interval map lives in getgenv().activeIntervals, next to a
    getgenv().intervalWatchdogVersion marker, so a re-executed script adopts the intervals
    already there instead of dropping them or double-binding the pass; missing fields are
    filled in on load. Re-registering an existing name replaces its callback by default,
    which is what makes a hot reload pick up the new closure. Pass { Replace = false } to
    get the old "already exists" rejection instead.

    Callbacks stay in that shared map until they are unregistered, and they keep the script
    alive with them: Unload(true) or Clear() drops them, Unload() only unbinds the pass.
    Unregister by name rather than calling Clear() from a script that shares the executor
    with other scripts.

    API
    ---
    Registration
        Every / RegisterInterval(name, delay, callback, options?)   -> boolean
        After(name, delay, callback, options?)                      -> boolean (one-shot)
        UnregisterInterval(name)                                    -> boolean
        UnregisterOwner(owner)                                      -> count
        Clear()                                                     -> count

    Control
        SetDelay(name, delay)           SetCallback(name, callback)
        Pause(name)                     Resume(name)
        PauseAll()                      ResumeAll()                 -> count
        Trigger(name)                   -- becomes due on the next frame

    Inspection
        IsRegistered(name)              -> boolean
        GetInfo(name)                   -> { Name, Delay, Enabled, Once, Owner, Runs,
                                            Errors, LastError, LastMs, NextIn } or nil
        List()                          -> array of GetInfo() copies, registration order
        Dump()                          -> List() plus one [i] line per interval

    Lifecycle
        SetPhase(phaseName)             -> boolean
        Unload(clearIntervals?)         -- unbind, optionally drop every interval

    options
        Enabled            = true       register in the paused state when false
        Immediate          = false      fire on the next frame instead of after one delay
        Once               = false      drop the interval as soon as it becomes due
        Owner              = nil        tag for UnregisterOwner(owner)
        Replace            = true       replace a name that is already registered
        DisableAfterErrors = nil        pause the interval after N consecutive failures

    Diagnostics
    -----------
    Every line is prefixed "[i] [Scope]" or "[!] [Scope]". A failing callback is reported
    once per distinct message and stays quiet until it succeeds again, and the record keeps
    Runs, Errors, LastError and LastMs for GetInfo() and Dump(). Delays must be finite and
    zero or greater (NaN and inf are rejected), which is what keeps an interval from
    silently never firing.
]]

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
    -- 0 is legal and means "every pass", which is what a raw BindToRenderStep callback
    -- gets. NaN fails every comparison, so it has to be rejected explicitly as well.
    return type(intervalDelay) == "number"
        and intervalDelay == intervalDelay
        and intervalDelay >= 0
        and intervalDelay < Huge
end

local function DescribeDelay(intervalDelay)
    if intervalDelay == 0 then
        return "per frame"
    end

    return Format("every %.3fs", intervalDelay)
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
        "%s interval '%s' (%s)",
        isNew and "Created" or "Replaced",
        intervalName,
        DescribeDelay(intervalDelay)
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

    LogInfo("SetDelay", Format("Interval '%s' now runs %s", intervalName, DescribeDelay(intervalDelay)))

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
            "%-24s every %-8s next %8s  runs %-6d errors %-4d %s",
            info.Name,
            info.Delay == 0 and "frame" or Format("%.3fs", info.Delay),
            info.Delay == 0 and "-" or Format("%.3fs", info.NextIn),
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

local Running      = false
local DueRecords   = {}
local DueTicks     = {}
local DueHighWater = 0

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

            if dueCount > DueHighWater then
                DueHighWater = dueCount
            end
        end
    end

    if dueCount == 0 then
        Running = false

        return
    end

    ProfileBegin("IntervalWatchdog")

    local deadline     = now + FRAME_BUDGET
    local invokedTimed = 0

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
            -- Per-frame intervals are never deferred: they run on every pass, the way the
            -- render-step callback they replace would. Timed work yields to the budget once
            -- one timed interval has already run this pass; a deferred record keeps its old
            -- NextTick, so it is still due and simply runs on the next frame.
            if record.Delay > 0 and Clock() >= deadline and invokedTimed > 0 then
                continue
            end

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

            if record.Delay > 0 then
                invokedTimed += 1
            end
        end
    end

    -- Drop the references a busier pass left behind, so an unregistered record cannot stay
    -- alive through the scratch arrays.
    for index = dueCount + 1, DueHighWater do
        DueRecords[index] = nil
        DueTicks[index]   = nil
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
