-- Follow handling for Multibox addon

MultiboxFollow = {
    followTarget = nil
}

function MultiboxFollow.SetFollowTarget(target)
    if target and target ~= "" and target ~= UnitName("player") then
        MultiboxFollow.followTarget = target
        DEFAULT_CHAT_FRAME:AddMessage("Multibox: Now following " .. target)
        FollowUnit(target)
    else
        MultiboxFollow.followTarget = nil
        DEFAULT_CHAT_FRAME:AddMessage("Multibox: Follow disabled")
        FollowUnit(nil) -- Stop following
    end
end

function MultiboxFollow.OnEvent(self, event, ...)
    if MultiboxFollow.followTarget then
        FollowUnit(MultiboxFollow.followTarget)
    end
end

function MultiboxFollow:Initialize()
    local frame = CreateFrame("Frame")
	frame:RegisterEvent( "PLAYER_REGEN_DISABLED" )
	frame:RegisterEvent( "PLAYER_REGEN_ENABLED" )	
	frame:RegisterEvent( "PLAYER_CONTROL_GAINED" )
    frame:SetScript("OnEvent", MultiboxFollow.OnEvent)
end
