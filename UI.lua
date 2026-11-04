-- Forever Chronicaller: main window + basic slash commands
--   Chronicle tab: the adventure log, newest first.
--   Goals tab: quest-log style - goal list on the left, details on the right
--   (type, status, dates, progress, editable description, actions).

local _, FC = ...

local WIDTH, HEIGHT = 640, 500
local DETAILS_W = 270
local MAX_SHOWN = 300 -- chronicle entries shown in the window (newest first)
local ROW_H = 24

local f = CreateFrame("Frame", "ForeverChronicallerFrame", UIParent,
    BackdropTemplateMixin and "BackdropTemplate" or nil)
f:SetSize(WIDTH, HEIGHT)
f:SetPoint("CENTER")
f:SetFrameStrata("DIALOG")
f:SetMovable(true)
f:EnableMouse(true)
f:SetClampedToScreen(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)
f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
f:Hide()
tinsert(UISpecialFrames, f:GetName()) -- Escape closes it
FC.window = f

local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -18)
title:SetText("Forever Chronicaller")

local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -6, -6)

local stats = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
stats:SetPoint("TOP", title, "BOTTOM", 0, -4)

-- Tabs
local tabs = {}
local function makeTab(label, x)
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(110, 22)
    b:SetPoint("TOPLEFT", x, -58)
    b:SetText(label)
    return b
end
tabs.chronicle = makeTab("Chronicle", 20)
tabs.goals = makeTab("Goals", 134)
FC.windowTabs = tabs -- other modules (e.g. Journey) can add tabs here

-- Scroll area (shared; narrower in Goals mode to make room for details)
local scroll = CreateFrame("ScrollFrame", "ForeverChronicallerScroll", f, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 20, -88)
scroll:SetPoint("BOTTOMRIGHT", -38, 62)

local content = CreateFrame("Frame", nil, scroll)
content:SetSize(WIDTH - 60, 1)
scroll:SetScrollChild(content)

-- Chronicle view: one wrapped FontString
local chronText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
chronText:SetPoint("TOPLEFT")
chronText:SetWidth(WIDTH - 60)
chronText:SetJustifyH("LEFT")
chronText:SetJustifyV("TOP")
if chronText.SetSpacing then chronText:SetSpacing(3) end

-- Goals view: list rows -----------------------------------------------------------
local selected -- index of the goal shown in the details panel
local refresh  -- forward declaration

local rows = {}
local function getRow(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Button", nil, content)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetPoint("RIGHT", content, "RIGHT")

    r.selectedBg = r:CreateTexture(nil, "BACKGROUND")
    r.selectedBg:SetAllPoints()
    r.selectedBg:SetColorTexture(1, 0.82, 0, 0.15)
    r.hover = r:CreateTexture(nil, "HIGHLIGHT")
    r.hover:SetAllPoints()
    r.hover:SetColorTexture(1, 1, 1, 0.06)

    r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
    r.check:SetSize(22, 22)
    r.check:SetPoint("LEFT")
    r.check:SetScript("OnClick", function() FC:SafeCall(FC.ToggleGoal, FC, r.index) end)

    r.del = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.del:SetSize(22, 20)
    r.del:SetPoint("RIGHT")
    r.del:SetText("x")
    r.del:SetScript("OnClick", function() FC:SafeCall(FC.RemoveGoal, FC, r.index) end)

    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.text:SetPoint("LEFT", r.check, "RIGHT", 4, 0)
    r.text:SetPoint("RIGHT", r.del, "LEFT", -4, 0)
    r.text:SetJustifyH("LEFT")
    if r.text.SetWordWrap then r.text:SetWordWrap(false) end

    r:SetScript("OnClick", function()
        selected = r.index
        FC:SafeCall(refresh)
    end)
    rows[i] = r
    return r
end

-- Goals view: details panel ---------------------------------------------------------
local details = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
details:SetPoint("TOPRIGHT", -20, -88)
details:SetPoint("BOTTOMRIGHT", -20, 62)
details:SetWidth(DETAILS_W)
details:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
if details.SetBackdropColor then details:SetBackdropColor(0, 0, 0, 0.5) end
details:Hide()

local function detailText(font, anchor, y)
    local fs = details:CreateFontString(nil, "OVERLAY", font)
    if anchor then fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y or -6)
    else fs:SetPoint("TOPLEFT", 10, -10) end
    fs:SetWidth(DETAILS_W - 20)
    fs:SetJustifyH("LEFT")
    return fs
end

local dTitle = detailText("GameFontNormalLarge")
local dType = detailText("GameFontHighlightSmall", dTitle, -8)
local dStatus = detailText("GameFontHighlightSmall", dType)
local dProgress = detailText("GameFontHighlightSmall", dStatus)
local dDescLabel = detailText("GameFontNormalSmall", dProgress, -12)
dDescLabel:SetText("Notes:")

local desc = CreateFrame("EditBox", "ForeverChronicallerGoalNotes", details, BackdropTemplateMixin and "BackdropTemplate" or nil)
desc:SetPoint("TOPLEFT", dDescLabel, "BOTTOMLEFT", 0, -4)
desc:SetSize(DETAILS_W - 20, 110)
desc:SetMultiLine(true)
desc:SetAutoFocus(false)
desc:SetMaxLetters(500)
desc:SetFontObject(ChatFontNormal)
desc:SetTextInsets(6, 6, 6, 6)
desc:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
if desc.SetBackdropColor then desc:SetBackdropColor(0, 0, 0, 0.6) end
desc:SetScript("OnEscapePressed", desc.ClearFocus)
desc:SetScript("OnTextChanged", function(self, userInput)
    if userInput and selected then FC:SafeCall(FC.SetGoalDescription, FC, selected, self:GetText()) end
end)

local function detailButton(label, x)
    local b = CreateFrame("Button", nil, details, "UIPanelButtonTemplate")
    b:SetSize(80, 22)
    b:SetPoint("BOTTOMLEFT", x, 10)
    b:SetText(label)
    return b
end
local btnArrow = detailButton("Arrow", 10)
local btnDone = detailButton("Done", 95)
local btnDelete = detailButton("Delete", 180)
btnArrow:SetScript("OnClick", function() if selected then FC:SafeCall(FC.SetGoalWaypoint, FC, selected) end end)
btnDone:SetScript("OnClick", function() if selected then FC:SafeCall(FC.ToggleGoal, FC, selected) end end)
btnDelete:SetScript("OnClick", function() if selected then FC:SafeCall(FC.RemoveGoal, FC, selected) end end)

local dEmpty = details:CreateFontString(nil, "OVERLAY", "GameFontDisable")
dEmpty:SetPoint("CENTER")
dEmpty:SetWidth(DETAILS_W - 30)
dEmpty:SetText("Select a goal, or add one below.")

-- Human-readable helpers
local function ago(t)
    local s = time() - t
    if s < 60 then return "just now" end
    if s < 3600 then return string.format("%d min ago", s / 60) end
    if s < 86400 then return string.format("%d h ago", s / 3600) end
    local d = math.floor(s / 86400)
    return string.format("%d day%s ago", d, d == 1 and "" or "s")
end

local function duration(seconds)
    if seconds < 3600 then return string.format("%d min", math.max(1, math.floor(seconds / 60))) end
    if seconds < 86400 then return string.format("%.1f h", seconds / 3600) end
    local d = math.floor(seconds / 86400)
    return string.format("%d day%s", d, d == 1 and "" or "s")
end

function FC:DescribeGoalType(g)
    if g.kind == "level" then return "Level goal - reach level " .. tostring(g.target)
    elseif g.kind == "zone" then return "Zone goal - enter " .. tostring(g.target)
    elseif g.kind == "quest" then
        return tonumber(g.target) and ("Quest goal - quest ID " .. g.target) or ("Quest goal - turn in \"" .. tostring(g.target) .. "\"")
    elseif g.kind == "location" then return "Location goal - arrive within " .. (self.db.settings.arrivalYards or 20) .. " yd"
    elseif g.kind == "shared" then return "Shared goal"
    end
    return "Personal goal - tick it off yourself"
end

local function showDetails()
    local g = selected and FC.db.goals[selected]
    if not g then
        for _, w in ipairs({ dTitle, dType, dStatus, dProgress, dDescLabel, desc, btnArrow, btnDone, btnDelete }) do w:Hide() end
        dEmpty:Show()
        return
    end
    dEmpty:Hide()
    for _, w in ipairs({ dTitle, dType, dStatus, dProgress, dDescLabel, desc, btnDone, btnDelete }) do w:Show() end
    dTitle:SetText(g.text)
    dType:SetText(FC:DescribeGoalType(g))
    if g.done then
        dStatus:SetText(string.format("|cff00ff00Completed|r %s (took %s)",
            date("%Y-%m-%d %H:%M", g.completed or time()), duration((g.completed or time()) - g.created)))
    else
        dStatus:SetText(string.format("Open - created %s (%s)", date("%Y-%m-%d", g.created), ago(g.created)))
    end
    local progress = FC:GoalProgressText(g)
    dProgress:SetText(progress ~= g.text and ("Progress: " .. progress:sub(#g.text + 2)) or "")
    if not desc:HasFocus() then desc:SetText(g.description or "") end
    btnDone:SetText(g.done and "Reopen" or "Done")
    btnArrow:SetShown(g.kind == "location" and not g.done)
end

-- Input box at the bottom ----------------------------------------------------------
local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hint:SetPoint("BOTTOMLEFT", 24, 44)

local input = CreateFrame("EditBox", "ForeverChronicallerInput", f, "InputBoxTemplate")
input:SetSize(WIDTH - 130, 20)
input:SetPoint("BOTTOMLEFT", 28, 20)
input:SetAutoFocus(false)
input:SetMaxLetters(200)

local addBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
addBtn:SetSize(70, 22)
addBtn:SetPoint("LEFT", input, "RIGHT", 8, 0)
addBtn:SetText("Add")

-- Rendering --------------------------------------------------------------------------
local mode = "chronicle"
FC.windowViews = {} -- extra views registered by other modules: name -> { show(), hide() }

refresh = function()
    if not FC.db or not f:IsShown() then return end
    local db = FC.db
    local open, done = 0, 0
    for _, g in ipairs(db.goals) do if g.done then done = done + 1 else open = open + 1 end end
    local zones = 0
    for _ in pairs(db.zones) do zones = zones + 1 end
    stats:SetText(string.format("Quests: %d   Zones: %d   Deaths: %d   Goals: %d/%d",
        db.stats.quests, zones, db.stats.deaths, done, done + open))

    for name, view in pairs(FC.windowViews) do
        if name ~= mode then view.hide() end
    end
    if FC.windowViews[mode] then
        scroll:Hide(); details:Hide(); chronText:Hide()
        for _, r in ipairs(rows) do r:Hide() end
        hint:Hide(); input:Hide(); addBtn:Hide()
        FC.windowViews[mode].show()
        return
    end
    scroll:Show(); hint:Show(); input:Show(); addBtn:Show()

    if mode == "chronicle" then
        details:Hide()
        scroll:SetPoint("BOTTOMRIGHT", -38, 62)
        content:SetWidth(WIDTH - 60)
        for _, r in ipairs(rows) do r:Hide() end
        local lines, n = {}, #db.entries
        for i = n, math.max(1, n - MAX_SHOWN + 1), -1 do
            lines[#lines + 1] = FC:FormatEntry(db.entries[i])
        end
        chronText:SetText(table.concat(lines, "\n"))
        chronText:Show()
        content:SetHeight(math.max(1, chronText:GetStringHeight() + 10))
        hint:SetText("Write a note in your chronicle:")
    else
        chronText:Hide()
        details:Show()
        scroll:SetPoint("BOTTOMRIGHT", -(DETAILS_W + 50), 62)
        content:SetWidth(WIDTH - DETAILS_W - 90)
        local goals = db.goals
        if selected and not goals[selected] then selected = #goals > 0 and #goals or nil end
        for i, g in ipairs(goals) do
            local r = getRow(i)
            r.index = i
            r.check:SetChecked(g.done)
            r.text:SetText(g.done and ("|cff888888" .. g.text .. "|r") or g.text)
            r.selectedBg:SetShown(i == selected)
            r:Show()
        end
        for i = #goals + 1, #rows do rows[i]:Hide() end
        content:SetHeight(math.max(1, #goals * ROW_H))
        hint:SetText("New goal  (try: level 20 / zone Duskwood / quest <name> / here / 45.2 63.1 / anything)")
        showDetails()
    end
end
FC.Refresh = refresh

local function setMode(m)
    mode = m
    for name, tab in pairs(tabs) do
        if name == m then tab:Disable() else tab:Enable() end
    end
    scroll:SetVerticalScroll(0)
    refresh()
end
for name, tab in pairs(tabs) do
    tab:SetScript("OnClick", function() FC:SafeCall(setMode, name) end)
end

-- Other modules call this to add a tab + view to the window.
function FC:AddWindowTab(name, label, view)
    local count = 0
    for _ in pairs(tabs) do count = count + 1 end
    local tab = makeTab(label, 20 + count * 114)
    tabs[name] = tab
    self.windowViews[name] = view
    tab:SetScript("OnClick", function() FC:SafeCall(setMode, name) end)
    return f -- parent for the view's frames
end

local function submit()
    local text = input:GetText()
    if text and text:match("%S") then
        if mode == "chronicle" then
            FC:AddEntry("note", "|cffdddddd\"" .. text .. "\"|r")
        else
            FC:AddGoal(text)
        end
    end
    input:SetText("")
    input:ClearFocus()
end
addBtn:SetScript("OnClick", function() FC:SafeCall(submit) end)
input:SetScript("OnEnterPressed", function() FC:SafeCall(submit) end)
input:SetScript("OnEscapePressed", input.ClearFocus)

f:SetScript("OnShow", function() FC:SafeCall(setMode, mode) end)
FC:On("ENTRY_ADDED", refresh)
FC:On("GOALS_CHANGED", refresh)
FC:On("GOAL_ADDED", function(_, index) selected = index end)
FC:On("LOCATIONS_UPDATED", function() if mode == "goals" then showDetails() end end)

function FC:Toggle(m)
    if m then mode = m end
    if f:IsShown() and not m then f:Hide() else f:Show(); setMode(mode) end
end

-- for tests
function FC:SelectGoal(index) selected = index; refresh() end
function FC:GetWindowState() return mode, selected end

-- Slash commands -----------------------------------------------------------------------
local function printGoals()
    if #FC.db.goals == 0 then FC:Print("No goals yet. /chron goal <text>") return end
    for i, g in ipairs(FC.db.goals) do
        FC:Print(string.format("%d. %s %s", i, g.done and "|cff00ff00[done]|r" or "[ ]", g.text))
    end
end

FC:Command("", "/chron - open/close the window", function() FC:Toggle() end, 1)

FC:Command("note", "/chron note <text> - add a note to your chronicle", function(rest)
    if rest == "" then return false end
    FC:AddEntry("note", "|cffdddddd\"" .. rest .. "\"|r")
    FC:Print("Noted.")
end)

FC:Command("goal", "/chron goal <text> - add a goal (level 20 / zone <name> / quest <name or ID> / here / 45.2 63.1 / anything)",
    function(rest)
        if rest == "" then return false end
        FC:AddGoal(rest)
    end)

FC:Command("goals", "/chron goals - list goals", printGoals)

FC:Command("done", "/chron done <n> - mark goal n as done", function(rest)
    if not tonumber(rest) then return false end
    FC:CompleteGoal(tonumber(rest))
end)

FC:Command("del", "/chron del <n> - delete goal n", function(rest)
    if not tonumber(rest) then return false end
    FC:RemoveGoal(tonumber(rest))
    printGoals()
end)

FC:Command("recent", "/chron recent [n] - print the last n chronicle entries", function(rest)
    local n = tonumber(rest) or 10
    local e = FC.db.entries
    for i = math.max(1, #e - n + 1), #e do FC:Print(FC:FormatEntry(e[i])) end
end, 20)
