local _, JP = ...
local Welcome = { rows = {} }
local UI = JP.UI
local C = UI.colors

local DEFAULT_WIDTH, DEFAULT_HEIGHT = 1320, 840
-- Пять вкладок требуют 12 + 5*146 = 742 пикселя, остальное отдаём под
-- содержимое. Прежние 1160x700 держали окно больше, чем нужно любой из
-- вкладок, и половина высоты уходила в пустоту.
local MIN_WIDTH, MIN_HEIGHT = 1000, 560
local HEADER_HEIGHT = 64

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
    local mark = UI.Text(badge, "GameFontNormalLarge", "MB", { 1, 1, 1, 1 })
    mark:SetPoint("CENTER", 0, 0)

    -- Вместо повторения названия аддона показываем полезное состояние пати.
    -- Каждый слот — настоящий Frame/Texture, поэтому пустые места больше не
    -- превращаются в квадраты из-за отсутствующего символа в шрифте клиента.
    local partyLabel = UI.Text(header, "GameFontNormalSmall", "ТВОЯ ГРУППА", C.faint)
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

    local maximize = UI.Button(header, "На весь экран", 128, 24)
    maximize:SetPoint("RIGHT", close, "LEFT", -8, 0)
    self.maximizeButton = maximize

    -- Обратный переход: создать объявление и управлять им по-прежнему можно
    -- только в штатном окне, поэтому дорога туда всегда под рукой.
    local blizzard = UI.Button(header, "Окно Blizzard", 128, 24)
    blizzard:SetPoint("RIGHT", maximize, "LEFT", -8, 0)
    blizzard:SetScript("OnClick", function()
        if JP.FrameSwitch then JP.FrameSwitch.OpenBlizzard() end
    end)
    blizzard:HookScript("OnEnter", function(self)
        UI.Tooltip(self, "Штатное окно",
            "Открыть «Подземелья и рейды» — там создаётся и меняется само объявление.")
    end)
    blizzard:HookScript("OnLeave", GameTooltip_Hide)

    self.status = UI.Text(header, "GameFontHighlightSmall", "", C.muted)
    self.status:SetPoint("RIGHT", blizzard, "LEFT", -14, 0)
    self.status:SetJustifyH("RIGHT")

    return header
end

-- Пустая выдача без объяснения — худшее, что может показать поиск: «0 из 100»
-- не даёт понять, ослаблять фильтр по лидеру или по подземельям. Поэтому
-- называем три главные причины отсева с числами.
local function EmptyStateText(rejected, scanned)
    local fallback = "Среди текущих результатов подходящих групп нет.\nОслабь фильтры или нажми «Обновить»."
    if not rejected or not scanned or scanned == 0 then return fallback end
    local ordered = {}
    for reason, count in pairs(rejected) do ordered[#ordered + 1] = { reason = reason, count = count } end
    if #ordered == 0 then return fallback end
    table.sort(ordered, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.reason < b.reason
    end)
    local text = { ("Ни одна из %d групп не прошла фильтры. Что отсеяло:"):format(scanned) }
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
        { key = "groups", label = "ПОДБОР ГРУПП" },
        { key = "applicants", label = "ПАТИ / КАНДИДАТЫ" },
        { key = "guild", label = "РЕЙТИНГ ГИЛЬДИИ" },
        { key = "upgrades", label = "УЛУЧШЕНИЯ" },
        { key = "settings", label = "НАСТРОЙКИ" },
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
        groups = groups, applicants = applicants, guild = guild,
        upgrades = upgrades, settings = settings,
    }
    self.currentPage = "groups"
    self.tabs.groups:SetActive(true)

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
    resize:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then frame:StartSizing("BOTTOMRIGHT") end end)
    resize:SetScript("OnMouseUp", function() frame:StopMovingOrSizing(); SaveWindow(frame) end)
    self.resizeGrip = resize

    local function SetMaximized(enabled, initial)
        local window = MythicBoostDB.window
        if enabled then
            if not initial and not frame.maximized then SaveWindow(frame) end
            frame.maximized, window.maximized = true, true
            frame:SetResizable(false)
            resize:Hide()
            self.maximizeButton:SetText("Свернуть окно")
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 14, -14)
            frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -14, 14)
        else
            frame.maximized, window.maximized = false, false
            frame:SetSize(window.width or DEFAULT_WIDTH, window.height or DEFAULT_HEIGHT)
            RestorePosition(frame)
            frame:SetResizable(true)
            resize:Show()
            self.maximizeButton:SetText("На весь экран")
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
            SaveWindow(frame)
        end)
    end)
    frame:SetScript("OnShow", function() self:Refresh() end)
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
    local matches, message, scanned, rejected
    if batch then
        matches, scanned, rejected = batch.matches or {}, batch.scanned or 0, batch.rejected or {}
    else
        matches, message, scanned, rejected = JP.AutoMatch:Scan(
            self:GetGroupFilters(), {
                bestByMap = self.bestByMap,
                bestByActivity = self.bestByActivity,
            })
    end
    -- Сортируем по силе всей текущей группы, а не только по лидеру.
    JP.GroupSearchUI:EnrichPartyRatings(matches)
    self.matches = matches

    local visible = self.visibleRows or 5
    local maximum = math.max(0, #matches - visible)
    self.scrollBar:SetMinMaxValues(0, maximum)
    self.offset = math.min(self.offset or 0, maximum)
    self.scrollBar:SetValue(self.offset)
    self.scrollBar:SetShown(maximum > 0)
    self:RenderRows()

    self.empty:SetShown(#matches == 0)
    if #matches == 0 then
        self.empty:SetText(message or EmptyStateText(rejected, scanned))
    end

    -- Счётчик показывает и отбор, и объём выборки: сразу видно, фильтры
    -- слишком строгие или Blizzard прислал мало групп.
    local scope = JP.GroupSearchUI:GetScopeText(self)
    if scanned and scanned > 0 then
        self.resultsCount:SetText(("%d из %d  •  %s"):format(#matches, scanned, scope))
    else
        self.resultsCount:SetText(scope or "")
    end
    self.status:SetText(#matches > 0 and ("найдено групп: " .. #matches) or "")
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
