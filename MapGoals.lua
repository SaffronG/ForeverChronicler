-- Forever Chronicaller: location goals
--   * Ctrl + right-click on the world map -> "Set as goal: travel here"
--   * /chron goal here        -> goal at your current position
--   * /chron goal 45.2 63.1   -> goal at those coordinates in your current zone
-- Uses the game's own user waypoint + super-tracking for the on-screen arrow,
-- and checks once per second whether you've arrived (open world only:
-- the game doesn't give your position inside instances).
--
-- Goal data: kind = "location", target = { mapID, x, y, armed }
--   x, y are 0..1 map coordinates. "armed" becomes true once you've been
--   well away from the spot, so "/chron goal here" doesn't complete instantly.

local _, FC = ...

local function mapName(mapID)
    local info = C_Map.GetMapInfo(mapID)
    return info and info.name or ("Map " .. tostring(mapID))
end

local function describe(mapID, x, y)
    return string.format("Travel to %s (%.1f, %.1f)", mapName(mapID), x * 100, y * 100)
end

local function playerMapPos()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return nil end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    return mapID, x, y
end

-- Map position -> continentID, worldX, worldY (world units are yards).
local function worldPos(mapID, x, y)
    local continent, wp = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
    if continent and wp then
        local wx, wy = wp:GetXY()
        return continent, wx, wy
    end
end

-- Goal text parser hook (called from Goals.lua).
-- Returns false if the text isn't location syntax, nil + message on error.
function FC:ParseLocation(text)
    local lower = text:lower()
    if lower == "here" then
        local mapID, x, y = playerMapPos()
        if not mapID then return nil, "Can't read your position here (instances hide it)." end
        return "location", { mapID = mapID, x = x, y = y, armed = false }, describe(mapID, x, y)
    end
    local cx, cy = text:match("^(%d+%.?%d*)[%s,]+(%d+%.?%d*)$")
    if cx then
        cx, cy = tonumber(cx), tonumber(cy)
        if cx > 100 or cy > 100 then return nil, "Coordinates go from 0 to 100." end
        local mapID = C_Map.GetBestMapForUnit("player")
        if not mapID then return nil, "Can't tell which zone you're in." end
        return "location", { mapID = mapID, x = cx / 100, y = cy / 100, armed = false },
            describe(mapID, cx / 100, cy / 100)
    end
    return false
end

-- Waypoint / arrow ----------------------------------------------------------

function FC:SetGoalWaypoint(index)
    local g = self.db.goals[index]
    if not g or g.kind ~= "location" then
        self:Print("That isn't a location goal.")
        return false
    end
    local t = g.target
    if not C_Map.CanSetUserWaypointOnMap(t.mapID) then
        self:Print("Can't place a waypoint on " .. mapName(t.mapID) .. ".")
        return false
    end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(t.mapID, t.x, t.y))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end
    return true
end

-- Clear the game's waypoint only if it's still the one we placed for this goal.
local function clearWaypointFor(g)
    if not (C_Map.HasUserWaypoint and C_Map.HasUserWaypoint()) then return end
    local wp = C_Map.GetUserWaypoint()
    local t = g.target
    if wp and wp.uiMapID == t.mapID and wp.position
        and math.abs(wp.position.x - t.x) < 0.001 and math.abs(wp.position.y - t.y) < 0.001 then
        C_Map.ClearUserWaypoint()
    end
end

FC:On("GOAL_ADDED", function(g, index)
    if g.kind == "location" then FC:SetGoalWaypoint(index) end
end)
-- Completed (incl. ticked by hand) or deleted: remove our arrow.
local function onGoalGone(g)
    if g.kind == "location" then clearWaypointFor(g) end
end
FC:On("GOAL_COMPLETED", onGoalGone)
FC:On("GOAL_REMOVED", onGoalGone)

-- Arrival check -------------------------------------------------------------

local ticker, positionBroken

-- Latest distance (yards) to each open location goal, for the tracker.
-- Weak keys so deleted goals disappear; never written to saved data.
FC.goalDistance = setmetatable({}, { __mode = "k" })

local function checkLocations()
    local pMap, px, py = playerMapPos()
    if not pMap then return end -- instance / loading screen
    local pCont, pwx, pwy = worldPos(pMap, px, py)
    if not pCont then return end
    local radius = FC.db.settings.arrivalYards or 20
    for i, g in ipairs(FC.db.goals) do
        if g.kind == "location" and not g.done then
            local t = g.target
            local gCont, gwx, gwy = worldPos(t.mapID, t.x, t.y)
            if gCont ~= pCont then
                FC.goalDistance[g] = nil -- other continent
            else
                local dist = math.sqrt((gwx - pwx) ^ 2 + (gwy - pwy) ^ 2)
                FC.goalDistance[g] = dist
                if not t.armed then
                    if dist > radius * 2 then t.armed = true end
                elseif dist <= radius then
                    FC:CompleteGoal(i) -- also clears the waypoint (GOAL_COMPLETED)
                end
            end
        end
    end
end

-- Position APIs could be restricted (Midnight-style "secret values").
-- If the check ever errors, stop polling instead of spamming errors.
local function safeCheck()
    local ok, err = pcall(checkLocations)
    if ok then FC:Fire("LOCATIONS_UPDATED") end
    if not ok and not positionBroken then
        positionBroken = true
        if ticker then ticker:Cancel(); ticker = nil end
        FC:Print("Location goals can't read your position on this client; mark them done manually. (" .. tostring(err) .. ")")
    end
end

local function updateTicker()
    if positionBroken then return end
    local open = false
    for _, g in ipairs(FC.db.goals) do
        if g.kind == "location" and not g.done then open = true break end
    end
    if open and not ticker then
        ticker = C_Timer.NewTicker(1, safeCheck)
    elseif not open and ticker then
        ticker:Cancel()
        ticker = nil
    end
end
FC:On("READY", updateTicker)
FC:On("GOALS_CHANGED", updateTicker)
FC.CheckLocations = safeCheck -- exposed for testing
FC.WorldPos = worldPos

-- World map: Ctrl + right-click menu ----------------------------------------
-- Right-click normally zooms the map out, so we remember the map and cursor
-- position on mouse down, put the map back on mouse up, then show the menu.

local pending

local function showMenu(p)
    local label = describe(p.mapID, p.x, p.y)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        FC:CreateGoal("location", { mapID = p.mapID, x = p.x, y = p.y, armed = false }, label)
        return
    end
    MenuUtil.CreateContextMenu(WorldMapFrame, function(_, root)
        root:CreateTitle(label)
        root:CreateButton("Set as goal: travel here", function()
            FC:CreateGoal("location", { mapID = p.mapID, x = p.x, y = p.y, armed = false }, label)
        end)
        root:CreateButton("Cancel", function() end)
    end)
end

local function hookWorldMap()
    local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
    if not sc or FC.mapHooked then return end
    FC.mapHooked = true

    sc:HookScript("OnMouseDown", function(_, button)
        pending = nil
        if button ~= "RightButton" or not IsControlKeyDown() then return end
        local mapID = WorldMapFrame:GetMapID()
        local x, y = sc:GetNormalizedCursorPosition()
        if mapID and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
            pending = { mapID = mapID, x = x, y = y }
        end
    end)

    sc:HookScript("OnMouseUp", function(_, button)
        if button ~= "RightButton" or not pending then return end
        local p = pending
        pending = nil
        if WorldMapFrame:GetMapID() ~= p.mapID and not InCombatLockdown() then
            WorldMapFrame:SetMapID(p.mapID) -- undo the zoom-out
        end
        if not C_Map.CanSetUserWaypointOnMap(p.mapID) then
            FC:Print("Zoom in to a zone map to set a location goal.")
            return
        end
        showMenu(p)
    end)
end

-- Run fn once the world map exists (it may load after this addon).
function FC:WhenWorldMap(fn)
    if WorldMapFrame then
        self:SafeCall(fn)
    else
        self:RegisterEvent("ADDON_LOADED", function(name)
            if name == "Blizzard_WorldMap" then fn() end
        end)
    end
end

FC:WhenWorldMap(hookWorldMap)

FC:Command("way", "/chron way <n> - point the waypoint arrow at location goal n", function(rest)
    if not tonumber(rest) then return false end
    if FC:SetGoalWaypoint(tonumber(rest)) then FC:Print("Waypoint set.") end
end)
