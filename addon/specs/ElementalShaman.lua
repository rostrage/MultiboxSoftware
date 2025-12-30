-- Define named constants for macro types (simulating enums)
local MacroTypes = {
    DOING_NOTHING = 0,
    TOTEM_OF_WRATH = 1,
    SEARING_TOTEM = 2,
    CALL_OF_THE_ELEMENTS = 3,
    ELEMENTAL_MASTERY = 4,
    FLAME_SHOCK = 5,
    LAVA_BURST = 6,
    CHAIN_LIGHTNING = 7,
    LIGHTNING_BOLT = 8,
    WATER_SHIELD = 9,
    FLAMETONGUE_WEAPON = 10,
}

-- Map of macro strings for each action
local macroMap = {
    [MacroTypes.TOTEM_OF_WRATH] = "/cast Totem of Wrath",
    [MacroTypes.SEARING_TOTEM] = "/cast Searing Totem",
    [MacroTypes.CALL_OF_THE_ELEMENTS] = "/cast Call of the Elements",
    [MacroTypes.ELEMENTAL_MASTERY] = "/cast Elemental Mastery",
    [MacroTypes.FLAME_SHOCK] = "/cast [target=focustarget] Flame Shock",
    [MacroTypes.LAVA_BURST] = "/cast [target=focustarget] Lava Burst",
    [MacroTypes.CHAIN_LIGHTNING] = "/cast [target=focustarget] Chain Lightning",
    [MacroTypes.LIGHTNING_BOLT] = "/cast [target=focustarget] Lightning Bolt",
    [MacroTypes.WATER_SHIELD] = "/cast Water Shield",
    [MacroTypes.FLAMETONGUE_WEAPON] = "/cast Flametongue Weapon",
    [MacroTypes.DOING_NOTHING] = "/stopcasting",
}

-- ========= DEBUG FLAG =========
local isDebug = false
local function debug(msg)
    if isDebug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[ElementalShaman]|r " .. msg)
    end
end
-- ============================


local function getSpellCooldownRemaining(spellName)
    local startTime, duration, _ = GetSpellCooldown(spellName)
    if startTime and startTime > 0 then
        local remaining = (startTime + duration) - GetTime()
        return remaining > 0 and remaining or 0
    end
    return 0
end

-- Function to return a tuple (key, target) based on current conditions
local function getElementalShamanMacro()

    if UnitIsDeadOrGhost("player") or IsMounted()  then
        return MacroTypes.DOING_NOTHING, 0
    end

    if not UnitBuff("player", "Water Shield") then
        debug("ACTION: Water Shield. (Missing Water Shield)")
        return MacroTypes.WATER_SHIELD, 0
    end

    if not GetWeaponEnchantInfo() then
        debug("ACTION: Flametongue Weapon. (Missing weapon enchant)")
        return MacroTypes.FLAMETONGUE_WEAPON, 0
    end

    if not UnitAffectingCombat("focus") then
        return MacroTypes.DOING_NOTHING, 0
    end
    
    debug("---------- New Rotation Tick ----------")
    
    local focusName, _ = UnitName("focustarget")
    if not focusName or UnitIsDeadOrGhost("focustarget") then
        debug("ACTION: Doing nothing. (Invalid focus target)")
        return MacroTypes.DOING_NOTHING, 0
    end
    debug("Condition: Focus target is valid.")

    local gcd = getSpellCooldownRemaining("Flametongue Weapon")


    local _, airTotemName = GetTotemInfo(3) -- 1 is the slot for Air Totem
    -- 1. Call of the Elements if we don't have totems down.
    if airTotemName == "" then
        debug("ACTION: Call of the Elements. (Available)")
        return MacroTypes.CALL_OF_THE_ELEMENTS, 0
    end
    debug("Condition: Totems are already active.")
    
    -- 2. Keep up Totem of Wrath glyph buff
    if not UnitBuff("player", "Totem of Wrath") then
        debug("ACTION: Totem of Wrath. (Initial totem or expired)")
        return MacroTypes.TOTEM_OF_WRATH, 0
    end

    -- 3. Searing totem if we have demonic pact buff and it's not already on the ground
    if UnitBuff("player", "Demonic Pact") then
        local _, fireTotemName = GetTotemInfo(1) -- 1 is the slot for Fire Totem
        if fireTotemName ~= "Searing Totem X" then
            debug("ACTION: Searing Totem. (Demonic Pact buff active and totem not present)")
            return MacroTypes.SEARING_TOTEM, 0
        end
        debug("Condition: Searing Totem is already active.")
    end

    -- 4. Elemental Mastery
    local elementalMasteryCooldown = getSpellCooldownRemaining("Elemental Mastery")
    if elementalMasteryCooldown <= gcd then
        debug("ACTION: Elemental Mastery. (Available)")
        return MacroTypes.ELEMENTAL_MASTERY, 0
    end
    debug(string.format("Condition: Elemental Mastery CD=%.1f", elementalMasteryCooldown))

    -- 5. Flame Shock
    if not UnitAura("focustarget", "Flame Shock", nil, "PLAYER|HARMFUL") then
        debug("ACTION: Flame Shock. (Debuff not on target)")
        return MacroTypes.FLAME_SHOCK, 0
    end
    debug("Condition: Flame Shock is on target.")

    -- 6. Lava Burst if Flame Shock on target
    local lavaBurstCooldown = getSpellCooldownRemaining("Lava Burst")
    if lavaBurstCooldown <= gcd and UnitAura("focustarget", "Flame Shock", nil, "PLAYER|HARMFUL") then
        debug("ACTION: Lava Burst. (Available and Flame Shock on target)")
        return MacroTypes.LAVA_BURST, 0
    end
    debug(string.format("Condition: Lava Burst CD=%.1f", lavaBurstCooldown))

    -- 7. Chain Lightning if available
    local chainLightningCooldown = getSpellCooldownRemaining("Chain Lightning")
    if chainLightningCooldown <= gcd then
        debug("ACTION: Chain Lightning. (Available and enough mana)")
        return MacroTypes.CHAIN_LIGHTNING, 0
    end
    debug(string.format("Condition: Chain Lightning CD=%.1f", chainLightningCooldown))

    -- 8. Lightning Bolt filler
    debug("ACTION: Lightning Bolt. (Fallback)")
    return MacroTypes.LIGHTNING_BOLT, 0
end

-- Initialize keybinds for macros in macroMap using secure buttons and SetBindingClick
local function initElementalShamanKeybinds()
    local macroKeys = {
        [MacroTypes.TOTEM_OF_WRATH] = "F1",
        [MacroTypes.SEARING_TOTEM] = "F2",
        [MacroTypes.CALL_OF_THE_ELEMENTS] = "F3",
        [MacroTypes.ELEMENTAL_MASTERY] = "F4",
        [MacroTypes.FLAME_SHOCK] = "F5",
        [MacroTypes.LAVA_BURST] = "F6",
        [MacroTypes.CHAIN_LIGHTNING] = "F7",
        [MacroTypes.LIGHTNING_BOLT] = "F8",
        [MacroTypes.WATER_SHIELD] = "F9",
        [MacroTypes.FLAMETONGUE_WEAPON] = "F10",
    }

    for key, binding in pairs(macroKeys) do
        local macroText = macroMap[key]
        local buttonName = "ElementalShamanMacroButton_" .. binding
        local button = CreateFrame("Button", buttonName, nil, "SecureActionButtonTemplate")
        button:SetAttribute("type", "macro")
        SetBindingClick(binding, buttonName)
        button:SetAttribute("macrotext", macroText)
    end
end

-- Return module exports
ElementalShaman = {
    MacroTypes = MacroTypes,
    macroMap = macroMap,
    getElementalShamanMacro = getElementalShamanMacro,
    initElementalShamanKeybinds = initElementalShamanKeybinds,
}
