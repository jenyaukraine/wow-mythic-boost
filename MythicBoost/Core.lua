local addonName, JP = ...

local L = JP.L
JP.name = addonName
JP.modules, JP.pendingReloads = {}, {}
JP.positivePlayers = {}
JP.positivePlayerOrder = {}

local DB_VERSION = JP.Contracts.DATABASE_VERSION
local SCANNED_TTL = JP.Limits.SCANNED_PLAYER_TTL
local SCANNED_LIMIT = JP.Limits.SCANNED_PLAYERS

function JP.Settings(section, defaults)
    if type(MythicBoostDB) ~= "table" then return nil end
    MythicBoostDB[section] = type(MythicBoostDB[section]) == "table" and MythicBoostDB[section] or {}
    local settings = MythicBoostDB[section]
    if defaults then
        for key, value in pairs(defaults) do
            if settings[key] == nil then settings[key] = value end
        end
    end
    return settings
end

local UsableNumber = JP.UsableNumber

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

local LOG_LIMIT = JP.Limits.LOG_ENTRIES
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
            JP:Print(L("Начался новый сезон — личные рекорды подземелий сброшены."))
        end
        MythicBoostDB.localBestsSeason = season
    end
end

function JP:RefreshLocalBests(requestInfo)
    DropStaleSeason()
    if requestInfo and C_MythicPlus and C_MythicPlus.RequestMapInfo then C_MythicPlus.RequestMapInfo() end
    for _, mapID in ipairs(JP.API.GetChallengeMapIDs()) do
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
    local total, oldestKey, oldestSeen = 0, nil, math.huge
    for key, record in pairs(MythicBoostDB.scannedPlayers) do
        total = total + 1
        local seen = type(record) == "table" and tonumber(record.lastSeen) or 0
        if seen < oldestSeen then oldestKey, oldestSeen = key, seen end
    end
    if total > SCANNED_LIMIT and oldestKey then
        local removed = MythicBoostDB.scannedPlayers[oldestKey]
        MythicBoostDB.scannedPlayers[oldestKey] = nil
        if JP.positivePlayers[oldestKey] == removed then JP.positivePlayers[oldestKey] = nil end
        local short = oldestKey:match("^([^-]+)")
        if short and JP.positivePlayers[short] == removed then JP.positivePlayers[short] = nil end
    end
end

function JP:MarkPositivePlayer(fullName, data, saveRecent)
    local full, short = PlayerKeys(fullName)
    if not full then return end
    local isNew = self.positivePlayers[full] == nil
    self.positivePlayers[full] = data or true
    if short then self.positivePlayers[short] = data or true end
    if isNew then
        self.positivePlayerOrder[#self.positivePlayerOrder + 1] = { key = full, short = short }
        while #self.positivePlayerOrder > SCANNED_LIMIT do
            local old = table.remove(self.positivePlayerOrder, 1)
            local removed = self.positivePlayers[old.key]
            self.positivePlayers[old.key] = nil
            if old.short and self.positivePlayers[old.short] == removed then self.positivePlayers[old.short] = nil end
        end
    end
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
        JP.positivePlayerOrder[#JP.positivePlayerOrder + 1] = { key = key, short = short }
    end
end

---------------------------------------------------------------------------
-- Модули
---------------------------------------------------------------------------

local function SafeCall(module, methodName)
    local method = module[methodName]
    if type(method) ~= "function" then return true end
    local function ErrorHandler(err)
        local message = tostring(err or L("неизвестная ошибка"))
        local handler = type(CallErrorHandler) == "function" and CallErrorHandler
            or (type(geterrorhandler) == "function" and geterrorhandler())
        if type(handler) == "function" then pcall(handler, message) end
        -- xpcall возвращает именно результат error handler. Blizzard
        -- CallErrorHandler возвращает nil, поэтому сохраняем текст сами.
        return message
    end
    local ok, err = xpcall(method, ErrorHandler, module)
    if not ok then JP:Print((L("|cffff6b6bОшибка|r %s в модуле %s: %s")):format(methodName, module.name, tostring(err))) end
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
    if not module then return false, L("модуль не найден") end
    if module.enabled then return true end
    if not SafeCall(module, "Create") then return false, L("ошибка Create") end
    if not SafeCall(module, "Enable") then return false, L("ошибка Enable") end
    module.enabled = true
    return true
end

function JP:ReloadModule(inputName)
    local module, name = self:FindModule(inputName)
    if not module then
        self:Print((L("Модуль «%s» не найден. Список: /mb modules")):format(tostring(inputName)))
        return
    end
    if InCombatLockdown() then
        self.pendingReloads[name] = true
        self:Print(name .. L(" будет пересобран после боя."))
        return
    end
    SafeCall(module, "Disable"); SafeCall(module, "Destroy"); module.enabled = false
    local ok, reason = self:EnableModule(name)
    self:Print(ok and (name .. L(" пересобран.")) or (L("Не удалось пересобрать ") .. name .. ": " .. reason))
end

function JP:ListModules()
    local names = {}
    for name, module in pairs(self.modules) do
        names[#names + 1] = (module.enabled and "|cff43d17a" or "|cff8a8f98") .. name .. "|r"
    end
    table.sort(names)
    self:Print(L("Модули: ") .. table.concat(names, ", "))
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
    local function Default(settings, key, value)
        if settings[key] == nil then settings[key] = value end
    end
    db.dbVersion = DB_VERSION
    db.scannedPlayers = type(db.scannedPlayers) == "table" and db.scannedPlayers or {}
    db.groupFilters = type(db.groupFilters) == "table" and db.groupFilters or {}
    db.localBests = type(db.localBests) == "table" and db.localBests or {}
    db.autoMatch = type(db.autoMatch) == "table" and db.autoMatch or { requireTank = true }
    db.window = type(db.window) == "table" and db.window or {}
    if db.minimumKeystoneRuns ~= nil and not tonumber(db.minimumKeystoneRuns) then db.minimumKeystoneRuns = nil end
    if db.filterGroupFinder == nil then db.filterGroupFinder = true end
    if db.logging == nil then db.logging = false end
    -- Search and analysis are the product core. Rejected results stay visible
    -- by default so our list never looks smaller than Blizzard's real result
    -- set; the player may hide the lower section or make it read-only.
    db.search = type(db.search) == "table" and db.search or {}
    Default(db.search, "showRejectedResults", true)
    Default(db.search, "allowRejectedApplications", true)
    db.playerAnalysis = type(db.playerAnalysis) == "table" and db.playerAnalysis or {}
    Default(db.playerAnalysis, "enabled", true)
    Default(db.playerAnalysis, "nameplateMarkers", true)
    -- Earlier releases silently raised the required number of the leader's
    -- +10 runs every time *the player* finished a key. Those values are not
    -- causally related and the hidden growth eventually pushed most listings
    -- into the rejected section. Migrate that legacy automatic value once;
    -- explicit future edits of runsMin remain untouched.
    if db.search.defaultsRevision ~= 1 then
        local storedRuns = tonumber(db.groupFilters.runsMin)
        local automaticRuns = tonumber(db.minimumKeystoneRuns)
        if storedRuns == nil or (automaticRuns and storedRuns == automaticRuns) then
            db.groupFilters.runsMin = 0
        end
        db.minimumKeystoneRuns = 0
        db.search.defaultsRevision = 1
    end
    -- Старый режим захвата штатной кнопки удалён: MythicBoost теперь
    -- открывается только своей кнопкой внутри Blizzard Group Finder.
    db.replaceGroupFinder = false
    -- Минималистичный интерфейс выключен по умолчанию намеренно: это не
    -- галочка возможности, а полный рескин чужих панелей, миникарты и
    -- трекера. Такое включают осознанно, а не получают при обновлении.
    if db.minimalUI == nil then db.minimalUI = false end
    db.minimalUIOptions = type(db.minimalUIOptions) == "table" and db.minimalUIOptions or {}
    -- Отдельное владение миникартой: старым пользователям сохраняем прежний
    -- вид, но теперь его можно выключить независимо от остального Minimal UI.
    if db.minimalUIOptions.minimap == nil then db.minimalUIOptions.minimap = true end
    -- The bottom HUD takes ownership of positions, so upgrades never enable
    -- it behind the player's back.  The one-time layout proposal turns it on
    -- only after explicit acceptance.
    if db.minimalUIOptions.bottomDock == nil then db.minimalUIOptions.bottomDock = false end
    if db.minimalUIOptions.compactActionBars == nil then db.minimalUIOptions.compactActionBars = false end
    if db.minimalUIOptions.hideStanceBar == nil then db.minimalUIOptions.hideStanceBar = false end
    db.convenience = type(db.convenience) == "table" and db.convenience or {}
    -- Actions that accept dialogs, spend money, alter quests or invite other
    -- people are explicit opt-ins. Inserting a Keystone is the only automatic
    -- action enabled initially: it runs after the player opens the pedestal.
    local convenienceDefaults = {
        autoKeystone = true,
        autoQuests = false,
        guildRepair = true,
        hideBags = true,
        merchantSummary = true,
        repair = false,
        resurrection = false,
        resNoCombat = true,
        sellJunk = false,
        summon = false,
        whisperInvite = false,
    }
    for key, value in pairs(convenienceDefaults) do Default(db.convenience, key, value) end
    db.unitFrames = type(db.unitFrames) == "table" and db.unitFrames or {}
    Default(db.unitFrames, "enabled", false)
    Default(db.unitFrames, "hideBlizzard", true)
    -- The compact player/target capsule is optional, but once enabled it must
    -- be a complete HUD component rather than a fixed mock-up. These values
    -- are deliberately independent so an existing profile only receives the
    -- settings it did not already choose.
    Default(db.unitFrames, "scale", 1)
    Default(db.unitFrames, "opacity", 1)
    Default(db.unitFrames, "showHealthText", true)
    Default(db.unitFrames, "showPowerText", true)
    Default(db.unitFrames, "animatedPortrait", true)
    Default(db.unitFrames, "showBadges", true)
    Default(db.unitFrames, "badgesUnlocked", false)
    Default(db.unitFrames, "badgeShape", 1)
    Default(db.unitFrames, "alwaysShowTarget", false)
    db.unitFrames.badgePositions = type(db.unitFrames.badgePositions) == "table"
        and db.unitFrames.badgePositions or {}
    Default(db.unitFrames, "showPlayerAuras", true)
    Default(db.unitFrames, "showTargetAuras", true)
    Default(db.unitFrames, "aurasAbove", false)
    Default(db.unitFrames, "showResourcePips", true)
    Default(db.unitFrames, "showEmptyResources", true)
    Default(db.unitFrames, "resourceHeight", 10)
    Default(db.unitFrames, "resourceGap", 2)
    Default(db.unitFrames, "resourceOpacity", 1)
    local function ClampFrameNumber(key, minimum, maximum, fallback)
        local value = tonumber(db.unitFrames[key])
        if not value then value = fallback end
        db.unitFrames[key] = math.max(minimum, math.min(maximum, value))
    end
    ClampFrameNumber("scale", .75, 2.00, 1)
    ClampFrameNumber("badgeShape", 1, 3, 1)
    ClampFrameNumber("opacity", .55, 1, 1)
    ClampFrameNumber("resourceHeight", 6, 16, 10)
    ClampFrameNumber("resourceGap", 0, 6, 2)
    ClampFrameNumber("resourceOpacity", .30, 1, 1)
    db.castBar = type(db.castBar) == "table" and db.castBar or {}
    Default(db.castBar, "enabled", false)
    db.lootUI = type(db.lootUI) == "table" and db.lootUI or {}
    Default(db.lootUI, "enabled", false)
    Default(db.lootUI, "atCursor", true)
    Default(db.lootUI, "showRolls", true)
    Default(db.lootUI, "showHistory", true)
    db.smartClick = type(db.smartClick) == "table" and db.smartClick or {}
    Default(db.smartClick, "buff", false)
    Default(db.smartClick, "res", false)
    db.rcLoot = type(db.rcLoot) == "table" and db.rcLoot or {}
    Default(db.rcLoot, "enabled", false)
    db.errorGuard = type(db.errorGuard) == "table" and db.errorGuard or {}
    Default(db.errorGuard, "enabled", false)
    Default(db.errorGuard, "keepBetweenSessions", true)
    db.bagUI = type(db.bagUI) == "table" and db.bagUI or {}
    -- The unified inventory replaces protected Blizzard bag behaviour, so it
    -- must be an explicit opt-in. Apply this once to profiles that inherited
    -- the former automatic default; later manual choices remain untouched.
    if db.bagUI.defaultDisabledRevision ~= 1 then
        db.bagUI.enabled = false
        db.bagUI.defaultDisabledRevision = 1
    elseif db.bagUI.enabled == nil then
        db.bagUI.enabled = false
    end
    -- BagUI is no longer loaded. Remove its historical captured errors once so
    -- the in-game journal reflects the current build instead of dead code.
    if db.bagUI.errorLogPruned ~= 1 then
        if type(db.errorGuard) == "table" and type(db.errorGuard.log) == "table" then
            for index = #db.errorGuard.log, 1, -1 do
                local entry = db.errorGuard.log[index]
                local key = type(entry) == "table" and type(entry.key) == "string" and entry.key or ""
                local message = type(entry) == "table" and type(entry.message) == "string" and entry.message or ""
                if key:find("/BagUI.lua", 1, true) or message:find("/BagUI.lua", 1, true) then
                    table.remove(db.errorGuard.log, index)
                end
            end
        end
        db.bagUI.errorLogPruned = 1
    end
    -- Revision 2 keeps the convenient global switch but no longer overwrites
    -- the capsule-specific move toggle on every /reload. Existing profiles are
    -- migrated once from the old single-state model, then each component may
    -- be locked independently from its own settings page.
    if db.interfaceUnlockRevision ~= 2 then
        local unlocked = db.interfaceUnlocked == true or db.unitFrames.unlocked == true
            or db.castBar.unlocked == true or db.convenience.movableKeystoneFrame == true
        db.interfaceUnlocked = unlocked
        db.unitFrames.unlocked = unlocked
        db.castBar.unlocked = unlocked
        db.convenience.movableKeystoneFrame = unlocked
        db.interfaceUnlockRevision = 2
    else
        db.unitFrames.unlocked = db.unitFrames.unlocked == true
        db.castBar.unlocked = db.castBar.unlocked == true
        db.convenience.movableKeystoneFrame = db.convenience.movableKeystoneFrame == true
        db.interfaceUnlocked = db.unitFrames.unlocked or db.castBar.unlocked
            or db.convenience.movableKeystoneFrame
    end
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
        local completion = JP.API.GetChallengeCompletion()
        local active = JP.API.GetActiveChallenge()
        local mapID, level = completion and completion.mapID, completion and completion.level
        if not JP.UsableNumber(mapID) then mapID = active and active.mapID end
        if not JP.UsableNumber(level) then level = active and active.level end
        if not (completion and completion.practiceRun)
            and JP.UsableNumber(mapID) and JP.UsableNumber(level) then
            JP:SetLocalBest(mapID, level)
        end
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
    record.text = ok and tostring(result):sub(1, 200) or L("<нечитаемо>")
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
    if not ok then out.__error = L("pairs() упал на защищённом значении") end
    return out
end

local function DumpSearchResults()
    local _, resultIDs = C_LFGList.GetSearchResults()
    if type(resultIDs) ~= "table" or #resultIDs == 0 then
        JP:Print(L("Результатов поиска нет — сначала нажми «Обновить» в окне."))
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
            entry.memberCounts = ok and DescribeTable(counts) or { __error = L("недоступно") }
        end
        snapshot.results[index] = entry
    end

    MythicBoostDB.diagnostics = snapshot
    JP:Print((L("Снимок %d результатов сохранён. Выполни |cff28b8f5/reload|r — после него структуру видно в SavedVariables.")):format(#snapshot.results))

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
    JP:Print(L("версия ") .. JP:GetVersion())
    JP:Print(L("|cff28b8f5/mb|r — открыть или закрыть окно"))
    JP:Print(L("|cff28b8f5/mb filter|r — открыть безопасные фильтры MythicBoost"))
    JP:Print(L("|cff28b8f5/mb players|r — сколько перспективных игроков сохранено"))
    JP:Print(L("|cff28b8f5/mb clear|r — очистить базу игроков"))
    JP:Print(L("|cff28b8f5/mb modules|r — список модулей"))
    JP:Print(L("|cff28b8f5/mb reload|r [модуль] — перезагрузить интерфейс или один модуль"))
    JP:Print(L("|cff28b8f5/mb smartclick|r — разбор умного клика: заклинания, кнопки, атрибуты"))
    JP:Print(L("|cff28b8f5/mb errors|r — журнал перехваченных ошибок (clear — очистить)"))
    JP:Print(L("|cff28b8f5/mb debug|r — снимок структуры от API поиска групп"))
    JP:Print(L("|cff28b8f5/mb log|r [on|off|clear] — журнал последних событий"))
    JP:Print(L("|cff28b8f5/mb restorefilter|r — вернуть фильтр стандартного окна групп"))
    JP:Print(L("|cff28b8f5/mb replace|r — открывать своё окно вместо штатного поиска групп"))
    JP:Print(L("|cff28b8f5/mb frames|r [reset] — свои фреймы игрока и цели, reset — сбросить позиции"))
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
        JP:Print(L("Фильтры работают в окне MythicBoost. Штатный список Blizzard не изменяется: в Midnight это вызывает secret-taint."))
        ToggleWindow()
    elseif command == "smartclick" or command == "click" then
        if JP.SmartClick then JP.SmartClick:Diagnose() else JP:Print(L("Модуль SmartClick не загружен.")) end
    elseif command == "errors" or command == "error" then
        if JP.ErrorGuard then
            if argument == "clear" then
                JP.ErrorGuard:Clear()
            else
                local unique, total = JP.ErrorGuard:Count()
                JP:Print((L("Ошибок в журнале: %d (срабатываний %d)")):format(unique, total))
                JP.ErrorGuard:Toggle()
            end
        end
    elseif command == "players" then
        JP:Print((L("Сохранено перспективных игроков: %d")):format(PruneScannedPlayers()))
    elseif command == "clear" then
        wipe(MythicBoostDB.scannedPlayers)
        wipe(JP.positivePlayers)
        wipe(JP.positivePlayerOrder)
        local marker = JP.modules.NameplateMarker
        if marker and marker.RefreshAll then marker:RefreshAll() end
        JP:Print(L("База перспективных игроков очищена."))
    elseif command == "replace" then
        if JP.FrameSwitch then
            JP.FrameSwitch:SetReplacing(false)
        end
    elseif command == "restorefilter" then
        local backup = MythicBoostDB.blizzardFilterBackup
        if type(backup) == "table" and type(C_LFGList.SaveAdvancedFilter) == "function" then
            local ok = pcall(C_LFGList.SaveAdvancedFilter, backup)
            JP:Print(ok and L("Фильтр стандартного окна групп возвращён к исходному.")
                or L("Не удалось вернуть фильтр — попробуй вне боя."))
        else
            JP:Print(L("Сохранённого фильтра нет: MythicBoost его ещё не менял."))
        end
    elseif command == "debug" or command == "dump" then
        DumpSearchResults()
    elseif command == "log" then
        local mode = argument:lower()
        if mode == "on" or mode == "off" then
            MythicBoostDB.logging = mode == "on"
            JP:Print(L("Журнал ") .. (MythicBoostDB.logging and L("|cff43d17aвключён|r") or L("|cffff9966выключен|r")) .. ".")
        elseif mode == "clear" then
            wipe(JP.log)
            JP:Print(L("Журнал очищен."))
        elseif #JP.log == 0 then
            JP:Print(JP:IsLogging() and L("Журнал пуст.") or L("Журнал выключен. Включить: /mb log on"))
        else
            JP:Print((L("Последние записи (%d):")):format(#JP.log))
            for index = math.max(1, #JP.log - 19), #JP.log do JP:Print("  " .. JP.log[index]) end
        end
    elseif command == "frames" then
        local settings = MythicBoostDB.unitFrames
        if argument:lower() == "reset" then
            settings.player, settings.target = nil, nil
            if JP.UnitFrames and JP.UnitFrames.ResetPositions then JP.UnitFrames:ResetPositions() end
            JP:Print(L("Позиции фреймов игрока и цели сброшены."))
        else
            settings.enabled = not settings.enabled
            JP:Print(L("Свои фреймы: ") .. (settings.enabled and L("|cff43d17aвключены|r") or L("|cffff9966выключены|r")))
        end
        JP:ReloadModule("UnitFrames")
    else
        ShowHelp()
    end
end
