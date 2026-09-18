local _, NS = ...
local phase, generation = nil, 0
local stopped, lastAttempt = false, nil
local attempts = {}
local attemptState, blockedState
local Recover
local function Status(text) NS.lastQuestAction = text end
local function Paused()
    return IsShiftKeyDown() or InCombatLockdown()
end
local function ReadResources()
    local state = { items = {}, free = 0 }
    if C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo then
        for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                local item = C_Container.GetContainerItemInfo(bag, slot)
                if item and item.itemID then
                    state.items[item.itemID] = (state.items[item.itemID] or 0) + (item.stackCount or 1)
                elseif not item then state.free = state.free + 1 end
            end
        end
        state.bags = true
    end
    local getCount = C_QuestLog and C_QuestLog.GetNumQuestLogEntries or GetNumQuestLogEntries
    if getCount then
        local _, count = getCount()
        state.quests = count
    end
    return state
end
local function Snapshot()
    local ok, state = pcall(ReadResources)
    return ok and state or nil
end
local function ResourcesImproved(before, after)
    if not before or not after then return false end
    if before.bags and after.bags then
        if after.free > before.free then return true end
        for id, count in pairs(before.items) do
            if (after.items[id] or 0) < count then return true end
        end
    end
    return type(before.quests) == 'number' and type(after.quests) == 'number'
        and after.quests < before.quests
end

local function Stop(reason)
    if stopped then return end
    stopped = true
    blockedState = attemptState or Snapshot()
    generation = generation + 1
    Status('Automatik pausiert: ' .. reason .. '. Fortsetzung automatisch nach freiem Platz.')
    DEFAULT_CHAT_FRAME:AddMessage('Quester: ' .. NS.lastQuestAction)
end

function NS.ResumeAutomation()
    stopped, lastAttempt, attempts = false, nil, {}
    attemptState, blockedState = nil, nil
    generation = generation + 1
    phase = nil
    Status('Sperre aufgehoben; Questgeber erneut ansprechen')
end

local function InventoryError(message)
    if type(message) ~= 'string' then return false end
    for _, key in ipairs({ 'ERR_INV_FULL', 'ERR_QUEST_FAILED_BAG_FULL',
        'ERR_ITEM_MAX_COUNT', 'ERR_QUEST_FAILED_MAX_COUNT_S', 'ERR_QUEST_LOG_FULL' }) do
        local text = _G[key]
        if type(text) == 'string' then
            if message == text then return true end
            -- Quest-name placeholders differ between clients/locales.
            local prefix = text:match('^(.-)%%s')
            if prefix and #prefix > 8 and message:sub(1, #prefix) == prefix then return true end
        end
    end
    return false
end

local function Call(label, fn, ...)
    if stopped then return end
    if type(fn) ~= 'function' then Stop(label .. ': API fehlt'); return end
    local id = (label == 'Quest öffnen' or label == 'Abgabe öffnen') and select(1, ...)
        or (GetQuestID and GetQuestID()) or 0
    local key = label .. ':' .. tostring(id)
    if attempts[key] then
        Stop('wiederholter Questversuch ohne bestätigten Erfolg')
        return
    end
    -- Mark before calling: WoW can synchronously send another dialog/error event.
    attempts[key] = true
    lastAttempt = GetTime()
    attemptState = Snapshot()
    Status(label .. ' angefordert')
    local ok, err = pcall(fn, ...)
    if not ok then Stop(label .. ': ' .. tostring(err)) end
end
local function Complete(value) return value == true or value == 1 end
local function Process(event)
    if stopped then return end
    if Paused() then Status('Durch Shift oder Kampf pausiert'); return end
    if event == 'GOSSIP_SHOW' then
        if QuesterDB.autoTurnIn and C_GossipInfo and C_GossipInfo.GetActiveQuests then
            for _, quest in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
                if Complete(quest.isComplete) then
                    Call('Abgabe öffnen', C_GossipInfo.SelectActiveQuest, quest.questID)
                    return
                end
            end
        end
        if QuesterDB.autoAccept and C_GossipInfo and C_GossipInfo.GetAvailableQuests then
            for _, quest in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
                if not quest.isTrivial or QuesterDB.acceptTrivial then
                    Call('Quest öffnen', C_GossipInfo.SelectAvailableQuest, quest.questID)
                    return
                end
            end
        end
    elseif event == 'QUEST_GREETING' then
        if QuesterDB.autoTurnIn and GetNumActiveQuests and GetActiveTitle then
            for index = 1, GetNumActiveQuests() do
                local _, finished = GetActiveTitle(index)
                if Complete(finished) then Call('Abgabe öffnen', SelectActiveQuest, index); return end
            end
        end
        if QuesterDB.autoAccept and GetNumAvailableQuests and GetAvailableQuestInfo then
            for index = 1, GetNumAvailableQuests() do
                local trivial = GetAvailableQuestInfo(index)
                if not trivial or QuesterDB.acceptTrivial then
                    Call('Quest öffnen', SelectAvailableQuest, index); return
                end
            end
        end
    elseif event == 'QUEST_DETAIL' and QuesterDB.autoAccept then
        Call('Quest annehmen', AcceptQuest)
    elseif event == 'QUEST_PROGRESS' and QuesterDB.autoTurnIn then
        if IsQuestCompletable and IsQuestCompletable() then
            if GetQuestMoneyToGet and GetQuestMoneyToGet() > 0 then
                Status('Quest mit Geldkosten: manuelle Bestätigung'); return
            end
            Call('Quest abschließen', CompleteQuest)
        else Status('Quest noch nicht abgabebereit') end
    elseif event == 'QUEST_COMPLETE' and QuesterDB.autoTurnIn then
        if not GetNumQuestChoices then Status('Belohnungs-API fehlt'); return end
        local choices = GetNumQuestChoices()
        if type(choices) ~= 'number' then Status('Belohnungen noch nicht geladen'); return end
        if choices > 1 then Status('Mehrere Belohnungen: bitte selbst auswählen'); return end
        if GetQuestMoneyToGet and GetQuestMoneyToGet() > 0 then
            Status('Quest mit Geldkosten: manuelle Bestätigung'); return
        end
        Call('Questbelohnung abholen', GetQuestReward, choices == 1 and 1 or 0)
    end
end

local panels = {
    GOSSIP_SHOW = 'GossipFrame', QUEST_GREETING = 'QuestFrameGreetingPanel',
    QUEST_DETAIL = 'QuestFrameDetailPanel', QUEST_PROGRESS = 'QuestFrameProgressPanel',
    QUEST_COMPLETE = 'QuestFrameRewardPanel',
}
Recover = function()
    if not stopped or Paused() or not ResourcesImproved(blockedState, Snapshot()) then return end
    local currentPhase = phase
    NS.ResumeAutomation()
    Status('Platz verfügbar; Automatik fortgesetzt')
    local panel = currentPhase and _G[panels[currentPhase]]
    if panel and panel:IsShown() then NS.HandleQuestEvent(currentPhase) end
end

function NS.HandleQuestEvent(event, arg1, arg2)
    if event == 'BAG_UPDATE_DELAYED' or event == 'QUEST_LOG_UPDATE' or event == 'PLAYER_REGEN_ENABLED' then
        Recover()
        return event == 'BAG_UPDATE_DELAYED'
    end
    if event == 'UI_ERROR_MESSAGE' then
        local message = type(arg2) == 'string' and arg2 or arg1
        if lastAttempt and GetTime() - lastAttempt <= 5 and InventoryError(message) then
            Stop('Inventar/Questlog voll oder Gegenstandslimit erreicht')
        end
        return true
    end
    if event == 'QUEST_ACCEPTED' or event == 'QUEST_TURNED_IN' then
        -- Only server-confirmed success permits the same actions again.
        attempts, lastAttempt = {}, nil
        return false -- Main handler must still refresh the target macro.
    end
    if event == 'QUEST_FINISHED' or (event == 'GOSSIP_CLOSED' and phase == 'GOSSIP_SHOW') then
        generation = generation + 1; phase = nil
        return true
    end
    if event ~= 'QUEST_DETAIL' and event ~= 'QUEST_GREETING' and event ~= 'GOSSIP_SHOW'
        and event ~= 'QUEST_PROGRESS' and event ~= 'QUEST_COMPLETE' then return false end
    phase = event
    if stopped then Recover(); return true end
    generation = generation + 1
    local token = generation
    if Paused() then Status('Durch Shift oder Kampf pausiert'); return true end
    local questID = event ~= 'GOSSIP_SHOW' and event ~= 'QUEST_GREETING' and GetQuestID and GetQuestID()
    -- Let Blizzard finish building the dialog before advancing it.
    C_Timer.After(0.05, function()
        if token ~= generation then return end
        if questID and GetQuestID() ~= questID then return end
        Process(event)
    end)
    return true
end
