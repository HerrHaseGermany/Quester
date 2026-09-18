local addonName, NS = ...
local frame = CreateFrame("Frame")
local macroName = "QuesterTarget"
local queued, ready, slotWarning = false, false, false
local targetCount, omitted = 0, 0

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
local function CollectTargets()
    local names, seen, rows = {}, {}, {}
    local function AddObjective(title, text, kind, finished, questID, objective)
        objective = objective or { text = text, type = kind, finished = finished }
        if type(objective.numRequired) == "number" and objective.numRequired > 0
            and type(objective.numFulfilled) == "number" and objective.numFulfilled >= objective.numRequired then
            finished = true
        end
        local learned = not finished and NS.GetLearnedTargets(questID, objective) or {}
        local targets = learned
        if #targets == 0 and kind == "monster" and not finished then
            local name = TargetName(text)
            if name then targets = { name } end
        end
        local function AddRow(name)
            rows[#rows + 1] = { title = title or "Quest", text = text or "Zieltext wird geladen …",
                kind = kind, finished = finished, name = name, questID = questID,
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
                local objectives = C_QuestLog.GetQuestObjectives(info.questID)
                if not objectives or #objectives == 0 then
                    rows[#rows + 1] = { title = info.title or "Quest", text = "Keine Zielzeilen von der Quest-API geliefert.", kind = "empty" }
                end
                for _, objective in ipairs(objectives or {}) do
                    AddObjective(info.title, objective.text, objective.type, objective.finished, info.questID, objective)
                end
            end
        end
    elseif GetNumQuestLogEntries and GetQuestLogTitle
        and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
        for index = 1, GetNumQuestLogEntries() do
            local title, _, _, header = GetQuestLogTitle(index)
            if not header then
                for objective = 1, GetNumQuestLeaderBoards(index) do
                    AddObjective(title, GetQuestLogLeaderBoard(objective, index))
                end
            end
        end
    else
        if not apiWarning then
            Print("Questlog-API nicht verfügbar; Zielmakro bleibt unverändert.")
            apiWarning = true
        end
        return nil
    end
    return names, rows
end

local function UpdateMacro()
    if not ready then return end
    local names, rows = CollectTargets()
    if not names then
        NS.Render({}, "Questlog-API nicht verfügbar. Makro unverändert.", {})
        return
    end
    local body, included = "/cleartarget", {}
    targetCount, omitted = 0, 0
    for _, name in ipairs(names) do
        local line = "\n/targetexact " .. name .. "\n/stopmacro [exists,nodead]"
        if #body + #line <= 255 then
            body = body .. line
            included[name] = true
            targetCount = targetCount + 1
        else
            omitted = omitted + 1
        end
    end
    if targetCount == 0 then body = "#showtooltip" end

    local status = targetCount .. " Ziele im globalen Makro; " .. omitted .. " ohne Platz."
    if not QuesterDB.targetMacro then
        status = "Makro-Aktualisierung aus. Vorschau: " .. targetCount .. " Ziele."
    elseif InCombatLockdown() then
        status = "Im Kampf: Makro unverändert. Vorschau: " .. targetCount .. " Ziele."
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
            status = "Kein freier globaler Makroplatz. Bitte unter /macro Platz schaffen."
            if not slotWarning then Print(status); slotWarning = true end
        end
        -- Remove the obsolete addon-owned character copy only after global creation succeeds.
        if macroIndex and macroIndex > 0 and macroIndex <= limit then
            for index = limit + characters, limit + 1, -1 do
                if GetMacroInfo(index) == macroName then
                    DeleteMacro(index)
                    Print("Makro auf global umgestellt. QuesterTarget unter Allgemeine Makros neu auf die Leiste ziehen.")
                end
            end
        end
    end
    if #rows == 0 then
        status = status .. " Keine Questziele geliefert; Questlog-Kategorien aufklappen."
    elseif #names == 0 then
        status = status .. " Keine offenen Gegnernamen erkannt; /quester debug zeigt die Zieltexte."
    end
    NS.lastRows, NS.lastStatus = rows, status
    NS.Render(rows, status, included, body)
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
        ready = true
        NS.InitWindow()
        NS.InitLearning()
    elseif NS.HandleQuestEvent(event, name, ...) then
        -- Quest-dialog automation handles its own delayed actions.
    else
        ScheduleUpdate()
    end
end)

for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "QUEST_DETAIL", "GOSSIP_SHOW",
    "QUEST_GREETING", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED",
    "PLAYER_REGEN_ENABLED", "UPDATE_MACROS", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_FINISHED", "GOSSIP_CLOSED", "UI_ERROR_MESSAGE", "QUEST_TURNED_IN", "BAG_UPDATE_DELAYED" }) do
    frame:RegisterEvent(event)
end

SLASH_QUESTER1 = "/quester"
SlashCmdList.QUESTER = function(input)
    local command = input:lower():match("^%s*(.-)%s*$")
    if command == "" or command == "show" then
        NS.ShowWindow()
        ScheduleUpdate()
    elseif command == "hide" then
        NS.HideWindow()
    elseif command == "resume" then
        NS.ResumeAutomation()
        Print("Sperre aufgehoben. Questgeber erneut ansprechen.")
    elseif command == "inspect" then
        NS.InspectTarget()
    elseif command == "debug" then
        Print(NS.lastStatus or "Noch keine Questdaten.")
        Print(NS.lastQuestAction or "Noch keine Questinteraktion.")
        for _, row in ipairs(NS.lastRows or {}) do
            Print(row.title .. ": " .. row.text .. " → " .. (row.name or "kein Gegnername"))
        end
    elseif command == "auto" or command == "auto on" or command == "auto off" then
        local enabled = command == "auto on" or (command == "auto" and not QuesterDB.autoAccept)
        QuesterDB.autoAccept, QuesterDB.autoTurnIn = enabled, enabled
        if enabled then NS.ResumeAutomation() end
        Print("Questannahme und Abgabe: " .. (enabled and "an" or "aus"))
    elseif command == "turnin" then
        QuesterDB.autoTurnIn = not QuesterDB.autoTurnIn
        Print("Questabgabe: " .. (QuesterDB.autoTurnIn and "an" or "aus"))
    elseif command == "macro" then
        QuesterDB.targetMacro = not QuesterDB.targetMacro
        Print("Makro-Aktualisierung: " .. (QuesterDB.targetMacro and "an" or "aus"))
        ScheduleUpdate()
    elseif command == "trivial" then
        QuesterDB.acceptTrivial = not QuesterDB.acceptTrivial
        Print("Graue Quests im Dialog auswählen: " .. (QuesterDB.acceptTrivial and "an" or "aus"))
    elseif command == "update" then
        ScheduleUpdate()
        Print(InCombatLockdown() and "Aktualisierung nach Kampfende vorgemerkt." or "Aktualisierung angefordert.")
    else
        Print("/quester show | hide | inspect | debug | resume | auto [on/off] | turnin | macro | trivial | update")
        Print("Questannahme: " .. (QuesterDB.autoAccept and "an" or "aus")
            .. "; Abgabe: " .. (QuesterDB.autoTurnIn and "an" or "aus")
            .. "; Makro: " .. (QuesterDB.targetMacro and "an" or "aus")
            .. "; Ziele: " .. targetCount .. "; wegen Platzlimit ausgelassen: " .. omitted)
    end
end
