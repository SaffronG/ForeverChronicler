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
        settings = {
            -- which automatic entry types get written (notes and the opening entry are always kept)
            chronicle = { level = true, zone = true, quest = true, death = true, achievement = true, goal = true },
            maxEntries = 0, -- 0 = unlimited; otherwise oldest entries are dropped as new ones arrive
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

-- Simple internal message bus so modules don't depend on each other directly.
FC.listeners = {}
function FC:On(msg, fn)
    self.listeners[msg] = self.listeners[msg] or {}
    table.insert(self.listeners[msg], fn)
end
function FC:Fire(msg, ...)
    for _, fn in ipairs(self.listeners[msg] or {}) do fn(...) end
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
    for _, fn in ipairs(handlers[event] or {}) do fn(...) end
end)

FC:RegisterEvent("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    ForeverChronicallerDB = ForeverChronicallerDB or defaults()
    merge(ForeverChronicallerDB, defaults())
    FC.db = ForeverChronicallerDB
    FC:Fire("READY")
end)