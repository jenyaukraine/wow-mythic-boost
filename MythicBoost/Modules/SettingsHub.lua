local _, JP = ...
local L = JP.L
local SettingsHub = {}
local UI, C = JP.UI, JP.UI.colors

-- Дефолты теперь выставляет InitializeDatabase при загрузке. Здесь они
-- остаются страховкой и обязаны с ним совпадать: раньше этот список
-- был единственным источником, а применялся только при открытии окна
-- настроек — до этого Convenience читал базу напрямую и видел nil.
local DEFAULTS = {
    autoQuests = false,
    summon = false,
    resurrection = false,
    resNoCombat = true,
    sellJunk = false,
    repair = false,
    guildRepair = true,
    merchantSummary = true,
    whisperInvite = false,
    inviteKeyword = "inv",
    autoKeystone = true,
    movableKeystoneFrame = false,
    hideBags = true,
}

function SettingsHub:GetSettings()
    return JP.Settings("convenience", DEFAULTS) or {}
end

local function Heading(parent, text, x, y, width)
    local label = UI.Text(parent, "GameFontNormalLarge", text, C.accent)
    label:SetPoint("TOPLEFT", x, y)
    local line = UI.Line(parent, C.lineSoft)
    line:SetPoint("TOPLEFT", x, y - 25)
    line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -28, y - 25)
    line:SetHeight(1)
end

local function ColumnAnchor(frame, parent, right, y, inset)
    inset = inset or 28
    frame:SetPoint(right and "TOPRIGHT" or "TOPLEFT", parent,
        right and "TOPRIGHT" or "TOPLEFT", right and -inset or inset, y)
end

local function ColumnHeading(parent, text, right, y)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(300, 28)
    ColumnAnchor(holder, parent, right, y)
    local label = UI.Text(holder, "GameFontNormalLarge", text, C.accent)
    label:SetPoint("TOPLEFT", 0, 0)
    local line = UI.Line(holder, C.lineSoft)
    line:SetPoint("BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", 0, 0)
    line:SetHeight(1)
    return holder
end

local function TextBox(parent, width, height, placeholder)
    local holder = UI.Panel(parent, C.field, C.line)
    holder:SetSize(width, height or 28)
    local field = CreateFrame("EditBox", nil, holder)
    field:SetPoint("TOPLEFT", 8, -2)
    field:SetPoint("BOTTOMRIGHT", -8, 2)
    field:SetFontObject("GameFontHighlightSmall")
    field:SetAutoFocus(false)
    field:SetTextInsets(2, 2, 0, 0)
    field:SetJustifyH("LEFT")
    field:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    field:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    if placeholder then
        field:SetScript("OnEditFocusGained", function(self)
            if self.placeholderShown then
                self:SetText(""); self.placeholderShown = nil
                self:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
            end
        end)
        field:SetScript("OnEditFocusLost", function(self)
            if self:GetText() == "" then
                self:SetText(placeholder); self:SetTextColor(C.faint[1], C.faint[2], C.faint[3], 1)
                self.placeholderShown = true
            end
        end)
        field:SetText(placeholder)
        field:SetTextColor(C.faint[1], C.faint[2], C.faint[3], 1)
        field.placeholderShown = true
    end
    return field, holder
end

function SettingsHub:AddStoredCheck(parent, settings, key, label, x, y, callback, checkKey)
    local check = UI.CheckBox(parent, label, settings[key], function(value)
        settings[key] = value and true or false
        if callback then callback(value) end
        SettingsHub:RefreshDependencies()
    end)
    check:SetPoint("TOPLEFT", x, y)
    check:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -28, y)
    self.checks[checkKey or key] = check
    return check
end

function SettingsHub:AddCheck(parent, key, label, x, y, callback)
    return self:AddStoredCheck(parent, self:GetSettings(), key, label, x, y, callback)
end


function SettingsHub:AddColumnCheck(parent, settings, key, label, right, y, callback, checkKey, indent)
    local check = UI.CheckBox(parent, label, settings[key], function(value)
        settings[key] = value and true or false
        if callback then callback(value) end
        SettingsHub:RefreshDependencies()
    end)
    check:SetWidth(300 - (indent or 0))
    -- Indentation moves the checkbox inward while preserving the outer edge
    -- of either column. A mirrored column therefore keeps its right inset.
    ColumnAnchor(check, parent, right, y, right and 28 or 28 + (indent or 0))
    self.checks[checkKey or key] = check
    self.frameCheckKeys[checkKey or key] = key
    return check
end

function SettingsHub:AddStepper(parent, settings, key, label, right, y,
    minimum, maximum, step, formatter, callback, controlKey)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(300, 28)
    ColumnAnchor(row, parent, right, y)

    local caption = UI.Text(row, "GameFontHighlightSmall", label, C.text)
    caption:SetPoint("LEFT", 0, 0)
    caption:SetPoint("RIGHT", row, "RIGHT", -122, 0)
    caption:SetJustifyH("LEFT")
    caption:SetWordWrap(false)

    -- WoW's bundled font does not contain the typographic U+2212 minus on
    -- every locale, where it renders as an empty square. ASCII is universal.
    local minus = UI.Button(row, "-", 26, 24)
    minus:SetPoint("RIGHT", row, "RIGHT", -92, 0)
    local valueFrame = UI.Panel(row, C.field, C.line)
    valueFrame:SetSize(58, 24)
    valueFrame:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    local valueText = UI.Text(valueFrame, "GameFontHighlightSmall", "", C.text)
    valueText:SetAllPoints()
    valueText:SetJustifyH("CENTER")
    valueText:SetJustifyV("MIDDLE")
    local plus = UI.Button(row, "+", 26, 24)
    plus:SetPoint("LEFT", valueFrame, "RIGHT", 4, 0)

    local function Normalize(value)
        value = tonumber(value) or minimum
        local steps = math.floor(((value - minimum) / step) + .5)
        return math.max(minimum, math.min(maximum, minimum + steps * step))
    end
    function row:SetValue(value, silent)
        value = Normalize(value)
        self.value = value
        valueText:SetText(formatter and formatter(value) or tostring(value))
        if not silent then
            settings[key] = value
            if callback then callback(value) end
        end
    end
    function row:SetControlEnabled(enabled)
        if enabled then minus:Enable(); plus:Enable() else minus:Disable(); plus:Disable() end
        row:SetAlpha(enabled and 1 or .42)
    end
    minus:SetScript("OnClick", function() row:SetValue((row.value or minimum) - step) end)
    plus:SetScript("OnClick", function() row:SetValue((row.value or minimum) + step) end)
    row:SetValue(settings[key], true)
    self.steppers[controlKey or key] = { control = row, settings = settings, key = key }
    return row
end

function SettingsHub:RefreshDependencies()
    if not self.checks then return end
    local function Enable(key, enabled)
        local check = self.checks[key]
        if check then
            if enabled then check:Enable() else check:Disable() end
            return
        end
        local binding = self.steppers and self.steppers[key]
        if binding and binding.control.SetControlEnabled then binding.control:SetControlEnabled(enabled) end
    end
    local convenience = self:GetSettings()
    Enable("resNoCombat", convenience.resurrection == true)
    Enable("guildRepair", convenience.repair == true)
    Enable("merchantSummary", convenience.repair == true or convenience.sellJunk == true)
    Enable("hideBags", MythicBoostDB.minimalUI == true)
    Enable("minimalUIMinimap", MythicBoostDB.minimalUI == true)
    Enable("minimalUIStanceBar", MythicBoostDB.minimalUI == true)
    Enable("unitFramesHideBlizzard", MythicBoostDB.unitFrames and MythicBoostDB.unitFrames.enabled == true)
    local resources = MythicBoostDB.unitFrames and MythicBoostDB.unitFrames.showResourcePips ~= false
    Enable("frameEmptyResources", resources)
    Enable("frameResourceHeight", resources)
    Enable("frameResourceGap", resources)
    Enable("frameResourceOpacity", resources)
    local lootEnabled = MythicBoostDB.lootUI and MythicBoostDB.lootUI.enabled == true
    Enable("lootAtCursor", lootEnabled)
    Enable("lootRolls", lootEnabled)
    Enable("lootHistory", lootEnabled)
    if self.lootTestButton then
        self.lootTestButton:SetEnabled(lootEnabled
            and MythicBoostDB.lootUI and MythicBoostDB.lootUI.showRolls ~= false)
    end
    Enable("allowRejectedApplications", MythicBoostDB.search and MythicBoostDB.search.showRejectedResults ~= false)
    Enable("nameplateMarkers", MythicBoostDB.playerAnalysis and MythicBoostDB.playerAnalysis.enabled ~= false)
    Enable("errorKeep", MythicBoostDB.errorGuard and MythicBoostDB.errorGuard.enabled == true)
end

function SettingsHub:SetInterfaceUnlocked(value)
    local unlocked = value == true
    MythicBoostDB.interfaceUnlocked = unlocked
    JP.Settings("unitFrames").unlocked = unlocked
    JP.Settings("castBar").unlocked = unlocked
    JP.Settings("positiveAuraTracker").unlocked = unlocked
    self:GetSettings().movableKeystoneFrame = unlocked
    if JP.UnitFrames then JP.UnitFrames:SetUnlocked(unlocked) end
    if JP.CastBar then JP.CastBar:SetUnlocked(unlocked) end
    if JP.LootUI then JP.LootUI:SetUnlocked(unlocked) end
    if JP.PositiveAuraTracker then JP.PositiveAuraTracker:SetUnlocked(unlocked) end
    if JP.Convenience then JP.Convenience:SetupKeystoneFrame() end
end

function SettingsHub:Build(_, parent)
    if self.page then return end
    self.page, self.checks, self.steppers, self.frameCheckKeys = parent, {}, {}, {}
    local title = UI.Text(parent, "GameFontNormalHuge", L("НАСТРОЙКИ"), C.accent)
    title:SetPoint("TOPLEFT", 22, -20)
    local note = UI.Text(parent, "GameFontHighlightSmall", L("Единый центр функций вместо набора мелких аддонов"), C.muted)
    note:SetPoint("LEFT", title, "RIGHT", 14, -2)
    -- The outer Welcome tab already says "Настройки". Repeating the same
    -- heading inside wastes a full navigation row, so category navigation is
    -- a stable left rail and only the active category occupies the workspace.
    title:Hide()
    note:Hide()

    local sidebar = UI.Panel(parent, C.raised, C.line)
    sidebar:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, -18)
    sidebar:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 18, 18)
    sidebar:SetWidth(210)
    local sideTitle = UI.Text(sidebar, "GameFontNormalSmall", L("РАЗДЕЛЫ"), C.muted)
    sideTitle:SetPoint("TOPLEFT", 16, -16)

    -- One focused category at a time. The previous two-column canvas made
    -- related options drift apart and left large dead zones on wide screens.
    local content = UI.Panel(parent, C.raised, C.line)
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 12, 0)
    content:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -18, 18)

    local function MakePage(key, pageTitle, description)
        local page = CreateFrame("Frame", nil, content)
        page:SetAllPoints()
        page:Hide()
        local heading = UI.Text(page, "GameFontNormalLarge", pageTitle, C.accent)
        heading:SetPoint("TOPLEFT", 28, -22)
        local summary = UI.Text(page, "GameFontHighlightSmall", description, C.muted)
        summary:SetPoint("TOPLEFT", 28, -50)
        summary:SetPoint("TOPRIGHT", -28, -50)
        summary:SetJustifyH("LEFT")
        self.categoryPages[key] = page
        return page
    end

    self.categoryTabs, self.categoryPages = {}, {}
    local mainPage = MakePage("main", L("ОСНОВНОЕ"),
        L("Быстрый доступ и основные настройки"))
    local automationPage = MakePage("automation", L("АВТОМАТИЗАЦИЯ"),
        L("Задания, приглашения и действия у торговцев"))
    local groupPage = MakePage("groups", L("ГРУППЫ И КЛЮЧИ"),
        L("Приглашения, эпохальные ключи и умный клик"))
    local interfacePage = MakePage("interface", L("ИНТЕРФЕЙС"),
        L("Общий внешний вид и расположение элементов"))
    local framesPage = MakePage("frames", L("КАПСУЛА И РЕСУРСЫ"),
        L("Точная настройка карточек игрока и цели, ресурсов и аур"))
    local auraPage = MakePage("auras", L("ТРЕКЕР БАФОВ"),
        L("Мини-трекер разрешённых положительных аур на персонаже"))
    local screenshotsPage = MakePage("screenshots", L("РЕЖИМ СКРИНШОТОВ"),
        L("Пять готовых анонимных сцен для страницы аддона"))
    local lootPage = MakePage("loot", L("ДОБЫЧА"),
        L("Окно добычи, голосования и история предметов"))
    local systemPage = MakePage("system", L("СИСТЕМА"),
        L("Перехват ошибок и диагностический журнал"))

    local function SwitchCategory(key)
        if not self.categoryPages[key] then key = "main" end
        for name, page in pairs(self.categoryPages) do page:SetShown(name == key) end
        for name, tab in pairs(self.categoryTabs) do tab:SetActive(name == key) end
        MythicBoostDB.settingsCategory = key
    end
    self.SwitchCategory = SwitchCategory

    local tabOrder = {
        { "main", L("Основное") },
        { "automation", L("Автоматизация") },
        { "groups", L("Группы и ключи") },
        { "interface", L("Интерфейс") },
        { "frames", L("Капсула") },
        { "auras", L("Трекер бафов") },
        { "screenshots", L("Скриншоты") },
        { "loot", L("Добыча") },
        { "system", L("Система") },
    }
    for index, item in ipairs(tabOrder) do
        local tab = UI.Tab(sidebar, item[2], 178)
        tab.categoryKey = item[1]
        tab:SetHeight(42)
        tab:SetPoint("TOPLEFT", 16, -44 - (index - 1) * 50)
        tab.label:ClearAllPoints()
        tab.label:SetPoint("LEFT", 14, 0)
        tab.label:SetJustifyH("LEFT")
        tab.underline:ClearAllPoints()
        tab.underline:SetPoint("TOPLEFT", 1, -1)
        tab.underline:SetPoint("BOTTOMLEFT", 1, 1)
        tab.underline:SetWidth(3)
        tab:SetScript("OnClick", function(button) SwitchCategory(button.categoryKey) end)
        self.categoryTabs[item[1]] = tab
    end

    local quickPages = {
        { L("Найти группу"), "groups" },
        { L("Собрать пати"), "applicants" },
        { L("История напарников"), "history" },
    }
    for index, item in ipairs(quickPages) do
        local button = UI.Button(mainPage, item[1], 190, 30, index == 1)
        button:SetPoint("TOPLEFT", 28 + (index - 1) * 204, -82)
        button:SetScript("OnClick", function()
            local welcome = JP.modules and JP.modules.Welcome
            if welcome and welcome.SwitchPage then welcome:SwitchPage(item[2]) end
        end)
    end

    Heading(mainPage, L("ПОЛНОТА ВЫДАЧИ"), 28, -136, 764)
    local searchSettings = JP.Settings("search", {
        showRejectedResults = true,
        allowRejectedApplications = true,
    })
    self:AddStoredCheck(mainPage, searchSettings, "showRejectedResults",
        L("Показывать серым группы, не прошедшие фильтры"), 28, -170, function()
            JP:RequestRefresh(0)
        end)
    self:AddStoredCheck(mainPage, searchSettings, "allowRejectedApplications",
        L("Разрешать ручную заявку в серые группы"), 52, -204, function()
            JP:RequestRefresh(0)
        end)

    Heading(mainPage, L("АНАЛИЗ ИГРОКОВ"), 28, -254, 764)
    local playerAnalysis = JP.Settings("playerAnalysis", { enabled = true, nameplateMarkers = true })
    self:AddStoredCheck(mainPage, playerAnalysis, "enabled",
        L("Дополнять подсказки ключами и прогнозом игрока"), 28, -288, function()
            JP:ReloadModule("NameplateMarker")
        end, "playerAnalysis")
    self:AddStoredCheck(mainPage, playerAnalysis, "nameplateMarkers",
        L("Отмечать сохранённых перспективных игроков"), 52, -322, function()
            JP:ReloadModule("NameplateMarker")
        end)

    Heading(mainPage, L("ПОМОЩЬ"), 28, -372, 764)
    local guide = UI.Button(mainPage, L("Показать краткую инструкцию"), 230, 28)
    guide:SetPoint("TOPLEFT", 28, -406)
    guide:SetScript("OnClick", function()
        local welcome = JP.modules and JP.modules.Welcome
        if welcome and welcome.ShowGuide then welcome:ShowGuide() end
    end)
    Heading(automationPage, L("ЗАДАНИЯ И ПРИГЛАШЕНИЯ"), 28, -84, 764)
    self:AddCheck(automationPage, "autoQuests", L("Автоматически принимать и сдавать задания"), 28, -118)
    self:AddCheck(automationPage, "summon", L("Автоматически принимать призыв вне боя"), 28, -152)
    self:AddCheck(automationPage, "resurrection", L("Автоматически принимать воскрешение"), 28, -186)
    self:AddCheck(automationPage, "resNoCombat", L("Не принимать боевое воскрешение"), 52, -220)

    Heading(automationPage, L("ТОРГОВЦЫ"), 28, -270, 764)
    self:AddCheck(automationPage, "sellJunk", L("Автоматически продавать серые предметы"), 28, -304)
    self:AddCheck(automationPage, "repair", L("Автоматически ремонтировать экипировку"), 28, -338)
    self:AddCheck(automationPage, "guildRepair", L("Сначала использовать средства гильдии"), 52, -372)
    self:AddCheck(automationPage, "merchantSummary", L("Показывать итог в чате"), 52, -406)

    Heading(groupPage, L("ПОИСК ГРУППЫ"), 28, -84, 764)
    self:AddCheck(groupPage, "whisperInvite", L("Приглашать по шёпоту «inv», «123» или «+»"), 28, -118)
    self:AddCheck(groupPage, "autoKeystone", L("Автоматически вставлять эпохальный ключ"), 28, -152)

    Heading(interfacePage, L("ВНЕШНИЙ ВИД"), 28, -84, 764)
    self:AddCheck(interfacePage, "minimalUI", L("Минимальный интерфейс MythicBoost"), 28, -118, function(value)
        MythicBoostDB.minimalUI = value
        if JP.MinimalUI then JP.MinimalUI:SetEnabled(value) end
    end)
    self.checks.minimalUI:SetChecked(MythicBoostDB.minimalUI == true)
    local minimalOptions = JP.Settings("minimalUIOptions", {
        minimap = true, hideStanceBar = false,
    })
    self:AddStoredCheck(interfacePage, minimalOptions, "minimap",
        L("Оформлять миникарту MythicBoost"), 52, -152, function(value)
            if JP.MinimalUI then JP.MinimalUI:SetMinimapEnabled(value) end
        end, "minimalUIMinimap")
    self:AddStoredCheck(interfacePage, minimalOptions, "hideStanceBar",
        L("Скрывать панель стоек"), 52, -186, function()
            if JP.MinimalUI then JP.MinimalUI:Apply() end
        end, "minimalUIStanceBar")
    self:AddCheck(interfacePage, "hideBags", L("Скрывать панель сумок"), 28, -220, function(value)
        if JP.MinimalUI then JP.MinimalUI:StyleBags(value) end
    end)
    local castBar = UI.CheckBox(interfacePage, L("Кастбар игрока в стиле Quartz"),
        MythicBoostDB.castBar and MythicBoostDB.castBar.enabled == true, function(value)
            MythicBoostDB.castBar.enabled = value and true or false
            JP:ReloadModule("CastBar")
        end)
    castBar:SetPoint("TOPLEFT", 28, -254)
    castBar:SetPoint("TOPRIGHT", -28, -254)
    self.checks.castBar = castBar

    -----------------------------------------------------------------------
    -- Compact player/target capsule. It has its own category because these
    -- are HUD decisions, not incidental toggles in the global interface page.
    -----------------------------------------------------------------------
    local unitFrameSettings = JP.Settings("unitFrames", {
        enabled = true, hideBlizzard = true, unlocked = false,
        scale = 1.5, opacity = 1,
        showHealthText = true, classColoredHealth = false, showPowerText = true,
        animatedPortrait = true, showBadges = true,
        badgesUnlocked = false, badgeShape = 1,
        alwaysShowTarget = true,
        showPlayerAuras = true, showTargetAuras = true,
        aurasAbove = true,
        showResourcePips = true, showEmptyResources = false,
        resourceHeight = 10, resourceGap = 2, resourceOpacity = 1,
    })
    local function ApplyFrameSettings()
        if JP.UnitFrames then JP.UnitFrames:ApplySettings() end
    end
    local function Percent(value)
        return ("%d%%"):format(math.floor(value * 100 + .5))
    end

    ColumnHeading(framesPage, L("КАПСУЛА ИГРОКА И ЦЕЛИ"), false, -84)
    self:AddColumnCheck(framesPage, unitFrameSettings, "enabled",
        L("Включить компактные капсулы"), false, -118, function(value)
            unitFrameSettings.enabled = value and true or false
            JP:ReloadModule("UnitFrames")
        end, "unitFrames")
    local hideBlizzardFrames = self:AddColumnCheck(framesPage, unitFrameSettings, "hideBlizzard",
        L("Скрывать стандартные фреймы Blizzard"), false, -152, ApplyFrameSettings,
        "unitFramesHideBlizzard", 24)
    hideBlizzardFrames:HookScript("OnEnter", function(self)
        UI.Tooltip(self, L("Стандартные фреймы Blizzard"),
            L("Выключи галочку, если хочешь оставить стандартные фреймы рядом с компактными."))
    end)
    hideBlizzardFrames:HookScript("OnLeave", GameTooltip_Hide)
    self:AddColumnCheck(framesPage, unitFrameSettings, "unlocked",
        L("Разблокировать капсулы для перемещения"), false, -186, function(value)
            if JP.UnitFrames then JP.UnitFrames:SetUnlocked(value) end
            MythicBoostDB.interfaceUnlocked = value == true
                or (MythicBoostDB.castBar and MythicBoostDB.castBar.unlocked == true)
                or SettingsHub:GetSettings().movableKeystoneFrame == true
        end, "unitFramesUnlocked")
    self:AddStepper(framesPage, unitFrameSettings, "scale", L("Размер"), false, -224,
        .75, 2.00, .05, Percent, ApplyFrameSettings, "frameScale")
    self:AddStepper(framesPage, unitFrameSettings, "opacity", L("Непрозрачность капсул"), false, -260,
        .55, 1, .05, Percent, ApplyFrameSettings, "frameOpacity")
    self:AddColumnCheck(framesPage, unitFrameSettings, "showHealthText",
        L("Показывать числа здоровья"), false, -298, ApplyFrameSettings, "frameHealthText")
    self:AddColumnCheck(framesPage, unitFrameSettings, "classColoredHealth",
        L("Цвет здоровья по классу"), false, -332, ApplyFrameSettings, "frameClassHealth")
    self:AddColumnCheck(framesPage, unitFrameSettings, "showPowerText",
        L("Показывать числа ресурса"), false, -366, ApplyFrameSettings, "framePowerText")
    self:AddColumnCheck(framesPage, unitFrameSettings, "animatedPortrait",
        L("Живой 3D-портрет"), false, -400, ApplyFrameSettings, "frameAnimatedPortrait")
    self:AddColumnCheck(framesPage, unitFrameSettings, "showBadges",
        L("Показывать класс и уровень"), false, -434, ApplyFrameSettings, "frameBadges")
    self:AddColumnCheck(framesPage, unitFrameSettings, "badgesUnlocked",
        L("Перемещать значки класса и уровня"), false, -468, ApplyFrameSettings,
        "frameBadgesUnlocked", 24)
    self:AddColumnCheck(framesPage, unitFrameSettings, "alwaysShowTarget",
        L("Всегда показывать рамку цели"), false, -502, ApplyFrameSettings,
        "frameAlwaysTarget")
    local resetFrames = UI.Button(framesPage, L("Сбросить позиции капсул"), 210, 28)
    resetFrames:SetPoint("TOPLEFT", 28, -540)
    resetFrames:SetScript("OnClick", function()
        if JP.UnitFrames then
            JP.UnitFrames:AfterCombat("resetPositions", function(module) module:ResetPositions() end)
        end
    end)

    ColumnHeading(framesPage, L("КВАДРАТЫ РЕСУРСА"), true, -84)
    local resourceToggle = self:AddColumnCheck(framesPage, unitFrameSettings, "showResourcePips",
        L("Показывать ресурсные сегменты"), true, -118, ApplyFrameSettings, "frameResources")
    resourceToggle:HookScript("OnEnter", function(self)
        UI.Tooltip(self, L("Ресурсные сегменты"),
            L("Комбо-поинты, руны, осколки душ, сила Света, ци, чародейские заряды и эссенция."))
    end)
    resourceToggle:HookScript("OnLeave", GameTooltip_Hide)
    self:AddColumnCheck(framesPage, unitFrameSettings, "showEmptyResources",
        L("Показывать пустые сегменты"), true, -152, ApplyFrameSettings,
        "frameEmptyResources", 24)
    self:AddStepper(framesPage, unitFrameSettings, "resourceHeight", L("Высота сегментов"), true, -190,
        6, 16, 1, function(value) return tostring(value) .. " px" end,
        ApplyFrameSettings, "frameResourceHeight")
    self:AddStepper(framesPage, unitFrameSettings, "resourceGap", L("Расстояние между ними"), true, -226,
        0, 6, 1, function(value) return tostring(value) .. " px" end,
        ApplyFrameSettings, "frameResourceGap")
    self:AddStepper(framesPage, unitFrameSettings, "resourceOpacity", L("Яркость сегментов"), true, -262,
        .30, 1, .10, Percent, ApplyFrameSettings, "frameResourceOpacity")

    ColumnHeading(framesPage, L("АУРЫ"), true, -312)
    self:AddColumnCheck(framesPage, unitFrameSettings, "aurasAbove",
        L("Размещать ауры сверху"), true, -346, ApplyFrameSettings, "frameAurasAbove")
    self:AddColumnCheck(framesPage, unitFrameSettings, "showPlayerAuras",
        L("Показывать ауры игрока"), true, -380, ApplyFrameSettings, "framePlayerAuras", 24)
    self:AddColumnCheck(framesPage, unitFrameSettings, "showTargetAuras",
        L("Показывать ауры цели"), true, -414, ApplyFrameSettings, "frameTargetAuras", 24)
    self:AddStepper(framesPage, unitFrameSettings, "badgeShape", L("Форма значков"), true, -452,
        1, 4, 1, function(value)
            return ({ L("Круг"), L("Квадрат"), L("Ромб"), L("Нет") })[value] or tostring(value)
        end, ApplyFrameSettings, "frameBadgeShape")
    local resetAppearance = UI.Button(framesPage, L("Вернуть оформление по умолчанию"), 238, 28)
    resetAppearance:SetPoint("TOPRIGHT", framesPage, "TOPRIGHT", -28, -490)
    resetAppearance:SetScript("OnClick", function()
        local defaults = {
            scale = 1.5, opacity = 1,
            showHealthText = true, classColoredHealth = false, showPowerText = true,
            animatedPortrait = true, showBadges = true,
            badgesUnlocked = false, badgeShape = 1,
            alwaysShowTarget = true,
            showPlayerAuras = true, showTargetAuras = true,
            aurasAbove = true,
            showResourcePips = true, showEmptyResources = false,
            resourceHeight = 10, resourceGap = 2, resourceOpacity = 1,
        }
        for key, value in pairs(defaults) do unitFrameSettings[key] = value end
        ApplyFrameSettings()
        SettingsHub:Refresh()
    end)

    -----------------------------------------------------------------------
    -- Positive aura tracker. Every runtime lookup is by an exact spell ID;
    -- it never enumerates the player's global aura list in restricted combat.
    -----------------------------------------------------------------------
    local auraSettings = JP.Settings("positiveAuraTracker", {
        enabled = false, spellIDs = {}, showWhenMissing = false,
        showSeconds = true, showStacks = true, showIcon = true,
        barHeight = 190, barWidth = 72, sideGap = 110, barSpacing = 12,
        colorPreset = 2, texturePreset = 1, fontSize = 24,
        pulse = true, pulseSpeed = .8, maxIcons = 8, iconOverride = nil,
        x = 0, y = -20, unlocked = false,
    })
    -- The old free-form texture field encouraged pasting square spell icons as
    -- tall bar art. Remove that one-time override now that forms are presets.
    if auraSettings.textureInputRevision ~= 1 then
        auraSettings.barTexture = nil
        auraSettings.textureInputRevision = 1
    end
    -- Leave a real gutter before the preview at narrow UI scales. The fixed
    -- stepper controls end at the row edge, so even the '+' button remains
    -- completely outside the preview border.
    local AURA_LEFT, AURA_RIGHT, AURA_CONTROL_WIDTH = 28, 286, 240
    local function PlaceAuraControl(control, x, y, width)
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", x, y)
        control:SetWidth(width or AURA_CONTROL_WIDTH)
        return control
    end
    Heading(auraPage, L("ОТОБРАЖЕНИЕ"), 28, -84, 764)
    local auraEnabled = self:AddStoredCheck(auraPage, auraSettings, "enabled",
        L("Включить мини-трекер положительных аур"), 28, -118, function()
            if JP.PositiveAuraTracker then JP.PositiveAuraTracker:Refresh() end
        end, "positiveAuraEnabled")
    PlaceAuraControl(auraEnabled, AURA_LEFT, -118, 506)
    local auraMissing = self:AddStoredCheck(auraPage, auraSettings, "showWhenMissing",
        L("Предупреждать, если бафа нет"), 28, -152, function()
            if JP.PositiveAuraTracker then JP.PositiveAuraTracker:Refresh() end
        end, "positiveAuraMissing")
    PlaceAuraControl(auraMissing, AURA_LEFT, -152)
    local auraSeconds = self:AddStoredCheck(auraPage, auraSettings, "showSeconds",
        L("Показывать оставшиеся секунды"), 28, -186, function()
            if JP.PositiveAuraTracker then JP.PositiveAuraTracker:Refresh() end
        end, "positiveAuraSeconds")
    PlaceAuraControl(auraSeconds, AURA_LEFT, -186)
    local auraPulse = self:AddStoredCheck(auraPage, auraSettings, "pulse",
        L("Плавное переливание"), AURA_RIGHT, -152, function()
            if JP.PositiveAuraTracker then JP.PositiveAuraTracker:Refresh() end
        end, "positiveAuraPulse")
    PlaceAuraControl(auraPulse, AURA_RIGHT, -152)
    local auraStacks = self:AddStoredCheck(auraPage, auraSettings, "showStacks",
        L("Показывать количество зарядов"), 28, -220, function()
            if JP.PositiveAuraTracker then JP.PositiveAuraTracker:Refresh() end
        end, "positiveAuraStacks")
    PlaceAuraControl(auraStacks, AURA_LEFT, -220)
    local auraIcon = self:AddStoredCheck(auraPage, auraSettings, "showIcon",
        L("Иконка заклинания на шкале"), AURA_RIGHT, -186, function()
            if JP.PositiveAuraTracker then JP.PositiveAuraTracker:Refresh() end
        end, "positiveAuraIcon")
    PlaceAuraControl(auraIcon, AURA_RIGHT, -186)
    local auraHeight = self:AddStepper(auraPage, auraSettings, "barHeight", L("Высота шкалы"), false, -260,
        100, 300, 10, function(value) return tostring(value) .. " px" end, function()
            if JP.PositiveAuraTracker then JP.PositiveAuraTracker:ApplySettings() end
        end, "positiveAuraHeight")
    PlaceAuraControl(auraHeight, AURA_LEFT, -260)
    local auraWidth = self:AddStepper(auraPage, auraSettings, "barWidth", L("Ширина шкалы"), false, -260,
        36, 120, 6, function(value) return tostring(value) .. " px" end, function()
            if JP.PositiveAuraTracker then JP.PositiveAuraTracker:ApplySettings() end
        end, "positiveAuraWidth")
    PlaceAuraControl(auraWidth, AURA_RIGHT, -260)
    local auraSideGap = self:AddStepper(auraPage, auraSettings, "sideGap", L("Отступ от персонажа"), false, -296,
        40, 240, 10, function(value) return tostring(value) .. " px" end, function()
            if JP.PositiveAuraTracker then JP.PositiveAuraTracker:ApplySettings() end
        end, "positiveAuraSideGap")
    PlaceAuraControl(auraSideGap, AURA_LEFT, -296)
    local auraSpacing = self:AddStepper(auraPage, auraSettings, "barSpacing", L("Между шкалами"), false, -296,
        0, 40, 2, function(value) return tostring(value) .. " px" end, function()
            if JP.PositiveAuraTracker then JP.PositiveAuraTracker:ApplySettings() end
        end, "positiveAuraBarSpacing")
    PlaceAuraControl(auraSpacing, AURA_RIGHT, -296)
    local auraColor = self:AddStepper(auraPage, auraSettings, "colorPreset", L("Цвет шкал"), false, -332,
        1, 6, 1, function(value)
            return JP.PositiveAuraTracker and JP.PositiveAuraTracker:GetColorName(value) or tostring(value)
        end, function()
            if JP.PositiveAuraTracker then JP.PositiveAuraTracker:ApplySettings(); JP.PositiveAuraTracker:Refresh() end
            if SettingsHub.RefreshAuraPreview then SettingsHub:RefreshAuraPreview() end
        end, "positiveAuraColor")
    PlaceAuraControl(auraColor, AURA_LEFT, -332)
    local auraTexture = self:AddStepper(auraPage, auraSettings, "texturePreset", L("Форма шкал"), false, -332,
        1, 3, 1, function(value)
            return JP.PositiveAuraTracker and JP.PositiveAuraTracker:GetTextureName(value) or tostring(value)
        end, function(value)
            if JP.PositiveAuraTracker then JP.PositiveAuraTracker:SetTexturePreset(value) end
            if SettingsHub.RefreshAuraPreview then SettingsHub:RefreshAuraPreview() end
        end, "positiveAuraTexture")
    PlaceAuraControl(auraTexture, AURA_RIGHT, -332)
    local auraFontSize = self:AddStepper(auraPage, auraSettings, "fontSize", L("Размер секунд"), false, -368,
        12, 48, 2, function(value) return tostring(value) .. " px" end, function()
            if JP.PositiveAuraTracker then JP.PositiveAuraTracker:ApplySettings() end
            if SettingsHub.RefreshAuraPreview then SettingsHub:RefreshAuraPreview() end
        end, "positiveAuraFontSize")
    PlaceAuraControl(auraFontSize, AURA_LEFT, -368)
    local auraPulseSpeed = self:AddStepper(auraPage, auraSettings, "pulseSpeed", L("Скорость переливания"), false, -368,
        .3, 2, .1, function(value) return ("%.1f c"):format(value) end, function()
            if JP.PositiveAuraTracker then JP.PositiveAuraTracker:ApplySettings() end
        end, "positiveAuraPulseSpeed")
    PlaceAuraControl(auraPulseSpeed, AURA_RIGHT, -368)

    local previewPanel = UI.Panel(auraPage, C.field, C.line)
    previewPanel:SetSize(150, 240)
    previewPanel:SetPoint("TOPRIGHT", -28, -84)
    local previewTitle = UI.Text(previewPanel, "GameFontNormalSmall", L("ПРЕДПРОСМОТР"), C.muted)
    previewTitle:SetPoint("TOP", 0, -9)
    local previewLeft = previewPanel:CreateTexture(nil, "ARTWORK")
    previewLeft:SetSize(56, 168)
    previewLeft:SetPoint("BOTTOMLEFT", 12, 31)
    previewLeft:SetBlendMode("ADD")
    previewLeft:SetAlpha(.16)
    local previewLeftFill = previewPanel:CreateTexture(nil, "OVERLAY")
    previewLeftFill:SetSize(56, 109)
    previewLeftFill:SetPoint("BOTTOMLEFT", 12, 31)
    previewLeftFill:SetBlendMode("ADD")
    previewLeftFill:SetTexCoord(0, 1, .35, 1)
    local previewRight = previewPanel:CreateTexture(nil, "ARTWORK")
    previewRight:SetSize(56, 168)
    previewRight:SetPoint("BOTTOMRIGHT", -12, 31)
    previewRight:SetBlendMode("ADD")
    previewRight:SetTexCoord(1, 0, 0, 1)
    previewRight:SetAlpha(.16)
    local previewRightFill = previewPanel:CreateTexture(nil, "OVERLAY")
    previewRightFill:SetSize(56, 109)
    previewRightFill:SetPoint("BOTTOMRIGHT", -12, 31)
    previewRightFill:SetBlendMode("ADD")
    previewRightFill:SetTexCoord(1, 0, .35, 1)
    local previewSeconds = UI.Text(previewPanel, "GameFontNormalHuge", "35", C.text)
    previewSeconds:SetPoint("CENTER", 0, -4)
    previewSeconds:SetShadowColor(0, 0, 0, 1)
    previewSeconds:SetShadowOffset(2, -2)
    local previewCaption = UI.Text(previewPanel, "GameFontHighlightSmall", L("65% времени"), C.muted)
    previewCaption:SetPoint("BOTTOM", 0, 8)
    function self:RefreshAuraPreview()
        local colors = {
            { 1.00, .78, .20 }, { .20, .82, 1.00 }, { .32, 1.00, .48 },
            { .72, .34, 1.00 }, { 1.00, .30, .18 }, { 1.00, 1.00, 1.00 },
        }
        local color = colors[tonumber(auraSettings.colorPreset) or 2] or colors[2]
        local texture = JP.PositiveAuraTracker and JP.PositiveAuraTracker:GetBarTexture()
            or "Interface\\AddOns\\MythicBoost\\Media\\AuraWingMask"
        previewLeft:SetTexture(texture); previewRight:SetTexture(texture)
        previewLeftFill:SetTexture(texture); previewRightFill:SetTexture(texture)
        previewLeft:SetVertexColor(color[1], color[2], color[3], 1)
        previewRight:SetVertexColor(color[1], color[2], color[3], 1)
        previewLeftFill:SetVertexColor(color[1], color[2], color[3], 1)
        previewRightFill:SetVertexColor(color[1], color[2], color[3], 1)
        previewSeconds:SetFont("Fonts\\FRIZQT__.TTF", tonumber(auraSettings.fontSize) or 24, "OUTLINE")
    end
    previewPanel:SetScript("OnUpdate", function(_, elapsed)
        previewPanel.elapsed = (previewPanel.elapsed or 0) + elapsed
        if previewPanel.elapsed < .05 then return end
        previewPanel.elapsed = 0
        if auraSettings.pulse == false then
            previewLeftFill:SetAlpha(1); previewRightFill:SetAlpha(1)
            return
        end
        local speed = math.max(.3, tonumber(auraSettings.pulseSpeed) or .8)
        local wave = .5 + .5 * math.cos((GetTime() % speed) / speed * math.pi * 2)
        local alpha = .68 + .32 * wave
        previewLeftFill:SetAlpha(alpha); previewRightFill:SetAlpha(alpha)
    end)
    self:RefreshAuraPreview()

    Heading(auraPage, L("СПИСОК ЗАКЛИНАНИЙ"), 28, -414, 764)
    local spellInput, spellInputHolder = TextBox(auraPage, 270, 30,
        L("ID, ссылка или точное имя; несколько — через запятую"))
    spellInputHolder:SetPoint("TOPLEFT", 28, -448)
    local addSpell = UI.Button(auraPage, L("Добавить"), 82, 30, true)
    addSpell:SetPoint("LEFT", spellInputHolder, "RIGHT", 8, 0)
    local scanSpell = UI.Button(auraPage, L("Сканировать"), 132, 30, true)
    scanSpell:SetPoint("LEFT", addSpell, "RIGHT", 8, 0)
    local eclipsePreset = UI.Button(auraPage, L("Затмение"), 94, 30)
    eclipsePreset:SetPoint("LEFT", scanSpell, "RIGHT", 8, 0)
    local clearSpells = UI.Button(auraPage, L("Очистить"), 86, 30)
    clearSpells:SetPoint("LEFT", eclipsePreset, "RIGHT", 8, 0)

    self.auraSpellSummary = UI.Text(auraPage, "GameFontHighlightSmall", "", C.muted)
    self.auraSpellSummary:SetPoint("TOPLEFT", 28, -488)
    self.auraSpellSummary:SetPoint("TOPRIGHT", -28, -488)
    self.auraSpellSummary:SetJustifyH("LEFT")
    self.auraSpellSummary:SetWordWrap(true)

    self.auraStatus = UI.Text(auraPage, "GameFontHighlightSmall", "", C.amber)
    self.auraStatus:SetPoint("TOPLEFT", 28, -526)
    self.auraStatus:SetPoint("TOPRIGHT", -28, -526)
    self.auraStatus:SetJustifyH("LEFT")
    self.auraStatus:SetText(L("Сканирование поймает следующий успешно применённый вами спелл."))

    local spellScanner = CreateFrame("Frame")
    local scanning
    local function StopSpellScan(message)
        scanning = nil
        spellScanner:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        scanSpell.label:SetText(L("Сканировать"))
        if message then self.auraStatus:SetText(message) end
    end
    spellScanner:SetScript("OnEvent", function(_, _, unit, _, spellID)
        if not scanning or unit ~= "player" then return end
        spellID = UI.SafeNumber(spellID)
        if not spellID or not JP.PositiveAuraTracker then return end
        local resolved = JP.PositiveAuraTracker:ResolveInput(tostring(spellID))
        local spell = resolved and resolved[1]
        if not spell then return end
        local added = JP.PositiveAuraTracker:AddFromInput(tostring(spellID))
        if added > 0 then
            StopSpellScan((L("Найдено: %s (%d) — добавлено в список")):format(spell.name, spellID))
        else
            StopSpellScan((L("Найдено: %s (%d) — уже в списке")):format(spell.name, spellID))
        end
        self:Refresh()
    end)
    scanSpell:SetScript("OnClick", function()
        if scanning then
            StopSpellScan(L("Сканирование отменено"))
            return
        end
        scanning = true
        spellScanner:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        scanSpell.label:SetText(L("Отмена"))
        self.auraStatus:SetText(L("Жду следующий успешно применённый спелл..."))
    end)

    addSpell:SetScript("OnClick", function()
        if not JP.PositiveAuraTracker then return end
        local input = spellInput.placeholderShown and "" or spellInput:GetText()
        local added, rejected = JP.PositiveAuraTracker:AddFromInput(input)
        self.auraStatus:SetText((L("Добавлено: %d; не распознано: %d")):format(added, #rejected))
        spellInput:SetText(""); spellInput.placeholderShown = nil
        self:Refresh()
    end)
    clearSpells:SetScript("OnClick", function()
        if JP.PositiveAuraTracker then JP.PositiveAuraTracker:ClearSpells() end
        self.auraStatus:SetText(L("Список очищен"))
        self:Refresh()
    end)
    eclipsePreset:SetScript("OnClick", function()
        if not JP.PositiveAuraTracker then return end
        local added, rejected = JP.PositiveAuraTracker:AddFromInput("1233272,194223,102560")
        self.auraStatus:SetText((L("Пресет затмения: добавлено %d; недоступно %d")):format(added, #rejected))
        self:Refresh()
    end)
    eclipsePreset:HookScript("OnEnter", function(self)
        UI.Tooltip(self, L("Затмение друида"),
            L("Одним нажатием добавляет три эффекта затмения в список."))
    end)
    eclipsePreset:HookScript("OnLeave", GameTooltip_Hide)

    -----------------------------------------------------------------------
    -- Screenshot showcase: exact non-secure copies of the capsule, never the
    -- live player frames. The opaque stage also keeps chat and character data
    -- out of screenshots intended for the public addon page.
    -----------------------------------------------------------------------
    Heading(screenshotsPage, L("АНОНИМНЫЕ ДЕМО-СЦЕНЫ"), 28, -84, 764)
    local privacyNote = UI.Text(screenshotsPage, "GameFontHighlightSmall",
        L("Демо закрывает остальной интерфейс. Все имена и значения вымышлены; данные персонажа, сервера и чата не используются."), C.green)
    privacyNote:SetPoint("TOPLEFT", 28, -118)
    privacyNote:SetPoint("TOPRIGHT", -28, -118)
    privacyNote:SetJustifyH("LEFT")
    privacyNote:SetWordWrap(true)

    local screenshotScenes = {
        { L("1 - Общий вид"), L("Спокойная пара игрок/цель с ресурсом и базовыми аурами.") },
        { L("2 - Танк под давлением"), L("Низкое здоровье, защитные эффекты и шесть рун.") },
        { L("3 - Лекарь и опасная цель"), L("Мана, критическое здоровье и эффекты для рассеивания.") },
        { L("4 - Комбо и дебаффы"), L("Семь комбо-поинтов и плотная строка эффектов.") },
        { L("5 - Чистый минимал"), L("Чистые капсулы без эффектов для обложки и сравнения.") },
    }
    for index, scene in ipairs(screenshotScenes) do
        local y = -166 - (index - 1) * 56
        local button = UI.Button(screenshotsPage, scene[1], 286, 36, true)
        button:SetPoint("TOPLEFT", 28, y)
        button:SetScript("OnClick", function()
            if JP.UnitFrames then JP.UnitFrames:ShowScreenshotDemo(index) end
        end)
        local description = UI.Text(screenshotsPage, "GameFontHighlightSmall", scene[2], C.muted)
        description:SetPoint("LEFT", button, "RIGHT", 18, 0)
        description:SetPoint("RIGHT", screenshotsPage, "RIGHT", -28, 0)
        description:SetJustifyH("LEFT")
        description:SetWordWrap(false)
    end
    local closeDemo = UI.Button(screenshotsPage, L("Закрыть демо"), 170, 28)
    closeDemo:SetPoint("TOPLEFT", 28, -452)
    closeDemo:SetScript("OnClick", function()
        if JP.UnitFrames then JP.UnitFrames:HideScreenshotDemo() end
    end)

    Heading(lootPage, L("ОКНО И ПОЛУЧЕНИЕ"), 28, -84, 764)
    local lootUI = UI.CheckBox(lootPage, L("Встроенное компактное окно добычи"),
        MythicBoostDB.lootUI and MythicBoostDB.lootUI.enabled == true, function(value)
            MythicBoostDB.lootUI.enabled = value and true or false
            JP:ReloadModule("LootUI")
            SettingsHub:RefreshDependencies()
        end)
    lootUI:SetPoint("TOPLEFT", 28, -118)
    lootUI:SetPoint("TOPRIGHT", -28, -118)
    lootUI:HookScript("OnEnter", function(self)
        UI.Tooltip(self, L("Окно добычи MythicBoost"),
            L("Компактные строки, голосование Need/Greed, история победителей, подсказки и сбор кликом."),
            L("Внешние XLoot_Frame, XLoot_Group и XLoot_Monitor необходимо отключить."))
    end)
    lootUI:HookScript("OnLeave", GameTooltip_Hide)
    self.checks.lootUI = lootUI

    local lootAtCursor = UI.CheckBox(lootPage, L("Открывать добычу рядом с курсором"),
        MythicBoostDB.lootUI and MythicBoostDB.lootUI.atCursor ~= false, function(value)
            MythicBoostDB.lootUI.atCursor = value
        end)
    lootAtCursor:SetPoint("TOPLEFT", 52, -152)
    lootAtCursor:SetPoint("TOPRIGHT", -28, -152)
    self.checks.lootAtCursor = lootAtCursor

    local lootRolls = UI.CheckBox(lootPage, L("Голосование за групповую добычу"),
        MythicBoostDB.lootUI and MythicBoostDB.lootUI.showRolls ~= false, function(value)
            MythicBoostDB.lootUI.showRolls = value
            if JP.LootUI then
                if value then
                    JP.LootUI:SuppressBlizzardRolls()
                    JP.LootUI:RecoverRolls()
                else
                    if JP.LootUI.rollFrame then JP.LootUI.rollFrame:Hide() end
                    JP.LootUI:RestoreBlizzardRolls()
                end
            end
            SettingsHub:RefreshDependencies()
        end)
    lootRolls:SetPoint("TOPLEFT", 52, -186)
    lootRolls:SetPoint("TOPRIGHT", -28, -186)
    self.checks.lootRolls = lootRolls

    local lootHistory = UI.CheckBox(lootPage, L("Показывать, кто что получил"),
        MythicBoostDB.lootUI and MythicBoostDB.lootUI.showHistory ~= false, function(value)
            MythicBoostDB.lootUI.showHistory = value
            if JP.LootUI then
                if value then JP.LootUI:RefreshHistory()
                elseif JP.LootUI.historyFrame then JP.LootUI.historyFrame:Hide() end
            end
        end)
    lootHistory:SetPoint("TOPLEFT", 52, -220)
    lootHistory:SetPoint("TOPRIGHT", -28, -220)
    self.checks.lootHistory = lootHistory

    local testRoll = UI.Button(lootPage, L("Показать тестовый бросок"), 230, 28)
    testRoll:SetPoint("TOPLEFT", 52, -264)
    testRoll:SetScript("OnClick", function()
        if JP.LootUI then JP.LootUI:ShowTestRoll() end
    end)
    testRoll:HookScript("OnEnter", function(self)
        UI.Tooltip(self, L("Тестовый бросок"),
            L("Показывает безопасный локальный пример. Перетащи окно за заголовок — позиция сохранится."))
    end)
    testRoll:HookScript("OnLeave", GameTooltip_Hide)
    self.lootTestButton = testRoll

    Heading(interfacePage, L("РАСПОЛОЖЕНИЕ"), 28, -372, 764)
    local interfaceMove = UI.CheckBox(interfacePage, L("Режим перемещения интерфейса"),
        MythicBoostDB.interfaceUnlocked == true, function(value)
            SettingsHub:SetInterfaceUnlocked(value)
        end)
    interfaceMove:SetPoint("TOPLEFT", 28, -406)
    interfaceMove:SetPoint("TOPRIGHT", -28, -406)
    interfaceMove:HookScript("OnEnter", function(self)
        UI.Tooltip(self, L("Единый режим перемещения"),
            L("Разблокирует фреймы, кастбар, окно ключа и добычу, если она не привязана к курсору."),
            L("После расстановки отключи режим здесь же."))
    end)
    interfaceMove:HookScript("OnLeave", GameTooltip_Hide)
    self.checks.interfaceUnlocked = interfaceMove

    -- Умный левый клик. Обе галочки меняют атрибут защищённой кнопки, поэтому
    -- применяются вне боя; сама проверка «мёртв / в бою» делается условниками
    -- макроса уже в момент нажатия.
    Heading(groupPage, L("УМНЫЙ КЛИК"), 28, -206, 764)
    local smartBuff = UI.CheckBox(groupPage, L("Умный клик: давать недостающий бафф"),
        MythicBoostDB.smartClick and MythicBoostDB.smartClick.buff == true, function(value)
            if JP.SmartClick then JP.SmartClick:SetOption("buff", value) end
        end)
    smartBuff:SetPoint("TOPLEFT", 28, -240)
    smartBuff:SetPoint("TOPRIGHT", -28, -240)
    smartBuff:HookScript("OnEnter", function(self)
        UI.Tooltip(self, L("Умный клик: бафф"),
            L("Добавляет в макрос MBSmartClick групповой бафф твоего класса."),
            L("Аддон ведёт макрос MBSmartClick — привяжи его один раз в клик-касте DandersFrames."),
            JP.SmartClick and JP.SmartClick:Describe() or "")
    end)
    smartBuff:HookScript("OnLeave", GameTooltip_Hide)
    self.checks.smartBuff = smartBuff

    local smartRes = UI.CheckBox(groupPage, L("Умный клик: поднимать мёртвого"),
        MythicBoostDB.smartClick and MythicBoostDB.smartClick.res == true, function(value)
            if JP.SmartClick then JP.SmartClick:SetOption("res", value) end
        end)
    smartRes:SetPoint("TOPLEFT", 28, -274)
    smartRes:SetPoint("TOPRIGHT", -28, -274)
    smartRes:HookScript("OnEnter", function(self)
        UI.Tooltip(self, L("Умный клик: воскрешение"),
            L("В бою — боевое воскрешение, вне боя — обычное. Заклинание выбирает игра в момент клика."),
            L("Аддон ведёт макрос MBSmartClick — привяжи его один раз в клик-касте DandersFrames."),
            JP.SmartClick and JP.SmartClick:Describe() or "")
    end)
    smartRes:HookScript("OnLeave", GameTooltip_Hide)
    self.checks.smartRes = smartRes

    Heading(lootPage, L("ГРУППОВАЯ ДОБЫЧА"), 28, -322, 764)
    local rcLoot = UI.CheckBox(lootPage, L("Отвечать на розыгрыши RCLootCouncil"),
        MythicBoostDB.rcLoot and MythicBoostDB.rcLoot.enabled == true, function(value)
            if JP.RCLootBridge then JP.RCLootBridge:SetEnabled(value) end
        end)
    rcLoot:SetPoint("TOPLEFT", 28, -356)
    rcLoot:SetPoint("TOPRIGHT", -28, -356)
    rcLoot:HookScript("OnEnter", function(self)
        UI.Tooltip(self, L("Мост к RCLootCouncil"),
            L("Лидер разыгрывает вещь — окно открывается у нас, ответ уходит в его RCLootCouncil."),
            L("Сам RCLootCouncil тебе больше не нужен: если он стоит, отключи его, иначе ответите оба."),
            L("Сверху к каждой вещи добавлен наш вердикт: BIS для спека или нет."))
    end)
    rcLoot:HookScript("OnLeave", GameTooltip_Hide)
    self.checks.rcLoot = rcLoot

    -- Prevent Error in Game: заменяет связку BugGrabber + BugSack. Флажок и
    -- кнопка стоят рядом намеренно — выключить перехват и тут же посмотреть,
    -- что он успел накопить, это один сценарий.
    Heading(systemPage, L("ПЕРЕХВАТ ОШИБОК"), 28, -84, 764)
    local preventErrors = UI.CheckBox(systemPage, L("Перехватывать Lua-ошибки в журнал"),
        MythicBoostDB.errorGuard and MythicBoostDB.errorGuard.enabled == true, function(value)
            if JP.ErrorGuard then
                JP.ErrorGuard:SetEnabled(value)
            end
            SettingsHub:RefreshDependencies()
        end)
    preventErrors:SetPoint("TOPLEFT", 28, -118)
    preventErrors:SetPoint("TOPRIGHT", -28, -118)
    preventErrors:HookScript("OnEnter", function(self)
        UI.Tooltip(self, L("Перехват Lua-ошибок"),
            L("Ошибки Lua не показываются на экране, а сохраняются в журнале со счётчиком повторов."),
            L("Они не теряются — копятся в журнале со счётчиком повторов и переживают /reload."),
            L("Функция выключена по умолчанию. Не включай её одновременно с BugGrabber или BugSack."))
    end)
    preventErrors:HookScript("OnLeave", GameTooltip_Hide)
    self.checks.preventErrors = preventErrors

    local errorKeepSettings = JP.Settings("errorGuard", { enabled = false, keepBetweenSessions = true })
    self:AddStoredCheck(systemPage, errorKeepSettings, "keepBetweenSessions",
        L("Сохранять журнал между перезагрузками"), 52, -152, nil, "errorKeep")

    local errorLog = UI.Button(systemPage, L("Открыть журнал ошибок"), 210, 28)
    errorLog:SetPoint("TOPLEFT", 52, -190)
    errorLog:SetScript("OnClick", function()
        if JP.ErrorGuard then JP.ErrorGuard:Toggle() end
    end)
    errorLog:HookScript("OnEnter", function(self)
        local unique, total = 0, 0
        if JP.ErrorGuard then unique, total = JP.ErrorGuard:Count() end
        UI.Tooltip(self, L("Журнал ошибок"),
            (L("Сейчас в журнале: %d уникальных, %d срабатываний.")):format(unique, total),
            L("Щелчок по строке открывает полный трейс — его можно выделить и скопировать."))
    end)
    errorLog:HookScript("OnLeave", GameTooltip_Hide)

    Heading(systemPage, L("СОСТОЯНИЕ"), 28, -246, 764)
    self.systemStatus = UI.Text(systemPage, "GameFontHighlightSmall", "", C.muted)
    self.systemStatus:SetPoint("TOPLEFT", 28, -280)
    self.systemStatus:SetPoint("TOPRIGHT", -28, -280)
    self.systemStatus:SetJustifyH("LEFT")
    self.systemStatus:SetWordWrap(true)

    local automationInfo = UI.Text(automationPage, "GameFontHighlightSmall",
        L("Shift временно отключает автоматизацию заданий, продажу и ремонт."), C.muted)
    automationInfo:SetPoint("TOPLEFT", 28, -432)
    automationInfo:SetPoint("TOPRIGHT", -28, -432)
    automationInfo:SetJustifyH("LEFT")

    SwitchCategory(MythicBoostDB.settingsCategory or "main")
    self:RefreshDependencies()
end

function SettingsHub:Refresh()
    if not self.page then return end
    local settings = self:GetSettings()
    for key, check in pairs(self.checks or {}) do
        local value
        local frameKey = self.frameCheckKeys and self.frameCheckKeys[key]
        if frameKey then value = MythicBoostDB.unitFrames and MythicBoostDB.unitFrames[frameKey] == true
        elseif key == "minimalUI" then value = MythicBoostDB.minimalUI == true
        elseif key == "minimalUIMinimap" then
            value = MythicBoostDB.minimalUIOptions and MythicBoostDB.minimalUIOptions.minimap ~= false
        elseif key == "minimalUIStanceBar" then
            value = MythicBoostDB.minimalUIOptions and MythicBoostDB.minimalUIOptions.hideStanceBar == true
        elseif key == "showRejectedResults" then value = MythicBoostDB.search and MythicBoostDB.search.showRejectedResults ~= false
        elseif key == "allowRejectedApplications" then value = MythicBoostDB.search and MythicBoostDB.search.allowRejectedApplications ~= false
        elseif key == "playerAnalysis" then value = MythicBoostDB.playerAnalysis and MythicBoostDB.playerAnalysis.enabled ~= false
        elseif key == "nameplateMarkers" then value = MythicBoostDB.playerAnalysis and MythicBoostDB.playerAnalysis.nameplateMarkers ~= false
        elseif key == "unitFrames" then value = MythicBoostDB.unitFrames and MythicBoostDB.unitFrames.enabled == true
        elseif key == "unitFramesHideBlizzard" then value = MythicBoostDB.unitFrames and MythicBoostDB.unitFrames.hideBlizzard ~= false
        elseif key == "castBar" then value = MythicBoostDB.castBar and MythicBoostDB.castBar.enabled == true
        elseif key == "lootUI" then value = MythicBoostDB.lootUI and MythicBoostDB.lootUI.enabled == true
        elseif key == "lootAtCursor" then value = MythicBoostDB.lootUI and MythicBoostDB.lootUI.atCursor ~= false
        elseif key == "lootRolls" then value = MythicBoostDB.lootUI and MythicBoostDB.lootUI.showRolls ~= false
        elseif key == "lootHistory" then value = MythicBoostDB.lootUI and MythicBoostDB.lootUI.showHistory ~= false
        elseif key == "interfaceUnlocked" then value = MythicBoostDB.interfaceUnlocked == true
        elseif key == "positiveAuraEnabled" then
            value = MythicBoostDB.positiveAuraTracker and MythicBoostDB.positiveAuraTracker.enabled == true
        elseif key == "positiveAuraMissing" then
            value = MythicBoostDB.positiveAuraTracker and MythicBoostDB.positiveAuraTracker.showWhenMissing == true
        elseif key == "positiveAuraSeconds" then
            value = not MythicBoostDB.positiveAuraTracker or MythicBoostDB.positiveAuraTracker.showSeconds ~= false
        elseif key == "positiveAuraStacks" then
            value = not MythicBoostDB.positiveAuraTracker or MythicBoostDB.positiveAuraTracker.showStacks ~= false
        elseif key == "positiveAuraIcon" then
            value = not MythicBoostDB.positiveAuraTracker or MythicBoostDB.positiveAuraTracker.showIcon ~= false
        elseif key == "positiveAuraPulse" then
            value = not MythicBoostDB.positiveAuraTracker or MythicBoostDB.positiveAuraTracker.pulse ~= false
        elseif key == "smartBuff" then
            value = MythicBoostDB.smartClick and MythicBoostDB.smartClick.buff == true
        elseif key == "smartRes" then
            value = MythicBoostDB.smartClick and MythicBoostDB.smartClick.res == true
        elseif key == "rcLoot" then
            value = MythicBoostDB.rcLoot and MythicBoostDB.rcLoot.enabled == true
        elseif key == "preventErrors" then
            value = MythicBoostDB.errorGuard and MythicBoostDB.errorGuard.enabled == true
        elseif key == "errorKeep" then
            value = MythicBoostDB.errorGuard and MythicBoostDB.errorGuard.keepBetweenSessions ~= false
        else value = settings[key] == true end
        check:SetChecked(value)
    end
    for _, binding in pairs(self.steppers or {}) do
        binding.control:SetValue(binding.settings[binding.key], true)
    end
    self:RefreshDependencies()
    if self.auraSpellSummary and JP.PositiveAuraTracker then
        self.auraSpellSummary:SetText(L("Отслеживается: ") .. JP.PositiveAuraTracker:GetSpellSummary())
    end
    if self.RefreshAuraPreview then self:RefreshAuraPreview() end
    if self.systemStatus then
        local rioReady = RaiderIO and type(RaiderIO.GetProfile) == "function"
        local unique, total = 0, 0
        if JP.ErrorGuard then unique, total = JP.ErrorGuard:Count() end
        self.systemStatus:SetText((L("Версия %s  -  Raider.IO: %s  -  журнал: %d / %d")):format(
            JP:GetVersion(), rioReady and L("подключён") or L("не найден"), unique, total))
    end
end

function SettingsHub:Enable() self:GetSettings() end
function SettingsHub:Disable() end
function SettingsHub:Destroy() end

JP.SettingsHub = SettingsHub
JP:RegisterModule("SettingsHub", SettingsHub)
