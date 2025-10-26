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

-- Function to return a tuple (key, target) based on current conditions
local function getDemonologyWarlockMacro()
    
    if UnitIsDeadOrGhost("player") or IsMounted()  then
        return MacroTypes.DOING_NOTHING, 0
    end

    if not UnitAffectingCombat("player") then
        return MacroTypes.DOING_NOTHING, 0
    end



    -- Check focus target for debuffs and damage rotation
    local focusName, _ = UnitName("focustarget")
    if focusName and not UnitIsDeadOrGhost("focustarget") then
        -- Check if any buffs are missing
        if not UnitBuff("player", "Fel Armor") or 
        not UnitBuff("player", "Soul Link") or 
        not UnitBuff("player", "Master Demonologist") then
            return MacroTypes.BUFF_SEQUENCE, 0
        end 
        -- Check for Life Tap buff (highest priority in combat)
        -- 655 mana is the minimum to cast most spells in our rotation, so it's double that so we cast it immediately after our last spell that consumed mana
        if not UnitBuff("player", "Life Tap") or UnitPower("player", 0) < 1310 then
            return MacroTypes.LIFE_TAP, 0
        end

        -- Check for Curse of Doom on focus
        local start, duration, enabled, modRate = GetSpellCooldown("Curse of Doom")
        if not UnitDebuff("focustarget", "Curse of Doom") and start <= 0.1  then
            return MacroTypes.CURSE_OF_DOOM, 0
        end

        -- Check for Immolate on focus (with debouncing)
        if not UnitDebuff("focustarget", "Immolate") and GetTime() > lastImmolateAppliedAt + 2 then
            return MacroTypes.IMMOLATE, 0
        end

        -- Check if focus target has Shadow Mastery
        if not UnitDebuff("focustarget", "Shadow Mastery") then
            return MacroTypes.SHADOW_BOLT, 0
        end

        -- Check for Corruption on focus
        if not UnitDebuff("focustarget", "Corruption") then
            return MacroTypes.CORRUPTION, 0
        end
        
        -- Check for Metamorphosis cooldown
        local start, duration, enabled, modRate = GetSpellCooldown("Metamorphosis")
        if start <= 0.1 then
            return MacroTypes.METAMORPHOSIS, 0
        end

        -- Check for Immolation Aura cooldown
        local start, duration, enabled, modRate = GetSpellCooldown("Immolation Aura")
        if start <= 0.1 and UnitBuff("player", "Metamorphosis") then
            return MacroTypes.IMMOLATION_AURA, 0
        end

        -- Check for Decimation buff
        if UnitBuff("player", "Decimation") then
            return MacroTypes.SOUL_FIRE, 0
        end

        -- Check for Molten Core buff
        if UnitBuff("player", "Molten Core") then
            return MacroTypes.INCINERATE, 0
        end
        
        -- Fallback to Shadow Bolt
        return MacroTypes.SHADOW_BOLT, 0
    end

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
