local _, JP = ...
local N, UI, L, C = JP.PlayerNetwork, JP.UI, JP.L, JP.UI.colors

local WIDTH, HEIGHT = 600, 670
local HISTORY_ROWS, PARTY_ROWS = 10, 4

local function Label(parent, text, x, y, width, color)
    local f = UI.Text(parent, "GameFontHighlightSmall", text, color or C.text)
    f:SetPoint("TOPLEFT", x, y)
    f:SetWidth(width)
    f:SetJustifyH("LEFT")
    f:SetWordWrap(false)
    return f
end

local function Window(name, width, height)
    local f = UI.HUDPanel(UIParent, name, width, height)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    -- Keep the memory window movable from its empty header area. Child rows
    -- still receive their own clicks, while dragging never moves a Blizzard
    -- frame or an external tooltip.
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(owner) owner:StartMoving() end)
    f:SetScript("OnDragStop", function(owner) owner:StopMovingOrSizing() end)
    f:SetBackdropColor(C.window[1], C.window[2], C.window[3], C.window[4])
    local close = UI.Button(f, "x", 24, 24)
    close:SetPoint("TOPRIGHT", -10, -10)
    close:SetScript("OnClick", function() f:Hide() end)
    f:Hide()
    return f
end

local function Has(mask, index)
    return math.floor((mask or 0) / 2^(index - 1)) % 2 == 1
end

local function FullName(value, realm)
    return value and JP.Reviews and JP.Reviews.FullName(value, realm)
end

local function SetButtonText(button, text)
    if button.label then button.label:SetText(text) else button:SetText(text) end
end

function N:PaintTags()
    for i, button in ipairs(self.tagButtons or {}) do
        button:SetBackdropBorderColor(UI.Unpack(
            Has(self.draftMask or 0, i) and C.green or C.lineSoft))
    end
end

function N:PaintAvoid()
    local days = self.avoidDays
    if days == nil then
        self.avoid:SetText(L("Не приглашать: выкл."))
    elseif days == 0 then
        self.avoid:SetText(L("Не приглашать: бессрочно"))
    else
        self.avoid:SetText((L("Не приглашать: %d д.")):format(days))
    end
end

local function PaintMemoryRow(row, run, target)
    if not run then
        row.run = nil
        row.text:SetText("")
        row.stats:SetText("")
        row:Hide()
        return
    end
    row.run = run
    row:SetShown(true)
    local stamp = JP.SafeNumber(run.completedAt)
    row.text:SetText(("%s  %s +%d  -  %s"):format(
        stamp and date("%d.%m", stamp) or "—",
        run.mapName or L("Подземелье"),
        run.level or 0,
        run.onTime and L("В ТАЙМЕР") or L("не закрыт")))
    if JP.RunStats then
        row.stats:SetText(JP.RunStats:Text(JP.RunStats:ForMember(run, target)))
    else
        row.stats:SetText("")
    end
end

function N:CreateMemory()
    if self.frame then return end
    local f = Window("MythicBoostPlayerMemory", WIDTH, HEIGHT)
    self.frame = f

    self.title = Label(f, "", 16, -16, 530, C.accent)
    self.title:SetJustifyH("LEFT")
    self.context = Label(f, "", 16, -44, 568, C.text)
    self.context:SetHeight(68)
    self.context:SetWordWrap(true)
    self.historyHint = Label(f,
        L("История и цифры — локальные данные; статистика только для чтения."),
        16, -112, 568, C.muted)

    self.runRows = {}
    for i = 1, HISTORY_ROWS do
        local row = CreateFrame("Frame", nil, f)
        row:SetPoint("TOPLEFT", 16, -132 - (i - 1) * 25)
        row:SetSize(568, 24)
        row:EnableMouse(true)
        local shade = row:CreateTexture(nil, "BACKGROUND")
        shade:SetAllPoints()
        shade:SetColorTexture(.12, .18, .22, i % 2 == 0 and .26 or .08)
        row.text = Label(row, "", 5, -3, 370, C.muted)
        row.stats = Label(row, "", 376, -3, 187, C.amber)
        row.stats:SetJustifyH("RIGHT")
        row:SetScript("OnEnter", function()
            if not row.run then return end
            local stats = JP.RunStats and JP.RunStats:Text(
                JP.RunStats:ForMember(row.run, self.target), true)
            UI.Tooltip(row, row.run.mapName or L("Подземелье"), stats,
                L("DPS/HPS: сумма за ключ / время счётчика Blizzard. Статистика только для чтения."))
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
        self.runRows[i] = row
    end

    Label(f, L("Публичные рекомендации - выбираешь сам"), 16, -389, 568, C.accent)
    self.tagButtons = {}
    for i, text in ipairs(self.tags or {}) do
        -- The network deliberately exposes seven positive choices. Keep the
        -- grid bounded if an older/newer database contains extra values.
        if i > 7 then break end
        local button = UI.Button(f, text, 136, 24)
        button:SetPoint("TOPLEFT", 16 + ((i - 1) % 4) * 140,
            -412 - math.floor((i - 1) / 4) * 28)
        button:SetScript("OnClick", function()
            local bit = 2^(i - 1)
            self.draftMask = (self.draftMask or 0)
                + (Has(self.draftMask or 0, i) and -bit or bit)
            self:PaintTags()
        end)
        self.tagButtons[i] = button
    end

    self.localLabel = Label(f, L("Личная заметка - не передаётся"),
        16, -474, 360, C.muted)
    self.note = UI.NumberBox(f, 568, 27)
    self.note.frame:SetPoint("TOPLEFT", 16, -495)
    self.note:SetNumeric(false)
    self.note:SetMaxLetters(120)
    self.note:SetJustifyH("LEFT")

    self.avoid = UI.Button(f, "", 270, 25)
    self.avoid:SetPoint("TOPLEFT", 16, -535)
    self.avoid:SetScript("OnClick", function()
        -- nil (off) -> 1 -> 7 -> 30 -> 0 (permanent) -> nil.
        local nextDays = {[1] = 7, [7] = 30, [30] = 0, [0] = nil}
        self.avoidDays = self.avoidDays == nil and 1 or nextDays[self.avoidDays]
        self.avoidChanged = true
        self:PaintAvoid()
    end)
    local save = UI.Button(f, L("Сохранить"), 132, 28, true)
    self.saveButton = save
    save:SetPoint("TOPRIGHT", -16, -533)
    save:SetScript("OnClick", function()
        if not self.target then return end
        local old = self:GetOwn(self.target)
        if (old and old.mask or 0) ~= (self.draftMask or 0)
            and not self:Recommend(self.target, self.draftMask or 0) then
            JP:Print(L("Рекомендация доступна после совместного ключа."))
            return
        end
        local previous = self:Private(self.target)
        local expires = previous and previous.avoidUntil
        if not self:SavePrivate(self.target, self.note:GetText(), self.avoidDays) then
            JP:Print(L("Не удалось сохранить личную заметку."))
            return
        end
        -- Note edits must retain the exact existing temporary expiry. The
        -- expiry changes only when the user explicitly clicks Avoid.
        if not self.avoidChanged then
            local saved = self:Private(self.target)
            if saved then saved.avoidUntil = expires end
        end
        self.note:ClearFocus()
        f:Hide()
    end)

    self.syncButton = UI.Button(f, L("Обмен рекомендациями"), 270, 25)
    self.syncButton:SetPoint("TOPLEFT", 16, -576)
    self.syncButton:SetScript("OnClick", function()
        local enabled = JP.Settings("playerNetwork").enabled ~= false
        self:SetEnabled(not enabled)
        self:PaintSync()
    end)
    self.syncStatus = Label(f, "", 300, -579, 284, C.muted)
    self.syncStatus:SetJustifyH("RIGHT")
    self.foot = Label(f,
        L("Личная заметка и Avoid не передаются. Рекомендации — отдельный обмен."),
        16, -620, 568, C.muted)
    self.foot:SetWordWrap(true)
    self.foot:SetHeight(34)
    f:SetScript("OnHide", function()
        self.note:ClearFocus()
        self.target = nil
        for _, row in ipairs(self.runRows) do
            row.run = nil
            row:Hide()
        end
        GameTooltip_Hide()
    end)
end

function N:PaintSync()
    local enabled = JP.Settings("playerNetwork").enabled ~= false
    self.syncButton:SetBackdropBorderColor(UI.Unpack(enabled and C.green or C.lineSoft))
    self.syncStatus:SetText(JP.PlayerNetwork:Status())
end

function N:ShowMemory(target)
    target = FullName(target)
    if not target or JP.SafeOptionalBoolean(InCombatLockdown()) ~= false then return end
    -- Opening this window from a player row can leave the row's tooltip alive;
    -- that used to render a second "ПАМЯТЬ ИГРОКА" block over the window.
    GameTooltip_Hide()
    self:CreateMemory()
    self.target = target
    local summary, c = self:Summary(target)
    c = c or {runs = {}, recommended = 0}
    self.title:SetText(target)
    self.context:SetText(summary or L("Совместных ключей пока нет"))
    for i, row in ipairs(self.runRows) do
        PaintMemoryRow(row, c.runs and c.runs[i], target)
    end
    self.draftMask = c.recommended or 0
    self:PaintTags()
    self.note:SetText(c.private and c.private.note or "")
    local expires = c.private and c.private.avoidUntil
    self.avoidDays = expires and (expires == 0 and 0
        or math.ceil((expires - time()) / 86400)) or nil
    if self.avoidDays and self.avoidDays ~= 0 then
        self.avoidDays = self.avoidDays <= 1 and 1
            or self.avoidDays <= 7 and 7 or 30
    end
    self.avoidChanged = nil
    self:PaintAvoid()
    self:PaintSync()
    self.frame:Show()
end

function N:ShowRoster()
    if JP.SafeOptionalBoolean(InCombatLockdown()) ~= false then return end
    if not self.rosterFrame then
        local f = Window("MythicBoostGroupMemory", 600, 310)
        self.rosterFrame = f
        Label(f, L("МОЯ ГРУППА"), 16, -16, 530, C.accent)
        f.summary = Label(f, "", 16, -45, 568, C.muted)
        f.rows = {}
        for i = 1, PARTY_ROWS do
            local row = UI.Button(f, "", 568, 46)
            row:SetPoint("TOPLEFT", 16, -77 - (i - 1) * 51)
            if row.label then
                row.label:SetPoint("TOPLEFT", 8, -6)
                row.label:SetPoint("TOPRIGHT", -8, -6)
                row.label:SetJustifyH("LEFT")
                row.label:SetWordWrap(false)
            end
            row:SetScript("OnClick", function()
                if row.target then self:ShowMemory(row.target) end
            end)
            f.rows[i] = row
        end
        f:SetScript("OnHide", function()
            for _, row in ipairs(f.rows) do row.target = nil end
        end)
    end
    local known, total, warnings = 0, 0, 0
    for i, row in ipairs(self.rosterFrame.rows) do
        local unit = "party" .. i
        local name = JP.SafeOptionalBoolean(UnitExists(unit)) == true
            and FullName(UnitFullName(unit))
        row.target = name
        row:SetShown(name ~= nil and name ~= false)
        if name then
            local c = self:Context(name)
            total = total + 1
            if c.history then known = known + 1 end
            local avoid = c.private and c.private.avoidUntil ~= nil
            if avoid then warnings = warnings + 1 end
            local text = avoid and L("Личная метка: пока не приглашать")
                or c.history and (L("Вместе: %d ключей - в таймер: %d")):format(
                    c.history.runs or 0, c.history.timed or 0)
                or c.trusted > 0 and (L("Рекомендуют знакомые: %d")):format(c.trusted)
                or L("Совместных ключей пока нет")
            SetButtonText(row, name .. "\n" .. text)
            row:SetBackdropBorderColor(UI.Unpack(
                avoid and C.amber or c.history and C.green or C.lineSoft))
        end
    end
    self.rosterFrame.summary:SetText((L("Знакомые: %d/%d - личные предупреждения: %d")):format(
        known, total, warnings))
    self.rosterFrame:Show()
end
