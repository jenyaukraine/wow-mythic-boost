local _, JP = ...
local L = JP.L
local Welcome = { rows = {} }
local UI = JP.UI
local C = UI.colors
local ICON = "Interface\\AddOns\\MythicBoost\\Media\\MythicBoostIcon.tga"

local DEFAULT_WIDTH, DEFAULT_HEIGHT = 1320, 840
-- Шесть вкладок требуют 12 + 6*146 = 888 пикселей, остальное отдаём под
-- содержимое. Прежние 1160x700 держали окно больше, чем нужно любой из
-- вкладок, и половина высоты уходила в пустоту.
-- The settings page needs enough vertical room for its last toggle and help
-- text. At 560 px those controls were clipped even though the resize grip
-- still allowed that size, so 650 is the truthful minimum for every tab.
local MIN_WIDTH, MIN_HEIGHT = 1000, 650
local HEADER_HEIGHT = 64
local WINDOW_ALPHA = .94
local ONBOARDING_VERSION = 1

local function SaveWindow(frame)
    if frame.maximized then return end
    local window = MythicBoostDB.window
    window.width = math.floor(frame:GetWidth() + .5)
    window.height = math.floor(frame:GetHeight() + .5)
    local point, _, relativePoint, x, y = frame:GetPoint()
    window.point, window.relativePoint = point, relativePoint
    window.x, window.y = math.floor(x + .5), math.floor(y + .5)
end

local function RestorePosition(frame)
    local window = MythicBoostDB.window
    frame:ClearAllPoints()
    if window.point and window.x and window.y then
        frame:SetPoint(window.point, UIParent, window.relativePoint or window.point, window.x, window.y)
    else
        frame:SetPoint("CENTER")
    end
end

local function BuildHeader(self, frame)
    local header = UI.Panel(frame, { .028, .036, .048, .98 }, { .028, .036, .048, 0 })
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_HEIGHT)

    local stripe = header:CreateTexture(nil, "OVERLAY")
    stripe:SetColorTexture(UI.Unpack(C.accent))
    stripe:SetPoint("BOTTOMLEFT")
    stripe:SetPoint("BOTTOMRIGHT")
    stripe:SetHeight(2)

    local badge = UI.Panel(header, { .10, .42, .58, 1 }, { .22, .70, .92, 1 })
    badge:SetSize(36, 36)
    badge:SetPoint("LEFT", 18, 1)
    local mark = badge:CreateTexture(nil, "ARTWORK")
    mark:SetPoint("TOPLEFT", 2, -2)
    mark:SetPoint("BOTTOMRIGHT", -2, 2)
    mark:SetTexture(ICON)

    -- Вместо повторения названия аддона показываем полезное состояние пати.
    -- Каждый слот — настоящий Frame/Texture, поэтому пустые места больше не
    -- превращаются в квадраты из-за отсутствующего символа в шрифте клиента.
    local partyLabel = UI.Text(header, "GameFontNormalSmall", L("ТВОЯ ГРУППА"), C.faint)
    partyLabel:SetPoint("TOPLEFT", badge, "TOPRIGHT", 14, -1)
    self.partySlots = {}
    for index = 1, 5 do
        local slot = UI.Panel(header, { .035, .047, .061, 1 }, { .16, .22, .29, 1 })
        slot:SetSize(20, 20)
        slot:SetPoint("BOTTOMLEFT", badge, "BOTTOMRIGHT", 14 + (index - 1) * 26, 0)
        slot.icon = slot:CreateTexture(nil, "ARTWORK")
        slot.icon:SetPoint("TOPLEFT", 2, -2)
        slot.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        slot.unknown = UI.Text(slot, "GameFontHighlightSmall", "?", C.muted)
        slot.unknown:SetPoint("CENTER", 0, 0)
        slot.unknown:Hide()
        self.partySlots[index] = slot
    end

    local close = UI.CloseButton(header)
    close:SetPoint("TOPRIGHT", -10, -10)
    close:SetScript("OnClick", function() frame:Hide() end)

    local maximize = UI.Button(header, L("На весь экран"), 128, 24)
    maximize:SetPoint("RIGHT", close, "LEFT", -8, 0)
    self.maximizeButton = maximize

    -- Обратный переход: создать объявление и управлять им по-прежнему можно
    -- только в штатном окне, поэтому дорога туда всегда под рукой.
    local blizzard = UI.Button(header, L("Окно Blizzard"), 128, 24)
    blizzard:SetPoint("RIGHT", maximize, "LEFT", -8, 0)
    blizzard:SetScript("OnClick", function()
        if JP.FrameSwitch then JP.FrameSwitch.OpenBlizzard() end
    end)
    blizzard:HookScript("OnEnter", function(self)
        UI.Tooltip(self, L("Штатное окно"),
            L("Открыть «Подземелья и рейды» — там создаётся и меняется само объявление."))
    end)
    blizzard:HookScript("OnLeave", GameTooltip_Hide)

    self.status = UI.Text(header, "GameFontHighlightSmall", "", C.muted)
    self.status:SetPoint("RIGHT", blizzard, "LEFT", -14, 0)
    self.status:SetJustifyH("RIGHT")

    return header
end

local function BuildGuide(self, owner)
    local shade = CreateFrame("Frame", nil, owner, "BackdropTemplate")
    shade:SetAllPoints()
    shade:SetFrameLevel(owner:GetFrameLevel() + 50)
    shade:EnableMouse(true)
    UI.Backdrop(shade, { .01, .015, .022, .86 }, { 0, 0, 0, 0 })

    local card = UI.Panel(shade, { .035, .052, .071, 1 }, { .20, .52, .68, 1 })
    card:SetSize(760, 404)
    card:SetPoint("CENTER", 0, 0)

    local close = UI.CloseButton(card)
    close:SetPoint("TOPRIGHT", -10, -10)
    close:SetScript("OnClick", function() shade:Hide() end)

    local title = UI.Text(card, "GameFontNormalHuge", L("Что ты хочешь сделать?"), C.text)
    title:SetPoint("TOPLEFT", 28, -24)
    local subtitle = UI.Text(card, "GameFontHighlightSmall",
        L("MythicBoost ведёт по трём шагам: найти группу, собрать пати и сохранить результат."), C.muted)
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -9)

    local function Choice(index, heading, description, action, onClick)
        local panel = UI.Panel(card, C.panel, C.line)
        panel:SetPoint("TOPLEFT", 28, -94 - (index - 1) * 86)
        panel:SetPoint("TOPRIGHT", -28, -94 - (index - 1) * 86)
        panel:SetHeight(72)
        local number = UI.Text(panel, "GameFontNormalLarge", tostring(index), C.accent)
        number:SetPoint("LEFT", 16, 0)
        local label = UI.Text(panel, "GameFontNormal", heading, C.text)
        label:SetPoint("TOPLEFT", 48, -13)
        local detail = UI.Text(panel, "GameFontHighlightSmall", description, C.muted)
        detail:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6)
        detail:SetPoint("RIGHT", -190, 0)
        detail:SetJustifyH("LEFT")
        local button = UI.Button(panel, action, 160, 32)
        button:SetPoint("RIGHT", -14, 0)
        button:SetScript("OnClick", function()
            MythicBoostDB.onboardingVersion = ONBOARDING_VERSION
            shade:Hide()
            onClick()
        end)
    end

    Choice(1, L("Найти подходящую группу"),
        L("Выбери подземелья и нажми «Найти группы». Результаты можно отсортировать по силе и шансу повысить рейтинг."),
        L("К поиску"), function() self:SwitchPage("groups") end)
    Choice(2, L("Собрать группу на свой ключ"),
        L("Сначала создай объявление в окне Blizzard. После этого кандидаты появятся здесь с опытом по каждому подземелью."),
        L("Создать объявление"), function()
            if JP.FrameSwitch then JP.FrameSwitch.OpenBlizzard() end
        end)
    Choice(3, L("Проверить пати или кандидатов"),
        L("Сравни рейтинг, лучшие ключи и слабые места. Пригласить или отклонить игрока можно прямо из списка."),
        L("К кандидатам"), function() self:SwitchPage("applicants") end)

    local hint = UI.Text(card, "GameFontHighlightSmall",
        L("Подсказка: окно всегда открывается командой /mb или через кнопку аддона у миникарты."), C.faint)
    hint:SetPoint("BOTTOMLEFT", 28, 18)
    shade:Hide()
    self.guide = shade
end

function Welcome:ShowGuide()
    if self.guide then self.guide:Show() end
end

-- Пустая выдача без объяснения — худшее, что может показать поиск: «0 из 100»
-- не даёт понять, ослаблять фильтр по лидеру или по подземельям. Поэтому
-- называем три главные причины отсева с числами.
local function EmptyStateText(rejected, scanned)
    local fallback = L("Среди текущих результатов подходящих групп нет.\nОслабь фильтры или нажми «Обновить».")
    if not rejected or not scanned or scanned == 0 then return fallback end
    local ordered = {}
    for reason, count in pairs(rejected) do ordered[#ordered + 1] = { reason = reason, count = count } end
    if #ordered == 0 then return fallback end
    table.sort(ordered, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.reason < b.reason
    end)
    local text = { (L("Ни одна из %d групп не прошла фильтры. Что отсеяло:")):format(scanned) }
    for index = 1, math.min(3, #ordered) do
        text[#text + 1] = ("|cffa9b4c2%s|r   |cffffb93d%d|r"):format(ordered[index].reason, ordered[index].count)
    end
    return table.concat(text, "\n")
end


function Welcome:Create()
    if self.frame then return end

    local frame = CreateFrame("Frame", "MythicBoostWelcomeFrame", UIParent, "BackdropTemplate")
    local saved = MythicBoostDB.window
    frame:SetSize(saved.width or DEFAULT_WIDTH, saved.height or DEFAULT_HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetAlpha(WINDOW_ALPHA)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, 2400, 1400)
    frame:RegisterForDrag("LeftButton")
    UI.Backdrop(frame, C.window, { .24, .32, .42, 1 })
    RestorePosition(frame)

    frame:SetScript("OnDragStart", function(self) if not self.maximized then self:StartMoving() end end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SaveWindow(self) end)

    BuildHeader(self, frame)

    -- Вкладки. Страницы лежат одна поверх другой в одной области, поэтому
    -- переключение не трогает раскладку окна.
    local tabTop = -(HEADER_HEIGHT + 8)
    self.tabs = {}
    local order = {
        { key = "groups", label = L("НАЙТИ ГРУППУ") },
        { key = "applicants", label = L("СОБРАТЬ ПАТИ") },
        { key = "history", label = L("НАПАРНИКИ") },
        { key = "guild", label = L("РЕЙТИНГ ГИЛЬДИИ") },
        { key = "upgrades", label = L("УЛУЧШЕНИЯ") },
        { key = "settings", label = L("НАСТРОЙКИ") },
    }
    for index, item in ipairs(order) do
        local tab = UI.Tab(frame, item.label, 140)
        tab:SetPoint("TOPLEFT", 12 + (index - 1) * 146, tabTop)
        tab:SetScript("OnClick", function() self:SwitchPage(item.key) end)
        self.tabs[item.key] = tab
    end

    local pageTop = tabTop - 34
    local groups = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    groups:SetPoint("TOPLEFT", 12, pageTop)
    groups:SetPoint("BOTTOMRIGHT", -12, 12)
    JP.GroupSearchUI:Build(self, groups)

    local guild = UI.Panel(frame, C.panel, C.line)
    guild:SetPoint("TOPLEFT", 12, pageTop)
    guild:SetPoint("BOTTOMRIGHT", -12, 12)
    guild:Hide()
    JP.GuildBoard:Build(self, guild)

    local applicants = UI.Panel(frame, C.panel, C.line)
    applicants:SetPoint("TOPLEFT", 12, pageTop)
    applicants:SetPoint("BOTTOMRIGHT", -12, 12)
    applicants:Hide()
    JP.ApplicantBoard:Build(self, applicants)

    local history = UI.Panel(frame, C.panel, C.line)
    history:SetPoint("TOPLEFT", 12, pageTop)
    history:SetPoint("BOTTOMRIGHT", -12, 12)
    history:Hide()
    JP.RunHistory:Build(self, history)

    local upgrades = UI.Panel(frame, C.panel, C.line)
    upgrades:SetPoint("TOPLEFT", 12, pageTop)
    upgrades:SetPoint("BOTTOMRIGHT", -12, 12)
    upgrades:Hide()
    JP.UpgradeCalculator:Build(self, upgrades)

    local settings = UI.Panel(frame, C.panel, C.line)
    settings:SetPoint("TOPLEFT", 12, pageTop)
    settings:SetPoint("BOTTOMRIGHT", -12, 12)
    settings:Hide()
    JP.SettingsHub:Build(self, settings)

    self.pages = {
        groups = groups, applicants = applicants, history = history, guild = guild,
        upgrades = upgrades, settings = settings,
    }
    self.currentPage = "groups"
    self.tabs.groups:SetActive(true)
    BuildGuide(self, frame)

    local resize = CreateFrame("Button", nil, frame)
    resize:SetSize(20, 20)
    resize:SetPoint("BOTTOMRIGHT", -3, 3)
    resize:SetFrameLevel(frame:GetFrameLevel() + 20)
    local grip = resize:CreateTexture(nil, "OVERLAY")
    grip:SetAllPoints()
    grip:SetTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up")
    grip:SetVertexColor(.34, .42, .52, .9)
    resize:SetScript("OnEnter", function() grip:SetVertexColor(UI.Unpack(C.accent)) end)
    resize:SetScript("OnLeave", function() grip:SetVertexColor(.34, .42, .52, .9) end)
    local function StopResize()
        if not resize.sizing then return end
        resize.sizing = nil
        resize:SetScript("OnUpdate", nil)
        SaveWindow(frame)
    end
    resize:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or frame.maximized then return end
        local cursorX, cursorY = GetCursorPosition()
        local scale = frame:GetEffectiveScale()
        self.sizing = true
        self.startCursorX, self.startCursorY = cursorX / scale, cursorY / scale
        self.startWidth, self.startHeight = frame:GetWidth(), frame:GetHeight()
        self:SetScript("OnUpdate", function(owner)
            if not IsMouseButtonDown("LeftButton") then StopResize(); return end
            local currentX, currentY = GetCursorPosition()
            currentX, currentY = currentX / scale, currentY / scale
            local width = math.max(MIN_WIDTH, math.min(2400,
                owner.startWidth + currentX - owner.startCursorX))
            local height = math.max(MIN_HEIGHT, math.min(1400,
                owner.startHeight + owner.startCursorY - currentY))
            frame:SetSize(width, height)
        end)
    end)
    resize:SetScript("OnMouseUp", StopResize)
    self.resizeGrip = resize

    local function SetMaximized(enabled, initial)
        local window = MythicBoostDB.window
        if enabled then
            if not initial and not frame.maximized then SaveWindow(frame) end
            frame.maximized, window.maximized = true, true
            frame:SetResizable(false)
            resize:Hide()
            self.maximizeButton:SetText(L("Свернуть окно"))
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 14, -14)
            frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -14, 14)
        else
            frame.maximized, window.maximized = false, false
            frame:SetSize(window.width or DEFAULT_WIDTH, window.height or DEFAULT_HEIGHT)
            RestorePosition(frame)
            frame:SetResizable(true)
            resize:Show()
            self.maximizeButton:SetText(L("На весь экран"))
        end
    end
    self.maximizeButton:SetScript("OnClick", function() SetMaximized(not frame.maximized, false) end)

    -- OnSizeChanged приходит на каждом кадре перетаскивания угла. Полная
    -- пересборка раскладки и списка групп на каждый кадр давала рывки,
    -- поэтому склеиваем вызовы в один.
    local layoutQueued = false
    frame:SetScript("OnSizeChanged", function()
        if layoutQueued then return end
        layoutQueued = true
        C_Timer.After(.05, function()
            layoutQueued = false
            JP.GroupSearchUI:Layout(self)
            JP.GuildBoard:Layout()
            JP.ApplicantBoard:Layout()
            JP.RunHistory:Layout()
            SaveWindow(frame)
        end)
    end)
    frame:SetScript("OnShow", function()
        self:Refresh()
        if (tonumber(MythicBoostDB.onboardingVersion) or 0) < ONBOARDING_VERSION then
            self:ShowGuide()
        end
    end)
    frame:SetScript("OnHide", function()
        if JP.GroupSearchUI.groupTooltip then JP.GroupSearchUI.groupTooltip:Hide() end
    end)

    frame:Hide()
    self.frame = frame
    if saved.maximized then SetMaximized(true, true) end
    JP.GroupSearchUI:Layout(self)
    tinsert(UISpecialFrames, "MythicBoostWelcomeFrame")
end

function Welcome:RenderRows()
    JP.GroupSearchUI:RenderRows(self)
end

function Welcome:SwitchPage(key)
    if not self.pages or not self.pages[key] then return end
    self.currentPage = key
    for name, page in pairs(self.pages) do page:SetShown(name == key) end
    for name, tab in pairs(self.tabs) do tab:SetActive(name == key) end
    self:Refresh()
end

function Welcome:Refresh()
    if not self.frame or not self.rows then return end
    if self.currentPage == "guild" then
        JP.GuildBoard:Refresh()
        self.status:SetText("")
        return
    end
    if self.currentPage == "applicants" then
        JP.ApplicantBoard:Refresh()
        self.status:SetText("")
        return
    end
    if self.currentPage == "history" then
        JP.RunHistory:Refresh()
        self.status:SetText("")
        return
    end
    if self.currentPage == "upgrades" then
        JP.UpgradeCalculator:Refresh()
        self.status:SetText("")
        return
    end
    if self.currentPage == "settings" then
        JP.SettingsHub:Refresh()
        self.status:SetText("")
        return
    end

    JP.GroupSearchUI:Layout(self)
    JP.GroupSearchUI:RefreshDungeonCards(self)
    JP.GroupSearchUI:RefreshOwnComposition(self)

    local batch = JP.GroupSearchUI.completedBatch
    JP.GroupSearchUI.completedBatch = nil
    local matches, excluded, message, scanned, rejected
    if batch then
        matches, excluded = batch.matches or {}, batch.excluded or {}
        scanned, rejected = batch.scanned or 0, batch.rejected or {}
    else
        matches, message, scanned, rejected, excluded = JP.AutoMatch:Scan(
            self:GetGroupFilters(), {
                bestByMap = self.bestByMap,
                bestByActivity = self.bestByActivity,
            })
    end
    -- Сортируем по силе всей текущей группы, а не только по лидеру.
    excluded = excluded or {}
    local experienceRejected = JP.GroupSearchUI:EnrichPartyRatings(matches, self.groupFilters, excluded) or 0
    if experienceRejected > 0 then
        rejected = rejected or {}
        local reason = L("не все участники проходили этот уровень")
        rejected[reason] = (rejected[reason] or 0) + experienceRejected
    end
    self.eligibleMatches = matches
    self.excludedMatches = excluded
    self.matches = JP.GroupSearchUI:ComposeResults(matches, excluded)

    local visible = self.visibleRows or 5
    local maximum = math.max(0, #self.matches - visible)
    self.scrollBar:SetMinMaxValues(0, maximum)
    self.offset = math.min(self.offset or 0, maximum)
    self.scrollBar:SetValue(self.offset)
    self.scrollBar:SetShown(maximum > 0)
    self:RenderRows()

    self.empty:SetShown(#self.matches == 0)
    if #self.matches == 0 then
        local rejectedHidden = #excluded > 0 and MythicBoostDB.search
            and MythicBoostDB.search.showRejectedResults == false
        self.empty:SetText(rejectedHidden
            and (L("Подходящих групп нет. Ещё %d групп скрыты настройкой нижней серой секции.")):format(#excluded)
            or message or EmptyStateText(rejected, scanned))
    end

    -- Счётчик показывает и отбор, и объём выборки: сразу видно, фильтры
    -- слишком строгие или Blizzard прислал мало групп.
    local scope = JP.GroupSearchUI:GetScopeText(self)
    if scanned and scanned > 0 then
        self.resultsCount:SetText((L("%d подходят  -  %d ниже  -  %d всего"))
            :format(#matches, #excluded, scanned))
    else
        self.resultsCount:SetText(scope or "")
    end
    self.status:SetText(scanned and scanned > 0 and
        ((L("подходит групп: %d, ниже фильтров: %d")):format(#matches, #excluded)) or "")
end

function Welcome:Toggle()
    if not self.frame then self:Create() end
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        -- Если своё объявление уже создано, человеку сейчас важнее состав
        -- пати и заявки, а не каталог чужих групп.
        local listed = C_LFGList.GetActiveEntryInfo and C_LFGList.GetActiveEntryInfo()
        if listed and self.pages and self.pages.applicants then self:SwitchPage("applicants") end
        self.frame:Show()
    end
end

function Welcome:Enable() end
function Welcome:Disable() if self.frame then self.frame:Hide() end end
function Welcome:Destroy() if self.frame then self.frame:Hide() end end

JP:RegisterModule("Welcome", Welcome)
