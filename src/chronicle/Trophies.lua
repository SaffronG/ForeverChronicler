-- Forever Chronicler: trophies (notable loot and mighty foes slain)
-- Writes chronicle entries for:
--   * notable loot: the first time you loot each item of the chosen quality or
--     better (Rare by default; Epic and better are highlighted), with the boss
--     it came from if you just defeated one;
--   * bosses defeated (dungeons and raids, ENCOUNTER_END / BOSS_KILL): the first
--     kill per boss and difficulty gets an entry, later kills are only counted;
--   * rare and world-boss monsters slain in the open world: the first kill of
--     each gets an entry.
--
-- No combat log or combat data (Midnight rules): bosses come from encounter
-- events, rares from your target being dead (and not tapped by someone else) or
-- from looting its corpse. Values the client marks as secret are ignored.
--
-- Saved data:
--   db.loot[itemID]  = { n = times looted, q = quality, first = time }
--   db.slain[key]    = { name, kind = "boss"|"rare"|"worldboss", n, first, last, diff }
--                      key = "e<encounterID>:<difficultyID>" or "n<npcID>"
--   db.stats.bosses / db.stats.rares / db.stats.notableLoot = counters

local _, FC = ...

local QUALITY = { [2] = "Uncommon", [3] = "Rare", [4] = "Epic", [5] = "Legendary", [6] = "Artifact", [7] = "Heirloom" }
local QUALITY_COLOR = { [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000", [6] = "e6cc80", [7] = "00ccff" }
-- old-style link colours -> quality (modern links use |cnIQ<q>:)
local COLOR_QUALITY = { ["1eff00"] = 2, ["0070dd"] = 3, ["a335ee"] = 4, ["ff8000"] = 5, ["e6cc80"] = 6, ["00ccff"] = 7 }
local RARE_KINDS = { rare = "rare", rareelite = "rare", worldboss = "worldboss" }
local BOSS_LOOT_WINDOW = 180 -- seconds after a boss kill in which loot is credited to that boss
local MAX_SLAIN = 2000
FC.QUALITY_NAMES = QUALITY

local function db() return FC.db end
local function loot() db().loot = db().loot or {}; return db().loot end
local function slain() db().slain = db().slain or {}; return db().slain end
local function bump(stat) local s = db().stats; s[stat] = (s[stat] or 0) + 1 end

local function secret(v) return issecretvalue and issecretvalue(v) or false end

-- Register an event only if the client knows it.
local function tryEvent(event, fn)
    if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then return false end
    return (pcall(FC.RegisterEvent, FC, event, fn))
end

local function difficultyName(id)
    local name = id and GetDifficultyInfo and GetDifficultyInfo(id)
    return (type(name) == "string" and name ~= "") and name or nil
end

-- Bosses ----------------------------------------------------------------------------------
local lastBoss          -- { name, t } for crediting loot
local recentKill = {}   -- encounterID -> time (ENCOUNTER_END and BOSS_KILL both fire)

function FC:RecordBossKill(encounterID, name, difficultyID, groupSize)
    if secret(encounterID) or secret(name) then return end
    encounterID = tonumber(encounterID)
    if not encounterID or type(name) ~= "string" or name == "" then return end
    local now = time()
    if recentKill[encounterID] and now - recentKill[encounterID] < 30 then return end
    recentKill[encounterID] = now
    lastBoss = { name = name, t = now }
    FC:Fire("BOSS_DEFEATED", name) -- every kill (Companions credits the group)
    difficultyID = tonumber(difficultyID) or 0
    local key = "e" .. encounterID .. ":" .. difficultyID
    local list = slain()
    local rec = list[key]
    bump("bosses")
    if rec then
        rec.n, rec.last = (rec.n or 1) + 1, now
        FC:Fire("TROPHIES_CHANGED")
        return
    end
    list[key] = { name = name:sub(1, 80), kind = "boss", n = 1, first = now, last = now, diff = difficultyID }
    local diff = difficultyName(difficultyID)
    local size = tonumber(groupSize)
    local detail = {}
    if diff then detail[#detail + 1] = diff end
    if size and size > 5 then detail[#detail + 1] = size .. " players" end
    FC:AddEntry("slay", string.format("|cffff6633Defeated %s%s in %s!|r", name,
        #detail > 0 and (" (" .. table.concat(detail, ", ") .. ")") or "", FC:Zone()))
    FC:Fire("TROPHIES_CHANGED")
end

tryEvent("ENCOUNTER_END", function(encounterID, name, difficultyID, groupSize, success)
    if success == 1 or success == true then FC:RecordBossKill(encounterID, name, difficultyID, groupSize) end
end)
tryEvent("BOSS_KILL", function(encounterID, name)
    local diff = GetInstanceInfo and select(3, GetInstanceInfo())
    FC:RecordBossKill(encounterID, name, diff)
end)

-- Rare monsters (open world) ----------------------------------------------------------------
local function npcID(guid)
    if type(guid) ~= "string" or secret(guid) then return nil end
    local unitType, _, _, _, _, id = strsplit("-", guid)
    if unitType ~= "Creature" and unitType ~= "Vehicle" then return nil end
    return tonumber(id)
end

local watched = {} -- guid -> { name, kind, id } of rare targets seen alive

function FC:RecordRareKill(name, kind, id)
    if type(name) ~= "string" or name == "" or not id then return end
    local key = "n" .. id
    local list = slain()
    local now = time()
    bump("rares")
    local rec = list[key]
    if rec then
        rec.n, rec.last = (rec.n or 1) + 1, now
    else
        local n = 0
        for _ in pairs(list) do n = n + 1 end
        if n < MAX_SLAIN then
            list[key] = { name = name:sub(1, 80), kind = kind, n = 1, first = now, last = now }
        end
        FC:AddEntry("slay", string.format(kind == "worldboss" and "|cffff6633Slew the world boss %s in %s!|r"
            or "|cffff9966Slew %s, a rare foe, in %s.|r", name, FC:Zone()))
    end
    FC:Fire("TROPHIES_CHANGED")
end

local function slew(guid)
    local w = watched[guid]
    if not w then return end
    watched[guid] = nil
    FC:RecordRareKill(w.name, w.kind, w.id)
end

local function checkTarget()
    if not UnitExists or not UnitExists("target") then return end
    local guid = UnitGUID and UnitGUID("target")
    local id = npcID(guid)
    if not id then return end
    local class = UnitClassification and UnitClassification("target")
    if secret(class) then return end
    local dead = UnitIsDead and UnitIsDead("target")
    if secret(dead) then return end
    local kind = RARE_KINDS[class or ""]
    if not kind then return end
    if not dead then
        if not watched[guid] then
            local name = UnitName("target")
            if secret(name) then return end
            watched[guid] = { name = name, kind = kind, id = id }
        end
    elseif watched[guid] then
        local denied = UnitIsTapDenied and UnitIsTapDenied("target")
        if denied and not secret(denied) then watched[guid] = nil; return end -- someone else's kill
        slew(guid)
    end
end

FC:RegisterEvent("PLAYER_TARGET_CHANGED", checkTarget)
tryEvent("UNIT_HEALTH", function(unit) if unit == "target" then checkTarget() end end)
tryEvent("UNIT_FLAGS", function(unit) if unit == "target" then checkTarget() end end)

-- Looting a watched rare's corpse also proves the kill (e.g. target already cleared).
tryEvent("LOOT_OPENED", function()
    if not (GetNumLootItems and GetLootSourceInfo) then return end
    for slot = 1, GetNumLootItems() do
        local sources = { GetLootSourceInfo(slot) }
        for i = 1, #sources, 2 do
            if type(sources[i]) == "string" and not secret(sources[i]) then slew(sources[i]) end
        end
    end
end)

-- Loot --------------------------------------------------------------------------------------
-- "You receive loot: %s." -> Lua pattern capturing the link (and the count for _MULTIPLE).
local function toPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local p = fmt:gsub("%%%d?%$?s", "\1"):gsub("%%%d?%$?d", "\2")
    p = p:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    return "^" .. p:gsub("\1", "(.+)"):gsub("\2", "(%%d+)") .. "$"
end
local LOOT_PATTERNS = {}
for _, g in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF" }) do
    local p = toPattern(_G[g])
    if p then LOOT_PATTERNS[#LOOT_PATTERNS + 1] = p end
end
if #LOOT_PATTERNS == 0 then -- English fallback if the globals are missing
    LOOT_PATTERNS = { "^You receive loot: (.+)x(%d+)%.$", "^You receive loot: (.+)%.$",
        "^You receive item: (.+)x(%d+)%.$", "^You receive item: (.+)%.$" }
end

local function linkQuality(link)
    local q = tonumber(link:match("|cnIQ(%d):"))
    if q then return q end
    local hex = link:match("|c%x%x(%x%x%x%x%x%x)")
    return hex and COLOR_QUALITY[hex:lower()]
end

local function itemInfo(link)
    local id = tonumber(link:match("item:(%d+)"))
    if not id then return nil end
    local name = link:match("%[(.-)%]")
    local quality
    if C_Item and C_Item.GetItemQualityByID then quality = C_Item.GetItemQualityByID(link) end
    if not quality then quality = linkQuality(link) end
    return id, name, quality
end

function FC:RecordLoot(link, source)
    if type(link) ~= "string" or secret(link) then return end
    local id, name, quality = itemInfo(link)
    if not id or not quality then return end
    local list = loot()
    local rec = list[id]
    if rec then rec.n = (rec.n or 1) + 1; return end -- only notable items are kept, see below
    local min = tonumber(db().settings.lootQuality) or 3
    if quality < min or quality > 7 then return end
    list[id] = { n = 1, q = quality, first = time() }
    bump("notableLoot")
    if not source and lastBoss and time() - lastBoss.t <= BOSS_LOOT_WINDOW then source = lastBoss.name end
    local color = QUALITY_COLOR[quality] or "ffffff"
    local verb = quality >= 4 and "Claimed" or "Found"
    FC:AddEntry("loot", string.format("|cff%s%s %s %s%s.|r", color, verb,
        quality >= 4 and ("the " .. QUALITY[quality]:lower()) or ((quality == 2 and "an " or "a ") .. QUALITY[quality]:lower()),
        "[" .. (name or ("item #" .. id)) .. "]", source and (" from " .. source) or ""))
    FC:Fire("TROPHIES_CHANGED")
end

tryEvent("CHAT_MSG_LOOT", function(text)
    if type(text) ~= "string" or secret(text) then return end
    for _, p in ipairs(LOOT_PATTERNS) do
        local link = text:match(p)
        if link then FC:RecordLoot(link); return end
    end
end)

-- Personal loot from a boss (raids): names the boss's loot without the chat message.
tryEvent("ENCOUNTER_LOOT_RECEIVED", function(_, _, link, _, player)
    if type(player) ~= "string" or secret(player) then return end
    if Ambiguate and Ambiguate(player, "short") ~= UnitName("player") then return end
    FC:RecordLoot(link)
end)

-- Summaries ---------------------------------------------------------------------------------
-- Slain foes, most recent first: { name, kind, n, first, last, diff }
function FC:SlainList()
    local out = {}
    for _, r in pairs(slain()) do out[#out + 1] = r end
    table.sort(out, function(a, b) return (a.last or 0) > (b.last or 0) end)
    return out
end

FC:Command({ "trophies", "slain" }, "/chron trophies - bosses and rare foes you've slain, and notable loot", function()
    local s = db().stats
    FC:Print(string.format("Bosses defeated: %d   Rare foes slain: %d   Notable items found: %d",
        s.bosses or 0, s.rares or 0, s.notableLoot or 0))
    local list = FC:SlainList()
    for i = 1, math.min(15, #list) do
        local r = list[i]
        local diff = r.kind == "boss" and difficultyName(r.diff)
        FC:Print(string.format("  %s%s%s (x%d, first %s)", r.name, diff and (" - " .. diff) or "",
            r.kind == "boss" and "" or (r.kind == "worldboss" and " [world boss]" or " [rare]"),
            r.n or 1, date("%Y-%m-%d", r.first or 0)))
    end
    if #list > 15 then FC:Print(string.format("  ... and %d more.", #list - 15)) end
end, 19)
