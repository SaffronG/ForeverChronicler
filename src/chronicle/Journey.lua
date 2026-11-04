-- Forever Chronicaller: journey statistics and graphs ("Journey" tab)
-- Records small snapshots ("samples") of your progress over time and draws them
-- as line charts with the client's line API, plus a written summary:
-- zones in the order you found them, time per level, totals.

local _, FC = ...

local SAMPLE_EVERY = 600   -- seconds between periodic samples (only stored if something changed)
local MAX_SAMPLES = 2000

-- Recording ---------------------------------------------------------------------------
local function countZones()
    local n = 0
    for _ in pairs(FC.db.zones) do n = n + 1 end
    return n
end

function FC:TakeSample(levelOverride)
    local db = self.db
    db.samples = db.samples or {}
    local level = levelOverride or UnitLevel("player") or 0
    local xp, xpMax = UnitXP and UnitXP("player") or 0, UnitXPMax and UnitXPMax("player") or 0
    local progress = level + ((xpMax and xpMax > 0) and (xp / xpMax) or 0)
    if levelOverride then progress = levelOverride end -- XP just reset at level-up
    local s = {
        t = time(),
        level = math.floor(progress * 100 + 0.5) / 100,
        money = GetMoney and GetMoney() or 0,
        quests = db.stats.quests,
        deaths = db.stats.deaths,
        zones = countZones(),
    }
    local last = db.samples[#db.samples]
    if last and last.level == s.level and last.money == s.money and last.quests == s.quests
        and last.deaths == s.deaths and last.zones == s.zones then
        return -- nothing changed
    end
    table.insert(db.samples, s)
    if #db.samples > MAX_SAMPLES then
        -- thin out the oldest half instead of dropping history entirely
        local keep = {}
        local half = math.floor(#db.samples / 2)
        for i, smp in ipairs(db.samples) do
            if i > half or i % 2 == 1 then keep[#keep + 1] = smp end
        end
        db.samples = keep
    end
    self:Fire("SAMPLES_CHANGED")
end

FC:On("READY", function()
    FC:TakeSample()
    C_Timer.NewTicker(SAMPLE_EVERY, function() FC:SafeCall(FC.TakeSample, FC) end)
end)
FC:On("LEVEL", function(level) FC:TakeSample(level) end)
FC:On("QUEST", function() FC:TakeSample() end)
FC:On("ENTRY_ADDED", function(e) if e and (e.kind == "zone" or e.kind == "death") then FC:TakeSample() end end)

-- Statistics ----------------------------------------------------------------------------
local function duration(seconds)
    if seconds < 3600 then return string.format("%d min", math.max(1, math.floor(seconds / 60))) end
    if seconds < 86400 * 2 then return string.format("%.1f h", seconds / 3600) end
    return string.format("%.1f days", seconds / 86400)
end

function FC:JourneyStats()
    local db = self.db
    local stats = { zones = {}, levels = {} }
    for zone, t in pairs(db.zones) do stats.zones[#stats.zones + 1] = { zone = zone, t = t } end
    table.sort(stats.zones, function(a, b) return a.t < b.t end)

    local lastLevelT, lastLevel
    local first = db.entries[1]
    if first then lastLevelT, lastLevel = first.t, first.level end
    for _, e in ipairs(db.entries) do
        if e.kind == "level" then
            local lvl = tonumber(e.text:match("level (%d+)"))
            if lvl and lastLevelT and lastLevel and lvl == lastLevel + 1 then
                stats.levels[#stats.levels + 1] = { level = lvl, seconds = e.t - lastLevelT }
            end
            lastLevelT, lastLevel = e.t, lvl
        end
    end
    local total, fastest, slowest = 0, nil, nil
    for _, l in ipairs(stats.levels) do
        total = total + l.seconds
        if not fastest or l.seconds < fastest.seconds then fastest = l end
        if not slowest or l.seconds > slowest.seconds then slowest = l end
    end
    stats.fastest, stats.slowest = fastest, slowest
    stats.averageLevel = #stats.levels > 0 and total / #stats.levels or nil
    stats.since = first and first.t or time()
    return stats
end

function FC:JourneySummary()
    local s = self:JourneyStats()
    local db = self.db
    local lines = {}
    lines[#lines + 1] = string.format("|cffffd100Adventuring for|r %s   |cffffd100Quests|r %d   |cffffd100Deaths|r %d   |cffffd100Entries|r %d",
        duration(time() - s.since), db.stats.quests, db.stats.deaths, #db.entries)
    if s.averageLevel then
        lines[#lines + 1] = string.format("|cffffd100Average time per level|r %s   |cffffd100Fastest|r %d (%s)   |cffffd100Slowest|r %d (%s)",
            duration(s.averageLevel), s.fastest.level, duration(s.fastest.seconds), s.slowest.level, duration(s.slowest.seconds))
    end
    if #s.zones > 0 then
        local names = {}
        for _, z in ipairs(s.zones) do names[#names + 1] = z.zone end
        lines[#lines + 1] = "|cffffd100Your path|r " .. table.concat(names, " > ")
    end
    return table.concat(lines, "\n")
end

-- Chart view -----------------------------------------------------------------------------
local SERIES = {
    { key = "level",  label = "Level",  color = { 0.3, 0.9, 0.3 }, fmt = function(v) return string.format("%.1f", v) end },
    { key = "money",  label = "Gold",   color = { 1.0, 0.82, 0.0 }, scale = 1 / 10000, fmt = function(v) return string.format("%dg", v) end },
    { key = "quests", label = "Quests", color = { 1.0, 1.0, 0.3 }, fmt = function(v) return string.format("%d", v) end },
    { key = "zones",  label = "Zones",  color = { 0.4, 0.8, 1.0 }, fmt = function(v) return string.format("%d", v) end },
    { key = "deaths", label = "Deaths", color = { 1.0, 0.3, 0.3 }, fmt = function(v) return string.format("%d", v) end },
}

local CHART_W, CHART_H = 560, 230
local view, chart, lines, labels, summary, emptyText = nil, nil, {}, {}, nil, nil
local current = SERIES[1]

-- Points to draw: { x = 0..1, y = 0..1 } plus min/max labels.
function FC:ChartPoints(seriesKey)
    local series
    for _, s in ipairs(SERIES) do if s.key == seriesKey then series = s end end
    local samples = self.db.samples or {}
    if #samples < 2 or not series then return nil end
    local t0, t1 = samples[1].t, samples[#samples].t
    if t1 - t0 < 60 then return nil end -- need at least a minute of history
    local minV, maxV
    for _, smp in ipairs(samples) do
        local v = (smp[seriesKey] or 0) * (series.scale or 1)
        minV = minV and math.min(minV, v) or v
        maxV = maxV and math.max(maxV, v) or v
    end
    if maxV == minV then maxV = minV + 1 end
    local pts = {}
    for _, smp in ipairs(samples) do
        local v = (smp[seriesKey] or 0) * (series.scale or 1)
        pts[#pts + 1] = { x = (smp.t - t0) / (t1 - t0), y = (v - minV) / (maxV - minV) }
    end
    return pts, minV, maxV, t0, t1, series
end

local function label(parent, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    labels[#labels + 1] = fs
    return fs
end

local yMin, yMax, xStart, xEnd

local function drawChart()
    for _, l in ipairs(lines) do l:Hide() end
    local pts, minV, maxV, t0, t1, series = FC:ChartPoints(current.key)
    if not pts then
        emptyText:Show()
        yMin:SetText(""); yMax:SetText(""); xStart:SetText(""); xEnd:SetText("")
        return
    end
    emptyText:Hide()
    if not chart.CreateLine then return end
    -- downsample to at most ~280 segments so drawing stays cheap
    local step = math.max(1, math.floor(#pts / 280))
    local n = 0
    local prev
    for i = 1, #pts, step do
        local p = pts[i]
        if i + step > #pts then p = pts[#pts] end
        if prev then
            n = n + 1
            local line = lines[n]
            if not line then
                line = chart:CreateLine(nil, "ARTWORK")
                line:SetThickness(2)
                lines[n] = line
            end
            line:SetColorTexture(series.color[1], series.color[2], series.color[3], 1)
            line:SetStartPoint("BOTTOMLEFT", chart, prev.x * CHART_W, prev.y * CHART_H)
            line:SetEndPoint("BOTTOMLEFT", chart, p.x * CHART_W, p.y * CHART_H)
            line:Show()
        end
        prev = p
    end
    yMin:SetText(series.fmt(minV)); yMax:SetText(series.fmt(maxV))
    xStart:SetText(date("%b %d", t0)); xEnd:SetText(date("%b %d %H:%M", t1))
end

local buttons = {}
local function refreshView()
    if not view or not view:IsShown() then return end
    for _, b in ipairs(buttons) do
        if b.series == current then b:Disable() else b:Enable() end
    end
    drawChart()
    summary:SetText(FC:JourneySummary())
end

local function build(parent)
    view = CreateFrame("Frame", nil, parent)
    view:SetPoint("TOPLEFT", 20, -88)
    view:SetPoint("BOTTOMRIGHT", -20, 16)
    view:Hide()

    for i, s in ipairs(SERIES) do
        local b = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
        b:SetSize(80, 20)
        b:SetPoint("TOPLEFT", (i - 1) * 84, 0)
        b:SetText(s.label)
        b.series = s
        b:SetScript("OnClick", function() current = s; FC:SafeCall(refreshView) end)
        buttons[#buttons + 1] = b
    end

    chart = CreateFrame("Frame", nil, view)
    chart:SetSize(CHART_W, CHART_H)
    chart:SetPoint("TOPLEFT", 40, -32)
    local bg = chart:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.35)
    for _, y in ipairs({ 0, 0.5, 1 }) do -- light grid
        local g = chart:CreateTexture(nil, "BORDER")
        g:SetColorTexture(1, 1, 1, 0.08)
        g:SetHeight(1)
        g:SetPoint("BOTTOMLEFT", 0, y * CHART_H)
        g:SetPoint("BOTTOMRIGHT", 0, y * CHART_H)
    end

    yMax = label(view); yMax:SetPoint("TOPRIGHT", chart, "TOPLEFT", -4, 0)
    yMin = label(view); yMin:SetPoint("BOTTOMRIGHT", chart, "BOTTOMLEFT", -4, 0)
    xStart = label(view); xStart:SetPoint("TOPLEFT", chart, "BOTTOMLEFT", 0, -3)
    xEnd = label(view); xEnd:SetPoint("TOPRIGHT", chart, "BOTTOMRIGHT", 0, -3)

    emptyText = chart:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("CENTER")
    emptyText:SetText("Not enough history yet - your journey graph fills in as you play.")

    summary = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", chart, "BOTTOMLEFT", -40, -22)
    summary:SetWidth(CHART_W + 40)
    summary:SetJustifyH("LEFT")
    if summary.SetSpacing then summary:SetSpacing(4) end
end

FC:On("READY", function()
    if not FC.AddWindowTab then return end
    local parent = FC:AddWindowTab("journey", "Journey", {
        show = function() view:Show(); refreshView() end,
        hide = function() if view then view:Hide() end end,
    })
    build(parent)
end)
FC:On("SAMPLES_CHANGED", refreshView)

FC:Command("journey", "/chron journey - open your journey graphs and statistics", function()
    FC:Toggle("journey")
end, 15)

-- for tests
function FC:SetChartSeries(key) for _, s in ipairs(SERIES) do if s.key == key then current = s end end end
function FC:ChartLineCount() local n = 0 for _, l in ipairs(lines) do if l:IsShown() then n = n + 1 end end return n end
