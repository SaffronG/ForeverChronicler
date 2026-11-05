-- Forever Chronicler: core / persistence
local ADDON, FC = ...

-- Feature flags. Diagnostics (handler timing for telemetry) are built and tested
-- but switched off in this version: no option, no command, no timing.
FC.FEATURES = { diagnostics = false }
FC.name = ADDON
_G.ForeverChronicler = FC -- handy for /dump and debugging

local DB_VERSION = 1

local function defaults()
    return {
        version = DB_VERSION,
        entries = {},   -- chronicle: { t = time(), kind = "level", text = "...", zone = "..." }
        goals = {},     -- { text, kind = "free"|"level"|"zone"|"quest", target, done, created, completed }
        zones = {},     -- set of zone names already visited
        stats = { deaths = 0, quests = 0, recipes = 0, crafts = 0 },
        professions = {}, -- [skillLineID] = { name, skill, maxSkill, learned, total, scanned, crafts, first, gone }
        crafted = {},     -- [itemID] = times crafted (for "first time crafted" entries)
        days = {},        -- ["YYYY-MM-DD"] = daily ledger for the letters (see Letters.lua)
        errorLog = {},  -- recent Lua errors caught by FC:SafeCall, see /chron errors
        settings = {
            -- which automatic entry types get written (notes and the opening entry are always kept)
            chronicle = { level = true, zone = true, quest = true, death = true, achievement = true, goal = true,
                profession = true, recipe = true, craft = true },
            maxEntries = 0, -- 0 = unlimited; otherwise oldest entries are dropped as new ones arrive
            arrivalYards = 20, -- how close you must get to complete a location goal
            showTracker = true, -- on-screen goal tracker
            acceptShares = true, -- show popups when group members share goals
            diagnostics = false, -- opt-in: time handlers locally (see FC:Dispatch, PRIVACY.md)
            trackerCollapsed = false,
            trackerPos = nil, -- { point, relativePoint, x, y } once the tracker has been moved
        },
    }
end

-- Fill in any keys missing from older saves without wiping existing data.
local function merge(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = v
        elseif type(v) == "table" and type(dst[k]) == "table" then
            merge(dst[k], v)
        end
    end
end

function FC:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffd4af37[Chronicler]|r " .. tostring(msg))
end

function FC:Zone()
    local z = GetRealZoneText()
    if not z or z == "" then z = GetZoneText() or "Unknown" end
    return z
end

-- Error isolation --------------------------------------------------------------
-- Every event handler, internal message listener and slash command runs through
-- FC:SafeCall. An error in one feature (say, map pins) is logged and reported,
-- but never stops the chronicle or other features from working.

local unpack = unpack or table.unpack
local MAX_ERRORS = 30

local function report(err)
    local msg = tostring(err)
    local log = FC.db and FC.db.errorLog
    if log then
        local last = log[#log]
        if last and last.msg == msg then
            last.count = (last.count or 1) + 1 -- e.g. a 1-second ticker failing repeatedly
            last.t = time()
        else
            local stack = debugstack and debugstack(2, 8, 0) or nil
            -- v and label link the error to a version and to the handler that failed
            -- (used by the companion's opt-in telemetry; see PRIVACY.md)
            table.insert(log, { t = time(), first = time(), msg = msg, stack = stack, count = 1,
                v = FC.version, label = FC.currentLabel })
            while #log > MAX_ERRORS do table.remove(log, 1) end
        end
    end
    if not FC.warnedAboutErrors then
        FC.warnedAboutErrors = true
        FC:Print("|cffff5555Something went wrong in one feature; everything else keeps working. Type /chron errors for details.|r")
    end
    local handler = geterrorhandler and geterrorhandler()
    if handler then pcall(handler, msg) end -- also show in BugSack / the Lua error window if enabled
    return msg
end

function FC:SafeCall(fn, ...)
    local n, args = select("#", ...), { ... }
    return xpcall(function() return fn(unpack(args, 1, n)) end, report)
end

-- Performance diagnostics (opt-in, off by default) --------------------------------
-- When settings.diagnostics is on, every dispatched handler is timed into
-- latency buckets per label ("event:PLAYER_LEVEL_UP", "msg:GOALS_CHANGED",
-- "cmd:goal"). Stored locally in db.diagnostics and reset when the version
-- changes. Labels are code names only, never player data. The companion app
-- sends these only if its telemetry is also turned on.
local BOUNDS = { 0.1, 0.5, 1, 2, 5, 10, 25, 50, 100, 250, 1000 } -- milliseconds
FC.DIAG_BOUNDS = BOUNDS
local MAX_LABELS = 200

local function recordTiming(label, ms, failed)
    local d = FC.db.diagnostics
    if type(d) ~= "table" or d.version ~= FC.version then
        d = { version = FC.version, since = time(), handlers = {}, labels = 0 }
        FC.db.diagnostics = d
    end
    local h = d.handlers[label]
    if not h then
        if d.labels >= MAX_LABELS then return end
        h = { n = 0, sum = 0, max = 0, err = 0, b = {} }
        for i = 1, #BOUNDS + 1 do h.b[i] = 0 end
        d.handlers[label] = h
        d.labels = d.labels + 1
    end
    h.n = h.n + 1
    h.sum = h.sum + ms
    if ms > h.max then h.max = ms end
    if failed then h.err = h.err + 1 end
    local i = 1
    while i <= #BOUNDS and ms > BOUNDS[i] do i = i + 1 end
    h.b[i] = h.b[i] + 1
end

-- Run a handler isolated (SafeCall) and, if diagnostics are on, timed.
function FC:Dispatch(label, fn, ...)
    local previous = self.currentLabel
    self.currentLabel = label
    local timing = self.FEATURES.diagnostics and self.db and self.db.settings and self.db.settings.diagnostics
        and debugprofilestop
    local start = timing and debugprofilestop()
    local ok, result = self:SafeCall(fn, ...)
    -- re-check: the handler itself may have just turned diagnostics off
    if timing and self.FEATURES.diagnostics and self.db.settings.diagnostics then recordTiming(label, debugprofilestop() - start, not ok) end
    self.currentLabel = previous
    return ok, result
end

-- Simple internal message bus so modules don't depend on each other directly.
FC.listeners = {}
function FC:On(msg, fn)
    self.listeners[msg] = self.listeners[msg] or {}
    table.insert(self.listeners[msg], fn)
end
function FC:Fire(msg, ...)
    for _, fn in ipairs(self.listeners[msg] or {}) do self:Dispatch("msg:" .. msg, fn, ...) end
end

-- WoW event dispatch
local frame = CreateFrame("Frame")
FC.frame = frame
local handlers = {}

function FC:RegisterEvent(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        frame:RegisterEvent(event)
    end
    table.insert(handlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event] or {}) do FC:Dispatch("event:" .. event, fn, ...) end
end)

FC:RegisterEvent("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    -- Up to 0.5.0 the addon was spelled "ForeverChronicaller". If the old saved
    -- table was loaded (the companion copies the old saved file across on
    -- install), adopt it once and drop the old name so it isn't saved again.
    local legacy = rawget(_G, "ForeverChronicallerDB")
    -- "Fresh" = nothing yet, or only the opening entry and no goals.
    -- If both have real data, the old table is left alone (still saved, never lost).
    local current = ForeverChroniclerDB
    local fresh = type(current) ~= "table"
        or (#(current.entries or {}) <= 1 and #(current.goals or {}) == 0)
    if type(legacy) == "table" and fresh then
        ForeverChroniclerDB = legacy
        _G.ForeverChronicallerDB = nil
        FC.migratedFromLegacy = true
    end
    ForeverChroniclerDB = ForeverChroniclerDB or defaults()
    merge(ForeverChroniclerDB, defaults())
    FC.db = ForeverChroniclerDB
    FC:Fire("READY")
    if FC.migratedFromLegacy then FC:Print("Your chronicle from the old \"Forever Chronicaller\" was carried over.") end
end)
-- Slash commands -----------------------------------------------------------------
-- Modules register their own sub-commands: FC:Command("name", "usage text", fn).
-- fn(rest) gets the text after the command name; return false to print the usage.
-- Several names can share one handler: FC:Command({ "config", "options" }, ...).

FC.commands, FC.commandOrder = {}, {}

-- order (optional, default 50) sorts the help list; lower comes first.
function FC:Command(names, usage, fn, order)
    if type(names) ~= "table" then names = { names } end
    local cmd = { usage = usage, fn = fn, order = order or 50, seq = #self.commandOrder }
    for _, name in ipairs(names) do self.commands[name] = cmd end
    if usage then table.insert(self.commandOrder, cmd) end
end

local function help()
    table.sort(FC.commandOrder, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.seq < b.seq
    end)
    FC:Print("Commands (/chron or /fc):")
    for _, cmd in ipairs(FC.commandOrder) do FC:Print(cmd.usage) end
end

FC:Command("help", nil, help)

FC:Command("errors", "/chron errors [clear] - show or clear errors logged by the addon", function(rest)
    local log = FC.db.errorLog
    if rest == "clear" then
        wipe(log)
        FC:Print("Error log cleared.")
        return
    end
    if #log == 0 then FC:Print("No errors logged.") return end
    for i, e in ipairs(log) do
        FC:Print(string.format("%d. %s (x%d) %s", i, date("%m-%d %H:%M", e.t), e.count or 1, e.msg))
    end
    FC:Print("Full details incl. stack traces are saved in WTF/.../SavedVariables/ForeverChronicler.lua (errorLog).")
end, 95)

-- Privacy summary (full text: PRIVACY.md, shipped with the addon) -------------------
local PRIVACY = {
    "|cffd4af37Privacy:|r your chronicle, goals and notes stay on this computer (in WoW's saved data).",
    "This addon can't use the internet. It only sends hidden addon messages when you",
    "share a goal or do a together goal (the goal and your character name, to the players",
    "you choose) and your addon version to your group. Nothing else leaves the game.",
    "Optional extras (Discord/phone posts) live in the separate companion app and are off",
    "unless you set them up. No telemetry is collected. Details: PRIVACY.md in the addon folder.",
}

FC:Command("diagnostics", FC.FEATURES.diagnostics and "/chron diagnostics [on|off] - opt-in local performance timing (sent only via companion telemetry)" or nil, function(rest)
    if not FC.FEATURES.diagnostics then
        FC:Print("Diagnostics aren't available in this version.")
        return
    end
    local s = FC.db.settings
    if rest == "on" then s.diagnostics = true
    elseif rest == "off" then s.diagnostics = false; FC.db.diagnostics = nil
    elseif rest ~= "" then return false end
    FC:Print("Performance diagnostics are " .. (s.diagnostics and "|cff00ff00on|r (timings are kept locally; the companion sends them only if its telemetry is on)." or "off."))
    local d = FC.db.diagnostics
    if s.diagnostics and d and d.handlers then
        local rows = {}
        for label, h in pairs(d.handlers) do rows[#rows + 1] = { label = label, h = h } end
        table.sort(rows, function(a, b) return a.h.sum > b.h.sum end)
        for i = 1, math.min(5, #rows) do
            local h = rows[i].h
            FC:Print(string.format("  %s: %d runs, avg %.2f ms, max %.2f ms", rows[i].label, h.n, h.sum / h.n, h.max))
        end
    end
end, 93)

FC:Command("privacy", "/chron privacy - what this addon stores and shares", function()
    for _, line in ipairs(PRIVACY) do FC:Print(line) end
end, 94)

-- Shown once per character, the first time the addon loads.
FC:On("READY", function()
    if not FC.db.privacyNoticeShown then
        FC.db.privacyNoticeShown = true
        FC:Print("Your chronicle stays on this computer; nothing is shared unless you share goals. /chron privacy for details.")
    end
end)

SLASH_FOREVERCHRONICLER1 = "/chron"
SLASH_FOREVERCHRONICLER2 = "/fc"
SlashCmdList["FOREVERCHRONICLER"] = function(msg)
    if not FC.db then return end
    local name, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    local cmd = FC.commands[(name or ""):lower()]
    if not cmd then help() return end
    local ok, result = FC:Dispatch("cmd:" .. (name or ""):lower(), cmd.fn, rest or "")
    if ok and result == false and cmd.usage then FC:Print("Usage: " .. cmd.usage) end
end
