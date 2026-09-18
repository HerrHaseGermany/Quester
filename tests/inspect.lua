local NS = {}
local exists, player = true, false
local calls, messages = 0, {}
local secret = {}
function issecretvalue(value) return value == secret end
function UnitExists(unit) assert(unit == 'target'); return exists end
function UnitIsPlayer() return player end
function UnitName() return 'Kobold Worker' end
function UnitGUID() return 'Creature-0-123-0-55-257-0000012345' end
function UnitCanAttack() return true end
function UnitIsDead() return false end
function GetBuildInfo() return '1.60.1', '69913', 'Sep 18 2026', 16001 end
function GetLocale() return 'enUS' end
function InCombatLockdown() return false end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) messages[#messages + 1] = message end }
Enum = { TooltipDataLineType = { QuestObjective = 8 } }
C_TooltipInfo = { GetUnit = function(unit)
    assert(unit == 'target'); calls = calls + 1
    return { lines = {
        { type = 2, leftText = 'Kobold Worker' },
        { type = 8, questID = 47, leftText = 'Gold Dust: 2/10', customBetaField = 17, restricted = secret },
    } }
end }
C_QuestLog = {
    GetNumQuestLogEntries = function() return 2 end,
    GetInfo = function(index)
        if index == 1 then return { title = 'Elwynn', isHeader = true } end
        return { title = 'Gold Dust Exchange', questID = 47 }
    end,
    GetQuestObjectives = function(id)
        assert(id == 47)
        return {{ text = 'Gold Dust: 2/10', type = 'item', numFulfilled = 2, numRequired = 10 }}
    end,
    GetQuestsOnMap = function(id) assert(id == 1429); return {{ questID = 47, x = 0.4, y = 0.5 }} end,
}
C_Map = { GetBestMapForUnit = function() return 1429 end }
assert(loadfile('inspect.lua'))('Quester', NS)
local report = assert(NS.BuildInspection())
assert(report:find('NPC%-ID: 257'))
assert(report:find('questID=47', 1, true))
assert(report:find('customBetaField=17', 1, true))
assert(report:find('Gold Dust: 2/10', 1, true))
assert(report:find('restricted=<geschützt>', 1, true))
assert(report:find('Map-ID: 1429', 1, true))
assert(report:find('type="item"', 1, true))
exists = false
local count = calls
local empty, reason = NS.BuildInspection()
assert(not empty and reason:find('anvisieren') and calls == count)
exists, player = true, true
assert(not NS.BuildInspection()); assert(calls == count)
player = false
-- Missing modern tooltip support falls back to an isolated GameTooltip.
local scan = { hidden = false }
function scan:SetOwner() end
function scan:ClearLines() end
function scan:SetUnit(unit) assert(unit == 'target') end
function scan:NumLines() return 1 end
function scan:Hide() self.hidden = true end
function CreateFrame(kind, name)
    assert(kind == 'GameTooltip' and name == 'QuesterInspectScanTooltip')
    return scan
end
UIParent = {}
QuesterInspectScanTooltipTextLeft1 = { GetText = function() return 'Gold Dust: 2/10' end }
C_TooltipInfo, C_Map, C_QuestLog = nil, nil, nil
report = assert(NS.BuildInspection())
assert(report:find('API fehlt', 1, true))
assert(report:find('Gold Dust: 2/10', 1, true) and scan.hidden)
-- A failed modern call still captures fallback data and identifies the failure.
C_TooltipInfo = { GetUnit = function() error('unavailable in this client') end }
report = assert(NS.BuildInspection())
assert(report:find('API-Aufruf fehlgeschlagen', 1, true))
assert(report:find('Gold Dust: 2/10', 1, true))
-- Legacy quest APIs retain all objective fields, including item type.
function GetNumQuestLogEntries() return 1 end
function GetQuestLogTitle() return 'Gold Dust Exchange' end
function GetNumQuestLeaderBoards() return 1 end
function GetQuestLogLeaderBoard() return 'Gold Dust: 2/10', 'item', false end
report = assert(NS.BuildInspection())
assert(report:find('type="item"', 1, true))
print('PASS: NPC ID, raw tooltip fields, item objectives, map context, secret values, no target/player, missing/failed APIs, legacy fallback')

-- Report UI opens only on explicit inspection and exposes copyable text.
local frames, methods = {}, {}
local function object(name)
    local value = setmetatable({ scripts = {}, shown = false }, { __index = methods })
    if name then frames[name] = value end
    return value
end
for _, name in ipairs({ 'SetSize', 'SetPoint', 'SetFrameStrata', 'SetClampedToScreen',
    'EnableMouse', 'SetBackdrop', 'SetBackdropColor', 'SetMultiLine', 'SetAutoFocus',
    'SetFontObject', 'SetWidth', 'SetMaxLetters', 'SetScrollChild' }) do
    methods[name] = function() end
end
function methods:SetText(value) self.text = value end
function methods:SetScript(name, value) self.scripts[name] = value end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
function methods:SetFocus() self.focused = true end
function methods:ClearFocus() self.focused = false end
function methods:HighlightText() self.highlighted = true end
function methods:CreateFontString() return object() end
local editor
function CreateFrame(kind, name)
    local result = object(name)
    if kind == 'EditBox' then editor = result end
    return result
end
NS.InspectTarget()
assert(frames.QuesterInspectWindow.shown)
assert(editor.text == NS.lastInspection and editor.focused and editor.highlighted)
editor.scripts.OnEscapePressed()
assert(not frames.QuesterInspectWindow.shown and not editor.focused)
exists = false
NS.InspectTarget()
assert(not frames.QuesterInspectWindow.shown and #messages > 0)
print('PASS: explicit report window, copy selection, Escape, no-target feedback')
