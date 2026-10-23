local _, NS = ...
local driver, owner, uid, current
local elapsed = 0
local hookedTomTom, selectedArrow
NS.tomTomStatus = "TomTom navigation: off."

-- Read only public, usable values. Restricted or unavailable data is unknown.
local function Read(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, a, b, c = pcall(fn, ...)
    if not ok or (issecretvalue and (issecretvalue(a) or issecretvalue(b) or issecretvalue(c))) then return end
    return a, b, c
end

local function Valid(map, x, y)
    return type(map) == "number" and map > 0 and map < math.huge
        and type(x) == "number" and type(y) == "number"
        and x >= 0 and x <= 1 and y >= 0 and y <= 1 and (x ~= 0 or y ~= 0)
end

local function Clear()
    if owner and uid then Read(owner.RemoveWaypoint, owner, uid) end
    owner, uid, current = nil, nil, nil
end

local function ObserveArrow(tt)
    if hookedTomTom == tt or type(hooksecurefunc) ~= "function" then return end
    hooksecurefunc(tt, "SetCrazyArrow", function(_, waypoint) selectedArrow = waypoint end)
    if type(tt.ClearCrazyArrowPoint) == "function" then
        hooksecurefunc(tt, "ClearCrazyArrowPoint", function() selectedArrow = nil end)
    end
    hookedTomTom = tt
end

function NS.GetTomTomDiagnostics()
    local tt = TomTom
    local shown = Read(TomTomCrazyArrow and TomTomCrazyArrow.IsShown, TomTomCrazyArrow)
    local distance = owner == tt and uid and Read(tt.GetDistanceToWaypoint, tt, uid)
    local summary = string.format("TomTom arrow: shown=%s, distance=%s, tracking quest=%s, pin=%s, placed pin=%s, type=%s.",
        tostring(shown), tostring(distance),
        tostring((Read(C_SuperTrack and C_SuperTrack.IsSuperTrackingQuest))),
        tostring((Read(C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint))),
        tostring(Read(C_Map and C_Map.GetUserWaypoint) ~= nil),
        tostring((Read(C_SuperTrack and C_SuperTrack.GetHighestPrioritySuperTrackingType))))
    local function Describe(fn, ...)
        if type(fn) ~= "function" then return "API missing" end
        local ok, a, b, c = pcall(fn, ...)
        if not ok then return "API error" end
        local values = {"nil", "nil", "nil"}
        for index = 1, 3 do
            local value = select(index, a, b, c)
            if issecretvalue and issecretvalue(value) then
                values[index] = "restricted"
            else
                values[index] = tostring(value)
            end
        end
        return table.concat(values, ", ")
    end
    local map = Read(C_Map and C_Map.GetBestMapForUnit, "player")
    local navigation = "player map unavailable"
    if type(map) == "number" then
        navigation = Describe(C_Navigation and C_Navigation.GetNextWaypointForMap, map)
    end
    return summary .. "\nTomTom target: player map=" .. tostring(map)
        .. "; native point=" .. navigation
        .. "; map pin type/id=" .. Describe(C_SuperTrack and C_SuperTrack.GetSuperTrackedMapPin)
        .. "; quest=" .. Describe(C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID)
end

-- Navigation coordinates belong to the requested map, not the destination map.
local function NextNavigationPoint()
    local map = Read(C_Map and C_Map.GetBestMapForUnit, "player")
    if type(map) ~= "number" or not (map > 0) then return end
    local x, y, description = Read(C_Navigation and C_Navigation.GetNextWaypointForMap, map)
    if Valid(map, x, y) then return map, x, y, description end
end

local function QuestOfferPoint()
    if Read(C_SuperTrack and C_SuperTrack.IsSuperTrackingMapPin) ~= true then return end
    local pinType, questID = Read(C_SuperTrack.GetSuperTrackedMapPin)
    local offerType = Enum and Enum.SuperTrackingMapPinType and Enum.SuperTrackingMapPinType.QuestOffer
    if offerType == nil or pinType ~= offerType or type(questID) ~= "number" or not (questID > 0) then return end
    local map = Read(C_Map and C_Map.GetBestMapForUnit, "player")
    if type(map) ~= "number" or not (map > 0) then return end
    -- The returned x/y are relative to the requested map, as in Blizzard's
    -- QuestOfferDataProvider. An available quest has no supertracked quest ID.
    local info = Read(C_QuestLine and C_QuestLine.GetQuestLineInfo, questID, map)
    if info and info.questID == questID and Valid(map, info.x, info.y) then
        return map, info.x, info.y, info.questName
    end
end

local function Target()
    local questTracked = Read(C_SuperTrack and C_SuperTrack.IsSuperTrackingQuest) == true
    local pinTracked = Read(C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint) == true
    local point = Read(C_Map and C_Map.GetUserWaypoint)
    if pinTracked or (point and not questTracked) then
        local map, x, y, description
        -- An untracked pin has no native route. Do not use another target's route.
        if pinTracked then map, x, y, description = NextNavigationPoint() end
        if not map and point and point.position then
            map = point.uiMapID
            x, y = Read(point.position.GetXY, point.position)
        end
        if not Valid(map, x, y) then return nil, "No usable coordinates for tracked map pin." end
        local title = "Map pin"
        return {kind = "pin", map = map, x = x, y = y, title = "Quester: " .. title,
            arrowTitle = type(description) == "string" and description ~= ""
                and title .. "\n" .. description or title}
    end
    -- Native navigation also supports map POIs and other non-quest targets.
    if not questTracked and Read(C_SuperTrack and C_SuperTrack.IsSuperTrackingAnything) == true
        and Read(C_SuperTrack and C_SuperTrack.IsSuperTrackingCorpse) ~= true then
        local map, x, y, description = NextNavigationPoint()
        local offerTitle
        if not map then map, x, y, offerTitle = QuestOfferPoint() end
        if not map then return nil, "No usable coordinates for the active navigation target." end
        local title = offerTitle or Read(C_SuperTrack.GetSuperTrackedItemName)
        if type(title) ~= "string" or title == "" then title = "Navigation target" end
        return {kind = "navigation", map = map, x = x, y = y, title = "Quester: " .. title,
            arrowTitle = type(description) == "string" and description ~= ""
                and title .. "\n" .. description or title}
    end
    if not C_SuperTrack or type(C_SuperTrack.GetSuperTrackedQuestID) ~= "function"
        or not C_QuestLog then
        return nil, "Quest navigation APIs unavailable."
    end
    if not questTracked then
        return nil, "No active navigation target or placed map pin."
    end
    local questID = Read(C_SuperTrack.GetSuperTrackedQuestID)
    if type(questID) ~= "number" or not (questID > 0) then
        return nil, "No quest is highlighted by the game."
    end
    local map, x, y = Read(C_QuestLog.GetNextWaypoint, questID)
    -- Some quests expose only a map POI instead of a navigation waypoint.
    if not Valid(map, x, y) then
        x, y = nil, nil
        map = Read(GetQuestUiMapID, questID)
        if type(map) == "number" and map > 0 then
            local pois = Read(C_QuestLog.GetQuestsOnMap, map)
            for _, info in ipairs(type(pois) == "table" and pois or {}) do
                if info.questID == questID and not info.isQuestStart and Valid(map, info.x, info.y) then
                    x, y = info.x, info.y
                    break
                end
            end
        end
    end
    local navMap, navX, navY, description = NextNavigationPoint()
    if navMap then map, x, y = navMap, navX, navY end
    if not Valid(map, x, y) then return nil, "No usable coordinates for quest " .. questID .. "." end
    local title = Read(C_QuestLog.GetTitleForQuestID, questID)
    if type(title) ~= "string" then title = "Quest " .. questID end
    local objective = description
    if type(objective) ~= "string" or objective == "" then
        objective = Read(C_QuestLog.GetNextWaypointText, questID)
    end
    if type(objective) ~= "string" or objective == "" then
        local objectives = Read(C_QuestLog.GetQuestObjectives, questID)
        local pending = {}
        for _, info in ipairs(type(objectives) == "table" and objectives or {}) do
            if not info.finished and type(info.text) == "string" and info.text ~= "" then
                pending[#pending + 1] = info.text
            end
        end
        -- Without a waypoint description the API does not identify a single
        -- objective; show the remaining objectives rather than guess one.
        objective = table.concat(pending, "; ")
    end
    local arrowTitle = title
    if objective ~= "" then arrowTitle = title .. "\n" .. objective end
    -- Keep our waypoint identity separate from its visible arrow label.
    return {kind = "quest", questID = questID, map = map, x = x, y = y,
        title = "Quester: " .. title, arrowTitle = arrowTitle}
end

function NS.RefreshTomTom()
    if not QuesterDB or not QuesterDB.tomTomNavigation then
        Clear()
        NS.tomTomStatus = "TomTom navigation: off."
        return
    end
    local tt = TomTom
    if type(tt) ~= "table" or type(tt.AddWaypoint) ~= "function"
        or type(tt.RemoveWaypoint) ~= "function" or type(tt.SetCrazyArrow) ~= "function" then
        Clear()
        NS.tomTomStatus = "TomTom navigation: TomTom is not installed or enabled. Enable TomTom in the AddOns list and reload."
        return
    end
    ObserveArrow(tt)
    -- Includes POI fields that may be restricted in newer clients.
    local ok, target, reason = pcall(Target)
    if not ok or not target then
        Clear()
        NS.tomTomStatus = "TomTom navigation: " .. (ok and reason or "Quest data unavailable.")
        return
    end
    local valid = uid and (not tt.IsValidWaypoint or Read(tt.IsValidWaypoint, tt, uid))
    if owner == tt and valid and current and current.kind == target.kind and current.questID == target.questID
        and current.map == target.map and math.abs(current.x - target.x) < 0.00001
        and math.abs(current.y - target.y) < 0.00001 and current.title == target.title
        and current.arrowTitle == target.arrowTitle then
        -- TomTom hides its frame when distance is temporarily unavailable.
        -- Its hidden OnUpdate cannot show it again once the data returns.
        -- Recover only our selected arrow, preserving manual/other-addon choices.
        if hookedTomTom == tt and selectedArrow == uid
            and Read(TomTomCrazyArrow and TomTomCrazyArrow.IsShown, TomTomCrazyArrow) == false
            and type(Read(tt.GetDistanceToWaypoint, tt, uid)) == "number" then
            Read(tt.SetCrazyArrow, tt, uid, 15, target.arrowTitle)
        end
        return
    end
    Clear()
    local waypoint = Read(tt.AddWaypoint, tt, target.map, target.x, target.y, {
        title = target.title, from = "Quester", persistent = false,
        minimap = false, world = false, crazy = false, silent = true,
        cleardistance = 0, arrivaldistance = 15,
    })
    if not waypoint then
        NS.tomTomStatus = "TomTom navigation: TomTom could not create the waypoint."
        return
    end
    owner, uid, current = tt, waypoint, target
    Read(tt.SetCrazyArrow, tt, uid, 15, target.arrowTitle)
    NS.tomTomStatus = string.format("TomTom navigation: %s, map %d, %.2f / %.2f.",
        target.questID and "quest " .. target.questID or target.kind == "pin" and "map pin" or "navigation target",
        target.map, target.x * 100, target.y * 100)
end

function NS.SetTomTomNavigation(enabled)
    QuesterDB.tomTomNavigation = not not enabled
    NS.RefreshTomTom()
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00Quester:|r " .. NS.tomTomStatus)
    end
end

function NS.InitTomTom()
    if driver then return end
    driver = CreateFrame("Frame")
    for _, event in ipairs({"SUPER_TRACKING_CHANGED", "SUPER_TRACKING_PATH_UPDATED",
        "QUEST_POI_UPDATE", "QUEST_LOG_UPDATE", "PLAYER_ENTERING_WORLD", "ADDON_LOADED",
        "USER_WAYPOINT_UPDATED", "PLAYER_MAP_CHANGED", "NAVIGATION_DESTINATION_REACHED"}) do
        -- Other clients still load Quester without Retail's navigation events.
        pcall(driver.RegisterEvent, driver, event)
    end
    driver:SetScript("OnEvent", function() elapsed = 0.5 end)
    driver:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed < 0.5 then return end
        elapsed = 0
        if QuesterDB and QuesterDB.tomTomNavigation then NS.RefreshTomTom() end
    end)
    NS.RefreshTomTom()
    if QuesterDB and QuesterDB.tomTomNavigation and not TomTom
        and DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00Quester:|r " .. NS.tomTomStatus)
    end
end
