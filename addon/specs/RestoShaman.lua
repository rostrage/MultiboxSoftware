-- Define named constants for macro types (simulating enums)

-- ========= DEBUG FLAG =========
local isDebug = true
local function debug(msg)
    if isDebug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[RestoShaman]|r " .. msg)
    end
end
-- ============================

local lastHealOnTarget = {}

local function onUnitSpellcastSent(self, event, unit, spellName, _, targetName)
    if unit == "player" and targetName then
        if spellName == "Chain Heal" or spellName == "Lesser Healing Wave" or spellName == "Riptide" then
            lastHealOnTarget[targetName] = GetTime()
        end
    end
end

local function ensureAuraFrame()
    if _G.RestoShamanAuraFrame then return end
    local f = CreateFrame("Frame")
    f:RegisterEvent("UNIT_SPELLCAST_SENT")
    f:SetScript("OnEvent", onUnitSpellcastSent)
    _G.RestoShamanAuraFrame = f
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
    MANA_TIDE_TOTEM = 10
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
    [MacroTypes.MANA_TIDE_TOTEM] = "/cast Mana Tide Totem"
}

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
        debug("ACTION: Stop Casting. (No targets need healing)")
        return MacroTypes.STOP_CASTING, 0
    end
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
        [MacroTypes.MANA_TIDE_TOTEM] = "F10"
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
