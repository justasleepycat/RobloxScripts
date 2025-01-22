-- local VirtualKeyCodes = loadstring(game:HttpGet("https://raw.githubusercontent.com/justasleepycat/RobloxScripts/refs/heads/main/VirtualKeyCodes.lua"))()
local VirtualKeyCodes = {
    [0x01] = "VK_LBUTTON",       -- Left mouse button
    [0x02] = "VK_RBUTTON",       -- Right mouse button
    [0x03] = "VK_CANCEL",        -- Control-break processing
    [0x04] = "VK_MBUTTON",       -- Middle mouse button (three-button mouse)
    [0x05] = "VK_XBUTTON1",      -- X1 mouse button
    [0x06] = "VK_XBUTTON2",      -- X2 mouse button
    [0x08] = "VK_BACK",          -- BACKSPACE key
    [0x09] = "VK_TAB",           -- TAB key
    [0x0C] = "VK_CLEAR",         -- CLEAR key
    [0x0D] = "VK_RETURN",        -- ENTER key
    [0x10] = "VK_SHIFT",         -- SHIFT key
    [0x11] = "VK_CONTROL",       -- CTRL key
    [0x12] = "VK_MENU",          -- ALT key
    [0x13] = "VK_PAUSE",         -- PAUSE key
    [0x14] = "VK_CAPITAL",       -- CAPS LOCK key
    [0x15] = "VK_KANA",          -- IME Kana mode
    [0x17] = "VK_JUNJA",         -- IME Junja mode
    [0x18] = "VK_FINAL",         -- IME final mode
    [0x19] = "VK_HANJA",         -- IME Hanja mode
    [0x1B] = "VK_ESCAPE",        -- ESC key
    [0x1C] = "VK_CONVERT",       -- IME convert
    [0x1D] = "VK_NONCONVERT",    -- IME nonconvert
    [0x1E] = "VK_ACCEPT",        -- IME accept
    [0x1F] = "VK_MODECHANGE",    -- IME mode change request
    [0x20] = "VK_SPACE",         -- SPACEBAR
    [0x21] = "VK_PRIOR",         -- PAGE UP key
    [0x22] = "VK_NEXT",          -- PAGE DOWN key
    [0x23] = "VK_END",           -- END key
    [0x24] = "VK_HOME",          -- HOME key
    [0x25] = "VK_LEFT",          -- LEFT ARROW key
    [0x26] = "VK_UP",            -- UP ARROW key
    [0x27] = "VK_RIGHT",         -- RIGHT ARROW key
    [0x28] = "VK_DOWN",          -- DOWN ARROW key
    [0x29] = "VK_SELECT",        -- SELECT key
    [0x2A] = "VK_PRINT",         -- PRINT key
    [0x2B] = "VK_EXECUTE",       -- EXECUTE key
    [0x2C] = "VK_SNAPSHOT",      -- PRINT SCREEN key
    [0x2D] = "VK_INSERT",        -- INS key
    [0x2E] = "VK_DELETE",        -- DEL key
    [0x2F] = "VK_HELP",          -- HELP key

    -- Numeric keys
    [0x30] = "VK_0",
    [0x31] = "VK_1",
    [0x32] = "VK_2",
    [0x33] = "VK_3",
    [0x34] = "VK_4",
    [0x35] = "VK_5",
    [0x36] = "VK_6",
    [0x37] = "VK_7",
    [0x38] = "VK_8",
    [0x39] = "VK_9",

    -- Alphabet keys
    [0x41] = "VK_A",
    [0x42] = "VK_B",
    [0x43] = "VK_C",
    [0x44] = "VK_D",
    [0x45] = "VK_E",
    [0x46] = "VK_F",
    [0x47] = "VK_G",
    [0x48] = "VK_H",
    [0x49] = "VK_I",
    [0x4A] = "VK_J",
    [0x4B] = "VK_K",
    [0x4C] = "VK_L",
    [0x4D] = "VK_M",
    [0x4E] = "VK_N",
    [0x4F] = "VK_O",
    [0x50] = "VK_P",
    [0x51] = "VK_Q",
    [0x52] = "VK_R",
    [0x53] = "VK_S",
    [0x54] = "VK_T",
    [0x55] = "VK_U",
    [0x56] = "VK_V",
    [0x57] = "VK_W",
    [0x58] = "VK_X",
    [0x59] = "VK_Y",
    [0x5A] = "VK_Z",

    -- Numpad keys
    [0x60] = "VK_NUMPAD0",
    [0x61] = "VK_NUMPAD1",
    [0x62] = "VK_NUMPAD2",
    [0x63] = "VK_NUMPAD3",
    [0x64] = "VK_NUMPAD4",
    [0x65] = "VK_NUMPAD5",
    [0x66] = "VK_NUMPAD6",
    [0x67] = "VK_NUMPAD7",
    [0x68] = "VK_NUMPAD8",
    [0x69] = "VK_NUMPAD9",
    [0x6A] = "VK_MULTIPLY",
    [0x6B] = "VK_ADD",
    [0x6C] = "VK_SEPARATOR",
    [0x6D] = "VK_SUBTRACT",
    [0x6E] = "VK_DECIMAL",
    [0x6F] = "VK_DIVIDE",

    -- Function keys
    [0x70] = "VK_F1",
    [0x71] = "VK_F2",
    [0x72] = "VK_F3",
    [0x73] = "VK_F4",
    [0x74] = "VK_F5",
    [0x75] = "VK_F6",
    [0x76] = "VK_F7",
    [0x77] = "VK_F8",
    [0x78] = "VK_F9",
    [0x79] = "VK_F10",
    [0x7A] = "VK_F11",
    [0x7B] = "VK_F12",

    -- Additional keys
    [0x90] = "VK_NUMLOCK",       -- NUM LOCK key
    [0x91] = "VK_SCROLL",        -- SCROLL LOCK key
}

function VirtualKeyCodes:GetCurrentPressedKeys()
	local keys = {} 

    for i,v in pairs(VirtualKeyCodes) do
		pcall(function()
			if typeof(i) == "number" and iskeydown(i) then
	            table.insert(keys, v)
			end	
		end)
	end

    return keys
end

-- Functions
-- VirtualKeyCodes:GetCurrentPressedKeys() -> table

if false then
repeat task.wait()
    if table.find(VirtualKeyCodes:GetCurrentPressedKeys(), "VK_LBUTTON") then
		break
	end
    if game:GetService("UserInputService"):IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
        break
    end
until false
print("done")
end

return VirtualKeyCodes


