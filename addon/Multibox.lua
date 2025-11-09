SLASH_MBOX1 = '/mbox';
local controlCommand = 0
local keysEnabled = true
local broadcastEnabled = false
-- Frame for drawing
local frame = CreateFrame("Frame", nil, UIParent)
frame:SetPoint("TOPLEFT", 0, 0)
frame:SetSize(3, 1)
frame:SetFrameStrata("HIGH")

-- Texture to draw command pixel
local commandTexture = frame:CreateTexture(nil, "ARTWORK")
commandTexture:SetPoint("TOPLEFT", 0, 0)
commandTexture:SetSize(1, 1)
commandTexture:SetTexture("Interface\\AddOns\\Multibox\\Smooth.tga")

-- Texture for sentinel pixel 1
local sentinelTexture = frame:CreateTexture(nil, "ARTWORK")
sentinelTexture:SetPoint("TOPLEFT", 1, 0)
sentinelTexture:SetSize(1, 1)
sentinelTexture:SetTexture("Interface\\AddOns\\Multibox\\Smooth.tga")

local getNextMacro = RestoShaman.getRestoShamanMacro;
-- Draws a single pixel with given RGB values (0-1 range)
local function drawPixel(r, g, b)
    commandTexture:SetVertexColor(r, g, b)
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
        local b = controlCommand / 255
        drawPixel(r, g, b)
        if controlCommand ~= 0 then
            controlCommand = 0
        end
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
    -- Initialize configuration system
    MultiboxConfig:RegisterOptions()
end

local CURRENT_SPEC = "Unsupported"
local function init(msg, editBox)
    initTargettingKeybinds();
    MultiboxGuildBank:Initialize()
    MultiboxFollow:Initialize()
    MultiboxParty:Initialize()
    MultiboxQuest:Initialize()
    
    -- Initialize configuration system
    MultiboxConfig:RegisterOptions()
    
    local playerClass = UnitClass("player");
    if playerClass == "Paladin" then
        _, _, _, _, currentRank = GetTalentInfo(3, 26)
        if currentRank == 1 then
            DEFAULT_CHAT_FRAME:AddMessage("INIT RETRI PALADIN");
            RetriPaladin.initRetriPaladinKeybinds();
            getNextMacro = RetriPaladin.getRetriPaladinMacro;
            CURRENT_SPEC = "Retribution Paladin"
            
            -- Initialize Retribution Paladin configuration
            RetriPaladinDB = RetriPaladinDB or { judgmentType = "light" }
            RetriPaladin:UpdateJudgmentMacro()
        end
        _, _, _, _, currentRank = GetTalentInfo(1, 26)
        if currentRank == 1 then
            DEFAULT_CHAT_FRAME:AddMessage("INIT HOLY PALADIN");
            HolyPaladin.initHolyPaladinKeybinds();
            getNextMacro = HolyPaladin.getHolyPaladinMacro;
            CURRENT_SPEC = "Holy Paladin"
        end
    elseif playerClass == "Shaman" then
        DEFAULT_CHAT_FRAME:AddMessage("INIT RESTO SHAMAN");
        RestoShaman.initRestoShamanKeybinds();
        getNextMacro = RestoShaman.getRestoShamanMacro;
        CURRENT_SPEC = "Restoration Shaman"
    elseif playerClass == "Druid" then
        _, _, _, _, currentRank = GetTalentInfo(1, 28);
        if currentRank == 1 then
            DEFAULT_CHAT_FRAME:AddMessage("INIT BALANCE DRUID");
            BalanceDruid.initBalanceDruidKeybinds();
            getNextMacro = BalanceDruid.getBalanceDruidMacro;
            CURRENT_SPEC = "Balance Druid"
        end
        -- -- Feral cat - Feral Aggression rank 5
        _, _, _, _, currentRank = GetTalentInfo(2, 2);
        if currentRank == 5 then
            DEFAULT_CHAT_FRAME:AddMessage("INIT FERAL CAT DRUID");
            FeralCatDruid.initFeralCatDruidKeybinds();
            getNextMacro = FeralCatDruid.getFeralCatDruidMacro;
            CURRENT_SPEC = "Feral (Cat) Druid"
        end
        -- Feral bear - Thick Hide rank 3
        _, _, _, _, currentRank = GetTalentInfo(2, 5);
        if currentRank == 3 then
            DEFAULT_CHAT_FRAME:AddMessage("INIT FERAL BEAR DRUID");
            FeralBearDruid.initFeralBearDruidKeybinds();
            getNextMacro = FeralBearDruid.getFeralBearDruidMacro;
            CURRENT_SPEC = "Feral (Bear) Druid"
        end
        _, _, _, _, currentRank = GetTalentInfo(3, 27);
        if currentRank == 1 then
            DEFAULT_CHAT_FRAME:AddMessage("INIT RESTO DRUID");
            RestoDruid.initRestoDruidKeybinds();
            getNextMacro = RestoDruid.getRestoDruidMacro;
            CURRENT_SPEC = "Restoration Druid"
        end
    elseif playerClass == "Priest" then
        _, _, _, _, currentRank = GetTalentInfo(3, 27);
        if currentRank == 1 then
            DEFAULT_CHAT_FRAME:AddMessage("INIT SHADOW PRIEST");
            ShadowPriest.initShadowPriestKeybinds();
            getNextMacro = ShadowPriest.getShadowPriestMacro;
            CURRENT_SPEC = "Shadow Priest"
        end
    elseif playerClass == "Warlock" then
        _, _, _, _, currentRank = GetTalentInfo(2, 27);
        if currentRank == 1 then
            DEFAULT_CHAT_FRAME:AddMessage("INIT DEMONOLOGY WARLOCK");
            DemonologyWarlock.initDemonologyWarlockKeybinds();
            getNextMacro = DemonologyWarlock.getDemonologyWarlockMacro;
            CURRENT_SPEC = "Demonology Warlock"
        end
    else
        DEFAULT_CHAT_FRAME:AddMessage("CLASS NOT SUPPORTED");
    end
    MultiboxConfig:UpdateSpecStatus(CURRENT_SPEC)
    drawPixel(0, 0, 0)
    sentinelTexture:SetVertexColor(0x12 / 255, 0x34 / 255, 0x56 / 255)
end

local function MboxCommandHandler(msg, editBox)
    local cmd, args = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd and string.lower(cmd) or ""

    if cmd == "toggle" then
        keysEnabled = not keysEnabled
        if keysEnabled then
            controlCommand = 2 -- enable
            DEFAULT_CHAT_FRAME:AddMessage("Keys enabled")
        else
            controlCommand = 1 -- disable
            DEFAULT_CHAT_FRAME:AddMessage("Keys disabled")
        end
    elseif cmd == "broadcast" then
        broadcastEnabled = not broadcastEnabled
        if broadcastEnabled then
            controlCommand = 3 -- enable broadcast
            DEFAULT_CHAT_FRAME:AddMessage("Broadcast enabled")
        else
            controlCommand = 4 -- disable broadcast
            DEFAULT_CHAT_FRAME:AddMessage("Broadcast disabled")
        end
    elseif cmd == "swap" then
        local target = tonumber(args)
        if target and target > 0 then
            controlCommand = target + 4
            DEFAULT_CHAT_FRAME:AddMessage("Signaling swap with window " .. target)
        else
            DEFAULT_CHAT_FRAME:AddMessage("Invalid swap target. Usage: /mbox swap <window_number>")
        end
    elseif cmd == "" then
        init(msg, editBox)
    else
        DEFAULT_CHAT_FRAME:AddMessage("Unknown mbox command: " .. cmd)
        DEFAULT_CHAT_FRAME:AddMessage("Usage: /mbox [toggle|broadcast|swap <target>]")
    end
end

SlashCmdList["MBOX"] = MboxCommandHandler; -- Also a valid assignment strategy
-- init()
