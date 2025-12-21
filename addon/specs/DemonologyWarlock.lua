-- Define named constants for macro types (simulating enums)
local MacroTypes = {
    DOING_NOTHING = 0,
    BUFF_SEQUENCE = 1,
    LIFE_TAP = 2,
    CORRUPTION = 3,
    CURSE_OF_DOOM = 4,
    IMMOLATE = 5,
    SHADOW_BOLT = 6,
    METAMORPHOSIS = 7,
    IMMOLATION_AURA = 8,
    SOUL_FIRE = 9,
    INCINERATE = 10,
}

-- Map of macro strings for each key (0 to n)
local macroMap = {
    [MacroTypes.BUFF_SEQUENCE] = "/castsequence Fel Armor, Summon Felguard, Soul Link",
    [MacroTypes.LIFE_TAP] = "/cast Life Tap",
    [MacroTypes.CORRUPTION] = [[/cast [pet:Felguard] Demonic Empowerment
/cast [target=focustarget] Corruption]],
    [MacroTypes.CURSE_OF_DOOM] = [[/cast [pet:Felguard] Demonic Empowerment
/cast [target=focustarget] Curse of Doom]],
    [MacroTypes.IMMOLATE] = [[/cast [pet:Felguard] Demonic Empowerment
/cast [target=focustarget] Immolate]],
    [MacroTypes.SHADOW_BOLT] = [[/use 10
/cast [pet:Felguard] Demonic Empowerment
/cast [target=focustarget] Shadow Bolt]],
    [MacroTypes.METAMORPHOSIS] = "/cast Metamorphosis",
    [MacroTypes.IMMOLATION_AURA] = "/cast Immolation Aura",
    [MacroTypes.SOUL_FIRE] = [[/use 10
/cast [pet:Felguard] Demonic Empowerment
/cast [target=focustarget] Soul Fire]],
    [MacroTypes.INCINERATE] = "/cast [target=focustarget] Incinerate",
    [MacroTypes.DOING_NOTHING] = "/stopcasting"
}

-- ========= DEBUG FLAG =========
local isDebug = true
local function debug(msg)
    if isDebug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[DemonologyWarlock]|r " .. msg)
    end
end
-- ============================

local lastImmolateAppliedAt = 0

-- Used to debounce Immolate applications
local function onUnitSpellcastStart(self, event, unitTarget, spellName, spellRank)
    if spellName == "Immolate" then
        lastImmolateAppliedAt = GetTime()
    end
end

local function ensureAuraFrame()
    if _G.DemonologyWarlockAuraFrame then return end
    local f = CreateFrame("Frame")
    f:RegisterEvent("UNIT_SPELLCAST_START")
    f:SetScript("OnEvent", onUnitSpellcastStart)
    _G.DemonologyWarlockAuraFrame = f
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
local function getDemonologyWarlockMacro()
    
    if UnitIsDeadOrGhost("player") or IsMounted()  then
        return MacroTypes.DOING_NOTHING, 0
    end

    if not UnitAffectingCombat("focus") then
        return MacroTypes.DOING_NOTHING, 0
    end

    -- Check focus target for debuffs and damage rotation
    local focusName, _ = UnitName("focustarget")
    if focusName and not UnitIsDeadOrGhost("focustarget") then
        debug("---------- New Rotation Tick ----------")        
    
        -- Check if any buffs are missing
        if not UnitBuff("player", "Fel Armor") or
        not UnitBuff("player", "Soul Link") or
        not UnitBuff("player", "Master Demonologist") then
            debug("ACTION: Buff Sequence. (Missing buffs)")
            return MacroTypes.BUFF_SEQUENCE, 0
        end
        debug("Condition: All buffs are active.")
        
        -- Check for Life Tap buff (highest priority in combat)
        -- 655 mana is the minimum to cast most spells in our rotation, so it's double that so we cast it immediately after our last spell that consumed mana
        local currentMana = UnitPower("player", 0)
        if not UnitBuff("player", "Life Tap") or currentMana < 1310 then
            debug(string.format("ACTION: Life Tap. (Life Tap buff missing or mana %d < 1310)", currentMana))
            return MacroTypes.LIFE_TAP, 0
        end
        debug(string.format("Condition: Life Tap buff active and mana %d >= 1310", currentMana))

        -- Check for Curse of Doom on focus
        local curseDoomCooldown = getSpellCooldownRemaining("Curse of Doom")
        if not UnitDebuff("focustarget", "Curse of Doom") and curseDoomCooldown <= 0.1 then
            debug("ACTION: Curse of Doom. (Not on target and off cooldown)")
            return MacroTypes.CURSE_OF_DOOM, 0
        end
        debug(string.format("Condition: Curse of Doom CD=%.1f, Debuff on target: %s", curseDoomCooldown, tostring(UnitDebuff("focustarget", "Curse of Doom"))))

        -- Check for Immolate on focus (with debouncing)
        if not UnitDebuff("focustarget", "Immolate") and GetTime() > lastImmolateAppliedAt + 2 then
            debug("ACTION: Immolate. (Not on target and debounced)")
            return MacroTypes.IMMOLATE, 0
        end
        debug(string.format("Condition: Immolate debuffed: %s, Last applied: %.1f ago", tostring(UnitDebuff("focustarget", "Immolate")), GetTime() - lastImmolateAppliedAt))

        -- Check if focus target has Shadow Mastery
        if not UnitDebuff("focustarget", "Shadow Mastery") then
            debug("ACTION: Shadow Bolt. (Shadow Mastery debuff missing)")
            return MacroTypes.SHADOW_BOLT, 0
        end
        debug("Condition: Shadow Mastery is on target.")

        -- Check for Corruption on focus
        if not UnitDebuff("focustarget", "Corruption") then
            debug("ACTION: Corruption. (Not on target)")
            return MacroTypes.CORRUPTION, 0
        end
        debug("Condition: Corruption is on target.")
        
        -- Check for Metamorphosis cooldown
        local metamorphosisCooldown = getSpellCooldownRemaining("Metamorphosis")
        if metamorphosisCooldown <= 0.1 then
            debug("ACTION: Metamorphosis. (Available)")
            return MacroTypes.METAMORPHOSIS, 0
        end
        debug(string.format("Condition: Metamorphosis CD=%.1f", metamorphosisCooldown))

        -- Check for Immolation Aura cooldown
        local immolationAuraCooldown = getSpellCooldownRemaining("Immolation Aura")
        if immolationAuraCooldown <= 0.1 and UnitBuff("player", "Metamorphosis") then
            debug("ACTION: Immolation Aura. (Available and in Metamorphosis)")
            return MacroTypes.IMMOLATION_AURA, 0
        end

        -- Check for Decimation buff
        if UnitBuff("player", "Decimation") then
            debug("ACTION: Soul Fire. (Decimation buff active)")
            return MacroTypes.SOUL_FIRE, 0
        end
        debug("Condition: Decimation buff not active.")

        -- Check for Molten Core buff
        if UnitBuff("player", "Molten Core") then
            debug("ACTION: Incinerate. (Molten Core buff active)")
            return MacroTypes.INCINERATE, 0
        end
        debug("Condition: Molten Core buff not active.")
        
        -- Fallback to Shadow Bolt
        debug("ACTION: Shadow Bolt. (Fallback)")
        return MacroTypes.SHADOW_BOLT, 0
    end

    debug("ACTION: Doing nothing. (Invalid focus target)")
    return MacroTypes.DOING_NOTHING, 0
end

-- Initialize keybinds for macros in macroMap using secure buttons and SetBindingClick
local function initDemonologyWarlockKeybinds()
    local macroKeys = {
        [MacroTypes.BUFF_SEQUENCE] = "F1",
        [MacroTypes.LIFE_TAP] = "F2",
        [MacroTypes.CORRUPTION] = "F3",
        [MacroTypes.CURSE_OF_DOOM] = "F4",
        [MacroTypes.IMMOLATE] = "F5",
        [MacroTypes.SHADOW_BOLT] = "F6",
        [MacroTypes.METAMORPHOSIS] = "F7",
        [MacroTypes.IMMOLATION_AURA] = "F8",
        [MacroTypes.SOUL_FIRE] = "F9",
        [MacroTypes.INCINERATE] = "F10"
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
DemonologyWarlock = {
    MacroTypes = MacroTypes,
    macroMap = macroMap,
    getDemonologyWarlockMacro = getDemonologyWarlockMacro,
    initDemonologyWarlockKeybinds = initDemonologyWarlockKeybinds
}
