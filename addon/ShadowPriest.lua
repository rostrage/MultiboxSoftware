-- Define named constants for macro types (simulating enums)
local MacroTypes = {
    DOING_NOTHING = 0,
    BUFF_SEQUENCE = 1,
    VAMPIRIC_TOUCH = 2,
    DEVOURING_PLAGUE = 3,
    SHADOW_WORD_PAIN = 4,
    MIND_FLAY = 5,
    SHADOWFIEND = 6,
    DISPERSION = 7,
}

-- Map of macro strings for each key (0 to n)
local macroMap = {
    [MacroTypes.BUFF_SEQUENCE] = "/castsequence Divine Spirit, Power Word: Fortitude, Shadow Protection, Shadowform, Vampiric Embrace, Inner Fire",
    [MacroTypes.VAMPIRIC_TOUCH] = [[/use 10
/cast [target=focustarget] Vampiric Touch]],
    [MacroTypes.DEVOURING_PLAGUE] = "/cast [target=focustarget] Devouring Plague",
    [MacroTypes.SHADOW_WORD_PAIN] = [[/use 10
/cast [target=focustarget] Shadow Word: Pain]],
    [MacroTypes.MIND_FLAY] = [[/use 10
/cast [target=focustarget] Mind Flay]],
    [MacroTypes.SHADOWFIEND] = [[/use 10
/cast [target=focustarget] Shadowfiend]],
    [MacroTypes.DISPERSION] = "/cast Dispersion",
    [MacroTypes.DOING_NOTHING] = "/stopcasting"
}

local lastVampiricTouchAppliedAt = 0

-- Used to debounce Vampiric Touch applications
local function onUnitSpellcastStart(self, event, unitTarget, spellName, spellRank)
    if spellName == "Vampiric Touch" then
        lastVampiricTouchAppliedAt = GetTime()
    end
end

local function ensureAuraFrame()
    if _G.ShadowPriestAuraFrame then return end
    local f = CreateFrame("Frame")
    f:RegisterEvent("UNIT_SPELLCAST_START")
    f:SetScript("OnEvent", onUnitSpellcastStart)
    _G.ShadowPriestAuraFrame = f
end

-- Function to return a tuple (key, target) based on current conditions
local function getShadowPriestMacro()
    
    if UnitIsDeadOrGhost("player") or IsMounted()  then
        return MacroTypes.DOING_NOTHING, 0
    end

    -- Use Dispersion if low on mana and not in combat
    local currentMana = UnitPower("player", 0)
    if currentMana and currentMana < 1000 and not UnitAffectingCombat("player") then
        return MacroTypes.DISPERSION, 0
    end

    -- Check if any buffs are missing
    if not (UnitBuff("player", "Divine Spirit") or UnitBuff("player", "Prayer of Spirit")) or 
       not (UnitBuff("player", "Power Word: Fortitude") or UnitBuff("player", "Prayer of Fortitude")) or 
       not UnitBuff("player", "Shadowform") or 
       not UnitBuff("player", "Vampiric Embrace") or 
       not UnitBuff("player", "Inner Fire") then
        return MacroTypes.BUFF_SEQUENCE, 0
    end

    if not UnitAffectingCombat("player") then
        return MacroTypes.DOING_NOTHING, 0
    end

    -- Check focus target for debuffs
    local focusName, _ = UnitName("focustarget")
    if focusName and not UnitIsDeadOrGhost("focustarget") then
        local start, duration, enabled, modRate = GetSpellCooldown("Shadowfiend")
        if start <= 0.1 and not UnitBuff("player", "Shadowfiend") then
            -- Highest priority in combat: Shadowfiend
            return MacroTypes.SHADOWFIEND, 0
        end
        
        -- Check for Vampiric Touch on focus
        if not UnitDebuff("focustarget", "Vampiric Touch") and GetTime() > lastVampiricTouchAppliedAt + 2 then
            return MacroTypes.VAMPIRIC_TOUCH, 0
        end

        -- Check for Devouring Plague on focus
        if not UnitDebuff("focustarget", "Devouring Plague") then
            return MacroTypes.DEVOURING_PLAGUE, 0
        end

        -- Check for Shadow Word: Pain on focus
        if not UnitDebuff("focustarget", "Shadow Word: Pain") then
            return MacroTypes.SHADOW_WORD_PAIN, 0
        end
        
        -- Cast Mind Flay as lowest priority
        return MacroTypes.MIND_FLAY, 0
    end

    return MacroTypes.DOING_NOTHING, 0
end

-- Initialize keybinds for macros in macroMap using secure buttons and SetBindingClick
local function initShadowPriestKeybinds()
    local macroKeys = {
        [MacroTypes.BUFF_SEQUENCE] = "F1",
        [MacroTypes.VAMPIRIC_TOUCH] = "F2",
        [MacroTypes.DEVOURING_PLAGUE] = "F3",
        [MacroTypes.SHADOW_WORD_PAIN] = "F4",
        [MacroTypes.MIND_FLAY] = "F5",
        [MacroTypes.SHADOWFIEND] = "F6",
        [MacroTypes.DISPERSION] = "F7"
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
ShadowPriest = {
    MacroTypes = MacroTypes,
    macroMap = macroMap,
    getShadowPriestMacro = getShadowPriestMacro,
    initShadowPriestKeybinds = initShadowPriestKeybinds
}
