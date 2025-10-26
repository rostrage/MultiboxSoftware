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


-- ========= DEBUG FLAG =========
local isDebug = true
local function debug(msg)
    if isDebug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[RetriPaladin]|r " .. msg)
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
local function getRetriPaladinMacro()
    debug("---------- New Rotation Tick ----------")
    if not UnitAffectingCombat("player") or IsMounted() then
        debug("Player not in combat or is mounted. Doing nothing.")
        return MacroTypes.DOING_NOTHING, 0
    end
    
    -- Check if focustarget exists
    if not UnitExists("focustarget") then
        debug("Focus target does not exist. Doing nothing.")
        return MacroTypes.DOING_NOTHING, 0
    end
    
    debug("Player in combat, not mounted, and focustarget exists. Evaluating rotation.")

    -- 1. Judgement of Light
    local judgementCooldown = getSpellCooldownRemaining("Judgement of Light")
    if judgementCooldown <= 0.2 then
        debug("ACTION: Judgement of Light. (Available)")
        return MacroTypes.JUDGEMENT_OF_LIGHT, 0
    end
    debug(string.format("Condition: Judgement of Light CD=%.1f", judgementCooldown))
    
    -- 2. Avenging Wrath
    local avengingWrathCooldown = getSpellCooldownRemaining("Avenging Wrath")
    if avengingWrathCooldown <= 0.2 then
        debug("ACTION: Avenging Wrath. (Available)")
        return MacroTypes.AVENGING_WRATH, 0
    end
    debug(string.format("Condition: Avenging Wrath CD=%.1f", avengingWrathCooldown))

    -- 3. Divine Storm
    local divineStormCooldown = getSpellCooldownRemaining("Divine Storm")
    if divineStormCooldown <= 0.2 then
        debug("ACTION: Divine Storm. (Available)")
        return MacroTypes.DIVINE_STORM, 0
    end
    debug(string.format("Condition: Divine Storm CD=%.1f", divineStormCooldown))

    -- 4. Crusader Strike
    local crusaderStrikeCooldown = getSpellCooldownRemaining("Crusader Strike")
    if crusaderStrikeCooldown <= 0.2 then
        debug("ACTION: Crusader Strike. (Available)")
        return MacroTypes.CRUSADER_STRIKE, 0
    end
    debug(string.format("Condition: Crusader Strike CD=%.1f", crusaderStrikeCooldown))

    -- 5. Hammer of Wrath
    local hammerOfWrathCooldown = getSpellCooldownRemaining("Hammer of Wrath")
    local health = UnitHealth("focustarget")
    local maxHealth = UnitHealthMax("focustarget")
    if maxHealth > 0 then
        local healthPercent = (health / maxHealth) * 100
        if hammerOfWrathCooldown <= 0.2 and healthPercent < 20 then
            debug(string.format("ACTION: Hammer of Wrath. (Available and target health is %.1f%%)", healthPercent))
            return MacroTypes.HAMMER_OF_WRATH, 0
        end
        debug(string.format("Condition: Hammer of Wrath CD=%.1f, Target Health=%.1f%%", hammerOfWrathCooldown, healthPercent))
    else
        debug("Condition: Hammer of Wrath cannot be evaluated, target has 0 max health.")
    end

    -- 6. Consecration
    local consecrationCooldown = getSpellCooldownRemaining("Consecration")
    if consecrationCooldown <= 0.2 then
        debug("ACTION: Consecration. (Available)")
        return MacroTypes.CONSECRATION, 0
    end
    debug(string.format("Condition: Consecration CD=%.1f", consecrationCooldown))

    -- 7. Exorcism
    local exorcismCooldown = getSpellCooldownRemaining("Exorcism")
    if exorcismCooldown <= 0.2 and UnitBuff("player", "The Art of War") then
        debug("ACTION: Exorcism. (Available with The Art of War buff)")
        return MacroTypes.EXORCISM, 0
    end
    debug(string.format("Condition: Exorcism CD=%.1f, Art of War buff: %s", exorcismCooldown, tostring(UnitBuff("player", "The Art of War"))))

    -- 8. Divine Plea
    local divinePleaCooldown = getSpellCooldownRemaining("Divine Plea")
    if divinePleaCooldown <= 0.2 then
        debug("ACTION: Divine Plea. (Available)")
        return MacroTypes.DIVINE_PLEA, 0
    end
    debug(string.format("Condition: Divine Plea CD=%.1f", divinePleaCooldown))

    debug("ACTION: Doing nothing. (No abilities available)")
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
