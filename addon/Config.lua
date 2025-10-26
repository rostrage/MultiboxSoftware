MultiboxConfig = LibStub("AceAddon-3.0"):NewAddon("MultiboxConfig", "AceConsole-3.0")

local frame
local specStatus

function MultiboxConfig:OnInitialize()
    self.currentSpec = "Unknown"
    self.optionsRegistered = false
    self:RegisterOptions()
end

function MultiboxConfig:OnEnable()
    self:RegisterChatCommand("mboxconfig", "ChatCommand")
    self:RegisterChatCommand("mbox", "ChatCommand")
end

function MultiboxConfig:ChatCommand(input)
    self:ShowConfig()
end

function MultiboxConfig:RegisterOptions()
    -- Only register once to avoid exceptions on reload
    if self.optionsRegistered then return end
    
    -- Register AceConfig options
    local AceConfig = LibStub("AceConfig-3.0")
    local AceConfigDialog = LibStub("AceConfigDialog-3.0")
    
    -- Create main options table
    local options = {
        type = "group",
        name = "Multibox Configuration",
        args = {
            general = {
                type = "group",
                name = "General",
                order = 1,
                args = {
                    specStatus = {
                        type = "description",
                        name = function()
                            return "Current Spec: |cff33ccff" .. self.currentSpec .. "|r"
                        end,
                        order = 1,
                        fontSize = "medium"
                    },
                    configButton = {
                        type = "execute",
                        name = "Open Configuration",
                        desc = "Open the full configuration interface",
                        order = 2,
                        func = function()
                            self:ShowConfig()
                        end
                    }
                }
            },
            specs = {
                type = "group",
                name = "Spec Configuration",
                order = 2,
                args = {}
            }
        }
    }
    
    -- Add spec-specific options if available
    if RetriPaladin and RetriPaladin.Options then
        options.args.specs.args.retriPaladin = RetriPaladin.Options
    end
    
    -- Register the options table
    AceConfig:RegisterOptionsTable("MultiboxConfig", options, {"/mboxconfig", "/mbox"})
    
    -- Add to Blizzard options panel (only once)
    AceConfigDialog:AddToBlizOptions("MultiboxConfig", "Multibox")
    
    self.optionsRegistered = true
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
        
        -- Add Retribution Paladin options if available
        if RetriPaladin and RetriPaladin.Options then
            local retriGroup = LibStub("AceGUI-3.0"):Create("InlineGroup")
            retriGroup:SetTitle("Retribution Paladin Settings")
            retriGroup:SetLayout("Flow")
            retriGroup:SetWidth(300)
            
            local judgmentType = LibStub("AceGUI-3.0"):Create("Dropdown")
            judgmentType:SetLabel("Judgment Type")
            judgmentType:SetList({
                ["light"] = "Judgment of Light",
                ["wisdom"] = "Judgment of Wisdom"
            })
            judgmentType:SetValue(RetriPaladinDB and RetriPaladinDB.judgmentType or "light")
            judgmentType:SetCallback("OnValueChanged", function(widget, event, value)
                RetriPaladinDB = RetriPaladinDB or {}
                RetriPaladinDB.judgmentType = value
                RetriPaladin:UpdateJudgmentMacro()
                DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[RetriPaladin]|r Judgment type changed to: " .. (value == "wisdom" and "Judgment of Wisdom" or "Judgment of Light"))
            end)
            
            retriGroup:AddChild(judgmentType)
            frame:AddChild(retriGroup)
        end
    end

    specStatus:SetText(self.currentSpec)
    frame:Show()
end

function MultiboxConfig:UpdateSpecStatus(spec)
    self.currentSpec = spec
    if specStatus then
        specStatus:SetText(spec)
    end
    
    -- Notify AceConfig of changes if Retribution Paladin
    if RetriPaladin and RetriPaladin:IsRetributionSpec() then
        local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
        AceConfigRegistry:NotifyChange("MultiboxConfig")
    end
end
