local _, JP = ...
local L = JP.L
local ApplicantBoard = {}
local UI = JP.UI
local C = UI.colors

-- Своя таблица кандидатов вместо штатной панели Blizzard.
--
-- В родной сетке колонки стоят вплотную, и любая наша пометка неизбежно
-- наезжала на «Ур. пр.» или «Рейтинг». Здесь мы владеем раскладкой целиком и
-- показываем ровно то, по чему принимают решение: кто это, какая роль,
-- экипировка, рейтинг и нужен ли он группе прямо сейчас.

local MAX_ROWS = 14
local ROW_HEIGHT, ROW_STEP = 80, 84
local PARTY_ROWS, PARTY_ROW_HEIGHT = 5, 26
local PARTY_TOP, PARTY_SECTION_BOTTOM = -52, -190
local ROW_LEFT_INSET, ROW_RIGHT_INSET = 12, 18

-- Одна таблица геометрии на заголовки и на строки, чтобы колонки не разъехались.
local COL = {
    declineWidth = 34, declineRight = 12,
    inviteWidth = 104, inviteRight = 52,
    statusWidth = 104, statusRight = 162,
    ratingWidth = 74, ratingRight = 272,
    ilvlWidth = 62, ilvlRight = 350,
    roleWidth = 52, roleRight = 416,
    contentRight = 474,
    nameLeft = 16,
}

local STATUS = {
    best = { label = L("ЛУЧШИЙ"), color = C.amber },
    needed = { label = L("ПОДХОДИТ"), color = { .62, .40, .95, 1 } },
}

local function UsableNumber(value)
    return type(value) == "number" and not issecretvalue(value)
end

local function SafeString(value)
    if type(value) ~= "string" or issecretvalue(value) or value == "" then return nil end
    return value
end


local function SafeBoolean(value)
    return type(value) == "boolean" and not issecretvalue(value) and value or false
end

local function RelevantMilestone(milestones, level)
    for _, entry in ipairs(type(milestones) == "table" and milestones or {}) do
        if level >= (tonumber(entry.level) or math.huge) then return entry end
    end
end

local function ShowDungeonTooltip(tile)
    local data = tile.tooltipData
    if not data then return end

    GameTooltip:SetOwner(tile, "ANCHOR_RIGHT")
    GameTooltip:SetText(tile.dungeonName or data.label or L("Подземелье"), .15, .78, .96)

    local level = tonumber(data.level) or 0
    if level <= 0 then
        GameTooltip:AddLine(L("Нет записанных прохождений"), .55, .58, .63)
        GameTooltip:Show()
        return
    end

    GameTooltip:AddDoubleLine(L("Лучший ключ"), "+" .. level, 1, 1, 1, 1, .75, .18)
    local upgrades = tonumber(data.upgrades) or 0
    if upgrades > 0 then
        GameTooltip:AddDoubleLine(L("Повышение ключа"), "+" .. upgrades, 1, 1, 1, .30, .92, .56)
    else
        GameTooltip:AddDoubleLine(L("Таймер"), L("не закрыт"), 1, 1, 1, .62, .64, .68)
    end

    if data.runCount ~= nil then
        GameTooltip:AddDoubleLine(L("Проходок этого данжа"), tostring(data.runCount), 1, 1, 1, 1, 1, 1)
    end

    local milestone = RelevantMilestone(data.milestones, level)
    if milestone then
        GameTooltip:AddDoubleLine(milestone.label, milestone.text, .72, .75, .80, .30, .92, .56)
    end
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Данные
---------------------------------------------------------------------------

function ApplicantBoard:Collect()
    if type(C_LFGList.GetApplicants) ~= "function" then return {}, nil end
    local ok, applicantIDs = pcall(C_LFGList.GetApplicants)
    if not ok or type(applicantIDs) ~= "table" or issecretvalue(applicantIDs) then return {}, nil end

    local highlighter = JP.modules.ApplicantHighlighter
    local selected = highlighter and highlighter.GetSelection and highlighter:GetSelection() or {}
    local missing = highlighter and highlighter.GetMissingRoles and highlighter:GetMissingRoles() or nil

    local entries = {}
    for _, applicantID in ipairs(applicantIDs) do
        local applicant = C_LFGList.GetApplicantInfo(applicantID)
        local status = applicant and SafeString(applicant.applicationStatus)
        local numMembers = applicant and UsableNumber(applicant.numMembers) and applicant.numMembers or 0
        if applicant and status == "applied" then
            for memberIdx = 1, numMembers do
                local name, classFile, _, _, itemLevel, _, tank, healer, damage, assignedRole, _, score =
                    C_LFGList.GetApplicantMemberInfo(applicantID, memberIdx)
                local role = SafeString(assignedRole)
                if role ~= "TANK" and role ~= "HEALER" and role ~= "DAMAGER" then
                    role = SafeBoolean(tank) and "TANK" or SafeBoolean(healer) and "HEALER" or SafeBoolean(damage) and "DAMAGER" or "DAMAGER"
                end
                entries[#entries + 1] = {
                    applicantID = applicantID,
                    memberIdx = memberIdx,
                    name = SafeString(name) or L("Кандидат"),
                    classFile = SafeString(classFile),
                    role = role,
                    itemLevel = UsableNumber(itemLevel) and itemLevel or 0,
                    score = UsableNumber(score) and score or 0,
                    status = selected[applicantID .. ":" .. memberIdx],
                    dungeonCells = JP.GroupSearchUI and JP.GroupSearchUI.GetDungeonCells
                        and JP.GroupSearchUI:GetDungeonCells(SafeString(name), SafeString(classFile)) or nil,
                    numMembers = numMembers,
                }
            end
        end
    end

    local weight = { best = 0, needed = 1 }
    table.sort(entries, function(a, b)
        local aw, bw = weight[a.status] or 2, weight[b.status] or 2
        if aw ~= bw then return aw < bw end
        if a.itemLevel ~= b.itemLevel then return a.itemLevel > b.itemLevel end
        return a.name < b.name
    end)
    return entries, missing
end

local function Act(action, applicantID, failure)
    if type(C_LFGList[action]) ~= "function" then
        JP:Print(L("Это действие недоступно: API поиска групп не отвечает."))
        return false
    end
    local ok = pcall(C_LFGList[action], applicantID)
    if not ok then JP:Print(failure) end
    return ok
end

---------------------------------------------------------------------------
-- Строки
---------------------------------------------------------------------------

local function CreateRow(parent, index)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(ROW_HEIGHT)
    row:EnableMouse(true)
    row.baseColor = index % 2 == 0 and C.rowAlt or C.row
    UI.Backdrop(row, row.baseColor, C.lineSoft)

    row.accent = row:CreateTexture(nil, "OVERLAY")
    row.accent:SetPoint("TOPLEFT", 1, -1)
    row.accent:SetPoint("BOTTOMLEFT", 1, 1)
    row.accent:SetWidth(3)

    row.name = UI.Text(row, "GameFontHighlight", "", C.text)
    row.name:SetPoint("TOPLEFT", COL.nameLeft, -9)
    row.name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -COL.contentRight, -9)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    -- Компактная таблица ключей: названия и значения больше не слипаются в
    -- одну длинную строку и всегда стоят строго друг под другом.
    row.dungeonGrid = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.dungeonGrid:SetPoint("BOTTOMLEFT", COL.nameLeft, 4)
    row.dungeonGrid:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -COL.contentRight, 4)
    row.dungeonGrid:SetHeight(44)
    row.dungeonTiles = {}
    for cellIndex = 1, 8 do
        local tile = CreateFrame("Frame", nil, row.dungeonGrid, "BackdropTemplate")
        tile:EnableMouse(true)
        UI.Backdrop(tile, { .015, .022, .030, 1 }, C.lineSoft)
        tile.image = tile:CreateTexture(nil, "ARTWORK")
        tile.image:SetPoint("TOPLEFT", 1, -1)
        tile.image:SetPoint("BOTTOMRIGHT", -1, 1)
        tile.image:SetTexCoord(.07, .93, .07, .93)
        tile.shade = tile:CreateTexture(nil, "OVERLAY")
        tile.shade:SetAllPoints(tile.image)
        tile.shade:SetColorTexture(0, 0, 0, .54)
        tile.upgrades = UI.Text(tile, "GameFontNormalSmall", "", C.text)
        tile.upgrades:SetPoint("TOP", 0, -1)
        local upgradesFont = tile.upgrades:GetFont()
        if upgradesFont then tile.upgrades:SetFont(upgradesFont, 12, "THICKOUTLINE") end
        tile.upgrades:SetShadowColor(0, 0, 0, 1)
        tile.upgrades:SetShadowOffset(1, -1)
        tile.value = UI.Text(tile, "GameFontNormalHuge", "—", C.muted)
        tile.value:SetPoint("BOTTOM", 0, 1)
        local fontPath = tile.value:GetFont()
        if fontPath then tile.value:SetFont(fontPath, 22, "THICKOUTLINE") end
        tile.value:SetShadowColor(0, 0, 0, 1)
        tile.value:SetShadowOffset(2, -2)
        tile:SetScript("OnEnter", function(self)
            row:SetBackdropColor(UI.Unpack(C.rowHover))
            ShowDungeonTooltip(self)
        end)
        tile:SetScript("OnLeave", function()
            row:SetBackdropColor(UI.Unpack(row.baseColor))
            GameTooltip_Hide()
        end)
        row.dungeonTiles[cellIndex] = tile
    end

    row.role = UI.Text(row, "GameFontHighlight", "")
    row.role:SetPoint("RIGHT", -COL.roleRight, 0)
    row.role:SetWidth(COL.roleWidth)
    row.role:SetJustifyH("CENTER")

    row.ilvl = UI.Text(row, "GameFontHighlightSmall", "", C.text)
    row.ilvl:SetPoint("RIGHT", -COL.ilvlRight, 0)
    row.ilvl:SetWidth(COL.ilvlWidth)
    row.ilvl:SetJustifyH("CENTER")

    row.rating = UI.Text(row, "GameFontNormal", "", C.amber)
    row.rating:SetPoint("RIGHT", -COL.ratingRight, 0)
    row.rating:SetWidth(COL.ratingWidth)
    row.rating:SetJustifyH("CENTER")

    row.status = UI.Text(row, "GameFontNormalSmall", "")
    row.status:SetPoint("RIGHT", -COL.statusRight, 0)
    row.status:SetWidth(COL.statusWidth)
    row.status:SetJustifyH("CENTER")

    row.invite = UI.Button(row, L("Пригласить"), COL.inviteWidth, 24, true)
    row.invite:SetPoint("RIGHT", -COL.inviteRight, 0)
    row.invite:SetScript("OnClick", function(self)
        if not self.applicantID then return end
        if Act("InviteApplicant", self.applicantID, L("Blizzard не принял приглашение. Попробуй ещё раз.")) then
            self:SetText(L("Отправлено"))
        end
    end)

    row.decline = UI.Button(row, "×", COL.declineWidth, 24)
    row.decline:SetPoint("RIGHT", -COL.declineRight, 0)
    row.decline:SetScript("OnClick", function(self)
        if self.applicantID then Act("DeclineApplicant", self.applicantID, L("Не удалось отклонить заявку.")) end
    end)
    row.decline:HookScript("OnEnter", function(self) UI.Tooltip(self, L("Отклонить заявку")) end)
    row.decline:HookScript("OnLeave", GameTooltip_Hide)

    row:SetScript("OnEnter", function(self) self:SetBackdropColor(UI.Unpack(C.rowHover)) end)
    row:SetScript("OnLeave", function(self) self:SetBackdropColor(UI.Unpack(self.baseColor)) end)

    row:Hide()
    return row
end

---------------------------------------------------------------------------
-- Сборка
---------------------------------------------------------------------------

function ApplicantBoard:Build(welcome, page)
    self.page = page
    self.welcome = welcome

    local partyTitle = UI.Text(page, "GameFontNormalSmall", L("ТВОЯ ПАТИ"), C.accent)
    partyTitle:SetPoint("TOPLEFT", 16, -14)

    self.partyPower = UI.Text(page, "GameFontHighlightSmall", "", C.muted)
    self.partyPower:SetPoint("LEFT", partyTitle, "RIGHT", 14, 0)
    self.partyPower:SetJustifyH("LEFT")

    local partyHeaders = {
        { text = L("ИГРОК"), x = 16, width = 210, justify = "LEFT" },
        { text = L("РОЛЬ"), x = 230, width = 54 },
        { text = "RIO", x = 290, width = 72 },
    }
    for _, data in ipairs(partyHeaders) do
        local label = UI.Text(page, "GameFontNormalSmall", data.text, C.faint)
        label:SetPoint("TOPLEFT", data.x, -34)
        label:SetWidth(data.width)
        label:SetJustifyH(data.justify or "CENTER")
    end

    self.partyDungeonHeaders = {}
    for index = 1, 8 do
        local label = UI.Text(page, "GameFontNormalSmall", "", C.accent)
        label:SetPoint("TOPLEFT", 374 + (index - 1) * 58, -34)
        label:SetWidth(54)
        label:SetJustifyH("CENTER")
        self.partyDungeonHeaders[index] = label
    end

    self.partyRows = {}
    for index = 1, PARTY_ROWS do
        local row = CreateFrame("Frame", nil, page, "BackdropTemplate")
        row:SetPoint("TOPLEFT", 12, PARTY_TOP - (index - 1) * PARTY_ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", -12, PARTY_TOP - (index - 1) * PARTY_ROW_HEIGHT)
        row:SetHeight(PARTY_ROW_HEIGHT - 2)
        UI.Backdrop(row, index % 2 == 0 and C.rowAlt or C.row, C.lineSoft)

        row.name = UI.Text(row, "GameFontHighlightSmall", "", C.text)
        row.name:SetPoint("LEFT", 6, 0)
        row.name:SetWidth(208)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.role = UI.Text(row, "GameFontHighlightSmall", "")
        row.role:SetPoint("LEFT", 218, 0)
        row.role:SetWidth(54)
        row.role:SetJustifyH("CENTER")
        row.score = UI.Text(row, "GameFontNormalSmall", "—", C.muted)
        row.score:SetPoint("LEFT", 278, 0)
        row.score:SetWidth(72)
        row.score:SetJustifyH("CENTER")
        row.cells = {}
        for cellIndex = 1, 8 do
            local cell = UI.Text(row, "GameFontHighlightSmall", "—", C.muted)
            cell:SetPoint("LEFT", 362 + (cellIndex - 1) * 58, 0)
            cell:SetWidth(54)
            cell:SetJustifyH("CENTER")
            row.cells[cellIndex] = cell
        end
        self.partyRows[index] = row
    end

    local partyDivider = UI.Line(page, C.accentDim)
    partyDivider:SetPoint("TOPLEFT", 12, PARTY_SECTION_BOTTOM)
    partyDivider:SetPoint("TOPRIGHT", -12, PARTY_SECTION_BOTTOM)

    local title = UI.Text(page, "GameFontNormalSmall", L("КАНДИДАТЫ"), C.muted)
    title:SetPoint("TOPLEFT", 16, PARTY_SECTION_BOTTOM - 16)

    self.count = UI.Text(page, "GameFontHighlightSmall", "", C.accent)
    self.count:SetPoint("LEFT", title, "RIGHT", 10, 0)

    self.needs = UI.Text(page, "GameFontHighlightSmall", "", C.muted)
    self.needs:SetPoint("LEFT", self.count, "RIGHT", 16, 0)
    self.needs:SetJustifyH("LEFT")

    local divider = UI.Line(page, C.lineSoft)
    divider:SetPoint("TOPLEFT", 12, PARTY_SECTION_BOTTOM - 38)
    divider:SetPoint("TOPRIGHT", -12, PARTY_SECTION_BOTTOM - 38)

    local function Header(text, width, right)
        local label = UI.Text(page, "GameFontNormalSmall", text, C.faint)
        -- Значения привязаны к правому краю строки, а сама строка отступает
        -- от страницы. Шапка обязана учитывать тот же отступ.
        label:SetPoint("TOPRIGHT", -(right + ROW_RIGHT_INSET), PARTY_SECTION_BOTTOM - 50)
        label:SetWidth(width)
        label:SetJustifyH("CENTER")
    end
    local nameHeader = UI.Text(page, "GameFontNormalSmall", L("ИГРОК"), C.faint)
    nameHeader:SetPoint("TOPLEFT", ROW_LEFT_INSET + COL.nameLeft, PARTY_SECTION_BOTTOM - 50)
    nameHeader:SetJustifyH("LEFT")
    Header(L("РОЛЬ"), COL.roleWidth, COL.roleRight)
    Header("iLvL", COL.ilvlWidth, COL.ilvlRight)
    Header(L("РЕЙТИНГ"), COL.ratingWidth, COL.ratingRight)
    Header(L("ОТБОР"), COL.statusWidth, COL.statusRight)

    self.rows = {}
    for index = 1, MAX_ROWS do
        local row = CreateRow(page, index)
        row:SetPoint("TOPLEFT", ROW_LEFT_INSET, PARTY_SECTION_BOTTOM - 66 - (index - 1) * ROW_STEP)
        row:SetPoint("TOPRIGHT", -ROW_RIGHT_INSET, PARTY_SECTION_BOTTOM - 66 - (index - 1) * ROW_STEP)
        self.rows[index] = row
    end

    self.scrollBar = UI.ScrollBar(page)
    self.scrollBar:SetPoint("TOPRIGHT", -6, PARTY_SECTION_BOTTOM - 66)
    self.scrollBar:SetPoint("BOTTOMRIGHT", -6, 12)
    self.scrollBar:SetScript("OnValueChanged", function(_, value)
        local offset = math.floor(value + .5)
        if offset ~= self.offset then
            self.offset = offset
            self:Render()
        end
    end)
    self.scrollBar:Hide()

    local function OnMouseWheel(_, delta)
        local _, maximum = self.scrollBar:GetMinMaxValues()
        self.scrollBar:SetValue(math.max(0, math.min(maximum, (self.offset or 0) - delta)))
    end
    page:EnableMouseWheel(true)
    page:SetScript("OnMouseWheel", OnMouseWheel)
    for _, row in ipairs(self.rows) do
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", OnMouseWheel)
    end

    self.message = UI.Text(page, "GameFontHighlight", "", C.muted)
    self.message:SetPoint("TOPLEFT", 24, PARTY_SECTION_BOTTOM - 120)
    self.message:SetPoint("TOPRIGHT", -24, PARTY_SECTION_BOTTOM - 120)
    self.message:SetJustifyH("CENTER")
    self.message:SetSpacing(6)

    self:Layout()
end

function ApplicantBoard:Layout()
    if not self.page then return end
    local height = self.page:GetHeight()
    if height < 100 then return end
    local visible = math.max(2, math.min(MAX_ROWS, math.floor((height + PARTY_SECTION_BOTTOM - 72) / ROW_STEP)))
    self.visibleRows = visible
    for index, row in ipairs(self.rows or {}) do
        row.layoutVisible = index <= visible
        if not row.layoutVisible then row:Hide() end
        local gridWidth = math.max(240, row.dungeonGrid:GetWidth())
        local tileGap = 2
        local tileSize = math.min(44, math.floor((gridWidth - tileGap * 7) / 8))
        local totalWidth = tileSize * 8 + tileGap * 7
        local startX = math.max(0, math.floor((gridWidth - totalWidth) / 2))
        local startY = -math.max(0, math.floor((44 - tileSize) / 2))
        for cellIndex = 1, 8 do
            local tile = row.dungeonTiles[cellIndex]
            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT", startX + (cellIndex - 1) * (tileSize + tileGap), startY)
            tile:SetSize(tileSize, tileSize)
        end
    end
end

local function UnitRole(unit)
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
    if role == "NONE" or not role then
        if unit == "player" then
            local spec = GetSpecialization and GetSpecialization()
            role = spec and GetSpecializationRole and GetSpecializationRole(spec) or nil
        end
    end
    if role == "TANK" or role == "HEALER" or role == "DAMAGER" then return role end
end

function ApplicantBoard:RefreshParty()
    if not self.partyRows then return end
    local units = { "player" }
    for index = 1, 4 do
        local unit = "party" .. index
        if UnitExists(unit) then units[#units + 1] = unit end
    end

    local columns = JP.GroupSearchUI:GetPartyDungeonColumns()
    for index, header in ipairs(self.partyDungeonHeaders) do
        header:SetText(columns[index] and columns[index].label or "")
    end

    local total, known = 0, 0
    local memberStrengths = {}
    for index, row in ipairs(self.partyRows) do
        local unit = units[index]
        if unit then
            local name = UnitName(unit) or L("Игрок")
            local _, classFilename = UnitClass(unit)
            local profile = JP.GroupSearchUI:GetPartyMemberProfile(unit) or { score = 0, cells = {} }
            local score = tonumber(profile.score) or 0
            if score > 0 then total, known = total + score, known + 1 end

            -- Прогноз строится по трём сильнейшим подземельям игрока. +2/+3
            -- дают небольшой запас, но не превращаются в обещание нескольких
            -- уровней сверху. Затем усредняем силу всех найденных участников.
            local runs = {}
            local gradeBonus = { plusTwo = .5, plusThree = 1 }
            for _, data in ipairs(profile.cells or {}) do
                local level = tonumber(data.level) or tonumber(tostring(data.value or ""):match("(%d+)") or "")
                if level and level > 0 then runs[#runs + 1] = level + (gradeBonus[data.grade] or 0) end
            end
            table.sort(runs, function(a, b) return a > b end)
            if #runs > 0 then
                local count, strength = math.min(3, #runs), 0
                for runIndex = 1, count do strength = strength + runs[runIndex] end
                memberStrengths[#memberStrengths + 1] = strength / count
            end

            row.name:SetText(('%s  %s%s'):format(
                UI.ClassIcon(classFilename, 16),
                name,
                UnitIsGroupLeader(unit)
                    and "  |TInterface\\GroupFrame\\UI-Group-LeaderIcon:14:14:0:0|t" or ""))
            row.name:SetTextColor(UI.ClassColor(classFilename))
            row.role:SetText(UI.RoleIcon(UnitRole(unit), 16))
            row.score:SetText(score > 0 and tostring(math.floor(score + .5)) or "—")
            if score > 0 then
                local code = JP.GroupSearchUI:GetPartyRatingColor(score)
                row.score:SetTextColor(tonumber(code:sub(1, 2), 16) / 255, tonumber(code:sub(3, 4), 16) / 255, tonumber(code:sub(5, 6), 16) / 255)
            else
                row.score:SetTextColor(UI.Unpack(C.muted))
            end
            for cellIndex, cell in ipairs(row.cells) do
                local data = profile.cells and profile.cells[cellIndex]
                cell:SetText(data and data.value or "—")
                local color = JP.GroupSearchUI:GetRunGradeColor(data and data.grade)
                cell:SetTextColor(color[1], color[2], color[3], 1)
            end
            row:Show()
        else
            row:Hide()
        end
    end

    local members = math.max(1, #units)
    local average = total / members
    local forecast = 0
    for _, strength in ipairs(memberStrengths) do forecast = forecast + strength end
    if #memberStrengths > 0 then forecast = math.max(2, math.floor(forecast / #memberStrengths)) end
    self.partyPower:SetText((L("|cff8a939fучастников|r %d   |cff8a939fсумма RIO|r %d   |cff%sсредний %d|r   |cff8a939fнайдено|r %d/%d   |cff28c8f5прогноз группы ~+%d|r")):format(
        members, math.floor(total + .5), JP.GroupSearchUI:GetPartyRatingColor(average), math.floor(average + .5), known, members, forecast))
end

function ApplicantBoard:Render()
    local entries = self.entries or {}
    local offset = self.offset or 0
    local dungeonColumns = JP.GroupSearchUI:GetPartyDungeonColumns()
    for index, row in ipairs(self.rows) do
        local entry = entries[offset + index]
        if entry and row.layoutVisible ~= false then
            local style = entry.status and STATUS[entry.status]

            row.name:SetText(("%s  %s"):format(UI.ClassIcon(entry.classFile, 18), entry.name))
            row.name:SetTextColor(UI.ClassColor(entry.classFile))
            row.role:SetText(UI.RoleIcon(entry.role, 18))
            row.ilvl:SetText(entry.itemLevel > 0 and ("%.0f"):format(entry.itemLevel) or "—")
            row.rating:SetText(entry.score > 0 and tostring(math.floor(entry.score)) or "—")
            for cellIndex = 1, 8 do
                local data = entry.dungeonCells and entry.dungeonCells[cellIndex]
                local column = dungeonColumns[cellIndex]
                local tile = row.dungeonTiles[cellIndex]
                tile.tooltipData = data
                tile.dungeonName = column and column.name
                tile.image:SetTexture(column and column.texture or 134400)
                tile.image:SetShown(column and column.texture and true or false)
                local level = data and tonumber(data.level) or 0
                tile.value:SetText(level > 0 and tostring(level) or "—")
                local color = JP.GroupSearchUI:GetRunGradeColor(data and data.grade)
                local upgrades = data and tonumber(data.upgrades) or 0
                tile.upgrades:SetText(upgrades > 0 and string.rep("+", math.min(3, upgrades)) or "")
                tile.upgrades:SetTextColor(color[1], color[2], color[3], 1)
                tile.value:SetTextColor(color[1], color[2], color[3], 1)
                tile:SetBackdropBorderColor(color[1], color[2], color[3], level > 0 and .9 or .35)
            end

            if style then
                row.accent:SetColorTexture(unpack(style.color))
                row.accent:Show()
                row.status:SetText(style.label)
                row.status:SetTextColor(unpack(style.color))
            else
                row.accent:Hide()
                row.status:SetText("")
            end

            row.invite.applicantID = entry.applicantID
            row.invite:SetText(entry.numMembers > 1 and (L("Пригласить ×") .. entry.numMembers) or L("Пригласить"))
            row.decline.applicantID = entry.applicantID
            row:Show()
        else
            row.invite.applicantID = nil
            row.decline.applicantID = nil
            for _, tile in ipairs(row.dungeonTiles) do
                tile.tooltipData = nil
                tile.dungeonName = nil
            end
            row:Hide()
        end
    end
end

function ApplicantBoard:Refresh()
    if not self.page then return end
    self:Layout()

    self:RefreshParty()
    local entries, missing = self:Collect()
    self.entries = entries

    local visible = self.visibleRows or MAX_ROWS
    local maximum = math.max(0, #entries - visible)
    self.scrollBar:SetMinMaxValues(0, maximum)
    self.offset = math.min(self.offset or 0, maximum)
    self.scrollBar:SetValue(self.offset)
    self.scrollBar:SetShown(maximum > 0)
    self:Render()

    self.count:SetText(#entries > 0 and tostring(#entries) or "")
    if missing then
        self.needs:SetText((L("|cff8a939fнужно|r  %s %d   %s %d   %s %d")):format(
            UI.RoleIcon("TANK", 14), missing.TANK,
            UI.RoleIcon("HEALER", 14), missing.HEALER,
            UI.RoleIcon("DAMAGER", 14), missing.DAMAGER))
    else
        self.needs:SetText("")
    end

    if #entries == 0 then
        local listed = C_LFGList.GetActiveEntryInfo and C_LFGList.GetActiveEntryInfo()
        self.message:SetText(listed
            and L("Заявок пока нет.\nОни появятся здесь, как только кто-то откликнется.")
            or L("Ты сейчас не собираешь группу.\nСоздай объявление в поиске групп — заявки придут сюда."))
        self.message:Show()
    else
        self.message:Hide()
    end
end

function ApplicantBoard:Create()
    if self.events then return end
    self.events = CreateFrame("Frame")
    for _, event in ipairs({ "LFG_LIST_APPLICANT_LIST_UPDATED", "LFG_LIST_APPLICANT_UPDATED", "GROUP_ROSTER_UPDATE" }) do
        self.events:RegisterEvent(event)
    end
    self.events:SetScript("OnEvent", function()
        local welcome = JP.modules.Welcome
        if welcome and welcome.currentPage == "applicants" and welcome.frame and welcome.frame:IsShown() then
            self:Refresh()
        end
    end)
end

function ApplicantBoard:Enable() end
function ApplicantBoard:Disable() end
function ApplicantBoard:Destroy() end

JP.ApplicantBoard = ApplicantBoard
JP:RegisterModule("ApplicantBoard", ApplicantBoard)
