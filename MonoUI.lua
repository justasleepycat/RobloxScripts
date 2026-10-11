--[[ MonoUI ====================================================================
    The monochrome window from Stretcher.lua, extracted into a reusable library.

    Same palette, type scale, motion, spacing and gethui-first parenting as the window it
    came from. Every layout capability that file uses is available here, so a script can be
    laid out exactly the way Stretcher is - several independent plates, each with its own
    title bar and drag - or use the higher-level tabs and elements:

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

local MonoUI = {}
MonoUI.Debug = false

--=== theme =================================================================

local Theme = {
    Surface      = Color3.fromRGB(10, 10, 10),                                       -- window plate
    Header       = Color3.fromRGB(17, 17, 17),                                       -- title bar
    Row          = Color3.fromRGB(20, 20, 20),                                       -- inactive buttons
    RowHover     = Color3.fromRGB(34, 34, 34),                                       -- hovered buttons
    Well         = Color3.fromRGB(15, 15, 15),                                       -- inputs / selects
    Text         = Color3.fromRGB(242, 242, 242),                                    -- primary text
    Muted        = Color3.fromRGB(146, 146, 146),                                    -- secondary text
    Line         = Color3.fromRGB(58, 58, 58),                                       -- strokes
    Outline      = Color3.fromRGB(104, 104, 104),                                    -- window outline
    Invert       = Color3.fromRGB(14, 14, 14),                                       -- text on a white pill
    WindowAlpha  = 0.12,                                                             -- window plate opacity
    PanelAlpha   = 0.30,                                                             -- inner cards opacity
    RowAlpha     = 0.15,                                                             -- buttons / wells opacity
    OutlineAlpha = 0.30,                                                             -- outline transparency
    Radius       = 12,                                                               -- window corner radius
    RowRadius    = 8,                                                                -- inner corner radius
    Space        = { Micro = 4, Gap = 8, Pad = 12, Section = 16, Block = 22 },        -- one spacing scale
    Type         = { Title = 15, Heading = 11, Label = 13, Body = 12, Support = 9 },  -- named sizes
    Width        = 720,                                                              -- default plate width
    Blur         = 12,                                                               -- backdrop blur, 0 for none
    VisibleRows  = 5,                                                                -- options shown before a dropdown scrolls
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

-- Applies theme shorthands so every element stays on the same palette:
--   Color = "Surface"  Corner = "RowRadius"  Stroke = "Line"
--   Padding = { 10, 10, 10, 10 }             Gap = { Padding = 6, ... }
local function Sticker(instance, properties)
    properties = properties or {}

    local color   = properties.Color
    local corner  = properties.Corner
    local stroke  = properties.Stroke
    local padding = properties.Padding
    local gap     = properties.Gap

    if color ~= nil and Theme[color] then
        instance.BackgroundColor3 = Theme[color]
    end
    if properties.Alpha ~= nil then
        instance.BackgroundTransparency = properties.Alpha
    end
    if corner ~= nil then
        local radius = Theme.RowRadius
        if type(corner) == "string" then
            radius = UDim.new(0, Theme[corner] or Theme.RowRadius)                      -- palette key -> pixel radius
        elseif type(corner) == "number" then
            radius = corner < 1 and UDim.new(corner, 0) or UDim.new(0, corner)          -- 0.5 -> pill, 12 -> pixels
        end
        Element {
            ClassName    = "UICorner",
            Parent       = instance,
            Name         = "Corner",
            CornerRadius = radius,
        }
    end
    if stroke ~= nil then
        Element {
            ClassName       = "UIStroke",
            Parent          = instance,
            Name            = "Stroke",
            Color           = Theme[stroke] or Theme.Line,
            Thickness       = properties.StrokeWidth or 1,
            Transparency    = properties.StrokeAlpha or 0.35,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        }
    end
    if padding ~= nil then
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
    if gap ~= nil then
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
    return instance
end

local function Fonted(instance, bold)
    instance.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
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

-- One motion language for the whole window, so transitions read as one system instead of
-- being chosen per call site. A new tween on the same instance and channel cancels the old
-- one, which is what makes hover-out interrupt hover-in and rapid toggling settle on the
-- last request. Motion = false in the settings drops the movement, never the feedback.
local Motion = {}

Motion.Specs = {
    Hover  = { Time = 0.12, Style = Enum.EasingStyle.Quad,  Direction = Enum.EasingDirection.Out },
    Press  = { Time = 0.08, Style = Enum.EasingStyle.Quad,  Direction = Enum.EasingDirection.Out },
    Switch = { Time = 0.16, Style = Enum.EasingStyle.Quad,  Direction = Enum.EasingDirection.Out },
    Open   = { Time = 0.15, Style = Enum.EasingStyle.Cubic, Direction = Enum.EasingDirection.Out },
    Close  = { Time = 0.11, Style = Enum.EasingStyle.Quad,  Direction = Enum.EasingDirection.In  },
    Panel  = { Time = 0.18, Style = Enum.EasingStyle.Cubic, Direction = Enum.EasingDirection.Out },
}

local channels = {}
local motionOn = true

local function Tweener()
    local ok, service = pcall(function()
        return game:GetService("TweenService")
    end)
    if not ok or service == nil then
        return nil
    end
    return service
end

-- With no tween service, or with motion switched off, the end state is applied at once:
-- every state change stays visible, only the movement is dropped.
local function Snap(instance, properties)
    for key, value in pairs(properties) do
        pcall(function()
            instance[key] = value
        end)
    end
end

function Motion.Play(instance, channel, properties)
    if instance == nil then
        return nil
    end

    local service = motionOn and Tweener() or nil
    local spec    = Motion.Specs[channel] or Motion.Specs.Hover
    if service == nil or service.Create == nil then
        Snap(instance, properties)
        return nil
    end

    channels[instance] = channels[instance] or {}
    local open = channels[instance]
    if open[channel] ~= nil then
        pcall(function()
            open[channel]:Cancel()                                                      -- replace, never stack
        end)
    end

    local ok, tween = pcall(function()
        return service:Create(instance, TweenInfo.new(spec.Time, spec.Style, spec.Direction), properties)
    end)
    if not ok or tween == nil then
        Snap(instance, properties)
        return nil
    end

    open[channel] = tween
    pcall(function()
        tween:Play()
    end)
    return tween
end

function Motion.Destroy()
    for instance, open in pairs(channels) do
        for _, tween in pairs(open) do
            pcall(function()
                tween:Cancel()
            end)
        end
    end
    channels = {}
    return true
end

--=== layout ================================================================

-- Exploit UI belongs in the hidden UI container, not the player's PlayerGui, so game
-- scripts cannot find it: gethui first, then the older fallbacks.
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

-- A full-width bar with the knob riding left and the caption clearing it in both states.
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
    }, { Color = properties.Color or "Row", Alpha = Theme.RowAlpha, Corner = "RowRadius", Stroke = "Line" })

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
        local position = state and UDim2.new(1, -23, 0.5, -10) or UDim2.new(0, 3, 0.5, -10)
        if animate then
            Motion.Play(knob, "Switch", { Position = position })
        else
            knob.Position = position
        end

        caption.TextColor3     = Theme[state and "Invert" or "Text"]
        knob.BackgroundColor3  = Theme[state and "Invert" or "Muted"]
        track.BackgroundColor3 = Theme[state and "Text" or "Row"]
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
    }, { Color = "Well", Alpha = Theme.RowAlpha, Corner = "RowRadius", Stroke = "Line" })

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
    }, { Color = "Surface", Alpha = 0.05, Corner = "RowRadius", Stroke = "Line", Padding = { 4, 4, 4, 4 } })

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
        }, { Color = "Well", Alpha = 1, Corner = "RowRadius" })

        local label = Texted(entry, {
            Text     = option,
            Size     = Theme.Type.Body,
            Position = UDim2.fromOffset(8, 0),
            Size2    = UDim2.new(1, -16, 1, 0),
            ZIndex   = 52,
        })
        entries[option] = { Frame = entry, label = label }

        entry.MouseEnter:Connect(function()
            Motion.Play(entry, "Hover", { BackgroundColor3 = Theme.RowHover, BackgroundTransparency = Theme.RowAlpha })
        end)
        entry.MouseLeave:Connect(function()
            Motion.Play(entry, "Hover", { BackgroundColor3 = Theme.Well, BackgroundTransparency = 1 })
        end)
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
-- fires when Enter is pressed, with it off on every keystroke.
local function Input(properties)
    local box = Sticker(Element {
        ClassName         = "TextBox",
        Parent            = properties.Parent,
        Name              = properties.Name or "Input",
        Size              = properties.Size or UDim2.new(0, properties.Width or 50, 0, 26),
        Position          = properties.Position,
        ClearTextOnFocus  = false,
        Text              = "",
        TextSize          = Theme.Type.Body,
        TextColor3        = Theme.Text,
        TextXAlignment    = properties.X or Enum.TextXAlignment.Center,
        PlaceholderText   = properties.PlaceholderText or "0",
        PlaceholderColor3 = Theme.Muted,
        LayoutOrder       = properties.Order or 1,
        ZIndex            = properties.ZIndex or 2,
    }, { Color = "Well", Alpha = Theme.RowAlpha, Corner = "RowRadius", Stroke = "Line" })
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

    return {
        Frame = box,
        Set   = function(value)
            box.Text = tostring(value)
        end,
        Get   = function()
            return box.Text
        end,
    }
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
    }, { Color = properties.Color or "Row", Alpha = Theme.RowAlpha, Corner = "RowRadius", Stroke = properties.Stroke or "Line" })

    Texted(button, {
        Text   = string.upper(properties.Caption or properties.Text or "BUTTON"),
        Size   = properties.TextSize or Theme.Type.Heading,
        X      = Enum.TextXAlignment.Center,
        Tint   = properties.Tint or "Text",
        ZIndex = (properties.ZIndex or 2) + 1,
    })

    button.MouseEnter:Connect(function()
        Motion.Play(button, "Hover", { BackgroundColor3 = Theme[properties.Hover or "RowHover"] })
    end)
    button.MouseLeave:Connect(function()
        Motion.Play(button, "Hover", { BackgroundColor3 = Theme[properties.Color or "Row"], BackgroundTransparency = Theme.RowAlpha })
    end)
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

    Element {
        ClassName              = "Frame",
        Parent                 = header,
        Name                   = "Divider",
        BackgroundColor3       = Theme.Line,
        BackgroundTransparency = 0.4,
        BorderSizePixel        = 0,
        Position               = UDim2.fromOffset(0, 16),
        Size                   = UDim2.new(1, 0, 0, 1),
        ZIndex                 = 3,
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

        local element = Input {
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
        element.Frame.AnchorPoint = Vector2.new(1, 0.5)

        RegisterFlag(settings.Flag, {
            Type = "Input",
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

local App = { gui = nil, blur = nil, blurOwned = false, connections = {}, windows = {}, plates = {} }

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

    local existing = Lighting:FindFirstChild("MonoUIBlur")
    App.blurOwned = existing == nil                                                             -- only ever remove what this made
    App.blur = existing or Element {
        ClassName = "BlurEffect",
        Parent    = Lighting,
        Name      = "MonoUIBlur",
        Size      = settings.Blur or Theme.Blur,
    }
    return App.blur
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
        Color       = "Surface",
        Alpha       = Theme.WindowAlpha,
        Corner      = "Radius",
        Stroke      = "Outline",
        StrokeAlpha = Theme.OutlineAlpha,
        Padding     = { Theme.Space.Pad, Theme.Space.Pad, Theme.Space.Pad, Theme.Space.Pad },
        Gap         = { Padding = Theme.Space.Gap },
    })

    local bar = Sticker(Element {
        ClassName   = "Frame",
        Parent      = plate,
        Name        = "Bar",
        Size        = UDim2.new(1, 0, 0, 34),
        LayoutOrder = 1,
    }, { Color = "Header", Alpha = Theme.PanelAlpha, Corner = "RowRadius", Stroke = "Line" })

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
    motionOn = settings.Motion ~= false

    local plate, bar, hint, status = CreatePlateFrame(settings, #App.plates + 1)

    local object = {
        connections = {},
        dragThreshold = settings.DragThreshold or 3,
        plate = plate,
        bar = bar,
        status = status,
        settings = settings,
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

    EnsureBlur(settings)
    Dragging(object, plate, bar)

    hint.Text = settings.Hint or (settings.ToggleKey and (string.upper(tostring(settings.ToggleKey.Name)) .. " TO HIDE") or "")

    function object:SetStatus(text, tint)
        status.label.Text    = tostring(text or "")
        status.dot.BackgroundColor3 = tint or Theme.Muted
    end

    function object:SetVisible(visible)
        plate.Visible = visible and true or false
        return plate.Visible
    end

    function object:Destroy()
        for _, connection in ipairs(object.connections) do
            pcall(function()
                connection:Disconnect()
            end)
        end
        table.clear(object.connections)
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
    motionOn          = settings.Motion ~= false

    local name = tostring(settings.Name or "MONOUI")
    EnsureGui(settings.GuiName or name)
    EnsureBlur(settings)

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
    }, { Color = "Surface", Alpha = Theme.WindowAlpha, Corner = "RowRadius", Stroke = "Outline", StrokeAlpha = Theme.OutlineAlpha })

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
        window.visible    = visible and true or false
        plate.Visible     = window.visible
        chip.Visible      = not window.visible
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
                other.button.BackgroundTransparency = active and 0 or Theme.RowAlpha
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
        local blur = App.blurOwned and App.blur or nil
        App.gui      = nil
        App.blur     = nil
        App.blurOwned = false
        App.windows  = {}
        App.plates   = {}
        if gui ~= nil then
            pcall(function()
                gui:Destroy()
            end)
        end
        if blur ~= nil then
            pcall(function()
                blur:Destroy()
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

return MonoUI
