-- Define named constants for macro types (simulating enums)

-- ========= DEBUG FLAG =========
local isDebug = false
local function debug(msg)
    if isDebug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[RestoShaman]|r " .. msg)
    end
end
-- ============================

local lastHealOnTarget = {}

-- Store swing timer information here
_G.MultiboxBossSwingTimer_swings = _G.MultiboxBossSwingTimer_swings or {}

-- Helper function to extract NPC ID from GUID
local function npcid(guid)
    return tonumber(guid:sub(-10, -7), 16)
end

-- Helper function to check if a GUID belongs to an NPC
local function isnpc(guid)
    local B = tonumber(guid:sub(5,5), 16)
    local maskedB = B % 8
    if maskedB == 3 then -- 3 is NPC
        return true
    end
    return false
end

-- Simplified OnSwing function to update swing timers
local function OnSwing(time, guid, name)
    -- DEFAULT_CHAT_FRAME:AddMessage("OnSwing called for name: " .. name .. " at time: " .. time)
    _G.MultiboxBossSwingTimer_swings[guid] = _G.MultiboxBossSwingTimer_swings[guid] or {}
    local prev = _G.MultiboxBossSwingTimer_swings[guid].time
    _G.MultiboxBossSwingTimer_swings[guid].time = time
    -- DEFAULT_CHAT_FRAME:AddMessage("foo")
    local speed = nil
    if prev and (time - prev) < 5000 then -- Only consider recent swings for speed calculation
        speed = time - prev
    end

    -- Attempt to get attack speed from UnitAttackSpeed if available and not yet set
    local unitId = nil
    if UnitGUID("boss1") == guid then unitId = "boss1" end

    if unitId then
        local apiSpeed = UnitAttackSpeed(unitId)
        if apiSpeed and apiSpeed > 0 then
            -- Prefer API speed if available
            speed = apiSpeed
        end
    end

    if speed then
        _G.MultiboxBossSwingTimer_swings[guid].next = time + speed
    end
end


local function onUnitSpellcastSent(self, event, unit, spellName, _, targetName)
    if unit == "player" and targetName then
        if spellName == "Chain Heal" or spellName == "Lesser Healing Wave" or spellName == "Riptide" then
            lastHealOnTarget[targetName] = GetTime()
        end
    end
end

local function onCombatLogEventUnfiltered(self, event, timestamp, subevent, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, ...)
    if subevent == "SWING_DAMAGE" or subevent == "SWING_MISSED" then
        if isnpc(sourceGUID) then
            OnSwing(GetTime(), sourceGUID, sourceName)
        end
    elseif subevent == "UNIT_DIED" then
        if _G.MultiboxBossSwingTimer_swings[destGUID] then
            _G.MultiboxBossSwingTimer_swings[destGUID] = nil
        end
    end
end

local function onCombatEnd(self)
    debug("Combat ended, clearing swing timers.")
    _G.MultiboxBossSwingTimer_swings = {}
end

local function ensureAuraFrame()
    if _G.RestoShamanAuraFrame then return end
    local f = CreateFrame("Frame")
    f:RegisterEvent("UNIT_SPELLCAST_SENT")
    f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function(self, event, ...)
        if event == "UNIT_SPELLCAST_SENT" then
            onUnitSpellcastSent(self, event, ...)
        elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
            onCombatLogEventUnfiltered(self, event, ...)
        elseif event == "PLAYER_REGEN_ENABLED" then
            onCombatEnd(self)
        end
    end)
    _G.RestoShamanAuraFrame = f
end

local function getSpellCooldownRemaining(spellName)
    local startTime, duration, _ = GetSpellCooldown(spellName)
    if startTime and startTime > 0 then
        local remaining = (startTime + duration) - GetTime()
        return remaining > 0 and remaining or 0
    end
    return 0
end

local MacroTypes = {
    DOING_NOTHING = 0,
    WATER_SHIELD = 1,
    EARTHLIVING_WEAPON = 2,
    EARTH_SHIELD_FOCUS = 3,
    CHAIN_HEAL = 4,
    LESSER_HEALING_WAVE = 5,
    RIPTIDE = 6,
    STOP_CASTING = 7,
    CLEANSE_SPIRIT = 8,
    CALL_OF_THE_ELEMENTS = 9,
    MANA_TIDE_TOTEM = 10,
    HEALING_WAVE = 11
}

-- Debuffs that should not be instantly dispelled
local DISPEL_BLACKLIST = {
    ["Mark of Combustion"] = true,
    ["Mark of Consumption"] = true,
    ["Mutated Infection"] = true,
    ["Necrotic Plague"] = true,
}

local DISPEL_TYPES = {
    ["Curse"] = true,
    ["Poison"] = true,
    ["Disease"] = true,
    ["Magic"] = false
}

-- Map of macro strings for each key (0 to n)
local macroMap = {
    [MacroTypes.DOING_NOTHING] = "/stopcasting",
    [MacroTypes.WATER_SHIELD] = "/cast Water Shield",
    [MacroTypes.EARTHLIVING_WEAPON] = "/cast Earthliving Weapon",
    [MacroTypes.EARTH_SHIELD_FOCUS] = "/cast [target=focus] Earth Shield",
    [MacroTypes.CHAIN_HEAL] = "/cast Chain Heal",
    [MacroTypes.LESSER_HEALING_WAVE] = "/cast Lesser Healing Wave",
    [MacroTypes.RIPTIDE] = "/cast Riptide",
    [MacroTypes.STOP_CASTING] = [[/stopcasting
/assist focus
/startattack]],
    [MacroTypes.CLEANSE_SPIRIT] = "/cast Cleanse Spirit",
    [MacroTypes.CALL_OF_THE_ELEMENTS] = "/cast Call of the Elements",
    [MacroTypes.MANA_TIDE_TOTEM] = "/cast Mana Tide Totem",
    [MacroTypes.HEALING_WAVE] = "/cast Healing Wave"
}

local function getNextBossSwingTimer()
    local nextSwingTime = math.huge

    local targetGUID = UnitGUID("boss1")
    if targetGUID and isnpc(targetGUID) then
        if _G.MultiboxBossSwingTimer_swings[targetGUID] and _G.MultiboxBossSwingTimer_swings[targetGUID].next then
            nextSwingTime = math.min(nextSwingTime, _G.MultiboxBossSwingTimer_swings[targetGUID].next)
        end
    end

    if nextSwingTime == math.huge or nextSwingTime > GetTime() then
        return nil -- No boss swing timer found
    end

    return nextSwingTime
end

-- Function to return a tuple (key, target) based on current conditions
local function getRestoShamanMacro()
    
    if  UnitIsDeadOrGhost("player") or IsMounted() then
        -- debug("ACTION: Doing nothing. (Player is dead/ghost or mounted)")
        return MacroTypes.DOING_NOTHING, 0
    end

    if not UnitBuff("player", "Water Shield") then
        debug("ACTION: Water Shield. (Missing Water Shield)")
        return MacroTypes.WATER_SHIELD, 0
    end

    if not GetWeaponEnchantInfo() then
        debug("ACTION: Earthliving Weapon. (Missing weapon enchant)")
        return MacroTypes.EARTHLIVING_WEAPON, 0
    end

    local focusName, _ = UnitName("focus")
    if focusName and UnitInRange("focus") and not UnitBuff("focus", "Earth Shield") and not UnitIsDeadOrGhost("focus") and not UnitIsEnemy("player", "focus") then
        debug("ACTION: Earth Shield on Focus. (Focus needs Earth Shield)")
        return MacroTypes.EARTH_SHIELD_FOCUS, 0
    end

    if not UnitAffectingCombat("focus") and not UnitAffectingCombat("player") then
        -- debug("ACTION: Doing nothing. (Focus and player not in combat)")
        return MacroTypes.DOING_NOTHING, 0
    end

    debug("---------- New Rotation Tick ----------")
    local _, totemName = GetTotemInfo(1)
    if totemName == "" then
        debug("ACTION: Call of the Elements. (Missing Totem)")
        return MacroTypes.CALL_OF_THE_ELEMENTS, 0
    end

    local currentMana = UnitPower("player", 0)
    local maxMana = UnitPowerMax("player", 0)
    if currentMana < maxMana * 0.7 then
        local manaTideCooldown = getSpellCooldownRemaining("Mana Tide Totem")
        if manaTideCooldown <= 0.2 then
            debug("ACTION: Mana Tide. (Available)")
            return MacroTypes.MANA_TIDE_TOTEM, 0
        end
    end

    local numtargets = 0
    local target = 0
    local targetPercent = 0.95
    local raidmembers = GetNumRaidMembers()
    local focusTarget = -1
    debug(string.format("Starting target scan. Raid members: %d", raidmembers))
    
    if raidmembers == 0 then
        debug("Scanning party members for healing targets")
        for i = 1, 4 do
            local u = GetUnitName("party" .. i)
            if UnitIsPlayer(u) and UnitInRange(u) and not UnitIsDeadOrGhost(u) and not UnitIsEnemy("player",u) then
                local health = UnitHealth(u)
                local maxHealth = UnitHealthMax(u)
                local percent = health / maxHealth

                if percent < 0.95 then
                    numtargets = numtargets + 1
                    debug(string.format("Party member %s needs healing (%.1f%%)", u, percent * 100))
                    if percent < targetPercent then
                        if not lastHealOnTarget[u] or GetTime() > lastHealOnTarget[u] + 2.5 then
                            targetPercent = percent
                            target = i
                            debug(string.format("Selected party member %s as primary target (%.1f%%)", u, percent * 100))
                        end
                    end
                end
            end
        end
        local u = GetUnitName("player")
        if UnitIsPlayer(u) and UnitInRange(u) then
            local health = UnitHealth(u)
            local maxHealth = UnitHealthMax(u)
            local percent = health / maxHealth

            if percent < 0.95 then
                numtargets = numtargets + 1
                -- debug(string.format("Player needs healing (%.1f%%)", percent * 100))
                if percent < targetPercent then
                    if not lastHealOnTarget[u] or GetTime() > lastHealOnTarget[u] + 2.5 then
                        targetPercent = percent
                        target = 5
                        -- debug(string.format("Selected player as primary target (%.1f%%)", percent * 100))
                    end
                end
            end
        end
    else
        debug("Scanning raid members for healing targets")
        for i = 1, GetNumRaidMembers() do
            local u = GetUnitName("raid" .. i)
            if u == focusName then
                focusTarget = i
            end
            if UnitIsPlayer(u) and UnitInRange(u) and not UnitIsDeadOrGhost(u) and not UnitIsEnemy("player", u) then
                local health = UnitHealth(u)
                local maxHealth = UnitHealthMax(u)
                local percent = health / maxHealth
                -- scan for debuffs in raid
                for tCnt = 1, 40 do
                    local tName, _, tIcon, tStacks, tType, tDuration, tExpiry = UnitDebuff(u, tCnt)
                    if (tIcon == nil or tName == nil) then
                        break
                    end
                    if not DISPEL_BLACKLIST[tName] and tType ~= nil and DISPEL_TYPES[tType] then
                        debug(string.format("ACTION: Cleanse Spirit. (Raid member %d has debuff: %s)", i, tName))
                        return MacroTypes.CLEANSE_SPIRIT, i
                    end
                end
                if percent < 0.95 then
                    numtargets = numtargets + 1
                    if percent < targetPercent then
                        if not lastHealOnTarget[u] or GetTime() > lastHealOnTarget[u] + 2.5 then
                            targetPercent = percent
                            target = i
                        end
                    end
                end
            end
        end
    end

    if numtargets > 2 then
        local start, duration, enabled, modRate = GetSpellCooldown("Riptide")
        if start > 0 and duration > 0 then
            debug(string.format("ACTION: Chain Heal. (Multiple targets (%d), Riptide on CD)", numtargets))
            return MacroTypes.CHAIN_HEAL, target
        else
            debug(string.format("ACTION: Riptide. (Multiple targets (%d), Riptide available)", numtargets))
            return MacroTypes.RIPTIDE, target
        end
    elseif numtargets > 0 then
        local start, duration, enabled, modRate = GetSpellCooldown("Riptide")
        if start > 0 and duration > 0 then
            debug(string.format("ACTION: Lesser Healing Wave. (Single target (%d), Riptide on CD)", numtargets))
            return MacroTypes.LESSER_HEALING_WAVE, target
        else
            debug(string.format("ACTION: Riptide. (Single target (%d), Riptide available)", numtargets))
            return MacroTypes.RIPTIDE, target
        end
    else
        local _, _, _, _, _, endtimeMS = UnitCastingInfo("player")
        local castFinishTime = endtimeMS and (endtimeMS / 1000) or nil
        local nextBossSwing = getNextBossSwingTimer()
        if nextBossSwing ~= nil then
            -- If we are casting and a boss swing is coming soon
            if castFinishTime ~= nil and castFinishTime < nextBossSwing then
                debug("ACTION: Stop Casting. (Cast finishes before next boss swing)")
                return MacroTypes.STOP_CASTING, 0
            elseif focusTarget ~= -1 then
                -- If nothing better to do, precast a heal on focus
                debug("ACTION: Healing Wave on Focus. (No targets need healing)")
                return MacroTypes.HEALING_WAVE, focusTarget
            end
        end
    end
    debug("ACTION: Doing nothing. (No targets need healing)")
    return MacroTypes.DOING_NOTHING, 0
end

-- Initialize keybinds for macros in macroMap using secure buttons and SetBindingClick
local function initRestoShamanKeybinds()
    local macroKeys = {
        [MacroTypes.WATER_SHIELD] = "F1",
        [MacroTypes.EARTHLIVING_WEAPON] = "F2",
        [MacroTypes.EARTH_SHIELD_FOCUS] = "F3",
        [MacroTypes.CHAIN_HEAL] = "F4",
        [MacroTypes.LESSER_HEALING_WAVE] = "F5",
        [MacroTypes.RIPTIDE] = "F6",
        [MacroTypes.STOP_CASTING] = "F7",
        [MacroTypes.CLEANSE_SPIRIT] = "F8",
        [MacroTypes.CALL_OF_THE_ELEMENTS] = "F9",
        [MacroTypes.MANA_TIDE_TOTEM] = "F10",
        [MacroTypes.HEALING_WAVE] = "F11"
    }

    for key, binding in pairs(macroKeys) do
        local macroText = macroMap[key]

        -- Create a unique button name for each macro
        local buttonName = "MacroButton_" .. binding

        -- Create the button and set its attributes
        local button = CreateFrame("Button", buttonName, nil, "SecureActionButtonTemplate")
        button:SetAttribute("type", "macro")
        SetBindingClick(binding, buttonName)
        button:SetAttribute("macrotext", macroText)
    end
    ensureAuraFrame()
end

-- Return module exports
RestoShaman = {
    MacroTypes = MacroTypes,
    macroMap = macroMap,
    getRestoShamanMacro = getRestoShamanMacro,
    initRestoShamanKeybinds = initRestoShamanKeybinds
}