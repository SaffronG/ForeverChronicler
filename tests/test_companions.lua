-- Companions: who you grouped with, for how long, and the friends you made (src/chronicle/Companions.lua)

local NOON = os.time({ year = 2026, month = 11, day = 5, hour = 12 })

local function social(opts)
    local clock = NOON
    opts = opts or {}
    opts.time = function() return clock end
    local env = setup(opts)
    env.advance = function(seconds) clock = clock + seconds end
    return env
end

local function entriesOf(FC, kind)
    local out = {}
    for _, e in ipairs(FC.db.entries) do if e.kind == kind then out[#out + 1] = e.text end end
    return out
end

local function has(list, s)
    for _, t in ipairs(list) do if t:find(s, 1, true) then return true end end
    return false
end

local BUDDY = { name = "Buddy", class = "Hunter", race = "Dwarf", level = 30 }
local PAL = { name = "Pal", realm = "Elsewhere", class = "Mage", race = "Gnome", level = 31 }

test("a party session: who, how long, where, first time together", function()
    local env = social()
    local FC = env.FC
    env.roster = { BUDDY, PAL }
    env.fire("GROUP_ROSTER_UPDATE")
    ok(FC.db.openGroup, "group open")
    local c = FC.db.companions.Buddy
    ok(c, "Buddy remembered")
    eq(c.class, "Hunter", "class"); eq(c.level, 30, "level"); eq(c.firstZone, "Elwynn Forest", "where we met")
    ok(FC.db.companions["Pal-Elsewhere"], "other realm keyed with realm")
    env.advance(1800)
    env.player.zone = "Westfall"; env.fire("ZONE_CHANGED_NEW_AREA")
    env.advance(1800)
    eq(FC:CompanionTime("Buddy"), 3600, "live time while still grouped")
    env.roster = {}
    env.fire("GROUP_ROSTER_UPDATE")
    eq(FC.db.openGroup, nil, "group closed")
    local list = entriesOf(FC, "social")
    ok(has(list, "Adventured with Buddy and Pal for 1 h 0 min in Elwynn Forest and Westfall."), "summary entry")
    ok(has(list, "First time with Buddy and Pal."), "new companions noted")
    ok(has(list, "You have now adventured 1 hour with Buddy."), "hour milestone")
    eq(FC.db.companions.Buddy.time, 3600, "time banked")
    eq(FC.db.companions.Buddy.groups, 1, "one group")
    eq(#FC.db.groups, 1, "group recorded")
    eq(FC.db.groups[1].members[1], "Buddy", "members recorded")

    -- second time: no "first time" note
    env.roster = { BUDDY }
    env.fire("GROUP_ROSTER_UPDATE")
    env.advance(600)
    env.roster = {}
    env.fire("GROUP_ROSTER_UPDATE")
    ok(has(entriesOf(FC, "social"), "Adventured with Buddy for 10 min in Westfall."), "second session")
    eq(#entriesOf(FC, "social"), 4, "no first-time note, no milestone")
    eq(FC.db.companions.Buddy.groups, 2, "two groups")
end)

test("short groups and members who left early", function()
    local env = social()
    local FC = env.FC
    env.roster = { BUDDY }
    env.fire("GROUP_ROSTER_UPDATE")
    env.advance(60)
    env.roster = {}
    env.fire("GROUP_ROSTER_UPDATE")
    eq(#entriesOf(FC, "social"), 0, "a one-minute group gets no entry")
    eq(#FC.db.groups, 1, "but it's recorded")

    env.roster = { BUDDY, PAL }
    env.fire("GROUP_ROSTER_UPDATE")
    env.advance(30)
    env.roster = { BUDDY } -- Pal leaves after 30 s
    env.fire("GROUP_ROSTER_UPDATE")
    env.advance(600)
    env.roster = {}
    env.fire("GROUP_ROSTER_UPDATE")
    local list = entriesOf(FC, "social")
    ok(has(list, "Adventured with Buddy for 10 min"), "Buddy listed")
    ok(not has(list, "Pal"), "Pal stayed too briefly to be listed")
    eq(FC.db.companions["Pal-Elsewhere"].time, 30, "but Pal's time counts")
end)

test("raids are summed up, and bosses are shared with the group", function()
    local env = social()
    local FC = env.FC
    local roster = {}
    for i = 1, 9 do roster[i] = { name = "Raider" .. i, class = "Priest", level = 60 } end
    env.roster, env.raid = roster, true
    env.player.zone = "Molten Core"
    env.fire("GROUP_ROSTER_UPDATE")
    env.advance(3600)
    env.fire("ENCOUNTER_END", 663, "Lucifron", 9, 10, 1)
    env.advance(3600)
    env.roster = {}
    env.fire("GROUP_ROSTER_UPDATE")
    ok(has(entriesOf(FC, "social"), "Raided with 9 companions for 2 h 0 min in Molten Core, and defeated 1 boss together."), "raid summary")
    local c = FC.db.companions.Raider1
    eq(c.raids, 1, "raid counted"); eq(c.bosses, 1, "boss credited")
    eq(FC.db.groups[1].size, 10, "group size includes you")
end)

test("a /reload keeps the group going; a long logout ends it when last seen", function()
    local env = social()
    local FC = env.FC
    env.roster = { BUDDY }
    env.fire("GROUP_ROSTER_UPDATE")
    env.advance(600)
    env.fire("PLAYER_LOGOUT")
    -- /reload: same saved data, a moment later, still in the group
    local saved = FC.db
    local clock = NOON + 620
    local env2 = setup({ time = function() return clock end, savedDB = saved, roster = { BUDDY } })
    eq(env2.FC.db.openGroup.start, NOON, "same group continues")
    -- now log out for a day; next login (not grouped) closes it at the last-seen time
    env2.fire("PLAYER_LOGOUT")
    clock = clock + 86400
    local env3 = setup({ time = function() return clock end, savedDB = env2.FC.db })
    eq(env3.FC.db.openGroup, nil, "closed")
    local g = env3.FC.db.groups[#env3.FC.db.groups]
    eq(g.stop, NOON + 620, "ended when last seen, not a day later")
    eq(env3.FC.db.companions.Buddy.time, 620, "time not inflated")
end)

test("new friends get an entry with your shared history; the first scan is silent", function()
    local env = social()
    local FC = env.FC
    env.friendList = { "Oldfriend" }
    env.fire("FRIENDLIST_UPDATE")
    eq(#entriesOf(FC, "social"), 0, "existing friends recorded silently")
    ok(FC.db.friends.Oldfriend, "recorded")
    -- group with Buddy for an hour, then add Buddy as a friend (after the login quiet window)
    env.roster = { BUDDY }
    env.fire("GROUP_ROSTER_UPDATE")
    env.advance(3600)
    env.now = 100
    env.friendList = { "Oldfriend", "Buddy" }
    env.fire("FRIENDLIST_UPDATE")
    ok(has(entriesOf(FC, "social"), "Became friends with Buddy."), "friend entry")
    ok(FC.db.companions.Buddy.friend, "marked as friend")
    env.friendList = { "Oldfriend", "Buddy", "Stranger" }
    env.fire("FRIENDLIST_UPDATE")
    ok(has(entriesOf(FC, "social"), "Became friends with Stranger."), "non-companion friend")
    -- friend later after time banked: history in the entry
    env.roster = {}
    env.fire("GROUP_ROSTER_UPDATE")
    env.roster = { PAL }
    env.fire("GROUP_ROSTER_UPDATE"); env.advance(900); env.roster = {}; env.fire("GROUP_ROSTER_UPDATE")
    env.friendList = { "Oldfriend", "Buddy", "Stranger", "Pal-Elsewhere" }
    env.fire("FRIENDLIST_UPDATE")
    ok(has(entriesOf(FC, "social"), "Became friends with Pal. You met in Elwynn Forest on 2026-11-05 and have adventured 15 min together."), "history")
    env.slash("companions")
    ok(env.chatContains("2 companions, 2 of them became friends, 2 groups in all"), "companions list")
    env.slash("companions buddy")
    ok(env.chatContains("1 h 0 min together over 1 group (0 raids)"), "companion details")
end)

test("companions appear in the day's letter and stats, and survive export/import", function()
    local env = social()
    local FC = env.FC
    env.roster = { BUDDY }
    env.fire("GROUP_ROSTER_UPDATE")
    env.advance(1200)
    env.roster = {}
    env.fire("GROUP_ROSTER_UPDATE")
    env.now = 100
    env.friendList = { "Buddy" }
    FC.db.friendsBaseline = true
    env.fire("FRIENDLIST_UPDATE")
    local letter, stats = FC:ComposeLetter(FC.DayKey())
    eq(stats.companions[1], "Buddy", "companion that day")
    eq(stats.groupTime, 1200, "time in a group")
    eq(stats.newFriends[1], "Buddy", "new friend")
    ok(letter:find("I was not alone: I travelled with Buddy for 20 min.", 1, true), "letter: companions")
    ok(letter:find("I made a new friend today: Buddy.", 1, true), "letter: friend")
    local lines = table.concat(FC:DayStatsLines(stats), "\n")
    ok(lines:find("Companions:|r Buddy", 1, true), "stats line")

    local str = FC:ExportString()
    local other = setup({ name = "Alt" })
    ok(other.FC:ImportString(str, "merge"), "import")
    eq(other.FC.db.companions.Buddy.time, 1200, "companion imported")
    eq(#other.FC.db.groups, 1, "group imported")
    ok(other.FC.db.friends.Buddy, "friends imported")
    other.FC:ImportString(str, "merge")
    eq(#other.FC.db.groups, 1, "groups not duplicated")
end)

test("import drops malformed companions and groups", function()
    local env = social()
    local FC = env.FC
    FC.db.companions = { Good = { name = "Good", time = 5 }, ["Bad|cff"] = { name = "Bad" }, NoName = { time = 1 },
        [5] = { name = "Num" } }
    FC.db.groups = { { start = 10, stop = 20, kind = "party", members = { "Good", 7, "a|b" } },
        { start = 30, stop = 20, kind = "party", members = {} }, { start = 1, stop = 2, kind = "guild" } }
    FC.db.friends = { Good = 5, ["x|y"] = 1, Other = "soon" }
    local str = FC:ExportString()
    local other = setup({ name = "Alt" })
    other.FC:ImportString(str, "replace")
    local n = 0
    for _ in pairs(other.FC.db.companions) do n = n + 1 end
    eq(n, 1, "one valid companion")
    eq(#other.FC.db.groups, 1, "one valid group")
    eq(#other.FC.db.groups[1].members, 1, "bad member names dropped")
    n = 0
    for _ in pairs(other.FC.db.friends) do n = n + 1 end
    eq(n, 1, "one valid friend")
end)
