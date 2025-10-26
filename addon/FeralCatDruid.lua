-- Define named constants for macro types (simulating enums)
local MacroTypes = {
    DOING_NOTHING = 0,
    TIGERS_FURY = 1,
    FAERIE_FIRE = 2,
    BERSERK = 3,
    SAVAGE_ROAR = 4,
    RIP = 5,
    FEROCIOUS_BITE = 6,
    MANGLE = 7,
    RAKE = 8,
    SHRED = 9,
}

-- Map of macro strings for each key
local macroMap = {
    [MacroTypes.TIGERS_FURY] = "/cast Tiger's Fury",
    [MacroTypes.FAERIE_FIRE] = "/cast [target=focustarget] Faerie Fire (Feral)",
    [MacroTypes.BERSERK] = "/cast Berserk",
    [MacroTypes.SAVAGE_ROAR] = "/cast Savage Roar",
    [MacroTypes.RIP] = "/cast [target=focustarget] Rip",
    [MacroTypes.FEROCIOUS_BITE] = "/cast [target=focustarget] Ferocious Bite",
    [MacroTypes.MANGLE] = "/cast [target=focustarget] Mangle (Cat)",
    [MacroTypes.RAKE] = "/cast [target=focustarget] Rake",
    [MacroTypes.SHRED] = "/cast [target=focustarget] Shred",
    [MacroTypes.DOING_NOTHING] = "/print Doing nothing"
}

-- Function to return a tuple (key, target) based on current conditions
local function getFeralCatDruidMacro()
    
    if UnitIsDeadOrGhost("player") or IsMounted() or not UnitAffectingCombat("player") then
        return MacroTypes.DOING_NOTHING, 0
    end

    -- Check focus target for debuffs and damage rotation
    local focusName, _ = UnitName("focustarget")
    if focusName and not UnitIsDeadOrGhost("focustarget") then
        local comboPoints = GetComboPoints("player", "focustarget")
        local energy = UnitPower("player", 3) -- 3 is the index for Energy

        -- 1. Manage Buffs & Cooldowns
        
        -- Tiger's Fury: Cast below 30 energy when off cooldown and not Berserking
        local tf_start, _, _, _ = GetSpellCooldown("Tiger's Fury")
        if energy < 30 and tf_start == 0 and not UnitBuff("player", "Berserk") then
            return MacroTypes.TIGERS_FURY, 0
        end

        -- Faerie Fire: Keep debuff applied
        local ff_start, _, _, _ = GetSpellCooldown("Faerie Fire (Feral)")
        if not UnitDebuff("focustarget", "Faerie Fire (Feral)") and ff_start == 0 then
            return MacroTypes.FAERIE_FIRE, 0
        end

        -- Berserk: Use when off cooldown and Rip is on the target
        local berserk_start, _, _, _ = GetSpellCooldown("Berserk")
        if berserk_start == 0 and UnitDebuff("focustarget", "Rip") then
            return MacroTypes.BERSERK, 0
        end

        -- 2. Spend Combo Points (Finishers)

        -- Savage Roar: Maintain buff, use with any combo points
        if not UnitBuff("player", "Savage Roar") and comboPoints >= 1 then
            return MacroTypes.SAVAGE_ROAR, 0
        end

        -- Rip: Use at 5 combo points if debuff is missing
        if not UnitDebuff("focustarget", "Rip") and comboPoints == 5 then
            return MacroTypes.RIP, 0
        end

        -- Ferocious Bite: Use at 5 combo points if Rip and Roar are active
        if UnitDebuff("focustarget", "Rip") and UnitBuff("player", "Savage Roar") and comboPoints == 5 then
            return MacroTypes.FEROCIOUS_BITE, 0
        end

        -- 3. Maintain Debuffs & Build Combo Points (Builders)

        -- Mangle: Keep debuff applied
        if not UnitDebuff("focustarget", "Mangle (Cat)") then
            return MacroTypes.MANGLE, 0
        end

        -- Rake: Keep debuff applied
        if not UnitDebuff("focustarget", "Rake") then
            return MacroTypes.RAKE, 0
        end

        -- 4. Filler
        -- Shred: Use as primary combo point builder
        return MacroTypes.SHRED, 0
    end

    return MacroTypes.DOING_NOTHING, 0
end

-- Initialize keybinds for macros in macroMap
local function initFeralCatDruidKeybinds()
    local macroKeys = {
        [MacroTypes.TIGERS_FURY] = "F1",
        [MacroTypes.FAERIE_FIRE] = "F2",
        [MacroTypes.BERSERK] = "F3",
        [MacroTypes.SAVAGE_ROAR] = "F4",
        [MacroTypes.RIP] = "F5",
        [MacroTypes.FEROCIOUS_BITE] = "F6",
        [MacroTypes.MANGLE] = "F7",
        [MacroTypes.RAKE] = "F8",
        [MacroTypes.SHRED] = "F9",
    }

    for key, binding in pairs(macroKeys) do
        local macroText = macroMap[key]
        local buttonName = "MacroButton_Feral_" .. binding
        local button = CreateFrame("Button", buttonName, nil, "SecureActionButtonTemplate")
        button:SetAttribute("type", "macro")
        SetBindingClick(binding, buttonName)
        button:SetAttribute("macrotext", macroText)
    end
end

-- Return module exports
FeralCatDruid = {
    MacroTypes = MacroTypes,
    macroMap = macroMap,
    getFeralCatDruidMacro = getFeralCatDruidMacro,
    initFeralCatDruidKeybinds = initFeralCatDruidKeybinds
}
