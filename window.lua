local _, NS = ...
local window, handle
local buttons, latestRows = {}, {}
local latestStatus = "Questziele werden geladen …"
local SIZE, GAP, COLUMNS = 30, 4, 8
local PADDING, GRIP = 8, 12

local function Safe(text)
    -- gsub also returns a replacement count; UI calls must receive only the text.
    local escaped = tostring(text or ""):gsub("|", "||")
    return escaped
end

function NS.HideWindow()
    QuesterDB.windowHidden = true
    if window and not InCombatLockdown() then window:Hide() end
end

function NS.ShowWindow()
    QuesterDB.windowHidden = false
    NS.Render(latestRows, latestStatus)
end

function NS.ToggleCollapsed()
    QuesterDB.windowCollapsed = not QuesterDB.windowCollapsed
    NS.Render(latestRows, latestStatus)
    GameTooltip:Hide()
end

function NS.InitWindow()
    if window or InCombatLockdown() then return end
    window = CreateFrame("Frame", "QuesterWindow", UIParent, "BackdropTemplate")
    window:SetSize(PADDING * 2 + GRIP, PADDING * 2 + SIZE)
    window:SetBackdrop({
        bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    window:SetBackdropColor(0.8, 0.8, 0.8, 0.95)
    window:SetBackdropBorderColor(0.85, 0.75, 0.55, 1)
    window:SetFrameStrata("MEDIUM")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    local position = QuesterDB.windowPosition
    if type(position) == "table" and type(position.x) == "number" and type(position.y) == "number" then
        window:SetPoint("CENTER", UIParent, "CENTER", position.x, position.y)
    else
        window:SetPoint("CENTER", UIParent, "CENTER", 260, 0)
    end
    handle = CreateFrame("Button", nil, window)
    handle:SetSize(GRIP, SIZE)
    handle:SetPoint("TOPLEFT", PADDING, -PADDING)
    handle:RegisterForDrag("LeftButton")
    handle:RegisterForClicks("RightButtonUp")
    -- Textures avoid missing-glyph boxes in the client's font.
    for index = -1, 1 do
        local dot = handle:CreateTexture(nil, "ARTWORK")
        dot:SetSize(3, 3)
        dot:SetPoint("CENTER", 0, index * 6)
        dot:SetColorTexture(0.8, 0.66, 0.36, 0.9)
    end
    handle:SetHighlightTexture("Interface/Buttons/ButtonHilight-Square", "ADD")
    handle:SetScript("OnDragStart", function()
        if not InCombatLockdown() then window:StartMoving() end
    end)
    handle:SetScript("OnDragStop", function()
        if InCombatLockdown() then return end
        window:StopMovingOrSizing()
        local x, y = window:GetCenter()
        local px, py = UIParent:GetCenter()
        QuesterDB.windowPosition = { x = x - px, y = y - py }
    end)
    handle:SetScript("OnClick", NS.ToggleCollapsed)
    handle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Quester")
        GameTooltip:AddLine(Safe(latestStatus), 1, 1, 1, true)
        local action = QuesterDB.windowCollapsed and "ausklappen" or "einklappen"
        GameTooltip:AddLine("Ziehen: verschieben · Rechtsklick: " .. action, 0.7, 0.7, 0.7)
        if InCombatLockdown() then
            GameTooltip:AddLine("Änderungen werden nach Kampfende angewendet.", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    handle:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if QuesterDB.windowHidden then window:Hide() end
end

local function NewButton(index)
    local button = CreateFrame("Button", "QuesterTargetButton" .. index, window, "SecureActionButtonTemplate")
    button:SetSize(SIZE, SIZE)
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:SetAttribute("type1", "macro")
    button:SetNormalTexture(132212)
    button:SetHighlightTexture("Interface/Buttons/ButtonHilight-Square", "ADD")
    local number = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    number:SetPoint("BOTTOMRIGHT", -2, 2)
    number:SetText(index)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(Safe(self.targetName))
        for _, row in ipairs(self.rows) do
            GameTooltip:AddLine(Safe(row.title), 1, 0.82, 0.35)
            GameTooltip:AddLine(Safe(row.text), 1, 1, 1, true)
        end
        GameTooltip:AddLine("Linksklick: dieses Ziel anvisieren", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return button
end

function NS.Render(rows, status)
    latestRows, latestStatus = rows, status
    -- The parent of secure buttons is protected too: defer all layout/visibility changes.
    if InCombatLockdown() then return end
    NS.InitWindow()
    local targets, byName = {}, {}
    for _, row in ipairs(rows) do
        if row.name and not row.finished then
            if not byName[row.name] then
                byName[row.name] = { name = row.name, rows = {} }
                targets[#targets + 1] = byName[row.name]
            end
            local entries = byName[row.name].rows
            entries[#entries + 1] = row
        end
    end
    for index, target in ipairs(targets) do
        local button = buttons[index] or NewButton(index)
        buttons[index] = button
        button.targetName, button.rows = target.name, target.rows
        button:SetAttribute("macrotext1", "/cleartarget\n/targetexact " .. target.name)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", PADDING + GRIP + GAP + ((index - 1) % COLUMNS) * (SIZE + GAP),
            -PADDING - math.floor((index - 1) / COLUMNS) * (SIZE + GAP))
        if QuesterDB.windowCollapsed then button:Hide() else button:Show() end
    end
    for index = #targets + 1, #buttons do
        buttons[index]:SetAttribute("macrotext1", nil)
        buttons[index]:Hide()
    end
    local visibleCount = QuesterDB.windowCollapsed and 0 or #targets
    local columns = math.min(visibleCount, COLUMNS)
    window:SetSize(PADDING * 2 + GRIP + columns * (SIZE + GAP),
        PADDING * 2 + math.max(1, math.ceil(visibleCount / COLUMNS)) * (SIZE + GAP) - GAP)
    if QuesterDB.windowHidden then window:Hide() else window:Show() end
end
