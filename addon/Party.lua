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
        DEFAULT_CHAT_FRAME:AddMessage("Accepting party invite from: " .. inviter)
        AcceptGroup()
    end
end
