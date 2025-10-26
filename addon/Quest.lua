-- Quest handling for Multibox addon

MultiboxQuest = {}

function MultiboxQuest:Initialize()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("QUEST_CONFIRM")
    frame:RegisterEvent("QUEST_DETAIL")
    frame:SetScript("OnEvent", MultiboxQuest.OnEvent)
end

function MultiboxQuest.OnEvent(self, event, ...)
    if event == "QUEST_CONFIRM" then
        local questGiver, questTitle, unk = ...
        DEFAULT_CHAT_FRAME:AddMessage("Accepting shared quest: " .. questTitle)
        AcceptQuest()
    elseif event == "QUEST_DETAIL" then
        -- from a player
        if UnitIsPlayer("npc") then
            AcceptQuest()
        end
    end
end
