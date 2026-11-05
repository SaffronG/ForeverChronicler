-- Forever Chronicler: look and feel
-- Night elf style for the main window (midnight-blue to deep-teal sky, stars,
-- a crescent moon, moon-silver borders, Morpheus title font) and a parchment
-- scroll for the chronicle page. Everything is built from textures the client
-- always has (plain colours, gradients, a few icons). Atlases are only used if
-- the client says it has them, so missing art never breaks the window.
--
-- FC.Ink(text) recolours an entry's colour codes for dark-on-parchment reading,
-- so every event keeps its own colour without changing the saved text.

local _, FC = ...

local T = {
    night1   = { 0.07, 0.05, 0.17 }, -- top of the sky (violet)
    night2   = { 0.02, 0.08, 0.12 }, -- bottom (deep teal)
    border   = { 0.62, 0.70, 0.95 }, -- moon silver
    accent   = { 0.45, 0.85, 0.85 }, -- elune teal
    title    = { 0.86, 0.84, 1.00 },
    text     = { 0.80, 0.82, 0.95 },
    dim      = { 0.55, 0.58, 0.72 },
    panel    = { 0.04, 0.05, 0.12, 0.75 },
    paper1   = { 0.80, 0.69, 0.49 }, -- parchment edge (aged)
    paper2   = { 0.95, 0.89, 0.74 }, -- parchment centre
    ink      = { 0.24, 0.15, 0.07 }, -- default text on parchment
    wood1    = { 0.22, 0.13, 0.06 }, -- scroll rollers
    wood2    = { 0.55, 0.36, 0.18 },
}
FC.Theme = T

local WHITE = "Interface\\Buttons\\WHITE8X8"
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local TITLE_FONT = "Fonts\\MORPHEUS.TTF"
local PAPER_ATLASES = { "QuestBG-Parchment", "Professions-Recipe-Background" }

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

function FC:StyleFont(fs, size, color, fontFile)
    if fontFile and fs.SetFont then
        -- back to a standard font if this file can't be loaded
        local ok, loaded = pcall(fs.SetFont, fs, fontFile, size or 14, "")
        if (not ok or loaded == false) and GameFontNormalLarge then fs:SetFontObject(GameFontNormalLarge) end
    end
    if color then fs:SetTextColor(color[1], color[2], color[3]) end
end

-- Night elf window: backdrop + sky gradient + stars + crescent moon.
function FC:StyleNightElfFrame(frame, insets)
    insets = insets or 11
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = WHITE,
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 16, edgeSize = 32,
            insets = { left = insets, right = insets, top = insets, bottom = insets },
        })
        frame:SetBackdropColor(T.night2[1], T.night2[2], T.night2[3], 0.97)
        frame:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
    end
    local sky = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    sky:SetPoint("TOPLEFT", insets, -insets)
    sky:SetPoint("BOTTOMRIGHT", -insets, insets)
    gradient(sky, "VERTICAL", T.night2, T.night1, 0.97, 0.97) -- VERTICAL goes bottom -> top

    -- stars: fixed pseudo-random positions in the upper part of the window
    local seed = 7
    local function rand() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
    frame.stars = {}
    for i = 1, 40 do
        local s = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
        local size = rand() < 0.2 and 3 or 2
        s:SetSize(size, size)
        s:SetColorTexture(0.85, 0.9, 1, 0.25 + rand() * 0.5)
        s:SetPoint("TOPLEFT", frame, "TOPLEFT", insets + 4 + rand() * 600, -(insets + 4 + rand() * 70))
        frame.stars[i] = s
    end

    -- crescent moon (a pale disc partly covered by a sky-coloured one)
    local moon = circle(frame, "BACKGROUND", 30, { 0.92, 0.94, 1.0, 0.95 }, 3)
    moon:SetPoint("TOPLEFT", 26, -18)
    local shadow = circle(frame, "BACKGROUND", 28, { T.night1[1], T.night1[2], T.night1[3], 1 }, 4)
    shadow:SetPoint("TOPLEFT", moon, "TOPLEFT", 8, -3)
    frame.moon = moon

    -- a soft teal glow line under the header
    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", insets + 10, -54)
    line:SetPoint("TOPRIGHT", -(insets + 10), -54)
    gradient(line, "HORIZONTAL", T.accent, T.border, 0.1, 0.6)
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
    frame:SetBackdropColor(T.panel[1], T.panel[2], T.panel[3], alpha or T.panel[4])
    frame:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 0.8)
end

-- Night elf button. Disabled = "selected" look (tabs, chart series), since the
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
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 2, -2)
    hl:SetPoint("BOTTOMRIGHT", -2, 2)
    hl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.15)

    local function look(selected)
        if b.SetBackdropColor then
            if selected then
                b:SetBackdropColor(0.10, 0.24, 0.32, 0.95)
                b:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], 1)
            else
                b:SetBackdropColor(0.06, 0.07, 0.17, 0.9)
                b:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 0.7)
            end
        end
        local c = selected and { 1, 1, 1 } or T.text
        b.label:SetTextColor(c[1], c[2], c[3])
    end
    b:SetScript("OnEnable", function() look(false) end)
    b:SetScript("OnDisable", function() look(true) end)
    look(false)
    -- route the button's text to our own label
    b.SetText = function(self, text) self.label:SetText(text) end
    b.GetText = function(self) return self.label:GetText() end
    if label then b:SetText(label) end
    return b
end

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
