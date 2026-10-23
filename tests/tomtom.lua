-- Run from the repository root with Lua 5.1 or newer.
local NS, frames, messages = {}, {}, {}
DEFAULT_CHAT_FRAME = {AddMessage = function(_, message) messages[#messages + 1] = message end}
WOW_PROJECT_MAINLINE, WOW_PROJECT_ID = 1, 1
QuesterDB = {tomTomNavigation = false}
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
    SetCrazyArrow = function(_, uid, _, title) assert(points[uid]); arrows = arrows + 1; arrowTitle = title end,
    IsValidWaypoint = function(_, uid) return points[uid] end,
}
assert(loadfile("tomtom.lua"))("Quester", NS)
NS.InitTomTom(); NS.InitTomTom(); assert(#frames == 1 and added == 0)
QuesterDB.tomTomNavigation = true
NS.RefreshTomTom(); assert(added == 1 and arrows == 1)
NS.RefreshTomTom(); assert(added == 1 and arrows == 1, "unchanged target does not reclaim arrow")
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
