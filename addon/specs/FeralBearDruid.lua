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
/cancelaura Divine Intervention
/cancelaura Hand of Protection
/use [target=focustarget] Faerie Fire (Feral)]],
    [MacroTypes.ENRAGE] = "/use Enrage",
    [MacroTypes.MANGLE_BEAR] = [[/use !Maul
/use 10
/startattack
/cancelaura Divine Intervention
/cancelaura Hand of Protection
/use [target=focustarget] Mangle (Bear)]],
    [MacroTypes.BERSERK] = "/use Berserk",
    [MacroTypes.LACERATE] = [[/use !Maul
/use 10
/startattack
/cancelaura Divine Intervention
/cancelaura Hand of Protection
/use [target=focustarget] Lacerate]],
    [MacroTypes.SWIPE_BEAR] = [[/use !Maul
/use 10
/startattack
/cancelaura Divine Intervention
/cancelaura Hand of Protection
/use [target=focustarget] Swipe (Bear)]],
    [MacroTypes.DOING_NOTHING] = "/run print(\"Doing nothing\")"
}

-- ========= DEBUG FLAG =========
local isDebug = false
local function debug(msg)
    if isDebug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[FeralBearDruid]|r " .. msg)
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
local function getFeralBearDruidMacro()

    if not UnitAffectingCombat("focus") or IsMounted() then
        return MacroTypes.DOING_NOTHING, 0
    end

    -- Check if focustarget exists
    if not UnitExists("focustarget") then
        return MacroTypes.DOING_NOTHING, 0
    end
    
    debug("---------- New Rotation Tick ----------") 
    local gcd = getSpellCooldownRemaining("Lacerate")
   
    -- 1. If the focustarget does not have the Faerie Fire (Feral) debuff, return Faerie Fire (Feral)
    if not UnitDebuff("focustarget", "Faerie Fire (Feral)") then
        debug("ACTION: Faerie Fire (Feral). (Debuff not on target)")
        return MacroTypes.FAERIE_FIRE_FERAL, 0
    end
    debug("Condition: Faerie Fire is on target.")
    
    -- 2. If Enrage is available, return Enrage
    local enrageStart, enrageDuration = getSpellCooldownRemaining("Enrage")
    if enrageStart <= 0.1 then
        debug("ACTION: Enrage. (Available)")
        return MacroTypes.ENRAGE, 0
    end
    debug(string.format("Condition: Enrage CD=%.1f", enrageStart))
    
    local _, _, _, lacerateStacks, _, lacerateDuration, lacerateExpirationTime = UnitAura("focustarget", "Lacerate", nil, "PLAYER|HARMFUL")
    local lacerateRemains = (lacerateExpirationTime or 0) - GetTime()

    if (lacerateStacks or 0) == 5 and lacerateRemains <= 5.0 then
        debug(string.format("ACTION: Lacerate. (Stacks=%d, Duration=%.1f)", lacerateStacks or 0, lacerateRemains or 0))
        return MacroTypes.LACERATE, 0
    end
    
    -- 3. If the Mangle (Bear) is available, return Mangle (Bear)
    local start, duration = getSpellCooldownRemaining("Mangle (Bear)")
    if start <= gcd then
        debug("ACTION: Mangle (Bear). (Available)")
        return MacroTypes.MANGLE_BEAR, 0
    end
    debug(string.format("Condition: Mangle CD=%.1f", start))
    
    -- 4. If the focustarget does not have 5 stacks of Lacerate, return Lacerate

    if (lacerateStacks or 0) < 5 or lacerateRemains <= 5.0 then
        debug(string.format("ACTION: Lacerate. (Stacks=%d, Duration=%.1f)", lacerateStacks or 0, lacerateRemains or 0))
        return MacroTypes.LACERATE, 0
    end
    debug(string.format("Condition: Lacerate has %d stacks with %.1f duration.", lacerateStacks or 0, lacerateRemains or 0))
        
    -- 5. If Berserk is available, return Berserk
    local berserkStart, berserkDuration = getSpellCooldownRemaining("Berserk")
    if berserkStart <= gcd then
        debug("ACTION: Berserk. (Available)")
        return MacroTypes.BERSERK, 0
    end
    debug(string.format("Condition: Berserk CD=%.1f", berserkStart))

    -- 6. If Faerie Fire (Feral) is off cooldown, use it (low priority filler)
    local ffStart, ffDuration = getSpellCooldownRemaining("Faerie Fire (Feral)")
    if ffStart <= gcd then
        debug("ACTION: Faerie Fire (Feral). (Off cooldown, low priority filler)")
        return MacroTypes.FAERIE_FIRE_FERAL, 0
    end
    debug(string.format("Condition: Faerie Fire (Feral) CD=%.1f", ffStart))

    -- 7. Otherwise return Swipe (Bear)
    debug("ACTION: Swipe (Bear). (Filler)")
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
