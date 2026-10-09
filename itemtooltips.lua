local _, NS = ...
local byID, byName, dirty = {}, {}, true
local initialized = false

local function ItemID(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)"))
end

local function ItemName(text)
    if type(text) ~= "string" then return nil end
    return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|H.-|h(.-)|h", "%1"):gsub("\194\160", " ")
        :gsub("^%s*%d+%s*/%s*%d+%s+", "")
        :gsub("%s*:%s*%d+%s*/%s*%d+%s*$", "")
        :gsub("%s+", " "):match("^%s*(.-)%s*$")
end

local function Rebuild()
    byID, byName = {}, {}
    local function Add(index, title, number, objective, complete)
        if objective.type ~= "item" then return end
        local fulfilled, required = objective.numFulfilled, objective.numRequired
        if type(fulfilled) ~= "number" or type(required) ~= "number" then
            local current, total = (objective.text or ""):match("(%d+)%s*/%s*(%d+)")
            fulfilled, required = tonumber(current), tonumber(total)
        end
        local remaining
        if complete or objective.finished then remaining = 0
        elseif fulfilled and required then remaining = math.max(0, required - fulfilled) end
        local link = GetQuestLogItemLink and GetQuestLogItemLink("objective", number, index)
        local id = ItemID(link) or objective.objectID
        local name = ItemName(objective.text)
        local lookup, key
        if type(id) == "number" and id > 0 then lookup, key = byID, id
        elseif name and name ~= "" then lookup, key = byName, name
        else return end
        lookup[key] = lookup[key] or {}
        lookup[key][#lookup[key] + 1] = { title = title or "Quest", remaining = remaining }
    end
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo
        and C_QuestLog.GetQuestObjectives then
        for index = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(index)
            if info and not info.isHeader and not info.isHidden and info.questID and info.questID > 0 then
                local complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID)
                for number, objective in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
                    Add(index, info.title, number, objective, complete == true or complete == 1)
                end
            end
        end
    elseif GetNumQuestLogEntries and GetQuestLogTitle and GetNumQuestLeaderBoards
        and GetQuestLogLeaderBoard then
        for index = 1, GetNumQuestLogEntries() do
            local title, _, _, header, _, complete = GetQuestLogTitle(index)
            if not header then
                for number = 1, GetNumQuestLeaderBoards(index) do
                    local text, kind, finished = GetQuestLogLeaderBoard(number, index)
                    Add(index, title, number, { text = text, type = kind, finished = finished },
                        complete == true or complete == 1)
                end
            end
        end
    end
    dirty = false
end

local function AddItemQuests(tooltip)
    if not tooltip.GetItem or tooltip.QuesterItemQuests then return end
    if not tooltip.QuesterItemQuestsHooked then
        tooltip:HookScript("OnTooltipCleared", function(self) self.QuesterItemQuests = nil end)
        tooltip.QuesterItemQuestsHooked = true
    end
    local name, link = tooltip:GetItem()
    local id = ItemID(link)
    if not id then return end
    if dirty then Rebuild() end
    local quests = byID[id]
    local namedQuests = byName[ItemName(name)]
    if not quests and not namedQuests then return end
    tooltip.QuesterItemQuests = true
    tooltip:AddLine("Quester · Aktive Quests", 1, 0.82, 0.35)
    local function Append(entries)
        for _, quest in ipairs(entries or {}) do
            local text = quest.title
            if quest.remaining ~= nil then text = text .. " — Noch benötigt: " .. quest.remaining end
            tooltip:AddLine(text, 1, 1, 1, true)
        end
    end
    Append(quests)
    Append(namedQuests)
    tooltip:Show()
end

function NS.InitItemTooltips()
    if initialized or not GameTooltip then return end
    initialized = true
    local frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function() dirty = true end)
    for _, event in ipairs({ "PLAYER_LOGIN", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED",
        "QUEST_REMOVED", "QUEST_TURNED_IN", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED" }) do
        frame:RegisterEvent(event)
    end
    local modern = TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
    for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
        tooltip:HookScript("OnTooltipCleared", function(self) self.QuesterItemQuests = nil end)
        tooltip.QuesterItemQuestsHooked = true
        if not modern and (not tooltip.HasScript or tooltip:HasScript("OnTooltipSetItem")) then
            tooltip:HookScript("OnTooltipSetItem", AddItemQuests)
        end
    end
    if modern then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, AddItemQuests)
    end
end
