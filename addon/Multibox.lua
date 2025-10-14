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
local getNextMacro = RestoShaman.getRestoShamanMacro;
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

        local key, target = getNextMacro()
        -- Normalize the key to a value between 0 and 1 using 255 as the max for 8-bit color
        local r = key / 255
        local g = target / 255
        -- DEFAULT_CHAT_FRAME:AddMessage(target);
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
        if i <= 4 then
            button:SetAttribute("macrotext", "/target party" .. i .. "\r\n/target raid" .. i)
        elseif i == 5 then
            button:SetAttribute("macrotext", "/target player")
        else
            button:SetAttribute("macrotext", "/target raid" .. i)
        end

        -- Bind the key to this button
    end
end

function SlashCmdList.MBOX_INIT(msg, editBox) -- 4.

end
local function init(msg, editBox)
    initTargettingKeybinds();
    local playerClass = UnitClass("player");
    if playerClass == "Paladin" then
        _, _, _, _, currentRank = GetTalentInfo(3, 26)
        if currentRank == 1 then
            DEFAULT_CHAT_FRAME:AddMessage("INIT RETRI PALADIN");
            RetriPaladin.initRetriPaladinKeybinds();
            getNextMacro = RetriPaladin.getRetriPaladinMacro;
        end
        _, _, _, _, currentRank = GetTalentInfo(1, 26)
        if currentRank == 1 then
            DEFAULT_CHAT_FRAME:AddMessage("INIT HOLY PALADIN");
            HolyPaladin.initHolyPaladinKeybinds();
            getNextMacro = HolyPaladin.getHolyPaladinMacro;
        end
    elseif playerClass == "Shaman" then
        DEFAULT_CHAT_FRAME:AddMessage("INIT RESTO SHAMAN");
        RestoShaman.initRestoShamanKeybinds();
        getNextMacro = RestoShaman.getRestoShamanMacro;
    elseif playerClass == "Druid" then
        _, _, _, _, currentRank = GetTalentInfo(1, 28);
        if currentRank == 1 then
            DEFAULT_CHAT_FRAME:AddMessage("INIT BALANCE DRUID");
            BalanceDruid.initBalanceDruidKeybinds();
            getNextMacro = BalanceDruid.getBalanceDruidMacro;
        end
        -- -- Feral cat - Feral Aggression rank 5
        -- _, _, _, _, currentRank = GetTalentInfo(2, 2);
        -- if currentRank == 5 then
        --     DEFAULT_CHAT_FRAME:AddMessage("INIT FERAL CAT DRUID");
        --     FeralDruid.initFeralDruidKeybinds();
        --     getNextMacro = FeralDruid.getFeralDruidMacro;
        -- end
        -- Feral bear - Thick Hide rank 3
        _, _, _, _, currentRank = GetTalentInfo(2, 5);
        if currentRank == 3 then
            DEFAULT_CHAT_FRAME:AddMessage("INIT FERAL BEAR DRUID");
            FeralBearDruid.initFeralBearDruidKeybinds();
            getNextMacro = FeralBearDruid.getFeralBearDruidMacro;
        end
        -- _, _, _, _, currentRank = GetTalentInfo(3, 27);
        -- if currentRank == 1 then
        --     DEFAULT_CHAT_FRAME:AddMessage("INIT RESTO DRUID");
        --     RestoDruid.initRestoDruidKeybinds();
        --     getNextMacro = RestoDruid.getRestoDruidMacro;
        -- end
    elseif playerClass == "Priest" then
        _, _, _, _, currentRank = GetTalentInfo(3, 27);
        if currentRank == 1 then
            DEFAULT_CHAT_FRAME:AddMessage("INIT SHADOW PRIEST");
            ShadowPriest.initShadowPriestKeybinds();
            getNextMacro = ShadowPriest.getShadowPriestMacro;
        end
    elseif playerClass == "Warlock" then
        _, _, _, _, currentRank = GetTalentInfo(2, 27);
        if currentRank == 1 then
            DEFAULT_CHAT_FRAME:AddMessage("INIT DEMONOLOGY WARLOCK");
            DemonologyWarlock.initDemonologyWarlockKeybinds();
            getNextMacro = DemonologyWarlock.getDemonologyWarlockMacro;
        end
    else
        DEFAULT_CHAT_FRAME:AddMessage("CLASS NOT SUPPORTED");
    end
end
SlashCmdList["MBOX"] = init; -- Also a valid assignment strategy
