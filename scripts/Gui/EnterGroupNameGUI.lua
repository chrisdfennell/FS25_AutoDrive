--
-- AutoDrive Enter Group Name GUI
-- V1.1.0.0
--
-- @author Stephan Schlosser
-- @date 09/06/2019

ADEnterGroupNameGui = {}
ADEnterGroupNameGui.debug = false

local ADEnterGroupNameGui_mt = Class(ADEnterGroupNameGui, DialogElement)

function ADEnterGroupNameGui.new(target)
    local self = DialogElement.new(target, ADEnterGroupNameGui_mt)
    self:include(ADGuiDebugMixin)
    return self
end

-- parentGroupName: create the new folder as sub folder of this folder, nil for a top level folder
-- renameGroupName: rename this folder instead of creating a new one
function ADEnterGroupNameGui:setGroupNames(parentGroupName, renameGroupName)
    self.renameGroupName = renameGroupName
    if renameGroupName ~= nil then
        self.parentGroupName = ADGraphManager:getParentGroupName(renameGroupName)
    else
        self.parentGroupName = parentGroupName
    end
end

function ADEnterGroupNameGui:onOpen()
    self:debugMsg("ADEnterGroupNameGui:onOpen")
    ADEnterGroupNameGui:superClass().onOpen(self)
    if self.titleElement ~= nil then
        if self.renameGroupName ~= nil and g_i18n:hasText("gui_ad_renameGroupNameTitle") then
            self.titleElement:setText(string.format(g_i18n:getText("gui_ad_renameGroupNameTitle"), self.renameGroupName))
        elseif self.parentGroupName ~= nil and g_i18n:hasText("gui_ad_enterSubGroupNameTitle") then
            self.titleElement:setText(string.format(g_i18n:getText("gui_ad_enterSubGroupNameTitle"), self.parentGroupName))
        else
            self.titleElement:setText(g_i18n:getText("gui_ad_enterGroupNameTitle"))
        end
    end
    self.textInputElement.blockTime = 0
    self.textInputElement:onFocusActivate()
    if self.renameGroupName ~= nil then
        self.textInputElement:setText(ADGraphManager:getGroupDisplayName(self.renameGroupName))
    else
        self.textInputElement:setText("")
    end
end

function ADEnterGroupNameGui:onClickOk()
    self:debugMsg("ADEnterGroupNameGui:onClickOk")
    local groupName = self.textInputElement.text
    groupName = string.gsub(groupName, ",", "_") -- remove separation characters
    groupName = string.gsub(groupName, ";", "_")
    if self.renameGroupName ~= nil then
        -- renaming keeps the folder in its parent folder
        groupName = string.gsub(groupName, ADGraphManager.GROUP_SEPARATOR, "_")
    end
    if self.parentGroupName ~= nil then
        groupName = self.parentGroupName .. ADGraphManager.GROUP_SEPARATOR .. groupName
    end
    groupName = ADGraphManager:normalizeGroupName(groupName)
    if groupName ~= ADGraphManager.debugGroupName and groupName ~= "All" then
        -- do not allow user to create debug group
        if self.renameGroupName ~= nil then
            ADGraphManager:renameGroup(self.renameGroupName, groupName)
        else
            ADGraphManager:addGroup(groupName)
            ADEnterGroupNameGui.switchFoldersOn()
        end
    end

    self:onClickBack()
end

-- a new folder is only listed with the setting "use folders": switch it on, else the folder seems to be lost
function ADEnterGroupNameGui.switchFoldersOn()
    if AutoDrive.getSetting("useFolders") then
        return
    end
    AutoDrive.setSettingState("useFolders", 2)
    AutoDriveUpdateSettingsEvent.sendEvent(AutoDrive.getControlledVehicle())
    ADMessagesManager:addMessage(nil, ADMessagesManager.messageTypes.INFO, g_i18n:getText("AD_folders_switchedOn"), 6000)
end

function ADEnterGroupNameGui:onEnterPressed(_, isClick)
    self:debugMsg("ADEnterGroupNameGui:onEnterPressed")
    if not isClick then
        self:onClickOk()
    end
end

function ADEnterGroupNameGui:onEscPressed()
    self:debugMsg("ADEnterGroupNameGui:onEscPressed")
    self:onClickBack()
end
