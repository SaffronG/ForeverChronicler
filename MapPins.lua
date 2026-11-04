-- Forever Chronicaller: world map pins for open location goals
-- A MapCanvas data provider places one pin per open location goal on whatever
-- map is being viewed, including parent maps (continent view), by converting
-- through world coordinates. Hover shows the goal, left-click points the
-- waypoint arrow at it. The pin frame template lives in MapPins.xml.

local _, FC = ...

local TEMPLATE = "ForeverChronicallerGoalPinTemplate"
local ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1" -- gold star

-- Pin ------------------------------------------------------------------------

ForeverChronicallerGoalPinMixin = CreateFromMixins(MapCanvasPinMixin)

function ForeverChronicallerGoalPinMixin:OnLoad()
    self.Icon:SetTexture(ICON)
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
    self:SetScalingLimits(1, 1.0, 1.2) -- don't shrink to nothing when zoomed out
end

function ForeverChronicallerGoalPinMixin:OnAcquired(index, goal, x, y)
    self.index = index
    self.goal = goal
    self:SetPosition(x, y)
end

function ForeverChronicallerGoalPinMixin:OnMouseEnter()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Goal: " .. self.goal.text, 1, 0.82, 0)
    GameTooltip:AddLine("Click to point the arrow here.", 1, 1, 1)
    GameTooltip:Show()
end

function ForeverChronicallerGoalPinMixin:OnMouseLeave()
    GameTooltip:Hide()
end

-- The map canvas has routed pin clicks through different methods over the
-- years, so handle all of them. Setting the waypoint twice is harmless.
function ForeverChronicallerGoalPinMixin:HandleClick(button)
    if button == "LeftButton" and self.index then
        FC:SetGoalWaypoint(self.index)
    end
end
function ForeverChronicallerGoalPinMixin:OnMouseClickAction(button) self:HandleClick(button) end
function ForeverChronicallerGoalPinMixin:OnClick(button) self:HandleClick(button) end
function ForeverChronicallerGoalPinMixin:OnMouseUp(button, upInside)
    if upInside ~= false then self:HandleClick(button) end
end

-- Data provider --------------------------------------------------------------

-- Where does a goal (stored on its own map) appear on the map being viewed?
local function projectOnto(target, viewMapID)
    if target.mapID == viewMapID then return target.x, target.y end
    local continent, wx, wy = FC.WorldPos(target.mapID, target.x, target.y)
    if not continent then return nil end
    local _, pos = C_Map.GetMapPosFromWorldPos(continent, CreateVector2D(wx, wy), viewMapID)
    if not pos then return nil end
    local x, y = pos:GetXY()
    if x < 0 or x > 1 or y < 0 or y > 1 then return nil end -- off this map
    return x, y
end

local Provider = CreateFromMixins(MapCanvasDataProviderMixin)

function Provider:RemoveAllData()
    self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
end

-- Called by the map on show and on every map change.
function Provider:RefreshAllData()
    self:RemoveAllData()
    if not FC.db then return end
    local map = self:GetMap()
    local viewMapID = map:GetMapID()
    if not viewMapID then return end
    for i, g in ipairs(FC.db.goals) do
        if g.kind == "location" and not g.done then
            local ok, x, y = pcall(projectOnto, g.target, viewMapID)
            if ok and x then map:AcquirePin(TEMPLATE, i, g, x, y) end
        end
    end
end

FC:WhenWorldMap(function()
    if not (WorldMapFrame.AddDataProvider and MapCanvasDataProviderMixin) then return end
    WorldMapFrame:AddDataProvider(Provider)
    FC.mapPinProvider = Provider
end)

-- Goal list changed (added, done, deleted, reordered): redraw if the map is open.
FC:On("GOALS_CHANGED", function()
    if FC.mapPinProvider and WorldMapFrame:IsShown() then
        Provider:RefreshAllData()
    end
end)
