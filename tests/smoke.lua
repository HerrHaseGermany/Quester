function GetTime() return 100 end
-- Run from the repository root with Lua 5.1 or newer.
local handler, timers, macros = nil, {}, {}
local characterMacros = { { name = "QuesterTarget", body = "#showtooltip" } }
local rendered, renderStatus, windowShown, renderedItems
local NS = {
    InitWindow = function() end,
    InitLearning = function() end,
    GetLearnedTargets = function() return {} end,
    ShowWindow = function() windowShown = true end,
    HideWindow = function() windowShown = false end,
    Render = function(rows, status, _, _, items) rendered = rows; renderStatus = status; renderedItems = items end,
}
local combat, shift, accepted, edits, selected = false, false, 0, 0, nil
local objectives = { { 'Wolf slain: 0/2', 'monster', false } }
QUEST_MONSTERS_KILLED = '%s slain: %d/%d'
MAX_ACCOUNT_MACROS, MAX_CHARACTER_MACROS = 120, 18
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
SlashCmdList = {}
function CreateFrame() return {
    SetScript = function(_, _, fn) handler = fn end,
    RegisterEvent = function() end,
} end
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function flush()
    local batch = timers; timers = {}
    for _, fn in ipairs(batch) do fn() end
end
local function event(name, arg) handler(nil, name, arg) end
function GetLocale() return "enUS" end
function InCombatLockdown() return combat end
function IsShiftKeyDown() return shift end
function GetNumQuestLogEntries() return 1 end
function GetQuestLogTitle() return 'Hunt', 1, nil, false, false, 0 end
function GetNumQuestLeaderBoards() return #objectives end
function GetQuestLogLeaderBoard(i) return unpack(objectives[i]) end
function GetNumMacros() return #macros, #characterMacros end
function GetMacroInfo(i)
    local entry = i > 120 and characterMacros[i - 120] or macros[i]
    return entry and entry.name
end
function GetMacroBody(i) return macros[i].body end
function CreateMacro(name, _, body, character)
    assert(not combat and not character)
    macros[#macros + 1] = { name = name, body = body }
    return #macros
end
function EditMacro(i, name, _, body)
    assert(not combat); edits = edits + 1
    macros[i] = { name = name, body = body }
end
function DeleteMacro(i)
    assert(not combat and #macros > 0 and i > 120)
    table.remove(characterMacros, i - 120)
end
function AcceptQuest() accepted = accepted + 1 end
C_GossipInfo = {
    GetAvailableQuests = function() return {{ questID = 1, isTrivial = true }, { questID = 2 }} end,
    SelectAvailableQuest = function(id) selected = id end,
}
function GetNumAvailableQuests() return 1 end
function GetAvailableQuestInfo() return false end
function SelectAvailableQuest(i) selected = i end
assert(loadfile('automation.lua'))('Quester', NS)
QuesterDB = { acceptTrivial = false }
assert(loadfile('quester.lua'))('Quester', NS)
event('ADDON_LOADED', 'Quester'); event('PLAYER_LOGIN'); flush()
assert(macros[1].body:find('/targetexact Wolf', 1, true))
assert(#characterMacros == 0, 'character copy migrated after global creation')
event('QUEST_DETAIL'); flush(); assert(accepted == 1)
NS.HandleQuestEvent('QUEST_ACCEPTED',42)
shift = true; event('QUEST_DETAIL'); flush(); assert(accepted == 1)
shift = false; event('GOSSIP_SHOW'); flush(); assert(selected == 2)
event('QUEST_GREETING'); flush(); assert(selected == 1)
SlashCmdList.QUESTER('auto'); event('QUEST_DETAIL'); flush(); assert(accepted == 1)
combat = true; objectives[1][3] = true
event('QUEST_LOG_UPDATE'); flush(); assert(edits == 0)
combat = false; event('PLAYER_REGEN_ENABLED'); flush()
assert(macros[1].body == '#showtooltip')
QUEST_MONSTERS_KILLED = '%s getötet: %d/%d'
objectives = {{ 'Wölfin getötet: 0/2', 'monster', false },
              { 'Wölfin getötet: 0/2', 'monster', false },
              { 'Fell: 0/2', 'item', false },
              { 'Bad\n/run evil getötet: 0/2', 'monster', false }}
event('QUEST_LOG_UPDATE'); flush()
local _, count = macros[1].body:gsub('/targetexact', '')
assert(count == 1 and macros[1].body:find('Wölfin', 1, true))
for i = 1, 30 do objectives[i] = { 'Wolf' .. i .. ' getötet: 0/2', 'monster', false } end
event('QUEST_LOG_UPDATE'); flush(); assert(#macros[1].body <= 255)
local before = edits
event('QUEST_LOG_UPDATE'); event('QUEST_LOG_UPDATE'); flush(); assert(edits == before)
SlashCmdList.QUESTER('macro'); objectives = {}; flush(); assert(edits == before)
SlashCmdList.QUESTER('macro'); flush(); assert(macros[1].body == '#showtooltip')
print('PASS: acceptance, Shift, gossip, toggle, combat deferral, localized targets, deduplication, injection rejection, length limit, no-op updates')

-- Regression: this client exposes only the namespaced quest log API.
GetNumQuestLogEntries, GetQuestLogTitle = nil, nil
GetNumQuestLeaderBoards, GetQuestLogLeaderBoard = nil, nil
C_QuestLog = {
    GetNumQuestLogEntries = function() return 4 end,
    GetInfo = function(index)
        if index == 1 then return { isHeader = true } end
        if index == 2 then return nil end
        return { questID = index == 3 and 42 or 43 }
    end,
    GetQuestObjectives = function(id)
        if id == 43 then return nil end
        assert(id == 42)
        return {
            { text = 'Bär getötet: 0/2', type = 'monster', finished = false },
            { text = 'Wolf getötet: 2/2', type = 'monster', finished = true },
        }
    end,
}
event('QUEST_LOG_UPDATE'); flush()
assert(macros[1].body:find('/targetexact Bär', 1, true))
assert(not macros[1].body:find('Wolf', 1, true))
local saved = macros[1].body
C_QuestLog = nil
event('QUEST_LOG_UPDATE'); flush(); assert(macros[1].body == saved)
print('PASS: modern-only API, quest IDs, missing entries/objectives, completed objectives, unavailable API')

-- Bare counters, positional formats and readable rows even with macro updates off.
C_QuestLog = {
    GetNumQuestLogEntries = function() return 1 end,
    GetInfo = function() return { questID = 42, title = 'Waldjagd' } end,
    GetQuestObjectives = function() return {
        { text = 'Waldwolf: 0 / 8', type = 'monster', finished = false },
        { text = 'Fell: 0/8', type = 'item', finished = false },
        { text = 'Unbekanntes Ziel', type = 'monster', finished = false },
        { text = 'Wolf getötet: 2/2', type = 'monster', finished = true },
    } end,
}
event('QUEST_LOG_UPDATE'); flush()
assert(macros[1].body:find('/targetexact Waldwolf', 1, true))
assert(#rendered == 4 and rendered[1].title == 'Waldjagd')
assert(rendered[2].kind == 'item' and not rendered[2].name)
assert(not rendered[3].name and rendered[4].finished)
QUEST_MONSTERS_KILLED = '%1$s getötet: %2$d/%3$d'
C_QuestLog.GetQuestObjectives = function() return {
    { text = '|cffffffffBär getötet: 0/4|r', type = 'monster', finished = false },
} end
event('QUEST_LOG_UPDATE'); flush()
assert(macros[1].body:find('/targetexact Bär', 1, true))
SlashCmdList.QUESTER('macro'); flush()
assert(#rendered == 1 and renderStatus:find('aus', 1, true))
SlashCmdList.QUESTER(''); assert(windowShown)
SlashCmdList.QUESTER('hide'); assert(not windowShown)
-- A full global macro bank must retain the old character copy.
SlashCmdList.QUESTER('macro')
macros = {}
for i = 1, 120 do macros[i] = { name = 'Other' .. i, body = 'untouched' } end
characterMacros = {{ name = 'QuesterTarget', body = 'old' }}
flush()
assert(#characterMacros == 1 and #macros == 120)
assert(renderStatus:find('Kein freier globaler', 1, true))
print('PASS: global migration, full account slots, bare counters, positional formats, colors, diagnostic rows, window commands')

-- Actual reported regression: plural objective versus singular NPC name.
macros, characterMacros = {}, {}
QUEST_MONSTERS_KILLED = '%s slain: %d/%d'
C_QuestLog.GetQuestObjectives = function() return {
    { text = 'Kobold Workers slain: 0/10', type = 'monster', finished = false },
    { text = 'Princess slain: 0/1', type = 'monster', finished = false },
} end
event('QUEST_LOG_UPDATE'); flush()
assert(macros[1].body:find('/targetexact Kobold Worker\n', 1, true))
assert(not macros[1].body:find('Kobold Workers', 1, true))
assert(macros[1].body:find('/targetexact Princess\n', 1, true))
assert(rendered[1].name == 'Kobold Worker')
function GetLocale() return 'deDE' end
C_QuestLog.GetQuestObjectives = function() return {
    { text = 'Workers: 0/10', type = 'monster', finished = false },
} end
event('QUEST_LOG_UPDATE'); flush()
assert(rendered[1].name == 'Workers', 'English normalization must not modify other locales')
print('PASS: Kobold Workers regression, singular names preserved, locale-specific aliases')

-- Integrate tooltip learning with the actual macro collector.
local mainHandler = handler
function GetLocale() return 'enUS' end
function GetBuildInfo() return '1.60.1', '69913', '', 16001 end
function UnitExists() return true end
function UnitIsPlayer() return false end
function UnitCanAttack() return true end
function UnitName() return 'Kobold Worker' end
function UnitGUID() return 'Creature-0-123-0-55-257-0000012345' end
local book = {text='5/8 Stolen Book', type='item', finished=false}
C_QuestLog.GetInfo = function() return { questID=91743, title='Rascally Rodents' } end
C_QuestLog.GetQuestObjectives = function() return {book} end
C_TooltipInfo = { GetUnit = function() return {lines={
    {type=17, id=91743}, {type=8, completed=false, leftText='5/8 Stolen Book'},
}} end }
assert(loadfile('learning.lua'))('Quester', NS)
NS.InitLearning()
handler = mainHandler
assert(NS.LearnUnit('target')); flush()
assert(macros[1].body:find('/targetexact Kobold Worker\n', 1, true))
assert(rendered[1].source == 'tooltip' and rendered[1].kind == 'item')
combat = true; book.finished = true
event('QUEST_LOG_UPDATE'); flush()
assert(macros[1].body:find('Kobold Worker', 1, true), 'combat mutation deferred')
combat = false; event('PLAYER_REGEN_ENABLED'); flush()
assert(macros[1].body == '#showtooltip')
book.finished = false; event('QUEST_LOG_UPDATE'); flush()
assert(macros[1].body:find('Kobold Worker', 1, true))
C_QuestLog.GetNumQuestLogEntries = function() return 0 end
event('QUEST_LOG_UPDATE'); flush()
assert(macros[1].body == '#showtooltip', 'abandoned quest must remove learned target')
print('PASS: learned collection target in macro/icons, completion, combat deferral, abandoned quest')

-- Priority reorders both icons and macro while progress counts objectives once.
local first = { text = 'Wolf: 2/8', type = 'monster', numFulfilled = 2, numRequired = 8 }
local second = { text = 'Bear: 1/3', type = 'monster' }
local shared = { text = 'Wolf: 0/4', type = 'monster' }
C_QuestLog.GetNumQuestLogEntries = function() return 2 end
C_QuestLog.GetInfo = function(index)
    return { questID = index, title = index == 1 and 'Wolf Hunt' or 'Bear Hunt' }
end
C_QuestLog.GetQuestObjectives = function(id)
    return id == 1 and { first } or { second, shared }
end
event('QUEST_LOG_UPDATE'); flush()
assert(rendered[1].fulfilled == 2 and rendered[1].required == 8)
assert(rendered[2].fulfilled == 1 and rendered[2].required == 3)
SlashCmdList.QUESTER('priority 2'); flush()
assert(QuesterDB.priorityQuest.id == 2)
assert(rendered[1].name == 'Bear' and rendered[1].priority)
assert(macros[1].body:find('/targetexact Bear') < macros[1].body:find('/targetexact Wolf'))
SlashCmdList.QUESTER('priority Missing Quest'); flush()
assert(QuesterDB.priorityQuest.id == 2, 'invalid selection preserves priority')
combat = true
local priorityBody = macros[1].body
SlashCmdList.QUESTER('priority Wolf Hunt'); flush()
assert(macros[1].body == priorityBody, 'priority mutation deferred during combat')
combat = false; event('PLAYER_REGEN_ENABLED'); flush()
assert(rendered[1].name == 'Wolf' and rendered[1].priority)
SlashCmdList.QUESTER('priority clear'); flush()
assert(not QuesterDB.priorityQuest and not rendered[1].priority)
second.text = 'Bear: 3/3'
event('QUEST_LOG_UPDATE'); flush()
assert(NS.objectiveOverview.total == 3 and NS.objectiveOverview.completed == 1)
local messages = {}
DEFAULT_CHAT_FRAME.AddMessage = function(_, message) messages[#messages + 1] = message end
SlashCmdList.QUESTER('objectives')
assert(#messages == 3 and messages[1]:find('1/3', 1, true))

-- A single objective can produce several learned enemy rows.
NS.GetLearnedTargets = function() return {'Wolf', 'Bear'} end
C_QuestLog.GetNumQuestLogEntries = function() return 1 end
C_QuestLog.GetQuestObjectives = function() return { first } end
event('QUEST_LOG_UPDATE'); flush()
assert(#rendered == 2 and NS.objectiveOverview.total == 1)

-- Legacy clients retain title-based priority and parsed progress counters.
C_QuestLog = nil
NS.GetLearnedTargets = function() return {} end
function GetNumQuestLogEntries() return 2 end
function GetQuestLogTitle(index) return index == 1 and 'Wolf Hunt' or 'Bear Hunt', 1, nil, false end
function GetNumQuestLeaderBoards() return 1 end
function GetQuestLogLeaderBoard(_, index)
    return index == 1 and 'Wolf: 2/8' or 'Bear: 1/3', 'monster', false
end
SlashCmdList.QUESTER('priority Bear Hunt'); flush()
assert(not QuesterDB.priorityQuest.id and QuesterDB.priorityQuest.title == 'Bear Hunt')
assert(rendered[1].name == 'Bear' and rendered[1].fulfilled == 1 and rendered[1].required == 3)
print('PASS: priority by ID/title, stable target order, combat deferral, invalid selection, clear, progress and overview deduplication, legacy fallback')

-- Quest actions use log indices and remain available without objective rows.
local owned, complete, keepComplete = 1, false, false
function GetQuestLogSpecialItemInfo(index)
    assert(index == 1 or index == 2)
    return '|Hitem:123|h[Net]|h', 456, 3, keepComplete
end
C_Item = { GetItemCount = function(id) assert(id == 123); return owned end }
event('BAG_UPDATE_DELAYED'); flush()
assert(#renderedItems == 1 and #renderedItems[1].quests == 2)
assert(renderedItems[1].id == 123 and renderedItems[1].texture == 456)
C_QuestLog = {
    GetNumQuestLogEntries = function() return 1 end,
    GetInfo = function() return { questID = 42, title = 'Summon' } end,
    GetQuestObjectives = function() return {} end,
    IsComplete = function() return complete end,
}
event('QUEST_LOG_UPDATE'); flush()
assert(#renderedItems == 1 and renderedItems[1].quests[1].questID == 42)
complete = true; event('QUEST_LOG_UPDATE'); flush(); assert(#renderedItems == 0)
keepComplete = true; event('QUEST_LOG_UPDATE'); flush(); assert(#renderedItems == 1)
owned = 0; event('BAG_UPDATE_DELAYED'); flush(); assert(#renderedItems == 0)
GetQuestLogSpecialItemInfo = nil
event('QUEST_LOG_UPDATE'); flush(); assert(#renderedItems == 0)
print('PASS: modern/legacy quest items, deduplication, empty objectives, completion policy, ownership and unavailable API')

-- Hidden quests exclude their rows and actions, preserving shared targets/items.
C_QuestLog.GetNumQuestLogEntries = function() return 2 end
C_QuestLog.GetInfo = function(index) return {questID = index, title = index == 1 and 'Wolf Hunt' or 'Bear Hunt'} end
C_QuestLog.GetQuestObjectives = function(id)
    return id == 1 and {{text = 'Wolf: 0/8', type = 'monster'}}
        or {{text = 'Wolf: 0/4', type = 'monster'}, {text = 'Bear: 0/3', type = 'monster'}}
end
C_QuestLog.IsComplete = nil
owned = 1
function GetQuestLogSpecialItemInfo() return '|Hitem:123|h[Net]|h', 456 end
event('QUEST_LOG_UPDATE'); flush()
SlashCmdList.QUESTER('hide Wolf Hunt'); flush()
assert(QuesterDB.hiddenQuests[1] == 'Wolf Hunt' and #rendered == 2)
assert(macros[1].body:find('Wolf', 1, true), 'shared enemy remains visible')
assert(#renderedItems == 1 and #renderedItems[1].quests == 1 and renderedItems[1].quests[1].questID == 2)
event('ADDON_LOADED', 'Quester'); event('PLAYER_LOGIN'); flush()
assert(QuesterDB.hiddenQuests[1] and #rendered == 2, 'saved exclusions survive initialization')
combat = true
local visibleBody = macros[1].body
SlashCmdList.QUESTER('hide 2'); flush()
assert(macros[1].body == visibleBody, 'hide macro update deferred during combat')
combat = false; event('PLAYER_REGEN_ENABLED'); flush()
assert(macros[1].body == '#showtooltip' and #rendered == 0 and #renderedItems == 0)
SlashCmdList.QUESTER('show 1'); flush()
assert(not QuesterDB.hiddenQuests[1] and #rendered == 1)
SlashCmdList.QUESTER('hide Missing'); flush()
assert(QuesterDB.hiddenQuests[2] and not QuesterDB.hiddenQuests[1])
SlashCmdList.QUESTER('hidden clear'); flush()
assert(not next(QuesterDB.hiddenQuests) and #rendered == 3)
C_QuestLog.GetQuestObjectives = function() return {} end
SlashCmdList.QUESTER('hide 1'); flush()
assert(#rendered == 1 and #renderedItems[1].quests == 1, 'quests with no objectives can be hidden')
C_QuestLog.GetNumQuestLogEntries = function() return 0 end
messages = {}; SlashCmdList.QUESTER('hidden')
assert(messages[2]:find('Wolf Hunt', 1, true), 'inactive saved exclusions remain listed')
SlashCmdList.QUESTER('show Wolf Hunt'); flush()
assert(not next(QuesterDB.hiddenQuests), 'inactive quests can be restored by saved title')
C_QuestLog = nil
SlashCmdList.QUESTER('hide Bear Hunt'); flush()
assert(QuesterDB.hiddenQuests['Bear Hunt'] and #rendered == 1 and rendered[1].name == 'Wolf')
SlashCmdList.QUESTER('show Bear Hunt'); flush()
assert(not next(QuesterDB.hiddenQuests) and #rendered == 2)
print('PASS: hidden quests by ID/title, saved state, shared targets/items, combat deferral, empty objectives, inactive restoration and legacy fallback')

-- Turn-in readiness comes from quest status, including quests without counters.
C_QuestLog = {
    GetNumQuestLogEntries = function() return 3 end,
    GetInfo = function(index) return { questID = index, title = 'Quest ' .. index } end,
    IsComplete = function(id) return id ~= 3 end,
    GetQuestObjectives = function(id)
        if id == 1 then return {} end
        if id == 2 then return {
            { text = 'Speak to the scout', type = 'event' },
            { text = 'Wolf: 0/2', type = 'monster' },
        } end
        return {{ text = 'Wolf: 2/2', type = 'monster', finished = true }}
    end,
}
event('QUEST_LOG_UPDATE'); flush()
assert(#NS.objectiveOverview.readyQuests == 2, 'deduplicate ready quests; completed counters alone do not imply turn-in readiness')
assert(NS.objectiveOverview.readyQuests[1].questID == 1, 'ready quest without objectives remains visible')
assert(#NS.objectiveOverview.pending == 0 and macros[1].body == '#showtooltip', 'ready quests no longer produce targets')
C_QuestLog.IsComplete = function() return false end
event('QUEST_LOG_UPDATE'); flush()
assert(#NS.objectiveOverview.readyQuests == 0, 'readiness refresh clears stale entries')
C_QuestLog = nil
function GetNumQuestLogEntries() return 3 end
function GetQuestLogTitle(index) return 'Delivery ' .. index, 1, nil, false, false, index == 1 and true or (index == 2 and 1 or -1), nil, index end
function GetNumQuestLeaderBoards() return 0 end
event('QUEST_LOG_UPDATE'); flush()
assert(#NS.objectiveOverview.readyQuests == 2, 'legacy boolean/numeric readiness includes empty quests and excludes failed quests')
assert(NS.objectiveOverview.total == 0)

local notifications = {}
UIErrorsFrame = { AddMessage = function(_, message) notifications[#notifications + 1] = message end }
assert(QuesterDB.notifyReady == false, 'notifications default to off')
SlashCmdList.QUESTER('notify on')
event('QUEST_LOG_UPDATE'); flush()
assert(#notifications == 0, 'enabling notifications does not repeat existing readiness')
local deliveryReady = false
function GetQuestLogTitle(index) return 'Delivery ' .. index, 1, nil, false, false, deliveryReady and 1 or 0, nil, index end
event('QUEST_LOG_UPDATE'); flush()
QuesterDB.hiddenQuests[1] = 'Delivery 1'
deliveryReady = true
event('QUEST_LOG_UPDATE'); event('QUEST_LOG_UPDATE'); flush()
assert(#notifications == 3 and notifications[1]:find('Delivery 1', 1, true), 'notify once per quest, including hidden quests')
event('QUEST_LOG_UPDATE'); flush()
assert(#notifications == 3, 'unchanged readiness does not repeat notifications')
deliveryReady = false; event('QUEST_LOG_UPDATE'); flush()
deliveryReady = true; event('QUEST_LOG_UPDATE'); flush()
assert(#notifications == 6, 'a new transition to ready can notify again')
SlashCmdList.QUESTER('notify off')
deliveryReady = false; event('QUEST_LOG_UPDATE'); flush()
deliveryReady = true; event('QUEST_LOG_UPDATE'); flush()
SlashCmdList.QUESTER('notify on'); event('QUEST_LOG_UPDATE'); flush()
assert(#notifications == 6, 'disabled notifications still track readiness')
print('PASS: optional turn-in notifications, hidden quests, status transitions and duplicate suppression')
print('PASS: actual turn-in status, counterless quests, deduplication, readiness refresh and legacy completion flags')
