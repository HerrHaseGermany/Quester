-- Reproduces the 1.60.1/69913 user diagnostic, including adjacent completed quest.
local timers, handler, refreshes = {}, nil, 0
local exists, player, attackable = true, false, true
local npcID, npcName, locale = 257, 'Kobold Worker', 'enUS'
local active = {91743, 15, 18}
local objectives = {
    [91743] = {{ finished=false, numFulfilled=5, numRequired=8, objectiveType=1, text='5/8 Stolen Book', type='item' }},
    [15] = {{ finished=true, numFulfilled=10, numRequired=10, objectiveType=0, text='10/10 Kobold Workers slain', type='monster' }},
    [18] = {{ finished=false, numFulfilled=0, numRequired=12, objectiveType=1, text='0/12 Red Burlap Bandana', type='item' }},
}
local lines = {
    {type=2, leftText='Kobold Worker'},
    {type=17, id=91743, leftText='Rascally Rodents'},
    {type=8, completed=false, leftText='5/8 Stolen Book', numFulfilled=5, numRequired=8},
    {type=17, id=15, leftText='Investigate Echo Ridge'},
    {type=8, completed=true, leftText='10/10 Kobold Workers slain', numFulfilled=10, numRequired=10},
}
function UnitExists() return exists end
function UnitIsPlayer() return player end
function UnitCanAttack() return attackable end
function UnitName() return npcName end
function UnitGUID() return 'Creature-0-123-0-55-' .. npcID .. '-0000012345' end
function GetLocale() return locale end
function GetBuildInfo() return '1.60.1', '69913', '', 16001 end
C_QuestLog = {
    GetNumQuestLogEntries = function() return #active end,
    GetInfo = function(index) return { questID = active[index] } end,
    GetQuestObjectives = function(id) return objectives[id] end,
}
C_TooltipInfo = { GetUnit = function() return {lines=lines} end }
Enum = { TooltipDataLineType = { QuestTitle=17, QuestObjective=8 } }
QuesterDB = {}
function CreateFrame() return {
    SetScript = function(_, _, fn) handler = fn end,
    RegisterEvent = function() end,
} end
C_Timer = { After = function(_, fn) timers[#timers+1] = fn end }
local NS = { Refresh = function() refreshes = refreshes + 1 end }
assert(loadfile('learning.lua'))('Quester', NS)
NS.InitLearning()
assert(NS.LearnUnit('target'))
assert(refreshes == 1)
local book = objectives[91743][1]
assert(NS.GetLearnedTargets(91743, book)[1] == 'Kobold Worker')
assert(#NS.GetLearnedTargets(15, objectives[15][1]) == 0)
assert(#NS.GetLearnedTargets(18, objectives[18][1]) == 0)
assert(not NS.LearnUnit('target') and refreshes == 1)
book.text, book.numFulfilled = '6/8 Stolen Book', 6
assert(NS.GetLearnedTargets(91743, book)[1] == 'Kobold Worker', 'counts must not be part of cache key')
book.finished = true
assert(#NS.GetLearnedTargets(91743, book) == 0)
book.finished = false
-- Independent NPCs for the same objective are retained and persisted.
npcID, npcName = 258, 'Kobold Laborer'
assert(NS.LearnUnit('mouseover'))
assert(#NS.GetLearnedTargets(91743, book) == 2)
local reloaded = {Refresh = NS.Refresh}
assert(loadfile('learning.lua'))('Quester', reloaded)
reloaded.InitLearning()
assert(#reloaded.GetLearnedTargets(91743, book) == 2)
locale = 'deDE'; reloaded.InitLearning()
assert(#reloaded.GetLearnedTargets(91743, book) == 0)
locale = 'enUS'; reloaded.InitLearning()
assert(#reloaded.GetLearnedTargets(91743, book) == 2)
-- False positives: unrelated objective, absent quest, orphan line, ambiguous objective.
npcID, npcName = 999, 'Unrelated Mob'
lines = {{type=17,id=18},{type=8,completed=false,leftText='6/8 Stolen Book'}}
assert(not NS.LearnUnit('target'))
lines = {{type=8,completed=false,leftText='6/8 Stolen Book'}}
assert(not NS.LearnUnit('target'))
lines = {{type=17,id=91743},{type=8,completed=false,leftText='6/8 Stolen Book'}}
active = {15,18}; assert(not NS.LearnUnit('target')); active = {91743,15,18}
objectives[91743][2] = book
assert(not NS.LearnUnit('target')); objectives[91743][2] = nil
lines[2].completed = true; assert(not NS.LearnUnit('target')); lines[2].completed = false
lines[2].numRequired, lines[2].numFulfilled = 8, 8
assert(not NS.LearnUnit('target')); lines[2].numRequired, lines[2].numFulfilled = nil, nil
npcName = 'Bad\n/run evil'; assert(not NS.LearnUnit('target')); npcName = 'Unrelated Mob'
player = true; assert(not NS.LearnUnit('target')); player = false
attackable = false; assert(not NS.LearnUnit('target')); attackable = true
C_TooltipInfo.GetUnit = function() error('restricted') end
assert(not NS.LearnUnit('target'))
C_TooltipInfo.GetUnit = function() return {lines=lines} end
-- Event bursts are coalesced; current unit is read after the tooltip has loaded.
handler(nil, 'PLAYER_TARGET_CHANGED'); handler(nil, 'PLAYER_TARGET_CHANGED')
assert(#timers == 1)
timers[1](); timers = {}
assert(#reloaded.GetLearnedTargets(91743, book) == 3)
C_TooltipInfo = nil
assert(not NS.LearnUnit('target'))
print('PASS: supplied Forever fixture, quest isolation, completion, persistence, locale, multiple NPCs, ambiguous/orphan data, unavailable APIs, coalesced events')
