-- Daily letters and per-day stats (src/chronicle/Letters.lua)

local DAY = 86400
-- 2026-11-05 12:00 local time (a day runs 04:00 - 04:00)
local NOON = os.time({ year = 2026, month = 11, day = 5, hour = 12 })

local function journey(opts)
    local clock = NOON
    opts = opts or {}
    opts.time = function() return clock end
    local env = setup(opts)
    env.advance = function(seconds) clock = clock + seconds end
    env.clock = function() return clock end
    return env
end

test("a day starts at 04:00, so late nights count as the day before", function()
    local env = journey()
    local FC = env.FC
    eq(FC.DayKey(NOON), "2026-11-05", "noon")
    eq(FC.DayKey(NOON + 14 * 3600), "2026-11-05", "02:00 the next morning")
    eq(FC.DayKey(NOON + 17 * 3600), "2026-11-06", "05:00 the next morning")
end)

test("the daily ledger records time, level, gold and zones", function()
    local env = journey({ level = 10 })
    local FC = env.FC
    env.player.money = 10000
    local today = FC:Today()
    eq(today.level0, 10, "start level"); eq(today.visited[1], "Elwynn Forest", "login zone")
    env.advance(60); env.runTickers()
    env.advance(60); env.runTickers()
    eq(today.active, 120, "two minutes played")
    env.advance(3600); env.runTickers() -- a long gap (away) doesn't count
    eq(today.active, 120, "gaps ignored")
    env.player.zone = "Westfall"; env.fire("ZONE_CHANGED_NEW_AREA")
    env.player.level = 11; env.fire("PLAYER_LEVEL_UP", 11)
    env.player.money = 25000; env.fire("PLAYER_MONEY")
    eq(today.level1, 11, "end level"); eq(today.money1, 25000, "end gold")
    eq(today.visited[2], "Westfall", "zone added")
end)

test("day stats come from that day's entries and ledger", function()
    local env = journey({ level = 10 })
    local FC = env.FC
    env.player.money = 10000
    env.player.zone = "Westfall"; env.fire("ZONE_CHANGED_NEW_AREA")
    env.questTitles = { [1] = "The Defias Brotherhood" }; env.fire("QUEST_TURNED_IN", 1)
    env.fire("PLAYER_DEAD")
    env.player.level = 11; env.fire("PLAYER_LEVEL_UP", 11)
    env.slash("note Saw a murloc dance")
    env.player.money = 15050; env.fire("PLAYER_MONEY")
    -- tomorrow
    env.advance(DAY); env.slash("note next day")

    local s = FC:DayStats("2026-11-05")
    eq(s.dayNumber, 1, "day 1")
    eq(s.quests[1], "The Defias Brotherhood", "quest")
    eq(s.deaths[1], "Westfall", "death zone")
    eq(s.firstVisits[#s.firstVisits], "Westfall", "first visit (after the login zone)")
    eq(s.level0, 10, "level from"); eq(s.level1, 11, "level to")
    eq(s.money0, 0, "gold at login"); eq(s.moneyChange, 15050, "gold change")
    eq(s.notes[1], "Saw a murloc dance", "note")
    local s2 = FC:DayStats("2026-11-06")
    eq(s2.dayNumber, 2, "day 2"); eq(#s2.quests, 0, "nothing carried over")
    eq(#FC:JourneyDays(), 2, "two days")
end)

test("letters use the race and class voice and tell the day", function()
    local env = journey({ level = 10, name = "Lunara" })
    local FC = env.FC
    env.player.zone = "Darkshore"; env.fire("ZONE_CHANGED_NEW_AREA")
    env.questTitles = { [1] = "The Absent-Minded Prospector" }; env.fire("QUEST_TURNED_IN", 1)
    env.player.level = 11; env.fire("PLAYER_LEVEL_UP", 11)
    local letter = FC:ComposeLetter("2026-11-05")
    ok(letter:find("Darkshore, the 5th of November 2026", 1, true), "dateline: " .. letter)
    ok(letter:find("Day 1 of my journey", 1, true), "day number")
    ok(letter:find("Beloved sister in Darnassus,", 1, true), "night elf greeting")
    ok(letter:find("Under Elune's light", 1, true), "night elf sign-off")
    ok(letter:find("keeper of the Dream", 1, true), "druid signature")
    ok(letter:find("[Ff]or the first time I set foot in [^.]*Darkshore"), "first visit")
    ok(letter:find("reached level 11", 1, true), "level")
    ok(letter:find("The Absent-Minded Prospector", 1, true), "quest")
    ok(letter:find("Lunara", 1, true), "signed with the name")
    ok(not letter:find("|c", 1, true), "plain text")
    eq(FC:ComposeLetter("2026-11-05"), letter, "the same day always reads the same")

    -- another race and class
    env.player.race, env.player.raceName = "Orc", "Orc"
    env.player.class, env.player.className = "WARRIOR", "Warrior"
    local orc = FC:ComposeLetter("2026-11-05")
    ok(orc:find("To the Warchief and my clan,", 1, true), "orc greeting")
    ok(orc:find("Lok'tar ogar!", 1, true), "orc sign-off")
    ok(orc:find("your shield on the road", 1, true), "warrior signature")
    -- unknown (allied) race falls back to the faction
    env.player.race, env.player.faction = "Vulpera", "Horde"
    ok(FC:ComposeLetter("2026-11-05"):find("To my kin in Orgrimmar,", 1, true), "faction fallback")
end)

test("a quiet day still gets a letter", function()
    local env = journey()
    -- a later day where you only logged in, in a zone you already knew
    env.FC.db.days["2026-11-20"] = { first = NOON, last = NOON, active = 0, level0 = 10, level1 = 10,
        money0 = 0, money1 = 0, visited = {} }
    local letter = env.FC:ComposeLetter("2026-11-20")
    ok(letter:find("quiet day", 1, true), "quiet day: " .. letter)
end)

test("days from before letters existed get letters from the chronicle alone", function()
    local env = journey({ level = 20 })
    local FC = env.FC
    local old = NOON - 10 * DAY
    table.insert(FC.db.entries, 1, { t = old, kind = "quest", text = "|cffffff00Completed quest: Old Times|r", zone = "Duskwood", level = 19 })
    table.insert(FC.db.entries, 2, { t = old + 60, kind = "level", text = "|cff00ff00Reached level 20!|r", zone = "Duskwood", level = 20 })
    local key = FC.DayKey(old)
    local s = FC:DayStats(key)
    eq(s.ledger, false, "no ledger")
    eq(s.level0, 19, "level before"); eq(s.level1, 20, "level after")
    eq(s.dayNumber, 1, "oldest day is day 1")
    local letter = FC:ComposeLetter(key)
    ok(letter:find("Old Times", 1, true), "quest in letter")
    ok(letter:find("Duskwood", 1, true), "place from the entries")
    local lines = table.concat(FC:DayStatsLines(s), "\n")
    ok(lines:find("not recorded", 1, true), "time unknown for old days")
end)

test("Letters tab lists days and loads each day's letter and stats", function()
    local env = journey()
    local FC = env.FC
    env.slash("note day one")
    env.advance(DAY); env.slash("note day two")
    env.slash("letters")
    eq(FC:SelectedLetter(), "2026-11-06", "newest day selected")
    local text = FC:LetterViewText()
    ok(text:find("Still being written", 1, true), "today is a draft")
    ok(text:find("The day's ledger", 1, true), "stats shown")
    ok(text:find("Notes written:|r 1", 1, true), "stat line")
    FC:ShowLetter("2026-11-05")
    ok(FC:LetterViewText():find("day one", 1, true), "older day loaded")
    ok(not FC:LetterViewText():find("Still being written", 1, true), "past day isn't a draft")
    env.slash("letter 2026-11-05")
    ok(env.chatContains("Day 1 of my journey"), "printed to chat")
    env.slash("letter nonsense")
    ok(env.chatContains("Usage: /chron letter"), "bad date")
    eq(#FC.db.errorLog, 0, "no errors")
end)

test("days survive export and import", function()
    local env = journey({ noEncoding = true })
    env.advance(60); env.runTickers()
    local str = env.FC:ExportString()
    local env2 = setup({ noEncoding = true })
    ok(env2.FC:ImportString(str, "merge"), "import")
    local d = env2.FC.db.days["2026-11-05"]
    ok(d, "day imported"); eq(d.active, 60, "time played")
    eq(d.visited[1], "Elwynn Forest", "zones")
end)

test("import rejects malformed days", function()
    local env = setup({ noEncoding = true })
    env.FC.db.days = { ["2026-01-01"] = { active = 5, visited = { "A", 42 } }, ["bad key"] = { active = 1 },
        ["2026-01-02"] = "nope" }
    local str = env.FC:ExportString()
    local env2 = setup({ noEncoding = true })
    env2.FC.db.days = {}
    ok(env2.FC:ImportString(str, "merge"), "import")
    local days = env2.FC.db.days
    eq(days["bad key"], nil, "bad key dropped"); eq(days["2026-01-02"], nil, "bad record dropped")
    eq(#days["2026-01-01"].visited, 1, "non-string zone dropped")
end)
