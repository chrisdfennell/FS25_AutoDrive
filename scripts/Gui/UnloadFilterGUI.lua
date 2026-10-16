-- unload products of a vehicle or a target (ADUnloadFilter): click products to select / unselect them,
-- "All products" removes the limit. Changes are sent right away (AutoDriveUnloadFilterEvent).
ADUnloadFilterGui = {}
ADUnloadFilterGui.debug = false
ADUnloadFilterGui.CHECKED = "[x] "
ADUnloadFilterGui.UNCHECKED = "[  ] "

local ADUnloadFilterGui_mt = Class(ADUnloadFilterGui, DialogElement)

function ADUnloadFilterGui.new(target)
    local self = DialogElement.new(target, ADUnloadFilterGui_mt)
    self:include(ADGuiDebugMixin)
    self.rows = {}
    return self
end

-- vehicle or marker (target)
function ADUnloadFilterGui:setSubject(vehicle, marker)
    self.vehicle = vehicle
    self.marker = marker
end

function ADUnloadFilterGui:getSet()
    if self.marker ~= nil then
        return ADUnloadFilter.getTargetFilter(self.marker) or {}
    end
    if self.vehicle ~= nil and self.vehicle.ad ~= nil then
        return self.vehicle.ad.unloadFilter or {}
    end
    return {}
end

function ADUnloadFilterGui:getChoices()
    if self.marker ~= nil then
        return ADUnloadFilter.getTargetChoices(self.marker)
    end
    return ADUnloadFilter.getVehicleChoices(self.vehicle)
end

function ADUnloadFilterGui:onOpen()
    ADUnloadFilterGui:superClass().onOpen(self)
    if self.titleText ~= nil then
        if self.marker ~= nil then
            self.titleText:setText(string.format(g_i18n:getText("gui_ad_unloadFilterTitleTarget"), self.marker.name))
        elseif self.vehicle ~= nil and self.vehicle.ad ~= nil then
            self.titleText:setText(string.format(g_i18n:getText("gui_ad_unloadFilterTitleVehicle"), self.vehicle.ad.stateModule:getName()))
        end
    end
    self.list:setDataSource(self)
    self:refreshItems()
end

function ADUnloadFilterGui:refreshItems()
    self.rows = ADUnloadFilter.getRows(self:getChoices(), self:getSet())
    -- pallets can only be chosen when Universal Autoload sets them down (left / behind / right)
    if self.marker == nil and self.vehicle ~= nil then
        local hasPallets, canChoose = ADUnloadFilter.getPalletState(self.vehicle)
        if hasPallets and not canChoose then
            table.insert(self.rows, 1, {note = "AD_unloadFilter_palletPosition"})
        end
    end
    self.list:reloadData()
end

-- a multiplayer client gets the current lists a moment after opening
function ADUnloadFilterGui:update(dt)
    ADUnloadFilterGui:superClass().update(self, dt)
    if self.refreshTimer ~= nil then
        self.refreshTimer = self.refreshTimer - dt
        if self.refreshTimer <= 0 then
            self.refreshTimer = nil
            self:refreshItems()
        end
    end
end

function ADUnloadFilterGui:getNumberOfItemsInSection(list, section)
    if list == self.list then
        return math.max(1, #self.rows)
    end
    return 0
end

function ADUnloadFilterGui.getRowText(row)
    local text = (row.selected and ADUnloadFilterGui.CHECKED or ADUnloadFilterGui.UNCHECKED) .. row.title
    if row.litres > 0 then
        text = text .. "  (" .. string.format(g_i18n:getText("AD_unloadFilter_onBoard"), string.format("%d l", math.floor(row.litres + 0.5))) .. ")"
    end
    return text
end

function ADUnloadFilterGui:populateCellForItemInSection(list, section, index, cell)
    if list == self.list then
        local row = self.rows[index]
        if row ~= nil and row.note ~= nil then
            cell.attributes.listItemIcon:setImageSlice(nil, "ad_gui.warn_icon")
            cell.attributes.listItemText:setText(g_i18n:getText(row.note))
        elseif row == nil then
            -- nothing to choose from
            cell.attributes.listItemIcon:setImageSlice(nil, "ad_gui.warn_icon")
            cell.attributes.listItemText:setText(g_i18n:getText(self.marker ~= nil and "AD_unloadFilter_noneTarget" or "AD_unloadFilter_noneVehicle"))
        else
            cell.attributes.listItemIcon:setImageSlice(nil, "ad_gui.info_icon")
            cell.attributes.listItemText:setText(ADUnloadFilterGui.getRowText(row))
        end
        cell.target = self
    end
end

function ADUnloadFilterGui:send(set)
    if self.marker ~= nil then
        AutoDriveUnloadFilterEvent.setTarget(self.marker.name, set)
        ADUnloadFilter.setTargetFilter(self.marker.name, set)
    elseif self.vehicle ~= nil then
        AutoDriveUnloadFilterEvent.setVehicle(self.vehicle, set)
        ADUnloadFilter.setVehicleFilter(self.vehicle, set)
    end
    self:refreshItems()
end

function ADUnloadFilterGui:toggle(index)
    local row = self.rows[index]
    if row == nil or row.note ~= nil then
        return
    end
    local set = ADUnloadFilter.copy(self:getSet())
    if set[row.name] then
        set[row.name] = nil
    else
        set[row.name] = true
    end
    self:send(set)
end

function ADUnloadFilterGui:onDoubleClick(list, section, index, cell)
    self:toggle(index)
end

function ADUnloadFilterGui:onClickToggle()
    self:toggle(self.list:getSelectedIndexInSection())
end

function ADUnloadFilterGui:onClickAll()
    self:send({})
end

-------------------------------------------------------------------------------
-- fleet overview: double click on a vehicle -> send to / unload products / enter vehicle
-------------------------------------------------------------------------------

ADVehicleMenuGui = {}
ADVehicleMenuGui.debug = false
ADVehicleMenuGui.ITEMS = {"AD_vehicleMenu_sendTo", "AD_vehicleMenu_unload", "AD_vehicleMenu_enter"}

local ADVehicleMenuGui_mt = Class(ADVehicleMenuGui, DialogElement)

function ADVehicleMenuGui.new(target)
    local self = DialogElement.new(target, ADVehicleMenuGui_mt)
    self:include(ADGuiDebugMixin)
    return self
end

function ADVehicleMenuGui:setVehicle(vehicle)
    self.vehicle = vehicle
end

function ADVehicleMenuGui:onOpen()
    ADVehicleMenuGui:superClass().onOpen(self)
    if self.titleText ~= nil and self.vehicle ~= nil and self.vehicle.ad ~= nil then
        self.titleText:setText(self.vehicle.ad.stateModule:getName())
    end
    self.list:setDataSource(self)
    self.list:reloadData()
end

function ADVehicleMenuGui:getNumberOfItemsInSection(list, section)
    return #ADVehicleMenuGui.ITEMS
end

function ADVehicleMenuGui:populateCellForItemInSection(list, section, index, cell)
    cell.attributes.listItemIcon:setImageSlice(nil, "ad_gui.info_icon")
    cell.attributes.listItemText:setText(g_i18n:getText(ADVehicleMenuGui.ITEMS[index]))
    cell.target = self
end

function ADVehicleMenuGui:choose(index)
    local vehicle = self.vehicle
    if vehicle == nil or vehicle.ad == nil then
        return
    end
    self:onClickBack()
    if index == 1 then
        AutoDrive.onOpenSendTo(vehicle)
    elseif index == 2 then
        AutoDrive.onOpenUnloadFilter(vehicle, nil)
    elseif index == 3 then
        if AutoDrive.gui.ADFleetGui.isOpen then
            AutoDrive.gui.ADFleetGui:onClickBack()
        end
        AutoDrive.requestToEnterVehicle(vehicle)
    end
end

function ADVehicleMenuGui:onDoubleClick(list, section, index, cell)
    self:choose(index)
end

function ADVehicleMenuGui:onClickChoose()
    self:choose(self.list:getSelectedIndexInSection())
end
