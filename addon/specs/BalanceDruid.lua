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
    MOONKIN_FORM = 8,
    CYCLONE = 9,
}

-- Map of macro strings for each action
local macroMap = {
    [MacroTypes.MARK_OF_THE_WILD] = "/cast [target=player] Mark of the Wild",
    [MacroTypes.FAERIE_FIRE] = "/cast [target=focustarget] Faerie Fire",
    [MacroTypes.MOONFIRE] = "/cast [target=focustarget] Moonfire",
    [MacroTypes.INSECT_SWARM] = "/cast [target=focustarget] Insect Swarm",
    [MacroTypes.STARFALL] = "/cast Starfall",
    [MacroTypes.STARFIRE] = [[/use 10;
/cast [target=focustarget] Starfire]],
    [MacroTypes.WRATH] = "/cast [target=focustarget] Wrath",
    [MacroTypes.DOING_NOTHING] = "/stopcasting",
    [MacroTypes.MOONKIN_FORM] = "/cast Moonkin Form",
    [MacroTypes.CYCLONE] = "/cast Cyclone",
}

local lastCycloneTime = 0

-- ========= DEBUG FLAG =========
local isDebug = false
local function debug(msg)
    if isDebug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[BalanceDruid]|r " .. msg)
    end
end
-- ============================

-- Track Lunar Eclipse state and cooldown timings
local LUNAR_ECLIPSE_BUFF_NAME = "Eclipse (Lunar)"
local SOLAR_ECLIPSE_BUFF_NAME = "Eclipse (Solar)"
local lunarEclipseActive = false
local lunarEclipseAppliedAt = nil
local solarEclipseActive = false
local solarEclipseAppliedAt = nil

-- Used to debounce Vampiric Touch applications
local function onUnitSpellcastStart(self, event, unitTarget, spellName, spellRank)
    if spellName == "Cyclone" then
        lastCycloneTime = GetTime()
    end
end

local function onUnitAura(self, event, unit)
    if unit ~= "player" then return end

    local hasLunarBuff = UnitBuff("player", LUNAR_ECLIPSE_BUFF_NAME) ~= nil
    local hasSolarBuff = UnitBuff("player", SOLAR_ECLIPSE_BUFF_NAME) ~= nil

    if hasLunarBuff and not lunarEclipseActive then
        debug("Lunar Eclipse activated")
        lunarEclipseActive = true
        lunarEclipseAppliedAt = GetTime()
    elseif not hasLunarBuff and lunarEclipseActive then
        debug("Lunar Eclipse expired")
        lunarEclipseActive = false
    end
    if hasSolarBuff and not solarEclipseActive then
        debug("Solar Eclipse activated")
        solarEclipseActive = true
        solarEclipseAppliedAt = GetTime()
    elseif not hasSolarBuff and solarEclipseActive then
        debug("Solar Eclipse expired")
        solarEclipseActive = false
    end
end

local function ensureAuraFrame()
    if _G.BalanceDruidAuraFrame then return end
    local f = CreateFrame("Frame")
    f:RegisterEvent("UNIT_AURA")
    f:SetScript("OnEvent", onUnitAura)
    _G.BalanceDruidAuraFrame = f
end

local function getSpellCooldownRemaining(spellName)
    local startTime, duration, _ = GetSpellCooldown(spellName)
    if startTime and startTime > 0 then
        local remaining = (startTime + duration) - GetTime()
        return remaining > 0 and remaining or 0
    end
    return 0
end

local function isLunarEclipseOnCooldown()
    -- Consider Eclipse on cooldown while active
    if lunarEclipseActive then
        return true
    end

    local now = GetTime()
    -- Cooldown logic:
    -- Available 30s after applied
    local readyAt = lunarEclipseAppliedAt and (lunarEclipseAppliedAt + 30) or 0

    return now < readyAt
end

local function isSolarEclipseOnCooldown()
    if solarEclipseActive then
        return true
    end
    local now = GetTime()
    local readyAt = solarEclipseAppliedAt and (solarEclipseAppliedAt + 30) or 0
    return now < readyAt
end

-- Function to return a tuple (key, target) based on current conditions
local function getBalanceDruidMacro()

    if UnitIsDeadOrGhost("player") or IsMounted()  then
        return MacroTypes.DOING_NOTHING, 0
    end

    -- 1) Ensure Mark of the Wild (or Gift of the Wild)
    if not UnitBuff("player", "Mark of the Wild") and not UnitBuff("player", "Gift of the Wild") then
        debug("ACTION: Mark of the Wild. (Missing buff)")
        return MacroTypes.MARK_OF_THE_WILD, 0
    end

    -- 2) If not in combat or no valid focus target, do nothing
    if not UnitAffectingCombat("focus") then
        return MacroTypes.DOING_NOTHING, 0
    end
    
    debug("---------- New Rotation Tick ----------")
    
    local raidmembers = GetNumRaidMembers()
    if raidmembers == 0 then
        for i = 1, raidmembers do
            local u = "raid" .. i
            -- cyclone lasts 6 seconds
            if UnitIsEnemy(u) and not UnitAura(u, "Cyclone", nil, "PLAYER|HARMFUL") and GetTime() > lastCycloneTime + 6 then
                local name = UnitName(u)
                debug(string.format("Cyclone mind control: %s", name))
                return MacroTypes.CYCLONE, i
            end
        end
    end
    local gcd = getSpellCooldownRemaining("Moonfire")

    if not UnitBuff("player", "Moonkin Form") then
        debug("ACTION: Moonkin Form. (Not in form)")
        return MacroTypes.MOONKIN_FORM, 0
    end
    debug("Condition: Moonkin Form is active.")

    local focusName, _ = UnitName("focustarget")
    if not focusName or UnitIsDeadOrGhost("focustarget") then
        debug("ACTION: Doing nothing. (Invalid focus target)")
        return MacroTypes.DOING_NOTHING, 0
    end
    debug("Condition: Focus target is valid.")

    -- 3) Faerie Fire
    if not UnitDebuff("focustarget", "Faerie Fire") then
        debug("ACTION: Faerie Fire. (Debuff not on target)")
        return MacroTypes.FAERIE_FIRE, 0
    end
    debug("Condition: Faerie Fire is on target.")

    -- 4) Moonfire
    if not UnitAura("focustarget", "Moonfire", nil, "PLAYER|HARMFUL") and not UnitBuff("player", SOLAR_ECLIPSE_BUFF_NAME) then
        debug("ACTION: Moonfire. (Debuff not on target and not in Solar Eclipse)")
        return MacroTypes.MOONFIRE, 0
    end

    -- 5) Insect Swarm
    if not UnitAura("focustarget", "Insect Swarm", nil, "PLAYER|HARMFUL") and not UnitBuff("player", LUNAR_ECLIPSE_BUFF_NAME) then
        debug("ACTION: Insect Swarm. (Debuff not on target and not in Lunar Eclipse)")
        return MacroTypes.INSECT_SWARM, 0
    end

    -- 6) Starfall if not on cooldown
    local starfallCooldown = getSpellCooldownRemaining("Starfall")
    if starfallCooldown <= gcd then
        debug("ACTION: Starfall. (Available)")
        return MacroTypes.STARFALL, 0
    end
    debug(string.format("Condition: Starfall CD=%.1f", starfallCooldown))

    -- 7) If Lunar Eclipse active or it just finished and we are trying to get it again, cast Starfire
    if isLunarEclipseOnCooldown() and not UnitBuff("player", SOLAR_ECLIPSE_BUFF_NAME) then
        debug("ACTION: Starfire. (Lunar Eclipse active or on cooldown)")
        return MacroTypes.STARFIRE, 0
    end
    debug("Condition: Lunar Eclipse not active or on cooldown, and Solar Eclipse buff is active.")

    -- 8) Wrath fallback
    debug("ACTION: Wrath. (Fallback)")
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
        [MacroTypes.MOONKIN_FORM] = "F8",
        [MacroTypes.CYCLONE] = "F9",
    }

    for key, binding in pairs(macroKeys) do
        local macroText = macroMap[key]
        local buttonName = "BalanceMacroButton_" .. binding
        local button = CreateFrame("Button", buttonName, nil, "SecureActionButtonTemplate")
        button:SetAttribute("type", "macro")
        SetBindingClick(binding, buttonName)
        button:SetAttribute("macrotext", macroText)
    end
    ensureAuraFrame()
end

-- Return module exports
BalanceDruid = {
    MacroTypes = MacroTypes,
    macroMap = macroMap,
    getBalanceDruidMacro = getBalanceDruidMacro,
    initBalanceDruidKeybinds = initBalanceDruidKeybinds,
}


