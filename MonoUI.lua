-- Latest update: 10/25/2026 5:29 PM
--[[ MonoUI ====================================================================
    The monochrome window from Stretcher.lua, extracted into a reusable library.

    Same type scale, motion, spacing and gethui-first parenting as the window it came from, laid
    out the same way; the surface is a frosted glass plate rather than a flat grey one, built from
    white tints over transparency, a sheen across the fill and a gradient rim. Every layout
    capability that file uses is available here, so a script can be laid out exactly the way
    Stretcher is - several independent plates, each with its own title bar and drag - or use the
    higher-level tabs and elements:

    Hand-laid out, the way Stretcher does it:
        local Plate = MonoUI:CreatePlate { Name = "MY SWITCHES", Width = 248, Position = UDim2.fromOffset(812, 120), Hint = "RIGHT CONTROL TO HIDE" }
        local Row   = Plate:Row(28)
        Plate:Columns(Row, 2, 6, 28)                 -- UIGridLayout, equal cells, returns the cell size
        MonoUI.Switch { Parent = Row, Caption = "CATCH", Order = 1, Value = true, OnChange = onCatch }
        MonoUI.Input  { Parent = Row, Order = 2, Hint = "0", OnSubmit = onNumber }
        MonoUI.Texted(Row, { Text = "SEND XYZ", Tint = "Muted", Size = 11, Position = UDim2.fromOffset(0, 0), Size2 = UDim2.new(0, 80, 1, 0) })

    Or with tabs and named elements:
        local Window  = MonoUI:CreateWindow { Name = "MY SCRIPT", ConfigurationSaving = { Enabled = true, FileName = "MyScript" } }
        local Tab     = Window:CreateTab("Main")
        Tab:CreateSection("Features")
        Tab:CreateToggle   { Name = "Debug", CurrentValue = false, Flag = "debug", Callback = onDebug }
        Tab:CreateDropdown { Name = "Mode", Options = {"A", "B"}, CurrentOption = "A", Flag = "mode", Callback = onMode }
        Tab:CreateInput    { Name = "Strength", PlaceholderText = "1e5", Flag = "strength", Callback = onStrength }
        Tab:CreateButton   { Name = "Exit", Callback = exit }

        MonoUI:LoadConfiguration()   -- apply saved flags, through each element's Callback
        Window:Destroy()             -- window, plates, blur, listeners and tweens

    The named elements take the ArrayField-shaped table, so a script moving over from that
    hub only changes the names: Name / CurrentValue / Options / CurrentOption / Flag /
    Callback. Unknown keys are ignored rather than rejected.

    On a phone or a tablet the same window is laid out for a fingertip, without the calling script
    asking for it: the type scale and every control height grow a step, the plate is fitted to the
    width of the screen instead of running off it, the body scrolls when a tab is taller than the
    screen, a list opened in that body is lifted out of it so it is not clipped and opens upward
    near the bottom edge, hover is dropped (a finger cannot hover, and the leave that would end it
    never comes), a drag belongs to the one finger that started it, the title bar grows a hide
    button because there is no Right Control, an input moves the window above the keyboard while
    it has the caret, and the rain falls at a phone's budget with no cursor warp. The device is
    asked once; MonoUI:SetTouch(false) or (true) forces either layout, as does
    CreateWindow { Mobile = false }.
]]

local Players     = game:GetService("Players")
local Lighting    = game:GetService("Lighting")
local UserInput   = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Workspace   = game:GetService("Workspace")
local RunService  = game:GetService("RunService")
local GuiService  = game:GetService("GuiService")

local MonoUI = {}
MonoUI.Debug = false

--=== theme =================================================================

-- The palette is white-on-transparent rather than gray-on-gray: the tints are the light the
-- glass catches, and every *Alpha below is a BackgroundTransparency, so a higher value is a
-- more see-through surface. The plate is the only layer the world is meant to show through.
local Theme = {
    Surface      = Color3.fromRGB(8, 8, 8),                                          -- window plate
    Header       = Color3.fromRGB(255, 255, 255),                                    -- title bar, a white lift
    Row          = Color3.fromRGB(255, 255, 255),                                    -- inactive buttons
    RowHover     = Color3.fromRGB(255, 255, 255),                                    -- hovered buttons
    Well         = Color3.fromRGB(0, 0, 0),                                          -- inputs / selects
    Text         = Color3.fromRGB(250, 250, 250),                                    -- primary text
    Muted        = Color3.fromRGB(160, 160, 160),                                    -- secondary text
    Line         = Color3.fromRGB(255, 255, 255),                                    -- strokes
    Outline      = Color3.fromRGB(255, 255, 255),                                    -- window outline
    Invert       = Color3.fromRGB(10, 10, 10),                                       -- text on a white pill
    Car          = Color3.fromRGB(70, 70, 70),                                       -- tint for a player who is sitting in a car
    CarHover     = Color3.fromRGB(96, 96, 96),                                       -- and its hover
    WindowTransparency  = 1.00,                                                             -- frosted plate, the blur shows through
    PanelAlpha   = 0.90,                                                             -- title bar, white lift
    RowAlpha     = 0.92,                                                             -- buttons, rest
    HoverAlpha   = 0.84,                                                             -- buttons, hovered: denser fill, same tint
    PressAlpha   = 0.74,                                                             -- and pressed, denser still
    WellAlpha    = 0.55,                                                             -- inputs / selects are inset, so darker
    MenuAlpha    = 0.18,                                                             -- dropdown must stay readable
    LineAlpha    = 0.88,                                                             -- hairline strokes
    FocusAlpha   = 0.45,                                                             -- the ring an input shows while focused
    OutlineAlpha = 0.70,                                                             -- window outline
    SwitchOnAlpha = 0.08,                                                            -- the white pill of a switch that is on
    RevealScale  = 0.97,                                                             -- plate scale it grows from when it is shown
    Radius       = 16,                                                               -- window corner radius
    RowRadius    = 10,                                                               -- inner corner radius
    Space        = { Micro = 4, Gap = 8, Pad = 14, Section = 16, Block = 22 },        -- one spacing scale
    Type         = { Title = 15, Heading = 11, Label = 13, Body = 12, Support = 9 },  -- named sizes
    Width        = 720,                                                              -- default plate width
    Blur         = 16,                                                               -- backdrop blur, 0 for none
    VisibleRows  = 5,                                                                -- options shown before a dropdown scrolls
    Metrics      = {                                                                 -- what a control is worth touching, one row of numbers
        Row     = 30,                                                                -- a full-width control: switch, button
        Inset   = 26,                                                                -- a control inside a row: input
        Select  = 32,                                                                -- the well a dropdown shows its choice in
        Bar     = 34,                                                                -- the title bar
        Tab     = 28,                                                                -- a tab button, and one row of the strip
        Section = 22,                                                                -- a section heading
        MenuRow = 22,                                                                -- one option in a dropdown list
        MenuGap = 2,                                                                 -- between two options
        MenuPad = 4,                                                                 -- around the list
        Knob    = 20,                                                                -- switch knob diameter
        Hide    = 30,                                                                -- the hide button on a touch title bar
    },
    Mobile       = {                                                                 -- what a phone needs that a desktop does not
        Margin          = 10,                                                        -- screen edge kept clear around a plate
        MinScale        = 0.75,                                                      -- never shrink a plate past this to make it fit
        MinWidth        = 260,                                                       -- a plate narrower than this is not worth laying out
        LiftForKeyboard = true,                                                      -- move the plate out from under the keyboard while an input has the caret
    },
    Rain         = {                                                                 -- drops behind the window while it is up, sized by weather rather than by dice
        Enabled        = true,
        Count          = 450,                                                        -- one Frame per drop: this is the biggest CPU cost in the file
        Tint           = "Muted",                                                    -- what a drop is drawn in, before its own opacity lightens it
        Intensity      = 25,                                                         -- rain rate in mm/h: 1 drizzle, 5 steady, 25 heavy, 100 a downpour
        MinDiameter    = 0.3,                                                        -- mm, the floor the exponential size distribution is clamped to
        MaxDiameter    = 5.5,                                                        -- mm, and its ceiling
        PixelsPerMeter = 70,                                                         -- screen per metre of fall; this sets the whole speed scale
        Exposure       = 1 / 60,                                                     -- seconds a drop is smeared over, so length = speed * exposure
        MaxStep        = 1 / 20,                                                     -- a long frame (an alt-tab) is clamped to this, so nothing teleports
        Depth          = { 0.45, 1.00 },                                             -- { near, far } parallax: a far drop is slower, thinner, fainter
        Wind           = {                                                           -- the sheet of rain leans, and gusts over the lean
            Angle    = 8,                                                            -- degrees off vertical
            Gust     = 6,                                                            -- degrees either way, from math.noise
            GustRate = 0.15,                                                         -- how fast the gust wanders
        },
        Warp           = {                                                           -- the cursor bends the space the drops fall through
            Enabled  = true,                                                         -- off on a touch screen, where there is no cursor to bend it
            Radius   = 220,                                                          -- pixels of space that bend: a cursor-sized well, not a pinprick
            Strength = 260,                                                          -- peak displacement, fold-free up to 3 * Radius
            Follow   = 14,                                                           -- how fast the well itself catches the cursor, in e-folds per second
        },
    },
}

--=== platform ==============================================================

-- What the device can do, asked once. A phone and a desktop want different numbers out of the same
-- layout: a fingertip needs a bigger target than a pointer, a mouse is the only thing that hovers, a
-- phone screen is a limit a desktop window never has to think about, and there is no Right Control
-- to hide by.
local Platform = {
    Touch    = UserInput.TouchEnabled,
    Mouse    = UserInput.MouseEnabled,
    Keyboard = UserInput.KeyboardEnabled,
}

-- Touch with no pointer: a phone, or a tablet held in two hands. Asked again per window through
-- settings.Mobile, so either layout can be seen on any device without editing the theme.
Platform.TouchOnly = Platform.Touch and not Platform.Mouse

local Metrics = Theme.Metrics

-- The numbers a touch device swaps in. Only the differences are written down; everything the table
-- leaves out - the palette, the spacing scale, the rain's physics - is the same on both.
local TouchProfile = {
    Width       = 360,                                                               -- a design width a phone screen actually has
    Blur        = 12,                                                                -- the same effect over fewer pixels
    RainCount   = 140,                                                               -- one Frame per drop, so a third of the desktop shower
    Warp        = false,                                                             -- a cursor lens with no cursor in it
    VisibleRows = 4,                                                                 -- one fewer option before the list scrolls
    Type        = { Title = 16, Heading = 12, Label = 14, Body = 13, Support = 10 },  -- one step up, because a phone is held further away
    Space       = { Gap = 10, Pad = 16, Section = 20, Block = 24 },
    Metrics     = {                                                                  -- every row at least a fingertip tall
        Row = 44, Inset = 36, Select = 44, Bar = 48, Tab = 44, Section = 26,
        MenuRow = 38, MenuGap = 4, MenuPad = 6, Knob = 26, Hide = 36,
    },
}

-- The design values, kept so the profile can be swapped back and so a caller can see what the
-- touch table is a departure from. A list, not a copy of the theme, because only these move.
local DesktopProfile = {
    Width       = Theme.Width,
    Blur        = Theme.Blur,
    RainCount   = Theme.Rain.Count,
    Warp        = Theme.Rain.Warp.Enabled,
    VisibleRows = Theme.VisibleRows,
    Type        = { Title = Theme.Type.Title, Heading = Theme.Type.Heading, Label = Theme.Type.Label, Body = Theme.Type.Body, Support = Theme.Type.Support },
    Space       = { Micro = Theme.Space.Micro, Gap = Theme.Space.Gap, Pad = Theme.Space.Pad, Section = Theme.Space.Section, Block = Theme.Space.Block },
    Metrics     = {
        Row = Metrics.Row, Inset = Metrics.Inset, Select = Metrics.Select, Bar = Metrics.Bar, Tab = Metrics.Tab, Section = Metrics.Section,
        MenuRow = Metrics.MenuRow, MenuGap = Metrics.MenuGap, MenuPad = Metrics.MenuPad, Knob = Metrics.Knob, Hide = Metrics.Hide,
    },
}

-- Applied in place: every table a caller may already be holding - MonoUI.Theme, MonoUI.Metrics -
-- stays the same table and simply holds the other set of numbers.
local function ApplyProfile(profile)
    Theme.Width             = profile.Width
    Theme.Blur              = profile.Blur
    Theme.Rain.Count        = profile.RainCount
    Theme.Rain.Warp.Enabled = profile.Warp
    Theme.VisibleRows       = profile.VisibleRows

    for key, value in pairs(profile.Type) do Theme.Type[key] = value end
    for key, value in pairs(profile.Space) do Theme.Space[key] = value end
    for key, value in pairs(profile.Metrics) do Metrics[key] = value end
end

-- One switch for the whole library, because the layout decisions below are made while controls are
-- being built and have to agree with each other: a window cannot have touch rows in a desktop body.
function MonoUI:SetTouch(touch)
    MonoUI.Touch = touch and true or false
    ApplyProfile(MonoUI.Touch and TouchProfile or DesktopProfile)
    return MonoUI.Touch
end

MonoUI:SetTouch(Platform.TouchOnly)

--=== reporting =============================================================

-- A property that does not exist used to vanish silently; say so when Debug is on, on the
-- executor's own console, which is where that belongs.
local function Report(message)
    if not MonoUI.Debug then return end
    if type(rconsoleprint) == "function" then
        pcall(rconsoleprint, message)
        return
    end
    pcall(warn, message)
end

--=== primitives ============================================================

local function Element(properties)
    local parent = properties.Parent
    properties.Parent = nil

    local instance = Instance.new(properties.ClassName or "Frame")
    properties.ClassName = nil

    for key, value in pairs(properties) do
        local ok, problem = pcall(function()
            instance[key] = value
        end)
        if not ok then
            Report(string.format("%s.%s · %s", instance.ClassName, tostring(key), tostring(problem)))
        end
    end

    if parent then
        instance.Parent = parent
    end
    return instance
end

-- The glass is built out of four layers rather than one flat frame: a fill whose tint comes from
-- the palette, a sheen across it, a rim that is bright at the top-left and fades away, and a
-- hairline stroke. Sticker hands out the whole set, and each piece below early-returns when its
-- property is absent, so the shapes stay readable and a caller opts in per piece:
--   Color = "Surface"  Corner = "RowRadius"  Stroke = "Line"
--   Glass = true       -- top-to-bottom sheen across the fill
--   Rim = true         -- bright top-left edge, fading toward the bottom-right
--   Padding = { 10, 10, 10, 10 }             Gap = { Padding = 6, ... }

-- The rim: brightest where a light would catch the top-left edge, fading off over the long sides
-- and lifting again at the very corner, so the pane reads as a solid object with an edge.
local RimTransparency = NumberSequence.new {
    NumberSequenceKeypoint.new(0.00, 0.25),
    NumberSequenceKeypoint.new(0.35, 0.75),
    NumberSequenceKeypoint.new(0.70, 0.90),
    NumberSequenceKeypoint.new(1.00, 0.55),
}

-- The fill is a little denser at the top than the bottom, which is what reads as a pane of glass
-- lying under a light rather than a flat cutout.
local SheenTransparency = NumberSequence.new {
    NumberSequenceKeypoint.new(0, 0.00),
    NumberSequenceKeypoint.new(1, 0.45),
}

-- 0.5 -> pill, 12 -> pixels, "RowRadius" -> that palette entry
local function ResolveRadius(corner)
    if type(corner) == "string" then return UDim.new(0, Theme[corner] or Theme.RowRadius) end
    if type(corner) ~= "number" then return UDim.new(0, Theme.RowRadius) end
    if corner < 1 then return UDim.new(corner, 0) end
    return UDim.new(0, corner)
end

local function AddFill(instance, properties)
    local color = Theme[properties.Color]
    if color ~= nil then instance.BackgroundColor3 = color end
    if properties.Alpha ~= nil then instance.BackgroundTransparency = properties.Alpha end
end

local function AddCorner(instance, corner)
    if corner == nil then return end
    Element { ClassName = "UICorner", Parent = instance, Name = "Corner", CornerRadius = ResolveRadius(corner) }
end

-- With Rim the stroke itself goes to full opacity and a gradient does the fading instead; without
-- it the stroke is simply the flat hairline it always was.
local function AddStroke(instance, properties)
    if properties.Stroke == nil then return end

    local hasRim = properties.Rim == true
    local stroke = Element {
        ClassName       = "UIStroke",
        Parent          = instance,
        Name            = "Stroke",
        Color           = Theme[properties.Stroke] or Theme.Line,
        Thickness       = properties.StrokeWidth or 1,
        Transparency    = hasRim and 0 or (properties.StrokeAlpha or Theme.LineAlpha),
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }
    if not hasRim then return end

    Element { ClassName = "UIGradient", Parent = stroke, Name = "Rim", Rotation = 45, Transparency = RimTransparency }
end

-- A gradient modulates what it is parented to, so on a Frame it lightens the fill and on a
-- TextBox it would also tint the text: controls that carry text keep the fill unglassed.
local function AddSheen(instance, properties)
    if not properties.Glass then return end
    Element { ClassName = "UIGradient", Parent = instance, Name = "Sheen", Rotation = 90, Transparency = SheenTransparency }
end

local function AddPadding(instance, padding)
    if padding == nil then return end
    Element {
        ClassName     = "UIPadding",
        Parent        = instance,
        Name          = "Padding",
        PaddingTop    = UDim.new(0, padding[1] or 0),
        PaddingRight  = UDim.new(0, padding[2] or 0),
        PaddingBottom = UDim.new(0, padding[3] or 0),
        PaddingLeft   = UDim.new(0, padding[4] or 0),
    }
end

local function AddLayout(instance, gap)
    if gap == nil then return end
    Element {
        ClassName           = "UIListLayout",
        Parent              = instance,
        Name                = "Layout",
        FillDirection       = gap.Direction or Enum.FillDirection.Vertical,
        HorizontalAlignment = gap.X or Enum.HorizontalAlignment.Center,
        VerticalAlignment   = gap.Y or Enum.VerticalAlignment.Center,
        SortOrder           = gap.Order or Enum.SortOrder.LayoutOrder,
        Padding             = UDim.new(0, gap.Padding or 0),
    }
end

local function Sticker(instance, properties)
    properties = properties or {}
    AddFill(instance, properties)
    AddCorner(instance, properties.Corner)
    AddStroke(instance, properties)
    AddSheen(instance, properties)
    AddPadding(instance, properties.Padding)
    AddLayout(instance, properties.Gap)
    return instance
end

local function Fonted(instance, bold)
    instance.Font = bold and Enum.Font.GothamBold or Enum.Font.GothamMedium
    return instance
end

local function Texted(parent, properties)
    local label = Element {
        ClassName              = "TextLabel",
        Parent                 = parent,
        BackgroundTransparency = 1,
        Text                   = properties.Text or "",
        TextColor3             = Theme[properties.Tint or "Text"],
        TextSize               = properties.Size or Theme.Type.Body,
        TextXAlignment         = properties.X or Enum.TextXAlignment.Left,
        TextYAlignment         = Enum.TextYAlignment.Center,
        TextTruncate           = Enum.TextTruncate.AtEnd,
        Size                   = properties.Size2 or UDim2.new(1, 0, 1, 0),
        Position               = properties.Position or UDim2.fromOffset(0, 0),
        ZIndex                 = properties.ZIndex or 1,
        LayoutOrder            = properties.LayoutOrder,
    }
    return Fonted(label, properties.Bold ~= false)
end

--=== motion ================================================================

-- One motion language for the whole window, driven by a single Heartbeat connection that exists
-- only while something is actually moving.
--
-- Two modes, chosen per channel and never per call site:
--
--   Decay - moves a fixed fraction of the distance left each frame, so it is frame-rate
--           independent and has no duration and no start time. That means it can be retargeted
--           mid-flight without a kink, which is what anything the user can interrupt needs: hover,
--           press, focus, follow. The rate is a lambda: 95% of the way there in 3/lambda seconds,
--           99% in 4.6/lambda.
--   Cubic - a fixed duration through a cubic ease, for scripted changes that have a known beginning
--           and an end: the switch knob travelling, a plate opening, a panel closing.
--
-- Tracks are keyed by instance and property, not by channel: two writers to one property replace
-- each other, and two properties never collide. Motion = false in the settings drops the movement,
-- never the feedback.
local Motion = {}

-- The fraction of the distance left that one step of dt covers. Sixty steps of 1/60 s land in the
-- same place as one step of 1 s, which is the whole point of a decay over a fixed-length tween.
local function DecayAlpha(rate, deltaTime)
    return 1 - math.exp(-rate * deltaTime)
end

Motion.DecayAlpha = DecayAlpha                                                       -- exported, so a script smoothing its own value uses this math and not a second one

local Easings = {}

function Easings.CubicOut(progress)
    local remaining = 1 - progress
    return 1 - remaining * remaining * remaining
end

function Easings.CubicIn(progress)
    return progress * progress * progress
end

function Easings.CubicInOut(progress)
    if progress < 0.5 then
        return 4 * progress * progress * progress
    end
    local remaining = -2 * progress + 2
    return 1 - remaining * remaining * remaining / 2
end

-- The timings that were here as tweens, in the modes that carry them now: hover and press are
-- interruptible at any moment, so they decay, and the rest are discrete moves with an end.
Motion.Specs = {
    Hover  = { Kind = "Decay", Rate = 25 },                                          -- 95% in 120 ms, where the 0.12 s tween used to land
    Press  = { Kind = "Decay", Rate = 38 },                                          -- 95% in 79 ms
    Switch = { Kind = "Cubic", Duration = 0.16, Ease = Easings.CubicOut },
    Open   = { Kind = "Cubic", Duration = 0.15, Ease = Easings.CubicOut },
    Close  = { Kind = "Cubic", Duration = 0.11, Ease = Easings.CubicIn },
    Panel  = { Kind = "Cubic", Duration = 0.18, Ease = Easings.CubicOut },
}

-- Public, so a script that owns its own layout can honour its own motion setting: the window
-- creator sets this from its settings, and anything can turn motion off and keep the feedback.
Motion.Enabled = true

-- A stall - an alt-tab, one slow frame - is clamped to this, so a long frame moves a value by at
-- most a twentieth of a second's worth rather than teleporting it.
Motion.MaxStep = 1 / 20

-- What feedback decays at while motion is reduced: a colour or a transparency still has to change
-- visibly, it just must not slide. 95% in 75 ms.
local FeedbackRate = 40

-- The properties that count as movement. Everything else the driver touches is feedback - a colour,
-- a transparency, a stroke - and that is what stays when motion is reduced.
local Movement = { Position = true, Size = true, Rotation = true, Scale = true }

-- Set now rather than over time: what an unblendable type, a snap in reduced motion, or a state
-- that must not slide does. Every state change stays visible; only the movement is dropped.
local function Snap(instance, properties)
    for key, value in pairs(properties) do
        pcall(function()
            instance[key] = value
        end)
    end
end

-- Interpolation per value type, so the driver never has to assume a number.
local Blenders = {}

function Blenders.number(from, to, alpha)
    return from + (to - from) * alpha
end

function Blenders.UDim(from, to, alpha)
    return UDim.new(from.Scale + (to.Scale - from.Scale) * alpha, from.Offset + (to.Offset - from.Offset) * alpha)
end

function Blenders.UDim2(from, to, alpha)
    return from:Lerp(to, alpha)
end

function Blenders.Color3(from, to, alpha)
    return from:Lerp(to, alpha)
end

function Blenders.Vector2(from, to, alpha)
    return from:Lerp(to, alpha)
end

local function Blend(from, to, alpha)
    local blender = Blenders[typeof(from)]
    if blender == nil then
        return to
    end
    return blender(from, to, alpha)
end

-- How close is close enough. A decay only ever approaches its target, so it needs a floor to land
-- on, and the floor has to match the unit: a position is pixels, a rotation is degrees, and a
-- transparency, a colour or a scale is a 0..1 fraction where two thousandths is below the eye.
local Tolerances = {
    Position = 0.25,
    Size     = 0.25,
    Rotation = 0.1,
    Scale    = 0.002,
}

local DefaultTolerance = 0.002

-- Distance, in the unit the property moves in: pixels for a UDim2, which is what every animated
-- Position and Size in this file uses, and a fraction for everything else.
local function Distance(from, to)
    if type(from) == "number" then
        return math.abs(from - to)
    end
    if typeof(from) == "Color3" then
        return math.max(math.abs(from.R - to.R), math.abs(from.G - to.G), math.abs(from.B - to.B))
    end
    if typeof(from) == "UDim2" then
        return math.abs(from.X.Offset - to.X.Offset) + math.abs(from.Y.Offset - to.Y.Offset)
    end
    if typeof(from) == "UDim" then
        return math.abs(from.Offset - to.Offset)
    end
    if typeof(from) == "Vector2" then
        return (from - to).Magnitude
    end
    return math.huge                                                                     -- unknown: never settles on its own, so it is set and dropped
end

-- How a track covers its remaining ground, one per mode above.
local Advancers = {}

-- A decay is checked against its tolerance every step, and lands exactly on the target when it is
-- close enough: it would otherwise approach for ever.
function Advancers.Decay(track, step)
    local value   = Blend(track.current, track.target, DecayAlpha(track.rate, step))
    local settled = Distance(value, track.target) <= track.tolerance
    return settled and track.target or value, settled
end

function Advancers.Cubic(track, step)
    track.elapsed = track.elapsed + step
    local progress = math.min(track.elapsed / track.duration, 1)
    return Blend(track.origin, track.target, track.ease(progress)), progress >= 1
end

-- One connection, alive only while there is something to move: with no tracks on it, the UI costs
-- nothing per frame at all.
local Animator = { tracks = {}, count = 0, connection = nil }

local function StopAnimator()
    if Animator.connection == nil then
        return
    end
    pcall(function()
        Animator.connection:Disconnect()
    end)
    Animator.connection = nil
end

-- Dropping a track is the only thing that ever happens during a step, and it only ever nils the
-- entry being visited, which is what keeps walking these tables while stepping safe.
local function RemoveTrack(instance, property)
    local set = Animator.tracks[instance]
    if set == nil or set[property] == nil then
        return
    end

    set[property] = nil
    Animator.count = Animator.count - 1
    if next(set) == nil then
        Animator.tracks[instance] = nil
    end
    if Animator.count <= 0 then
        Animator.count = 0
        StopAnimator()
    end
end

-- A track that has arrived is set exactly on its target and then dropped: this snap is the only way
-- a decay ever finishes.
local function StepTrack(instance, property, track, step)
    local value, finished = Advancers[track.kind](track, step)
    track.current = value
    Snap(instance, { [property] = value })
    if finished then
        RemoveTrack(instance, property)
    end
end

local function StepAnimator(deltaTime)
    local step = math.min(deltaTime, Motion.MaxStep)
    for instance, set in pairs(Animator.tracks) do
        for property, track in pairs(set) do
            StepTrack(instance, property, track, step)
        end
    end
end

local function StartAnimator()
    if Animator.connection ~= nil then
        return
    end
    Animator.connection = RunService.Heartbeat:Connect(StepAnimator)
end

-- The duration a restarted cubic should take: the time the distance left would have taken at the
-- average speed of the move it interrupted. Capped by the spec, so a retarget is never slower than
-- a fresh move, and floored so that it is never a jump.
local function RebasedDuration(existing, duration, origin, target)
    if existing.duration == nil then
        return duration
    end
    local span = Distance(existing.origin, existing.target)
    if span <= 0 then
        return duration
    end
    local left = Distance(origin, target)
    return math.clamp(left / (span / existing.duration), duration * 0.35, duration)
end

-- Starts or replaces the track for one property. A track that is replaced starts from where the
-- value is now, which is what makes an interrupted move carry on instead of jumping back to where
-- it began.
local function Start(instance, property, target, spec)
    local current
    local ok = pcall(function()
        current = instance[property]
    end)

    -- A property that cannot be read, or a type the driver cannot blend, is set once rather than
    -- animated: a window that refuses to update is worse than one that does not glide.
    if not ok or current == nil or typeof(current) ~= typeof(target) or Blenders[typeof(current)] == nil then
        RemoveTrack(instance, property)
        Snap(instance, { [property] = target })
        return nil
    end

    -- Reduced motion: the movement goes, the feedback stays. A colour or a transparency still
    -- changes, quickly enough to read as a change rather than as a slide.
    local rate = spec.Rate
    if Motion.Enabled == false then
        if Movement[property] then
            RemoveTrack(instance, property)
            Snap(instance, { [property] = target })
            return nil
        end
        rate = FeedbackRate
    end

    local existing = Animator.tracks[instance] and Animator.tracks[instance][property]
    local track = {
        kind      = spec.Kind,
        rate      = rate,
        duration  = spec.Duration,
        ease      = spec.Ease,
        tolerance = Tolerances[property] or DefaultTolerance,
        origin    = current,
        current   = current,
        target    = target,
        elapsed   = 0,
    }

    if existing ~= nil then
        track.origin  = existing.current
        track.current = existing.current
        if track.kind == "Cubic" then
            track.duration = RebasedDuration(existing, track.duration, track.origin, target)
        end
    end

    local set = Animator.tracks[instance]
    if set == nil then
        set = {}
        Animator.tracks[instance] = set
    elseif existing == nil then
        Animator.count = Animator.count + 1                                          -- a replacement is one track for one track
    end
    set[property] = track

    StartAnimator()
    return track
end

function Motion.Play(instance, channel, properties)
    if instance == nil or properties == nil then
        return nil
    end

    local spec  = Motion.Specs[channel] or Motion.Specs.Hover
    local track = nil
    for property, target in pairs(properties) do
        track = Start(instance, property, target, spec)
    end
    return track
end

-- For a value that is retargeted every frame - a drag, a parallax offset. The first call starts the
-- track and every call after it only moves the target, so the value chases a moving point without
-- the curve ever restarting underneath it.
function Motion.Follow(instance, property, target, rate)
    if instance == nil then
        return nil
    end

    local existing = Animator.tracks[instance] and Animator.tracks[instance][property]
    if existing ~= nil and existing.kind == "Decay" then
        existing.target = target
        if rate ~= nil then
            existing.rate = rate
        end
        return existing
    end
    return Start(instance, property, target, { Kind = "Decay", Rate = rate or 25 })
end

function Motion.Cancel(instance)
    local set = Animator.tracks[instance]
    if set == nil then
        return false
    end

    for property in pairs(set) do
        RemoveTrack(instance, property)
    end
    return true
end

function Motion.Destroy()
    for instance in pairs(Animator.tracks) do
        Animator.tracks[instance] = nil
    end
    Animator.count = 0
    StopAnimator()
    return true
end

-- Motion off means the end state without the movement, which is what every caller below wants;
-- routing all of them through here keeps that decision in one place.
local function Apply(instance, channel, properties, animate)
    if animate then
        Motion.Play(instance, channel, properties)
        return
    end
    Snap(instance, properties)
end

-- The states of anything clickable, wired once: rest, hover, the press, and the way back when the
-- press ends. Hover and press are transparency changes, never colour changes - that is what keeps a
-- glass surface reading as one material.
--
-- Hover is a mouse state, though: a finger cannot rest over a control without pressing it, and a
-- device with no pointer never sends the leave that would end the hover - which is what used to
-- leave a tapped row sitting a shade denser than the one beside it for the rest of the session.
-- Without a pointer the press is the whole feedback, and it returns to rest.
local function Hoverable(instance, looks)
    if not MonoUI.Touch then
        instance.MouseEnter:Connect(function() Motion.Play(instance, "Hover", looks.Hover) end)
        instance.MouseLeave:Connect(function() Motion.Play(instance, "Hover", looks.Rest)  end)
    end

    instance.MouseButton1Down:Connect(function() Motion.Play(instance, "Press", looks.Press) end)
    instance.MouseButton1Up:Connect(function()   Motion.Play(instance, "Press", MonoUI.Touch and looks.Rest or looks.Hover) end)

    -- A finger lifted off a control ends its press whether or not that counted as a click.
    instance.InputEnded:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.Touch then return end
        Motion.Play(instance, "Press", looks.Rest)
    end)
end

local RowLooks = {
    Rest  = { BackgroundTransparency = Theme.RowAlpha   },
    Hover = { BackgroundTransparency = Theme.HoverAlpha },
    Press = { BackgroundTransparency = Theme.PressAlpha },
}

-- A plate grows the last few percent into place when it is shown, so it arrives rather than
-- appears. The Scale is looked up by name: a plate built by hand without one is simply left alone,
-- which is what keeps this optional for anyone laying out their own surface. The fit the plate was
-- given by FitSurface is the scale it settles on, so a window shrunk to fit a phone still arrives
-- rather than appears - and does not lose its fit on the way in.
local function Reveal(plate)
    local scale = plate:FindFirstChild("Scale")
    if scale == nil then return end

    local fit = plate:GetAttribute("FitScale") or 1
    scale.Scale = fit * Theme.RevealScale
    Motion.Play(scale, "Open", { Scale = fit })
end

--=== screen ================================================================

-- The space the window is drawn in. Everything below measures against this rather than against a
-- number, because on a phone it is a different number every time the device is turned.
local function Viewport()
    local camera = Workspace.CurrentCamera
    return camera and camera.ViewportSize or Vector2.new(1920, 1080)
end

-- The safe area's top edge, in screen pixels. The gui ignores the inset, so the window is allowed to
-- draw behind the topbar and the notch - which is only safe if the title bar is placed by hand.
local function TopInset()
    local ok, inset = pcall(function()
        return GuiService:GetGuiInset()
    end)
    if ok and typeof(inset) == "Vector2" then
        return inset.Y
    end
    return 0
end

-- A surface's on-screen size against its size in design pixels: the factor a pointer delta has to be
-- divided by when a UIScale is shrinking the whole window to fit.
local function SurfaceScale(surface)
    local design = surface.Size.X.Offset
    if design <= 0 then return 1 end
    return math.max(surface.AbsoluteSize.X / design, 0.05)
end

-- The nearest ancestor of a given class, which is how a control finds the scroller it was laid out
-- in without having to be told about it.
local function AncestorOfClass(instance, className)
    local node = instance.Parent
    while node ~= nil do
        if node.ClassName == className then
            return node
        end
        node = node.Parent
    end
    return nil
end

-- The plate a control belongs to: the nearest ancestor that is a direct child of the gui.
local function PlateOf(instance)
    local node = instance
    while node ~= nil and node.Parent ~= nil and node.Parent.ClassName ~= "ScreenGui" do
        node = node.Parent
    end
    return node
end

-- Assigned with the app, which is where the plates that own a keyboard are known. An input calls
-- these when it takes focus and when it lets go.
local LiftForKeyboard
local DropLift

-- Assigned with the app, where the overlay a list escapes into lives. A dropdown calls this as it
-- opens, so it has to be in scope here, before the controls are built.
local PlaceMenu

-- The width a plate gets. A desktop hands back what was asked for; a phone keeps the request but
-- takes it down to what is on the screen, because a window laid out past the edge is a window with
-- controls the user cannot reach.
local function PlateWidth(requested)
    local width = requested or Theme.Width
    if not MonoUI.Touch then return width end

    local room = Viewport().X - Theme.Mobile.Margin * 2
    return math.max(math.min(width, room), math.min(Theme.Mobile.MinWidth, room))
end

-- Where the first plate lands. Centred under the safe area on a phone, so it does not open under
-- the notch; at the same 80, 120 a desktop window has always opened at on a desktop.
local function PlatePosition(width, order)
    if not MonoUI.Touch then
        return UDim2.fromOffset(80, 120 + ((order or 1) - 1) * 24)
    end

    local screen = Viewport()
    local step   = math.min(24, ((order or 1) - 1) * 12)
    return UDim2.fromOffset(
        math.max(Theme.Mobile.Margin, math.floor((screen.X - width) / 2)),
        TopInset() + Theme.Mobile.Margin + step
    )
end

-- A phone can be narrower than a plate is designed to be, so the plate is scaled rather than laid
-- out off the screen: one UIScale for the whole window, never per control, so the type scale keeps
-- its relationships. The fit is kept on the plate as an attribute because that is where Reveal
-- reads it back from.
local function FitSurface(plate, width)
    local fit = 1
    if MonoUI.Touch then
        local room = Viewport().X - Theme.Mobile.Margin * 2
        fit = math.clamp(room / math.max(width, 1), Theme.Mobile.MinScale, 1)
    end

    plate:SetAttribute("FitScale", fit)

    local scale = plate:FindFirstChild("Scale")
    if scale ~= nil then
        scale.Scale = fit
    end
    return fit
end

-- After a fit or a rotation a plate may be hanging off an edge it used to be clear of; the rule is
-- the same one the drag keeps: the bar stays on the screen, which is where it can be grabbed again.
local function ClampSurface(plate)
    if not MonoUI.Touch then return end

    local screen   = Viewport()
    local size     = plate.AbsoluteSize
    local position = plate.Position
    plate.Position = UDim2.new(
        position.X.Scale, math.clamp(position.X.Offset, 8 - size.X + 60, screen.X - 60),
        position.Y.Scale, math.clamp(position.Y.Offset, TopInset() + Theme.Mobile.Margin * 0.5, screen.Y - 40)
    )
end

-- Turning the device, or resizing a window, changes the space the plate was fitted to. The plate is
-- re-fitted rather than left hanging off an edge it was clear of a moment ago, so the window that
-- was laid out in portrait is still usable after a rotation into landscape.
local function WatchViewport(owner)
    local camera = Workspace.CurrentCamera
    if camera == nil then return end

    owner.connections[#owner.connections + 1] = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
        if owner.Refit ~= nil then owner.Refit() end
    end)
end

--=== layout ================================================================

-- UI belongs in the hidden UI container, not the player's PlayerGui
-- gethui first, then the older fallbacks.
local function UiContainer()
    if type(gethui) == "function" then
        local ok, hidden = pcall(gethui)
        if ok and hidden ~= nil then
            return hidden
        end
    end

    local player = Players.LocalPlayer
    local gui    = player and player:FindFirstChildOfClass("PlayerGui")
    if gui then
        return gui
    end
    local ok, core = pcall(function()
        return game:GetService("CoreGui")
    end)
    return ok and core or game:GetService("StarterGui")
end

-- Drag from any handle: a title bar, the plate itself, or a chip while a window is hidden.
-- Movement is measured as a pointer delta from where the plate already is, never against
-- AbsolutePosition - that one includes the GUI inset while Position does not, which is what
-- makes a naive drag jump on its first frame. A press only becomes a drag after the threshold.
--
-- One pointer owns the drag, and it is the one that started it: a second finger landing anywhere on
-- the screen used to move the window as well, which on a phone happens constantly. A touch carries
-- its own position, so the touch itself is watched; a mouse button does not, so its movement
-- arrives as separate MouseMovement inputs. Either way the delta is divided by the window's fit,
-- so a plate that was scaled down to fit the screen still follows the finger exactly.
local function Dragging(owner, target, ...)
    local handles = { ... }
    local drag    = { input = nil, moved = false, start = Vector2.zero, base = nil, watch = nil, follow = nil }

    local function Untrack()
        for _, connection in ipairs({ drag.watch, drag.follow }) do
            if connection ~= nil then
                pcall(function()
                    connection:Disconnect()
                end)
            end
        end
        drag.watch  = nil
        drag.follow = nil
        drag.input  = nil
    end

    local function Move(input)
        local wanted = Vector2.new(input.Position.X, input.Position.Y)
        local stepX  = wanted.X - drag.start.X
        local stepY  = wanted.Y - drag.start.Y
        if not drag.moved then
            if math.sqrt(stepX * stepX + stepY * stepY) < owner.dragThreshold then
                return
            end
            drag.moved = true
        end

        local screen  = Viewport()
        local scale   = SurfaceScale(target)
        local size    = target.AbsoluteSize / scale
        local floor   = MonoUI.Touch and (TopInset() + 4) or 8
        local wantedX = drag.base.X.Offset + stepX / scale
        local wantedY = drag.base.Y.Offset + stepY / scale
        target.Position = UDim2.new(
            drag.base.X.Scale, math.clamp(wantedX, 8 - size.X + 60, screen.X - 60),
            drag.base.Y.Scale, math.clamp(wantedY, floor, screen.Y - 40)
        )
    end

    local function Begin(input)
        if drag.input ~= nil then return end                                         -- the drag already has an owner
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end

        drag.input  = input
        drag.moved  = false
        drag.start  = Vector2.new(input.Position.X, input.Position.Y)
        drag.base   = target.Position
        owner.lifted = nil                                                           -- a place the user chose is not a place to put back

        drag.watch = input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel then
                Untrack()
            end
        end)
        owner.connections[#owner.connections + 1] = drag.watch

        if input.UserInputType == Enum.UserInputType.Touch then
            drag.follow = input:GetPropertyChangedSignal("Position"):Connect(function()
                Move(input)
            end)
            owner.connections[#owner.connections + 1] = drag.follow
        end
    end

    for _, handle in ipairs(handles) do
        owner.connections[#owner.connections + 1] = handle.InputBegan:Connect(Begin)
    end

    -- The mouse's side of the same drag; a touch never gets here, because it is followed above.
    owner.connections[#owner.connections + 1] = UserInput.InputChanged:Connect(function(input)
        if drag.input == nil or input.UserInputType ~= Enum.UserInputType.MouseMovement then
            return
        end
        Move(input)
    end)

    return drag
end

-- A transparent row, so a line of controls has something to sit in. Fixed height, because
-- a row is a line, not a stack.
local function Row(parent, order, height)
    return Element {
        ClassName              = "Frame",
        Parent                 = parent,
        Name                   = "Row",
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, 0, height),
        LayoutOrder            = order,
    }
end

-- Equal cells for a row: the UIGridLayout does the arithmetic, so every row of buttons
-- lines up with the others and nothing can overflow. The returned size goes on each child
-- so the grid and the controls agree.
local function Columns(frame, count, gap, height)
    -- Cells are 1/count of the row wide, less the gaps, less a couple of pixels of slack: an
    -- exact fit rounds the last cell of the row onto a second line.
    local slack = 2
    local cell  = UDim2.new(1 / count, -((gap * (count - 1)) / count) - slack, 0, height)
    Element {
        ClassName             = "UIGridLayout",
        Parent                = frame,
        Name                  = "Columns",
        CellSize              = cell,
        CellPadding           = UDim2.new(0, gap, 0, 0),
        FillDirection         = Enum.FillDirection.Horizontal,
        FillDirectionMaxCells = count,
        SortOrder             = Enum.SortOrder.LayoutOrder,
    }
    return cell
end

--=== controls ==============================================================

-- A full-width bar with the knob riding left and the caption clearing it in both states. Off is a
-- pane of glass; on is a near-solid white pill, so the two states differ in density rather than in
-- hue and the whole control stays monochrome.
local SwitchLooks = {
    [true]  = { Track = Theme.Text, TrackAlpha = Theme.SwitchOnAlpha, Knob = Theme.Invert, Caption = Theme.Invert },
    [false] = { Track = Theme.Row,  TrackAlpha = Theme.RowAlpha,       Knob = Theme.Muted,  Caption = Theme.Text   },
}

local function Switch(properties)
    local knobSize = Metrics.Knob
    local knobGap  = 3

    local track = Sticker(Element {
        ClassName       = "TextButton",
        Parent          = properties.Parent,
        Name            = properties.Name or properties.Caption or "Switch",
        Size            = properties.Size or UDim2.new(1, 0, 0, Metrics.Row),
        AutoButtonColor = false,
        Text            = "",
        LayoutOrder     = properties.Order or 1,
        Position        = properties.Position,
        ZIndex          = properties.ZIndex or 2,
    }, { Color = properties.Color or "Row", Alpha = Theme.RowAlpha, Corner = "RowRadius", Stroke = "Line", Glass = true })

    local knob = Sticker(Element {
        ClassName   = "Frame",
        Parent      = track,
        Name        = "Knob",
        Size        = UDim2.fromOffset(knobSize, knobSize),
        Position    = UDim2.new(0, knobGap, 0.5, -knobSize / 2),
        ZIndex      = 3,
    }, { Color = "Muted", Corner = 0.5 })

    local caption = Texted(track, {
        Text     = string.upper(properties.Caption or "TOGGLE"),
        Tint     = "Text",
        Size     = Theme.Type.Heading,
        Position = UDim2.fromOffset(knobSize + 8, 0),
        Size2    = UDim2.new(1, -(knobSize + 35), 1, 0),
        ZIndex   = 4,
    })

    local state = properties.Value and true or false

    local function Render(animate)
        local look     = SwitchLooks[state]
        local position = state and UDim2.new(1, -(knobSize + knobGap), 0.5, -knobSize / 2) or UDim2.new(0, knobGap, 0.5, -knobSize / 2)

        Apply(knob,    "Switch", { Position = position, BackgroundColor3 = look.Knob }, animate)
        Apply(caption, "Switch", { TextColor3 = look.Caption },                         animate)
        Apply(track,   "Switch", { BackgroundColor3 = look.Track, BackgroundTransparency = look.TrackAlpha }, animate)
    end

    track.MouseButton1Click:Connect(function()
        state = not state
        Render(true)
        if properties.OnChange then
            properties.OnChange(state)
        end
    end)

    Render(false)

    return {
        Frame = track,
        Set   = function(value)
            state = value and true or false
            Render(true)
        end,
        Get   = function()
            return state
        end,
    }
end

-- A well showing the caption and the current value, with the option list dropping out of it.
local function Select(properties)
    local options = {}
    for _, option in ipairs(properties.Options or {}) do
        options[#options + 1] = tostring(option)
    end

    local row = Sticker(Element {
        ClassName       = "TextButton",
        Parent          = properties.Parent,
        Name            = properties.Name or properties.Caption or "Select",
        Size            = properties.Size or UDim2.new(1, 0, 0, properties.Height or Metrics.Select),
        AutoButtonColor = false,
        Text            = "",
        LayoutOrder     = properties.Order or 1,
        Position        = properties.Position,
        ZIndex          = properties.ZIndex or 2,
    }, { Color = "Well", Alpha = Theme.WellAlpha, Corner = "RowRadius", Stroke = "Line" })

    -- A well with a caption keeps the value in the right 60%, ending clear of the stroke. A well
    -- without one has nothing to caption, so the value takes the whole width and sits centred in
    -- it, which is what a caller laying out a name/value column wants.
    local hasCaption = properties.Caption ~= nil and properties.Caption ~= ""
    Texted(row, {
        Text     = hasCaption and string.upper(properties.Caption) or "",
        Tint     = "Muted",
        Size     = Theme.Type.Heading,
        Position = UDim2.fromOffset(10, 0),
        Size2    = UDim2.new(0.4, -14, 1, 0),
        ZIndex   = 3,
    })

    local value = Texted(row, {
        Tint     = "Text",
        Size     = Theme.Type.Body,
        X        = hasCaption and Enum.TextXAlignment.Right or Enum.TextXAlignment.Center,
        Position = hasCaption and UDim2.new(0.4, 0, 0, 0) or UDim2.fromOffset(10, 0),
        Size2    = hasCaption and UDim2.new(0.6, -10, 1, 0) or UDim2.new(1, -20, 1, 0),
        ZIndex   = 3,
    })

    -- The list is exactly as tall as the options it shows, in the same metrics as the entries, so a
    -- touch list scrolls at a thumb's size rather than a mouse's.
    local shown = math.min(#options, properties.VisibleRows or Theme.VisibleRows)
    local list  = (shown * Metrics.MenuRow) + (math.max(shown - 1, 0) * Metrics.MenuGap) + (Metrics.MenuPad * 2)

    local menu = Sticker(Element {
        ClassName           = "ScrollingFrame",
        Parent              = row,
        Name                = "Menu",
        Size                = UDim2.new(1, 0, 0, list),
        Position            = UDim2.new(0, 0, 1, 4),
        BorderSizePixel     = 0,
        ScrollBarThickness  = 4,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize          = UDim2.new(0, 0, 0, 0),
        Visible             = false,
        ZIndex              = 50,
    }, { Color = "Surface", Alpha = Theme.MenuAlpha, Corner = "RowRadius", Stroke = "Line", Rim = true, Glass = true,
         Padding = { Metrics.MenuPad, Metrics.MenuPad, Metrics.MenuPad, Metrics.MenuPad } })

    Element {
        ClassName = "UIListLayout",
        Parent    = menu,
        Name      = "Layout",
        Padding   = UDim.new(0, Metrics.MenuGap),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }

    local entries = {}
    local selected = nil

    local function Render(name)
        selected         = name
        value.Text       = name or "—"
        value.TextColor3 = name and Theme.Text or Theme.Muted
        for option, entry in pairs(entries) do
            entry.label.TextColor3 = Theme[option == name and "Text" or "Muted"]
        end
    end

    -- An entry is glass over the menu, so at rest it is nothing at all and only the hover and the
    -- press bring a fill up under the text.
    local EntryLooks = {
        Rest  = { BackgroundTransparency = 1 },
        Hover = { BackgroundTransparency = Theme.HoverAlpha },
        Press = { BackgroundTransparency = Theme.PressAlpha },
    }

    for index, option in ipairs(options) do
        local entry = Sticker(Element {
            ClassName       = "TextButton",
            Parent          = menu,
            Name            = option,
            Size            = UDim2.new(1, 0, 0, Metrics.MenuRow),
            AutoButtonColor = false,
            Text            = "",
            LayoutOrder     = index,
            ZIndex          = 51,
        }, { Color = "Row", Alpha = 1, Corner = "RowRadius" })

        local label = Texted(entry, {
            Text     = option,
            Size     = Theme.Type.Body,
            Position = UDim2.fromOffset(8, 0),
            Size2    = UDim2.new(1, -16, 1, 0),
            ZIndex   = 52,
        })
        entries[option] = { Frame = entry, label = label }
        Hoverable(entry, EntryLooks)

        entry.MouseButton1Click:Connect(function()
            Render(option)
            menu.Visible = false
            if properties.OnSelect then
                properties.OnSelect(option)
            end
        end)
    end

    -- Opening is the moment the list learns where the row is: a list that has been scrolled or
    -- re-parented since the last time it opened cannot have kept a position from then.
    local function SetMenuOpen(open)
        if open and PlaceMenu ~= nil then
            PlaceMenu(menu, row)
        end
        menu.Visible = open
    end

    row.MouseButton1Click:Connect(function()
        SetMenuOpen(not menu.Visible)
    end)

    Render(tostring(properties.Value or options[1] or "—"))

    return {
        Frame = row,
        Set   = function(option)
            Render(tostring(option))
        end,
        Get   = function()
            return selected
        end,
        Options = options,
    }
end

-- The box on its own. SubmitOnEnter keeps the ArrayField meaning: with it on the Callback
-- fires when Enter is pressed, with it off on every keystroke. Text is the value the box starts
-- with, so a field can be born holding its default instead of needing a write after creation;
-- CurrentValue is the same thing under the name ArrayField gave it.
local function Input(properties)
    local box = Sticker(Element {
        ClassName         = "TextBox",
        Parent            = properties.Parent,
        Name              = properties.Name or "Input",
        Size              = properties.Size or UDim2.new(0, properties.Width or 50, 0, Metrics.Inset),
        Position          = properties.Position,
        ClearTextOnFocus  = false,
        Text              = properties.Text or properties.CurrentValue or "",
        TextSize          = Theme.Type.Body,
        TextColor3        = Theme.Text,
        TextXAlignment    = properties.X or Enum.TextXAlignment.Center,
        PlaceholderText   = properties.PlaceholderText or properties.Hint or "0",
        PlaceholderColor3 = Theme.Muted,
        LayoutOrder       = properties.Order or 1,
        ZIndex            = properties.ZIndex or 2,
    }, { Color = "Well", Alpha = Theme.WellAlpha, Corner = "RowRadius", Stroke = "Line",
         Padding = { 0, 8, 0, 8 } })
    Fonted(box)

    local function Submit(text)
        if properties.OnSubmit then
            properties.OnSubmit(text)
        end
    end

    if properties.CharacterLimit then
        box:GetPropertyChangedSignal("Text"):Connect(function()
            if #box.Text > properties.CharacterLimit then
                box.Text = string.sub(box.Text, 1, properties.CharacterLimit)
            end
        end)
    end

    if properties.NumbersOnly then
        box:GetPropertyChangedSignal("Text"):Connect(function()
            local cleaned = string.gsub(box.Text, "[^%d%.%-e]", "")
            if cleaned ~= box.Text then
                box.Text = cleaned
            end
        end)
    end

    if properties.SubmitOnEnter then
        box.FocusLost:Connect(function(entered)
            if entered then
                Submit(box.Text)
            end
        end)
    else
        box:GetPropertyChangedSignal("Text"):Connect(function()
            Submit(box.Text)
        end)
    end

    if properties.RemoveTextAfterFocusLost then
        box.FocusLost:Connect(function(entered)
            if not entered then
                box.Text = ""
            end
        end)
    end

    if properties.OnChange then
        box:GetPropertyChangedSignal("Text"):Connect(function()
            properties.OnChange(box.Text)
        end)
    end

    -- The ring an input wears while the caret is in it: the same stroke, brought up to a solid
    -- edge on focus and returned to the hairline on the way out, so focus adds no new furniture.
    local stroke = box:FindFirstChild("Stroke")
    box.Focused:Connect(function()   Motion.Play(stroke, "Hover", { Transparency = Theme.FocusAlpha }) end)
    box.FocusLost:Connect(function() Motion.Play(stroke, "Hover", { Transparency = Theme.LineAlpha  }) end)

    -- On a phone the keyboard is a slab over the bottom of the screen, so the window the box lives
    -- in moves up while the caret is in it.
    box.Focused:Connect(function()  LiftForKeyboard(box) end)
    box.FocusLost:Connect(function() DropLift(box) end)

    return box
end

local function Button(properties)
    local button = Sticker(Element {
        ClassName       = "TextButton",
        Parent          = properties.Parent,
        Name            = properties.Name or properties.Caption or "Button",
        Size            = properties.Size or UDim2.new(1, 0, 0, Metrics.Row),
        Position        = properties.Position,
        AutoButtonColor = false,
        Text            = "",
        LayoutOrder     = properties.Order or 1,
        ZIndex          = properties.ZIndex or 2,
    }, { Color = properties.Color or "Row", Alpha = properties.Alpha or Theme.WellAlpha, Corner = "RowRadius", Stroke = properties.Stroke or "Line", Glass = true })

    Texted(button, {
        Text   = string.upper(properties.Caption or properties.Text or "BUTTON"),
        Size   = properties.TextSize or Theme.Type.Heading,
        X      = Enum.TextXAlignment.Center,
        Tint   = properties.Tint or "Text",
        ZIndex = (properties.ZIndex or 2) + 1,
    })

    -- Hover picks no new colour: the fill keeps its tint and simply comes up a little denser,
    -- which is the one thing every glass control in this file does when it is touched. A button
    -- whose fill is not the usual glass - a solid pill - brings its own looks, or the default
    -- hover would fade it back out from under the caption.
    Hoverable(button, properties.Looks or RowLooks)

    button.MouseButton1Click:Connect(function()
        if properties.OnClick then
            properties.OnClick()
        end
    end)

    return button
end

-- A section is a heading and a hairline, the way the window separates its parts.
local function Heading(parent, order, text)
    local header = Row(parent, order, Metrics.Section)

    Texted(header, {
        Text     = string.upper(text or "SECTION"),
        Tint     = "Muted",
        Size     = Theme.Type.Heading,
        Size2    = UDim2.new(1, 0, 0, 13),
        ZIndex   = 3,
    })

    -- The hairline runs out toward its right end, so a section break fades into the body instead
    -- of stopping, which on a glass surface would read as a seam.
    local divider = Element {
        ClassName              = "Frame",
        Parent                 = header,
        Name                   = "Divider",
        BackgroundColor3       = Theme.Line,
        BackgroundTransparency = Theme.LineAlpha,
        BorderSizePixel        = 0,
        Position               = UDim2.fromOffset(0, 16),
        Size                   = UDim2.new(1, 0, 0, 1),
        ZIndex                 = 3,
    }
    Element {
        ClassName    = "UIGradient",
        Parent       = divider,
        Name         = "Fade",
        Transparency = NumberSequence.new { NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) },
    }

    return { Frame = header, Set = function() end, Get = function() return text end }
end

--=== flags =================================================================

MonoUI.Flags = {}

-- Registering with no Flag is normal - the named elements all accept one, none require it -
-- so the guard here is what keeps a flagless element from indexing the table with nil.
local function RegisterFlag(flag, entry)
    if flag == nil then return end
    MonoUI.Flags[flag] = entry
end

local Settings = { Enabled = false, FileName = "MonoUI" }

-- The file lives in the executor's own workspace folder, next to every other script's
-- configuration, and is plain flag -> value JSON so a saved file stays readable.
local function ConfigurationPath()
    return Settings.FileName .. ".json"
end

-- Saving and loading live next to the path they use. Loading applies each value through its
-- element, so the element's own Callback runs exactly as if the control had been clicked.
function MonoUI:SaveConfiguration()
    if not Settings.Enabled then return end

    local data = {}
    for flag, entry in pairs(MonoUI.Flags) do
        data[flag] = entry.Get()
    end

    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(data)
    end)
    if not ok then return end

    pcall(function()
        writefile(ConfigurationPath(), encoded)
    end)
end

function MonoUI:LoadConfiguration()
    if not Settings.Enabled then return end

    local ok, contents = pcall(function()
        if type(isfile) == "function" and not isfile(ConfigurationPath()) then
            return nil
        end
        return readfile(ConfigurationPath())
    end)
    if not ok or contents == nil then return end

    local decoded, data = pcall(function()
        return HttpService:JSONDecode(contents)
    end)
    if not decoded or type(data) ~= "table" then return end

    for flag, value in pairs(data) do
        local entry = MonoUI.Flags[flag]
        if entry ~= nil then
            entry.Set(value)                                                            -- through the element, so its Callback runs
        end
    end
end

function MonoUI:GetFlag(flag)
    local entry = MonoUI.Flags[flag]
    if entry == nil then return nil end
    return entry.Get()
end

--=== regions ===============================================================

-- A region is a body: a vertical list of rows with its own ordering, which is what both a
-- tab and a plate hand out. The element methods are the named, flag-registering wrappers
-- around the controls above, so a caller can mix them with hand-placed primitives freely.
local function CreateRegion(frame)
    local region = { frame = frame, order = 0 }

    Element {
        ClassName = "UIListLayout",
        Parent    = frame,
        Name      = "Layout",
        Padding   = UDim.new(0, Theme.Space.Gap),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }

    function region:Next()
        region.order = region.order + 1
        return region.order
    end

    function region:CreateRow(height)
        return Row(region.frame, region:Next(), height or 28)
    end

    function region:Columns(row, count, gap, height)
        return Columns(row, count, gap, height)
    end

    function region:CreateSection(name)
        return Heading(region.frame, region:Next(), name)
    end

    function region:CreateToggle(settings)
        settings = settings or {}
        local element = Switch {
            Parent  = region.frame,
            Name    = settings.Name,
            Caption = settings.Name,
            Order   = region:Next(),
            Value   = settings.CurrentValue,
            OnChange = settings.Callback,
        }
        RegisterFlag(settings.Flag, {
            Type = "Toggle",
            Get  = element.Get,
            Set  = function(value)
                element.Set(value)
                if settings.Callback then
                    settings.Callback(value)
                end
            end,
        })
        return element
    end

    function region:CreateDropdown(settings)
        settings = settings or {}
        local element = Select {
            Parent   = region.frame,
            Name     = settings.Name,
            Caption  = settings.Name,
            Order    = region:Next(),
            Options  = settings.Options,
            Value    = settings.CurrentOption,
            OnSelect = settings.Callback,
        }
        RegisterFlag(settings.Flag, {
            Type = "Dropdown",
            Get  = element.Get,
            Set  = function(value)
                element.Set(value)
                if settings.Callback then
                    settings.Callback(value)
                end
            end,
        })
        return element
    end

    function region:CreateInput(settings)
        settings = settings or {}
        local row = region:CreateRow(Metrics.Inset + 2)

        Texted(row, {
            Text     = string.upper(settings.Name or "INPUT"),
            Tint     = "Muted",
            Size     = Theme.Type.Heading,
            Size2    = UDim2.new(0.45, 0, 1, 0),
            ZIndex   = 3,
        })

        local box = Input {
            Parent           = row,
            Name             = settings.Name,
            Order            = 1,
            Size             = UDim2.new(0.55, 0, 0, Metrics.Inset),
            Position         = UDim2.new(1, 0, 0.5, 0),
            PlaceholderText  = settings.PlaceholderText,
            NumbersOnly      = settings.NumbersOnly,
            CharacterLimit   = settings.CharacterLimit,
            SubmitOnEnter    = settings.OnEnter,
            RemoveTextAfterFocusLost = settings.RemoveTextAfterFocusLost,
            OnSubmit         = settings.Callback,
        }
        box.AnchorPoint = Vector2.new(1, 0.5)

        RegisterFlag(settings.Flag, {
            Type = "Input",
            Get  = function()
                return box.Text
            end,
            Set  = function(value)
                box.Text = tostring(value)
                if settings.Callback then
                    settings.Callback(value)
                end
            end,
        })
        return box
    end

    function region:CreateButton(settings)
        settings = settings or {}
        return Button {
            Parent  = region.frame,
            Name    = settings.Name,
            Caption = settings.Name,
            Order   = region:Next(),
            OnClick = settings.Callback,
        }
    end

    -- A hand-placed control joins the same list, so mixing the two styles keeps the order
    -- the caller wrote them in.
    function region:Place(properties)
        properties = properties or {}
        properties.Parent = region.frame
        properties.Order  = region:Next()
        return properties
    end

    return region
end

--=== app ===================================================================

-- clock, appliedAngle and lens are the rain's own state: the clock drives the gusts, appliedAngle is
-- the lean the drops were last rotated to, and lens is the eased cursor the warp is centred on.
local App = { gui = nil, overlay = nil, blur = nil, rain = nil, rainConnection = nil, streaks = {}, connections = {}, windows = {}, plates = {}, surfaces = {},
    clock = 0, appliedAngle = 0, lens = nil, seededWidth = nil }

local function EnsureGui(name)
    if App.gui ~= nil and App.gui.Parent ~= nil then
        return App.gui
    end

    App.gui = Element {
        ClassName      = "ScreenGui",
        Parent         = UiContainer(),
        Name           = name or "MonoUI",
        IgnoreGuiInset = true,
        ResetOnSpawn   = false,
        DisplayOrder   = 2147483000,
        ZIndexBehavior = Enum.ZIndexBehavior.Global,
    }

    -- The layer anything inside a window can escape into: a dropdown list opened inside a scrolling
    -- body would be clipped by it, so the list is re-parented here and placed by hand. Zero-sized
    -- and without a layout of its own, so it costs the plate nothing at all.
    App.overlay = Element {
        ClassName              = "Frame",
        Parent                 = App.gui,
        Name                   = "Overlay",
        BackgroundTransparency = 1,
        Size                   = UDim2.fromOffset(0, 0),
        ZIndex                 = 40,
    }
    return App.gui
end

-- The plate each control belongs to, so a control deep inside a tab can find the window that has to
-- move out of the keyboard's way without being handed it at creation.
local PlateObjects = {}

-- A phone's keyboard covers the bottom half of the screen, and the box the caret is in is usually
-- the last thing laid out. So the window steps above the keyboard when an input takes focus, and
-- comes back when it lets go - unless the user dragged it somewhere in the meantime, which is a
-- place they chose and not one to take back.
function LiftForKeyboard(box)
    if not MonoUI.Touch or not Theme.Mobile.LiftForKeyboard then return end

    local surface = box
    while surface ~= nil and PlateObjects[surface] == nil do
        surface = surface.Parent
    end

    local object = surface and PlateObjects[surface]
    if object == nil or object.lifted ~= nil then return end
    if box.AbsolutePosition.Y < Viewport().Y * 0.45 then return end

    object.lifted = object.plate.Position
    object.plate.Position = UDim2.new(object.lifted.X.Scale, object.lifted.X.Offset, 0, TopInset() + Theme.Mobile.Margin)
end

function DropLift(box)
    local surface = box
    while surface ~= nil and PlateObjects[surface] == nil do
        surface = surface.Parent
    end

    local object = surface and PlateObjects[surface]
    if object == nil or object.lifted == nil then return end

    object.plate.Position = object.lifted
    object.lifted = nil
end

-- A phone's strip is only as wide as the phone, so the cells are cut to the number of tabs and
-- allowed to wrap instead of running off the edge: a tab is never narrower than a fingertip, and
-- the strip grows by a row rather than hiding the tab that did not fit.
local function ArrangeTabs(window)
    if not MonoUI.Touch then return end

    local count = #window.tabs
    local grid  = window.grid
    if count == 0 or grid == nil then return end

    local gap    = Theme.Space.Gap
    local room   = window.width - (Theme.Space.Pad * 2)
    local perRow = math.max(1, math.min(count, math.floor((room + gap) / ((Metrics.Row * 2) + gap))))
    local rows   = math.ceil(count / perRow)
    local cell   = (room - (gap * (perRow - 1))) / perRow
    local height = (rows * Metrics.Tab) + ((rows - 1) * gap)

    grid.CellSize              = UDim2.new(0, cell, 0, Metrics.Tab)
    grid.CellPadding           = UDim2.new(0, gap, 0, gap)
    grid.FillDirectionMaxCells = perRow
    window.strip.Size          = UDim2.new(1, 0, 0, height)
    window.viewport.Reserve    = count > 1 and height or 0                              -- a lone tab needs no strip at all
    window.viewport:Resize()
end

-- A list opened inside a scroller is lifted out of it, because the scroller would cut it off at the
-- first row past its own edge. It is placed against the row it belongs to, in the row's own width,
-- and it opens upward when there is no room below - the row that needs a list can be the last one
-- on the screen, and a list that opens off the bottom is a list that cannot be used.
function PlaceMenu(menu, row)
    if AncestorOfClass(row, "ScrollingFrame") == nil then return end                -- nothing is clipping it
    local overlay = App.overlay
    local plate   = PlateOf(row)
    if overlay == nil or plate == nil then return end

    local scale  = SurfaceScale(plate)
    local screen = Viewport()
    local height = menu.Size.Y.Offset
    local shift  = 4                                                                 -- the gap the list keeps from its row
    local top    = row.AbsolutePosition.Y
    local bottom = top + row.AbsoluteSize.Y
    local upward = bottom + ((height + shift) * scale) > (screen.Y - Theme.Mobile.Margin)

    menu.Parent      = overlay
    menu.AnchorPoint = upward and Vector2.new(0, 1) or Vector2.new(0, 0)
    menu.Size        = UDim2.fromOffset(row.AbsoluteSize.X / scale, height)
    menu.Position    = UDim2.fromOffset(
        (row.AbsolutePosition.X - overlay.AbsolutePosition.X) / scale,
        (top - overlay.AbsolutePosition.Y + (upward and -(shift * scale) or ((row.AbsoluteSize.Y + shift) * scale))) / scale
    )
end

local function EnsureBlur(settings)
    if settings.Blur == false or (settings.Blur or Theme.Blur) <= 0 then
        return nil
    end
    if App.blur ~= nil and App.blur.Parent ~= nil then
        return App.blur
    end

    -- The effect is named for this library, so one left over from an earlier run is ours to take
    -- over and ours to remove again; there is no foreign blur to be careful about.
    local existing = Lighting:FindFirstChild("MonoUIBlur")
    App.blur = existing or Element {
        ClassName = "BlurEffect",
        Parent    = Lighting,
        Name      = "MonoUIBlur",
        Size      = settings.Blur or Theme.Blur,
    }
    return App.blur
end

-- Rain: a sheet of drops behind the window, inside the same gui at ZIndex 0 while the plate sits at
-- 1, so it reads as the window's own background rather than as something laid over the game.
--
-- A drop is one Frame, and every property of it comes from a single sampled drop size and a single
-- depth: a 5 mm drop falls at about 9 m/s and is drawn wide and nearly opaque, a drizzle drop falls
-- at under 2 m/s and is a faint hairline further back. Drawing speed, length and opacity from
-- separate dice is what makes rain read as a scrolling texture, because it produces combinations no
-- camera would ever see.
local function Between(range)
    return range[1] + math.random() * (range[2] - range[1])
end

-- How far past a side edge a drifting drop is allowed to go before it is recycled: wider than a
-- drop, so one is fully out of sight before it is rolled again.
local EdgeMargin = 20

-- Marshall-Palmer: drop sizes are exponential in diameter, not uniform, so small drops are common
-- and large ones rare. The slope follows the rain rate, which is what lets Intensity be the one
-- control the whole shower hangs off.
local function SampleDiameter(rain)
    local slope    = 4.1 * rain.Intensity ^ -0.21
    local diameter = -math.log(1 - math.random()) / slope
    return math.clamp(diameter, rain.MinDiameter, rain.MaxDiameter)
end

-- Terminal velocity against diameter: about 4 m/s at 1 mm and 9 m/s at 5 mm, which is the range the
-- measurements agree on for real rain.
local function FallSpeedMetres(diameter)
    return 9.65 - 10.3 * math.exp(-0.6 * diameter)
end

-- The lean of the whole sheet, in radians. The noise term is the gust: it wanders smoothly rather
-- than jumping, so the rain sways instead of every drop turning at once.
local function WindAngle(clock)
    local wind = Theme.Rain.Wind
    local gust = math.noise(clock * wind.GustRate, 7.3) * 2
    return math.rad(wind.Angle + gust * wind.Gust)
end

-- One drop, rolled from scratch: size, speed, length, width, opacity, and a spawn on the slanted
-- band just above the top edge. Everything a drop is, in one place, so a recycled drop is a new
-- drop rather than an old one wearing a new speed.
local function RollDrop(drop, bounds, tangent)
    local rain     = Theme.Rain
    local diameter = SampleDiameter(rain)
    local depth    = Between(rain.Depth)
    local speed    = FallSpeedMetres(diameter) * rain.PixelsPerMeter * depth
    local opacity  = depth * (0.35 + 0.5 * diameter / rain.MaxDiameter)
    local width    = math.max(1, math.floor(diameter * depth * 0.6 + 0.5))
    local spawnMin = math.min(0, -bounds.Y * tangent)
    local spawnMax = math.max(bounds.X, bounds.X - bounds.Y * tangent)

    drop.Speed                        = speed
    drop.Length                       = math.max(4, speed * rain.Exposure)
    drop.X                            = Between({ spawnMin, spawnMax })
    drop.Y                            = -drop.Length
    drop.Frame.Size                   = UDim2.fromOffset(width, drop.Length)
    drop.Frame.BackgroundTransparency = 1 - opacity
end

local function BuildDrop(layer, index)
    local frame = Element {
        ClassName        = "Frame",
        Parent           = layer,
        Name             = "Drop" .. index,
        AnchorPoint      = Vector2.new(0.5, 0.5),                                     -- the position is the middle of the streak
        BackgroundColor3 = Theme[Theme.Rain.Tint or "Muted"],
        BorderSizePixel  = 0,
        ZIndex           = 0,
    }

    -- A streak is a smear, not a bar: clear where it has been, solid at the head that is still
    -- moving. Rotation 90 runs the gradient down the streak, keypoint 0 at the top.
    Element {
        ClassName    = "UIGradient",
        Parent       = frame,
        Rotation     = 90,
        Transparency = NumberSequence.new {
            NumberSequenceKeypoint.new(0.0, 1.0),
            NumberSequenceKeypoint.new(0.6, 0.5),
            NumberSequenceKeypoint.new(1.0, 0.0),
        },
    }
    return { Frame = frame, X = 0, Y = 0, Speed = 0, Length = 0 }
end

-- The cursor is a lens, and a lens has to stay monotonic to read as one. This displacement is zero
-- at the centre - so there is no undefined direction to scatter drops - and zero at the rim, so a
-- drop enters and leaves the well without jumping. It is fold-free for any Strength up to
-- 3 * Radius. The shape it replaced, Strength * (1 - ratio^2)^2, peaked away from the centre and
-- folded the field inside the radius, crushing everything in range into a ring.
local function LensOffset(offsetX, offsetY, warp)
    local squared = offsetX * offsetX + offsetY * offsetY
    if squared >= warp.Radius * warp.Radius or squared == 0 then return 0, 0 end

    local distance = math.sqrt(squared)
    local ratio    = distance / warp.Radius
    local push     = warp.Strength * ratio * (1 - ratio) ^ 2
    return (offsetX / distance) * push, (offsetY / distance) * push
end

local function AdvanceDrop(drop, step, wind, bounds)
    drop.X = drop.X + drop.Speed * wind.Sine   * step
    drop.Y = drop.Y + drop.Speed * wind.Cosine * step

    local fellOut    = drop.Y - drop.Length > bounds.Y
    local driftedOut = (wind.Sine > 0 and drop.X > bounds.X + EdgeMargin) or (wind.Sine < 0 and drop.X < -EdgeMargin)
    if not (fellOut or driftedOut) then return end

    RollDrop(drop, bounds, wind.Tangent)
end

local function DrawDrop(drop, lens, warp, rotation)
    -- No lens, no displacement: a phone skips the whole warp rather than paying for it per drop.
    local x, y = drop.X, drop.Y
    if lens ~= nil then
        local pushX, pushY = LensOffset(drop.X - lens.X, drop.Y - lens.Y, warp)
        x, y = x + pushX, y + pushY
    end

    drop.Frame.Position = UDim2.fromOffset(x, y)
    if rotation == nil then return end
    drop.Frame.Rotation = rotation
end

local function StepRain(deltaTime)
    local layer = App.rain
    if layer == nil then return end

    local bounds = layer.AbsoluteSize
    if bounds.Y <= 0 then return end

    -- Clamped, so an alt-tab or one slow frame cannot drop the whole shower below the bottom edge
    -- at once: the rain keeps its shape through a hitch instead of teleporting.
    local rain = Theme.Rain
    local step = math.min(deltaTime, rain.MaxStep)
    App.clock  = App.clock + step

    local angle    = WindAngle(App.clock)
    local wind     = { Sine = math.sin(angle), Cosine = math.cos(angle), Tangent = math.tan(angle) }
    local turned   = math.abs(angle - App.appliedAngle) > 0.01
    local rotation = turned and -math.deg(angle) or nil                            -- a rotated streak: the frame follows the fall
    App.appliedAngle = turned and angle or App.appliedAngle

    -- The layer is built before the layout has run, so its width may still be the 1920 default when
    -- the drops are seeded. The first step that knows the real bounds re-seeds inside them: without
    -- this, a hand-built 720-wide window only ever sees a third of the rain, the rest falling outside.
    if App.seededWidth ~= bounds.X then
        App.seededWidth = bounds.X
        for _, drop in ipairs(App.streaks) do
            RollDrop(drop, bounds, wind.Tangent)
            drop.Y = math.random() * bounds.Y
        end
    end

    -- The well trails the cursor rather than snapping to it, so the glass bends the rain a moment
    -- after the pointer arrives. The drops still fall on their own path - the warp only decides
    -- where each one is drawn - which is what lets a drop enter or leave the field without jumping.
    -- A touch screen has no cursor to bend the space with, so the well is skipped there and the
    -- drops fall straight.
    local lens = nil
    if rain.Warp.Enabled then
        local target = UserInput:GetMouseLocation() - layer.AbsolutePosition
        App.lens     = (App.lens or target):Lerp(target, 1 - math.exp(-rain.Warp.Follow * step))
        lens         = App.lens
    end

    for _, drop in ipairs(App.streaks) do
        AdvanceDrop(drop, step, wind, bounds)
        DrawDrop(drop, lens, rain.Warp, rotation)
    end
end

local function StartRain()
    if App.rain == nil then
        return
    end

    App.rain.Visible = true
    if App.rainConnection == nil then
        -- Heartbeat, not RenderStepped: nothing here has to be decided before the frame is drawn,
        -- and it keeps the whole effect off the frame's critical path.
        App.rainConnection = RunService.Heartbeat:Connect(StepRain)
    end
end

local function StopRain()
    if App.rainConnection ~= nil then
        pcall(function()
            App.rainConnection:Disconnect()                                              -- hidden means nothing steps
        end)
        App.rainConnection = nil
    end
    if App.rain ~= nil then
        App.rain.Visible = false
    end
end

local function EnsureRain(settings)
    local rain = Theme.Rain
    if settings.Rain == false or rain == nil or rain.Enabled == false or (rain.Count or 0) <= 0 then
        return nil
    end
    if App.rain ~= nil and App.rain.Parent ~= nil then
        return App.rain
    end

    local layer = Element {
        ClassName              = "Frame",
        Parent                 = settings.RainParent or App.gui,                      -- a hand-built window owns its own rain
        Name                   = "Rain",
        BackgroundTransparency = 1,
        ClipsDescendants       = true,                                                -- a plate-sized layer must not spill outside its window
        Size                   = UDim2.new(1, 0, 1, 0),
        Visible                = false,
        ZIndex                 = 0,
    }

    -- A surface can register before its layout has run, in which case the layer still measures
    -- (0, 0) and the drops have to be spread across a guessed viewport. Leaving seededWidth unset in
    -- that case is what makes the first step that knows the real bounds re-seed inside them.
    local size   = layer.AbsoluteSize
    local width  = size.X > 0 and size.X or 1920
    local height = size.Y > 0 and size.Y or 1080
    App.seededWidth = size.X > 0 and size.X or nil
    App.lens        = nil                                                             -- a new layer, a new space for the well to live in

    local bounds  = Vector2.new(width, height)
    local tangent = math.tan(WindAngle(App.clock))

    -- Rolled, then spread down the whole layer, so the first frame is already rain falling rather
    -- than a burst starting on one line.
    App.streaks = {}
    for index = 1, rain.Count do
        local drop = BuildDrop(layer, index)
        RollDrop(drop, bounds, tangent)
        drop.Y = math.random() * height
        drop.Frame.Position = UDim2.fromOffset(drop.X, drop.Y)                        -- in place from the first frame, not piled at (0, 0)
        App.streaks[index] = drop
    end

    App.rain = layer
    return layer
end

-- What each surface asked for, kept beside the list rather than on the surface itself: a surface may
-- be a plain Frame - a window built by hand, like Stretcher's - and an instance rejects an unknown
-- field ("wantsBlur is not a valid member of Frame"), which took the whole registration down with it.
local surfaceWants = {}

-- Blur and rain follow the surfaces that are on screen: only visible ones are registered, so a
-- hidden window cannot switch off the effects a plate is still using. The decision itself lives in
-- one place because the blur is one shared effect for the whole app, which is why hiding the last
-- surface stops both instead of each effect deciding for itself.
local function SyncEffects()
    local wantBlur = false
    local wantRain = false

    for _, surface in ipairs(App.surfaces) do
        local wanted = surfaceWants[surface]
        if wanted ~= nil and wanted.blur then wantBlur = true end
        if wanted ~= nil and wanted.rain then wantRain = true end
    end

    if App.blur ~= nil and App.blur.Parent ~= nil then
        App.blur.Enabled = wantBlur
    end

    if App.rain ~= nil and wantRain then
        StartRain()
    else
        StopRain()
    end
end

-- Windows and plates register while they are visible and unregister when hidden, so this list is
-- a list of what is actually on screen.
local function RegisterSurface(surface, settings)
    surfaceWants[surface] = {
        blur = EnsureBlur(settings) ~= nil,
        rain = EnsureRain(settings) ~= nil,
    }
    if table.find(App.surfaces, surface) == nil then
        App.surfaces[#App.surfaces + 1] = surface
    end
    SyncEffects()
    return surface
end

local function UnregisterSurface(surface)
    local index = table.find(App.surfaces, surface)
    if index ~= nil then
        table.remove(App.surfaces, index)
    end
    surfaceWants[surface] = nil
    SyncEffects()
end

-- How tall a body is allowed to get before it scrolls: the screen, less the safe area, less the
-- window's own chrome and one margin at each edge. `reserve` is the room the body does not get -
-- the tab strip, on a window.
local function BodyCapacity(reserve)
    local screen = Viewport()
    return math.max(screen.Y - TopInset() - (Theme.Mobile.Margin * 2) - Metrics.Bar - (reserve or 0) - (Theme.Space.Pad * 2), 120)
end

-- A body sits in a viewport. On a desktop that is a plain frame that grows with what is in it, so
-- the plate is exactly as tall as its contents; on a phone it is a scrolling frame capped at what
-- the screen can show, because a window taller than the phone is a window with controls that cannot
-- be reached.
--
-- The height is measured from the content rather than guessed, so a short window stays short and
-- only a long one scrolls. Only the frame that is on screen is measured: a tab waiting in the
-- holder is zero-sized and would otherwise report nothing and collapse the window.
local function CreateViewport(plate, order, reserve)
    local touch = MonoUI.Touch

    -- Built in two passes because the two frames differ in which properties exist at all: a plain
    -- frame cannot carry a canvas size, and a scrolling frame must not also auto-size, or it would
    -- grow to its contents and never scroll.
    local properties = {
        ClassName              = touch and "ScrollingFrame" or "Frame",
        Parent                 = plate,
        Name                   = "Viewport",
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, 0, 0),
        LayoutOrder            = order or 3,
    }

    if touch then
        properties.AutomaticCanvasSize = Enum.AutomaticSize.Y
        properties.CanvasSize          = UDim2.new(0, 0, 0, 0)
        properties.ScrollBarThickness  = 3
        properties.ScrollingEnabled    = true
        properties.ElasticBehavior     = Enum.ElasticBehavior.WhenScrollable
    else
        properties.AutomaticSize = Enum.AutomaticSize.Y
    end

    local frame = Element(properties)

    local viewport = { Frame = frame, content = nil, connection = nil, Reserve = reserve or 0 }

    function viewport:Resize()
        if not touch or viewport.content == nil then return end

        local capacity = BodyCapacity(viewport.Reserve)
        local height   = math.min(viewport.content.AbsoluteSize.Y / SurfaceScale(plate), capacity)
        frame.Size     = UDim2.new(1, 0, 0, math.max(height, 1))
    end

    function viewport:Show(content)
        if viewport.connection ~= nil then
            pcall(function()
                viewport.connection:Disconnect()
            end)
            viewport.connection = nil
        end

        viewport.content = content
        if content == nil then return end
        content.Parent = frame
        if not touch then return end

        viewport.connection = content:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
            viewport:Resize()
        end)
        frame.CanvasPosition = Vector2.zero                                          -- a tab opened fresh starts at its top
        viewport:Resize()
    end

    function viewport:Destroy()
        if viewport.connection ~= nil then
            pcall(function()
                viewport.connection:Disconnect()
            end)
            viewport.connection = nil
        end
    end

    return viewport
end

-- One plate: the window surface itself, with the title bar, the hint line and the drag.
-- Everything else - the tab strip, the body, a second plate - hangs off it.
local function CreatePlateFrame(settings, order)
    local width = PlateWidth(settings.Width)
    local plate = Sticker(Element {
        ClassName     = "Frame",
        Parent        = EnsureGui(settings.GuiName),
        Name          = settings.Name or "Plate",
        AnchorPoint   = Vector2.new(0, 0),
        Position      = settings.Position or PlatePosition(width, order),
        Size          = UDim2.fromOffset(width, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        ZIndex        = 1,
    }, {
        Color   = "Surface",
        Alpha   = Theme.WindowTransparency,
        Corner  = "Radius",
        Stroke  = "Outline",
        Rim     = true,
        Glass   = true,
        Padding = { Theme.Space.Pad, Theme.Space.Pad, Theme.Space.Pad, Theme.Space.Pad },
        Gap     = { Padding = Theme.Space.Gap },
    })

    -- The scale the plate is revealed with. It lives on the plate itself, so the whole window
    -- moves together and nothing inside it has to know that it was shown rather than placed.
    Element { ClassName = "UIScale", Parent = plate, Name = "Scale" }

    -- The bar is measured from the metrics, and so is everything on it: the title sits above the
    -- hint line, both placed off the bar's own middle, so a touch bar is taller without the two
    -- lines drifting apart.
    local middle = math.floor(Metrics.Bar / 2)
    local bar = Sticker(Element {
        ClassName   = "Frame",
        Parent      = plate,
        Name        = "Bar",
        Size        = UDim2.new(1, 0, 0, Metrics.Bar),
        LayoutOrder = 1,
    }, { Color = "Header", Alpha = Theme.PanelAlpha, Corner = "RowRadius", Stroke = "Line", Glass = true })

    -- With no keyboard there is no Right Control, so a touch window carries the way out on itself:
    -- a small button at the end of the title bar. It is what the chip brings the window back from.
    local wantsHide = MonoUI.Touch or settings.HideButton == true
    local hideWidth = wantsHide and (Metrics.Hide + 6) or 0
    local hideButton = nil

    if wantsHide then
        hideButton = Sticker(Element {
            ClassName       = "TextButton",
            Parent          = bar,
            Name            = "Hide",
            AnchorPoint     = Vector2.new(1, 0.5),
            Position        = UDim2.new(1, -8, 0.5, 0),
            Size            = UDim2.fromOffset(Metrics.Hide, Metrics.Hide),
            AutoButtonColor = false,
            Text            = "",
            ZIndex          = 3,
        }, { Color = "Row", Alpha = Theme.RowAlpha, Corner = "RowRadius", Stroke = "Line" })

        Texted(hideButton, {
            Text   = "-",
            Tint   = "Muted",
            Size   = Theme.Type.Label,
            X      = Enum.TextXAlignment.Center,
            ZIndex = 4,
        })
        Hoverable(hideButton, RowLooks)
    end

    Texted(bar, {
        Text     = string.upper(settings.Name or "PLATE"),
        Size     = Theme.Type.Label,
        Bold     = true,
        Position = UDim2.fromOffset(12, middle - 13),
        Size2    = UDim2.new(1, -(128 + hideWidth), 0, 16),
        ZIndex   = 2,
    })

    local hint = Texted(bar, {
        Text     = settings.Hint or "",
        Tint     = "Muted",
        Size     = Theme.Type.Support,
        Bold     = false,
        Position = UDim2.fromOffset(12, middle + 3),
        Size2    = UDim2.new(1, -(128 + hideWidth), 0, 11),
        ZIndex   = 2,
    })

    -- the pill that shows state, and the dot that carries its colour
    local pill = Sticker(Element {
        ClassName   = "Frame",
        Parent      = bar,
        Name        = "Status",
        AnchorPoint = Vector2.new(1, 0.5),
        Position    = UDim2.new(1, -(10 + hideWidth), 0.5, 0),
        Size        = UDim2.fromOffset(settings.PillWidth or (MonoUI.Touch and 96 or 112), 22),
        ZIndex      = 2,
    }, { Color = "Row", Alpha = Theme.RowAlpha, Corner = 0.5, Stroke = "Line" })

    local dot = Sticker(Element {
        ClassName   = "Frame",
        Parent      = pill,
        Name        = "Dot",
        AnchorPoint = Vector2.new(0, 0.5),
        Position    = UDim2.new(0, 8, 0.5, 0),
        Size        = UDim2.fromOffset(7, 7),
        ZIndex      = 3,
    }, { Color = "Muted", Corner = 0.5 })

    local status = Texted(pill, {
        Text     = "READY",
        Size     = Theme.Type.Support,
        Position = UDim2.fromOffset(21, 0),
        Size2    = UDim2.new(1, -28, 1, 0),
        ZIndex   = 3,
    })

    return plate, bar, hint, { pill = pill, dot = dot, label = status }, hideButton
end

function MonoUI:CreatePlate(settings)
    settings = settings or {}
    Motion.Enabled = settings.Motion ~= false

    local plate, bar, hint, status, hideButton = CreatePlateFrame(settings, #App.plates + 1)

    local object = {
        connections   = {},
        dragThreshold = settings.DragThreshold or 3,
        plate         = plate,
        bar           = bar,
        status        = status,
        settings      = settings,
        visible       = true,
        width         = plate.Size.X.Offset,                                         -- what FitSurface fits the window into
        hideButton    = hideButton,
    }
    App.plates[#App.plates + 1] = object
    PlateObjects[plate] = object

    object.viewport = CreateViewport(plate, 2, 0)

    object.body = Element {
        ClassName     = "Frame",
        Parent        = nil,
        Name          = "Body",
        BackgroundTransparency = 1,
        Size          = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
    }
    object.viewport:Show(object.body)

    local region = CreateRegion(object.body)
    for key, value in pairs(region) do
        if type(value) == "function" then
            object[key] = value
        end
    end
    object.region = region

    RegisterSurface(object, settings)
    Dragging(object, plate, bar)

    if hideButton ~= nil then
        hideButton.MouseButton1Click:Connect(function()
            object:SetVisible(false)
        end)
    end

    local hintText = settings.Hint
    if hintText == nil and settings.ToggleKey ~= nil then
        hintText = string.upper(tostring(settings.ToggleKey.Name)) .. " TO HIDE"
    end
    if hintText == nil and hideButton ~= nil then
        hintText = "TAP - TO HIDE"
    end
    hint.Text = hintText or ""

    FitSurface(plate, object.width)

    function object:Refit()
        FitSurface(plate, object.width)
        ClampSurface(plate)
        object.viewport:Resize()
    end

    WatchViewport(object)

    function object:SetStatus(text, tint)
        status.label.Text    = tostring(text or "")
        status.dot.BackgroundColor3 = tint or Theme.Muted
    end

    function object:SetVisible(visible)
        object.visible = visible and true or false
        plate.Visible  = object.visible

        if object.visible then
            RegisterSurface(object, settings)
            Reveal(plate)
        else
            UnregisterSurface(object)
        end
        return object.visible
    end

    function object:Destroy()
        for _, connection in ipairs(object.connections) do
            pcall(function()
                connection:Disconnect()
            end)
        end
        table.clear(object.connections)
        PlateObjects[plate] = nil
        object.viewport:Destroy()
        UnregisterSurface(object)
        pcall(function()
            plate:Destroy()
        end)
    end

    return object
end

function MonoUI:CreateWindow(settings)
    settings = settings or {}
    if settings.Mobile ~= nil then
        MonoUI:SetTouch(settings.Mobile)                                             -- the switch is global: row heights are read while controls are built
    end
    Settings.Enabled  = (settings.ConfigurationSaving or {}).Enabled == true
    Settings.FileName = (settings.ConfigurationSaving or {}).FileName or settings.Name or "MonoUI"
    Motion.Enabled    = settings.Motion ~= false

    local name = tostring(settings.Name or "MONOUI")
    EnsureGui(settings.GuiName or name)

    local window = {
        connections = {},
        dragThreshold = settings.DragThreshold or 3,
        settings = settings,
        tabs = {},
        active = nil,
        visible = not settings.StartHidden,
    }
    App.windows[#App.windows + 1] = window

    local plate, bar, hint, status, hideButton = CreatePlateFrame(settings, #App.windows)
    window.plate = plate
    window.bar = bar
    window.status = status
    window.hideButton = hideButton
    window.width = plate.Size.X.Offset                                             -- what FitSurface fits the window into
    PlateObjects[plate] = window

    local strip = Element {
        ClassName              = "Frame",
        Parent                 = nil,                                             -- only parented once a second tab exists
        Name                   = "Tabs",
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, 0, Metrics.Tab),
        LayoutOrder            = 2,
    }
    Element {
        ClassName             = "UIGridLayout",
        Parent                = strip,
        Name                  = "Columns",
        CellSize              = UDim2.new(0, 132, 0, Metrics.Tab),
        CellPadding           = UDim2.new(0, 6, 0, 0),
        FillDirection         = Enum.FillDirection.Horizontal,
        FillDirectionMaxCells = 6,
        SortOrder             = Enum.SortOrder.LayoutOrder,
    }
    window.strip = strip
    window.grid  = strip:FindFirstChild("Columns")

    -- The body of the window: whichever tab is in front, inside a frame that scrolls when the
    -- screen is shorter than the tab is.
    window.viewport = CreateViewport(plate, 3, Metrics.Tab)

    local holder = Element {
        ClassName = "Frame",
        Parent    = App.gui,
        Name      = "Inactive",
        Size      = UDim2.fromOffset(0, 0),
        Visible   = false,
        ZIndex    = 0,
    }
    window.holder = holder

    -- the pill that stays on screen while the window is hidden
    local chipSize = MonoUI.Touch and UDim2.fromOffset(168, 40) or UDim2.fromOffset(132, 26)
    local chip = Sticker(Element {
        ClassName       = "TextButton",
        Parent          = App.gui,
        Name            = "Chip",
        Position        = MonoUI.Touch and UDim2.fromOffset(Theme.Mobile.Margin, TopInset() + Theme.Mobile.Margin) or nil,
        Size            = chipSize,
        AutoButtonColor = false,
        Text            = "",
        Visible         = false,
        ZIndex          = 5,
    }, { Color = "Surface", Alpha = Theme.WindowTransparency, Corner = "RowRadius", Stroke = "Outline", Rim = true, Glass = true })

    Texted(chip, {
        Text   = string.upper(name),
        Size   = Theme.Type.Support,
        X      = Enum.TextXAlignment.Center,
        ZIndex = 6,
    })
    window.chip = chip

    Dragging(window, plate, bar)
    Dragging(window, chip, chip)
    chip.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            window:SetVisible(true)
        end
    end)

    FitSurface(plate, window.width)

    function window:Refit()
        FitSurface(plate, window.width)
        ClampSurface(plate)
        window.viewport:Resize()
    end

    WatchViewport(window)

    function window:SetStatus(text, tint)
        status.label.Text = tostring(text or "")
        status.dot.BackgroundColor3 = tint or Theme.Muted
    end

    function window:SetVisible(visible)
        window.visible = visible and true or false
        plate.Visible  = window.visible
        chip.Visible   = not window.visible

        if window.visible then
            RegisterSurface(window, settings)
            Reveal(plate)
        else
            UnregisterSurface(window)
        end
        return window.visible
    end

    function window:Toggle()
        return window:SetVisible(not window.visible)
    end

    function window:CreateTab(tabName)
        local tab = {
            Name    = tostring(tabName or "Tab"),
            content = Element {
                ClassName     = "Frame",
                Parent        = nil,
                Name          = tostring(tabName or "Tab") .. "Content",
                BackgroundTransparency = 1,
                Size          = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                LayoutOrder   = 3,
            },
        }

        local region = CreateRegion(tab.content)
        for key, value in pairs(region) do
            if type(value) == "function" then
                tab[key] = value
            end
        end

        tab.button = Sticker(Element {
            ClassName       = "TextButton",
            Parent          = strip,
            Name            = tab.Name,
            Size            = UDim2.new(1, 0, 1, 0),
            AutoButtonColor = false,
            Text            = "",
            LayoutOrder     = #window.tabs + 1,
            ZIndex          = 2,
        }, { Color = "Row", Alpha = Theme.RowAlpha, Corner = "RowRadius", Stroke = "Line" })

        tab.label = Texted(tab.button, {
            Text   = string.upper(tab.Name),
            Size   = Theme.Type.Heading,
            X      = Enum.TextXAlignment.Center,
            ZIndex = 3,
        })

        local function Focus()
            window.active = tab
            for _, other in ipairs(window.tabs) do
                local active = other == tab
                if active then
                    window.viewport:Show(other.content)
                else
                    other.content.Parent = holder
                end
                other.content.LayoutOrder = 3
                other.button.BackgroundColor3 = Theme[active and "Text" or "Row"]
                other.button.BackgroundTransparency = active and Theme.SwitchOnAlpha or Theme.WellAlpha
                other.label.TextColor3 = Theme[active and "Invert" or "Text"]
            end
        end

        tab.button.MouseButton1Click:Connect(Focus)
        window.tabs[#window.tabs + 1] = tab
        ArrangeTabs(window)

        -- a single tab needs no strip; with two or more it comes back into the plate, and in
        -- between it waits inside the holder so Destroy still reaches it
        strip.Parent = #window.tabs > 1 and plate or holder
        Focus()

        return tab
    end

    function window:Destroy()
        for _, connection in ipairs(window.connections) do
            pcall(function()
                connection:Disconnect()
            end)
        end
        table.clear(window.connections)
        PlateObjects[plate] = nil

        Motion.Destroy()

        for flag in pairs(MonoUI.Flags) do
            MonoUI.Flags[flag] = nil
        end

        -- every plate lives in the one gui, so the app goes together
        local gui  = App.gui
        local blur = App.blur

        window.viewport:Destroy()
        UnregisterSurface(window)
        StopRain()
        table.clear(surfaceWants)

        App.gui      = nil
        App.overlay  = nil
        App.blur     = nil
        App.rain     = nil
        App.streaks  = {}
        App.windows  = {}
        App.plates   = {}
        App.surfaces = {}

        -- what the rain carries between frames: a destroyed app leaves no clock, well or seed behind
        App.clock        = 0
        App.appliedAngle = 0
        App.lens         = nil
        App.seededWidth  = nil
        if gui ~= nil then
            pcall(function()
                gui:Destroy()
            end)
        end
        if blur ~= nil then
            pcall(function()
                blur:Destroy()                                                              -- named for this library, so it goes with it
            end)
        end
    end

    if hideButton ~= nil then
        hideButton.MouseButton1Click:Connect(function()
            window:SetVisible(false)
        end)
    end

    -- The hide key, and the hint that names it. A phone has no Right Control, so a touch window
    -- gets no default key - only one the caller asked for, or one that exists on a keyboard that
    -- happens to be attached - and the hint names the button instead.
    local key = settings.ToggleKey
    if key == nil and (not MonoUI.Touch or Platform.Keyboard) then
        key = Enum.KeyCode.RightControl
    end
    window.settings.ToggleKey = key

    local hintText = settings.Hint
    if hintText == nil and key ~= nil then
        hintText = string.upper(tostring(key.Name)) .. " TO HIDE"
    end
    if hintText == nil and hideButton ~= nil then
        hintText = "TAP - TO HIDE"
    end
    hint.Text = hintText or "NO TOGGLE KEY"

    if key ~= nil then
        window.connections[#window.connections + 1] = UserInput.InputBegan:Connect(function(input, processed)
            if processed then return end
            if input.KeyCode == key then
                window:Toggle()
            end
        end)
    end

    window:SetVisible(window.visible)
    window:SetStatus("READY")

    MonoUI.Window = window
    return window
end

--=== overlay components ====================================================

-- A stack of transient status cards. The newest card sits at the bottom and older cards move up;
-- each card fades in, slides in from the right with a cubic ease, and fades out before removal.
-- The component is data-light on purpose: Push(message, kind) is all a caller needs.
function MonoUI:CreateToastQueue(settings)
    settings = settings or {}
    local tweenService = game:GetService("TweenService")
    local width        = settings.Width or 380
    local height       = settings.Height or 34
    local lifetime     = settings.Lifetime or 4
    local maximum      = settings.Max or 8
    local margin       = settings.Margin or 20
    local queue = {
        Gui       = nil,
        Container = nil,
        Items     = {},
    }

    local function Ensure()
        if queue.Gui and queue.Gui.Parent then
            return
        end

        local gui = Element {
            ClassName      = "ScreenGui",
            Parent         = UiContainer(),
            Name           = settings.GuiName or "MonoUIToasts",
            ResetOnSpawn   = false,
            IgnoreGuiInset = true,
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
            DisplayOrder   = settings.DisplayOrder or 2147483002,
        }
        queue.Gui = gui

        local container = Element {
            ClassName              = "Frame",
            Parent                 = gui,
            Name                   = "Toasts",
            BackgroundTransparency = 1,
            AnchorPoint            = Vector2.new(1, 1),
            Position               = UDim2.new(1, -margin, 1, -margin),
            Size                   = UDim2.new(0, width, 0, height * maximum + 4 * maximum),
            ZIndex                 = 10,
        }
        queue.Container = container
    end

    local function Layout()
        if not queue.Container then
            return
        end

        local baseY = queue.Container.Size.Y.Offset - height

        for index, item in ipairs(queue.Items) do
            if item.Frame and item.Frame.Parent and not item.Dismissed then
                tweenService:Create(
                    item.Frame,
                    TweenInfo.new(0.35, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out),
                    { Position = UDim2.fromOffset(0, baseY - (index - 1) * (height + 4)) }
                ):Play()
            end
        end
    end

    local function Dismiss(item)
        if not item or item.Dismissed or not item.Frame or not item.Frame.Parent then
            return
        end

        item.Dismissed = true
        local tween = tweenService:Create(
            item.Frame,
            TweenInfo.new(0.3, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out),
            { GroupTransparency = 1 }
        )

        tween.Completed:Once(function()
            if item.Frame then
                item.Frame:Destroy()
            end

            for index, value in ipairs(queue.Items) do
                if value == item then
                    table.remove(queue.Items, index)
                    break
                end
            end

            Layout()
        end)
        tween:Play()
    end

    function queue:Push(message, kind)
        Ensure()

        if not queue.Container then
            return
        end

        local accent = kind == "success" and Color3.fromRGB(140, 255, 180)
            or kind == "error" and Color3.fromRGB(255, 95, 95)
            or Theme.Text

        local card = Element {
            ClassName              = "CanvasGroup",
            Parent                 = queue.Container,
            Name                   = "Toast",
            BackgroundColor3       = Theme.Surface,
            BackgroundTransparency = 0.04,
            BorderSizePixel        = 0,
            Size                   = UDim2.new(0, width, 0, height),
            Position               = UDim2.fromOffset(width, queue.Container.Size.Y.Offset - height),
            GroupTransparency      = 1,
            ZIndex                 = 11,
        }

        Element {
            ClassName   = "UICorner",
            Parent      = card,
            CornerRadius = UDim.new(0, Theme.RowRadius),
        }
        Element {
            ClassName   = "UIStroke",
            Parent      = card,
            Color       = accent,
            Transparency = 0.35,
            Thickness   = 1,
        }
        Element {
            ClassName       = "Frame",
            Parent          = card,
            BackgroundColor3 = accent,
            BorderSizePixel  = 0,
            Position         = UDim2.fromOffset(3, 4),
            Size             = UDim2.new(0, 3, 1, -8),
            ZIndex           = 12,
        }
        local label = Element {
            ClassName              = "TextLabel",
            Parent                 = card,
            BackgroundTransparency = 1,
            BorderSizePixel        = 0,
            Text                   = tostring(message),
            TextColor3             = Theme.Text,
            TextSize               = Theme.Type.Body,
            Font                   = Enum.Font.Gotham,
            TextXAlignment          = Enum.TextXAlignment.Left,
            TextYAlignment          = Enum.TextYAlignment.Center,
            TextWrapped            = true,
            Position               = UDim2.fromOffset(12, 2),
            Size                   = UDim2.new(1, -18, 1, -4),
            ZIndex                 = 12,
        }
        Fonted(label, false)

        local item = { Frame = card, Dismissed = false }
        table.insert(queue.Items, 1, item)
        Layout()

        tweenService:Create(
            card,
            TweenInfo.new(0.28, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out),
            { GroupTransparency = 0 }
        ):Play()

        if #queue.Items > maximum then
            Dismiss(queue.Items[#queue.Items])
        end

        task.delay(lifetime, function()
            Dismiss(item)
        end)
    end

    function queue:Show(message, kind)
        queue:Push(message, kind)
    end

    function queue:Clear()
        for _, item in ipairs(queue.Items) do
            if item.Frame then
                item.Frame:Destroy()
            end
        end

        table.clear(queue.Items)
    end

    function queue:Destroy()
        queue:Clear()

        if queue.Gui then
            queue.Gui:Destroy()
            queue.Gui = nil
            queue.Container = nil
        end
    end

    return queue
end

-- A compact command menu: title, optional preview area, and a list of actions. Open it with a
-- position in screen space; entries are ordinary { Label, Callback, Danger } tables.
function MonoUI:CreateContextMenu(settings)
    settings = settings or {}
    local width         = settings.Width or 226
    local headerHeight  = settings.HeaderHeight or 56
    local previewHeight = settings.PreviewHeight or 112
    local previewGap    = settings.PreviewGap or 8
    local rowHeight     = settings.RowHeight or 27
    local sidePadding   = settings.SidePadding or 8
    local bottomPadding = settings.BottomPadding or 10
    local background    = settings.Background or Theme.Surface
    local mutedColor    = settings.Muted or Theme.Muted
    local dangerColor   = settings.Danger or Color3.fromRGB(255, 95, 95)

    local menu = {
        Gui    = nil,
        Frame  = nil,
        Open   = false,
        Bounds = nil,
    }

    local function EnsureGui()
        if menu.Gui and menu.Gui.Parent then
            return
        end

        menu.Gui = Element {
            ClassName      = "ScreenGui",
            Parent         = UiContainer(),
            Name           = settings.GuiName or "MonoUIContextMenu",
            ResetOnSpawn   = false,
            IgnoreGuiInset = true,
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
            DisplayOrder   = settings.DisplayOrder or 2147483003,
        }
    end

    function menu:Close()
        if menu.Frame then
            menu.Frame:Destroy()
            menu.Frame = nil
        end

        menu.Open = false
        menu.Bounds = nil

        if settings.OnClose then
            pcall(settings.OnClose)
        end
    end

    function menu:IsOpen()
        return menu.Open
    end

    function menu:OpenAt(options)
        options = options or {}
        menu:Close()
        EnsureGui()

        local entries = options.Entries or {}
        local hasPreview = options.Preview ~= nil
        local height = headerHeight
            + (hasPreview and (previewHeight + previewGap) or 0)
            + #entries * rowHeight
            + bottomPadding
        local screen = Viewport()
        local position = options.Position or UserInput:GetMouseLocation()
        local x = math.clamp(math.floor(position.X), 8, math.max(8, screen.X - width - 8))
        local y = math.clamp(math.floor(position.Y), 8, math.max(8, screen.Y - height - 8))

        local frame = Element {
            ClassName              = "Frame",
            Parent                 = menu.Gui,
            Name                   = "MonoUIContextMenuFrame",
            BackgroundColor3       = background,
            BackgroundTransparency = 0.04,
            BorderSizePixel        = 0,
            Position               = UDim2.fromOffset(x, y),
            Size                   = UDim2.fromOffset(width, height),
            ZIndex                 = 50,
        }
        Element { ClassName = "UICorner", Parent = frame, CornerRadius = UDim.new(0, Theme.RowRadius) }
        Element { ClassName = "UIStroke", Parent = frame, Color = Theme.Line, Transparency = 0.55, Thickness = 1 }

        local title = Texted(frame, {
            Text     = options.Title or "ACTIONS",
            Size     = Theme.Type.Label,
            Bold     = true,
            Position = UDim2.fromOffset(12, 8),
            Size2    = UDim2.new(1, -44, 0, 16),
            ZIndex   = 51,
        })
        title.TextTruncate = Enum.TextTruncate.AtEnd

        Texted(frame, {
            Text     = options.Subtitle or "",
            Tint     = "Muted",
            Size     = Theme.Type.Support,
            Bold     = false,
            Position = UDim2.fromOffset(12, 25),
            Size2    = UDim2.new(1, -24, 0, 11),
            ZIndex   = 51,
        })

        local close = Element {
            ClassName       = "TextButton",
            Parent          = frame,
            Name            = "Close",
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Font            = Enum.Font.GothamBold,
            Text            = "X",
            TextColor3      = mutedColor,
            TextSize        = 12,
            Position        = UDim2.new(1, -28, 0, 5),
            Size            = UDim2.fromOffset(22, 20),
            ZIndex          = 52,
        }
        close.MouseButton1Click:Connect(function()
            menu:Close()
        end)

        Element {
            ClassName       = "Frame",
            Parent          = frame,
            BackgroundColor3 = Theme.Line,
            BackgroundTransparency = 0.5,
            BorderSizePixel = 0,
            Position        = UDim2.fromOffset(8, 42),
            Size            = UDim2.new(1, -16, 0, 1),
            ZIndex          = 51,
        }

        local cursorY = headerHeight

        if hasPreview then
            local preview = Element {
                ClassName       = "Frame",
                Parent          = frame,
                Name            = "Preview",
                BackgroundColor3 = Theme.Well,
                BackgroundTransparency = 0.15,
                BorderSizePixel = 0,
                Position        = UDim2.fromOffset(8, cursorY - 4),
                Size            = UDim2.new(1, -16, 0, previewHeight),
                ZIndex          = 51,
            }
            Element { ClassName = "UICorner", Parent = preview, CornerRadius = UDim.new(0, 5) }
            options.Preview(preview, width - 16, previewHeight)
            cursorY += previewHeight + previewGap
        end

        for _, entry in ipairs(entries) do
            local row = Element {
                ClassName       = "TextButton",
                Parent          = frame,
                Name            = "Action",
                BackgroundColor3 = Theme.Well,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                AutoButtonColor = false,
                Text            = "",
                Position        = UDim2.fromOffset(sidePadding, cursorY),
                Size            = UDim2.new(1, -sidePadding * 2, 0, rowHeight - 2),
                ZIndex          = 51,
            }
            local label = Texted(row, {
                Text     = entry.Label or "",
                Size     = Theme.Type.Body,
                Tint     = entry.Danger and "Danger" or "Text",
                Bold     = false,
                Position = UDim2.fromOffset(4, 0),
                Size2    = UDim2.new(1, -8, 1, 0),
                ZIndex   = 52,
            })
            if entry.Danger then
                label.TextColor3 = dangerColor
            end

            row.MouseEnter:Connect(function()
                row.BackgroundTransparency = 0.82
            end)
            row.MouseLeave:Connect(function()
                row.BackgroundTransparency = 1
            end)
            row.MouseButton1Click:Connect(function()
                local callback = entry.Callback
                menu:Close()
                if callback then
                    task.spawn(callback)
                end
            end)

            cursorY += rowHeight
        end

        local absolute = frame.AbsolutePosition
        menu.Frame = frame
        menu.Open = true
        menu.Bounds = {
            Min = Vector2.new(absolute.X, absolute.Y),
            Max = Vector2.new(absolute.X + width, absolute.Y + height),
        }
    end

    function menu:GetBounds()
        return menu.Bounds
    end

    function menu:Destroy()
        menu:Close()

        if menu.Gui then
            menu.Gui:Destroy()
            menu.Gui = nil
        end
    end

    return menu
end

-- A data-driven roster for any game: the caller supplies rows and two callbacks, and this owns
-- search, case sensitivity, sort, grid/list mode, avatar cells, collapse, and friend/enemy marks.
-- Row shape: { Id, Name, DisplayName, UserId, Rank, Distance, Speed, Gps, State, StateColor, Relation }
function MonoUI:CreatePlayerList(settings)
    settings = settings or {}
    local width      = settings.Width or 680
    local rowHeight  = settings.RowHeight or 30
    local gridWidth  = settings.GridCellWidth or 206
    local gridHeight = settings.GridCellHeight or 62
    local muted      = settings.Muted or Theme.Muted
    local relationColors = settings.RelationColors or {
        Friend = Color3.fromRGB(80, 235, 140),
        Enemy  = Color3.fromRGB(255, 105, 105),
    }

    local list = {
        Gui       = nil,
        Frame     = nil,
        Body      = nil,
        Layout    = nil,
        Toolbar   = nil,
        SearchRow = nil,
        SearchBox = nil,
        CaseButton = nil,
        CollapseButton = nil,
        ViewButton = nil,
        SortButton = nil,
        SpeedButton = nil,
        RankButton = nil,
        DistanceButton = nil,
        Rows      = {},
        Visible   = true,
        Collapsed = false,
        Grid      = false,
        Sort      = "Name",
        Ascending = true,
        CaseSensitive = false,
        SearchText = "",
        ShowSpeed = true,
        ShowRank = true,
        ShowDistance = true,
        RowMode = nil,
    }

    local function Label(parent, name, text, size, color, position, size2, zIndex)
        local label = Element {
            ClassName              = "TextLabel",
            Parent                 = parent,
            Name                   = name,
            BackgroundTransparency = 1,
            BorderSizePixel        = 0,
            Font                   = Enum.Font.Gotham,
            TextSize               = size,
            TextColor3             = color or Theme.Text,
            TextXAlignment         = Enum.TextXAlignment.Left,
            TextYAlignment         = Enum.TextYAlignment.Center,
            Text                   = text or "",
            Position               = position,
            Size                   = size2,
            ZIndex                 = zIndex or 12,
        }
        return label
    end

    local function Button(parent, name, text, position, size, callback)
        local button = Element {
            ClassName              = "TextButton",
            Parent                 = parent,
            Name                   = name,
            BackgroundColor3       = Theme.Row,
            BackgroundTransparency = Theme.RowAlpha,
            BorderSizePixel        = 0,
            AutoButtonColor        = false,
            Font                   = Enum.Font.GothamBold,
            TextSize               = Theme.Type.Support,
            TextColor3             = Theme.Text,
            Text                   = text,
            Position               = position,
            Size                   = size,
            ZIndex                 = 13,
        }
        Sticker(button, {
            Color = "Row",
            Alpha = Theme.RowAlpha,
            Corner = "RowRadius",
            Stroke = "Line",
            Glass = true,
        })
        if callback then
            button.MouseButton1Click:Connect(callback)
        end
        return button
    end

    local function UpdateLayout()
        if not list.Frame then
            return
        end

        list.Frame.Size = UDim2.fromOffset(width, list.Collapsed and 38 or 440)
        list.SearchRow.Visible = not list.Collapsed
        list.Body.Visible = not list.Collapsed
        list.Body.Size = UDim2.new(1, -8, 0, list.Collapsed and 0 or 370)
        list.CollapseButton.Text = list.Collapsed and "›" or "⌄"
        list.ViewButton.Text = list.Grid and "GRID" or "LIST"
        list.SortButton.Text = string.format("SORT %s %s", string.upper(list.Sort), list.Ascending and "↑" or "↓")
        local function StyleToggle(button, active)
            button.BackgroundColor3 = active and Theme.Text or Theme.Row
            button.BackgroundTransparency = active and Theme.SwitchOnAlpha or Theme.RowAlpha
            button.TextColor3 = active and Theme.Invert or Theme.Text
        end
        StyleToggle(list.SpeedButton, list.ShowSpeed)
        StyleToggle(list.RankButton, list.ShowRank)
        StyleToggle(list.DistanceButton, list.ShowDistance)
        list.CaseButton.Text = list.CaseSensitive and "CASE: ON" or "CASE: OFF"
        list.CaseButton.TextColor3 = list.CaseSensitive and Theme.Text or muted

        local mode = list.Grid and "Grid" or "List"
        if list.RowMode ~= mode then
            list.RowMode = mode

            for _, row in pairs(list.Rows) do
                row.Frame:Destroy()
            end
            list.Rows = {}

            if list.Layout then
                list.Layout:Destroy()
            end

            if list.Grid then
                list.Layout = Element {
                    ClassName     = "UIGridLayout",
                    Parent        = list.Body,
                    CellSize      = UDim2.fromOffset(gridWidth, gridHeight),
                    CellPadding   = UDim2.fromOffset(4, 4),
                    SortOrder     = Enum.SortOrder.LayoutOrder,
                }
            else
                list.Layout = Element {
                    ClassName = "UIListLayout",
                    Parent    = list.Body,
                    Padding   = UDim.new(0, 2),
                    SortOrder = Enum.SortOrder.LayoutOrder,
                }
            end
        end
    end

    local function CreateRow(rowData)
        local frame = Element {
            ClassName              = "TextButton",
            Parent                 = list.Body,
            Name                   = "Player_" .. tostring(rowData.Id or rowData.Name or "Row"),
            BackgroundColor3       = Theme.Row,
            BackgroundTransparency = Theme.RowAlpha,
            BorderSizePixel        = 0,
            AutoButtonColor        = false,
            Text                   = "",
            ZIndex                 = 11,
        }
        Sticker(frame, {
            Color = "Row",
            Alpha = 0.94,
            Corner = "RowRadius",
            Stroke = "Line",
            Glass = true,
        })

        local avatar = Element {
            ClassName              = "ImageLabel",
            Parent                 = frame,
            Name                   = "Avatar",
            BackgroundTransparency = 1,
            BorderSizePixel        = 0,
            Image                  = rowData.UserId
                and string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", rowData.UserId)
                or "",
            Visible                = false,
            ZIndex                 = 12,
        }
        Element { ClassName = "UICorner", Parent = avatar, CornerRadius = UDim.new(0, 4) }

        local name = Label(frame, "Name", rowData.Name or "", 11, Theme.Text, UDim2.fromOffset(8, 0), UDim2.fromOffset(150, rowHeight), 12)
        name.Font = Enum.Font.GothamBold
        local rank = Label(frame, "Rank", rowData.Rank or "", 10, muted, UDim2.fromOffset(165, 0), UDim2.fromOffset(70, rowHeight), 12)
        local distance = Label(frame, "Distance", "", 10, muted, UDim2.fromOffset(240, 0), UDim2.fromOffset(75, rowHeight), 12)
        local speed = Label(frame, "Speed", "", 10, muted, UDim2.fromOffset(320, 0), UDim2.fromOffset(70, rowHeight), 12)
        local gps = Label(frame, "GPS", "GPS", 9, muted, UDim2.fromOffset(396, 0), UDim2.fromOffset(44, rowHeight), 12)
        gps.Font = Enum.Font.GothamBold
        gps.TextXAlignment = Enum.TextXAlignment.Center
        local state = Label(frame, "State", "", 9, muted, UDim2.fromOffset(444, 0), UDim2.fromOffset(150, rowHeight), 12)
        state.Font = Enum.Font.GothamBold
        state.TextXAlignment = Enum.TextXAlignment.Center
        local friend = Button(frame, "Friend", "F", UDim2.new(1, -46, 0, 5), UDim2.fromOffset(18, 20), function()
            if settings.OnRelation then
                settings.OnRelation(rowData.Id, "Friend")
            end
            list:Refresh()
        end)
        local enemy = Button(frame, "Enemy", "E", UDim2.new(1, -24, 0, 5), UDim2.fromOffset(18, 20), function()
            if settings.OnRelation then
                settings.OnRelation(rowData.Id, "Enemy")
            end
            list:Refresh()
        end)

        frame.MouseButton1Click:Connect(function()
            if settings.OnSelect then
                settings.OnSelect(rowData.Id)
            end
        end)

        local data = {
            Frame = frame, Avatar = avatar, Name = name, Rank = rank,
            Distance = distance, Speed = speed, GPS = gps, State = state,
            Friend = friend, Enemy = enemy,
        }
        list.Rows[rowData.Id] = data
        return data
    end

    local function ApplyRowLayout(row)
        if list.Grid then
            row.Avatar.Visible = true
            row.Avatar.Position = UDim2.fromOffset(6, 13)
            row.Avatar.Size = UDim2.fromOffset(36, 36)
            row.Name.Position = UDim2.fromOffset(50, 2)
            row.Name.Size = UDim2.fromOffset(100, 16)
            row.Rank.Position = UDim2.fromOffset(50, 20)
            row.Rank.Size = UDim2.fromOffset(44, 14)
            row.Distance.Position = UDim2.fromOffset(96, 20)
            row.Distance.Size = UDim2.fromOffset(44, 14)
            row.Speed.Position = UDim2.fromOffset(142, 20)
            row.Speed.Size = UDim2.fromOffset(40, 14)
            row.GPS.Position = UDim2.fromOffset(6, 1)
            row.GPS.Size = UDim2.fromOffset(38, 12)
            row.State.Position = UDim2.fromOffset(50, 42)
            row.State.Size = UDim2.fromOffset(100, 12)
            row.Friend.Position = UDim2.new(1, -46, 0, 6)
            row.Enemy.Position = UDim2.new(1, -24, 0, 6)
            row.Frame.Size = UDim2.fromOffset(gridWidth, gridHeight)
        else
            row.Avatar.Visible = false
            row.Name.Position = UDim2.fromOffset(8, 0)
            row.Name.Size = UDim2.fromOffset(150, rowHeight)
            row.Rank.Position = UDim2.fromOffset(165, 0)
            row.Rank.Size = UDim2.fromOffset(70, rowHeight)
            row.Distance.Position = UDim2.fromOffset(240, 0)
            row.Distance.Size = UDim2.fromOffset(75, rowHeight)
            row.Speed.Position = UDim2.fromOffset(320, 0)
            row.Speed.Size = UDim2.fromOffset(70, rowHeight)
            row.GPS.Position = UDim2.fromOffset(396, 0)
            row.GPS.Size = UDim2.fromOffset(44, rowHeight)
            row.State.Position = UDim2.fromOffset(444, 0)
            row.State.Size = UDim2.fromOffset(150, rowHeight)
            row.Friend.Position = UDim2.new(1, -46, 0, 5)
            row.Enemy.Position = UDim2.new(1, -24, 0, 5)
            row.Frame.Size = UDim2.new(1, -4, 0, rowHeight)
        end
    end

    local function SortKey(row)
        if list.Sort == "Distance" then
            return type(row.Distance) == "number" and row.Distance == row.Distance and row.Distance or math.huge
        end
        if list.Sort == "Rank" then
            local ranks = { Owner = 1, Admin = 2, Unranked = 3 }
            return ranks[row.Rank] or 4
        end
        return string.lower(row.Name or "")
    end

    function list:Refresh()
        UpdateLayout()
        if not list.Frame then
            return
        end

        local rows = settings.GetRows and settings.GetRows() or {}
        local ids = {}

        for _, row in ipairs(rows) do
            ids[row.Id] = true
        end

        for id, row in pairs(list.Rows) do
            if not ids[id] then
                row.Frame:Destroy()
                list.Rows[id] = nil
            end
        end

        local query = list.SearchText or ""
        local lowerQuery = string.lower(query)
        local filtered = {}

        for _, row in ipairs(rows) do
            local haystack = tostring(row.Name or "") .. " " .. tostring(row.DisplayName or "")
            local matched = query == ""
                or (list.CaseSensitive and string.find(haystack, query, 1, true) ~= nil)
                or (not list.CaseSensitive and string.find(string.lower(haystack), lowerQuery, 1, true) ~= nil)

            if matched then
                filtered[#filtered + 1] = row
            end
        end

        table.sort(filtered, function(left, right)
            local leftKey, rightKey = SortKey(left), SortKey(right)

            if type(leftKey) ~= type(rightKey) then
                return tostring(leftKey) < tostring(rightKey)
            end

            if leftKey == rightKey then
                return tostring(left.Name or "") < tostring(right.Name or "")
            end

            if list.Ascending then
                return leftKey < rightKey
            end

            return leftKey > rightKey
        end)

        for _, row in pairs(list.Rows) do
            row.Frame.Visible = false
        end

        for index, rowData in ipairs(filtered) do
            local row = list.Rows[rowData.Id] or CreateRow(rowData)
            ApplyRowLayout(row)
            local relation = rowData.Relation
            row.Frame.Visible = true
            row.Frame.LayoutOrder = index
            row.Name.Text = tostring(rowData.Name or "")
            row.Name.TextColor3 = Theme.Text
            row.Rank.Text = tostring(rowData.Rank or "Unranked")
            row.Rank.Visible = list.ShowRank
            row.Distance.Text = type(rowData.Distance) == "number"
                and string.format("%.0f%s", rowData.Distance, rowData.Gps and " GPS" or "")
                or "N/A"
            row.Distance.Visible = list.ShowDistance
            row.Speed.Text = type(rowData.Speed) == "number" and string.format("%.0f mph", rowData.Speed) or "N/A"
            row.Speed.Visible = list.ShowSpeed
            row.GPS.TextColor3 = rowData.Gps and Theme.Text or muted
            row.State.Text = tostring(rowData.State or "Unknown")
            row.State.TextColor3 = rowData.State == "Unknown" and muted or Theme.Text
            local function StyleRelation(button, active)
                button.BackgroundColor3 = active and Theme.Text or Theme.Row
                button.BackgroundTransparency = active and Theme.SwitchOnAlpha or Theme.RowAlpha
                button.TextColor3 = active and Theme.Invert or Theme.Text
            end
            StyleRelation(row.Friend, relation == "Friend")
            StyleRelation(row.Enemy, relation == "Enemy")
        end
    end

    local function Build()
        local gui = Element {
            ClassName      = "ScreenGui",
            Parent         = UiContainer(),
            Name           = settings.GuiName or "MonoUIPlayerList",
            ResetOnSpawn   = false,
            IgnoreGuiInset = true,
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
            DisplayOrder   = settings.DisplayOrder or 2147483001,
        }
        list.Gui = gui

        local frame = Element {
            ClassName              = "Frame",
            Parent                 = gui,
            Name                   = "PlayerListFrame",
            BackgroundColor3       = Theme.Surface,
            BackgroundTransparency = Theme.WindowTransparency,
            BorderSizePixel        = 0,
            AnchorPoint            = Vector2.new(1, 0),
            Position               = settings.Position or UDim2.new(1, -20, 0, 20),
            Size                   = UDim2.fromOffset(width, 440),
            ZIndex                 = 5,
        }
        Sticker(frame, {
            Color = "Surface",
            Alpha = Theme.WindowTransparency,
            Corner = "Radius",
            Stroke = "Outline",
            Rim = true,
            Glass = true,
        })
        list.Frame = frame

        local toolbar = Element {
            ClassName = "Frame", Parent = frame, Name = "Toolbar",
            BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), ZIndex = 6,
        }
        list.Toolbar = toolbar
        list.CollapseButton = Button(toolbar, "Collapse", "⌄", UDim2.fromOffset(4, 3), UDim2.fromOffset(22, 24), function()
            list.Collapsed = not list.Collapsed
            UpdateLayout()
        end)
        Label(toolbar, "Title", settings.Title or "PLAYERS", 12, Theme.Text, UDim2.fromOffset(32, 3), UDim2.fromOffset(72, 24), 7).Font = Enum.Font.GothamBold
        list.ViewButton = Button(toolbar, "View", "LIST", UDim2.fromOffset(106, 3), UDim2.fromOffset(54, 24), function()
            list.Grid = not list.Grid
            UpdateLayout()
            list:Refresh()
        end)
        list.SortButton = Button(toolbar, "Sort", "SORT NAME ↑", UDim2.fromOffset(164, 3), UDim2.fromOffset(118, 24), function()
            if list.Sort == "Name" then list.Sort = "Distance"
            elseif list.Sort == "Distance" then list.Sort = "Rank"
            else list.Sort = "Name" end
            list.Ascending = true
            UpdateLayout()
            list:Refresh()
        end)
        list.SpeedButton = Button(toolbar, "Speed", "SPD", UDim2.fromOffset(286, 3), UDim2.fromOffset(50, 24), function()
            list.ShowSpeed = not list.ShowSpeed
            UpdateLayout()
            list:Refresh()
        end)
        list.RankButton = Button(toolbar, "Rank", "RANK", UDim2.fromOffset(340, 3), UDim2.fromOffset(50, 24), function()
            list.ShowRank = not list.ShowRank
            UpdateLayout()
            list:Refresh()
        end)
        list.DistanceButton = Button(toolbar, "Distance", "DIST", UDim2.fromOffset(394, 3), UDim2.fromOffset(52, 24), function()
            list.ShowDistance = not list.ShowDistance
            UpdateLayout()
            list:Refresh()
        end)

        local searchRow = Element { ClassName = "Frame", Parent = frame, Name = "SearchRow", BackgroundTransparency = 1, Position = UDim2.fromOffset(4, 32), Size = UDim2.new(1, -8, 0, 26), ZIndex = 6 }
        list.SearchRow = searchRow
        local search = Element {
            ClassName = "TextBox", Parent = searchRow, Name = "Search",
            BackgroundColor3 = Theme.Well, BackgroundTransparency = Theme.WellAlpha, BorderSizePixel = 0,
            Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = Theme.Text,
            PlaceholderText = "Search players...", PlaceholderColor3 = muted,
            Text = "", ClearTextOnFocus = false, Size = UDim2.new(1, -92, 0, 26), ZIndex = 7,
        }
        Sticker(search, {
            Color = "Well",
            Alpha = Theme.WellAlpha,
            Corner = "RowRadius",
            Stroke = "Line",
        })
        search:GetPropertyChangedSignal("Text"):Connect(function()
            list.SearchText = search.Text
            list:Refresh()
        end)
        list.CaseButton = Button(searchRow, "Case", "CASE: OFF", UDim2.new(1, -88, 0, 0), UDim2.fromOffset(88, 26), function()
            list.CaseSensitive = not list.CaseSensitive
            UpdateLayout()
            list:Refresh()
        end)

        local body = Element {
            ClassName = "ScrollingFrame", Parent = frame, Name = "Players",
            BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(4, 62),
            Size = UDim2.new(1, -8, 0, 370), ScrollBarThickness = 4,
            CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 6,
        }
        list.Body = body
        UpdateLayout()
    end

    function list:SetVisible(visible)
        list.Visible = visible and true or false
        if list.Frame then
            list.Frame.Visible = list.Visible
        end
        return list.Visible
    end

    function list:IsVisible()
        return list.Visible
    end

    function list:Destroy()
        if list.Gui then
            list.Gui:Destroy()
            list.Gui = nil
        end
        list.Frame = nil
        list.Body = nil
        table.clear(list.Rows)
    end

    Build()
    list:Refresh()
    return list
end

-- A centered, draggable profile card with two preview viewports, a text panel, per-section action
-- buttons, friend/enemy state and a coordinate prompt. The caller supplies the profile through
-- GetProfile(Id); preview builders receive a blank ViewportFrame and may attach their own camera.
function MonoUI:CreatePlayerInfo(settings)
    settings = settings or {}
    local width      = settings.Width or 660
    local height     = settings.Height or 420
    local muted      = settings.Muted or Theme.Muted
    local info = {
        Gui = nil,
        Frame = nil,
        IsOpen = false,
        Target = nil,
        PreviewKey = nil,
        ActionKey = nil,
        ActionButtons = {},
        VehicleActionButtons = {},
        PlayerPanel = nil,
        VehiclePanel = nil,
        VehicleEmpty = nil,
        InfoText = nil,
        Title = nil,
        RelationButtons = {},
        TeleportDialog = nil,
        TeleportInput = nil,
        TeleportError = nil,
        DragConnection = nil,
        Dragging = false,
        DragOffset = Vector2.zero,
    }

    local function Label(parent, name, text, size, color, position, size2, zIndex)
        return Element {
            ClassName              = "TextLabel",
            Parent                 = parent,
            Name                   = name,
            BackgroundTransparency = 1,
            BorderSizePixel        = 0,
            Font                   = Enum.Font.Gotham,
            TextSize               = size,
            TextColor3             = color or Theme.Text,
            TextXAlignment         = Enum.TextXAlignment.Left,
            TextYAlignment         = Enum.TextYAlignment.Top,
            TextWrapped            = true,
            Text                   = text or "",
            Position               = position,
            Size                   = size2,
            ZIndex                 = zIndex or 12,
        }
    end

    local function Button(parent, name, text, position, size, callback)
        local button = Element {
            ClassName              = "TextButton",
            Parent                 = parent,
            Name                   = name,
            BackgroundColor3       = Theme.Row,
            BackgroundTransparency = Theme.RowAlpha,
            BorderSizePixel        = 0,
            AutoButtonColor        = false,
            Font                   = Enum.Font.GothamBold,
            TextSize               = Theme.Type.Support,
            TextColor3             = Theme.Text,
            Text                   = text,
            Position               = position,
            Size                   = size,
            ZIndex                 = 13,
        }
        Sticker(button, {
            Color = "Row",
            Alpha = Theme.RowAlpha,
            Corner = "RowRadius",
            Stroke = "Line",
            Glass = true,
        })
        if callback then
            button.MouseButton1Click:Connect(callback)
        end
        return button
    end

    local function ClearViewport(viewport)
        if not viewport then
            return
        end

        viewport.CurrentCamera = nil

        for _, child in ipairs(viewport:GetChildren()) do
            child:Destroy()
        end
    end

    local function BuildPreviewPanel(parent, name, position, size)
        local panel = Element {
            ClassName              = "Frame",
            Parent                 = parent,
            Name                   = name,
            BackgroundColor3       = Theme.Well,
            BackgroundTransparency = Theme.WellAlpha,
            BorderSizePixel        = 0,
            Position               = position,
            Size                   = size,
            ZIndex                 = 11,
        }
        Sticker(panel, {
            Color = "Well",
            Alpha = Theme.WellAlpha,
            Corner = "RowRadius",
            Stroke = "Line",
            Glass = true,
        })

        local viewport = Element {
            ClassName              = "ViewportFrame",
            Parent                 = panel,
            Name                   = name .. "Viewport",
            BackgroundTransparency = 1,
            Ambient                = Color3.fromRGB(180, 180, 180),
            LightColor             = Color3.fromRGB(255, 255, 255),
            LightDirection         = Vector3.new(-0.4, -0.8, -0.5),
            Position               = UDim2.fromOffset(1, 1),
            Size                   = UDim2.new(1, -2, 1, -2),
            ZIndex                 = 12,
        }
        return panel, viewport
    end

    local function BuildActions(actions, startX, startY, cellWidth)
        for _, button in ipairs(info.ActionButtons) do
            button:Destroy()
        end
        table.clear(info.ActionButtons)

        for index, action in ipairs(actions or {}) do
            local column = (index - 1) % 2
            local row = math.floor((index - 1) / 2)
            local button = Button(
                info.Frame,
                "Action" .. index,
                action.Text or action.Label or "ACTION",
                UDim2.fromOffset(startX + column * (cellWidth + 5), startY + row * 24),
                UDim2.fromOffset(cellWidth, 21),
                action.Callback
            )

            table.insert(info.ActionButtons, button)
        end
    end

    local function ActionSignature(actions)
        local parts = {}
        for _, action in ipairs(actions or {}) do
            parts[#parts + 1] = tostring(action.Text or action.Label or "") .. (action.Danger and "!" or "")
        end
        return table.concat(parts, "|")
    end

    local function Ensure()
        if info.Frame and info.Frame.Parent then
            return
        end

        local gui = Element {
            ClassName      = "ScreenGui",
            Parent         = UiContainer(),
            Name           = settings.GuiName or "MonoUIPlayerInfo",
            ResetOnSpawn   = false,
            IgnoreGuiInset = true,
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
            DisplayOrder   = settings.DisplayOrder or 2147483002,
        }
        info.Gui = gui

        local frame = Element {
            ClassName              = "Frame",
            Parent                 = gui,
            Name                   = "PlayerInfoFrame",
            BackgroundColor3       = Theme.Surface,
            BackgroundTransparency = Theme.WindowTransparency,
            BorderSizePixel        = 0,
            Size                   = UDim2.fromOffset(width, height),
            Visible                = false,
            ZIndex                 = 10,
        }
        Sticker(frame, {
            Color = "Surface",
            Alpha = Theme.WindowTransparency,
            Corner = "Radius",
            Stroke = "Outline",
            Rim = true,
            Glass = true,
        })
        info.Frame = frame

        local titleBar = Element {
            ClassName = "TextButton", Parent = frame, Name = "TitleBar",
            BackgroundTransparency = 1, AutoButtonColor = false, Text = "",
            Size = UDim2.new(1, 0, 0, 30), ZIndex = 11,
        }
        local title = Label(frame, "Title", "", 13, Theme.Text, UDim2.fromOffset(12, 6), UDim2.new(1, -48, 0, 18), 12)
        title.Font = Enum.Font.GothamBold
        info.Title = title
        Button(frame, "Close", "X", UDim2.new(1, -30, 0, 5), UDim2.fromOffset(22, 20), function()
            info:Close()
        end)

        local playerPanel, playerViewport = BuildPreviewPanel(frame, "PlayerPreview", UDim2.fromOffset(12, 40), UDim2.fromOffset(190, 224))
        local vehiclePanel, vehicleViewport = BuildPreviewPanel(frame, "VehiclePreview", UDim2.fromOffset(212, 40), UDim2.fromOffset(220, 150))
        info.PlayerPanel = playerPanel
        info.PlayerViewport = playerViewport
        info.VehiclePanel = vehiclePanel
        info.VehicleViewport = vehicleViewport

        info.VehicleEmpty = Label(vehiclePanel, "NoVehicle", "NO VEHICLE", 10, muted, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), 13)
        info.VehicleEmpty.TextXAlignment = Enum.TextXAlignment.Center
        info.InfoText = Label(frame, "Info", "", 10, Theme.Text, UDim2.fromOffset(442, 40), UDim2.fromOffset(206, 300), 12)

        info.RelationButtons = {
            Friend = Button(frame, "Friend", "FRIEND", UDim2.fromOffset(12, 366), UDim2.fromOffset(100, 24), function()
                if info.Target and settings.OnRelation then
                    settings.OnRelation(info.Target, "Friend")
                    info:Update()
                end
            end),
            Enemy = Button(frame, "Enemy", "ENEMY", UDim2.fromOffset(120, 366), UDim2.fromOffset(100, 24), function()
                if info.Target and settings.OnRelation then
                    settings.OnRelation(info.Target, "Enemy")
                    info:Update()
                end
            end),
        }

        local dialog = Element {
            ClassName = "Frame", Parent = frame, Name = "TeleportDialog",
            BackgroundColor3 = Theme.Surface, BackgroundTransparency = Theme.WindowTransparency, BorderSizePixel = 0,
            Position = UDim2.fromOffset(180, 140), Size = UDim2.fromOffset(300, 126),
            Visible = false, ZIndex = 50,
        }
        Sticker(dialog, {
            Color = "Surface",
            Alpha = Theme.WindowTransparency,
            Corner = "Radius",
            Stroke = "Outline",
            Rim = true,
            Glass = true,
        })
        Label(dialog, "Title", "TELEPORT TARGET", 11, Theme.Text, UDim2.fromOffset(12, 8), UDim2.fromOffset(276, 18), 51).Font = Enum.Font.GothamBold
        local input = Element {
            ClassName = "TextBox", Parent = dialog, Name = "Coordinates",
            BackgroundColor3 = Theme.Well, BackgroundTransparency = Theme.WellAlpha, BorderSizePixel = 0,
            Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = Theme.Text,
            PlaceholderText = "X, Y, Z", PlaceholderColor3 = muted, Text = "",
            ClearTextOnFocus = false, Position = UDim2.fromOffset(12, 30), Size = UDim2.fromOffset(276, 26), ZIndex = 52,
        }
        Sticker(input, {
            Color = "Well",
            Alpha = Theme.WellAlpha,
            Corner = "RowRadius",
            Stroke = "Line",
        })
        local errorLabel = Label(dialog, "Error", "", 9, settings.Danger or Color3.fromRGB(255, 95, 95), UDim2.fromOffset(12, 58), UDim2.fromOffset(276, 14), 51)
        errorLabel.TextYAlignment = Enum.TextYAlignment.Center
        info.TeleportDialog = dialog
        info.TeleportInput = input
        info.TeleportError = errorLabel

        input.FocusLost:Connect(function(enterPressed)
            if enterPressed then
                info:SubmitTeleport()
            end
        end)
        Button(dialog, "Go", "TELEPORT", UDim2.fromOffset(12, 78), UDim2.fromOffset(130, 24), function()
            info:SubmitTeleport()
        end)
        Button(dialog, "Cancel", "CANCEL", UDim2.fromOffset(158, 78), UDim2.fromOffset(130, 24), function()
            dialog.Visible = false
        end)

        titleBar.InputBegan:Connect(function(inputObject)
            if not info.IsOpen then
                return
            end

            if inputObject.UserInputType == Enum.UserInputType.MouseButton1
                or inputObject.UserInputType == Enum.UserInputType.Touch then
                local mouse = UserInput:GetMouseLocation()
                local position = frame.Position
                info.Dragging = true
                info.DragOffset = mouse - Vector2.new(position.X.Offset, position.Y.Offset)
            end
        end)
    end

    function info:SubmitTeleport()
        local x, y, z = string.match(self.TeleportInput.Text, "^%s*([^,%s]+)%s*[,%s]+([^,%s]+)%s*[,%s]+([^,%s]+)")
        local numberX, numberY, numberZ = tonumber(x), tonumber(y), tonumber(z)

        if not numberX or not numberY or not numberZ then
            self.TeleportError.Text = "Use X, Y, Z coordinates"
            return
        end

        self.TeleportDialog.Visible = false

        if self.Target and settings.OnTeleport then
            settings.OnTeleport(self.Target, numberX, numberY, numberZ)
        end
    end

    function info:PromptTeleport()
        if not self.TeleportDialog then
            return
        end

        local profile = self.Target and settings.GetProfile(self.Target) or nil
        if profile and profile.TeleportPosition then
            self.TeleportInput.Text = tostring(profile.TeleportPosition)
        else
            self.TeleportInput.Text = ""
        end

        self.TeleportError.Text = ""
        self.TeleportDialog.Visible = true
        self.TeleportInput:CaptureFocus()
    end

    function info:Open(id)
        Ensure()
        self.Target = id
        self.PreviewKey = nil
        self.ActionKey = nil
        local viewport = Viewport()
        local size = self.Frame.Size
        self.Frame.Position = UDim2.fromOffset(
            math.max(8, math.floor((viewport.X - size.X.Offset) * 0.5)),
            math.max(8, math.floor((viewport.Y - size.Y.Offset) * 0.5))
        )
        self.Frame.Visible = true
        self.IsOpen = true
        self:Update()
    end

    function info:Update()
        if not self.IsOpen or not self.Frame then
            return
        end

        local profile = self.Target and settings.GetProfile(self.Target) or nil
        if not profile then
            self:Close()
            return
        end

        self.Title.Text = profile.Title or ""
        self.InfoText.Text = profile.Text or ""
        local relation = profile.Relation or "Neutral"
        local function StyleRelationButton(button, active)
            button.BackgroundColor3 = active and Theme.Text or Theme.Row
            button.BackgroundTransparency = active and Theme.SwitchOnAlpha or Theme.RowAlpha
            button.TextColor3 = active and Theme.Invert or Theme.Text
        end
        StyleRelationButton(self.RelationButtons.Friend, relation == "Friend")
        StyleRelationButton(self.RelationButtons.Enemy, relation == "Enemy")

        local actionSignature = ActionSignature(profile.PlayerActions) .. "|" .. ActionSignature(profile.VehicleActions)
        if self.ActionKey ~= actionSignature then
            self.ActionKey = actionSignature
            BuildActions(profile.PlayerActions or {}, 12, 268, 90)
            local vehicleButtons = {}
            for index, action in ipairs(profile.VehicleActions or {}) do
                local column = (index - 1) % 2
                local row = math.floor((index - 1) / 2)
                local button = Button(
                    self.Frame, "VehicleAction" .. index, action.Text or "ACTION",
                    UDim2.fromOffset(212 + column * 115, 196 + row * 25), UDim2.fromOffset(109, 22), action.Callback
                )
                table.insert(vehicleButtons, button)
            end
            for _, old in ipairs(self.VehicleActionButtons or {}) do old:Destroy() end
            self.VehicleActionButtons = vehicleButtons
        end

        local previewKey = tostring(self.Target) .. ":" .. tostring(profile.PreviewKey or "")
        if self.PreviewKey ~= previewKey then
            self.PreviewKey = previewKey
            ClearViewport(self.PlayerViewport)
            ClearViewport(self.VehicleViewport)

            if profile.PlayerPreview then
                pcall(profile.PlayerPreview, self.PlayerViewport)
            end

            self.VehiclePanel.Visible = profile.VehiclePreview ~= nil
            self.VehicleEmpty.Visible = profile.VehiclePreview == nil

            if profile.VehiclePreview then
                pcall(profile.VehiclePreview, self.VehicleViewport)
            end
        end
    end

    function info:Close()
        if self.TeleportDialog then
            self.TeleportDialog.Visible = false
        end
        ClearViewport(self.PlayerViewport)
        ClearViewport(self.VehicleViewport)
        self.IsOpen = false
        self.Target = nil
        self.PreviewKey = nil
        self.ActionKey = nil
        if self.Frame then
            self.Frame.Visible = false
        end

        if settings.OnClose then
            pcall(settings.OnClose)
        end
    end

    function info:Destroy()
        self:Close()
        if self.DragConnection then
            self.DragConnection:Disconnect()
            self.DragConnection = nil
        end
        if self.Gui then
            self.Gui:Destroy()
            self.Gui = nil
        end
        self.Frame = nil
    end

    Ensure()
    info.DragConnection = UserInput.InputChanged:Connect(function(inputObject)
        if not info.IsOpen or not info.Dragging or not info.Frame then
            return
        end

        if inputObject.UserInputType ~= Enum.UserInputType.MouseMovement
            and inputObject.UserInputType ~= Enum.UserInputType.Touch then
            return
        end

        local mouse = UserInput:GetMouseLocation()
        info.Frame.Position = UDim2.fromOffset(
            math.floor(mouse.X - info.DragOffset.X),
            math.floor(mouse.Y - info.DragOffset.Y)
        )
    end)
    UserInput.InputEnded:Connect(function(inputObject)
        if inputObject.UserInputType == Enum.UserInputType.MouseButton1
            or inputObject.UserInputType == Enum.UserInputType.Touch then
            info.Dragging = false
        end
    end)

    return info
end

--=== export ================================================================

-- Everything a script needs to lay itself out the way Stretcher does.
MonoUI.Theme     = Theme
MonoUI.Metrics   = Metrics
MonoUI.Platform  = Platform
MonoUI.Motion    = Motion
MonoUI.Element   = Element
MonoUI.Sticker   = Sticker
MonoUI.Fonted    = Fonted
MonoUI.Texted    = Texted
MonoUI.Row       = Row
MonoUI.Columns   = Columns
MonoUI.Dragging  = Dragging
MonoUI.UiContainer = UiContainer
MonoUI.Switch    = Switch
MonoUI.Select    = Select
MonoUI.Input     = Input
MonoUI.Button    = Button
MonoUI.Heading   = Heading
MonoUI.CreateRegion = CreateRegion

-- A surface is any frame that wants the shared backdrop while it is on screen: the blur for the game
-- behind it, and the rain inside it. Windows and plates made here register themselves; these two are
-- for a window built by hand, such as Stretcher's, so it can have the same backdrop without adopting
-- the whole window object. The rain layer is built inside the frame given as RainParent, so it covers
-- that window rather than the whole screen.
function MonoUI:ShowSurface(frame, settings)
    if frame == nil then
        return nil
    end

    local wanted = settings or {}
    wanted.RainParent = wanted.RainParent or frame
    return RegisterSurface(frame, wanted)
end

function MonoUI:HideSurface(frame)
    if frame == nil then
        return nil
    end

    UnregisterSurface(frame)
    return frame
end

MonoUI.GlassVersion = "2026-10-25-glass-6"

return MonoUI
