local _, JP = ...
local AutoMatch = {}

local BLOODLUST_CLASSES = { HUNTER = true, MAGE = true, SHAMAN = true, EVOKER = true }
local MIN_KEY_LEVEL, MAX_KEY_LEVEL = 2, 40

local function UsableNumber(value)
    return type(value) == "number" and not issecretvalue(value)
end

-- Строки из C_LFGList в Midnight приходят защищёнными. Пропускаем их через
-- один фильтр, чтобы фильтрация и отрисовка видели ровно одно и то же
-- значение: иначе список показывает «+12», а колонка «Ключ» — прочерк.
local function SafeString(value)
    if type(value) ~= "string" or issecretvalue(value) or value == "" then return nil end
    return value
end

local function Contains(list, value)
    if type(list) ~= "table" then return false end
    local wanted = tonumber(value) or value
    for _, item in pairs(list) do
        if (tonumber(item) or item) == wanted then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Кэш одного скана
--
-- В списке до сотни групп, и на каждую приходится дёргать профиль лидера.
-- Без кэша один Refresh стоит сотен обращений к Raider.IO.
---------------------------------------------------------------------------

local cache = { playerRuns = nil, dungeonByActivity = {}, leaderRuns = {} }

local function ResetCache()
    cache.playerRuns = nil
    cache.dungeonByActivity = {}
    cache.leaderRuns = {}
end

local function PlayerRuns()
    if cache.playerRuns then return cache.playerRuns end
    local runs
    if RaiderIO and type(RaiderIO.GetProfile) == "function" then
        local ok, profile = pcall(RaiderIO.GetProfile, "player")
        local keystone = ok and profile and profile.mythicKeystoneProfile
        runs = keystone and keystone.sortedDungeons
    end
    cache.playerRuns = type(runs) == "table" and runs or {}
    return cache.playerRuns
end

local function PlayerDungeon(activityID)
    if not activityID then return end
    local cached = cache.dungeonByActivity[activityID]
    if cached ~= nil then return cached or nil end
    for _, run in ipairs(PlayerRuns()) do
        if run.dungeon and Contains(run.dungeon.lfd_activity_ids, activityID) then
            cache.dungeonByActivity[activityID] = run
            return run
        end
    end
    cache.dungeonByActivity[activityID] = false
end

local function LeaderRunCount(leaderName)
    local name = SafeString(leaderName)
    if not name or not RaiderIO or type(RaiderIO.GetProfile) ~= "function" then return end
    local cached = cache.leaderRuns[name]
    if cached ~= nil then return cached or nil end
    local ok, profile = pcall(RaiderIO.GetProfile, name)
    local keystone = ok and profile and profile.mythicKeystoneProfile
    if not keystone then cache.leaderRuns[name] = false; return end
    local total = 0
    for _, level in ipairs({ 10, 12, 15 }) do
        local count = keystone["keystoneMilestone" .. level]
        if UsableNumber(count) then total = total + count end
    end
    cache.leaderRuns[name] = total
    return total
end

---------------------------------------------------------------------------
-- Подземелье и уровень ключа
---------------------------------------------------------------------------

-- Сопоставление «название активности → mapID сезона». Нужен запасной путь
-- на случай, когда Raider.IO не установлен: иначе фильтр по подземельям
-- не находит вообще ничего.
local challengeMapsByName
local function ChallengeMapsByName()
    if challengeMapsByName then return challengeMapsByName end
    local maps, count = {}, 0
    for _, mapID in ipairs(C_ChallengeMode.GetMapTable and C_ChallengeMode.GetMapTable() or {}) do
        local name = C_ChallengeMode.GetMapUIInfo(mapID)
        if type(name) == "string" and name ~= "" then
            maps[name:lower()] = mapID
            count = count + 1
        end
    end
    -- Пустой результат не кэшируем. Таблица подземелий сезона приходит не
    -- сразу после входа в игру, а окно открывается раньше: один ранний вызов
    -- иначе намертво ломал сопоставление подземелий на всю сессию.
    if count > 0 then challengeMapsByName = maps end
    return maps
end

local function MapIDFromActivity(activity, activityID)
    activityID = tonumber(activityID)
    if activityID and JP.SeasonMapByActivity and JP.SeasonMapByActivity[activityID] then
        return JP.SeasonMapByActivity[activityID]
    end
    local direct = activity and tonumber(activity.mapChallengeModeID or activity.challengeMapID or activity.mapID)
    if direct then return direct end
    local name = activity and SafeString(activity.fullName or activity.shortName)
    if not name then return end
    local lowered = name:lower()
    for mapName, mapID in pairs(ChallengeMapsByName()) do
        if lowered:find(mapName, 1, true) then return mapID end
    end
end

local function ParseKeyLevel(text)
    if not text then return end
    -- В названиях LFG встречаются три разных символа плюса, цветовые коды и
    -- хвосты вроде "+11 weekly". Ищем плюс не только в начале строки, а если
    -- его нет -- разрешаем число лишь в самом первом токене.
    local clean = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local parsed = clean:match("%+%s*(%d%d?)")
        or clean:match("＋%s*(%d%d?)")
        or clean:match("﹢%s*(%d%d?)")
    if not parsed then
        -- Без плюса принимаем число только как первый самостоятельный токен.
        -- Поиск любого числа в строке ошибочно принимал «rio 3k», возраст или
        -- Discord-тег за уровень ключа и выкидывал реальные подходящие группы.
        parsed = clean:match("^%s*(%d%d?)%f[%D]")
    end
    local level = tonumber(parsed)
    if level and level >= MIN_KEY_LEVEL and level <= MAX_KEY_LEVEL then return level end
end

local function GetActivityID(info)
    local activityID = info and info.activityID
    if UsableNumber(activityID) then return activityID end
    local activityIDs = info and info.activityIDs
    if type(activityIDs) == "table" and not issecretvalue(activityIDs) then
        activityID = activityIDs[1]
        if UsableNumber(activityID) then return activityID end
    end
end

local function PlayerRole()
    local specialization = GetSpecialization and GetSpecialization()
    local role = specialization and GetSpecializationRole(specialization)
    if role == "TANK" or role == "HEALER" or role == "DAMAGER" then return role end
    role = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")
    if role == "TANK" or role == "HEALER" or role == "DAMAGER" then return role end
    return "DAMAGER"
end

local function Composition(searchResultID, numMembers)
    local counts = C_LFGList.GetSearchResultMemberCounts and C_LFGList.GetSearchResultMemberCounts(searchResultID)
    local hasTank = counts and (counts.TANK or 0) > 0 or false
    local hasHealer = counts and (counts.HEALER or 0) > 0 or false
    local hasBloodlust = false
    local memberInfo = {}
    for index = 1, (numMembers or 0) do
        local member = C_LFGList.GetSearchResultPlayerInfo(searchResultID, index)
        if member then
            memberInfo[#memberInfo + 1] = {
                name = SafeString(member.name),
                classFilename = member.classFilename,
                assignedRole = member.assignedRole,
                isLeader = member.isLeader or index == 1,
            }
            local role = member.assignedRole
            if not counts and (role == "TANK" or ((not role or role == "NONE") and member.lfgRoles and member.lfgRoles.tank)) then hasTank = true end
            if not counts and (role == "HEALER" or ((not role or role == "NONE") and member.lfgRoles and member.lfgRoles.healer)) then hasHealer = true end
            if BLOODLUST_CLASSES[member.classFilename] then hasBloodlust = true end
        end
    end
    return hasTank, hasHealer, hasBloodlust, counts, memberInfo
end

---------------------------------------------------------------------------
-- Фильтры
---------------------------------------------------------------------------

local function HasPlayerRoleSlot(counts)
    if not counts then return true end
    local role = PlayerRole()
    local key = role == "TANK" and "TANK_REMAINING" or role == "HEALER" and "HEALER_REMAINING" or "DAMAGER_REMAINING"
    local remaining = counts[key]
    return not UsableNumber(remaining) or remaining > 0
end

local function InRange(value, minimum, maximum, allowUnknown)
    minimum, maximum = tonumber(minimum), tonumber(maximum)
    if not UsableNumber(value) then return allowUnknown ~= false end
    if minimum and value < minimum then return false end
    if maximum and value > maximum then return false end
    return true
end

local function DungeonSelected(filters, mapID)
    local selected = filters and filters.dungeons
    if type(selected) ~= "table" then return true end
    local any = false
    for _, enabled in pairs(selected) do if enabled then any = true break end end
    if not any then return true end
    return mapID and (selected[mapID] or selected[tostring(mapID)]) and true or false
end

local function IsDeclined(searchResultID)
    if not C_LFGList.GetApplicationInfo then return false end
    local _, status, pending = C_LFGList.GetApplicationInfo(searchResultID)
    return status == "declined" or pending == "declined" or status == "declined_full" or status == "declined_delisted"
end

-- Уровень ключа объявления аддонам в Midnight недоступен.
--
-- Проверено дампом реального API: searchResultInfo.name приходит непрозрачным
-- токеном вида "|Kt458|k" — настоящий текст клиент подставляет только при
-- отрисовке. Поля с уровнем ключа в таблице нет, а GetKeystoneForActivity
-- отдаёт СВОЙ ключ игрока, а не ключ группы.
--
-- Ближайшее читаемое приближение — лучший результат лидера в этом подземелье:
-- кто закрыл +11, тот примерно на +11 и набирает.
local function LeaderRunLevel(info, mapID)
    local list = info.leaderDungeonScoreInfo
    if type(list) == "table" then
        local fallback
        for _, entry in ipairs(list) do
            if type(entry) == "table" and UsableNumber(entry.bestRunLevel) and entry.bestRunLevel > 0 then
                if mapID and entry.mapChallengeModeID == mapID then return entry.bestRunLevel end
                fallback = fallback or entry.bestRunLevel
            end
        end
        if fallback then return fallback end
    end
    local best = info.leaderBestDungeonScoreInfo
    if type(best) == "table" and UsableNumber(best.bestRunLevel) and best.bestRunLevel > 0 then
        return best.bestRunLevel
    end
end

-- Причины отсева. Без них «0 из 100» невозможно объяснить: по экрану не
-- видно, который из десятка фильтров съел всю выборку.
local REASON = {
    delisted = "объявление уже снято",
    full = "группа уже полная",
    belowBest = "ключ ниже твоего рекорда",
    notUpgrade = "ключ не поднимает рейтинг",
    keyUnknown = "уровень ключа не распознан",
    recordUnknown = "не найден твой рекорд подземелья",
    roleFit = "нет места под твою роль",
    tank = "в группе нет танка",
    bloodlust = "в группе нет Bloodlust",
    declined = "тебе уже отказали",
    dungeon = "подземелье выключено",
    keyRange = "ключ вне диапазона",
    score = "рейтинг лидера вне диапазона",
    runsUnknown = "нет данных Raider.IO о лидере",
    runs = "мало ключей +10 у лидера",
    members = "размер группы вне диапазона",
    age = "объявление старше лимита",
}

local function BuildMatch(searchResultID, requireTank, requireBloodlust, filters, runtime)
    local info = C_LFGList.GetSearchResultInfo(searchResultID)
    if not info or info.isDelisted then return nil, REASON.delisted end
    if (info.numMembers or 0) >= 5 then return nil, REASON.full end
    filters = filters or {}

    local activityID = GetActivityID(info)
    local activity = activityID and C_LFGList.GetActivityInfoTable(activityID)
    local title, comment = SafeString(info.name), SafeString(info.comment)
    local keyLevel = ParseKeyLevel(title) or ParseKeyLevel(comment)

    local run = PlayerDungeon(activityID)
    local mapID = (run and run.dungeon and run.dungeon.keystone_instance) or MapIDFromActivity(activity, activityID)
    local bestLevel = runtime and activityID and runtime.bestByActivity and runtime.bestByActivity[activityID]
    bestLevel = bestLevel or (runtime and mapID and runtime.bestByMap and runtime.bestByMap[mapID])
    bestLevel = bestLevel or JP:GetBestLevel(mapID, run and run.level or 0)

    -- Заголовок разбираем только на случай, если Blizzard вернёт открытый
    -- текст; штатный источник — результат лидера, см. LeaderRunLevel.
    local keyApprox = false
    if not keyLevel then
        keyLevel = LeaderRunLevel(info, mapID)
        keyApprox = keyLevel ~= nil
    end

    local score = UsableNumber(info.leaderOverallDungeonScore) and info.leaderOverallDungeonScore or 0
    local leaderRuns = LeaderRunCount(info.leaderName)
    local age = UsableNumber(info.age) and info.age or nil
    local members = UsableNumber(info.numMembers) and info.numMembers or 0
    local hasTank, hasHealer, hasBloodlust, counts, memberInfo = Composition(searchResultID, members)

    -- Сначала отбираем подземелье: activityID остаётся обычным числом даже
    -- тогда, когда Blizzard защищает пользовательское название объявления.
    if not DungeonSelected(filters, mapID) then return nil, REASON.dungeon end

    -- Ключ ниже личного рекорда рейтинг не поднимет — такие группы прячем,
    -- когда клиент действительно разрешил прочитать уровень.
    -- LeaderRunLevel() is only the leader's best result for this dungeon. It
    -- is useful as a hint in the row, but it is NOT the level advertised by
    -- the group. Never use that approximation as a hard filter.
    if keyLevel and not keyApprox and keyLevel < bestLevel then return nil, REASON.belowBest end
    -- В Midnight name/comment являются protected strings. Стандартный фрейм
    -- умеет их рисовать, но Lua не имеет права вызвать на них match(). Поэтому
    -- известный уровень проверяем строго, а скрытый не превращаем в ложный
    -- отсев всех 100 результатов. В строке он будет явно показан как цель.
    local targetLevel
    if filters.scoreUpgrade then
        if not bestLevel or bestLevel <= 0 then return nil, REASON.recordUnknown end
        targetLevel = bestLevel + 1
        if filters.searchTargetLevel and targetLevel ~= filters.searchTargetLevel then
            return nil, REASON.notUpgrade
        end
        if keyLevel and not keyApprox and keyLevel ~= targetLevel then return nil, REASON.notUpgrade end
    end
    if filters.roleFit ~= false and not HasPlayerRoleSlot(counts) then return nil, REASON.roleFit end
    if requireTank and not hasTank then return nil, REASON.tank end
    if requireBloodlust and not hasBloodlust then return nil, REASON.bloodlust end
    if filters.notDeclined and IsDeclined(searchResultID) then return nil, REASON.declined end
    -- Уровень ключа в заголовке может быть скрыт клиентом. Неизвестный
    -- уровень оставляем видимым, вместо того чтобы выкинуть годную группу.
    if not filters.scoreUpgrade and not InRange(keyLevel, filters.keyMin, filters.keyMax, true) then return nil, REASON.keyRange end
    if not InRange(score, filters.scoreMin, filters.scoreMax, false) then return nil, REASON.score end
    if tonumber(filters.runsMin) then
        -- Отсутствие профиля и слабый профиль — разные причины: иначе выдача
        -- молча пустеет там, где на самом деле просто нет данных.
        if leaderRuns == nil then return nil, REASON.runsUnknown end
        if not InRange(leaderRuns, filters.runsMin, nil, false) then return nil, REASON.runs end
    end
    -- Поля «Игроков от/до» и «Возраст» есть в интерфейсе, поэтому они обязаны
    -- влиять на выдачу: молча игнорировать введённое значение нельзя.
    if not InRange(members, filters.membersMin, filters.membersMax, false) then return nil, REASON.members end
    local maxAge = tonumber(filters.maxAge)
    if maxAge and age and age > maxAge * 60 then return nil, REASON.age end
    return {
        searchResultID = searchResultID,
        activityID = activityID,
        mapID = mapID,
        dungeon = (activity and SafeString(activity.fullName or activity.shortName))
            or (mapID and C_ChallengeMode.GetMapUIInfo(mapID))
            or "Подземелье",
        title = title,
        comment = comment,
        leaderName = SafeString(info.leaderName),
        leaderDungeonScoreInfo = info.leaderDungeonScoreInfo,
        keyLevel = keyLevel,
        keyApprox = keyApprox,
        targetLevel = targetLevel,
        keyLevelProtected = filters.scoreUpgrade and (not keyLevel or keyApprox) or false,
        bestLevel = bestLevel,
        score = score,
        leaderRuns = leaderRuns,
        age = age,
        members = members,
        memberInfo = memberInfo,
        hasTank = hasTank,
        hasHealer = hasHealer,
        hasBloodlust = hasBloodlust,
    }
end

function AutoMatch:Scan(requireTank, requireBloodlust, filters, runtime)
    local matches = {}
    if not C_LFGList or not C_LFGList.GetSearchResults then return matches, "Поиск групп недоступен." end
    local _, resultIDs = C_LFGList.GetSearchResults()
    if type(resultIDs) ~= "table" or #resultIDs == 0 then
        return matches, "Нажми «Обновить» — MythicBoost сам запросит группы у Blizzard."
    end

    ResetCache()
    local total = #resultIDs
    -- Уровень ключа в Midnight может приходить защищённым значением. Журнал
    -- показывает, что именно вернул API, вместо догадок по пустой колонке.
    if JP:IsLogging() then
        for index = 1, math.min(3, total) do
            local info = C_LFGList.GetSearchResultInfo(resultIDs[index])
            local title = info and info.name
            JP:Log("скан #%d: тип=%s secret=%s имя=%s ключ=%s", index,
                type(title), tostring(issecretvalue(title)), tostring(title),
                tostring(ParseKeyLevel(SafeString(title))))
        end
    end
    local rejected = {}
    for _, searchResultID in ipairs(resultIDs) do
        local match, reason = BuildMatch(searchResultID, requireTank, requireBloodlust, filters, runtime)
        if match then
            matches[#matches + 1] = match
        elseif reason then
            rejected[reason] = (rejected[reason] or 0) + 1
        end
    end
    ResetCache()

    JP:Log("скан: подошло %d из %d", #matches, total)
    if JP:IsLogging() then
        for reason, count in pairs(rejected) do JP:Log("  отсеяно (%s): %d", reason, count) end
    end

    table.sort(matches, function(a, b)
        -- Сначала то, что сильнее двигает рейтинг вверх.
        local ag = a.keyLevel and (a.keyLevel - a.bestLevel) or -1000
        local bg = b.keyLevel and (b.keyLevel - b.bestLevel) or -1000
        if ag ~= bg then return ag > bg end
        if a.hasTank ~= b.hasTank then return a.hasTank end
        if a.hasHealer ~= b.hasHealer then return a.hasHealer end
        if a.hasBloodlust ~= b.hasBloodlust then return a.hasBloodlust end
        if a.score ~= b.score then return a.score > b.score end
        return (a.age or math.huge) < (b.age or math.huge)
    end)
    return matches, nil, total, rejected
end

function AutoMatch:Apply(match)
    local searchResultID = type(match) == "table" and match.searchResultID or match
    local info = searchResultID and C_LFGList.GetSearchResultInfo(searchResultID)
    if not info or info.isDelisted then
        JP:Print("Эта группа уже исчезла. Обнови список.")
        return false
    end
    if type(C_LFGList.ApplyToGroup) ~= "function" then
        JP:Print("Заявка недоступна: API поиска групп не отвечает.")
        return false
    end
    local role = PlayerRole()
    C_LFGList.ApplyToGroup(searchResultID, role == "TANK", role == "HEALER", role == "DAMAGER")
    return true
end

function AutoMatch:Cancel(match)
    local searchResultID = type(match) == "table" and match.searchResultID or match
    if not searchResultID or type(C_LFGList.CancelApplication) ~= "function" then
        JP:Print("Отмена заявки сейчас недоступна.")
        return false
    end
    -- CancelApplication защищён hardware event, поэтому этот вызов должен
    -- оставаться непосредственно внутри клика пользователя по кнопке.
    local ok = pcall(C_LFGList.CancelApplication, searchResultID)
    if not ok then
        JP:Print("Blizzard не разрешил отменить заявку сейчас.")
        return false
    end
    return true
end

function AutoMatch:Enable() end
function AutoMatch:Disable() ResetCache() end
function AutoMatch:Destroy() ResetCache() end
JP.AutoMatch = AutoMatch
JP:RegisterModule("AutoMatch", AutoMatch)
