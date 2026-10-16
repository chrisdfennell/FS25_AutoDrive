function AutoDrive:loadGUI()
	g_overlayManager:addTextureConfigFile(g_autoDriveUIConfigPath, "ad_gui")
	g_gui:loadProfiles(AutoDrive.directory .. "gui/guiProfiles.xml")

	AutoDrive.gui = {}
	AutoDrive.gui.ADEnterDriverNameGui = ADEnterDriverNameGui.new()
	AutoDrive.gui.ADEnterTargetNameGui = ADEnterTargetNameGui.new()
	AutoDrive.gui.ADEnterGroupNameGui = ADEnterGroupNameGui.new()
	AutoDrive.gui.ADEnterDestinationFilterGui = ADEnterDestinationFilterGui.new()
	AutoDrive.gui.ADRoutesManagerGui = ADRoutesManagerGui.new()
	AutoDrive.gui.ADNotificationsHistoryGui = ADNotificationsHistoryGui.new()
	AutoDrive.gui.ADColorSettingsGui = ADColorSettingsGui.new()
	AutoDrive.gui.ADScanConfirmationGui = ADScanConfirmationGui.new()
	AutoDrive.gui.ADRouteCheckGui = ADRouteCheckGui.new()
	AutoDrive.gui.ADFleetGui = ADFleetGui.new()
	AutoDrive.gui.ADSendToGui = ADSendToGui.new()
	AutoDrive.gui.ADUnloadFilterGui = ADUnloadFilterGui.new()
	AutoDrive.gui.ADVehicleMenuGui = ADVehicleMenuGui.new()

    local count = 1
    local result = nil

	result = g_gui:loadGui(AutoDrive.directory .. "gui/enterDriverNameGUI.xml", "ADEnterDriverNameGui", AutoDrive.gui.ADEnterDriverNameGui)
    count = count + 1
    if result == nil then
        AutoDrive.debugMsg(nil, "AutoDrive:loadGUI failed count %d", count)
    end

	result = g_gui:loadGui(AutoDrive.directory .. "gui/enterTargetNameGUI.xml", "ADEnterTargetNameGui", AutoDrive.gui.ADEnterTargetNameGui)
    count = count + 1
    if result == nil then
        AutoDrive.debugMsg(nil, "AutoDrive:loadGUI failed count %d", count)
    end

	result = g_gui:loadGui(AutoDrive.directory .. "gui/enterGroupNameGUI.xml", "ADEnterGroupNameGui", AutoDrive.gui.ADEnterGroupNameGui)
    count = count + 1
    if result == nil then
        AutoDrive.debugMsg(nil, "AutoDrive:loadGUI failed count %d", count)
    end

	result = g_gui:loadGui(AutoDrive.directory .. "gui/enterDestinationFilterGUI.xml", "ADEnterDestinationFilterGui", AutoDrive.gui.ADEnterDestinationFilterGui)
    count = count + 1
    if result == nil then
        AutoDrive.debugMsg(nil, "AutoDrive:loadGUI failed count %d", count)
    end

	result = g_gui:loadGui(AutoDrive.directory .. "gui/routesManagerGUI.xml", "ADRoutesManagerGui", AutoDrive.gui.ADRoutesManagerGui)
    count = count + 1
    if result == nil then
        AutoDrive.debugMsg(nil, "AutoDrive:loadGUI failed count %d", count)
    end

	result = g_gui:loadGui(AutoDrive.directory .. "gui/notificationsHistoryGUI.xml", "ADNotificationsHistoryGui", AutoDrive.gui.ADNotificationsHistoryGui)
    count = count + 1
    if result == nil then
        AutoDrive.debugMsg(nil, "AutoDrive:loadGUI failed count %d", count)
    end

	result = g_gui:loadGui(AutoDrive.directory .. "gui/colorSettingsGUI.xml", "ADColorSettingsGui", AutoDrive.gui.ADColorSettingsGui)
    count = count + 1
    if result == nil then
        AutoDrive.debugMsg(nil, "AutoDrive:loadGUI failed count %d", count)
    end

	result = g_gui:loadGui(AutoDrive.directory .. "gui/scanConfirmationGUI.xml", "ADScanConfirmationGui", AutoDrive.gui.ADScanConfirmationGui)
    count = count + 1
    if result == nil then
        AutoDrive.debugMsg(nil, "AutoDrive:loadGUI failed count %d", count)
    end

	result = g_gui:loadGui(AutoDrive.directory .. "gui/routeCheckGUI.xml", "ADRouteCheckGui", AutoDrive.gui.ADRouteCheckGui)
    count = count + 1
    if result == nil then
        AutoDrive.debugMsg(nil, "AutoDrive:loadGUI failed count %d", count)
    end

	result = g_gui:loadGui(AutoDrive.directory .. "gui/fleetGUI.xml", "ADFleetGui", AutoDrive.gui.ADFleetGui)
    count = count + 1
    if result == nil then
        AutoDrive.debugMsg(nil, "AutoDrive:loadGUI failed count %d", count)
    end

	result = g_gui:loadGui(AutoDrive.directory .. "gui/sendToGUI.xml", "ADSendToGui", AutoDrive.gui.ADSendToGui)
    count = count + 1
    if result == nil then
        AutoDrive.debugMsg(nil, "AutoDrive:loadGUI failed count %d", count)
    end

	result = g_gui:loadGui(AutoDrive.directory .. "gui/unloadFilterGUI.xml", "ADUnloadFilterGui", AutoDrive.gui.ADUnloadFilterGui)
    count = count + 1
    if result == nil then
        AutoDrive.debugMsg(nil, "AutoDrive:loadGUI failed count %d", count)
    end

	result = g_gui:loadGui(AutoDrive.directory .. "gui/vehicleMenuGUI.xml", "ADVehicleMenuGui", AutoDrive.gui.ADVehicleMenuGui)
    count = count + 1
    if result == nil then
        AutoDrive.debugMsg(nil, "AutoDrive:loadGUI failed count %d", count)
    end

	AutoDrive.gui.ADGlobalSettingsPage = ADSettingsPage.new()
	AutoDrive.gui.ADUserSettingsPage = ADSettingsPage.new()
	AutoDrive.gui.ADVehicleSettingsPage = ADSettingsPage.new()
	AutoDrive.gui.ADCombineUnloadSettingsPage = ADSettingsPage.new()
	AutoDrive.gui.ADEnvironmentSettingsPage = ADSettingsPage.new()
	AutoDrive.gui.ADDebugSettingsPage = ADDebugSettingsPage.new()

	AutoDrive.gui.ADSettings = ADSettings.new()

	result = g_gui:loadGui(AutoDrive.directory .. "gui/globalSettingsPage.xml", "autoDriveGlobalSettings", AutoDrive.gui.ADGlobalSettingsPage, true)
    count = count + 1
    if result == nil then
        AutoDrive.debugMsg(nil, "AutoDrive:loadGUI failed count %d", count)
    end

	result = g_gui:loadGui(AutoDrive.directory .. "gui/userSettingsPage.xml", "autoDriveUserSettings", AutoDrive.gui.ADUserSettingsPage, true)
    count = count + 1
    if result == nil then
        AutoDrive.debugMsg(nil, "AutoDrive:loadGUI failed count %d", count)
    end

	result = g_gui:loadGui(AutoDrive.directory .. "gui/vehicleSettingsPage.xml", "autoDriveVehicleSettings", AutoDrive.gui.ADVehicleSettingsPage, true)
    count = count + 1
    if result == nil then
        AutoDrive.debugMsg(nil, "AutoDrive:loadGUI failed count %d", count)
    end

	result = g_gui:loadGui(AutoDrive.directory .. "gui/combineUnloadSettingsPage.xml", "autoDriveCombineUnloadSettings", AutoDrive.gui.ADCombineUnloadSettingsPage, true)
    count = count + 1
    if result == nil then
        AutoDrive.debugMsg(nil, "AutoDrive:loadGUI failed count %d", count)
    end

	result = g_gui:loadGui(AutoDrive.directory .. "gui/environmentSettingsPage.xml", "autoDriveEnvironmentSettings", AutoDrive.gui.ADEnvironmentSettingsPage, true)
    count = count + 1
    if result == nil then
        AutoDrive.debugMsg(nil, "AutoDrive:loadGUI failed count %d", count)
    end

	result = g_gui:loadGui(AutoDrive.directory .. "gui/debugSettingsPage.xml", "autoDriveDebugSettings", AutoDrive.gui.ADDebugSettingsPage, true)
    count = count + 1
    if result == nil then
        AutoDrive.debugMsg(nil, "AutoDrive:loadGUI failed count %d", count)
    end

	result = g_gui:loadGui(AutoDrive.directory .. "gui/settings.xml", "ADSettings", AutoDrive.gui.ADSettings)
    count = count + 1
    if result == nil then
        AutoDrive.debugMsg(nil, "AutoDrive:loadGUI failed count %d", count)
    end
end

function AutoDrive.onOpenSettings()
	if AutoDrive.gui.ADSettings.isOpen then
		AutoDrive.gui.ADSettings:onClickBack()
	elseif not g_gui:getIsGuiVisible() then
		g_gui:showGui("ADSettings")
	end
end

function AutoDrive.onOpenEnterDriverName()
	if not AutoDrive.gui.ADEnterDriverNameGui.isOpen then
		g_gui:showDialog("ADEnterDriverNameGui")
	end
end

function AutoDrive.onOpenEnterTargetName()
	if not AutoDrive.gui.ADEnterTargetNameGui.isOpen then
		g_gui:showDialog("ADEnterTargetNameGui")
	end
end

function AutoDrive.onOpenEnterGroupName(parentGroupName, renameGroupName)
	if not AutoDrive.gui.ADEnterGroupNameGui.isOpen then
		AutoDrive.gui.ADEnterGroupNameGui:setGroupNames(parentGroupName, renameGroupName)
		g_gui:showDialog("ADEnterGroupNameGui")
	end
end

function AutoDrive.onOpenEnterDestinationFilter()
	if not AutoDrive.gui.ADEnterDestinationFilterGui.isOpen then
		g_gui:showDialog("ADEnterDestinationFilterGui")
	end
end

function AutoDrive.onOpenRoutesManager()
	if not AutoDrive.gui.ADRoutesManagerGui.isOpen then
		g_gui:showDialog("ADRoutesManagerGui")
	end
end

function AutoDrive.onOpenRouteCheck()
	if not AutoDrive.gui.ADRouteCheckGui.isOpen then
		g_gui:showDialog("ADRouteCheckGui")
	end
end

function AutoDrive.onOpenSendTo(vehicle)
	if not AutoDrive.gui.ADSendToGui.isOpen then
		AutoDrive.gui.ADSendToGui:setVehicle(vehicle)
		g_gui:showDialog("ADSendToGui")
	end
end

-- unload products of a vehicle, or of a target (marker) when given
function AutoDrive.onOpenUnloadFilter(vehicle, marker)
	if not AutoDrive.gui.ADUnloadFilterGui.isOpen then
		AutoDrive.gui.ADUnloadFilterGui:setSubject(vehicle, marker)
		AutoDriveUnloadFilterEvent.request(vehicle)
		AutoDrive.gui.ADUnloadFilterGui.refreshTimer = 500
		g_gui:showDialog("ADUnloadFilterGui")
	end
end

function AutoDrive.onOpenVehicleMenu(vehicle)
	if not AutoDrive.gui.ADVehicleMenuGui.isOpen then
		AutoDrive.gui.ADVehicleMenuGui:setVehicle(vehicle)
		g_gui:showDialog("ADVehicleMenuGui")
	end
end

function AutoDrive.onOpenFleet()
	if not AutoDrive.gui.ADFleetGui.isOpen then
		g_gui:showDialog("ADFleetGui")
	end
end

function AutoDrive.onOpenNotificationsHistory()
	if not AutoDrive.gui.ADNotificationsHistoryGui.isOpen then
		g_gui:showDialog("ADNotificationsHistoryGui")
	end
end

function AutoDrive.onOpenColorSettings()
	if not AutoDrive.gui.ADColorSettingsGui.isOpen then
		g_gui:showDialog("ADColorSettingsGui")
	end
end

function AutoDrive.onOpenScanConfirmation()
	if not AutoDrive.gui.ADScanConfirmationGui.isOpen then
		g_gui:showDialog("ADScanConfirmationGui")
	end
end

function AutoDrive.showYesNoDialog(title, text, callback, target, ...)
	local dlg = g_gui:showDialog("YesNoDialog")
	dlg.target:setTitle(title)
	dlg.target.dialogTextElement:setText(text)
	dlg.target:setCallback(callback, target, ...)
end


ADGuiDebugMixin = {}

function ADGuiDebugMixin.new()
    return setmetatable({}, {__index = ADGuiDebugMixin})
end

function ADGuiDebugMixin:addTo(guiElement)
    guiElement.debugMsg = ADGuiDebugMixin.debugMsg
end

function ADGuiDebugMixin:debugMsg(...)
    if self.debug == true then
        AutoDrive.debugMsg(nil, ...)
    end
end
