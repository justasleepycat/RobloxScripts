--[[ GreenvilleVehicleProperties.lua ==========================================
    A client-side property editor for the vehicle you have spawned in Greenville.

    What it does
        - Lists every attribute of your spawned car and of its Wheels model, grouped by the part of
          the car they belong to (paint, interior, plates, rims, brakes, suspension, dynamics,
          friction, condition), with a typed editor per row: a switch for booleans, a numeric box
          for numbers, a hex box and swatch for colours, a dropdown for enums and for the few
          strings that are really an enumeration, and a text box for everything else.
        - Applies the values that have a live client-side effect straight away (body paint,
          interior trim, brake colour, rim decal, plate text). Dynamics and suspension are written
          to the vehicle as well, but A-Chassis reads those while it initialises, so the value is
          stored on the client's copy without changing this spawn's handling.
        - Watches every attribute it lists, so a value the game changes (odometer, dirt level, an
          attribute the server rewrote) updates in the window without a refresh.
        - Saves a snapshot of the properties you tick and restores it later, with Select All and
          Unselect All at the top of the selection list.
        - Shows the car's preview image, taken from the same CarData module the spawn menu uses
          (`VehicleImagePreview`), and reloads the header if the vehicle is respawned.
        - Reports every apply, save and restore in a toast and in the window's status line.

    Layout
        |--------------------------------------------------------------|
        | Car name                                  Preview image       |
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
local TweenService      = game:GetService("TweenService")
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
        entry.target:SetAttribute(entry.key, value)
    end)
    if not applied then
        LogError(string.format("Failed to set %s: %s", entry.id, tostring(problem)))
        if not silent then
            Notify("error", string.format("%s failed: %s", entry.key, tostring(problem)))
        end
        return false
    end

    local refreshed, visualProblem = pcall(ApplyVisuals, entry.key)
    if not refreshed then
        LogError(string.format("%s was written but the visual refresh failed: %s", entry.id, tostring(visualProblem)))
        if not silent then
            Notify("error", string.format("%s written, visual failed: %s", entry.key, tostring(visualProblem)))
        end
        return false
    end

    if not silent then
        local hint = ReadAtSpawn(entry.key) and " (read by A-Chassis at spawn)" or ""
        Notify("success", string.format("Applied %s = %s%s", entry.key, FormatValue(value), hint))
    end
    return true
end

--=== snapshot ==============================================================

local function SelectedEntries()
    local selected = {}
    for _, entry in ipairs(State.entries) do
        if State.selection[entry.id] ~= false then
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
        values[entry.id] = entry.target:GetAttribute(entry.key)
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
        elseif ApplyProperty(entry, value, true) then
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
        name    = car.Name,
        brand   = "",
        trim    = "",
        carId   = "",
        preview = nil,
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

    identity.name    = tostring(data.VehicleName or identity.name)
    identity.brand   = tostring(data.VehicleBrand or "")
    identity.preview = data.VehicleImagePreview
    return identity
end

-- Restricted previews are not an asset id of their own: the game swaps them for an image from a
-- client module. That module can yield, so it resolves in the background and fills the label in
-- when it is done.
local function ResolvePreviewImage(preview, carId, imageLabel)
    if type(preview) ~= "number" or preview <= 0 then
        return nil
    end
    local restricted = ReplicatedStorage:GetAttribute("RestrictedImage")
    if restricted == nil or preview ~= restricted then
        return "rbxassetid://" .. tostring(preview)
    end

    task.spawn(function()
        local clientModules = ReplicatedStorage:FindFirstChild("ClientModules")
        local resolverModule = clientModules and clientModules:FindFirstChild("GetRestrictedPreview")
        if resolverModule == nil then
            LogError("Restricted preview module is not present")
            return
        end
        local required, resolver = pcall(require, resolverModule)
        if not required or type(resolver) ~= "function" then
            LogError("Restricted preview module could not be read")
            return
        end
        local resolved, image = pcall(resolver, carId)
        if not resolved or type(image) ~= "string" then
            LogError("Restricted preview could not be resolved")
            return
        end
        if imageLabel.Parent ~= nil then
            imageLabel.Image = image
        end
    end)
    return nil
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

    local imageLabel = MonoUI.Sticker(MonoUI.Element {
        ClassName              = "ImageLabel",
        Parent                 = header,
        Name                   = "CarImage",
        BackgroundColor3       = Theme.Well,
        BackgroundTransparency = Theme.WellAlpha,
        Image                  = "",
        Size                   = UDim2.new(0, 238, 1, -12),
        Position               = UDim2.new(1, -250, 0, 6),
        ScaleType              = Enum.ScaleType.Fit,
        ZIndex                 = 2,
    }, { Corner = "RowRadius", Stroke = "Line" })

    local image = ResolvePreviewImage(identity.preview, identity.carId, imageLabel)
    if image ~= nil then
        imageLabel.Image = image
    end

    MonoUI.Texted(header, {
        Text     = identity.name,
        Size     = Theme.Type.Title + 2,
        Tint     = "Text",
        Position = UDim2.fromOffset(14, 14),
        Size2    = UDim2.new(1, -272, 0, 24),
        ZIndex   = 3,
    })
    MonoUI.Texted(header, {
        Text     = subtitle,
        Size     = Theme.Type.Body,
        Tint     = "Muted",
        Bold     = false,
        Position = UDim2.fromOffset(14, 42),
        Size2    = UDim2.new(1, -272, 0, 18),
        ZIndex   = 3,
    })
    MonoUI.Texted(header, {
        Text     = string.format("%d properties · %s", #State.entries, identity.carId ~= "" and identity.carId or car.Name),
        Size     = Theme.Type.Support,
        Tint     = "Muted",
        Bold     = false,
        Position = UDim2.fromOffset(14, 66),
        Size2    = UDim2.new(1, -272, 0, 16),
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
        X               = Enum.TextXAlignment.Right,
        PlaceholderText = "number",
        OnSubmit        = function(text)
            local value = tonumber(text)
            if value == nil or value ~= value or value == math.huge or value == -math.huge then
                Notify("error", string.format("%s needs a number", entry.key))
                control.Text = FormatValue(entry.target:GetAttribute(entry.key))
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
        X               = Enum.TextXAlignment.Right,
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
        X               = Enum.TextXAlignment.Right,
        PlaceholderText = "#RRGGBB",
        OnSubmit        = function(text)
            local color = ParseColor(text)
            if color == nil then
                Notify("error", string.format("%s needs #RRGGBB or R,G,B", entry.key))
                local current = entry.target:GetAttribute(entry.key)
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

local function CreateReadOnlyEditor(row, entry)
    MonoUI.Texted(row, {
        Text     = FormatValue(entry.value),
        Size     = Theme.Type.Support,
        Tint     = "Muted",
        Bold     = false,
        X        = Enum.TextXAlignment.Right,
        Position = UDim2.new(0.52, 0, 0, 0),
        Size2    = UDim2.new(0.48, 0, 1, 0),
        ZIndex   = 3,
    })
    return {}
end

local function CreateEditor(row, entry)
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
        Text     = entry.key,
        Size     = Theme.Type.Body,
        Tint     = "Text",
        Bold     = false,
        Position = UDim2.fromOffset(0, 0),
        Size2    = UDim2.new(0.50, -4, 1, 0),
        ZIndex   = 3,
    })

    local widget = CreateEditor(row, entry)

    local connection = entry.target:GetAttributeChangedSignal(entry.key):Connect(function()
        local value = entry.target:GetAttribute(entry.key)
        if value == nil or widget.Apply == nil then
            return
        end
        local applied = pcall(widget.Apply, value)
        if not applied then
            LogError(string.format("Could not refresh the editor for %s", entry.id))
        end
    end)
    table.insert(State.rowConnections, connection)
end

local function CollectEntries()
    local entries = {}

    local function Collect(target, targetName)
        if target == nil then
            return
        end
        for key, value in pairs(target:GetAttributes()) do
            table.insert(entries, {
                id         = targetName .. "." .. key,
                key        = key,
                target     = target,
                targetName = targetName,
                kind       = KindOf(value),
                value      = value,
                group      = GroupOf(key),
            })
        end
    end

    Collect(State.car, "Car")
    Collect(State.wheels, "Wheels")
    table.sort(entries, function(left, right)
        local leftRank  = GroupRank[left.group] or 99
        local rightRank = GroupRank[right.group] or 99
        if leftRank ~= rightRank then
            return leftRank < rightRank
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
        Text     = string.format("%s · %s", entry.group, entry.key),
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
        State.selection[entry.id] = selected
    end
    for _, refresh in ipairs(State.checkboxRefreshers) do
        refresh()
    end
    UpdateSnapshotStatus()
end

function UpdateSnapshotStatus()
    local label = State.panelStatus
    if label == nil then
        return
    end
    local parts = { string.format("%d of %d properties selected", CountSelected(), #State.entries) }
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
        for index, entry in ipairs(State.entries) do
            CreateCheckboxRow(selectionScroller, index, entry)
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
    State.car          = car
    State.wheels       = car and car:FindFirstChild("Wheels")
    State.entries      = CollectEntries()
    State.structureKey = StructureSignature()

    if car == nil then
        LogError("No vehicle is spawned for " .. Player.Name .. " - waiting for one")
        RenderAll()
        return
    end

    table.insert(State.carConnections, car.AttributeChanged:Connect(ScheduleStructureCheck))
    table.insert(State.carConnections, car.ChildAdded:Connect(function(child)
        if child.Name == "Wheels" then
            task.defer(BindVehicle)
        end
    end))
    table.insert(State.carConnections, car.ChildRemoved:Connect(function(child)
        if child.Name == "Wheels" then
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

    local headerRow = MonoUI.Row(State.content, NextOrder(), 96)
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
end

function Unload()
    LogInfo("Unloading the vehicle property editor")
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
