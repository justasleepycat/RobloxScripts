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
        - Reports every apply, save and restore in a toast and in the window's status line.

    Layout
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
    print("[!] [VehicleProperties] MonoUI is missing - pass it in, set it globally, or put MonoUI.lua beside this script")
    return
end

local Players           = game:GetService("Players")
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
    viewport           = nil,
    viewportDisplay    = nil,
    viewportCenter     = nil,
    viewportYaw        = 25,
    viewportPitch      = 8,
    viewportRefresh    = false,
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

-- Assigned with the display, but needed by the apply path above it.
local ScheduleViewportRefresh

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
    print(string.format("[i] [%s] %s", Scope, message))
end

local function LogError(message)
    print(string.format("[!] [%s] %s", Scope, message))
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

-- The same arithmetic the dealership uses for its speed spec: the driven wheel's diameter, the
-- redline, the last gear ratio and the final drive, in the unit the car's speedometer speaks.
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

--=== toasts ================================================================

local ToastLooks = {
    success = { prefix = "[i]", tint = Theme.Text },
    info    = { prefix = "[i]", tint = Theme.Muted },
    error   = { prefix = "[!]", tint = Color3.fromRGB(255, 128, 128) },
}

local function Notify(kind, message)
    local look = ToastLooks[kind] or ToastLooks.info
    print(string.format("%s [%s] %s", look.prefix, Scope, message))

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

local function ApplyBrakes()
    local wheels = State.wheels
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

local function ApplyRimDecal()
    local car = State.car
    local wheels = State.wheels
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

local function ApplyPlateText()
    local car = State.car
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
    local swatch = MonoUI.Sticker(MonoUI.Element {
        ClassName        = "Frame",
        Parent           = row,
        Name             = "Swatch",
        BackgroundColor3 = entry.value,
        Size             = UDim2.fromOffset(24, 24),
        Position         = UDim2.new(0.52, 0, 0, 3),
        ZIndex           = 3,
    }, { Corner = "RowRadius", Stroke = "Line" })

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
            swatch.BackgroundColor3 = value
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
    MonoUI.Texted(row, {
        Text     = entry.label,
        Size     = Theme.Type.Body,
        Tint     = "Text",
        Bold     = false,
        Position = UDim2.fromOffset(0, 0),
        Size2    = UDim2.new(0.50, -4, 1, 0),
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
    return {
        id         = targetName .. "." .. key,
        key        = key,
        label      = key,
        target     = target,
        targetName = targetName,
        source     = "Attribute",
        kind       = KindOf(value),
        value      = value,
        group      = GroupOf(key),
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
        table.insert(entries, DerivedEntry("MaxSpeed", "Max speed (mph)", ComputeMaxSpeed, 1))
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

    DisconnectCar()
    State.pollToken    = State.pollToken + 1
    State.car          = car
    State.wheels       = car and car:FindFirstChild("Wheels")
    State.tune         = nil
    State.tuneModule   = nil

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
        end))
    end

    LogInfo(string.format("Bound '%s' with %d properties", car.Name, #State.entries))
    RenderAll()
end

--=== interface =============================================================

local Unload

local function CreateInterface()
    local window = MonoUI:CreateWindow {
        Name  = "VEHICLE PROPERTIES",
        Width = 620,
        Hint  = "RIGHT CONTROL TO HIDE",
    }
    local tab = window:CreateTab("Vehicle")

    State.window  = window
    State.content = tab.content

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

    local panelButtonRow = MonoUI.Row(State.content, NextOrder(), 34)
    MonoUI.Button {
        Parent  = panelButtonRow,
        Caption = "Save / Restore Properties",
        OnClick = function()
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
end

function Unload()
    LogInfo("Unloading the vehicle property editor")
    State.pollToken = State.pollToken + 1
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

CreateInterface()

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
