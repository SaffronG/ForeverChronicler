-- Night elf window and parchment chronicle (src/ui/Theme.lua)

local function luma(hex)
    local r, g, b = tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
end

test("ink keeps event colours but makes them readable on parchment", function()
    local env = setup()
    local Ink = env.FC.Ink
    -- yellow (quest), green (level), light blue (zone): darkened, hue kept
    for _, hex in ipairs({ "ffff00", "00ff00", "66ccff", "ffcc00", "ff80ff" }) do
        local out = Ink("|cff" .. hex .. "Text|r")
        local newHex = out:match("^|cff(%x%x%x%x%x%x)Text|r$")
        ok(newHex, "format kept for " .. hex)
        ok(luma(newHex) <= 0.37, hex .. " dark enough: " .. newHex)
        -- strongest channel stays the strongest (same hue family)
        local function maxChannel(h)
            local c = { tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16) }
            local best = 1
            for i = 2, 3 do if c[i] > c[best] then best = i end end
            return best
        end
        eq(maxChannel(newHex), maxChannel(hex), "hue kept for " .. hex)
    end
    -- a colour that's already dark enough is unchanged
    eq(Ink("|cffaa2200x|r"), "|cffaa2200x|r", "dark red unchanged")
    -- greys (dates, levels, notes) become brown ink
    local r, g, b = Ink("|cff888888d|r"):match("|cff(%x%x)(%x%x)(%x%x)")
    ok(r and tonumber(r, 16) > tonumber(b, 16), "grey turned brown")
    ok(luma(r .. g .. b) <= 0.37, "grey ink dark enough")
    eq(Ink("no colours"), "no colours", "plain text untouched")
end)

test("chronicle page shows the parchment with inked entries; other tabs hide it", function()
    local env = setup()
    local FC = env.FC
    env.player.level = 11; env.fire("PLAYER_LEVEL_UP", 11)
    env.slash("")
    ok(FC.windowParchment:IsShown(), "parchment on the chronicle tab")
    eq(FC.db.entries[#FC.db.entries].text:find("|cff00ff00", 1, true) ~= nil, true, "saved text keeps its original colour")
    env.slash("goals")
    FC:Toggle("goals")
    ok(not FC.windowParchment:IsShown(), "hidden on the goals tab")
    FC:Toggle("journey")
    ok(not FC.windowParchment:IsShown(), "hidden on the journey tab")
    FC:Toggle("chronicle")
    ok(FC.windowParchment:IsShown(), "back on the chronicle tab")
    eq(#FC.db.errorLog, 0, "no errors")
end)

test("night buttons route their text and work without backdrop support", function()
    local env = setup()
    local b = env.FC:NightButton(UIParent, 60, 20, "Done")
    eq(b:GetText(), "Done", "label")
    b:SetText("Reopen")
    eq(b:GetText(), "Reopen", "relabelled")
    ok(env.FC.window.stars and #env.FC.window.stars > 0, "stars drawn")
end)

test("themes: swap between Night Elf, Alliance, Horde and Blood Elf", function()
    local env = setup()
    local FC = env.FC
    eq(FC.currentTheme, "nightelf", "night elf by default")
    local win = FC.window
    ok(win.moon:IsShown() and not win.emblem:IsShown() and not win.sun:IsShown(), "night elf: moon, no crest, no sun")
    local titleRef, accentRef = FC.Theme.title, FC.Theme.accent
    local neAccent = accentRef[1]

    env.slash("theme horde")
    eq(FC.currentTheme, "horde", "switched")
    eq(FC.db.settings.theme, "horde", "remembered")
    ok(win.emblem:IsShown() and not win.moon:IsShown(), "horde crest, no moon")
    ok(win.stars[1]:IsShown(), "embers")
    ok(FC.Theme.title == titleRef and FC.Theme.accent == accentRef, "colour tables are updated in place")
    ok(accentRef[1] ~= neAccent, "accent colour changed")

    env.slash("theme Blood Elf")
    eq(FC.currentTheme, "bloodelf", "by display name")
    ok(win.sun:IsShown() and not win.emblem:IsShown(), "blood elf sun")
    env.slash("theme alliance")
    ok(win.emblem:IsShown() and not win.stars[1]:IsShown(), "alliance crest, no stars")
    env.slash("theme dark elf")
    eq(FC.currentTheme, "nightelf", "'dark elf' is the night elf theme")

    env.chat = {}
    env.slash("theme pirate")
    ok(env.chatContains("Usage: /chron theme"), "unknown theme shows usage")
    eq(FC.currentTheme, "nightelf", "unchanged")
    env.slash("theme")
    ok(env.chatContains("Night Elf (current)"), "lists themes")

    -- buttons and panels repaint without errors, tabs keep their selected state
    env.slash("")
    FC:Toggle("goals")
    env.slash("theme horde")
    eq(#FC.db.errorLog, 0, "no errors while repainting")
end)

test("the saved theme is applied on login, and the options dropdown lists all four", function()
    local env = setup({ savedDB = { settings = { theme = "bloodelf" } } })
    eq(env.FC.currentTheme, "bloodelf", "saved theme applied")
    local opts = env.dropdowns and env.dropdowns.ForeverChronicler_Theme
    ok(opts, "dropdown registered")
    eq(#opts, 4, "four themes")
    eq(opts[1].label, "Night Elf", "labels")
    -- the options page changes the saved value, then tells everyone
    env.FC.db.settings.theme = "alliance"
    env.FC:Fire("SETTINGS_CHANGED", "ForeverChronicler_Theme")
    eq(env.FC.currentTheme, "alliance", "applied from the options page")
    local bad = setup({ savedDB = { settings = { theme = "nope" } } })
    eq(bad.FC.currentTheme, "nightelf", "unknown saved theme falls back")
    eq(bad.FC.db.settings.theme, "nightelf", "and is repaired")
end)
