-- Forever Chronicler: companions ("the friends you made along the way")
-- Remembers who you grouped with, for how long, where, how many raids and
-- bosses you shared, and when a companion became your friend.
--
--   * A group session starts when you join a party or raid and ends when you
--     leave it (or log out). When it ends, one chronicle entry sums it up:
--     "Adventured with Buddy and Pal for 1 h 5 min in Westfall." Raids are
--     summed up as "Raided with 24 companions ...". Very short groups (under
--     MIN_GROUP seconds) are recorded but get no entry.
--   * Time together is added up per companion, with milestone entries
--     (1, 5, 10, 24, 100 hours together).
--   * Adding someone to your friend list gives an entry, with your shared
--     history if they were a companion.
--
-- Local only: this module never sends anything. Other players' names are
-- stored on your computer and only posted by the companion app if you turn
-- on the "social" entry type there (off by default).
--
-- Saved data:
--   db.companions[key] = { name, realm, class, race, level, first, last, firstZone,
--                          time, groups, raids, bosses, friend }   key = "Name" or "Name-Realm"
--   db.groups = { { start, stop, kind = "party"|"raid", zones = {...}, members = { key, ... }, size }, ... }
--   db.openGroup = the group you're in right now (survives /reload)
--   db.friends[key] = time first seen on your friend list

local _, FC = ...

local MIN_GROUP = 300          -- groups shorter than this get no chronicle entry
local MIN_MEMBER = 60          -- members who stayed less than this aren't listed
local RESUME_GAP = 600         -- after a /reload or short disconnect, the open group continues
local MAX_GROUPS = 1000
local MAX_COMPANIONS = 5000
local MAX_ZONES = 10
local FRIEND_QUIET = 30        -- seconds after login in which friend-list scans are silent
local HOURS = { 1, 5, 10, 24, 100, 250, 500 }

local function db() return FC.db end
local function companions() db().companions = db().companions or {}; return db().companions end
local function groups() db().groups = db().groups or {}; return db().groups end
local function secret(v) return issecretvalue and issecretvalue(v) or false end

-- Roster -----------------------------------------------------------------------------------
local function unitInfo(unit)
    local name, realm = UnitName(unit)
    if type(name) ~= "string" or name == "" or secret(name) or name == UNKNOWNOBJECT or name == "Unknown" then return nil end
    if secret(realm) then realm = nil end
    if realm == "" then realm = nil end
    local key = realm and (name .. "-" .. realm) or name
    local className, race, level
    if UnitClass then className = UnitClass(unit) end
    if UnitRace then race = UnitRace(unit) end
    if UnitLevel then level = UnitLevel(unit) end
    if secret(className) then className = nil end
    if secret(race) then race = nil end
    if secret(level) then level = nil end
    return key, { name = name, realm = realm, class = className, race = race, level = tonumber(level) }
end

-- Everyone in your group except you: { [key] = info }
function FC:GroupRoster()
    local out = {}
    if not (IsInGroup and IsInGroup()) then return out end
    local raid = IsInRaid and IsInRaid()
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    local me = UnitName("player")
    for i = 1, raid and n or math.max(0, n - 1) do
        local unit = raid and ("raid" .. i) or ("party" .. i)
        if not (UnitIsUnit and UnitIsUnit(unit, "player")) then
            local key, info = unitInfo(unit)
            if key and key ~= me then out[key] = info end
        end
    end
    return out, raid
end

-- Companion records ----------------------------------------------------------------------------
local function remember(key, info)
    local list = companions()
    local c = list[key]
    if not c then
        local n = 0
        for _ in pairs(list) do n = n + 1 end
        if n >= MAX_COMPANIONS then return nil end
        c = { first = time(), firstZone = FC:Zone(), time = 0, groups = 0, raids = 0, bosses = 0 }
        list[key] = c
    end
    c.name, c.realm = info.name, info.realm
    c.class = info.class or c.class
    c.race = info.race or c.race
    c.level = info.level or c.level
    c.last = time()
    return c
end

local function addTime(key, seconds)
    local c = companions()[key]
    if not c or seconds <= 0 then return end
    local before = c.time or 0
    c.time = before + seconds
    for _, h in ipairs(HOURS) do
        if before < h * 3600 and c.time >= h * 3600 then
            FC:AddEntry("social", string.format("|cff66ddaaYou have now adventured %d hour%s with %s.|r",
                h, h == 1 and "" or "s", c.name or key))
        end
    end
end

-- Group sessions -------------------------------------------------------------------------------
local function open() return db().openGroup end

local function listNames(keys, max)
    local names = {}
    for i = 1, math.min(#keys, max) do
        local c = companions()[keys[i]]
        names[i] = c and c.name or keys[i]
    end
    local text
    if #names == 1 then text = names[1]
    else text = table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names] end
    if #keys > max then text = text .. string.format(" (and %d more)", #keys - max) end
    return text
end

local function zonesText(zones)
    if not zones or #zones == 0 then return "" end
    if #zones == 1 then return " in " .. zones[1] end
    return " in " .. table.concat(zones, ", ", 1, math.min(#zones, 3) - 1) .. " and " .. zones[math.min(#zones, 3)]
end

-- A member left (or the group ended): bank their time.
local function memberLeft(g, key, now)
    local m = g.members[key]
    if not m or m.left then return end
    m.left = now
    m.time = (m.time or 0) + math.max(0, now - (m.joined or now))
    addTime(key, math.max(0, now - (m.joined or now)))
end

local function closeGroup(now)
    local g = open()
    if not g then return end
    db().openGroup = nil
    now = now or time()
    for key in pairs(g.members) do memberLeft(g, key, now) end
    local duration = now - g.start
    -- members who stayed long enough, longest first
    local keys = {}
    for key, m in pairs(g.members) do if (m.time or 0) >= MIN_MEMBER then keys[#keys + 1] = key end end
    table.sort(keys, function(a, b)
        local ta, tb = g.members[a].time or 0, g.members[b].time or 0
        if ta ~= tb then return ta > tb end
        return a < b
    end)
    local list = groups()
    list[#list + 1] = { start = g.start, stop = now, kind = g.kind, zones = g.zones, members = keys, size = g.size,
        bosses = g.bosses }
    while #list > MAX_GROUPS do table.remove(list, 1) end
    if duration >= MIN_GROUP and #keys > 0 then
        local newOnes = {}
        for _, key in ipairs(keys) do
            if g.members[key].new then newOnes[#newOnes + 1] = key end
        end
        local text
        if g.kind == "raid" then
            text = string.format("Raided with %d companions for %s%s", #keys, FC.PlayedText(duration), zonesText(g.zones))
        else
            text = string.format("Adventured with %s for %s%s", listNames(keys, 5), FC.PlayedText(duration), zonesText(g.zones))
        end
        if (g.bosses or 0) > 0 then
            text = text .. string.format(", and defeated %d boss%s together", g.bosses, g.bosses == 1 and "" or "es")
        end
        text = text .. "."
        if #newOnes > 0 and g.kind ~= "raid" then
            text = text .. " First time with " .. listNames(newOnes, 5) .. "."
        end
        FC:AddEntry("social", "|cff66ddaa" .. text .. "|r")
    end
    FC:Fire("COMPANIONS_CHANGED")
end

-- atLogin: a group left over from a session that ended while we were offline
-- (longer than RESUME_GAP ago) ended when it was last seen.
function FC:ScanGroup(atLogin)
    local now = time()
    local g = open()
    if atLogin and g and now - (g.seen or now) > RESUME_GAP then closeGroup(g.seen); g = nil end
    if not (IsInGroup and IsInGroup()) then
        -- right at load the roster may not be known yet; PLAYER_ENTERING_WORLD checks again
        if g and not atLogin then closeGroup(now) end
        return
    end
    local roster, raid = self:GroupRoster()
    if not g then
        g = { start = now, seen = now, kind = raid and "raid" or "party", zones = {}, members = {}, size = 1 }
        db().openGroup = g
        local z = FC:Zone()
        if z and z ~= "" and z ~= "Unknown" then g.zones[1] = z end
    end
    g.seen = now
    if raid then g.kind = "raid" end
    local size = 1
    for key, info in pairs(roster) do
        size = size + 1
        local m = g.members[key]
        if not m or m.left then
            local isNew = companions()[key] == nil
            local c = remember(key, info)
            if c then
                if not m then
                    c.groups = (c.groups or 0) + 1
                    m = { new = isNew or nil }
                    g.members[key] = m
                end
                m.joined, m.left = now, nil
                if g.kind == "raid" and not m.raid then m.raid = true; c.raids = (c.raids or 0) + 1 end
            end
        else
            remember(key, info)
            if g.kind == "raid" and not m.raid then
                m.raid = true
                local c = companions()[key]
                if c then c.raids = (c.raids or 0) + 1 end
            end
        end
    end
    if size > (g.size or 1) then g.size = size end
    for key, m in pairs(g.members) do
        if not m.left and not roster[key] then memberLeft(g, key, now) end
    end
    FC:Fire("COMPANIONS_CHANGED")
end

FC:On("READY", function()
    FC:ScanGroup(true)
    C_Timer.NewTicker(60, function() FC:SafeCall(function() local g = open(); if g then g.seen = time() end end) end)
end)
FC:RegisterEvent("GROUP_ROSTER_UPDATE", function() FC:ScanGroup() end)
FC:RegisterEvent("PLAYER_ENTERING_WORLD", function() FC:ScanGroup() end)
FC:RegisterEvent("PLAYER_LOGOUT", function()
    -- keep the group open across /reload; if you really logged out, the next login closes it
    local g = open()
    if g then g.seen = time() end
end)
FC:On("ZONE", function(zone)
    local g = open()
    if not g or type(zone) ~= "string" or zone == "" or zone == "Unknown" then return end
    for _, z in ipairs(g.zones) do if z == zone then return end end
    if #g.zones < MAX_ZONES then g.zones[#g.zones + 1] = zone end
end)
FC:On("BOSS_DEFEATED", function()
    local g = open()
    if not g then return end
    g.bosses = (g.bosses or 0) + 1
    for key, m in pairs(g.members) do
        if not m.left then
            local c = companions()[key]
            if c then c.bosses = (c.bosses or 0) + 1 end
        end
    end
end)

-- Friends ------------------------------------------------------------------------------------
local loginAt
FC:On("READY", function()
    loginAt = GetTime()
    if C_FriendList and C_FriendList.ShowFriends then C_FriendList.ShowFriends() end
end)

function FC:ScanFriends()
    local F = C_FriendList
    if not (F and F.GetNumFriends and F.GetFriendInfoByIndex) then return end
    local n = F.GetNumFriends() or 0
    if n == 0 then return end -- not loaded yet (or no friends): nothing to learn
    local d = db()
    d.friends = d.friends or {}
    local quiet = not d.friendsBaseline or (loginAt and GetTime() - loginAt < FRIEND_QUIET)
    for i = 1, n do
        local info = F.GetFriendInfoByIndex(i)
        local name = info and info.name
        if type(name) == "string" and name ~= "" and not secret(name) and not d.friends[name] then
            d.friends[name] = time()
            local short = name:gsub("%-.*$", "")
            local c = companions()[name] or companions()[short]
            if c and not c.friend then c.friend = time() end
            if not quiet then
                local text = string.format("Became friends with %s.", c and c.name or short)
                if c and (c.time or 0) >= 60 then
                    text = text .. string.format(" You met in %s on %s and have adventured %s together.",
                        c.firstZone or "?", date("%Y-%m-%d", c.first or time()), FC.PlayedText(c.time))
                end
                FC:AddEntry("social", "|cff66ddaa" .. text .. "|r")
            end
        end
    end
    d.friendsBaseline = true
    FC:Fire("COMPANIONS_CHANGED")
end
FC:RegisterEvent("FRIENDLIST_UPDATE", function() FC:ScanFriends() end)

-- Summaries ----------------------------------------------------------------------------------
-- Time with a companion, including the group you're in now.
function FC:CompanionTime(key)
    local c = companions()[key]
    local t = c and c.time or 0
    local g = open()
    local m = g and g.members[key]
    if m and not m.left then t = t + math.max(0, time() - (m.joined or time())) end
    return t
end

-- Companions, most time together first: { key, name, time, groups, raids, bosses, friend, first, ... }
function FC:CompanionList()
    local out = {}
    for key, c in pairs(companions()) do
        local row = { key = key, time = self:CompanionTime(key) }
        for k, v in pairs(c) do if row[k] == nil then row[k] = v end end
        out[#out + 1] = row
    end
    table.sort(out, function(a, b)
        if a.time ~= b.time then return a.time > b.time end
        return a.key < b.key
    end)
    return out
end

-- Groups that started on a day (FC.DayKey): for the letters.
function FC:GroupsOnDay(key)
    local out = {}
    for _, g in ipairs(groups()) do
        if FC.DayKey(g.start) == key then out[#out + 1] = g end
    end
    local g = open()
    if g and FC.DayKey(g.start) == key then
        local members = {}
        for k, m in pairs(g.members) do
            if m.left and (m.time or 0) >= MIN_MEMBER or not m.left then members[#members + 1] = k end
        end
        table.sort(members)
        out[#out + 1] = { start = g.start, stop = time(), kind = g.kind, zones = g.zones, members = members,
            size = g.size, bosses = g.bosses, ongoing = true }
    end
    return out
end

local function describe(c)
    local who = {}
    if c.level then who[#who + 1] = "level " .. c.level end
    if c.race then who[#who + 1] = c.race end
    if c.class then who[#who + 1] = c.class end
    return #who > 0 and table.concat(who, " ") or nil
end
FC.DescribeCompanion = describe

FC:Command({ "companions", "party" }, "/chron companions [name] - who you've adventured with, for how long, and the friends you made", function(rest)
    local list = FC:CompanionList()
    if #list == 0 then FC:Print("No companions yet. Group up with someone and they'll be remembered here.") return end
    if rest ~= "" then
        local want = rest:lower()
        for _, c in ipairs(list) do
            if c.key:lower() == want or (c.name or ""):lower() == want then
                FC:Print(string.format("%s%s", c.name or c.key, describe(c) and (", " .. describe(c)) or ""))
                FC:Print(string.format("  First met %s in %s. Last seen %s.", date("%Y-%m-%d", c.first or 0),
                    c.firstZone or "?", date("%Y-%m-%d", c.last or 0)))
                FC:Print(string.format("  %s together over %d group%s (%d raid%s), %d boss%s defeated together.",
                    FC.PlayedText(c.time), c.groups or 0, (c.groups or 0) == 1 and "" or "s",
                    c.raids or 0, (c.raids or 0) == 1 and "" or "s", c.bosses or 0, (c.bosses or 0) == 1 and "" or "es"))
                if c.friend then FC:Print("  Friends since " .. date("%Y-%m-%d", c.friend) .. ".") end
                return
            end
        end
        FC:Print("No companion called " .. rest .. ".")
        return
    end
    local friends = 0
    for _, c in ipairs(list) do if c.friend then friends = friends + 1 end end
    FC:Print(string.format("%d companions, %d of them became friends, %d groups in all.", #list, friends, #groups()))
    for i = 1, math.min(15, #list) do
        local c = list[i]
        FC:Print(string.format("  %s%s - %s, %d group%s%s", c.name or c.key, c.friend and " (friend)" or "",
            FC.PlayedText(c.time), c.groups or 0, (c.groups or 0) == 1 and "" or "s",
            (c.raids or 0) > 0 and string.format(", %d raid%s", c.raids, c.raids == 1 and "" or "s") or ""))
    end
    if #list > 15 then FC:Print(string.format("  ... and %d more. /chron companions <name> for details.", #list - 15)) end
end, 20)
