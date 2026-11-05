-- Forever Chronicler: export / import (backup, or move to another computer)
--   /chron export  -> window with a text string; Ctrl+C to copy it.
--   /chron import  -> paste a string, then "Merge" (adds what's missing) or "Replace".
--   /chron import undo -> put back the data from before the last import (this session).
--
-- Format: "FC1C:" + Base64(Deflate(CBOR(data))) using C_EncodingUtil when the
-- client has it, otherwise "FC1T:" + Base64(own text serializer). The importer
-- never runs code from the string; it parses it and validates every field.

local _, FC = ...

local MAX_DEPTH = 8

-- Own serializer (fallback) ----------------------------------------------------------
-- n<number>;  s<len>:<bytes>  b1/b0  t ... e   (tables: key, value, key, value...)
local function serialize(v, out, depth)
    depth = depth or 0
    if depth > MAX_DEPTH then error("data too deeply nested") end
    local ty = type(v)
    if ty == "number" then out[#out + 1] = "n" .. string.format("%.17g", v) .. ";"
    elseif ty == "string" then out[#out + 1] = "s" .. #v .. ":" .. v
    elseif ty == "boolean" then out[#out + 1] = v and "b1" or "b0"
    elseif ty == "table" then
        out[#out + 1] = "t"
        for k, val in pairs(v) do
            serialize(k, out, depth + 1)
            serialize(val, out, depth + 1)
        end
        out[#out + 1] = "e"
    end -- functions etc. are skipped
    return out
end

local function deserialize(s)
    local pos = 1
    local function read(depth)
        if depth > MAX_DEPTH then error("data too deeply nested") end
        local tag = s:sub(pos, pos)
        pos = pos + 1
        if tag == "n" then
            local num, nextPos = s:match("^([^;]+);()", pos)
            num = tonumber(num)
            if not num then error("bad number") end
            pos = nextPos
            return num
        elseif tag == "s" then
            local len, nextPos = s:match("^(%d+):()", pos)
            len = tonumber(len)
            if not len or nextPos + len - 1 > #s then error("bad string") end
            local str = s:sub(nextPos, nextPos + len - 1)
            pos = nextPos + len
            return str
        elseif tag == "b" then
            local b = s:sub(pos, pos)
            pos = pos + 1
            return b == "1"
        elseif tag == "t" then
            local t = {}
            while s:sub(pos, pos) ~= "e" do
                if pos > #s then error("unterminated table") end
                local k = read(depth + 1)
                local v = read(depth + 1)
                if type(k) == "table" then error("bad key") end
                t[k] = v
            end
            pos = pos + 1
            return t
        end
        error("bad data")
    end
    local value = read(0)
    return value
end

-- Base64 (fallback; plain arithmetic so it works on any Lua 5.1)
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function b64encode(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1, c2 = math.floor(n / 262144) % 64, math.floor(n / 4096) % 64
        local c3, c4 = math.floor(n / 64) % 64, n % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
            .. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
    end
    return table.concat(out)
end
local B64INV = {}
for i = 1, 64 do B64INV[B64:sub(i, i)] = i - 1 end
local function b64decode(data)
    data = data:gsub("[^%w%+/=]", "")
    local out = {}
    for i = 1, #data, 4 do
        local q = { data:byte(i, i + 3) }
        local v, pad = 0, 0
        for j = 1, 4 do
            local ch = q[j] and string.char(q[j]) or "="
            if ch == "=" then pad = pad + 1; v = v * 64
            else
                local d = B64INV[ch]
                if not d then return nil end
                v = v * 64 + d
            end
        end
        local bytes = string.char(math.floor(v / 65536) % 256, math.floor(v / 256) % 256, v % 256)
        out[#out + 1] = bytes:sub(1, 3 - pad)
    end
    return table.concat(out)
end
FC._b64encode, FC._b64decode = b64encode, b64decode -- for tests

-- Encode / decode --------------------------------------------------------------------
local E = function() return C_EncodingUtil end

function FC:ExportString()
    local data = {
        v = 1,
        exported = time(),
        character = UnitName("player"),
        realm = GetRealmName and GetRealmName() or nil,
        entries = self.db.entries,
        goals = self.db.goals,
        zones = self.db.zones,
        stats = self.db.stats,
        samples = self.db.samples,
        professions = self.db.professions,
        crafted = self.db.crafted,
        days = self.db.days,
    }
    local enc = E()
    if enc and enc.SerializeCBOR and enc.CompressString and enc.EncodeBase64 then
        local ok, result = pcall(function()
            local method = Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate
            return "FC1C:" .. enc.EncodeBase64(enc.CompressString(enc.SerializeCBOR(data), method))
        end)
        if ok and result then return result end
    end
    return "FC1T:" .. b64encode(table.concat(serialize(data, {})))
end

local function decode(str)
    str = str:gsub("^%s+", ""):gsub("%s+$", "")
    local kind, body = str:match("^FC1([CT]):(.+)$")
    if not kind then return nil, "That doesn't look like a Forever Chronicler export." end
    local ok, data = pcall(function()
        if kind == "C" then
            local enc = E()
            if not (enc and enc.DecodeBase64 and enc.DecompressString and enc.DeserializeCBOR) then
                error("this client can't read compressed exports")
            end
            local method = Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate
            return enc.DeserializeCBOR(enc.DecompressString(enc.DecodeBase64(body), method))
        end
        local raw = b64decode(body)
        if not raw then error("damaged text") end
        return deserialize(raw)
    end)
    if not ok or type(data) ~= "table" then
        return nil, "Couldn't read the export (" .. tostring(ok and "empty" or data) .. "). Was it copied completely?"
    end
    return data
end

-- Validation: keep only well-formed records.
local GOAL_KINDS = { free = true, level = true, zone = true, quest = true, location = true, shared = true }

local function cleanEntries(list)
    local out = {}
    if type(list) ~= "table" then return out end
    for _, e in ipairs(list) do
        if type(e) == "table" and type(e.t) == "number" and type(e.kind) == "string" and type(e.text) == "string" then
            out[#out + 1] = { t = e.t, kind = e.kind:sub(1, 20), text = e.text:sub(1, 1000),
                zone = type(e.zone) == "string" and e.zone:sub(1, 100) or nil,
                level = tonumber(e.level) }
        end
    end
    return out
end

local function cleanGoals(list)
    local out = {}
    if type(list) ~= "table" then return out end
    for _, g in ipairs(list) do
        if type(g) == "table" and GOAL_KINDS[g.kind] and type(g.text) == "string" and type(g.created) == "number" then
            local target = g.target
            if g.kind == "location" then
                if type(target) ~= "table" or not (tonumber(target.mapID) and tonumber(target.x) and tonumber(target.y)) then
                    target = nil
                else
                    target = { mapID = tonumber(target.mapID), x = tonumber(target.x), y = tonumber(target.y), armed = false }
                end
            elseif g.kind == "level" then target = tonumber(target)
            elseif g.kind == "shared" then target = FC.CleanSharedTarget and FC.CleanSharedTarget(target) or nil
            elseif type(target) == "table" then target = nil end
            if g.kind == "free" or target ~= nil then
                out[#out + 1] = { kind = g.kind, target = target, text = g.text:sub(1, 200),
                    done = g.done == true, created = g.created, completed = tonumber(g.completed),
                    description = type(g.description) == "string" and g.description:sub(1, 500) or nil,
                    sharedBy = type(g.sharedBy) == "string" and g.sharedBy or nil,
                    shared = type(g.shared) == "table" and g.shared or nil }
            end
        end
    end
    return out
end

-- professions: [skillLineID] = { name, skill, maxSkill, learned, total, scanned, crafts, first, gone }
local function cleanProfessions(list)
    local out = {}
    if type(list) ~= "table" then return out end
    local n = 0
    for id, p in pairs(list) do
        if type(id) == "number" and type(p) == "table" and type(p.name) == "string" and n < 20 then
            local function num(v) v = tonumber(v); return (v and v >= 0 and v < 1e9) and math.floor(v) or nil end
            local learned, total = num(p.learned), num(p.total)
            if learned and total and learned > total then learned = total end
            out[id] = { name = p.name:sub(1, 60), skill = num(p.skill), maxSkill = num(p.maxSkill),
                learned = learned, total = total, scanned = num(p.scanned), crafts = num(p.crafts) or 0,
                first = num(p.first), gone = num(p.gone) }
            n = n + 1
        end
    end
    return out
end

-- crafted: [itemID] = count
local function cleanCrafted(list)
    local out = {}
    if type(list) ~= "table" then return out end
    for id, count in pairs(list) do
        count = tonumber(count)
        if type(id) == "number" and id > 0 and count and count > 0 then out[id] = math.floor(count) end
    end
    return out
end

-- days: ["YYYY-MM-DD"] = { first, last, active, level0, level1, money0, money1, visited = { zone, ... } }
local function cleanDays(list)
    local out = {}
    if type(list) ~= "table" then return out end
    local n = 0
    for key, d in pairs(list) do
        if type(key) == "string" and key:match("^%d%d%d%d%-%d%d%-%d%d$") and type(d) == "table" and n < 5000 then
            local function num(v) v = tonumber(v); return (v and v >= 0 and v < 1e12) and math.floor(v) or nil end
            local visited = {}
            if type(d.visited) == "table" then
                for _, z in ipairs(d.visited) do
                    if type(z) == "string" and #visited < 40 then visited[#visited + 1] = z:sub(1, 100) end
                end
            end
            out[key] = { first = num(d.first), last = num(d.last), active = num(d.active) or 0,
                level0 = num(d.level0), level1 = num(d.level1), money0 = num(d.money0), money1 = num(d.money1),
                visited = visited }
            n = n + 1
        end
    end
    return out
end

local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, val in pairs(v) do t[k] = deepCopy(val) end
    return t
end

-- mode: "merge" (default) or "replace"
function FC:ImportString(str, mode)
    local data, err = decode(str)
    if not data then return false, err end
    local entries, goals = cleanEntries(data.entries), cleanGoals(data.goals)
    local db = self.db
    self.lastImportBackup = deepCopy({ entries = db.entries, goals = db.goals, zones = db.zones, stats = db.stats, samples = db.samples,
        professions = db.professions, crafted = db.crafted, days = db.days })
    local importedDays = cleanDays(data.days)
    local professions, crafted = cleanProfessions(data.professions), cleanCrafted(data.crafted)

    if mode == "replace" then
        db.entries, db.goals = entries, goals
        db.zones = {}
        db.stats = { deaths = 0, quests = 0, recipes = 0, crafts = 0 }
        db.samples = {}
        db.professions, db.crafted, db.days = {}, {}, {}
    else
        local seen = {}
        for _, e in ipairs(db.entries) do seen[e.t .. "\1" .. e.kind .. "\1" .. e.text] = true end
        local added = 0
        for _, e in ipairs(entries) do
            local key = e.t .. "\1" .. e.kind .. "\1" .. e.text
            if not seen[key] then db.entries[#db.entries + 1] = e; seen[key] = true; added = added + 1 end
        end
        table.sort(db.entries, function(a, b) return a.t < b.t end)
        local seenGoals = {}
        for _, g in ipairs(db.goals) do seenGoals[g.created .. "\1" .. g.text] = true end
        for _, g in ipairs(goals) do
            if not seenGoals[g.created .. "\1" .. g.text] then db.goals[#db.goals + 1] = g end
        end
    end
    if type(data.zones) == "table" then
        for zone, t in pairs(data.zones) do
            if type(zone) == "string" and type(t) == "number" and (not db.zones[zone] or t < db.zones[zone]) then db.zones[zone] = t end
        end
    end
    if type(data.stats) == "table" then
        for _, k in ipairs({ "deaths", "quests", "recipes", "crafts" }) do
            local v = tonumber(data.stats[k])
            if v and v > (db.stats[k] or 0) then db.stats[k] = v end
        end
    end
    -- professions: take the imported record if it's newer (scanned later) or unknown here
    db.professions = db.professions or {}
    for id, p in pairs(professions) do
        local mine = db.professions[id]
        if not mine or (p.scanned or 0) > (mine.scanned or 0) then db.professions[id] = p end
    end
    -- days: add the ones we don't have; for shared days keep the one with more time played
    db.days = db.days or {}
    for key, d in pairs(importedDays) do
        local mine = db.days[key]
        if not mine or (d.active or 0) > (mine.active or 0) then db.days[key] = d end
    end
    db.crafted = db.crafted or {}
    for id, count in pairs(crafted) do
        if count > (db.crafted[id] or 0) then db.crafted[id] = count end
    end
    if type(data.samples) == "table" then
        db.samples = db.samples or {}
        local have = {}
        for _, smp in ipairs(db.samples) do have[smp.t] = true end
        for _, smp in ipairs(data.samples) do
            if type(smp) == "table" and type(smp.t) == "number" and not have[smp.t] then db.samples[#db.samples + 1] = smp end
        end
        table.sort(db.samples, function(a, b) return a.t < b.t end)
    end
    self:Fire("GOALS_CHANGED")
    self:Fire("ENTRY_ADDED")
    self:Fire("PROFESSIONS_CHANGED")
    return true, string.format("Imported %d entries and %d goals from %s (%s).",
        #entries, #goals, tostring(data.character or "?"), mode == "replace" and "replaced your data" or "merged")
end

function FC:UndoImport()
    local b = self.lastImportBackup
    if not b then return false end
    for k, v in pairs(b) do self.db[k] = v end
    self.lastImportBackup = nil
    self:Fire("GOALS_CHANGED")
    self:Fire("ENTRY_ADDED")
    return true
end

-- Window -------------------------------------------------------------------------------
local win
local function buildWindow()
    win = CreateFrame("Frame", "ForeverChroniclerExport", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    win:SetSize(520, 360)
    win:SetPoint("CENTER")
    win:SetFrameStrata("FULLSCREEN_DIALOG")
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    tinsert(UISpecialFrames, win:GetName())

    win.title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    win.title:SetPoint("TOP", 0, -18)
    win.help = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.help:SetPoint("TOP", win.title, "BOTTOM", 0, -6)
    win.help:SetWidth(470)

    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    local sf = CreateFrame("ScrollFrame", "ForeverChroniclerExportScroll", win, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 24, -70)
    sf:SetPoint("BOTTOMRIGHT", -42, 50)
    local box = CreateFrame("EditBox", nil, sf)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetMaxLetters(0)
    box:SetFontObject(ChatFontNormal)
    box:SetWidth(440)
    box:SetScript("OnEscapePressed", function() win:Hide() end)
    sf:SetScrollChild(box)
    win.box = box

    local function button(label, x)
        local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
        b:SetSize(110, 22)
        b:SetPoint("BOTTOMLEFT", x, 18)
        b:SetText(label)
        return b
    end
    win.merge = button("Merge", 24)
    win.replace = button("Replace", 140)
    win.merge:SetScript("OnClick", function()
        FC:SafeCall(function()
            local ok, msg = FC:ImportString(box:GetText(), "merge")
            FC:Print(msg)
            if ok then win:Hide(); FC:Print("Changed your mind? /chron import undo") end
        end)
    end)
    win.replace:SetScript("OnClick", function()
        StaticPopup_Show("FOREVERCHRONICLER_IMPORT_REPLACE", nil, nil, box:GetText())
    end)
end

StaticPopupDialogs["FOREVERCHRONICLER_IMPORT_REPLACE"] = {
    text = "Replace this character's whole chronicle and goal list with the imported data?\n\n(You can undo with /chron import undo until you log out.)",
    button1 = "Replace",
    button2 = "Cancel",
    OnAccept = function(_, text)
        FC:SafeCall(function()
            local ok, msg = FC:ImportString(text, "replace")
            FC:Print(msg)
            if ok and win then win:Hide() end
        end)
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function FC:ShowExport()
    if not win then buildWindow() end
    win.title:SetText("Export chronicle")
    win.help:SetText("Press Ctrl+C to copy, then save it somewhere safe or paste it into /chron import on another computer.")
    win.merge:Hide(); win.replace:Hide()
    local str = self:ExportString()
    win.box:SetText(str)
    win:Show()
    win.box:SetFocus()
    win.box:HighlightText()
    self:Print(string.format("Export ready (%d characters).", #str))
end

function FC:ShowImport()
    if not win then buildWindow() end
    win.title:SetText("Import chronicle")
    win.help:SetText("Paste an export with Ctrl+V. Merge adds missing entries and goals; Replace overwrites this character's data.")
    win.merge:Show(); win.replace:Show()
    win.box:SetText("")
    win:Show()
    win.box:SetFocus()
end

FC:Command("export", "/chron export - copy your chronicle and goals as text (backup / other computer)", function()
    FC:ShowExport()
end, 40)

FC:Command("import", "/chron import [undo] - paste an export to merge or replace; 'undo' reverts the last import", function(rest)
    if rest == "undo" then
        FC:Print(FC:UndoImport() and "Import undone." or "Nothing to undo (only works until you log out).")
        return
    end
    FC:ShowImport()
end, 41)

-- /chron sync: the game only writes saved data on logout or reload. Reloading
-- lets the companion app (companion/fcompanion.py) post your latest entries now.
StaticPopupDialogs["FOREVERCHRONICLER_SYNC"] = {
    text = "Reload your UI now to save your chronicle?\n\n(The companion app posts new entries as soon as they're saved.)",
    button1 = "Reload",
    button2 = "Cancel",
    OnAccept = function() ReloadUI() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

FC:Command("sync", "/chron sync - save now (reloads the UI) so the companion app can post your latest entries", function()
    if InCombatLockdown() then FC:Print("Not during combat.") return end
    StaticPopup_Show("FOREVERCHRONICLER_SYNC")
end, 42)
