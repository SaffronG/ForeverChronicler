-- Forever Chronicaller: goals you complete *together* with friends
--   /chron together <name> <goal>   e.g. /chron together Buddy level 30
--   /chron invite <n> <name>        invite another friend to shared goal n
--
-- Each player's addon checks its own part (level / zone / quest / tick it off
-- yourself) and tells the others. The goal is achieved when every member who
-- joined has done their part.
--
-- Data: kind = "shared", target = {
--   id = "<unique>", inner = { kind = "level"|"zone"|"quest"|"free", target = ... },
--   members = { [shortName] = { full = "Name-Realm", done = <time>|nil, pending = true|nil } } }
--
-- Syncing: progress is sent straight away to members who are online (in your
-- group or online on your friend list) and remembered for the others; it's sent
-- when they come online, join your group, or message you. State only ever moves
-- forward (once someone's part is done it stays done), so the order in which
-- updates arrive doesn't matter. Progress is trust-based: each client reports
-- its own part.

local _, FC = ...

local INNER_KINDS = { level = true, zone = true, quest = true, free = true, location = true }
local MAX_MEMBERS = 10
local SYNC_EVERY = 60

local function me() return UnitName("player") end
local function myFullName()
    local name, realm = UnitFullName and UnitFullName("player")
    name = name or UnitName("player")
    realm = realm or (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
    realm = realm:gsub("%s", "")
    return realm ~= "" and (name .. "-" .. realm) or name
end

local function shortName(name) return FC.ShortName(name) end

-- Helpers ------------------------------------------------------------------------------
local function findShared(id)
    for i, g in ipairs(FC.db.goals) do
        if g.kind == "shared" and type(g.target) == "table" and g.target.id == id then return g, i end
    end
end

local function joinedMembers(g)
    local list = {}
    for name, m in pairs(g.target.members) do
        if not m.pending then list[#list + 1] = name end
    end
    table.sort(list)
    return list
end

function FC:SharedProgressText(g)
    local t = g.target
    if type(t) ~= "table" or type(t.members) ~= "table" then return "" end
    local parts, done, total = {}, 0, 0
    local names = {}
    for name in pairs(t.members) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local m = t.members[name]
        if m.pending then
            parts[#parts + 1] = name .. " (invited)"
        else
            total = total + 1
            if m.done then done = done + 1 end
            parts[#parts + 1] = name .. (m.done and " |cff00ff00done|r" or " ...")
        end
    end
    return string.format("(%d/%d: %s)", done, total, table.concat(parts, ", "))
end

-- Validate a shared target (from an import or a message). Returns a clean copy or nil.
function FC.CleanSharedTarget(t)
    if type(t) ~= "table" or type(t.id) ~= "string" or #t.id > 40 then return nil end
    if type(t.inner) ~= "table" or not INNER_KINDS[t.inner.kind] then return nil end
    local inner = { kind = t.inner.kind }
    if inner.kind == "level" then
        inner.target = tonumber(t.inner.target)
        if not inner.target then return nil end
    elseif inner.kind == "location" then
        local l = t.inner.target
        if type(l) == "string" then -- "mapID,x,y" from a message
            local m, x, y = l:match("^(%d+),([%d%.]+),([%d%.]+)$")
            l = m and { mapID = tonumber(m), x = tonumber(x), y = tonumber(y) } or nil
        end
        if type(l) ~= "table" then return nil end
        local m, x, y = tonumber(l.mapID), tonumber(l.x), tonumber(l.y)
        if not (m and x and y) or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
        inner.target = { mapID = m, x = x, y = y, armed = l.armed == true }
    elseif inner.kind ~= "free" then
        if type(t.inner.target) ~= "string" or #t.inner.target > 200 then return nil end
        inner.target = t.inner.target
    end
    local members, count = {}, 0
    if type(t.members) ~= "table" then return nil end
    for name, m in pairs(t.members) do
        if type(name) == "string" and #name <= 64 and type(m) == "table" and count < MAX_MEMBERS then
            members[name] = { full = type(m.full) == "string" and m.full:sub(1, 80) or name,
                done = tonumber(m.done), pending = m.pending == true or nil }
            count = count + 1
        end
    end
    return { id = t.id, inner = inner, members = members }
end

-- Members string for messages: "name:full:done:pending;..."
local function encodeMembers(members)
    local out = {}
    for name, m in pairs(members) do
        out[#out + 1] = table.concat({ name, m.full or name, m.done or 0, m.pending and 1 or 0 }, ":")
    end
    table.sort(out)
    return table.concat(out, ";")
end

local function decodeMembers(s)
    if type(s) ~= "string" then return nil end
    local members, count = {}, 0
    for part in s:gmatch("[^;]+") do
        local name, full, done, pending = part:match("^([^:]+):([^:]+):(%d+):([01])$")
        if not name or #name > 64 or #full > 80 then return nil end
        count = count + 1
        if count > MAX_MEMBERS then return nil end
        done = tonumber(done)
        members[name] = { full = full, done = done ~= 0 and done or nil, pending = pending == "1" or nil }
    end
    return members
end

-- Online check: in our group, or online on the friend list. Unknown = not online.
function FC:IsMemberOnline(name)
    if UnitInParty and (UnitInParty(name) or (UnitInRaid and UnitInRaid(name))) then return true end
    if C_FriendList and C_FriendList.GetFriendInfo then
        local info = C_FriendList.GetFriendInfo(name)
        if info and info.connected then return true end
    end
    return self.recentlySeen and self.recentlySeen[name] and (time() - self.recentlySeen[name] < 300) or false
end

-- Sending --------------------------------------------------------------------------------
local function stateFields(g)
    local t = g.target
    local itarget = t.inner.target or ""
    if t.inner.kind == "location" then
        itarget = string.format("%d,%.4f,%.4f", itarget.mapID, itarget.x, itarget.y)
    end
    return { id = t.id, text = g.text, ikind = t.inner.kind, itarget = itarget,
        members = encodeMembers(t.members) }
end

-- Send this goal's state to every other member; remember who we couldn't reach.
local function syncGoal(g, onlyTo)
    local t = g.target
    t.unsynced = t.unsynced or {}
    for name, m in pairs(t.members) do
        if name ~= me() and (not onlyTo or onlyTo == name) then
            if FC:IsMemberOnline(name) then
                FC:SendComm("SGSYNC", stateFields(g), "WHISPER", m.full or name)
                t.unsynced[name] = nil
            else
                t.unsynced[name] = true
            end
        end
    end
end

local function syncPending()
    for _, g in ipairs(FC.db.goals) do
        if g.kind == "shared" and type(g.target) == "table" and g.target.unsynced then
            for name in pairs(g.target.unsynced) do
                if FC:IsMemberOnline(name) then syncGoal(g, name) end
            end
        end
    end
end
FC.SyncSharedGoals = syncPending

local function checkComplete(g, index)
    if g.done then return end
    local joined = joinedMembers(g)
    if #joined < 2 then return end -- waiting for someone to join
    for _, name in ipairs(joined) do
        if not g.target.members[name].done then return end
    end
    local others = {}
    for _, name in ipairs(joined) do if name ~= me() then others[#others + 1] = name end end
    FC:CompleteGoal(index, true)
    FC:Print(string.format("|cffff80ffAchieved together with %s!|r", table.concat(others, ", ")))
end

-- Merge another member's view of the goal into ours. Only moves forward.
local function merge(g, index, incoming)
    local members = g.target.members
    local changed = false
    for name, m in pairs(incoming) do
        local mine = members[name]
        if not mine then
            local count = 0
            for _ in pairs(members) do count = count + 1 end
            if count < MAX_MEMBERS then members[name] = m; changed = true end
        else
            if m.done and (not mine.done or m.done < mine.done) and name ~= me() then mine.done = m.done; changed = true end
            if mine.pending and not m.pending then mine.pending = nil; changed = true end
            if m.full and mine.full == name and m.full ~= name then mine.full = m.full end
        end
    end
    if changed then
        FC:Fire("GOALS_CHANGED")
        checkComplete(g, index)
    end
    return changed
end

-- Does state `a` contain anything `b` doesn't know yet? (Used to decide whether
-- to answer a sync; this can't loop, because after merging, b knows everything in a.)
local function knowsMore(a, b)
    for name, m in pairs(a) do
        local other = b[name]
        if not other then return true end
        if m.done and (not other.done or m.done < other.done) then return true end
        if other.pending and not m.pending then return true end
    end
    return false
end

-- My part --------------------------------------------------------------------------------
function FC:MarkSharedPartDone(g)
    local m = g.target.members[me()]
    if not m or m.done then return end
    m.done = time()
    self:Fire("SHARED_PART_DONE", g)
    self:Print(string.format("Your part of \"%s\" is done! %s", g.text, self:SharedProgressText(g)))
    syncGoal(g)
    self:Fire("GOALS_CHANGED")
    for i, goal in ipairs(self.db.goals) do if goal == g then checkComplete(g, i) end end
end

local function innerSatisfied(inner, questTitle, questID, level)
    if inner.kind == "level" then return (level or UnitLevel("player")) >= inner.target end
    if inner.kind == "zone" then return FC:Zone():lower() == tostring(inner.target):lower() end
    if inner.kind == "quest" then
        if questID and tonumber(inner.target) == questID then return true end
        return questTitle and questTitle:lower() == tostring(inner.target):lower()
    end
    return false -- free: ticked off by hand; location: checked by MapGoals.lua
end

local function checkMine(questTitle, questID, level)
    for _, g in ipairs(FC.db.goals) do
        if g.kind == "shared" and not g.done and type(g.target) == "table" then
            local m = g.target.members[me()]
            if m and not m.done and innerSatisfied(g.target.inner, questTitle, questID, level) then
                FC:MarkSharedPartDone(g)
            end
        end
    end
end

FC:On("READY", function() checkMine() end)
FC:On("LEVEL", function(level) checkMine(nil, nil, level) end)
FC:On("ZONE", function() checkMine() end)
FC:On("QUEST", function(title, id) checkMine(title, id) end)

-- Creating and inviting --------------------------------------------------------------------
local function newId()
    return string.format("%s%x%x", me():sub(1, 6), time(), math.random(0, 65535))
end

function FC:CreateSharedGoal(friend, goalText)
    local kind, target, text = FC.ParseGoalText(goalText)
    if not kind then self:Print(target) return end
    if not INNER_KINDS[kind] then
        self:Print("That kind of goal can't be done together.")
        return
    end
    local t = { id = newId(), inner = { kind = kind, target = target },
        members = { [me()] = { full = myFullName() } } }
    local g = self:CreateGoal("shared", t, "Together: " .. text)
    self:InviteToShared(g, friend)
    checkMine()
    return g
end

function FC:InviteToShared(g, friend)
    if not friend or friend == "" then return end
    local short = shortName(friend)
    if short == me() then self:Print("You can't invite yourself.") return end
    local members = g.target.members
    if not members[short] then
        local count = 0
        for _ in pairs(members) do count = count + 1 end
        if count >= MAX_MEMBERS then self:Print("That goal already has the maximum number of members.") return end
        members[short] = { full = friend, pending = true }
    end
    self:SendComm("SGINV", stateFields(g), "WHISPER", friend)
    self:Print(string.format("Invited %s to \"%s\". They need Forever Chronicaller and must be online to get the invite.", short, g.text))
    self:Fire("GOALS_CHANGED")
end

-- Receiving ----------------------------------------------------------------------------------
local function fieldsToShared(fields)
    local members = decodeMembers(fields.members)
    if not members or type(fields.id) ~= "string" or type(fields.text) ~= "string" or #fields.text > 220 then return nil end
    local inner = { kind = fields.ikind, target = fields.itarget ~= "" and fields.itarget or nil }
    local clean = FC.CleanSharedTarget({ id = fields.id, inner = inner, members = members })
    return clean
end

local invites = {}
StaticPopupDialogs["FOREVERCHRONICALLER_SHARED_INVITE"] = {
    text = "%s wants to complete a goal together with you:\n\n|cffffd100%s|r\n\nJoin?",
    button1 = "Join",
    button2 = "No thanks",
    OnAccept = function(_, inv)
        FC:SafeCall(function()
            if findShared(inv.target.id) then return end
            inv.target.members[me()] = { full = myFullName() }
            local g = FC:CreateGoal("shared", inv.target, inv.text)
            g.sharedBy = inv.from
            for name, m in pairs(g.target.members) do
                if name ~= me() and not m.pending then
                    FC:SendComm("SGJOIN", stateFields(g), "WHISPER", m.full or name)
                end
            end
            checkMine()
        end)
    end,
    timeout = 120, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

FC:OnComm("SGINV", function(fields, sender)
    if FC.db.settings.acceptShares == false then return end
    local target = fieldsToShared(fields)
    if not target or findShared(target.id) then return end
    local from = shortName(sender)
    if not target.members[from] then return end -- the inviter must be a member
    target.members[from].full = sender
    target.members[me()] = nil
    local inv = { target = target, text = fields.text, from = from }
    invites[#invites + 1] = inv
    StaticPopup_Show("FOREVERCHRONICALLER_SHARED_INVITE", from, fields.text, inv)
end)

local function onState(fields, sender)
    local from = shortName(sender)
    FC.recentlySeen = FC.recentlySeen or {}
    FC.recentlySeen[from] = time()
    local g, index = findShared(fields.id)
    if not g then return end
    local m = g.target.members[from]
    if not m then return end -- only members may update a goal
    local incoming = decodeMembers(fields.members)
    if not incoming then return end
    if incoming[from] then incoming[from].full = sender end
    m.full = sender
    m.pending = nil
    merge(g, index, incoming)
    -- if they're behind us, answer with our state
    if knowsMore(g.target.members, incoming) then syncGoal(g, from) end
    FC:Fire("GOALS_CHANGED")
end
FC:OnComm("SGJOIN", function(fields, sender)
    onState(fields, sender)
    local g = findShared(fields.id)
    if g then
        FC:Print(string.format("%s joined \"%s\".", shortName(sender), g.text))
        syncGoal(g) -- let everyone know about the new member
    end
end)
FC:OnComm("SGSYNC", onState)

FC:OnComm("SGLEAVE", function(fields, sender)
    local g, index = findShared(fields.id)
    local from = shortName(sender)
    if not g or not g.target.members[from] then return end
    g.target.members[from] = nil
    FC:Print(string.format("%s left the shared goal \"%s\".", from, g.text))
    FC:Fire("GOALS_CHANGED")
    checkComplete(g, index)
end)

-- Deleting a shared goal tells the others you left.
FC:On("GOAL_REMOVED", function(g)
    if g.kind ~= "shared" or type(g.target) ~= "table" or g.done then return end
    for name, m in pairs(g.target.members) do
        if name ~= me() and not m.pending and FC:IsMemberOnline(name) then
            FC:SendComm("SGLEAVE", { id = g.target.id }, "WHISPER", m.full or name)
        end
    end
end)

-- Catch-up triggers
FC:RegisterEvent("GROUP_ROSTER_UPDATE", syncPending)
FC:RegisterEvent("FRIENDLIST_UPDATE", syncPending)
FC:On("READY", function()
    C_Timer.NewTicker(SYNC_EVERY, function() FC:SafeCall(syncPending) end)
end)

-- Commands --------------------------------------------------------------------------------------
FC:Command("together", "/chron together <name> <goal> - a goal you complete together (e.g. together Buddy level 30)", function(rest)
    local friend, goal = rest:match("^(%S+)%s+(.+)$")
    if not friend then return false end
    FC:CreateSharedGoal(friend, goal)
end, 31)

FC:Command("invite", "/chron invite <n> <name> - invite another friend to shared goal n", function(rest)
    local n, friend = rest:match("^(%d+)%s+(%S+)$")
    if not n then return false end
    local g = FC.db.goals[tonumber(n)]
    if not g or g.kind ~= "shared" then FC:Print("Goal " .. n .. " isn't a shared goal.") return end
    FC:InviteToShared(g, friend)
end, 32)
