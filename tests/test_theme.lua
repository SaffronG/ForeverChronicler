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
