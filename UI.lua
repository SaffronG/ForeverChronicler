-- Forever Chronicaller: window + slash commands
-- Uses only templates that exist from 3.3.5 through modern clients.

local _, FC = ...

local WIDTH, HEIGHT = 460, 480
local CONTENT_W = WIDTH - 60
local MAX_SHOWN = 300 -- chronicle entries shown in the window (newest first)

local f = CreateFrame("Frame", "ForeverChronicallerFrame", UIParent,
    BackdropTemplateMixin and "BackdropTemplate" or nil)
f:SetSize(WIDTH, HEIGHT)
f:SetPoint("CENTER")
f:SetFrameStrata("DIALOG")
f:SetMovable(true)
f:EnableMouse(true)
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
local function makeTab(label, x)
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(110, 22)
    b:SetPoint("TOPLEFT", x, -58)
    b:SetText(label)
    return b
end
local chronTab = makeTab("Chronicle", 20)
local goalTab = makeTab("Goals", 134)

-- Scroll area
local scroll = CreateFrame("ScrollFrame", "ForeverChronicallerScroll", f, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 20, -88)
scroll:SetPoint("BOTTOMRIGHT", -38, 62)

local content = CreateFrame("Frame", nil, scroll)
content:SetSize(CONTENT_W, 1)
scroll:SetScrollChild(content)

-- Chronicle view: one wrapped FontString
local chronText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
chronText:SetPoint("TOPLEFT")
chronText:SetWidth(CONTENT_W)
chronText:SetJustifyH("LEFT")
chronText:SetJustifyV("TOP")
if chronText.SetSpacing then chronText:SetSpacing(3) end

-- Goals view: pooled rows with a checkbox and a delete button
local rows = {}
local ROW_H = 24
local function getRow(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Frame", nil, content)
    r:SetSize(CONTENT_W, ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)

    r.check = CreateFrame("CheckButton", "ForeverChronicallerGoalCheck" .. i, r, "UICheckButtonTemplate")
    r.check:SetSize(22, 22)
    r.check:SetPoint("LEFT")
    r.check:SetScript("OnClick", function() FC:ToggleGoal(r.index) end)

    r.del = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.del:SetSize(22, 20)
    r.del:SetPoint("RIGHT")
    r.del:SetText("x")
    r.del:SetScript("OnClick", function() FC:RemoveGoal(r.index) end)

    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.text:SetPoint("LEFT", r.check, "RIGHT", 4, 0)
    r.text:SetPoint("RIGHT", r.del, "LEFT", -4, 0)
    r.text:SetJustifyH("LEFT")

    rows[i] = r
    return r
end

-- Input box at the bottom
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

-- Rendering
local mode = "chronicle"

local function refresh()
    if not FC.db or not f:IsShown() then return end
    local db = FC.db
    local open, done = 0, 0
    for _, g in ipairs(db.goals) do if g.done then done = done + 1 else open = open + 1 end end
    local zones = 0
    for _ in pairs(db.zones) do zones = zones + 1 end
    stats:SetText(string.format("Quests: %d   Zones: %d   Deaths: %d   Goals: %d/%d",
        db.stats.quests, zones, db.stats.deaths, done, done + open))

    if mode == "chronicle" then
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
        local goals = db.goals
        for i, g in ipairs(goals) do
            local r = getRow(i)
            r.index = i
            r.check:SetChecked(g.done)
            r.text:SetText(g.done and ("|cff888888" .. g.text .. "|r") or g.text)
            r:Show()
        end
        for i = #goals + 1, #rows do rows[i]:Hide() end
        content:SetHeight(math.max(1, #goals * ROW_H))
        hint:SetText("New goal  (try: level 20 / zone Duskwood / quest <name> / anything)")
    end
end
FC.Refresh = refresh

local function setMode(m)
    mode = m
    if m == "chronicle" then chronTab:Disable(); goalTab:Enable()
    else goalTab:Disable(); chronTab:Enable() end
    scroll:SetVerticalScroll(0)
    refresh()
end
chronTab:SetScript("OnClick", function() setMode("chronicle") end)
goalTab:SetScript("OnClick", function() setMode("goals") end)

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
addBtn:SetScript("OnClick", submit)
input:SetScript("OnEnterPressed", submit)
input:SetScript("OnEscapePressed", input.ClearFocus)

f:SetScript("OnShow", function() setMode(mode) end)
FC:On("ENTRY_ADDED", refresh)
FC:On("GOALS_CHANGED", refresh)

function FC:Toggle(m)
    if m then mode = m end
    if f:IsShown() and not m then f:Hide() else f:Show(); setMode(mode) end
end

-- Slash commands
local function printGoals()
    if #FC.db.goals == 0 then FC:Print("No goals yet. /chron goal <text>") return end
    for i, g in ipairs(FC.db.goals) do
        FC:Print(string.format("%d. %s %s", i, g.done and "|cff00ff00[done]|r" or "[ ]", g.text))
    end
end

SLASH_FOREVERCHRONICALLER1 = "/chron"
SLASH_FOREVERCHRONICALLER2 = "/fc"
SlashCmdList["FOREVERCHRONICALLER"] = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    if cmd == "" then
        FC:Toggle()
    elseif cmd == "note" and rest ~= "" then
        FC:AddEntry("note", "|cffdddddd\"" .. rest .. "\"|r")
        FC:Print("Noted.")
    elseif cmd == "goal" and rest ~= "" then
        FC:AddGoal(rest)
    elseif cmd == "goals" then
        printGoals()
    elseif cmd == "done" and tonumber(rest) then
        FC:CompleteGoal(tonumber(rest))
    elseif cmd == "del" and tonumber(rest) then
        FC:RemoveGoal(tonumber(rest))
        printGoals()
    elseif cmd == "way" and tonumber(rest) then
        if FC:SetGoalWaypoint(tonumber(rest)) then FC:Print("Waypoint set.") end
    elseif cmd == "config" or cmd == "options" then
        FC:OpenSettings()
    elseif cmd == "recent" then
        local n = tonumber(rest) or 10
        local e = FC.db.entries
        for i = math.max(1, #e - n + 1), #e do FC:Print(FC:FormatEntry(e[i])) end
    else
        FC:Print("Commands:")
        FC:Print("/chron - open/close the window")
        FC:Print("/chron note <text> - add a note to your chronicle")
        FC:Print("/chron goal <text> - add a goal (level 20 / zone <name> / quest <name> auto-complete)")
        FC:Print("/chron goals - list goals    /chron done <n>    /chron del <n>")
        FC:Print("/chron recent [n] - print last n chronicle entries")
        FC:Print("/chron goal here  |  /chron goal 45.2 63.1 - location goal (or Ctrl+right-click the world map)")
        FC:Print("/chron way <n> - point the arrow at location goal n")
        FC:Print("/chron config - open the options page")
    end
end