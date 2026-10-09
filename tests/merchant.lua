local NS, sold = {}, {}
local shift, combat, shown = false, false, true
QuesterDB = {}
NUM_BAG_SLOTS = 0
function IsShiftKeyDown() return shift end
function InCombatLockdown() return combat end
MerchantFrame = { IsShown = function() return shown end }
local items = {
    {itemID=1, quality=0}, -- sellable
    {itemID=2, quality=1}, -- higher quality
    {itemID=3, quality=0, isLocked=true},
    {itemID=4, quality=0, hasNoValue=true},
    {itemID=5, quality=0}, -- protected by ID
    {itemID=6, quality=0}, -- protected by name
    {itemID=7, quality=0}, -- quest item
    {itemID=8, quality=0}, -- uncached
    {itemID=9, quality=0}, -- no price
    {itemID=10, quality=0}, -- quest class
}
C_Container = {
    GetContainerNumSlots = function() return #items end,
    GetContainerItemInfo = function(_, slot) return items[slot] end,
    GetContainerItemQuestInfo = function(_, slot) return {isQuestItem=slot==7} end,
    UseContainerItem = function(_, slot) sold[#sold+1] = slot end,
}
function GetItemInfo(id)
    if id == 8 then return end
    return 'Item ' .. id, nil, 0, nil, nil, nil, nil, nil, nil, nil,
        id == 9 and 0 or 100, id == 10 and 12 or 0
end
assert(loadfile('automation.lua'))('Quester', NS)
local function command(text) assert(NS.HandleExceptionCommand(text, function() end)) end
command('exclude item 5'); command('exclude item Item 6')
NS.HandleMerchantEvent('MERCHANT_SHOW'); assert(#sold==0)
QuesterDB.autoSellGrey=true
shift=true; NS.HandleMerchantEvent('MERCHANT_SHOW'); assert(#sold==0); shift=false
combat=true; NS.HandleMerchantEvent('MERCHANT_SHOW'); assert(#sold==0); combat=false
shown=false; NS.HandleMerchantEvent('MERCHANT_SHOW'); assert(#sold==0); shown=true
NS.HandleMerchantEvent('MERCHANT_SHOW'); assert(#sold==1 and sold[1]==1)
command('allow item 5'); command('allow item Item 6')
sold={}; NS.HandleMerchantEvent('MERCHANT_SHOW')
assert(#sold==3 and sold[1]==1 and sold[2]==5 and sold[3]==6)
-- Legacy tuple APIs sell the same safe slots and respect quest flags.
function GetContainerNumSlots() return #items end
function GetContainerItemInfo(_, slot)
    local item=items[slot]
    return 1, 1, item.isLocked, item.quality, nil, nil,
        'item:'..item.itemID, nil, item.hasNoValue, item.itemID
end
function GetContainerItemQuestInfo(_, slot) return slot==7 end
UseContainerItem=C_Container.UseContainerItem
C_Container=nil
sold={}; NS.HandleMerchantEvent('MERCHANT_SHOW'); assert(#sold==3)
assert(not NS.HandleMerchantEvent('BAG_UPDATE_DELAYED'))
print('PASS: merchant setting, Shift/combat, closed merchant, ID/name protection, locked/quest/uncached/valueless items, modern and legacy APIs')

local repairs, messages = 0, {}
local repairVendor, cost, damaged, gold = true, 12345, true, 12345
function CanMerchantRepair() return repairVendor end
function GetRepairAllCost() return cost, damaged end
function GetMoney() return gold end
function RepairAllItems(guildBank)
    assert(guildBank == false)
    repairs = repairs + 1
end
DEFAULT_CHAT_FRAME = {AddMessage = function(_, message) messages[#messages+1] = message end}
QuesterDB.autoSellGrey = false
NS.HandleMerchantEvent('MERCHANT_SHOW'); assert(repairs == 0 and #messages == 0)
QuesterDB.autoRepair = true
shift=true; NS.HandleMerchantEvent('MERCHANT_SHOW'); shift=false
combat=true; NS.HandleMerchantEvent('MERCHANT_SHOW'); combat=false
shown=false; NS.HandleMerchantEvent('MERCHANT_SHOW'); shown=true
repairVendor=false; NS.HandleMerchantEvent('MERCHANT_SHOW'); repairVendor=true
damaged=false; NS.HandleMerchantEvent('MERCHANT_SHOW'); damaged=true
assert(repairs == 0 and #messages == 0)
NS.HandleMerchantEvent('MERCHANT_SHOW')
assert(repairs == 1 and messages[1]:find('Kosten: 1g 23s 45c', 1, true))
gold=12000; NS.HandleMerchantEvent('MERCHANT_SHOW')
assert(repairs == 1 and messages[2]:find('Nicht genug Gold', 1, true)
    and messages[2]:find('fehlend: 0g 3s 45c', 1, true))
print('PASS: optional personal-gold repairs, Shift/combat, vendor checks, undamaged equipment, costs and insufficient gold')
