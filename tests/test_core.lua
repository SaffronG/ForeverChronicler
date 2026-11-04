test("chronicle starts with an opening entry and first zone", function()
    local env = setup()
    local e = env.FC.db.entries
    eq(e[1].kind, "start", "first entry")
    eq(e[2].kind, "zone", "second entry")
end)

test("level up, death, achievement and quest are chronicled", function()
    local env = setup()
    env.player.level = 11; env.fire("PLAYER_LEVEL_UP", 11)
    env.fire("PLAYER_DEAD")
    env.fire("ACHIEVEMENT_EARNED", 7)
    env.questTitles = { [176] = "Hogger" }
    env.fire("QUEST_TURNED_IN", 176, 0, 0)
    env.fire("QUEST_TURNED_IN", 999, 0, 0) -- uncached title -> fallback
    local kinds = {}
    for _, x in ipairs(env.FC.db.entries) do kinds[#kinds + 1] = x.kind end
    eq(table.concat(kinds, ","), "start,zone,level,death,achievement,quest,quest", "entry kinds")
    eq(env.FC.db.stats.deaths, 1, "deaths")
    eq(env.FC.db.stats.quests, 2, "quests")
    ok(env.FC.db.entries[7].text:find("Quest #999", 1, true), "fallback quest title")
end)

test("first visit to a zone is only logged once", function()
    local env = setup()
    env.player.zone = "Westfall"; env.fire("ZONE_CHANGED_NEW_AREA")
    env.player.zone = "Elwynn Forest"; env.fire("ZONE_CHANGED_NEW_AREA")
    env.player.zone = "Westfall"; env.fire("ZONE_CHANGED_NEW_AREA")
    local zones = 0
    for _, x in ipairs(env.FC.db.entries) do if x.kind == "zone" then zones = zones + 1 end end
    eq(zones, 2, "zone entries")
end)

test("old save without newer keys gets defaults and keeps data", function()
    local env = setup({ savedDB = { version = 1, entries = { { t = 1, kind = "note", text = "old", level = 1 } },
        goals = {}, zones = { ["Elwynn Forest"] = 1 }, stats = { deaths = 3, quests = 9 } } })
    eq(env.FC.db.entries[1].text, "old", "kept entry")
    eq(env.FC.db.stats.deaths, 3, "kept deaths")
    eq(env.FC.db.settings.chronicle.level, true, "default setting added")
    ok(env.FC.db.errorLog, "errorLog added")
end)

test("an error in one listener is logged and does not stop others", function()
    local env = setup()
    local FC = env.FC
    local reached = false
    FC:On("TEST_MSG", function() error("boom") end)
    FC:On("TEST_MSG", function() reached = true end)
    FC:Fire("TEST_MSG")
    ok(reached, "second listener ran")
    eq(#FC.db.errorLog, 1, "error logged")
    ok(FC.db.errorLog[1].msg:find("boom"), "error message")
    ok(env.chatContains("/chron errors"), "user told about /chron errors")
    FC:Fire("TEST_MSG")
    eq(#FC.db.errorLog, 1, "repeat error is merged")
    eq(FC.db.errorLog[1].count, 2, "repeat count")
end)

test("an error in an event handler does not break the chronicle", function()
    local env = setup()
    env.FC:RegisterEvent("PLAYER_LEVEL_UP", function() error("bad handler") end)
    env.player.level = 11; env.fire("PLAYER_LEVEL_UP", 11)
    local last = env.FC.db.entries[#env.FC.db.entries]
    eq(last.kind, "level", "level still logged")
end)

test("slash commands: help, usage, unknown, errors", function()
    local env = setup()
    env.slash("help")
    ok(env.chatContains("/chron note <text>"), "help lists note")
    env.slash("note")
    ok(env.chatContains("Usage: /chron note"), "usage when missing text")
    env.slash("note Met a gnome")
    ok(env.FC.db.entries[#env.FC.db.entries].text:find("Met a gnome", 1, true), "note added")
    env.slash("errors")
    ok(env.chatContains("No errors logged."), "errors empty")
    env.slash("nonsense")
    ok(env.chatContains("Commands (/chron or /fc):"), "unknown shows help")
end)

test("a failing slash command is contained", function()
    local env = setup()
    env.FC:Command("explode", "/chron explode", function() error("kaboom") end)
    env.slash("explode")
    ok(env.FC.db.errorLog[1].msg:find("kaboom"), "logged")
end)

test("privacy notice shown once, /chron privacy explains", function()
    local env = setup()
    ok(env.chatContains("/chron privacy for details"), "first-run notice")
    eq(env.FC.db.privacyNoticeShown, true, "remembered")
    local env2 = setup({ savedDB = { privacyNoticeShown = true } })
    ok(not env2.chatContains("/chron privacy for details"), "not shown again")
    env2.slash("privacy")
    ok(env2.chatContains("can't use the internet"), "summary")
end)

test("diagnostics are off by default and record nothing", function()
    local env = setup()
    eq(env.FC.db.settings.diagnostics, false, "off by default")
    env.slash("note hi")
    eq(env.FC.db.diagnostics, nil, "nothing recorded")
end)

test("diagnostics on: per-label latency buckets, errors, version reset", function()
    local env = setup({ version = "0.3.1" })
    local FC = env.FC
    FC.FEATURES.diagnostics = true -- feature flag is off in releases; the code stays tested
    env.slash("diagnostics on")
    env.tick = 3 -- each handler "takes" 3 ms
    env.player.level = 11; env.fire("PLAYER_LEVEL_UP", 11)
    env.slash("note hello")
    local d = FC.db.diagnostics
    eq(d.version, "0.3.1", "linked to version")
    local lvl = d.handlers["event:PLAYER_LEVEL_UP"]
    ok(lvl and lvl.n == 1, "event timed")
    ok(lvl.sum > 3, "nested handlers count towards their parent")
    FC:RegisterEvent("TEST_LEAF", function() end)
    env.fire("TEST_LEAF")
    local h = d.handlers["event:TEST_LEAF"]
    eq(h.sum, 3, "leaf handler took 3 ms")
    eq(h.b[5], 1, "3 ms lands in the (2, 5] bucket")
    local total = 0
    for _, c in ipairs(h.b) do total = total + c end
    eq(total, h.n, "bucket counts add up to runs")
    ok(d.handlers["cmd:note"] and d.handlers["msg:ENTRY_ADDED"], "commands and messages timed")
    for label in pairs(d.handlers) do ok(not label:find("hello"), "labels never contain user text") end
    FC:On("BOOM", function() error("x") end)
    FC:Fire("BOOM")
    eq(d.handlers["msg:BOOM"].err, 1, "failure counted")
    eq(FC.db.errorLog[1].v, "0.3.1", "error linked to version")
    eq(FC.db.errorLog[1].label, "msg:BOOM", "error linked to handler")
    FC.version = "0.4.0"; env.slash("note again")
    eq(FC.db.diagnostics.version, "0.4.0", "reset on new version")
    eq(FC.db.diagnostics.handlers["msg:BOOM"], nil, "old data dropped")
    env.slash("diagnostics off")
    eq(FC.db.diagnostics, nil, "turning off deletes the data")
end)

test("diagnostics feature flag off: hidden, no timing, no option", function()
    local env = setup()
    local FC = env.FC
    eq(FC.FEATURES.diagnostics, false, "flag is off in this version")
    eq(env.settings["ForeverChronicaller_Diagnostics"], nil, "no options checkbox")
    env.slash("help")
    ok(not env.chatContains("/chron diagnostics"), "not listed in help")
    env.slash("diagnostics on")
    ok(env.chatContains("aren't available in this version"), "command explains")
    eq(FC.db.settings.diagnostics, false, "setting unchanged")
    FC.db.settings.diagnostics = true -- even if a saved setting says on...
    env.slash("note hi")
    eq(FC.db.diagnostics, nil, "...nothing is timed")
end)
