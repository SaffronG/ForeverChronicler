test("version comparison", function()
    local env = setup()
    local c = env.FC.CompareVersions
    eq(c("0.2.0", "0.10.0"), -1, "numeric not alphabetical")
    eq(c("1.0", "1.0.0"), 0, "missing parts are zero")
    eq(c("2.0.1", "2.0.0"), 1, "patch")
end)

test("older player is told about a newer version, both ways", function()
    local old = setup({ name = "Chase", version = "0.2.0" })
    local new = setup({ name = "Buddy", version = "0.3.0" })
    old.inGroup = true; new.inGroup = true
    old.fire("GROUP_ROSTER_UPDATE")          -- old announces 0.2.0
    transfer(old, new)                       -- new sees an older version -> whispers back
    eq(new.addonMessages[1].channel, "WHISPER", "newer player answers")
    transfer(new, old)
    ok(old.chatContains("A newer version (0.3.0) is available"), "old player told")
    -- told only once per session
    new.FC:SendComm("VER", { v = "0.3.0" }, "PARTY"); transfer(new, old)
    local count = 0
    for _, l in ipairs(old.chat) do if l:find("newer version", 1, true) then count = count + 1 end end
    eq(count, 1, "only once")
end)

test("junk version messages are ignored", function()
    local env = setup()
    env.FC:SendComm("VER", { v = "<script>" }, "PARTY")
    env.deliver("Friend-Forever")
    eq(#env.addonMessages, 0, "no reply")
end)
