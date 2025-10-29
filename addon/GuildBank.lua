-- Guild bank handling for Multibox addon

MultiboxGuildBank = {}

local MY_GUILD = "Raiders of Tamriel"

function MultiboxGuildBank:Initialize()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("GUILDBANKFRAME_OPENED")
    frame:SetScript("OnEvent", MultiboxGuildBank.OnEvent)
end

function MultiboxGuildBank.OnEvent(self, event, ...)
    if event == "GUILDBANKFRAME_OPENED" then
        local guildName = GetGuildInfo("player")
        if guildName == MY_GUILD then
            DepositGuildBankMoney(GetMoney())
            return
        end
    end
end
