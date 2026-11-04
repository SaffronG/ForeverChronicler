-- Forever Chronicaller: the chronicle (automatic adventure log)

local _, FC = ...

function FC:AddEntry(kind, text)
    local e = { t = time(), kind = kind, text = text, zone = self:Zone(), level = UnitLevel("player") }
    table.insert(self.db.entries, e)
    self:Fire("ENTRY_ADDED", e)
    return e
end

function FC:FormatEntry(e)
    return string.format("|cff888888%s|r |cffaaaaaa[Lv%d]|r %s",
        date("%Y-%m-%d %H:%M", e.t), e.level or 0, e.text)
end

FC:On("READY", function()
    if #FC.db.entries == 0 then
        local name = UnitName("player")
        FC:AddEntry("start", string.format("The chronicle of %s begins in %s.", name or "a hero", FC:Zone()))
    end
end)

-- Level ups
FC:RegisterEvent("PLAYER_LEVEL_UP", function(newLevel)
    FC:AddEntry("level", string.format("|cff00ff00Reached level %d!|r", newLevel))
    FC:Fire("LEVEL", tonumber(newLevel))
end)

-- First visit to a zone
local function checkZone()
    if not FC.db then return end
    local zone = FC:Zone()
    if zone and zone ~= "" and zone ~= "Unknown" and not FC.db.zones[zone] then
        FC.db.zones[zone] = time()
        FC:AddEntry("zone", string.format("|cff66ccffFirst arrived in %s.|r", zone))
    end
    FC:Fire("ZONE", zone)
end
FC:RegisterEvent("ZONE_CHANGED_NEW_AREA", checkZone)
FC:RegisterEvent("PLAYER_ENTERING_WORLD", checkZone)

-- Deaths
FC:RegisterEvent("PLAYER_DEAD", function()
    FC.db.stats.deaths = FC.db.stats.deaths + 1
    FC:AddEntry("death", string.format("|cffff4444Fell in battle in %s (death #%d).|r",
        FC:Zone(), FC.db.stats.deaths))
end)

-- Achievements (WotLK+)
if GetAchievementInfo then
    FC:RegisterEvent("ACHIEVEMENT_EARNED", function(id)
        local _, name = GetAchievementInfo(id)
        if name then
            FC:AddEntry("achievement", string.format("|cffffcc00Earned achievement: %s|r", name))
        end
    end)
end

-- Quest turn-ins. QUEST_TURNED_IN gives the quest ID; the title may not be
-- cached yet, so fall back to the open quest frame, then to the ID.
FC:RegisterEvent("QUEST_TURNED_IN", function(questID)
    local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
    if not title or title == "" then title = GetTitleText and GetTitleText() end
    if not title or title == "" then title = "Quest #" .. tostring(questID) end
    FC.db.stats.quests = FC.db.stats.quests + 1
    FC:AddEntry("quest", string.format("|cffffff00Completed quest: %s|r", title))
    FC:Fire("QUEST", title, questID)
end)
