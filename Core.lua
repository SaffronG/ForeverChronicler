-- Forever Chronicaller: core / persistence
local ADDON, FC = ...
FC.name = ADDON
_G.ForeverChronicaller = FC -- handy for /dump and debugging

local DB_VERSION = 1

local function defaults()
    return {
        version = DB_VERSION,
        entries = {},   -- chronicle: { t = time(), kind = "level", text = "...", zone = "..." }
        goals = {},     -- { text, kind = "free"|"level"|"zone"|"quest", target, done, created, completed }
        zones = {},     -- set of zone names already visited
        stats = { deaths = 0, quests = 0 },
        errorLog = {},  -- recent Lua errors caught by FC:SafeCall, see /chron errors
        settings = {
            -- which automatic entry types get written (notes and the opening entry are always kept)
            chronicle = { level = true, zone = true, quest = true, death = true, achievement = true, goal = true },
            maxEntries = 0, -- 0 = unlimited; otherwise oldest entries are dropped as new ones arrive
            arrivalYards = 20, -- how close you must get to complete a location goal
            showTracker = true, -- on-screen goal tracker
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
    DEFAULT_CHAT_FRAME:AddMessage("|cffd4af37[Chronicaller]|r " .. tostring(msg))
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
            table.insert(log, { t = time(), msg = msg, stack = stack, count = 1 })
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

-- Simple internal message bus so modules don't depend on each other directly.
FC.listeners = {}
function FC:On(msg, fn)
    self.listeners[msg] = self.listeners[msg] or {}
    table.insert(self.listeners[msg], fn)
end
function FC:Fire(msg, ...)
    for _, fn in ipairs(self.listeners[msg] or {}) do self:SafeCall(fn, ...) end
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
    for _, fn in ipairs(handlers[event] or {}) do FC:SafeCall(fn, ...) end
end)

FC:RegisterEvent("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    ForeverChronicallerDB = ForeverChronicallerDB or defaults()
    merge(ForeverChronicallerDB, defaults())
    FC.db = ForeverChronicallerDB
    FC:Fire("READY")
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
    FC:Print("Full details incl. stack traces are saved in WTF/.../SavedVariables/ForeverChronicaller.lua (errorLog).")
end, 95)

SLASH_FOREVERCHRONICALLER1 = "/chron"
SLASH_FOREVERCHRONICALLER2 = "/fc"
SlashCmdList["FOREVERCHRONICALLER"] = function(msg)
    if not FC.db then return end
    local name, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    local cmd = FC.commands[(name or ""):lower()]
    if not cmd then help() return end
    local ok, result = FC:SafeCall(cmd.fn, rest or "")
    if ok and result == false and cmd.usage then FC:Print("Usage: " .. cmd.usage) end
end
