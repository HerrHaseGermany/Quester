local NS, frames, commands = {}, {}, {}
local refreshed, resumed, visible = 0, 0, nil
QuesterDB = { autoAccept = true, autoTurnIn = false, windowHidden = true,
    hiddenQuests = { [42] = "Hidden quest" }, priorityQuest = { title = "Priority quest" },
    automationExceptions = { item = { [10] = "Protected item" } } }
UIParent = {}
GameTooltip = {Hide = function() end}
local function Widget()
    local widget = {scripts = {}}
    function widget:SetScript(event, callback) self.scripts[event] = callback end
    function widget:SetText(value) self.text = value end
    function widget:GetText() return self.text or "" end
    function widget:SetChecked(value) self.checked = value end
    function widget:GetChecked() return self.checked end
    function widget:CreateFontString() return Widget() end
    for _, method in ipairs({ "SetPoint", "SetSize", "SetWidth", "SetHeight", "SetScrollChild",
        "SetJustifyH", "SetAutoFocus", "SetMaxLetters", "Hide", "SetFocus", "ClearFocus" }) do
        widget[method] = function() end
    end
    return widget
end
function CreateFrame(kind, name, parent, template)
    local widget = Widget()
    widget.kind, widget.name, widget.parent, widget.template = kind, name, parent, template
    widget.Text = Widget()
    frames[#frames + 1] = widget
    return widget
end
function NS.Refresh() refreshed = refreshed + 1 end
function NS.ResumeAutomation() resumed = resumed + 1 end
function NS.ShowWindow() visible = true end
function NS.HideWindow() visible = false end
SlashCmdList = {QUESTER = function(command) commands[#commands + 1] = command end}
local registered, opened
Settings = {
    RegisterCanvasLayoutCategory = function(panel, name)
        assert(panel.name == name and name == "Quester")
        return {GetID = function() return 123 end}
    end,
    RegisterAddOnCategory = function(category) registered = category end,
    OpenToCategory = function(id) opened = id end,
}
assert(loadfile('settings.lua'))('Quester', NS)
NS.InitSettings()
local count = #frames
NS.InitSettings(); assert(#frames == count and registered)
local panel = frames[1]
panel.scripts.OnShow()
local checks, inputs, buttons = {}, {}, {}
for _, frame in ipairs(frames) do
    if frame.kind == "CheckButton" then checks[frame.Text.text] = frame end
    if frame.kind == "EditBox" then inputs[#inputs + 1] = frame end
    if frame.kind == "Button" then buttons[frame.text] = frame end
end
local function Click(label, checked)
    local button = checks[label]
    button:SetChecked(checked)
    button.scripts.OnClick(button)
end
assert(checks['Quests automatisch annehmen']:GetChecked())
assert(not checks['Quests automatisch abgeben']:GetChecked())
assert(not checks['Questfenster anzeigen']:GetChecked())
Click('Quests automatisch abgeben', true); assert(QuesterDB.autoTurnIn and resumed == 1)
Click('Ausrüstung automatisch reparieren', true); assert(QuesterDB.autoRepair)
Click('Questfenster anzeigen', true); assert(not QuesterDB.windowHidden and visible)
Click('Questfenster anzeigen', false); assert(QuesterDB.windowHidden and visible == false)
Click('Questfenster einklappen', true); assert(QuesterDB.windowCollapsed)
Click('Zielmakro automatisch aktualisieren', false); assert(not QuesterDB.targetMacro and refreshed == 4)
QuesterDB.autoRepair = false
panel.scripts.OnShow(); assert(not checks['Ausrüstung automatisch reparieren']:GetChecked())
inputs[1]:SetText('  42  ')
buttons.Priorisieren.scripts.OnClick(); assert(commands[#commands] == 'priority 42')
buttons.Ausblenden.scripts.OnClick(); assert(commands[#commands] == 'hide 42')
inputs[4]:SetText('Protected item')
buttons['Ausschließen'].scripts.OnClick(); assert(commands[#commands] == 'exclude item Protected item')
buttons['Automatik fortsetzen'].scripts.OnClick(); assert(commands[#commands] == 'resume')
NS.OpenSettings(); assert(opened == 123)
print('PASS: settings registration, saved values, toggles, window inversion, effects, command actions and opening')

Settings = nil
local legacyPanel, legacyOpened, legacyCount
function InterfaceOptions_AddCategory(value) legacyPanel = value end
function InterfaceOptionsFrame_OpenToCategory(value)
    legacyOpened, legacyCount = value, (legacyCount or 0) + 1
end
assert(loadfile('settings.lua'))('Quester', NS)
NS.OpenSettings()
assert(legacyPanel == legacyOpened and legacyCount == 2)
print('PASS: legacy interface-options registration and opening')
