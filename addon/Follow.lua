-- Follow handling for Multibox addon

MultiboxFollow = {}



function MultiboxFollow.OnEvent(self, event, ...)
    -- local master = UnitName("player")
    -- if msg and msg ~= "" then
    --     master = msg
    -- end
    FollowUnit("focus")
end

function MultiboxFollow:Initialize()
    local frame = CreateFrame("Frame")
	frame:RegisterEvent( "PLAYER_REGEN_DISABLED" )
	frame:RegisterEvent( "PLAYER_REGEN_ENABLED" )	
	frame:RegisterEvent( "PLAYER_CONTROL_GAINED" )
    frame:SetScript("OnEvent", MultiboxFollow.OnEvent)
end