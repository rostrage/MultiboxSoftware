local Multibox = LibStub("AceAddon-3.0"):NewAddon("Multibox", "AceComm-3.0")

local MESSAGE_PREFIX = "MBX"


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

-- Texture for movement/rotation pixel (bitmask)
local movementRotationTexture = frame:CreateTexture(nil, "ARTWORK")
movementRotationTexture:SetPoint("TOPLEFT", 2, 0) -- New pixel at (2,0)
movementRotationTexture:SetSize(1, 1)
movementRotationTexture:SetTexture("Interface\\AddOns\\Multibox\\Smooth.tga")

local getNextMacro
local targetRotation = nil
local targetX = nil
local targetY = nil

-- Draws a single pixel with given RGB values (0-1 range)
local function drawPixel(r, g, b)
    commandTexture:SetVertexColor(r, g, b)
end

-- New function to draw the movement/rotation pixel
local function drawMovementRotationPixel(value)
    -- Only using the red component for simplicity, as it's a single byte bitmask
    movementRotationTexture:SetVertexColor(value / 255, 0, 0)
end

function Multibox:OnInitialize()
    self.keysEnabled = true
    self.broadcastEnabled = false
    self.stackingEnabled = false
    self.stackedPlayers = {}
    self.controlCommand = 0
    self:RegisterComm(MESSAGE_PREFIX)
    self:Init()
end

-- OnUpdate loop to draw the key value as a pixel color
local timeElapsed = 0
local stackBroadcastTimeElapsed = 0
frame:HookScript("OnUpdate", function(self, elapsed)
    timeElapsed = timeElapsed + elapsed
    stackBroadcastTimeElapsed = stackBroadcastTimeElapsed + elapsed

    if (timeElapsed > 0.1) then
        timeElapsed = 0
        if not Multibox.keysEnabled then
            DEFAULT_CHAT_FRAME:AddMessage("Keys disabled, not sending commands")
            drawPixel(0, 0, 0)
            drawMovementRotationPixel(0) -- Also clear movement pixel
            return
        end
        if getNextMacro then
            local key, target = getNextMacro()
            -- Normalize the key to a value between 0 and 1 using 255 as the max for 8-bit color
            local r = key / 255
            local g = target / 255
            local b = Multibox.controlCommand / 255
            drawPixel(r, g, b)
            if Multibox.controlCommand ~= 0 then
                Multibox.controlCommand = 0
            end
        end
    end

    if Multibox.stackingEnabled and stackBroadcastTimeElapsed > 0.5 then
        stackBroadcastTimeElapsed = 0
        local unitX, unitY = GetPlayerMapPosition("player")
        local unitRotation = GetPlayerFacing()
        local moveMessage = "move " .. unitRotation .. " " .. unitX .. " " .. unitY
        for i, playerName in ipairs(Multibox.stackedPlayers) do
            Multibox:SendCommMessage(MESSAGE_PREFIX, moveMessage, "WHISPER", playerName)
        end
    end

    local movementRotationBitmask = MultiboxMovement:getMovementRotationBitmask(targetRotation, targetX, targetY)
    if movementRotationBitmask == 0 then
        targetRotation = nil
        targetX = nil
        targetY = nil
    end
    drawMovementRotationPixel(movementRotationBitmask) -- Draw the movement/rotation bitmask
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
            button:SetAttribute("macrotext", "/target player" .. "\r\n/target raid" .. i)
        else
            button:SetAttribute("macrotext", "/target raid" .. i)
        end
    end
end

function Multibox:Init()
    initTargettingKeybinds();
    MultiboxLFG:Initialize()
    MultiboxGuildBank:Initialize()
    MultiboxFollow:Initialize()
    MultiboxParty:Initialize()
    MultiboxQuest:Initialize()
    MultiboxMovement:Initialize()
    -- Initialize configuration system
    MultiboxConfig:RegisterOptions()
    
    local playerClass = UnitClass("player");
    if playerClass == "Paladin" then
        _, _, _, _, currentRank = GetTalentInfo(3, 26)
        if currentRank == 1 then
            DEFAULT_CHAT_FRAME:AddMessage("INIT RETRI PALADIN2");
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
        _, _, _, _, currentRank = GetTalentInfo(2, 2);
        if currentRank == 5 then
            DEFAULT_CHAT_FRAME:AddMessage("INIT FERAL CAT DRUID");
            FeralCatDruid.initFeralCatDruidKeybinds();
            getNextMacro = FeralCatDruid.getFeralCatDruidMacro;
        end
        _, _, _, _, currentRank = GetTalentInfo(2, 5);
        if currentRank == 3 then
            DEFAULT_CHAT_FRAME:AddMessage("INIT FERAL BEAR DRUID");
            FeralBearDruid.initFeralBearDruidKeybinds();
            getNextMacro = FeralBearDruid.getFeralBearDruidMacro;
        end
        _, _, _, _, currentRank = GetTalentInfo(3, 27);
        if currentRank == 1 then
            DEFAULT_CHAT_FRAME:AddMessage("INIT RESTO DRUID");
            RestoDruid.initRestoDruidKeybinds();
            getNextMacro = RestoDruid.getRestoDruidMacro;
        end
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
    drawPixel(0, 0, 0)
    sentinelTexture:SetVertexColor(0x12 / 255, 0x34 / 255, 0x56 / 255)
end

function Multibox:MboxCommandHandler(msg)
    local cmd, args = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd and string.lower(cmd) or ""

    if cmd == "toggle" then
        self.keysEnabled = not self.keysEnabled
        self:SendToggle()
    elseif cmd == "broadcast" then
        self.broadcastEnabled = not self.broadcastEnabled
        if self.broadcastEnabled then
            self.controlCommand = 3 -- enable broadcast
            DEFAULT_CHAT_FRAME:AddMessage("Broadcast enabled")
        else
            self.controlCommand = 4 -- disable broadcast
            DEFAULT_CHAT_FRAME:AddMessage("Broadcast disabled")
        end
        self:SendBroadcast()
    elseif cmd == "swap" then
        local target = tonumber(args)
        if target and target > 0 then
            self.controlCommand = target + 4
            DEFAULT_CHAT_FRAME:AddMessage("Signaling swap with window " .. target)
        else
            DEFAULT_CHAT_FRAME:AddMessage("Invalid swap target. Usage: /mbox swap <window_number>")
        end
    elseif cmd == "follow" then
        MultiboxFollow.SetFollowTarget(args)
    elseif cmd == "move" then
        local rotation_str, x_str, y_str = args:match("^(%S*)%s*(%S*)%s*(%S*)$")
        targetRotation = tonumber(rotation_str)
        targetX = tonumber(x_str)
        targetY = tonumber(y_str)
    elseif cmd == "stack" then
        if args == "clear" then
            self.stackedPlayers = {}
            self.stackingEnabled = false
            DEFAULT_CHAT_FRAME:AddMessage("Stacking cleared and disabled.")
        else
            self.stackedPlayers = {strsplit(" ", args)}
            self.stackingEnabled = true
            DEFAULT_CHAT_FRAME:AddMessage("Stacking enabled for: " .. args)
        end
    elseif cmd == "" then
        self:Init()
    else
        DEFAULT_CHAT_FRAME:AddMessage("Unknown mbox command: " .. cmd)
        DEFAULT_CHAT_FRAME:AddMessage("Usage: /mbox [toggle|broadcast|swap <target>|follow <target>|move <rotation> <x> <y>|stack <player1> <player2> ...|stack clear]")
    end
end

function Multibox:OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= MESSAGE_PREFIX then
        return
    end

    local command, value = message:match("^(%S*)%s*(.-)$")
    command = command and string.lower(command) or ""

    if command == "toggle" then
        local newState = (value == "true")
        if self.keysEnabled ~= newState then
            self.keysEnabled = newState
            if self.keysEnabled then
                self.controlCommand = 2 -- enable
                DEFAULT_CHAT_FRAME:AddMessage("Keys enabled by " .. sender)
            else
                self.controlCommand = 1 -- disable
                DEFAULT_CHAT_FRAME:AddMessage("Keys disabled by " .. sender)
            end
        end
    elseif command == "broadcast" then
        local newState = (value == "true")
        if self.broadcastEnabled ~= newState then
            self.broadcastEnabled = newState
            if self.broadcastEnabled then
                self.controlCommand = 3 -- enable broadcast
                DEFAULT_CHAT_FRAME:AddMessage("Broadcast enabled by " .. sender)
            else
                self.controlCommand = 4 -- disable broadcast
                DEFAULT_CHAT_FRAME:AddMessage("Broadcast disabled by " .. sender)
            end
        end
    elseif command == "move" then
        self:MboxCommandHandler(message)
    end
end

function Multibox:SendToggle()
    local message = "toggle " .. tostring(self.keysEnabled)
    self:SendCommMessage(MESSAGE_PREFIX, message, "RAID", nil)
    self:SendCommMessage(MESSAGE_PREFIX, message, "PARTY", nil)
end

function Multibox:SendBroadcast()
    local message = "broadcast " .. tostring(self.broadcastEnabled)
    self:SendCommMessage(MESSAGE_PREFIX, message, "RAID", nil)
    self:SendCommMessage(MESSAGE_PREFIX, message, "PARTY", nil)
end

SLASH_MBOX1 = '/mbox'
function SlashCmdList.MBOX(msg)
    Multibox:MboxCommandHandler(msg)
end