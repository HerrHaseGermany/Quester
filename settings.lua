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
    subtitle:SetText("Änderungen werden sofort accountweit gespeichert. Shift pausiert die Automatik.")

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
    Check("autoAccept", "Quests automatisch annehmen",
        "Nimmt Quests automatisch an. Quest- und NPC-Ausnahmen werden berücksichtigt.", Resume)
    Check("autoTurnIn", "Quests automatisch abgeben",
        "Gibt fertige Quests ab. Mehrere Belohnungen und Quests mit Geldkosten bleiben zur manuellen Auswahl offen.", Resume)
    Check("acceptTrivial", "Graue Quests im Dialog auswählen",
        "Wählt auch niedrigstufige Quests aus. Bereits geöffnete Questdetails folgen der automatischen Questannahme.")
    Check("notifyReady", "Abgabebereite Quests melden",
        "Zeigt eine Meldung, sobald eine Quest abgabebereit wird.")

    y = y + 12
    Text("Händler", "GameFontNormal")
    Check("autoSellGrey", "Graue Gegenstände automatisch verkaufen",
        "Verkauft graue Gegenstände mit bekanntem Verkaufspreis. Gesperrte, geschützte und Questgegenstände bleiben erhalten.")
    Check("autoRepair", "Ausrüstung automatisch reparieren",
        "Repariert mit eigenem Gold und meldet Kosten oder fehlendes Gold im Chat. Händlerautomatik pausiert bei Shift und im Kampf.")

    y = y + 12
    Text("Makro und Questfenster", "GameFontNormal")
    Check("targetMacro", "Zielmakro automatisch aktualisieren",
        "Aktualisiert das Makro QuesterTarget für offene Questziele. Änderungen im Kampf werden vorgemerkt.", NS.Refresh)
    Check("windowHidden", "Questfenster anzeigen",
        "Zeigt das Fenster mit Questzielen und verwendbaren Questgegenständen.", function(enabled)
            if enabled then NS.ShowWindow() else NS.HideWindow() end
            NS.Refresh()
        end, true)
    Check("windowCollapsed", "Questfenster einklappen",
        "Blendet Ziel- und Gegenstandsschaltflächen aus; der Fenstergriff bleibt sichtbar.", function()
            NS.Refresh()
        end)

    y = y + 12
    Text("Questpriorität und ausgeblendete Quests", "GameFontNormal")
    Text("Questname oder ID eingeben. Ausgeblendete Quests erscheinen nicht im Zielmakro oder Questfenster.")
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
    InputRow("Questname / ID", {
        { "Priorisieren", "priority" }, { "Ausblenden", "hide" }, { "Einblenden", "show" },
    })
    local questStatus = Text("")
    updates[#updates + 1] = function()
        local count = 0
        for _ in pairs(QuesterDB.hiddenQuests or {}) do count = count + 1 end
        questStatus:SetText("Priorität: " .. (QuesterDB.priorityQuest and QuesterDB.priorityQuest.title or "keine")
            .. " · Ausgeblendete Quests: " .. count)
    end
    Button("Priorität aufheben", 0, 170, function() Run("priority clear") end)
    Button("Alle Quests einblenden", 180, 190, function() Run("hidden clear") end)
    Button("Liste im Chat", 380, 140, function() Run("hidden") end)
    y = y + 46

    Text("Automatik-Ausnahmen", "GameFontNormal")
    Text("Exakten Namen oder ID eingeben. Quest- und NPC-Ausnahmen pausieren die Questautomatik; Gegenstandsausnahmen schützen vor Verkauf.")
    for _, entry in ipairs({ { "quest", "Quest" }, { "npc", "NPC" }, { "item", "Gegenstand" } }) do
        InputRow(entry[2] .. " – Name / ID", {
            { "Ausschließen", "exclude " .. entry[1] }, { "Zulassen", "allow " .. entry[1] },
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
        exceptionStatus:SetText("Ausnahmen: " .. counts[1] .. " Quests · " .. counts[2]
            .. " NPCs · " .. counts[3] .. " Gegenstände")
    end
    Button("Ausnahmen im Chat", 0, 180, function() Run("exceptions") end)
    Button("Alle Ausnahmen entfernen", 190, 220, function() Run("exceptions clear") end)
    y = y + 46

    Text("Weitere Funktionen", "GameFontNormal")
    Text("Gelernte Questziele, Kartenmarkierungen und Questinformationen in Gegenstandstooltips sind automatisch aktiv.")
    Button("Automatik fortsetzen", 0, 180, function() Run("resume") end)
    Button("Ziel untersuchen", 190, 155, function() Run("inspect") end)
    Button("Questziele im Chat", 355, 165, function() Run("objectives") end)
    y = y + 36
    Button("Diagnose im Chat", 0, 180, function() Run("debug") end)
    Button("Jetzt aktualisieren", 190, 155, function() Run("update") end)
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
