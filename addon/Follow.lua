-- Follow handling for Multibox addon

MultiboxFollow = {}

function MultiboxFollow:Initialize()
    SLASH_FOLLOW1 = "/followme"
    SlashCmdList["FOLLOW"] = MultiboxFollow.FollowMe
end

function MultiboxFollow.FollowMe(msg, editbox)
    local master = UnitName("player")
    if msg and msg ~= "" then
        master = msg
    end
    FollowUnit(master)
end
