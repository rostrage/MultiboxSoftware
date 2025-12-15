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
/stopmacro [channeling]
/cast [target=focustarget] Mind Flay]],
    [MacroTypes.SHADOWFIEND] = [[/use 10
/cast [target=focustarget] Shadowfiend]],
    [MacroTypes.DISPERSION] = "/cast Dispersion",
    [MacroTypes.DOING_NOTHING] = "/stopcasting"
}

local lastVampiricTouchAppliedAt = 0

-- ========= DEBUG FLAG =========
local isDebug = false
local function debug(msg)
    if isDebug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[ShadowPriest]|r " .. msg)
    end
end
-- ============================

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
local function getShadowPriestMacro()
    
    if UnitIsDeadOrGhost("player") or IsMounted()  then
        return MacroTypes.DOING_NOTHING, 0
    end

    -- Use Dispersion if low on mana
    local currentMana = UnitPower("player", 0)
    if currentMana and currentMana < 1000 then
        debug("ACTION: Dispersion. (Low mana: " .. currentMana .. ")")
        return MacroTypes.DISPERSION, 0
    end

    -- Check if any buffs are missing
    local missingBuffs = {}
    if not (UnitBuff("player", "Divine Spirit") or UnitBuff("player", "Prayer of Spirit")) then
        table.insert(missingBuffs, "Divine Spirit")
    end
    if not (UnitBuff("player", "Power Word: Fortitude") or UnitBuff("player", "Prayer of Fortitude")) then
        table.insert(missingBuffs, "Power Word: Fortitude")
    end
    if not UnitBuff("player", "Shadowform") then
        table.insert(missingBuffs, "Shadowform")
    end
    if not UnitBuff("player", "Vampiric Embrace") then
        table.insert(missingBuffs, "Vampiric Embrace")
    end
    if not UnitBuff("player", "Inner Fire") then
        table.insert(missingBuffs, "Inner Fire")
    end
    
    if #missingBuffs > 0 then
        debug("ACTION: Buff sequence. (Missing buffs: " .. table.concat(missingBuffs, ", ") .. ")")
        return MacroTypes.BUFF_SEQUENCE, 0
    end

    if not UnitAffectingCombat("focus") then
        return MacroTypes.DOING_NOTHING, 0
    end

    -- Check focus target for debuffs
    local focusName, _ = UnitName("focustarget")
    if focusName and not UnitIsDeadOrGhost("focustarget") then
        debug("---------- New Rotation Tick ----------")
        local gcd = getSpellCooldownRemaining("Devouring Plague")
        local start, duration, enabled, modRate = GetSpellCooldown("Shadowfiend")
        if start <= gcd and not UnitBuff("player", "Shadowfiend") then
            -- Highest priority in combat: Shadowfiend
            debug("ACTION: Shadowfiend. (Available)")
            return MacroTypes.SHADOWFIEND, 0
        end
        debug(string.format("Condition: Shadowfiend CD=%.1f", start))
        
        -- Check for Vampiric Touch on focus
        if not UnitAura("focustarget", "Vampiric Touch", nil, "PLAYER|HARMFUL") and GetTime() > lastVampiricTouchAppliedAt + 2 then
            debug("ACTION: Vampiric Touch. (Not on target, cooldown ready)")
            return MacroTypes.VAMPIRIC_TOUCH, 0
        end
        debug("Condition: Vampiric Touch is on target or on cooldown")

        -- Check for Devouring Plague on focus
        if not UnitAura("focustarget", "Devouring Plague", nil, "PLAYER|HARMFUL") then
            debug("ACTION: Devouring Plague. (Not on target)")
            return MacroTypes.DEVOURING_PLAGUE, 0
        end
        debug("Condition: Devouring Plague is on target")

        -- Check for Shadow Word: Pain on focus
        if not UnitAura("focustarget", "Shadow Word: Pain", nil, "PLAYER|HARMFUL") then
            debug("ACTION: Shadow Word: Pain. (Not on target)")
            return MacroTypes.SHADOW_WORD_PAIN, 0
        end
        debug("Condition: Shadow Word: Pain is on target")
        
        -- Cast Mind Flay as lowest priority
        debug("ACTION: Mind Flay. (All debuffs present, filler)")
        return MacroTypes.MIND_FLAY, 0
    end

    debug("ACTION: Doing nothing. (No valid focus target)")
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
