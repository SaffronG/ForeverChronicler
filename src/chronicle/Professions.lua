-- Forever Chronicler: professions, crafting and recipes
-- Records profession milestones in the chronicle (new profession, skill-ups in
-- steps of 25, max skill reached), recipes you learn and your first craft of each
-- item. Counts known recipes per profession when you open its window, so the
-- Professions tab can show % completion bars, and the Journey tab can graph
-- recipes and crafts over time.
--
-- Saved data:
--   db.professions[skillLineID] = { name, skill, maxSkill, learned, total, scanned, crafts, first, gone }
--   db.crafted[itemID] = number of times crafted
--   db.stats.recipes / db.stats.crafts = counters (kept even if the entry type is off)

local _, FC = ...

local SKILL_STEP = 25         -- write a skill entry every 25 points
local RECIPE_BATCH_DELAY = 2  -- seconds to collect NEW_RECIPE_LEARNED bursts (trainers)
local RECIPE_BATCH_MAX = 3    -- more than this in one burst -> one summary entry
local SCAN_DELAY = 1          -- debounce for recipe list scans
local CRAFT_MILESTONES = { 10, 50, 100, 250, 500 } -- then every 1000

local function db() return FC.db end

local function profs()
    local d = db()
    d.professions = d.professions or {}
    return d.professions
end

-- Register an event only if the client knows it (an unknown event would error at load).
local function tryEvent(event, fn)
    if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then return false end
    return (pcall(FC.RegisterEvent, FC, event, fn))
end

-- Profession skill (GetProfessions) -------------------------------------------------------
local quietUntil -- first scan on a character records silently (no "learned X" spam)

-- detectGone: only on SKILL_LINES_CHANGED, never right after login, when the
-- profession list may not be loaded yet (that would log false "Unlearned" entries).
function FC:ScanProfessions(detectGone)
    if not (GetProfessions and GetProfessionInfo) then return end
    local list = profs()
    local quiet = quietUntil and GetTime() < quietUntil
    local seen, seenAny = {}, false
    -- prof1, prof2, archaeology, fishing, cooking: any of them can be nil, so no ipairs
    local slots = { GetProfessions() }
    for slot = 1, 5 do
        local index = slots[slot]
        local name, _, rank, maxRank, _, _, skillLine
        if index then name, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(index) end
        if name and skillLine then
            seen[skillLine], seenAny = true, true
            local p = list[skillLine]
            if not p or p.gone then
                p = p or { first = time(), crafts = 0 }
                p.gone = nil
                p.name, p.skill, p.maxSkill = name, rank or 0, maxRank or 0
                list[skillLine] = p
                if not quiet then
                    FC:AddEntry("profession", string.format("|cffff9933Learned a new profession: %s.|r", name))
                end
            else
                local old = p.skill or 0
                p.name, p.skill, p.maxSkill = name, rank or 0, maxRank or 0
                if not quiet and p.skill > old then
                    if p.maxSkill > 0 and p.skill >= p.maxSkill then
                        FC:AddEntry("profession", string.format("|cffff9933%s skill maxed out at %d!|r", name, p.skill))
                    elseif math.floor(p.skill / SKILL_STEP) > math.floor(old / SKILL_STEP) then
                        FC:AddEntry("profession", string.format("|cffff9933%s skill reached %d.|r", name, p.skill))
                    end
                end
            end
        end
    end
    if detectGone and seenAny and not quiet then
        for id, p in pairs(list) do
            if not seen[id] and not p.gone then
                p.gone = time()
                FC:AddEntry("profession", string.format("|cffff9933Unlearned %s.|r", p.name or "a profession"))
            end
        end
    end
    db().professionsBaseline = true
    FC:Fire("PROFESSIONS_CHANGED")
end

FC:On("READY", function()
    if not db().professionsBaseline then quietUntil = GetTime() + 30 end
end)
FC:RegisterEvent("PLAYER_ENTERING_WORLD", function() FC:ScanProfessions(false) end)
tryEvent("SKILL_LINES_CHANGED", function() FC:ScanProfessions(true) end)

-- Recipe counts (only while your own profession window is open) ---------------------------
local function canScan()
    local T = C_TradeSkillUI
    if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo and T.GetBaseProfessionInfo) then return false end
    if T.IsTradeSkillReady and not T.IsTradeSkillReady() then return false end
    if T.IsTradeSkillLinked and T.IsTradeSkillLinked() then return false end
    if T.IsTradeSkillGuild and T.IsTradeSkillGuild() then return false end
    if T.IsNPCCrafting and T.IsNPCCrafting() then return false end
    return true
end

-- Returns the base profession's saved record for the open window, creating it if needed.
local function openProfession()
    local base = C_TradeSkillUI.GetBaseProfessionInfo()
    local id = base and (base.professionID or base.parentProfessionID)
    if not id or id == 0 then return nil end
    local list = profs()
    local p = list[id]
    if not p then -- same profession recorded under another ID? match by name
        for otherID, other in pairs(list) do
            if other.name and other.name == base.professionName then p, id = other, otherID end
        end
    end
    if not p then
        p = { name = base.professionName, first = time(), crafts = 0 }
        list[id] = p
    end
    p.name = p.name or base.professionName
    return p, id
end

function FC:ScanRecipes()
    if not canScan() then return false end
    local p = openProfession()
    if not p then return false end
    local learned, total = 0, 0
    for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
        local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
        if info and not info.isDummyRecipe and not info.isGatheringRecipe and not info.isRecraft then
            total = total + 1
            if info.learned then learned = learned + 1 end
        end
    end
    if total == 0 then return false end -- list not loaded yet
    local changed = p.learned ~= learned or p.total ~= total
    p.learned, p.total, p.scanned = learned, total, time()
    if changed then
        FC:Fire("PROFESSIONS_CHANGED")
        if FC.TakeSample then FC:TakeSample() end
    end
    return true
end

local scanPending = false
local function scheduleScan()
    if scanPending then return end
    scanPending = true
    C_Timer.After(SCAN_DELAY, function()
        scanPending = false
        FC:SafeCall(FC.ScanRecipes, FC)
    end)
end
tryEvent("TRADE_SKILL_SHOW", scheduleScan)
tryEvent("TRADE_SKILL_LIST_UPDATE", scheduleScan)

-- Learning recipes ------------------------------------------------------------------------
local pending = {}

local function recipeName(recipeID)
    local info = C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(recipeID)
    local name = info and info.name
    if (not name or name == "") and C_Spell and C_Spell.GetSpellName then name = C_Spell.GetSpellName(recipeID) end
    return (name and name ~= "") and name or ("Recipe #" .. tostring(recipeID))
end

-- Profession ID and name for a recipe (base profession, e.g. Tailoring rather than "Khaz Algar Tailoring").
local function recipeProfession(recipeID)
    local T = C_TradeSkillUI
    if not (T and T.GetTradeSkillLineForRecipe) then return nil end
    local tradeSkillID, lineName, parentID = T.GetTradeSkillLineForRecipe(recipeID)
    local id = (parentID and parentID ~= 0) and parentID or tradeSkillID
    local p = id and profs()[id]
    return id, (p and p.name) or lineName
end

local function flushRecipes()
    local batch = pending
    pending = {}
    if #batch == 0 then return end
    if #batch <= RECIPE_BATCH_MAX then
        for _, r in ipairs(batch) do
            if r.rank then
                FC:AddEntry("recipe", string.format("|cff99ccffLearned rank %d of %s.|r", r.rank, r.name))
            else
                FC:AddEntry("recipe", string.format("|cff99ccffLearned recipe: %s%s.|r", r.name,
                    r.profName and (" (" .. r.profName .. ")") or ""))
            end
        end
    else
        -- a trainer visit or a new profession: one line per profession instead of dozens
        local byProf, order = {}, {}
        for _, r in ipairs(batch) do
            local key = r.profName or "?"
            if not byProf[key] then byProf[key] = 0; order[#order + 1] = key end
            byProf[key] = byProf[key] + 1
        end
        for _, key in ipairs(order) do
            FC:AddEntry("recipe", string.format("|cff99ccffLearned %d new %s recipes.|r", byProf[key],
                key ~= "?" and key or "profession"))
        end
    end
    FC:Fire("PROFESSIONS_CHANGED")
    if FC.TakeSample then FC:TakeSample() end
end

tryEvent("NEW_RECIPE_LEARNED", function(recipeID, recipeLevel)
    if type(recipeID) ~= "number" then return end
    local profID, profName = recipeProfession(recipeID)
    local r = { name = recipeName(recipeID), profName = profName }
    if recipeLevel and recipeLevel > 1 then
        r.rank = recipeLevel -- an upgrade of a recipe you know, not a new one
    else
        local s = db().stats
        s.recipes = (s.recipes or 0) + 1
        local p = profID and profs()[profID]
        if p and p.learned and p.total and p.learned < p.total then p.learned = p.learned + 1 end
    end
    pending[#pending + 1] = r
    if #pending == 1 then
        C_Timer.After(RECIPE_BATCH_DELAY, function() FC:SafeCall(flushRecipes) end)
    end
end)

-- Crafting --------------------------------------------------------------------------------
local function itemName(result)
    local name = C_Item and C_Item.GetItemNameByID and result.itemID and C_Item.GetItemNameByID(result.itemID)
    if (not name or name == "") and type(result.hyperlink) == "string" then name = result.hyperlink:match("%[(.-)%]") end
    return (name and name ~= "") and name or ("item #" .. tostring(result.itemID))
end

local function isMilestone(n)
    for _, m in ipairs(CRAFT_MILESTONES) do if n == m then return true end end
    return n >= 1000 and n % 1000 == 0
end

function FC:RecordCraft(result)
    if type(result) ~= "table" or type(result.itemID) ~= "number" then return end
    local d = db()
    d.crafted = d.crafted or {}
    d.stats.crafts = (d.stats.crafts or 0) + 1
    if canScan() then
        local p = openProfession()
        if p then p.crafts = (p.crafts or 0) + 1 end
    end
    local times = (d.crafted[result.itemID] or 0) + 1
    d.crafted[result.itemID] = times
    if times == 1 then
        FC:AddEntry("craft", string.format("|cffcc99ffCrafted %s for the first time.|r", itemName(result)))
    end
    if isMilestone(d.stats.crafts) then
        FC:AddEntry("craft", string.format("|cffcc99ffCrafted %d items so far!|r", d.stats.crafts))
    end
    FC:Fire("PROFESSIONS_CHANGED")
end
tryEvent("TRADE_SKILL_ITEM_CRAFTED_RESULT", function(result) FC:RecordCraft(result) end)

-- Summaries -------------------------------------------------------------------------------
function FC:RecipeCompletion(p)
    if not (p and p.total and p.total > 0 and p.learned) then return nil end
    return p.learned, p.total, p.learned / p.total * 100
end

-- Current professions, sorted by name: { id, name, skill, maxSkill, learned, total, pct, crafts }
function FC:ProfessionRows()
    local rows = {}
    for id, p in pairs(profs()) do
        if not p.gone then
            local learned, total, pct = self:RecipeCompletion(p)
            rows[#rows + 1] = { id = id, name = p.name or "?", skill = p.skill, maxSkill = p.maxSkill,
                learned = learned, total = total, pct = pct, crafts = p.crafts or 0 }
        end
    end
    table.sort(rows, function(a, b) return a.name < b.name end)
    return rows
end

-- Total known recipes across current professions (nil until a profession window was opened).
function FC:KnownRecipes()
    local sum, any = 0, false
    for _, p in pairs(profs()) do
        if not p.gone and p.learned then sum = sum + p.learned; any = true end
    end
    return any and sum or nil
end

local function rowText(r)
    local skill = (r.skill and r.maxSkill and r.maxSkill > 0) and string.format("skill %d/%d", r.skill, r.maxSkill) or "skill ?"
    local recipes = r.pct and string.format("recipes %d/%d (%.0f%%)", r.learned, r.total, r.pct)
        or "recipes: open the profession window to count them"
    return string.format("%s: %s, %s, %d crafted", r.name, skill, recipes, r.crafts)
end

FC:Command({ "professions", "prof" }, "/chron professions - open your professions: skill, recipe completion and crafts", function(rest)
    if rest == "list" or not FC.AddWindowTab then
        local rows = FC:ProfessionRows()
        if #rows == 0 then FC:Print("No professions recorded yet.") return end
        for _, r in ipairs(rows) do FC:Print(rowText(r)) end
        return
    end
    FC:Toggle("professions")
end, 16)

-- Professions tab -------------------------------------------------------------------------
local BAR_W, BAR_H, ROW_H, MAX_ROWS = 380, 14, 56, 6
local view, rowFrames, emptyText, footer = nil, {}, nil, nil

local function bar(parent, y, color)
    local bg = parent:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(0, 0, 0, 0.4)
    bg:SetSize(BAR_W, BAR_H)
    bg:SetPoint("TOPLEFT", 150, y)
    local fill = parent:CreateTexture(nil, "ARTWORK")
    fill:SetColorTexture(color[1], color[2], color[3], 0.85)
    fill:SetHeight(BAR_H)
    fill:SetPoint("TOPLEFT", bg, "TOPLEFT")
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER", bg, "CENTER")
    return { bg = bg, fill = fill, text = text }
end

local function setBar(b, frac, text)
    frac = math.max(0, math.min(1, frac or 0))
    if frac > 0 then b.fill:SetWidth(BAR_W * frac); b.fill:Show() else b.fill:Hide() end
    b.text:SetText(text)
end

local function makeRow(i)
    local r = CreateFrame("Frame", nil, view)
    r:SetSize(BAR_W + 160, ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.name:SetPoint("TOPLEFT", 0, -2)
    r.name:SetWidth(140)
    r.name:SetJustifyH("LEFT")
    r.crafts = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.crafts:SetPoint("TOPLEFT", 0, -20)
    r.skill = bar(r, 0, { 0.9, 0.6, 0.2 })
    r.recipes = bar(r, -20, { 0.3, 0.7, 1.0 })
    rowFrames[i] = r
    return r
end

-- Bar data for the view (also used by tests): { name, skillFrac, skillText, recipeFrac, recipeText, craftsText }
function FC:ProfessionBars()
    local out = {}
    for _, r in ipairs(self:ProfessionRows()) do
        local hasSkill = r.skill and r.maxSkill and r.maxSkill > 0
        out[#out + 1] = {
            name = r.name,
            skillFrac = hasSkill and r.skill / r.maxSkill or 0,
            skillText = hasSkill and string.format("Skill %d / %d", r.skill, r.maxSkill) or "Skill ?",
            recipeFrac = r.pct and r.pct / 100 or 0,
            recipeText = r.pct and string.format("Recipes %d / %d  (%.0f%%)", r.learned, r.total, r.pct)
                or "Open this profession's window to count recipes",
            craftsText = string.format("%d crafted", r.crafts),
        }
    end
    return out
end

local function countCrafted()
    local n = 0
    for _ in pairs(db().crafted or {}) do n = n + 1 end
    return n
end

local function refreshView()
    if not view or not view:IsShown() then return end
    local bars = FC:ProfessionBars()
    for i = 1, math.max(#bars, #rowFrames) do
        local data = bars[i]
        local r = rowFrames[i]
        if data and i <= MAX_ROWS then
            r = r or makeRow(i)
            r.name:SetText(data.name)
            r.crafts:SetText(data.craftsText)
            setBar(r.skill, data.skillFrac, data.skillText)
            setBar(r.recipes, data.recipeFrac, data.recipeText)
            r:Show()
        elseif r then
            r:Hide()
        end
    end
    if #bars == 0 then emptyText:Show() else emptyText:Hide() end
    local s = db().stats
    footer:SetText(string.format("|cffffd100Recipes learned while chronicling|r %d   |cffffd100Items crafted|r %d   |cffffd100Different items|r %d",
        s.recipes or 0, s.crafts or 0, countCrafted()))
end

FC:On("READY", function()
    if not FC.AddWindowTab then return end
    local parent = FC:AddWindowTab("professions", "Professions", {
        show = function() view:Show(); refreshView() end,
        hide = function() if view then view:Hide() end end,
    })
    view = CreateFrame("Frame", nil, parent)
    view:SetPoint("TOPLEFT", 20, -88)
    view:SetPoint("BOTTOMRIGHT", -20, 16)
    view:Hide()
    emptyText = view:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("TOP", 0, -60)
    emptyText:SetText("No professions yet. Learn one from a trainer and it shows up here.")
    footer = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footer:SetPoint("BOTTOMLEFT", 0, 4)
    footer:SetJustifyH("LEFT")
end)
FC:On("PROFESSIONS_CHANGED", function() refreshView() end)

-- for tests
function FC:ProfessionRowCount() local n = 0 for _, r in ipairs(rowFrames) do if r:IsShown() then n = n + 1 end end return n end
