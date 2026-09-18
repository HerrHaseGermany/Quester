function GetTime() return 100 end
local NS, timers, calls = {}, {}, {}
local shift, combat, questID, choices, money, completable = false, false, 42, 0, 0, true
local available = {{questID=42, isTrivial=true}}
local active = {{questID=41, isComplete=false}}
QuesterDB = {autoAccept=true, autoTurnIn=true, acceptTrivial=true}
DEFAULT_CHAT_FRAME = {AddMessage=function() end}
C_Timer = {After=function(_, fn) timers[#timers+1]=fn end}
function IsShiftKeyDown() return shift end
function InCombatLockdown() return combat end
function GetQuestID() return questID end
function GetNumQuestChoices() return choices end
function GetQuestMoneyToGet() return money end
function IsQuestCompletable() return completable end
function AcceptQuest() calls[#calls+1]='accept' end
function CompleteQuest() calls[#calls+1]='complete' end
function GetQuestReward(index) calls[#calls+1]='reward:'..index end
C_GossipInfo = {
    GetActiveQuests=function() return active end,
    GetAvailableQuests=function() return available end,
    SelectActiveQuest=function(id) calls[#calls+1]='active:'..id end,
    SelectAvailableQuest=function(id) calls[#calls+1]='available:'..id end,
}
assert(loadfile('automation.lua'))('Quester',NS)
local function flush()
    local batch=timers; timers={}
    for _,fn in ipairs(batch) do fn() end
end
local function event(name) assert(NS.HandleQuestEvent(name)); flush() end
NS.HandleQuestEvent('GOSSIP_SHOW'); assert(#calls==0); flush()
assert(calls[#calls]=='available:42')
event('QUEST_DETAIL'); assert(calls[#calls]=='accept')
NS.HandleQuestEvent('QUEST_ACCEPTED',42)
active={{questID=41,isComplete=0},{questID=43,isComplete=true}}
event('GOSSIP_SHOW'); assert(calls[#calls]=='active:43')
event('QUEST_PROGRESS'); assert(calls[#calls]=='complete')
event('QUEST_COMPLETE'); assert(calls[#calls]=='reward:0')
NS.HandleQuestEvent('QUEST_TURNED_IN',42)
choices=1; event('QUEST_COMPLETE'); assert(calls[#calls]=='reward:1')
local count=#calls
NS.HandleQuestEvent('QUEST_TURNED_IN',42)
choices=2; event('QUEST_COMPLETE'); assert(#calls==count)
choices=0; money=100; event('QUEST_COMPLETE'); event('QUEST_PROGRESS'); assert(#calls==count)
money=0; completable=false; event('QUEST_PROGRESS'); assert(#calls==count); completable=true
-- Pause applies both at receipt and execution; releasing Shift doesn't resume an old dialog.
shift=true; NS.HandleQuestEvent('QUEST_DETAIL'); shift=false; flush(); assert(#calls==count)
NS.HandleQuestEvent('QUEST_DETAIL'); shift=true; flush(); assert(#calls==count); shift=false
combat=true; event('QUEST_COMPLETE'); assert(#calls==count); combat=false
NS.HandleQuestEvent('QUEST_DETAIL'); NS.HandleQuestEvent('QUEST_FINISHED'); flush(); assert(#calls==count)
NS.HandleQuestEvent('QUEST_DETAIL'); questID=99; flush(); assert(#calls==count)
NS.HandleQuestEvent('GOSSIP_SHOW'); NS.HandleQuestEvent('GOSSIP_CLOSED'); flush(); assert(#calls==count)
-- Gossip closes as the selected quest detail opens: don't cancel the new detail.
NS.HandleQuestEvent('GOSSIP_SHOW'); NS.HandleQuestEvent('QUEST_DETAIL'); NS.HandleQuestEvent('GOSSIP_CLOSED'); flush()
assert(#calls==count+1 and calls[#calls]=='accept')
count=#calls
QuesterDB.autoAccept=false; event('QUEST_DETAIL'); assert(#calls==count)
QuesterDB.autoTurnIn=false; event('QUEST_COMPLETE'); assert(#calls==count)
QuesterDB.autoAccept=true; QuesterDB.acceptTrivial=false; active={}
event('GOSSIP_SHOW'); assert(#calls==count)
-- Classic greeting API is still supported.
function GetNumActiveQuests() return 2 end
function GetActiveTitle(i) return 'Quest', i==2 and 1 or 0 end
function SelectActiveQuest(i) calls[#calls+1]='legacy-active:'..i end
function GetNumAvailableQuests() return 1 end
function GetAvailableQuestInfo() return false end
function SelectAvailableQuest(i) calls[#calls+1]='legacy-available:'..i end
QuesterDB.autoTurnIn=true; event('QUEST_GREETING'); assert(calls[#calls]=='legacy-active:2')
QuesterDB.autoTurnIn=false; event('QUEST_GREETING'); assert(calls[#calls]=='legacy-available:1')
NS.ResumeAutomation()
AcceptQuest=nil; event('QUEST_DETAIL'); assert(NS.lastQuestAction:find('API fehlt',1,true))
assert(not NS.HandleQuestEvent('QUEST_LOG_UPDATE'))
print('PASS: deferred acceptance, gossip/legacy selection, turn-in stages, 0/1/multiple rewards, cost confirmation, Shift/combat, closed/replaced dialogs, settings')

-- Inventory errors can arrive synchronously inside the reward/accept API call.
local notices = 0
DEFAULT_CHAT_FRAME.AddMessage = function() notices = notices + 1 end
ERR_INV_FULL = 'Inventory is full.'
ERR_QUEST_FAILED_BAG_FULL = 'Quest failed: Inventory is full.'
ERR_QUEST_FAILED_MAX_COUNT_S = 'Too many of the item required for %s.'
QuesterDB.autoAccept, QuesterDB.autoTurnIn = true, true
choices, money = 0, 0
NS.ResumeAutomation()
GetQuestReward = function(index)
    calls[#calls+1]='reward:'..index
    NS.HandleQuestEvent('UI_ERROR_MESSAGE', 50, ERR_INV_FULL)
end
local before = #calls
event('QUEST_COMPLETE')
assert(#calls == before + 1 and notices == 1)
for i=1,20 do
    event('QUEST_FINISHED'); event('GOSSIP_SHOW'); event('QUEST_PROGRESS'); event('QUEST_COMPLETE')
end
assert(#calls == before + 1 and notices == 1, 'error loop must remain latched across dialog changes')
-- Freeing inventory must not restart the process without explicit user action.
assert(NS.HandleQuestEvent('BAG_UPDATE_DELAYED'))
event('QUEST_COMPLETE'); assert(#calls == before + 1)
NS.ResumeAutomation()
GetQuestReward = function(index) calls[#calls+1]='reward:'..index end
event('QUEST_COMPLETE'); assert(#calls == before + 2)
NS.HandleQuestEvent('QUEST_TURNED_IN', questID)
event('QUEST_COMPLETE'); assert(#calls == before + 3, 'confirmed success permits next transaction')
-- A queued action is invalidated as soon as an inventory error is observed.
NS.ResumeAutomation()
AcceptQuest = function() calls[#calls+1]='accept' end
event('QUEST_DETAIL')
before = #calls
NS.HandleQuestEvent('QUEST_COMPLETE')
NS.HandleQuestEvent('UI_ERROR_MESSAGE', 50, ERR_QUEST_FAILED_BAG_FULL)
flush(); assert(#calls == before)
-- Old one-argument error form and formatted localized messages are supported.
NS.ResumeAutomation(); event('QUEST_DETAIL'); before = #calls
NS.HandleQuestEvent('UI_ERROR_MESSAGE', 'Too many of the item required for Quest Name.')
event('QUEST_DETAIL'); assert(#calls == before)
-- Missing or unknown error events still cannot cause repeated calls.
NS.ResumeAutomation(); event('QUEST_DETAIL'); before = #calls
for i=1,20 do event('QUEST_FINISHED'); event('QUEST_DETAIL') end
assert(#calls == before)
assert(NS.lastQuestAction:find('ohne bestätigten Erfolg', 1, true))
-- Selection loops (before acceptance is reached) are bounded as well.
NS.ResumeAutomation(); active={{questID=43,isComplete=true}}
event('GOSSIP_SHOW'); before=#calls
event('GOSSIP_SHOW'); event('GOSSIP_SHOW'); assert(#calls==before)
-- Unrelated errors outside an automation attempt are ignored.
NS.ResumeAutomation()
NS.HandleQuestEvent('UI_ERROR_MESSAGE', 50, ERR_INV_FULL)
event('QUEST_DETAIL'); assert(calls[#calls]=='accept')
NS.HandleQuestEvent('QUEST_ACCEPTED', questID)
NS.HandleQuestEvent('UI_ERROR_MESSAGE', 50, ERR_INV_FULL)
before=#calls; event('QUEST_DETAIL'); assert(#calls==before+1)
print('PASS: inventory loops, synchronous errors, cancellation, explicit resume, success reset, fallback guard, selection loops, no unrelated-error latch')


-- Automatic recovery requires genuinely improved inventory, not repeated bag events.
local slots = { {itemID=100,stackCount=1}, {itemID=200,stackCount=20} }
NUM_BAG_SLOTS = 0
C_Container = {
    GetContainerNumSlots = function() return 2 end,
    GetContainerItemInfo = function(_,slot) return slots[slot] end,
}
QuestFrameRewardPanel = {IsShown=function() return true end}
NS.ResumeAutomation()
GetQuestReward = function() calls[#calls+1]='blocked-reward'; NS.HandleQuestEvent('UI_ERROR_MESSAGE',50,ERR_INV_FULL) end
event('QUEST_COMPLETE'); before=#calls
for i=1,20 do event('BAG_UPDATE_DELAYED'); event('QUEST_COMPLETE') end
assert(#calls==before)
-- Merely moving stacks between slots does not remove the block.
slots[1],slots[2] = slots[2],slots[1]
event('BAG_UPDATE_DELAYED'); assert(#calls==before)
slots[2]=nil
GetQuestReward = function() calls[#calls+1]='recovered-reward' end
event('BAG_UPDATE_DELAYED')
assert(#calls==before+1 and calls[#calls]=='recovered-reward')
-- If the retry still fails (not enough room), it pauses against the new state.
NS.ResumeAutomation()
slots[2]={itemID=300,stackCount=1}
GetQuestReward = function() calls[#calls+1]='blocked-again'; NS.HandleQuestEvent('UI_ERROR_MESSAGE',50,ERR_INV_FULL) end
event('QUEST_COMPLETE'); slots[2]=nil
event('BAG_UPDATE_DELAYED'); before=#calls
for i=1,10 do event('BAG_UPDATE_DELAYED'); event('QUEST_COMPLETE') end
assert(#calls==before)
-- A closed dialog is not reopened. Future NPC interaction works without a command.
event('QUEST_FINISHED'); slots[1]=nil
event('BAG_UPDATE_DELAYED'); assert(#calls==before)
GetQuestReward = function() calls[#calls+1]='next-dialog' end
event('QUEST_COMPLETE'); assert(#calls==before+1)
-- Combat postpones recovery until combat ends.
NS.ResumeAutomation(); slots[1]={itemID=100,stackCount=1}
GetQuestReward = function() calls[#calls+1]='combat-block'; NS.HandleQuestEvent('UI_ERROR_MESSAGE',50,ERR_INV_FULL) end
event('QUEST_COMPLETE'); before=#calls
combat=true; slots[1]=nil; event('BAG_UPDATE_DELAYED'); assert(#calls==before)
combat=false
GetQuestReward = function() calls[#calls+1]='after-combat' end
NS.HandleQuestEvent('PLAYER_REGEN_ENABLED'); flush()
assert(#calls==before+1 and calls[#calls]=='after-combat')
print('PASS: automatic inventory recovery, unchanged/moved contents, repeat failure, closed dialog and combat deferral')
