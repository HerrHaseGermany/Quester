local _, NS = ...
local active, locations, markers = {}, nil, {}
local miniPins, mapFrame = {}, nil
local dirty, elapsed, mapID, playerMap = true, 0, nil, nil
local labels = { giver = "Quest giver", turnin = "Turn-in point", objective = "Objective area" }
local textures = {
    giver = "Interface/GossipFrame/AvailableQuestIcon",
    turnin = "Interface/GossipFrame/ActiveQuestIcon",
    objective = "Interface/Minimap/Tracking/QuestBlob",
}

-- Forever is a beta client: absence, restricted data and API errors mean unknown.
local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if not ok or (issecretvalue and (issecretvalue(a) or issecretvalue(b) or issecretvalue(c))) then return nil end
    return a, b, c
end

local function Valid(id, x, y)
    return type(id) == "number" and id > 0 and type(x) == "number" and type(y) == "number"
        and x >= 0 and x <= 1 and y >= 0 and y <= 1 and (x ~= 0 or y ~= 0)
end

local function PlayerPosition()
    local id = Read(C_Map and C_Map.GetBestMapForUnit, "player")
    if type(id) ~= "number" then return end
    local pos = Read(C_Map and C_Map.GetPlayerMapPosition, id, "player")
    local x, y
    if pos then x, y = Read(pos.GetXY, pos) end
    if Valid(id, x, y) then return id, x, y end
end

local function Decorate(pin, marker)
    pin.marker = marker
    if not pin.icon then
        pin.icon = pin:CreateTexture(nil, "ARTWORK")
        pin.icon:SetAllPoints()
    end
    pin.icon:SetTexture(textures[marker.kind])
    pin.icon:SetVertexColor(1, 1, 1)
    -- A stable built-in marker even if this client's QuestBlob texture is absent.
    if marker.kind == "objective" then
        pin.icon:SetTexture("Interface/TargetingFrame/UI-RaidTargetingIcon_8")
        pin.icon:SetVertexColor(0.3, 0.8, 1)
    end
end

local function Tooltip(pin)
    local marker = pin.marker
    if not marker or not GameTooltip then return end
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:AddLine(marker.title or ("Quest " .. marker.questID), 1, 0.82, 0)
    GameTooltip:AddLine(labels[marker.kind], 1, 1, 1)
    GameTooltip:AddLine(marker.observed and "Visited position near the quest NPC"
        or "Position from the quest map API", 0.7, 0.7, 0.7, true)
    if marker.observed and marker.kind == "giver" then
        GameTooltip:AddLine("Current quest availability not confirmed", 0.7, 0.7, 0.7, true)
    end
    GameTooltip:Show()
end

QuesterMapPinMixin = {}
function QuesterMapPinMixin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
    self:SetScalingLimits(1, 1, 1.2)
end
function QuesterMapPinMixin:OnAcquired(marker)
    Decorate(self, marker)
    self:SetPosition(marker.x, marker.y)
end
function QuesterMapPinMixin:OnEnter() Tooltip(self) end
function QuesterMapPinMixin:OnLeave() if GameTooltip then GameTooltip:Hide() end end

local function Observe(questID, kind, title)
    if not locations or type(questID) ~= "number" or questID <= 0 then return end
    -- Never use the player's position for remote/item quest dialogs.
    local guid = Read(UnitGUID, "npc")
    if type(guid) ~= "string" or not (guid:match("^Creature%-") or guid:match("^GameObject%-")) then return end
    local id, x, y = PlayerPosition()
    if not id then return end
    local quest = locations[questID]
    if type(quest) ~= "table" then quest = {}; locations[questID] = quest end
    quest[kind] = { mapID = id, x = x, y = y, title = title, observed = true }
    dirty = true
end

function NS.HandleMapEvent(event)
    if event == "GOSSIP_SHOW" then
        for _, quest in ipairs(Read(C_GossipInfo and C_GossipInfo.GetAvailableQuests) or {}) do
            Observe(quest.questID, "giver", quest.title)
        end
    elseif event == "QUEST_DETAIL" then
        Observe(Read(GetQuestID), "giver", Read(GetTitleText))
    elseif event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" then
        Observe(Read(GetQuestID), "turnin", Read(GetTitleText))
    end
    dirty = true
end

function NS.UpdateMapQuests(quests)
    active = {}
    for _, quest in ipairs(quests) do
        if type(quest.key) == "number" then active[quest.key] = quest end
    end
    dirty = true
end

local function Collect(displayMap, currentMap)
    local result, seen = {}, {}
    local function Add(questID, kind, id, x, y, title, observed)
        if not Valid(id, x, y) or type(questID) ~= "number" or questID <= 0
            or (QuesterDB.hiddenQuests and QuesterDB.hiddenQuests[questID]) then return end
        local key = questID .. ":" .. kind .. ":" .. id .. ":" .. x .. ":" .. y
        if seen[key] then return end
        seen[key] = true
        result[#result + 1] = { questID = questID, kind = kind, mapID = id, x = x, y = y,
            title = title, observed = observed }
    end
    local function Native(id)
        if not id then return end
        for _, info in ipairs(Read(C_QuestLog and C_QuestLog.GetQuestsOnMap, id) or {}) do
            local quest = active[info.questID]
            if info.isQuestStart then
                Add(info.questID, "giver", id, info.x, info.y,
                    Read(C_QuestLog and C_QuestLog.GetQuestInfo, info.questID))
            elseif quest then
                Add(info.questID, quest.complete and "turnin" or "objective", id, info.x, info.y, quest.title)
            end
        end
    end
    Native(displayMap)
    if currentMap ~= displayMap then Native(currentMap) end
    for questID, quest in pairs(active) do
        local id, x, y = Read(C_QuestLog and C_QuestLog.GetNextWaypoint, questID)
        Add(questID, quest.complete and "turnin" or "objective", id, x, y, quest.title)
    end
    for questID, known in pairs(locations or {}) do
        local quest = active[questID]
        if type(known) == "table" then
            local kind = quest and quest.complete and "turnin" or (not quest and "giver")
            local position = kind and known[kind]
            local complete = Read(C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted, questID)
            -- Observations do not prove eligibility; completed quests are suppressed.
            if type(position) == "table" and (quest or not complete) then
                Add(questID, kind, position.mapID, position.x, position.y,
                    quest and quest.title or position.title, true)
            end
        end
    end
    return result
end

local function DrawMap()
    if not mapFrame or not mapFrame.AcquirePin or not mapFrame.RemoveAllPinsByTemplate then return end
    mapFrame:RemoveAllPinsByTemplate("QuesterMapPinTemplate")
    if not mapFrame:IsShown() then return end
    for _, marker in ipairs(markers) do
        if marker.mapID == mapID then mapFrame:AcquirePin("QuesterMapPinTemplate", marker) end
    end
end

local outdoor = { [0] = 466.6667, 400, 333.3333, 266.6667, 200, 133.3333 }
local indoor = { [0] = 300, 240, 180, 120, 80, 50 }
local function DrawMinimap()
    for _, pin in ipairs(miniPins) do pin:Hide() end
    if not Minimap or not Minimap:IsShown() then return end
    local id, px, py = PlayerPosition()
    if not id then return end
    local width, height = Read(C_Map and C_Map.GetMapWorldSize, id)
    if not width and CreateVector2D then
        local _, top = Read(C_Map and C_Map.GetWorldPosFromMapPos, id, CreateVector2D(0, 0))
        local _, center = Read(C_Map and C_Map.GetWorldPosFromMapPos, id, CreateVector2D(0.5, 0.5))
        if top and center then
            local tx, ty = Read(top.GetXY, top)
            local cx, cy = Read(center.GetXY, center)
            if tx and ty and cx and cy then width, height = (ty - cy) * 2, (tx - cx) * 2 end
        end
    end
    if type(width) ~= "number" or type(height) ~= "number" or width <= 0 or height <= 0 then return end
    local radius = Read(C_Minimap and C_Minimap.GetViewRadius)
    if not radius then
        local zoom = Minimap:GetZoom()
        local sizes = tonumber(Read(GetCVar, "minimapZoom")) == zoom and outdoor or indoor
        radius = sizes[zoom] and sizes[zoom] / 2
    end
    if type(radius) ~= "number" or radius <= 0 then return end
    local facing = Read(GetCVar, "rotateMinimap") == "1" and Read(GetPlayerFacing) or 0
    if not facing then return end
    local count = 0
    for _, marker in ipairs(markers) do
        if marker.mapID == id then
            local dx, dy = (marker.x - px) * width, (py - marker.y) * height
            local c, s = math.cos(facing), math.sin(facing)
            dx, dy = dx * c + dy * s, -dx * s + dy * c
            -- An inset circle also keeps icons inside custom minimap masks.
            if dx * dx + dy * dy <= (radius * 0.9) ^ 2 then
                count = count + 1
                local pin = miniPins[count]
                if not pin then
                    pin = CreateFrame("Frame", nil, Minimap)
                    pin:SetSize(14, 14)
                    pin:SetFrameLevel(Minimap:GetFrameLevel() + 10)
                    pin:EnableMouse(true)
                    pin:SetScript("OnEnter", Tooltip)
                    pin:SetScript("OnLeave", QuesterMapPinMixin.OnLeave)
                    miniPins[count] = pin
                end
                Decorate(pin, marker)
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", Minimap, "CENTER", dx / radius * Minimap:GetWidth() / 2,
                    dy / radius * Minimap:GetHeight() / 2)
                pin:Show()
            end
        end
    end
end

function NS.InitMaps()
    if locations then return end
    if type(QuesterDB.mapLocations) ~= "table" then QuesterDB.mapLocations = {} end
    local _, build, _, interface = GetBuildInfo()
    local bucket = tostring(interface) .. ":" .. tostring(build) .. ":" .. GetLocale()
    if type(QuesterDB.mapLocations[bucket]) ~= "table" then QuesterDB.mapLocations[bucket] = {} end
    locations = QuesterDB.mapLocations[bucket]
    NS.mapCapabilities = {
        positions = C_Map and type(C_Map.GetPlayerMapPosition) == "function" or false,
        questPOIs = C_QuestLog and type(C_QuestLog.GetQuestsOnMap) == "function" or false,
        waypoints = C_QuestLog and type(C_QuestLog.GetNextWaypoint) == "function" or false,
    }
    local frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function() dirty = true; if NS.Refresh then NS.Refresh() end end)
    for _, event in ipairs({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "QUEST_POI_UPDATE", "PLAYER_ENTERING_WORLD" }) do
        frame:RegisterEvent(event)
    end
    frame:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed < 0.2 then return end
        elapsed = 0
        local display = WorldMapFrame and WorldMapFrame:IsShown() and Read(WorldMapFrame.GetMapID, WorldMapFrame)
        local current = Read(C_Map and C_Map.GetBestMapForUnit, "player")
        if mapFrame ~= WorldMapFrame or display ~= mapID or current ~= playerMap then dirty = true end
        mapFrame, mapID, playerMap = WorldMapFrame, display, current
        if dirty then
            -- A restricted value inside a returned beta table discards that update.
            local ok, result = pcall(Collect, display, current)
            markers = ok and result or {}
            NS.mapMarkers = markers
            DrawMap()
            dirty = false
        end
        pcall(DrawMinimap)
    end)
end
