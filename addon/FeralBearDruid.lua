-- Define named constants for macro types (simulating enums)
local MacroTypes = {
    DOING_NOTHING = 0,
    FAERIE_FIRE_FERAL = 1,
    ENRAGE = 2,
    MANGLE_BEAR = 3,
    BERSERK = 4,
    LACERATE = 5,
    SWIPE_BEAR = 6
}

-- Map of macro strings for each key (0 to n)
local macroMap = {
    [MacroTypes.FAERIE_FIRE_FERAL] = [[/use !Maul
/use 10
/startattack
/use [target=focustarget] Faerie Fire (Feral)]],
    [MacroTypes.ENRAGE] = "/use Enrage",
    [MacroTypes.MANGLE_BEAR] = [[/use !Maul
/use 10
/startattack
/use [target=focustarget] Mangle (Bear)]],
    [MacroTypes.BERSERK] = "/use Berserk",
    [MacroTypes.LACERATE] = [[/use !Maul
/use 10
/startattack
/use [target=focustarget] Lacerate]],
    [MacroTypes.SWIPE_BEAR] = [[/use !Maul
/use 10
/startattack
/use [target=focustarget] Swipe (Bear)]],
    [MacroTypes.DOING_NOTHING] = "/run print(\"Doing nothing\")"
}

-- Function to return a tuple (key, target) based on current conditions
local function getFeralBearDruidMacro()
    if not UnitAffectingCombat("player") or IsMounted() then
        return MacroTypes.DOING_NOTHING, 0
    end
    
    -- Check if focustarget exists
    if not UnitExists("focustarget") then
        return MacroTypes.DOING_NOTHING, 0
    end
    
    -- 1. If the focustarget does not have the Faerie Fire (Feral) debuff, return Faerie Fire (Feral)
    if not UnitDebuff("focustarget", "Faerie Fire (Feral)") then
        return MacroTypes.FAERIE_FIRE_FERAL, 0
    end
    
    -- 2. If Enrage is available, return Enrage
    local enrageStart, enrageDuration, enrageEnabled, enrageModRate = GetSpellCooldown("Enrage")
    if enrageStart <= 0.1 and not UnitBuff("player", "Enrage") then
        return MacroTypes.ENRAGE, 0
    end
    
    -- 3. If the Mangle (Bear) is available, return Mangle (Bear)
    local start, duration, enabled, modRate = GetSpellCooldown("Mangle (Bear)")
    if start <= 0.1 then
        return MacroTypes.MANGLE_BEAR, 0
    end

    
    -- 4. If the focustarget does not have 5 stacks of Lacerate, return Lacerate
    local _, _, _, lacerateStacks = UnitDebuff("focustarget", "Lacerate")
    if lacerateStacks < 5 then
        return MacroTypes.LACERATE, 0
    end

        
    -- 5. If Berserk is available, return Berserk
    local berserkStart, berserkDuration, berserkEnabled, berserkModRate = GetSpellCooldown("Berserk")
    if berserkStart <= 0.1 then
        return MacroTypes.BERSERK, 0
    end

    -- 6. Otherwise return Swipe (Bear)
    return MacroTypes.SWIPE_BEAR, 0
end

-- Initialize keybinds for macros in macroMap using secure buttons and SetBindingClick
local function initFeralBearDruidKeybinds()
    local macroKeys = {
        [MacroTypes.FAERIE_FIRE_FERAL] = "F1",
        [MacroTypes.ENRAGE] = "F2",
        [MacroTypes.MANGLE_BEAR] = "F3",
        [MacroTypes.BERSERK] = "F4",
        [MacroTypes.LACERATE] = "F5",
        [MacroTypes.SWIPE_BEAR] = "F6",
        [MacroTypes.DOING_NOTHING] = "F7",
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
end

-- Return module exports
FeralBearDruid = {
    MacroTypes = MacroTypes,
    macroMap = macroMap,
    getFeralBearDruidMacro = getFeralBearDruidMacro,
    initFeralBearDruidKeybinds = initFeralBearDruidKeybinds
}
