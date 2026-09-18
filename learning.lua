local _, NS = ...
local cache, eventFrame
local pending = {}

local function Secret(value)
    return issecretvalue and issecretvalue(value)
end

local function ObjectiveKey(text)
    if Secret(text) or type(text) ~= "string" then return nil end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|H.-|h(.-)|h", "%1"):gsub("\194\160", " ")
        :gsub("^%s*%d+%s*/%s*%d+%s+", "")
        :gsub("%s*:%s*%d+%s*/%s*%d+%s*$", "")
        :gsub("%s+", " "):match("^%s*(.-)%s*$")
    if text == "" then return nil end
    return text
end

local function ValidName(name)
    return not Secret(name) and type(name) == "string" and name ~= ""
        and #name <= 150 and not name:find("[\r\n%[%];|]")
end

local function IsOpen(objective)
    if objective.finished or objective.completed then return false end
    return not (type(objective.numRequired) == "number" and objective.numRequired > 0
        and type(objective.numFulfilled) == "number" and objective.numFulfilled >= objective.numRequired)
end

function NS.GetLearnedTargets(questID, objective)
    local names = {}
    if not cache or not questID or (objective.type ~= "item" and objective.type ~= "monster")
        or not IsOpen(objective) then return names end
    local key = ObjectiveKey(objective.text)
    local quests = cache[questID]
    local targets = type(quests) == "table" and key and quests[objective.type .. ":" .. key]
    if type(targets) ~= "table" then return names end
    local seen = {}
    for _, name in pairs(targets) do
        if ValidName(name) and not seen[name] then names[#names + 1] = name; seen[name] = true end
    end
    table.sort(names)
    return names
end

-- Validate against the current questlog; a tooltip header alone is insufficient.
local function Observe(unit)
    if not UnitExists(unit) or UnitIsPlayer(unit) or not UnitCanAttack("player", unit) then return {} end
    local guid, name = UnitGUID(unit), UnitName(unit)
    if Secret(guid) or type(guid) ~= "string" or not ValidName(name) then return {} end
    local npcID = tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
    if not npcID then return {} end
    local data = C_TooltipInfo.GetUnit(unit)
    if not data or not data.lines then return {} end
    local active = {}
    for index = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(index)
        if info and not info.isHeader and not info.isHidden and info.questID and info.questID > 0 then
            active[info.questID] = true
        end
    end
    local kinds = Enum and Enum.TooltipDataLineType or {}
    -- 17/8 are confirmed by the Forever 1.60.1 client diagnostic.
    local titleType, objectiveType = kinds.QuestTitle or 17, kinds.QuestObjective or 8
    local questID, objectives
    local observations = {}
    for _, line in ipairs(data.lines) do
        if line.type == titleType then
            questID = line.id
            objectives = active[questID] and C_QuestLog.GetQuestObjectives(questID) or nil
        elseif line.type == objectiveType and objectives and IsOpen(line) then
            local key = ObjectiveKey(line.leftText)
            local match, ambiguous
            for _, objective in ipairs(objectives) do
                if (objective.type == "monster" or objective.type == "item") and IsOpen(objective)
                    and key and key == ObjectiveKey(objective.text) then
                    if match then ambiguous = true end
                    match = objective
                end
            end
            if match and not ambiguous then
                observations[#observations + 1] = {
                    questID = questID, key = match.type .. ":" .. key, npcID = npcID, name = name,
                }
            end
        end
    end
    if UnitGUID(unit) ~= guid then return {} end
    return observations
end

function NS.LearnUnit(unit)
    if not cache or not C_TooltipInfo or not C_TooltipInfo.GetUnit then return false end
    -- Beta APIs can return restricted data: discard the observation, never infer a match.
    local ok, observations = pcall(Observe, unit)
    if not ok then return false end
    local changed = false
    for _, observation in ipairs(observations) do
        local quest = cache[observation.questID]
        if type(quest) ~= "table" then quest = {}; cache[observation.questID] = quest end
        local targets = quest[observation.key]
        if type(targets) ~= "table" then targets = {}; quest[observation.key] = targets end
        if targets[observation.npcID] ~= observation.name then
            targets[observation.npcID] = observation.name
            changed = true
        end
    end
    if changed and NS.Refresh then NS.Refresh() end
    return changed
end

local function QueueUnit(unit)
    if pending[unit] then return end
    pending[unit] = true
    C_Timer.After(0.2, function()
        pending[unit] = nil
        NS.LearnUnit(unit)
    end)
end

function NS.InitLearning()
    if type(QuesterDB.learnedTargets) ~= "table" then QuesterDB.learnedTargets = {} end
    local _, build, _, interface = GetBuildInfo()
    -- Keep local NPC names separate, and re-learn after beta builds change.
    local bucket = "v1:" .. tostring(interface) .. ":" .. tostring(build) .. ":" .. GetLocale()
    if type(QuesterDB.learnedTargets[bucket]) ~= "table" then QuesterDB.learnedTargets[bucket] = {} end
    cache = QuesterDB.learnedTargets[bucket]
    if eventFrame or not C_TooltipInfo or not C_TooltipInfo.GetUnit then return end
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "UPDATE_MOUSEOVER_UNIT" then QueueUnit("mouseover")
        elseif event == "PLAYER_TARGET_CHANGED" then QueueUnit("target")
        else QueueUnit("target"); QueueUnit("mouseover") end
    end)
    for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "PLAYER_LOGIN", "QUEST_LOG_UPDATE" }) do
        eventFrame:RegisterEvent(event)
    end
end
