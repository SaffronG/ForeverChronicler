-- Professions, recipes and crafting (src/chronicle/Professions.lua)

local TAILORING = 197

local function entriesOf(FC, kind)
    local out = {}
    for _, e in ipairs(FC.db.entries) do if e.kind == kind then out[#out + 1] = e.text end end
    return out
end

local function has(list, s)
    for _, t in ipairs(list) do if t:find(s, 1, true) then return true end end
    return false
end

-- A character whose baseline scan is done (past the quiet first-login window).
local function settled(opts)
    local env = setup(opts)
    env.now = 100 -- GetTime() past the 30 s quiet window
    return env
end

test("first scan on a character records professions silently", function()
    local env = setup()
    env.professions = { { name = "Tailoring", rank = 40, maxRank = 75, skillLine = TAILORING } }
    env.fire("PLAYER_ENTERING_WORLD")
    local p = env.FC.db.professions[TAILORING]
    ok(p, "recorded")
    eq(p.skill, 40, "skill"); eq(p.maxSkill, 75, "max")
    eq(#entriesOf(env.FC, "profession"), 0, "no entries for what you already had")
    ok(env.FC.db.professionsBaseline, "baseline done")
end)

test("new profession, skill steps of 25, max skill and unlearning", function()
    local env = settled()
    local FC = env.FC
    env.fire("PLAYER_ENTERING_WORLD") -- baseline with no professions
    env.professions = { { name = "Tailoring", rank = 1, maxRank = 75, skillLine = TAILORING } }
    env.fire("SKILL_LINES_CHANGED")
    ok(has(entriesOf(FC, "profession"), "Learned a new profession: Tailoring"), "new profession")
    env.professions[1].rank = 20; env.fire("SKILL_LINES_CHANGED")
    eq(#entriesOf(FC, "profession"), 1, "no entry below 25")
    env.professions[1].rank = 26; env.fire("SKILL_LINES_CHANGED")
    ok(has(entriesOf(FC, "profession"), "Tailoring skill reached 26"), "step entry")
    env.professions[1].rank = 75; env.fire("SKILL_LINES_CHANGED")
    ok(has(entriesOf(FC, "profession"), "maxed out at 75"), "max entry")
    -- empty list right after login must not count as unlearning
    env.professions = {}
    env.fire("PLAYER_ENTERING_WORLD")
    eq(FC.db.professions[TAILORING].gone, nil, "not gone after an empty login scan")
    env.professions = { { name = "Cooking", rank = 1, maxRank = 75, skillLine = 185 } }
    env.fire("SKILL_LINES_CHANGED")
    ok(has(entriesOf(FC, "profession"), "Unlearned Tailoring"), "unlearned")
    ok(FC.db.professions[TAILORING].gone, "marked gone")
    eq(#FC:ProfessionRows(), 1, "gone profession hidden")
end)

test("opening the profession window counts recipes for % completion", function()
    local env = settled()
    local FC = env.FC
    env.professions = { { name = "Tailoring", rank = 50, maxRank = 75, skillLine = TAILORING } }
    env.fire("PLAYER_ENTERING_WORLD")
    env.recipes = {
        [1] = { name = "Bolt of Linen", learned = true, prof = TAILORING },
        [2] = { name = "Linen Bag", learned = true, prof = TAILORING },
        [3] = { name = "Silk Robe", learned = false, prof = TAILORING },
        [4] = { name = "Placeholder", learned = false, prof = TAILORING, dummy = true },
        [5] = { name = "Copper Bar", learned = true, prof = 186 },
    }
    eq(FC:ProfessionRows()[1].pct, nil, "unknown before the window was opened")
    env.openProf = TAILORING
    local timersBefore = #env.timers
    env.fire("TRADE_SKILL_SHOW"); env.fire("TRADE_SKILL_LIST_UPDATE")
    eq(#env.timers - timersBefore, 1, "scans are debounced")
    env.runTimers()
    local row = FC:ProfessionRows()[1]
    eq(row.learned, 2, "learned"); eq(row.total, 3, "total (dummy and other professions left out)")
    eq(math.floor(row.pct), 66, "percent")
    eq(FC:KnownRecipes(), 2, "known recipes")
    eq(FC.db.samples[#FC.db.samples].recipes, 2, "sampled for the Journey graph")
    -- another player's linked profession isn't counted
    env.linked = true; env.recipes[3].learned = true
    env.fire("TRADE_SKILL_LIST_UPDATE"); env.runTimers()
    eq(FC:ProfessionRows()[1].learned, 2, "linked window ignored")
end)

test("learning recipes: single entries, ranks and trainer bursts", function()
    local env = settled()
    local FC = env.FC
    env.professions = { { name = "Tailoring", rank = 50, maxRank = 75, skillLine = TAILORING } }
    env.fire("PLAYER_ENTERING_WORLD")
    env.recipes = { [3] = { name = "Silk Robe", learned = false, prof = TAILORING },
        [6] = { name = "Linen Belt", learned = true, prof = TAILORING } }
    env.openProf = TAILORING; env.fire("TRADE_SKILL_SHOW"); env.runTimers(); env.openProf = nil
    eq(FC.db.professions[TAILORING].learned, 1, "scanned")

    env.fire("NEW_RECIPE_LEARNED", 3, 1)
    env.fire("NEW_RECIPE_LEARNED", 6, 2)
    eq(#entriesOf(FC, "recipe"), 0, "collected first")
    env.runTimers()
    local list = entriesOf(FC, "recipe")
    ok(has(list, "Learned recipe: Silk Robe (Tailoring)"), "recipe entry with profession")
    ok(has(list, "Learned rank 2 of Linen Belt"), "rank entry")
    eq(FC.db.stats.recipes, 1, "ranks aren't new recipes")
    eq(FC.db.professions[TAILORING].learned, 2, "completion updated without reopening the window")

    for id = 10, 19 do env.recipes[id] = { name = "R" .. id, prof = TAILORING } end
    for id = 10, 19 do env.fire("NEW_RECIPE_LEARNED", id, 1) end
    env.runTimers()
    ok(has(entriesOf(FC, "recipe"), "Learned 10 new Tailoring recipes"), "burst summed up")
    eq(#entriesOf(FC, "recipe"), 3, "one line for the burst")
    eq(FC.db.professions[TAILORING].learned, 2, "never above the scanned total")
    eq(FC.db.stats.recipes, 11, "all counted")
end)

test("crafting: first craft per item, milestones, per-profession counts", function()
    local env = settled()
    local FC = env.FC
    env.professions = { { name = "Tailoring", rank = 50, maxRank = 75, skillLine = TAILORING } }
    env.fire("PLAYER_ENTERING_WORLD")
    env.items[2996] = "Bolt of Linen Cloth"
    env.openProf = TAILORING
    for _ = 1, 10 do env.fire("TRADE_SKILL_ITEM_CRAFTED_RESULT", { itemID = 2996, quantity = 1 }) end
    env.fire("TRADE_SKILL_ITEM_CRAFTED_RESULT", { itemID = 4240, hyperlink = "|cffffffff|Hitem:4240::|h[Woolen Bag]|h|r" })
    env.fire("TRADE_SKILL_ITEM_CRAFTED_RESULT", { quantity = 1 }) -- malformed: ignored
    local list = entriesOf(FC, "craft")
    ok(has(list, "Crafted Bolt of Linen Cloth for the first time"), "first craft")
    ok(has(list, "Crafted Woolen Bag for the first time"), "name from hyperlink")
    ok(has(list, "Crafted 10 items so far"), "milestone")
    eq(#list, 3, "no entry for repeat crafts")
    eq(FC.db.stats.crafts, 11, "craft count")
    eq(FC.db.crafted[2996], 10, "per item")
    eq(FC:ProfessionRows()[1].crafts, 11, "per profession")
    eq(#FC.db.errorLog, 0, "no errors")
end)

test("profession entry types can be switched off", function()
    local env = settled()
    local FC = env.FC
    ok(env.settings["ForeverChronicler_Log_craft"], "craft toggle registered")
    FC.db.settings.chronicle.craft = false
    env.fire("TRADE_SKILL_ITEM_CRAFTED_RESULT", { itemID = 1 })
    eq(#entriesOf(FC, "craft"), 0, "no entry")
    eq(FC.db.stats.crafts, 1, "still counted")
end)

test("Professions tab draws one row per profession with bars", function()
    local env = settled()
    local FC = env.FC
    env.slash("professions") -- empty, must not error
    eq(FC:ProfessionRowCount(), 0, "no rows")
    env.professions = { { name = "Tailoring", rank = 50, maxRank = 100, skillLine = TAILORING },
        { name = "Cooking", rank = 10, maxRank = 50, skillLine = 185 } }
    env.fire("SKILL_LINES_CHANGED")
    eq(FC:ProfessionRowCount(), 2, "rows")
    local bars = FC:ProfessionBars()
    eq(bars[1].name, "Cooking", "sorted by name")
    eq(bars[2].skillFrac, 0.5, "skill fraction")
    ok(bars[2].recipeText:find("Open this profession", 1, true), "hint until scanned")
    env.slash("professions list")
    ok(env.chatContains("Tailoring: skill 50/100"), "text list")
    eq(#FC.db.errorLog, 0, "no errors")
end)

test("recipes and crafts graph only uses samples that have them", function()
    local clock = 1000000
    local env = settled({ time = function() return clock end })
    local FC = env.FC
    FC.db.samples = { { t = clock - 7200, level = 1, money = 0, quests = 0, deaths = 0, zones = 1 } } -- old save
    env.professions = { { name = "Tailoring", rank = 50, maxRank = 75, skillLine = TAILORING } }
    env.fire("PLAYER_ENTERING_WORLD")
    env.recipes = { [1] = { name = "A", learned = true, prof = TAILORING }, [2] = { name = "B", learned = false, prof = TAILORING } }
    env.openProf = TAILORING; env.fire("TRADE_SKILL_SHOW"); env.runTimers()
    eq(FC:ChartPoints("recipes"), nil, "one sample with recipes isn't a graph yet")
    clock = clock + 600; env.recipes[2].learned = true
    env.fire("TRADE_SKILL_LIST_UPDATE"); env.runTimers()
    local pts, minV, maxV = FC:ChartPoints("recipes")
    eq(#pts, 2, "old sample skipped"); eq(minV, 1, "min"); eq(maxV, 2, "max")
    FC:SetChartSeries("crafts")
    env.slash("journey")
    eq(#FC.db.errorLog, 0, "no errors")
end)

test("professions and crafts survive export and import", function()
    local env = settled({ noEncoding = true })
    env.professions = { { name = "Tailoring", rank = 50, maxRank = 75, skillLine = TAILORING } }
    env.fire("PLAYER_ENTERING_WORLD")
    env.openProf = TAILORING
    env.fire("TRADE_SKILL_ITEM_CRAFTED_RESULT", { itemID = 2996 })
    local str = env.FC:ExportString()

    local env2 = setup({ noEncoding = true })
    ok(env2.FC:ImportString(str, "merge"), "import")
    local db = env2.FC.db
    eq(db.professions[TAILORING].name, "Tailoring", "profession")
    eq(db.professions[TAILORING].crafts, 1, "crafts")
    eq(db.crafted[2996], 1, "crafted item")
    eq(db.stats.crafts, 1, "stats")
    env2.FC:ImportString(str, "replace")
    eq(db.stats.recipes ~= nil, true, "replace keeps the new counters")
    ok(env2.FC:UndoImport(), "undo")
end)

test("import rejects malformed profession data", function()
    local env = setup({ noEncoding = true })
    local FC = env.FC
    FC.db.professions = { [TAILORING] = { name = "Tailoring", learned = 900, total = 10 }, bad = { name = "x" },
        [5] = { name = 42 } }
    FC.db.crafted = { [1] = 3, [2] = "lots", x = 1 }
    local str = FC:ExportString()
    local env2 = setup({ noEncoding = true })
    ok(env2.FC:ImportString(str, "merge"), "import")
    local db = env2.FC.db
    eq(db.professions[TAILORING].learned, 10, "learned capped at total")
    eq(db.professions.bad, nil, "string key dropped"); eq(db.professions[5], nil, "bad name dropped")
    eq(db.crafted[1], 3, "valid count"); eq(db.crafted[2], nil, "bad count dropped")
end)

test("secondary professions are found when the primary slots are empty", function()
    local env = settled()
    -- no primary professions, no archaeology/fishing: GetProfessions() returns nil, nil, nil, nil, 5
    env.professions = { false, false, false, false, { name = "Cooking", rank = 30, maxRank = 75, skillLine = 185 } }
    env.fire("PLAYER_ENTERING_WORLD")
    ok(env.FC.db.professions[185], "cooking recorded")
    eq(env.FC:ProfessionRows()[1].name, "Cooking", "shown")
end)
