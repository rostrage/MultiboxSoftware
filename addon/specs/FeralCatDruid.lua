-- Define named constants for macro types (simulating enums)
local MacroTypes = {
    DOING_NOTHING = 0,
    TIGERS_FURY = 1,
    FAERIE_FIRE = 2,
    BERSERK = 3,
    SAVAGE_ROAR = 4,
    RIP = 5,
    FEROCIOUS_BITE = 6,
    MANGLE = 7,
    RAKE = 8,
    SHRED = 9,
}

-- Map of macro strings for each key
local macroMap = {
    [MacroTypes.TIGERS_FURY] = "/cast Tiger's Fury",
    [MacroTypes.FAERIE_FIRE] = "/cast [target=focustarget] Faerie Fire (Feral)",
    [MacroTypes.BERSERK] = "/cast Berserk",
    [MacroTypes.SAVAGE_ROAR] = "/cast Savage Roar",
    [MacroTypes.RIP] = "/cast [target=focustarget] Rip",
    [MacroTypes.FEROCIOUS_BITE] = "/cast [target=focustarget] Ferocious Bite",
    [MacroTypes.MANGLE] = "/cast [target=focustarget] Mangle (Cat)",
    [MacroTypes.RAKE] = "/cast [target=focustarget] Rake",
    [MacroTypes.SHRED] = "/cast [target=focustarget] Shred",
    [MacroTypes.DOING_NOTHING] = "/print Doing nothing"
}

-- ========= DEBUG FLAG =========
local isDebug = true
local function debug(msg)
    if isDebug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[FeralCatDruid]|r " .. msg)
    end
end
-- ============================

-- Helper functions to get remaining aura durations
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

local function getDebuffDuration(unit, auraName, isPlayerOnly)
    local name, _, _, _, _, _, expirationTime, caster = UnitDebuff(unit, auraName)
    if name then
        if isPlayerOnly then
            if caster == "player" then
                local duration = expirationTime - GetTime()
                debug(string.format("getDebuffDuration: Found player's '%s' on '%s', duration=%.1f", auraName, unit, duration))
                return duration
            end
        else
            local duration = expirationTime - GetTime()
            debug(string.format("getDebuffDuration: Found '%s' on '%s', duration=%.1f", auraName, unit, duration))
            return duration
        end
    end
    debug(string.format("getDebuffDuration: '%s' not found on '%s'", auraName, unit))
    return 0
end

-- Function to return a tuple (key, target) based on current conditions
local function getFeralCatDruidMacro()
    
    if UnitIsDeadOrGhost("player") or IsMounted() or not UnitAffectingCombat("player") then
        return MacroTypes.DOING_NOTHING, 0
    end

    -- Check focus target for debuffs and damage rotation
    local focusName, _ = UnitName("focustarget")
    if focusName and not UnitIsDeadOrGhost("focustarget") then
        debug("---------- New Rotation Tick ----------")
        -- Configurable thresholds from feraldruidcat.go
        local BITE_TIME = 4.0 -- Seconds. Min duration of Rip/Roar to allow Bite.
        local TF_ENERGY_THRESHOLD = 40.0 -- Use TF below this energy.
        local FF_ENERGY_THRESHOLD = 85.0 -- Don't use FF above this energy to avoid capping.
        local BERSERK_BITE_THRESH = 25.0 -- During Berserk, only Bite below this energy.
        local ROAR_CLIP_TIME = 3.0 -- Refresh Roar if it has less than this duration.
        local MANGLE_CLIP_TIME = 3.0 -- Refresh Mangle if it has less than this duration.

        -- Player and Target State
        local energy = UnitPower("player", 3)
        local comboPoints = GetComboPoints("player", "focustarget")
        local isBerserk = UnitBuff("player", "Berserk")
        
        debug(string.format("State: Energy=%d, CP=%d, Berserk=%s", energy, comboPoints, tostring(isBerserk)))

        -- Aura Durations
        local roar_remains = getPlayerBuffDuration("player", "Savage Roar")
        local rip_remains = getDebuffDuration("focustarget", "Rip", true)
        local rake_remains = getDebuffDuration("focustarget", "Rake", true)
        local mangle_remains = getDebuffDuration("focustarget", "Mangle (Cat)", false)
        local faerie_fire_remains = getDebuffDuration("focustarget", "Faerie Fire (Feral)", false)

        local roar_active = roar_remains > 0
        local rip_active = rip_remains > 0
        local rake_active = rake_remains > 0
        local mangle_active = mangle_remains > 0
        local faerie_fire_active = faerie_fire_remains > 0

        debug(string.format("Auras: Roar=%.1f, Rip=%.1f, Rake=%.1f, Mangle=%.1f, FF=%.1f", roar_remains, rip_remains, rake_remains, mangle_remains, faerie_fire_remains))

        -- Cooldowns
        local function getSpellCooldownRemaining(spellName)
            local startTime, duration, _ = GetSpellCooldown(spellName)
            if startTime and startTime > 0 then
                local remaining = (startTime + duration) - GetTime()
                return remaining > 0 and remaining or 0
            end
            return 0
        end

        local tf_cd_remains = getSpellCooldownRemaining("Tiger's Fury")
        local berserk_cd_remains = getSpellCooldownRemaining("Berserk")
        local ff_cd_remains = getSpellCooldownRemaining("Faerie Fire (Feral)")

        debug(string.format("Cooldowns: TF=%.1f, Berserk=%.1f, FF=%.1f", tf_cd_remains, berserk_cd_remains, ff_cd_remains))

        -- Rotation Logic inspired by feraldruidcat.go
        
        debug("Step 1: Manage Buffs & Cooldowns")
        -- 1. Manage Buffs & Cooldowns
        
        -- Berserk: Use when off cooldown and Rip is on the target.
        -- Delay if Tiger's Fury is coming off cooldown soon.
        if berserk_cd_remains <= 0.2 and rip_active and tf_cd_remains > 3 then
            debug("ACTION: Berserk. (CD ready, Rip active, TF CD > 3s)")
            return MacroTypes.BERSERK, 0
        end

        -- Tiger's Fury: Cast below threshold when off cooldown and not Berserking
        if energy < TF_ENERGY_THRESHOLD and tf_cd_remains <= 0.2 and not isBerserk then
            debug(string.format("ACTION: Tiger's Fury. (Energy %.1f < %.1f, CD ready, not Berserk)", energy, TF_ENERGY_THRESHOLD))
            return MacroTypes.TIGERS_FURY, 0
        end

        -- Faerie Fire: Keep debuff applied, but avoid casting if energy is high.
        if ff_cd_remains <= 0.2 and energy < FF_ENERGY_THRESHOLD then
            debug(string.format("ACTION: Faerie Fire. (Not active, CD ready, Energy %.1f < %.1f)", energy, FF_ENERGY_THRESHOLD))
            return MacroTypes.FAERIE_FIRE, 0
        end

        debug("Step 2: Spend Combo Points (Finishers)")
        -- 2. Spend Combo Points (Finishers)

        -- Savage Roar: Maintain buff. Refresh if it's about to expire (clipping).
        if comboPoints >= 1 and (not roar_active or roar_remains < ROAR_CLIP_TIME) then
            debug(string.format("ACTION: Savage Roar. (CP>=1, Roar active=%s, Roar remains %.1f < %.1f)", tostring(roar_active), roar_remains, ROAR_CLIP_TIME))
            return MacroTypes.SAVAGE_ROAR, 0
        end

        -- Rip: Use at 5 combo points if debuff is missing.
        if comboPoints == 5 and not rip_active then
            debug("ACTION: Rip. (CP=5, Rip not active)")
            return MacroTypes.RIP, 0
        end

        -- Ferocious Bite: Use at 5 combo points if Rip and Roar are active with enough duration.
        if comboPoints == 5 and rip_remains > BITE_TIME and roar_remains > BITE_TIME then
            debug("Evaluating Ferocious Bite...")
            if isBerserk then
                debug(string.format("...Berserking. Checking energy %.1f < %.1f", energy, BERSERK_BITE_THRESH))
                -- During Berserk, only bite at low energy to maximize Shreds
                if energy < BERSERK_BITE_THRESH then
                    debug("ACTION: Ferocious Bite. (Berserking, low energy)")
                    return MacroTypes.FEROCIOUS_BITE, 0
                end
            else
                debug("ACTION: Ferocious Bite. (Not Berserking, conditions met)")
                return MacroTypes.FEROCIOUS_BITE, 0
            end
        end

        debug("Step 3: Maintain Debuffs & Build Combo Points (Builders)")
        -- 3. Maintain Debuffs & Build Combo Points (Builders)

        -- Mangle: Keep debuff applied
        if not mangle_active then
            debug("ACTION: Mangle. (Not active)")
            return MacroTypes.MANGLE, 0
        end

        -- Rake: Keep debuff applied
        if not rake_active then
            debug("ACTION: Rake. (Not active)")
            return MacroTypes.RAKE, 0
        end

        if mangle_remains < MANGLE_CLIP_TIME then
            debug(string.format("ACTION: Mangle. (Clipping, remains %.1f < %.1f)", mangle_remains, MANGLE_CLIP_TIME))
            return MacroTypes.MANGLE, 0
        end

        debug("Step 4: Filler")
        -- 4. Filler
        -- Shred: Use as primary combo point builder.
        -- If we've reached this point, it means no high-priority actions are needed,
        -- so we can spend our "excess" energy on Shred.
        debug("ACTION: Shred. (Filler)")
        return MacroTypes.SHRED, 0
    end

    debug("Target not valid. Doing nothing.")
    return MacroTypes.DOING_NOTHING, 0
end

-- Initialize keybinds for macros in macroMap
local function initFeralCatDruidKeybinds()
    local macroKeys = {
        [MacroTypes.TIGERS_FURY] = "F1",
        [MacroTypes.FAERIE_FIRE] = "F2",
        [MacroTypes.BERSERK] = "F3",
        [MacroTypes.SAVAGE_ROAR] = "F4",
        [MacroTypes.RIP] = "F5",
        [MacroTypes.FEROCIOUS_BITE] = "F6",
        [MacroTypes.MANGLE] = "F7",
        [MacroTypes.RAKE] = "F8",
        [MacroTypes.SHRED] = "F9",
    }

    for key, binding in pairs(macroKeys) do
        local macroText = macroMap[key]
        local buttonName = "MacroButton_Feral_" .. binding
        local button = CreateFrame("Button", buttonName, nil, "SecureActionButtonTemplate")
        button:SetAttribute("type", "macro")
        SetBindingClick(binding, buttonName)
        button:SetAttribute("macrotext", macroText)
    end
end

-- Return module exports
FeralCatDruid = {
    MacroTypes = MacroTypes,
    macroMap = macroMap,
    getFeralCatDruidMacro = getFeralCatDruidMacro,
    initFeralCatDruidKeybinds = initFeralCatDruidKeybinds
}
