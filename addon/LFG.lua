-- LFG handling for Multibox addon

MultiboxLFG = {}

function MultiboxLFG.OnEvent(self, event, ...)
    if event == "LFG_PROPOSAL_SHOW" then
		LFDDungeonReadyDialogEnterDungeonButton:Click();
	elseif event == "LFG_ROLE_CHECK_SHOW" then
		LFDRoleCheckPopupAcceptButton:Click();
    end
end

function MultiboxLFG:Initialize()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("LFG_PROPOSAL_SHOW")
    frame:RegisterEvent("LFG_ROLE_CHECK_SHOW")
    frame:SetScript("OnEvent", MultiboxLFG.OnEvent)
end