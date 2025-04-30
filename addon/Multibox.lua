SLASH_MBOX1 = '/mbox';
-- Frame for drawing
local frame = CreateFrame("Frame", nil, UIParent)
frame:SetPoint("TOPLEFT", 0, 0)
frame:SetSize(1, 1)

-- Texture to draw pixel color
local texture = frame:CreateTexture()
texture:SetPoint("TOPLEFT", 0, 0)
texture:SetSize(1, 1)
texture:SetTexture("Interface\\AddOns\\Multibox\\Smooth.tga")

-- Draws a single pixel with given RGB values (0-1 range)
local function drawPixel(r, g, b)
    texture:SetVertexColor(r, g, b)
    frame:SetFrameStrata("HIGH")
end

-- OnUpdate loop to draw the key value as a pixel color
local timeElapsed = 0
frame:HookScript("OnUpdate", function(self, elapsed)
    timeElapsed = timeElapsed + elapsed
    if (timeElapsed > 0.1) then
        timeElapsed = 0

        local key, target = RestoShaman.getRestoShamanMacro()
        -- Normalize the key to a value between 0 and 1 using 255 as the max for 8-bit color
        local r = key / 255
        local g = target / 255
        drawPixel(r, g, 0)
    end
end)

-- Helper: Initialize keybinds to target raid members (1-40) using Numpad keys and modifiers
local function initTargettingKeybinds()
    for i = 1, 40 do
        local numpadIndex = math.floor((i - 1) / 4)
        local modIndex = (i - 1) % 4

        -- Determine modifier
        local modifier = ""
        if modIndex == 1 then
            modifier = "CTRL-"
        elseif modIndex == 2 then
            modifier = "SHIFT-"
        elseif modIndex == 3 then
            modifier = "ALT-"
        end

        -- Numpad key (0 to 9)
        local numpadKey = numpadIndex

        -- Construct binding string
        local bindingKey = modifier .. "NUMPAD" .. numpadKey

        -- Create a unique button for this target
        local buttonName = "TargetButton_" .. i
        local button = CreateFrame("Button", buttonName, UIParent, "SecureActionButtonTemplate")
        button:SetAttribute("type", "macro")
        SetBindingClick(bindingKey, buttonName)
        button:SetAttribute("macrotext", "/target raid" .. i)

        -- Bind the key to this button
        end
end

function SlashCmdList.MBOX_INIT(msg, editBox) -- 4.

end
local function init(msg, editBox)
    DEFAULT_CHAT_FRAME:AddMessage("INIT");
    initTargettingKeybinds()
    RestoShaman.initRestoShamanKeybinds()
end
SlashCmdList["MBOX"] = init; -- Also a valid assignment strategy
