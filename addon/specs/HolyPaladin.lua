-- Define named constants for macro types (simulating enums)
local MacroTypes = {
    DOING_NOTHING = 0,
    BEACON_OF_LIGHT = 1,
    SACRED_SHIELD = 2,
    DIVINE_PLEA = 3,
    JUDGEMENT_OF_LIGHT = 4,
    HOLY_LIGHT = 5
}

-- Map of macro strings for each key (0 to n)
local macroMap = {
    [MacroTypes.BEACON_OF_LIGHT] = "/cast [target=focus] Beacon of Light",
    [MacroTypes.SACRED_SHIELD] = "/cast [target=focus] Sacred Shield",
    [MacroTypes.DIVINE_PLEA] = "/cast Divine Plea",
    [MacroTypes.JUDGEMENT_OF_LIGHT] = "/cast [target=focustarget] Judgement of Light",
    [MacroTypes.HOLY_LIGHT] = "/cast Holy Light", -- Dynamic target will be handled at runtime
    [MacroTypes.DOING_NOTHING] = "/stopcasting"
}

-- ========= DEBUG FLAG =========
local isDebug = true
local function debug(msg)
    if isDebug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[HolyPaladin]|r " .. msg)
    end
end
-- ============================

local lastHealOnTarget = {}

local function onUnitSpellcastSent(self, event, unit, spellName, _, targetName)
    if unit == "player" and spellName == "Holy Light" and targetName then
        lastHealOnTarget[targetName] = GetTime()
    end
end

local function ensureAuraFrame()
    if _G.HolyPaladinAuraFrame then return end
    local f = CreateFrame("Frame")
    f:RegisterEvent("UNIT_SPELLCAST_SENT")
    f:SetScript("OnEvent", onUnitSpellcastSent)
    _G.HolyPaladinAuraFrame = f
end

local function getSpellCooldownRemaining(spellName)
    local startTime, duration, _ = GetSpellCooldown(spellName)
    if startTime and startTime > 0 then
        local remaining = (startTime + duration) - GetTime()
        return remaining > 0 and remaining or 0
    end
    return 0
end

-- Function to return a tuple (key, target) based on current conditions
local function getHolyPaladinMacro()
    
    local focusName = UnitName("focus")

    -- 1. Use Divine Plea when mana is low and off cooldown
    local currentMana = UnitPower("player", 0)
    local maxMana = UnitPowerMax("player", 0)
    if currentMana < maxMana * 0.75 then
        local divinePleaCooldown = getSpellCooldownRemaining("Divine Plea")
        if divinePleaCooldown <= 0.2 then
            debug("ACTION: Divine Plea. (Available)")
            return MacroTypes.DIVINE_PLEA, 0
        end
        debug(string.format("Condition: Divine Plea CD=%.1f, Mana=%.1f%%", divinePleaCooldown, (currentMana / maxMana) * 100))
    end

    if not UnitAffectingCombat("focus")  then
        return MacroTypes.DOING_NOTHING, 0
    end
    
    debug("---------- New Rotation Tick ----------")

    -- 2. Cast Beacon of Light if not already on focus
    if not UnitAura("focus", "Beacon of Light", nil , "PLAYER") and UnitInRange("focus") and not UnitIsDeadOrGhost("focus") then
        debug("ACTION: Beacon of Light. (Not on focus)")
        return MacroTypes.BEACON_OF_LIGHT, 0
    end
    debug("Condition: Beacon of Light is on focus.")

    -- 3. Cast Sacred Shield if not already on focus
    if not UnitBuff("focus", "Sacred Shield") and UnitInRange("focus") and not UnitIsDeadOrGhost("focus") then
        debug("ACTION: Sacred Shield. (Not on focus)")
        return MacroTypes.SACRED_SHIELD, 0
    end
    debug("Condition: Sacred Shield is on focus.")

    -- 4. Cast Judgement of Light on focustarget when off cooldown
    local judgementCooldown = getSpellCooldownRemaining("Judgement of Light")
    if judgementCooldown <= 0.2 and IsSpellInRange("Judgement of Light", "focustarget") then
        debug("ACTION: Judgement of Light. (Available)")
        return MacroTypes.JUDGEMENT_OF_LIGHT, 0
    end
    debug(string.format("Condition: Judgement of Light CD=%.1f", judgementCooldown))

    -- 5. Loop through raid members and find lowest HP non-focus target
    local targetIndex = 0
    local lowestPercent = 1.0

    for i = 1, GetNumRaidMembers() do
        local unit = "raid" .. i
        if UnitIsPlayer(unit) and UnitInRange(unit) and not UnitIsDeadOrGhost(unit) then
            local name = UnitName(unit)
            local health = UnitHealth(unit)
            local maxHealth = UnitHealthMax(unit)
            local percent = health / maxHealth
            if percent < lowestPercent then
                if percent < 0.5 or not lastHealOnTarget[name] or GetTime() > lastHealOnTarget[name] + 2.5 then
                    lowestPercent = percent
                    if name ~= focusName then -- Skip the focus target
                        targetIndex = i
                    end
                end
            end
        end
    end

    if lowestPercent < 1.0 then
        debug(string.format("ACTION: Holy Light. (Target %d at %.1f%% health)", targetIndex, lowestPercent * 100))
        return MacroTypes.HOLY_LIGHT, targetIndex
    else
        -- No raid members in need; check focus now (focus is last priority)
        local focusHealth = UnitHealth("focus")
        local focusMaxHealth = UnitHealthMax("focus")
        local focusPercent = (focusHealth / focusMaxHealth) * 100

        if focusHealth < focusMaxHealth then
            debug(string.format("ACTION: Holy Light. (Focus at %.1f%% health)", focusPercent))
            return MacroTypes.HOLY_LIGHT, targetIndex
        else
            debug("ACTION: Doing nothing. (No targets need healing)")
            return MacroTypes.DOING_NOTHING, 0
        end
    end
end

-- Initialize keybinds for macros in macroMap using secure buttons and SetBindingClick
local function initHolyPaladinKeybinds()
    local macroKeys = {
        [MacroTypes.BEACON_OF_LIGHT] = "F1",
        [MacroTypes.SACRED_SHIELD] = "F2",
        [MacroTypes.DIVINE_PLEA] = "F3",
        [MacroTypes.JUDGEMENT_OF_LIGHT] = "F4",
        [MacroTypes.HOLY_LIGHT] = "F5",
        [MacroTypes.DOING_NOTHING] = "F6"
    }

    for key, binding in pairs(macroKeys) do
        local buttonName = "MacroButton_" .. binding

        -- Create a secure macro button
        local button = CreateFrame("Button", buttonName, nil, "SecureActionButtonTemplate")
        button:SetAttribute("type", "macro")

        local macroText = macroMap[key]

        SetBindingClick(binding, buttonName)
        button:SetAttribute("macrotext", macroText)
    end
    ensureAuraFrame()
end

-- Return module exports
HolyPaladin = {
    MacroTypes = MacroTypes,
    macroMap = macroMap,
    getHolyPaladinMacro = getHolyPaladinMacro,
    initHolyPaladinKeybinds = initHolyPaladinKeybinds
}
