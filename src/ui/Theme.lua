-- Forever Chronicler: look and feel
-- Four window themes to swap between (/chron theme, or the options page):
--   Night Elf (default): violet-to-teal night sky, stars, crescent moon, moon-silver borders
--   Alliance:  royal blue, gold borders, the Alliance crest
--   Horde:     blood red to iron black, bronze borders, embers, the Horde crest
--   Blood Elf: crimson and gold, a golden sun, arcane sparkles, fel-green highlights
-- The chronicle page is a parchment scroll in every theme. Everything is built
-- from textures the client always has (plain colours, gradients, a few icons).
-- Atlases are only used if the client says it has them, and missing art never
-- breaks the window.
--
-- How swapping works: FC.Theme holds the current colours. Other files keep
-- references to its colour tables (FC.Theme.title, ...), so a theme change
-- copies the new values into those same tables, then repaints everything that
-- was styled through these helpers and fires THEME_CHANGED for the rest.
--
-- FC.Ink(text) recolours an entry's colour codes for dark-on-parchment reading,
-- so every event keeps its own colour without changing the saved text.

local ADDON, FC = ...

local WHITE = "Interface\\Buttons\\WHITE8X8"
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local PAPER_ATLASES = { "QuestBG-Parchment", "Professions-Recipe-Background" }

local THEMES = {
    nightelf = {
        name = "Night Elf",
        font = "Fonts\\MORPHEUS.TTF",
        colors = {
            night1 = { 0.07, 0.05, 0.17 }, -- top of the sky (violet)
            night2 = { 0.02, 0.08, 0.12 }, -- bottom (deep teal)
            border = { 0.62, 0.70, 0.95 }, -- moon silver
            accent = { 0.45, 0.85, 0.85 }, -- elune teal
            title  = { 0.86, 0.84, 1.00 },
            text   = { 0.80, 0.82, 0.95 },
            dim    = { 0.55, 0.58, 0.72 },
            panel  = { 0.04, 0.05, 0.12, 0.75 },
            shadow = { 0.20, 0.50, 0.60 },
            button = { 0.06, 0.07, 0.17 },
            buttonSelected = { 0.10, 0.24, 0.32 },
        },
        decor = { stars = { 0.85, 0.90, 1.00 }, moon = true },
    },
    alliance = {
        name = "Alliance",
        font = "Fonts\\FRIZQT__.TTF",
        colors = {
            night1 = { 0.10, 0.17, 0.40 }, -- royal blue
            night2 = { 0.02, 0.04, 0.13 }, -- deep navy
            border = { 0.88, 0.72, 0.32 }, -- gold
            accent = { 0.40, 0.65, 1.00 }, -- bright blue
            title  = { 1.00, 0.88, 0.55 },
            text   = { 0.88, 0.89, 0.96 },
            dim    = { 0.60, 0.66, 0.82 },
            panel  = { 0.03, 0.06, 0.17, 0.78 },
            shadow = { 0.10, 0.20, 0.55 },
            button = { 0.05, 0.09, 0.24 },
            buttonSelected = { 0.17, 0.27, 0.55 },
        },
        decor = { emblem = "Interface\\Timer\\Alliance-Logo" },
    },
    horde = {
        name = "Horde",
        font = "Fonts\\SKURRI.TTF",
        colors = {
            night1 = { 0.32, 0.05, 0.03 }, -- blood red
            night2 = { 0.06, 0.03, 0.03 }, -- iron black
            border = { 0.72, 0.50, 0.28 }, -- bronze
            accent = { 0.95, 0.38, 0.15 }, -- fire
            title  = { 1.00, 0.78, 0.50 },
            text   = { 0.93, 0.85, 0.78 },
            dim    = { 0.72, 0.60, 0.52 },
            panel  = { 0.10, 0.03, 0.02, 0.80 },
            shadow = { 0.55, 0.10, 0.05 },
            button = { 0.14, 0.05, 0.04 },
            buttonSelected = { 0.40, 0.11, 0.05 },
        },
        decor = { emblem = "Interface\\Timer\\Horde-Logo", stars = { 1.00, 0.50, 0.20 } }, -- embers
    },
    bloodelf = {
        name = "Blood Elf",
        font = "Fonts\\MORPHEUS.TTF",
        colors = {
            night1 = { 0.45, 0.08, 0.10 }, -- crimson
            night2 = { 0.13, 0.03, 0.05 }, -- dark wine
            border = { 0.96, 0.78, 0.36 }, -- sunwell gold
            accent = { 0.55, 0.95, 0.40 }, -- fel green
            title  = { 1.00, 0.86, 0.45 },
            text   = { 0.96, 0.89, 0.82 },
            dim    = { 0.76, 0.63, 0.56 },
            panel  = { 0.15, 0.03, 0.05, 0.80 },
            shadow = { 0.60, 0.30, 0.05 },
            button = { 0.21, 0.04, 0.06 },
            buttonSelected = { 0.46, 0.13, 0.08 },
        },
        decor = { stars = { 1.00, 0.82, 0.40 }, sun = { 1.00, 0.82, 0.35 } }, -- arcane sparkles, the sun
    },
}
local ORDER = { "nightelf", "alliance", "horde", "bloodelf" }
local ALIASES = {
    ["night elf"] = "nightelf", ["dark elf"] = "nightelf", darkelf = "nightelf", ne = "nightelf", night = "nightelf",
    ["blood elf"] = "bloodelf", be = "bloodelf", blood = "bloodelf", sindorei = "bloodelf",
    a = "alliance", h = "horde",
}
FC.THEMES, FC.THEME_ORDER = THEMES, ORDER

local function copy(c) local t = {} for i, v in ipairs(c) do t[i] = v end return t end

-- The current colours. Parchment, ink and wood are the same in every theme.
local T = {
    paper1 = { 0.80, 0.69, 0.49 }, -- parchment edge (aged)
    paper2 = { 0.95, 0.89, 0.74 }, -- parchment centre
    ink    = { 0.24, 0.15, 0.07 }, -- default text on parchment
    wood1  = { 0.22, 0.13, 0.06 }, -- scroll rollers
    wood2  = { 0.55, 0.36, 0.18 },
}
for k, c in pairs(THEMES.nightelf.colors) do T[k] = copy(c) end
FC.Theme = T
FC.currentTheme = "nightelf"

-- Everything styled here, so a theme change can repaint it.
local styled = { frames = {}, panels = {}, buttons = {}, fonts = {} }

local function hasAtlas(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

-- Vertical/horizontal gradient from c1 to c2 (falls back to the average colour).
local function gradient(tex, orientation, c1, c2, a1, a2)
    tex:SetColorTexture(1, 1, 1, 1)
    local ok = CreateColor and tex.SetGradient and pcall(tex.SetGradient, tex, orientation,
        CreateColor(c1[1], c1[2], c1[3], a1 or 1), CreateColor(c2[1], c2[2], c2[3], a2 or 1))
    if not ok then
        tex:SetColorTexture((c1[1] + c2[1]) / 2, (c1[2] + c2[2]) / 2, (c1[3] + c2[3]) / 2, ((a1 or 1) + (a2 or 1)) / 2)
    end
    return tex
end
FC.ThemeGradient = gradient

local function circle(parent, layer, size, color, sublevel)
    local t = parent:CreateTexture(nil, layer, nil, sublevel)
    t:SetSize(size, size)
    t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    if parent.CreateMaskTexture then
        local m = parent:CreateMaskTexture()
        m:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(t)
        t:AddMaskTexture(m)
    end
    return t
end

local function setFont(fs, fontFile, size)
    if not (fontFile and fs.SetFont) then return end
    -- back to a standard font if this file can't be loaded
    local ok, loaded = pcall(fs.SetFont, fs, fontFile, size or 14, "")
    if (not ok or loaded == false) and GameFontNormalLarge then fs:SetFontObject(GameFontNormalLarge) end
end

-- fontFile "title" means the current theme's title font (changes with the theme).
function FC:StyleFont(fs, size, color, fontFile)
    styled.fonts[#styled.fonts + 1] = { fs = fs, size = size, color = color, font = fontFile }
    setFont(fs, fontFile == "title" and THEMES[FC.currentTheme].font or fontFile, size)
    if color then fs:SetTextColor(color[1], color[2], color[3]) end
end

-- Paint (or repaint) a themed window in the current theme.
local function paintFrame(frame)
    local d = THEMES[FC.currentTheme].decor
    if frame.SetBackdropColor then
        frame:SetBackdropColor(T.night2[1], T.night2[2], T.night2[3], 0.97)
        frame:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
    end
    gradient(frame.sky, "VERTICAL", T.night2, T.night1, 0.97, 0.97) -- VERTICAL goes bottom -> top
    for _, s in ipairs(frame.stars) do
        if d.stars then
            s:SetColorTexture(d.stars[1], d.stars[2], d.stars[3], s.alpha)
            s:Show()
        else
            s:Hide()
        end
    end
    frame.moon:SetShown(d.moon == true)
    frame.moonShadow:SetColorTexture(T.night1[1], T.night1[2], T.night1[3], 1)
    frame.moonShadow:SetShown(d.moon == true)
    if d.sun then
        frame.sun:SetColorTexture(d.sun[1], d.sun[2], d.sun[3], 0.95)
        frame.sunGlow:SetColorTexture(d.sun[1], d.sun[2], d.sun[3], 0.25)
    end
    frame.sun:SetShown(d.sun ~= nil)
    frame.sunGlow:SetShown(d.sun ~= nil)
    if d.emblem then frame.emblem:SetTexture(d.emblem) end
    frame.emblem:SetShown(d.emblem ~= nil)
    gradient(frame.line, "HORIZONTAL", T.accent, T.border, 0.1, 0.6)
end

-- Themed window: backdrop + sky gradient + decorations (stars or embers, moon,
-- sun, crest), shown according to the current theme.
function FC:StyleThemedFrame(frame, insets)
    insets = insets or 11
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = WHITE,
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 16, edgeSize = 32,
            insets = { left = insets, right = insets, top = insets, bottom = insets },
        })
    end
    local sky = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    sky:SetPoint("TOPLEFT", insets, -insets)
    sky:SetPoint("BOTTOMRIGHT", -insets, insets)
    frame.sky = sky

    -- stars / embers / sparkles: fixed pseudo-random positions in the upper part of the window
    local seed = 7
    local function rand() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
    frame.stars = {}
    for i = 1, 40 do
        local s = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
        local size = rand() < 0.2 and 3 or 2
        s:SetSize(size, size)
        s.alpha = 0.25 + rand() * 0.5
        s:SetPoint("TOPLEFT", frame, "TOPLEFT", insets + 4 + rand() * 600, -(insets + 4 + rand() * 70))
        frame.stars[i] = s
    end

    -- crescent moon (a pale disc partly covered by a sky-coloured one)
    frame.moon = circle(frame, "BACKGROUND", 30, { 0.92, 0.94, 1.0, 0.95 }, 3)
    frame.moon:SetPoint("TOPLEFT", 26, -18)
    frame.moonShadow = circle(frame, "BACKGROUND", 28, { 0, 0, 0, 1 }, 4)
    frame.moonShadow:SetPoint("TOPLEFT", frame.moon, "TOPLEFT", 8, -3)
    -- sun (a golden disc with a soft glow)
    frame.sunGlow = circle(frame, "BACKGROUND", 44, { 1, 1, 1, 0.25 }, 3)
    frame.sunGlow:SetPoint("TOPLEFT", 19, -11)
    frame.sun = circle(frame, "BACKGROUND", 28, { 1, 1, 1, 1 }, 4)
    frame.sun:SetPoint("CENTER", frame.sunGlow, "CENTER")
    -- faction crest
    frame.emblem = frame:CreateTexture(nil, "ARTWORK")
    frame.emblem:SetSize(40, 40)
    frame.emblem:SetPoint("TOPLEFT", 20, -12)

    -- a soft glow line under the header
    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", insets + 10, -54)
    line:SetPoint("TOPRIGHT", -(insets + 10), -54)
    frame.line = line

    styled.frames[#styled.frames + 1] = frame
    paintFrame(frame)
end
FC.StyleNightElfFrame = FC.StyleThemedFrame -- name used up to 0.9.0

local function paintPanel(p)
    p.frame:SetBackdropColor(T.panel[1], T.panel[2], T.panel[3], p.alpha or T.panel[4])
    p.frame:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 0.8)
end

-- Dark inner panel (goal details, notes box).
function FC:StylePanel(frame, alpha)
    if not frame.SetBackdrop then return end
    frame:SetBackdrop({
        bgFile = WHITE,
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    local p = { frame = frame, alpha = alpha }
    styled.panels[#styled.panels + 1] = p
    paintPanel(p)
end

-- Themed button. Disabled = "selected" look (tabs, chart series), since the
-- window disables the active tab.
function FC:NightButton(parent, width, height, label)
    local b = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    b:SetSize(width, height)
    if b.SetBackdrop then
        b:SetBackdrop({
            bgFile = WHITE,
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
    end
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("CENTER", 0, 0)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetPoint("TOPLEFT", 2, -2)
    b.hl:SetPoint("BOTTOMRIGHT", -2, 2)

    function b.look(selected)
        b.isSelected = selected
        if b.SetBackdropColor then
            local bg = selected and T.buttonSelected or T.button
            b:SetBackdropColor(bg[1], bg[2], bg[3], selected and 0.95 or 0.9)
            if selected then
                b:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], 1)
            else
                b:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 0.7)
            end
        end
        b.hl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.15)
        local c = selected and { 1, 1, 1 } or T.text
        b.label:SetTextColor(c[1], c[2], c[3])
    end
    b:SetScript("OnEnable", function() b.look(false) end)
    b:SetScript("OnDisable", function() b.look(true) end)
    b.look(false)
    -- route the button's text to our own label
    b.SetText = function(self, text) self.label:SetText(text) end
    b.GetText = function(self) return self.label:GetText() end
    if label then b:SetText(label) end
    styled.buttons[#styled.buttons + 1] = b
    return b
end

-- Switching themes -------------------------------------------------------------------------
-- Accepts an id ("bloodelf"), a display name ("Blood Elf") or an alias ("dark elf").
function FC.ThemeID(name)
    if type(name) ~= "string" then return nil end
    local key = name:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if THEMES[key] then return key end
    if ALIASES[key] then return ALIASES[key] end
    for id, t in pairs(THEMES) do if t.name:lower() == key then return id end end
    return nil
end

function FC:ApplyTheme(name)
    local id = FC.ThemeID(name) or "nightelf"
    FC.currentTheme = id
    for k, c in pairs(THEMES[id].colors) do
        local target = T[k]
        for i = 1, #c do target[i] = c[i] end
        for i = #c + 1, #target do target[i] = nil end
    end
    for _, f in ipairs(styled.frames) do paintFrame(f) end
    for _, p in ipairs(styled.panels) do paintPanel(p) end
    for _, b in ipairs(styled.buttons) do b.look(b.isSelected) end
    for _, f in ipairs(styled.fonts) do
        if f.font == "title" then setFont(f.fs, THEMES[id].font, f.size) end
        if f.color then f.fs:SetTextColor(f.color[1], f.color[2], f.color[3]) end
    end
    FC:Fire("THEME_CHANGED", id)
    return id
end

-- Choose a theme and remember it (per character).
function FC:SetTheme(name)
    local id = FC.ThemeID(name)
    if not id then return nil end
    self.db.settings.theme = id
    return self:ApplyTheme(id)
end

FC:On("READY", function()
    local saved = FC.db.settings.theme
    if not FC.ThemeID(saved) then FC.db.settings.theme = "nightelf" end
    if FC.db.settings.theme ~= FC.currentTheme then FC:ApplyTheme(FC.db.settings.theme) end
end)
FC:On("SETTINGS_CHANGED", function(variable)
    if variable == ADDON .. "_Theme" and FC.db.settings.theme ~= FC.currentTheme then
        FC:ApplyTheme(FC.db.settings.theme)
    end
end)

FC:Command("theme", "/chron theme [nightelf|alliance|horde|bloodelf] - change the window's look", function(rest)
    if rest == "" then
        local names = {}
        for _, id in ipairs(ORDER) do
            names[#names + 1] = (id == FC.currentTheme and "|cff00ff00" .. THEMES[id].name .. " (current)|r") or THEMES[id].name
        end
        FC:Print("Themes: " .. table.concat(names, ", ") .. ". Change with /chron theme <name>.")
        return
    end
    local id = FC:SetTheme(rest)
    if not id then return false end
    FC:Print("Theme: " .. THEMES[id].name .. ".")
end, 89)

-- Parchment scroll: paper with darker aged edges and wooden rollers top and bottom.
function FC:CreateParchment(parent)
    local p = CreateFrame("Frame", nil, parent)
    local paper = p:CreateTexture(nil, "BACKGROUND", nil, 3)
    paper:SetPoint("TOPLEFT", 0, -8)
    paper:SetPoint("BOTTOMRIGHT", 0, 8)
    local atlas
    for _, name in ipairs(PAPER_ATLASES) do if hasAtlas(name) then atlas = name break end end
    if atlas then
        paper:SetAtlas(atlas)
        paper:SetVertexColor(1, 0.97, 0.9)
    else
        gradient(paper, "VERTICAL", T.paper1, T.paper2)
    end
    p.paper, p.atlas = paper, atlas

    -- aged edges: gradients from darker brown to transparent on all four sides
    local function edge(point1, point2, w, h, orient, inward)
        local t = p:CreateTexture(nil, "BACKGROUND", nil, 4)
        t:SetPoint(point1, paper, point1)
        t:SetPoint(point2, paper, point2)
        if w then t:SetWidth(w) else t:SetHeight(h) end
        local dark = { 0.45, 0.30, 0.14 }
        if inward then gradient(t, orient, dark, dark, 0.45, 0) else gradient(t, orient, dark, dark, 0, 0.45) end
    end
    edge("TOPLEFT", "BOTTOMLEFT", 26, nil, "HORIZONTAL", true)
    edge("TOPRIGHT", "BOTTOMRIGHT", 26, nil, "HORIZONTAL", false)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 18, "VERTICAL", true)
    edge("TOPLEFT", "TOPRIGHT", nil, 18, "VERTICAL", false)

    -- rollers: a wooden rod with a light stripe and round knobs on each end
    local function roller(anchor)
        local rod = p:CreateTexture(nil, "ARTWORK", nil, 1)
        rod:SetHeight(16)
        rod:SetPoint(anchor .. "LEFT", p, anchor .. "LEFT", -10, 0)
        rod:SetPoint(anchor .. "RIGHT", p, anchor .. "RIGHT", 10, 0)
        gradient(rod, "VERTICAL", T.wood1, T.wood2)
        local shine = p:CreateTexture(nil, "ARTWORK", nil, 2)
        shine:SetHeight(3)
        shine:SetPoint("LEFT", rod, "LEFT", 0, 3)
        shine:SetPoint("RIGHT", rod, "RIGHT", 0, 3)
        shine:SetColorTexture(1, 0.85, 0.6, 0.25)
        for _, side in ipairs({ "LEFT", "RIGHT" }) do
            local knob = circle(p, "ARTWORK", 22, { T.wood1[1], T.wood1[2], T.wood1[3], 1 }, 3)
            knob:SetPoint("CENTER", rod, side, side == "LEFT" and -6 or 6, 0)
            local cap = circle(p, "ARTWORK", 12, { T.wood2[1], T.wood2[2], T.wood2[3], 1 }, 4)
            cap:SetPoint("CENTER", knob, "CENTER", 0, 2)
        end
        return rod
    end
    p.topRoller, p.bottomRoller = roller("TOP"), roller("BOTTOM")
    return p
end

-- Ink ------------------------------------------------------------------------------------
-- Bright colours (made for a dark background) are darkened until they read well
-- on parchment; greys become brown ink. The hue of each event colour is kept.
local MAX_LUMA = 0.36

function FC.InkColor(r, g, b)
    local hi, lo = math.max(r, g, b), math.min(r, g, b)
    if hi - lo < 0.08 then -- grey: faded brown ink, a bit lighter for lighter greys
        local k = 0.75 + (hi - 0.5) * 0.3
        return T.ink[1] * 1.6 * k, T.ink[2] * 1.6 * k, T.ink[3] * 1.6 * k
    end
    local luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
    if luma > MAX_LUMA then
        local f = MAX_LUMA / luma
        r, g, b = r * f, g * f, b * f
    end
    return r, g, b
end

function FC.Ink(text)
    return (text:gsub("|c(%x%x)(%x%x)(%x%x)(%x%x)", function(a, rh, gh, bh)
        local r, g, b = FC.InkColor(tonumber(rh, 16) / 255, tonumber(gh, 16) / 255, tonumber(bh, 16) / 255)
        return string.format("|c%s%02x%02x%02x", a, math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
    end))
end
