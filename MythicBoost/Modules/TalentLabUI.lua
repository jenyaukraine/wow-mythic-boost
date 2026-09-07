local _, JP = ...
local Lab, UI, L, C = JP.TalentLab, JP.UI, JP.L, JP.UI.colors

local WIDTH, HEIGHT = 640, 580
local ROW_STEP, ROW_HEIGHT, ROW_VIEWPORT_HEIGHT = 34, 31, 270
local MAX_ROWS, MAX_RUNS = 256, 30

local function Number(value)
    value = JP.SafeNumber(value)
    return type(value) == "number" and value == value and value ~= math.huge
        and value ~= -math.huge and value >= 0 and value or nil
end

local function FormatDuration(seconds)
    seconds = Number(seconds)
    if not seconds or seconds <= 0 or seconds > 86400 then return "—" end
    seconds = math.floor(seconds + .5)
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

local function CanUseUI()
    if type(InCombatLockdown) ~= "function" then return false end
    local ok, locked = pcall(InCombatLockdown)
    return ok and not JP.IsSecret(locked) and (locked == nil or locked == false)
end

local function Text(value)
    value = JP.SafeString(value)
    return type(value) == "string" and value ~= "" and value or nil
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end

local function Label(parent, value, x, y, width, color)
    local f = UI.Text(parent, "GameFontHighlightSmall", value or "", color or C.text)
    f:SetPoint("TOPLEFT", x, y); f:SetWidth(width)
    f:SetJustifyH("LEFT"); f:SetWordWrap(false)
    return f
end

local function Panel(name, width, height)
    local f = UI.HUDPanel(UIParent, name, width, height)
    f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); f:SetClampedToScreen(true)
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(owner) owner:StartMoving() end)
    f:SetScript("OnDragStop", function(owner) owner:StopMovingOrSizing() end)
    local close = UI.Button(f, "x", 24, 24)
    close:SetPoint("TOPRIGHT", -10, -10)
    close:SetScript("OnClick", function() f:Hide() end)
    f:Hide(); return f
end

local function Compact(value)
    if not Number(value) then return "—" end
    if value >= 1000000000 then return ("%.2fB"):format(value / 1000000000) end
    if value >= 1000000 then return ("%.2fM"):format(value / 1000000) end
    if value >= 1000 then return ("%.1fk"):format(value / 1000) end
    return ("%.0f"):format(value)
end

local function Count(value)
    local n = 0
    for _ in pairs(type(value) == "table" and value or {}) do n = n + 1 end
    return n
end

local function SetButtonEnabled(button, enabled)
    if type(button.SetEnabled) == "function" then
        button:SetEnabled(enabled == true)
    end
    if button.label and type(button.label.SetTextColor) == "function" then
        button.label:SetTextColor(enabled and .9 or .35, enabled and .95 or .38,
            enabled and 1 or .42, 1)
    end
end

local function SpellInfo(spellID)
    spellID = Number(spellID)
    if not spellID or spellID % 1 ~= 0 or spellID > 100000000 then return end
    if not C_Spell or type(C_Spell.GetSpellInfo) ~= "function" then return spellID end
    local info = Call(C_Spell.GetSpellInfo, spellID)
    if type(info) == "table" then
        return spellID, Text(info.name), info.iconID
    end
    if type(info) == "string" then return spellID, info end
    return spellID
end

local function RunStamp(run)
    return Number(run and (run.completedAt or run.startedAt)) or 0
end

local function ReadRuns()
    local settings = JP.Settings("runHistory", {runs = {}})
    local source = settings and type(settings.runs) == "table" and settings.runs or {}
    local runs = {}
    for i = 1, math.min(#source, MAX_RUNS) do
        if type(source[i]) == "table" then runs[#runs + 1] = source[i] end
    end
    table.sort(runs, function(a, b) return RunStamp(a) > RunStamp(b) end)
    return runs
end

local function BuildText(sample)
    if type(sample) ~= "table" then return L("Сборка неизвестна") end
    local name = Text(sample.buildName) or Text(sample.buildKey) or L("Сборка без названия")
    local selected = Count(sample.selected)
    return (L("Сборка: %s - выбранных талантов: %d")):format(name, selected)
end

local function PublicTooltip(row)
    local id = row and Number(row.spellID)
    if not id or id % 1 ~= 0 then return end
    if row.comparisonDetail then
        UI.Tooltip(row,row.spellName or L("Талант"),row.comparisonDetail)
        return
    end
    -- Only rows owned by this panel may invoke the native tooltip. There are
    -- no global tooltip hooks and no traversal of Blizzard talent objects.
    if GameTooltip and type(GameTooltip.SetSpellByID) == "function" then
        local ownerOK = type(GameTooltip.SetOwner) ~= "function"
            or pcall(GameTooltip.SetOwner, GameTooltip, row, "ANCHOR_RIGHT")
        local ok = ownerOK and pcall(GameTooltip.SetSpellByID, GameTooltip, id)
        if ok then
            if row.kind == "unattributed" and type(GameTooltip.AddLine) == "function" then
                GameTooltip:AddLine(L("Источник не сопоставлен или отсутствует в этом замере."), .7, .7, .7, true)
            end
            GameTooltip:Show(); return
        end
    end
    UI.Tooltip(row, row.spellName or L("Источник заклинания"),
        (L("Публичный ID заклинания: %d")):format(id),
        row.kind == "unattributed" and L("Источник не сопоставлен или отсутствует в этом замере.") or nil)
end

local function HideTooltip()
    if GameTooltip_Hide then GameTooltip_Hide() end
end

function Lab.UIRows(sample, metric)
    if not Lab or type(Lab.Rows) ~= "function" then return {} end
    local rows = Call(Lab.Rows, Lab, sample, metric)
    return type(rows) == "table" and rows or {}
end

function Lab:CreateUI()
    if self.uiFrame then return end
    local f = Panel("MythicBoostTalentLab", WIDTH, HEIGHT)
    f:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
    f:SetBackdropColor(.018, .026, .034, .98)
    f:SetBackdropBorderColor(.30, .32, .34, .92)
    self.uiFrame = f; self.rows = {}; self.page = 0; self.metric = "healing"; self.view = "sources"

    self.uiTitle = Label(f, L("ЛАБОРАТОРИЯ ТАЛАНТОВ"), 16, -16, 580, C.accent)
    self.uiSubtitle = Label(f, "", 16, -43, 450, C.text)
    self.uiSubtitle:SetWordWrap(true); self.uiSubtitle:SetMaxLines(1); self.uiSubtitle:SetHeight(18)
    self.uiDate = Label(f, "", 16, -65, 450, C.muted)
    self.uiBuild = Label(f, "", 16, -87, 445, C.muted)
    self.uiBuild:SetWordWrap(true); self.uiBuild:SetMaxLines(1); self.uiBuild:SetHeight(18)
    self.comparisonButton = UI.Button(f,L("Сравнить сборки"),140,25)
    self.comparisonButton:SetPoint("TOPLEFT",476,-83)
    self.comparisonButton:SetScript("OnClick",function()
        self.view="comparison"; self.keyPickerMenu:Hide(); self:Render()
    end)
    self.keyPicker = UI.Button(f, L("Выбрать ключ"), 136, 28)
    self.keyPicker:SetPoint("TOPRIGHT", -16, -39)
    self.keyPicker:SetScript("OnClick", function()
        self.keyPickerMenu:SetShown(not self.keyPickerMenu:IsShown())
        if self.keyPickerMenu:IsShown() then self:RefreshKeyPicker() end
    end)

    self.keyPickerMenu = UI.Panel(f, { C.window[1], C.window[2], C.window[3], .99 }, C.surfaceEdge)
    self.keyPickerMenu:SetSize(330, 252)
    self.keyPickerMenu:SetPoint("TOPRIGHT", self.keyPicker, "BOTTOMRIGHT", 0, -5)
    self.keyPickerMenu:SetFrameStrata("TOOLTIP")
    self.keyPickerMenu:EnableMouse(true)
    self.keyPickerScroll = CreateFrame("ScrollFrame", nil, self.keyPickerMenu,
        "UIPanelScrollFrameTemplate")
    self.keyPickerScroll:SetPoint("TOPLEFT", 8, -8)
    self.keyPickerScroll:SetPoint("BOTTOMRIGHT", -30, 8)
    self.keyPickerScroll:EnableMouseWheel(true)
    self.keyPickerCanvas = CreateFrame("Frame", nil, self.keyPickerScroll)
    self.keyPickerCanvas:SetSize(292, 1)
    self.keyPickerScroll:SetScrollChild(self.keyPickerCanvas)
    self.keyPickerOptions = {}
    self.keyPickerMenu:Hide()

    self.healButton = UI.Button(f, L("Исцеление / HPS"), 132, 25)
    self.healButton:SetPoint("TOPLEFT", 16, -120)
    self.damageButton = UI.Button(f, L("Урон / DPS"), 110, 25)
    self.damageButton:SetPoint("TOPLEFT", 154, -120)
    self.sourceButton = UI.Button(f, L("Источники"), 98, 25)
    self.sourceButton:SetPoint("TOPLEFT", 272, -120)
    self.talentButton = UI.Button(f, L("Таланты"), 92, 25)
    self.talentButton:SetPoint("TOPLEFT", 376, -120)
    self.allTalentsButton = UI.Button(f, L("Все таланты"), 140, 25)
    self.allTalentsButton:SetPoint("TOPLEFT", 476, -120)
    self.allTalentsButton:SetScript("OnClick", function()
        if self.view=="comparison" then self.showComparisonAll=not self.showComparisonAll
        else self.showUnknown = not self.showUnknown end
        self:Render()
    end)
    self.healButton:SetScript("OnClick", function() self.metric = "healing"; self.page = 0; self:Render() end)
    self.damageButton:SetScript("OnClick", function() self.metric = "damage"; self.page = 0; self:Render() end)
    self.sourceButton:SetScript("OnClick", function() self.view = "sources"; self.page = 0; self:Render() end)
    self.talentButton:SetScript("OnClick", function() self.view = "talents"; self.page = 0; self:Render() end)

    self.sourceHeader = Label(f, L("Источник"), 16, -155, 250, C.accent)
    self.amountHeader = Label(f, L("Сумма"), 330, -155, 82, C.accent); self.amountHeader:SetJustifyH("RIGHT")
    self.rateHeader = Label(f, L("Скорость"), 420, -155, 80, C.accent); self.rateHeader:SetJustifyH("RIGHT")
    self.shareHeader = Label(f, L("Доля"), 510, -155, 74, C.accent); self.shareHeader:SetJustifyH("RIGHT")

    -- The list gets its own clipped viewport. Keeping the canvas separate from
    -- the panel means every measured source/talent can be reached with the
    -- native scrollbar instead of being split across pages.
    self.rowScroll = CreateFrame("ScrollFrame", "MythicBoostTalentLabRows", f,
        "UIPanelScrollFrameTemplate")
    self.rowScroll:SetPoint("TOPLEFT", 16, -174)
    self.rowScroll:SetSize(568, ROW_VIEWPORT_HEIGHT)
    self.rowScroll:EnableMouseWheel(true)
    self.rowCanvas = CreateFrame("Frame", nil, self.rowScroll)
    self.rowCanvas:SetSize(568, ROW_VIEWPORT_HEIGHT)
    self.rowScroll:SetScrollChild(self.rowCanvas)

    local function Scroll(delta)
        local maximum = self.rowScroll:GetVerticalScrollRange()
        self.rowScroll:SetVerticalScroll(math.max(0, math.min(maximum,
            self.rowScroll:GetVerticalScroll() - delta * ROW_STEP)))
    end
    self.rowScroll:SetScript("OnMouseWheel", function(_, delta) Scroll(delta) end)

    local function CreateRow(index)
        local row = CreateFrame("Button", nil, self.rowCanvas, "BackdropTemplate")
        row:SetSize(568, ROW_HEIGHT); row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_STEP)
        row:EnableMouse(true); row:EnableMouseWheel(true)
        local shade = row:CreateTexture(nil, "BACKGROUND"); shade:SetAllPoints()
        shade:SetColorTexture(.12, .18, .22, index % 2 == 0 and .25 or .08)
        row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(26, 26); row.icon:SetPoint("LEFT", 5, 0)
        row.nameText = Label(row, "", 38, -5, 275, C.text)
        row.amount = Label(row, "", 320, -5, 86, C.text); row.amount:SetJustifyH("RIGHT")
        row.rate = Label(row, "", 410, -5, 86, C.amber); row.rate:SetJustifyH("RIGHT")
        row.share = Label(row, "", 500, -5, 62, C.green); row.share:SetJustifyH("RIGHT")
        row.meta = Label(row,"",38,-24,520,C.muted); row.meta:Hide()
        row:SetScript("OnEnter", function() PublicTooltip(row) end)
        row:SetScript("OnLeave", HideTooltip)
        row:SetScript("OnMouseWheel", function(_, delta) Scroll(delta) end)
        return row
    end
    self.createRow = CreateRow

    self.empty = Label(f, "", 16, -448, 568, C.muted); self.empty:SetWordWrap(true); self.empty:SetHeight(44)
    self.coverage = Label(f, "", 16, -489, 600, C.muted)
    self.compare = Label(f, "", 16, -514, 600, C.amber); self.compare:SetWordWrap(true); self.compare:SetHeight(52)
    f:SetScript("OnHide", function()
        HideTooltip()
        self.latestRun, self.sampleRuns = nil, nil
        self.comparisonContexts=nil
        self.keyPickerMenu:Hide()
    end)
end

function Lab:RefreshKeyPicker()
    if not self.keyPickerOptions then return end
    local comparing=self.view=="comparison"
    local runs = (comparing and self.comparisonContexts or self.sampleRuns) or {}
    local count = math.min(#runs, MAX_RUNS)
    while #self.keyPickerOptions < count do
        local index = #self.keyPickerOptions + 1
        local option = UI.Button(self.keyPickerCanvas, "", 292, 44)
        if option.label then
            option.label:ClearAllPoints(); option.label:SetPoint("LEFT", 8, 0)
            option.label:SetSize(276, 36); option.label:SetJustifyH("LEFT")
            option.label:SetWordWrap(true); option.label:SetMaxLines(2)
        end
        option:SetPoint("TOPLEFT", 0, -(index - 1) * 48)
        option:SetScript("OnClick", function()
            if self.view=="comparison" then
                local context=self.comparisonContexts and self.comparisonContexts[index]
                self.comparisonKey=context and context.key
            else self.sampleIndex = index end
            self.keyPickerMenu:Hide()
            self:Render()
        end)
        self.keyPickerOptions[index] = option
    end
    self.keyPickerCanvas:SetSize(292, math.max(1, count * 48))
    self.keyPickerScroll:SetVerticalScroll(math.min(self.keyPickerScroll:GetVerticalScroll(),
        self.keyPickerScroll:GetVerticalScrollRange()))
    for index, option in ipairs(self.keyPickerOptions) do
        local run = index <= count and runs[index] or nil
        option:SetShown(run ~= nil)
        if run then
            if comparing then
                option:SetText(("+%d %s\n"):format(run.level,run.mapName or L("Подземелье"))
                    ..(L("Замеров: %d | Талантов с парой: %d")):format(run.runs,run.pairs))
            else
            local sample = run.talentSample or {}
            local map = Text(run.mapName) or L("Подземелье")
            local level = Number(run.level) or 0
            local stamp = RunStamp(run)
            local completed = stamp > 0 and date("%d.%m %H:%M", stamp) or "—"
            option:SetText(("%s +%d\n%s | %s"):format(
                map, level, completed, (L("Замер %s")):format(FormatDuration(sample.duration))))
            end
        end
    end
end

function Lab:CompareText(runs, metric)
    if not Lab or type(Lab.Compare) ~= "function" then
        return L("Сравнение недоступно: нужны две сборки одной специализации, версии, карты и уровня с полными снимками.")
    end
    local compared = Call(Lab.Compare, Lab, runs, metric)
    if type(compared) ~= "table" or type(compared.builds) ~= "table" or #compared.builds < 2 then
        return L("Сравнение недоступно: измеримые данные не подтверждены.")
    end
    local function Rate(result)
        local total = 0
        for _, row in ipairs(result.rows or {}) do total = total + (Number(row.amount) or 0) end
        return Number(result.duration) and result.duration > 0 and total / result.duration or nil
    end
    local a = compared.builds[1]
    local b
    if a then
        for i = 2, #compared.builds do
            local candidate = compared.builds[i]
            if candidate.specID == a.specID and candidate.gameBuild == a.gameBuild
                and candidate.mapID == a.mapID and candidate.level == a.level
                and candidate.buildKey ~= a.buildKey then
                b = candidate; break
            end
        end
    end
    if not a or not b then return L("Сравнение недоступно: измеримые данные не подтверждены.") end
    local unit = metric == "healing" and "HPS" or "DPS"
    local ra, rb = Rate(a), Rate(b)
    local left = Text(a.buildName) or Text(a.buildKey) or L("Сборка неизвестна")
    local right = Text(b.buildName) or Text(b.buildKey) or L("Сборка неизвестна")
    local line = (L("Сравнение сборок - %s: %s (%d ключей) - %s: %s (%d ключей)")):format(
        left, ra and (unit .. " " .. Compact(ra)) or "—", a.runs or 0,
        right, rb and (unit .. " " .. Compact(rb)) or "—", b.runs or 0)
    return line .. "\n" .. L("Условия и состав группы влияют на результат.")
end

local function CohortText(label,summary,unit)
    if summary.runs==0 then return label..": "..L("Нет замеров") end
    local range=summary.hasSpread and (Compact(summary.min).." - "..Compact(summary.max))
        or L("нужны хотя бы 2 замера")
    return (L("%s: %s %s | замеров: %d")):format(label,Compact(summary.mean),unit,summary.runs)
        .."\n"..(L("Диапазон: %s")):format(range)
        .."\n"..(L("Замерено: %s")):format(FormatDuration(summary.duration))
end

function Lab:StyleButtons()
    for _,state in ipairs({{self.healButton,self.metric=="healing"},{self.damageButton,self.metric=="damage"},
        {self.sourceButton,self.view=="sources"},{self.talentButton,self.view=="talents"},
        {self.comparisonButton,self.view=="comparison"}}) do
        local button,active=state[1],state[2]
        button:SetBackdropBorderColor(active and .25 or .30,active and .70 or .32,active and .85 or .34,1)
        button:SetBackdropColor(active and .06 or .025,active and .16 or .032,active and .21 or .042,1)
    end
end

function Lab:RenderComparison(runs)
    self:StyleButtons()
    local result=self:CompareTalents(runs,self.metric)
    local contexts=result.contexts
    self.comparisonContexts=contexts
    local context=contexts[1]
    for _,candidate in ipairs(contexts) do if candidate.key==self.comparisonKey then context=candidate; break end end
    self.comparisonKey=context and context.key
    self.keyPicker:SetText(L("Выбрать условия")); SetButtonEnabled(self.keyPicker,#contexts>0)
    self:RefreshKeyPicker()
    self.uiSubtitle:SetText(context and (L("Сравнение: +%d %s")):format(context.level,context.mapName or L("Подземелье"))
        or L("Нет замеров с известной неизменной сборкой"))
    local unit=self.metric=="healing" and "HPS" or "DPS"
    self.uiDate:SetText(context and (L("Замеров: %d | Неполных: %d | %s")):format(context.runs,context.partial,context.gameBuild) or "")
    self.uiBuild:SetText((L("Средний %s за прохождение: с талантом / без таланта")):format(unit))
    self.sourceHeader:SetText(L("Талант / ранг"))
    self.amountHeader:SetText(L("С талантом")); self.rateHeader:SetText(L("Без таланта"))
    self.shareHeader:SetText(L("Разница"))
    self.allTalentsButton:Show()
    self.allTalentsButton:SetText(self.showComparisonAll and L("Только с парой") or L("Все таланты"))
    local rows={}
    for _,row in ipairs(context and context.rows or {}) do
        if row.comparable or self.showComparisonAll then rows[#rows+1]=row end
    end
    while #self.rows<#rows do self.rows[#self.rows+1]=self.createRow(#self.rows+1) end
    self.rowCanvas:SetSize(568,math.max(ROW_VIEWPORT_HEIGHT,#rows*48)); self.rowScroll:SetVerticalScroll(0)
    for i,row in ipairs(self.rows) do
        local data=rows[i]
        row:SetShown(data~=nil)
        if data then
            local id,name,icon=SpellInfo(data.spellID)
            row.spellID=id; row.spellName=name or (L("ID заклинания %d")):format(id)
            row.kind=nil
            row:SetHeight(44); row:ClearAllPoints(); row:SetPoint("TOPLEFT",0,-(i-1)*48)
            row.nameText:SetText(row.spellName.." ("..data.rank..")")
            row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.amount:SetWidth(86); row.amount:SetText(Compact(data.with.mean)); row.rate:SetText(Compact(data.without.mean))
            row.share:SetText(data.percent and ("%+.1f%%"):format(data.percent) or "—")
            row.share:SetTextColor(UI.Unpack(C.amber)); row.amount:SetTextColor(UI.Unpack(C.text))
            row.meta:Show()
            row.meta:SetText((L("Замеров с / без: %d / %d")):format(data.with.runs,data.without.runs)
                ..(not data.comparable and (" | "..L("Нет пары")) or data.smallSample and (" | "..L("Мало замеров")) or "")
                ..(data.partial and (" | "..L("Неполные данные")) or ""))
            local detail=CohortText(L("С талантом"),data.with,unit).."\n"..CohortText(L("Без таланта"),data.without,unit)
            if data.comparable then
                detail=detail.."\n"..(L("Других различий в талантах: %d - %d")):format(data.otherChangesMin,data.otherChangesMax)
                if data.rosterChanged then detail=detail.."\n"..L("Состав группы различается.") end
                if data.rosterUnknown then detail=detail.."\n"..L("Состав группы неизвестен.") end
            end
            row.comparisonDetail=detail.."\n"..L("Это сравнение результатов сборок, не доказанный прирост от одного таланта.")
        else
            row.spellID=nil; row.comparisonDetail=nil; row.meta:Hide()
        end
    end
    self.empty:SetText(context and (L("Талантов с замерами с обеих сторон: %d. Наведи на строку для диапазона и условий.")):format(context.pairs)
        or L("Нужны сохранённые прохождения с известными талантами и длительностью замера."))
    self.coverage:SetText((L("Исключено: смешанная сборка %d | недоступные данные %d")):format(result.excluded.mixed,result.excluded.invalid))
    self.compare:SetText(L("Это сравнение результатов сборок, не доказанный прирост от одного таланта.")
        .."\n"..L("При одном замере с каждой стороны разброс неизвестен."))
end

function Lab:Render()
    local runs = ReadRuns()
    if self.view=="comparison" and self.CompareTalents then self:RenderComparison(runs); return end
    self.comparisonContexts=nil
    local sampleRuns = {}
    for _, run in ipairs(runs) do
        if type(run.talentSample) == "table" then sampleRuns[#sampleRuns + 1] = run end
    end
    self.sampleRuns = sampleRuns
    self.sampleIndex = math.max(1, math.min(self.sampleIndex or 1, math.max(1, #sampleRuns)))
    local latest = sampleRuns[self.sampleIndex]
    self.latestRun = latest
    local sample = latest and latest.talentSample
    if self.ResolveSample then sample=self:ResolveSample(sample,runs) end
    local selectedMap = latest and (Text(latest.mapName) or L("Подземелье")) or L("Подземелье")
    local selectedLevel = latest and (Number(latest.level) or 0) or 0
    local selectedStamp = latest and RunStamp(latest) or 0
    local selectedDate = selectedStamp > 0 and date("%d.%m %H:%M", selectedStamp) or "—"
    local selectedDuration = latest and latest.talentSample and latest.talentSample.duration
    self.keyPicker:SetText(L("Выбрать ключ"))
    SetButtonEnabled(self.keyPicker, #sampleRuns > 0)
    self.uiDate:SetText(latest and (selectedDate .. " | " .. (L("Ключ %s / замер %s")):format(
        FormatDuration(latest.duration), FormatDuration(selectedDuration))) or "")
    self.allTalentsButton:SetShown(self.view=="talents")
    self.allTalentsButton:SetText(self.showUnknown and L("Только с цифрами") or L("Все таланты"))
    self:StyleButtons()
    self:RefreshKeyPicker()
    self.uiSubtitle:SetText(latest and ((L("Ключ: +%d %s")):format(
        Number(latest.level) or 0, Text(latest.mapName) or L("Подземелье")))
        or L("Нет сохранённых измерений талантов"))
    self.uiBuild:SetText(BuildText(sample))
    self.amountHeader:SetText(self.metric == "healing" and L("Исцеление") or L("Урон"))
    self.rateHeader:SetText(self.metric == "healing" and "HPS" or "DPS")
    self.shareHeader:SetText(L("Доля"))
    self.sourceHeader:SetText(self.view == "talents" and L("Талант") or L("Источник"))
    local rows = self.view == "talents" and type(Lab.TalentRows) == "function"
        and Call(Lab.TalentRows, Lab, sample, self.metric) or Lab.UIRows(sample, self.metric)
    if type(rows) ~= "table" then rows = {} end
    local unknown,known=0,0
    if self.view=="talents" then
        local visible={}
        for _,row in ipairs(rows) do
            if Number(row.amount)~=nil then known=known+1
            else unknown=unknown+1 end
            if self.showUnknown or Number(row.amount)~=nil then visible[#visible+1]=row end
        end
        rows=visible
    end
    self.coverage:SetText(self.view=="talents" and (L("С цифрами: %d | Без привязанных данных: %d")):format(known,unknown) or "")
    local duration = sample and Number(sample.duration)
    local total = sample and Number(self.metric == "healing" and sample.overallHealing or sample.overallDamage)
    local rowCount = math.min(#rows, MAX_ROWS)
    while #self.rows < rowCount do
        self.rows[#self.rows + 1] = self.createRow(#self.rows + 1)
    end
    self.rowCanvas:SetSize(568, math.max(ROW_VIEWPORT_HEIGHT, rowCount * ROW_STEP))
    self.rowScroll:SetVerticalScroll(0)
    for i, row in ipairs(self.rows) do
        row.comparisonDetail=nil; row.meta:Hide()
        row:SetHeight(ROW_HEIGHT); row:ClearAllPoints(); row:SetPoint("TOPLEFT",0,-(i-1)*ROW_STEP)
        row.share:SetTextColor(UI.Unpack(C.green))
        local data = i <= rowCount and rows[i] or nil
        row:SetShown(data ~= nil)
        if data then
            local id, name, icon = SpellInfo(self.view == "talents" and (data.talentSpellID or data.spellID) or data.spellID)
            row.spellID, row.spellName = id, name or (id and (L("ID заклинания %d")):format(id) or L("Источник неизвестен"))
            row.kind = data.kind
            row.nameText:SetText(row.spellName)
            row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            local amount = Number(data.amount)
            row.amount:SetWidth(amount~=nil and 86 or 242)
            row.amount:SetTextColor(UI.Unpack(amount~=nil and C.text or C.muted))
            row.amount:SetText(amount~=nil and Compact(amount) or L("Нет привязанных данных"))
            row.rate:SetText(amount==nil and "" or (duration and duration > 0 and Compact(amount / duration) or "—"))
            row.share:SetText(amount==nil and "" or (total and total > 0 and (("%.1f%%"):format(amount / total * 100)) or "—"))
        else
            row.spellID, row.spellName, row.kind = nil, nil, nil
            row.icon:SetTexture(nil); row.nameText:SetText(""); row.amount:SetText(""); row.rate:SetText(""); row.share:SetText("")
        end
    end
    local state = sample and (sample.mixed and L("Смешанная сборка: смена талантов отмечена; данные не объединяются.")
        or sample.complete ~= true and L("Снимок неполный: неизвестное и нераспределённое не оценивается.") or "") or
        L("Нет измеримого снимка: отключённые или неизвестные данные не заменяются нулями.")
    local unit = self.metric == "healing" and "HPS" or "DPS"
    local measured = total and duration and duration > 0
        and (unit .. ": " .. Compact(total / duration) .. " | " .. Compact(total) .. " | " .. FormatDuration(duration)) or ""
    self.empty:SetText(measured ~= "" and (measured .. "\n" .. state) or state)
    local observed = Lab.ObservedComparison and Lab:ObservedComparison(runs, latest, self.metric)
    if observed then
        local delta = observed.percent and ("%+.1f%%"):format(observed.percent) or "—"
        self.compare:SetText((L("Замеры %s: выбранный %s (%s), другой %s (%s). Разница: %s.")):format(
            unit, Compact(observed.current), FormatDuration(observed.currentDuration),
            Compact(observed.previous), FormatDuration(observed.previousDuration), delta)
            .. "\n" .. (observed.uncertain
                and L("Есть неполные или смешанные данные. Это разница записанных отрезков, не эффект смены талантов.")
                or L("Условия и состав группы влияют на результат.")))
    else self.compare:SetText(self:CompareText(runs, self.metric)) end
end

function Lab:Show()
    if not CanUseUI() then return end
    self:CreateUI(); self.page = 0; self.sampleIndex = 1; self:Render(); self.uiFrame:Show()
end

-- Blizzard loads the talent window on demand. One event frame and one set of
-- hooks survive module reloads; no polling, native reparenting or secure edits.
function Lab:AttachTalentButton()
    if not self.launcherRunning or not CanUseUI() then return end
    local owner = PlayerSpellsFrame
    if not owner or not owner.TalentsFrame then return end
    if not self.talentButtonLauncher then
        local button = UI.Button(owner, "MythicBoost", 142, 23)
        self.talentButtonLauncher = button
        button:SetScript("OnClick", function()
            if not self.launcherRunning or not CanUseUI() then return end
            self.view = "sources"
            self:Show()
            -- A custom UI may raise the talent window to DIALOG as well.
            self.uiFrame:SetFrameStrata("DIALOG")
            self.uiFrame:SetFrameLevel(button:GetFrameLevel() + 10)
        end)
        button:SetScript("OnEnter", function()
            UI.Tooltip(button, L("Лаборатория талантов"))
        end)
        button:SetScript("OnLeave", HideTooltip)
        local function Refresh() self:AttachTalentButton() end
        owner:HookScript("OnShow", Refresh)
        owner:HookScript("OnSizeChanged", Refresh)
        owner:HookScript("OnHide", function() button:Hide(); HideTooltip() end)
        owner.TalentsFrame:HookScript("OnShow", Refresh)
        owner.TalentsFrame:HookScript("OnHide", function() button:Hide(); HideTooltip() end)
    end
    local button = self.talentButtonLauncher
    button:ClearAllPoints()
    local control = owner.MaximizeMinimizeButton or owner.CloseButton
    if control then
        button:SetPoint("RIGHT", control, "LEFT", -8, 0)
    else
        button:SetPoint("TOPRIGHT", owner, "TOPRIGHT", -74, -3)
    end
    local level = owner:GetFrameLevel()
    for _, key in ipairs({"TitleContainer", "NineSlice", "TalentsFrame", "MaximizeMinimizeButton", "CloseButton"}) do
        local part = owner[key]
        if part and part.GetFrameLevel then level = math.max(level, part:GetFrameLevel()) end
    end
    button:SetFrameStrata(owner:GetFrameStrata())
    button:SetFrameLevel(level + 10)
    button:SetShown(owner:IsShown() and owner.TalentsFrame:IsShown())
end

function Lab:Enable()
    self.launcherRunning = true
    if not self.launcherEvents then
        self.launcherEvents = CreateFrame("Frame")
        self.launcherEvents:SetScript("OnEvent", function(_, event, addon)
            if event ~= "ADDON_LOADED" or addon == "Blizzard_PlayerSpells" then
                self:AttachTalentButton()
            end
        end)
    end
    self.launcherEvents:RegisterEvent("ADDON_LOADED")
    self.launcherEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
    self:AttachTalentButton()
end

function Lab:Disable()
    self.launcherRunning = false
    if self.launcherEvents then self.launcherEvents:UnregisterAllEvents() end
    if self.talentButtonLauncher then self.talentButtonLauncher:Hide() end
    self:Hide()
end

function Lab:Hide()
    if self.uiFrame then self.uiFrame:Hide() end
end

function Lab:Toggle()
    if self.uiFrame and self.uiFrame:IsShown() then self:Hide() else self:Show() end
end

JP.TalentLabUI = Lab
