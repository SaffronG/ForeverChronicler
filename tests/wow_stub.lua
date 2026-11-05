-- Minimal fake WoW API so the addon's logic can run under plain Lua 5.1+.
-- This only checks *logic*. Real frames, templates, the Settings API and the
-- world map can only be verified in game.
--
-- Usage: local W = dofile("tests/wow_stub.lua"); local env = W.setup(addonDir, opts)

local W = { cbor = {} }

local function vec(x, y) return { x = x, y = y, GetXY = function(s) return s.x, s.y end } end

-- A frame/region whose every unknown method is a no-op.
local function newObject(name)
    local o = { scripts = {}, hooks = {}, shown = false, text = "", name = name, children = {} }
    return setmetatable(o, { __index = function(_, k)
        if k == "SetScript" then return function(s, n, fn) s.scripts[n] = fn end end
        if k == "GetScript" then return function(s, n) return s.scripts[n] end end
        if k == "HookScript" then return function(s, n, fn) s.hooks[n] = fn end end
        if k == "RegisterEvent" then return function(s, e) W.env.registerEventFrame(s, e) end end
        if k == "UnregisterEvent" then return function() end end
        if k == "Show" then return function(s)
            local was = s.shown; s.shown = true
            if not was and s.scripts.OnShow then s.scripts.OnShow(s) end
        end end
        if k == "Hide" then return function(s)
            local was = s.shown; s.shown = false
            if was and s.scripts.OnHide then s.scripts.OnHide(s) end
        end end
        if k == "IsShown" or k == "IsVisible" then return function(s) return s.shown end end
        if k == "SetShown" then return function(s, v) if v then s:Show() else s:Hide() end end end
        if k == "SetText" then return function(s, x) s.text = x end end
        if k == "GetText" then return function(s) return s.text end end
        if k == "SetChecked" then return function(s, v) s.checked = v end end
        if k == "GetChecked" then return function(s) return s.checked end end
        if k == "GetName" then return function(s) return s.name end end
        if k == "SetHeight" then return function(s, h) s.height = h end end
        if k == "GetHeight" then return function(s) return s.height or 10 end end
        if k == "GetStringHeight" or k == "GetWidth" then return function() return 10 end end
        if k == "GetStringWidth" then return function(s) return #tostring(s.text) * 6 end end
        if k == "CreateFontString" or k == "CreateTexture" or k == "CreateLine" or k == "CreateMaskTexture" then
            return function(s) local c = newObject(); c.shown = true; table.insert(s.children, c); return c end
        end
        if k == "GetPoint" then return function() return "CENTER", nil, "CENTER", 0, 0 end end
        return function() end
    end })
end
W.newObject = newObject

-- Several fake players can exist at once: each setup() remembers the globals it
-- created, and W.activate(env) switches the "current" player back to it.
function W.activate(env)
    for k, v in pairs(env.globals) do _G[k] = v end
    W.env = env
end

-- Deliver messages `from` has sent to `to` (whispers only if addressed to `to`).
function W.transfer(from, to)
    local msgs = from.addonMessages
    from.addonMessages = {}
    W.activate(to)
    for _, m in ipairs(msgs) do
        local target = m.target and m.target:gsub("%-.*$", "")
        if m.channel ~= "WHISPER" or target == to.player.name then
            to.fire("CHAT_MSG_ADDON", m.prefix, m.msg, m.channel, from.player.name .. "-Forever")
        end
    end
end

function W.setup(dir, opts)
    opts = opts or {}
    local before = {}
    for k, v in pairs(_G) do before[k] = v end
    local env = { chat = {}, eventFrames = {}, tickers = {}, timers = {}, addonMessages = {}, menus = {},
        settings = {}, pins = {}, popups = {}, played = 0 }
    W.env = env

    function env.registerEventFrame(frame, event)
        env.eventFrames[frame] = env.eventFrames[frame] or {}
        env.eventFrames[frame][event] = true
    end
    function env.fire(event, ...)
        if env.globals and W.env ~= env then W.activate(env) end
        for frame, events in pairs(env.eventFrames) do
            if events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end
        end
    end

    -- Lua 5.1 / WoW globals
    _G.unpack = _G.unpack or table.unpack
    time = opts.time or os.time
    date = os.date
    wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    tinsert, tremove = table.insert, table.remove
    strsplit = function(sep, s)
        local out = {}
        for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
        return unpack(out)
    end
    GetTime = function() return env.now or 0 end
    env.ms = 0
    debugprofilestop = function() env.ms = env.ms + (env.tick or 0.3); return env.ms end
    geterrorhandler = function() return function(msg) env.lastError = msg end end
    debugstack = function() return "stack" end
    hooksecurefunc = function(name, fn)
        local orig = _G[name]
        _G[name] = function(...) local r = { orig(...) }; fn(...); return unpack(r) end
    end
    CreateFromMixins = function(...)
        local t = {}
        for _, m in ipairs({ ... }) do for k, v in pairs(m) do t[k] = v end end
        return t
    end
    Mixin = function(obj, ...) for _, m in ipairs({ ... }) do for k, v in pairs(m) do obj[k] = v end end return obj end

    -- Frames & UI
    CreateFrame = function(_, name, parent, template)
        local f = newObject(name)
        if name then _G[name] = f end
        f.template = template
        return f
    end
    UIParent = newObject("UIParent"); UIParent.shown = true
    UISpecialFrames = {}
    BackdropTemplateMixin = {}
    DEFAULT_CHAT_FRAME = { AddMessage = function(_, m)
        local clean = m:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        table.insert(env.chat, clean)
        if opts.echo then print("CHAT: " .. clean) end
    end }
    UIErrorsFrame = { AddMessage = function() end }
    GameTooltip = { SetOwner = function() end, SetText = function(_, t) env.tooltip = t end,
        AddLine = function() end, Show = function() end, Hide = function() end, ClearLines = function() end }
    C_AddOns = { GetAddOnMetadata = function(_, field) if field == "Version" then return opts.version or "0.2.0" end end }
    PlaySound = function() end
    SOUNDKIT = {}
    InCombatLockdown = function() return env.inCombat or false end
    IsControlKeyDown = function() return env.ctrl or false end
    IsShiftKeyDown = function() return env.shift or false end
    StaticPopupDialogs = {}
    StaticPopup_Show = function(which, a, b, data)
        table.insert(env.popups, { which = which, a = a, b = b, data = data })
        return {}
    end
    StaticPopup_Hide = function() end
    SlashCmdList = {}

    -- Player / world
    env.player = { name = opts.name or "Chase", level = opts.level or 10, zone = "Elwynn Forest", map = 1, x = 0.5, y = 0.5,
        money = 0, realm = "Forever" }
    local P = env.player
    UnitName = function(unit) if unit == "player" then return P.name end return unit end
    UnitLevel = function() return P.level end
    UnitRace = function() return P.raceName or "Night Elf", P.race or "NightElf", 4 end
    UnitClass = function() return P.className or "Druid", P.class or "DRUID", 11 end
    UnitFactionGroup = function() return P.faction or "Alliance" end
    UnitXP = function() return P.xp or 0 end
    UnitXPMax = function() return 1000 end
    GetMoney = function() return P.money end
    GetRealmName = function() return P.realm end
    UnitFullName = function() return P.name, P.realm end
    GetRealZoneText = function() return P.zone end
    GetZoneText = GetRealZoneText
    GetTitleText = function() return env.questTitle end
    GetAchievementInfo = function(id) return id, "Achievement " .. id end
    RequestTimePlayed = function() env.timePlayedRequested = true end
    IsInGroup = function(category) if category == 2 then return env.inInstanceGroup or false end return env.inGroup or false end
    LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE = 1, 2
    Ambiguate = function(name) return (name:gsub("%-.*$", "")) end
    IsInRaid = function() return false end
    IsInInstance = function() return env.inInstance or false, env.inInstance and "party" or "none" end
    env.groupMembers, env.friendsOnline = {}, {}
    UnitInParty = function(name) return env.groupMembers[name] or false end
    UnitInRaid = function() return nil end
    C_FriendList = { GetFriendInfo = function(name) if env.friendsOnline[name] ~= nil then return { connected = env.friendsOnline[name] } end end }
    GetNumGroupMembers = function() return env.inGroup and 2 or 0 end

    -- Quests
    C_QuestLog = { GetTitleForQuestID = function(id) return env.questTitles and env.questTitles[id] end }

    -- Professions: env.professions = { { name, rank, maxRank, skillLine }, ... } (5 slots; false = empty slot)
    -- env.recipes[recipeID] = { name, learned, prof = skillLineID, line = childName }; env.openProf = skillLineID
    -- of the profession window that is open (nil = closed), env.items[itemID] = name
    env.professions, env.recipes, env.items = {}, {}, {}
    GetProfessions = function()
        local idx = {}
        for i = 1, 5 do idx[i] = env.professions[i] and i or nil end -- empty slots are nil, like the client
        return idx[1], idx[2], idx[3], idx[4], idx[5]
    end
    GetProfessionInfo = function(i)
        local p = env.professions[i]
        if p then return p.name, 0, p.rank, p.maxRank, 0, 0, p.skillLine end
    end
    local function profName(id)
        for i = 1, 5 do local p = env.professions[i]; if p and p.skillLine == id then return p.name end end
        return env.profNames and env.profNames[id]
    end
    C_TradeSkillUI = {
        IsTradeSkillReady = function() return env.openProf ~= nil end,
        IsTradeSkillLinked = function() return env.linked or false end,
        IsTradeSkillGuild = function() return false end,
        IsNPCCrafting = function() return false end,
        GetBaseProfessionInfo = function()
            if env.openProf then return { professionID = env.openProf, professionName = profName(env.openProf) } end
        end,
        GetAllRecipeIDs = function()
            local ids = {}
            for id, r in pairs(env.recipes) do if r.prof == env.openProf then ids[#ids + 1] = id end end
            table.sort(ids)
            return ids
        end,
        GetRecipeInfo = function(id)
            local r = env.recipes[id]
            if r then return { recipeID = id, name = r.name, learned = r.learned, isDummyRecipe = r.dummy } end
        end,
        GetTradeSkillLineForRecipe = function(id)
            local r = env.recipes[id]
            if r then return r.prof + 1000, r.line or "Child", r.prof end
        end,
    }
    C_Item = { GetItemNameByID = function(id) return env.items[id] end }
    C_Spell = { GetSpellName = function() return nil end }

    -- Maps: map 1 "Elwynn Forest" = 1000x1000 yd at world 0..1000; map 2 = continent 0..4000
    CreateVector2D = vec
    UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { uiMapID = m, position = vec(x, y) } end }
    C_Map = {
        GetBestMapForUnit = function() return P.map end,
        GetPlayerMapPosition = function() if P.map then return vec(P.x, P.y) end end,
        GetMapInfo = function(m) return { name = (m == 1 and "Elwynn Forest") or (m == 2 and "Eastern Kingdoms") or ("Map" .. m) } end,
        GetWorldPosFromMapPos = function(m, v)
            if m == 2 then return 0, vec(v.x * 4000, v.y * 4000) end
            return 0, vec(v.x * 1000, v.y * 1000)
        end,
        GetMapPosFromWorldPos = function(_, v, m)
            if m == 2 then return 2, vec(v.x / 4000, v.y / 4000) end
            if m == 1 then return 1, vec(v.x / 1000, v.y / 1000) end
            return m, vec(5, 5)
        end,
        CanSetUserWaypointOnMap = function(m) return m == 1 end,
        SetUserWaypoint = function(p) env.waypoint = p end,
        GetUserWaypoint = function() return env.waypoint end,
        HasUserWaypoint = function() return env.waypoint ~= nil end,
        ClearUserWaypoint = function() env.waypoint = nil end,
    }
    C_SuperTrack = { SetSuperTrackedUserWaypoint = function(v) env.supertracked = v end }

    -- Timers: run manually with env.runTickers() / env.runTimers()
    C_Timer = {
        NewTicker = function(_, fn)
            local t = { fn = fn }
            t.Cancel = function() t.cancelled = true end
            t.IsCancelled = function() return t.cancelled end
            table.insert(env.tickers, t)
            return t
        end,
        After = function(_, fn) table.insert(env.timers, fn) end,
    }
    function env.runTickers()
        if env.globals and W.env ~= env then W.activate(env) end
        for _, t in ipairs(env.tickers) do if not t.cancelled then t.fn(t) end end
    end
    function env.activeTickers()
        local n = 0
        for _, t in ipairs(env.tickers) do if not t.cancelled then n = n + 1 end end
        return n
    end
    function env.runTimers()
        local list = env.timers; env.timers = {}
        for _, fn in ipairs(list) do fn() end
    end

    -- Addon messaging
    C_ChatInfo = {
        RegisterAddonMessagePrefix = function(p) env.prefix = p; return true end,
        SendAddonMessage = function(prefix, msg, channel, target)
            if env.commsBlocked then return false, 9 end
            table.insert(env.addonMessages, { prefix = prefix, msg = msg, channel = channel, target = target })
            return true, 0
        end,
        InChatMessagingLockdown = function() return env.commsBlocked or false end,
    }
    Enum = { SendAddonMessageResult = { Success = 0 } }

    -- Encoding (11.1.5+ C_EncodingUtil); tests use a reversible fake
    if not opts.noEncoding then
        C_EncodingUtil = {
            -- shared across setups so one fake character can import another's export
            SerializeCBOR = function(t) table.insert(W.cbor, t); return "CBOR" .. #W.cbor end,
            DeserializeCBOR = function(s) local n = tonumber(s:match("^CBOR(%d+)$")); return n and W.cbor[n] end,
            CompressString = function(s) return "Z" .. s end,
            DecompressString = function(s) return s:sub(1, 1) == "Z" and s:sub(2) or nil end,
            EncodeBase64 = function(s) return "B" .. s end,
            DecodeBase64 = function(s) return s:sub(1, 1) == "B" and s:sub(2) or nil end,
        }
    else
        C_EncodingUtil = nil
    end

    -- Settings API
    MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }
    Settings = {
        VarType = { Boolean = "boolean", Number = "number" },
        RegisterVerticalLayoutCategory = function(name) return { GetID = function() return name end } end,
        RegisterAddOnSetting = function(_, var, key, tbl, ty, name)
            assert(type(tbl[key]) == ty, var .. " stored value has wrong type")
            env.settings[var] = { key = key, tbl = tbl, name = name }
            return { var = var }
        end,
        CreateCheckbox = function() end,
        CreateSlider = function() end,
        CreateSliderOptions = function() return { SetLabelFormatter = function(_, _, fn) env.sliderLabels = env.sliderLabels or {}; table.insert(env.sliderLabels, fn) end } end,
        RegisterAddOnCategory = function() end,
        OpenToCategory = function(id) env.openedSettings = id end,
    }

    -- Menus
    MenuUtil = { CreateContextMenu = function(owner, gen)
        local menu = { buttons = {}, owner = owner }
        gen(owner, {
            CreateTitle = function(_, t) menu.title = t end,
            CreateButton = function(_, label, fn) menu.buttons[label] = fn end,
            CreateDivider = function() end,
        })
        table.insert(env.menus, menu)
    end }

    -- World map + MapCanvas
    MapCanvasPinMixin = { SetPosition = function(s, x, y) s.x, s.y = x, y end,
        UseFrameLevelType = function() end, SetScalingLimits = function() end }
    MapCanvasDataProviderMixin = { GetMap = function(s) return s.owner end }
    env.mapID = 1
    WorldMapFrame = newObject("WorldMapFrame")
    WorldMapFrame.ScrollContainer = newObject()
    WorldMapFrame.ScrollContainer.GetNormalizedCursorPosition = function() return env.cursorX or 0.5, env.cursorY or 0.5 end
    WorldMapFrame.GetMapID = function() return env.mapID end
    WorldMapFrame.SetMapID = function(_, m) env.mapID = m end
    WorldMapFrame.IsShown = function() return env.mapShown ~= false end
    WorldMapFrame.AddDataProvider = function(m, p) p.owner = m; env.pinProvider = p; p:RefreshAllData() end
    WorldMapFrame.RemoveAllPinsByTemplate = function() env.pins = {} end
    WorldMapFrame.AcquirePin = function(_, _, ...)
        local p = CreateFromMixins(ForeverChroniclerGoalPinMixin)
        p.Icon = { SetTexture = function(_, t) p.texture = t end }
        p:OnLoad(); p:OnAcquired(...)
        table.insert(env.pins, p)
        return p
    end

    -- Load the addon in .toc order (Lua files only)
    _G.ForeverChroniclerDB = opts.savedDB
    _G.ForeverChronicallerDB = opts.legacyDB -- saved data from before the 0.5.1 rename
    _G.ForeverChroniclerAccountDB = opts.savedAccountDB
    env.FC = {}
    local toc = assert(io.open(dir .. "/ForeverChronicler.toc")):read("*a")
    for line in toc:gmatch("[^\r\n]+") do
        if line:match("%.lua$") and not line:match("^#") then
            local chunk = assert(loadfile(dir .. "/" .. line))
            chunk("ForeverChronicler", env.FC)
        end
    end
    env.fire("ADDON_LOADED", "ForeverChronicler")
    env.fire("PLAYER_LOGIN")
    env.fire("PLAYER_ENTERING_WORLD")

    -- Deliver every sent addon message to ourselves as if it came from `sender`.
    function env.deliver(sender, filter)
        local msgs = env.addonMessages; env.addonMessages = {}
        for _, m in ipairs(msgs) do
            if not filter or filter(m) then
                env.fire("CHAT_MSG_ADDON", m.prefix, m.msg, m.channel, sender or "Friend-Forever")
            end
        end
        return msgs
    end
    function env.acceptPopup(i)
        W.activate(env)
        local p = table.remove(env.popups, i or 1)
        local dialog = StaticPopupDialogs[p.which]
        dialog.OnAccept(nil, p.data)
        if dialog.OnHide then dialog.OnHide() end
        env.runTimers()
    end

    env.globals = {}
    for k, v in pairs(_G) do if before[k] ~= v then env.globals[k] = v end end
    env.globals.ForeverChroniclerDB = env.FC.db

    function env.slash(msg) W.activate(env); SlashCmdList.FOREVERCHRONICLER(msg) end
    function env.activate() W.activate(env) end
    function env.chatContains(s)
        for _, line in ipairs(env.chat) do if line:find(s, 1, true) then return true end end
        return false
    end
    return env
end

return W
