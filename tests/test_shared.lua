-- Two fake players, Chase and Buddy, both online friends of each other.
local clock = { now = 1000000 }
local function now() return clock.now end
local function pair()
    local a = setup({ name = "Chase", level = 10, time = now })
    local b = setup({ name = "Buddy", level = 10, time = now })
    a.friendsOnline.Buddy = true
    b.friendsOnline.Chase = true
    return a, b
end

test("invite, join, each does their part, completes for both", function()
    local a, b = pair()
    a.slash("together Buddy level 12")
    local ga = a.FC.db.goals[1]
    eq(ga.kind, "shared", "kind"); eq(ga.text, "Together: Reach level 12", "text")
    ok(ga.target.members.Buddy.pending, "Buddy pending")
    transfer(a, b)
    eq(#b.popups, 1, "Buddy gets invite popup")
    b.acceptPopup()
    local gb = b.FC.db.goals[1]
    eq(gb.target.id, ga.target.id, "same id")
    eq(gb.sharedBy, "Chase", "sharedBy")
    transfer(b, a)
    eq(ga.target.members.Buddy.pending, nil, "Buddy joined on Chase's side")
    ok(a.chatContains("Buddy joined"), "join message")
    transfer(a, b); transfer(b, a) -- settle

    a.player.level = 12; a.fire("PLAYER_LEVEL_UP", 12)
    ok(ga.target.members.Chase.done, "Chase's part done")
    eq(ga.done, false, "not complete yet")
    transfer(a, b)
    ok(gb.target.members.Chase.done, "Buddy sees Chase done")
    eq(gb.done, false, "Buddy's not done yet")

    b.player.level = 12; b.fire("PLAYER_LEVEL_UP", 12)
    eq(gb.done, true, "complete for Buddy")
    transfer(b, a)
    eq(ga.done, true, "complete for Chase")
    ok(a.chatContains("Achieved together with Buddy"), "together message")
    -- no endless back-and-forth
    for _ = 1, 3 do transfer(a, b); transfer(b, a) end
    eq(#a.addonMessages + #b.addonMessages, 0, "conversation settles")
end)

test("progress made while a friend is offline is synced later", function()
    local a, b = pair()
    a.slash("together Buddy Kill Hogger")
    transfer(a, b); b.acceptPopup(); transfer(b, a); transfer(a, b); transfer(b, a)
    a.friendsOnline.Buddy = false
    clock.now = clock.now + 600 -- "seen recently" expires after 5 minutes
    a.slash("done 1") -- free goal: tick off my part
    eq(#a.addonMessages, 0, "nothing sent while Buddy offline")
    ok(a.FC.db.goals[1].target.unsynced.Buddy, "remembered for later")
    a.friendsOnline.Buddy = true
    a.fire("FRIENDLIST_UPDATE")
    eq(#a.addonMessages, 1, "sent when Buddy comes online")
    transfer(a, b)
    ok(b.FC.db.goals[1].target.members.Chase.done, "Buddy got the update")
    b.slash("done 1")
    eq(b.FC.db.goals[1].done, true, "complete for Buddy")
end)

test("location goals can't be together goals; non-members can't update", function()
    local a, b = pair()
    a.slash("together Buddy here")
    ok(a.chatContains("Location goals can't be done together yet"), "refused")
    eq(#a.FC.db.goals, 0, "no goal")
    a.slash("together Buddy level 30")
    transfer(a, b); b.acceptPopup(); transfer(b, a)
    -- a stranger tries to mark Chase's goal complete
    local stranger = setup({ name = "Mallory" })
    stranger.FC:SendComm("SGSYNC", { id = a.FC.db.goals[1].target.id, text = "x", ikind = "level", itarget = "30",
        members = "Mallory:Mallory-Forever:5:0;Chase:Chase-Forever:5:0;Buddy:Buddy-Forever:5:0" }, "WHISPER", "Chase")
    transfer(stranger, a)
    eq(a.FC.db.goals[1].done, false, "ignored")
    eq(a.FC.db.goals[1].target.members.Mallory, nil, "stranger not added")
end)

test("a member can't mark someone else's part done for them, and it can't loop", function()
    local a, b = pair()
    a.slash("together Buddy level 30")
    transfer(a, b); b.acceptPopup(); transfer(b, a); transfer(a, b); transfer(b, a)
    local id = a.FC.db.goals[1].target.id
    b.FC:SendComm("SGSYNC", { id = id, text = "x", ikind = "level", itarget = "30",
        members = "Chase:Chase-Forever:5:0;Buddy:Buddy-Forever:0:0" }, "WHISPER", "Chase")
    transfer(b, a)
    eq(a.FC.db.goals[1].target.members.Chase.done, nil, "my own part is only set by me")
    for _ = 1, 3 do transfer(a, b); transfer(b, a) end
    eq(#a.addonMessages + #b.addonMessages, 0, "no ping-pong")
end)

test("leaving a shared goal", function()
    local a, b = pair()
    a.slash("together Buddy level 30")
    transfer(a, b); b.acceptPopup(); transfer(b, a); transfer(a, b); transfer(b, a)
    b.slash("del 1")
    transfer(b, a)
    eq(a.FC.db.goals[1].target.members.Buddy, nil, "Buddy removed")
    ok(a.chatContains("Buddy left"), "told")
end)

test("shared goals survive export/import validation", function()
    local a, b = pair()
    a.slash("together Buddy level 30")
    local str = a.FC:ExportString()
    local c = setup({ name = "Chase" })
    c.FC:ImportString(str, "merge")
    local g = c.FC.db.goals[1]
    eq(g.kind, "shared", "kind"); eq(g.target.inner.target, 30, "inner target")
end)
