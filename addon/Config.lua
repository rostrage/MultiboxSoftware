MultiboxConfig = LibStub("AceAddon-3.0"):NewAddon("MultiboxConfig", "AceConsole-3.0")

local frame
local specStatus

function MultiboxConfig:OnInitialize()
    self.currentSpec = "Unknown"
end

function MultiboxConfig:OnEnable()
    self:RegisterChatCommand("mboxconfig", "ChatCommand")
end

function MultiboxConfig:ChatCommand(input)
    self:ShowConfig()
end

function MultiboxConfig:ShowConfig()
    if not frame then
        frame = LibStub("AceGUI-3.0"):Create("Frame")
        frame:SetTitle("Multibox Configuration")
        frame:SetCallback("OnClose", function(widget)
            LibStub("AceGUI-3.0"):Release(widget)
            frame = nil
            specStatus = nil
        end)
        frame:SetLayout("Flow")

        local statusLabel = LibStub("AceGUI-3.0"):Create("Label")
        statusLabel:SetText("Spec:")
        statusLabel:SetWidth(50)
        frame:AddChild(statusLabel)

        specStatus = LibStub("AceGUI-3.0"):Create("Label")
        frame:AddChild(specStatus)
    end

    specStatus:SetText(self.currentSpec)
    frame:Show()
end

function MultiboxConfig:UpdateSpecStatus(spec)
    self.currentSpec = spec
    if specStatus then
        specStatus:SetText(spec)
    end
end
