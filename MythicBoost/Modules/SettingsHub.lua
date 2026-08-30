local _, JP = ...
local L = JP.L
local SettingsHub = {}
local UI, C = JP.UI, JP.UI.colors

-- Дефолты теперь выставляет InitializeDatabase при загрузке. Здесь они
-- остаются страховкой и обязаны с ним совпадать: раньше этот список
-- был единственным источником, а применялся только при открытии окна
-- настроек — до этого Convenience читал базу напрямую и видел nil.
local DEFAULTS = {
    autoQuests = true,
    summon = true,
    resurrection = true,
    resNoCombat = true,
    sellJunk = true,
    repair = true,
    guildRepair = true,
    merchantSummary = true,
    whisperInvite = true,
    inviteKeyword = "inv",
    autoKeystone = true,
    movableKeystoneFrame = false,
    hideBags = true,
}

function SettingsHub:GetSettings()
    MythicBoostDB.convenience = type(MythicBoostDB.convenience) == "table" and MythicBoostDB.convenience or {}
    local settings = MythicBoostDB.convenience
    for key, value in pairs(DEFAULTS) do if settings[key] == nil then settings[key] = value end end
    return settings
end

local function Heading(parent, text, x, y, width)
    local label = UI.Text(parent, "GameFontNormalLarge", text, C.accent)
    label:SetPoint("TOPLEFT", x, y)
    local line = UI.Line(parent, C.lineSoft)
    line:SetPoint("TOPLEFT", x, y - 25)
    line:SetSize(width, 1)
end

function SettingsHub:AddCheck(parent, key, label, x, y, callback)
    local settings = self:GetSettings()
    local check = UI.CheckBox(parent, label, settings[key], function(value)
        settings[key] = value
        if callback then callback(value) end
    end)
    check:SetPoint("TOPLEFT", x, y)
    check:SetWidth(330)
    self.checks[key] = check
    return check
end

function SettingsHub:SetInterfaceUnlocked(value)
    local unlocked = value == true
    MythicBoostDB.interfaceUnlocked = unlocked
    MythicBoostDB.unitFrames = type(MythicBoostDB.unitFrames) == "table" and MythicBoostDB.unitFrames or {}
    MythicBoostDB.castBar = type(MythicBoostDB.castBar) == "table" and MythicBoostDB.castBar or {}
    MythicBoostDB.unitFrames.unlocked = unlocked
    MythicBoostDB.castBar.unlocked = unlocked
    self:GetSettings().movableKeystoneFrame = unlocked
    if JP.UnitFrames then JP.UnitFrames:SetUnlocked(unlocked) end
    if JP.CastBar then JP.CastBar:SetUnlocked(unlocked) end
    if JP.Convenience then JP.Convenience:SetupKeystoneFrame() end
end

function SettingsHub:Build(_, parent)
    if self.page then return end
    self.page, self.checks = parent, {}
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
        summary:SetWidth(750)
        summary:SetJustifyH("LEFT")
        self.categoryPages[key] = page
        return page
    end

    self.categoryTabs, self.categoryPages = {}, {}
    local automationPage = MakePage("automation", L("АВТОМАТИЗАЦИЯ"),
        L("Задания, приглашения и действия у торговцев"))
    local groupPage = MakePage("groups", L("ГРУППЫ И КЛЮЧИ"),
        L("Приглашения, эпохальные ключи и умный клик"))
    local interfacePage = MakePage("interface", L("ИНТЕРФЕЙС"),
        L("Внешний вид, фреймы и расположение элементов"))
    local lootPage = MakePage("loot", L("ДОБЫЧА"),
        L("Окно добычи, голосования и история предметов"))
    local systemPage = MakePage("system", L("СИСТЕМА"),
        L("Перехват ошибок и диагностический журнал"))

    local function SwitchCategory(key)
        if not self.categoryPages[key] then key = "automation" end
        for name, page in pairs(self.categoryPages) do page:SetShown(name == key) end
        for name, tab in pairs(self.categoryTabs) do tab:SetActive(name == key) end
        MythicBoostDB.settingsCategory = key
    end
    self.SwitchCategory = SwitchCategory

    local tabOrder = {
        { "automation", L("Автоматизация") },
        { "groups", L("Группы и ключи") },
        { "interface", L("Интерфейс") },
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
    self:AddCheck(interfacePage, "hideBags", L("Скрывать панель сумок"), 28, -152, function(value)
        if JP.MinimalUI then JP.MinimalUI:StyleBags(value) end
    end)
    local bagUI = UI.CheckBox(interfacePage, L("Единое окно сумок MythicBoost"),
        MythicBoostDB.bagUI and MythicBoostDB.bagUI.enabled == true, function(value)
            MythicBoostDB.bagUI = type(MythicBoostDB.bagUI) == "table" and MythicBoostDB.bagUI or {}
            MythicBoostDB.bagUI.enabled = value
            JP:ReloadModule("BagUI")
        end)
    bagUI:SetPoint("TOPLEFT", 28, -186)
    bagUI:SetWidth(740)
    bagUI:HookScript("OnEnter", function(self)
        UI.Tooltip(self, L("Единый инвентарь"),
            L("Все надетые сумки в одной сетке: фильтр по сумке, сортировка, занято/всего и деньги."),
            L("Перед включением отключи Bagnon, AdiBags или BetterBags."))
    end)
    bagUI:HookScript("OnLeave", GameTooltip_Hide)
    self.checks.bagUI = bagUI
    local frames = UI.CheckBox(interfacePage, L("Компактные фреймы игрока и цели"),
        MythicBoostDB.unitFrames and MythicBoostDB.unitFrames.enabled ~= false, function(value)
            MythicBoostDB.unitFrames.enabled = value
            JP:ReloadModule("UnitFrames")
        end)
    frames:SetPoint("TOPLEFT", 28, -220)
    frames:SetWidth(740)
    self.checks.unitFrames = frames

    local castBar = UI.CheckBox(interfacePage, L("Кастбар игрока в стиле Quartz"),
        MythicBoostDB.castBar and MythicBoostDB.castBar.enabled ~= false, function(value)
            MythicBoostDB.castBar.enabled = value
            JP:ReloadModule("CastBar")
        end)
    castBar:SetPoint("TOPLEFT", 28, -254)
    castBar:SetWidth(740)
    self.checks.castBar = castBar

    Heading(lootPage, L("ОКНО И ПОЛУЧЕНИЕ"), 28, -84, 764)
    local lootUI = UI.CheckBox(lootPage, L("Встроенное компактное окно добычи"),
        MythicBoostDB.lootUI and MythicBoostDB.lootUI.enabled ~= false, function(value)
            MythicBoostDB.lootUI.enabled = value
            JP:ReloadModule("LootUI")
        end)
    lootUI:SetPoint("TOPLEFT", 28, -118)
    lootUI:SetWidth(740)
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
    lootAtCursor:SetWidth(716)
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
        end)
    lootRolls:SetPoint("TOPLEFT", 52, -186)
    lootRolls:SetWidth(716)
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
    lootHistory:SetWidth(716)
    self.checks.lootHistory = lootHistory

    Heading(interfacePage, L("РАСПОЛОЖЕНИЕ"), 28, -304, 764)
    local interfaceMove = UI.CheckBox(interfacePage, L("Режим перемещения интерфейса"),
        MythicBoostDB.interfaceUnlocked == true, function(value)
            SettingsHub:SetInterfaceUnlocked(value)
        end)
    interfaceMove:SetPoint("TOPLEFT", 28, -338)
    interfaceMove:SetWidth(740)
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
    smartBuff:SetWidth(740)
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
    smartRes:SetWidth(740)
    smartRes:HookScript("OnEnter", function(self)
        UI.Tooltip(self, L("Умный клик: воскрешение"),
            L("В бою — боевое воскрешение, вне боя — обычное. Заклинание выбирает игра в момент клика."),
            L("Аддон ведёт макрос MBSmartClick — привяжи его один раз в клик-касте DandersFrames."),
            JP.SmartClick and JP.SmartClick:Describe() or "")
    end)
    smartRes:HookScript("OnLeave", GameTooltip_Hide)
    self.checks.smartRes = smartRes

    Heading(lootPage, L("ГРУППОВАЯ ДОБЫЧА"), 28, -270, 764)
    local rcLoot = UI.CheckBox(lootPage, L("Отвечать на розыгрыши RCLootCouncil"),
        MythicBoostDB.rcLoot and MythicBoostDB.rcLoot.enabled == true, function(value)
            if JP.RCLootBridge then JP.RCLootBridge:SetEnabled(value) end
        end)
    rcLoot:SetPoint("TOPLEFT", 28, -304)
    rcLoot:SetWidth(740)
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
    local preventErrors = UI.CheckBox(systemPage, L("Не показывать ошибки в игре"),
        not (MythicBoostDB.errorGuard and MythicBoostDB.errorGuard.enabled == false), function(value)
            if JP.ErrorGuard then
                local settings = JP.ErrorGuard:GetSettings()
                if settings then settings.enabled = value end
                if value then JP.ErrorGuard:SuppressBlizzardFrame() end
            end
        end)
    preventErrors:SetPoint("TOPLEFT", 28, -118)
    preventErrors:SetWidth(740)
    preventErrors:HookScript("OnEnter", function(self)
        UI.Tooltip(self, L("Не показывать ошибки в игре"),
            L("Ошибки Lua перехватываются и не показываются на экране: ни окна, ни звука."),
            L("Они не теряются — копятся в журнале со счётчиком повторов и переживают /reload."),
            L("Отключи BugGrabber и BugSack: обработчик ошибок в игре один, и достаётся он тому, кто загрузился последним."))
    end)
    preventErrors:HookScript("OnLeave", GameTooltip_Hide)
    self.checks.preventErrors = preventErrors

    local errorLog = UI.Button(systemPage, L("Открыть журнал ошибок"), 210, 28)
    errorLog:SetPoint("TOPLEFT", 52, -158)
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

    local automationInfo = UI.Text(automationPage, "GameFontHighlightSmall",
        L("Shift временно отключает автоматизацию заданий, продажу и ремонт."), C.muted)
    automationInfo:SetPoint("TOPLEFT", 28, -432)
    automationInfo:SetWidth(740)
    automationInfo:SetJustifyH("LEFT")

    SwitchCategory(MythicBoostDB.settingsCategory or "automation")
end

function SettingsHub:Refresh()
    if not self.page then return end
    local settings = self:GetSettings()
    for key, check in pairs(self.checks or {}) do
        local value
        if key == "minimalUI" then value = MythicBoostDB.minimalUI == true
        elseif key == "unitFrames" then value = MythicBoostDB.unitFrames and MythicBoostDB.unitFrames.enabled ~= false
        elseif key == "castBar" then value = MythicBoostDB.castBar and MythicBoostDB.castBar.enabled ~= false
        elseif key == "lootUI" then value = MythicBoostDB.lootUI and MythicBoostDB.lootUI.enabled ~= false
        elseif key == "lootAtCursor" then value = MythicBoostDB.lootUI and MythicBoostDB.lootUI.atCursor ~= false
        elseif key == "lootRolls" then value = MythicBoostDB.lootUI and MythicBoostDB.lootUI.showRolls ~= false
        elseif key == "lootHistory" then value = MythicBoostDB.lootUI and MythicBoostDB.lootUI.showHistory ~= false
        elseif key == "bagUI" then value = MythicBoostDB.bagUI and MythicBoostDB.bagUI.enabled == true
        elseif key == "interfaceUnlocked" then value = MythicBoostDB.interfaceUnlocked == true
        elseif key == "smartBuff" then
            value = MythicBoostDB.smartClick and MythicBoostDB.smartClick.buff == true
        elseif key == "smartRes" then
            value = MythicBoostDB.smartClick and MythicBoostDB.smartClick.res == true
        elseif key == "keystoneTimer" then
            value = MythicBoostDB.keystoneTimer and MythicBoostDB.keystoneTimer.enabled ~= false
        elseif key == "rcLoot" then
            value = MythicBoostDB.rcLoot and MythicBoostDB.rcLoot.enabled == true
        elseif key == "preventErrors" then
            value = not (MythicBoostDB.errorGuard and MythicBoostDB.errorGuard.enabled == false)
        else value = settings[key] == true end
        check:SetChecked(value)
    end
end

function SettingsHub:Enable() self:GetSettings() end
function SettingsHub:Disable() end
function SettingsHub:Destroy() end

JP.SettingsHub = SettingsHub
JP:RegisterModule("SettingsHub", SettingsHub)
