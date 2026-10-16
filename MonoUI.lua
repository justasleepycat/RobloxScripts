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
-- appears. The Scale is looked up by name: a plate built by hand without one is simply left alone,
-- which is what keeps this optional for anyone laying out their own surface.
local function Reveal(plate)
    local scale = plate:FindFirstChild("Scale")
    if scale == nil then return end
    scale.Scale = Theme.RevealScale
    Motion.Play(scale, "Open", { Scale = 1 })
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
-- Movement is measured as a mouse delta from where the plate already is, never against
-- AbsolutePosition - that one includes the GUI inset while Position does not, which is what
-- makes a naive drag jump on its first frame. A press only becomes a drag after the
-- threshold.
local function Dragging(owner, target, ...)
    local drag    = { active = false, moved = false, start = Vector2.zero, base = nil }
    local handles = { ... }

    for _, handle in ipairs(handles) do
        owner.connections[#owner.connections + 1] = handle.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                drag.active = true
                drag.moved  = false
                drag.start  = Vector2.new(input.Position.X, input.Position.Y)
                drag.base   = target.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        drag.active = false
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

        local camera  = Workspace.CurrentCamera
        local screen  = camera and camera.ViewportSize or Vector2.new(1920, 1080)
        local wantedX = drag.base.X.Offset + stepX
        local wantedY = drag.base.Y.Offset + stepY
        target.Position = UDim2.new(
            drag.base.X.Scale, math.clamp(wantedX, 8 - target.AbsoluteSize.X + 60, screen.X - 60),
            drag.base.Y.Scale, math.clamp(wantedY, 8, screen.Y - 40)
        )
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
        Size2    = UDim2.new(0.6, -14, 1, 0),
        ZIndex   = 3,
    })

    local menu = Sticker(Element {
        ClassName           = "ScrollingFrame",
        Parent              = row,
        Name                = "Menu",
        Size                = UDim2.new(1, 0, 0, (math.min(#options, properties.VisibleRows or Theme.VisibleRows) * 24) + 8),
        Position            = UDim2.new(0, 0, 1, 4),
        BorderSizePixel     = 0,
        ScrollBarThickness  = 4,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize          = UDim2.new(0, 0, 0, 0),
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
            Size            = UDim2.new(1, 0, 0, 22),
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

    row.MouseButton1Click:Connect(function()
        menu.Visible = not menu.Visible
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

    button.MouseButton1Click:Connect(function()
        if properties.OnClick then
            properties.OnClick()
        end
    end)

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
local App = { gui = nil, blur = nil, rain = nil, rainConnection = nil, streaks = {}, connections = {}, windows = {}, plates = {}, surfaces = {},
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
    local target = UserInput:GetMouseLocation() - layer.AbsolutePosition
    App.lens     = (App.lens or target):Lerp(target, 1 - math.exp(-rain.Warp.Follow * step))

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
        visible = not settings.StartHidden,
    }
    App.windows[#App.windows + 1] = window

    local plate, bar, hint, status = CreatePlateFrame(settings, #App.windows)
    window.plate = plate
    window.bar = bar
    window.status = status

    local strip = Element {
        ClassName              = "Frame",
        Parent                 = nil,                                             -- only parented once a second tab exists
        Name                   = "Tabs",
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, 0, 28),
        LayoutOrder            = 2,
    }
    Element {
        ClassName             = "UIGridLayout",
        Parent                = strip,
        Name                  = "Columns",
        CellSize              = UDim2.new(0, 132, 0, 28),
        CellPadding           = UDim2.new(0, 6, 0, 0),
        FillDirection         = Enum.FillDirection.Horizontal,
        FillDirectionMaxCells = 6,
        SortOrder             = Enum.SortOrder.LayoutOrder,
    }
    window.strip = strip

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
            for index, other in ipairs(window.tabs) do
                local active = other == tab
                other.content.Parent = active and plate or holder
                other.content.LayoutOrder = 3
                other.button.BackgroundColor3 = Theme[active and "Text" or "Row"]
                other.button.BackgroundTransparency = active and Theme.SwitchOnAlpha or Theme.RowAlpha
                other.label.TextColor3 = Theme[active and "Invert" or "Text"]
            end
        end

        tab.button.MouseButton1Click:Connect(Focus)
        window.tabs[#window.tabs + 1] = tab

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

        Motion.Destroy()

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
