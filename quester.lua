local addonName, NS = ...
local frame = CreateFrame("Frame")
local macroName = "QuesterTarget"
local queued, ready, slotWarning = false, false, false
local targetCount, omitted = 0, 0
local questReadiness

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00Quester:|r " .. message)
end

-- Blizzard formats may use positional placeholders and localized whitespace.
local function CleanText(text)
    return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|H.-|h(.-)|h", "%1"):gsub("\194\160", " ")
        :match("^%s*(.-)%s*$")
end

local function ObjectivePattern(format)
    if type(format) ~= "string" then return nil end
    local pattern = CleanText(format):gsub("%%(%d+)%$", "%%")
    pattern = pattern:gsub("%%s", "\001"):gsub("%%d", "\002")
    pattern = pattern:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    pattern = pattern:gsub("%s+", "%%s*")
    return "^" .. pattern:gsub("\001", "(.+)"):gsub("\002", "%%d+") .. "$"
end

-- Conservative English noun aliases; never strip a trailing s from arbitrary names.
local singularNouns = {
    Workers = "Worker", Laborers = "Laborer", Scouts = "Scout", Warriors = "Warrior",
    Miners = "Miner", Raiders = "Raider", Bandits = "Bandit", Defias = "Defias",
    Wolves = "Wolf", Boars = "Boar", Spiders = "Spider", Bears = "Bear",
    Gnolls = "Gnoll", Kobolds = "Kobold", Murlocs = "Murloc", Zombies = "Zombie",
}
local function NormalizeName(name)
    local locale = GetLocale()
    if locale == "enUS" or locale == "enGB" then
        name = name:gsub("(%a+)$", function(noun) return singularNouns[noun] or noun end)
    end
    return name
end

local function TargetName(text)
    if type(text) ~= "string" or text:find("[\r\n]") then return nil end
    text = CleanText(text)
    local name
    for _, key in ipairs({ "QUEST_MONSTERS_KILLED", "QUEST_MONSTERS_KILLED_NOPROGRESS" }) do
        local pattern = ObjectivePattern(_G[key])
        name = pattern and text:match(pattern)
        if name then break end
    end
    -- Some clients return the bare monster name plus a counter instead.
    if not name then
        name = text:match("^(.-)%s*:%s*%d+%s*/%s*%d+%s*$")
            or text:match("^%d+%s*/%s*%d+%s+(.+)$")
        if name then
            -- Localized game input must still be recognized on German clients.
            name = name:gsub("%s+getötet$", ""):gsub("%s+besiegt$", "")
                :gsub("%s+slain$", ""):gsub("%s+killed$", "")
        end
    end
    if not name then return nil end
    name = name:match("^%s*(.-)%s*$")
    if name == "" or name:find("[\r\n%[%];|]") then return nil end
    return NormalizeName(name)
end

local apiWarning = false
local function QuestKey(questID, title)
    return type(questID) == "number" and questID > 0 and questID or title
end

local function CollectTargets(includeHidden)
    local names, seen, rows = {}, {}, {}
    local items, byItem = {}, {}
    local quests = {}
    local function IncludeQuest(questID, title, complete)
        local key = QuestKey(questID, title)
        quests[#quests + 1] = { key = key, title = title or "Quest",
            complete = complete == true or complete == 1 }
        return includeHidden or not QuesterDB.hiddenQuests[key]
    end
    local function AddQuestItem(index, title, questID, complete)
        -- Forever retains this index-based API alongside C_QuestLog. Feature-test
        -- it; collection objectives and reward items are not usable quest actions.
        if not GetQuestLogSpecialItemInfo then return end
        local link, texture, charges, showWhenComplete = GetQuestLogSpecialItemInfo(index)
        local itemID = type(link) == "string" and tonumber(link:match("item:(%d+)"))
        if not itemID or (complete and not showWhenComplete) then return end
        local getCount = C_Item and C_Item.GetItemCount or GetItemCount
        if getCount and getCount(itemID) == 0 then return end
        local item = byItem[itemID]
        if not item then
            item = { id = itemID, link = link, texture = texture, charges = charges, quests = {} }
            byItem[itemID] = item
            items[#items + 1] = item
        end
        item.quests[#item.quests + 1] = { title = title or "Quest", questID = questID }
    end
    local function AddObjective(title, text, kind, finished, questID, objective, readyForTurnIn)
        finished = finished or readyForTurnIn
        if type(questID) ~= "number" or questID <= 0 then questID = nil end
        objective = objective or { text = text, type = kind, finished = finished }
        local fulfilled, required = objective.numFulfilled, objective.numRequired
        if type(fulfilled) ~= "number" or type(required) ~= "number" then
            local current, total
            if type(text) == "string" then current, total = text:match("(%d+)%s*/%s*(%d+)") end
            fulfilled, required = tonumber(current), tonumber(total)
        end
        if type(required) == "number" and required > 0
            and type(fulfilled) == "number" and fulfilled >= required then
            finished = true
        end
        local learned = not finished and NS.GetLearnedTargets(questID, objective) or {}
        local targets = learned
        if #targets == 0 and kind == "monster" and not finished then
            local name = TargetName(text)
            if name then targets = { name } end
        end
        local function AddRow(name)
            rows[#rows + 1] = { title = title or "Quest", text = text or "Loading objective text …",
                kind = kind, finished = finished, name = name, questID = questID,
                objective = objective, readyForTurnIn = readyForTurnIn,
                fulfilled = fulfilled, required = required,
                source = #learned > 0 and "tooltip" or "text" }
            if name and not seen[name] then seen[name] = true; names[#names + 1] = name end
        end
        if #targets == 0 then AddRow(nil) else
            for _, name in ipairs(targets) do AddRow(name) end
        end
    end

    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries
        and C_QuestLog.GetInfo and C_QuestLog.GetQuestObjectives then
        for index = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(index)
            if info and not info.isHeader and not info.isHidden and info.questID
                and info.questID > 0 then
                local complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID)
                if IncludeQuest(info.questID, info.title, complete) then
                    complete = complete == true or complete == 1
                    AddQuestItem(index, info.title, info.questID, complete)
                    local objectives = C_QuestLog.GetQuestObjectives(info.questID)
                    if not objectives or #objectives == 0 then
                        rows[#rows + 1] = { title = info.title or "Quest", text = "No objective rows returned by the quest API.", kind = "empty", questID = info.questID, readyForTurnIn = complete }
                    end
                    for _, objective in ipairs(objectives or {}) do
                        AddObjective(info.title, objective.text, objective.type, objective.finished, info.questID, objective, complete)
                    end
                end
            end
        end
    elseif GetNumQuestLogEntries and GetQuestLogTitle
        and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
        for index = 1, GetNumQuestLogEntries() do
            local title, _, _, header, _, complete, _, questID = GetQuestLogTitle(index)
            if not header and IncludeQuest(questID, title, complete) then
                complete = complete == true or complete == 1
                AddQuestItem(index, title, questID, complete)
                local count = GetNumQuestLeaderBoards(index)
                if count == 0 then
                    rows[#rows + 1] = { title = title or "Quest", text = "No objective rows returned by the quest API.", kind = "empty", questID = questID, readyForTurnIn = complete }
                end
                for objective = 1, count do
                    local text, kind, finished = GetQuestLogLeaderBoard(objective, index)
                    AddObjective(title, text, kind, finished, questID, nil, complete)
                end
            end
        end
    else
        if not apiWarning then
            Print("Quest log API unavailable; target macro unchanged.")
            apiWarning = true
        end
        return nil
    end
    local priority = QuesterDB.priorityQuest
    if type(priority) == "table" then
        local ordered = {}
        for _, row in ipairs(rows) do
            row.priority = (priority.id and row.questID == priority.id)
                or (not priority.id and row.title == priority.title) or false
            if row.priority then ordered[#ordered + 1] = row end
        end
        for _, row in ipairs(rows) do
            if not row.priority then ordered[#ordered + 1] = row end
        end
        rows = ordered
        names, seen = {}, {}
        for _, row in ipairs(rows) do
            if row.name and not seen[row.name] then
                seen[row.name] = true
                names[#names + 1] = row.name
            end
        end
    end
    return names, rows, items, quests
end

local function ObjectiveOverview(rows)
    local overview = { total = 0, completed = 0, pending = {}, unknown = {}, readyQuests = {} }
    local seen, seenQuests = {}, {}
    for _, row in ipairs(rows) do
        local questKey = QuestKey(row.questID, row.title)
        if row.readyForTurnIn and not seenQuests[questKey] then
            seenQuests[questKey] = true
            overview.readyQuests[#overview.readyQuests + 1] = row
        end
        local key = row.objective or row
        if row.kind ~= "empty" and not seen[key] then
            seen[key] = true
            overview.total = overview.total + 1
            if row.finished then
                overview.completed = overview.completed + 1
            else
                overview.pending[#overview.pending + 1] = row
                if not row.name then overview.unknown[#overview.unknown + 1] = row end
            end
        end
    end
    return overview
end

local function UpdateMacro()
    if not ready then return end
    local names, rows, items, quests = CollectTargets()
    if NS.UpdateMapQuests then NS.UpdateMapQuests(quests or {}) end
    if not names then
        NS.objectiveOverview = nil
        NS.Render({}, "Quest log API unavailable. Macro unchanged.", {})
        return
    end
    local currentReadiness = {}
    for _, quest in ipairs(quests) do
        currentReadiness[quest.key] = quest.complete
        if QuesterDB.notifyReady and quest.complete and questReadiness
            and not questReadiness[quest.key] then
            local message = "Quest ready for turn-in: " .. quest.title
            if UIErrorsFrame and UIErrorsFrame.AddMessage then
                UIErrorsFrame:AddMessage(message, 1, 0.82, 0)
            else
                Print(message)
            end
        end
    end
    questReadiness = currentReadiness
    NS.objectiveOverview = ObjectiveOverview(rows)
    local body, included = "/cleartarget", {}
    targetCount, omitted = 0, 0
    for _, name in ipairs(names) do
        local line = "\n/targetexact " .. name .. "\n/tm 8 " .. "\n/stopmacro [exists,nodead]"
        if #body + #line <= 255 then
            body = body .. line
            included[name] = true
            targetCount = targetCount + 1
        else
            omitted = omitted + 1
        end
    end
    if targetCount == 0 then body = "#showtooltip" end

    local status = targetCount .. " targets in the global macro; " .. omitted .. " omitted due to the size limit."
    if not QuesterDB.targetMacro then
        status = "Macro updates off. Preview: " .. targetCount .. " targets."
    elseif InCombatLockdown() then
        status = "In combat: macro unchanged. Preview: " .. targetCount .. " targets."
    else
        local macroIndex
        local accounts, characters = GetNumMacros()
        local limit = MAX_ACCOUNT_MACROS or 120
        for index = 1, accounts do
            if GetMacroInfo(index) == macroName then macroIndex = index; break end
        end
        if macroIndex then
            if GetMacroBody(macroIndex) ~= body then
                EditMacro(macroIndex, macroName, 134400, body)
            end
        elseif accounts < limit then
            macroIndex = CreateMacro(macroName, 134400, body, false)
            slotWarning = false
        else
            status = "No free global macro slot. Please free a slot under /macro."
            if not slotWarning then Print(status); slotWarning = true end
        end
        -- Remove the obsolete addon-owned character copy only after global creation succeeds.
        if macroIndex and macroIndex > 0 and macroIndex <= limit then
            for index = limit + characters, limit + 1, -1 do
                if GetMacroInfo(index) == macroName then
                    DeleteMacro(index)
                    Print("Macro migrated to global storage. Drag QuesterTarget from General Macros onto your action bar again.")
                end
            end
        end
    end
    if #rows == 0 then
        status = status .. " No quest objectives returned; expand quest log categories."
    elseif #names == 0 then
        status = status .. " No unfinished enemy targets detected; /quester debug shows objective text."
    end
    NS.lastRows, NS.lastStatus = rows, status
    NS.Render(rows, status, included, body, items)
end

local function ScheduleUpdate()
    if queued then return end
    queued = true
    C_Timer.After(0.3, function()
        queued = false
        UpdateMacro()
    end)
end

NS.Refresh = ScheduleUpdate

frame:SetScript("OnEvent", function(_, event, name, ...)
    if event == "ADDON_LOADED" then
        if name ~= addonName then return end
        if type(QuesterDB) ~= "table" then QuesterDB = {} end
        if QuesterDB.autoAccept == nil then QuesterDB.autoAccept = true end
        if QuesterDB.autoTurnIn == nil then QuesterDB.autoTurnIn = true end
        if QuesterDB.acceptTrivial == nil then QuesterDB.acceptTrivial = true end
        if QuesterDB.targetMacro == nil then QuesterDB.targetMacro = true end
        if QuesterDB.notifyReady == nil then QuesterDB.notifyReady = false end
        if QuesterDB.autoSellGrey == nil then QuesterDB.autoSellGrey = false end
        if QuesterDB.autoRepair == nil then QuesterDB.autoRepair = false end
        if type(QuesterDB.hiddenQuests) ~= "table" then QuesterDB.hiddenQuests = {} end
        ready = true
        NS.InitWindow()
        NS.InitLearning()
        if NS.InitMaps then NS.InitMaps() end
        if NS.InitItemTooltips then NS.InitItemTooltips() end
        if NS.InitSettings then NS.InitSettings() end
    else
        if NS.HandleMerchantEvent(event) then return end
        if NS.HandleMapEvent then NS.HandleMapEvent(event, name, ...) end
        if NS.HandleQuestEvent(event, name, ...) then
            -- Quest-dialog automation handles its own delayed actions.
            if event == "BAG_UPDATE_DELAYED" then ScheduleUpdate() end
        else
            ScheduleUpdate()
        end
    end
end)

for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "QUEST_DETAIL", "GOSSIP_SHOW",
    "QUEST_GREETING", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED",
    "PLAYER_REGEN_ENABLED", "UPDATE_MACROS", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_FINISHED", "GOSSIP_CLOSED", "UI_ERROR_MESSAGE", "QUEST_TURNED_IN", "BAG_UPDATE_DELAYED", "MERCHANT_SHOW" }) do
    frame:RegisterEvent(event)
end

SLASH_QUESTER1 = "/quester"
SlashCmdList.QUESTER = function(input)
    if NS.HandleExceptionCommand(input, Print) then return end
    local command = input:lower():match("^%s*(.-)%s*$")
    if command == "" or command == "show" then
        NS.ShowWindow()
        ScheduleUpdate()
    elseif command == "settings" or command == "options" then
        NS.OpenSettings()
    elseif command == "hide" then
        NS.HideWindow()
    elseif command == "hidden" then
        Print("/quester hide <quest name or ID> | show <quest name or ID> | hidden clear")
        local _, _, _, quests = CollectTargets(true)
        local active = {}
        for _, quest in ipairs(quests or {}) do
            active[quest.key] = true
            Print((QuesterDB.hiddenQuests[quest.key] and "[hidden] " or "")
                .. quest.title .. (type(quest.key) == "number" and " [" .. quest.key .. "]" or ""))
        end
        -- Saved exclusions remain manageable after a quest is abandoned.
        for key, title in pairs(QuesterDB.hiddenQuests) do
            if not active[key] then
                Print("[hidden] " .. title .. (type(key) == "number" and " [" .. key .. "]" or ""))
            end
        end
    elseif command == "hidden clear" then
        QuesterDB.hiddenQuests = {}
        ScheduleUpdate()
        Print("All hidden quests restored.")
    elseif command:match("^hide%s+") or command:match("^show%s+") then
        local action, query = command:match("^(%a+)%s+(.+)$")
        local key, title
        if action == "show" then
            for savedKey, savedTitle in pairs(QuesterDB.hiddenQuests) do
                if tostring(savedKey):lower() == query or savedTitle:lower() == query then
                    key, title = savedKey, savedTitle
                    break
                end
            end
        end
        if not key then
            local _, _, _, quests = CollectTargets(true)
            for _, quest in ipairs(quests or {}) do
                if quest.title:lower() == query or tostring(quest.key):lower() == query then
                    key, title = quest.key, quest.title
                    break
                end
            end
        end
        if not key then Print("Quest not found. /quester hidden lists available quests."); return end
        QuesterDB.hiddenQuests[key] = action == "hide" and title or nil
        ScheduleUpdate()
        Print((action == "hide" and "Quest hidden: " or "Quest restored: ") .. title)
    elseif command == "resume" then
        NS.ResumeAutomation()
        Print("Error lock cleared. Talk to the quest giver again.")
    elseif command == "inspect" then
        NS.InspectTarget()
    elseif command == "objectives" then
        local _, rows = CollectTargets()
        if not rows then Print("Quest log API unavailable."); return end
        local overview = ObjectiveOverview(rows)
        Print(overview.completed .. "/" .. overview.total .. " quest objectives completed.")
        for _, row in ipairs(overview.pending) do
            Print(row.title .. ": " .. row.text)
        end
        if #overview.pending == 0 then Print("No unfinished quest objectives.") end
    elseif command == "priority clear" then
        QuesterDB.priorityQuest = nil
        ScheduleUpdate()
        Print("Quest priority cleared.")
    elseif command == "priority" or command:match("^priority%s+") then
        local _, rows = CollectTargets()
        if not rows then Print("Quest log API unavailable."); return end
        local query = command:match("^priority%s+(.+)$")
        if query then
            for _, row in ipairs(rows) do
                if row.title:lower() == query or (row.questID and tostring(row.questID) == query) then
                    QuesterDB.priorityQuest = { id = row.questID and row.questID > 0 and row.questID or nil, title = row.title }
                    ScheduleUpdate()
                    Print("Prioritized quest: " .. row.title)
                    return
                end
            end
            Print("Quest not found. /quester priority lists available quests.")
        else
            Print("/quester priority <quest name or ID> | priority clear")
            local seen = {}
            for _, row in ipairs(rows) do
                local key = row.questID or row.title
                if not seen[key] then
                    seen[key] = true
                    Print((row.priority and "* " or "") .. row.title .. (row.questID and " [" .. row.questID .. "]" or ""))
                end
            end
        end
    elseif command == "debug" then
        Print(NS.lastStatus or "No quest data yet.")
        Print(NS.lastQuestAction or "No quest interaction yet.")
        for _, row in ipairs(NS.lastRows or {}) do
            Print(row.title .. ": " .. row.text .. " → " .. (row.name or "no enemy name"))
        end
    elseif command == "auto" or command == "auto on" or command == "auto off" then
        local enabled = command == "auto on" or (command == "auto" and not QuesterDB.autoAccept)
        QuesterDB.autoAccept, QuesterDB.autoTurnIn = enabled, enabled
        if enabled then NS.ResumeAutomation() end
        Print("Quest acceptance and turn-in: " .. (enabled and "on" or "off"))
    elseif command == "turnin" then
        QuesterDB.autoTurnIn = not QuesterDB.autoTurnIn
        Print("Quest turn-in: " .. (QuesterDB.autoTurnIn and "on" or "off"))
    elseif command == "macro" then
        QuesterDB.targetMacro = not QuesterDB.targetMacro
        Print("Macro updates: " .. (QuesterDB.targetMacro and "on" or "off"))
        ScheduleUpdate()
    elseif command == "notify" or command == "notify on" or command == "notify off" then
        QuesterDB.notifyReady = command == "notify on"
            or (command == "notify" and not QuesterDB.notifyReady)
        Print("Turn-in notifications: " .. (QuesterDB.notifyReady and "on" or "off"))
    elseif command == "sell" or command == "sell on" or command == "sell off" then
        QuesterDB.autoSellGrey = command == "sell on"
            or (command == "sell" and not QuesterDB.autoSellGrey)
        Print("Automatically sell grey items: " .. (QuesterDB.autoSellGrey and "on" or "off"))
    elseif command == "repair" or command == "repair on" or command == "repair off" then
        QuesterDB.autoRepair = command == "repair on"
            or (command == "repair" and not QuesterDB.autoRepair)
        Print("Automatically repair equipment: " .. (QuesterDB.autoRepair and "on" or "off"))
    elseif command == "trivial" then
        QuesterDB.acceptTrivial = not QuesterDB.acceptTrivial
        Print("Select trivial quests in dialogues: " .. (QuesterDB.acceptTrivial and "on" or "off"))
    elseif command == "update" then
        ScheduleUpdate()
        Print(InCombatLockdown() and "Update deferred until combat ends." or "Update requested.")
    else
        Print("/quester settings | show [quest name/ID] | hide [quest name/ID] | hidden [clear] | exclude quest/npc/item [ID/name] | allow quest/npc/item [ID/name] | exceptions [clear] | objectives | priority [quest name/ID/clear] | inspect | debug | resume | auto [on/off] | turnin | macro | notify [on/off] | sell [on/off] | repair [on/off] | trivial | update")
        Print("Quest acceptance: " .. (QuesterDB.autoAccept and "on" or "off")
            .. "; Turn-in: " .. (QuesterDB.autoTurnIn and "on" or "off")
            .. "; Macro: " .. (QuesterDB.targetMacro and "on" or "off")
            .. "; Targets: " .. targetCount .. "; Omitted due to the size limit: " .. omitted)
    end
end
