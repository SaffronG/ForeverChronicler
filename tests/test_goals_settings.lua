test("level, zone, quest and free goals", function()
    local env = setup({ level = 5 })
    local FC = env.FC
    env.slash("goal level 6"); env.slash("goal zone Westfall"); env.slash("goal quest Hogger")
    env.slash("goal quest 999"); env.slash("goal Get a mount"); env.slash("goal level 3")
    local g = FC.db.goals
    eq(g[6].done, true, "already-reached level goal completes immediately")
    env.player.level = 6; env.fire("PLAYER_LEVEL_UP", 6)
    eq(g[1].done, true, "level goal")
    env.player.zone = "Westfall"; env.fire("ZONE_CHANGED_NEW_AREA")
    eq(g[2].done, true, "zone goal")
    env.questTitles = { [176] = "Hogger" }
    env.fire("QUEST_TURNED_IN", 176); env.fire("QUEST_TURNED_IN", 999)
    eq(g[3].done, true, "quest goal by name")
    eq(g[4].done, true, "quest goal by ID")
    eq(g[5].done, false, "free goal stays open")
    env.slash("done 5")
    eq(g[5].done, true, "manual done")
    env.slash("del 5")
    eq(#g, 5, "deleted")
end)

test("settings register and open", function()
    local env = setup()
    ok(env.settings["ForeverChronicler_Log_death"], "death toggle registered")
    ok(env.settings["ForeverChronicler_MaxEntries"], "cap registered")
    env.slash("config")
    eq(env.openedSettings, "Forever Chronicler", "opened")
end)

test("disabled entry type is skipped but counted", function()
    local env = setup()
    local FC = env.FC
    FC.db.settings.chronicle.death = false
    local before = #FC.db.entries
    env.fire("PLAYER_DEAD")
    eq(#FC.db.entries, before, "no entry")
    eq(FC.db.stats.deaths, 1, "still counted")
end)

test("entry cap trims only when a new entry arrives", function()
    local env = setup()
    local FC = env.FC
    for i = 1, 10 do env.slash("note n" .. i) end
    FC.db.settings.maxEntries = 5
    eq(#FC.db.entries, 12, "nothing deleted by changing the setting")
    env.slash("note last")
    eq(#FC.db.entries, 5, "trimmed on next entry")
end)
