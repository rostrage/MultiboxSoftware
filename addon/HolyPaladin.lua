-- Define named constants for macro types (simulating enums)
local MacroTypes = {
    DOING_NOTHING = 0
    BEACON_OF_LIGHT = 1,
    DIVINE_PLEA = 2,
    JUDGEMENT_OF_LIGHT = 3,
    HOLY_LIGHT = 4,
}

-- Map of macro strings for each key (0 to n)
local macroMap = {
    [MacroTypes.BEACON_OF_LIGHT] = "/cast [target=focus] Beacon of Light",
    [MacroTypes.DIVINE_PLEA] = "/cast Divine Plea",
    [MacroTypes.JUDGEMENT_OF_LIGHT] = "/cast [target=focustarget] Judgement of Light",
    [MacroTypes.HOLY_LIGHT] = "/cast [target=raidX] Holy Light", -- Dynamic target will be handled at runtime
    [MacroTypes.DOING_NOTHING] = "/run print(\"Doing nothing\")"
}

-- Function to return a tuple (key, target) based on current conditions
local function getHolyPaladinMacro()
    local focusName, _ = UnitName("focus")

    -- 1. Cast Beacon of Light if not already on focus
    if not UnitBuff("focus", "Beacon of Light") then
        return MacroTypes.BEACON_OF_LIGHT, 0
    end

    -- 2. Use Divine Plea when mana is low and off cooldown
    local currentMana = UnitPower("player", 0)
    local maxMana = UnitPowerMax("player", 0)
    if currentMana < maxMana * 0.75 then
        local start, duration = GetSpellCooldown("Divine Plea")
        if start == 0 then
            return MacroTypes.DIVINE_PLEA, 0
        end
    end

    -- 3. Cast Judgement of Light on focustarget when off cooldown
    local startJ, durationJ = GetSpellCooldown("Judgement of Light")
    if startJ == 0 then
        return MacroTypes.JUDGEMENT_OF_LIGHT, 0
    end

    -- 4. Loop through raid members and find lowest HP non-focus target
    local targetIndex = 0
    local lowestPercent = 1.0

    for i = 1, GetNumRaidMembers() do
        local unit = "raid" .. i
        if UnitIsPlayer(unit) and UnitInRange(unit) then
            local name = UnitName(unit)
            if name == focusName then continue end -- Skip the focus target

            local health = UnitHealth(unit)
            local maxHealth = UnitHealthMax(unit)
            local percent = health / maxHealth

            if percent < lowestPercent then
                lowestPercent = percent
                targetIndex = i
            end
        end
    end

    if lowestPercent < 1.0 then
        return MacroTypes.HOLY_LIGHT, targetIndex
    else
        -- No raid members in need; check focus now (focus is last priority)
        local focusHealth = UnitHealth("focus")
        local focusMaxHealth = UnitHealthMax("focus")

        if focusHealth < focusMaxHealth then
            return MacroTypes.HOLY_LIGHT, 0
        else
            return MacroTypes.DOING_NOTHING, 0
        end
    end
end

-- Initialize keybinds for macros in macroMap using secure buttons and SetBindingClick
local function initHolyPaladinKeybinds()
    local macroKeys = {
        [MacroTypes.BEACON_OF_LIGHT] = "F1",
        [MacroTypes.DIVINE_PLEA] = "F2",
        [MacroTypes.JUDGEMENT_OF_LIGHT] = "F3",
        [MacroTypes.HOLY_LIGHT] = "F4",
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
HolyPaladin = {
    MacroTypes = MacroTypes,
    macroMap = macroMap,
    getHolyPaladinMacro = getHolyPaladinMacro,
    initHolyPaladinKeybinds = initHolyPaladinKeybinds
}
