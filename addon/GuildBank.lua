-- Guild bank handling for Multibox addon

MultiboxGuildBank = {}

local MY_GUILD = "Raiders of Tamriel"

function MultiboxGuildBank:Initialize()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("GUILDBANKFRAME_OPENED")
    frame:SetScript("OnEvent", MultiboxGuildBank.OnEvent)
end

function MultiboxGuildBank.OnEvent(self, event, ...)
    DEFAULT_CHAT_FRAME:AddMessage(event)
    if event == "GUILDBANKFRAME_OPENED" then
        local guildName = GetGuildInfo("player")
        if guildName == MY_GUILD then
            DepositGuildBankMoney(GetMoney())
            return
        end
        DEFAULT_CHAT_FRAME:AddMessage("You are not in the correct guild for Multibox banking.")
    end
end
