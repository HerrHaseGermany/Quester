local _, NS = ...
local phase, generation = nil, 0
local stopped, lastAttempt = false, nil
local attempts = {}
local attemptState, blockedState
local Recover
local function Status(text) NS.lastQuestAction = text end
local function ExceptionTables()
    if type(QuesterDB.automationExceptions) ~= 'table' then QuesterDB.automationExceptions = {} end
    local exceptions = QuesterDB.automationExceptions
    for _, kind in ipairs({ 'quest', 'npc', 'item' }) do
        if type(exceptions[kind]) ~= 'table' then exceptions[kind] = {} end
    end
    return exceptions
end
local function NPCIdentity()
    local unit = 'npc'
    local guid = UnitGUID and UnitGUID(unit)
    if not guid then unit = 'target'; guid = UnitGUID and UnitGUID(unit) end
    local kind, id
    if guid then
        kind = guid:match('^([^-]+)-')
        if kind == 'Creature' or kind == 'Vehicle' then
            id = tonumber(guid:match('^[^-]+%-[^-]+%-[^-]+%-[^-]+%-[^-]+%-(%d+)%-'))
        else return nil end
    end
    return id, UnitName and UnitName(unit)
end
local function Excluded(kind, id, title)
    local entries = ExceptionTables()[kind]
    id = type(id) == 'number' and id > 0 and id or nil
    if id and entries[id] then return true end
    if type(title) ~= 'string' or title == '' then return false end
    title = title:lower()
    if entries[title] then return true end
    -- Legacy greeting APIs may expose only titles, even for saved ID exclusions.
    if not id then
        for _, label in pairs(entries) do
            if type(label) == 'string' and label:lower() == title then return true end
        end
    end
    return false
end

function NS.HandleExceptionCommand(input, printMessage)
    local command = input:match('^%s*(.-)%s*$')
    local lower = command:lower()
    if lower == 'exceptions' or lower == 'exceptions clear' then
        local exceptions = ExceptionTables()
        if lower == 'exceptions clear' then
            exceptions.quest, exceptions.npc, exceptions.item = {}, {}, {}
            printMessage('All automation exceptions cleared.')
        else
            printMessage('/quester exclude quest|npc|item [ID/name] | allow quest|npc|item [ID/name] | exceptions clear')
            for _, kind in ipairs({ 'quest', 'npc', 'item' }) do
                for key, label in pairs(exceptions[kind]) do
                    printMessage(kind .. ': ' .. label .. ' [' .. tostring(key) .. ']')
                end
            end
        end
        return true
    end
    local action, kind, query = lower:match('^(%a+)%s+(%a+)%s*(.-)$')
    if action ~= 'exclude' and action ~= 'allow' then return false end
    if kind ~= 'quest' and kind ~= 'npc' and kind ~= 'item' then
        printMessage('/quester ' .. action .. ' quest|npc|item [ID/name]'); return true
    end
    local entries = ExceptionTables()[kind]
    local id, title
    if query == '' then
        if kind == 'item' then
            printMessage('Please provide an item ID or exact name.'); return true
        end
        if kind == 'quest' then
            id, title = GetQuestID and GetQuestID(), GetTitleText and GetTitleText()
        else id, title = NPCIdentity() end
    else
        id = tonumber(query)
        title = command:match('^%S+%s+%S+%s+(.+)$')
    end
    if id and (id <= 0 or id % 1 ~= 0) then
        printMessage('Please provide a positive integer ID.'); return true
    end
    if not id and (not title or title == '') then
        printMessage('No quest or NPC found. Hold Shift while opening the dialogue, or provide an ID or name.'); return true
    end
    local key = id or title:lower()
    if action == 'exclude' then
        entries[key] = title and title ~= '' and title or tostring(id)
        printMessage('Automation exception saved: ' .. entries[key])
    else
        entries[key] = nil
        if not id then
            for savedKey, label in pairs(entries) do
                if type(label) == 'string' and label:lower() == title:lower() then entries[savedKey] = nil end
            end
        end
        printMessage('Automation exception removed: ' .. (title or tostring(id)))
    end
    return true
end
local function Paused()
    return IsShiftKeyDown() or InCombatLockdown()
end

function NS.HandleMerchantEvent(event)
    if event ~= 'MERCHANT_SHOW' then return false end
    if Paused() or (GetCursorInfo and GetCursorInfo())
        or not MerchantFrame or not MerchantFrame:IsShown() then return true end
    if QuesterDB.autoRepair and CanMerchantRepair and CanMerchantRepair()
        and GetRepairAllCost and GetMoney and RepairAllItems then
        local cost, needsRepair = GetRepairAllCost()
        if needsRepair and type(cost) == 'number' and cost > 0 then
            local function Money(amount)
                if GetCoinTextureString then return GetCoinTextureString(amount) end
                return string.format('%dg %ds %dc', math.floor(amount / 10000),
                    math.floor(amount / 100) % 100, amount % 100)
            end
            local gold = GetMoney()
            local message
            if gold >= cost then
                RepairAllItems(false)
                message = 'Equipment automatically repaired. Cost: ' .. Money(cost)
            else
                message = 'Not enough gold for repairs. Cost: ' .. Money(cost)
                    .. '; shortfall: ' .. Money(cost - gold)
            end
            DEFAULT_CHAT_FRAME:AddMessage('|cffffff00Quester:|r ' .. message)
        end
    end
    if not QuesterDB.autoSellGrey then return true end
    local containers = C_Container or {}
    local slots = containers.GetContainerNumSlots or GetContainerNumSlots
    local info = containers.GetContainerItemInfo or GetContainerItemInfo
    local use = containers.UseContainerItem or UseContainerItem
    local questInfo = containers.GetContainerItemQuestInfo or GetContainerItemQuestInfo
    local itemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
    if not slots or not info or not use or not itemInfo then return true end
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        for slot = 1, slots(bag) do
            local item, _, locked, quality, _, _, link, _, noValue, itemID = info(bag, slot)
            if type(item) == 'table' then
                locked, quality, link, noValue, itemID = item.isLocked, item.quality,
                    item.hyperlink, item.hasNoValue, item.itemID
            end
            if item and quality == 0 and not locked and not noValue and (itemID or link) then
                itemID = itemID or (link and tonumber(link:match('item:(%d+)')))
                local name, _, _, _, _, _, _, _, _, _, price, classID = itemInfo(itemID or link)
                local isQuestItem, questID
                if questInfo then
                    local quest, id = questInfo(bag, slot)
                    if type(quest) == 'table' then
                        isQuestItem, questID = quest.isQuestItem, quest.questID
                    else
                        isQuestItem, questID = quest, id
                    end
                end
                -- Uncached, valueless, quest-related and explicitly protected items stay in the bags.
                if name and price and price > 0 and classID ~= 12 and not isQuestItem
                    and not questID and not Excluded('item', itemID, name) then
                    if Paused() or not QuesterDB.autoSellGrey
                        or (GetCursorInfo and GetCursorInfo())
                        or not MerchantFrame or not MerchantFrame:IsShown() then return true end
                    use(bag, slot)
                end
            end
        end
    end
    return true
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
    Status('Automation paused: ' .. reason .. '. Resumes automatically when space is freed.')
    DEFAULT_CHAT_FRAME:AddMessage('Quester: ' .. NS.lastQuestAction)
end

function NS.ResumeAutomation()
    stopped, lastAttempt, attempts = false, nil, {}
    attemptState, blockedState = nil, nil
    generation = generation + 1
    phase = nil
    Status('Error lock cleared; talk to the quest giver again')
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
    if type(fn) ~= 'function' then Stop(label .. ': API unavailable'); return end
    local id = (label == 'Open quest' or label == 'Open turn-in') and select(1, ...)
        or (GetQuestID and GetQuestID()) or 0
    local key = label .. ':' .. tostring(id)
    if attempts[key] then
        Stop('repeated quest attempt without confirmed success')
        return
    end
    -- Mark before calling: WoW can synchronously send another dialog/error event.
    attempts[key] = true
    lastAttempt = GetTime()
    attemptState = Snapshot()
    Status(label .. ' requested')
    local ok, err = pcall(fn, ...)
    if not ok then Stop(label .. ': ' .. tostring(err)) end
end
local function Complete(value) return value == true or value == 1 end
local function Process(event)
    if stopped then return end
    if Paused() then Status('Paused by Shift or combat'); return end
    local npcID, npcName = NPCIdentity()
    if Excluded('npc', npcID, npcName) then Status('NPC excluded from automation'); return end
    if event ~= 'GOSSIP_SHOW' and event ~= 'QUEST_GREETING'
        and Excluded('quest', GetQuestID and GetQuestID(), GetTitleText and GetTitleText()) then
        Status('Quest excluded from automation'); return
    end
    if event == 'GOSSIP_SHOW' then
        if QuesterDB.autoTurnIn and C_GossipInfo and C_GossipInfo.GetActiveQuests then
            for _, quest in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
                if Complete(quest.isComplete) and not Excluded('quest', quest.questID, quest.title) then
                    Call('Open turn-in', C_GossipInfo.SelectActiveQuest, quest.questID)
                    return
                end
            end
        end
        if QuesterDB.autoAccept and C_GossipInfo and C_GossipInfo.GetAvailableQuests then
            for _, quest in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
                if (not quest.isTrivial or QuesterDB.acceptTrivial)
                    and not Excluded('quest', quest.questID, quest.title) then
                    Call('Open quest', C_GossipInfo.SelectAvailableQuest, quest.questID)
                    return
                end
            end
        end
    elseif event == 'QUEST_GREETING' then
        if QuesterDB.autoTurnIn and GetNumActiveQuests and GetActiveTitle then
            for index = 1, GetNumActiveQuests() do
                local title, finished = GetActiveTitle(index)
                if Complete(finished) and not Excluded('quest', GetActiveQuestID and GetActiveQuestID(index), title) then
                    Call('Open turn-in', SelectActiveQuest, index); return
                end
            end
        end
        if QuesterDB.autoAccept and GetNumAvailableQuests and GetAvailableQuestInfo then
            for index = 1, GetNumAvailableQuests() do
                local trivial = GetAvailableQuestInfo(index)
                if (not trivial or QuesterDB.acceptTrivial)
                    and not Excluded('quest', GetAvailableQuestID and GetAvailableQuestID(index),
                        GetAvailableTitle and GetAvailableTitle(index)) then
                    Call('Open quest', SelectAvailableQuest, index); return
                end
            end
        end
    elseif event == 'QUEST_DETAIL' and QuesterDB.autoAccept then
        Call('Accept quest', AcceptQuest)
    elseif event == 'QUEST_PROGRESS' and QuesterDB.autoTurnIn then
        if IsQuestCompletable and IsQuestCompletable() then
            if GetQuestMoneyToGet and GetQuestMoneyToGet() > 0 then
                Status('Quest with monetary costs: manual confirmation required'); return
            end
            Call('Complete quest', CompleteQuest)
        else Status('Quest not yet ready for turn-in') end
    elseif event == 'QUEST_COMPLETE' and QuesterDB.autoTurnIn then
        if not GetNumQuestChoices then Status('Reward API unavailable'); return end
        local choices = GetNumQuestChoices()
        if type(choices) ~= 'number' then Status('Rewards not yet loaded'); return end
        if choices > 1 then Status('Multiple rewards: please choose manually'); return end
        if GetQuestMoneyToGet and GetQuestMoneyToGet() > 0 then
            Status('Quest with monetary costs: manual confirmation required'); return
        end
        Call('Collect quest reward', GetQuestReward, choices == 1 and 1 or 0)
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
    Status('Space available; automation resumed')
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
            Stop('inventory or quest log full, or item limit reached')
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
    if Paused() then Status('Paused by Shift or combat'); return true end
    local questID = event ~= 'GOSSIP_SHOW' and event ~= 'QUEST_GREETING' and GetQuestID and GetQuestID()
    -- Let Blizzard finish building the dialog before advancing it.
    C_Timer.After(0.05, function()
        if token ~= generation then return end
        if questID and GetQuestID() ~= questID then return end
        Process(event)
    end)
    return true
end
