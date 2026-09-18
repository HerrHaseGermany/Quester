function GetTime() return 100 end
-- Run from the repository root with Lua 5.1 or newer.
local handler, timers, macros = nil, {}, {}
local characterMacros = { { name = "QuesterTarget", body = "#showtooltip" } }
local rendered, renderStatus, windowShown
local NS = {
    InitWindow = function() end,
    InitLearning = function() end,
    GetLearnedTargets = function() return {} end,
    ShowWindow = function() windowShown = true end,
    HideWindow = function() windowShown = false end,
    Render = function(rows, status) rendered = rows; renderStatus = status end,
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
