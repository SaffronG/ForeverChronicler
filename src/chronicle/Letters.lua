-- Forever Chronicler: daily letters ("Letters" tab)
-- One letter per day of adventuring, written in a voice that depends on your
-- race (who you write to, how you sign off) and class (how you tell it). Each
-- letter comes with the stats of that day, and any day can be opened again.
--
-- A day runs from 04:00 to 04:00 local time, so a late night still counts as
-- the day it started. Stats come from the chronicle entries of that day plus a
-- small daily ledger for things entries don't record:
--   db.days["YYYY-MM-DD"] = { first, last, active (seconds played), level0, level1,
--                             money0, money1, visited = { zone, ... } }
-- Letters are composed when you read them, so days from before this feature
-- (from the chronicle alone) get letters too.

local _, FC = ...

local DAY_OFFSET = 4 * 3600 -- the adventurer's day starts at 04:00
local TICK = 60             -- seconds between active-time updates
local MAX_GAP = 180         -- longer gaps (sleep, alt-tab for ages) don't count as played
local MAX_VISITED = 40

function FC.DayKey(t) return date("%Y-%m-%d", (t or time()) - DAY_OFFSET) end

local function days()
    FC.db.days = FC.db.days or {}
    return FC.db.days
end

-- Ledger ---------------------------------------------------------------------------------
function FC:Today()
    local key = FC.DayKey()
    local d = days()[key]
    if not d then
        local level, money = UnitLevel("player") or 0, GetMoney and GetMoney() or 0
        d = { first = time(), last = time(), active = 0, level0 = level, level1 = level,
              money0 = money, money1 = money, visited = {} }
        days()[key] = d
    end
    return d, key
end

local function visit(zone)
    if not zone or zone == "" or zone == "Unknown" then return end
    local d = FC:Today()
    for _, z in ipairs(d.visited) do if z == zone then return end end
    if #d.visited < MAX_VISITED then d.visited[#d.visited + 1] = zone end
end

local function touch()
    local d = FC:Today()
    d.last = time()
    d.level1 = UnitLevel("player") or d.level1
    d.money1 = GetMoney and GetMoney() or d.money1
end

local lastTick
local function tick()
    local now = time()
    local d = FC:Today()
    if lastTick and now - lastTick > 0 and now - lastTick <= MAX_GAP then
        d.active = (d.active or 0) + (now - lastTick)
    end
    lastTick = now
    touch()
end

FC:On("READY", function()
    lastTick = time()
    touch()
    visit(FC:Zone())
    C_Timer.NewTicker(TICK, function() FC:SafeCall(tick) end)
end)
FC:On("ZONE", function(zone) visit(zone) end)
FC:On("LEVEL", function() touch() end)
FC:RegisterEvent("PLAYER_MONEY", function() touch() end)
FC:RegisterEvent("PLAYER_LOGOUT", function() tick() end)

-- Day stats ------------------------------------------------------------------------------
local function plain(text)
    return (text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
end

function FC.FormatMoney(copper)
    copper = math.floor(math.abs(copper or 0))
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end

local function playedText(seconds)
    if seconds < 60 then return "less than a minute" end
    if seconds < 3600 then return string.format("%d min", math.floor(seconds / 60)) end
    return string.format("%d h %d min", math.floor(seconds / 3600), math.floor(seconds / 60) % 60)
end
FC.PlayedText = playedText

-- All days with any activity, oldest first: { key, ... }
function FC:JourneyDays()
    local set = {}
    for key in pairs(days()) do set[key] = true end
    for _, e in ipairs(self.db.entries) do set[FC.DayKey(e.t)] = true end
    local list = {}
    for key in pairs(set) do list[#list + 1] = key end
    table.sort(list)
    return list
end

-- Everything known about one day.
function FC:DayStats(key)
    local ledger = days()[key]
    local s = { key = key, ledger = ledger ~= nil, entries = 0,
        zonesVisited = {}, firstVisits = {}, quests = {}, deaths = {}, achievements = {}, goals = {},
        notes = {}, recipes = {}, crafts = {}, professions = {}, levels = {} }
    local list = self:JourneyDays()
    for i, k in ipairs(list) do if k == key then s.dayNumber = i end end

    local minLevel, lastZone
    for _, e in ipairs(self.db.entries) do
        if FC.DayKey(e.t) == key then
            s.entries = s.entries + 1
            local text = plain(e.text)
            if e.level and (not minLevel or e.level < minLevel) then minLevel = e.level end
            if e.zone then lastZone = e.zone end
            if e.kind == "zone" then s.firstVisits[#s.firstVisits + 1] = text:match("First arrived in (.-)%.?$") or e.zone
            elseif e.kind == "quest" then s.quests[#s.quests + 1] = text:match("Completed quest: (.+)$") or text
            elseif e.kind == "death" then s.deaths[#s.deaths + 1] = e.zone or "?"
            elseif e.kind == "achievement" then s.achievements[#s.achievements + 1] = text:match("Earned achievement: (.+)$") or text
            elseif e.kind == "goal" then s.goals[#s.goals + 1] = (text:match("Goal achieved: (.-)%s*%(") or text:match("Goal achieved: (.+)$") or text)
            elseif e.kind == "note" then s.notes[#s.notes + 1] = text:match('^"(.*)"$') or text
            elseif e.kind == "level" then s.levels[#s.levels + 1] = tonumber(text:match("level (%d+)"))
            elseif e.kind == "recipe" then s.recipes[#s.recipes + 1] = text
            elseif e.kind == "craft" then s.crafts[#s.crafts + 1] = text
            elseif e.kind == "profession" then s.professions[#s.professions + 1] = text
            end
        end
    end

    if ledger then
        s.active = ledger.active or 0
        s.level0, s.level1 = ledger.level0, ledger.level1
        s.money0, s.money1 = ledger.money0, ledger.money1
        for _, z in ipairs(ledger.visited or {}) do s.zonesVisited[#s.zonesVisited + 1] = z end
        s.first, s.last = ledger.first, ledger.last
    end
    -- without a ledger (days before letters existed), fill in from the entries
    local before = #s.levels > 0 and s.levels[1] - 1 or nil
    if before and s.level0 then s.level0 = math.min(s.level0, before) end
    s.level0 = s.level0 or before or minLevel
    if #s.levels > 0 then s.level1 = math.max(s.level1 or 0, s.levels[#s.levels]) end
    s.level1 = s.level1 or s.level0
    for _, z in ipairs(s.firstVisits) do
        local seen = false
        for _, v in ipairs(s.zonesVisited) do if v == z then seen = true end end
        if not seen then s.zonesVisited[#s.zonesVisited + 1] = z end
    end
    s.lastZone = (ledger and ledger.visited and ledger.visited[#ledger.visited]) or lastZone
    if s.money0 and s.money1 then s.moneyChange = s.money1 - s.money0 end
    return s
end

-- Voices ---------------------------------------------------------------------------------
-- Race: who the letter goes to and how it's signed. Class: how the day is told.
local RACE = {
    Human              = { to = "Dear Mother,", sign = "May the Light keep you,", home = "Stormwind" },
    Dwarf              = { to = "To the clan back in Ironforge,", sign = "Stone and steel,", home = "Ironforge" },
    NightElf           = { to = "Beloved sister in Darnassus,", sign = "Under Elune's light, ever yours,", home = "Darnassus" },
    Gnome              = { to = "Dear friends at the Tinkers' Guild,", sign = "Yours in cogs and sprockets,", home = "Gnomeregan" },
    Draenei            = { to = "To the faithful aboard the Exodar,", sign = "May the Naaru guide you,", home = "the Exodar" },
    Worgen             = { to = "To Gilneas, ever unbowed,", sign = "Until the moon rises again,", home = "Gilneas" },
    Pandaren           = { to = "Honoured elders of the Wandering Isle,", sign = "With a full belly and a light heart,", home = "the Wandering Isle" },
    Orc                = { to = "To the Warchief and my clan,", sign = "Lok'tar ogar!", home = "Orgrimmar" },
    Scourge            = { to = "To whoever still reads these,", sign = "Forsaken, never forgotten,", home = "the Undercity" },
    Tauren             = { to = "To my tribe at Thunder Bluff,", sign = "Walk with the Earth Mother,", home = "Thunder Bluff" },
    Troll              = { to = "To de Darkspear, mon,", sign = "Stay away from da voodoo,", home = "the Echo Isles" },
    BloodElf           = { to = "To the court of Silvermoon,", sign = "Glory to the sin'dorei,", home = "Silvermoon" },
    Goblin             = { to = "To the Bilgewater accountants,", sign = "Time is money, friend,", home = "Bilgewater Harbor" },
    Dracthyr           = { to = "To my kin of the Black Dragonflight,", sign = "On wing and in flame,", home = "the Forbidden Reach" },
    Earthen            = { to = "To the keepers of the Ringing Deeps,", sign = "Steadfast as the stone,", home = "Dornogal" },
}
local FACTION = {
    Alliance = { to = "To my friends in Stormwind,", sign = "For the Alliance,", home = "Stormwind" },
    Horde    = { to = "To my kin in Orgrimmar,", sign = "For the Horde!", home = "Orgrimmar" },
    Neutral  = { to = "To whoever finds this letter,", sign = "Yours, from the road,", home = "home" },
}

local CLASS = {
    WARRIOR     = { open = { "My sword arm aches, but my spirit is unbroken.", "Another day of honest steel." },
                    death = "I was beaten down %s, but a warrior always gets back up.", sign = "your shield on the road" },
    PALADIN     = { open = { "By the Light's grace, I write to you once more.", "The Light walked with me today." },
                    death = "Even the Light could not keep me standing %s; I rose again, humbled.", sign = "a humble servant of the Light" },
    HUNTER      = { open = { "My companion and I followed the tracks wherever they led.", "The hunt went well today." },
                    death = "The hunted became the hunter %s, and I paid for it.", sign = "a tracker far from home" },
    ROGUE       = { open = { "Quietly, as ever, I slipped through the day.", "Few saw me today, and fewer will remember." },
                    death = "I was careless %s, and the shadows did not hide me.", sign = "someone you've never met" },
    PRIEST      = { open = { "I prayed at dawn, and the day answered.", "Faith carried me through another day." },
                    death = "My prayers went unanswered %s, if only for a moment.", sign = "in faith" },
    SHAMAN      = { open = { "The elements whispered to me as I travelled.", "Earth, wind and fire were restless today." },
                    death = "The spirits called me close %s, then sent me back.", sign = "who listens to the elements" },
    MAGE        = { open = { "Between my studies, I found time for adventure.", "The arcane hums louder out here than in any library." },
                    death = "A miscalculation %s; I shall correct my formulae.", sign = "a scholar of the arcane" },
    WARLOCK     = { open = { "My demon grew restless, so we set out early.", "The fel whispers were loud today. I ignored most of them." },
                    death = "I was bested %s. My demon has not stopped laughing.", sign = "with a pact well kept" },
    DRUID       = { open = { "The wilds welcomed me today.", "I walked in many shapes, and the land walked with me." },
                    death = "The cycle took me %s, as it takes all things, and returned me.", sign = "a keeper of the Dream" },
    MONK        = { open = { "With a calm mind and a steady breath, I began the day.", "Balance, as ever, was the lesson of the day." },
                    death = "I lost my balance %s. A lesson, not a defeat.", sign = "on the path of harmony" },
    DEATHKNIGHT = { open = { "The cold in my bones stirred as I rode out.", "Another day; the runeblade hungers still." },
                    death = "Death found me %s. We are old acquaintances.", sign = "who has died before" },
    DEMONHUNTER = { open = { "My spectral sight burned with the day's dangers.", "I hunted what others fear to name." },
                    death = "I fell %s. The demons within were not pleased.", sign = "who sacrificed everything" },
    EVOKER      = { open = { "On wing and flame, I crossed the land.", "The dragonflight's blood ran warm today." },
                    death = "Even dragons fall: I did, %s.", sign = "of the dragonflights" },
}
local DEFAULT_CLASS = { open = { "Another day on the road.", "I have much to tell you." },
                        death = "I fell %s, but I am well now.", sign = "an adventurer" }

local function voice()
    -- (separate calls: "f and f()" would keep only the first return value)
    local raceName, raceFile, className, classFile, faction
    if UnitRace then raceName, raceFile = UnitRace("player") end
    if UnitClass then className, classFile = UnitClass("player") end
    if UnitFactionGroup then faction = UnitFactionGroup("player") end
    local race = RACE[raceFile or ""] or FACTION[faction or ""] or FACTION.Neutral
    return race, CLASS[classFile or ""] or DEFAULT_CLASS, raceName or "", className or ""
end
FC.LetterVoice = voice

local function pick(list, key, salt)
    local h = salt or 0
    for i = 1, #key do h = (h * 31 + key:byte(i)) % 2147483647 end
    return list[(h % #list) + 1]
end

local function listText(items, max)
    max = max or #items
    local shown = {}
    for i = 1, math.min(#items, max) do shown[i] = items[i] end
    local text
    if #shown <= 1 then text = shown[1] or ""
    else text = table.concat(shown, ", ", 1, #shown - 1) .. " and " .. shown[#shown] end
    if #items > max then text = text .. string.format(" (and %d more)", #items - max) end
    return text
end

local MONTHS = { "January", "February", "March", "April", "May", "June", "July",
    "August", "September", "October", "November", "December" }

local function ordinal(n)
    local s = (n % 100 >= 11 and n % 100 <= 13) and "th" or ({ "st", "nd", "rd" })[n % 10] or "th"
    return n .. s
end

local function count(n, one, many) return n == 1 and one or string.format(many, n) end

-- The letter for one day, as plain text (no colour codes).
function FC:ComposeLetter(key)
    local s = self:DayStats(key)
    local race, class, raceName, className = voice()
    local y, m, d = key:match("(%d+)-(%d+)-(%d+)")
    local lines = {}

    lines[#lines + 1] = string.format("%s, the %s of %s %s", s.lastZone or race.home, ordinal(tonumber(d)),
        MONTHS[tonumber(m)] or m, y)
    lines[#lines + 1] = string.format("Day %d of my journey", s.dayNumber or 1)
    lines[#lines + 1] = ""
    lines[#lines + 1] = race.to
    lines[#lines + 1] = ""

    local body = { pick(class.open, key) }
    -- zones you already knew vs. ones you saw for the first time today
    local isNew, known = {}, {}
    for _, z in ipairs(s.firstVisits) do isNew[z] = true end
    for _, z in ipairs(s.zonesVisited) do if not isNew[z] then known[#known + 1] = z end end
    if #known > 0 and #s.firstVisits > 0 then
        body[#body + 1] = "My road led through " .. listText(known, 5)
            .. ", and for the first time I set foot in " .. listText(s.firstVisits, 4) .. "."
    elseif #s.firstVisits > 0 then
        body[#body + 1] = "For the first time I set foot in " .. listText(s.firstVisits, 4) .. "."
    elseif #known > 0 then
        body[#body + 1] = "My road led through " .. listText(known, 5) .. "."
    end
    if s.level0 and s.level1 and s.level1 > s.level0 then
        body[#body + 1] = s.level1 - s.level0 == 1
            and string.format("I grew stronger and reached level %d.", s.level1)
            or string.format("I grew much stronger, from level %d to level %d.", s.level0, s.level1)
    end
    if #s.quests > 0 then
        body[#body + 1] = count(#s.quests, "I answered one call for help", "I answered %d calls for help")
            .. ", among them \"" .. s.quests[1] .. "\"" .. (s.quests[2] and (" and \"" .. s.quests[2] .. "\"") or "") .. "."
    end
    if #s.achievements > 0 then
        body[#body + 1] = "Word of my deeds will spread: " .. listText(s.achievements, 3) .. "."
    end
    if #s.goals > 0 then
        body[#body + 1] = "I kept a promise to myself: " .. listText(s.goals, 3) .. "."
    end
    if #s.deaths > 0 then
        local where = "in " .. s.deaths[1]
        if #s.deaths > 1 then where = where .. string.format(" (%d times in all)", #s.deaths) end
        body[#body + 1] = string.format(class.death, where)
    end
    local craftWork = #s.recipes + #s.crafts + #s.professions
    if craftWork > 0 then
        local bits = {}
        if #s.professions > 0 then bits[#bits + 1] = "honed my craft" end
        if #s.recipes > 0 then bits[#bits + 1] = count(#s.recipes, "learned something new", "learned %d new things") end
        if #s.crafts > 0 then bits[#bits + 1] = "made things with my own hands" end
        body[#body + 1] = "In quieter hours I " .. listText(bits) .. "."
    end
    if s.moneyChange and s.moneyChange ~= 0 then
        body[#body + 1] = s.moneyChange > 0
            and string.format("My purse is %s heavier.", FC.FormatMoney(s.moneyChange))
            or string.format("My purse is %s lighter.", FC.FormatMoney(s.moneyChange))
    end
    if #s.notes > 0 then
        body[#body + 1] = "I wrote this down, so I would not forget: \"" .. s.notes[1] .. "\""
    end
    if s.active and s.active >= 60 then
        body[#body + 1] = "All told, I spent " .. playedText(s.active) .. " on the road."
    end
    if #body == 1 then
        body[#body + 1] = "It was a quiet day, with little to report. Perhaps that is its own kind of blessing."
    end
    lines[#lines + 1] = table.concat(body, " ")
    lines[#lines + 1] = ""
    lines[#lines + 1] = race.sign
    lines[#lines + 1] = UnitName("player") or "?"
    lines[#lines + 1] = (string.format("Level %d %s %s, %s", s.level1 or UnitLevel("player") or 0,
        raceName, className, class.sign):gsub("  +", " "))
    return table.concat(lines, "\n"), s
end

-- The stats of a day as lines of text (the "ledger" under each letter).
function FC:DayStatsLines(s)
    local out = {}
    local function add(label, value) out[#out + 1] = "|cff5a3a12" .. label .. ":|r " .. value end
    add("Day", string.format("%d  (%s)", s.dayNumber or 1, s.key))
    add("Time adventuring", s.active and playedText(s.active) or "not recorded (before letters existed)")
    if s.level0 then add("Level", s.level1 ~= s.level0 and (s.level0 .. " > " .. s.level1) or tostring(s.level0)) end
    if s.money0 then
        add("Gold", string.format("%s > %s (%s%s)", FC.FormatMoney(s.money0), FC.FormatMoney(s.money1),
            (s.moneyChange or 0) >= 0 and "+" or "-", FC.FormatMoney(s.moneyChange)))
    end
    add("Zones visited", #s.zonesVisited > 0 and table.concat(s.zonesVisited, ", ") or "-")
    add("First visits", #s.firstVisits > 0 and table.concat(s.firstVisits, ", ") or "-")
    add("Quests completed", #s.quests .. (#s.quests > 0 and (": " .. table.concat(s.quests, ", ")) or ""))
    add("Deaths", #s.deaths .. (#s.deaths > 0 and (": " .. table.concat(s.deaths, ", ")) or ""))
    add("Achievements", #s.achievements > 0 and table.concat(s.achievements, ", ") or "-")
    add("Goals achieved", #s.goals > 0 and table.concat(s.goals, ", ") or "-")
    add("Recipes learned", tostring(#s.recipes))
    add("Crafting milestones", tostring(#s.crafts))
    add("Profession milestones", #s.professions > 0 and table.concat(s.professions, "; ") or "-")
    add("Notes written", tostring(#s.notes))
    add("Chronicle entries", tostring(s.entries))
    return out
end

-- Letters tab -------------------------------------------------------------------------------
local LIST_W, ROW_H = 160, 24
local view, listContent, dayButtons, letterText, letterContent, scroll = nil, nil, {}, nil, nil, nil
local selectedKey

-- cheap label (no full stats): day number, date, level from the ledger if there is one
local function rowLabel(key, number)
    local m, d = key:match("%d+-(%d+)-(%d+)")
    local ledger = days()[key]
    local lvl = ""
    if ledger and ledger.level0 and ledger.level1 then
        lvl = ledger.level1 ~= ledger.level0 and string.format("  Lv %d>%d", ledger.level0, ledger.level1)
            or ("  Lv " .. ledger.level1)
    end
    return string.format("Day %d  %s/%s%s", number, m, d, lvl)
end

local function refreshView()
    if not view or not view:IsShown() then return end
    local list = FC:JourneyDays()
    local known = false
    for _, k in ipairs(list) do if k == selectedKey then known = true end end
    if not known then selectedKey = list[#list] end
    -- newest first
    for i = 1, math.max(#list, #dayButtons) do
        local number = #list - i + 1
        local key = list[number]
        local b = dayButtons[i]
        if key then
            if not b then
                b = FC:NightButton(listContent, LIST_W - 8, ROW_H - 2)
                b:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
                b:SetScript("OnClick", function(self) selectedKey = self.key; FC:SafeCall(refreshView) end)
                dayButtons[i] = b
            end
            b.key = key
            b:SetText(rowLabel(key, number))
            if key == selectedKey then b:Disable() else b:Enable() end
            b:Show()
        elseif b then
            b:Hide()
        end
    end
    listContent:SetHeight(math.max(1, #list * ROW_H))
    if not selectedKey then
        letterText:SetText("No letters yet. Your first one is being written as you play today.")
        return
    end
    local letter, stats = FC:ComposeLetter(selectedKey)
    local draft = selectedKey == FC.DayKey() and "|cff7a5a32(Still being written: today isn't over yet.)|r\n\n" or ""
    letterText:SetText(draft .. letter .. "\n\n|cff5a3a12~ The day's ledger ~|r\n" .. table.concat(FC:DayStatsLines(stats), "\n"))
    letterContent:SetHeight(math.max(1, letterText:GetStringHeight() + 10))
    scroll:SetVerticalScroll(0)
end

function FC:ShowLetter(key)
    selectedKey = key
    if FC.Toggle then FC:Toggle("letters") end
    refreshView()
end

FC:On("READY", function()
    if not FC.AddWindowTab then return end
    local parent = FC:AddWindowTab("letters", "Letters", {
        show = function() view:Show(); refreshView() end,
        hide = function() if view then view:Hide() end end,
    })
    view = CreateFrame("Frame", nil, parent)
    view:SetPoint("TOPLEFT", 20, -88)
    view:SetPoint("BOTTOMRIGHT", -20, 16)
    view:Hide()

    local listScroll = CreateFrame("ScrollFrame", "ForeverChroniclerLetterList", view, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 0, 0)
    listScroll:SetPoint("BOTTOMLEFT", 0, 0)
    listScroll:SetWidth(LIST_W - 8)
    listContent = CreateFrame("Frame", nil, listScroll)
    listContent:SetSize(LIST_W - 8, 1)
    listScroll:SetScrollChild(listContent)

    local paper = FC:CreateParchment(view)
    paper:SetPoint("TOPLEFT", LIST_W + 22, 0)
    paper:SetPoint("BOTTOMRIGHT", 0, 0)

    scroll = CreateFrame("ScrollFrame", "ForeverChroniclerLetterScroll", view, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", paper, "TOPLEFT", 22, -22)
    scroll:SetPoint("BOTTOMRIGHT", paper, "BOTTOMRIGHT", -40, 22)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(330, 1)
    scroll:SetScrollChild(content)
    letterContent = content
    letterText = content:CreateFontString(nil, "OVERLAY", QuestFont and "QuestFont" or "GameFontHighlight")
    letterText:SetPoint("TOPLEFT", 4, -4)
    letterText:SetWidth(320)
    letterText:SetJustifyH("LEFT")
    letterText:SetJustifyV("TOP")
    letterText:SetTextColor(FC.Theme.ink[1], FC.Theme.ink[2], FC.Theme.ink[3])
    if letterText.SetShadowColor then letterText:SetShadowColor(0, 0, 0, 0) end
    if letterText.SetSpacing then letterText:SetSpacing(3) end
end)
FC:On("ENTRY_ADDED", function() refreshView() end)

FC:Command("letters", "/chron letters - read your daily letters and each day's stats", function()
    FC:Toggle("letters")
end, 17)

FC:Command("letter", "/chron letter [YYYY-MM-DD] - print a day's letter to chat (today if no date)", function(rest)
    local key = rest ~= "" and rest or FC.DayKey()
    if not key:match("^%d%d%d%d%-%d%d%-%d%d$") then return false end
    local letter = FC:ComposeLetter(key)
    for line in (letter .. "\n"):gmatch("(.-)\n") do
        if line ~= "" then FC:Print(line) end
    end
end, 18)

-- for tests
function FC:SelectedLetter() return selectedKey end
function FC:LetterViewText() return letterText and letterText:GetText() end
