-- Frame simulation verifies secure button configuration and combat deferral.
local frames, buttons, combat = {}, {}, false
local methods = {}
local function object(name)
    local value = setmetatable({ scripts = {}, attributes = {}, shown = true, name = name }, { __index = methods })
    if name then frames[name] = value end
    return value
end
for _, method in ipairs({ 'SetFrameStrata', 'SetClampedToScreen', 'SetMovable',
    'RegisterForDrag', 'RegisterForClicks', 'SetPoint', 'ClearAllPoints',
    'SetNormalTexture', 'SetHighlightTexture', 'StartMoving', 'StopMovingOrSizing',
    'SetBackdrop', 'SetBackdropColor', 'SetBackdropBorderColor', 'SetColorTexture' }) do
    methods[method] = function() assert(not combat, 'protected mutation in combat: ' .. method) end
end
function methods:SetSize(width, height)
    assert(not combat); self.width, self.height = width, height
end
function methods:SetAttribute(key, value)
    assert(not combat); self.attributes[key] = value
end
function methods:SetScript(event, callback) self.scripts[event] = callback end
function methods:SetText(text) self.text = text end
function methods:GetCenter() return 500, 400 end
function methods:Show() assert(not combat); self.shown = true end
function methods:Hide() assert(not combat); self.shown = false end
function methods:CreateFontString() return object() end
function methods:CreateTexture() return object() end
function CreateFrame(_, name, _, template)
    assert(not combat)
    local frame = object(name)
    if template == 'SecureActionButtonTemplate' then buttons[#buttons + 1] = frame end
    return frame
end
function InCombatLockdown() return combat end
UIParent = object()
QuesterDB = {}
local NS = {}
assert(loadfile('window.lua'))('Quester', NS)
NS.InitWindow()
local rows = {
    { title = 'Mine', text = 'Kobold Workers: 0/10', name = 'Kobold Worker' },
    { title = 'Other', text = 'Kobold Workers: 0/10', name = 'Kobold Worker' },
    { title = 'Hunt', text = 'Wolf: 0/8', name = 'Wolf' },
    { title = 'Hunt', text = 'Fell: 0/8', kind = 'item' },
    { title = 'Hunt', text = 'Bear: 1/1', name = 'Bear', finished = true },
}
NS.Render(rows, '2 targets')
assert(#buttons == 2, 'one icon per distinct unfinished target')
assert(frames.QuesterWindow.width == 96 and frames.QuesterWindow.height == 46)
assert(buttons[1].attributes.type1 == 'macro')
assert(buttons[1].attributes.macrotext1 == '/cleartarget\n/targetexact Kobold Worker')
assert(#buttons[1].rows == 2)
NS.HideWindow(); assert(not frames.QuesterWindow.shown and QuesterDB.windowHidden)
NS.ShowWindow(); assert(frames.QuesterWindow.shown and not QuesterDB.windowHidden)
combat = true
NS.Render({}, 'In combat')
NS.HideWindow()
assert(frames.QuesterWindow.shown and buttons[1].shown)
assert(buttons[1].attributes.macrotext1:find('Kobold Worker', 1, true))
combat = false
NS.Render({}, 'Leer')
assert(not frames.QuesterWindow.shown)
assert(not buttons[1].shown and not buttons[1].attributes.macrotext1)
NS.ShowWindow(); assert(frames.QuesterWindow.width == 28)
local many = {}
for index = 1, 10 do many[index] = { name = 'Mob' .. index } end
NS.Render(many, '10 targets')
assert(frames.QuesterWindow.width == 300 and frames.QuesterWindow.height == 80)
print('PASS: compact dimensions, deduplicated icons, secure clicks, combat deferral, visibility and wrapping')

-- Regression: gsub's second return must not reach GameTooltip:SetText as a color.
GameTooltip = {
    SetOwner = function() end,
    SetText = function(self, ...)
        assert(select('#', ...) == 1, 'tooltip title must receive only the text')
        local text = ...
        assert(type(text) == 'string')
        self.text = text
    end,
    AddLine = function() end,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
}
buttons[1].targetName = 'Kobold Laborer'
buttons[1].scripts.OnEnter(buttons[1])
assert(GameTooltip.text == 'Kobold Laborer' and GameTooltip.shown)
buttons[1].scripts.OnLeave(buttons[1])
assert(not GameTooltip.shown)
buttons[1].targetName = 'Name|WithPipe'
buttons[1].scripts.OnEnter(buttons[1])
assert(GameTooltip.text == 'Name||WithPipe')
print('PASS: tooltip hover passes one string, including escaped pipes')

-- Collapse keeps the handle/window visible, remembers preference and defers combat changes.
NS.ToggleCollapsed()
assert(QuesterDB.windowCollapsed and frames.QuesterWindow.shown)
assert(frames.QuesterWindow.width == 28 and not buttons[1].shown)
NS.Render(rows, '2 targets')
assert(frames.QuesterWindow.width == 28 and not buttons[1].shown)
NS.ToggleCollapsed()
assert(not QuesterDB.windowCollapsed and buttons[1].shown)
assert(frames.QuesterWindow.width == 96)
combat = true
NS.ToggleCollapsed()
assert(buttons[1].shown and frames.QuesterWindow.width == 96)
combat = false
NS.Render(rows, '2 targets')
assert(not buttons[1].shown and frames.QuesterWindow.shown)
NS.ToggleCollapsed()
assert(buttons[1].shown)
print('PASS: collapse/expand, persistent state across refreshes, combat deferral')

-- Progress sums distinct objectives for one enemy and marks prioritized quests.
local objective = {}
local progressRows = {
    { name = 'Wolf', title = 'Hunt', text = 'Wolf: 2/8', fulfilled = 2, required = 8, objective = objective, priority = true },
    { name = 'Wolf', title = 'Hunt', text = 'Wolf: 2/8', fulfilled = 2, required = 8, objective = objective },
    { name = 'Wolf', title = 'Other', text = 'Wolf: 1/3', fulfilled = 1, required = 3 },
    { name = 'Bear', title = 'Hunt', text = 'Bear' },
}
NS.Render(progressRows, 'Progress')
assert(buttons[1].progress.text == '3/11' and buttons[1].number.text == '*1')
assert(buttons[2].progress.text == '' and buttons[2].number.text == '2')
combat = true
NS.Render({{name = 'Wolf', fulfilled = 9, required = 10}}, 'Combat')
assert(buttons[1].progress.text == '3/11', 'progress layout deferred in combat')
combat = false
NS.Render({{name = 'Wolf', fulfilled = 9, required = 10}}, 'Updated')
assert(buttons[1].progress.text == '9/10' and buttons[1].number.text == '1')
print('PASS: numeric progress, objective deduplication, priority marker, unknown counters and combat deferral')

local items = {{ id = 123, link = 'item:123', texture = 456, charges = 3,
    quests = {{ title = 'Net quest' }} }}
NS.Render(rows, 'Items', nil, nil, items)
local itemButton = frames.QuesterItemButton1
assert(itemButton.attributes.type1 == 'item' and itemButton.attributes.item1 == 'item:123')
assert(itemButton.shown and itemButton.charges.text == 3 and frames.QuesterWindow.width == 130)
GameTooltip.SetHyperlink = function(self, link) self.link = link end
itemButton.scripts.OnEnter(itemButton)
assert(GameTooltip.link == 'item:123')
combat = true
NS.Render({}, 'Combat', nil, nil, {})
assert(itemButton.shown and itemButton.attributes.item1 == 'item:123')
combat = false
NS.ShowWindow()
assert(not itemButton.shown and not itemButton.attributes.item1)
NS.Render({}, 'Item only', nil, nil, items)
assert(itemButton.shown and frames.QuesterWindow.width == 62)
NS.ToggleCollapsed(); assert(not itemButton.shown)
NS.ToggleCollapsed(); assert(itemButton.shown and itemButton.attributes.item1 == 'item:123')
print('PASS: secure item action, tooltip, shared layout, combat deferral, removal and item-only collapse')
