-- Run from the repository root with Lua 5.1 or newer.
local NS, frames, messages = {}, {}, {}
DEFAULT_CHAT_FRAME = {AddMessage = function(_, message) messages[#messages + 1] = message end}
WOW_PROJECT_MAINLINE, WOW_PROJECT_ID = 1, 1
QuesterDB = {tomTomNavigation = false}
function hooksecurefunc(object, method, hook)
    local original = object[method]
    object[method] = function(...)
        local result = original(...)
        hook(...)
        return result
    end
end
local arrowShown, distance = false, 100
TomTomCrazyArrow = {IsShown = function() return arrowShown end}
function CreateFrame()
    local f = {scripts = {}}
    function f:RegisterEvent(event) if event == "SUPER_TRACKING_PATH_UPDATED" then error("unknown event") end end
    function f:SetScript(event, fn) self.scripts[event] = fn end
    frames[#frames + 1] = f
    return f
end
local quest, tracking, map, x, y = 42, true, 100, 0.4, 0.6
C_SuperTrack = {
    GetSuperTrackedQuestID = function() return quest end,
    IsSuperTrackingQuest = function() return tracking end,
}
C_QuestLog = {
    GetNextWaypoint = function() return map, x, y end,
    GetTitleForQuestID = function(id) return "Quest " .. id end,
}
local points, added, removed, arrows, arrowTitle = {}, 0, 0, 0, nil
TomTom = {
    AddWaypoint = function(_, m, px, py, opts)
        assert(m > 0 and px >= 0 and px <= 1 and py >= 0 and py <= 1)
        assert(not opts.persistent and not opts.world and not opts.minimap and not opts.crazy)
        assert(opts.silent and opts.cleardistance == 0 and opts.from == "Quester")
        local uid = {m, px, py, opts = opts}; points[uid] = true; added = added + 1; return uid
    end,
    RemoveWaypoint = function(_, uid) assert(points[uid]); points[uid] = nil; removed = removed + 1 end,
    SetCrazyArrow = function(_, uid, _, title)
        assert(points[uid]); arrows = arrows + 1; arrowTitle = title; arrowShown = true
    end,
    GetDistanceToWaypoint = function() return distance end,
    IsValidWaypoint = function(_, uid) return points[uid] end,
}
assert(loadfile("tomtom.lua"))("Quester", NS)
NS.InitTomTom(); NS.InitTomTom(); assert(#frames == 1 and added == 0)
QuesterDB.tomTomNavigation = true
NS.RefreshTomTom(); assert(added == 1 and arrows == 1)
NS.RefreshTomTom(); assert(added == 1 and arrows == 1, "unchanged target does not reclaim arrow")
-- Reproduce TomTom hiding its frame during a transient missing-distance update.
arrowShown, distance = false, nil
NS.RefreshTomTom(); assert(arrows == 1, "wait for usable distance")
distance = 100
NS.RefreshTomTom(); assert(arrows == 2 and arrowShown, "recover hidden owned arrow when distance returns")
NS.RefreshTomTom(); assert(arrows == 2, "visible arrow is not repeatedly selected")
local other = {}; points[other] = true
TomTom:SetCrazyArrow(other, 15, "Manual target")
arrowShown = false
NS.RefreshTomTom(); assert(arrows == 3 and not arrowShown, "do not reclaim another selected arrow")
assert(NS.GetTomTomDiagnostics():find("shown=false"))
quest = 43; NS.RefreshTomTom(); assert(added == 2 and removed == 1)
x = 0.7; frames[1].scripts.OnUpdate(nil, 0.5); assert(added == 3 and removed == 2)
-- Manual or other-addon waypoints are not removed.
local manual = {}; points[manual] = true
tracking = false; NS.RefreshTomTom(); assert(removed == 3 and points[manual])
tracking = true; NS.RefreshTomTom(); assert(added == 4)
QuesterDB.tomTomNavigation = false; NS.RefreshTomTom(); assert(removed == 4 and points[manual])
QuesterDB.tomTomNavigation = true
local saved = TomTom; TomTom = nil; NS.RefreshTomTom(); assert(NS.tomTomStatus:find("not installed or enabled"))
NS.SetTomTomNavigation(true)
assert(messages[#messages]:find("not installed or enabled"), "missing optional dependency provides feedback")
TomTom = saved; NS.RefreshTomTom(); assert(added == 5)
-- Missing, failing, invalid and restricted APIs clear stale navigation safely.
C_QuestLog.GetNextWaypoint = function() error("restricted") end
NS.RefreshTomTom(); assert(removed == 5 and NS.tomTomStatus:find("No usable"))
C_QuestLog.GetNextWaypoint = function() return map, x, y end
for _, coords in ipairs({{0, 0}, {-0.1, 0.5}, {1.1, 0.5}, {0/0, 0.5}}) do
    x, y = coords[1], coords[2]; NS.RefreshTomTom(); assert(added == 5)
end
x, y = 0.4, 0.6
function issecretvalue(value) return value == 0.4 end
NS.RefreshTomTom(); assert(added == 5)
issecretvalue = nil
-- Native POI fallback must belong to the highlighted quest and have its own coordinates.
C_QuestLog.GetNextWaypoint = function() return nil end
function GetQuestUiMapID() return 200 end
C_QuestLog.GetQuestsOnMap = function() return {
    {questID = 999, x = 0.1, y = 0.1}, {questID = 43, x = 0.2, y = 0.3},
} end
NS.RefreshTomTom(); assert(added == 6 and NS.tomTomStatus:find("map 200"))
C_QuestLog.GetQuestsOnMap = function() return {} end
C_QuestLog.GetNextWaypoint = function() return -1, 0.2, 0.3 end
NS.RefreshTomTom(); assert(added == 6 and removed == 6, "never reuse coordinates from invalid waypoint")
-- The arrow has a quest title and objective, independently of waypoint ownership.
C_QuestLog.GetNextWaypoint = function() return 100, 0.4, 0.6 end
local objective = "Reach the tower"
C_QuestLog.GetNextWaypointText = function() return objective end
NS.RefreshTomTom(); assert(arrowTitle == "Quest 43\nReach the tower")
objective = "Speak to the guard"
NS.RefreshTomTom(); assert(arrowTitle == "Quest 43\nSpeak to the guard", "text changes at unchanged coordinates")
objective = nil
C_QuestLog.GetQuestObjectives = function() return {
    {text = "Finished task", finished = true},
    {text = "Wolves slain: 1/5", finished = false},
    {text = "Collect supplies: 0/3", finished = false},
} end
NS.RefreshTomTom(); assert(arrowTitle == "Quest 43\nWolves slain: 1/5; Collect supplies: 0/3")
C_QuestLog.GetQuestObjectives = nil
NS.RefreshTomTom(); assert(arrowTitle == "Quest 43", "no empty or invented objective")
print("PASS: two-line arrow label, waypoint description, objective progress fallback and missing text")

-- Native navigation points use the player's map, even for another-zone pins.
local pinTracking, pin = false, {uiMapID = 900, position = {GetXY = function() return 0.8, 0.9 end}}
C_SuperTrack.IsSuperTrackingUserWaypoint = function() return pinTracking end
C_Map = {GetBestMapForUnit = function() return 300 end, GetUserWaypoint = function() return pin end}
local navX, navY = 0.2, 0.3
C_Navigation = {GetNextWaypointForMap = function(m)
    assert(m == 300); return navX, navY, "Take the portal"
end}
NS.RefreshTomTom()
assert(NS.tomTomStatus:find("map 300") and arrowTitle == "Quest 43\nTake the portal")
pinTracking, tracking = true, false
NS.RefreshTomTom()
assert(arrowTitle == "Map pin\nTake the portal")
local count = added
NS.RefreshTomTom(); assert(added == count, "unchanged navigation does not reclaim arrow")
navX = 0.5
frames[1].scripts.OnUpdate(nil, 0.5)
assert(added == count + 1, "next route point updates automatically")
navX, navY = nil, nil
NS.RefreshTomTom()
assert(NS.tomTomStatus:find("map 900") and arrowTitle == "Map pin", "fallback uses destination map")
pin = nil
NS.RefreshTomTom(); assert(NS.tomTomStatus:find("No usable"), "removed pin clears stale target")
navX, navY = 0.4, 0.6
function issecretvalue(value) return value == 0.4 end
NS.RefreshTomTom(); assert(NS.tomTomStatus:find("No usable"), "restricted route coordinates are ignored")
issecretvalue = nil
pinTracking = false
NS.RefreshTomTom(); assert(NS.tomTomStatus:find("No active"))
-- A newly placed Blizzard pin is initially untracked. It must still reach TomTom.
pin = {uiMapID = 901, position = {GetXY = function() return 0.7, 0.8 end}}
NS.RefreshTomTom()
assert(NS.tomTomStatus:find("map pin, map 901") and arrowTitle == "Map pin",
    "placed pin uses its own coordinates, never another target's native route")
count = added
NS.RefreshTomTom(); assert(added == count)
pin = {uiMapID = 902, position = {GetXY = function() return 0.6, 0.7 end}}
frames[1].scripts.OnEvent(nil, "USER_WAYPOINT_UPDATED")
frames[1].scripts.OnUpdate(nil, 0)
assert(added == count + 1 and NS.tomTomStatus:find("map 902"), "moving a placed pin updates TomTom")
tracking = true
NS.RefreshTomTom(); assert(NS.tomTomStatus:find("quest 43"), "selecting a quest takes precedence over a stored pin")
tracking, pin = false, nil
NS.RefreshTomTom(); assert(NS.tomTomStatus:find("No active"), "removing pin clears its arrow")
-- A tracked POI can provide a native navigation route without any quest or user pin.
local anything, corpse = true, false
C_SuperTrack.IsSuperTrackingAnything = function() return anything end
C_SuperTrack.IsSuperTrackingCorpse = function() return corpse end
C_SuperTrack.GetSuperTrackedItemName = function() return "Flight master" end
NS.RefreshTomTom()
assert(NS.tomTomStatus:find("navigation target, map 300") and arrowTitle == "Flight master\nTake the portal")
count = added
navX = 0.55
NS.RefreshTomTom(); assert(added == count + 1, "non-quest route follows intermediate points")
navX = nil
NS.RefreshTomTom(); assert(NS.tomTomStatus:find("No usable"), "missing non-quest route clears stale arrow")
-- Retail reproduction: MapPin/QuestOffer 84442 has no quest ID or native waypoint.
Enum = {SuperTrackingMapPinType = {QuestOffer = 1}}
local offerID = 84442
C_SuperTrack.IsSuperTrackingMapPin = function() return true end
C_SuperTrack.GetSuperTrackedMapPin = function() return 1, offerID end
local offer = {questID = offerID, questName = "Invitation to the Spirit Festival", x = 0.52023971, y = 0.13395643}
C_QuestLine = {GetQuestLineInfo = function(id, m)
    assert(id == offerID and m == 300); return offer
end}
NS.RefreshTomTom()
assert(NS.tomTomStatus:find("navigation target, map 300") and arrowTitle == offer.questName,
    "available quest marker uses quest-line coordinates without an accepted quest")
count = added
offerID = 84443
offer = {questID = offerID, questName = "Another available quest", x = 0.6, y = 0.2}
NS.RefreshTomTom(); assert(added == count + 1 and arrowTitle == offer.questName, "switching offer markers updates arrow")
offer.questID = 999
NS.RefreshTomTom(); assert(NS.tomTomStatus:find("No usable"), "reject mismatched offer data")
offer.questID, offer.x = offerID, 0/0
NS.RefreshTomTom(); assert(NS.tomTomStatus:find("No usable"), "reject invalid offer coordinates")
offer.x = 0.6
navX = 0.4
NS.RefreshTomTom(); assert(arrowTitle == "Flight master\nTake the portal", "native intermediate point takes priority")
Enum, C_QuestLine = nil, nil
navX, corpse = 0.5, true
NS.RefreshTomTom(); assert(NS.tomTomStatus:find("No active"), "leave corpse navigation to TomTom")
anything, corpse = false, false
NS.RefreshTomTom(); assert(NS.tomTomStatus:find("No active"), "inactive route data is not adopted")
tracking, C_Map, C_Navigation = true, nil, nil
print("PASS: native route updates, tracked map pins, destination fallback and restricted coordinates")

-- Forever may use a different project ID or expose no project constants.
-- Navigation depends on actual API availability, not the project identifier.
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = nil, nil
local forever = {}; assert(loadfile("tomtom.lua"))("Quester", forever)
local before = added
forever.InitTomTom()
assert(added == before + 1 and forever.tomTomStatus:find("quest 43"))
forever.RefreshTomTom(); assert(added == before + 1)
C_SuperTrack = nil
forever.RefreshTomTom()
assert(forever.tomTomStatus:find("APIs unavailable") and points[manual])
QuesterDB.tomTomNavigation = false
forever.RefreshTomTom(); assert(forever.tomTomStatus:find("off"))
print("PASS: TomTom lifecycle, ownership, POI fallback, restricted APIs and Forever capability checks")
