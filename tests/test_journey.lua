test("samples are recorded on login, level up and quests, without duplicates", function()
    local clock = 1000000
    local env = setup({ time = function() return clock end, level = 5 })
    local FC = env.FC
    local base = #FC.db.samples
    ok(base >= 1, "login sample")
    FC:TakeSample()
    eq(#FC.db.samples, base, "unchanged state not recorded again")
    clock = clock + 3600; env.player.level = 6; env.fire("PLAYER_LEVEL_UP", 6)
    eq(FC.db.samples[#FC.db.samples].level, 6, "level sample")
    clock = clock + 60; env.player.money = 250000
    env.questTitles = { [1] = "Q" }; env.fire("QUEST_TURNED_IN", 1)
    local last = FC.db.samples[#FC.db.samples]
    eq(last.quests, 1, "quest count"); eq(last.money, 250000, "money")
end)

test("level progress includes XP fraction", function()
    local env = setup({ level = 7 })
    env.player.xp = 500
    env.FC:TakeSample()
    eq(env.FC.db.samples[#env.FC.db.samples].level, 7.5, "7 + 500/1000")
end)

test("chart points are normalised and the chart draws lines", function()
    local clock = 1000000
    local env = setup({ time = function() return clock end, level = 1 })
    local FC = env.FC
    for lvl = 2, 5 do
        clock = clock + 1800; env.player.level = lvl; env.fire("PLAYER_LEVEL_UP", lvl)
    end
    local pts, minV, maxV = FC:ChartPoints("level")
    eq(minV, 1, "min"); eq(maxV, 5, "max")
    eq(pts[1].x, 0, "first x"); eq(pts[#pts].x, 1, "last x")
    eq(pts[#pts].y, 1, "last y")
    env.slash("journey")
    eq(FC:ChartLineCount(), #pts - 1, "one line per segment")
    FC:SetChartSeries("money")
    eq(FC:ChartPoints("money") ~= nil, true, "money series")
end)

test("too little data shows no chart", function()
    local env = setup()
    eq(env.FC:ChartPoints("level"), nil, "nil with under a minute of history")
    env.slash("journey") -- must not error
    eq(#env.FC.db.errorLog, 0, "no errors")
end)

test("journey summary: path and time per level", function()
    local clock = 1000000
    local env = setup({ time = function() return clock end, level = 1 })
    local FC = env.FC
    clock = clock + 600;  env.player.zone = "Westfall"; env.fire("ZONE_CHANGED_NEW_AREA")
    clock = clock + 1200; env.player.level = 2; env.fire("PLAYER_LEVEL_UP", 2)
    clock = clock + 3600; env.player.level = 3; env.fire("PLAYER_LEVEL_UP", 3)
    local s = FC:JourneyStats()
    eq(#s.levels, 2, "two level durations")
    eq(s.levels[1].seconds, 1800, "level 2 took 30 min")
    eq(s.fastest.level, 2, "fastest"); eq(s.slowest.level, 3, "slowest")
    local text = FC:JourneySummary()
    ok(text:find("Elwynn Forest > Westfall", 1, true), "path in order")
    ok(text:find("Average time per level", 1, true), "average")
end)

test("sample history is thinned, not cut, when it gets large", function()
    local env = setup()
    local FC = env.FC
    FC.db.samples = {}
    for i = 1, 2000 do FC.db.samples[i] = { t = i, level = i, money = 0, quests = 0, deaths = 0, zones = 0 } end
    env.player.level = 99999; FC:TakeSample()
    ok(#FC.db.samples < 2000, "shrunk")
    eq(FC.db.samples[1].t, 1, "oldest kept")
end)
