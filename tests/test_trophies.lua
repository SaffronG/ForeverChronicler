-- Notable loot, bosses and rare foes (src/chronicle/Trophies.lua)

local function entriesOf(FC, kind)
    local out = {}
    for _, e in ipairs(FC.db.entries) do if e.kind == kind then out[#out + 1] = e.text end end
    return out
end

local function has(list, s)
    for _, t in ipairs(list) do if t:find(s, 1, true) then return true end end
    return false
end

local function link(id, name, quality)
    return string.format("|cnIQ%d:|Hitem:%d::::::::80:::::|h[%s]|h|r", quality, id, name)
end

test("notable loot: first time per item, quality threshold, old-style links", function()
    local env = setup()
    local FC = env.FC
    env.fire("CHAT_MSG_LOOT", "You receive loot: " .. link(100, "Linen Cloth", 1) .. "x3.")
    env.fire("CHAT_MSG_LOOT", "You receive loot: " .. link(101, "Green Sword", 2) .. ".")
    eq(#entriesOf(FC, "loot"), 0, "common and uncommon are below the default (Rare)")
    env.fire("CHAT_MSG_LOOT", "You receive loot: " .. link(102, "Blue Helm", 3) .. ".")
    ok(has(entriesOf(FC, "loot"), "Found a rare [Blue Helm]."), "rare entry")
    env.fire("CHAT_MSG_LOOT", "You receive loot: " .. link(102, "Blue Helm", 3) .. ".")
    eq(#entriesOf(FC, "loot"), 1, "only the first time")
    eq(FC.db.loot[102].n, 2, "repeats counted")
    -- old-style colour link, quality from the colour
    env.fire("CHAT_MSG_LOOT", "You receive item: |cffa335ee|Hitem:103::::|h[Purple Ring]|h|r.")
    ok(has(entriesOf(FC, "loot"), "Claimed the epic [Purple Ring]."), "epic from colour code")
    -- quality from C_Item wins over the link
    env.itemQuality = { [104] = 5 }
    env.fire("CHAT_MSG_LOOT", "You receive loot: " .. link(104, "Old Axe", 2) .. ".")
    ok(has(entriesOf(FC, "loot"), "Claimed the legendary [Old Axe]."), "quality from C_Item")
    eq(FC.db.stats.notableLoot, 3, "counter")
    -- other players' loot and secret messages are ignored
    env.fire("CHAT_MSG_LOOT", "Buddy receives loot: " .. link(105, "Their Epic", 4) .. ".")
    local secretText = "You receive loot: " .. link(106, "Hidden", 4) .. "."
    env.secret[secretText] = true
    env.fire("CHAT_MSG_LOOT", secretText)
    eq(#entriesOf(FC, "loot"), 3, "ignored")
    -- the threshold is a setting
    FC.db.settings.lootQuality = 2
    env.fire("CHAT_MSG_LOOT", "You receive loot: " .. link(107, "Green Boots", 2) .. ".")
    ok(has(entriesOf(FC, "loot"), "Found an uncommon [Green Boots]."), "uncommon now counts")
    FC.db.settings.chronicle.loot = false
    env.fire("CHAT_MSG_LOOT", "You receive loot: " .. link(108, "Quiet Epic", 4) .. ".")
    eq(#entriesOf(FC, "loot"), 4, "entry type off")
    ok(FC.db.loot[108], "still recorded")
end)

test("bosses: first kill per difficulty gets an entry, loot is credited to the boss", function()
    local clock = 1000000
    local env = setup({ time = function() return clock end })
    local FC = env.FC
    env.player.zone = "Molten Core"
    env.fire("ENCOUNTER_END", 663, "Lucifron", 14, 20, 0)
    eq(#entriesOf(FC, "slay"), 0, "a wipe isn't a kill")
    env.fire("ENCOUNTER_END", 663, "Lucifron", 14, 20, 1)
    env.fire("BOSS_KILL", 663, "Lucifron") -- fires too; must not double count
    ok(has(entriesOf(FC, "slay"), "Defeated Lucifron (Normal, 20 players) in Molten Core!"), "boss entry")
    eq(FC.db.stats.bosses, 1, "counted once")
    env.fire("CHAT_MSG_LOOT", "You receive loot: " .. link(200, "Flamewaker Belt", 4) .. ".")
    ok(has(entriesOf(FC, "loot"), "[Flamewaker Belt] from Lucifron."), "loot credited")
    -- personal loot event for someone else is ignored
    env.fire("ENCOUNTER_LOOT_RECEIVED", 663, 201, link(201, "Not Mine", 4), 1, "Buddy-Forever")
    ok(not FC.db.loot[201], "not mine")
    env.fire("ENCOUNTER_LOOT_RECEIVED", 663, 202, link(202, "Mine", 4), 1, "Chase-Forever")
    ok(FC.db.loot[202], "mine")
    -- same boss on heroic is a new first kill; normal again is only counted
    clock = clock + 3600
    env.fire("ENCOUNTER_END", 663, "Lucifron", 15, 20, 1)
    ok(has(entriesOf(FC, "slay"), "Defeated Lucifron (Heroic, 20 players)"), "heroic first kill")
    clock = clock + 3600
    env.fire("ENCOUNTER_END", 663, "Lucifron", 14, 20, 1)
    eq(FC.db.slain["e663:14"].n, 2, "repeat kill counted")
    eq(#entriesOf(FC, "slay"), 2, "repeat kill has no entry")
    eq(#FC:SlainList(), 2, "two records")
end)

test("rare monsters: slain when your target dies, or when you loot its corpse", function()
    local env = setup()
    local FC = env.FC
    local guid = "Creature-0-1-2-3-5000-0001"
    env.target = { guid = guid, name = "Mor'Ladim", class = "rareelite" }
    env.fire("PLAYER_TARGET_CHANGED")
    env.target.dead = true
    env.fire("UNIT_HEALTH", "target")
    ok(has(entriesOf(FC, "slay"), "Slew Mor'Ladim, a rare foe, in Elwynn Forest."), "rare entry")
    eq(FC.db.slain.n5000.n, 1, "keyed by NPC id")
    env.fire("UNIT_FLAGS", "target")
    eq(FC.db.stats.rares, 1, "not counted twice")

    -- someone else's kill (tap denied) doesn't count
    local other = "Creature-0-1-2-3-5001-0002"
    env.target = { guid = other, name = "Taken Rare", class = "rare" }
    env.fire("PLAYER_TARGET_CHANGED")
    env.target.dead, env.target.tapDenied = true, true
    env.fire("UNIT_HEALTH", "target")
    eq(FC.db.stats.rares, 1, "tap denied")

    -- target cleared before it died; looting its corpse proves the kill
    local wb = "Creature-0-1-2-3-6109-0003"
    env.target = { guid = wb, name = "Azuregos", class = "worldboss" }
    env.fire("PLAYER_TARGET_CHANGED")
    env.target = nil
    env.fire("PLAYER_TARGET_CHANGED")
    env.lootSources = { wb }
    env.fire("LOOT_OPENED")
    ok(has(entriesOf(FC, "slay"), "Slew the world boss Azuregos"), "world boss via loot")

    -- normal and elite monsters are ignored
    env.target = { guid = "Creature-0-1-2-3-7000-0004", name = "Wolf", class = "elite" }
    env.fire("PLAYER_TARGET_CHANGED"); env.target.dead = true; env.fire("UNIT_HEALTH", "target")
    eq(FC.db.stats.rares, 2, "elites aren't rares")
    env.slash("trophies")
    ok(env.chatContains("Bosses defeated: 0   Rare foes slain: 2"), "trophies command")
end)

test("trophies appear in the day's letter and stats, and survive export/import", function()
    local env = setup()
    local FC = env.FC
    env.fire("ENCOUNTER_END", 1, "Hogger", 1, 5, 1)
    env.fire("CHAT_MSG_LOOT", "You receive loot: " .. link(300, "Hogger's Claw", 3) .. ".")
    local letter, stats = FC:ComposeLetter(FC.DayKey())
    eq(stats.slain[1], "Hogger", "slain parsed from the entry")
    eq(stats.loot[1], "[Hogger's Claw]", "loot parsed")
    ok(letter:find("I stood against mighty foes and prevailed: Hogger.", 1, true), "letter sentence")
    ok(letter:find("Among the spoils I found [Hogger's Claw].", 1, true), "loot sentence")
    local lines = table.concat(FC:DayStatsLines(stats), "\n")
    ok(lines:find("Bosses and rare foes slain:|r Hogger", 1, true), "stats line")

    local str = FC:ExportString()
    local other = setup({ name = "Alt" })
    local ok2 = other.FC:ImportString(str, "merge")
    ok(ok2, "import ok")
    eq(other.FC.db.loot[300].q, 3, "loot imported")
    eq(other.FC.db.slain["e1:1"].name, "Hogger", "slain imported")
    eq(other.FC.db.stats.bosses, 1, "counter imported")
end)

test("import drops malformed loot and slain records", function()
    local env = setup()
    local FC = env.FC
    FC.db.loot = { [1] = { n = 1, q = 4 }, [2] = { n = "x", q = 4 }, bad = { n = 1, q = 4 }, [3] = { n = 1, q = 99 } }
    FC.db.slain = { ["e1:1"] = { name = "Ok", kind = "boss", n = 1 }, ["zzz"] = { name = "Bad", kind = "boss", n = 1 },
        ["n5"] = { name = "Bad kind", kind = "dragon", n = 1 }, ["n6"] = { name = 5, kind = "rare", n = 1 } }
    local str = FC:ExportString()
    local other = setup({ name = "Alt" })
    other.FC:ImportString(str, "replace")
    local n = 0
    for _ in pairs(other.FC.db.loot) do n = n + 1 end
    eq(n, 1, "one valid loot record")
    n = 0
    for _ in pairs(other.FC.db.slain) do n = n + 1 end
    eq(n, 1, "one valid slain record")
end)
