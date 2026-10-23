local _, NS = ...
local driver, owner, uid, current
local elapsed = 0
NS.tomTomStatus = "TomTom quest navigation: off."

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

local function Target()
    if not C_SuperTrack or type(C_SuperTrack.GetSuperTrackedQuestID) ~= "function"
        or not C_QuestLog then
        return nil, "Quest navigation APIs unavailable."
    end
    if Read(C_SuperTrack.IsSuperTrackingQuest) ~= true then
        return nil, "No quest is highlighted by the game."
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
    if not Valid(map, x, y) then return nil, "No usable coordinates for quest " .. questID .. "." end
    local title = Read(C_QuestLog.GetTitleForQuestID, questID)
    if type(title) ~= "string" then title = "Quest " .. questID end
    local objective = Read(C_QuestLog.GetNextWaypointText, questID)
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
    return {questID = questID, map = map, x = x, y = y,
        title = "Quester: " .. title, arrowTitle = arrowTitle}
end

function NS.RefreshTomTom()
    if not QuesterDB or not QuesterDB.tomTomNavigation then
        Clear()
        NS.tomTomStatus = "TomTom quest navigation: off."
        return
    end
    local tt = TomTom
    if type(tt) ~= "table" or type(tt.AddWaypoint) ~= "function"
        or type(tt.RemoveWaypoint) ~= "function" or type(tt.SetCrazyArrow) ~= "function" then
        Clear()
        NS.tomTomStatus = "TomTom quest navigation: TomTom is not installed or enabled. Enable TomTom in the AddOns list and reload."
        return
    end
    -- Includes POI fields that may be restricted in newer clients.
    local ok, target, reason = pcall(Target)
    if not ok or not target then
        Clear()
        NS.tomTomStatus = "TomTom quest navigation: " .. (ok and reason or "Quest data unavailable.")
        return
    end
    local valid = uid and (not tt.IsValidWaypoint or Read(tt.IsValidWaypoint, tt, uid))
    if owner == tt and valid and current and current.questID == target.questID
        and current.map == target.map and math.abs(current.x - target.x) < 0.00001
        and math.abs(current.y - target.y) < 0.00001 and current.title == target.title
        and current.arrowTitle == target.arrowTitle then
        return
    end
    Clear()
    local waypoint = Read(tt.AddWaypoint, tt, target.map, target.x, target.y, {
        title = target.title, from = "Quester", persistent = false,
        minimap = false, world = false, crazy = false, silent = true,
        cleardistance = 0, arrivaldistance = 15,
    })
    if not waypoint then
        NS.tomTomStatus = "TomTom quest navigation: TomTom could not create the waypoint."
        return
    end
    owner, uid, current = tt, waypoint, target
    Read(tt.SetCrazyArrow, tt, uid, 15, target.arrowTitle)
    NS.tomTomStatus = string.format("TomTom quest navigation: quest %d, map %d, %.2f / %.2f.",
        target.questID, target.map, target.x * 100, target.y * 100)
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
        "QUEST_POI_UPDATE", "QUEST_LOG_UPDATE", "PLAYER_ENTERING_WORLD", "ADDON_LOADED"}) do
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
