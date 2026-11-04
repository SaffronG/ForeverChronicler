test("field encoding round-trips special characters and UTF-8", function()
    local env = setup()
    local FC = env.FC
    local f = { text = "Kill Hogger | 100% ~ fun = yes\nnew line", name = "Zoë", n = 5 }
    local back = FC.DecodeFields(FC.EncodeFields(f))
    eq(back.text, f.text, "text"); eq(back.name, "Zoë", "utf8"); eq(back.n, "5", "number as string")
    ok(not FC.EncodeFields(f):find("|", 1, true), "no raw pipes on the wire")
end)

test("long messages are chunked and reassembled", function()
    local env = setup()
    local FC = env.FC
    local got
    FC:OnComm("TEST", function(fields, sender) got = { fields = fields, sender = sender } end)
    FC:SendComm("TEST", { body = string.rep("abc~|é", 100) }, "PARTY")
    eq(#env.addonMessages, 4, "throttled to 4 per second")
    env.runTickers()
    ok(#env.addonMessages > 4, "rest sent on the next tick")
    eq(FC:PendingCommCount(), 0, "queue drained")
    for _, m in ipairs(env.addonMessages) do ok(#m.msg <= 255, "message within 255 bytes") end
    env.deliver("Friend-Forever")
    eq(got.fields.body, string.rep("abc~|é", 100), "reassembled")
    eq(got.sender, "Friend-Forever", "sender")
end)

test("messages wait while addon messaging is blocked", function()
    local env = setup()
    local FC = env.FC
    env.commsBlocked = true
    FC:SendComm("TEST", { a = 1 }, "PARTY")
    eq(#env.addonMessages, 0, "nothing sent while blocked")
    eq(FC:PendingCommCount(), 1, "queued")
    env.runTickers()
    eq(#env.addonMessages, 0, "still waiting")
    env.commsBlocked = false
    env.runTickers()
    eq(#env.addonMessages, 1, "sent once allowed")
    eq(FC:PendingCommCount(), 0, "queue empty")
end)

test("own messages and malformed messages are ignored", function()
    local env = setup()
    local FC = env.FC
    local count = 0
    FC:OnComm("TEST", function() count = count + 1 end)
    FC:SendComm("TEST", { a = 1 }, "PARTY")
    env.deliver("Chase-Forever")
    eq(count, 0, "own message ignored")
    env.fire("CHAT_MSG_ADDON", "FChron", "garbage", "PARTY", "Friend")
    env.fire("CHAT_MSG_ADDON", "FChron", "1|TEST|ab|1|999|x", "PARTY", "Friend")
    env.fire("CHAT_MSG_ADDON", "OtherAddon", "1|TEST|ab|1|1|a=1", "PARTY", "Friend")
    eq(count, 0, "malformed / oversized / foreign ignored")
end)

test("share a goal with the group; friend accepts", function()
    local env = setup()
    local FC = env.FC
    env.slash("goal level 30")
    FC:SetGoalDescription(1, "Ding together")
    env.slash("share 1")
    ok(env.chatContains("not in a group"), "needs a group")
    env.inGroup = true
    env.slash("share 1")
    eq(env.addonMessages[1].channel, "PARTY", "party channel")
    env.slash("del 1") -- so the "already have it" check doesn't swallow the offer
    env.deliver("Friend-Forever")
    eq(#env.popups, 1, "popup shown")
    eq(env.popups[1].a, "Friend", "from")
    env.acceptPopup()
    local g = FC.db.goals[1]
    eq(g.kind, "level", "kind"); eq(g.target, 30, "target"); eq(g.sharedBy, "Friend", "sharedBy")
    eq(g.description, "Ding together", "description")
    local ack = env.addonMessages[1]
    eq(ack.channel, "WHISPER", "ack whispered"); eq(ack.target, "Friend-Forever", "ack target")
    env.deliver("Friend-Forever")
    ok(env.chatContains("Friend accepted your goal \"Reach level 30\""), "sender told")
end)

test("location goal sharing and whisper to a friend", function()
    local env = setup()
    local FC = env.FC
    env.slash("goal 45.2 63.1")
    env.slash("share 1 Buddy")
    eq(env.addonMessages[1].channel, "WHISPER", "whisper"); eq(env.addonMessages[1].target, "Buddy", "target")
    env.slash("del 1")
    env.deliver("Buddy-Forever"); env.acceptPopup()
    local t = FC.db.goals[1].target
    eq(t.mapID, 1, "map"); eq(t.x, 0.452, "x"); eq(t.armed, false, "not armed")
end)

test("invalid or unwanted shared goals are rejected", function()
    local env = setup()
    local FC = env.FC
    local function offer(fields)
        FC:SendComm("GOAL", fields, "PARTY"); env.deliver("Friend-Forever")
    end
    offer({ kind = "level", text = "x", target = "abc" })
    offer({ kind = "evil", text = "x" })
    offer({ kind = "location", text = "x", map = 1, x = 5, y = 0 })
    offer({ kind = "free", text = string.rep("a", 300) })
    eq(#env.popups, 0, "all invalid rejected")
    FC.db.settings.acceptShares = false
    offer({ kind = "free", text = "fine" })
    eq(#env.popups, 0, "shares turned off")
    FC.db.settings.acceptShares = true
    for i = 1, 8 do offer({ kind = "free", text = "spam" .. i }) end
    ok(#FC:PendingOffers() <= 5, "pending offers capped")
end)
