-- Define named constants for macro types (simulating enums)
local MacroTypes = {
    DOING_NOTHING = 0,
    JUDGEMENT_OF_LIGHT = 1,
    DIVINE_STORM = 2,
    CRUSADER_STRIKE = 3,
    HAMMER_OF_WRATH = 4,
    CONSECRATION = 5,
    EXORCISM = 6,
    DIVINE_PLEA = 7,
    AVENGING_WRATH = 8
}

-- Map of macro strings for each key (0 to n)
local macroMap = {
    [MacroTypes.JUDGEMENT_OF_LIGHT] = [[/use 10;
/cast [target=focustarget] Judgement of Light]],
    [MacroTypes.DIVINE_STORM] = [[/use 10;
/cast [target=focustarget] Divine Storm]],
    [MacroTypes.CRUSADER_STRIKE] = [[/use 10;
/cast [target=focustarget] Crusader Strike]],
    [MacroTypes.HAMMER_OF_WRATH] = [[/use 10;
/cast [target=focustarget] Hammer of Wrath]],
    [MacroTypes.CONSECRATION] = [[/use 10;
/cast [target=focustarget] Consecration]],
    [MacroTypes.EXORCISM] = [[/use 10;
/cast [target=focustarget] Exorcism]],
    [MacroTypes.DIVINE_PLEA] = "/cast Divine Plea",
    [MacroTypes.AVENGING_WRATH] = "/cast Avenging Wrath",
    [MacroTypes.DOING_NOTHING] = "/run print(\"Doing nothing\")"
}


-- Function to return a tuple (key, target) based on current conditions
local function getRetriPaladinMacro()
    if not UnitAffectingCombat("player") or IsMounted()  then
        return MacroTypes.DOING_NOTHING, 0
    end
    local startJ, durationJ = GetSpellCooldown("Judgement of Light")
    if startJ <= 0.1 then
        return MacroTypes.JUDGEMENT_OF_LIGHT, 0
    end
    local startJ, durationJ = GetSpellCooldown("Avenging Wrath")
    if startJ <= 0.1 then
        return MacroTypes.AVENGING_WRATH, 0
    end
    local startJ, durationJ = GetSpellCooldown("Divine Storm")
    if startJ <= 0.1 then
        return MacroTypes.DIVINE_STORM, 0
    end
    local startJ, durationJ = GetSpellCooldown("Crusader Strike")
    if startJ <= 0.1 then
        return MacroTypes.CRUSADER_STRIKE, 0
    end
    local startJ, durationJ = GetSpellCooldown("Hammer of Wrath")
    local health = UnitHealth("focustarget")
    local maxHealth = UnitHealthMax("focustarget")
    if startJ <= 0.1  and health/maxHealth < 0.2 then
        return MacroTypes.HAMMER_OF_WRATH, 0
    end
    local startJ, durationJ = GetSpellCooldown("Consecration")
    if startJ <= 0.1 then
        return MacroTypes.CONSECRATION, 0
    end
    local startJ, durationJ = GetSpellCooldown("Exorcism")
    if startJ <= 0.1 and UnitBuff("player", "The Art of War") then
        return MacroTypes.EXORCISM, 0
    end
    local startJ, durationJ = GetSpellCooldown("Divine Plea")
    if startJ <= 0.1 then
        return MacroTypes.DIVINE_PLEA, 0
    end
    return MacroTypes.DOING_NOTHING, 0
end

-- Initialize keybinds for macros in macroMap using secure buttons and SetBindingClick
local function initRetriPaladinKeybinds()
    local macroKeys = {
        [MacroTypes.JUDGEMENT_OF_LIGHT] = "F1",
        [MacroTypes.DIVINE_STORM] = "F2",
        [MacroTypes.CRUSADER_STRIKE] = "F3",
        [MacroTypes.HAMMER_OF_WRATH] = "F4",
        [MacroTypes.CONSECRATION] = "F5",
        [MacroTypes.EXORCISM] = "F6",
        [MacroTypes.DIVINE_PLEA] = "F7",
        [MacroTypes.AVENGING_WRATH] = "F8",
        [MacroTypes.DOING_NOTHING] = "F9",
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
RetriPaladin = {
    MacroTypes = MacroTypes,
    macroMap = macroMap,
    getRetriPaladinMacro = getRetriPaladinMacro,
    initRetriPaladinKeybinds = initRetriPaladinKeybinds
}
