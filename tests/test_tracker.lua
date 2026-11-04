-- Tracker height = 22 + lines * 16 + 4 (22 when collapsed)
local function lineCount(env) local h = env.FC.tracker:GetHeight(); return h <= 22 and 0 or (h - 26) / 16 end

test("tracker hidden without goals, shown with open goals", function()
    local env = setup()
    local t = env.FC.tracker
    eq(t:IsShown(), false, "hidden with no goals")
    env.slash("goal Get a mount")
    eq(t:IsShown(), true, "shown with an open goal")
    eq(lineCount(env), 1, "one line")
    env.slash("done 1")
    eq(t:IsShown(), false, "hidden when all done")
end)

test("tracker shows level progress and location distance", function()
    local env = setup({ level = 10 })
    local FC = env.FC
    env.slash("goal level 20"); env.slash("goal 80 50")
    ok(FC:GoalProgressText(FC.db.goals[1]):find("(10/20)", 1, true), "level progress")
    env.runTickers()
    ok(FC:GoalProgressText(FC.db.goals[2]):find("300 yd", 1, true), "distance (0.5 -> 0.8 of 1000 yd)")
end)

test("tracker toggle command and collapse", function()
    local env = setup()
    local FC = env.FC
    env.slash("goal A"); env.slash("goal B")
    eq(lineCount(env), 2, "two lines")
    env.slash("tracker")
    eq(FC.tracker:IsShown(), false, "hidden by command")
    env.slash("tracker")
    eq(FC.tracker:IsShown(), true, "shown again")
    FC.db.settings.trackerCollapsed = true; FC.RefreshTracker()
    eq(FC.tracker:IsShown(), true, "collapsed tracker still shown")
    eq(lineCount(env), 0, "no lines when collapsed")
end)

test("tracker caps at 8 lines plus a 'more' line", function()
    local env = setup()
    for i = 1, 11 do env.slash("goal g" .. i) end
    eq(lineCount(env), 9, "8 goals + more")
end)

test("saved tracker position is restored", function()
    local env = setup({ savedDB = { settings = { trackerPos = { "TOPLEFT", "TOPLEFT", 100, -200 } } } })
    eq(env.FC.db.settings.trackerPos[3], 100, "position kept")
end)
