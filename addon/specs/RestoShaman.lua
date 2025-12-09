-- Define named constants for macro types (simulating enums)

local lastHealOnTarget = {}

local function onUnitSpellcastSent(self, event, unit, spellName, _, targetName)
    if unit == "player" and targetName then
        if spellName == "Chain Heal" or spellName == "Lesser Healing Wave" or spellName == "Riptide" then
            lastHealOnTarget[targetName] = GetTime()
        end
    end
end

local function ensureAuraFrame()
    if _G.RestoShamanAuraFrame then return end
    local f = CreateFrame("Frame")
    f:RegisterEvent("UNIT_SPELLCAST_SENT")
    f:SetScript("OnEvent", onUnitSpellcastSent)
    _G.RestoShamanAuraFrame = f
end

local MacroTypes = {
    DOING_NOTHING = 0,
    WATER_SHIELD = 1,
    EARTHLIVING_WEAPON = 2,
    EARTH_SHIELD_FOCUS = 3,
    CHAIN_HEAL = 4,
    LESSER_HEALING_WAVE = 5,
    RIPTIDE = 6,
    STOP_CASTING = 7
}

-- Map of macro strings for each key (0 to n)
local macroMap = {
    [MacroTypes.DOING_NOTHING] = "/stopcasting",
    [MacroTypes.WATER_SHIELD] = "/cast Water Shield",
    [MacroTypes.EARTHLIVING_WEAPON] = "/cast Earthliving Weapon",
    [MacroTypes.EARTH_SHIELD_FOCUS] = "/cast [target=focus] Earth Shield",
    [MacroTypes.CHAIN_HEAL] = "/cast Chain Heal",
    [MacroTypes.LESSER_HEALING_WAVE] = "/cast Lesser Healing Wave",
    [MacroTypes.RIPTIDE] = "/cast Riptide",
    [MacroTypes.STOP_CASTING] = [[/stopcasting
/assist focus]]
}

-- Function to return a tuple (key, target) based on current conditions
local function getRestoShamanMacro()
    
    if  UnitIsDeadOrGhost("player") or IsMounted() then
        return MacroTypes.DOING_NOTHING, 0
    end

    if not UnitBuff("player", "Water Shield") then
        return MacroTypes.WATER_SHIELD, 0
    end

    if not GetWeaponEnchantInfo() then
        return MacroTypes.EARTHLIVING_WEAPON, 0
    end

    local focusName, _ = UnitName("focus")
    if focusName and UnitInRange("focus") and not UnitBuff("focus", "Earth Shield") and not UnitIsDeadOrGhost("focus") and not UnitIsEnemy(u) then
        return MacroTypes.EARTH_SHIELD_FOCUS, 0
    end

    if not UnitAffectingCombat("focus") then
        return MacroTypes.DOING_NOTHING, 0
    end

    local numtargets = 0
    local target = 0
    local targetPercent = 0.95
    local raidmembers = GetNumRaidMembers()
    if raidmembers == 0 then
        for i = 1, 4 do
            local u = GetUnitName("party" .. i)
            if UnitIsPlayer(u) and UnitInRange(u) and not UnitIsDeadOrGhost(u) and not UnitIsEnemy(u) then
                local health = UnitHealth(u)
                local maxHealth = UnitHealthMax(u)
                local percent = health / maxHealth

                if percent < 0.95 then
                    numtargets = numtargets + 1
                    if percent < targetPercent then
                        if not lastHealOnTarget[u] or GetTime() > lastHealOnTarget[u] + 2.5 then
                            targetPercent = percent
                            target = i
                        end
                    end
                end
            end
        end
        local u = GetUnitName("player")
        if UnitIsPlayer(u) and UnitInRange(u) then
            local health = UnitHealth(u)
            local maxHealth = UnitHealthMax(u)
            local percent = health / maxHealth

            if percent < 0.95 then
                numtargets = numtargets + 1
                if percent < targetPercent then
                    if not lastHealOnTarget[u] or GetTime() > lastHealOnTarget[u] + 2.5 then
                        targetPercent = percent
                        target = 5
                    end
                end
            end
        end
    else 
        for i = 1, GetNumRaidMembers() do
            local u = GetUnitName("raid" .. i)
            if UnitIsPlayer(u) and UnitInRange(u) and not UnitIsDeadOrGhost(u) then
                local health = UnitHealth(u)
                local maxHealth = UnitHealthMax(u)
                local percent = health / maxHealth

                if percent < 0.95 then
                    numtargets = numtargets + 1
                    if percent < targetPercent then
                        if not lastHealOnTarget[u] or GetTime() > lastHealOnTarget[u] + 2.5 then
                            targetPercent = percent
                            target = i
                        end
                    end
                end
            end
        end
    end
    if numtargets > 2 then
        local start, duration, enabled, modRate = GetSpellCooldown("Riptide")
        if start > 0 and duration > 0 then
            return MacroTypes.CHAIN_HEAL, target
        else
            return MacroTypes.RIPTIDE, target
        end
    elseif numtargets > 0 then
        local start, duration, enabled, modRate = GetSpellCooldown("Riptide")
        if start > 0 and duration > 0 then
            return MacroTypes.LESSER_HEALING_WAVE, target
        else
            return MacroTypes.RIPTIDE, target
        end
    else
        return MacroTypes.STOP_CASTING, 0
    end
end

-- Initialize keybinds for macros in macroMap using secure buttons and SetBindingClick
local function initRestoShamanKeybinds()
    local macroKeys = {
        [MacroTypes.WATER_SHIELD] = "F1",
        [MacroTypes.EARTHLIVING_WEAPON] = "F2",
        [MacroTypes.EARTH_SHIELD_FOCUS] = "F3",
        [MacroTypes.CHAIN_HEAL] = "F4",
        [MacroTypes.LESSER_HEALING_WAVE] = "F5",
        [MacroTypes.RIPTIDE] = "F6",
        [MacroTypes.STOP_CASTING] = "F7"
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
RestoShaman = {
    MacroTypes = MacroTypes,
    macroMap = macroMap,
    getRestoShamanMacro = getRestoShamanMacro,
    initRestoShamanKeybinds = initRestoShamanKeybinds
}
