local _, NS = ...
local panel, category

function NS.InitSettings()
    if panel then return end
    panel = CreateFrame("Frame", "QuesterSettingsPanel", UIParent)
    panel.name = "Quester"
    panel:Hide()

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Quester")
    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", 16, -42)
    subtitle:SetText("Changes are saved immediately account-wide. Hold Shift to pause automation.")

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -66)
    scroll:SetPoint("BOTTOMRIGHT", -34, 16)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(560, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, width) content:SetWidth(width) end)

    local y, checks = 0, {}
    local function Text(text, font)
        local label = content:CreateFontString(nil, "ARTWORK", font or "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", 0, -y)
        label:SetPoint("TOPRIGHT", 0, -y)
        label:SetJustifyH("LEFT")
        label:SetText(text)
        y = y + (font and 28 or 40)
        return label
    end
    local function Check(key, label, description, changed, inverted)
        local button = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
        button:SetSize(26, 26)
        button:SetPoint("TOPLEFT", 0, -y)
        button.Text:SetText(label)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label)
            GameTooltip:AddLine(description, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        button:SetScript("OnClick", function(self)
            local checked = not not self:GetChecked()
            QuesterDB[key] = inverted and not checked or (not inverted and checked)
            if changed then changed(checked) end
        end)
        checks[#checks + 1] = { button = button, key = key, inverted = inverted }
        y = y + 30
    end
    local function Resume(enabled) if enabled then NS.ResumeAutomation() end end
    Text("Quests", "GameFontNormal")
    Check("autoAccept", "Automatically accept quests",
        "Automatically accepts quests, respecting quest and NPC exceptions.", Resume)
    Check("autoTurnIn", "Automatically turn in quests",
        "Turns in completed quests. Multiple reward choices and quests with monetary costs require manual selection or confirmation.", Resume)
    Check("acceptTrivial", "Select trivial quests in dialogues",
        "Also selects low-level quests. Quest details already open follow the automatic acceptance setting.")
    Check("notifyReady", "Notify when quests are ready for turn-in",
        "Shows a message when a quest becomes ready for turn-in.")

    y = y + 12
    Text("Merchants", "GameFontNormal")
    Check("autoSellGrey", "Automatically sell grey items",
        "Sells grey items with a known vendor price. Locked, protected and quest items are kept.")
    Check("autoRepair", "Automatically repair equipment",
        "Repairs using your own gold and reports costs or insufficient gold in chat. Merchant automation pauses while holding Shift or during combat.")

    y = y + 12
    Text("Macro and quest window", "GameFontNormal")
    Check("targetMacro", "Automatically update the target macro",
        "Updates the QuesterTarget macro for unfinished quest objectives. Changes during combat are deferred.", NS.Refresh)
    Check("windowHidden", "Show quest window",
        "Shows the window with quest targets and usable quest items.", function(enabled)
            if enabled then NS.ShowWindow() else NS.HideWindow() end
            NS.Refresh()
        end, true)
    Check("windowCollapsed", "Collapse quest window",
        "Hides target and item buttons while keeping the window handle visible.", function()
            NS.Refresh()
        end)

    y = y + 12
    Text("Quest priority and hidden quests", "GameFontNormal")
    Text("Enter a quest name or ID. Hidden quests are excluded from the target macro and quest window.")
    local updates = {}
    local function Sync()
        for _, entry in ipairs(checks) do
            local value = not not QuesterDB[entry.key]
            if entry.inverted then value = not value end
            entry.button:SetChecked(value)
        end
        for _, update in ipairs(updates) do update() end
    end
    local function Run(command)
        SlashCmdList.QUESTER(command)
        Sync()
    end
    local function Button(label, x, width, callback)
        local button = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        button:SetPoint("TOPLEFT", x, -y)
        button:SetSize(width, 24)
        button:SetText(label)
        button:SetScript("OnClick", callback)
        return button
    end
    local function InputRow(label, actions)
        Text(label, "GameFontNormalSmall")
        local input = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
        input:SetPoint("TOPLEFT", 6, -y)
        input:SetSize(205, 24)
        input:SetAutoFocus(false)
        input:SetMaxLetters(200)
        input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        for index, action in ipairs(actions) do
            Button(action[1], 222 + (index - 1) * 108, 104, function()
                local query = input:GetText():match("^%s*(.-)%s*$")
                if query == "" then input:SetFocus(); return end
                input:ClearFocus()
                Run(action[2] .. " " .. query)
            end)
        end
        y = y + 34
    end
    InputRow("Quest name / ID", {
        { "Prioritize", "priority" }, { "Hide", "hide" }, { "Show", "show" },
    })
    local questStatus = Text("")
    updates[#updates + 1] = function()
        local count = 0
        for _ in pairs(QuesterDB.hiddenQuests or {}) do count = count + 1 end
        questStatus:SetText("Priority: " .. (QuesterDB.priorityQuest and QuesterDB.priorityQuest.title or "none")
            .. " · Hidden quests: " .. count)
    end
    Button("Clear priority", 0, 170, function() Run("priority clear") end)
    Button("Show all quests", 180, 190, function() Run("hidden clear") end)
    Button("List in chat", 380, 140, function() Run("hidden") end)
    y = y + 46

    Text("Automation exceptions", "GameFontNormal")
    Text("Enter an exact name or ID. Quest and NPC exceptions pause quest automation; item exceptions prevent selling.")
    for _, entry in ipairs({ { "quest", "Quest" }, { "npc", "NPC" }, { "item", "Item" } }) do
        InputRow(entry[2] .. " – name / ID", {
            { "Exclude", "exclude " .. entry[1] }, { "Allow", "allow " .. entry[1] },
        })
    end
    local exceptionStatus = Text("")
    updates[#updates + 1] = function()
        local counts = {}
        for _, kind in ipairs({ "quest", "npc", "item" }) do
            local count = 0
            for _ in pairs((QuesterDB.automationExceptions or {})[kind] or {}) do count = count + 1 end
            counts[#counts + 1] = count
        end
        exceptionStatus:SetText("Exceptions: " .. counts[1] .. " Quests · " .. counts[2]
            .. " NPCs · " .. counts[3] .. " items")
    end
    Button("List exceptions in chat", 0, 180, function() Run("exceptions") end)
    Button("Clear all exceptions", 190, 220, function() Run("exceptions clear") end)
    y = y + 46

    Text("Other features", "GameFontNormal")
    Text("Learned quest targets, map markers and quest information in item tooltips are automatically enabled.")
    Button("Resume automation", 0, 180, function() Run("resume") end)
    Button("Inspect target", 190, 155, function() Run("inspect") end)
    Button("List objectives in chat", 355, 165, function() Run("objectives") end)
    y = y + 36
    Button("Diagnostics in chat", 0, 180, function() Run("debug") end)
    Button("Update now", 190, 155, function() Run("update") end)
    content:SetHeight(y + 40)
    panel:SetScript("OnShow", Sync)

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

function NS.OpenSettings()
    NS.InitSettings()
    if category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end
