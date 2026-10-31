if PRINT_LOGS == nil then
    PRINT_LOGS = false
end

--[[ GreenvilleVehicleProperties.lua ==========================================
    A client-side property editor for the vehicle you have spawned in Greenville.

    What it does
        - Lists every attribute of your spawned car and of its Wheels model, grouped by the part of
          the car they belong to (paint, interior, plates, rims, brakes, suspension, dynamics,
          friction, condition), with a typed editor per row: a switch for booleans, a numeric box
          for numbers, a hex box and swatch for colours, a dropdown for enums and for the few
          strings that are really an enumeration, and a text box for everything else.
        - Adds a MOTOR group read from the car's own A-Chassis Tune module: the top-speed and 0-60
          estimates those fields add up to, then every lever behind them - horsepower, weight,
          redline, gear ratios, final drive, brake/parking/handbrake torque, steering torque,
          electric motor torque, torque vector, differential preloads and the throttle/brake
          response curves. Tune rows are polled, so a change the chassis makes shows up too.
        - Applies the values that have a live client-side effect straight away (body paint,
          interior trim, brake colour, rim decal, plate text). Dynamics, suspension and the motor
          tune are read by A-Chassis while it initialises, so they are stored on the client's copy
          and take effect when the game restarts the chassis - leaving and re-entering the vehicle
          does that, and every apply of that kind says so in its notification.
        - Watches every attribute it lists, so a value the game changes (odometer, dirt level, an
          attribute the server rewrote) updates in the window without a refresh.
        - Saves a snapshot of the properties you tick and restores it later, with Select All and
          Unselect All at the top of the selection list.
        - Renders a clone of the current car in a ViewportFrame: the Body, Wheels and Misc geometry
          with every script, effect and constraint stripped out, turning at ten degrees a second and
          draggable to look around. It is rebuilt when the paint, interior, brakes or rims change.
        - Keeps named presets on a Presets tab. A preset stores every property of the current car,
          shows its own 3D preview styled with the preset's paint/interior/brakes/rims/plate, and is
          listed only while that car is spawned. The list can be searched; any one preset per car
          can be marked AUTO-LOAD so it is applied when that car is entered; presets can be renamed
          and deleted. Presets are written to GreenvilleVehicleProperties.presets.json in the
          executor's workspace, so they survive a reload.
        - Offers Stabilize High Speed in the Vehicle tab: suspension height, camber and damping are
          clamped into the ranges the game's own editor uses, AWD/TCS/ABS stay on, the tires become
          track tires, the friction is raised, and the weight distribution, weight and centre of
          gravity are set for a planted car. It also enables the Downforce Assist switch, which
          presses the car down at speed (and keeps the high-grip friction values asserted), and the
          Wheel Lock 300+ switch: above 300 mph an axle-aligned hinge on each wheel holds its
          position and steer/camber while leaving it free to roll, and their suspension/steering
          links are released; below 295 mph the hinges go and every link is restored. Gearing and
          redline are left alone, so top speed is not reduced.
        - Refresh Values reads every row back from the live car and the tune without changing either,
          for when something else moved a value and the rows look stale.
        - Adds a Drive tab. Boost burns Strength (studs/s total) along the selected velocity
          components (X, Y, Z; for example X+Z keeps the horizontal part) and/or car directions
          (Forward, Backward, Right, Left), summed and normalized; not fixed world axes. Car
          directions allow boosting from rest. It stops at Max speed. Fly drives the car with
          W/A/S/D relative to the camera, with a configurable maximum speed, CFrame or Velocity
          movement, and optional lerping. Speed limits and the derived max-speed row are speedometer
          mph (the raw studs-per-second conversion is four times the dial). Both have a selectable
          keybind: None, F1-F15, every numpad key (Keypad0-9, plus, minus, multiply, divide,
          period, enter, equals and NumLock), and Mouse Wheel Forward/Backward through
          LocalPlayer:GetMouse(). F16-F18 and the mouse side buttons are not exposed by this client.
        - Reports every apply, save and restore in a toast and in the window's status line.

    Layout
        Two tabs in one MonoUI window.
        Vehicle:
        |--------------------------------------------------------------|
        | Car name                                  Live car viewport   |
        |--------------------------------------------------------------|
        | Save / restore properties (opens the checkbox dropdown)      |
        |--------------------------------------------------------------|
        | Property name                              Value             |
        | ...                                                          |
        |--------------------------------------------------------------|
        |                          Unload                              |
        |--------------------------------------------------------------|
        Presets:
        |--------------------------------------------------------------|
        | Preset name input / Save preset                              |
        | Search presets                                               |
        | [preview] Name / meta / AUTO   Load Rename Auto Delete      |
        | ...                                                          |
        |                          Unload                              |
        |--------------------------------------------------------------|

    How to run it
        MonoUI must be reachable, in the order below:
            local MonoUI = loadstring(readfile("MonoUI.lua"))()
            loadstring(readfile("GreenvilleVehicleProperties.lua"))()(MonoUI)

        It also accepts a global MonoUI, or loads MonoUI.lua itself when nothing was passed in.

    Notes
        - This edits the client's copy of the vehicle. The server still owns the real car: the
          changes are local and are lost on respawn, which is what makes save/restore useful.
        - MonoUI's own hide key is Right Control, as with every other MonoUI window.
]]

local MonoUI = ...
if MonoUI == nil then
    MonoUI = rawget(_G, "MonoUI")
end
if MonoUI == nil and type(loadstring) == "function" and type(readfile) == "function" then
    local loaded, library = pcall(function()
        return loadstring(readfile("MonoUI.lua"))()
    end)
    if loaded then
        MonoUI = library
    end
end
if MonoUI == nil or type(MonoUI.CreateWindow) ~= "function" then
    if PRINT_LOGS then
        print("[!] [VehicleProperties] MonoUI is missing - pass it in, set it globally, or put MonoUI.lua beside this script")
    end
    return
end

local Players           = game:GetService("Players")
local HttpService       = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local Workspace         = game:GetService("Workspace")

local Player = Players.LocalPlayer
local Scope  = "VehicleProperties"
local Theme  = MonoUI.Theme

local RowHeight         = 30
local SelectionListSize = 180
local ToastWidth        = 320
local ToastLifetime     = 4

-- The in-game speedometer reads a quarter of the raw studs-per-second conversion: 400 in the raw
-- unit the rest of this file used to print shows as 100 on the dial. Every user-facing speed limit
-- is therefore expressed in speedometer mph and converted here.
local SPEEDOMETER_MPH_PER_STUD = 0.559234

local function SpeedometerMph(velocity)
    return velocity.Magnitude * SPEEDOMETER_MPH_PER_STUD
end

-- Presets live in the executor's own workspace folder, next to the script, as one JSON file. Only
-- the presets for the car in front of the player are shown, but the file keeps every car's set.
local PresetFilePath    = "GreenvilleVehicleProperties.presets.json"
local PresetRenderLimit = 16
local PresetRowHeight   = 84

-- Groups are shown in this order; anything unrecognised lands in Other. The order mirrors the car
-- itself: what you see from outside first, then what you feel from the driver's seat.
local GroupRank = {
    Motor      = 0,
    Paint      = 1,
    Interior   = 2,
    Plates     = 3,
    Rims       = 4,
    Brakes     = 5,
    Suspension = 6,
    Dynamics   = 7,
    Friction   = 8,
    Condition  = 9,
    Other      = 10,
}

-- A-Chassis reads these while the car initialises, not while it is driving.
local SpawnReadPrefixes = { "Dynamics_", "SuspensionTune_" }

local State = {
    window             = nil,
    content            = nil,
    headerRow          = nil,
    panelFrame         = nil,
    panelOpen          = false,
    panelStatus        = nil,
    listFrame          = nil,
    listHeight         = 380,
    car                = nil,
    wheels             = nil,
    entries            = {},
    selection          = {},
    snapshot           = nil,
    tune               = nil,
    tuneModule         = nil,
    pollToken          = 0,
    builderDialog      = nil,
    viewport           = nil,
    viewportDisplay    = nil,
    viewportCenter     = nil,
    viewportYaw        = 25,
    viewportPitch      = 8,
    viewportRefresh    = false,
    presets            = {},
    presetsTab         = nil,
    presetSearch       = "",
    presetListFrame    = nil,
    presetStatus       = nil,
    presetNameInput    = nil,
    presetSearchInput  = nil,
    presetRenameBar    = nil,
    presetRenameLabel  = nil,
    presetRenameInput  = nil,
    presetRenameId     = nil,
    presetDeleteId     = nil,
    presetRenderPending = false,
    autoLoadedCar      = nil,
    structureKey       = "",
    structurePending   = false,
    checkboxRefreshers = {},
    selectMenus        = {},
    rowConnections     = {},
    carConnections     = {},
    globalConnections  = {},
}

local ToastHost = nil
local ToastList = {}

-- The display is dragged with the same pointer state the spin loop reads, so a drag anywhere on the
-- viewport freezes the spin until the pointer is released.
local ViewportDrag = { active = false, pointer = nil, last = Vector2.zero }

-- The client-side high-speed assist: a downward force that grows with speed, and a friction values
-- re-assert because the server can hand the car a fresh set at any time.
local Downforce = {
    Enabled       = false,
    Force         = nil,
    Attachment    = nil,
    Car           = nil,
    Connection    = nil,
    FrictionClock = 0,
    Switch        = nil,
}

-- Above 300 mph an axle-aligned hinge holds each wheel's position relative to the chassis and locks
-- its steer/camber, while leaving it free to roll. Below 295 mph the hinges go and every released
-- suspension/steering link is restored. A short cooldown keeps the two states from flapping at 300.
local WheelLock = {
    Enabled     = false,
    Locked      = false,
    Locks       = {},
    Constraints = {},
    Car         = nil,
    Connection  = nil,
    Cooldown    = 0,
    Recheck     = 0,
    Switch      = nil,
}

local WHEEL_NAMES         = { "FL", "FR", "RL", "RR" }
local WHEEL_LOCK_SPEED    = 300
local WHEEL_UNLOCK_SPEED  = 295

-- Boost: add Strength along the car's current velocity over Duration, stopping at MaxSpeedMph.
local Boost = {
    Strength      = 10,
    MaxSpeedMph   = 400,
    Duration      = 0.75,
    Axes          = { X = true, Y = true, Z = true },
    ActiveAxes    = {},
    ActiveLabel   = "X, Y, Z",
    AxisOpen      = false,
    AxisPanel     = nil,
    AxisStatus    = nil,
    AxisRefreshers = {},
    Active        = false,
    Elapsed       = 0,
    Car           = nil,
    Connection    = nil,
    Keybind       = "None",
    KeySelect     = nil,
    StrengthInput = nil,
    MaxSpeedInput = nil,
    DurationInput = nil,
}

-- Fly: the car follows the camera. CFrame mode anchors the seat and writes its CFrame; Velocity
-- mode leaves it unanchored and writes AssemblyLinearVelocity. Both can lerp toward the target.
local Fly = {
    Active           = false,
    MaxSpeedMph      = 250,
    Mode             = "CFrame",
    Lerp             = true,
    LerpRate         = 10,
    Keys             = { W = false, A = false, S = false, D = false },
    Car              = nil,
    Seat             = nil,
    OriginalAnchored = false,
    Connection       = nil,
    KeyConnections   = {},
    Switch           = nil,
    ModeSelect       = nil,
    LerpSwitch       = nil,
    Keybind          = "None",
    KeySelect        = nil,
    MaxSpeedInput    = nil,
}

-- Roblox only exposes the function keys the engine knows; every one that exists up to F18 is
-- offered, so this is F1..F15 on the current client and will include F16..F18 if they are added.
local KEYBIND_OPTIONS = { "None" }
for index = 1, 18 do
    local ok, keyCode = pcall(function()
        return Enum.KeyCode["F" .. index]
    end)
    if ok and keyCode ~= nil then
        KEYBIND_OPTIONS[#KEYBIND_OPTIONS + 1] = "F" .. index
    end
end

-- Player:GetMouse() exposes the wheel's forward and backward events. The side buttons have no
-- Button4/Button5 events and no UserInputType/KeyCode in this client, so the wheel is the mouse
-- forward/backward input that can be bound.
local DriveMouse = nil
local HasWheelForward = false
local HasWheelBackward = false
local mouseOk, mouseObject = pcall(function()
    return Player:GetMouse()
end)
if mouseOk and mouseObject ~= nil then
    DriveMouse = mouseObject
    local forwardOk = pcall(function()
        return DriveMouse.WheelForward
    end)
    if forwardOk then
        HasWheelForward = true
        KEYBIND_OPTIONS[#KEYBIND_OPTIONS + 1] = "Wheel Forward"
    end
    local backwardOk = pcall(function()
        return DriveMouse.WheelBackward
    end)
    if backwardOk then
        HasWheelBackward = true
        KEYBIND_OPTIONS[#KEYBIND_OPTIONS + 1] = "Wheel Backward"
    end
end

for _, item in ipairs(Enum.KeyCode:GetEnumItems()) do
    local name = item.Name
    if string.sub(name, 1, 6) == "Keypad" or name == "NumLock" then
        KEYBIND_OPTIONS[#KEYBIND_OPTIONS + 1] = name
    end
end

local BOOST_AXIS_OPTIONS = { "X", "Y", "Z", "Forward", "Backward", "Right", "Left" }

-- The Drive tab is part of the config: these helpers capture and restore its settings, and the
-- config file keeps both a current copy and one per preset.
local SaveDriveConfigSoon

local function FormatDriveAxes(axes)
    local names = {}
    for _, axis in ipairs(BOOST_AXIS_OPTIONS) do
        if axes[axis] then
            names[#names + 1] = axis
        end
    end
    if #names == 0 then
        return "None"
    end
    return table.concat(names, ", ")
end

local function ValidKeybind(value)
    if value == "None" then
        return true
    end
    for _, option in ipairs(KEYBIND_OPTIONS) do
        if option == value then
            return true
        end
    end
    return false
end

local function CaptureDriveSettings()
    local axes = {}
    for _, axis in ipairs(BOOST_AXIS_OPTIONS) do
        if Boost.Axes[axis] then
            axes[axis] = true
        end
    end
    return {
        boost = {
            strength    = Boost.Strength,
            maxSpeedMph = Boost.MaxSpeedMph,
            duration    = Boost.Duration,
            axes        = axes,
            keybind     = Boost.Keybind,
        },
        fly = {
            maxSpeedMph = Fly.MaxSpeedMph,
            mode        = Fly.Mode,
            lerp        = Fly.Lerp,
            keybind     = Fly.Keybind,
        },
    }
end

local function ApplyDriveSettings(config, silent)
    if type(config) ~= "table" then
        return false
    end
    local boost = type(config.boost) == "table" and config.boost or {}
    local fly = type(config.fly) == "table" and config.fly or {}

    if type(boost.strength) == "number" and boost.strength > 0 then
        Boost.Strength = boost.strength
    end
    if type(boost.maxSpeedMph) == "number" and boost.maxSpeedMph > 0 then
        Boost.MaxSpeedMph = boost.maxSpeedMph
    end
    if type(boost.duration) == "number" and boost.duration > 0 then
        Boost.Duration = boost.duration
    end
    if type(boost.axes) == "table" then
        Boost.Axes = {}
        for _, axis in ipairs(BOOST_AXIS_OPTIONS) do
            if boost.axes[axis] then
                Boost.Axes[axis] = true
            end
        end
    end
    if type(boost.keybind) == "string" and ValidKeybind(boost.keybind) then
        Boost.Keybind = boost.keybind
    end

    if type(fly.maxSpeedMph) == "number" and fly.maxSpeedMph > 0 then
        Fly.MaxSpeedMph = fly.maxSpeedMph
    end
    if fly.mode == "CFrame" or fly.mode == "Velocity" then
        Fly.Mode = fly.mode
    end
    if type(fly.lerp) == "boolean" then
        Fly.Lerp = fly.lerp
    end
    if type(fly.keybind) == "string" and ValidKeybind(fly.keybind) then
        Fly.Keybind = fly.keybind
    end

    if Boost.StrengthInput ~= nil then
        Boost.StrengthInput.Text = tostring(Boost.Strength)
    end
    if Boost.MaxSpeedInput ~= nil then
        Boost.MaxSpeedInput.Text = tostring(Boost.MaxSpeedMph)
    end
    if Boost.DurationInput ~= nil then
        Boost.DurationInput.Text = tostring(Boost.Duration)
    end
    if Fly.MaxSpeedInput ~= nil then
        Fly.MaxSpeedInput.Text = tostring(Fly.MaxSpeedMph)
    end
    if Boost.KeySelect ~= nil then
        Boost.KeySelect.Set(Boost.Keybind)
    end
    if Fly.KeySelect ~= nil then
        Fly.KeySelect.Set(Fly.Keybind)
    end
    if Fly.ModeSelect ~= nil then
        Fly.ModeSelect.Set(Fly.Mode)
    end
    if Fly.LerpSwitch ~= nil then
        Fly.LerpSwitch.Set(Fly.Lerp)
    end
    for _, refresh in ipairs(Boost.AxisRefreshers) do
        pcall(refresh)
    end
    if Boost.AxisStatus ~= nil then
        Boost.AxisStatus.Text = "Selected: " .. FormatDriveAxes(Boost.Axes)
    end
    if Fly.Active and Fly.Seat ~= nil and Fly.Seat.Parent ~= nil then
        Fly.Seat.Anchored = Fly.Mode == "CFrame"
    end
    if SaveDriveConfigSoon ~= nil then
        SaveDriveConfigSoon()
    end
    return true
end

-- Assigned with the display, but needed by the apply path above it.
local ScheduleViewportRefresh
-- Assigned at the bottom, but both tab footers need to reach it.
local Unload

-- Everything a car carries for driving, not for looking at: scripts, remotes, physics constraints,
-- effects and values. The clone keeps only geometry, decals/textures and the plate SurfaceGuis.
local ViewportBlocklist = {
    Script = true, LocalScript = true, ModuleScript = true,
    RemoteEvent = true, RemoteFunction = true, BindableEvent = true, BindableFunction = true,
    Sound = true, ParticleEmitter = true, Trail = true, Beam = true, Smoke = true, Fire = true,
    Sparkles = true, Explosion = true, Highlight = true, SelectionBox = true, SelectionSphere = true,
    Attachment = true, Weld = true, WeldConstraint = true, Motor6D = true, HingeConstraint = true,
    SpringConstraint = true, RigidConstraint = true, Torque = true,
    BodyGyro = true, BodyVelocity = true, BodyAngularVelocity = true, BodyPosition = true,
    BodyForce = true, VectorForce = true, AlignPosition = true, AlignOrientation = true,
    LinearVelocity = true, AngularVelocity = true,
    ClickDetector = true, ProximityPrompt = true, BillboardGui = true,
    NumberValue = true, StringValue = true, ObjectValue = true, IntValue = true, BoolValue = true,
    PointLight = true, SpotLight = true, SurfaceLight = true,
}

--=== logging ================================================================

local function LogInfo(message)
    if PRINT_LOGS then
        print(string.format("[i] [%s] %s", Scope, message))
    end
end

local function LogError(message)
    if PRINT_LOGS then
        print(string.format("[!] [%s] %s", Scope, message))
    end
end

-- A MonoUI window installs one RightControl handler. When a script is reloaded without Unload, the
-- old gui is gone but that handler can survive and toggle a dead plate's backdrop blur on the next
-- key press. Clear any such handler at startup so only this instance owns the key.
local function CleanupStaleMonoUIHandlers()
    if type(getconnections) ~= "function" or type(debug.getupvalue) ~= "function" then
        return
    end
    local removed = 0
    for _, connection in ipairs(getconnections(UserInputService.InputBegan)) do
        if connection.Function ~= nil then
            local window = nil
            for slot = 1, 8 do
                local ok, a, b = pcall(debug.getupvalue, connection.Function, slot)
                if not ok then
                    break
                end
                local value = type(a) == "string" and b or a
                if value == nil then
                    break
                end
                if type(value) == "table" and (value.plate ~= nil or value.settings ~= nil) then
                    window = value
                end
            end
            if window ~= nil and (window.plate == nil or window.plate.Parent == nil) then
                pcall(function()
                    connection:Disconnect()
                end)
                removed = removed + 1
            end
        end
    end
    if removed > 0 then
        LogInfo(string.format("Disconnected %d stale MonoUI key handler(s)", removed))
    end
end

--=== value helpers ==========================================================

local function FormatNumber(value)
    if value ~= value then
        return "nan"
    end
    if value == math.huge then
        return "inf"
    end
    if value == -math.huge then
        return "-inf"
    end
    if value == math.floor(value) and math.abs(value) < 1e15 then
        return string.format("%.0f", value)
    end
    return string.format("%.7g", value)
end

local function ColorToHex(color)
    local function Channel(value)
        return math.clamp(math.floor(value * 255 + 0.5), 0, 255)
    end
    return string.format("#%02X%02X%02X", Channel(color.R), Channel(color.G), Channel(color.B))
end

local function FormatValue(value)
    local valueType = typeof(value)
    if valueType == "number" then
        return FormatNumber(value)
    end
    if valueType == "boolean" then
        return value and "true" or "false"
    end
    if valueType == "EnumItem" then
        return value.Name
    end
    if valueType == "Color3" then
        return ColorToHex(value)
    end
    if valueType == "table" then
        local parts = {}
        for _, item in ipairs(value) do
            table.insert(parts, FormatValue(item))
        end
        return table.concat(parts, ", ")
    end
    return tostring(value)
end

local function ParseColor(text)
    local hex = string.match(text, "#?(%x%x%x%x%x%x)")
    if hex ~= nil then
        return Color3.fromRGB(
            tonumber(string.sub(hex, 1, 2), 16),
            tonumber(string.sub(hex, 3, 4), 16),
            tonumber(string.sub(hex, 5, 6), 16)
        )
    end
    local red, green, blue = string.match(text, "(%d+%.?%d*)%s*,%s*(%d+%.?%d*)%s*,%s*(%d+%.?%d*)")
    if red ~= nil then
        return Color3.fromRGB(tonumber(red), tonumber(green), tonumber(blue))
    end
    return nil
end

local function KindOf(value)
    local valueType = typeof(value)
    if valueType == "boolean" then
        return "Boolean"
    end
    if valueType == "number" then
        return "Number"
    end
    if valueType == "string" then
        return "String"
    end
    if valueType == "Color3" then
        return "Color"
    end
    if valueType == "EnumItem" then
        return "Enum"
    end
    return "Unsupported"
end

local function GroupOf(key)
    if string.match(key, "^Paint") then
        return "Paint"
    end
    if string.match(key, "^Int%d_") then
        return "Interior"
    end
    if key == "RimDecal" then
        return "Rims"
    end
    if string.match(key, "^Plate") or key == "StateName" then
        return "Plates"
    end
    if string.match(key, "^ClassicBrake") then
        return "Brakes"
    end
    if string.match(key, "^SuspensionTune_") then
        return "Suspension"
    end
    if string.match(key, "^Dynamics_") then
        return "Dynamics"
    end
    if string.match(key, "^Friction_") then
        return "Friction"
    end
    if key == "DirtLevel" or key == "Odometer" then
        return "Condition"
    end
    return "Other"
end

local function ReadAtSpawn(key)
    for _, prefix in ipairs(SpawnReadPrefixes) do
        if string.sub(key, 1, #prefix) == prefix then
            return true
        end
    end
    return false
end

--=== list helpers ==========================================================

local function CopyValue(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for index, item in ipairs(value) do
        copy[index] = item
    end
    return copy
end

local function FormatList(list)
    local parts = {}
    for _, value in ipairs(list) do
        table.insert(parts, FormatNumber(value))
    end
    return table.concat(parts, ", ")
end

local function ParseList(text)
    local values = {}
    for token in string.gmatch(text, "[^,%s]+") do
        local value = tonumber(token)
        if value == nil then
            return nil
        end
        table.insert(values, value)
    end
    if #values < 2 then
        return nil
    end
    return values
end

--=== motor sources =========================================================

-- A-Chassis keeps its drivetrain in the car's own tune module, not in attributes. These are the
-- fields that decide how much torque the car puts down, how hard it stops, and where its top speed
-- lands; the two derived rows at the top are what those fields add up to.
local MotorFields = {
    { key = "Horsepower",       label = "Horsepower" },
    { key = "Weight",           label = "Weight (lb)" },
    { key = "WeightDist",       label = "Weight distribution (%)" },
    { key = "CGHeight",         label = "Center of gravity height" },
    { key = "Redline",          label = "Redline (RPM)" },
    { key = "PeakRPM",          label = "Peak RPM" },
    { key = "FinalDrive",       label = "Final drive" },
    { key = "FDMult",           label = "Final drive mult" },
    { key = "Ratios",           label = "Gear ratios", kind = "List" },
    { key = "BrakeForce",       label = "Brake torque" },
    { key = "PBrakeForce",      label = "Parking brake torque" },
    { key = "EBrakeForce",      label = "Handbrake torque" },
    { key = "SteerMaxTorque",   label = "Steer torque" },
    { key = "RSteerMaxTorque",  label = "Rear steer torque" },
    { key = "E_Horsepower",     label = "Electric horsepower" },
    { key = "E_Torque",         label = "Electric motor torque" },
    { key = "E_Redline",        label = "Electric redline (RPM)" },
    { key = "E_Trans1",         label = "Electric torque rise" },
    { key = "E_Trans2",         label = "Electric torque peak" },
    { key = "TorqueVector",     label = "Torque vector" },
    { key = "FDiffPreload",     label = "Front diff preload" },
    { key = "RDiffPreload",     label = "Rear diff preload" },
    { key = "ThrotAccel",       label = "Throttle accel" },
    { key = "ThrotDecel",       label = "Throttle decel" },
    { key = "BrakeAccel",       label = "Brake accel" },
    { key = "BrakeDecel",       label = "Brake decel" },
    { key = "RevAccel",         label = "Rev accel" },
    { key = "LaunchRPM",        label = "Launch RPM" },
    { key = "LaunchMult",       label = "Launch mult" },
    { key = "KickMult",         label = "Kick mult" },
    { key = "Turbochargers",    label = "Turbochargers" },
    { key = "T_Boost",          label = "Turbo boost" },
    { key = "T_Efficiency",     label = "Turbo efficiency" },
    { key = "T_Size",           label = "Turbo size" },
    { key = "Superchargers",    label = "Superchargers" },
    { key = "S_Boost",          label = "Supercharger boost" },
    { key = "S_Efficiency",     label = "Supercharger efficiency" },
    { key = "S_Sensitivity",    label = "Supercharger sensitivity" },
}

--=== help copy =============================================================

local GroupHelp = {
    Paint      = "Paint channels are painted onto the Body and Misc parts named Color, Color1, Color2 and Color3. The color is the panel colour; reflectance is the clearcoat highlight. Paint changes are local to this client and are applied immediately.",
    Interior   = "Interior channels drive the InteriorColor, InteriorColor1..6 parts. Colour sets the trim colour, material changes the surface type and reflectance controls how glossy it is. Interior changes are applied immediately on this client.",
    Plates     = "Plate data is stored on the car and rendered on the plate. PlateText is the displayed registration, PlateCode is the issuing state code, PlateType selects the plate style and PlateVanity keeps a personalised plate. StateName is the state shown on the plate.",
    Rims       = "RimDecal is a Roblox asset id applied to the visible rim decals on all four wheels. An empty value leaves the current rim finish alone.",
    Brakes     = "ClassicBrake values paint the brake calipers and visible brake hardware inside WheelFixed. They do not change braking force; use BrakeForce, PBrakeForce and EBrakeForce for that.",
    Suspension = "SuspensionTune values are read by A-Chassis while the car is initialising. Height moves the ride height, camber tilts the wheel, offset moves it in or out and the accessory offsets position the suspension trim. Stay inside the limits shown by the game's SuspensionLimits module.",
    Dynamics   = "Dynamics values control the drivetrain, tire compounds, traction control, ABS, brake bias and steering response. A-Chassis reads them when the car initialises, so a change generally needs the player to exit and re-enter the vehicle.",
    Friction   = "Friction values are local tire grip values. Friction_UseLocalValues must be true for the other Friction_* values to be used. Higher values grip more; lower values slide more. The server may reset these values, so re-check them after a respawn.",
    Condition  = "Condition values describe the car's current wear and mileage. They are normal car data rather than a styling or performance setting; editing them changes the local car model only.",
    Motor      = "This is an A-Chassis tune field. The chassis reads it when the car initialises, so exit and re-enter the vehicle to apply a change. Client-side tune edits are lost when the car respawns.",
    Other      = "This is a car attribute exposed by Greenville. The editor writes it directly to the local car model; whether the visible car reacts depends on which system reads the attribute.",
}

local KeyHelp = {
    PaintColor0     = "PaintColor0 is the main body colour for the Color parts. Use the swatch to open the colour editor, then Apply to paint the car immediately.",
    PaintColor1     = "PaintColor1 is the second paint channel (usually the secondary body or trim colour). It is painted onto Body and Misc parts named Color1.",
    PaintColor2     = "PaintColor2 is the third paint channel (often a stripe, lower body or accent colour). It is painted onto Color2 parts.",
    PaintColor3     = "PaintColor3 is the fourth paint channel (often a detail or pinstripe colour). It is painted onto Color3 parts.",
    PaintReflectance0 = "PaintReflectance0 is the clearcoat reflectance of the main paint channel. 0 is matte, around 0.1-0.3 is glossy, and 1 is mirror-like.",
    PaintReflectance1 = "PaintReflectance1 is the clearcoat reflectance of paint channel 1. Higher values make that panel or stripe shinier.",
    PaintReflectance2 = "PaintReflectance2 is the clearcoat reflectance of paint channel 2. Higher values make that accent shinier.",
    PaintReflectance3 = "PaintReflectance3 is the clearcoat reflectance of paint channel 3. Higher values make that detail shinier.",
    PlateText       = "PlateText is the registration shown on the physical plate. Greenville renders it through the plate SurfaceGui; it can contain letters, digits and a dash within the plate's character limit.",
    PlateCode       = "PlateCode is the jurisdiction code shown beside the plate text. The dropdown lists the codes the current car's plate data exposes.",
    PlateType       = "PlateType selects the plate style, such as a normal, dealer or vanity plate. It changes which plate artwork the game draws.",
    PlateVanity     = "PlateVanity marks the plate as a personalised vanity plate. The game uses it when deciding which plate layout and text rules to use.",
    StateName       = "StateName is the state or region shown on the plate. It is a display string, not a plate texture id.",
    RimDecal        = "RimDecal is a Roblox asset id for the rim decal. Applying it sets the decal on every wheel's Parts.Rims holder and restores the visible wheel mesh.",
    ClassicBrakeColor = "ClassicBrakeColor is the colour of the brake calipers and visible brake hardware inside WheelFixed. Use the swatch to edit it.",
    ClassicBrakeReflectance = "ClassicBrakeReflectance controls how glossy the caliper paint is. 0 is matte; higher values catch more light.",
    ClassicBrakeMaterial = "ClassicBrakeMaterial sets the Roblox Material on the caliper parts, for example SmoothPlastic, Metal or Neon.",
    ClassicBrakeVariant = "ClassicBrakeVariant is the MaterialVariant name applied to the caliper parts. Leave it empty to use the material's default look.",
    SuspensionTune_Height = "SuspensionTune_Height moves the whole car up or down relative to the wheels. The game's editor limits it to about +/-0.32; larger values can make the wheels lose contact.",
    SuspensionTune_FrontCamber = "SuspensionTune_FrontCamber tilts the front wheels inward or outward. Negative camber leans the top inward; values are read when the car spawns.",
    SuspensionTune_RearCamber = "SuspensionTune_RearCamber tilts the rear wheels. Small negative values improve cornering grip; extreme values reduce the contact patch.",
    SuspensionTune_FrontOffset = "SuspensionTune_FrontOffset moves the front wheels outward or inward relative to the body. Stay within the game's suspension limits to avoid clipping the arch.",
    SuspensionTune_RearOffset = "SuspensionTune_RearOffset moves the rear wheels outward or inward. It is useful for flush fitment but can cause tire and body collisions at extremes.",
    SuspensionTune_FrontAccessoryOffset = "SuspensionTune_FrontAccessoryOffset adjusts the front suspension trim independently of the wheel. It is cosmetic and is applied at spawn.",
    SuspensionTune_RearAccessoryOffset = "SuspensionTune_RearAccessoryOffset adjusts the rear suspension trim independently of the wheel. It is cosmetic and is applied at spawn.",
    Dynamics_Drivetrain = "Dynamics_Drivetrain selects which wheels receive power: AWD, RWD or FWD. A-Chassis reads it at spawn; changing it while driving does nothing until the car is re-entered.",
    Dynamics_Traction = "Dynamics_Traction enables traction control. It cuts torque when the driven wheels slip, which helps launches but can slow a deliberate drift.",
    Dynamics_Antilock = "Dynamics_Antilock enables ABS. It releases brake pressure when a wheel locks, trading some stopping distance for steering control under heavy braking.",
    Dynamics_BrakeBias = "Dynamics_BrakeBias moves braking force between the front and rear. -1 and 1 are the extremes; 0 is a neutral starting point. Too much rear bias can spin the car.",
    Dynamics_SteerAngleMult = "Dynamics_SteerAngleMult scales the maximum steering angle. Lower values calm the car at speed; higher values turn in harder and can make it twitchy.",
    Dynamics_SteerTorqueMult = "Dynamics_SteerTorqueMult scales the steering motor torque. Higher values reach the target angle faster and hold it against self-aligning forces.",
    Dynamics_SteerDampMult = "Dynamics_SteerDampMult scales steering damping. More damping suppresses oscillation; too much makes the steering feel slow and heavy.",
    Dynamics_SteerDecayMult = "Dynamics_SteerDecayMult scales how quickly the steering returns toward centre when the player lets go.",
    Dynamics_FSuspDampMult = "Dynamics_FSuspDampMult scales front suspension damping. More damping controls bounce; too much makes the front feel rigid and skittish.",
    Dynamics_RSuspDampMult = "Dynamics_RSuspDampMult scales rear suspension damping. More damping settles the rear; too much reduces mechanical grip over bumps.",
    Dynamics_FSuspStiffMult = "Dynamics_FSuspStiffMult scales front spring stiffness. Stiffer springs resist roll and dive but reduce compliance.",
    Dynamics_RSuspStiffMult = "Dynamics_RSuspStiffMult scales rear spring stiffness. Stiffer rear springs reduce squat but can make the car snap loose.",
    Dynamics_FTireCompound = "Dynamics_FTireCompound selects the front tire compound. The options come from the game's WheelFX TireTextures module; each compound has its own grip curve.",
    Dynamics_RTireCompound = "Dynamics_RTireCompound selects the rear tire compound. Mixing compounds changes the balance; a stickier rear increases understeer resistance.",
    Friction_UseLocalValues = "Friction_UseLocalValues switches the wheel friction model to the local Friction_* values. Turn it on before expecting the other values to do anything.",
    Friction_DryRoad = "Friction_DryRoad is the grip multiplier on dry tarmac. The game's normal road value is around 1.0; lower values slide more.",
    Friction_WetRoad = "Friction_WetRoad is the grip multiplier on wet tarmac. It is usually lower than DryRoad; raising it makes wet roads behave like dry ones.",
    Friction_DryDirt = "Friction_DryDirt is the grip multiplier on dry dirt. Lower values make the car slide more on loose surfaces.",
    Friction_WetDirt = "Friction_WetDirt is the grip multiplier on wet dirt. It should normally be lower than the dry-dirt value.",
    Friction_DryGrass = "Friction_DryGrass is the grip multiplier on dry grass. Grass is usually much slippier than tarmac.",
    Friction_WetGrass = "Friction_WetGrass is the grip multiplier on wet grass. Lower it for even less traction.",
    DirtLevel = "DirtLevel is the car's accumulated dirt from 0 (clean) to 1 (dirty). The game applies dirt textures from this value; editing it changes the local appearance.",
    Odometer = "Odometer is the car's mileage counter in miles. It is read from the car model and is normally maintained by the game.",
    InBounds = "InBounds reports whether the car is inside the game's playable boundary. It is a runtime flag, not a styling setting.",
}

local MotorHelp = {
    Horsepower       = "Horsepower is the engine's rated power. A-Chassis turns it into a torque curve together with PeakRPM, so raising it makes the car pull harder everywhere, not just at the top end.",
    Weight           = "Weight is the car's mass in pounds. More weight reduces acceleration and tyre load response; less weight makes it quicker but can make the car nervous and airborne over crests.",
    WeightDist       = "WeightDist is the front percentage of the car's weight. 50 is neutral; moving it forward adds front grip and stability, moving it rearward helps rotation but can cause oversteer.",
    CGHeight         = "CGHeight is the centre of gravity above the car's origin, in studs. Lowering it reduces body roll and rollover risk; raising it makes weight transfer and roll more dramatic.",
    Redline          = "Redline is the maximum engine RPM used by the automatic gearbox. In the top gear it is one of the two numbers that decide the car's theoretical top speed.",
    PeakRPM          = "PeakRPM is the engine speed where the torque curve peaks. A lower value makes the engine pull from low RPM; a higher value favours a screaming top end.",
    FinalDrive       = "FinalDrive is the axle ratio after the gearbox. A numerically higher final drive multiplies torque and lowers top speed; a lower one does the opposite.",
    FDMult           = "FDMult is a final-drive multiplier applied on top of FinalDrive. The dealership's speed calculation divides by it, so it can trim top speed without changing the physical axle ratio.",
    Ratios           = "Ratios is A-Chassis's gear table: index 1 is reverse, index 2 is neutral (normally 0), and indices 3 onward are the forward gears. A-Chassis uses Ratios[3] as first gear and Ratios[#] as top gear. The last forward ratio, FinalDrive and Redline decide top speed; the first forward ratio decides launch punch.",
    BrakeForce       = "BrakeForce is the total brake torque applied by the service brakes. Higher values stop harder but can lock the wheels if ABS is off.",
    PBrakeForce      = "PBrakeForce is the parking-brake torque. It holds the car when parked and can lock the rear wheels if applied while moving.",
    EBrakeForce      = "EBrakeForce is the handbrake torque. Raising it makes handbrake turns easier; too much can stop the car instantly or spin it.",
    SteerMaxTorque   = "SteerMaxTorque is the front steering motor's maximum torque. More torque reaches the target angle faster but can feel artificial and twitchy.",
    RSteerMaxTorque  = "RSteerMaxTorque is the rear-steer motor torque. It only matters on cars with rear-wheel steering; more torque makes the rear axle respond faster.",
    E_Horsepower     = "E_Horsepower is the electric motor's rated power when the car uses the electric drivetrain. It is separate from the combustion Horsepower.",
    E_Torque         = "E_Torque is the electric motor's torque. Electric torque is available from zero RPM, so this value strongly affects launch.",
    E_Redline        = "E_Redline is the electric motor's RPM limit. It decides the electric drivetrain's top speed much like Redline does for combustion.",
    E_Trans1         = "E_Trans1 is the first electric torque-curve point. It shapes how quickly the electric motor reaches peak torque.",
    E_Trans2         = "E_Trans2 is the second electric torque-curve point. Together with E_Trans1 it shapes the electric motor's pull at speed.",
    TorqueVector     = "TorqueVector splits drive torque between the left and right wheels to help the car turn. Higher values rotate the car more aggressively.",
    FDiffPreload     = "FDiffPreload is the front differential's preload. More preload resists wheel-speed differences and stabilises the front axle under power.",
    RDiffPreload     = "RDiffPreload is the rear differential's preload. More preload reduces inside-wheel slip but can increase understeer.",
    ThrotAccel       = "ThrotAccel is how quickly the throttle rises toward the requested value. Higher values respond faster and can make the car jerkier.",
    ThrotDecel       = "ThrotDecel is how quickly the throttle falls when released. Higher values engine-brake more sharply.",
    BrakeAccel       = "BrakeAccel is how quickly brake pressure builds. Higher values make the initial pedal bite stronger.",
    BrakeDecel       = "BrakeDecel is how quickly brake pressure releases. Higher values let the car roll freely sooner.",
    RevAccel         = "RevAccel is how quickly the engine revs in neutral. It affects throttle blips and the sound/RPM response.",
    LaunchRPM        = "LaunchRPM is the RPM the launch controller tries to hold before the clutch engages. Higher values launch harder but can spin the tyres.",
    LaunchMult       = "LaunchMult scales the launch torque. Higher values make launches more violent; lower values are gentler and more controllable.",
    KickMult         = "KickMult is the extra torque applied when the throttle is stabbed at low speed (the kickdown/overboost effect).",
    Turbochargers    = "Turbochargers is how many turbochargers the tune models. It changes how the boost curve is applied.",
    T_Boost          = "T_Boost is the turbo boost pressure contribution. Higher values add more top-end torque.",
    T_Efficiency     = "T_Efficiency is the turbo's efficiency. Higher values reduce lag and make the boost more useful.",
    T_Size           = "T_Size is the turbo size. Larger turbos usually make more top-end power at the cost of spool time.",
    Superchargers    = "Superchargers is how many superchargers the tune models. Superchargers add boost more linearly than turbos.",
    S_Boost          = "S_Boost is the supercharger boost contribution. Higher values add torque throughout the rev range.",
    S_Efficiency     = "S_Efficiency is the supercharger's efficiency. Higher values waste less power driving the blower.",
    S_Sensitivity    = "S_Sensitivity controls how strongly the supercharger boost follows throttle. Higher values make it respond more sharply.",
}

local DerivedHelp = {
    MaxSpeed     = "Max speed is calculated from the driven wheel's diameter, Redline, the last gear ratio, FinalDrive and FDMult, then converted to the speedometer's mph scale. It is a theoretical top-gear speed, not a measured run.",
    Acceleration = "Acceleration is the ideal 0-60 mph time from a simple power-to-weight estimate. It assumes every horsepower reaches the road with no losses, traction limit or shifting, so real times will be slower.",
}

local FEATURE_HELP = {
    Stabilize = "Stabilize High Speed writes a conservative high-speed setup: suspension height and damping are brought back inside the game's editor limits, camber is reduced, the centre of gravity is lowered, the car is weighted for its springs, and AWD, traction control, ABS, track tires and calmer steering are selected. It also enables Downforce Assist and Wheel Lock. Chassis and motor values apply after you exit and re-enter the vehicle.",
    Refresh = "Refresh Values re-reads every property from the live car and the A-Chassis tune without changing either. It also releases any focused textbox first, then rebuilds the list if the car's attribute layout changed. Use it after a respawn or after another editor changed the car.",
    Downforce = "Downforce Assist adds a local downward force to the car as speed rises. It starts above about 70 mph, grows with the square of speed and pushes near the centre of mass. It also re-asserts dry-road friction every second. It is a client-side aid, not a server modification.",
    WheelLock = "Wheel Lock 300+ places an axle-aligned hinge on each wheel above 300 mph. The hinge holds the wheel's position relative to the chassis and locks steering and camber while leaving the wheel free to roll. Below 295 mph the hinges are removed and the original suspension and steering links are restored. It is intended only for extreme-speed stabilisation.",
    SaveRestore = "Save / Restore Properties stores a snapshot of the selected car and wheel attributes. Open the panel to choose which properties are included; Select All and Unselect All are at the top. Saving captures the values, restoring writes them back to the local car. Snapshots are in memory and are lost when the script unloads, so save a named preset instead for a persistent copy.",
    Unload = "Unload closes the editor, stops Downforce, Boost and Fly, removes the Wheel Lock hinges, disconnects every listener and removes the window. It restores any values the editor changed while it was running; the car then belongs to the game again.",
    GearRatioBuilder = "The Gear Ratio Builder turns a target top speed into a usable A-Chassis gear set. It uses the driven wheel's diameter, Redline, FinalDrive, FDMult and the number of forward gears. Build preserves the reverse and neutral slots and generates a geometric spread from your first forward gear to the top forward gear. Apply writes the result into the tune; exit and re-enter the vehicle for A-Chassis to use it.",
    FinalDriveBuilder = "The Final Drive Builder splits A-Chassis's final drive into its two components: FinalDrive (the axle ratio) and FDMult (the multiplier). Enter a total final-drive product and an axle ratio, then Build calculates the multiplier. Apply writes both fields into the tune. If the product stays the same, the car's physics stays the same; splitting only changes how the two fields are labelled.",
    MaxSpeedBuilder = "The Max Speed Builder calculates the final drive needed for a target top speed with the current gear ratios. Its acceleration section uses a real-world efficiency and a grip-limited 0-60 floor (defaults 12.5% and 1.0 s) to turn a target time into a required horsepower; the current HP is kept when it is already higher. Apply acceleration writes horsepower, the first forward ratio, AWD, TCS/ABS, sticky tires, local dry-road friction, weight distribution and centre of gravity so the launch actually changes. Exit and re-enter the vehicle for A-Chassis to read the tune.",
}

local function PropertyHelp(key, group, kind)
    local specific = KeyHelp[key]
    if specific == nil then
        local slot, field = string.match(key, "^Int(%d)_(%a+)$")
        if slot ~= nil then
            if field == "Color" then
                local name = slot == "0" and "InteriorColor" or ("InteriorColor" .. slot)
                specific = string.format("Int%s_Color is the colour of the %s interior trim. The editor paints every part with that name; the swatch opens the colour picker.", slot, name)
            elseif field == "Reflectance" then
                specific = string.format("Int%s_Reflectance is the gloss of interior channel %s. 0 is matte; higher values catch more light.", slot, slot)
            elseif field == "Material" then
                specific = string.format("Int%s_Material is the Roblox Material used on interior channel %s. The dropdown lists every Material the client exposes.", slot, slot)
            elseif field == "Variant" then
                specific = string.format("Int%s_Variant is the MaterialVariant name for interior channel %s. It refines the selected material; leave it empty for the default variant.", slot, slot)
            end
        end
    end
    if specific == nil then
        specific = GroupHelp[group] or GroupHelp.Other
    end
    local kindText = kind == "Color" and "Colour3" or tostring(kind or "value")
    return string.format(
        "%s — %s property (%s).\n\n%s\n\nEdit the value in the field or picker on the right. Changes are written to the local car; values marked as spawn-read need the player to exit and re-enter the vehicle before A-Chassis sees them.",
        key, group, kindText, specific
    )
end

local function ComputeMaxSpeed()
    local tune = State.tune
    local wheels = State.wheels
    if tune == nil or wheels == nil then
        return 0
    end
    local ratios = tune.Ratios
    if type(ratios) ~= "table" or #ratios == 0 then
        return 0
    end
    local redline = tonumber(tune.Redline)
    local finalDrive = tonumber(tune.FinalDrive)
    local finalMult = tonumber(tune.FDMult)
    if redline == nil or finalDrive == nil or finalMult == nil or finalDrive == 0 or finalMult == 0 then
        return 0
    end

    local diameter = 0
    for _, wheel in ipairs(wheels:GetChildren()) do
        local driven = tune.Config == "AWD"
        if not driven then
            local isFront = string.sub(wheel.Name, 1, 1) == "F"
            driven = isFront == (tune.Config == "FWD")
        end
        if driven then
            diameter = math.max(diameter, wheel.Size.X)
        end
    end
    if diameter <= 0 then
        return 0
    end

    local raw = diameter * math.pi * redline / 60
    local geared = raw / ratios[#ratios] / finalDrive
    local rounded = math.ceil(geared / finalMult)
    return math.floor(rounded * 0.56818181818181812)
end

-- A lower bound, not a promise: it is the time 60 mph takes if every horsepower reached the road
-- with no losses, no traction limit and no shifting. It moves with the two numbers that really
-- decide acceleration - power and weight - which is what makes it useful beside them.
local function ComputeAcceleration()
    local tune = State.tune
    if tune == nil then
        return 0
    end
    local horsepower = tonumber(tune.Horsepower) or 0
    local weight = tonumber(tune.Weight) or 0
    if horsepower <= 0 or weight <= 0 then
        return 0
    end
    local mass = weight * 0.45359237
    local power = horsepower * 745.699872
    local target = 60 * 0.44704
    return math.floor((0.5 * mass * target * target / power) * 10 + 0.5) / 10
end

local function RefreshDerivedEntries()
    for _, entry in ipairs(State.entries) do
        if entry.source == "Derived" then
            local value = entry.compute()
            entry.value = value
            if entry.widget ~= nil and entry.widget.Apply ~= nil then
                pcall(entry.widget.Apply, value)
            end
        end
    end
end

-- Tune fields have no attribute signal. Half a second of polling is enough for a value nothing in
-- the car rewrites per frame, and it catches the fields the chassis itself adjusts at spawn.
local function PollTune()
    for _, entry in ipairs(State.entries) do
        if entry.source == "Motor" then
            local value = entry.getValue()
            if value ~= entry.value then
                entry.value = value
                if entry.widget ~= nil and entry.widget.Apply ~= nil then
                    pcall(entry.widget.Apply, value)
                end
            end
        elseif entry.source == "Derived" then
            local value = entry.compute()
            if value ~= entry.value then
                entry.value = value
                if entry.widget ~= nil and entry.widget.Apply ~= nil then
                    pcall(entry.widget.Apply, value)
                end
            end
        end
    end
end

local function StartTunePolling(token)
    task.spawn(function()
        while State.window ~= nil and State.pollToken == token do
            task.wait(0.5)
            if State.window == nil or State.pollToken ~= token then
                return
            end
            pcall(PollTune)
        end
    end)
end

--=== option sources ========================================================

local EnumOptionsCache = {}
local TireCompoundOptionsCache = nil
local PlateStateOptionsCache = nil

local function EnumOptions(enumType)
    if EnumOptionsCache[enumType] ~= nil then
        return EnumOptionsCache[enumType]
    end
    local names = {}
    for _, item in ipairs(enumType:GetEnumItems()) do
        table.insert(names, item.Name)
    end
    table.sort(names)
    EnumOptionsCache[enumType] = names
    return names
end

local function TireCompoundOptions()
    if TireCompoundOptionsCache ~= nil then
        return TireCompoundOptionsCache
    end
    local options = {}
    local objectStorage = ReplicatedStorage:FindFirstChild("ObjectStorage")
    local wheelEffects = objectStorage and objectStorage:FindFirstChild("WheelFX")
    local tireTextures = wheelEffects and wheelEffects:FindFirstChild("TireTextures")
    if tireTextures ~= nil then
        for _, child in ipairs(tireTextures:GetChildren()) do
            table.insert(options, child.Name)
        end
        table.sort(options)
    end
    TireCompoundOptionsCache = options
    return options
end

local function PlateStateOptions()
    if PlateStateOptionsCache ~= nil then
        return PlateStateOptionsCache
    end
    local options = {}
    local dataModule = ReplicatedStorage:FindFirstChild("DataModule")
    local plateData = dataModule and dataModule:FindFirstChild("PlateData")
    if plateData ~= nil then
        for _, child in ipairs(plateData:GetChildren()) do
            table.insert(options, child.Name)
        end
        table.sort(options)
    end
    PlateStateOptionsCache = options
    return options
end

local function DropdownOptions(key)
    if key == "Dynamics_Drivetrain" then
        return { "AWD", "RWD", "FWD" }
    end
    if key == "Dynamics_FTireCompound" or key == "Dynamics_RTireCompound" then
        local options = TireCompoundOptions()
        if #options > 0 then
            return options
        end
        return nil
    end
    if key == "PlateCode" then
        local options = PlateStateOptions()
        if #options > 0 then
            return options
        end
        return nil
    end
    return nil
end

local SuspensionLimitsCache = nil

local function SuspensionLimits()
    if SuspensionLimitsCache ~= nil then
        return SuspensionLimitsCache
    end
    local limits = {
        Height = 0.32,
        FrontCamber = 10,
        RearCamber = 10,
        FrontOffset = 0.3,
        RearOffset = 0.3,
    }
    local dataModule = ReplicatedStorage:FindFirstChild("DataModule")
    local module = dataModule and dataModule:FindFirstChild("SuspensionLimits")
    if module ~= nil then
        local loaded, required = pcall(require, module)
        if loaded and type(required) == "table" then
            limits = required
        end
    end
    SuspensionLimitsCache = limits
    return limits
end

local function PickTireCompound(preferred)
    local options = TireCompoundOptions()
    for _, name in ipairs(options) do
        if name == preferred then
            return name
        end
    end
    for _, fallback in ipairs({ "Track", "Sport", "All-Season" }) do
        for _, name in ipairs(options) do
            if name == fallback then
                return name
            end
        end
    end
    return nil
end

--=== toasts ================================================================

local ToastLooks = {
    success = { prefix = "[i]", tint = Theme.Text },
    info    = { prefix = "[i]", tint = Theme.Muted },
    error   = { prefix = "[!]", tint = Color3.fromRGB(255, 128, 128) },
}

local function Notify(kind, message)
    local look = ToastLooks[kind] or ToastLooks.info
    if PRINT_LOGS then
        print(string.format("%s [%s] %s", look.prefix, Scope, message))
    end

    if State.window ~= nil then
        State.window:SetStatus(string.upper(message), look.tint)
    end
    if ToastHost == nil or ToastHost.Parent == nil then
        return
    end

    local toast = MonoUI.Sticker(MonoUI.Element {
        ClassName              = "Frame",
        Parent                 = ToastHost,
        Name                   = "Toast",
        BackgroundColor3       = Theme.Surface,
        BackgroundTransparency = 0.12,
        AutomaticSize          = Enum.AutomaticSize.Y,
        Size                   = UDim2.new(1, 0, 0, 0),
        ZIndex                 = 201,
    }, {
        Corner  = "RowRadius",
        Stroke  = "Line",
        Glass   = true,
        Padding = { 7, 10, 7, 12 },
    })

    MonoUI.Texted(toast, {
        Text            = string.format("%s %s", look.prefix, message),
        Tint            = "Text",
        Size            = Theme.Type.Body,
        Bold            = false,
        Size2           = UDim2.new(1, 0, 0, 0),
        ZIndex          = 202,
    })
    local toastLabel = toast:FindFirstChildOfClass("TextLabel")
    toastLabel.TextWrapped   = true
    toastLabel.TextTruncate  = Enum.TextTruncate.None
    toastLabel.AutomaticSize = Enum.AutomaticSize.Y
    toastLabel.TextColor3    = look.tint

    table.insert(ToastList, toast)
    if #ToastList > 5 then
        local oldest = table.remove(ToastList, 1)
        if oldest ~= nil and oldest.Parent ~= nil then
            oldest:Destroy()
        end
    end

    task.delay(ToastLifetime, function()
        if toast.Parent == nil then
            return
        end
        local fadeInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        TweenService:Create(toast, fadeInfo, { BackgroundTransparency = 1 }):Play()
        for _, descendant in ipairs(toast:GetDescendants()) do
            if descendant:IsA("TextLabel") then
                TweenService:Create(descendant, fadeInfo, { TextTransparency = 1 }):Play()
            elseif descendant:IsA("UIStroke") then
                TweenService:Create(descendant, fadeInfo, { Transparency = 1 }):Play()
            end
        end
        task.delay(0.4, function()
            if toast.Parent ~= nil then
                toast:Destroy()
            end
        end)
    end)
end

--=== visual application ====================================================

-- The game's own paint routine (Client.ApplyPaintjob) writes Custom_0 over every part whose name
-- starts with "color" in Body and Misc. The attributes are the same value, so the same rule
-- applies the attribute back onto the car.
local function PaintBodyPart(car, part)
    if not part:IsA("BasePart") then
        return
    end
    local name = string.lower(part.Name)
    local index = 0
    if name ~= "color" then
        index = tonumber(string.match(name, "^color(%d)$"))
    end
    if index == nil then
        return
    end
    local color = car:GetAttribute("PaintColor" .. index)
    if color == nil then
        return
    end
    part.Color = color
    local reflectance = car:GetAttribute("PaintReflectance" .. index)
    if reflectance ~= nil then
        part.Reflectance = reflectance
    end
end

local function PaintContainer(car, container)
    if container == nil then
        return
    end
    for _, descendant in ipairs(container:GetDescendants()) do
        PaintBodyPart(car, descendant)
    end
end

local function ApplyBodyPaint()
    local car = State.car
    if car == nil then
        return
    end
    PaintContainer(car, car:FindFirstChild("Body"))
    PaintContainer(car, car:FindFirstChild("Misc"))
end

local function PaintInteriorPart(car, part)
    if not part:IsA("BasePart") then
        return
    end
    local name = string.lower(part.Name)
    local index = 0
    if name ~= "interiorcolor" then
        index = tonumber(string.match(name, "^interiorcolor(%d)$"))
    end
    if index == nil then
        return
    end
    local color = car:GetAttribute("Int" .. index .. "_Color")
    if color == nil then
        return
    end
    part.Color = color
    local reflectance = car:GetAttribute("Int" .. index .. "_Reflectance")
    local material = car:GetAttribute("Int" .. index .. "_Material")
    local variant = car:GetAttribute("Int" .. index .. "_Variant")
    if reflectance ~= nil then
        part.Reflectance = reflectance
    end
    if typeof(material) == "EnumItem" then
        part.Material = material
    end
    if type(variant) == "string" then
        part.MaterialVariant = variant
    end
    local appearance = part:FindFirstChildOfClass("SurfaceAppearance")
    if appearance ~= nil then
        appearance.Color = color
    end
end

local function ApplyInterior()
    local car = State.car
    if car == nil then
        return
    end
    for _, descendant in ipairs(car:GetDescendants()) do
        PaintInteriorPart(car, descendant)
    end
end

local function PaintBrakeParts(wheels)
    if wheels == nil then
        return
    end
    local color = wheels:GetAttribute("ClassicBrakeColor")
    if color == nil then
        return
    end
    local reflectance = wheels:GetAttribute("ClassicBrakeReflectance")
    local material = wheels:GetAttribute("ClassicBrakeMaterial")
    local variant = wheels:GetAttribute("ClassicBrakeVariant")
    for _, wheel in ipairs(wheels:GetChildren()) do
        local fixed = wheel:FindFirstChild("WheelFixed")
        if fixed ~= nil then
            for _, descendant in ipairs(fixed:GetDescendants()) do
                if descendant:IsA("MeshPart") then
                    local name = descendant.Name
                    if name == "Color" or name == "MeshPart" or name == "Caliper" then
                        descendant.Color = color
                        if reflectance ~= nil then
                            descendant.Reflectance = reflectance
                        end
                        if typeof(material) == "EnumItem" then
                            descendant.Material = material
                        end
                        if type(variant) == "string" then
                            descendant.MaterialVariant = variant
                        end
                    end
                end
            end
        end
    end
end

local function ApplyBrakes()
    PaintBrakeParts(State.wheels)
end

local function PaintRimDecal(car, wheels)
    if car == nil or wheels == nil then
        return
    end
    local texture = car:GetAttribute("RimDecal")
    if type(texture) ~= "string" or texture == "" then
        return
    end

    local function ApplyToRimHolder(rims)
        local decal = rims:FindFirstChild("Decal")
        local decal2 = rims:FindFirstChild("Decal2")
        if decal ~= nil and decal:IsA("Decal") then
            decal.Texture = texture
            decal.Transparency = 0
        end
        if decal2 ~= nil and decal2:IsA("Decal") then
            decal2.Texture = texture
            decal2.Transparency = 0
        end
    end

    for _, wheel in ipairs(wheels:GetChildren()) do
        local parts = wheel:FindFirstChild("Parts")
        local rims = parts and parts:FindFirstChild("Rims")
        if rims ~= nil then
            ApplyToRimHolder(rims)
            rims.Transparency = 1
            local wheelModel = parts:FindFirstChild("Wheels")
            local wheelMesh = wheelModel and wheelModel:FindFirstChild("Wheel")
            if wheelMesh ~= nil and wheelMesh:IsA("BasePart") then
                wheelMesh.Transparency = 0
            end
        end
    end

    local body = car:FindFirstChild("Body")
    local spare = body and body:FindFirstChild("Body")
    local spareRims = spare and spare:FindFirstChild("Spare") and spare.Spare:FindFirstChild("Rims")
    if spareRims ~= nil then
        ApplyToRimHolder(spareRims)
    end
end

local function ApplyRimDecal()
    PaintRimDecal(State.car, State.wheels)
end

local function PaintPlateText(car)
    if car == nil then
        return
    end
    local text = car:GetAttribute("PlateText")
    if type(text) ~= "string" then
        return
    end
    local plateModel = car:FindFirstChild("Body") and car.Body:FindFirstChild("Wisconsin License Plates")
    local holder = plateModel and plateModel:FindFirstChild("Plates")
    if holder == nil then
        return
    end
    for _, plate in ipairs(holder:GetChildren()) do
        local gui = plate:FindFirstChild("SGUI")
        local identifier = gui and gui:FindFirstChild("Identifier")
        if identifier ~= nil and (identifier:IsA("TextBox") or identifier:IsA("TextLabel")) then
            identifier.Text = text
        end
    end
end

local function ApplyPlateText()
    PaintPlateText(State.car)
end

local function HasDisplayEffect(key)
    return string.match(key, "^PaintColor%d$") ~= nil
        or string.match(key, "^PaintReflectance%d$") ~= nil
        or string.match(key, "^Int%d_") ~= nil
        or string.match(key, "^ClassicBrake") ~= nil
        or key == "RimDecal"
        or key == "PlateText"
end

local function ApplyVisuals(key)
    if string.match(key, "^PaintColor%d$") or string.match(key, "^PaintReflectance%d$") then
        ApplyBodyPaint()
        return
    end
    if string.match(key, "^Int%d_") then
        ApplyInterior()
        return
    end
    if key == "RimDecal" then
        ApplyRimDecal()
        return
    end
    if string.match(key, "^ClassicBrake") then
        ApplyBrakes()
        return
    end
    if key == "PlateText" then
        ApplyPlateText()
    end
end

--=== applying a property ===================================================

local function ApplyProperty(entry, value, silent)
    local applied, problem = pcall(function()
        entry.setValue(value)
    end)
    if not applied then
        LogError(string.format("Failed to set %s: %s", entry.id, tostring(problem)))
        if not silent then
            Notify("error", string.format("%s failed: %s", entry.label, tostring(problem)))
        end
        return false
    end

    if entry.source == "Attribute" then
        entry.value = value
        local refreshed, visualProblem = pcall(ApplyVisuals, entry.key)
        if not refreshed then
            LogError(string.format("%s was written but the visual refresh failed: %s", entry.id, tostring(visualProblem)))
            if not silent then
                Notify("error", string.format("%s written, visual failed: %s", entry.label, tostring(visualProblem)))
            end
            return false
        end
    end

    if entry.source == "Motor" then
        entry.value = value
        -- Tune values have no attribute signal, and the poll only refreshes when entry.value
        -- differs from the tune. Applying a preset writes entry.value, so the widget has to be
        -- told directly or the row would keep showing the value the car had before the load.
        if entry.widget ~= nil and entry.widget.Apply ~= nil then
            local drawn = pcall(entry.widget.Apply, value)
            if not drawn then
                LogError(string.format("Could not refresh the editor for %s after applying it", entry.id))
            end
        end
        RefreshDerivedEntries()
    end

    if not silent then
        local hint = ""
        if entry.source == "Motor" then
            hint = " (exit and re-enter the vehicle to apply)"
        elseif ReadAtSpawn(entry.key) then
            hint = " (exit and re-enter the vehicle to apply)"
        end
        Notify("success", string.format("Applied %s = %s%s", entry.label, FormatValue(value), hint))
    end
    return true
end

--=== snapshot ==============================================================

local function SelectedEntries()
    local selected = {}
    for _, entry in ipairs(State.entries) do
        if not entry.readOnly and State.selection[entry.id] ~= false then
            table.insert(selected, entry)
        end
    end
    return selected
end

local function CountSelected()
    return #SelectedEntries()
end

local UpdateSnapshotStatus

local function SaveSelection()
    local selected = SelectedEntries()
    if #selected == 0 then
        Notify("error", "Nothing is ticked to save")
        return
    end
    local values = {}
    for _, entry in ipairs(selected) do
        values[entry.id] = CopyValue(entry.getValue())
    end
    State.snapshot = {
        values  = values,
        count   = #selected,
        savedAt = os.date("%H:%M:%S"),
    }
    LogInfo(string.format("Saved a snapshot of %d properties", #selected))
    Notify("success", string.format("Saved %d properties at %s", #selected, State.snapshot.savedAt))
    UpdateSnapshotStatus()
end

local function RestoreSelection()
    local snapshot = State.snapshot
    if snapshot == nil then
        Notify("error", "No snapshot yet - save one first")
        return
    end
    local selected = SelectedEntries()
    if #selected == 0 then
        Notify("error", "Nothing is ticked to restore")
        return
    end

    local restored, failed, missing = 0, 0, 0
    for _, entry in ipairs(selected) do
        local value = snapshot.values[entry.id]
        if value == nil then
            missing = missing + 1
        elseif ApplyProperty(entry, CopyValue(value), true) then
            restored = restored + 1
        else
            failed = failed + 1
        end
    end

    LogInfo(string.format("Restore finished: %d restored, %d failed, %d not in the snapshot", restored, failed, missing))
    if failed == 0 then
        Notify("success", string.format("Restored %d properties%s", restored, missing > 0 and string.format(" (%d not in the snapshot)", missing) or ""))
        return
    end
    Notify("error", string.format("Restored %d properties, %d failed", restored, failed))
end

--=== header ================================================================

local function ResolveCarIdentity(car)
    local identity = {
        name  = car.Name,
        brand = "",
        trim  = "",
        carId = "",
    }

    local carIdValue = car:FindFirstChild("CarID")
    if carIdValue ~= nil and carIdValue:IsA("StringValue") then
        identity.carId = carIdValue.Value
    end

    local referenceRoot = ReplicatedStorage:FindFirstChild("CarDataReference")
    local node = referenceRoot and identity.carId ~= "" and referenceRoot:FindFirstChild(identity.carId)
    if node == nil then
        return identity
    end

    local trimValue = node:FindFirstChild("TrimName")
    if trimValue ~= nil and trimValue:IsA("StringValue") then
        identity.trim = trimValue.Value
    end

    local carDataValue = node:FindFirstChild("CarData")
    local module = nil
    if carDataValue ~= nil and carDataValue:IsA("ObjectValue") then
        module = carDataValue.Value
    end
    if module == nil then
        return identity
    end

    local required, data = pcall(require, module)
    if not required or type(data) ~= "table" then
        LogError(string.format("CarData for %s could not be read", identity.carId))
        return identity
    end

    identity.name  = tostring(data.VehicleName or identity.name)
    identity.brand = tostring(data.VehicleBrand or "")
    return identity
end

--=== vehicle display =======================================================

-- A copy of the car for the viewport: the geometry of Body, Wheels and Misc only, stripped of
-- everything that drives it and made static so the pointer can spin it.
local function CloneVehicleDisplay(car)
    local display = Instance.new("Model")
    display.Name = "VehicleDisplay"
    for _, name in ipairs({ "Body", "Wheels", "Misc" }) do
        local source = car:FindFirstChild(name)
        if source ~= nil then
            local copy = source:Clone()
            copy.Parent = display
        end
    end
    if #display:GetChildren() == 0 then
        display:Destroy()
        return nil
    end

    for _, descendant in ipairs(display:GetDescendants()) do
        if descendant.Parent == nil then
            continue
        end
        if ViewportBlocklist[descendant.ClassName] then
            descendant:Destroy()
        elseif descendant:IsA("BasePart") then
            descendant.Anchored = true
            descendant.CanCollide = false
            descendant.CanTouch = false
            descendant.CanQuery = false
            descendant.CastShadow = false
        end
    end
    return display
end

local function ApplyDisplayTransform()
    local display = State.viewportDisplay
    local center = State.viewportCenter
    if display == nil or center == nil then
        return
    end
    display:PivotTo(CFrame.new(center) * CFrame.Angles(math.rad(State.viewportPitch), math.rad(State.viewportYaw), 0))
end

local function BuildVehicleDisplay()
    local viewport = State.viewport
    if viewport == nil or viewport.Parent == nil then
        return
    end
    if State.viewportDisplay ~= nil then
        State.viewportDisplay:Destroy()
        State.viewportDisplay = nil
        State.viewportCenter = nil
    end

    local car = State.car
    if car == nil then
        return
    end

    local display = CloneVehicleDisplay(car)
    if display == nil then
        LogError("The vehicle has no Body, Wheels or Misc to display")
        return
    end

    local boundingCFrame, boundingSize = display:GetBoundingBox()
    local center = boundingCFrame.Position
    local radius = math.max(boundingSize.Magnitude / 2, 1)
    display.WorldPivot = CFrame.new(center)
    display.Parent = viewport

    if viewport.CurrentCamera ~= nil then
        viewport.CurrentCamera:Destroy()
    end
    local camera = Instance.new("Camera")
    camera.Name = "VehicleDisplayCamera"
    camera.FieldOfView = 35
    camera.CFrame = CFrame.lookAt(
        center + Vector3.new(radius * 1.15, radius * 0.55, radius * 1.55),
        center
    )
    camera.Parent = viewport
    viewport.CurrentCamera = camera

    State.viewportDisplay = display
    State.viewportCenter = center
    ApplyDisplayTransform()
    LogInfo(string.format("Vehicle display built from %d instances", #display:GetDescendants()))
end

function ScheduleViewportRefresh()
    if State.viewportRefresh then
        return
    end
    State.viewportRefresh = true
    task.delay(0.2, function()
        State.viewportRefresh = false
        BuildVehicleDisplay()
    end)
end

--=== preset storage ========================================================

local function CarIdOf(car)
    if car == nil then
        return ""
    end
    local value = car:FindFirstChild("CarID")
    if value ~= nil and value:IsA("StringValue") then
        return value.Value
    end
    return ""
end

local function CountPresetValues(preset)
    local count = 0
    for _ in pairs(preset.values or {}) do
        count = count + 1
    end
    return count
end

local function SerializeValue(value)
    local kind = typeof(value)
    if kind == "number" or kind == "string" or kind == "boolean" then
        return { t = string.sub(kind, 1, 1), v = value }
    end
    if kind == "Color3" then
        return { t = "c", r = value.R, g = value.G, b = value.B }
    end
    if kind == "EnumItem" then
        return { t = "e", e = tostring(value.EnumType), n = value.Name }
    end
    if kind == "table" then
        local items = {}
        for index, item in ipairs(value) do
            local serialized = SerializeValue(item)
            if serialized ~= nil then
                items[index] = serialized
            end
        end
        return { t = "t", v = items }
    end
    return nil
end

local function DeserializeValue(data)
    if type(data) ~= "table" or type(data.t) ~= "string" then
        return nil
    end
    if data.t == "n" then
        return tonumber(data.v)
    end
    if data.t == "s" then
        return type(data.v) == "string" and data.v or nil
    end
    if data.t == "b" then
        if type(data.v) == "boolean" then
            return data.v
        end
        return nil
    end
    if data.t == "c" then
        local red, green, blue = tonumber(data.r), tonumber(data.g), tonumber(data.b)
        if red == nil or green == nil or blue == nil then
            return nil
        end
        return Color3.new(math.clamp(red, 0, 1), math.clamp(green, 0, 1), math.clamp(blue, 0, 1))
    end
    if data.t == "e" then
        local enumName = tostring(data.e)
        enumName = string.match(enumName, "^Enum%.(.+)$") or enumName
        local enumType = Enum[enumName]
        if enumType == nil then
            return nil
        end
        return enumType[tostring(data.n)]
    end
    if data.t == "t" then
        local values = {}
        for _, item in ipairs(data.v or {}) do
            local value = DeserializeValue(item)
            if value == nil then
                return nil
            end
            table.insert(values, value)
        end
        return values
    end
    return nil
end

local function CapturePresetValues()
    local values = {}
    local skipped = 0
    for _, entry in ipairs(State.entries) do
        if not entry.readOnly then
            local serialized = SerializeValue(entry.getValue())
            if serialized ~= nil then
                values[entry.id] = serialized
            else
                skipped = skipped + 1
            end
        end
    end
    return values, skipped
end

local function PresetNeedsReentry(preset)
    for id in pairs(preset.values or {}) do
        if string.sub(id, 1, 6) == "Motor."
            or string.find(id, "Dynamics_", 1, true) ~= nil
            or string.find(id, "SuspensionTune_", 1, true) ~= nil
        then
            return true
        end
    end
    return false
end

local function NormalizePresets(list)
    local presets = {}
    local ids = {}
    for _, preset in ipairs(list or {}) do
        if type(preset) == "table" then
            local id = type(preset.id) == "string" and preset.id or nil
            local name = type(preset.name) == "string" and preset.name or nil
            local carId = type(preset.carId) == "string" and preset.carId or nil
            if id ~= nil and name ~= nil and carId ~= nil and type(preset.values) == "table" and not ids[id] then
                ids[id] = true
                table.insert(presets, {
                    id       = id,
                    name     = name,
                    carId    = carId,
                    carName  = type(preset.carName) == "string" and preset.carName or "",
                    trim     = type(preset.trim) == "string" and preset.trim or "",
                    autoLoad = preset.autoLoad == true,
                    savedAt  = tonumber(preset.savedAt) or 0,
                    values   = preset.values,
                    drive    = type(preset.drive) == "table" and preset.drive or nil,
                })
            end
        end
    end

    -- One auto-load preset per car, even if the file was edited by hand.
    local autoByCar = {}
    for _, preset in ipairs(presets) do
        if preset.autoLoad then
            if autoByCar[preset.carId] ~= nil then
                preset.autoLoad = false
            else
                autoByCar[preset.carId] = preset
            end
        end
    end
    return presets
end

local function PresetsForCar(carId)
    local list = {}
    for _, preset in ipairs(State.presets) do
        if preset.carId == carId then
            table.insert(list, preset)
        end
    end
    table.sort(list, function(left, right)
        if left.autoLoad ~= right.autoLoad then
            return left.autoLoad
        end
        return string.lower(left.name) < string.lower(right.name)
    end)
    return list
end

local function FindAutoPreset(carId)
    for _, preset in ipairs(State.presets) do
        if preset.carId == carId and preset.autoLoad then
            return preset
        end
    end
    return nil
end

local function ReadPresetsFile()
    if type(isfile) ~= "function" or type(readfile) ~= "function" then
        LogError("The executor has no file API - presets will not persist")
        return
    end
    local existsOk, exists = pcall(isfile, PresetFilePath)
    if not existsOk or not exists then
        LogInfo("No preset file yet at " .. PresetFilePath)
        return
    end
    local readOk, contents = pcall(readfile, PresetFilePath)
    if not readOk or type(contents) ~= "string" then
        LogError("Could not read " .. PresetFilePath .. ": " .. tostring(contents))
        return
    end
    local decodeOk, decoded = pcall(function()
        return HttpService:JSONDecode(contents)
    end)
    if not decodeOk or type(decoded) ~= "table" then
        LogError("Preset file is not valid JSON: " .. tostring(decoded))
        return
    end
    local list = decoded.presets
    if type(list) ~= "table" then
        list = decoded
    end
    State.presets = NormalizePresets(list)
    if type(decoded.drive) == "table" then
        ApplyDriveSettings(decoded.drive, true)
    end
    LogInfo(string.format("Loaded %d presets from %s", #State.presets, PresetFilePath))
end

local function WritePresetsFile()
    if type(writefile) ~= "function" then
        LogError("The executor has no writefile - presets are session-only")
        return false
    end
    local encodeOk, json = pcall(function()
        return HttpService:JSONEncode({
            version = 1,
            drive   = CaptureDriveSettings(),
            presets = State.presets,
        })
    end)
    if not encodeOk then
        LogError("Could not encode presets: " .. tostring(json))
        return false
    end
    local writeOk, problem = pcall(writefile, PresetFilePath, json)
    if not writeOk then
        LogError("Could not write presets: " .. tostring(problem))
        return false
    end
    LogInfo(string.format("Saved %d presets to %s", #State.presets, PresetFilePath))
    return true
end

local DriveSavePending = false
SaveDriveConfigSoon = function()
    if DriveSavePending then
        return
    end
    DriveSavePending = true
    task.delay(0.5, function()
        DriveSavePending = false
        WritePresetsFile()
    end)
end

local function NewPresetId(carId)
    local base = string.format("%s-%d", carId, os.time())
    local id = base
    local counter = 1
    while true do
        local taken = false
        for _, preset in ipairs(State.presets) do
            if preset.id == id then
                taken = true
                break
            end
        end
        if not taken then
            return id
        end
        counter = counter + 1
        id = base .. "-" .. counter
    end
end

local function ReleaseVehicleInputs()
    if State.content == nil then
        return
    end
    for _, descendant in ipairs(State.content:GetDescendants()) do
        if descendant:IsA("TextBox") and descendant:IsFocused() then
            pcall(function()
                descendant:ReleaseFocus()
            end)
        end
    end
end

local function ApplyPreset(preset, silent)
    -- A focused textbox deliberately ignores background refreshes while the caret is in it: the
    -- poll and the attribute signals both skip it. Loading a preset is not a background refresh,
    -- so let go of the caret first and every row gets to draw the value it just received.
    ReleaseVehicleInputs()

    local applied, failed, missing = 0, 0, 0
    for _, entry in ipairs(State.entries) do
        if not entry.readOnly then
            local data = preset.values[entry.id]
            if data == nil then
                missing = missing + 1
            else
                local value = DeserializeValue(data)
                if value ~= nil and ApplyProperty(entry, value, true) then
                    applied = applied + 1
                else
                    failed = failed + 1
                end
            end
        end
    end

    local driveApplied = false
    if type(preset.drive) == "table" then
        driveApplied = ApplyDriveSettings(preset.drive, true)
    end

    local driveNote = driveApplied and " + Drive" or ""
    local reentry = PresetNeedsReentry(preset) and " · re-enter for chassis values" or ""
    if not silent then
        if failed == 0 then
            Notify("success", string.format("Loaded preset '%s' (%d properties%s)%s", preset.name, applied, driveNote, reentry))
        else
            Notify("error", string.format("Preset '%s': %d applied, %d failed", preset.name, applied, failed))
        end
    end
    LogInfo(string.format("Preset '%s': %d applied, %d failed, %d not in preset", preset.name, applied, failed, missing))
    return applied, failed
end

local function MaybeAutoLoad()
    local car = State.car
    if car == nil or State.autoLoadedCar == car then
        return
    end
    State.autoLoadedCar = car
    local carId = CarIdOf(car)
    if carId == "" then
        return
    end
    local preset = FindAutoPreset(carId)
    if preset == nil then
        return
    end

    local applied, failed = ApplyPreset(preset, true)
    local driveNote = type(preset.drive) == "table" and " + Drive" or ""
    local reentry = PresetNeedsReentry(preset) and " · re-enter for chassis values" or ""
    if failed == 0 then
        Notify("success", string.format("Auto-loaded preset '%s' (%d properties%s)%s", preset.name, applied, driveNote, reentry))
    else
        Notify("error", string.format("Auto-load '%s': %d applied, %d failed", preset.name, applied, failed))
    end
end

-- A preview of a preset: a clone of the current display with that preset's paint, interior, brakes,
-- rims and plate laid over it. The live car is never touched.
local function StylePresetPreview(display, preset)
    local wheels = display:FindFirstChild("Wheels")
    for id, data in pairs(preset.values) do
        local targetName, key = string.match(id, "^(%w+)%.(.+)$")
        local value = DeserializeValue(data)
        if value ~= nil then
            if targetName == "Car" then
                display:SetAttribute(key, value)
            elseif targetName == "Wheels" and wheels ~= nil then
                wheels:SetAttribute(key, value)
            end
        end
    end
    PaintContainer(display, display:FindFirstChild("Body"))
    PaintContainer(display, display:FindFirstChild("Misc"))
    for _, descendant in ipairs(display:GetDescendants()) do
        PaintInteriorPart(display, descendant)
    end
    PaintBrakeParts(wheels)
    PaintRimDecal(display, wheels)
    PaintPlateText(display)
end

local function BuildPresetPreview(viewport, preset)
    local template = State.viewportDisplay
    if template == nil then
        return false
    end

    local display = template:Clone()
    display.Name = "PresetPreview"
    local styled, problem = pcall(StylePresetPreview, display, preset)
    if not styled then
        LogError("Could not style a preset preview: " .. tostring(problem))
    end

    local boundingCFrame, boundingSize = display:GetBoundingBox()
    local center = boundingCFrame.Position
    local radius = math.max(boundingSize.Magnitude / 2, 1)
    display.WorldPivot = CFrame.new(center)
    display:PivotTo(CFrame.new(center) * CFrame.Angles(math.rad(8), math.rad(25), 0))
    display.Parent = viewport

    local camera = Instance.new("Camera")
    camera.Name = "PresetPreviewCamera"
    camera.FieldOfView = 35
    camera.CFrame = CFrame.lookAt(center + Vector3.new(radius * 1.15, radius * 0.55, radius * 1.55), center)
    camera.Parent = viewport
    viewport.CurrentCamera = camera
    return true
end

local function RenderHeader()
    local header = State.headerRow
    if header == nil then
        return
    end
    for _, child in ipairs(header:GetChildren()) do
        if child:IsA("GuiObject") then
            child:Destroy()
        end
    end
    State.viewport = nil
    State.viewportDisplay = nil
    State.viewportCenter = nil

    local car = State.car
    if car == nil then
        MonoUI.Texted(header, {
            Text     = "NO VEHICLE SPAWNED",
            Size     = Theme.Type.Title,
            Tint     = "Text",
            Position = UDim2.fromOffset(14, 22),
            Size2    = UDim2.new(1, -28, 0, 24),
            ZIndex   = 3,
        })
        MonoUI.Texted(header, {
            Text     = "Spawn a vehicle and its properties appear here",
            Size     = Theme.Type.Body,
            Tint     = "Muted",
            Bold     = false,
            Position = UDim2.fromOffset(14, 50),
            Size2    = UDim2.new(1, -28, 0, 20),
            ZIndex   = 3,
        })
        return
    end

    local identity = ResolveCarIdentity(car)
    local subtitleParts = {}
    if identity.brand ~= "" then
        table.insert(subtitleParts, identity.brand)
    end
    if identity.trim ~= "" then
        table.insert(subtitleParts, identity.trim)
    end
    if identity.carId ~= "" then
        table.insert(subtitleParts, "ID " .. identity.carId)
    end
    local subtitle = #subtitleParts > 0 and table.concat(subtitleParts, " · ") or car.Name

    local container = MonoUI.Sticker(MonoUI.Element {
        ClassName              = "Frame",
        Parent                 = header,
        Name                   = "VehicleDisplay",
        BackgroundColor3       = Theme.Well,
        BackgroundTransparency = 0.35,
        Size                   = UDim2.new(0, 306, 0, 138),
        Position               = UDim2.new(1, -312, 0, 6),
        ZIndex                 = 2,
    }, { Corner = "RowRadius", Stroke = "Line", Glass = true })

    local viewport = MonoUI.Element {
        ClassName             = "ViewportFrame",
        Parent                = container,
        Name                  = "VehicleViewport",
        BackgroundTransparency = 1,
        Size                  = UDim2.new(1, -12, 1, -12),
        Position              = UDim2.fromOffset(6, 6),
        Ambient               = Color3.fromRGB(180, 180, 180),
        LightColor            = Color3.fromRGB(255, 255, 255),
        LightDirection        = Vector3.new(-0.4, -0.8, -0.5),
        ZIndex                = 3,
    }
    State.viewport = viewport

    local overlay = MonoUI.Element {
        ClassName             = "TextButton",
        Parent                = container,
        Name                  = "VehicleDrag",
        BackgroundTransparency = 1,
        AutoButtonColor       = false,
        Selectable            = false,
        Text                  = "",
        Size                  = UDim2.new(1, -12, 1, -12),
        Position              = UDim2.fromOffset(6, 6),
        ZIndex                = 5,
    }
    overlay.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        ViewportDrag.active = true
        ViewportDrag.pointer = input.UserInputType
        ViewportDrag.last = Vector2.new(input.Position.X, input.Position.Y)
    end)
    overlay.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            ViewportDrag.active = false
            ViewportDrag.pointer = nil
        end
    end)

    BuildVehicleDisplay()

    MonoUI.Texted(header, {
        Text     = identity.name,
        Size     = Theme.Type.Title + 2,
        Tint     = "Text",
        Position = UDim2.fromOffset(14, 14),
        Size2    = UDim2.new(1, -330, 0, 24),
        ZIndex   = 3,
    })
    MonoUI.Texted(header, {
        Text     = subtitle,
        Size     = Theme.Type.Body,
        Tint     = "Muted",
        Bold     = false,
        Position = UDim2.fromOffset(14, 42),
        Size2    = UDim2.new(1, -330, 0, 18),
        ZIndex   = 3,
    })
    MonoUI.Texted(header, {
        Text     = string.format("%d properties · %s", #State.entries, identity.carId ~= "" and identity.carId or car.Name),
        Size     = Theme.Type.Support,
        Tint     = "Muted",
        Bold     = false,
        Position = UDim2.fromOffset(14, 66),
        Size2    = UDim2.new(1, -330, 0, 16),
        ZIndex   = 3,
    })
    MonoUI.Texted(header, {
        Text     = "DRAG TO ROTATE",
        Size     = Theme.Type.Support,
        Tint     = "Muted",
        Bold     = false,
        Position = UDim2.fromOffset(14, 112),
        Size2    = UDim2.new(1, -330, 0, 16),
        ZIndex   = 3,
    })
end

--=== property editors ======================================================

local function CreateBooleanEditor(row, entry)
    local control = MonoUI.Switch {
        Parent   = row,
        Name     = entry.key,
        Caption  = "",
        Size     = UDim2.new(0.48, 0, 0, 24),
        Position = UDim2.new(0.52, 0, 0, 3),
        Value    = entry.value == true,
        OnChange = function(value)
            ApplyProperty(entry, value)
        end,
    }
    return {
        Apply = function(value)
            control.Set(value == true)
        end,
    }
end

local function CreateNumberEditor(row, entry)
    local control
    control = MonoUI.Input {
        Parent          = row,
        Name            = entry.key,
        Size            = UDim2.new(0.48, 0, 0, 24),
        Position        = UDim2.new(0.52, 0, 0, 3),
        Text            = FormatValue(entry.value),
        SubmitOnEnter   = true,
        PlaceholderText = "number",
        OnSubmit        = function(text)
            local value = tonumber(text)
            if value == nil or value ~= value or value == math.huge or value == -math.huge then
                Notify("error", string.format("%s needs a number", entry.label))
                control.Text = FormatValue(entry.getValue())
                return
            end
            ApplyProperty(entry, value)
        end,
    }
    return {
        Apply = function(value)
            if control:IsFocused() then
                return
            end
            control.Text = FormatValue(value)
        end,
    }
end

local function CreateTextEditor(row, entry)
    local control
    control = MonoUI.Input {
        Parent          = row,
        Name            = entry.key,
        Size            = UDim2.new(0.48, 0, 0, 24),
        Position        = UDim2.new(0.52, 0, 0, 3),
        Text            = FormatValue(entry.value),
        SubmitOnEnter   = true,
        PlaceholderText = "text",
        OnSubmit        = function(text)
            ApplyProperty(entry, text)
        end,
    }
    return {
        Apply = function(value)
            if control:IsFocused() then
                return
            end
            control.Text = FormatValue(value)
        end,
    }
end

local function CreateColorEditor(row, entry)
    local picker = MonoUI.ColorPicker {
        Parent   = row,
        Name     = entry.key .. "Picker",
        Size     = UDim2.fromOffset(24, 24),
        Position = UDim2.new(0.52, 0, 0, 3),
        Value    = entry.value,
        Title    = entry.label,
        OnChange = function(color)
            ApplyProperty(entry, color)
        end,
    }

    local control
    control = MonoUI.Input {
        Parent          = row,
        Name            = entry.key,
        Size            = UDim2.new(0.48, -32, 0, 24),
        Position        = UDim2.new(0.52, 30, 0, 3),
        Text            = ColorToHex(entry.value),
        SubmitOnEnter   = true,
        PlaceholderText = "#RRGGBB",
        OnSubmit        = function(text)
            local color = ParseColor(text)
            if color == nil then
                Notify("error", string.format("%s needs #RRGGBB or R,G,B", entry.label))
                local current = entry.getValue()
                if typeof(current) == "Color3" then
                    control.Text = ColorToHex(current)
                end
                return
            end
            ApplyProperty(entry, color)
        end,
    }

    return {
        Apply = function(value)
            if typeof(value) ~= "Color3" then
                return
            end
            picker.Set(value)
            if not control:IsFocused() then
                control.Text = ColorToHex(value)
            end
        end,
    }
end

local function CreateChoiceEditor(row, entry, options)
    local control = MonoUI.Select {
        Parent   = row,
        Name     = entry.key,
        Caption  = "",
        Size     = UDim2.new(0.48, 0, 0, 26),
        Position = UDim2.new(0.52, 0, 0, 2),
        Options  = options,
        Value    = FormatValue(entry.value),
        OnSelect = function(option)
            ApplyProperty(entry, option)
        end,
    }
    local menu = control.Frame:FindFirstChild("Menu")
    if menu ~= nil then
        table.insert(State.selectMenus, menu)
    end
    return {
        Apply = function(value)
            control.Set(FormatValue(value))
        end,
    }
end

local function CreateEnumEditor(row, entry)
    local enumType = entry.value.EnumType
    local options = EnumOptions(enumType)
    local control = MonoUI.Select {
        Parent   = row,
        Name     = entry.key,
        Caption  = "",
        Size     = UDim2.new(0.48, 0, 0, 26),
        Position = UDim2.new(0.52, 0, 0, 2),
        Options  = options,
        Value    = FormatValue(entry.value),
        OnSelect = function(option)
            local item = enumType[option]
            if item == nil then
                Notify("error", string.format("%s is not a %s", option, tostring(enumType)))
                return
            end
            ApplyProperty(entry, item)
        end,
    }
    local menu = control.Frame:FindFirstChild("Menu")
    if menu ~= nil then
        table.insert(State.selectMenus, menu)
    end
    return {
        Apply = function(value)
            control.Set(FormatValue(value))
        end,
    }
end

local function CreateListEditor(row, entry)
    local control
    control = MonoUI.Input {
        Parent          = row,
        Name            = entry.key,
        Size            = UDim2.new(0.48, 0, 0, 24),
        Position        = UDim2.new(0.52, 0, 0, 3),
        Text            = FormatList(entry.value),
        SubmitOnEnter   = true,
        PlaceholderText = "numbers, comma separated",
        OnSubmit        = function(text)
            local list = ParseList(text)
            if list == nil then
                Notify("error", string.format("%s needs comma-separated numbers", entry.label))
                control.Text = FormatList(entry.getValue())
                return
            end
            ApplyProperty(entry, list)
        end,
    }
    return {
        Apply = function(value)
            if control:IsFocused() or type(value) ~= "table" then
                return
            end
            control.Text = FormatList(value)
        end,
    }
end

local function CreateReadOnlyEditor(row, entry)
    local label = MonoUI.Texted(row, {
        Text     = FormatValue(entry.value),
        Size     = Theme.Type.Body,
        Tint     = "Muted",
        Bold     = false,
        X        = Enum.TextXAlignment.Center,
        Position = UDim2.new(0.52, 0, 0, 0),
        Size2    = UDim2.new(0.48, 0, 1, 0),
        ZIndex   = 3,
    })
    return {
        Apply = function(value)
            label.Text = FormatValue(value)
        end,
    }
end

local function CreateEditor(row, entry)
    if entry.readOnly then
        return CreateReadOnlyEditor(row, entry)
    end
    if entry.kind == "List" then
        return CreateListEditor(row, entry)
    end
    if entry.kind == "Boolean" then
        return CreateBooleanEditor(row, entry)
    end
    if entry.kind == "Color" then
        return CreateColorEditor(row, entry)
    end
    if entry.kind == "Enum" then
        return CreateEnumEditor(row, entry)
    end
    if entry.kind == "Number" then
        return CreateNumberEditor(row, entry)
    end
    if entry.kind == "String" then
        local options = DropdownOptions(entry.key)
        if options ~= nil then
            return CreateChoiceEditor(row, entry, options)
        end
        return CreateTextEditor(row, entry)
    end
    return CreateReadOnlyEditor(row, entry)
end

local function CreatePropertyRow(parent, order, entry)
    local row = MonoUI.Row(parent, order, RowHeight)
    MonoUI.Help {
        Parent   = row,
        Position = UDim2.fromOffset(0, 7),
        Title    = entry.label,
        Text     = entry.help,
    }
    MonoUI.Texted(row, {
        Text     = entry.label,
        Size     = Theme.Type.Body,
        Tint     = "Text",
        Bold     = false,
        Position = UDim2.fromOffset(20, 0),
        Size2    = UDim2.new(0.50, -24, 1, 0),
        ZIndex   = 3,
    })

    local widget = CreateEditor(row, entry)
    entry.widget = widget

    if entry.subscribe == nil then
        return
    end

    local connection = entry.subscribe(function()
        local value = entry.getValue()
        if value == nil or widget.Apply == nil then
            return
        end
        local applied = pcall(widget.Apply, value)
        if not applied then
            LogError(string.format("Could not refresh the editor for %s", entry.id))
        end
        if HasDisplayEffect(entry.key) then
            ScheduleViewportRefresh()
        end
    end)
    table.insert(State.rowConnections, connection)
end

local function AttributeEntry(target, targetName, key, value)
    local kind = KindOf(value)
    local group = GroupOf(key)
    return {
        id         = targetName .. "." .. key,
        key        = key,
        label      = key,
        target     = target,
        targetName = targetName,
        source     = "Attribute",
        kind       = kind,
        value      = value,
        group      = group,
        help       = PropertyHelp(key, group, kind),
        getValue   = function()
            return target:GetAttribute(key)
        end,
        setValue   = function(newValue)
            target:SetAttribute(key, newValue)
        end,
        subscribe  = function(callback)
            return target:GetAttributeChangedSignal(key):Connect(callback)
        end,
    }
end

local function TuneEntry(tune, spec, order)
    local value = tune[spec.key]
    return {
        id        = "Motor." .. spec.key,
        key       = spec.key,
        label     = spec.label or spec.key,
        tune      = tune,
        source    = "Motor",
        kind      = spec.kind or KindOf(value),
        value     = value,
        group     = "Motor",
        order     = order,
        help      = MotorHelp[spec.key] or GroupHelp.Motor,
        getValue  = function()
            return tune[spec.key]
        end,
        setValue  = function(newValue)
            tune[spec.key] = newValue
        end,
    }
end

local function DerivedEntry(key, label, compute, order)
    return {
        id       = "Motor." .. key,
        key      = key,
        label    = label,
        source   = "Derived",
        kind     = "Number",
        value    = compute(),
        group    = "Motor",
        order    = order,
        readOnly = true,
        compute  = compute,
        getValue = compute,
        help     = DerivedHelp[key] or GroupHelp.Motor,
    }
end

local function CollectEntries()
    local entries = {}

    local function Collect(target, targetName)
        if target == nil then
            return
        end
        for key, value in pairs(target:GetAttributes()) do
            table.insert(entries, AttributeEntry(target, targetName, key, value))
        end
    end

    Collect(State.car, "Car")
    Collect(State.wheels, "Wheels")

    if State.tune ~= nil then
        table.insert(entries, DerivedEntry("MaxSpeed", "Max speed (speedometer mph)", ComputeMaxSpeed, 1))
        table.insert(entries, DerivedEntry("Acceleration", "Acceleration (0-60 ideal, s)", ComputeAcceleration, 2))
        for index, spec in ipairs(MotorFields) do
            if State.tune[spec.key] ~= nil then
                table.insert(entries, TuneEntry(State.tune, spec, index + 2))
            end
        end
    end

    table.sort(entries, function(left, right)
        local leftRank  = GroupRank[left.group] or 99
        local rightRank = GroupRank[right.group] or 99
        if leftRank ~= rightRank then
            return leftRank < rightRank
        end
        if left.group == "Motor" then
            return (left.order or 0) < (right.order or 0)
        end
        return left.key < right.key
    end)
    return entries
end

local function StructureSignature()
    local keys = {}
    local function Collect(target, prefix)
        if target == nil then
            return
        end
        for key in pairs(target:GetAttributes()) do
            table.insert(keys, prefix .. "." .. key)
        end
    end
    Collect(State.car, "Car")
    Collect(State.wheels, "Wheels")
    table.sort(keys)
    return table.concat(keys, "|")
end

local function RenderPropertyList()
    local list = State.listFrame
    if list == nil then
        return
    end

    for _, connection in ipairs(State.rowConnections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    State.rowConnections = {}

    for _, menu in ipairs(State.selectMenus) do
        pcall(function()
            menu:Destroy()
        end)
    end
    State.selectMenus = {}

    for _, child in ipairs(list:GetChildren()) do
        if child:IsA("GuiObject") then
            child:Destroy()
        end
    end

    if #State.entries == 0 then
        MonoUI.Texted(list, {
            Text        = State.car == nil and "Spawn a vehicle to edit its properties" or "This vehicle exposes no attributes",
            Size        = Theme.Type.Body,
            Tint        = "Muted",
            Bold        = false,
            Size2       = UDim2.new(1, 0, 0, 24),
            LayoutOrder = 1,
        })
        return
    end

    local order = 0
    local currentGroup = nil
    for _, entry in ipairs(State.entries) do
        if entry.group ~= currentGroup then
            currentGroup = entry.group
            order = order + 1
            MonoUI.Heading(list, order, currentGroup)
            if currentGroup == "Motor" then
                order = order + 1
                MonoUI.Texted(list, {
                    Text        = "Motor changes apply after you exit and re-enter the vehicle · top two rows derived",
                    Size        = Theme.Type.Support,
                    Tint        = "Muted",
                    Bold        = false,
                    Size2       = UDim2.new(1, 0, 0, 14),
                    LayoutOrder = order,
                    ZIndex      = 3,
                })
            end
        end
        order = order + 1
        CreatePropertyRow(list, order, entry)
    end
end

--=== selection panel =======================================================

local function CreateCheckboxRow(parent, order, entry)
    local row = MonoUI.Element {
        ClassName              = "TextButton",
        Parent                 = parent,
        Name                   = entry.id,
        AutoButtonColor        = false,
        Text                   = "",
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, 0, 24),
        LayoutOrder            = order,
        ZIndex                 = 2,
    }

    local box = MonoUI.Sticker(MonoUI.Element {
        ClassName              = "Frame",
        Parent                 = row,
        Name                   = "Box",
        BackgroundColor3       = Theme.Well,
        BackgroundTransparency = Theme.WellAlpha,
        Size                   = UDim2.fromOffset(14, 14),
        Position               = UDim2.new(0, 2, 0.5, -7),
        ZIndex                 = 3,
    }, { Corner = 4, Stroke = "Line" })

    local mark = MonoUI.Element {
        ClassName        = "Frame",
        Parent           = box,
        Name             = "Mark",
        BackgroundColor3 = Theme.Text,
        BorderSizePixel  = 0,
        Size             = UDim2.fromOffset(8, 8),
        Position         = UDim2.new(0.5, -4, 0.5, -4),
        Visible          = false,
        ZIndex           = 4,
    }
    MonoUI.Element {
        ClassName    = "UICorner",
        Parent       = mark,
        CornerRadius = UDim.new(0, 2),
    }

    MonoUI.Texted(row, {
        Text     = string.format("%s · %s", entry.group, entry.label),
        Size     = Theme.Type.Body,
        Tint     = "Text",
        Bold     = false,
        Position = UDim2.fromOffset(24, 0),
        Size2    = UDim2.new(1, -28, 1, 0),
        ZIndex   = 3,
    })

    local function Refresh()
        local selected = State.selection[entry.id] ~= false
        mark.Visible = selected
        row.BackgroundTransparency = selected and 0.94 or 1
    end

    row.MouseButton1Click:Connect(function()
        State.selection[entry.id] = not (State.selection[entry.id] ~= false)
        Refresh()
        UpdateSnapshotStatus()
    end)

    Refresh()
    table.insert(State.checkboxRefreshers, Refresh)
end

local function SetAllSelected(selected)
    for _, entry in ipairs(State.entries) do
        if not entry.readOnly then
            State.selection[entry.id] = selected
        end
    end
    for _, refresh in ipairs(State.checkboxRefreshers) do
        refresh()
    end
    UpdateSnapshotStatus()
end

local function SelectableCount()
    local count = 0
    for _, entry in ipairs(State.entries) do
        if not entry.readOnly then
            count = count + 1
        end
    end
    return count
end

function UpdateSnapshotStatus()
    local label = State.panelStatus
    if label == nil then
        return
    end
    local parts = { string.format("%d of %d properties selected", CountSelected(), SelectableCount()) }
    if State.snapshot ~= nil then
        table.insert(parts, string.format("snapshot: %d properties at %s", State.snapshot.count, State.snapshot.savedAt))
    else
        table.insert(parts, "no snapshot saved yet")
    end
    label.Text = table.concat(parts, " · ")
end

local function RenderSnapshotPanel()
    local panel = State.panelFrame
    if panel == nil then
        return
    end

    for _, child in ipairs(panel:GetChildren()) do
        if child:IsA("GuiObject") then
            child:Destroy()
        end
    end
    State.checkboxRefreshers = {}
    State.panelStatus = nil

    if not State.panelOpen then
        panel.Visible = false
        panel.Size = UDim2.new(1, 0, 0, 0)
        return
    end

    panel.Visible = true
    panel.Size = UDim2.new(1, 0, 0, 0)

    local order = 0
    local function NextOrder()
        order = order + 1
        return order
    end

    local selectRow = MonoUI.Row(panel, NextOrder(), 28)
    local selectCell = MonoUI.Columns(selectRow, 2, 6, 26)
    MonoUI.Button {
        Parent  = selectRow,
        Caption = "Select All",
        Size    = selectCell,
        Order   = 1,
        OnClick = function()
            SetAllSelected(true)
        end,
    }
    MonoUI.Button {
        Parent  = selectRow,
        Caption = "Unselect All",
        Size    = selectCell,
        Order   = 2,
        OnClick = function()
            SetAllSelected(false)
        end,
    }

    MonoUI.Heading(panel, NextOrder(), "Properties to save / restore")

    local selectionScroller = MonoUI.Element {
        ClassName              = "ScrollingFrame",
        Parent                 = panel,
        Name                   = "Selection",
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        ScrollBarThickness     = 4,
        Size                   = UDim2.new(1, 0, 0, SelectionListSize),
        CanvasSize             = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize    = Enum.AutomaticSize.Y,
        LayoutOrder            = NextOrder(),
        ZIndex                 = 2,
    }
    MonoUI.Element {
        ClassName = "UIListLayout",
        Parent    = selectionScroller,
        Padding   = UDim.new(0, 2),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }

    if #State.entries == 0 then
        MonoUI.Texted(selectionScroller, {
            Text        = "No properties to list",
            Size        = Theme.Type.Body,
            Tint        = "Muted",
            Bold        = false,
            Size2       = UDim2.new(1, 0, 0, 24),
            LayoutOrder = 1,
        })
    else
        local checkboxOrder = 0
        for _, entry in ipairs(State.entries) do
            if not entry.readOnly then
                checkboxOrder = checkboxOrder + 1
                CreateCheckboxRow(selectionScroller, checkboxOrder, entry)
            end
        end
    end

    local actionRow = MonoUI.Row(panel, NextOrder(), 28)
    local actionCell = MonoUI.Columns(actionRow, 2, 6, 26)
    MonoUI.Button {
        Parent  = actionRow,
        Caption = "Save Selected",
        Size    = actionCell,
        Order   = 1,
        OnClick = SaveSelection,
    }
    MonoUI.Button {
        Parent  = actionRow,
        Caption = "Restore Selected",
        Size    = actionCell,
        Order   = 2,
        OnClick = RestoreSelection,
    }

    State.panelStatus = MonoUI.Texted(panel, {
        Text        = "",
        Size        = Theme.Type.Support,
        Tint        = "Muted",
        Bold        = false,
        Size2       = UDim2.new(1, 0, 0, 16),
        LayoutOrder = NextOrder(),
    })
    UpdateSnapshotStatus()
end

--=== preset interface =====================================================

local RenderPresets

-- Which tab is in front, asked of the window rather than tracked in a second flag: the tab strip
-- and a preset row both live inside the same window, and only the window knows which is showing.
local function PresetsIsActive()
    return State.window ~= nil and State.presetsTab ~= nil and State.window.active == State.presetsTab
end

local function RequestPresetRender()
    if PresetsIsActive() and RenderPresets ~= nil then
        RenderPresets()
    end
end

local function SchedulePresetListRender()
    if State.presetRenderPending then
        return
    end
    State.presetRenderPending = true
    task.delay(0.3, function()
        State.presetRenderPending = false
        if PresetsIsActive() and RenderPresets ~= nil then
            RenderPresets()
        end
    end)
end

local function HideRenameBar()
    State.presetRenameId = nil
    if State.presetRenameBar ~= nil then
        State.presetRenameBar.Visible = false
        State.presetRenameBar.Size = UDim2.new(1, 0, 0, 0)
    end
end

local function ShowRenameBar(preset)
    State.presetDeleteId = nil
    State.presetRenameId = preset.id
    if State.presetRenameLabel ~= nil then
        State.presetRenameLabel.Text = "RENAME: " .. preset.name
    end
    if State.presetRenameInput ~= nil then
        State.presetRenameInput.Text = preset.name
    end
    if State.presetRenameBar ~= nil then
        State.presetRenameBar.Visible = true
        State.presetRenameBar.Size = UDim2.new(1, 0, 0, 84)
    end
end

local function CommitRename(text)
    local preset = nil
    for _, candidate in ipairs(State.presets) do
        if candidate.id == State.presetRenameId then
            preset = candidate
            break
        end
    end
    if preset == nil then
        HideRenameBar()
        return
    end

    local name = string.match(text or "", "^%s*(.-)%s*$") or ""
    if name == "" then
        Notify("error", "The preset needs a name")
        return
    end
    name = string.sub(name, 1, 40)
    for _, other in ipairs(State.presets) do
        if other ~= preset and other.carId == preset.carId and string.lower(other.name) == string.lower(name) then
            Notify("error", "Another preset of this car already uses that name")
            return
        end
    end

    local oldName = preset.name
    preset.name = name
    WritePresetsFile()
    HideRenameBar()
    RequestPresetRender()
    Notify("success", string.format("Renamed '%s' to '%s'", oldName, name))
end

local function SavePresetFromName(text)
    local name = string.match(text or "", "^%s*(.-)%s*$") or ""
    if name == "" then
        Notify("error", "Type a name for the preset first")
        return
    end
    name = string.sub(name, 1, 40)

    local car = State.car
    if car == nil then
        Notify("error", "Spawn a vehicle before saving a preset")
        return
    end
    local carId = CarIdOf(car)
    if carId == "" then
        Notify("error", "This vehicle has no CarID")
        return
    end

    local values, skipped = CapturePresetValues()
    if next(values) == nil then
        Notify("error", "There are no properties to save yet")
        return
    end
    if skipped > 0 then
        LogError(string.format("%d properties could not be serialized", skipped))
    end
    local identity = ResolveCarIdentity(car)
    local drive = CaptureDriveSettings()

    for _, preset in ipairs(State.presets) do
        if preset.carId == carId and string.lower(preset.name) == string.lower(name) then
            preset.values = values
            preset.drive = drive
            preset.savedAt = os.time()
            preset.carName = identity.name
            preset.trim = identity.trim
            local persisted = WritePresetsFile()
            if State.presetNameInput ~= nil then
                State.presetNameInput.Text = ""
            end
            RequestPresetRender()
            Notify(persisted and "success" or "info", string.format(
                "Updated preset '%s' (%d properties + Drive)%s",
                name,
                CountPresetValues(preset),
                persisted and "" or " · memory only"
            ))
            return
        end
    end

    local preset = {
        id       = NewPresetId(carId),
        name     = name,
        carId    = carId,
        carName  = identity.name,
        trim     = identity.trim,
        autoLoad = false,
        savedAt  = os.time(),
        values   = values,
        drive    = drive,
    }
    table.insert(State.presets, preset)
    local persisted = WritePresetsFile()
    if State.presetNameInput ~= nil then
        State.presetNameInput.Text = ""
    end
    RequestPresetRender()
    Notify(persisted and "success" or "info", string.format(
        "Saved preset '%s' (%d properties + Drive)%s",
        name,
        CountPresetValues(preset),
        persisted and "" or " · memory only"
    ))
end

local function DeletePreset(preset)
    for index, candidate in ipairs(State.presets) do
        if candidate.id == preset.id then
            table.remove(State.presets, index)
            break
        end
    end
    State.presetDeleteId = nil
    if State.presetRenameId == preset.id then
        HideRenameBar()
    end
    WritePresetsFile()
    RequestPresetRender()
    Notify("success", string.format("Deleted preset '%s'", preset.name))
end

local function ToggleAutoLoad(preset)
    local enabled = not preset.autoLoad
    for _, other in ipairs(State.presets) do
        if other.carId == preset.carId then
            other.autoLoad = false
        end
    end
    preset.autoLoad = enabled
    State.presetDeleteId = nil
    WritePresetsFile()
    RequestPresetRender()
    if enabled then
        Notify("success", string.format("'%s' will auto-load when you next enter this car", preset.name))
    else
        Notify("info", "Auto-load cleared")
    end
end

local function LoadPresetButton(preset)
    State.presetDeleteId = nil
    ApplyPreset(preset, false)
end

local function ShowPresetPlaceholder(parent, text)
    MonoUI.Texted(parent, {
        Text        = text,
        Size        = Theme.Type.Body,
        Tint        = "Muted",
        Bold        = false,
        Size2       = UDim2.new(1, 0, 0, 28),
        LayoutOrder = 1,
        ZIndex      = 3,
    })
end

local function CreatePresetRow(parent, order, preset)
    local row = MonoUI.Sticker(MonoUI.Element {
        ClassName             = "Frame",
        Parent                = parent,
        Name                  = "Preset",
        BackgroundTransparency = 1,
        Size                  = UDim2.new(1, 0, 0, PresetRowHeight),
        LayoutOrder           = order,
        ZIndex                = 2,
    }, { Color = "Well", Alpha = Theme.WellAlpha, Corner = "RowRadius", Stroke = "Line" })

    local previewHolder = MonoUI.Sticker(MonoUI.Element {
        ClassName        = "Frame",
        Parent           = row,
        Name             = "Preview",
        BackgroundColor3 = Theme.Surface,
        Size             = UDim2.new(0, 128, 0, 72),
        Position         = UDim2.fromOffset(6, 6),
        ZIndex           = 3,
    }, { Color = "Surface", Alpha = 0.25, Corner = "RowRadius", Stroke = "Line" })

    local viewport = MonoUI.Element {
        ClassName             = "ViewportFrame",
        Parent                = previewHolder,
        Name                  = "PresetViewport",
        BackgroundTransparency = 1,
        Size                  = UDim2.new(1, -8, 1, -8),
        Position              = UDim2.fromOffset(4, 4),
        Ambient               = Color3.fromRGB(180, 180, 180),
        LightColor            = Color3.new(1, 1, 1),
        LightDirection        = Vector3.new(-0.4, -0.8, -0.5),
        ZIndex                = 4,
    }
    if not BuildPresetPreview(viewport, preset) then
        MonoUI.Texted(previewHolder, {
            Text     = "NO PREVIEW",
            Size     = Theme.Type.Support,
            Tint     = "Muted",
            Bold     = false,
            X        = Enum.TextXAlignment.Center,
            Size2    = UDim2.new(1, 0, 1, 0),
            ZIndex   = 5,
        })
    end

    local metaParts = { string.format("%d properties", CountPresetValues(preset)) }
    if preset.trim ~= "" then
        table.insert(metaParts, preset.trim)
    end
    if preset.savedAt > 0 then
        table.insert(metaParts, os.date("%Y-%m-%d %H:%M", preset.savedAt))
    end

    MonoUI.Texted(row, {
        Text     = preset.name,
        Size     = Theme.Type.Label,
        Tint     = "Text",
        Position = UDim2.fromOffset(142, 8),
        Size2    = UDim2.new(1, -340, 0, 20),
        ZIndex   = 3,
    })
    MonoUI.Texted(row, {
        Text     = table.concat(metaParts, " · "),
        Size     = Theme.Type.Support,
        Tint     = "Muted",
        Bold     = false,
        Position = UDim2.fromOffset(142, 30),
        Size2    = UDim2.new(1, -340, 0, 16),
        ZIndex   = 3,
    })
    MonoUI.Texted(row, {
        Text     = preset.autoLoad and "AUTO-LOAD ON" or "AUTO-LOAD OFF",
        Size     = Theme.Type.Support,
        Tint     = preset.autoLoad and "Text" or "Muted",
        Bold     = false,
        Position = UDim2.fromOffset(142, 52),
        Size2    = UDim2.new(1, -340, 0, 16),
        ZIndex   = 3,
    })

    local actions = MonoUI.Element {
        ClassName             = "Frame",
        Parent                = row,
        Name                  = "Actions",
        BackgroundTransparency = 1,
        Size                  = UDim2.new(0, 176, 0, 60),
        Position              = UDim2.new(1, -182, 0, 12),
        ZIndex                = 3,
    }
    local cell = MonoUI.Columns(actions, 2, 6, 26)
    MonoUI.Button {
        Parent   = actions,
        Caption  = "Load",
        Size     = cell,
        Order    = 1,
        TextSize = Theme.Type.Heading,
        OnClick  = function()
            LoadPresetButton(preset)
        end,
    }
    MonoUI.Button {
        Parent   = actions,
        Caption  = "Rename",
        Size     = cell,
        Order    = 2,
        TextSize = Theme.Type.Heading,
        OnClick  = function()
            ShowRenameBar(preset)
        end,
    }
    MonoUI.Button {
        Parent   = actions,
        Caption  = preset.autoLoad and "Auto: On" or "Auto: Off",
        Size     = cell,
        Order    = 3,
        TextSize = Theme.Type.Heading,
        OnClick  = function()
            ToggleAutoLoad(preset)
        end,
    }
    MonoUI.Button {
        Parent   = actions,
        Caption  = State.presetDeleteId == preset.id and "Confirm" or "Delete",
        Size     = cell,
        Order    = 4,
        TextSize = Theme.Type.Heading,
        OnClick  = function()
            if State.presetDeleteId == preset.id then
                DeletePreset(preset)
                return
            end
            State.presetDeleteId = preset.id
            Notify("info", string.format("Click CONFIRM to delete '%s'", preset.name))
            RenderPresets()
        end,
    }
end

function RenderPresets()
    local listFrame = State.presetListFrame
    if listFrame == nil then
        return
    end
    for _, child in ipairs(listFrame:GetChildren()) do
        if child:IsA("GuiObject") then
            child:Destroy()
        end
    end

    local carId = CarIdOf(State.car)
    local all = PresetsForCar(carId)
    local query = string.lower(State.presetSearch or "")
    local matches = {}
    for _, preset in ipairs(all) do
        if query == "" or string.find(string.lower(preset.name), query, 1, true) ~= nil then
            table.insert(matches, preset)
        end
    end

    local shown = math.min(#matches, PresetRenderLimit)
    for index = 1, shown do
        CreatePresetRow(listFrame, index, matches[index])
    end

    if State.car == nil then
        ShowPresetPlaceholder(listFrame, "Spawn a vehicle to see its presets")
    elseif #all == 0 then
        ShowPresetPlaceholder(listFrame, "No presets for this car yet - save one above")
    elseif #matches == 0 then
        ShowPresetPlaceholder(listFrame, "No preset matches that search")
    end

    if State.presetStatus ~= nil then
        local parts = {}
        if State.car == nil then
            table.insert(parts, "No vehicle")
            table.insert(parts, "presets are stored per car")
        else
            table.insert(parts, string.format("%d preset%s for this car", #all, #all == 1 and "" or "s"))
            if #matches > shown then
                table.insert(parts, string.format("showing %d - search to narrow", shown))
            end
            local autoPreset = FindAutoPreset(carId)
            if autoPreset ~= nil then
                table.insert(parts, "auto-load: " .. autoPreset.name)
            else
                table.insert(parts, "auto-load: none")
            end
        end
        State.presetStatus.Text = table.concat(parts, " · ")
    end
end

local function CreatePresetInterface(presetsTab)
    local content = presetsTab.content
    local order = 0
    local function NextOrder()
        order = order + 1
        return order
    end

    MonoUI.Heading(content, NextOrder(), "Save current configuration")

    local nameRow = MonoUI.Row(content, NextOrder(), 30)
    State.presetNameInput = MonoUI.Input {
        Parent          = nameRow,
        Name            = "PresetName",
        Size            = UDim2.new(1, 0, 0, 28),
        Position        = UDim2.new(0, 0, 0, 1),
        Text            = "",
        SubmitOnEnter   = true,
        X               = Enum.TextXAlignment.Left,
        PlaceholderText = "Preset name",
        OnSubmit        = function(text)
            SavePresetFromName(text)
        end,
    }

    local saveRow = MonoUI.Row(content, NextOrder(), 30)
    MonoUI.Button {
        Parent  = saveRow,
        Caption = "Save preset",
        OnClick = function()
            SavePresetFromName(State.presetNameInput.Text)
        end,
    }
    MonoUI.Texted(content, {
        Text        = "Saves every property of this car · saving an existing name updates it",
        Size        = Theme.Type.Support,
        Tint        = "Muted",
        Bold        = false,
        Size2       = UDim2.new(1, 0, 0, 16),
        LayoutOrder = NextOrder(),
    })

    MonoUI.Heading(content, NextOrder(), "Saved presets")

    local searchRow = MonoUI.Row(content, NextOrder(), 30)
    State.presetSearchInput = MonoUI.Input {
        Parent          = searchRow,
        Name            = "PresetSearch",
        Size            = UDim2.new(1, 0, 0, 28),
        Position        = UDim2.new(0, 0, 0, 1),
        Text            = "",
        SubmitOnEnter   = false,
        X               = Enum.TextXAlignment.Left,
        PlaceholderText = "Search presets",
        OnSubmit        = function(text)
            State.presetSearch = text or ""
            SchedulePresetListRender()
        end,
    }

    local renameBar = MonoUI.Element {
        ClassName             = "Frame",
        Parent                = content,
        Name                  = "PresetRename",
        BackgroundTransparency = 1,
        Size                  = UDim2.new(1, 0, 0, 0),
        LayoutOrder           = NextOrder(),
        Visible               = false,
        ZIndex                = 2,
    }
    MonoUI.Element {
        ClassName = "UIListLayout",
        Parent    = renameBar,
        Padding   = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }
    State.presetRenameBar = renameBar
    State.presetRenameLabel = MonoUI.Texted(renameBar, {
        Text        = "",
        Size        = Theme.Type.Heading,
        Tint        = "Muted",
        Bold        = false,
        Size2       = UDim2.new(1, 0, 0, 16),
        LayoutOrder = 1,
        ZIndex      = 3,
    })
    State.presetRenameInput = MonoUI.Input {
        Parent          = renameBar,
        Name            = "PresetRenameInput",
        Size            = UDim2.new(1, 0, 0, 28),
        Text            = "",
        SubmitOnEnter   = true,
        X               = Enum.TextXAlignment.Left,
        PlaceholderText = "New name",
        Order           = 2,
        OnSubmit        = function(text)
            CommitRename(text)
        end,
    }
    local renameActions = MonoUI.Row(renameBar, 3, 28)
    local renameCell = MonoUI.Columns(renameActions, 2, 6, 26)
    MonoUI.Button {
        Parent  = renameActions,
        Caption = "Save name",
        Size    = renameCell,
        Order   = 1,
        OnClick = function()
            CommitRename(State.presetRenameInput.Text)
        end,
    }
    MonoUI.Button {
        Parent  = renameActions,
        Caption = "Cancel",
        Size    = renameCell,
        Order   = 2,
        OnClick = function()
            HideRenameBar()
        end,
    }

    local screenHeight = 1080
    local camera = Workspace.CurrentCamera
    if camera ~= nil then
        screenHeight = camera.ViewportSize.Y
    end
    local listHeight = math.clamp(screenHeight * 0.30, 240, 360)

    local listFrame = MonoUI.Element {
        ClassName             = "ScrollingFrame",
        Parent                = content,
        Name                  = "PresetList",
        BackgroundTransparency = 1,
        BorderSizePixel       = 0,
        ScrollBarThickness    = 4,
        Size                  = UDim2.new(1, 0, 0, listHeight),
        CanvasSize            = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize   = Enum.AutomaticSize.Y,
        LayoutOrder           = NextOrder(),
        ZIndex                = 2,
    }
    MonoUI.Element {
        ClassName = "UIListLayout",
        Parent    = listFrame,
        Padding   = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }
    State.presetListFrame = listFrame

    State.presetStatus = MonoUI.Texted(content, {
        Text        = "",
        Size        = Theme.Type.Support,
        Tint        = "Muted",
        Bold        = false,
        Size2       = UDim2.new(1, 0, 0, 16),
        LayoutOrder = NextOrder(),
    })

    local footerRow = MonoUI.Row(content, NextOrder(), 46)
    local footerCell = MonoUI.Columns(footerRow, 3, 8, 34)
    MonoUI.Element {
        ClassName             = "Frame",
        Parent                = footerRow,
        BackgroundTransparency = 1,
        Size                  = footerCell,
        LayoutOrder           = 1,
    }
    MonoUI.Button {
        Parent  = footerRow,
        Caption = "Unload",
        Size    = footerCell,
        Order   = 2,
        OnClick = function()
            Unload()
        end,
    }
    MonoUI.Element {
        ClassName             = "Frame",
        Parent                = footerRow,
        BackgroundTransparency = 1,
        Size                  = footerCell,
        LayoutOrder           = 3,
    }
end

--=== high-speed setup =====================================================

local function FindEntry(id)
    for _, entry in ipairs(State.entries) do
        if entry.id == id then
            return entry
        end
    end
    return nil
end

--=== builders ==============================================================

local SPEED_FACTOR = 0.56818181818181812

local function DrivenWheelDiameter()
    local wheels = State.wheels
    local tune = State.tune
    if wheels == nil or tune == nil then
        return nil
    end
    local diameter = 0
    for _, wheel in ipairs(wheels:GetChildren()) do
        if wheel:IsA("BasePart") then
            local driven = tune.Config == "AWD"
            if not driven then
                local isFront = string.sub(wheel.Name, 1, 1) == "F"
                driven = isFront == (tune.Config == "FWD")
            end
            if driven then
                diameter = math.max(diameter, wheel.Size.X)
            end
        end
    end
    if diameter <= 0 then
        return nil
    end
    return diameter
end

local function GearTopSpeed(ratios, finalDrive, finalMult, diameter, redline)
    if type(ratios) ~= "table" or #ratios == 0 then
        return 0
    end
    local topRatio = tonumber(ratios[#ratios])
    if topRatio == nil or topRatio == 0 or finalDrive <= 0 or finalMult <= 0 then
        return 0
    end
    local raw = diameter * math.pi * redline / 60
    local geared = raw / topRatio / finalDrive
    return math.floor(math.ceil(geared / finalMult) * SPEED_FACTOR)
end

local function OpenBuilderDialog(title, width, height)
    if State.builderDialog ~= nil then
        pcall(function()
            State.builderDialog:Close()
        end)
        State.builderDialog = nil
    end

    local dialog
    dialog = MonoUI.Dialog {
        Title = title,
        Width = width or 400,
        Height = height or 420,
        OnClose = function()
            if State.builderDialog == dialog then
                State.builderDialog = nil
            end
        end,
    }
    State.builderDialog = dialog
    return dialog
end

local function OpenGearRatioBuilder()
    local tune = State.tune
    local wheels = State.wheels
    if tune == nil or wheels == nil then
        Notify("error", "Spawn a vehicle before opening the gear ratio builder")
        return
    end

    local ratios = tune.Ratios
    local reverseRatio = type(ratios) == "table" and tonumber(ratios[1]) or 0
    local neutralRatio = type(ratios) == "table" and tonumber(ratios[2]) or 0
    local forwardCount = type(ratios) == "table" and (#ratios - 2) or 0
    local count = forwardCount >= 2 and forwardCount or 6
    local firstRatio = type(ratios) == "table" and tonumber(ratios[3]) or 3.5
    if forwardCount < 2 or firstRatio == nil or firstRatio <= 0 then
        firstRatio = 3.5
    end
    local finalDrive = tonumber(tune.FinalDrive) or 3.5
    local finalMult = tonumber(tune.FDMult) or 1
    local redline = tonumber(tune.Redline) or 6000
    local diameter = DrivenWheelDiameter() or 2.5
    local currentTop = ComputeMaxSpeed()
    local target = currentTop > 0 and currentTop or 200

    local dialog = OpenBuilderDialog("GEAR RATIO BUILDER", 410, 510)
    local content = dialog.Content
    local order = 0
    local function NextOrder()
        order = order + 1
        return order
    end

    local modeSelect = MonoUI.Select {
        Parent  = content,
        Caption = "Mode",
        Options = { "Generate ratios", "Solve final drive" },
        Value   = "Generate ratios",
        Order   = NextOrder(),
        ZIndex  = 47,
    }

    local function NumberRow(label, value, placeholder)
        local row = MonoUI.Row(content, NextOrder(), 30)
        MonoUI.Texted(row, {
            Text     = label,
            Size     = Theme.Type.Body,
            Tint     = "Muted",
            Bold     = false,
            Size2    = UDim2.new(0.64, 0, 1, 0),
            ZIndex   = 47,
        })
        return MonoUI.Input {
            Parent          = row,
            Name            = label,
            Size            = UDim2.new(0.32, 0, 0, 24),
            Position        = UDim2.new(0.68, 0, 0, 3),
            Text            = tostring(value),
            X               = Enum.TextXAlignment.Center,
            NumbersOnly     = true,
            SubmitOnEnter   = true,
            PlaceholderText = placeholder,
            ZIndex          = 47,
        }
    end

    local targetInput = NumberRow("Target top speed (speedometer mph)", target, "mph")
    local diameterInput = NumberRow("Driven tire diameter (studs)", string.format("%.4f", diameter), "studs")
    local redlineInput = NumberRow("Engine redline (RPM)", redline, "RPM")
    local countInput = NumberRow("Forward gear count", count, "gears")
    local firstInput = NumberRow("First forward ratio", firstRatio, "ratio")
    local finalInput = NumberRow("Final drive", finalDrive, "ratio")
    local multInput = NumberRow("Final drive mult", finalMult, "mult")

    local status = MonoUI.Texted(content, {
        Text        = "Set a target and press Build.",
        Size        = Theme.Type.Support,
        Tint        = "Muted",
        Bold        = false,
        Size2       = UDim2.new(1, 0, 0, 0),
        ZIndex      = 47,
    })
    status.TextWrapped = true
    status.TextYAlignment = Enum.TextYAlignment.Top
    status.AutomaticSize = Enum.AutomaticSize.Y

    local generated = nil
    local actionRow = MonoUI.Row(content, NextOrder(), 30)
    local actionCell = MonoUI.Columns(actionRow, 3, 6, 30)

    local function SetStatus(text, error)
        status.Text = text
        status.TextColor3 = error and Color3.fromRGB(255, 128, 128) or Theme.Text
    end

    MonoUI.Button {
        Parent  = actionRow,
        Caption = "Build",
        Size    = actionCell,
        Order   = 1,
        ZIndex  = 47,
        OnClick = function()
            local targetValue = tonumber(targetInput.Text)
            local diameterValue = tonumber(diameterInput.Text)
            local redlineValue = tonumber(redlineInput.Text)
            local countValue = tonumber(countInput.Text)
            local firstValue = tonumber(firstInput.Text)
            local finalValue = tonumber(finalInput.Text)
            local multValue = tonumber(multInput.Text)
            local mode = modeSelect.Get() or "Generate ratios"

            if targetValue == nil or targetValue <= 0 then
                SetStatus("Target top speed must be a positive number.", true)
                return
            end
            if diameterValue == nil or diameterValue <= 0 then
                SetStatus("Driven tire diameter must be positive.", true)
                return
            end
            if redlineValue == nil or redlineValue <= 0 then
                SetStatus("Redline must be positive.", true)
                return
            end
            if countValue == nil then
                SetStatus("Gear count must be a number.", true)
                return
            end
            countValue = math.floor(countValue)
            if countValue < 2 or countValue > 12 then
                SetStatus("Gear count must be between 2 and 12.", true)
                return
            end
            if finalValue == nil or finalValue <= 0 then
                SetStatus("Final drive must be positive.", true)
                return
            end
            if multValue == nil or multValue <= 0 then
                SetStatus("Final drive mult must be positive.", true)
                return
            end

            local targetRaw = targetValue / SPEED_FACTOR
            local base = diameterValue * math.pi * redlineValue / 60

            if mode == "Solve final drive" then
                local baseRatios = CopyValue(tune.Ratios)
                local topRatio = type(baseRatios) == "table" and tonumber(baseRatios[#baseRatios]) or nil
                if topRatio == nil or topRatio <= 0 then
                    SetStatus("The current gear list has no usable top gear.", true)
                    return
                end
                local solvedFinal = base / (targetRaw * topRatio * multValue)
                if solvedFinal <= 0 or solvedFinal ~= solvedFinal then
                    SetStatus("Those values produce an invalid final drive.", true)
                    return
                end
                topRatio = topRatio
                generated = {
                    Ratios = baseRatios,
                    FinalDrive = solvedFinal,
                    FDMult = multValue,
                }
                local actual = GearTopSpeed(baseRatios, solvedFinal, multValue, diameterValue, redlineValue)
                SetStatus(string.format(
                    "Final drive: %.4f\nPredicted top speed: %d mph\nApply writes the final drive into the A-Chassis tune.",
                    solvedFinal, actual
                ), false)
                return
            end

            if firstValue == nil or firstValue <= 0 then
                SetStatus("First gear ratio must be positive.", true)
                return
            end
            local topRatio = base / (targetRaw * finalValue * multValue)
            if topRatio <= 0 or topRatio ~= topRatio or firstValue <= topRatio then
                SetStatus("The first gear must be numerically larger than the calculated top gear.", true)
                return
            end
            local step = (firstValue / topRatio) ^ (1 / (countValue - 1))
            local generatedRatios = { reverseRatio or 0, neutralRatio or 0 }
            for index = 1, countValue do
                generatedRatios[#generatedRatios + 1] = firstValue / (step ^ (index - 1))
            end
            generatedRatios[#generatedRatios] = topRatio
            generated = {
                Ratios = generatedRatios,
                FinalDrive = finalValue,
                FDMult = multValue,
            }
            local labels = {}
            for index = 3, #generatedRatios do
                labels[#labels + 1] = FormatNumber(generatedRatios[index])
            end
            local actual = GearTopSpeed(generatedRatios, finalValue, multValue, diameterValue, redlineValue)
            SetStatus(string.format(
                "Reverse %.2f · neutral %.2f\nForward: %s\nPredicted top speed: %d mph\nApply writes the gear set into the A-Chassis tune.",
                generatedRatios[1], generatedRatios[2], table.concat(labels, ", "), actual
            ), false)
        end,
    }

    MonoUI.Button {
        Parent  = actionRow,
        Caption = "Apply to tune",
        Size    = actionCell,
        Order   = 2,
        ZIndex  = 47,
        OnClick = function()
            if generated == nil then
                SetStatus("Press Build first, then apply the result.", true)
                return
            end
            if State.tune == nil then
                SetStatus("The car has no A-Chassis tune to write to.", true)
                return
            end
            State.tune.Ratios = CopyValue(generated.Ratios)
            State.tune.FinalDrive = generated.FinalDrive
            State.tune.FDMult = generated.FDMult
            local changed = 0
            for _, entry in ipairs(State.entries) do
                if entry.source == "Motor" and (entry.key == "Ratios" or entry.key == "FinalDrive" or entry.key == "FDMult") then
                    entry.value = entry.getValue()
                    if entry.widget ~= nil and entry.widget.Apply ~= nil then
                        pcall(entry.widget.Apply, entry.value)
                    end
                    changed = changed + 1
                end
            end
            RefreshDerivedEntries()
            LogInfo(string.format("Gear ratio builder applied %d tune fields", changed))
            Notify("success", "Gear ratios applied · exit and re-enter the vehicle")
            dialog:Close()
        end,
    }

    MonoUI.Button {
        Parent  = actionRow,
        Caption = "Close",
        Size    = actionCell,
        Order   = 3,
        ZIndex  = 47,
        OnClick = function()
            dialog:Close()
        end,
    }
end

local function BuilderNumberRow(parent, order, label, value, placeholder)
    local row = MonoUI.Row(parent, order, 30)
    MonoUI.Texted(row, {
        Text     = label,
        Size     = Theme.Type.Body,
        Tint     = "Muted",
        Bold     = false,
        Size2    = UDim2.new(0.64, 0, 1, 0),
        ZIndex   = 47,
    })
    return MonoUI.Input {
        Parent          = row,
        Name            = label,
        Size            = UDim2.new(0.32, 0, 0, 24),
        Position        = UDim2.new(0.68, 0, 0, 3),
        Text            = tostring(value),
        X               = Enum.TextXAlignment.Center,
        NumbersOnly     = true,
        SubmitOnEnter   = true,
        PlaceholderText = placeholder,
        ZIndex          = 47,
    }
end

local function ApplyFinalDriveToTune(finalDrive, finalMult)
    if State.tune == nil then
        return false, 0
    end
    State.tune.FinalDrive = finalDrive
    State.tune.FDMult = finalMult
    local changed = 0
    for _, entry in ipairs(State.entries) do
        if entry.source == "Motor" and (entry.key == "FinalDrive" or entry.key == "FDMult") then
            entry.value = entry.getValue()
            if entry.widget ~= nil and entry.widget.Apply ~= nil then
                pcall(entry.widget.Apply, entry.value)
            end
            changed = changed + 1
        end
    end
    RefreshDerivedEntries()
    return true, changed
end

local function ApplyAccelerationProfile(horsepower, firstForward)
    local tune = State.tune
    if tune == nil then
        return false
    end

    tune.Horsepower = horsepower
    tune.WeightDist = 50
    tune.CGHeight = 0.5
    local ratios = tune.Ratios
    if type(ratios) == "table" and #ratios >= 3 then
        ratios[3] = firstForward
    end

    local function SetCarAttribute(key, value)
        local entry = FindEntry("Car." .. key)
        if entry ~= nil then
            ApplyProperty(entry, value, true)
        elseif State.car ~= nil then
            State.car:SetAttribute(key, value)
        end
    end

    local function SetWheelAttribute(key, value)
        local entry = FindEntry("Wheels." .. key)
        if entry ~= nil then
            ApplyProperty(entry, value, true)
        elseif State.wheels ~= nil then
            State.wheels:SetAttribute(key, value)
        end
    end

    SetCarAttribute("Dynamics_Drivetrain", "AWD")
    SetCarAttribute("Dynamics_Traction", true)
    SetCarAttribute("Dynamics_Antilock", true)
    local compound = PickTireCompound("Racing Slick")
    if compound ~= nil then
        SetCarAttribute("Dynamics_FTireCompound", compound)
        SetCarAttribute("Dynamics_RTireCompound", compound)
    end
    SetWheelAttribute("Friction_UseLocalValues", true)
    SetWheelAttribute("Friction_DryRoad", 1)

    for _, entry in ipairs(State.entries) do
        if entry.source == "Motor" and (entry.key == "Horsepower" or entry.key == "Ratios" or entry.key == "WeightDist" or entry.key == "CGHeight") then
            entry.value = entry.getValue()
            if entry.widget ~= nil and entry.widget.Apply ~= nil then
                pcall(entry.widget.Apply, entry.value)
            end
        end
    end
    RefreshDerivedEntries()
    return true
end

local function OpenFinalDriveBuilder()
    local tune = State.tune
    if tune == nil then
        Notify("error", "Spawn a vehicle before opening the final drive builder")
        return
    end

    local finalDrive = tonumber(tune.FinalDrive) or 3.5
    local finalMult = tonumber(tune.FDMult) or 1
    local total = finalDrive * finalMult

    local dialog = OpenBuilderDialog("FINAL DRIVE BUILDER", 400, 380)
    local content = dialog.Content
    local order = 0
    local function NextOrder()
        order = order + 1
        return order
    end

    local axleInput = BuilderNumberRow(content, NextOrder(), "Axle ratio (FinalDrive)", finalDrive, "ratio")
    local multInput = BuilderNumberRow(content, NextOrder(), "Multiplier (FDMult)", finalMult, "mult")
    local totalInput = BuilderNumberRow(content, NextOrder(), "Total final drive", string.format("%.4f", total), "product")

    local status = MonoUI.Texted(content, {
        Text        = "Enter a total and axle ratio, then Build.",
        Size        = Theme.Type.Support,
        Tint        = "Muted",
        Bold        = false,
        Size2       = UDim2.new(1, 0, 0, 0),
        ZIndex      = 47,
    })
    status.TextWrapped = true
    status.TextYAlignment = Enum.TextYAlignment.Top
    status.AutomaticSize = Enum.AutomaticSize.Y

    local function SetStatus(text, error)
        status.Text = text
        status.TextColor3 = error and Color3.fromRGB(255, 128, 128) or Theme.Text
    end

    local actionRow = MonoUI.Row(content, NextOrder(), 30)
    local actionCell = MonoUI.Columns(actionRow, 3, 6, 30)

    MonoUI.Button {
        Parent  = actionRow,
        Caption = "Build",
        Size    = actionCell,
        Order   = 1,
        ZIndex  = 47,
        OnClick = function()
            local axle = tonumber(axleInput.Text)
            local targetTotal = tonumber(totalInput.Text)
            if axle == nil or axle <= 0 then
                SetStatus("Axle ratio must be positive.", true)
                return
            end
            if targetTotal == nil or targetTotal <= 0 then
                SetStatus("Total final drive must be positive.", true)
                return
            end
            local mult = targetTotal / axle
            if mult <= 0 or mult ~= mult then
                SetStatus("Those values produce an invalid multiplier.", true)
                return
            end
            multInput.Text = string.format("%.6f", mult)
            local ratios = tune.Ratios
            local diameter = DrivenWheelDiameter() or 2.5
            local redline = tonumber(tune.Redline) or 6000
            local actual = GearTopSpeed(ratios, axle, mult, diameter, redline)
            SetStatus(string.format(
                "FDMult = %.6f\nFinal drive product = %.4f\nPredicted top speed = %d mph",
                mult, axle * mult, actual
            ), false)
        end,
    }

    MonoUI.Button {
        Parent  = actionRow,
        Caption = "Apply to tune",
        Size    = actionCell,
        Order   = 2,
        ZIndex  = 47,
        OnClick = function()
            local axle = tonumber(axleInput.Text)
            local mult = tonumber(multInput.Text)
            if axle == nil or axle <= 0 or mult == nil or mult <= 0 then
                SetStatus("FinalDrive and FDMult must both be positive.", true)
                return
            end
            local ok, changed = ApplyFinalDriveToTune(axle, mult)
            if not ok then
                SetStatus("The car has no A-Chassis tune to write to.", true)
                return
            end
            LogInfo(string.format("Final drive builder applied %d tune fields", changed))
            Notify("success", "Final drive applied · exit and re-enter the vehicle")
            dialog:Close()
        end,
    }

    MonoUI.Button {
        Parent  = actionRow,
        Caption = "Close",
        Size    = actionCell,
        Order   = 3,
        ZIndex  = 47,
        OnClick = function()
            dialog:Close()
        end,
    }
end

local function OpenMaxSpeedBuilder()
    local tune = State.tune
    if tune == nil then
        Notify("error", "Spawn a vehicle before opening the max speed builder")
        return
    end

    local ratios = tune.Ratios
    local topRatio = type(ratios) == "table" and tonumber(ratios[#ratios]) or nil
    if topRatio == nil or topRatio <= 0 then
        Notify("error", "The car's gear table has no usable top gear")
        return
    end

    local diameter = DrivenWheelDiameter() or 2.5
    local redline = tonumber(tune.Redline) or 6000
    local finalDrive = tonumber(tune.FinalDrive) or 3.5
    local weight = tonumber(tune.Weight) or 3000
    local horsepower = tonumber(tune.Horsepower) or 500
    local currentAccel = ComputeAcceleration()
    local accelTarget = currentAccel > 0 and currentAccel or 5
    local firstForward = type(ratios) == "table" and tonumber(ratios[3]) or 3.5
    if firstForward == nil or firstForward <= 0 then
        firstForward = 3.5
    end
    firstForward = math.max(firstForward, 4.5)
    local efficiency = 12.5
    local gripFloor = 1.0
    local currentTop = ComputeMaxSpeed()
    local target = currentTop > 0 and currentTop or 200

    local dialog = OpenBuilderDialog("MAX SPEED BUILDER", 410, 620)
    local content = dialog.Content
    local order = 0
    local function NextOrder()
        order = order + 1
        return order
    end

    local targetInput = BuilderNumberRow(content, NextOrder(), "Target top speed (speedometer mph)", target, "mph")
    local diameterInput = BuilderNumberRow(content, NextOrder(), "Driven tire diameter (studs)", string.format("%.4f", diameter), "studs")
    local redlineInput = BuilderNumberRow(content, NextOrder(), "Engine redline (RPM)", redline, "RPM")
    local axleInput = BuilderNumberRow(content, NextOrder(), "Axle ratio (FinalDrive)", finalDrive, "ratio")

    MonoUI.Texted(content, {
        Text        = string.format("Current top gear ratio: %s", FormatNumber(topRatio)),
        Size        = Theme.Type.Support,
        Tint        = "Muted",
        Bold        = false,
        Size2       = UDim2.new(1, 0, 0, 16),
        LayoutOrder = NextOrder(),
        ZIndex      = 47,
    })

    MonoUI.Heading(content, NextOrder(), "Acceleration (power-limited)")
    local accelTargetInput = BuilderNumberRow(content, NextOrder(), "Target 0-60 (seconds)", accelTarget, "s")
    local weightInput = BuilderNumberRow(content, NextOrder(), "Weight (lb)", weight, "lb")
    local horsepowerInput = BuilderNumberRow(content, NextOrder(), "Horsepower", horsepower, "hp")
    local firstForwardInput = BuilderNumberRow(content, NextOrder(), "First forward ratio", firstForward, "ratio")
    local efficiencyInput = BuilderNumberRow(content, NextOrder(), "Real-world efficiency (%)", efficiency, "%")
    local gripFloorInput = BuilderNumberRow(content, NextOrder(), "Grip-limited 0-60 floor (s)", gripFloor, "s")
    local generatedHorsepower = nil

    local status = MonoUI.Texted(content, {
        Text        = "Enter a target, then Build.",
        Size        = Theme.Type.Support,
        Tint        = "Muted",
        Bold        = false,
        Size2       = UDim2.new(1, 0, 0, 0),
        ZIndex      = 47,
    })
    status.TextWrapped = true
    status.TextYAlignment = Enum.TextYAlignment.Top
    status.AutomaticSize = Enum.AutomaticSize.Y

    local function SetStatus(text, error)
        status.Text = text
        status.TextColor3 = error and Color3.fromRGB(255, 128, 128) or Theme.Text
    end

    local generated = nil
    local actionRow = MonoUI.Row(content, NextOrder(), 30)
    local actionCell = MonoUI.Columns(actionRow, 3, 6, 30)

    MonoUI.Button {
        Parent  = actionRow,
        Caption = "Build",
        Size    = actionCell,
        Order   = 1,
        ZIndex  = 47,
        OnClick = function()
            local targetValue = tonumber(targetInput.Text)
            local diameterValue = tonumber(diameterInput.Text)
            local redlineValue = tonumber(redlineInput.Text)
            local axleValue = tonumber(axleInput.Text)
            if targetValue == nil or targetValue <= 0 then
                SetStatus("Target top speed must be positive.", true)
                return
            end
            if diameterValue == nil or diameterValue <= 0 then
                SetStatus("Driven tire diameter must be positive.", true)
                return
            end
            if redlineValue == nil or redlineValue <= 0 then
                SetStatus("Redline must be positive.", true)
                return
            end
            if axleValue == nil or axleValue <= 0 then
                SetStatus("Axle ratio must be positive.", true)
                return
            end

            local targetRaw = targetValue / SPEED_FACTOR
            local raw = diameterValue * math.pi * redlineValue / 60
            local product = raw / (targetRaw * topRatio)
            local mult = product / axleValue
            if product <= 0 or product ~= product or mult <= 0 or mult ~= mult then
                SetStatus("Those values produce an invalid final drive.", true)
                return
            end
            generated = {
                FinalDrive = axleValue,
                FDMult = mult,
            }
            local actual = GearTopSpeed(ratios, axleValue, mult, diameterValue, redlineValue)
            SetStatus(string.format(
                "Required final drive product: %.4f\nFDMult: %.6f\nPredicted top speed: %d mph",
                product, mult, actual
            ), false)
        end,
    }

    MonoUI.Button {
        Parent  = actionRow,
        Caption = "Apply to tune",
        Size    = actionCell,
        Order   = 2,
        ZIndex  = 47,
        OnClick = function()
            if generated == nil then
                SetStatus("Press Build first, then apply the result.", true)
                return
            end
            local ok, changed = ApplyFinalDriveToTune(generated.FinalDrive, generated.FDMult)
            if not ok then
                SetStatus("The car has no A-Chassis tune to write to.", true)
                return
            end
            LogInfo(string.format("Max speed builder applied %d tune fields", changed))
            Notify("success", "Max speed final drive applied · exit and re-enter the vehicle")
            dialog:Close()
        end,
    }

    MonoUI.Button {
        Parent  = actionRow,
        Caption = "Close",
        Size    = actionCell,
        Order   = 3,
        ZIndex  = 47,
        OnClick = function()
            dialog:Close()
        end,
    }

    local accelActionRow = MonoUI.Row(content, NextOrder(), 30)
    local accelCell = MonoUI.Columns(accelActionRow, 2, 6, 30)
    MonoUI.Button {
        Parent  = accelActionRow,
        Caption = "Build acceleration",
        Size    = accelCell,
        Order   = 1,
        ZIndex  = 47,
        OnClick = function()
            local targetSeconds = tonumber(accelTargetInput.Text)
            local weightValue = tonumber(weightInput.Text)
            local horsepowerValue = tonumber(horsepowerInput.Text)
            local efficiencyValue = tonumber(efficiencyInput.Text)
            local floorValue = tonumber(gripFloorInput.Text)
            if targetSeconds == nil or targetSeconds <= 0 then
                SetStatus("Target 0-60 must be positive.", true)
                return
            end
            if weightValue == nil or weightValue <= 0 then
                SetStatus("Weight must be positive.", true)
                return
            end
            if horsepowerValue == nil or horsepowerValue <= 0 then
                SetStatus("Horsepower must be positive.", true)
                return
            end
            if efficiencyValue == nil or efficiencyValue <= 0 or efficiencyValue > 100 then
                SetStatus("Efficiency must be between 0 and 100 percent.", true)
                return
            end
            if floorValue == nil or floorValue < 0 then
                SetStatus("Grip floor must be zero or positive.", true)
                return
            end
            local mass = weightValue * 0.45359237
            local targetSpeed = 60 * 0.44704
            local effectiveTarget = math.max(targetSeconds, floorValue)
            local efficiencyFactor = efficiencyValue / 100
            local ideal = 0.5 * mass * targetSpeed * targetSpeed / (horsepowerValue * 745.699872)
            local required = 0.5 * mass * targetSpeed * targetSpeed / effectiveTarget / efficiencyFactor / 745.699872
            generatedHorsepower = math.max(math.ceil(required), math.ceil(horsepowerValue))
            local floorNote = ""
            if targetSeconds < floorValue then
                floorNote = string.format("\nTarget is below the grip floor; expect about %.2f s.", floorValue)
            end
            SetStatus(string.format(
                "Ideal 0-60 at %.0f hp: %.2f s\nEffective target: %.2f s (floor %.2f s) · efficiency %.1f%%\nRequired horsepower: %.0f hp (current HP kept if higher)%s\nApply acceleration also sets first gear, AWD/TCS/ABS, track tires, friction, weight distribution and CG.",
                horsepowerValue, ideal, effectiveTarget, floorValue, efficiencyValue, generatedHorsepower, floorNote
            ), false)
        end,
    }
    MonoUI.Button {
        Parent  = accelActionRow,
        Caption = "Apply acceleration",
        Size    = accelCell,
        Order   = 2,
        ZIndex  = 47,
        OnClick = function()
            if generatedHorsepower == nil then
                SetStatus("Press Build acceleration first.", true)
                return
            end
            local firstForwardValue = tonumber(firstForwardInput.Text)
            if firstForwardValue == nil or firstForwardValue <= 0 then
                SetStatus("First forward ratio must be positive.", true)
                return
            end
            if ApplyAccelerationProfile(generatedHorsepower, firstForwardValue) ~= true then
                SetStatus("The car has no A-Chassis tune to write to.", true)
                return
            end
            LogInfo(string.format("Acceleration profile: %d hp, first ratio %.3f", generatedHorsepower, firstForwardValue))
            Notify("success", "Acceleration profile applied · exit and re-enter the vehicle")
        end,
    }
end

--=== high-speed downforce ==================================================

local function StopDownforce()
    Downforce.Enabled = false
    if Downforce.Connection ~= nil then
        pcall(function()
            Downforce.Connection:Disconnect()
        end)
        Downforce.Connection = nil
    end
    if Downforce.Force ~= nil then
        pcall(function()
            Downforce.Force:Destroy()
        end)
        Downforce.Force = nil
    end
    if Downforce.Attachment ~= nil then
        pcall(function()
            Downforce.Attachment:Destroy()
        end)
        Downforce.Attachment = nil
    end
    Downforce.Car = nil
end

local function StartDownforce()
    if Downforce.Enabled then
        return
    end
    Downforce.Enabled = true
    Downforce.FrictionClock = 0
    Downforce.Connection = RunService.Heartbeat:Connect(function(deltaTime)
        if not Downforce.Enabled then
            return
        end
        -- The window can be destroyed without Unload (a reload from the executor). A loop left
        -- behind by such an instance must let go of the car instead of stacking a second force.
        if State.window == nil
            or State.window.plate == nil
            or State.window.plate.Parent == nil
        then
            StopDownforce()
            return
        end
        local car = State.car
        local seat = car and car:FindFirstChild("DriveSeat")
        if seat == nil then
            if Downforce.Force ~= nil and Downforce.Force.Parent ~= nil then
                Downforce.Force.Force = Vector3.zero
            end
            return
        end

        if Downforce.Car ~= seat then
            if Downforce.Force ~= nil then
                pcall(function()
                    Downforce.Force:Destroy()
                end)
            end
            if Downforce.Attachment ~= nil then
                pcall(function()
                    Downforce.Attachment:Destroy()
                end)
            end
            -- Clear anything an older instance left on the seat before taking it over.
            for _, child in ipairs(seat:GetChildren()) do
                if (child:IsA("VectorForce") or child:IsA("Attachment")) and child.Name == "HighSpeedDownforce" then
                    pcall(function()
                        child:Destroy()
                    end)
                end
            end
            local attachment = Instance.new("Attachment")
            attachment.Name = "HighSpeedDownforce"
            attachment.Parent = seat
            local force = Instance.new("VectorForce")
            force.Name = "HighSpeedDownforce"
            force.Attachment0 = attachment
            force.ApplyAtCenterOfMass = true
            force.RelativeTo = Enum.ActuatorRelativeTo.World
            force.Force = Vector3.zero
            force.Parent = seat
            Downforce.Attachment = attachment
            Downforce.Force = force
            Downforce.Car = seat
        end

        local speedMph = SpeedometerMph(seat.AssemblyLinearVelocity)
        local pressure = math.clamp((speedMph / 320) ^ 2, 0, 2.5)
        local downforce = 0
        if speedMph >= 70 then
            downforce = seat.AssemblyMass * Workspace.Gravity * 0.6 * pressure
        end
        if Downforce.Force ~= nil and Downforce.Force.Parent ~= nil then
            Downforce.Force.Force = Vector3.new(0, -downforce, 0)
        end

        -- The server can replace the friction attributes whenever it likes; keep them at the
        -- high-grip values while the assist is on.
        Downforce.FrictionClock = Downforce.FrictionClock + deltaTime
        if Downforce.FrictionClock >= 1 then
            Downforce.FrictionClock = 0
            local wheels = car:FindFirstChild("Wheels")
            if wheels ~= nil and wheels.Parent ~= nil then
                pcall(function()
                    wheels:SetAttribute("Friction_UseLocalValues", true)
                    wheels:SetAttribute("Friction_DryRoad", 1.0)
                    wheels:SetAttribute("Friction_WetRoad", 0.6)
                end)
            end
        end
    end)
end

local function SetDownforce(enabled)
    if enabled then
        StartDownforce()
    else
        StopDownforce()
    end
    if Downforce.Switch ~= nil then
        Downforce.Switch.Set(enabled)
    end
end

--=== high-speed wheel lock =================================================

local function IsInsideWheel(wheel, instance)
    local node = instance
    while node ~= nil do
        if node == wheel then
            return true
        end
        node = node.Parent
    end
    return false
end

local function IsRecordedConstraint(constraint)
    for _, record in ipairs(WheelLock.Constraints) do
        if record.Constraint == constraint then
            return true
        end
    end
    return false
end

-- Every link that reaches from this wheel to something outside its own assembly must let go for
-- the hinge to own the wheel's position. Links wholly inside the wheel stay, so its spin and
-- visual assembly keep working.
local function DisableExternalLinks(car, wheel)
    for _, child in ipairs(car:GetDescendants()) do
        if child.Name ~= "HighSpeedWheelLock"
            and (child:IsA("WeldConstraint") or child:IsA("Constraint"))
            and child.Enabled
        then
            local inside0, inside1
            if child:IsA("WeldConstraint") then
                inside0 = child.Part0 ~= nil and IsInsideWheel(wheel, child.Part0)
                inside1 = child.Part1 ~= nil and IsInsideWheel(wheel, child.Part1)
            else
                local a0 = child.Attachment0
                local a1 = child.Attachment1
                inside0 = a0 ~= nil and IsInsideWheel(wheel, a0.Parent)
                inside1 = a1 ~= nil and IsInsideWheel(wheel, a1.Parent)
            end
            if inside0 ~= nil and inside1 ~= nil and inside0 ~= inside1 then
                if not IsRecordedConstraint(child) then
                    table.insert(WheelLock.Constraints, { Constraint = child, Enabled = true })
                end
                pcall(function()
                    child.Enabled = false
                end)
            end
        end
    end
end

local function DestroyWheelLocks()
    for _, lock in ipairs(WheelLock.Locks) do
        if lock.Hinge ~= nil then
            pcall(function()
                lock.Hinge:Destroy()
            end)
        end
        if lock.WheelAttachment ~= nil then
            pcall(function()
                lock.WheelAttachment:Destroy()
            end)
        end
        if lock.SeatAttachment ~= nil then
            pcall(function()
                lock.SeatAttachment:Destroy()
            end)
        end
    end
    WheelLock.Locks = {}
end

local function RestoreWheelConstraints()
    for _, record in ipairs(WheelLock.Constraints) do
        if record.Constraint.Parent ~= nil then
            pcall(function()
                record.Constraint.Enabled = record.Enabled
            end)
        end
    end
    WheelLock.Constraints = {}
end

local function UnlockWheels(notify)
    if not WheelLock.Locked and #WheelLock.Locks == 0 and #WheelLock.Constraints == 0 then
        return
    end
    local wasLocked = WheelLock.Locked
    DestroyWheelLocks()
    RestoreWheelConstraints()
    WheelLock.Locked = false
    if notify and wasLocked then
        Notify("info", string.format("Wheels unlocked below %d mph", WHEEL_UNLOCK_SPEED))
    end
end

local function LockWheels(car, seat, wheels, speedMph)
    local locked = 0
    local axle = seat.CFrame.RightVector
    local up = seat.CFrame.UpVector
    for _, name in ipairs(WHEEL_NAMES) do
        local wheel = wheels:FindFirstChild(name)
        if wheel ~= nil and wheel:IsA("BasePart") then
            DisableExternalLinks(car, wheel)

            -- Both attachments sit at the wheel centre with the axle as their X axis: the hinge
            -- holds that point against the chassis and only lets the wheel spin around the axle.
            local frame = CFrame.fromMatrix(wheel.Position, axle, up)
            local wheelAttachment = Instance.new("Attachment")
            wheelAttachment.Name = "HighSpeedWheelLockWheel"
            wheelAttachment.WorldCFrame = frame
            wheelAttachment.Parent = wheel

            local seatAttachment = Instance.new("Attachment")
            seatAttachment.Name = "HighSpeedWheelLockChassis"
            seatAttachment.WorldCFrame = frame
            seatAttachment.Parent = seat

            local hinge = Instance.new("HingeConstraint")
            hinge.Name = "HighSpeedWheelLock"
            hinge.Attachment0 = wheelAttachment
            hinge.Attachment1 = seatAttachment
            hinge.ActuatorType = Enum.ActuatorType.None
            hinge.LimitsEnabled = false
            hinge.Enabled = true
            hinge.Parent = wheel

            table.insert(WheelLock.Locks, {
                Hinge = hinge,
                WheelAttachment = wheelAttachment,
                SeatAttachment = seatAttachment,
            })
            locked = locked + 1
        end
    end
    WheelLock.Locked = locked > 0
    WheelLock.Recheck = 0
    if WheelLock.Locked then
        Notify("success", string.format("Wheels locked at %d mph (axle hinges)", math.floor(speedMph)))
    end
end

local function StopWheelLock()
    WheelLock.Enabled = false
    UnlockWheels(false)
    if WheelLock.Connection ~= nil then
        pcall(function()
            WheelLock.Connection:Disconnect()
        end)
        WheelLock.Connection = nil
    end
    WheelLock.Car = nil
end

local function StartWheelLock()
    if WheelLock.Enabled then
        return
    end
    WheelLock.Enabled = true
    WheelLock.Car = nil
    WheelLock.Cooldown = 0
    WheelLock.Recheck = 0
    WheelLock.Connection = RunService.Heartbeat:Connect(function(deltaTime)
        if not WheelLock.Enabled then
            return
        end
        if State.window == nil
            or State.window.plate == nil
            or State.window.plate.Parent == nil
        then
            StopWheelLock()
            return
        end
        local car = State.car
        local seat = car and car:FindFirstChild("DriveSeat")
        local wheels = car and car:FindFirstChild("Wheels")
        if seat == nil or wheels == nil then
            UnlockWheels(false)
            WheelLock.Car = nil
            return
        end
        if WheelLock.Car ~= car then
            UnlockWheels(false)
            WheelLock.Car = car
        end

        local speedMph = SpeedometerMph(seat.AssemblyLinearVelocity)
        if WheelLock.Cooldown > 0 then
            WheelLock.Cooldown = math.max(0, WheelLock.Cooldown - deltaTime)
        end
        if WheelLock.Locked then
            if speedMph < WHEEL_UNLOCK_SPEED then
                UnlockWheels(true)
                WheelLock.Cooldown = 1.5
            else
                -- The chassis may put a link back; keep the suspension and steering released.
                WheelLock.Recheck = WheelLock.Recheck + deltaTime
                if WheelLock.Recheck >= 0.5 then
                    WheelLock.Recheck = 0
                    for _, name in ipairs(WHEEL_NAMES) do
                        local wheel = wheels:FindFirstChild(name)
                        if wheel ~= nil and wheel:IsA("BasePart") then
                            DisableExternalLinks(car, wheel)
                        end
                    end
                end
            end
        elseif speedMph >= WHEEL_LOCK_SPEED and WheelLock.Cooldown <= 0 then
            LockWheels(car, seat, wheels, speedMph)
        end
    end)
end

local function SetWheelLock(enabled)
    if enabled then
        StartWheelLock()
    else
        StopWheelLock()
    end
    if WheelLock.Switch ~= nil then
        WheelLock.Switch.Set(enabled)
    end
end

--=== boost =================================================================

local function FormatBoostAxes(axes)
    local names = {}
    for _, axis in ipairs(BOOST_AXIS_OPTIONS) do
        if axes[axis] then
            names[#names + 1] = axis
        end
    end
    if #names == 0 then
        return "None"
    end
    return table.concat(names, ", ")
end

local function BoostAxesDirection(seat, velocity, axes)
    local unit = velocity.Magnitude > 0.001 and velocity.Unit or Vector3.zero
    local direction = Vector3.new(
        axes.X and unit.X or 0,
        axes.Y and unit.Y or 0,
        axes.Z and unit.Z or 0
    )
    if seat ~= nil then
        local cframe = seat.CFrame
        if axes.Forward then
            direction = direction + cframe.LookVector
        end
        if axes.Backward then
            direction = direction - cframe.LookVector
        end
        if axes.Right then
            direction = direction + cframe.RightVector
        end
        if axes.Left then
            direction = direction - cframe.RightVector
        end
    end
    if direction.Magnitude < 0.001 then
        return nil
    end
    return direction.Unit
end

local function UpdateBoostAxisStatus()
    if Boost.AxisStatus ~= nil then
        Boost.AxisStatus.Text = "Selected: " .. FormatBoostAxes(Boost.Axes)
    end
end

local function SetAllBoostAxes(selected)
    for _, axis in ipairs(BOOST_AXIS_OPTIONS) do
        Boost.Axes[axis] = selected
    end
    for _, refresh in ipairs(Boost.AxisRefreshers) do
        refresh()
    end
    UpdateBoostAxisStatus()
    SaveDriveConfigSoon()
end

local function StopBoost(reason)
    if not Boost.Active then
        return
    end
    Boost.Active = false
    if Boost.Connection ~= nil then
        pcall(function()
            Boost.Connection:Disconnect()
        end)
        Boost.Connection = nil
    end
    Boost.Car = nil
    if reason ~= nil then
        Notify("info", reason)
    end
end

local function StepBoost(deltaTime)
    if not Boost.Active then
        return
    end
    if State.window == nil
        or State.window.plate == nil
        or State.window.plate.Parent == nil
    then
        StopBoost(nil)
        return
    end
    local car = State.car
    if car == nil or car ~= Boost.Car then
        StopBoost(nil)
        return
    end
    local seat = car:FindFirstChild("DriveSeat")
    if seat == nil then
        StopBoost(nil)
        return
    end

    local velocity = seat.AssemblyLinearVelocity
    local speedMph = SpeedometerMph(velocity)
    if speedMph >= Boost.MaxSpeedMph then
        StopBoost("Boost stopped at the maximum speed")
        return
    end
    local direction = BoostAxesDirection(seat, velocity, Boost.ActiveAxes)
    if direction == nil then
        StopBoost(nil)
        return
    end
    local rate = Boost.Strength / math.max(Boost.Duration, 0.05)
    local remaining = math.max(0, (Boost.MaxSpeedMph - speedMph) / SPEEDOMETER_MPH_PER_STUD)
    local added = math.min(rate * deltaTime, remaining)
    if added > 0 then
        seat.AssemblyLinearVelocity = velocity + direction * added
    end
    Boost.Elapsed = Boost.Elapsed + deltaTime
    if Boost.Elapsed >= Boost.Duration then
        StopBoost("Boost finished")
    end
end

local function StartBoost()
    if Boost.Active then
        Notify("info", "Boost is already running")
        return
    end
    if Fly.Active then
        Notify("error", "Turn Fly off before boosting")
        return
    end
    local car = State.car
    local seat = car and car:FindFirstChild("DriveSeat")
    if seat == nil then
        Notify("error", "Spawn a vehicle before boosting")
        return
    end
    local velocity = seat.AssemblyLinearVelocity
    local speedMph = SpeedometerMph(velocity)
    if speedMph >= Boost.MaxSpeedMph then
        Notify("info", string.format("Already at the %.0f mph boost limit", Boost.MaxSpeedMph))
        return
    end
    local activeAxes = {}
    local axisCount = 0
    for _, axis in ipairs(BOOST_AXIS_OPTIONS) do
        if Boost.Axes[axis] then
            activeAxes[axis] = true
            axisCount = axisCount + 1
        end
    end
    if axisCount == 0 then
        Notify("error", "Select at least one boost axis")
        return
    end
    local hasCarDirection = activeAxes.Forward or activeAxes.Backward or activeAxes.Right or activeAxes.Left
    local direction = BoostAxesDirection(seat, velocity, activeAxes)
    if direction == nil then
        if hasCarDirection then
            Notify("error", "The selected boost axes cancel out")
        else
            Notify("error", "The car has to be moving to boost along velocity components")
        end
        return
    end
    Boost.Car = car
    Boost.ActiveAxes = activeAxes
    Boost.ActiveLabel = FormatBoostAxes(activeAxes)
    Boost.Elapsed = 0
    Boost.Active = true
    Boost.Connection = RunService.PreSimulation:Connect(StepBoost)
    Notify("success", string.format(
        "Boost: +%.1f studs/s over %.2fs along %s (max %.0f mph)",
        Boost.Strength,
        Boost.Duration,
        Boost.ActiveLabel,
        Boost.MaxSpeedMph
    ))
end

--=== fly ===================================================================

local StepFly

local function FlyInputBegan(input)
    if input.UserInputType ~= Enum.UserInputType.Keyboard then
        return
    end
    if UserInputService:GetFocusedTextBox() ~= nil then
        return
    end
    local code = input.KeyCode
    if code == Enum.KeyCode.W then
        Fly.Keys.W = true
    elseif code == Enum.KeyCode.A then
        Fly.Keys.A = true
    elseif code == Enum.KeyCode.S then
        Fly.Keys.S = true
    elseif code == Enum.KeyCode.D then
        Fly.Keys.D = true
    end
end

local function FlyInputEnded(input)
    if input.UserInputType ~= Enum.UserInputType.Keyboard then
        return
    end
    local code = input.KeyCode
    if code == Enum.KeyCode.W then
        Fly.Keys.W = false
    elseif code == Enum.KeyCode.A then
        Fly.Keys.A = false
    elseif code == Enum.KeyCode.S then
        Fly.Keys.S = false
    elseif code == Enum.KeyCode.D then
        Fly.Keys.D = false
    end
end

local function SetFlyMode(mode)
    if mode ~= "CFrame" and mode ~= "Velocity" then
        return
    end
    Fly.Mode = mode
    if Fly.Active and Fly.Seat ~= nil and Fly.Seat.Parent ~= nil then
        Fly.Seat.Anchored = mode == "CFrame"
    end
    Notify("info", "Fly movement: " .. mode)
end

local function SetFly(enabled)
    if enabled == Fly.Active then
        if Fly.Switch ~= nil then
            Fly.Switch.Set(Fly.Active)
        end
        return
    end

    if enabled then
        local car = State.car
        local seat = car and car:FindFirstChild("DriveSeat")
        if seat == nil then
            Notify("error", "Spawn a vehicle before flying")
            if Fly.Switch ~= nil then
                Fly.Switch.Set(false)
            end
            return
        end
        if Boost.Active then
            StopBoost(nil)
        end
        Fly.Active = true
        Fly.Car = car
        Fly.Seat = seat
        Fly.OriginalAnchored = seat.Anchored
        Fly.Keys = { W = false, A = false, S = false, D = false }
        seat.Anchored = Fly.Mode == "CFrame"
        pcall(function()
            seat.AssemblyLinearVelocity = Vector3.zero
            seat.AssemblyAngularVelocity = Vector3.zero
        end)
        Fly.Connection = RunService.PreSimulation:Connect(function(deltaTime)
            StepFly(deltaTime)
        end)
        table.insert(Fly.KeyConnections, UserInputService.InputBegan:Connect(FlyInputBegan))
        table.insert(Fly.KeyConnections, UserInputService.InputEnded:Connect(FlyInputEnded))
        if Fly.Switch ~= nil then
            Fly.Switch.Set(true)
        end
        Notify("success", string.format("Fly enabled (%s%s)", Fly.Mode, Fly.Lerp and ", lerp" or ""))
        return
    end

    Fly.Active = false
    if Fly.Connection ~= nil then
        pcall(function()
            Fly.Connection:Disconnect()
        end)
        Fly.Connection = nil
    end
    for _, connection in ipairs(Fly.KeyConnections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    Fly.KeyConnections = {}
    Fly.Keys = { W = false, A = false, S = false, D = false }
    local seat = Fly.Seat
    if seat ~= nil and seat.Parent ~= nil then
        seat.Anchored = Fly.OriginalAnchored
        pcall(function()
            seat.AssemblyLinearVelocity = Vector3.zero
            seat.AssemblyAngularVelocity = Vector3.zero
        end)
    end
    Fly.Seat = nil
    Fly.Car = nil
    if Fly.Switch ~= nil then
        Fly.Switch.Set(false)
    end
    Notify("info", "Fly disabled")
end

StepFly = function(deltaTime)
    if not Fly.Active then
        return
    end
    if State.window == nil
        or State.window.plate == nil
        or State.window.plate.Parent == nil
    then
        SetFly(false)
        return
    end
    local car = State.car
    local seat = Fly.Seat
    if car == nil or seat == nil or seat.Parent == nil or car ~= Fly.Car then
        SetFly(false)
        return
    end
    local camera = Workspace.CurrentCamera
    if camera == nil then
        return
    end

    local look = camera.CFrame.LookVector
    local right = camera.CFrame.RightVector
    local direction = Vector3.zero
    if Fly.Keys.W then
        direction = direction + look
    end
    if Fly.Keys.S then
        direction = direction - look
    end
    if Fly.Keys.D then
        direction = direction + right
    end
    if Fly.Keys.A then
        direction = direction - right
    end
    if direction.Magnitude > 0 then
        direction = direction.Unit
    end

    local maxSpeed = math.max(Fly.MaxSpeedMph, 0) / SPEEDOMETER_MPH_PER_STUD
    local alpha = Fly.Lerp and (1 - math.exp(-Fly.LerpRate * deltaTime)) or 1
    if Fly.Mode == "CFrame" then
        if not seat.Anchored then
            seat.Anchored = true
        end
        local current = seat.CFrame
        local targetPosition = current.Position + direction * maxSpeed * deltaTime
        local targetCFrame = CFrame.new(targetPosition) * camera.CFrame.Rotation
        seat.CFrame = current:Lerp(targetCFrame, alpha)
        return
    end

    if seat.Anchored then
        seat.Anchored = false
    end
    local velocity = seat.AssemblyLinearVelocity
    local targetVelocity = direction * maxSpeed
    seat.AssemblyLinearVelocity = Fly.Lerp and velocity:Lerp(targetVelocity, alpha) or targetVelocity
    pcall(function()
        seat.AssemblyAngularVelocity = Vector3.zero
    end)
end

local function KeybindMatches(bind, input)
    if bind == "None" then
        return false
    end
    local keyCode = Enum.KeyCode[bind]
    return keyCode ~= nil and input.KeyCode == keyCode
end

local function TriggerDriveKeybind(bind)
    if State.window == nil
        or State.window.plate == nil
        or State.window.plate.Parent == nil
    then
        return
    end
    if UserInputService:GetFocusedTextBox() ~= nil then
        return
    end
    if Boost.Keybind == bind then
        StartBoost()
        return
    end
    if Fly.Keybind == bind then
        SetFly(not Fly.Active)
    end
end

local function HandleDriveKeybind(input)
    if State.window == nil
        or State.window.plate == nil
        or State.window.plate.Parent == nil
    then
        return
    end
    if UserInputService:GetFocusedTextBox() ~= nil then
        return
    end
    if KeybindMatches(Boost.Keybind, input) then
        StartBoost()
        return
    end
    if KeybindMatches(Fly.Keybind, input) then
        SetFly(not Fly.Active)
    end
end

-- A conservative high-speed setup: put the suspension and damping back inside the ranges the
-- game's own editor uses, lower the centre of gravity, weigh the car for its springs, and lean on
-- AWD/TCS/ABS with track tires and calmer steering. It does not touch the gearing or the redline,
-- so the car keeps its top speed.
local function StabilizeHighSpeed()
    local car = State.car
    if car == nil then
        Notify("error", "Spawn a vehicle before stabilizing it")
        return
    end

    local limits = SuspensionLimits()
    local profile = {
        ["Car.SuspensionTune_Height"]       = math.min(0.30, limits.Height or 0.32),
        ["Car.SuspensionTune_FrontCamber"]  = -3,
        ["Car.SuspensionTune_RearCamber"]   = -3,
        ["Car.SuspensionTune_FrontOffset"]  = limits.FrontOffset or 0.3,
        ["Car.SuspensionTune_RearOffset"]   = limits.RearOffset or 0.3,
        ["Car.Dynamics_FSuspStiffMult"]     = 1.1666666666666667,
        ["Car.Dynamics_RSuspStiffMult"]     = 1.1666666666666667,
        ["Car.Dynamics_FSuspDampMult"]      = 1.45,
        ["Car.Dynamics_RSuspDampMult"]      = 1.45,
        ["Car.Dynamics_Drivetrain"]         = "AWD",
        ["Car.Dynamics_Traction"]           = true,
        ["Car.Dynamics_Antilock"]           = true,
        ["Car.Dynamics_BrakeBias"]          = -1,
        ["Car.Dynamics_SteerAngleMult"]     = 0.7,
        ["Car.Dynamics_SteerTorqueMult"]    = 0.9,
        ["Car.Dynamics_SteerDampMult"]      = 1.3,
        ["Car.Dynamics_SteerDecayMult"]     = 1.0,
        ["Wheels.Friction_UseLocalValues"]  = true,
        ["Wheels.Friction_DryRoad"]         = 1.0,
        ["Wheels.Friction_WetRoad"]         = 0.6,
        ["Wheels.Friction_DryDirt"]         = 0.45,
        ["Wheels.Friction_WetDirt"]         = 0.35,
        ["Wheels.Friction_DryGrass"]        = 0.45,
        ["Wheels.Friction_WetGrass"]        = 0.3,
        ["Motor.WeightDist"]                = 50,
    }

    local compound = PickTireCompound("Racing Slick")
    if compound ~= nil then
        profile["Car.Dynamics_FTireCompound"] = compound
        profile["Car.Dynamics_RTireCompound"] = compound
    end

    local weightEntry = FindEntry("Motor.Weight")
    if weightEntry ~= nil and not weightEntry.readOnly then
        local current = tonumber(weightEntry.getValue()) or 6000
        profile["Motor.Weight"] = math.clamp(current, 5500, 6500)
    end

    local cgEntry = FindEntry("Motor.CGHeight")
    if cgEntry ~= nil and not cgEntry.readOnly then
        local current = tonumber(cgEntry.getValue()) or 0.5
        profile["Motor.CGHeight"] = math.min(current, 0.5)
    end

    local applied, skipped = 0, 0
    for id, value in pairs(profile) do
        local entry = FindEntry(id)
        if entry ~= nil and not entry.readOnly then
            if ApplyProperty(entry, value, true) then
                applied = applied + 1
            else
                skipped = skipped + 1
            end
        else
            skipped = skipped + 1
        end
    end

    if applied == 0 then
        Notify("error", "No high-speed properties matched this vehicle")
        return
    end
    SetDownforce(true)
    SetWheelLock(true)
    LogInfo(string.format("High-speed setup: %d applied, %d skipped, downforce + wheel lock on", applied, skipped))
    Notify("success", string.format(
        "High-speed setup applied (%d properties) + downforce + wheel lock · re-enter for chassis tuning",
        applied
    ))
end

-- Read every row back from the live car and the tune, without touching either. This is the button
-- to reach for when something changed the car behind the editor's back and the rows look stale.
local function RefreshVehicleValues()
    local car = State.car
    if car == nil then
        Notify("error", "Spawn a vehicle before refreshing its values")
        return
    end
    ReleaseVehicleInputs()

    local signature = StructureSignature()
    if signature ~= State.structureKey then
        State.structureKey = signature
        State.entries = CollectEntries()
        RenderPropertyList()
        RenderSnapshotPanel()
        RenderHeader()
    end

    local refreshed = 0
    for _, entry in ipairs(State.entries) do
        local value = entry.getValue()
        if value ~= nil then
            entry.value = value
            if entry.widget ~= nil and entry.widget.Apply ~= nil then
                pcall(entry.widget.Apply, value)
            end
            refreshed = refreshed + 1
        end
    end
    RefreshDerivedEntries()
    UpdateSnapshotStatus()
    Notify("success", string.format("Refreshed %d property values", refreshed))
end

--=== render ================================================================

local function RenderAll()
    RenderHeader()
    RenderSnapshotPanel()
    RenderPropertyList()
    UpdateSnapshotStatus()
end

-- The window is as tall as its contents on desktop, so the property list gives up the height the
-- selection panel takes rather than pushing the Unload button off the bottom of the screen.
local function UpdateListHeight()
    if State.listFrame == nil then
        return
    end
    local height = State.listHeight
    if State.panelOpen then
        height = math.max(180, height - SelectionListSize)
    end
    State.listFrame.Size = UDim2.new(1, 0, 0, height)
end

--=== vehicle binding =======================================================

local function DisconnectCar()
    for _, connection in ipairs(State.carConnections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    State.carConnections = {}
end

local function ScheduleStructureCheck()
    if State.structurePending then
        return
    end
    State.structurePending = true
    task.delay(0.25, function()
        State.structurePending = false
        local signature = StructureSignature()
        if signature == State.structureKey then
            return
        end
        State.structureKey = signature
        State.entries = CollectEntries()
        RenderPropertyList()
        RenderSnapshotPanel()
        RenderHeader()
    end)
end

local BindVehicle

function BindVehicle()
    if State.window == nil then
        return
    end
    local sessionVehicles = Workspace:FindFirstChild("SessionVehicles")
    local car = sessionVehicles and sessionVehicles:FindFirstChild(Player.Name .. "-Car")
    local previousCar = State.car

    DisconnectCar()
    State.pollToken    = State.pollToken + 1
    State.car          = car
    State.wheels       = car and car:FindFirstChild("Wheels")
    State.tune         = nil
    State.tuneModule   = nil

    if previousCar ~= car then
        State.presetDeleteId = nil
        if State.presetRenameId ~= nil then
            HideRenameBar()
        end
    end

    if car ~= nil then
        State.tuneModule = car:FindFirstChild("A-Chassis Tune")
        if State.tuneModule ~= nil then
            local loaded, tune = pcall(require, State.tuneModule)
            if loaded and type(tune) == "table" then
                State.tune = tune
            else
                LogError(string.format("A-Chassis Tune could not be read: %s", tostring(tune)))
            end
        else
            LogError("This vehicle has no A-Chassis Tune - motor properties are unavailable")
        end
    end

    State.entries      = CollectEntries()
    State.structureKey = StructureSignature()
    StartTunePolling(State.pollToken)

    if car == nil then
        LogError("No vehicle is spawned for " .. Player.Name .. " - waiting for one")
        RenderAll()
        if PresetsIsActive() then
            RenderPresets()
        end
        return
    end

    table.insert(State.carConnections, car.AttributeChanged:Connect(ScheduleStructureCheck))
    table.insert(State.carConnections, car.ChildAdded:Connect(function(child)
        if child.Name == "Wheels" or child.Name == "A-Chassis Tune" then
            task.defer(BindVehicle)
        end
    end))
    table.insert(State.carConnections, car.ChildRemoved:Connect(function(child)
        if child.Name == "Wheels" or child.Name == "A-Chassis Tune" then
            task.defer(BindVehicle)
        end
    end))
    if State.wheels ~= nil then
        table.insert(State.carConnections, State.wheels.AttributeChanged:Connect(ScheduleStructureCheck))
    end
    local carIdValue = car:FindFirstChild("CarID")
    if carIdValue ~= nil then
        table.insert(State.carConnections, carIdValue.Changed:Connect(function()
            State.entries = CollectEntries()
            RenderAll()
            if PresetsIsActive() then
                RenderPresets()
            end
        end))
    end

    LogInfo(string.format("Bound '%s' with %d properties", car.Name, #State.entries))
    RenderAll()
    MaybeAutoLoad()
    if PresetsIsActive() then
        RenderPresets()
    end
end

--=== drive interface =======================================================

local function CreateBoostAxisRow(parent, order, axis)
    local row = MonoUI.Element {
        ClassName              = "TextButton",
        Parent                 = parent,
        Name                   = axis,
        AutoButtonColor        = false,
        Text                   = "",
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, 0, 24),
        LayoutOrder            = order,
        ZIndex                 = 2,
    }
    local box = MonoUI.Sticker(MonoUI.Element {
        ClassName              = "Frame",
        Parent                 = row,
        Name                   = "Box",
        BackgroundColor3       = Theme.Well,
        BackgroundTransparency = Theme.WellAlpha,
        Size                   = UDim2.fromOffset(14, 14),
        Position               = UDim2.new(0, 2, 0.5, -7),
        ZIndex                 = 3,
    }, { Corner = 4, Stroke = "Line" })

    local mark = MonoUI.Element {
        ClassName        = "Frame",
        Parent           = box,
        Name             = "Mark",
        BackgroundColor3 = Theme.Text,
        BorderSizePixel  = 0,
        Size             = UDim2.fromOffset(8, 8),
        Position         = UDim2.new(0.5, -4, 0.5, -4),
        Visible          = false,
        ZIndex           = 4,
    }
    MonoUI.Element {
        ClassName    = "UICorner",
        Parent       = mark,
        CornerRadius = UDim.new(0, 2),
    }

    MonoUI.Texted(row, {
        Text     = axis,
        Size     = Theme.Type.Body,
        Tint     = "Text",
        Bold     = false,
        Position = UDim2.fromOffset(24, 0),
        Size2    = UDim2.new(1, -28, 1, 0),
        ZIndex   = 3,
    })

    local function Refresh()
        local selected = Boost.Axes[axis] == true
        mark.Visible = selected
        row.BackgroundTransparency = selected and 0.94 or 1
    end

    row.MouseButton1Click:Connect(function()
        Boost.Axes[axis] = not Boost.Axes[axis]
        Refresh()
        UpdateBoostAxisStatus()
        SaveDriveConfigSoon()
    end)

    Refresh()
    table.insert(Boost.AxisRefreshers, Refresh)
end

local function CreateDriveNumberRow(parent, order, label, value, onCommit)
    local row = MonoUI.Row(parent, order, 34)
    MonoUI.Texted(row, {
        Text     = label,
        Size     = Theme.Type.Body,
        Tint     = "Muted",
        Size2    = UDim2.new(0.56, 0, 1, 0),
    })
    local input = MonoUI.Input {
        Parent   = row,
        Size     = UDim2.new(0.40, 0, 0, 26),
        Position = UDim2.new(0.60, 0, 0, 4),
        Text     = tostring(value),
        X        = Enum.TextXAlignment.Center,
        NumbersOnly = true,
        SubmitOnEnter = true,
        OnSubmit = function(text)
            local number = tonumber(text)
            if number ~= nil then
                onCommit(number)
            end
        end,
    }
    return input
end

local function CreateDriveInterface(tab)
    local content = tab.content
    local order = 0
    local function NextOrder()
        order = order + 1
        return order
    end

    MonoUI.Heading(content, NextOrder(), "Boost")
    Boost.StrengthInput = CreateDriveNumberRow(content, NextOrder(), "Strength (studs/s)", Boost.Strength, function(value)
        if value <= 0 then
            Notify("error", "Boost strength must be positive")
            return
        end
        Boost.Strength = value
        SaveDriveConfigSoon()
        Notify("success", string.format("Boost strength: %.1f", value))
    end)
    Boost.MaxSpeedInput = CreateDriveNumberRow(content, NextOrder(), "Max speed (speedometer mph)", Boost.MaxSpeedMph, function(value)
        if value <= 0 then
            Notify("error", "Boost max speed must be positive")
            return
        end
        Boost.MaxSpeedMph = value
        SaveDriveConfigSoon()
        Notify("success", string.format("Boost max speed: %.0f mph", value))
    end)
    Boost.DurationInput = CreateDriveNumberRow(content, NextOrder(), "Duration (s)", Boost.Duration, function(value)
        if value <= 0 then
            Notify("error", "Boost duration must be positive")
            return
        end
        Boost.Duration = value
        SaveDriveConfigSoon()
        Notify("success", string.format("Boost duration: %.2fs", value))
    end)
    MonoUI.Button {
        Parent  = content,
        Caption = "Boost Axes",
        Order   = NextOrder(),
        OnClick = function()
            Boost.AxisOpen = not Boost.AxisOpen
            Boost.AxisPanel.Visible = Boost.AxisOpen
            Boost.AxisPanel.Size = UDim2.new(1, 0, 0, Boost.AxisOpen and 242 or 0)
        end,
    }
    Boost.AxisStatus = MonoUI.Texted(content, {
        Text        = "Selected: " .. FormatBoostAxes(Boost.Axes),
        Size        = Theme.Type.Support,
        Tint        = "Muted",
        Bold        = false,
        Size2       = UDim2.new(1, 0, 0, 16),
        LayoutOrder = NextOrder(),
    })
    local axisPanel = MonoUI.Element {
        ClassName              = "Frame",
        Parent                 = content,
        Name                   = "BoostAxes",
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, 0, 0),
        LayoutOrder            = NextOrder(),
        Visible                = false,
    }
    MonoUI.Element {
        ClassName = "UIListLayout",
        Parent    = axisPanel,
        Padding   = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }
    Boost.AxisPanel = axisPanel
    local axisOrder = 0
    local function NextAxisOrder()
        axisOrder = axisOrder + 1
        return axisOrder
    end
    local axisSelectRow = MonoUI.Row(axisPanel, NextAxisOrder(), 28)
    local axisSelectCell = MonoUI.Columns(axisSelectRow, 2, 6, 26)
    MonoUI.Button {
        Parent  = axisSelectRow,
        Caption = "Select All",
        Size    = axisSelectCell,
        Order   = 1,
        OnClick = function()
            SetAllBoostAxes(true)
        end,
    }
    MonoUI.Button {
        Parent  = axisSelectRow,
        Caption = "Unselect All",
        Size    = axisSelectCell,
        Order   = 2,
        OnClick = function()
            SetAllBoostAxes(false)
        end,
    }
    MonoUI.Heading(axisPanel, NextAxisOrder(), "Boost axes")
    local axisScroller = MonoUI.Element {
        ClassName              = "ScrollingFrame",
        Parent                 = axisPanel,
        Name                   = "AxisList",
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        ScrollBarThickness     = 4,
        Size                   = UDim2.new(1, 0, 0, 180),
        CanvasSize             = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize    = Enum.AutomaticSize.Y,
        LayoutOrder            = NextAxisOrder(),
        ZIndex                 = 2,
    }
    MonoUI.Element {
        ClassName = "UIListLayout",
        Parent    = axisScroller,
        Padding   = UDim.new(0, 2),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }
    for axisIndex, axis in ipairs(BOOST_AXIS_OPTIONS) do
        CreateBoostAxisRow(axisScroller, axisIndex, axis)
    end
    Boost.KeySelect = MonoUI.Select {
        Parent   = content,
        Caption  = "Boost Key",
        Options  = KEYBIND_OPTIONS,
        Value    = Boost.Keybind,
        Order    = NextOrder(),
        OnSelect = function(option)
            Boost.Keybind = option
            SaveDriveConfigSoon()
            Notify("info", "Boost key: " .. option)
        end,
    }
    MonoUI.Button {
        Parent  = content,
        Caption = "Boost",
        Order   = NextOrder(),
        OnClick = function()
            StartBoost()
        end,
    }
    MonoUI.Texted(content, {
        Text        = "Adds Strength along the selected velocity components and car directions; stops at Max speed.",
        Size        = Theme.Type.Support,
        Tint        = "Muted",
        Bold        = false,
        Size2       = UDim2.new(1, 0, 0, 16),
        LayoutOrder = NextOrder(),
    })

    MonoUI.Heading(content, NextOrder(), "Fly")
    Fly.Switch = MonoUI.Switch {
        Parent   = content,
        Caption  = "Enable Fly",
        Value    = false,
        Order    = NextOrder(),
        OnChange = function(value)
            SetFly(value)
        end,
    }
    Fly.ModeSelect = MonoUI.Select {
        Parent   = content,
        Caption  = "Movement",
        Options  = { "CFrame", "Velocity" },
        Value    = Fly.Mode,
        Order    = NextOrder(),
        OnSelect = function(option)
            SetFlyMode(option)
            SaveDriveConfigSoon()
        end,
    }
    Fly.LerpSwitch = MonoUI.Switch {
        Parent   = content,
        Caption  = "Lerp Movement",
        Value    = Fly.Lerp,
        Order    = NextOrder(),
        OnChange = function(value)
            Fly.Lerp = value
            SaveDriveConfigSoon()
        end,
    }
    Fly.MaxSpeedInput = CreateDriveNumberRow(content, NextOrder(), "Max fly speed (speedometer mph)", Fly.MaxSpeedMph, function(value)
        if value <= 0 then
            Notify("error", "Fly speed must be positive")
            return
        end
        Fly.MaxSpeedMph = value
        SaveDriveConfigSoon()
        Notify("success", string.format("Fly max speed: %.0f mph", value))
    end)
    Fly.KeySelect = MonoUI.Select {
        Parent   = content,
        Caption  = "Fly Key",
        Options  = KEYBIND_OPTIONS,
        Value    = Fly.Keybind,
        Order    = NextOrder(),
        OnSelect = function(option)
            Fly.Keybind = option
            SaveDriveConfigSoon()
            Notify("info", "Fly key: " .. option)
        end,
    }
    MonoUI.Texted(content, {
        Text        = "W/A/S/D move relative to the camera; CFrame anchors the seat, Velocity keeps it physical.",
        Size        = Theme.Type.Support,
        Tint        = "Muted",
        Bold        = false,
        Size2       = UDim2.new(1, 0, 0, 16),
        LayoutOrder = NextOrder(),
    })
end

--=== interface =============================================================

local function CreateInterface()
    local window = MonoUI:CreateWindow {
        Name  = "VEHICLE PROPERTIES",
        Width = 620,
        Hint  = "RIGHT CONTROL TO HIDE",
    }
    local vehicleTab = window:CreateTab("Vehicle")
    local driveTab = window:CreateTab("Drive")
    local presetsTab = window:CreateTab("Presets")

    State.window  = window
    State.content = vehicleTab.content

    ToastHost = MonoUI.Element {
        ClassName              = "Frame",
        Parent                 = window.plate.Parent,
        Name                   = "VehicleToasts",
        BackgroundTransparency = 1,
        AnchorPoint            = Vector2.new(1, 1),
        Position               = UDim2.new(1, -16, 1, -16),
        Size                   = UDim2.fromOffset(ToastWidth, 0),
        AutomaticSize          = Enum.AutomaticSize.Y,
        ZIndex                 = 200,
    }
    MonoUI.Element {
        ClassName           = "UIListLayout",
        Parent              = ToastHost,
        Padding             = UDim.new(0, 6),
        SortOrder           = Enum.SortOrder.LayoutOrder,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment   = Enum.VerticalAlignment.Bottom,
    }

    local order = 0
    local function NextOrder()
        order = order + 1
        return order
    end

    local headerRow = MonoUI.Row(State.content, NextOrder(), 150)
    MonoUI.Sticker(headerRow, {
        Color  = "Well",
        Alpha  = Theme.WellAlpha,
        Corner = "RowRadius",
        Stroke = "Line",
    })
    State.headerRow = headerRow

    local actionRow = MonoUI.Row(State.content, NextOrder(), 30)
    local actionCell = MonoUI.Columns(actionRow, 2, 6, 30)
    local function CreateActionCell(order, caption, helpTitle, helpText, onClick)
        local cell = MonoUI.Element {
            ClassName             = "Frame",
            Parent                = actionRow,
            BackgroundTransparency = 1,
            Size                  = actionCell,
            LayoutOrder           = order,
        }
        MonoUI.Help {
            Parent   = cell,
            Position = UDim2.fromOffset(0, 7),
            Title    = helpTitle,
            Text     = helpText,
        }
        MonoUI.Button {
            Parent   = cell,
            Caption  = caption,
            Size     = UDim2.new(1, -20, 0, 30),
            Position = UDim2.fromOffset(20, 0),
            OnClick  = onClick,
        }
    end
    CreateActionCell(1, "Stabilize High Speed", "Stabilize High Speed", FEATURE_HELP.Stabilize, function()
        StabilizeHighSpeed()
    end)
    CreateActionCell(2, "Refresh Values", "Refresh Values", FEATURE_HELP.Refresh, function()
        RefreshVehicleValues()
    end)
    MonoUI.Texted(State.content, {
        Text        = "AWD · TCS/ABS · suspension clamped to the game's limits · track tires · lower CG",
        Size        = Theme.Type.Support,
        Tint        = "Muted",
        Bold        = false,
        Size2       = UDim2.new(1, 0, 0, 16),
        LayoutOrder = NextOrder(),
    })
    MonoUI.Heading(State.content, NextOrder(), "Builders")
    local function CreateBuilderRow(caption, helpKey, onClick)
        local row = MonoUI.Row(State.content, NextOrder(), 30)
        MonoUI.Help {
            Parent   = row,
            Position = UDim2.fromOffset(0, 7),
            Title    = caption,
            Text     = FEATURE_HELP[helpKey],
        }
        MonoUI.Button {
            Parent   = row,
            Caption  = caption,
            Size     = UDim2.new(1, -20, 0, 30),
            Position = UDim2.fromOffset(20, 0),
            OnClick  = onClick,
        }
    end
    CreateBuilderRow("Gear Ratio Builder", "GearRatioBuilder", function()
        OpenGearRatioBuilder()
    end)
    CreateBuilderRow("Final Drive Builder", "FinalDriveBuilder", function()
        OpenFinalDriveBuilder()
    end)
    CreateBuilderRow("Max Speed Builder", "MaxSpeedBuilder", function()
        OpenMaxSpeedBuilder()
    end)
    local downforceRow = MonoUI.Row(State.content, NextOrder(), 30)
    MonoUI.Help {
        Parent   = downforceRow,
        Position = UDim2.fromOffset(0, 7),
        Title    = "Downforce Assist",
        Text     = FEATURE_HELP.Downforce,
    }
    Downforce.Switch = MonoUI.Switch {
        Parent   = downforceRow,
        Size     = UDim2.new(1, -20, 0, 30),
        Position = UDim2.fromOffset(20, 0),
        Caption  = "Downforce Assist",
        Value    = false,
        OnChange = function(value)
            SetDownforce(value)
        end,
    }
    local wheelLockRow = MonoUI.Row(State.content, NextOrder(), 30)
    MonoUI.Help {
        Parent   = wheelLockRow,
        Position = UDim2.fromOffset(0, 7),
        Title    = "Wheel Lock 300+",
        Text     = FEATURE_HELP.WheelLock,
    }
    WheelLock.Switch = MonoUI.Switch {
        Parent   = wheelLockRow,
        Size     = UDim2.new(1, -20, 0, 30),
        Position = UDim2.fromOffset(20, 0),
        Caption  = "Wheel Lock 300+",
        Value    = false,
        OnChange = function(value)
            SetWheelLock(value)
        end,
    }
    local panelButtonRow = MonoUI.Row(State.content, NextOrder(), 34)
    MonoUI.Help {
        Parent   = panelButtonRow,
        Position = UDim2.fromOffset(0, 9),
        Title    = "Save / Restore Properties",
        Text     = FEATURE_HELP.SaveRestore,
    }
    MonoUI.Button {
        Parent   = panelButtonRow,
        Caption  = "Save / Restore Properties",
        Size     = UDim2.new(1, -20, 0, 30),
        Position = UDim2.fromOffset(20, 2),
        OnClick  = function()
            State.panelOpen = not State.panelOpen
            RenderSnapshotPanel()
            UpdateListHeight()
        end,
    }

    local panelFrame = MonoUI.Element {
        ClassName              = "Frame",
        Parent                 = State.content,
        Name                   = "SnapshotPanel",
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, 0, 0),
        AutomaticSize          = Enum.AutomaticSize.Y,
        LayoutOrder            = NextOrder(),
        Visible                = false,
    }
    MonoUI.Element {
        ClassName = "UIListLayout",
        Parent    = panelFrame,
        Padding   = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }
    State.panelFrame = panelFrame

    local screenHeight = 1080
    local camera = Workspace.CurrentCamera
    if camera ~= nil then
        screenHeight = camera.ViewportSize.Y
    end
    local listHeight = math.clamp(screenHeight * 0.36, 240, 460)
    State.listHeight = listHeight

    local listFrame = MonoUI.Element {
        ClassName              = "ScrollingFrame",
        Parent                 = State.content,
        Name                   = "Properties",
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        ScrollBarThickness     = 4,
        Size                   = UDim2.new(1, 0, 0, listHeight),
        CanvasSize             = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize    = Enum.AutomaticSize.Y,
        LayoutOrder            = NextOrder(),
        ZIndex                 = 2,
    }
    MonoUI.Element {
        ClassName = "UIListLayout",
        Parent    = listFrame,
        Padding   = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }
    State.listFrame = listFrame

    local footerRow = MonoUI.Row(State.content, NextOrder(), 46)
    local footerCell = MonoUI.Columns(footerRow, 3, 8, 34)
    MonoUI.Element {
        ClassName              = "Frame",
        Parent                 = footerRow,
        BackgroundTransparency = 1,
        Size                   = footerCell,
        LayoutOrder            = 1,
    }
    local unloadCell = MonoUI.Element {
        ClassName              = "Frame",
        Parent                 = footerRow,
        BackgroundTransparency = 1,
        Size                   = footerCell,
        LayoutOrder            = 2,
    }
    MonoUI.Help {
        Parent   = unloadCell,
        Position = UDim2.fromOffset(0, 9),
        Title    = "Unload",
        Text     = FEATURE_HELP.Unload,
    }
    MonoUI.Button {
        Parent   = unloadCell,
        Caption  = "Unload",
        Size     = UDim2.new(1, -20, 0, 34),
        Position = UDim2.fromOffset(20, 0),
        OnClick  = function()
            Unload()
        end,
    }
    MonoUI.Element {
        ClassName              = "Frame",
        Parent                 = footerRow,
        BackgroundTransparency = 1,
        Size                   = footerCell,
        LayoutOrder            = 3,
    }

    -- The display spins ten degrees a second while nothing is dragging it. One loop for the app,
    -- reading whichever model the current header built, so a rebuilt header needs no new loop.
    table.insert(State.globalConnections, RunService.RenderStepped:Connect(function(deltaTime)
        if State.viewportDisplay == nil or State.window == nil or not State.window.visible then
            return
        end
        -- A mouse-up can be swallowed by the button that took the press. If the button is no
        -- longer down, the drag is over whether or not the release event arrived.
        if ViewportDrag.active
            and ViewportDrag.pointer == Enum.UserInputType.MouseButton1
            and not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
        then
            ViewportDrag.active = false
            ViewportDrag.pointer = nil
        end
        if not ViewportDrag.active then
            State.viewportYaw = (State.viewportYaw + 10 * deltaTime) % 360
        end
        ApplyDisplayTransform()
    end))

    table.insert(State.globalConnections, UserInputService.InputChanged:Connect(function(input)
        if not ViewportDrag.active then
            return
        end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        local position = Vector2.new(input.Position.X, input.Position.Y)
        local delta = position - ViewportDrag.last
        ViewportDrag.last = position
        State.viewportYaw = (State.viewportYaw + delta.X * 0.45) % 360
        State.viewportPitch = math.clamp(State.viewportPitch + delta.Y * 0.3, -20, 20)
    end))

    table.insert(State.globalConnections, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            ViewportDrag.active = false
            ViewportDrag.pointer = nil
        end
    end))

    CreateDriveInterface(driveTab)
    table.insert(State.globalConnections, UserInputService.InputBegan:Connect(HandleDriveKeybind))
    if DriveMouse ~= nil then
        if HasWheelForward then
            table.insert(State.globalConnections, DriveMouse.WheelForward:Connect(function()
                TriggerDriveKeybind("Wheel Forward")
            end))
        end
        if HasWheelBackward then
            table.insert(State.globalConnections, DriveMouse.WheelBackward:Connect(function()
                TriggerDriveKeybind("Wheel Backward")
            end))
        end
    end
    CreatePresetInterface(presetsTab)
    State.presetsTab = presetsTab
    if type(vehicleTab.Focus) == "function" then
        vehicleTab.Focus()
    end
    presetsTab.button.MouseButton1Click:Connect(function()
        RenderPresets()
    end)
end

function Unload()
    LogInfo("Unloading the vehicle property editor")
    pcall(function()
        MonoUI:CloseDialogs()
    end)
    State.pollToken = State.pollToken + 1
    SetDownforce(false)
    SetWheelLock(false)
    StopBoost(nil)
    SetFly(false)
    Downforce.Switch = nil
    WheelLock.Switch = nil
    Fly.Switch = nil
    Fly.ModeSelect = nil
    Fly.LerpSwitch = nil
    Boost.KeySelect = nil
    Fly.KeySelect = nil
    Boost.AxisPanel = nil
    Boost.AxisStatus = nil
    Boost.AxisRefreshers = {}
    State.builderDialog = nil
    State.viewport = nil
    State.viewportDisplay = nil
    State.viewportCenter = nil
    for _, connection in ipairs(State.globalConnections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    State.globalConnections = {}
    DisconnectCar()

    for _, connection in ipairs(State.rowConnections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    State.rowConnections = {}

    for _, menu in ipairs(State.selectMenus) do
        pcall(function()
            menu:Destroy()
        end)
    end
    State.selectMenus = {}

    if ToastHost ~= nil then
        ToastHost:Destroy()
        ToastHost = nil
    end
    ToastList = {}

    if State.window ~= nil then
        State.window:Destroy()
        State.window = nil
    end
end

--=== start =================================================================

CleanupStaleMonoUIHandlers()
CreateInterface()
ReadPresetsFile()

task.spawn(function()
    local sessionVehicles = Workspace:WaitForChild("SessionVehicles", 30)
    if State.window == nil then
        return
    end
    if sessionVehicles == nil then
        LogError("Workspace.SessionVehicles never appeared")
        BindVehicle()
        return
    end

    table.insert(State.globalConnections, sessionVehicles.ChildAdded:Connect(function(child)
        if child.Name == Player.Name .. "-Car" then
            task.delay(0.5, BindVehicle)
        end
    end))
    table.insert(State.globalConnections, sessionVehicles.ChildRemoved:Connect(function(child)
        if child.Name == Player.Name .. "-Car" then
            task.delay(0.2, BindVehicle)
        end
    end))

    BindVehicle()
    Notify("info", "Vehicle property editor loaded")
end)

return State.window
