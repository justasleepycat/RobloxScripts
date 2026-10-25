local RunService = game:GetService("RunService")

-- Diagnostics: every line is "[i] [Function] ..." or "[!] [Function] ...", where the
-- scope is the function the line is printed from. Failures that a hot loop can hit
-- repeatedly go through ReportFailure, which prints once until the failure clears.
local LOG_FORMAT        = "[%s] [%s] %s"
local reportedFailures  = {}

local function LogInfo(scope, message)
    print(string.format(LOG_FORMAT, "i", scope, message))
end

local function LogError(scope, message)
    print(string.format(LOG_FORMAT, "!", scope, message))
end

local function ReportFailure(failureKey, scope, message)
    if reportedFailures[failureKey] == message then
        return
    end

    reportedFailures[failureKey] = message
    LogError(scope, message)
end

local function ClearFailure(failureKey)
    reportedFailures[failureKey] = nil
end

local activeIntervals   = {}

local function RegisterInterval(intervalName, intervalDelay, callback)
    if type(intervalName) ~= "string" or intervalName == "" then
        LogError("RegisterInterval", "Interval name must be a non-empty string")

        return false
    end

    if type(intervalDelay) ~= "number" or intervalDelay <= 0 then
        LogError("RegisterInterval", string.format("Interval '%s' has an invalid delay (%s)",
            intervalName,
            tostring(intervalDelay)
        ))

        return false
    end

    if type(callback) ~= "function" then
        LogError("RegisterInterval", string.format("Interval '%s' has no callback function", intervalName))

        return false
    end

    if activeIntervals[intervalName] then
        LogError("RegisterInterval", string.format("Interval '%s' already exists", intervalName))

        return false
    end

    activeIntervals[intervalName] = {
        Delay       = intervalDelay,
        NextTick    = tick() + intervalDelay,
        Callback    = callback
    }

    LogInfo("RegisterInterval", string.format("Created interval '%s' (every %.3fs)", intervalName, intervalDelay))

    return true
end

local function UnregisterInterval(intervalName)
    if not activeIntervals[intervalName] then
        LogError("UnregisterInterval", string.format("Interval '%s' does not exist", tostring(intervalName)))

        return false
    end

    activeIntervals[intervalName] = nil

    LogInfo("UnregisterInterval", string.format("Removed interval '%s'", intervalName))

    return true
end


-- Runs whatever is due this frame. A callback that throws is reported once and the
-- loop keeps going: the old code let the error escape the render step every frame.
local function RunDueIntervals()
    local currentTick = tick()

    for intervalName, intervalInfo in pairs(activeIntervals) do
        if (currentTick - intervalInfo.NextTick) > 0 then
            intervalInfo.NextTick = currentTick + intervalInfo.Delay

            local ok, err = pcall(intervalInfo.Callback)

            if ok then
                ClearFailure("RunDueIntervals." .. intervalName)
            else
                ReportFailure("RunDueIntervals." .. intervalName, "RunDueIntervals", string.format(
                    "Interval '%s' callback failed (%s)",
                    intervalName,
                    tostring(err)
                ))
            end
        end
    end
end

LogInfo("Startup", string.format("Binding render step '%s' at priority %d", "intervalWatchdog", 0))
RunService:BindToRenderStep("intervalWatchdog", 0, RunDueIntervals)

local cachedPlayers     = {}

RegisterInterval("PlayerCache", 0.1, function()
    LogInfo("PlayerCache", "Caching players")
end)

task.wait(1)
RunService:UnbindFromRenderStep("intervalWatchdog")