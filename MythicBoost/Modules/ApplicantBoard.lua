local _, JP = ...
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
local ROW_HEIGHT, ROW_STEP = 34, 38

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
    best = { label = "ЛУЧШИЙ", color = C.amber },
    needed = { label = "ПОДХОДИТ", color = { .62, .40, .95, 1 } },
}

local function UsableNumber(value)
    return type(value) == "number" and not issecretvalue(value)
end

local function SafeString(value)
    if type(value) ~= "string" or issecretvalue(value) or value == "" then return nil end
    return value
end

---------------------------------------------------------------------------
-- Данные
---------------------------------------------------------------------------

function ApplicantBoard:Collect()
    if type(C_LFGList.GetApplicants) ~= "function" then return {}, nil end
    local ok, applicantIDs = pcall(C_LFGList.GetApplicants)
    if not ok or type(applicantIDs) ~= "table" then return {}, nil end

    local highlighter = JP.modules.ApplicantHighlighter
    local selected = highlighter and highlighter.GetSelection and highlighter:GetSelection() or {}
    local missing = highlighter and highlighter.GetMissingRoles and highlighter:GetMissingRoles() or nil

    local entries = {}
    for _, applicantID in ipairs(applicantIDs) do
        local applicant = C_LFGList.GetApplicantInfo(applicantID)
        if applicant and applicant.applicationStatus == "applied" then
            for memberIdx = 1, (applicant.numMembers or 0) do
                local name, classFile, _, _, itemLevel, _, tank, healer, damage, assignedRole, _, score =
                    C_LFGList.GetApplicantMemberInfo(applicantID, memberIdx)
                local role = assignedRole
                if role ~= "TANK" and role ~= "HEALER" and role ~= "DAMAGER" then
                    role = tank and "TANK" or healer and "HEALER" or damage and "DAMAGER" or "DAMAGER"
                end
                entries[#entries + 1] = {
                    applicantID = applicantID,
                    memberIdx = memberIdx,
                    name = SafeString(name) or "Кандидат",
                    classFile = classFile,
                    role = role,
                    itemLevel = UsableNumber(itemLevel) and itemLevel or 0,
                    score = UsableNumber(score) and score or 0,
                    status = selected[applicantID .. ":" .. memberIdx],
                    numMembers = applicant.numMembers or 1,
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
        JP:Print("Это действие недоступно: API поиска групп не отвечает.")
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
    row.name:SetPoint("LEFT", COL.nameLeft, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -COL.contentRight, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

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

    row.invite = UI.Button(row, "Пригласить", COL.inviteWidth, 24, true)
    row.invite:SetPoint("RIGHT", -COL.inviteRight, 0)
    row.invite:SetScript("OnClick", function(self)
        if not self.applicantID then return end
        if Act("InviteApplicant", self.applicantID, "Blizzard не принял приглашение. Попробуй ещё раз.") then
            self:SetText("Отправлено")
        end
    end)

    row.decline = UI.Button(row, "×", COL.declineWidth, 24)
    row.decline:SetPoint("RIGHT", -COL.declineRight, 0)
    row.decline:SetScript("OnClick", function(self)
        if self.applicantID then Act("DeclineApplicant", self.applicantID, "Не удалось отклонить заявку.") end
    end)
    row.decline:HookScript("OnEnter", function(self) UI.Tooltip(self, "Отклонить заявку") end)
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

    local title = UI.Text(page, "GameFontNormalSmall", "КАНДИДАТЫ", C.muted)
    title:SetPoint("TOPLEFT", 16, -14)

    self.count = UI.Text(page, "GameFontHighlightSmall", "", C.accent)
    self.count:SetPoint("LEFT", title, "RIGHT", 10, 0)

    self.needs = UI.Text(page, "GameFontHighlightSmall", "", C.muted)
    self.needs:SetPoint("LEFT", self.count, "RIGHT", 16, 0)
    self.needs:SetJustifyH("LEFT")

    local divider = UI.Line(page, C.lineSoft)
    divider:SetPoint("TOPLEFT", 12, -36)
    divider:SetPoint("TOPRIGHT", -12, -36)

    local function Header(text, width, right)
        local label = UI.Text(page, "GameFontNormalSmall", text, C.faint)
        label:SetPoint("TOPRIGHT", -right, -48)
        label:SetWidth(width)
        label:SetJustifyH("CENTER")
    end
    local nameHeader = UI.Text(page, "GameFontNormalSmall", "ИГРОК", C.faint)
    nameHeader:SetPoint("TOPLEFT", COL.nameLeft, -48)
    nameHeader:SetJustifyH("LEFT")
    Header("РОЛЬ", COL.roleWidth, COL.roleRight)
    Header("ЭКИПИРОВКА", COL.ilvlWidth + 40, COL.ilvlRight - 20)
    Header("РЕЙТИНГ", COL.ratingWidth, COL.ratingRight)
    Header("ОТБОР", COL.statusWidth, COL.statusRight)

    self.rows = {}
    for index = 1, MAX_ROWS do
        local row = CreateRow(page, index)
        row:SetPoint("TOPLEFT", 12, -64 - (index - 1) * ROW_STEP)
        row:SetPoint("TOPRIGHT", -18, -64 - (index - 1) * ROW_STEP)
        self.rows[index] = row
    end

    self.scrollBar = UI.ScrollBar(page)
    self.scrollBar:SetPoint("TOPRIGHT", -6, -64)
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
    self.message:SetPoint("TOPLEFT", 24, -120)
    self.message:SetPoint("TOPRIGHT", -24, -120)
    self.message:SetJustifyH("CENTER")
    self.message:SetSpacing(6)

    self:Layout()
end

function ApplicantBoard:Layout()
    if not self.page then return end
    local height = self.page:GetHeight()
    if height < 100 then return end
    local visible = math.max(2, math.min(MAX_ROWS, math.floor((height - 72) / ROW_STEP)))
    self.visibleRows = visible
    for index, row in ipairs(self.rows or {}) do
        row.layoutVisible = index <= visible
        if not row.layoutVisible then row:Hide() end
    end
end

function ApplicantBoard:Render()
    local entries = self.entries or {}
    local offset = self.offset or 0
    for index, row in ipairs(self.rows) do
        local entry = entries[offset + index]
        if entry and row.layoutVisible ~= false then
            local style = entry.status and STATUS[entry.status]

            row.name:SetText(("%s  %s"):format(UI.ClassIcon(entry.classFile, 18), entry.name))
            row.name:SetTextColor(UI.ClassColor(entry.classFile))
            row.role:SetText(UI.RoleIcon(entry.role, 18))
            row.ilvl:SetText(entry.itemLevel > 0 and ("%.0f"):format(entry.itemLevel) or "—")
            row.rating:SetText(entry.score > 0 and tostring(math.floor(entry.score)) or "—")

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
            row.invite:SetText(entry.numMembers > 1 and ("Взять +" .. (entry.numMembers - 1)) or "Пригласить")
            row.decline.applicantID = entry.applicantID
            row:Show()
        else
            row.invite.applicantID = nil
            row.decline.applicantID = nil
            row:Hide()
        end
    end
end

function ApplicantBoard:Refresh()
    if not self.page then return end
    self:Layout()

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
        self.needs:SetText(("|cff8a939fнужно|r  %s %d   %s %d   %s %d"):format(
            UI.RoleIcon("TANK", 14), missing.TANK,
            UI.RoleIcon("HEALER", 14), missing.HEALER,
            UI.RoleIcon("DAMAGER", 14), missing.DAMAGER))
    else
        self.needs:SetText("")
    end

    if #entries == 0 then
        local listed = C_LFGList.GetActiveEntryInfo and C_LFGList.GetActiveEntryInfo()
        self.message:SetText(listed
            and "Заявок пока нет.\nОни появятся здесь, как только кто-то откликнется."
            or "Ты сейчас не собираешь группу.\nСоздай объявление в поиске групп — заявки придут сюда.")
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
