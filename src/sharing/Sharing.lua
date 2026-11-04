-- Forever Chronicaller: share goals with your group (or whisper them to a friend)
--   * "Share" button in the goal log, or /chron share <n> [name]
--   * Receivers get a popup: "<name> shared a goal with you: ... Add it?"
--   * Accepting adds a copy of the goal and tells the sender.
-- Both players need the addon. Shared copies are independent goals; goals you
-- complete *together* are handled by SharedGoals.lua.

local _, FC = ...

local MAX_TEXT = 200
local MAX_DESC = 500
local MAX_PENDING = 5
local SHAREABLE = { free = true, level = true, zone = true, quest = true, location = true }

-- Goal <-> message fields (also used by SharedGoals.lua)
function FC.GoalToFields(g)
    local f = { kind = g.kind, text = g.text, desc = g.description or "" }
    if g.kind == "location" then
        f.map, f.x, f.y = g.target.mapID, string.format("%.4f", g.target.x), string.format("%.4f", g.target.y)
    elseif g.target ~= nil then
        f.target = g.target
    end
    return f
end

-- Validates untrusted fields. Returns kind, target, text, description or nil.
function FC.FieldsToGoal(f)
    local kind, text = f.kind, f.text
    if not SHAREABLE[kind] or type(text) ~= "string" or text == "" or #text > MAX_TEXT then return nil end
    local target
    if kind == "level" then
        target = tonumber(f.target)
        if not target or target < 1 or target > 1000 or target % 1 ~= 0 then return nil end
    elseif kind == "zone" or kind == "quest" then
        target = f.target
        if type(target) ~= "string" or target == "" or #target > MAX_TEXT then return nil end
    elseif kind == "location" then
        local map, x, y = tonumber(f.map), tonumber(f.x), tonumber(f.y)
        if not (map and x and y) or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
        target = { mapID = map, x = x, y = y, armed = false }
    end
    local desc = type(f.desc) == "string" and f.desc:sub(1, MAX_DESC) or ""
    return kind, target, text, desc ~= "" and desc or nil
end

-- Sending ---------------------------------------------------------------------------
function FC:ShareGoal(index, whisperTarget)
    local g = self.db.goals[index]
    if not g then self:Print("No goal number " .. tostring(index) .. ".") return false end
    if not SHAREABLE[g.kind] then self:Print("This goal can't be shared.") return false end
    local channel, target = self:GroupChannel(), nil
    if whisperTarget and whisperTarget ~= "" then
        channel, target = "WHISPER", whisperTarget
    elseif not channel then
        self:Print("You're not in a group. Use /chron share <n> <name> to send it to a friend.")
        return false
    end
    self:SendComm("GOAL", self.GoalToFields(g), channel, target)
    local blockedNote = (C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown())
        and " (will send when addon messages are allowed again)" or ""
    self:Print(string.format("Shared \"%s\" with %s%s.", g.text, target or "your group", blockedNote))
    return true
end

-- Receiving -------------------------------------------------------------------------
local pending = {}  -- offers waiting for a popup
local showing = false
local showNext

local function accept(offer)
    local g = FC:CreateGoal(offer.kind, offer.target, offer.text)
    g.description = offer.desc
    g.sharedBy = offer.from
    FC:SendComm("GOALACK", { text = offer.text }, "WHISPER", offer.sender)
end

StaticPopupDialogs["FOREVERCHRONICALLER_GOAL_OFFER"] = {
    text = "%s shared a goal with you:\n\n|cffffd100%s|r\n\nAdd it to your goals?",
    button1 = "Accept",
    button2 = "Decline",
    OnAccept = function(_, offer) FC:SafeCall(accept, offer) end,
    OnHide = function() showing = false; C_Timer.After(0.2, function() FC:SafeCall(showNext) end) end,
    timeout = 120,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

showNext = function()
    if showing or not pending[1] then return end
    local offer = table.remove(pending, 1)
    showing = true
    StaticPopup_Show("FOREVERCHRONICALLER_GOAL_OFFER", offer.from, offer.text, offer)
end

FC:OnComm("GOAL", function(fields, sender)
    if FC.db.settings.acceptShares == false then return end
    local kind, target, text, desc = FC.FieldsToGoal(fields)
    if not kind then return end -- invalid / unsupported: ignore silently
    if #pending >= MAX_PENDING then return end
    for _, g in ipairs(FC.db.goals) do
        if not g.done and g.text == text then return end -- already have it
    end
    table.insert(pending, { kind = kind, target = target, text = text, desc = desc,
        sender = sender, from = FC.ShortName(sender) })
    showNext()
end)

FC:OnComm("GOALACK", function(fields, sender)
    if type(fields.text) ~= "string" then return end
    FC:Print(string.format("%s accepted your goal \"%s\".", FC.ShortName(sender), fields.text:sub(1, MAX_TEXT)))
end)

FC:Command("share", "/chron share <n> [name] - share goal n with your group, or whisper it to a friend", function(rest)
    local n, name = rest:match("^(%d+)%s*(%S*)$")
    if not n then return false end
    FC:ShareGoal(tonumber(n), name)
end, 30)

-- for tests
function FC:PendingOffers() return pending end
