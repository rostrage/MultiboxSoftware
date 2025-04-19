SLASH_HELLO1 = "/hw"
local frame = CreateFrame("Frame", nil, UIParent) -- Creates a parent frame anchored to the main UI
local gsub = gsub;
-- Positioning settings:
frame:SetPoint("TOPLEFT", 63, -126)         -- Centers horizontally and vertically
frame:SetSize(1000, 1000)          -- Makes it 100x100 pixels in size

-- Create texture object and set properties:
local texture = frame:CreateTexture() 
-- message("3")
texture:SetPoint("TOPLEFT")
texture:SetSize(1, 1)
texture:SetTexture("Interface\\AddOns\\Pixels\\Smooth.tga")

local function drawPixel(r,g,b)
    texture:SetVertexColor(r, g, b) -- Set solid red color (R=1, G=0, B=0)
    -- Optional: Ensure it appears on top of other elements
    frame:SetFrameStrata("HIGH")
end

local function test(name)
    -- for i=0,255 do
    --     drawPixel(i/255,0,0,0,i-1)
    -- end
end

local function getRestoShamanMacro()
    if not UnitBuff("player", "Water Shield") then
        return "/cast Water Shield"
    end
    if not GetWeaponEnchantInfo() then
        return "/cast Earthliving Weapon"
    end
    if GetUnitName("focus") and UnitInRange("focus") and not UnitBuff("focus", "Earth Shield") then
        return "/cast [target=focus] Earth Shield"
    end
    local macrotemplate = "/cast [@raidNUMBER] Lesser Healing Wave"
    local targetPercent = 1.0
    local numtargets = 0
    local target = 0
    for i = 1, GetNumRaidMembers() do
        u=GetUnitName("raid"..i);
        local healthPercent = UnitHealth(u)/UnitHealthMax(u);
        if healthPercent < 1.0 then
            if UnitIsPlayer(u) and UnitInRange(u)  then
                numtargets = numtargets + 1;
                if healthPercent < targetPercent then
                    targetPercent = healthPercent;
                    target = i;
                end;
            end
        end
    end;
    if numtargets > 1 then
        return gsub("/cast [@raidNUMBER] Chain Heal", "NUMBER", target);
    elseif numtargets > 0 then
        local start, duration, enabled, modRate = GetSpellCooldown("Riptide")
        if start > 0 and duration > 0 then
            return gsub("/cast [@raidNUMBER] Lesser Healing Wave", "NUMBER", target);
        else
            return gsub("/cast [@raidNUMBER] Riptide", "NUMBER", target);
        end
    else
        return "/run print(\"Doing nothing\")";
    end;
end


SlashCmdList["HELLO"] = test
-- local i = 0;
local frame = CreateFrame("FRAME")
local timeElapsed = 0
MacroButton=CreateFrame("Button","MyMacroButton",nil,"SecureActionButtonTemplate");
MacroButton:RegisterForClicks("AnyUp");--   Respond to all buttons
MacroButton:SetAttribute("type","macro");-- Set type to "macro"
-- SetBindingClick("R", "MyMacroButton")
frame:HookScript("OnUpdate", function(self, elapsed)
	timeElapsed = timeElapsed + elapsed
	if (timeElapsed > .1) then
		timeElapsed = 0
        local nextMacro = getRestoShamanMacro();
        DEFAULT_CHAT_FRAME:AddMessage(nextMacro);

        -- DEFAULT_CHAT_FRAME:AddMessage("foo");
        MacroButton:SetAttribute("macrotext",nextMacro);
        -- drawPixel(i/255,0,0)
		-- do something
	end
end)