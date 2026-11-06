-- Spatial regression tests; run from the repository root.
local update, pins = nil, {}
local xmlFile = assert(io.open("maps.xml"))
local xml = xmlFile:read("*a")
xmlFile:close()
assert(not xml:find('inherits='), "map pins must not inherit a nonexistent XML template")
assert(not xml:find('<Scripts>'), "MapCanvas owns pin initialization and mouse scripts")
assert(xml:find('enableMouse="true"'), "map pins need mouse input for tooltips")
function CreateFromMixins(...)
    local result = {}
    for i = 1, select("#", ...) do
        for key, value in pairs(select(i, ...)) do result[key] = value end
    end
    return result
end
local function Frame()
    return {
        SetScript = function(_, event, fn) if event == "OnUpdate" then update = fn end end,
        RegisterEvent = function() end, SetSize = function() end,
        SetFrameLevel = function() end, EnableMouse = function() end,
        Hide = function(self) self.shown = false end,
        Show = function(self) self.shown = true end,
        ClearAllPoints = function() end,
        SetPoint = function(self, _, _, _, x, y) self.x, self.y = x, y end,
        CreateTexture = function() return {
            SetAllPoints = function() end, SetTexture = function() end, SetVertexColor = function() end,
        } end,
    }
end
function CreateFrame() local frame = Frame(); pins[#pins + 1] = frame; return frame end
local function Vector(x, y) return {GetXY = function() return x, y end} end
local display, current, facing = 1, 1, 0
C_Map = {
    GetBestMapForUnit = function() return current end,
    GetPlayerMapPosition = function() return Vector(0.5, 0.5) end,
    GetMapWorldSize = function() return 1000, 1000 end,
}
local pois = {
    {questID = 10, x = 0.52, y = 0.5},
    {questID = 20, x = 0.5, y = 0.51, isQuestStart = true},
    {questID = 30, x = 0.5, y = 0.5}, -- not in the active quest log
    {questID = 10, x = 2, y = 0.5}, -- invalid coordinates
}
local completed = {}
C_QuestLog = {
    GetQuestsOnMap = function(id) return id == 1 and pois or {} end,
    IsQuestFlaggedCompleted = function(id) return completed[id] end,
}
C_Minimap = { GetViewRadius = function() return 100 end }
Minimap = {
    IsShown = function() return true end, GetFrameLevel = function() return 1 end,
    GetWidth = function() return 200 end, GetHeight = function() return 200 end,
}
local worldMap = {
    IsShown = function() return display ~= nil end, GetMapID = function() return display end,
    RemoveAllPinsByTemplate = function(self) self.markers = {} end,
    AcquirePin = function(self, template, marker)
        assert(template == "QuesterMapPinTemplate")
        local pin = CreateFromMixins(Frame(), QuesterMapPinMixin)
        -- MapCanvas sets ownership before OnLoad; it dispatches these mouse callbacks.
        pin:SetOwningMap(self)
        pin:OnLoad()
        pin:OnAcquired(marker)
        assert(pin.x == marker.x and pin.y == marker.y)
        assert(type(pin.OnMouseEnter) == "function" and type(pin.OnMouseLeave) == "function")
        self.pin = pin
        self.markers[#self.markers + 1] = marker
    end,
}
function GetCVar() return "1" end
function GetPlayerFacing() return facing end
function GetBuildInfo() return "1.60.1", "69913", "", 16001 end
function GetLocale() return "enUS" end
local npc = true
function UnitGUID() return npc and "Creature-0-0-0-0-123-0" or nil end
function GetQuestID() return 40 end
function GetTitleText() return "Delivery" end
QuesterDB = { hiddenQuests = {} }
local NS = {}
assert(loadfile("maps.lua"))("Quester", NS)
NS.InitMaps()
NS.UpdateMapQuests({{key = 10, title = "Hunt", complete = false}})
update(nil, 0.2)
assert(#NS.mapMarkers == 2 and pins[2].shown, "minimap works before Blizzard_MapCanvas loads")
-- The map's mixin becomes available after Quester's Lua/XML have loaded.
MapCanvasPinMixin = {
    SetOwningMap = function(self, map) self.owningMap = map end,
    UseFrameLevelType = function(self, level)
        assert(self.owningMap == worldMap, "pin initialization requires map ownership")
        assert(level == "PIN_FRAME_LEVEL_AREA_POI")
    end,
    SetScalingLimits = function() end,
    SetPosition = function(self, x, y) self.x, self.y = x, y end,
}
WorldMapFrame = worldMap
update(nil, 0.2)
assert(#NS.mapMarkers == 2 and #WorldMapFrame.markers == 2)
local tooltipShown = false
GameTooltip = {
    SetOwner = function(_, pin) assert(pin == WorldMapFrame.pin) end,
    AddLine = function() end,
    Show = function() tooltipShown = true end,
    Hide = function() tooltipShown = false end,
}
WorldMapFrame.pin:OnMouseEnter()
assert(tooltipShown, "world map pin hover shows its tooltip")
WorldMapFrame.pin:OnMouseLeave()
assert(not tooltipShown, "world map pin mouse leave hides its tooltip")
assert(NS.mapMarkers[1].kind == "objective" and NS.mapMarkers[2].kind == "giver")
assert(pins[2].shown and math.abs(pins[2].x - 20) < 0.001 and pins[2].y == 0)
facing = math.pi / 2
update(nil, 0.2)
assert(math.abs(pins[2].x) < 0.001 and math.abs(pins[2].y + 20) < 0.001)
NS.HandleMapEvent("QUEST_COMPLETE")
NS.UpdateMapQuests({{key = 40, title = "Delivery", complete = true}})
update(nil, 0.2)
assert(#NS.mapMarkers == 2 and NS.mapMarkers[2].kind == "turnin" and NS.mapMarkers[2].observed)
QuesterDB.hiddenQuests[40] = "Delivery"
NS.UpdateMapQuests({})
update(nil, 0.2)
assert(#NS.mapMarkers == 1)
QuesterDB.hiddenQuests[40] = nil
NS.HandleMapEvent("QUEST_DETAIL")
completed[40] = true
update(nil, 0.2)
assert(#NS.mapMarkers == 1, "completed observed quest giver suppressed")
completed[40] = nil
update(nil, 0.2) -- waits for an event, rather than scanning APIs every frame
NS.UpdateMapQuests({})
update(nil, 0.2)
assert(#NS.mapMarkers == 2)
display, current = 2, 2
update(nil, 0.2)
assert(#WorldMapFrame.markers == 0 and not pins[2].shown, "old map/zone pins cleared")
display, current = 1, 1
C_QuestLog.GetQuestsOnMap = function() error("restricted beta API") end
NS.UpdateMapQuests({})
update(nil, 0.2)
assert(#NS.mapMarkers == 1 and NS.mapMarkers[1].observed)
npc = false
function GetQuestID() return 50 end
NS.HandleMapEvent("QUEST_DETAIL")
update(nil, 0.2)
assert(#NS.mapMarkers == 1, "remote quest must not record player as NPC location")
C_Map = nil
update(nil, 0.2)
assert(not pins[2].shown, "missing position API hides minimap markers")
print("PASS: deferred MapCanvas loading, pin lifecycle/tooltips, native/observed coordinates, readiness, hidden/completed quests, rotation, map/zone changes, missing/failing APIs and remote dialogs")
