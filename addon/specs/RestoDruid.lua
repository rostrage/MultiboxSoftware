-- Define named constants for macro types (simulating enums)
local MacroTypes = {
    DOING_NOTHING = 0,
    WILD_GROWTH = 1,
    REJUVENATION = 2,
    SWIFTMEND = 3,
    NOURISH = 4
}

-- Map of macro strings for each key (0 to n)
local macroMap = {
    [MacroTypes.WILD_GROWTH] = "/cast Wild Growth",
    [MacroTypes.REJUVENATION] = "/cast Rejuvenation", -- Dynamic target will be handled at runtime
    [MacroTypes.SWIFTMEND] = "/cast Swiftmend", -- Dynamic target will be handled at runtime
    [MacroTypes.NOURISH] = "/cast Nourish", -- Dynamic target will be handled at runtime
    [MacroTypes.DOING_NOTHING] = "/stopcasting"
}

-- ========= DEBUG FLAG =========
local isDebug = true
local function debug(msg)
    if isDebug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[RestoDruid]|r " .. msg)
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
local function getRestoDruidMacro()
    
    if not UnitAffectingCombat("focus")  then
        return MacroTypes.DOING_NOTHING, 0
    end
    
    debug("---------- New Rotation Tick ----------")

    -- 1. If wild growth is off cooldown, cast wild growth on target 0
    local wildGrowthCooldown = getSpellCooldownRemaining("Wild Growth")
    if wildGrowthCooldown <= 0.2 then
        debug("ACTION: Wild Growth. (Available on target 0)")
        return MacroTypes.WILD_GROWTH, 0
    end
    debug(string.format("Condition: Wild Growth CD=%.1f", wildGrowthCooldown))

    -- 2. Cast rejuvenation on any raid members that do not have rejuvenation
    local rejuvenationTarget = 0
    local foundRejuvenationTarget = false
    
    for i = 1, GetNumRaidMembers() do
        local unit = "raid" .. i
        if UnitIsPlayer(unit) and UnitInRange(unit) and not UnitBuff(unit, "Rejuvenation") and not UnitIsDeadOrGhost(unit) then            
            -- Prioritize targets with lower health
            if not foundRejuvenationTarget then
                rejuvenationTarget = i
                foundRejuvenationTarget = true
            end
        end
    end
    
    if foundRejuvenationTarget then
        debug(string.format("ACTION: Rejuvenation. (Target %d needs rejuvenation)", rejuvenationTarget))
        return MacroTypes.REJUVENATION, rejuvenationTarget
    end
    debug("Condition: All raid members have rejuvenation.")

    -- 3. Find the lowest HP raid member for swiftmend/nourish
    local lowestHpTarget = 0
    local lowestHpPercent = 1.0
    local swiftmendCooldown = getSpellCooldownRemaining("Swiftmend")
    
    for i = 1, GetNumRaidMembers() do
        local unit = "raid" .. i
        if UnitIsPlayer(unit) and UnitInRange(unit) and not UnitIsDeadOrGhost(unit) then
            local health = UnitHealth(unit)
            local maxHealth = UnitHealthMax(unit)
            local percent = health / maxHealth
            
            if percent < lowestHpPercent then
                lowestHpPercent = percent
                lowestHpTarget = i
            end
        end
    end
    
    -- 4. If there's a valid target, decide between swiftmend and nourish
    if lowestHpPercent < 1.0 then
        if swiftmendCooldown <= 0.2 then
            debug(string.format("ACTION: Swiftmend. (Target %d at %.1f%% health)", lowestHpTarget, lowestHpPercent * 100))
            return MacroTypes.SWIFTMEND, lowestHpTarget
        else
            debug(string.format("ACTION: Nourish. (Target %d at %.1f%% health, Swiftmend on CD)", lowestHpTarget, lowestHpPercent * 100))
            return MacroTypes.NOURISH, lowestHpTarget
        end
    else
        debug("Condition: No valid raid members found")
    end

    -- 5. Otherwise, do nothing
    debug("ACTION: Doing nothing. (No actions available)")
    return MacroTypes.DOING_NOTHING, 0
end

-- Initialize keybinds for macros in macroMap using secure buttons and SetBindingClick
local function initRestoDruidKeybinds()
    local macroKeys = {
        [MacroTypes.WILD_GROWTH] = "F1",
        [MacroTypes.REJUVENATION] = "F2",
        [MacroTypes.SWIFTMEND] = "F3",
        [MacroTypes.NOURISH] = "F4",
        [MacroTypes.DOING_NOTHING] = "F5"
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
RestoDruid = {
    MacroTypes = MacroTypes,
    macroMap = macroMap,
    getRestoDruidMacro = getRestoDruidMacro,
    initRestoDruidKeybinds = initRestoDruidKeybinds
}