-- Forever Chronicaller: on-screen goal tracker
-- A small movable box listing open goals, like the quest objective tracker.
--   * Drag the title to move it (position is saved); click the title to collapse.
--   * Location goals show live distance; click them to point the arrow there.
--   * Level goals show progress; clicking other goals opens the Goals tab.
--   * Hidden when there are no open goals, or via the "Show goal tracker" option / /chron tracker.

local _, FC = ...

local WIDTH = 240
local LINE_H = 16
local MAX_LINES = 8

local tracker = CreateFrame("Frame", "ForeverChronicallerTracker", UIParent)
tracker:SetSize(WIDTH, 24)
tracker:SetPoint("RIGHT", UIParent, "RIGHT", -80, 120)
tracker:SetClampedToScreen(true)
tracker:SetMovable(true)
tracker:Hide()
FC.tracker = tracker

local bg = tracker:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.35)

-- Title bar: drag to move, click to collapse
local header = CreateFrame("Button", nil, tracker)
header:SetPoint("TOPLEFT")
header:SetPoint("TOPRIGHT")
header:SetHeight(20)
header:RegisterForDrag("LeftButton")
header:RegisterForClicks("LeftButtonUp")

local headerText = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
headerText:SetPoint("LEFT", 6, 0)
headerText:SetJustifyH("LEFT")

local function savePosition()
    local point, _, relativePoint, x, y = tracker:GetPoint()
    FC.db.settings.trackerPos = { point, relativePoint, x, y }
end

header:SetScript("OnDragStart", function()
    if not InCombatLockdown() then tracker:StartMoving() end
end)
header:SetScript("OnDragStop", function()
    tracker:StopMovingOrSizing()
    FC:SafeCall(savePosition)
end)

-- Lines
local lines = {}
local function getLine(i)
    if lines[i] then return lines[i] end
    local b = CreateFrame("Button", nil, tracker)
    b:SetHeight(LINE_H)
    b:SetPoint("TOPLEFT", 10, -20 - (i - 1) * LINE_H)
    b:SetPoint("TOPRIGHT", -6, -20 - (i - 1) * LINE_H)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetAllPoints()
    b.text:SetJustifyH("LEFT")
    if b.text.SetWordWrap then b.text:SetWordWrap(false) end
    b:SetScript("OnClick", function(self)
        FC:SafeCall(function()
            local g = self.index and FC.db.goals[self.index]
            if not g then return end
            if FC:GoalLocation(g, true) then
                if FC:SetGoalWaypoint(self.index) then FC:Print("Arrow pointing to: " .. g.text) end
            else
                FC:Toggle("goals")
            end
        end)
    end)
    b:SetScript("OnEnter", function(self)
        local g = self.index and FC.db.goals[self.index]
        if not g then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(g.text, 1, 0.82, 0)
        if g.description and g.description ~= "" then GameTooltip:AddLine(g.description, 1, 1, 1, true) end
        GameTooltip:AddLine(FC:GoalLocation(g, true) and "Click to point the arrow here." or "Click to open your goals.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    lines[i] = b
    return b
end

local function formatDistance(yards)
    if yards >= 1000 then return string.format("%.1fk yd", yards / 1000) end
    return string.format("%d yd", math.floor(yards + 0.5))
end

-- Text for one goal line, including progress where we have it.
function FC:GoalProgressText(g)
    local text = g.text
    if g.kind == "level" then
        text = string.format("%s |cffaaaaaa(%d/%d)|r", text, UnitLevel("player") or 0, g.target)
    end
    if FC:GoalLocation(g, true) then
        local d = FC.goalDistance and FC.goalDistance[g]
        if d then text = string.format("%s |cffaaaaaa- %s|r", text, formatDistance(d)) end
    end
    if g.kind == "shared" and FC.SharedProgressText then
        text = string.format("%s |cffaaaaaa%s|r", text, FC:SharedProgressText(g))
    end
    return text
end

local function refresh()
    if not FC.db then return end
    local s = FC.db.settings
    local open = {}
    for i, g in ipairs(FC.db.goals) do
        if not g.done then open[#open + 1] = i end
    end
    if not s.showTracker or #open == 0 then
        tracker:Hide()
        return
    end

    headerText:SetText(string.format("%s Goals (%d)", s.trackerCollapsed and "+" or "-", #open))
    local shown = 0
    if not s.trackerCollapsed then
        for n, index in ipairs(open) do
            if n > MAX_LINES then break end
            local line = getLine(n)
            line.index = index
            line.text:SetText("- " .. FC:GoalProgressText(FC.db.goals[index]))
            line:Show()
            shown = n
        end
        if #open > MAX_LINES then
            local more = getLine(MAX_LINES + 1)
            more.index = nil
            more.text:SetText(string.format("|cffaaaaaa+%d more (/chron)|r", #open - MAX_LINES))
            more:Show()
            shown = shown + 1
        end
    end
    for i = shown + 1, #lines do lines[i]:Hide() end
    tracker:SetHeight(22 + shown * LINE_H + (shown > 0 and 4 or 0))
    tracker:Show()
end
FC.RefreshTracker = refresh

header:SetScript("OnClick", function()
    FC:SafeCall(function()
        FC.db.settings.trackerCollapsed = not FC.db.settings.trackerCollapsed
        refresh()
    end)
end)

FC:On("READY", function()
    local pos = FC.db.settings.trackerPos
    if pos then
        tracker:ClearAllPoints()
        tracker:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end
    refresh()
end)
FC:On("GOALS_CHANGED", refresh)
FC:On("LOCATIONS_UPDATED", refresh)
FC:On("LEVEL", function() C_Timer.After(0, function() FC:SafeCall(refresh) end) end) -- UnitLevel catches up next frame
FC:On("SETTINGS_CHANGED", refresh)

FC:Command("tracker", "/chron tracker - show/hide the goal tracker", function()
    FC.db.settings.showTracker = not FC.db.settings.showTracker
    refresh()
    FC:Print(FC.db.settings.showTracker and "Goal tracker shown." or "Goal tracker hidden.")
end, 25)
