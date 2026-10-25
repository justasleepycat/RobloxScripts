-- MonoUI.Showcase.lua =======================================================
-- Every element the library has, in every state it has, in one window. It is not part of the library and
-- nothing in it is used by it: it exists to be looked at after a change.
--
-- How to run it, once MonoUI has been loaded:
--     local MonoUI = loadstring(readfile("MonoUI.lua"))()
--     loadstring(readfile("MonoUI.Showcase.lua"))()(MonoUI)
--
-- It is handed the library as an argument; if it is instead a global in your executor, that works too.
--
-- The states that are interactions - hover, press, keyboard focus - cannot be posed by a script, so this
-- tells you to do them rather than faking them: hover the rows, press them, and tab through the page. The
-- states that are properties - ready, idle, busy, warning, error, disabled - are all posed, from the
-- States tab.
--
-- On a phone there is no hover and no tab key, and the library lays itself out for touch on its own: the
-- rows are a fingertip tall, the body scrolls, the dropdowns open upward near the bottom edge, and the
-- title bar carries the hide button in place of Right Control. Run it on a phone to see that layout, or
-- force it on a desktop with MonoUI:SetTouch(true) before this file - and check the window comes back
-- from its chip, since that is the only way back when the hide button is the only way out.

local MonoUI = ... or MonoUI                                                        -- handed in, or left as a global
assert(MonoUI ~= nil and type(MonoUI.CreateWindow) == "function", "load MonoUI before the showcase")

MonoUI.Debug = true                                                                -- say so when a property does not exist

local window = MonoUI:CreateWindow {
    Name    = "MONOUI SHOWCASE",
    Width   = 720,
    Hint    = "RIGHT CONTROL TO HIDE",
    ConfigurationSaving = { Enabled = true, FileName = "MonoUI-Showcase" },
}

-- 1. every element there is, at rest
local elements = window:CreateTab("Elements")
elements:CreateSection("Input")

elements:CreateToggle {
    Name = "A switch", CurrentValue = true, Flag = "showcase.switch",
    Description = "A switch, at rest and on",
}
elements:CreateSlider {
    Name = "A slider", Min = 0, Max = 100, CurrentValue = 40, Increment = 5, Suffix = "%",
    Flag = "showcase.slider", Description = "Drag the fill, or click the value to type one",
}
elements:CreateDropdown {
    Name = "A dropdown", Options = { "One", "Two", "Three", "Four", "Five", "Six", "Seven" },
    CurrentOption = "Three", Flag = "showcase.dropdown",
    Description = "Long lists scroll, and the list opens upward when there is no room below",
}
elements:CreateInput {
    Name = "An input", PlaceholderText = "type here", OnEnter = true,
    Flag = "showcase.input", Description = "Enter commits, Escape puts back what was there",
}
elements:CreateKeybind {
    Name = "A keybind", CurrentKeyCode = Enum.KeyCode.F, Mode = "Toggle",
    Flag = "showcase.keybind", Description = "Click to listen, Escape to cancel, Backspace to clear",
}
elements:CreateMultiSelect {
    Name = "A multi select", Options = { "Alpha", "Beta", "Gamma" }, CurrentOption = { "Alpha" },
    Flag = "showcase.multi", Description = "The list stays open while you choose",
}

elements:CreateSection("Output")

elements:CreateLabel { Name = "A label", Text = "A label says one thing and sizes itself to it." }
elements:CreateParagraph {
    Name = "A paragraph",
    Text = "A paragraph takes the longer thought, in the smaller muted type, and wraps to whatever width it is given.",
}
elements:CreateProgress { Name = "A progress bar", Value = 0.4, Flag = "showcase.progress" }
elements:CreateProgress { Name = "A bar with no end in sight", Value = true }
elements:CreateButton {
    Name = "A button",
    Callback = function()
        MonoUI:Notify("A button was pressed", "info")
    end,
}

-- 2. every state a property can hold
local states = window:CreateTab("States")
states:CreateSection("On the window")

local function pose(name, message)
    return function()
        window:SetState(name, message)
    end
end

states:CreateButton { Name = "Ready",   Callback = pose("ready") }
states:CreateButton { Name = "Idle",    Callback = pose("idle") }
states:CreateButton { Name = "Busy",    Callback = pose("busy") }
states:CreateButton { Name = "Warning", Callback = pose("warning", "Two of the routes overlap") }
states:CreateButton { Name = "Error",   Callback = pose("error", "No route to host") }

states:CreateSection("On a control")
local switchedOff = states:CreateToggle {
    Name = "Disabled, and saying why", CurrentValue = false, Flag = "showcase.off",
    Description = "Or this description, which is what a control with something to explain carries",
}
switchedOff:SetEnabled(false, "Only while the game is running")

states:CreateSection("Messages")
states:CreateButton { Name = "Success", Callback = function() MonoUI:Notify("Saved", "success") end }
states:CreateButton { Name = "Info",    Callback = function() MonoUI:Notify("Saved with the last change", "info") end }
states:CreateButton { Name = "Warning toast", Callback = function() MonoUI:Notify("Two of the routes overlap", "warning") end }
states:CreateButton { Name = "Error toast",   Callback = function() MonoUI:Notify("No route to host", "error") end }

-- 3. waiting, and nothing yet
local loading = window:CreateTab("Loading")
loading:CreateSection("While it is coming")
local skeleton = MonoUI:Skeleton(loading.content, 4)
loading:CreateButton {
    Name = "Stop the shimmer",
    Callback = function()
        skeleton.Stop()
    end,
}
loading:CreateSection("When there is nothing")
MonoUI:Empty(loading.content, "No routes saved yet", {
    Name = "Add a route",
    Run  = function()
        MonoUI:Notify("Nothing to add - this is the showcase", "info")
    end,
})

-- 4. the same page given more or less room, and said in more or less ink
local density = window:CreateTab("Density")
density:CreateSection("Room")
density:CreateButton { Name = "Comfortable", Callback = function() MonoUI:SetDensity("comfortable") end }
density:CreateButton { Name = "Compact",     Callback = function() MonoUI:SetDensity("compact") end }
density:CreateButton { Name = "Touch",       Callback = function() MonoUI:SetDensity("touch") end }

density:CreateSection("Ink")
density:CreateButton { Name = "Glass",    Callback = function() MonoUI:SetLegibility("Glass") end }
density:CreateButton { Name = "Balanced", Callback = function() MonoUI:SetLegibility("Balanced") end }
density:CreateButton { Name = "Solid",    Callback = function() MonoUI:SetLegibility("Solid") end }
density:CreateButton { Name = "High contrast", Callback = function() MonoUI:SetHighContrast(true) end }
density:CreateSlider {
    Name = "UI scale", Min = 0.5, Max = 2, Increment = 0.05, CurrentValue = 1,
    Callback = function(value)
        MonoUI:SetScale(value)
    end,
}

-- 5. what all of it costs
local costs = window:CreateTab("Costs")
costs:CreateSection("Budgets")
costs:CreateLabel {
    Name = "Budget note",
    Text = "A window should stay under a few hundred instances, and the driver should let go of the frame when nothing is moving.",
}
costs:CreateButton { Name = "Show the overlay", Callback = function() MonoUI:Overlay(true) end }
costs:CreateButton { Name = "Hide the overlay", Callback = function() MonoUI:Overlay(false) end }
costs:CreateButton {
    Name = "Count it",
    Callback = function()
        local stats = MonoUI:Stats()
        MonoUI:Notify(string.format("%d instances, %d tracks, %d drops", stats.Instances, stats.Tracks, stats.Rain), "info", 5)
    end,
}

window:SetState("ready")
MonoUI:Notify("Hover the rows, press them, and tab through the page", "info", 6)

return window
