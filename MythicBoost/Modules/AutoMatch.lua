local _, JP = ...
local L = JP.L
local AutoMatch = {}
local UI = JP.UI

local BLOODLUST_CLASSES = { HUNTER = true, MAGE = true, SHAMAN = true, EVOKER = true }
local BATTLE_REZ_CLASSES = { DEATHKNIGHT = true, DRUID = true, PALADIN = true, WARLOCK = true }
local MIN_KEY_LEVEL, MAX_KEY_LEVEL = 2, 40

-- Строки и числа из C_LFGList в Midnight могут быть защищёнными. Все
-- потребители используют общий фильтр, чтобы отбор и UI видели одно значение.
local UsableNumber, SafeString = UI.UsableNumber, UI.SafeString
local SafeBoolean, SafeTable = UI.SafeBoolean, UI.SafeTable

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
    for _, mapID in ipairs(JP.API.GetChallengeMapIDs()) do
        local mapInfo = JP.API.GetChallengeMap(mapID)
        local name = mapInfo and mapInfo.name
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

local function OwnPartyProfile()
    local profile = {
        roles = { TANK = 0, HEALER = 0, DAMAGER = 0 },
        hasBloodlust = false,
        hasBattleRes = false,
    }
    local units = { "player" }
    if IsInGroup and IsInGroup() and not (IsInRaid and IsInRaid()) then
        for index = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. index end
    end
    for _, unit in ipairs(units) do
        if UnitExists(unit) then
            local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
            if (not role or role == "NONE") and unit == "player" then role = PlayerRole() end
            if role ~= "TANK" and role ~= "HEALER" and role ~= "DAMAGER" then role = "DAMAGER" end
            profile.roles[role] = profile.roles[role] + 1
            local _, classFilename = UnitClass(unit)
            if BLOODLUST_CLASSES[classFilename] then profile.hasBloodlust = true end
            if BATTLE_REZ_CLASSES[classFilename] then profile.hasBattleRes = true end
        end
    end
    return profile
end

local function Composition(searchResultID, numMembers)
    local counts = C_LFGList.GetSearchResultMemberCounts and SafeTable(C_LFGList.GetSearchResultMemberCounts(searchResultID))
    local tankCount = counts and counts.TANK
    local healerCount = counts and counts.HEALER
    local hasTank = UsableNumber(tankCount) and tankCount > 0 or false
    local hasHealer = UsableNumber(healerCount) and healerCount > 0 or false
    local hasBloodlust = false
    local hasBattleRes = false
    local memberInfo = {}
    for index = 1, (numMembers or 0) do
        local member = C_LFGList.GetSearchResultPlayerInfo(searchResultID, index)
        if member then
            local classFilename = SafeString(member.classFilename)
            local role = SafeString(member.assignedRole)
            local lfgRoles = SafeTable(member.lfgRoles)
            memberInfo[#memberInfo + 1] = {
                name = SafeString(member.name),
                classFilename = classFilename,
                assignedRole = role,
                isLeader = SafeBoolean(member.isLeader) or index == 1,
            }
            if not counts and (role == "TANK" or ((not role or role == "NONE") and lfgRoles and SafeBoolean(lfgRoles.tank))) then hasTank = true end
            if not counts and (role == "HEALER" or ((not role or role == "NONE") and lfgRoles and SafeBoolean(lfgRoles.healer))) then hasHealer = true end
            if classFilename and BLOODLUST_CLASSES[classFilename] then hasBloodlust = true end
            if classFilename and BATTLE_REZ_CLASSES[classFilename] then hasBattleRes = true end
        end
    end
    return hasTank, hasHealer, hasBloodlust, hasBattleRes, counts, memberInfo
end

---------------------------------------------------------------------------
-- Фильтры
---------------------------------------------------------------------------

local ROLE_LIMIT = { TANK = 1, HEALER = 1, DAMAGER = 3 }

local function RemainingRoleSlots(counts, role)
    if not counts then return end
    local remaining = counts[role .. "_REMAINING"]
    if UsableNumber(remaining) then return math.max(0, remaining) end
    local current = counts[role]
    if UsableNumber(current) then return math.max(0, ROLE_LIMIT[role] - current) end
end

local function PartyFits(counts, party)
    if not counts then return true end
    for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
        local remaining = RemainingRoleSlots(counts, role)
        if remaining and party.roles[role] > remaining then return false end
    end
    return true
end

local function UtilityFits(counts, party, groupHasUtility, utilityRoles)
    if groupHasUtility then return true end
    if not counts then return true end
    for role in pairs(utilityRoles) do
        local remaining = RemainingRoleSlots(counts, role)
        if remaining and remaining - party.roles[role] > 0 then return true end
    end
    return false
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
    return JP.API.GetApplicationState(searchResultID).declined
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
    if SafeTable(list) then
        local fallback
        for _, entry in ipairs(list) do
            if type(entry) == "table" and UsableNumber(entry.bestRunLevel) and entry.bestRunLevel > 0 then
                local entryMapID = UsableNumber(entry.mapChallengeModeID) and entry.mapChallengeModeID or nil
                if mapID and entryMapID == mapID then return entry.bestRunLevel end
                fallback = fallback or entry.bestRunLevel
            end
        end
        if fallback then return fallback end
    end
    local best = info.leaderBestDungeonScoreInfo
    if SafeTable(best) and UsableNumber(best.bestRunLevel) and best.bestRunLevel > 0 then
        return best.bestRunLevel
    end
end

-- Причины отсева. Без них «0 из 100» невозможно объяснить: по экрану не
-- видно, который из десятка фильтров съел всю выборку.
local REASON = {
    delisted = L("объявление уже снято"),
    full = L("группа уже полная"),
    belowBest = L("ключ ниже твоего рекорда"),
    keyUnknown = L("уровень ключа не распознан"),
    recordUnknown = L("не найден твой рекорд подземелья"),
    roleFit = L("нет места под роли твоей пати"),
    tank = L("в группе нет танка"),
    healer = L("в группе нет лекаря"),
    bloodlust = L("после вступления негде взять Bloodlust"),
    battleRes = L("после вступления негде взять боевое воскрешение"),
    declined = L("тебе уже отказали"),
    dungeon = L("подземелье выключено"),
    keyRange = L("ключ вне диапазона"),
    score = L("рейтинг лидера вне диапазона"),
    runsUnknown = L("нет данных Raider.IO о лидере"),
    runs = L("мало ключей +10 у лидера"),
    readError = L("ошибка чтения результата"),
}

local function Reject(match, reason, actionable)
    match.rejected = true
    match.rejectionReason = reason
    match.actionable = actionable ~= false
    return nil, reason, match
end

-- Deterministic, read-only coaching signal. This deliberately describes the
-- application, but never predicts an invite and never participates in Apply.
local function ApplyCoach(match)
    local reasons, unknowns = {}, {}
    if match.keyLevel then
        if match.bestLevel and match.keyLevel > match.bestLevel then
            reasons[#reasons + 1] = "above_personal_best"
        else
            reasons[#reasons + 1] = "at_or_below_personal_best"
        end
    else
        unknowns[#unknowns + 1] = "key_level"
    end
    if match.keyApprox then unknowns[#unknowns + 1] = "key_level_approximate" end
    if not match.hasTank then reasons[#reasons + 1] = "tank_missing" end
    if not match.hasHealer then reasons[#reasons + 1] = "healer_missing" end
    if match.age then
        if match.age <= 120 then reasons[#reasons + 1] = "fresh_listing" end
    else
        unknowns[#unknowns + 1] = "listing_age"
    end
    if not match.score or match.score <= 0 then unknowns[#unknowns + 1] = "leader_score" end
    match.reasons = reasons
    match.unknowns = unknowns
    return match
end

local function BuildMatch(searchResultID, filters, runtime, party)
    local info = C_LFGList.GetSearchResultInfo(searchResultID)
    if not info then
        return Reject({
            searchResultID = searchResultID, dungeon = L("Недоступная группа"),
            members = 0, score = 0, bestLevel = 0,
        }, REASON.delisted, false)
    end
    filters = filters or {}
    local members = UsableNumber(info.numMembers) and info.numMembers or 0

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
    local leaderBestLevel = LeaderRunLevel(info, mapID)
    if not keyLevel then
        keyLevel = leaderBestLevel
        keyApprox = keyLevel ~= nil
    end
    -- searchExactLevel — только серверная цель запроса. Она не раскрывает
    -- защищённое имя объявления, поэтому не превращаем её в подтверждённый
    -- уровень строки. Если текст скрыт, keyLevel остаётся approximation лидера
    -- (либо nil), а UI показывает targetLevel отдельно как цель поиска.

    local score = UsableNumber(info.leaderOverallDungeonScore) and info.leaderOverallDungeonScore or 0
    local leaderRuns = LeaderRunCount(info.leaderName)
    local age = UsableNumber(info.age) and info.age or nil
    local hasTank, hasHealer, hasBloodlust, hasBattleRes, counts, memberInfo = Composition(searchResultID, members)

    local challengeMapInfo = mapID and JP.API.GetChallengeMap(mapID)
    local match = {
        searchResultID = searchResultID,
        activityID = activityID,
        mapID = mapID,
        dungeon = (activity and SafeString(activity.fullName or activity.shortName))
            or (challengeMapInfo and challengeMapInfo.name)
            or L("Подземелье"),
        title = title,
        comment = comment,
        leaderName = SafeString(info.leaderName),
        leaderDungeonScoreInfo = info.leaderDungeonScoreInfo,
        keyLevel = keyLevel,
        keyApprox = keyApprox,
        bestLevel = bestLevel,
        score = score,
        leaderRuns = leaderRuns,
        leaderBestLevel = leaderBestLevel,
        age = age,
        members = members,
        memberInfo = memberInfo,
        hasTank = hasTank,
        hasHealer = hasHealer,
        hasBloodlust = hasBloodlust,
        hasBattleRes = hasBattleRes,
        roleCounts = counts,
        actionable = true,
    }

    if SafeBoolean(info.isDelisted) then return Reject(match, REASON.delisted, false) end
    if members >= 5 then return Reject(match, REASON.full, false) end

    -- Сначала отбираем подземелье: activityID остаётся обычным числом даже
    -- тогда, когда Blizzard защищает пользовательское название объявления.
    if not DungeonSelected(filters, mapID) then return Reject(match, REASON.dungeon) end

    -- Ключ ниже личного рекорда рейтинг не поднимет — такие группы прячем,
    -- когда клиент действительно разрешил прочитать уровень.
    -- LeaderRunLevel() is only the leader's best result for this dungeon. It
    -- is useful as a hint in the row, but it is NOT the level advertised by
    -- the group. Never use that approximation as a hard filter.
    if keyLevel and not keyApprox and keyLevel <= bestLevel then return Reject(match, REASON.belowBest) end
    -- В Midnight name/comment являются protected strings. Стандартный фрейм
    -- умеет их рисовать, но Lua не имеет права вызвать на них match(). Поэтому
    -- известный уровень проверяем строго, а скрытый не превращаем в ложный
    -- отсев всех 100 результатов. В строке он будет явно показан как цель.
    local targetLevel
    if filters.scoreUpgrade then
        if not bestLevel or bestLevel <= 0 then return Reject(match, REASON.recordUnknown) end
        targetLevel = bestLevel + 1
        match.targetLevel = targetLevel
        -- searchTargetLevel is merely the one +N that the protected Blizzard
        -- search accepted from the hardware click. Different dungeons have
        -- different personal targets, and Blizzard also returns neighbouring
        -- levels. Comparing a dungeon's target with that shared query falsely
        -- rejected every unreadable listing in a mixed eight-dungeon search.
        -- Only a confirmed listing level at/below best is rejected above.
        -- Точная цель помогает сузить серверный поиск, но не является
        -- верхней границей. Любой подтверждённый ключ выше личного рекорда
        -- действительно повышает рейтинг и должен оставаться в выдаче.
    elseif UsableNumber(filters.searchExactLevel) and filters.searchExactLevel >= 2 then
        -- Это цель серверного запроса, а не раскрытый текст объявления. UI
        -- показывает её как цель, сохраняя keyApprox для честной пометки данных.
        targetLevel = filters.searchExactLevel
        match.targetLevel = targetLevel
    end
    match.keyLevelProtected = targetLevel and (not keyLevel or keyApprox) or false
    if targetLevel then
        match.targetSource = filters.scoreUpgrade and "upgrade" or "search_exact"
    end
    if filters.roleFit ~= false and not PartyFits(counts, party) then return Reject(match, REASON.roleFit) end
    if filters.requireTank and not hasTank then return Reject(match, REASON.tank) end
    if filters.requireHealer and not hasHealer then return Reject(match, REASON.healer) end
    if filters.bloodlustFit and not party.hasBloodlust
        and not UtilityFits(counts, party, hasBloodlust, { HEALER = true, DAMAGER = true }) then
        return Reject(match, REASON.bloodlust)
    end
    if filters.battleResFit and not party.hasBattleRes
        and not UtilityFits(counts, party, hasBattleRes, { TANK = true, HEALER = true, DAMAGER = true }) then
        return Reject(match, REASON.battleRes)
    end
    if filters.notDeclined and IsDeclined(searchResultID) then return Reject(match, REASON.declined, false) end
    -- Уровень ключа в заголовке может быть скрыт клиентом. Неизвестный
    -- уровень оставляем видимым, вместо того чтобы выкинуть годную группу.
    if not filters.scoreUpgrade and not InRange(keyApprox and nil or keyLevel, filters.keyMin, filters.keyMax, true) then
        return Reject(match, REASON.keyRange)
    end
    if not InRange(score, filters.scoreMin, filters.scoreMax, false) then return Reject(match, REASON.score) end
    if tonumber(filters.runsMin) then
        -- Отсутствие профиля и слабый профиль — разные причины: иначе выдача
        -- молча пустеет там, где на самом деле просто нет данных.
        if leaderRuns == nil then return Reject(match, REASON.runsUnknown) end
        if not InRange(leaderRuns, filters.runsMin, nil, false) then return Reject(match, REASON.runs) end
    end
    return ApplyCoach(match)
end

function AutoMatch:Scan(filters, runtime)
    local matches, excluded = {}, {}
    if not C_LFGList or not C_LFGList.GetSearchResults then return matches, L("Поиск групп недоступен."), nil, nil, excluded end
    local _, resultIDs = C_LFGList.GetSearchResults()
    if type(resultIDs) ~= "table" or #resultIDs == 0 then
        return matches, L("Нажми «Обновить» — MythicBoost сам запросит группы у Blizzard."), nil, nil, excluded
    end

    ResetCache()
    filters = filters or {}
    local party = OwnPartyProfile()
    local total = #resultIDs
    -- Уровень ключа в Midnight может приходить защищённым значением. Журнал
    -- показывает, что именно вернул API, вместо догадок по пустой колонке.
    if JP:IsLogging() then
        for index = 1, math.min(3, total) do
            local info = C_LFGList.GetSearchResultInfo(resultIDs[index])
            local title = info and info.name
            JP:Log(L("скан #%d: тип=%s secret=%s имя=%s ключ=%s"), index,
                type(title), tostring(issecretvalue(title)), SafeString(title) or "<secret>",
                tostring(ParseKeyLevel(SafeString(title))))
        end
    end
    local rejected = {}
    for sourceOrder, searchResultID in ipairs(resultIDs) do
        local ok, match, reason, rejectedMatch = pcall(BuildMatch, searchResultID, filters, runtime, party)
        if not ok then
            JP:Log(L("строка поиска %s не разобрана: %s"), tostring(searchResultID), tostring(match))
            reason = REASON.readError
            match = nil
            rejectedMatch = {
                searchResultID = searchResultID, dungeon = L("Недоступная группа"),
                members = 0, score = 0, bestLevel = 0,
                rejected = true, rejectionReason = reason, actionable = true,
            }
        end
        if match then
            match.sourceOrder = sourceOrder
            matches[#matches + 1] = match
        elseif reason then
            rejected[reason] = (rejected[reason] or 0) + 1
            rejectedMatch = rejectedMatch or {
                searchResultID = searchResultID, dungeon = L("Недоступная группа"),
                members = 0, score = 0, bestLevel = 0,
                rejected = true, rejectionReason = reason, actionable = false,
            }
            rejectedMatch.sourceOrder = sourceOrder
            excluded[#excluded + 1] = rejectedMatch
        end
    end
    ResetCache()

    JP:Log(L("скан: подошло %d из %d"), #matches, total)
    if JP:IsLogging() then
        for reason, count in pairs(rejected) do JP:Log(L("  отсеяно (%s): %d"), reason, count) end
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
    table.sort(excluded, function(a, b) return (a.sourceOrder or math.huge) < (b.sourceOrder or math.huge) end)
    return matches, nil, total, rejected, excluded
end

function AutoMatch:Apply(match, editBeforeApply)
    local searchResultID = type(match) == "table" and match.searchResultID or match
    local info = searchResultID and C_LFGList.GetSearchResultInfo(searchResultID)
    if not info or SafeBoolean(info.isDelisted) then
        JP:Print(L("Эта группа уже исчезла. Обнови список."))
        return false
    end
    -- Both branches begin with Blizzard's own protected dialog. Because this
    -- function is called directly from the user's mouse click, its Sign Up
    -- button may also be clicked synchronously in the same hardware event.
    -- Shift deliberately keeps the dialog open for role/note editing.
    if type(LFGListApplicationDialog_Show) == "function" and LFGListApplicationDialog then
        if not editBeforeApply and type(SetLFGRoles) == "function"
            and type(GetSpecialization) == "function" and type(GetSpecializationRole) == "function" then
            local spec = GetSpecialization()
            local role = spec and GetSpecializationRole(spec)
            if role == "TANK" or role == "HEALER" or role == "DAMAGER" then
                pcall(SetLFGRoles, role == "TANK", role == "HEALER", role == "DAMAGER")
            end
        end
        local ok = pcall(LFGListApplicationDialog_Show, LFGListApplicationDialog, searchResultID)
        if ok then
            if editBeforeApply then
                local description = _G.LFGListApplicationDialogDescription
                local editBox = description and description.EditBox
                if editBox then
                    editBox:Show()
                    editBox:SetFocus()
                    editBox:HighlightText(0, 0)
                end
                return true
            end

            -- Another addon may already implement one-click signup in its
            -- OnShow hook. In that case the dialog has disappeared and the
            -- application is already sent; never click the stale button twice.
            if not LFGListApplicationDialog:IsShown() then return true end
            local signUp = LFGListApplicationDialog.SignUpButton
            if signUp and signUp:IsEnabled() then
                local clicked = pcall(signUp.Click, signUp)
                if clicked then return true end
            end
            JP:Print(L("Не удалось отправить заявку одним кликом — проверь выбранную роль в открытом окне."))
            return true
        end
    end

    JP:Print(L("Окно заявки Blizzard сейчас недоступно. Открой поиск подземелий и попробуй ещё раз."))
    return false
end

function AutoMatch:Cancel(match)
    local searchResultID = type(match) == "table" and match.searchResultID or match
    if not searchResultID or type(C_LFGList.CancelApplication) ~= "function" then
        JP:Print(L("Отмена заявки сейчас недоступна."))
        return false
    end
    local state = JP.API.GetApplicationState(searchResultID)
    if not state.readable then
        JP:Print(L("Blizzard пока не отдал состояние заявки."))
        return false
    end
    if state.pending then
        JP:Print(L("Заявка ещё обрабатывается. Повтори отмену через секунду."))
        return false
    end
    if state.status ~= "applied" then
        JP:Print(state.status == "invited" and L("На эту группу уже пришло приглашение.") or L("Активной заявки уже нет."))
        return false
    end

    -- CancelApplication защищён hardware event, поэтому вызов остаётся
    -- непосредственно внутри клика пользователя по кнопке.
    local ok = pcall(C_LFGList.CancelApplication, searchResultID)
    if not ok then
        JP:Print(L("Blizzard не разрешил отменить заявку сейчас."))
        return false
    end
    return true
end

function AutoMatch:Enable() end
function AutoMatch:Disable() ResetCache() end
function AutoMatch:Destroy() ResetCache() end
JP.AutoMatch = AutoMatch
JP:RegisterModule("AutoMatch", AutoMatch)
