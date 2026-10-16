-- Latest update: 10/16/2026 11:44 PM
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
]]

local Players     = game:GetService("Players")
local Lighting    = game:GetService("Lighting")
local UserInput   = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Workspace   = game:GetService("Workspace")
local RunService  = game:GetService("RunService")

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
    WindowAlpha  = 0.38,                                                             -- frosted plate, the blur shows through
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
    MorphScale   = 0.20,                                                             -- and the scale that makes it the size of its chip, when the plate cannot be measured
    MaxHeight    = 420,                                                              -- a body taller than this scrolls instead of running off the screen
    FadeEdge     = 14,                                                               -- how deep the bands at a scrolling body's edges fade
    Radius       = 16,                                                               -- window corner radius
    RowRadius    = 10,                                                               -- inner corner radius
    Space        = { Micro = 4, Gap = 8, Pad = 14, Section = 16, Block = 22 },        -- one spacing scale
    Type         = { Title = 15, Heading = 11, Label = 13, Body = 12, Support = 9 },  -- named sizes
    Width        = 720,                                                              -- default plate width
    Blur         = 16,                                                               -- backdrop blur, 0 for none
    VisibleRows  = 5,                                                                -- options shown before a dropdown scrolls
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
            Radius   = 220,                                                          -- pixels of space that bend: a cursor-sized well, not a pinprick
            Strength = 260,                                                          -- peak displacement, fold-free up to 3 * Radius
            Follow   = 14,                                                           -- how fast the well itself catches the cursor, in e-folds per second
        },
    },
}

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

    -- A class this client does not have - a group, on an older build - falls back to a plain frame
    -- rather than taking the whole window down with it: the control loses its extra, not its life.
    local class = properties.ClassName or "Frame"
    properties.ClassName = nil

    local built, instance = pcall(Instance.new, class)
    if not built then
        Report(string.format("no %s here · falling back to a frame", class))
        instance = Instance.new("Frame")
    end

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
        Name                   = properties.Name,                                    -- named where a control needs to be found again
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
        AnchorPoint            = properties.AnchorPoint,                              -- the chevron turns about its middle
        Rotation               = properties.Rotation,
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

-- The timing table. Micro-interactions decay, because any of them can be interrupted mid-flight,
-- and discrete moves carry a duration, because they have a beginning and an end. Exits are shorter
-- than their enters - they need less attention - and anything that moves together shares a channel.
Motion.Specs = {
    Hover    = { Kind = "Decay", Rate = 24 },                                        -- 95% in 125 ms
    Press    = { Kind = "Decay", Rate = 36 },                                        -- 95% in 83 ms
    Focus    = { Kind = "Decay", Rate = 20 },                                        -- 95% in 150 ms
    Drag     = { Kind = "Decay", Rate = 8 },                                         -- a released drag glides, and keeps gliding
    Follow   = { Kind = "Decay", Rate = 14 },                                        -- the rain lens, and anything else retargeted every frame
    Switch   = { Kind = "Cubic", Duration = 0.14, Ease = Easings.CubicOut },          -- the knob's short travel
    Tab      = { Kind = "Cubic", Duration = 0.20, Ease = Easings.CubicInOut },        -- tab content sliding and fading
    Panel    = { Kind = "Cubic", Duration = 0.18, Ease = Easings.CubicOut },          -- a dropdown opening
    Close    = { Kind = "Cubic", Duration = 0.12, Ease = Easings.CubicIn },           -- and closing, which is quicker
    Open     = { Kind = "Cubic", Duration = 0.24, Ease = Easings.CubicOut },          -- a window arriving, or a body unfolding
    Dismiss  = { Kind = "Cubic", Duration = 0.16, Ease = Easings.CubicIn },           -- a window leaving, or a toast going
    Toast    = { Kind = "Cubic", Duration = 0.26, Ease = Easings.CubicOut },
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
    end
    if existing == nil then
        Animator.count = Animator.count + 1                                          -- one track added; a replacement is one track for one track
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
    return Start(instance, property, target, { Kind = "Decay", Rate = rate or Motion.Specs.Follow.Rate })
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

--=== motion setting ========================================================

-- Reduced motion is a setting rather than a build decision: a script can turn it on for a player who
-- wants it, for one window, or for a while. It rules the driver only - movement is set outright and
-- feedback still decays, quickly - so state stays legible without anything sliding. A script that
-- wants the rain gone as well turns that off on its own terms, through Theme.Rain or
-- CreateWindow { Rain = false }, because weather is not a transition.
function MonoUI:SetMotion(enabled)
    Motion.Enabled = enabled ~= false
    return Motion.Enabled
end

function MonoUI:GetMotion()
    return Motion.Enabled
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

-- The four states of anything clickable, wired once: rest, hover, the press, and back to hover
-- when the press ends inside the control. Hover and press are transparency changes, never colour
-- changes - that is what keeps a glass surface reading as one material.
local function Hoverable(instance, looks)
    instance.MouseEnter:Connect(function()        Motion.Play(instance, "Hover", looks.Hover) end)
    instance.MouseLeave:Connect(function()        Motion.Play(instance, "Hover", looks.Rest)  end)
    instance.MouseButton1Down:Connect(function()  Motion.Play(instance, "Press", looks.Press) end)
    instance.MouseButton1Up:Connect(function()    Motion.Play(instance, "Press", looks.Hover) end)
end

local RowLooks = {
    Rest  = { BackgroundTransparency = Theme.RowAlpha   },
    Hover = { BackgroundTransparency = Theme.HoverAlpha },
    Press = { BackgroundTransparency = Theme.PressAlpha },
}

-- A plate grows the last few percent into place when it is shown, so it arrives rather than
-- appears, and it grows from wherever it was left - the chip's size, after it has been hidden - when
-- it comes back. The Scale is looked up by name: a plate built by hand without one is simply left
-- alone, which is what keeps this optional for anyone laying out their own surface.
local function Reveal(plate, from)
    local scale = plate:FindFirstChild("Scale")
    if scale == nil then return end
    scale.Scale = from or Theme.RevealScale
    Motion.Play(scale, "Open", { Scale = 1 })
end

-- A part that folds: a window's contents, a tab strip, a column of options. AutomaticSize cannot be
-- tweened, so the part gives up its automatic height for the duration of the move and takes whatever it
-- had back afterwards - a strip or a capped body is not automatic, and giving one an automatic height
-- would either size it from scale-sized children or spring a folded part straight back open. The
-- unfolded height is passed in rather than guessed, because a part whose height is measured is not a
-- part whose height is knowable from inside it.
local function Fold(part, collapsed, open)
    local from      = part.AbsoluteSize.Y
    local to        = collapsed and 0 or (open or from)
    local automatic = part.AutomaticSize

    part.AutomaticSize = Enum.AutomaticSize.None
    part.Size          = UDim2.new(1, 0, 0, from)

    if collapsed then
        Motion.Play(part, "Close", { Size = UDim2.new(1, 0, 0, to) })              -- flattening is an exit
        return
    end

    Motion.Play(part, "Open", { Size = UDim2.new(1, 0, 0, to) })                   -- unfolding is an arrival
    task.delay(Motion.Enabled ~= false and Motion.Specs.Open.Duration or 0, function()
        if part.Parent ~= nil then
            part.AutomaticSize = automatic
        end
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

-- How fast a plate has to be moving when it is let go before it carries on: under this, a release is
-- a placement and the plate stays exactly where it was put.
local DragGlideMin = 120                                                              -- pixels per second

-- Where a plate is allowed to be: enough of it stays on screen to be caught again. The drag ends
-- here, and so does the glide it is released with, so a thrown plate cannot leave the screen either.
local function ClampedPosition(base, target, x, y)
    local camera = Workspace.CurrentCamera
    local screen = camera and camera.ViewportSize or Vector2.new(1920, 1080)
    return UDim2.new(
        base.X.Scale, math.clamp(x, 8 - target.AbsoluteSize.X + 60, screen.X - 60),
        base.Y.Scale, math.clamp(y, 8, screen.Y - 40)
    )
end

-- Drag from any handle: a title bar, the plate itself, or a chip while a window is hidden.
-- Movement is measured as a mouse delta from where the plate already is, never against
-- AbsolutePosition - that one includes the GUI inset while Position does not, which is what
-- makes a naive drag jump on its first frame. A press only becomes a drag after the
-- threshold.
--
-- Letting go of a moving plate does not stop it dead: it keeps the velocity the pointer was giving
-- it and loses it at the Drag channel's rate. A decay aimed at a point that is velocity over rate
-- away moves at exactly that velocity now and sheds it exponentially, so the glide is the driver's
-- own Decay rather than a second kind of motion bolted beside it.
local function Dragging(owner, target, ...)
    local drag    = {
        active   = false,
        moved    = false,
        start    = Vector2.zero,
        base     = nil,
        last     = Vector2.zero,
        at       = 0,
        velocity = Vector2.zero,
    }
    local handles = { ... }

    local function Glide()
        local rate = Motion.Specs.Drag.Rate
        if not drag.moved or drag.velocity.Magnitude < DragGlideMin then
            return
        end

        local here = target.Position
        local aim  = ClampedPosition(here, target, here.X.Offset + drag.velocity.X / rate, here.Y.Offset + drag.velocity.Y / rate)
        Motion.Follow(target, "Position", aim, rate)

        -- Where it came to rest is worth keeping, but once per gesture and not once per frame.
        -- Saving is a no-op unless the window asked for it.
        MonoUI:SaveConfiguration()
    end

    for _, handle in ipairs(handles) do
        owner.connections[#owner.connections + 1] = handle.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                -- Taking hold of a gliding plate stops it: otherwise the pointer and the driver
                -- would both be writing its position.
                Motion.Cancel(target)

                drag.active   = true
                drag.moved    = false
                drag.start    = Vector2.new(input.Position.X, input.Position.Y)
                drag.last     = drag.start
                drag.base     = target.Position
                drag.at       = os.clock()
                drag.velocity = Vector2.zero

                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        drag.active = false
                        Glide()
                    end
                end)
            end
        end)
    end

    owner.connections[#owner.connections + 1] = UserInput.InputChanged:Connect(function(input)
        if not drag.active then
            return
        end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end

        local wanted = Vector2.new(input.Position.X, input.Position.Y)
        local stepX  = wanted.X - drag.start.X
        local stepY  = wanted.Y - drag.start.Y
        if not drag.moved then
            if math.sqrt(stepX * stepX + stepY * stepY) < owner.dragThreshold then
                return
            end
            drag.moved = true
        end

        -- How fast the plate is being moved, smoothed so one jittery sample cannot decide the throw,
        -- and measured over the whole gesture so pausing before letting go cancels it.
        local now     = os.clock()
        local elapsed = now - drag.at
        if elapsed > 0 then
            local fresh   = Vector2.new(wanted.X - drag.last.X, wanted.Y - drag.last.Y) / elapsed
            drag.velocity = drag.velocity:Lerp(fresh, 0.4)
            drag.at       = now
            drag.last     = wanted
        end

        target.Position = ClampedPosition(drag.base, target, drag.base.X.Offset + stepX, drag.base.Y.Offset + stepY)
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

--=== focus =================================================================

-- Keyboard focus lives in one place, because four controls need the same four things from it: a ring
-- that says where you are, a key that presses the control, a key that walks to the next one, and
-- Escape for the control that has something to take back. The order they register in is the order
-- Tab and the arrows walk them.
--
-- The ring is the stroke the control already has, brought up to Theme.FocusAlpha, which is what
-- keeps focus adding no new furniture. It fades on the Focus channel rather than Hover: a ring is
-- not a hover, and the plan gives it its own rate.
local Focus = { order = {}, current = nil, editing = nil, layer = nil, connection = nil }

local function RingOf(control)
    return control.Frame and control.Frame:FindFirstChild("Stroke") or nil
end

-- A control whose frame has gone - a window that was destroyed - is dropped as focus walks past it,
-- so a stale registration cannot trap Tab. One that is merely hidden is kept: a tab that comes back
-- should be reachable again without re-registering anything.
function Focus.Live()
    local live = {}
    for _, control in ipairs(Focus.order) do
        if control.Frame ~= nil and control.Frame.Parent ~= nil then
            live[#live + 1] = control
        end
    end
    if #live ~= #Focus.order then
        Focus.order = live
    end
    return live
end

-- Whether a control can actually be looked at. A control in a tab that is not showing is still
-- parented, so parenting alone is not enough: a ring that lands on one is a focus with nothing to
-- look at, which is worse than no focus at all.
local function OnScreen(control)
    local node = control.Frame
    while node ~= nil do
        if node.Visible == false then
            return false
        end
        node = node.Parent
    end
    return true
end

-- The controls focus may actually land on.
function Focus.Reachable()
    local reachable = {}
    for _, control in ipairs(Focus.Live()) do
        if OnScreen(control) then
            reachable[#reachable + 1] = control
        end
    end
    return reachable
end

function Focus.Set(control)
    local previous = Focus.current
    if previous == control then
        return control
    end
    Focus.current = control

    if previous ~= nil then
        local stroke = RingOf(previous)
        if stroke ~= nil then
            Motion.Play(stroke, "Focus", { Transparency = Theme.LineAlpha })
        end
    end
    if control ~= nil then
        local stroke = RingOf(control)
        if stroke ~= nil then
            Motion.Play(stroke, "Focus", { Transparency = Theme.FocusAlpha })
        end
    end
    return control
end

function Focus.Move(step)
    local order = Focus.Reachable()
    local count = #order
    if count == 0 then
        return nil
    end

    local index = nil
    for position, control in ipairs(order) do
        if control == Focus.current then
            index = position
            break
        end
    end

    if index == nil then
        index = step >= 0 and 1 or count
    else
        index = ((index - 1 + step) % count) + 1                                     -- wraps, so Tab never dead-ends
    end
    return Focus.Set(order[index])
end

-- A transient layer - an open dropdown - claims this one slot while it is up. Only one can hold it
-- at a time, which is what keeps a second menu from opening on top of the first, and it is what
-- Escape and a click outside the layer both take down.
function Focus.Claim(layer)
    if Focus.layer ~= nil and Focus.layer ~= layer then
        Focus.Dismiss()
    end
    Focus.layer = layer
end

function Focus.Dismiss()
    local layer = Focus.layer
    if layer == nil then
        return false
    end
    Focus.layer = nil
    if layer.Dismiss ~= nil then
        layer.Dismiss()
    end
    return true
end

function Focus.Activate()
    local control = Focus.current
    if control == nil or control.Activate == nil then
        return false
    end
    control.Activate()
    return true
end

-- Escape belongs, in order, to the layer that is up, to the field that is editing, and last to the
-- focus itself: the most local thing that can act on it takes it.
function Focus.Escape()
    if Focus.Dismiss() then
        return true
    end

    local editing = Focus.editing
    if editing ~= nil and editing.Revert ~= nil then
        editing.Revert()
        return true
    end
    if Focus.current ~= nil then
        Focus.Set(nil)
        return true
    end
    return false
end

function Focus.Clear(control)
    local index = table.find(Focus.order, control)
    if index ~= nil then
        table.remove(Focus.order, index)
    end
    if Focus.current == control then
        Focus.current = nil
    end
    if Focus.editing == control then
        Focus.editing = nil
    end
end

-- One connection for every focusable control in the app, made when the first of them registers and
-- dropped when the app goes. It carries four duties: a press outside the layer that is up takes it
-- down, keys keep the same guard the hide key uses - anything the game has already handled is left
-- alone - while a text box has the caret only Escape is ours, because everything else is typing, and
-- a bare letter goes to the layer that is up, which is how type-ahead reaches a menu.
function Focus.Register(control)
    Focus.order[#Focus.order + 1] = control

    if Focus.connection == nil then
        Focus.connection = UserInput.InputBegan:Connect(function(input, processed)
            -- A press outside the layer that is up takes it down whether or not the game handled it:
            -- a menu left open behind a click is worse than one that closes a moment early.
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                if Focus.layer ~= nil and not Focus.layer.Contains(input.Position) then
                    Focus.Dismiss()
                end
                return
            end

            if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then
                return
            end

            local typing  = UserInput.GetFocusedTextBox ~= nil and UserInput:GetFocusedTextBox() ~= nil
            local pressed = Focus.Keys[input.KeyCode]
            if pressed ~= nil then
                if typing and input.KeyCode ~= Enum.KeyCode.Escape then return end
                pressed()
                return
            end

            if not typing and Focus.layer ~= nil and Focus.layer.Type ~= nil then
                local name = tostring(input.KeyCode.Name)
                if #name == 1 then
                    Focus.layer.Type(string.lower(name))
                end
            end
        end)
    end
    return control
end

function Focus.Reset()
    if Focus.connection ~= nil then
        pcall(function()
            Focus.connection:Disconnect()
        end)
        Focus.connection = nil
    end
    Focus.order     = {}
    Focus.current   = nil
    Focus.editing   = nil
    Focus.layer     = nil
end

-- Whether a screen position falls inside a control. This is what "clicked outside the menu" is
-- measured against, and why the row and the list are both asked rather than the whole screen.
local function Inside(control, position)
    local origin = control.AbsolutePosition
    local size   = control.AbsoluteSize
    return position.X >= origin.X and position.X <= origin.X + size.X
        and position.Y >= origin.Y and position.Y <= origin.Y + size.Y
end

Focus.Keys = {
    [Enum.KeyCode.Tab]      = function() Focus.Move(1) end,
    [Enum.KeyCode.Down]     = function() Focus.Move(1) end,
    [Enum.KeyCode.Right]    = function() Focus.Move(1) end,
    [Enum.KeyCode.Up]       = function() Focus.Move(-1) end,
    [Enum.KeyCode.Left]     = function() Focus.Move(-1) end,
    [Enum.KeyCode.Return]   = function() Focus.Activate() end,
    [Enum.KeyCode.Space]    = function() Focus.Activate() end,
    [Enum.KeyCode.Escape]   = function() Focus.Escape() end,
}

--=== tooltip ===============================================================

-- One tooltip per gui - a description belongs to the surface it describes - and only one of them is
-- ever up at a time.
local Tooltips = {}
local TipOwner = nil
local TipShown = nil
local TipWait  = 0.4                                                                  -- how long the pointer has to rest before a description is earned

-- Taking a surface away takes its tooltip with it: a description left floating over a window that is
-- no longer there is worse than no description at all.
local function HideTooltip()
    local tip = TipShown
    TipOwner = nil
    TipShown = nil
    if tip == nil then
        return
    end

    Motion.Play(tip, "Close", { GroupTransparency = 1 })
    task.delay(Motion.Specs.Close.Duration, function()
        if TipShown == nil then
            tip.Visible = false
        end
    end)
end

local function TooltipFor(frame)
    local gui = frame:FindFirstAncestorOfClass("ScreenGui")
    if gui == nil then
        return nil
    end
    if Tooltips[gui] ~= nil and Tooltips[gui].Parent ~= nil then
        return Tooltips[gui]
    end

    -- A group, so the whole tooltip fades with one property instead of one per part. Where the
    -- client has no group the frame still works: the fade goes, the description does not.
    local tip = Sticker(Element {
        ClassName         = "CanvasGroup",
        Parent            = gui,
        Name              = "Tooltip",
        Size              = UDim2.new(0, 0, 0, 22),
        AutomaticSize     = Enum.AutomaticSize.X,
        GroupTransparency = 1,
        Visible           = false,
        ZIndex            = 2147483000,
    }, { Color = "Surface", Alpha = Theme.WindowAlpha, Corner = "RowRadius", Stroke = "Outline", Rim = true, Glass = true, Padding = { 5, 9, 5, 9 } })

    local label = Texted(tip, {
        Name   = "Label",
        Text   = "",
        Tint   = "Text",
        Size   = Theme.Type.Support,
        Size2  = UDim2.new(0, 0, 1, 0),
        ZIndex = 2147483001,
    })
    label.AutomaticSize = Enum.AutomaticSize.X

    Tooltips[gui] = tip
    return tip
end

-- The wait is what makes a tooltip a tooltip: a description that appears as the pointer crosses the
-- window on its way somewhere else is noise, and one that appears once the pointer has stopped is an
-- answer. Leaving before the wait is over cancels it, which is what the token counts.
local function Describe(frame, description)
    if frame == nil or description == nil or description == "" then
        return
    end

    local text     = tostring(description)
    local hovering = false
    local token    = 0

    -- The tooltip is not built until a description is actually earned, so a control the pointer only
    -- crosses costs nothing at all.
    local function Show(mine)
        if not hovering or mine ~= token then
            return
        end

        local tip = TooltipFor(frame)
        if tip == nil then
            return
        end

        local label = tip:FindFirstChild("Label")
        label.Text = text

        -- Under the control, unless the screen has run out underneath it.
        local camera = Workspace.CurrentCamera
        local screen = camera and camera.ViewportSize or Vector2.new(1920, 1080)
        local origin = frame.AbsolutePosition
        local below  = origin.Y + frame.AbsoluteSize.Y + 6
        local up     = below + tip.AbsoluteSize.Y > screen.Y

        tip.Position = UDim2.fromOffset(
            math.clamp(origin.X, 8, math.max(8, screen.X - tip.AbsoluteSize.X - 8)),
            up and math.max(8, origin.Y - tip.AbsoluteSize.Y - 6) or below)
        tip.Visible = true
        TipOwner    = frame
        TipShown    = tip
        Motion.Play(tip, "Panel", { GroupTransparency = 0 })
    end

    frame.MouseEnter:Connect(function()
        hovering = true
        token    = token + 1
        local mine = token
        task.delay(TipWait, function()
            Show(mine)
        end)
    end)

    frame.MouseLeave:Connect(function()
        hovering = false
        token    = token + 1
        if TipOwner == frame then
            HideTooltip()
        end
    end)
end

-- A full-width bar with the knob riding left and the caption clearing it in both states. Off is a
-- pane of glass; on is a near-solid white pill, so the two states differ in density rather than in
-- hue and the whole control stays monochrome.
local SwitchLooks = {
    [true]  = { Track = Theme.Text, TrackAlpha = Theme.SwitchOnAlpha, Knob = Theme.Invert, Caption = Theme.Invert },
    [false] = { Track = Theme.Row,  TrackAlpha = Theme.RowAlpha,       Knob = Theme.Muted,  Caption = Theme.Text   },
}

local function Switch(properties)
    local track = Sticker(Element {
        ClassName       = "TextButton",
        Parent          = properties.Parent,
        Name            = properties.Name or properties.Caption or "Switch",
        Size            = properties.Size or UDim2.new(1, 0, 0, 30),
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
        Size        = UDim2.new(0, 20, 0, 20),
        Position    = UDim2.new(0, 3, 0.5, -10),
        ZIndex      = 3,
    }, { Color = "Muted", Corner = 0.5 })

    -- The knob stretches rather than grows: one Scale leaves the travel maths and the caption
    -- untouched, and the driver counts a Scale as movement, so reduced motion still snaps it.
    local stretch = Element { ClassName = "UIScale", Parent = knob, Name = "Scale" }

    local caption = Texted(track, {
        Text     = string.upper(properties.Caption or "TOGGLE"),
        Tint     = "Text",
        Size     = Theme.Type.Heading,
        Position = UDim2.fromOffset(28, 0),
        Size2    = UDim2.new(1, -55, 1, 0),
        ZIndex   = 4,
    })

    local state = properties.Value and true or false

    local function Render(animate)
        local look     = SwitchLooks[state]
        local position = state and UDim2.new(1, -23, 0.5, -10) or UDim2.new(0, 3, 0.5, -10)

        Apply(knob,    "Switch", { Position = position, BackgroundColor3 = look.Knob }, animate)
        Apply(caption, "Switch", { TextColor3 = look.Caption },                         animate)
        Apply(track,   "Switch", { BackgroundColor3 = look.Track, BackgroundTransparency = look.TrackAlpha }, animate)
    end

    local function Toggle()
        state = not state
        Render(true)
        if properties.OnChange then
            properties.OnChange(state)
        end
    end

    track.MouseButton1Click:Connect(Toggle)

    -- A press stretches the knob, so the control answers the hand before its state changes, and
    -- anything that ends the press - the button coming up, the pointer leaving - lets it back down.
    -- Both ride the Press channel, which is the one with the shortest fuse.
    local function Squeeze(scale)
        Motion.Play(stretch, "Press", { Scale = scale })
    end
    track.MouseButton1Down:Connect(function() Squeeze(1.18) end)
    track.MouseButton1Up:Connect(function()   Squeeze(1)    end)
    track.MouseLeave:Connect(function()       Squeeze(1)    end)

    Describe(track, properties.Description)

    Render(false)

    -- Activate is the same Toggle a click runs, so a key and a pointer are one path rather than two.
    return Focus.Register {
        Frame    = track,
        Activate = Toggle,
        Set      = function(value)
            state = value and true or false
            Render(true)
        end,
        Get      = function()
            return state
        end,
    }
end

-- A well showing the caption and the current value, with the option list dropping out of it.
--
-- The list is a layer while it is up: it holds the one transient slot the focus registry hands out,
-- and that is what makes Escape close it, a bare letter reach it for type-ahead, a press outside it
-- take it down, and a second menu impossible to open on top of it. Opening and closing run on the
-- Panel and Close channels, which are the dropdown's own two numbers in the timing table.
local ENTRY_HEIGHT = 24                                                               -- an entry's 22 px plus the list's 2 px of padding
local MENU_GAP     = 4                                                                -- between the row and its list
local MENU_SLIDE   = 6                                                                -- how far the list travels as it arrives

local function Select(properties)
    local options = {}
    for _, option in ipairs(properties.Options or {}) do
        options[#options + 1] = tostring(option)
    end

    local height = math.min(#options, properties.VisibleRows or Theme.VisibleRows) * ENTRY_HEIGHT + 8

    local row = Sticker(Element {
        ClassName       = "TextButton",
        Parent          = properties.Parent,
        Name            = properties.Name or properties.Caption or "Select",
        Size            = properties.Size or UDim2.new(1, 0, 0, properties.Height or 32),
        AutoButtonColor = false,
        Text            = "",
        LayoutOrder     = properties.Order or 1,
        Position        = properties.Position,
        ZIndex          = properties.ZIndex or 2,
    }, { Color = "Well", Alpha = Theme.WellAlpha, Corner = "RowRadius", Stroke = "Line" })

    Texted(row, {
        Text     = string.upper(properties.Caption or "SELECT"),
        Tint     = "Muted",
        Size     = Theme.Type.Heading,
        Position = UDim2.fromOffset(10, 0),
        Size2    = UDim2.new(0.4, -14, 1, 0),
        ZIndex   = 3,
    })

    local value = Texted(row, {
        Tint     = "Text",
        Size     = Theme.Type.Body,
        X        = Enum.TextXAlignment.Right,
        Size2    = UDim2.new(0.6, -30, 1, 0),                                          -- clear of the chevron
        ZIndex   = 3,
    })

    -- The chevron is a caret rotated into an arrow: pointing down while the list is shut, and turned
    -- up when it is out. One glyph, two states, nothing else to draw.
    local chevron = Texted(row, {
        Text        = ">",
        Tint        = "Muted",
        Size        = Theme.Type.Heading,
        Name        = "Chevron",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position    = UDim2.new(1, -14, 0.5, 0),
        Size2       = UDim2.fromOffset(12, 12),
        Rotation    = 90,
        ZIndex      = 3,
    })

    local menu = Sticker(Element {
        ClassName           = "ScrollingFrame",
        Parent              = row,
        Name                = "Menu",
        Size                = UDim2.new(1, 0, 0, height),
        Position            = UDim2.new(0, 0, 1, MENU_GAP),
        BorderSizePixel     = 0,
        ScrollBarThickness  = 4,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize          = UDim2.new(0, 0, 0, 0),
        CanvasPosition      = UDim2.new(0, 0, 0, 0),                                  -- where the list is scrolled to is decided when it opens
        Visible             = false,
        ZIndex              = 50,
    }, { Color = "Surface", Alpha = Theme.MenuAlpha, Corner = "RowRadius", Stroke = "Line", Rim = true, Glass = true, Padding = { 4, 4, 4, 4 } })

    Element {
        ClassName = "UIListLayout",
        Parent    = menu,
        Name      = "Layout",
        Padding   = UDim.new(0, 2),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }

    -- An entry is glass over the menu, so at rest it is nothing at all and only the hover and the
    -- press bring a fill up under the text.
    local EntryLooks = {
        Rest  = { BackgroundTransparency = 1 },
        Hover = { BackgroundTransparency = Theme.HoverAlpha },
        Press = { BackgroundTransparency = Theme.PressAlpha },
    }

    local entries  = {}
    local order    = {}                                                               -- options in display order, for scrolling and type-ahead
    local selected = nil
    local marked   = nil                                                              -- the entry the keys have reached
    local prefix   = ""
    local open     = false
    local layer                                                                       -- the transient slot, declared before the two functions that use it

    local function Render(name)
        selected         = name
        value.Text       = name or "—"
        value.TextColor3 = name and Theme.Text or Theme.Muted
        for option, entry in pairs(entries) do
            entry.label.TextColor3 = Theme[option == name and "Text" or "Muted"]
        end
    end

    -- Marking is what type-ahead moves: the fill a hover leaves, on whichever entry the keys have
    -- reached, cleared off the one before it.
    local function Mark(index)
        local previous = marked
        if previous ~= nil then
            local entry = entries[order[previous]]
            if entry ~= nil then
                entry.Frame.BackgroundTransparency = 1
            end
        end

        marked = index
        if index == nil then
            return
        end

        local entry = entries[order[index]]
        if entry ~= nil then
            entry.Frame.BackgroundTransparency = Theme.HoverAlpha
        end
    end

    -- An option that is out of sight is the same as not knowing which one is chosen, so the list is
    -- scrolled to put one in the middle of its window.
    local function ScrollTo(index)
        local window  = menu.AbsoluteSize.Y
        local content = #options * ENTRY_HEIGHT
        local wanted  = (index - 1) * ENTRY_HEIGHT - (window - ENTRY_HEIGHT) / 2
        menu.CanvasPosition = UDim2.new(0, 0, 0, math.clamp(wanted, 0, math.max(0, content - window)))
    end

    local function IndexOf(option)
        for index, held in ipairs(order) do
            if held == option then
                return index
            end
        end
        return nil
    end

    -- Below the row unless the screen has run out, in which case above it. The slide always runs away
    -- from the row, so both placements arrive the same way.
    local function Place()
        local camera  = Workspace.CurrentCamera
        local screen  = camera and camera.ViewportSize.Y or 1080
        local up      = row.AbsolutePosition.Y + row.AbsoluteSize.Y + MENU_GAP + height > screen
        local resting = up and UDim2.new(0, 0, 0, -(height + MENU_GAP)) or UDim2.new(0, 0, 1, MENU_GAP)
        return resting, (up and -MENU_SLIDE or MENU_SLIDE)
    end

    local function Shut()
        if not open then
            return
        end
        open   = false
        prefix = ""
        if Focus.layer == layer then
            Focus.layer = nil                                                         -- the list is down; nothing is claiming the keyboard
        end

        local resting, slide = Place()
        Motion.Play(menu, "Close",    { Position = UDim2.new(resting.X.Scale, resting.X.Offset, resting.Y.Scale, resting.Y.Offset + slide) })
        Motion.Play(chevron, "Close", { Rotation = 90 })
        Mark(nil)

        -- The exit is the shorter of the two, and the list stops being drawn once it has run.
        task.delay(Motion.Specs.Close.Duration, function()
            if not open then
                menu.Visible = false
            end
        end)
    end

    -- The layer: what the registry needs to take this list down, to recognise a press inside it, and
    -- to hand it the letters type-ahead is made of.
    layer = {
        Dismiss  = Shut,
        Contains = function(position)
            return Inside(row, position) or (open and Inside(menu, position))
        end,
        Type = function(letter)
            if not open then
                return
            end

            -- A letter that extends nothing starts the prefix again, which is what keeps a stale
            -- prefix from swallowing the next search.
            local function Find(text)
                for index, option in ipairs(order) do
                    if string.sub(string.lower(option), 1, #text) == text then
                        return index
                    end
                end
                return nil
            end

            local index = Find(prefix .. letter)
            if index ~= nil then
                prefix = prefix .. letter
            else
                index  = Find(letter)
                prefix = index ~= nil and letter or ""
            end

            if index == nil then
                return
            end
            Mark(index)
            ScrollTo(index)
        end,
    }

    local function Open()
        if open then
            return
        end

        Focus.Claim(layer)                                                           -- claiming takes down whatever else was up
        open   = true
        prefix = ""

        local resting, slide = Place()
        menu.Visible  = true
        menu.Position = UDim2.new(resting.X.Scale, resting.X.Offset, resting.Y.Scale, resting.Y.Offset + slide)
        Motion.Play(menu, "Panel",    { Position = resting })
        Motion.Play(chevron, "Panel", { Rotation = -90 })

        local index = IndexOf(selected) or 1
        Mark(index)
        ScrollTo(index)
    end

    -- Enter walks in and commits: on a shut row it opens the list, and on an open one it takes the
    -- entry the keys have reached.
    local function Activate()
        if not open then
            Open()
            return
        end

        local option = order[marked or 0]
        if option ~= nil then
            Render(option)
            Shut()
            if properties.OnSelect then
                properties.OnSelect(option)
            end
            return
        end
        Shut()
    end

    for index, option in ipairs(options) do
        local entry = Sticker(Element {
            ClassName       = "TextButton",
            Parent          = menu,
            Name            = option,
            Size            = UDim2.new(1, 0, 0, ENTRY_HEIGHT - 2),
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
        order[index]    = option
        Hoverable(entry, EntryLooks)

        entry.MouseButton1Click:Connect(function()
            Render(option)
            Shut()
            if properties.OnSelect then
                properties.OnSelect(option)
            end
        end)
    end

    row.MouseButton1Click:Connect(function()
        if open then
            Shut()
        else
            Open()
        end
    end)

    Describe(row, properties.Description)

    Render(tostring(properties.Value or options[1] or "—"))

    return Focus.Register {
        Frame    = row,
        Activate = Activate,
        Set      = function(option)
            Render(tostring(option))
        end,
        Get      = function()
            return selected
        end,
        Options  = options,
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
        Size              = properties.Size or UDim2.new(0, properties.Width or 50, 0, 26),
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
    }, { Color = "Well", Alpha = Theme.WellAlpha, Corner = "RowRadius", Stroke = "Line" })
    Fonted(box)

    -- Everything the focus registry needs from a field: the ring it wears while the caret is in it,
    -- the value Escape will put back, and whether it has the caret now.
    local stroke  = box:FindFirstChild("Stroke")
    local settled = box.Text                                                          -- refreshed every time the caret arrives
    local focused = false
    local shaking = false

    local function Ring(transparency)
        Motion.Play(stroke, "Focus", { Transparency = transparency })
    end

    -- A refused character shakes the field: alternating offsets, each smaller than the last, chased
    -- by the Press decay, so the box is never far from where it belongs and lands exactly on it. The
    -- offset is the whole animation - the position it returns to is captured once, up front.
    -- Reduced motion keeps the refusal and drops the movement, the same bargain the driver makes
    -- everywhere else. Overlapping shakes are ignored rather than queued: two would compound.
    local function Shake()
        if Motion.Enabled == false or shaking then
            return
        end
        shaking = true

        local base    = box.Position
        local offsets = { 5, -4, 3, -2, 1, 0 }
        for index, offset in ipairs(offsets) do
            task.delay((index - 1) * 0.035, function()
                Motion.Play(box, "Press", {
                    Position = UDim2.new(base.X.Scale, base.X.Offset + offset, base.Y.Scale, base.Y.Offset),
                })
            end)
        end
        task.delay(#offsets * 0.035, function()
            shaking = false
        end)
    end

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
                Shake()                                                                 -- the character is gone, and the box says so
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

    -- Escape inside a field puts its value back, and whatever is listening hears the reverted text:
    -- an abandoned edit that leaves a consumer holding the new value would be worse than no Escape.
    local function Revert()
        box.Text = settled
        if properties.OnSubmit then
            properties.OnSubmit(box.Text)
        end
        if focused then
            pcall(function()
                box:ReleaseFocus()
            end)
        end
    end

    -- Declared before the handlers, because they close over it: the field tells the registry that it
    -- is the one editing, which is what routes Escape here instead of dropping focus.
    local focusable = Focus.Register {
        Frame  = box,
        Revert = Revert,
        Activate = function()
            Submit(box.Text)                                                             -- Enter on a focused field is the submit Return already runs
        end,
    }

    box.Focused:Connect(function()
        focused = true
        settled = box.Text                                                           -- what Escape puts back is what the caret found
        Focus.editing = focusable

        -- The whole value is selected, so the first keystroke replaces it instead of being appended
        -- to a number the field was only showing.
        box.CursorPosition = #box.Text + 1
        box.SelectionStart = 1
        Ring(Theme.FocusAlpha)
    end)

    box.FocusLost:Connect(function(entered)
        focused = false
        Focus.editing = nil
        Ring(Theme.LineAlpha)

        -- Return is acknowledged rather than assumed: the edge goes flush bright and then settles
        -- back, so a value that was sent looks different from one that was simply let go.
        if entered then
            Ring(0)
            task.delay(0.12, function()
                if not focused then
                    Ring(Theme.LineAlpha)
                end
            end)
        end
    end)

    Describe(box, properties.Description)

    return box
end

local function Button(properties)
    local button = Sticker(Element {
        ClassName       = "TextButton",
        Parent          = properties.Parent,
        Name            = properties.Name or properties.Caption or "Button",
        Size            = properties.Size or UDim2.new(1, 0, 0, 30),
        Position        = properties.Position,
        AutoButtonColor = false,
        Text            = "",
        LayoutOrder     = properties.Order or 1,
        ZIndex          = properties.ZIndex or 2,
    }, { Color = properties.Color or "Row", Alpha = Theme.RowAlpha, Corner = "RowRadius", Stroke = properties.Stroke or "Line", Glass = true })

    Texted(button, {
        Text   = string.upper(properties.Caption or properties.Text or "BUTTON"),
        Size   = properties.TextSize or Theme.Type.Heading,
        X      = Enum.TextXAlignment.Center,
        Tint   = properties.Tint or "Text",
        ZIndex = (properties.ZIndex or 2) + 1,
    })

    -- Hover picks no new colour: the fill keeps its tint and simply comes up a little denser,
    -- which is the one thing every glass control in this file does when it is touched.
    Hoverable(button, RowLooks)

    local function Press()
        if properties.OnClick then
            properties.OnClick()
        end
    end

    button.MouseButton1Click:Connect(Press)

    -- A button is focusable as well, or Tab would walk straight past the only way out of a window.
    -- Activate is the same Press the pointer runs, so the two paths cannot drift apart.
    Focus.Register {
        Frame    = button,
        Activate = Press,
    }
    Describe(button, properties.Description)

    return button
end

-- A section is a heading and a hairline, the way the window separates its parts.
local function Heading(parent, order, text)
    local header = Row(parent, order, 22)

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

-- The app's own state is filled in further down, but the configuration is defined first and needs to
-- read the window list, so the name is declared here and the table itself is built there.
local App

--=== scrolling =============================================================

-- A body that scrolls once it is taller than the cap. Three deep, because the bands at the edges have
-- to hold still while the content moves under them: the wrap is the height the plate sees, the scroll
-- inside it is what actually scrolls, and the bands are children of the wrap rather than of the
-- scroller - a child of a ScrollingFrame travels with the canvas, which would make a band scroll away
-- with the very content it is meant to shade.
local function ScrollingBody(order)
    -- A group rather than a frame, so the whole tab - content, bands and all - can fade with one
    -- property when it arrives. Where the client has no group the body still works: the fade is
    -- dropped, the tab is not.
    local wrap = Element {
        ClassName              = "CanvasGroup",
        Name                   = "Body",
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, 0, 0),
        LayoutOrder            = order,
    }

    local scroll = Element {
        ClassName              = "ScrollingFrame",
        Parent                 = wrap,
        Name                   = "Scroll",
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, 1, 0),
        BorderSizePixel        = 0,
        ScrollBarThickness     = 4,
        ScrollingDirection     = Enum.ScrollingDirection.Y,
        AutomaticCanvasSize    = Enum.AutomaticSize.Y,
        CanvasSize             = UDim2.new(0, 0, 0, 0),
        CanvasPosition         = UDim2.new(0, 0, 0, 0),
        ZIndex                 = 2,
    }

    local content = Element {
        ClassName              = "Frame",
        Parent                 = scroll,
        Name                   = "Content",
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, 0, 0),
        AutomaticSize          = Enum.AutomaticSize.Y,
        ZIndex                 = 2,
    }

    local body = { Wrap = wrap, Scroll = scroll, Content = content, Fades = {}, Natural = 0, Height = 0, Collapsed = false }

    -- The bands that say there is more above or below: the surface the window is made of, fading to
    -- nothing toward the middle, so the content slides under them rather than being cut at a line.
    for _, band in ipairs({ { "Top", 0, 90 }, { "Bottom", 1, 270 } }) do
        local fade = Element {
            ClassName              = "Frame",
            Parent                 = wrap,
            Name                   = "Fade" .. band[1],
            AnchorPoint            = Vector2.new(0, band[2]),
            Position               = UDim2.new(0, 0, band[2], 0),
            Size                   = UDim2.new(1, 0, 0, Theme.FadeEdge),
            BackgroundColor3       = Theme.Surface,
            BackgroundTransparency = 1,
            BorderSizePixel        = 0,
            Visible                = false,
            ZIndex                 = 5,
        }
        Element {
            ClassName    = "UIGradient",
            Parent       = fade,
            Name         = "Band",
            Rotation     = band[3],
            Transparency = NumberSequence.new {
                NumberSequenceKeypoint.new(0, 0),
                NumberSequenceKeypoint.new(1, 1),
            },
        }
        body.Fades[#body.Fades + 1] = fade
    end

    -- The cap: what the plate sees is the content's height until that passes the maximum, and the
    -- maximum after it. AutomaticSize cannot be animated, so the height it would have produced is
    -- measured and then tweened, and the bands appear only when there is really more to see.
    function body:Cap()
        local natural = content.AbsoluteSize.Y
        local over    = natural > Theme.MaxHeight

        self.Natural = natural
        self.Height  = math.min(natural, Theme.MaxHeight)

        if self.Collapsed then
            return                                                                   -- folded away: its height is nothing until it unfolds
        end

        Motion.Play(wrap, "Panel", { Size = UDim2.new(1, 0, 0, self.Height) })

        for _, fade in ipairs(self.Fades) do
            if over and not fade.Visible then
                fade.Visible = true
                Motion.Play(fade, "Panel", { BackgroundTransparency = 0 })
            elseif not over and fade.Visible then
                Motion.Play(fade, "Close", { BackgroundTransparency = 1 })
                task.delay(Motion.Specs.Close.Duration, function()
                    if not over then
                        fade.Visible = false
                    end
                end)
            end
        end
    end

    function body:SetCollapsed(collapsed)
        if self.Collapsed == collapsed then
            return
        end
        self.Collapsed = collapsed and true or false
        Fold(wrap, self.Collapsed, self.Height)
    end

    return body
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

-- Where the surfaces are is saved beside the flags, under a key shaped like nothing a script would
-- name a flag: a flag has to be an identifier to be written, and this one cannot be.
local LayoutKey = "$layout"

-- A flag changing is worth remembering, but not worth writing down twelve times while someone types a
-- number: the save waits for the changes to stop and only then goes to disk, which is what a debounce
-- is. Nothing is scheduled at all unless the script asked for configuration saving, so a window that
-- never saves never pays for this.
local AUTOSAVE_DELAY = 0.5
local Autosave = { token = 0 }

local function ScheduleSave()
    if not Settings.Enabled then
        return
    end

    Autosave.token = Autosave.token + 1
    local mine = Autosave.token
    task.delay(AUTOSAVE_DELAY, function()
        if mine ~= Autosave.token then
            return                                                                   -- something changed again while this one waited
        end
        MonoUI:SaveConfiguration()
    end)
end

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

    -- Where each surface came to rest, so a window opens where it was left rather than where the
    -- script first put it. Keyed by the name it was created under.
    local layout = {}
    for _, list in ipairs({ App.windows, App.plates }) do
        for _, surface in ipairs(list) do
            local plate = surface.plate
            if plate ~= nil and plate.Parent ~= nil then
                layout[tostring(surface.settings.Name or "window")] = {
                    X = plate.Position.X.Offset,
                    Y = plate.Position.Y.Offset,
                }
            end
        end
    end
    data[LayoutKey] = layout

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

    -- Where the surfaces were, put back before the flags are applied: a script that reads its own
    -- flags should already find its window where it left it.
    local layout = data[LayoutKey]
    if type(layout) == "table" then
        for _, list in ipairs({ App.windows, App.plates }) do
            for _, surface in ipairs(list) do
                local plate = surface.plate
                local where = layout[tostring(surface.settings.Name or "window")]
                if plate ~= nil and type(where) == "table" and type(where.X) == "number" and type(where.Y) == "number" then
                    plate.Position = UDim2.new(plate.Position.X.Scale, where.X, plate.Position.Y.Scale, where.Y)
                end
            end
        end
    end

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

    -- Every way a flag's value can change ends here: the element's own callback when someone uses the
    -- control, and the Set the registry calls when a saved value is applied. Putting the autosave in one
    -- place means it never has to know which of them it was.
    local function Changed(settings, value)
        if settings.Callback then
            settings.Callback(value)
        end
        ScheduleSave()
    end

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
            OnChange = function(value)
                Changed(settings, value)
            end,
            Description = settings.Description,
        }
        RegisterFlag(settings.Flag, {
            Type = "Toggle",
            Get  = element.Get,
            Set  = function(value)
                element.Set(value)
                Changed(settings, value)
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
            OnSelect = function(value)
                Changed(settings, value)
            end,
            Description = settings.Description,
        }
        RegisterFlag(settings.Flag, {
            Type = "Dropdown",
            Get  = element.Get,
            Set  = function(value)
                element.Set(value)
                Changed(settings, value)
            end,
        })
        return element
    end

    function region:CreateInput(settings)
        settings = settings or {}
        local row = region:CreateRow(28)

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
            Size             = UDim2.new(0.55, 0, 0, 26),
            Position         = UDim2.new(1, 0, 0.5, 0),
            PlaceholderText  = settings.PlaceholderText,
            NumbersOnly      = settings.NumbersOnly,
            CharacterLimit   = settings.CharacterLimit,
            SubmitOnEnter    = settings.OnEnter,
            RemoveTextAfterFocusLost = settings.RemoveTextAfterFocusLost,
            OnSubmit         = function(value)
                Changed(settings, value)
            end,
            Description      = settings.Description,
        }
        box.AnchorPoint = Vector2.new(1, 0.5)

        RegisterFlag(settings.Flag, {
            Type = "Input",
            Get  = function()
                return box.Text
            end,
            Set  = function(value)
                box.Text = tostring(value)
                Changed(settings, value)
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
            Description = settings.Description,
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
App = { gui = nil, blur = nil, rain = nil, rainConnection = nil, streaks = {}, connections = {}, windows = {}, plates = {}, surfaces = {},
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
    return App.gui
end

--=== toasts ================================================================

-- A small stack of messages in the corner of the screen: what a script says happened when the window
-- has no room to say it - a save that went through, a load that found nothing, something that went
-- wrong. One stack per gui, so a script building two windows does not get two, and only the last few
-- are kept: a toast still on screen after the tenth has arrived has stopped being information.
local ToastStacks = {}
local ToastOrder  = 0
local Leaving     = {}                                                                -- toasts on their way out, which no longer count towards the stack
local TOASTS_KEPT = 4
local TOAST_LIFE  = 4                                                                 -- seconds a toast stays unless it is told otherwise

local function DismissToast(toast)
    if toast == nil or toast.Parent == nil or Leaving[toast] then
        return false
    end

    Leaving[toast] = true
    Motion.Play(toast, "Dismiss", { GroupTransparency = 1 })
    task.delay(Motion.Specs.Dismiss.Duration, function()
        Leaving[toast] = nil
        if toast.Parent ~= nil then
            toast:Destroy()
        end
    end)
    return true
end

function MonoUI:DismissToast(toast)
    return DismissToast(toast)
end

local function ToastStack()
    local gui = App.gui
    if gui == nil then
        return nil
    end
    if ToastStacks[gui] ~= nil and ToastStacks[gui].Parent ~= nil then
        return ToastStacks[gui]
    end

    -- Anchored to the corner and allowed to grow upward, so the newest message is always the one
    -- nearest the corner and the older ones rise out of the way.
    local stack = Element {
        ClassName              = "Frame",
        Parent                 = gui,
        Name                   = "Toasts",
        AnchorPoint            = Vector2.new(1, 1),
        Position               = UDim2.new(1, -16, 1, -16),
        Size                   = UDim2.new(0, 0, 0, 0),
        AutomaticSize          = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        ZIndex                 = 2147483000,
    }
    Element {
        ClassName = "UIListLayout",
        Parent    = stack,
        Name      = "Layout",
        Padding   = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }

    ToastStacks[gui] = stack
    return stack
end

-- A message, for as long as it is worth reading. A group, so the whole thing fades with one property,
-- and the label decides how wide it is.
function MonoUI:Toast(message, tint, lifetime)
    local stack = ToastStack()
    if stack == nil then
        return nil
    end

    -- Room is made *before* the new message joins the stack, so what is dropped is always the oldest
    -- of the toasts that are still being read rather than one that is already on its way out.
    local held = {}
    for _, child in ipairs(stack:GetChildren()) do
        if child.Name == "Toast" and not Leaving[child] then
            held[#held + 1] = child
        end
    end
    while #held >= TOASTS_KEPT do
        DismissToast(table.remove(held, 1))
    end

    ToastOrder = ToastOrder + 1

    local toast = Sticker(Element {
        ClassName         = "CanvasGroup",
        Parent            = stack,
        Name              = "Toast",
        Size              = UDim2.new(0, 0, 0, 30),
        AutomaticSize     = Enum.AutomaticSize.X,
        GroupTransparency = 1,
        LayoutOrder       = ToastOrder,
        ZIndex            = 2147483001,
    }, { Color = "Surface", Alpha = Theme.WindowAlpha, Corner = "RowRadius", Stroke = "Outline", Rim = true, Glass = true, Padding = { 6, 12, 6, 12 } })

    local label = Texted(toast, {
        Name   = "Label",
        Text   = tostring(message or ""),
        Tint   = tint or "Text",
        Size   = Theme.Type.Body,
        Size2  = UDim2.new(0, 0, 1, 0),
        ZIndex = 2147483002,
    })
    label.AutomaticSize = Enum.AutomaticSize.X

    Motion.Play(toast, "Toast", { GroupTransparency = 0 })
    task.delay(lifetime or TOAST_LIFE, function()
        DismissToast(toast)
    end)

    -- Only the last few are kept: a stack taller than the screen is not a stack, it is a wall.
    local held = {}
    for _, child in ipairs(stack:GetChildren()) do
        if child.Name == "Toast" then
            held[#held + 1] = child
        end
    end
    if #held > TOASTS_KEPT then
        DismissToast(held[1])
    end

    return toast
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
    local pushX, pushY = LensOffset(drop.X - lens.X, drop.Y - lens.Y, warp)
    drop.Frame.Position = UDim2.fromOffset(drop.X + pushX, drop.Y + pushY)
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
    -- The easing is the driver's own decay and not a second copy of it: the lens is a follower, so
    -- it is the same lambda that Motion.Specs.Follow carries.
    local follow = rain.Warp.Follow or Motion.Specs.Follow.Rate
    local target = UserInput:GetMouseLocation() - layer.AbsolutePosition
    App.lens     = (App.lens or target):Lerp(target, Motion.DecayAlpha(follow, step))

    for _, drop in ipairs(App.streaks) do
        AdvanceDrop(drop, step, wind, bounds)
        DrawDrop(drop, App.lens, rain.Warp, rotation)
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

-- One plate: the window surface itself, with the title bar, the hint line and the drag.
-- Everything else - the tab strip, the body, a second plate - hangs off it.
local function CreatePlateFrame(settings, order)
    local plate = Sticker(Element {
        ClassName     = "Frame",
        Parent        = EnsureGui(settings.GuiName),
        Name          = settings.Name or "Plate",
        AnchorPoint   = Vector2.new(0, 0),
        Position      = settings.Position or UDim2.fromOffset(80, 120 + ((order or 1) - 1) * 24),
        Size          = UDim2.fromOffset(settings.Width or Theme.Width, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        ZIndex        = 1,
    }, {
        Color   = "Surface",
        Alpha   = Theme.WindowAlpha,
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

    local bar = Sticker(Element {
        ClassName   = "Frame",
        Parent      = plate,
        Name        = "Bar",
        Size        = UDim2.new(1, 0, 0, 34),
        LayoutOrder = 1,
    }, { Color = "Header", Alpha = Theme.PanelAlpha, Corner = "RowRadius", Stroke = "Line", Glass = true })

    Texted(bar, {
        Text     = string.upper(settings.Name or "PLATE"),
        Size     = Theme.Type.Label,
        Bold     = true,
        Position = UDim2.fromOffset(12, 4),
        Size2    = UDim2.new(1, -128, 0, 16),
        ZIndex   = 2,
    })

    local hint = Texted(bar, {
        Text     = settings.Hint or "",
        Tint     = "Muted",
        Size     = Theme.Type.Support,
        Bold     = false,
        Position = UDim2.fromOffset(12, 20),
        Size2    = UDim2.new(1, -128, 0, 11),
        ZIndex   = 2,
    })

    -- the pill that shows state, and the dot that carries its colour
    local pill = Sticker(Element {
        ClassName   = "Frame",
        Parent      = bar,
        Name        = "Status",
        AnchorPoint = Vector2.new(1, 0.5),
        Position    = UDim2.new(1, -10, 0.5, 0),
        Size        = UDim2.fromOffset(settings.PillWidth or 112, 22),
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

    return plate, bar, hint, { pill = pill, dot = dot, label = status }
end

function MonoUI:CreatePlate(settings)
    settings = settings or {}
    Motion.Enabled = settings.Motion ~= false

    local plate, bar, hint, status = CreatePlateFrame(settings, #App.plates + 1)

    local object = {
        connections = {},
        dragThreshold = settings.DragThreshold or 3,
        plate = plate,
        bar = bar,
        status = status,
        settings = settings,
        visible = true,
    }
    App.plates[#App.plates + 1] = object

    object.body = Element {
        ClassName     = "Frame",
        Parent        = plate,
        Name          = "Body",
        BackgroundTransparency = 1,
        Size          = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder   = 2,
    }

    local region = CreateRegion(object.body)
    for key, value in pairs(region) do
        if type(value) == "function" then
            object[key] = value
        end
    end
    object.region = region

    RegisterSurface(object, settings)
    Dragging(object, plate, bar)

    hint.Text = settings.Hint or (settings.ToggleKey and (string.upper(tostring(settings.ToggleKey.Name)) .. " TO HIDE") or "")

    -- The pill says what the window is doing, and it says it once: the text fades out, becomes the new
    -- text, and comes back, so a status changed twice in a second reads as two changes rather than a
    -- flicker of characters. The dot takes its colour over the same moment, on a decay - SetStatus is
    -- called whenever the script likes, so it is the interruptible kind of change.
    local said = 0
    function object:SetStatus(text, tint)
        said = said + 1
        local mine = said

        Motion.Play(status.dot, "Hover", { BackgroundColor3 = tint or Theme.Muted })

        local message = tostring(text or "")
        if status.label.Text == message then
            return
        end
        if status.label.Text == "" then
            status.label.Text = message                                            -- nothing to fade out of
            Motion.Play(status.label, "Hover", { TextTransparency = 0 })
            return
        end

        Motion.Play(status.label, "Close", { TextTransparency = 1 })
        task.delay(Motion.Specs.Close.Duration, function()
            if mine ~= said then
                return                                                             -- another status arrived while this one was leaving
            end
            status.label.Text = message
            Motion.Play(status.label, "Hover", { TextTransparency = 0 })
        end)
    end

    function object:SetVisible(visible)
        object.visible = visible and true or false
        plate.Visible  = object.visible

        if object.visible then
            RegisterSurface(object, settings)
            Reveal(plate)
        else
            UnregisterSurface(object)
            HideTooltip()                                                          -- a description does not outlive the surface that owns it
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
        UnregisterSurface(object)
        pcall(function()
            plate:Destroy()
        end)
    end

    return object
end

function MonoUI:CreateWindow(settings)
    settings = settings or {}
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
        collapsed = false,
        morphed = false,
        visible = not settings.StartHidden,
    }
    App.windows[#App.windows + 1] = window

    local plate, bar, hint, status = CreatePlateFrame(settings, #App.windows)
    window.plate = plate
    window.bar = bar
    window.status = status

    -- The tab strip is a fixed grid of cells, a pill that slides to whichever tab is showing, and the
    -- host that carries both into the plate once there is more than one tab. The pill is made first so
    -- the buttons draw over it, and it is a sibling of the strip rather than a child, because a grid
    -- layout would lay the pill out as a cell of its own.
    local TAB_WIDTH   = 132
    local TAB_HEIGHT  = 28
    local TAB_GAP     = 6
    local TAB_PER_ROW = 6
    local TAB_SLIDE   = 8

    -- Where a tab's cell is: arithmetic rather than measurement, so the pill can be sent to a tab on the
    -- same frame the tab is made, before any layout has run.
    local function TabCell(index)
        local across = (index - 1) % TAB_PER_ROW
        local down   = math.floor((index - 1) / TAB_PER_ROW)
        return UDim2.fromOffset(across * (TAB_WIDTH + TAB_GAP), down * (TAB_HEIGHT + TAB_GAP))
    end

    local host = Element {
        ClassName              = "Frame",
        Parent                 = nil,                                             -- only parented once a second tab exists
        Name                   = "Tabs",
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, 0, TAB_HEIGHT),
        LayoutOrder            = 2,
    }

    local pill = Sticker(Element {
        ClassName   = "Frame",
        Parent      = host,
        Name        = "Pill",
        Size        = UDim2.fromOffset(TAB_WIDTH, TAB_HEIGHT),
        Position    = TabCell(1),
        ZIndex      = 2,
    }, { Color = "Text", Alpha = Theme.SwitchOnAlpha, Corner = "RowRadius", Stroke = "Line", Glass = true })

    local strip = Element {
        ClassName              = "Frame",
        Parent                 = host,
        Name                   = "Buttons",
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, 1, 0),
        ZIndex                 = 3,
    }
    Element {
        ClassName             = "UIGridLayout",
        Parent                = strip,
        Name                  = "Columns",
        CellSize              = UDim2.new(0, TAB_WIDTH, 0, TAB_HEIGHT),
        CellPadding           = UDim2.new(0, TAB_GAP, 0, 0),
        FillDirection         = Enum.FillDirection.Horizontal,
        FillDirectionMaxCells = TAB_PER_ROW,
        SortOrder             = Enum.SortOrder.LayoutOrder,
    }
    window.strip = host
    window.pill  = pill

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
    local chip = Sticker(Element {
        ClassName       = "TextButton",
        Parent          = App.gui,
        Name            = "Chip",
        Size            = UDim2.fromOffset(132, 26),
        AutoButtonColor = false,
        Text            = "",
        Visible         = false,
        ZIndex          = 5,
    }, { Color = "Surface", Alpha = Theme.WindowAlpha, Corner = "RowRadius", Stroke = "Outline", Rim = true, Glass = true })

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

    -- As on a plate: the text leaves before the next arrives, and the dot takes its colour on a decay.
    local announced = 0
    function window:SetStatus(text, tint)
        announced = announced + 1
        local mine = announced

        Motion.Play(status.dot, "Hover", { BackgroundColor3 = tint or Theme.Muted })

        local message = tostring(text or "")
        if status.label.Text == message then
            return
        end
        if status.label.Text == "" then
            status.label.Text = message
            Motion.Play(status.label, "Hover", { TextTransparency = 0 })
            return
        end

        Motion.Play(status.label, "Close", { TextTransparency = 1 })
        task.delay(Motion.Specs.Close.Duration, function()
            if mine ~= announced then
                return
            end
            status.label.Text = message
            Motion.Play(status.label, "Hover", { TextTransparency = 0 })
        end)
    end

    function window:SetVisible(visible)
        window.visible = visible and true or false

        if window.visible then
            chip.Visible  = false
            plate.Visible = true
            RegisterSurface(window, settings)
            Reveal(plate, window.morphed and Theme.MorphScale or nil)              -- back out of the chip it became
            window.morphed = false
            return true
        end

        -- Hiding is a morph rather than a swap: the plate shrinks to the size the chip has, and only
        -- then does the chip take over, so the two read as one object changing shape. The chip lands
        -- where the plate was, which is where the window was left.
        chip.Position = ClampedPosition(chip.Position, chip, plate.Position.X.Offset, plate.Position.Y.Offset)

        local scale = plate:FindFirstChild("Scale")
        local width = plate.AbsoluteSize.X
        if scale ~= nil and width > 0 then
            Motion.Play(scale, "Dismiss", { Scale = math.min(1, (chip.AbsoluteSize.X + 12) / width) })
        end

        UnregisterSurface(window)
        HideTooltip()                                                              -- a description does not outlive the surface that owns it

        task.delay(Motion.Enabled ~= false and Motion.Specs.Dismiss.Duration or 0, function()
            if window.visible then
                return                                                             -- shown again while it was shrinking
            end
            plate.Visible  = false
            chip.Visible   = true
            window.morphed = true
            if scale ~= nil then
                scale.Scale = 1                                                    -- off screen: give the plate its shape back for the next arrival
            end
        end)

        return false
    end

    function window:Toggle()
        return window:SetVisible(not window.visible)
    end

    -- What folds away: the tab strip when there is one, and every tab's body - so whichever tabs are
    -- waiting in the holder are the right height when they arrive.
    function window:SetCollapsed(collapsed)
        window.collapsed = collapsed and true or false

        if host.Parent == plate then
            Fold(host, window.collapsed, TAB_HEIGHT)
        end
        for _, tab in ipairs(window.tabs) do
            tab.body:SetCollapsed(window.collapsed)
        end
        return window.collapsed
    end

    -- A double click on the title bar folds the contents away and brings them back. A GuiObject has no
    -- double click of its own, so one is timed here, and a press that does not become one is left to
    -- the drag - which is what the drag threshold is for.
    local lastClick = 0
    bar.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
            return
        end

        local now = os.clock()
        if now - lastClick <= 0.35 then
            lastClick = 0
            window:SetCollapsed(not window.collapsed)
            return
        end
        lastClick = now
    end)

    -- The tab that is showing arrives rather than appearing: its content slides up against the tab that
    -- summoned it, and the body it lives in fades in as one group. The tab it replaced has already gone
    -- to the holder - the plate stacks what it is given, so the two cannot overlap while both are in it
    -- - which is why this is an arrival rather than a true cross-fade.
    local function Show(tab)
        local scroll = tab.body.Scroll
        scroll.Position = UDim2.fromOffset(0, TAB_SLIDE)
        Motion.Play(scroll, "Tab",    { Position = UDim2.fromOffset(0, 0) })
        Motion.Play(tab.wrap, "Tab",  { GroupTransparency = 0 })
    end

    function window:CreateTab(tabName)
        local body = ScrollingBody(3)
        local tab  = {
            Name    = tostring(tabName or "Tab"),
            body    = body,
            wrap    = body.Wrap,
            content = body.Content,
        }

        local region = CreateRegion(tab.content)
        for key, value in pairs(region) do
            if type(value) == "function" then
                tab[key] = value
            end
        end

        -- The cap follows the content - a row added, a section folded, a dropdown opened inside it -
        -- and the layout's content size is the signal that knows, watched for as long as the window
        -- lives. The first measurement is taken here so a tab that is never touched is still right.
        local layout = tab.content:FindFirstChild("Layout")
        if layout ~= nil then
            window.connections[#window.connections + 1] = layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
                body:Cap()
            end)
        end
        body:Cap()

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
            local previous = window.active
            window.active  = tab

            for index, other in ipairs(window.tabs) do
                local shown = other == tab
                other.wrap.Parent = shown and plate or holder
                other.wrap.LayoutOrder = 3

                if not shown then
                    Apply(other.wrap, "Tab", { GroupTransparency = 1 }, false)     -- waiting tabs are invisible until they arrive
                end

                -- The buttons are one surface, and the pill is what says which of them is showing: the
                -- swap lives in the label and in where the pill has been sent, not in the button's fill.
                other.button.BackgroundColor3       = Theme.Row
                other.button.BackgroundTransparency = Theme.RowAlpha
                Motion.Play(other.label, "Tab", { TextColor3 = Theme[shown and "Invert" or "Text"] })

                if shown then
                    Motion.Follow(pill, "Position", TabCell(index))                -- a decay, so a switch during a switch carries on
                    if previous ~= tab then
                        Show(other)
                    end
                end
            end
            body:Cap()                                                               -- the tab arriving is measured as it arrives
        end

        tab.button.MouseButton1Click:Connect(Focus)
        window.tabs[#window.tabs + 1] = tab

        -- a single tab needs no strip; with two or more the host carrying the pill and the buttons comes
        -- into the plate, and in between it waits inside the holder so Destroy still reaches it
        host.Parent = #window.tabs > 1 and plate or holder
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

        Motion.Destroy()
        Focus.Reset()
        HideTooltip()

        for flag in pairs(MonoUI.Flags) do
            MonoUI.Flags[flag] = nil
        end

        -- every plate lives in the one gui, so the app goes together
        local gui  = App.gui
        local blur = App.blur

        UnregisterSurface(window)
        StopRain()
        table.clear(surfaceWants)

        App.gui      = nil
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
        table.clear(ToastStacks)                                                  -- the stack went with the gui
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

    -- the hide key, and the hint that names it
    local key = settings.ToggleKey or Enum.KeyCode.RightControl
    window.settings.ToggleKey = key
    hint.Text = settings.Hint or (key and (string.upper(tostring(key.Name)) .. " TO HIDE") or "NO TOGGLE KEY")
    window.connections[#window.connections + 1] = UserInput.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode == key then
            window:Toggle()
        end
    end)

    window:SetVisible(window.visible)
    window:SetStatus("READY")

    MonoUI.Window = window
    return window
end

--=== export ================================================================

-- Everything a script needs to lay itself out the way Stretcher does.
MonoUI.Theme     = Theme
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

return MonoUI
