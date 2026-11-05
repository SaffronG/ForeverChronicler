local function populate(env)
    env.slash("note first note")
    env.slash("goal level 20"); env.slash("goal 45.2 63.1"); env.slash("goal Buy a mount")
    env.FC:SetGoalDescription(3, "90 gold | 100% ~ needed")
    env.slash("done 3")
    env.fire("PLAYER_DEAD")
end

test("base64 fallback round-trips all bytes", function()
    local env = setup()
    local all = {}
    for i = 0, 255 do all[#all + 1] = string.char(i) end
    local s = table.concat(all)
    for len = 0, 4 do
        local part = s:sub(1, #s - len)
        eq(env.FC._b64decode(env.FC._b64encode(part)), part, "length " .. #part)
    end
end)

for _, variant in ipairs({ { name = "text format", opts = { noEncoding = true }, prefix = "FC1T:" },
                           { name = "C_EncodingUtil format", opts = {}, prefix = "FC1C:" } }) do
    test("export -> import into an empty character (" .. variant.name .. ")", function()
        local env = setup(variant.opts)
        populate(env)
        local str = env.FC:ExportString()
        eq(str:sub(1, 5), variant.prefix, "prefix")
        local src = env.FC.db

        local env2 = setup(variant.opts)
        local ok_, msg = env2.FC:ImportString(str, "merge")
        ok(ok_, "import ok: " .. tostring(msg))
        local db = env2.FC.db
        local notes = 0
        for _, e in ipairs(db.entries) do if e.text:find("first note", 1, true) then notes = notes + 1 end end
        eq(notes, 1, "note imported once")
        eq(#db.goals, 3, "goals")
        eq(db.goals[2].target.x, 0.452, "location target")
        eq(db.goals[3].description, "90 gold | 100% ~ needed", "description with special characters")
        eq(db.goals[3].done, true, "done flag")
        eq(db.stats.deaths, 1, "stats")
        -- importing the same string again adds nothing
        local before = #db.entries
        env2.FC:ImportString(str, "merge")
        eq(#db.entries, before, "merge is idempotent")
        eq(#db.goals, 3, "goals not duplicated")
    end)
end

test("replace, undo, and bad input", function()
    local env = setup({ noEncoding = true })
    populate(env)
    local str = env.FC:ExportString()
    local env2 = setup({ noEncoding = true })
    env2.slash("goal Something else")
    env2.FC:ImportString(str, "replace")
    eq(#env2.FC.db.goals, 3, "replaced")
    ok(env2.FC:UndoImport(), "undo")
    eq(#env2.FC.db.goals, 1, "back to original")
    eq(env2.FC.db.goals[1].text, "Something else", "original goal")
    local ok1, err1 = env2.FC:ImportString("hello", "merge")
    eq(ok1, false, "rejects junk"); ok(err1:find("doesn't look like"), "message")
    local ok2, err2 = env2.FC:ImportString(str:sub(1, #str - 40), "merge")
    eq(ok2, false, "rejects truncated"); ok(err2:find("copied completely"), "truncation message")
end)

test("hostile import data is cleaned", function()
    local env = setup({ noEncoding = true })
    local FC = env.FC
    -- build a malicious payload with the addon's own serializer via a fake db
    local real = FC.db
    FC.db = { entries = { { t = 1, kind = "note", text = "ok" }, { t = "x", kind = 5 }, "junk" },
        goals = { { kind = "evil", text = "x", created = 1 }, { kind = "level", text = "L", created = 2, target = "notanumber" },
                  { kind = "free", text = string.rep("a", 5000), created = 3 } },
        zones = { [1] = "bad", Westfall = 5 }, stats = { deaths = "lots" } }
    local str = FC:ExportString()
    FC.db = real
    local before = #FC.db.entries
    FC:ImportString(str, "merge")
    eq(#FC.db.entries, before + 1, "only the valid entry")
    eq(#FC.db.goals, 1, "only the valid goal")
    eq(#FC.db.goals[1].text, 200, "text truncated")
    eq(FC.db.zones.Westfall, 5, "valid zone imported")
    eq(FC.db.zones[1], nil, "bad zone key ignored")
    eq(FC.db.stats.deaths, 0, "bad stats ignored")
end)

test("export and import commands open the window", function()
    local env = setup()
    env.slash("export")
    ok(env.chatContains("Export ready"), "export")
    env.slash("import undo")
    ok(env.chatContains("Nothing to undo"), "undo without import")
end)

test("/chron sync asks before reloading", function()
    local env = setup()
    local reloaded = false
    ReloadUI = function() reloaded = true end
    env.slash("sync")
    eq(env.popups[1].which, "FOREVERCHRONICLER_SYNC", "confirmation popup")
    eq(reloaded, false, "not reloaded without confirmation")
    env.acceptPopup()
    eq(reloaded, true, "reloaded after confirming")
end)
