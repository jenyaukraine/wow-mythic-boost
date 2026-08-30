local _, JP = ...
local ErrorGuard = {}
local UI, C = JP.UI, JP.UI.colors

---------------------------------------------------------------------------
-- Prevent Error in Game
--
-- Замена связки BugGrabber + BugSack внутри аддона. Три задачи, и все три
-- решаются здесь, а не тремя разными аддонами:
--   1. перехватить ошибку Lua раньше, чем её увидит игрок;
--   2. не показывать её на экране и не проигрывать звук;
--   3. сохранить, чтобы потом спокойно разобрать в окне.
--
-- Обработчик ставится на верхнем уровне файла, а не в Create: ошибки летят
-- с первого кадра, в том числе из аддонов, загруженных раньше нашего, и
-- ждать ADDON_LOADED здесь поздно.
---------------------------------------------------------------------------

local MAX_ENTRIES = 100     -- уникальных ошибок в журнале
local MAX_MESSAGE = 1200    -- обрезаем гигантские сообщения
local MAX_STACK = 4000      -- и трейсы: они бывают на сотни строк

-- Журнал до появления SavedVariables. MythicBoostDB создаётся только на
-- ADDON_LOADED, а ошибка может прилететь раньше — тогда она копится здесь
-- и переезжает в базу при первой возможности.
local earlyLog = {}

function ErrorGuard:GetSettings()
    if type(MythicBoostDB) ~= "table" then return nil end
    MythicBoostDB.errorGuard = type(MythicBoostDB.errorGuard) == "table" and MythicBoostDB.errorGuard or {}
    local settings = MythicBoostDB.errorGuard
    if settings.enabled == nil then settings.enabled = true end
    if settings.keepBetweenSessions == nil then settings.keepBetweenSessions = true end
    if settings.muteSound == nil then settings.muteSound = true end
    if type(settings.log) ~= "table" then settings.log = {} end
    return settings
end

function ErrorGuard:IsEnabled()
    local settings = self:GetSettings()
    -- До загрузки базы считаем включённым: пропустить ошибку на экран хуже,
    -- чем лишний раз её проглотить.
    if not settings then return true end
    return settings.enabled == true
end

function ErrorGuard:GetLog()
    local settings = self:GetSettings()
    if not settings then return earlyLog end
    if #earlyLog > 0 then
        -- Переносим всё, что накопилось до загрузки базы, сохраняя порядок.
        for index = #earlyLog, 1, -1 do
            table.insert(settings.log, 1, earlyLog[index])
            earlyLog[index] = nil
        end
    end
    return settings.log
end

---------------------------------------------------------------------------
-- Перехват
---------------------------------------------------------------------------

-- Одна и та же ошибка из OnUpdate прилетает каждый кадр. Ключом берём текст
-- сообщения — он уже содержит файл и строку, поэтому повторы схлопываются в
-- одну запись со счётчиком. Без этого журнал за минуту вырастает до десятков
-- тысяч строк и вешает сохранение переменных при выходе.
local function Signature(message)
    return tostring(message):sub(1, 300)
end

local function Store(message, stack)
    local log = ErrorGuard:GetLog()
    local key = Signature(message)
    local now = time()
    for index = 1, #log do
        local entry = log[index]
        if entry and entry.key == key then
            entry.count = (tonumber(entry.count) or 1) + 1
            entry.last = now
            return
        end
    end
    table.insert(log, 1, {
        key = key,
        message = tostring(message):sub(1, MAX_MESSAGE),
        stack = type(stack) == "string" and stack:sub(1, MAX_STACK) or "",
        count = 1,
        first = now,
        last = now,
    })
    while #log > MAX_ENTRIES do table.remove(log) end
end

local previousHandler = geterrorhandler and geterrorhandler() or nil

-- Обработчик обязан быть непробиваемым. Ошибка внутри обработчика ошибок
-- уходит в него же и уводит клиент в бесконечную рекурсию, поэтому всё тело
-- завёрнуто в pcall, а обращений к тому, чего может не быть, здесь нет.
-- Стек снимаем ПЕРВЫМ делом, до входа в защищённую обёртку. Раньше вызов
-- сидел внутри pcall внутри замыкания, и debugstack отсчитывал уровни от них,
-- а не от места ошибки: первые четыре строки каждого трейса занимали кадры
-- самого ErrorGuard, настоящий стек уезжал вниз и обрезался лимитом в 4000
-- символов. Чинить это одной лишь арифметикой уровней ненадёжно — она разная
-- в зависимости от того, как игра вызвала обработчик, — поэтому подстраховка
-- фильтром по имени файла.
local function CaptureStack()
    local ok, stack = pcall(debugstack, 1, 20, 20)
    if not ok or type(stack) ~= "string" then return "" end
    local kept = {}
    for line in stack:gmatch("[^\n]+") do
        if not line:find("ErrorGuard.lua", 1, true) then kept[#kept + 1] = line end
    end
    -- После вычистки наверху остаются осиротевшие обёртки pcall от самого
    -- обработчика — к месту ошибки они отношения не имеют.
    while kept[1] and (kept[1]:find("in function 'pcall'", 1, true)
        or kept[1]:find("ErrorUtil.lua", 1, true)) do
        table.remove(kept, 1)
    end
    return table.concat(kept, "\n")
end

local function Handler(message)
    local stack = CaptureStack()
    local ok = pcall(function()
        if not ErrorGuard:IsEnabled() then
            if previousHandler then previousHandler(message) end
            return
        end
        Store(message, stack)
        ErrorGuard.dirty = true
    end)
    -- Если даже защищённый разбор упал — молча глотаем. Показать ошибку из
    -- обработчика ошибок нечем, а падать нельзя.
    return ok
end

if type(seterrorhandler) == "function" then seterrorhandler(Handler) end

-- Штатное окно ошибок Blizzard всё равно может всплыть: его показывают и по
-- другим путям, не только через обработчик. Держим закрытым, пока функция
-- включена, но не ломаем — выключил функцию, и окно снова работает.
function ErrorGuard:SuppressBlizzardFrame()
    local frame = _G.ScriptErrorsFrame
    if not frame or frame.__mbErrorGuardHooked then return end
    frame.__mbErrorGuardHooked = true
    frame:HookScript("OnShow", function(owner)
        if ErrorGuard:IsEnabled() and not InCombatLockdown() then owner:Hide() end
    end)
    if self:IsEnabled() and frame:IsShown() then frame:Hide() end
end

---------------------------------------------------------------------------
-- Окно журнала
---------------------------------------------------------------------------

local ROWS, ROW_HEIGHT = 9, 30

local function FormatWhen(stamp)
    stamp = tonumber(stamp)
    if not stamp then return "—" end
    return date("%H:%M:%S", stamp)
end

function ErrorGuard:BuildWindow()
    if self.window then return self.window end

    local frame = CreateFrame("Frame", "MythicBoostErrorGuardFrame", UIParent, "BackdropTemplate")
    frame:SetSize(760, 500)
    frame:SetPoint("CENTER")
    -- The settings hub itself lives on DIALOG. Using the same strata left this
    -- window behind it, so only random labels/dividers bled through the page.
    -- The log is a modal diagnostic surface and must always be fully above it.
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(500)
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnShow", function(owner)
        owner:SetFrameStrata("FULLSCREEN_DIALOG")
        owner:SetFrameLevel(500)
        owner:Raise()
    end)
    UI.Backdrop(frame, C.window, C.surfaceEdge)

    local title = UI.Text(frame, "GameFontNormalLarge", "ОШИБКИ", C.accent)
    title:SetPoint("TOPLEFT", 14, -14)

    frame.summary = UI.Text(frame, "GameFontHighlightSmall", "", C.muted)
    frame.summary:SetPoint("LEFT", title, "RIGHT", 12, 0)
    -- Правый край ограничен кнопкой копирования: без него длинная сводка
    -- («уникальных: 100  всего срабатываний: 12480») наползала бы на неё.
    frame.summary:SetJustifyH("LEFT")
    frame.summary:SetWordWrap(false)

    local close = UI.CloseButton(frame)
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() frame:Hide() end)

    -- Второй экземпляр той же кнопки в шапке. Дубль намеренный: журнал
    -- открывают, чтобы отдать ошибки целиком, и искать кнопку внизу под
    -- девятью строками — лишний шаг в самом частом сценарии.
    local copyTop = UI.Button(frame, "Копировать всё", 150, 22, true)
    copyTop:SetPoint("RIGHT", close, "LEFT", -10, 0)
    copyTop:SetScript("OnClick", function() ErrorGuard:ShowAll() end)
    copyTop:HookScript("OnEnter", function(owner)
        UI.Tooltip(owner, "Копировать всё",
            "Собирает ВЕСЬ журнал — все ошибки с трейсами, а не выбранную строку.",
            "Текст ложится в нижнее поле и выделяется целиком: дальше Ctrl+C.",
            "Буфер обмена аддонам недоступен, выделить может только игрок.")
    end)
    copyTop:HookScript("OnLeave", GameTooltip_Hide)
    frame.summary:SetPoint("RIGHT", copyTop, "LEFT", -10, 0)

    local divider = UI.Line(frame, C.lineSoft)
    divider:SetPoint("TOPLEFT", 12, -40)
    divider:SetPoint("TOPRIGHT", -12, -40)

    -- Список слева, полный текст снизу: щёлкнул строку — увидел трейс.
    frame.rows = {}
    for index = 1, ROWS do
        local row = CreateFrame("Button", nil, frame, "BackdropTemplate")
        row:SetHeight(ROW_HEIGHT - 3)
        row:SetPoint("TOPLEFT", 12, -48 - (index - 1) * ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", -12, -48 - (index - 1) * ROW_HEIGHT)
        UI.Backdrop(row, index % 2 == 0 and C.rowAlt or C.row, C.lineSoft)

        row.count = UI.Text(row, "GameFontNormalSmall", "", C.amber)
        row.count:SetPoint("LEFT", 8, 0)
        row.count:SetWidth(46)
        row.count:SetJustifyH("CENTER")

        row.when = UI.Text(row, "GameFontHighlightSmall", "", C.faint)
        row.when:SetPoint("LEFT", 58, 0)
        row.when:SetWidth(62)
        row.when:SetJustifyH("LEFT")

        row.text = UI.Text(row, "GameFontHighlightSmall", "", C.text)
        row.text:SetPoint("LEFT", 126, 0)
        row.text:SetPoint("RIGHT", -8, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)

        row:SetScript("OnEnter", function(owner)
            owner:SetBackdropColor(UI.Unpack(C.rowHover))
        end)
        row:SetScript("OnLeave", function(owner)
            owner:SetBackdropColor(UI.Unpack(owner.index and owner.index % 2 == 0 and C.rowAlt or C.row))
        end)
        row:SetScript("OnClick", function(owner)
            if owner.entry then ErrorGuard:ShowDetail(owner.entry) end
        end)
        row.index = index
        frame.rows[index] = row
    end

    -- Текст трейса кладём в EditBox, а не в FontString: из него можно выделить
    -- и скопировать через Ctrl+C, а именно это и нужно, чтобы отдать ошибку
    -- автору аддона.
    local detail = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    detail:SetPoint("TOPLEFT", 12, -48 - ROWS * ROW_HEIGHT - 8)
    detail:SetPoint("BOTTOMRIGHT", -12, 46)
    UI.Backdrop(detail, C.field, C.lineSoft)

    local scroll = CreateFrame("ScrollFrame", "MythicBoostErrorGuardScroll", detail, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)

    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetWidth(680)
    box:SetScript("OnEscapePressed", function(owner) owner:ClearFocus() end)
    scroll:SetScrollChild(box)
    frame.detailBox = box

    local copyAll = UI.Button(frame, "Копировать всё", 150, 24, true)
    copyAll:SetPoint("BOTTOMLEFT", 12, 12)
    copyAll:SetScript("OnClick", function()
        ErrorGuard:ShowAll()
    end)
    copyAll:HookScript("OnEnter", function(owner)
        UI.Tooltip(owner, "Копировать всё",
            "Собирает весь журнал в нижнее поле и выделяет его целиком.",
            "Дальше жми Ctrl+C — буфер обмена аддонам недоступен, выделить текст может только игрок.")
    end)
    copyAll:HookScript("OnLeave", GameTooltip_Hide)

    local clear = UI.Button(frame, "Очистить", 120, 24)
    clear:SetPoint("LEFT", copyAll, "RIGHT", 8, 0)
    clear:SetScript("OnClick", function()
        ErrorGuard:Clear()
    end)

    local copyHint = UI.Text(frame, "GameFontHighlightSmall",
        "Щёлкни строку — внизу появится полный трейс. Выдели и Ctrl+C, чтобы скопировать.", C.faint)
    copyHint:SetPoint("LEFT", clear, "RIGHT", 12, 0)

    frame:Hide()
    tinsert(UISpecialFrames, "MythicBoostErrorGuardFrame")
    self.window = frame
    return frame
end

function ErrorGuard:ShowDetail(entry)
    if not self.window or type(entry) ~= "table" then return end
    local parts = {
        entry.message or "",
        "",
        ("Повторов: %d    Впервые: %s    Последний раз: %s"):format(
            tonumber(entry.count) or 1, FormatWhen(entry.first), FormatWhen(entry.last)),
        "",
        entry.stack or "",
    }
    self.window.detailBox:SetText(table.concat(parts, "\n"))
    self.window.detailBox:SetCursorPosition(0)
end

-- Весь журнал одним текстом. Положить его прямо в буфер обмена аддон не может
-- — такого API в игре нет вовсе, — поэтому делаем единственное, что разрешено:
-- собираем текст, кладём в поле и выделяем целиком. Игроку остаётся Ctrl+C.
function ErrorGuard:ShowAll()
    if not self.window then return end
    local log = self:GetLog()
    if #log == 0 then
        self.window.detailBox:SetText("Журнал пуст.")
        return
    end
    local out = {
        ("MythicBoost %s — журнал ошибок, %s"):format(JP:GetVersion(), date("%Y-%m-%d %H:%M:%S")),
        ("уникальных: %d"):format(#log),
        "",
    }
    for index, entry in ipairs(log) do
        out[#out + 1] = ("=== %d/%d   повторов: %d   впервые: %s   последний раз: %s ==="):format(
            index, #log, tonumber(entry.count) or 1, FormatWhen(entry.first), FormatWhen(entry.last))
        out[#out + 1] = entry.message or ""
        if entry.stack and entry.stack ~= "" then
            out[#out + 1] = entry.stack
        end
        out[#out + 1] = ""
    end
    local box = self.window.detailBox
    box:SetText(table.concat(out, "\n"))
    box:SetCursorPosition(0)
    box:SetFocus()
    box:HighlightText()
end

function ErrorGuard:Refresh()
    local frame = self.window
    if not frame or not frame:IsShown() then return end
    local log = self:GetLog()
    local total = 0
    for _, entry in ipairs(log) do total = total + (tonumber(entry.count) or 1) end
    frame.summary:SetFormattedText("уникальных: %d    всего срабатываний: %d", #log, total)

    for index, row in ipairs(frame.rows) do
        local entry = log[index]
        if entry then
            row.entry = entry
            row.count:SetText(tostring(tonumber(entry.count) or 1))
            row.when:SetText(FormatWhen(entry.last))
            -- В список кладём только первую строку: трейс уедет в нижнее поле.
            local firstLine = tostring(entry.message or ""):match("^[^\n]*") or ""
            row.text:SetText(firstLine)
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end
end

function ErrorGuard:Toggle()
    local frame = self:BuildWindow()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        self:Refresh()
    end
end

function ErrorGuard:Clear()
    local settings = self:GetSettings()
    if settings then wipe(settings.log) end
    wipe(earlyLog)
    if self.window then
        self.window.detailBox:SetText("")
        self:Refresh()
    end
    JP:Print("Журнал ошибок очищен.")
end

function ErrorGuard:Count()
    local log = self:GetLog()
    local total = 0
    for _, entry in ipairs(log) do total = total + (tonumber(entry.count) or 1) end
    return #log, total
end

---------------------------------------------------------------------------
-- Жизненный цикл
---------------------------------------------------------------------------

function ErrorGuard:Create()
    self:SuppressBlizzardFrame()

    -- Окно перерисовываем не на каждую ошибку, а раз в секунду: при буре из
    -- OnUpdate перерисовка на каждое срабатывание была бы дороже самой ошибки.
    if not self.ticker and C_Timer then
        self.ticker = C_Timer.NewTicker(1, function()
            if ErrorGuard.dirty then
                ErrorGuard.dirty = false
                ErrorGuard:Refresh()
            end
        end)
    end

    if not self.loader then
        self.loader = CreateFrame("Frame")
        self.loader:RegisterEvent("ADDON_LOADED")
        self.loader:SetScript("OnEvent", function()
            ErrorGuard:SuppressBlizzardFrame()
            local settings = ErrorGuard:GetSettings()
            -- Журнал прошлой сессии стирается здесь, а не при выходе: на
            -- выходе SavedVariables уже пишутся, и трогать их поздно.
            if settings and settings.keepBetweenSessions == false then wipe(settings.log) end
        end)
    end
end

function ErrorGuard:Enable()
    -- Чужие ловцы ошибок ставят свой обработчик тем же seterrorhandler, и
    -- побеждает тот, кто вызвал его последним. Одновременно с BugGrabber
    -- работать нельзя — предупреждаем прямо, а не оставляем гадать.
    local function Loaded(name)
        if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
            local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, name)
            return ok and loaded == true
        end
        return type(IsAddOnLoaded) == "function" and IsAddOnLoaded(name) == true
    end
    local conflicts = {}
    for _, name in ipairs({ "!BugGrabber", "BugGrabber", "BugSack", "Swatter" }) do
        if Loaded(name) then conflicts[#conflicts + 1] = name end
    end
    if #conflicts > 0 then
        JP:Print("Перехват ошибок делит место с: " .. table.concat(conflicts, ", ") ..
            ". Отключи их, иначе кто последним загрузился — тот и ловит.")
    end
end

function ErrorGuard:Disable() if self.window then self.window:Hide() end end
function ErrorGuard:Destroy() if self.window then self.window:Hide() end end

JP.ErrorGuard = ErrorGuard
JP:RegisterModule("ErrorGuard", ErrorGuard)
