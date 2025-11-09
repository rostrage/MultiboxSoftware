-- Party handling for Multibox addon

MultiboxParty = {}

function MultiboxParty:Initialize()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PARTY_INVITE_REQUEST")
    frame:SetScript("OnEvent", MultiboxParty.OnEvent)
end

function MultiboxParty.OnEvent(self, event, ...)
    if event == "PARTY_INVITE_REQUEST" then
        local inviter, unk = ...
        AcceptGroup()
        -- Make sure the invite dialog does not decline the invitation when hidden.
		for iteratePopups = 1, STATICPOPUP_NUMDIALOGS do
			local dialog = _G["StaticPopup"..iteratePopups]
			if dialog.which == "PARTY_INVITE" then
				-- Set the inviteAccepted flag to true (even if the invite was declined, as the
				-- flag is only set to stop the dialog from declining in its OnHide event).
				dialog.inviteAccepted = 1
				break
			end
		end
		StaticPopup_Hide( "PARTY_INVITE" )
    end
end
