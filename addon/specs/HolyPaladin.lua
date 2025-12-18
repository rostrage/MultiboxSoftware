-- Define named constants for macro types (simulating enums)
local MacroTypes = {
    DOING_NOTHING = 0,
    BEACON_OF_LIGHT = 1,
    SACRED_SHIELD = 2,
    DIVINE_PLEA = 3,
    JUDGEMENT_OF_LIGHT = 4,
    HOLY_LIGHT = 5,
    STOP_CASTING = 6
}

-- Map of macro strings for each key (0 to n)
local macroMap = {
    [MacroTypes.DOING_NOTHING] = "/stopcasting",
    [MacroTypes.BEACON_OF_LIGHT] = [[/cast [target=focus] Beacon of Light;
/assist focus;
/startattack]],
    [MacroTypes.SACRED_SHIELD] = [[/cast [target=focus] Sacred Shield;
/assist focus;
/startattack]],
    [MacroTypes.DIVINE_PLEA] = [[/cast Divine Plea;
/assist focus;
/startattack]],
    [MacroTypes.JUDGEMENT_OF_LIGHT] = "/cast [target=focustarget] Judgement of Light",
    [MacroTypes.HOLY_LIGHT] = "/cast Holy Light", -- Dynamic target will be handled at runtime
    [MacroTypes.STOP_CASTING] = [[/stopcasting;
/assist focus;
/startattack]]
}

-- ========= DEBUG FLAG =========
local isDebug = false
local function debug(msg)
    if isDebug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[HolyPaladin]|r " .. msg)
    end
end
-- ============================

local lastHealOnTarget = {}

-- Store swing timer information here
_G.MultiboxBossSwingTimer_swings = _G.MultiboxBossSwingTimer_swings or {}

-- Helper function to extract NPC ID from GUID
local function npcid(guid)
    return tonumber(guid:sub(-10, -7), 16)
end

-- Helper function to check if a GUID belongs to an NPC
local function isnpc(guid)
    local B = tonumber(guid:sub(5,5), 16)
    local maskedB = B % 8
    if maskedB == 3 then -- 3 is NPC
        return true
    end
    return false
end

-- Simplified OnSwing function to update swing timers
local function OnSwing(time, guid, name)
    -- DEFAULT_CHAT_FRAME:AddMessage("OnSwing called for name: " .. name .. " at time: " .. time)
    _G.MultiboxBossSwingTimer_swings[guid] = _G.MultiboxBossSwingTimer_swings[guid] or {}
    local prev = _G.MultiboxBossSwingTimer_swings[guid].time
    _G.MultiboxBossSwingTimer_swings[guid].time = time
    -- DEFAULT_CHAT_FRAME:AddMessage("foo")
    local speed = nil
    if prev and (time - prev) < 5000 then -- Only consider recent swings for speed calculation
        speed = time - prev
    end

    -- Attempt to get attack speed from UnitAttackSpeed if available and not yet set
    local unitId = nil
    if UnitGUID("boss1") == guid then unitId = "boss1" end

    if unitId then
        local apiSpeed = UnitAttackSpeed(unitId)
        if apiSpeed and apiSpeed > 0 then
            -- Prefer API speed if available
            speed = apiSpeed
        end
    end

    if speed then
        _G.MultiboxBossSwingTimer_swings[guid].next = time + speed
    end
end

local function onUnitSpellcastSent(self, event, unit, spellName, _, targetName)
    if unit == "player" and spellName == "Holy Light" and targetName then
        lastHealOnTarget[targetName] = GetTime()
    end
end

local function onCombatLogEventUnfiltered(self, event, timestamp, subevent, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, ...)
    if subevent == "SWING_DAMAGE" or subevent == "SWING_MISSED" then
        if isnpc(sourceGUID) then
            OnSwing(GetTime(), sourceGUID, sourceName)
        end
    elseif subevent == "UNIT_DIED" then
        if _G.MultiboxBossSwingTimer_swings[destGUID] then
            _G.MultiboxBossSwingTimer_swings[destGUID] = nil
        end
    end
end

local function onCombatEnd(self)
    debug("Combat ended, clearing swing timers.")
    _G.MultiboxBossSwingTimer_swings = {}
end

local function ensureAuraFrame()
    if _G.HolyPaladinAuraFrame then return end
    local f = CreateFrame("Frame")
    f:RegisterEvent("UNIT_SPELLCAST_SENT")
    f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function(self, event, ...)
        if event == "UNIT_SPELLCAST_SENT" then
            onUnitSpellcastSent(self, event, ...)
        elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
            onCombatLogEventUnfiltered(self, event, ...)
        elseif event == "PLAYER_REGEN_ENABLED" then
            onCombatEnd(self)
        end
    end)
    _G.HolyPaladinAuraFrame = f
end

local function getSpellCooldownRemaining(spellName)
    local startTime, duration, _ = GetSpellCooldown(spellName)
    if startTime and startTime > 0 then
        local remaining = (startTime + duration) - GetTime()
        return remaining > 0 and remaining or 0
    end
    return 0
end

local function getNextBossSwingTimer()
    local nextSwingTime = math.huge

    local targetGUID = UnitGUID("boss1")
    if targetGUID and isnpc(targetGUID) then
        if _G.MultiboxBossSwingTimer_swings[targetGUID] and _G.MultiboxBossSwingTimer_swings[targetGUID].next then
            nextSwingTime = math.min(nextSwingTime, _G.MultiboxBossSwingTimer_swings[targetGUID].next)
        end
    end

    if nextSwingTime == math.huge or nextSwingTime < GetTime() then
        return nil -- No boss swing timer found
    end

    return nextSwingTime
end

local function getPlayerBuffDuration(unit, auraName)
    local name, _, _, _, _, _, expirationTime, caster = UnitBuff(unit, auraName)
    if name and (caster == "player" or caster == nil) then
        local duration = expirationTime - GetTime()
        debug(string.format("getPlayerBuffDuration: Found '%s' on '%s', duration=%.1f", auraName, unit, duration))
        return duration
    end
    debug(string.format("getPlayerBuffDuration: '%s' not found on '%s'", auraName, unit))
    return 0
end

-- Function to return a tuple (key, target) based on current conditions
local function getHolyPaladinMacro()
    
    if UnitIsDeadOrGhost("player") or IsMounted() then
        -- debug("ACTION: Doing nothing. (Player is dead/ghost or mounted)")
        return MacroTypes.DOING_NOTHING, 0
    end
    
    local focusName = UnitName("focus")

    -- 1. Use Divine Plea when mana is low and off cooldown
    local currentMana = UnitPower("player", 0)
    local maxMana = UnitPowerMax("player", 0)
    if currentMana < maxMana * 0.9 then
        local divinePleaCooldown = getSpellCooldownRemaining("Divine Plea")
        if divinePleaCooldown <= 0.2 then
            debug("ACTION: Divine Plea. (Available)")
            return MacroTypes.DIVINE_PLEA, 0
        end
        debug(string.format("Condition: Divine Plea CD=%.1f, Mana=%.1f%%", divinePleaCooldown, (currentMana / maxMana) * 100))
    end

    if not UnitAffectingCombat("focus") and not UnitAffectingCombat("player") then
        return MacroTypes.DOING_NOTHING, 0
    end

    debug("---------- New Rotation Tick ----------")

        -- 1191 mana cost for Holy Light at level 80
    if currentMana < 1191 then
        debug("ACTION: Doing nothing. Out of mana.")
        return MacroTypes.STOP_CASTING, 0
    end
    
    local beaconDuration = getPlayerBuffDuration("focus", "Beacon of Light")
    -- 2. Cast Beacon of Light if not already on focus
    if beaconDuration == 0 and UnitInRange("focus") and not UnitIsDeadOrGhost("focus") and not UnitIsEnemy("player","focus") then
        debug("ACTION: Beacon of Light. (Not on focus)")
        return MacroTypes.BEACON_OF_LIGHT, 0
    end

    local judgementOfThePureDuration = getPlayerBuffDuration("player", "Judgement of the Pure")
    -- 3. Cast Judgement of Light on focustarget when off cooldown
    local judgementCooldown = getSpellCooldownRemaining("Judgement of Light")
    if judgementCooldown <= 0.2 and IsSpellInRange("Judgement of Light", "focustarget") and judgementOfThePureDuration == 0 then
        debug("ACTION: Judgement of Light. (Refreshing Judgement of the Pure)")
        return MacroTypes.JUDGEMENT_OF_LIGHT, 0
    end
    debug(string.format("Condition: Judgement of Light CD=%.1f", judgementCooldown))

    -- 4. Loop through raid members and find lowest HP non-focus target
    local targetIndex = 0
    local lowestPercent = 1.0
    local raidmembers = GetNumRaidMembers()
    if raidmembers == 0 then
        for i = 1, 4 do
            local u = GetUnitName("party" .. i)
            if UnitIsPlayer(u) and UnitInRange(u) and not UnitIsDeadOrGhost(u) and not UnitIsEnemy("player", u) then
                local health = UnitHealth(u)
                local maxHealth = UnitHealthMax(u)
                local percent = health / maxHealth
                local name = UnitName(u)
                if percent < 0.95 then
                    if percent < lowestPercent then
                        if not lastHealOnTarget[u] or GetTime() > lastHealOnTarget[u] + 2.0 or targetIndex == 0 then
                            lowestPercent = percent
                            if name ~= focusName then -- Skip the focus target
                                targetIndex = i
                            end
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
                if percent < lowestPercent then
                    if not lastHealOnTarget[u] or GetTime() > lastHealOnTarget[u] + 2.0 or targetIndex == 0 then
                        lowestPercent = percent
                        if name ~= focusName then -- Skip the focus target
                            targetIndex = 5
                        end
                    end
                end
            end
        end
    else 
        for i = 1, raidmembers do
            local unit = "raid" .. i
            if UnitIsPlayer(unit) and UnitInRange(unit) and not UnitIsDeadOrGhost(unit) and not UnitIsEnemy("player", unit) then
                local name = UnitName(unit)
                local health = UnitHealth(unit)
                local maxHealth = UnitHealthMax(unit)
                local percent = health / maxHealth
                if percent < lowestPercent then
                    if percent < 0.5 or not lastHealOnTarget[name] or GetTime() > lastHealOnTarget[name] + 2.0 or targetIndex == 0 then
                        lowestPercent = percent
                        if name ~= focusName then -- Skip the focus target
                            targetIndex = i
                        end
                    end
                end
            end
        end
    end
    if lowestPercent < 1.0 then
        debug(string.format("ACTION: Holy Light. (Target %d at %.1f%% health)", targetIndex, lowestPercent * 100))
        return MacroTypes.HOLY_LIGHT, targetIndex
    else
        if not UnitBuff("focus", "Sacred Shield") and UnitInRange("focus") and not UnitIsDeadOrGhost("focus") and not UnitIsEnemy("player","focus") then
            debug("ACTION: Sacred Shield. (Not on focus)")
            return MacroTypes.SACRED_SHIELD, 0
        end
        
        if beaconDuration < 10 and UnitInRange("focus") and not UnitIsDeadOrGhost("focus") and not UnitIsEnemy("player","focus") then
            debug("ACTION: Beacon of Light. (Refreshing on focus)")
            return MacroTypes.BEACON_OF_LIGHT, 0
        end

        if judgementCooldown <= 0.2 and IsSpellInRange("Judgement of Light", "focustarget") then
            debug("ACTION: Judgement of Light. (Available)")
            return MacroTypes.JUDGEMENT_OF_LIGHT, 0
        end

        -- No raid members in need; check focus now (focus is last priority)
        local focusHealth = UnitHealth("focus")
        local focusMaxHealth = UnitHealthMax("focus")
        local focusPercent = (focusHealth / focusMaxHealth) * 100

        if focusHealth < focusMaxHealth then
            debug(string.format("ACTION: Holy Light. (Focus at %.1f%% health)", focusPercent))
            return MacroTypes.HOLY_LIGHT, targetIndex
        else
            local _, _, _, _, _, endtimeMS = UnitCastingInfo("player")
            local castFinishTime = endtimeMS and (endtimeMS / 1000) or nil
            local nextBossSwing = getNextBossSwingTimer()
            if nextBossSwing ~= nil then
                -- If we are casting and a boss swing is coming soon
                if castFinishTime ~= nil and castFinishTime < nextBossSwing then
                    debug("ACTION: Stop Casting. (Cast finishes before next boss swing)")
                    return MacroTypes.STOP_CASTING, 0
                elseif focusTarget ~= -1 then
                    -- If nothing better to do, precast a holy light
                    debug("ACTION: Precast Holy Light. (No targets need healing)")
                    return MacroTypes.HOLY_LIGHT, 0
                end
            end
            return MacroTypes.STOP_CASTING, 0
        end
    end
    return MacroTypes.DOING_NOTHING, 0
end

-- Initialize keybinds for macros in macroMap using secure buttons and SetBindingClick
local function initHolyPaladinKeybinds()
    _G.HolyPaladinKeybindFrame = _G.HolyPaladinKeybindFrame or CreateFrame("Frame")
    local macroKeys = {
        [MacroTypes.BEACON_OF_LIGHT] = "F1",
        [MacroTypes.SACRED_SHIELD] = "F2",
        [MacroTypes.DIVINE_PLEA] = "F3",
        [MacroTypes.JUDGEMENT_OF_LIGHT] = "F4",
        [MacroTypes.HOLY_LIGHT] = "F5",
        [MacroTypes.STOP_CASTING] = "F6"
    }

    for key, binding in pairs(macroKeys) do
        local buttonName = "MacroButton_" .. binding

        -- Create a secure macro button
        local existingButton = nil;
        for _, frame in pairs({ _G.HolyPaladinKeybindFrame:GetChildren() }) do
            if frame:GetName() == buttonName then
                existingButton = frame
                break
            end
        end
        local button = existingButton or CreateFrame("Button", buttonName, _G.HolyPaladinKeybindFrame, "SecureActionButtonTemplate")
        button:SetAttribute("type", "macro")

        local macroText = macroMap[key]

        SetBindingClick(binding, buttonName)
        button:SetAttribute("macrotext", macroText)
    end
    ensureAuraFrame()
end

-- Return module exports
HolyPaladin = {
    MacroTypes = MacroTypes,
    macroMap = macroMap,
    getHolyPaladinMacro = getHolyPaladinMacro,
    initHolyPaladinKeybinds = initHolyPaladinKeybinds
}
