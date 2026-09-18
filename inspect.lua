local _, NS = ...
local dialog, editBox, scanTooltip

local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function Read(fn, ...)
    if type(fn) ~= "function" then return nil, "API fehlt" end
    local ok, value = pcall(fn, ...)
    if not ok then return nil, "API-Aufruf fehlgeschlagen" end
    if IsSecret(value) then return nil, "geschützter Wert" end
    return value
end

-- Preserve unknown fields for this beta client without assuming a tooltip schema.
local function Dump(value, depth, seen)
    if IsSecret(value) then return "<geschützt>" end
    local kind = type(value)
    if kind == "string" then
        local text = value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            :gsub("|H.-|h(.-)|h", "%1"):gsub("|", "/")
        if #text > 1000 then text = text:sub(1, 1000) .. " <gekürzt>" end
        return string.format("%q", text)
    end
    if kind == "nil" or kind == "boolean" or kind == "number" then return tostring(value) end
    if kind ~= "table" then return "<" .. kind .. ">" end
    if depth >= 5 then return "<Tiefenlimit>" end
    if seen[value] then return "<Zyklus>" end
    seen[value] = true
    local keys, parts = {}, {}
    for key in pairs(value) do
        if not IsSecret(key) and (type(key) == "string" or type(key) == "number") then
            keys[#keys + 1] = key
        end
        if #keys >= 100 then break end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do
        parts[#parts + 1] = tostring(key) .. "=" .. Dump(value[key], depth + 1, seen)
    end
    if #keys == 100 then parts[#parts + 1] = "<Feldlimit>" end
    seen[value] = nil
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function LegacyTooltip()
    if not scanTooltip then
        scanTooltip = CreateFrame("GameTooltip", "QuesterInspectScanTooltip", UIParent, "GameTooltipTemplate")
    end
    scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTooltip:ClearLines()
    local ok = pcall(scanTooltip.SetUnit, scanTooltip, "target")
    local lines = {}
    if ok then
        for index = 1, scanTooltip:NumLines() do
            local left = _G["QuesterInspectScanTooltipTextLeft" .. index]
            local right = _G["QuesterInspectScanTooltipTextRight" .. index]
            lines[#lines + 1] = {
                leftText = left and left:GetText(), rightText = right and right:GetText(),
            }
        end
    end
    scanTooltip:Hide()
    return lines
end

function NS.BuildInspection()
    local exists = Read(UnitExists, "target")
    if not exists then return nil, "Bitte zuerst einen Questgegner anvisieren." end
    if Read(UnitIsPlayer, "target") then return nil, "Bitte einen NPC statt eines Spielers anvisieren." end

    local lines = { "Quester Diagnose 0.5.3", "Momentaufnahme des anvisierten NPCs; keine bestätigte Beutezuordnung." }
    local function Add(label, value, reason)
        if #lines >= 650 then return end
        local ok, text = pcall(Dump, value, 0, {})
        lines[#lines + 1] = label .. ": " .. (reason or (ok and text or "<nicht lesbar>"))
    end
    Add("Client", Read(function()
        local version, build, date, interface = GetBuildInfo()
        return { version = version, build = build, date = date, interface = interface }
    end))
    Add("Sprache", Read(GetLocale))
    Add("Im Kampf", Read(InCombatLockdown))
    Add("NPC-Name", Read(UnitName, "target"))
    local guid, guidError = Read(UnitGUID, "target")
    local npcID = type(guid) == "string" and guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    Add("NPC-ID", tonumber(npcID), guidError)
    Add("Angreifbar", Read(UnitCanAttack, "player", "target"))
    Add("Tot", Read(UnitIsDead, "target"))

    local tooltip, tooltipError = Read(C_TooltipInfo and C_TooltipInfo.GetUnit, "target")
    Add("C_TooltipInfo.GetUnit", tooltip and "Daten vorhanden" or nil, tooltipError)
    Add("Enum.QuestObjective", Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective)
    if type(tooltip) == "table" and type(tooltip.lines) == "table" and #tooltip.lines > 0 then
        for index, line in ipairs(tooltip.lines) do Add("Tooltip[" .. index .. "]", line) end
    else
        local fallback, fallbackError = Read(LegacyTooltip)
        Add("Tooltip-Fallback", fallback, fallbackError)
    end

    lines[#lines + 1] = "--- Questlog (alle gelieferten Einträge, keine automatische NPC-Zuordnung) ---"
    local modern = C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo
    local count, countError = Read(modern and C_QuestLog.GetNumQuestLogEntries or GetNumQuestLogEntries)
    Add("Questlog-Einträge", count, countError)
    if type(count) == "number" then
        for index = 1, math.min(count, 150) do
            if modern then
                local info, infoError = Read(C_QuestLog.GetInfo, index)
                Add("Questlog[" .. index .. "]", info, infoError)
                if type(info) == "table" and not info.isHeader and info.questID and info.questID > 0 then
                    Add("Questziele[" .. info.questID .. "]", Read(C_QuestLog.GetQuestObjectives, info.questID))
                end
            else
                Add("Questtitel[" .. index .. "]", Read(GetQuestLogTitle, index))
                local objectives = Read(GetNumQuestLeaderBoards, index)
                for objective = 1, type(objectives) == "number" and math.min(objectives, 30) or 0 do
                    local ok, text, kind, finished = pcall(GetQuestLogLeaderBoard or function() end, objective, index)
                    Add("Questziel[" .. index .. "/" .. objective .. "]",
                        ok and { text = text, type = kind, finished = finished } or nil)
                end
            end
        end
    end
    lines[#lines + 1] = "--- Karte (räumlicher Kontext, keine bestätigte Beutequelle) ---"
    local mapID, mapError = Read(C_Map and C_Map.GetBestMapForUnit, "player")
    Add("Map-ID", mapID, mapError)
    if type(mapID) == "number" then
        Add("QuestsOnMap", Read(C_QuestLog and C_QuestLog.GetQuestsOnMap, mapID))
    end
    if #lines >= 650 then lines[#lines + 1] = "<Bericht gekürzt>" end
    return table.concat(lines, "\n")
end

local function ShowReport(report)
    if not dialog then
        dialog = CreateFrame("Frame", "QuesterInspectWindow", UIParent, "BackdropTemplate")
        dialog:SetSize(620, 390)
        dialog:SetPoint("CENTER")
        dialog:SetFrameStrata("DIALOG")
        dialog:SetClampedToScreen(true)
        dialog:EnableMouse(true)
        dialog:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        dialog:SetBackdropColor(0.04, 0.04, 0.05, 0.98)
        local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText("Quester · NPC-Diagnose")
        local hint = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", 16, -42)
        hint:SetText("Text ist markiert: mit Strg+C / Cmd+C kopieren. Escape schließt.")
        local close = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
        close:SetScript("OnClick", function() dialog:Hide() end)
        local scroll = CreateFrame("ScrollFrame", "QuesterInspectScroll", dialog, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 16, -68)
        scroll:SetPoint("BOTTOMRIGHT", -34, 16)
        editBox = CreateFrame("EditBox", nil, scroll)
        editBox:SetMultiLine(true)
        editBox:SetAutoFocus(false)
        editBox:SetFontObject(ChatFontNormal)
        editBox:SetWidth(562)
        editBox:SetMaxLetters(0)
        scroll:SetScrollChild(editBox)
        editBox:SetScript("OnEscapePressed", function() dialog:Hide() end)
        editBox:SetScript("OnCursorChanged", function(_, _, y, _, height)
            local offset = scroll:GetVerticalScroll()
            y = -y
            if y < offset then scroll:SetVerticalScroll(y)
            elseif y + height > offset + scroll:GetHeight() then
                scroll:SetVerticalScroll(y + height - scroll:GetHeight())
            end
        end)
        dialog:SetScript("OnHide", function() editBox:ClearFocus() end)
    end
    editBox:SetText(report)
    dialog:Show()
    editBox:SetFocus()
    editBox:HighlightText()
end

function NS.InspectTarget()
    local ok, report, reason = pcall(NS.BuildInspection)
    if not ok then
        DEFAULT_CHAT_FRAME:AddMessage("Quester: Diagnose konnte die Client-Daten nicht auslesen.")
        return
    end
    if not report then
        DEFAULT_CHAT_FRAME:AddMessage("Quester: " .. reason)
        return
    end
    NS.lastInspection = report
    ShowReport(report)
end
