-- list of the problems found by the route check (ADRouteCheck)
ADRouteCheckGui = {}
ADRouteCheckGui.debug = false

local ADRouteCheckGui_mt = Class(ADRouteCheckGui, DialogElement)

function ADRouteCheckGui.new(target)
    local self = DialogElement.new(target, ADRouteCheckGui_mt)
    self:include(ADGuiDebugMixin)
    self.problems = {}
    return self
end

function ADRouteCheckGui:onOpen()
    ADRouteCheckGui:superClass().onOpen(self)
    self.problemList:setDataSource(self)
    self:refreshItems()
end

function ADRouteCheckGui:refreshItems()
    self.problems = ADRouteCheck.problems or {}
    if self.titleText ~= nil then
        self.titleText:setText(ADRouteCheck:getTitle())
    end
    self.problemList:reloadData()
end

function ADRouteCheckGui:getNumberOfItemsInSection(list, section)
    if list == self.problemList then
        return #self.problems
    end
    return 0
end

function ADRouteCheckGui:populateCellForItemInSection(list, section, index, cell)
    if list == self.problemList then
        local problem = self.problems[index]
        cell.attributes.listItemIcon:setImageSlice(nil, ADRouteCheck.KIND_ICONS[problem.kind])
        cell.attributes.listItemText:setText(ADRouteCheck:getRowText(problem))
        cell.target = self
    end
end

function ADRouteCheckGui:showProblem(index)
    local problem = self.problems[index]
    if problem ~= nil then
        self:onClickBack()
        ADRouteCheck:show(problem, AutoDrive.getControlledVehicle())
    end
end

function ADRouteCheckGui:onDoubleClick(list, section, index, cell)
    self:showProblem(index)
end

function ADRouteCheckGui:onClickShow()
    self:showProblem(self.problemList:getSelectedIndexInSection())
end

-- the network changes on the server first, check again a moment later
ADRouteCheckGui.RECHECK_DELAY = 800

function ADRouteCheckGui:onClickFix()
    local problem = self.problems[self.problemList:getSelectedIndexInSection()]
    if problem ~= nil and ADRouteCheck:fix(problem) then
        self.recheckTimer = ADRouteCheckGui.RECHECK_DELAY
    end
end

function ADRouteCheckGui:update(dt)
    ADRouteCheckGui:superClass().update(self, dt)
    if self.recheckTimer ~= nil then
        self.recheckTimer = self.recheckTimer - dt
        if self.recheckTimer <= 0 then
            self.recheckTimer = nil
            self:onClickCheckAgain()
        end
    end
end

function ADRouteCheckGui:onClickCheckAgain()
    ADRouteCheck:run(AutoDrive.getControlledVehicle())
    self:refreshItems()
end
