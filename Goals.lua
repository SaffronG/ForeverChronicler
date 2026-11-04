-- Forever Chronicaller: goal setting
-- Goal text is parsed for auto-completing goal types:
--   "level 30"            -> completes when you reach level 30
--   "zone Stranglethorn Vale" -> completes when you enter that zone
--   "quest The Defias Brotherhood" -> completes when you turn in that quest
--   anything else         -> free-form goal, mark done manually

local _, FC = ...

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function parseGoal(text)
    text = trim(text)
    local lvl = text:match("^[Ll]evel%s+(%d+)$")
    if lvl then return "level", tonumber(lvl), "Reach level " .. lvl end
    local zone = text:match("^[Zz]one%s+(.+)$")
    if zone then return "zone", trim(zone), "Travel to " .. trim(zone) end
    local quest = text:match("^[Qq]uest%s+(.+)$")
    if quest then return "quest", trim(quest), "Complete quest: " .. trim(quest) end
    return "free", nil, text
end

function FC:AddGoal(rawText)
    if not rawText or trim(rawText) == "" then return end
    local kind, target, text = parseGoal(rawText)
    local g = { text = text, kind = kind, target = target, done = false, created = time() }
    table.insert(self.db.goals, g)
    self:Print("New goal: " .. text)
    self:Fire("GOALS_CHANGED")
    self:CheckGoals() -- e.g. "level 10" when you're already 12
    return g
end

function FC:CompleteGoal(index)
    local g = self.db.goals[index]
    if not g or g.done then return end
    g.done = true
    g.completed = time()
    local days = math.floor((g.completed - g.created) / 86400)
    local took = days > 0 and string.format(" (after %d day%s)", days, days == 1 and "" or "s") or ""
    self:AddEntry("goal", string.format("|cffff80ffGoal achieved: %s%s|r", g.text, took))
    self:Print("|cffff80ffGoal achieved:|r " .. g.text)
    UIErrorsFrame:AddMessage("Goal achieved: " .. g.text, 1, 0.5, 1)
    self:Fire("GOALS_CHANGED")
end

function FC:RemoveGoal(index)
    if self.db.goals[index] then
        table.remove(self.db.goals, index)
        self:Fire("GOALS_CHANGED")
    end
end

function FC:ToggleGoal(index)
    local g = self.db.goals[index]
    if not g then return end
    if g.done then
        g.done, g.completed = false, nil
        self:Fire("GOALS_CHANGED")
    else
        self:CompleteGoal(index)
    end
end

-- Check every open auto-goal against current state.
-- newLevel is passed on level-up because UnitLevel() can lag behind the event.
function FC:CheckGoals(questTitle, newLevel)
    if not self.db then return end
    local level, zone = newLevel or UnitLevel("player"), self:Zone()
    for i, g in ipairs(self.db.goals) do
        if not g.done then
            if (g.kind == "level" and level >= g.target)
                or (g.kind == "zone" and zone:lower() == g.target:lower())
                or (g.kind == "quest" and questTitle and questTitle:lower() == g.target:lower()) then
                self:CompleteGoal(i)
            end
        end
    end
end

FC:On("READY", function() FC:CheckGoals() end)
FC:On("LEVEL", function(lvl) FC:CheckGoals(nil, lvl) end)
FC:On("ZONE", function() FC:CheckGoals() end)
FC:On("QUEST", function(title) FC:CheckGoals(title) end)