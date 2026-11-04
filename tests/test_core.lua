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
