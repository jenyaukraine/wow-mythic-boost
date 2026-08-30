local addonName, JP = ...

JP.name = addonName
JP.modules, JP.pendingReloads = {}, {}
JP.positivePlayers = {}

local DB_VERSION = 5
local SCANNED_TTL = 30 * 24 * 60 * 60   -- запись об игроке живёт месяц
local SCANNED_LIMIT = 300               -- и база не растёт бесконечно

-- Midnight помечает часть данных как secret. На клиентах без этого API
-- подставляем заглушку, чтобы модули могли звать проверку без условий.
if type(issecretvalue) ~= "function" then
    issecretvalue = function() return false end
end

local function UsableNumber(value)
    return type(value) == "number" and not issecretvalue(value)
end

function JP:GetVersion()
    if self.version then return self.version end
    self.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version")) or "1.0.0"
    return self.version
end

function JP:Print(message)
    local frame = DEFAULT_CHAT_FRAME
    if not frame then return end
    frame:AddMessage("|cff28b8f5MythicBoost|r  " .. tostring(message))
end

---------------------------------------------------------------------------
-- Журнал
--
-- Кольцевой буфер в памяти: включается по требованию, ничего не пишет в
-- SavedVariables и нужен, чтобы разбирать жалобы вида «не находит группы»
-- не гадая, а по фактам от API.
---------------------------------------------------------------------------

local LOG_LIMIT = 200
JP.log = {}

function JP:IsLogging()
    return MythicBoostDB and MythicBoostDB.logging == true
end

function JP:Log(message, ...)
    if not self:IsLogging() then return end
    local ok, line = pcall(string.format, message, ...)
    self.log[#self.log + 1] = ("|cff5b6470%s|r  %s"):format(date("%H:%M:%S"), ok and line or tostring(message))
    if #self.log > LOG_LIMIT then table.remove(self.log, 1) end
end

---------------------------------------------------------------------------
-- Личные рекорды по подземельям
--
-- Raider.IO обновляет профиль не мгновенно, а API сезона иногда молчит
-- сразу после сдачи ключа. Держим собственный кэш максимумов и берём
-- наибольшее из трёх источников.
---------------------------------------------------------------------------

local function ApiBestLevel(mapID)
    if not mapID or not C_MythicPlus or not C_MythicPlus.GetSeasonBestForMap then return 0 end
    local inTimeInfo, overtimeInfo = C_MythicPlus.GetSeasonBestForMap(mapID)
    local inTimeLevel = inTimeInfo and UsableNumber(inTimeInfo.level) and inTimeInfo.level or 0
    local overtimeLevel = overtimeInfo and UsableNumber(overtimeInfo.level) and overtimeInfo.level or 0
    return math.max(inTimeLevel, overtimeLevel)
end

function JP:SetLocalBest(mapID, level)
    if not UsableNumber(mapID) or not UsableNumber(level) or level <= 0 then return false end
    MythicBoostDB.localBests = MythicBoostDB.localBests or {}
    local previous = tonumber(MythicBoostDB.localBests[mapID]) or 0
    if level <= previous then return false end
    MythicBoostDB.localBests[mapID] = level
    return true
end

function JP:GetBestLevel(mapID, fallback)
    MythicBoostDB.localBests = MythicBoostDB.localBests or {}
    local cached = tonumber(MythicBoostDB.localBests[mapID]) or 0
    local best = math.max(cached, ApiBestLevel(mapID), UsableNumber(fallback) and fallback or 0)
    if best > cached and UsableNumber(mapID) then MythicBoostDB.localBests[mapID] = best end
    return best
end

-- Рекорды копятся в базе и сами по себе не устаревают. При смене сезона все
-- результаты обнуляются на стороне игры, а у нас оставались прошлогодние —
-- и режим «только повышающие рейтинг» переставал находить хоть что-то.
local function DropStaleSeason()
    if not C_MythicPlus or type(C_MythicPlus.GetCurrentSeason) ~= "function" then return end
    local ok, season = pcall(C_MythicPlus.GetCurrentSeason)
    if not ok or not UsableNumber(season) or season <= 0 then return end
    if MythicBoostDB.localBestsSeason ~= season then
        if MythicBoostDB.localBestsSeason ~= nil then
            wipe(MythicBoostDB.localBests)
            JP:Print("Начался новый сезон — личные рекорды подземелий сброшены.")
        end
        MythicBoostDB.localBestsSeason = season
    end
end

function JP:RefreshLocalBests(requestInfo)
    DropStaleSeason()
    if requestInfo and C_MythicPlus and C_MythicPlus.RequestMapInfo then C_MythicPlus.RequestMapInfo() end
    for _, mapID in ipairs(C_ChallengeMode.GetMapTable and C_ChallengeMode.GetMapTable() or {}) do
        local best = ApiBestLevel(mapID)
        if best > 0 then self:SetLocalBest(mapID, best) end
    end
    self:RequestRefresh()
end

---------------------------------------------------------------------------
-- Перспективные игроки
---------------------------------------------------------------------------

local function PlayerKeys(fullName)
    if type(fullName) ~= "string" or issecretvalue(fullName) then return end
    local normalized = fullName:lower()
    if normalized == "" then return end
    return normalized, normalized:match("^([^-]+)")
end

local function StorePlayer(fullName, data)
    local full = PlayerKeys(fullName)
    if not full then return end
    MythicBoostDB.scannedPlayers = MythicBoostDB.scannedPlayers or {}
    data.name = fullName
    data.lastSeen = time()
    MythicBoostDB.scannedPlayers[full] = data
end

function JP:MarkPositivePlayer(fullName, data, saveRecent)
    local full, short = PlayerKeys(fullName)
    if not full then return end
    self.positivePlayers[full] = data or true
    if short then self.positivePlayers[short] = data or true end
    if saveRecent and type(data) == "table" then StorePlayer(fullName, data) end
    local marker = self.modules.NameplateMarker
    if marker and marker.RefreshAll then marker:RefreshAll() end
    self:RequestRefresh()
end

function JP:GetPositivePlayer(fullName)
    local full, short = PlayerKeys(fullName)
    if not full then return end
    return self.positivePlayers[full] or (short and self.positivePlayers[short])
end

function JP:TouchPositivePlayer(fullName, data)
    if type(data) == "table" then StorePlayer(fullName, data) end
end

-- Чистим просроченные записи и держим базу в разумном размере,
-- иначе SavedVariables растут от сессии к сессии без предела.
local function PruneScannedPlayers()
    local scanned = MythicBoostDB.scannedPlayers
    if type(scanned) ~= "table" then MythicBoostDB.scannedPlayers = {}; return 0 end
    local now, kept = time(), {}
    for key, data in pairs(scanned) do
        if type(data) == "table" and type(data.name) == "string" then
            local seen = tonumber(data.lastSeen) or 0
            if now - seen < SCANNED_TTL then kept[#kept + 1] = { key = key, data = data, seen = seen } end
        end
    end
    table.sort(kept, function(a, b) return a.seen > b.seen end)
    local fresh, total = {}, math.min(#kept, SCANNED_LIMIT)
    for index = 1, total do fresh[kept[index].key] = kept[index].data end
    MythicBoostDB.scannedPlayers = fresh
    return total
end

-- Метки на нейтплейтах должны переживать /reload, поэтому поднимаем
-- сохранённых игроков обратно в рабочую таблицу при входе.
local function RestorePositivePlayers()
    for key, data in pairs(MythicBoostDB.scannedPlayers) do
        JP.positivePlayers[key] = data
        local short = key:match("^([^-]+)")
        if short then JP.positivePlayers[short] = data end
    end
end

---------------------------------------------------------------------------
-- Модули
---------------------------------------------------------------------------

local function SafeCall(module, methodName)
    local method = module[methodName]
    if type(method) ~= "function" then return true end
    local function ErrorHandler(err)
        local message = tostring(err or "неизвестная ошибка")
        local handler = type(CallErrorHandler) == "function" and CallErrorHandler
            or (type(geterrorhandler) == "function" and geterrorhandler())
        if type(handler) == "function" then pcall(handler, message) end
        -- xpcall возвращает именно результат error handler. Blizzard
        -- CallErrorHandler возвращает nil, поэтому сохраняем текст сами.
        return message
    end
    local ok, err = xpcall(method, ErrorHandler, module)
    if not ok then JP:Print(("|cffff6b6bОшибка|r %s в модуле %s: %s"):format(methodName, module.name, tostring(err))) end
    return ok
end

function JP:RegisterModule(name, module)
    assert(type(name) == "string" and name ~= "" and type(module) == "table")
    assert(not self.modules[name], "MythicBoost module already exists: " .. name)
    module.name, module.addon = name, self
    self.modules[name] = module
end

function JP:FindModule(name)
    if type(name) ~= "string" or name == "" then return end
    if self.modules[name] then return self.modules[name], name end
    local lowered = name:lower()
    for moduleName, module in pairs(self.modules) do
        if moduleName:lower() == lowered then return module, moduleName end
    end
end

function JP:EnableModule(name)
    local module = self.modules[name]
    if not module then return false, "модуль не найден" end
    if module.enabled then return true end
    if not SafeCall(module, "Create") then return false, "ошибка Create" end
    if not SafeCall(module, "Enable") then return false, "ошибка Enable" end
    module.enabled = true
    return true
end

function JP:ReloadModule(inputName)
    local module, name = self:FindModule(inputName)
    if not module then
        self:Print(("Модуль «%s» не найден. Список: /mb modules"):format(tostring(inputName)))
        return
    end
    if InCombatLockdown() then
        self.pendingReloads[name] = true
        self:Print(name .. " будет пересобран после боя.")
        return
    end
    SafeCall(module, "Disable"); SafeCall(module, "Destroy"); module.enabled = false
    local ok, reason = self:EnableModule(name)
    self:Print(ok and (name .. " пересобран.") or ("Не удалось пересобрать " .. name .. ": " .. reason))
end

function JP:ListModules()
    local names = {}
    for name, module in pairs(self.modules) do
        names[#names + 1] = (module.enabled and "|cff43d17a" or "|cff8a8f98") .. name .. "|r"
    end
    table.sort(names)
    self:Print("Модули: " .. table.concat(names, ", "))
end

-- Общая точка обновления окна. События LFG приходят пачками, а перерисовка
-- стоит полного пересчёта списка групп, поэтому склеиваем вызовы в один.
function JP:RequestRefresh(delay)
    local welcome = self.modules.Welcome
    if not welcome or not welcome.frame or not welcome.frame:IsShown() then return end
    self.refreshRevision = (self.refreshRevision or 0) + 1
    local revision = self.refreshRevision
    C_Timer.After(delay or .12, function()
        if self.refreshRevision ~= revision then return end
        if welcome.frame and welcome.frame:IsShown() then welcome:Refresh() end
    end)
end

---------------------------------------------------------------------------
-- Загрузка
---------------------------------------------------------------------------

local function InitializeDatabase()
    MythicBoostDB = type(MythicBoostDB) == "table" and MythicBoostDB or {}
    local db = MythicBoostDB
    db.dbVersion = DB_VERSION
    db.scannedPlayers = type(db.scannedPlayers) == "table" and db.scannedPlayers or {}
    db.groupFilters = type(db.groupFilters) == "table" and db.groupFilters or {}
    db.localBests = type(db.localBests) == "table" and db.localBests or {}
    db.autoMatch = type(db.autoMatch) == "table" and db.autoMatch or { requireTank = true }
    db.window = type(db.window) == "table" and db.window or {}
    if db.minimumKeystoneRuns ~= nil and not tonumber(db.minimumKeystoneRuns) then db.minimumKeystoneRuns = nil end
    if db.filterGroupFinder == nil then db.filterGroupFinder = true end
    if db.logging == nil then db.logging = false end
    -- Старый режим захвата штатной кнопки удалён: MythicBoost теперь
    -- открывается только своей кнопкой внутри Blizzard Group Finder.
    db.replaceGroupFinder = false
    if db.minimalUI == nil then db.minimalUI = false end
    db.convenience = type(db.convenience) == "table" and db.convenience or {}
    if db.convenience.hideBags == nil then db.convenience.hideBags = true end
    db.unitFrames = type(db.unitFrames) == "table" and db.unitFrames or {}
    if db.unitFrames.enabled == nil then db.unitFrames.enabled = true end
    if db.unitFrames.hideBlizzard == nil then db.unitFrames.hideBlizzard = true end
    db.castBar = type(db.castBar) == "table" and db.castBar or {}
    if db.castBar.enabled == nil then db.castBar.enabled = true end
    db.lootUI = type(db.lootUI) == "table" and db.lootUI or {}
    if db.lootUI.enabled == nil then db.lootUI.enabled = true end
    if db.lootUI.atCursor == nil then db.lootUI.atCursor = true end
    if db.lootUI.showRolls == nil then db.lootUI.showRolls = true end
    if db.lootUI.showHistory == nil then db.lootUI.showHistory = true end
    -- Начиная с версии БД 3 все перемещаемые элементы используют один режим.
    -- При первом запуске после обновления сохраняем прежнее разблокированное
    -- состояние, но больше не держим три независимых переключателя.
    if db.interfaceUnlocked == nil then
        db.interfaceUnlocked = db.unitFrames.unlocked == true or db.castBar.unlocked == true
    end
    db.interfaceUnlocked = db.interfaceUnlocked == true
    db.unitFrames.unlocked = db.interfaceUnlocked
    db.castBar.unlocked = db.interfaceUnlocked
    db.convenience.movableKeystoneFrame = db.interfaceUnlocked
    JP.db = db
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("CHALLENGE_MODE_COMPLETED")
events:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        InitializeDatabase()
        PruneScannedPlayers()
        RestorePositivePlayers()
        for name in pairs(JP.modules) do JP:EnableModule(name) end
        C_Timer.After(.5, function() JP:RefreshLocalBests(true) end)
    elseif event == "PLAYER_REGEN_ENABLED" then
        local pending = JP.pendingReloads
        JP.pendingReloads = {}
        for name in pairs(pending) do JP:ReloadModule(name) end
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        local mapID = C_ChallengeMode.GetActiveChallengeMapID and C_ChallengeMode.GetActiveChallengeMapID()
        local level = C_ChallengeMode.GetActiveKeystoneInfo and C_ChallengeMode.GetActiveKeystoneInfo()
        if mapID and level then JP:SetLocalBest(mapID, level) end
        for _, delay in ipairs({ 1, 4, 9 }) do C_Timer.After(delay, function() JP:RefreshLocalBests(true) end) end
    elseif event == "CHALLENGE_MODE_MAPS_UPDATE" then
        JP:RefreshLocalBests()
    end
end)

---------------------------------------------------------------------------
-- Команды
---------------------------------------------------------------------------

local function ToggleWindow()
    local welcome = JP.modules.Welcome
    if welcome and welcome.Toggle then welcome:Toggle() end
end

function MythicBoost_OnAddonCompartmentClick()
    ToggleWindow()
end

-- Диагностика: показывает, что реально отдаёт API по первым результатам.
-- Уровень ключа в Midnight может приходить защищённым значением, и тогда
-- колонка «Ключ» пустует — эта команда отвечает почему за пару секунд.
-- Полный снимок того, что отдаёт API поиска групп.
--
-- Уровень ключа нигде не задокументирован как поле, а в Midnight часть
-- значений приходит защищёнными. Вместо перебора догадок один раз
-- записываем реальную структуру в SavedVariables: после /reload её видно
-- на диске целиком, вместе с типами и признаком secret.
local function DescribeValue(value)
    local record = {}
    local ok, result = pcall(type, value)
    record.type = ok and result or "?"
    ok, result = pcall(issecretvalue, value)
    record.secret = ok and result or "?"
    ok, result = pcall(tostring, value)
    record.text = ok and tostring(result):sub(1, 200) or "<нечитаемо>"
    return record
end

local function DescribeTable(source, depth)
    if type(source) ~= "table" then return DescribeValue(source) end
    local out = {}
    local ok = pcall(function()
        for key, value in pairs(source) do
            local name = tostring(key)
            if type(value) == "table" and (depth or 1) < 2 then
                out[name] = DescribeTable(value, (depth or 1) + 1)
            else
                out[name] = DescribeValue(value)
            end
        end
    end)
    if not ok then out.__error = "pairs() упал на защищённом значении" end
    return out
end

local function DumpSearchResults()
    local _, resultIDs = C_LFGList.GetSearchResults()
    if type(resultIDs) ~= "table" or #resultIDs == 0 then
        JP:Print("Результатов поиска нет — сначала нажми «Обновить» в окне.")
        return
    end

    local snapshot = {
        version = JP:GetVersion(),
        captured = date("%Y-%m-%d %H:%M:%S"),
        totalResults = #resultIDs,
        results = {},
    }

    for index = 1, math.min(5, #resultIDs) do
        local resultID = resultIDs[index]
        local info = C_LFGList.GetSearchResultInfo(resultID)
        local entry = { searchResultInfo = DescribeTable(info) }

        local activityID = info and (type(info.activityIDs) == "table" and info.activityIDs[1] or info.activityID)
        entry.activityID = DescribeValue(activityID)
        if activityID then
            entry.activityInfo = DescribeTable(C_LFGList.GetActivityInfoTable(activityID))
            if C_LFGList.GetKeystoneForActivity then
                local ok, level = pcall(C_LFGList.GetKeystoneForActivity, activityID)
                entry.keystoneForActivity = ok and DescribeValue(level) or { type = "error" }
            end
        end
        if C_LFGList.GetSearchResultMemberCounts then
            local ok, counts = pcall(C_LFGList.GetSearchResultMemberCounts, resultID)
            entry.memberCounts = ok and DescribeTable(counts) or { __error = "недоступно" }
        end
        snapshot.results[index] = entry
    end

    MythicBoostDB.diagnostics = snapshot
    JP:Print(("Снимок %d результатов сохранён. Выполни |cff28b8f5/reload|r — после него структуру видно в SavedVariables."):format(#snapshot.results))

    -- Заодно сразу показываем главное в чат, чтобы не ждать перезагрузки.
    local first = snapshot.results[1] and snapshot.results[1].searchResultInfo
    if type(first) == "table" then
        local shown = 0
        for key, record in pairs(first) do
            if type(record) == "table" and record.type and shown < 12 then
                shown = shown + 1
                JP:Print(("  %s: %s%s = %s"):format(key, record.type,
                    record.secret == true and " |cffff6b6b(secret)|r" or "", record.text))
            end
        end
    end
end

local function ShowHelp()
    JP:Print("версия " .. JP:GetVersion())
    JP:Print("|cff28b8f5/mb|r — открыть или закрыть окно")
    JP:Print("|cff28b8f5/mb filter|r — открыть безопасные фильтры MythicBoost")
    JP:Print("|cff28b8f5/mb players|r — сколько перспективных игроков сохранено")
    JP:Print("|cff28b8f5/mb clear|r — очистить базу игроков")
    JP:Print("|cff28b8f5/mb modules|r — список модулей")
    JP:Print("|cff28b8f5/mb reload|r [модуль] — перезагрузить интерфейс или один модуль")
    JP:Print("|cff28b8f5/mb smartclick|r — разбор умного клика: заклинания, кнопки, атрибуты")
    JP:Print("|cff28b8f5/mb errors|r — журнал перехваченных ошибок (clear — очистить)")
    JP:Print("|cff28b8f5/mb debug|r — снимок структуры от API поиска групп")
    JP:Print("|cff28b8f5/mb log|r [on|off|clear] — журнал последних событий")
    JP:Print("|cff28b8f5/mb restorefilter|r — вернуть фильтр стандартного окна групп")
    JP:Print("|cff28b8f5/mb replace|r — открывать своё окно вместо штатного поиска групп")
    JP:Print("|cff28b8f5/mb frames|r [reset] — свои фреймы игрока и цели, reset — сбросить позиции")
end

SLASH_MYTHICBOOST1 = "/mythicboost"
SLASH_MYTHICBOOST2 = "/mb"
SlashCmdList.MYTHICBOOST = function(input)
    local command, argument = tostring(input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()
    if command == "" or command == "open" or command == "toggle" then
        ToggleWindow()
    elseif command == "reload" then
        if argument == "" then ReloadUI() else JP:ReloadModule(argument) end
    elseif command == "modules" or command == "list" then
        JP:ListModules()
    elseif command == "filter" then
        MythicBoostDB.filterGroupFinder = false
        JP:Print("Фильтры работают в окне MythicBoost. Штатный список Blizzard не изменяется: в Midnight это вызывает secret-taint.")
        ToggleWindow()
    elseif command == "smartclick" or command == "click" then
        if JP.SmartClick then JP.SmartClick:Diagnose() else JP:Print("Модуль SmartClick не загружен.") end
    elseif command == "errors" or command == "error" then
        if JP.ErrorGuard then
            if argument == "clear" then
                JP.ErrorGuard:Clear()
            else
                local unique, total = JP.ErrorGuard:Count()
                JP:Print(("Ошибок в журнале: %d (срабатываний %d)"):format(unique, total))
                JP.ErrorGuard:Toggle()
            end
        end
    elseif command == "players" then
        JP:Print(("Сохранено перспективных игроков: %d"):format(PruneScannedPlayers()))
    elseif command == "clear" then
        wipe(MythicBoostDB.scannedPlayers)
        wipe(JP.positivePlayers)
        local marker = JP.modules.NameplateMarker
        if marker and marker.RefreshAll then marker:RefreshAll() end
        JP:Print("База перспективных игроков очищена.")
    elseif command == "replace" then
        if JP.FrameSwitch then
            JP.FrameSwitch:SetReplacing(false)
        end
    elseif command == "restorefilter" then
        local backup = MythicBoostDB.blizzardFilterBackup
        if type(backup) == "table" and type(C_LFGList.SaveAdvancedFilter) == "function" then
            local ok = pcall(C_LFGList.SaveAdvancedFilter, backup)
            JP:Print(ok and "Фильтр стандартного окна групп возвращён к исходному."
                or "Не удалось вернуть фильтр — попробуй вне боя.")
        else
            JP:Print("Сохранённого фильтра нет: MythicBoost его ещё не менял.")
        end
    elseif command == "debug" or command == "dump" then
        DumpSearchResults()
    elseif command == "log" then
        local mode = argument:lower()
        if mode == "on" or mode == "off" then
            MythicBoostDB.logging = mode == "on"
            JP:Print("Журнал " .. (MythicBoostDB.logging and "|cff43d17aвключён|r" or "|cffff9966выключен|r") .. ".")
        elseif mode == "clear" then
            wipe(JP.log)
            JP:Print("Журнал очищен.")
        elseif #JP.log == 0 then
            JP:Print(JP:IsLogging() and "Журнал пуст." or "Журнал выключен. Включить: /mb log on")
        else
            JP:Print(("Последние записи (%d):"):format(#JP.log))
            for index = math.max(1, #JP.log - 19), #JP.log do JP:Print("  " .. JP.log[index]) end
        end
    elseif command == "frames" then
        local settings = MythicBoostDB.unitFrames
        if argument:lower() == "reset" then
            settings.player, settings.target = nil, nil
            if JP.UnitFrames and JP.UnitFrames.ResetPositions then JP.UnitFrames:ResetPositions() end
            JP:Print("Позиции фреймов игрока и цели сброшены.")
        else
            settings.enabled = not settings.enabled
            JP:Print("Свои фреймы: " .. (settings.enabled and "|cff43d17aвключены|r" or "|cffff9966выключены|r"))
        end
        JP:ReloadModule("UnitFrames")
    else
        ShowHelp()
    end
end
