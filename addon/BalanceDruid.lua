-- Define named constants for macro types (simulating enums)
local MacroTypes = {
    DOING_NOTHING = 0,
    MARK_OF_THE_WILD = 1,
    FAERIE_FIRE = 2,
    MOONFIRE = 3,
    INSECT_SWARM = 4,
    STARFALL = 5,
    STARFIRE = 6,
    WRATH = 7,
}

-- Map of macro strings for each action
local macroMap = {
    [MacroTypes.MARK_OF_THE_WILD] = "/cast [target=player] Mark of the Wild",
    [MacroTypes.FAERIE_FIRE] = "/cast [target=focustarget] Faerie Fire",
    [MacroTypes.MOONFIRE] = "/cast [target=focustarget] Moonfire",
    [MacroTypes.INSECT_SWARM] = "/cast [target=focustarget] Insect Swarm",
    [MacroTypes.STARFALL] = "/cast Starfall",
    [MacroTypes.STARFIRE] = "/use 10 /cast [target=focustarget] Starfire",
    [MacroTypes.WRATH] = "/cast [target=focustarget] Wrath",
    [MacroTypes.DOING_NOTHING] = "/stopcasting",
}

-- Track Lunar Eclipse state and cooldown timings
local LUNAR_ECLIPSE_BUFF_NAME = "Eclipse (Lunar)"
local SOLAR_ECLIPSE_BUFF_NAME = "Eclipse (Solar)"
local lunarEclipseActive = false
local lunarEclipseAppliedAt = nil
local lunarEclipseLostAt = nil
local solarEclipseActive = false
local solarEclipseAppliedAt = nil
local solarEclipseLostAt = nil

local function onUnitAura(self, event, unit)
    if unit ~= "player" then return end

    local hasLunarBuff = UnitBuff("player", LUNAR_ECLIPSE_BUFF_NAME) ~= nil
    local hasSolarBuff = UnitBuff("player", SOLAR_ECLIPSE_BUFF_NAME) ~= nil

    if hasLunarBuff and not lunarEclipseActive then
        lunarEclipseActive = true
        lunarEclipseAppliedAt = GetTime()
    elseif not hasLunarBuff and lunarEclipseActive then
        lunarEclipseActive = false
        lunarEclipseLostAt = GetTime()
    end
    if hasSolarBuff and not solarEclipseActive then
        solarEclipseActive = true
        solarEclipseAppliedAt = GetTime()
    elseif not hasSolarBuff and solarEclipseActive then
        solarEclipseActive = false
        solarEclipseLostAt = GetTime()
    end
end

local function ensureAuraFrame()
    if _G.BalanceDruidAuraFrame then return end
    local f = CreateFrame("Frame")
    f:RegisterEvent("UNIT_AURA")
    f:SetScript("OnEvent", onUnitAura)
    _G.BalanceDruidAuraFrame = f
end

local function isLunarEclipseOnCooldown()
    -- Consider Eclipse on cooldown while active
    if lunarEclipseActive then
        return true
    end

    local now = GetTime()
    -- Cooldown logic:
    -- Available 30s after applied, equivalently 15s after lost (buff lasts 15s)
    local readyAtFromApplied = lunarEclipseAppliedAt and (lunarEclipseAppliedAt + 30) or 0
    local readyAtFromLost = lunarEclipseLostAt and (lunarEclipseLostAt + 15) or 0
    local readyAt = math.max(readyAtFromApplied, readyAtFromLost)

    return now < readyAt
end

local function isSpellOnCooldown(spellName)
    local start, duration, enable = GetSpellCooldown(spellName)
    if enable == 0 then return true end
    if not start or not duration then return false end
    if duration == 0 then return false end
    return (GetTime() < start + duration)
end

local function isSolarEclipseOnCooldown()
    if solarEclipseActive then
        return true
    end
    local now = GetTime()
    local readyAtFromApplied = solarEclipseAppliedAt and (solarEclipseAppliedAt + 30) or 0
    local readyAtFromLost = solarEclipseLostAt and (solarEclipseLostAt + 15) or 0
    local readyAt = math.max(readyAtFromApplied, readyAtFromLost)
    return now < readyAt
end

-- Function to return a tuple (key, target) based on current conditions
local function getBalanceDruidMacro()

    if UnitIsDeadOrGhost("player") then
        return MacroTypes.DOING_NOTHING, 0
    end

    -- 1) Ensure Mark of the Wild (or Gift of the Wild)
    if not UnitBuff("player", "Mark of the Wild") and not UnitBuff("player", "Gift of the Wild") then
        return MacroTypes.MARK_OF_THE_WILD, 0
    end

    -- 2) If not in combat or no valid focus target, do nothing
    if not UnitAffectingCombat("player") then
        DEFAULT_CHAT_FRAME:AddMessage("Not in combat");
        return MacroTypes.DOING_NOTHING, 0
    end

    local focusName, _ = UnitName("focustarget")
    if not focusName or UnitIsDeadOrGhost("focustarget") then
        DEFAULT_CHAT_FRAME:AddMessage("No valid focus target");
        return MacroTypes.DOING_NOTHING, 0
    end

    -- 3) Faerie Fire
    if not UnitDebuff("focustarget", "Faerie Fire") then
        return MacroTypes.FAERIE_FIRE, 0
    end

    -- 4) Moonfire
    if not UnitDebuff("focustarget", "Moonfire") then
        return MacroTypes.MOONFIRE, 0
    end

    -- 5) Insect Swarm
    if not UnitDebuff("focustarget", "Insect Swarm") and not UnitBuff("player", LUNAR_ECLIPSE_BUFF_NAME) then
        return MacroTypes.INSECT_SWARM, 0
    end

    -- 6) Starfall if not on cooldown
    if not isSpellOnCooldown("Starfall") then
        return MacroTypes.STARFALL, 0
    end

    -- 7) If Lunar Eclipse active or it just finished and we are trying to get it again, cast Starfire
    if UnitBuff("player", LUNAR_ECLIPSE_BUFF_NAME) or (isLunarEclipseOnCooldown() and not UnitBuff("player", SOLAR_ECLIPSE_BUFF_NAME)) then
        return MacroTypes.STARFIRE, 0
    end

    -- 8) Wrath fallback
    return MacroTypes.WRATH, 0
end

-- Initialize keybinds for macros in macroMap using secure buttons and SetBindingClick
local function initBalanceDruidKeybinds()
    local macroKeys = {
        [MacroTypes.MARK_OF_THE_WILD] = "F1",
        [MacroTypes.FAERIE_FIRE] = "F2",
        [MacroTypes.MOONFIRE] = "F3",
        [MacroTypes.INSECT_SWARM] = "F4",
        [MacroTypes.STARFALL] = "F5",
        [MacroTypes.STARFIRE] = "F6",
        [MacroTypes.WRATH] = "F7",
    }

    for key, binding in pairs(macroKeys) do
        local macroText = macroMap[key]
        local buttonName = "BalanceMacroButton_" .. binding
        local button = CreateFrame("Button", buttonName, nil, "SecureActionButtonTemplate")
        button:SetAttribute("type", "macro")
        SetBindingClick(binding, buttonName)
        button:SetAttribute("macrotext", macroText)
    end
end

-- Return module exports
BalanceDruid = {
    MacroTypes = MacroTypes,
    macroMap = macroMap,
    getBalanceDruidMacro = getBalanceDruidMacro,
    initBalanceDruidKeybinds = initBalanceDruidKeybinds,
}


