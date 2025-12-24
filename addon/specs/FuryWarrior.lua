FuryWarrior = {}

local buttonFrames = {}
-- Define named constants for macro types (simulating enums)
local MacroTypes = {
    DOING_NOTHING = 0,
    SUNDER_ARMOR = 1,
    RECKLESSNESS = 2,
    DEATH_WISH = 3,
    BLOODTHIRST = 4,
    WHIRLWIND = 5,
    SLAM = 6,
    EXECUTE = 7,
    BLOODRAGE = 8
}

-- Map of macro strings for each key (0 to n)
local macroMap = {
    [MacroTypes.SUNDER_ARMOR] = [[/use 10;
/use Heroic Strike
/startattack;
/cast [target=focustarget] Sunder Armor]],
    [MacroTypes.RECKLESSNESS] = "/cast Recklessness",
    [MacroTypes.DEATH_WISH] = "/cast Death Wish",
    [MacroTypes.BLOODTHIRST] = [[/use 10;
/use Heroic Strike
/startattack;
/cast [target=focustarget] Bloodthirst]],
    [MacroTypes.WHIRLWIND] = [[/use 10;
/use Heroic Strike
/startattack;
/cast [target=focustarget] Whirlwind]],
    [MacroTypes.SLAM] = [[/use 10;
/use Heroic Strike
/startattack;
/cast [target=focustarget] Slam]],
    [MacroTypes.EXECUTE] = [[/use 10;
/use Heroic Strike
/startattack;
/cast [target=focustarget] Execute]],
    [MacroTypes.BLOODRAGE] = "/cast Bloodrage",
    [MacroTypes.DOING_NOTHING] = "/run print(\"Doing nothing\")"
}


-- ========= DEBUG FLAG =========
local isDebug = false
local function debug(msg)
    if isDebug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[FuryWarrior]|r " .. msg)
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

local function getDebuffStacksAndRemaining(unit, debuffName)
    local name, _, _, count, _, duration, expirationTime = UnitAura(unit, debuffName, nil, "PLAYER|HARMFUL")
    if name then
        local remaining = expirationTime - GetTime()
        return count, remaining > 0 and remaining or 0
    end
    return 0, 0
end

-- Function to return a tuple (key, target) based on current conditions
local function getFuryWarriorMacro()
    if not UnitAffectingCombat("focus") or IsMounted() then
        return MacroTypes.DOING_NOTHING, 0
    end
    
    -- Check if focustarget exists
    if not UnitExists("focustarget") then
        return MacroTypes.DOING_NOTHING, 0
    end

    debug("---------- New Rotation Tick ----------")
    local gcd = getSpellCooldownRemaining("Battle Shout") -- Using Battle Shout for GCD approximation

    local sunderArmorStacks, sunderArmorRemaining = getDebuffStacksAndRemaining("focustarget", "Sunder Armor")
    local slamBuffActive = UnitBuff("player", "Slam!")
    local health = UnitHealth("focustarget")
    local maxHealth = UnitHealthMax("focustarget")
    local healthPercent = (maxHealth > 0 and (health / maxHealth) * 100) or 100

    -- 1. Highest priority = if focustarget has less than 5 stacks of Sunder Armor (or the stacks will drop in the next 3 seconds), use Sunder Armor.
    local sunderArmorCooldown = getSpellCooldownRemaining("Sunder Armor")
    if sunderArmorCooldown <= gcd then
        if sunderArmorStacks < 5 or sunderArmorRemaining <= 3 then
            debug("ACTION: Sunder Armor. (Stacks < 5 or dropping soon)")
            return MacroTypes.SUNDER_ARMOR, 0
        end
    end
    debug(string.format("Condition: Sunder Armor CD=%.1f, Stacks=%d, Remaining=%.1f", sunderArmorCooldown, sunderArmorStacks, sunderArmorRemaining))

    -- 2. Recklessness
    local recklessnessCooldown = getSpellCooldownRemaining("Recklessness")
    if recklessnessCooldown <= gcd then
        debug("ACTION: Recklessness. (Available)")
        return MacroTypes.RECKLESSNESS, 0
    end
    debug(string.format("Condition: Recklessness CD=%.1f", recklessnessCooldown))

    -- 3. Death Wish
    local deathWishCooldown = getSpellCooldownRemaining("Death Wish")
    if deathWishCooldown <= gcd then
        debug("ACTION: Death Wish. (Available)")
        return MacroTypes.DEATH_WISH, 0
    end
    debug(string.format("Condition: Death Wish CD=%.1f", deathWishCooldown))

    -- 4. Bloodthirst
    local bloodthirstCooldown = getSpellCooldownRemaining("Bloodthirst")
    if bloodthirstCooldown <= gcd then
        debug("ACTION: Bloodthirst. (Available)")
        return MacroTypes.BLOODTHIRST, 0
    end
    debug(string.format("Condition: Bloodthirst CD=%.1f", bloodthirstCooldown))

    -- 5. Whirlwind
    local whirlwindCooldown = getSpellCooldownRemaining("Whirlwind")
    if whirlwindCooldown <= gcd then
        debug("ACTION: Whirlwind. (Available)")
        return MacroTypes.WHIRLWIND, 0
    end
    debug(string.format("Condition: Whirlwind CD=%.1f", whirlwindCooldown))

    -- 6. Slam (only if the player currently has the Slam! buff available)
    local slamCooldown = getSpellCooldownRemaining("Slam")
    if slamCooldown <= gcd and slamBuffActive then
        debug("ACTION: Slam. (Available with Slam! buff)")
        return MacroTypes.SLAM, 0
    end
    debug(string.format("Condition: Slam CD=%.1f, Slam! Buff=%s", slamCooldown, tostring(slamBuffActive)))

    -- 7. Execute (if the focustarget is below 20% hp)
    local executeCooldown = getSpellCooldownRemaining("Execute")
    if executeCooldown <= gcd and healthPercent < 20 then
        debug(string.format("ACTION: Execute. (Available and target health is %.1f%%", healthPercent))
        return MacroTypes.EXECUTE, 0
    end
    debug(string.format("Condition: Execute CD=%.1f, Target Health=%.1f%%", executeCooldown, healthPercent))

    -- 8. Bloodrage
    local bloodrageCooldown = getSpellCooldownRemaining("Bloodrage")
    if bloodrageCooldown <= gcd then
        debug("ACTION: Bloodrage. (Available)")
        return MacroTypes.BLOODRAGE, 0
    end
    debug(string.format("Condition: Bloodrage CD=%.1f", bloodrageCooldown))

    -- 9. Refreshing Sunder (nothing better to do)
    return MacroTypes.SUNDER_ARMOR, 0
end

-- Initialize keybinds for macros in macroMap using secure buttons and SetBindingClick
local function initFuryWarriorKeybinds()
    local macroKeys = {
        [MacroTypes.SUNDER_ARMOR] = "F1",
        [MacroTypes.RECKLESSNESS] = "F2",
        [MacroTypes.DEATH_WISH] = "F3",
        [MacroTypes.BLOODTHIRST] = "F4",
        [MacroTypes.WHIRLWIND] = "F5",
        [MacroTypes.SLAM] = "F6",
        [MacroTypes.EXECUTE] = "F7",
        [MacroTypes.BLOODRAGE] = "F8",
        [MacroTypes.DOING_NOTHING] = "F9",
    }

    for key, binding in pairs(macroKeys) do
        local buttonName = "MacroButton_" .. binding

        -- Create a secure macro button
        local button = CreateFrame("Button", buttonName, nil, "SecureActionButtonTemplate")
        button:SetAttribute("type", "macro")

        local macroText = macroMap[key]

        SetBindingClick(binding, buttonName)
        button:SetAttribute("macrotext", macroText)
        buttonFrames[buttonName] = button
    end
end

-- Reinitialize keybinds (called when configuration changes)
local function ReinitializeKeybinds()
    local macroKeys = {
        [MacroTypes.SUNDER_ARMOR] = "F1",
        [MacroTypes.RECKLESSNESS] = "F2",
        [MacroTypes.DEATH_WISH] = "F3",
        [MacroTypes.BLOODTHIRST] = "F4",
        [MacroTypes.WHIRLWIND] = "F5",
        [MacroTypes.SLAM] = "F6",
        [MacroTypes.EXECUTE] = "F7",
        [MacroTypes.BLOODRAGE] = "F8",
        [MacroTypes.DOING_NOTHING] = "F9",
    }

    -- Clear existing buttons and bindings
    for key, binding in pairs(macroKeys) do
        local buttonName = "MacroButton_" .. binding
        local button = buttonFrames[buttonName]
        if button then
            button:SetAttribute("macrotext", macroMap[key])
        end
        SetBindingClick(binding, buttonName)
    end
end

-- Check if player is Fury Warrior spec
local function IsFuryWarriorSpec()
    local playerClass = UnitClass("player")
    if playerClass ~= "Warrior" then return false end
    
    -- This is a placeholder. You'll need to find the correct talent ID and rank for Fury spec.
    -- For example, for Fury, it might be checking a specific talent in the Fury tree.
    -- Assuming a common talent for Fury spec, this needs to be verified in-game.
    -- GetTalentInfo(tabIndex, talentIndex)
    local _, _, _, _, currentRank = GetTalentInfo(2, 1) -- Talent tab 2 is usually Fury, talent 1 is a placeholder
    return currentRank == 1 -- Or whatever rank signifies the spec
end


-- AceConfig options table (simplified for Fury Warrior, no specific configurable options for now)
FuryWarriorOptions = {
    type = "group",
    name = "Fury Warrior",
    handler = FuryWarrior,
    args = {
        specStatus = {
            type = "description",
            name = function()
                return IsFuryWarriorSpec() and
                    "|cff00ff00You are a Fury Warrior|r" or
                    "|cffff0000You are not a Fury Warrior|r"
            end,
            order = 1,
            fontSize = "medium"
        }
    }
}

-- Return module exports
FuryWarrior = {
    MacroTypes = MacroTypes,
    macroMap = macroMap,
    getFuryWarriorMacro = getFuryWarriorMacro,
    initFuryWarriorKeybinds = initFuryWarriorKeybinds,
    ReinitializeKeybinds = ReinitializeKeybinds,
    IsFuryWarriorSpec = IsFuryWarriorSpec,
    Options = FuryWarriorOptions
}
