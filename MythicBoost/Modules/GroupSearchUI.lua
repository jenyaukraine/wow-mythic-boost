local _, JP = ...
local L = JP.L
local GroupSearchUI = {}
local UI = JP.UI
local C = UI.colors

local SEASON_ORDER = { 588, 584, 586, 587, 585, 399, 250, 249 }
local DUNGEON_SHORT = { [588] = L("АК"), [584] = L("СД"), [586] = L("БН"), [587] = L("ЗД"), [585] = L("АШ"), [399] = L("РО"), [250] = L("ХС"), [249] = L("ГК") }
-- Точные activityGroupID текущего пула Midnight. Это те же идентификаторы,
-- которыми пользуется Premade Groups Filter; сопоставление по переведённому
-- названию оставлено ниже только как fallback для следующей ротации сезона.
local ACTIVITY_GROUP_BY_MAP = {
    [588] = 420, -- Altar of Fangs
    [584] = 382, -- The Blinding Vale
    [586] = 392, -- Den of Nalorakk
    [587] = 396, -- Murder Row
    [585] = 398, -- Voidscar Arena
    [399] = 306, -- Ruby Life Pools
    [250] = 139, -- Temple of Sethraliss
    [249] = 141, -- Kings' Rest
}

local MAX_RESULT_ROWS = 12
local APPLICATION_CAP = JP.Limits.ACTIVE_APPLICATIONS
local ROW_HEIGHT, ROW_STEP = 62, 68
local CARD_HEIGHT, CARD_GAP = 80, 8
local CARD_PAD = 12
local CARD_ICON = 56
local CARD_COLUMN = CARD_PAD + CARD_ICON + 12
local CARD_ITEM_SIZE, CARD_ITEM_STEP = 24, 28
local CARD_BADGE_H = 24
local CARD_ROW_TITLE = -14
local CARD_ROW_ITEMS = -48
local ART_LEFT, ART_RIGHT, ART_TOP, ART_BOTTOM = .095, .775, .237, .897
local CARDS_HEIGHT = 30 + CARD_HEIGHT * 2 + CARD_GAP + 10
local FILTERS_WIDTH = 238
-- Эти функции используются серверным фильтром, который объявлен раньше
-- блока карточек. Без forward declaration Lua искал глобальные функции и
-- запрос падал уже после Disable() кнопки, оставляя вечное «Поиск...».
local SelectedCount, IsCardSelected

-- Одна таблица геометрии на заголовки и на строки: колонки не могут
-- разъехаться, потому что оба места читают одни и те же числа.
local COL = {
    applyWidth = 94, applyRight = 12,
    ageWidth = 58, ageRight = 116,
    leaderWidth = 132, leaderRight = 184,
    rolesWidth = 106, rolesRight = 326,
    contentRight = 446,
    keyLeft = 12, keyWidth = 48,
    textLeft = 70,
}

local UsableNumber, SafeString = UI.UsableNumber, UI.SafeString
local SafeBoolean, SafeTable = UI.SafeBoolean, UI.SafeTable

local function OwnedKeystoneListingInfo()
    if C_LFGList and type(C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel) == "function" then
        local ok, activityID, groupID, level = pcall(C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel)
        if ok and UsableNumber(activityID) and UsableNumber(groupID) and UsableNumber(level) and level > 0 then
            return activityID, groupID, level
        end
    end
end

-- Creating a listing is protected by Blizzard. Open and prefill the native
-- creation form; the player performs the final protected click there.
local function OpenOwnKeystoneListingForm()
    if InCombatLockdown and InCombatLockdown() then
        JP:Print(L("Создание группы недоступно в бою."))
        return
    end
    if type(C_LFGList) ~= "table" then
        JP:Print(L("Blizzard API создания группы пока не загружен."))
        return
    end
    if C_LFGList.HasActiveEntryInfo and C_LFGList.HasActiveEntryInfo() then
        JP:Print(L("Группа уже зарегистрирована в поиске."))
        return
    end
    if IsInGroup and IsInGroup(LE_PARTY_CATEGORY_HOME)
        and UnitIsGroupLeader and not UnitIsGroupLeader("player", LE_PARTY_CATEGORY_HOME) then
        JP:Print(L("Создать объявление может только лидер группы."))
        return
    end

    local activityID, groupID = OwnedKeystoneListingInfo()
    if not activityID then
        JP:Print(L("Свой мифический ключ не найден."))
        return
    end

    local serious = Enum and Enum.LFGEntryGeneralPlaystyle and Enum.LFGEntryGeneralPlaystyle.FunSerious
    local pveFilter = Enum and Enum.LFGListFilter and Enum.LFGListFilter.PvE
    local activityInfo = C_LFGList.GetActivityInfoTable and C_LFGList.GetActivityInfoTable(activityID)
    local categoryID = type(activityInfo) == "table" and activityInfo.categoryID
    if not serious or not pveFilter or not UsableNumber(categoryID) then
        JP:Print(L("Blizzard API создания группы пока не загружен."))
        return
    end

    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_PVEFrame")
        pcall(C_AddOns.LoadAddOn, "Blizzard_GroupFinder")
    end
    local ready = _G.PVEFrame_ShowFrame and _G.LFGListPVEStub and _G.LFGListFrame
        and _G.LFGListEntryCreation_Show and _G.LFGListEntryCreation_Select
        and _G.LFGListEntryCreation_OnPlayStyleSelectedInternal
    if not ready then
        JP:Print(L("Окно заявки Blizzard сейчас недоступно. Открой поиск подземелий и попробуй ещё раз."))
        return
    end

    local filters = UsableNumber(activityInfo.filters) and activityInfo.filters or 0
    local welcome = JP.modules and JP.modules.Welcome
    local restoreWelcome = welcome and welcome.frame and welcome.frame:IsShown()
    if restoreWelcome then welcome.frame:Hide() end
    local ok = pcall(function()
        PVEFrame_ShowFrame("GroupFinderFrame", LFGListPVEStub)
        local panel = LFGListFrame.EntryCreation
        LFGListEntryCreation_Show(panel, pveFilter, categoryID, filters)
        LFGListEntryCreation_Select(panel, filters, categoryID, groupID, activityID)
        LFGListEntryCreation_OnPlayStyleSelectedInternal(panel, serious)
    end)
    if not ok then
        if restoreWelcome then welcome.frame:Show() end
        JP:Print(L("Окно заявки Blizzard сейчас недоступно. Открой поиск подземелий и попробуй ещё раз."))
    end
end

-- One public action for every "create/manage listing" button. Keeping it in
-- one place prevents the empty-state button and the compact key card from
-- disagreeing about what a click should do.
function GroupSearchUI:OpenListingAction()
    OpenOwnKeystoneListingForm()
end

-- fileID = 0 приходит от API как «текстуры нет». Без этой проверки
-- SetTexture(0) рисует чёрный прямоугольник вместо карточки.
local function ValidTexture(value)
    if type(value) == "number" and not issecretvalue(value) and value > 0 then return value end
    if type(value) == "string" and not issecretvalue(value) and value ~= "" then return value end
end

---------------------------------------------------------------------------
-- Данные Raider.IO
---------------------------------------------------------------------------

local function PlayerRuns()
    if not RaiderIO or type(RaiderIO.GetProfile) ~= "function" then return {} end
    local ok, profile = pcall(RaiderIO.GetProfile, "player")
    local keystone = ok and profile and profile.mythicKeystoneProfile
    return keystone and keystone.sortedDungeons or {}
end

local function RaiderProfile(name)
    if not RaiderIO or type(RaiderIO.GetProfile) ~= "function" or not SafeString(name) then return end
    -- Публичный API Raider.IO: GetProfile(name, realm[, region]). Один
    -- аргумент трактуется как unit-token, поэтому "Name-Realm" раньше
    -- никогда не искался в базе как персонаж с указанного сервера.
    local character, realm = name:match("^([^%-]+)%-(.+)$")
    local ok, profile
    if character and realm then
        ok, profile = pcall(RaiderIO.GetProfile, character, realm)
    else
        ok, profile = pcall(RaiderIO.GetProfile, name)
    end
    return ok and profile or nil
end

-- Класс участника известен из поиска групп, а профиль Raider.IO иногда несёт
-- свой. Несовпадение — верный признак, что это тёзка с другого реалма.
local classIDByFile
local function ClassIDForFile(classFilename)
    if type(classFilename) ~= "string" then return end
    if not classIDByFile then
        classIDByFile = {}
        for index = 1, (GetNumClasses and GetNumClasses() or 0) do
            local _, file, id = GetClassInfo(index)
            if file then classIDByFile[file] = id end
        end
    end
    return classIDByFile[classFilename]
end

local function ProfileClassID(profile)
    if type(profile) ~= "table" then return end
    local value = profile.classID or (type(profile.class) == "table" and profile.class.id)
    return type(value) == "number" and value or nil
end

local function ProfileForName(name, classFilename)
    local profile = RaiderProfile(name)
    local wanted, actual = ClassIDForFile(classFilename), ProfileClassID(profile)
    if wanted and actual and wanted ~= actual then return end
    return profile
end

local function ProfileScore(profile)
    return UI.KeystoneScore(profile and profile.mythicKeystoneProfile)
end

-- Имя участника приходит без реалма, а группы кросс-реалмовые. Раньше брался
-- первый попавшийся профиль — и в таблицу попадали ключи однофамильца с
-- соседнего реалма. Теперь догадка принимается только если она одна:
-- при нескольких совпадениях показываем прочерк, а не чужие данные.
local profileRunCache, resolvedProfileCache = {}, {}
local PROFILE_CACHE_LIMIT = JP.Limits.PROFILE_CACHE_ENTRIES
local profileCacheEntries = 0

local function RememberProfileCache(cache, key, value)
    if cache[key] == nil then
        profileCacheEntries = profileCacheEntries + 1
        if profileCacheEntries > PROFILE_CACHE_LIMIT then
            wipe(profileRunCache)
            wipe(resolvedProfileCache)
            profileCacheEntries = 1
        end
    end
    cache[key] = value == nil and false or value
    return value
end

local function RunsRank(runs)
    local rank = 0
    for _, run in ipairs(type(runs) == "table" and runs or {}) do
        local level = tonumber(run.bestRunLevel or run.level) or 0
        local increment = tonumber(run.bestLevelIncrement or run.upgrades) or 0
        rank = rank + level * 10 + increment
    end
    return rank
end

local function ResolveRaiderProfile(name, leaderName, classFilename)
    name = SafeString(name)
    if not name then return end
    local cacheKey = ("%s|%s|%s"):format(name, tostring(leaderName or ""), tostring(classFilename or ""))
    if resolvedProfileCache[cacheKey] ~= nil then return resolvedProfileCache[cacheKey] or nil end

    local function Remember(profile)
        return RememberProfileCache(resolvedProfileCache, cacheKey, profile)
    end

    -- Реалм известен точно.
    if name:find("-", 1, true) then
        return Remember(ProfileForName(name, classFilename))
    end

    -- Лидер назван полностью, и это он же.
    local leader = SafeString(leaderName)
    local leaderBase, leaderRealm
    if leader then leaderBase, leaderRealm = leader:match("^([^%-]+)%-(.+)$") end
    if leaderBase and leaderBase:lower() == name:lower() then
        return Remember(ProfileForName(leader, classFilename))
    end

    -- Дальше только догадки: собираем все и требуем единственного попадания.
    local realms, seen = {}, {}
    local function AddRealm(realm)
        if type(realm) ~= "string" or realm == "" or seen[realm:lower()] then return end
        seen[realm:lower()] = true
        realms[#realms + 1] = realm
    end
    AddRealm(leaderRealm)
    AddRealm(GetNormalizedRealmName and GetNormalizedRealmName())
    if GetAutoCompleteRealms then
        for _, realm in ipairs({ GetAutoCompleteRealms() }) do AddRealm(realm) end
    end
    -- Имена участников LFG приходят без realm даже в кросс-серверной группе.
    -- Raider.IO знает профиль только по паре name+realm, поэтому после быстрых
    -- догадок перебираем локальный EU-индекс. При нескольких совпадениях ничего
    -- не подставляем: чужой одноимённый персонаж хуже честного прочерка.
    local nearCount = #realms
    for _, realm in ipairs(JP.RaiderIORealmsEU or {}) do AddRealm(realm) end

    -- Сначала связанные реалмы, и только если там пусто — весь EU-индекс.
    -- Раньше перебор шёл по всем 267 записям без остановки на каждого
    -- участника каждой группы: на сотне объявлений это сотни тысяч обращений
    -- к Raider.IO в одном кадре, и клиент заметно подвисал при обновлении.
    local function ScanRealms(from, to)
        local best, count, bestRank = nil, 0, -1
        for index = from, to do
            local profile = ProfileForName(name .. "-" .. realms[index], classFilename)
            if profile then
                count = count + 1
                local keystone = profile.mythicKeystoneProfile
                local runs = keystone and keystone.sortedDungeons
                local rank = (ProfileScore(profile) or 0) * 10000 + RunsRank(runs)
                if rank > bestRank then best, bestRank = profile, rank end
            end
        end
        return best, count
    end

    local found, hits = ScanRealms(1, nearCount)
    if hits == 0 then found, hits = ScanRealms(nearCount + 1, #realms) end
    -- Blizzard скрывает реалм обычных участников. Если одноимённых профилей
    -- несколько, берём наиболее актуальный M+ профиль того же класса. Это
    -- полезнее вечных прочерков и соответствует приблизительному fallback,
    -- который используется только когда точного realm в данных нет.
    if hits > 0 then
        if hits > 1 then JP:Log(L("реалм выбран приблизительно: %s (%d профилей)"), name, hits) end
        return Remember(found)
    end
    return Remember(nil)
end

local function ResolveRaiderRuns(name, leaderName, classFilename)
    name = SafeString(name)
    if not name then return end
    local cacheKey = ("%s|%s|%s"):format(name, tostring(leaderName or ""), tostring(classFilename or ""))
    if profileRunCache[cacheKey] ~= nil then return profileRunCache[cacheKey] or nil end
    local profile = ResolveRaiderProfile(name, leaderName, classFilename)
    local keystone = profile and profile.mythicKeystoneProfile
    local runs = keystone and keystone.sortedDungeons
    RememberProfileCache(profileRunCache, cacheKey, type(runs) == "table" and #runs > 0 and runs or nil)
    return profileRunCache[cacheKey] or nil
end

function GroupSearchUI:ClearProfileCache()
    wipe(profileRunCache)
    wipe(resolvedProfileCache)
    profileCacheEntries = 0
end

local function PartyRatingColorCode(value)
    value = tonumber(value) or 0
    if value >= 3000 then return "ffb93d" end
    if value >= 2500 then return "b36cff" end
    if value >= 2000 then return "32b6ff" end
    return "43d17a"
end

local function CurrentPlayerRole()
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")
    if role ~= "TANK" and role ~= "HEALER" and role ~= "DAMAGER" then
        local spec = GetSpecialization and GetSpecialization()
        role = spec and GetSpecializationRole and GetSpecializationRole(spec) or "DAMAGER"
    end
    return role
end

-- Это не выдуманный «шанс инвайта», а порядок, куда выгоднее подаваться.
-- Геометрическая свёртка не даёт одному сильному параметру полностью скрыть
-- плохой: старое объявление с ненужной ролью не станет первым из-за уровня.
local function CalculateApplicationPriority(match, ownScore, playerRole)
    local exactLevel = match.keyLevel and not match.keyApprox and not match.keyLevelProtected
        and tonumber(match.keyLevel) or nil
    local level = exactLevel or tonumber(match.targetLevel or match.keyLevel)
    local best = tonumber(match.bestLevel) or 0
    local delta = level and (level - best) or 0
    local upgrade = level and math.max(.35, math.min(1, .55 + delta * .15)) or .48

    local counts = match.roleCounts or {}
    local roleNeeded = (playerRole == "TANK" and (counts.TANK or 0) == 0)
        or (playerRole == "HEALER" and (counts.HEALER or 0) == 0)
        or (playerRole == "DAMAGER" and (counts.DAMAGER or 0) < 3)
    local demand = roleNeeded and 1 or .72

    local members = math.max(1, tonumber(match.partyScoreMembers or match.members) or 1)
    local known = math.min(members, tonumber(match.partyScoreKnown) or 0)
    local average = tonumber(match.partyScoreAverage) or 0
    local gap = ownScore > 0 and average > 0 and math.abs(average - ownScore) or 700
    local scoreFit = 1 / (1 + gap / 1100)
    local dataCoverage = .55 + .45 * known / members
    local almostReady = .68 + .32 * math.min(4, members) / 4
    local composition = math.sqrt(scoreFit * dataCoverage) * almostReady

    local age = math.max(0, tonumber(match.age) or 600)
    local freshness = math.max(.35, math.exp(-age / 720))
    local certainty = match.keyApprox and .82 or (level and 1 or .70)
    local raw = (upgrade ^ .32) * (demand ^ .24) * (composition ^ .28) * (freshness ^ .16) * certainty
    local priority = math.max(1, math.min(100, math.floor(raw * 100 + .5)))

    local reasons = {}
    if delta > 0 then reasons[#reasons + 1] = L("выше твоего рекорда") end
    if roleNeeded then reasons[#reasons + 1] = L("твоя роль нужна") end
    if members >= 4 then reasons[#reasons + 1] = L("почти готовая группа") end
    if age <= 120 then reasons[#reasons + 1] = L("свежее объявление") end
    if #reasons == 0 then
        reasons[1] = match.keyApprox and L("уровень ключа приблизительный") or L("подходит базовым фильтрам")
    end
    return priority, table.concat(reasons, L(", "))
end

local function ProfileBestForMap(profile, mapID)
    local keystone = profile and profile.mythicKeystoneProfile
    for _, run in ipairs(type(keystone and keystone.sortedDungeons) == "table" and keystone.sortedDungeons or {}) do
        local dungeon = run and run.dungeon
        local runMapID = dungeon and (dungeon.keystone_instance or dungeon.id)
        if tonumber(runMapID) == tonumber(mapID) then
            return tonumber(run.bestRunLevel or run.level) or 0
        end
    end
    return 0
end

local function BlizzardBestForMap(scoreInfo, mapID)
    for _, entry in ipairs(SafeTable(scoreInfo) or {}) do
        local runMapID = UsableNumber(entry.challengeModeID) and entry.challengeModeID
            or (UsableNumber(entry.mapChallengeModeID) and entry.mapChallengeModeID)
        if tonumber(runMapID) == tonumber(mapID) then return tonumber(entry.bestRunLevel) or 0 end
    end
    return 0
end

-- Считаем силу всей уже собранной группы. Точный общий рейтинг лидера
-- приходит от Blizzard, остальные профили берём из локальной базы Raider.IO.
-- Делитель — фактическое количество людей, как и ожидается от среднего.
local EXPERIENCE_REJECTION = L("не все участники проходили этот уровень")

function GroupSearchUI:EnrichPartyRatings(matches, filters, excluded)
    filters = filters or {}
    excluded = excluded or {}
    for _, match in ipairs(type(matches) == "table" and matches or {}) do
        local members = type(match.memberInfo) == "table" and match.memberInfo or {}
        local memberCount = math.max(tonumber(match.members) or 0, #members)
        local total, known, leaderCounted = 0, 0, false
        local requiredLevel = (match.keyLevel and not match.keyApprox and match.keyLevel)
            or match.targetLevel
        local everyoneExperienced = requiredLevel ~= nil
        local experienceConfirmed = 0

        for _, member in ipairs(members) do
            local memberName = SafeString(member.name)
            local leaderBase = match.leaderName and match.leaderName:match("^([^%-]+)")
            local isLeader = member.isLeader
                or (leaderBase and memberName and leaderBase:lower() == memberName:lower())
            local lookupName = memberName or (isLeader and match.leaderName)
            local profile = ResolveRaiderProfile(lookupName, match.leaderName, member.classFilename)
            local score
            if isLeader and UsableNumber(match.score) and match.score > 0 then
                score, leaderCounted = match.score, true
            else
                score = ProfileScore(profile)
            end
            if UsableNumber(score) and score > 0 then
                total, known = total + score, known + 1
            end
            if filters.experiencedParty == true then
                local best = ProfileBestForMap(profile, match.mapID)
                if isLeader and best <= 0 then best = BlizzardBestForMap(match.leaderDungeonScoreInfo, match.mapID) end
                if requiredLevel and best >= requiredLevel then
                    experienceConfirmed = experienceConfirmed + 1
                else
                    everyoneExperienced = false
                end
            end
        end

        if not leaderCounted and UsableNumber(match.score) and match.score > 0 then
            total, known = total + match.score, known + 1
            memberCount = math.max(memberCount, 1)
        end
        memberCount = math.max(memberCount, 1)
        match.partyScoreTotal = total
        match.partyScoreKnown = math.min(known, memberCount)
        match.partyScoreMembers = memberCount
        -- Неизвестный профиль снижает уверенность отдельно; считать его как
        -- нулевой RIO и занижать среднее вдвое математически неверно.
        match.partyScoreAverage = known > 0 and total / known or 0
        match.experienceRequiredLevel = requiredLevel
        match.experienceConfirmed = experienceConfirmed
        match.everyoneExperienced = everyoneExperienced and experienceConfirmed == memberCount
    end

    local experienceRejected = 0
    if filters.experiencedParty == true then
        for index = #matches, 1, -1 do
            if not matches[index].everyoneExperienced then
                local match = table.remove(matches, index)
                match.rejected = true
                match.rejectionReason = EXPERIENCE_REJECTION
                match.actionable = true
                excluded[#excluded + 1] = match
                experienceRejected = experienceRejected + 1
            end
        end
    end

    local ownScore = C_ChallengeMode.GetOverallDungeonScore and C_ChallengeMode.GetOverallDungeonScore() or 0
    ownScore = UsableNumber(ownScore) and ownScore or 0
    local playerRole = CurrentPlayerRole()
    for _, match in ipairs(type(matches) == "table" and matches or {}) do
        match.applicationPriority, match.applicationReason = CalculateApplicationPriority(match, ownScore, playerRole)
        -- Coach metadata is derived from the canonical priority score; it is
        -- descriptive UI state, never a second ranking model.
        local known = tonumber(match.partyScoreKnown) or 0
        local members = math.max(1, tonumber(match.partyScoreMembers or match.members) or 1)
        local coverage = math.floor(math.min(1, known / members) * 100 + .5)
        local keyConfidence = match.keyLevelProtected and 45 or (match.keyApprox and 70 or (match.keyLevel and 100 or 35))
        match.applicationConfidence = math.floor((coverage * .55 + keyConfidence * .45) + .5)
        match.applicationUnknowns = {}
        if known < members then match.applicationUnknowns[#match.applicationUnknowns + 1] = L("неполный RIO") end
        if match.keyLevelProtected or match.keyApprox then
            match.applicationUnknowns[#match.applicationUnknowns + 1] = L("уровень ключа скрыт или оценён")
        end
        if #match.applicationUnknowns > 0 then
            match.applicationState = "unknown"
        elseif (match.applicationPriority or 0) >= 70 then
            match.applicationState = "ready"
        elseif (match.applicationPriority or 0) >= 45 then
            match.applicationState = "risky"
        else
            match.applicationState = "unknown"
        end
        match.applicationReasons = {}
        for reason in tostring(match.applicationReason or ""):gmatch("[^,]+") do
            match.applicationReasons[#match.applicationReasons + 1] = reason:gsub("^%s+", ""):gsub("%s+$", "")
        end
    end

    table.sort(matches, function(a, b)
        if (a.applicationPriority or 0) ~= (b.applicationPriority or 0) then
            return (a.applicationPriority or 0) > (b.applicationPriority or 0)
        end
        -- Более собранная группа выше: в ней меньше ожидания и меньше риска,
        -- что хороший лидер исчезнет, пока добираются остальные роли.
        local membersA, membersB = a.partyScoreMembers or a.members or 0, b.partyScoreMembers or b.members or 0
        if membersA ~= membersB then return membersA > membersB end
        local averageA, averageB = a.partyScoreAverage or 0, b.partyScoreAverage or 0
        if averageA ~= averageB then return averageA > averageB end
        local levelA, levelB = a.targetLevel or a.keyLevel or 0, b.targetLevel or b.keyLevel or 0
        if levelA ~= levelB then return levelA > levelB end
        if (a.partyScoreKnown or 0) ~= (b.partyScoreKnown or 0) then
            return (a.partyScoreKnown or 0) > (b.partyScoreKnown or 0)
        end
        if (a.score or 0) ~= (b.score or 0) then return (a.score or 0) > (b.score or 0) end
        return (a.age or math.huge) < (b.age or math.huge)
    end)
    table.sort(excluded, function(a, b)
        return (a.sourceOrder or math.huge) < (b.sourceOrder or math.huge)
    end)
    return experienceRejected
end

function GroupSearchUI:ComposeResults(matches, excluded)
    local results = {}
    for _, match in ipairs(matches or {}) do results[#results + 1] = match end
    local settings = JP.Settings and JP.Settings("search", {
        showRejectedResults = true,
        allowRejectedApplications = true,
    })
    local showRejected = not settings or settings.showRejectedResults ~= false
    if showRejected and #(excluded or {}) > 0 then
        results[#results + 1] = {
            isSection = true,
            sectionCount = #excluded,
            sectionLabel = (L("НЕ ПРОШЛИ ФИЛЬТРЫ - %d")):format(#excluded),
        }
        for _, match in ipairs(excluded) do results[#results + 1] = match end
    end
    return results
end

local function TimedValue(level, increments, finished)
    if not UsableNumber(level) or level <= 0 then return "—", "missing" end
    increments = UsableNumber(increments) and math.max(0, math.min(3, increments)) or (finished and 1 or 0)
    local grade = increments == 0 and "depleted"
        or increments == 1 and "timed"
        or increments == 2 and "plusTwo"
        or "plusThree"
    return (increments > 0 and string.rep("+", increments) or "") .. level, grade
end

local RUN_GRADE_COLOR = {
    missing = { .30, .34, .40 },
    depleted = { .48, .50, .54 },
    timed = { 1, 1, 1 },
    plusTwo = { .30, .92, .56 },
    plusThree = { .70, .36, 1 },
}

local BELOW_KEY_COLOR = { 1, .24, .30 }

local function RunLevel(run)
    return tonumber(run and (run.bestRunLevel or run.level)) or 0
end

local function RunUpgrades(run)
    local value = tonumber(run and (run.bestLevelIncrement or run.chests or run.upgrades)) or 0
    return math.max(0, math.min(3, value))
end

-- Стандартная локальная база Raider.IO хранит лучший результат каждого
-- подземелья, но не число всех его прохождений. Оставляем поддержку точного
-- счётчика, если другой провайдер профиля его добавил, и никогда не выдаём
-- единственную запись «лучшего рана» за количество всех ранов.
local function DungeonRunCount(run)
    if type(run) ~= "table" then return end
    local value = run.numRuns or run.runCount or run.completedRuns or run.runsCompleted
    if type(value) == "number" and not issecretvalue(value) and value >= 0 then return math.floor(value) end
    if type(run.runs) == "table" and not issecretvalue(run.runs) then return #run.runs end
end

local function ProfileMilestones(profile)
    local keystone = profile and profile.mythicKeystoneProfile
    local source = keystone and keystone.sortedMilestones
    local milestones = {}
    for _, entry in ipairs(type(source) == "table" and source or {}) do
        local label = SafeString(entry.label)
        local text = SafeString(entry.text)
        if label and text then
            milestones[#milestones + 1] = { label = label, text = text, level = tonumber(entry.level) or 0 }
        end
    end
    return milestones
end

local function LeaderKeyValue(entry)
    return TimedValue(entry and entry.bestRunLevel, entry and entry.bestLevelIncrement, entry and entry.finishedSuccess)
end

local function RaiderKeyValue(run)
    return TimedValue(run and run.level, run and run.chests, false)
end

local function DungeonKey(dungeon)
    return dungeon and (dungeon.keystone_instance or dungeon.id or dungeon.shortNameLocale or dungeon.shortName or dungeon.name)
end

local function DungeonKeyTexture(mapID)
    mapID = tonumber(mapID)
    local info = mapID and JP.API.GetChallengeMap(mapID)
    return info and (ValidTexture(info.icon) or ValidTexture(info.background))
end

local function DungeonColumns()
    local columns = {}
    for index, run in ipairs(PlayerRuns()) do
        if #columns >= 8 then break end
        local dungeon = run and run.dungeon
        local key = DungeonKey(dungeon)
        local mapID = tonumber(key)
        local challengeIcon, challengeBackground
        if mapID then
            local info = JP.API.GetChallengeMap(mapID)
            challengeIcon = info and info.icon
            challengeBackground = info and info.background
        end
        columns[#columns + 1] = {
            key = key or index,
            label = DUNGEON_SHORT[key] or (dungeon and (dungeon.shortNameLocale or dungeon.shortName)) or tostring(index),
            name = dungeon and dungeon.name,
            -- Для мини-таблиц нужна квадратная иконка Challenge Mode, а не
            -- широкий фон карточки, который при обрезке выглядит случайно.
            texture = ValidTexture(challengeIcon) or ValidTexture(dungeon and dungeon.icon)
                or ValidTexture(challengeBackground) or ValidTexture(dungeon and dungeon.background),
        }
    end
    if #columns == 0 then
        for index, mapID in ipairs(SEASON_ORDER) do
            local info = JP.API.GetChallengeMap(mapID) or {}
            columns[#columns + 1] = {
                key = mapID, label = DUNGEON_SHORT[mapID] or tostring(index), name = info.name,
                texture = ValidTexture(info.icon) or ValidTexture(info.background),
            }
        end
    end
    return columns
end

local function RunsByDungeon(runs)
    local mapped = {}
    for index, run in ipairs(type(runs) == "table" and runs or {}) do
        mapped[DungeonKey(run and run.dungeon) or index] = run
    end
    return mapped
end

-- Строка «ключи игрока по всем подземельям сезона» одним куском.
--
-- Разбор профиля Raider.IO, порядок подземелий и раскраска уже живут здесь,
-- поэтому таблица кандидатов берёт готовый результат, а не заводит свою
-- копию той же логики.
function GroupSearchUI:GetDungeonSummary(fullName, classFilename)
    local cells = self:GetDungeonCells(fullName, classFilename)
    if not cells then return nil end
    local parts = {}
    for _, cell in ipairs(cells) do
        local color = cell.value == "—" and "|cff454b54" or "|cff43d17a"
        parts[#parts + 1] = ("|cff5b6470%s|r %s%s|r"):format(cell.label, color, cell.value)
    end
    return table.concat(parts, "   ")
end

function GroupSearchUI:GetDungeonCells(fullName, classFilename)
    local profile = ResolveRaiderProfile(fullName, nil, classFilename)
    local keystone = profile and profile.mythicKeystoneProfile
    local runs = keystone and keystone.sortedDungeons
    if type(runs) ~= "table" or #runs == 0 then return nil end
    local mapped = RunsByDungeon(runs)
    local milestones = ProfileMilestones(profile)
    local cells = {}
    for index, column in ipairs(DungeonColumns()) do
        local run = mapped[column.key]
        local value, grade = RaiderKeyValue(run)
        cells[index] = {
            mapID = column.key,
            label = column.label,
            value = value,
            grade = grade,
            level = RunLevel(run),
            upgrades = RunUpgrades(run),
            runCount = DungeonRunCount(run),
            milestones = milestones,
        }
    end
    return cells
end

-- Данные уже собранной пати для отдельной таблицы на странице кандидатов.
-- Для unit-token Raider.IO сам знает точный realm, поэтому здесь не нужен
-- приблизительный перебор одноимённых персонажей из результатов LFG.
function GroupSearchUI:GetPartyMemberProfile(unit)
    if type(unit) ~= "string" or not UnitExists(unit) then return nil end

    local profile
    if RaiderIO and type(RaiderIO.GetProfile) == "function" then
        local ok, value = pcall(RaiderIO.GetProfile, unit)
        if ok then profile = value end
    end
    if not profile then
        local name, realm = UnitFullName(unit)
        local _, classFilename = UnitClass(unit)
        if name then profile = ProfileForName(realm and realm ~= "" and (name .. "-" .. realm) or name, classFilename) end
    end

    local runs = profile and profile.mythicKeystoneProfile and profile.mythicKeystoneProfile.sortedDungeons
    local mapped = RunsByDungeon(runs)
    local milestones = ProfileMilestones(profile)
    local cells = {}
    for index, column in ipairs(DungeonColumns()) do
        local run = mapped[column.key]
        local value, grade = RaiderKeyValue(run)
        cells[index] = {
            mapID = column.key,
            value = value,
            grade = grade,
            level = RunLevel(run),
            label = column.label,
            upgrades = RunUpgrades(run),
            runCount = DungeonRunCount(run),
            milestones = milestones,
        }
    end
    return {
        score = ProfileScore(profile) or 0,
        known = profile ~= nil,
        cells = cells,
    }
end

function GroupSearchUI:GetPartyDungeonColumns()
    return DungeonColumns()
end

function GroupSearchUI:GetPartyRatingColor(value)
    return PartyRatingColorCode(value)
end

function GroupSearchUI:GetRunGradeColor(grade)
    return RUN_GRADE_COLOR[grade] or RUN_GRADE_COLOR.missing
end

-- Уровень, относительно которого окрашивается таблица текущей пати.
-- В первую очередь это явно введённый/последний запрошенный ключ. Собственный
-- камень игрока может быть заметно выше и не должен делать всю таблицу красной
-- во время поиска, например, +11.
local function BlizzardRunsByDungeon(scoreInfo, columns)
    local mapped = {}
    for index, entry in ipairs(SafeTable(scoreInfo) or {}) do
        local key = UsableNumber(entry.challengeModeID) and entry.challengeModeID
            or (UsableNumber(entry.mapChallengeModeID) and entry.mapChallengeModeID)
        local mapName = SafeString(entry.mapName)
        if not key and mapName then
            for _, column in ipairs(columns) do if column.name == mapName then key = column.key break end end
        end
        mapped[key or (columns[index] and columns[index].key) or index] = entry
    end
    return mapped
end

---------------------------------------------------------------------------
-- Всплывающая таблица «участники × подземелья»
---------------------------------------------------------------------------

local TIP_NAME_WIDTH, TIP_CELL_WIDTH = 164, 56

local function GetGroupTooltip()
    if GroupSearchUI.groupTooltip then return GroupSearchUI.groupTooltip end
    local frame = CreateFrame("Frame", "MythicBoostGroupTooltip", UIParent, "BackdropTemplate")
    frame:SetSize(28 + TIP_NAME_WIDTH + TIP_CELL_WIDTH * 8, 190)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false)
    UI.Backdrop(frame, { .035, .045, .062, .98 }, { .22, .34, .46, 1 })

    frame.title = UI.Text(frame, "GameFontNormal", "", C.text)
    frame.title:SetPoint("TOPLEFT", 14, -12)
    frame.title:SetPoint("TOPRIGHT", -14, -12)
    frame.title:SetJustifyH("LEFT")
    frame.title:SetWordWrap(false)

    frame.meta = UI.Text(frame, "GameFontHighlightSmall", "", C.muted)
    frame.meta:SetPoint("TOPLEFT", 14, -32)
    frame.meta:SetPoint("TOPRIGHT", -126, -32)
    frame.meta:SetJustifyH("LEFT")
    frame.meta:SetWordWrap(false)

    frame.rioBadge = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.rioBadge:SetSize(104, 38)
    frame.rioBadge:SetPoint("TOPRIGHT", -12, -9)
    UI.Backdrop(frame.rioBadge, { .025, .040, .055, .98 }, { .20, .46, .62, .95 })
    frame.rioLabel = UI.Text(frame.rioBadge, "GameFontNormalSmall", L("СР. RIO"), C.muted)
    frame.rioLabel:SetPoint("TOP", 0, -3)
    frame.rioValue = UI.Text(frame.rioBadge, "GameFontNormal", "0", C.amber)
    frame.rioValue:SetPoint("BOTTOM", 0, 3)
    local rioFont = frame.rioValue:GetFont()
    if rioFont then frame.rioValue:SetFont(rioFont, 17, "OUTLINE") end

    local divider = UI.Line(frame, C.accentDim)
    divider:SetPoint("TOPLEFT", 12, -54)
    divider:SetPoint("TOPRIGHT", -12, -54)

    frame.playerHeader = UI.Text(frame, "GameFontNormalSmall", L("ИГРОК"), C.faint)
    frame.playerHeader:SetPoint("TOPLEFT", 14, -66)
    frame.playerHeader:SetWidth(TIP_NAME_WIDTH)
    frame.playerHeader:SetJustifyH("LEFT")

    frame.columnHeaders = {}
    for index = 1, 8 do
        local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        header:SetSize(22, 22)
        header:SetPoint("TOPLEFT",
            14 + TIP_NAME_WIDTH + (index - 1) * TIP_CELL_WIDTH + math.floor((TIP_CELL_WIDTH - 22) / 2), -60)
        UI.Backdrop(header, { .015, .022, .030, 1 }, { .18, .48, .62, .9 })
        header.icon = header:CreateTexture(nil, "ARTWORK")
        header.icon:SetPoint("TOPLEFT", 1, -1)
        header.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        header.icon:SetTexCoord(.07, .93, .07, .93)
        frame.columnHeaders[index] = header
    end

    frame.playerRows = {}
    for playerIndex = 1, 5 do
        local line = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        line:SetPoint("TOPLEFT", 10, -84 - (playerIndex - 1) * 24)
        line:SetPoint("TOPRIGHT", -10, -84 - (playerIndex - 1) * 24)
        line:SetHeight(22)
        UI.Backdrop(line, playerIndex % 2 == 0 and C.rowAlt or C.row, C.lineSoft)
        line.name = UI.Text(line, "GameFontHighlightSmall", "")
        line.name:SetPoint("LEFT", 6, 0)
        line.name:SetWidth(TIP_NAME_WIDTH - 4)
        line.name:SetJustifyH("LEFT")
        line.name:SetWordWrap(false)
        line.cells = {}
        for columnIndex = 1, 8 do
            local cell = UI.Text(line, "GameFontHighlightSmall", "")
            cell:SetPoint("LEFT", 4 + TIP_NAME_WIDTH + (columnIndex - 1) * TIP_CELL_WIDTH, 0)
            cell:SetWidth(TIP_CELL_WIDTH)
            cell:SetJustifyH("CENTER")
            line.cells[columnIndex] = cell
        end
        frame.playerRows[playerIndex] = line
    end

    frame:Hide()
    GroupSearchUI.groupTooltip = frame
    return frame
end

local function PositionGroupTooltip(tooltip, row, placement)
    tooltip:ClearAllPoints()
    if placement == "below" then
        local native = _G.GameTooltip
        if native and native:IsShown() and native ~= tooltip then
            local gap = 10
            local ownWidth, ownHeight = tooltip:GetWidth(), tooltip:GetHeight()
            local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
            local left, right = native:GetLeft(), native:GetRight()
            local top, bottom = native:GetTop(), native:GetBottom()

            -- The native group tooltip and Raider.IO normally occupy the upper
            -- half of the screen. Prefer the clear strip immediately below the
            -- native tooltip, then above/left, instead of drawing through it.
            if bottom and bottom >= ownHeight + gap then
                tooltip:SetPoint("TOPLEFT", native, "BOTTOMLEFT", 0, -gap)
                return
            elseif top and screenHeight - top >= ownHeight + gap then
                tooltip:SetPoint("BOTTOMLEFT", native, "TOPLEFT", 0, gap)
                return
            elseif left and left >= ownWidth + gap then
                tooltip:SetPoint("TOPRIGHT", native, "TOPLEFT", -gap, 0)
                return
            elseif right and screenWidth - right >= ownWidth + gap then
                tooltip:SetPoint("TOPLEFT", native, "TOPRIGHT", gap, 0)
                return
            end

            local x = math.max(12, math.min(left or 12, screenWidth - ownWidth - 12))
            tooltip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, 12)
            return
        end
        tooltip:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 0, -10)
        return
    end

    local spaceRight = (UIParent:GetRight() or 0) - (row:GetRight() or 0)
    if spaceRight > tooltip:GetWidth() + 18 then
        tooltip:SetPoint("TOPLEFT", row, "TOPRIGHT", 8, 0)
    else
        tooltip:SetPoint("TOPRIGHT", row, "TOPLEFT", -8, 0)
    end
end

local function ShowGroupTooltip(row, externalResultID, externalDungeonName, placement)
    local searchResultID = externalResultID or row.searchResultID
    local dungeonName = externalDungeonName or row.dungeonName
    if not searchResultID then return end
    local info = C_LFGList.GetSearchResultInfo(searchResultID)
    if not info then return end
    local tooltip = GetGroupTooltip()
    local columns = DungeonColumns()

    local leaderName = SafeString(info.leaderName)
    tooltip.title:SetText(SafeString(info.name) or dungeonName or L("Группа"))
    local match = row and row.match
    local listingKeyLevel = tonumber(match and (match.keyLevel or match.targetLevel))
    if not listingKeyLevel then
        -- На штатной строке Blizzard у нас нет match из AutoMatch, поэтому
        -- достаём тот же точный +N из названия/описания объявления локально.
        local function ParseListingLevel(text)
            text = SafeString(text)
            if not text then return end
            text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            local raw = text:match("%+%s*(%d%d?)")
                or text:match("＋%s*(%d%d?)")
                or text:match("﹢%s*(%d%d?)")
                or text:match("^%s*(%d%d?)%f[%D]")
            local level = tonumber(raw)
            if level and level >= 2 and level <= 40 then return level end
        end
        listingKeyLevel = ParseListingLevel(info.name) or ParseListingLevel(info.comment)
    end
    local ratingText, ratingValue
    local memberCount = UsableNumber(info.numMembers) and info.numMembers or 0
    if match and match.rejected then
        ratingText = (L("не прошло фильтр: %s")):format(match.rejectionReason or L("причина неизвестна"))
    elseif match and match.partyScoreAverage then
        ratingValue = math.floor(match.partyScoreAverage + .5)
        ratingText = (L("приоритет %d, средний RIO %d, найдено %d/%d")):format(
            match.applicationPriority or 0,
            ratingValue,
            match.partyScoreKnown or 0,
            match.partyScoreMembers or memberCount)
    else
        ratingValue = math.floor(UsableNumber(info.leaderOverallDungeonScore) and info.leaderOverallDungeonScore or 0)
        ratingText = (L("RIO лидера %d")):format(
            ratingValue)
    end
    tooltip.meta:SetText(("%s - %s%s"):format(
        dungeonName or L("Подземелье"), leaderName or L("лидер неизвестен"),
        match and (" - " .. (L("найдено %d/%d")):format(match.partyScoreKnown or 0,
            match.partyScoreMembers or memberCount)) or ""))
    ratingValue = ratingValue or 0
    tooltip.rioValue:SetText(tostring(ratingValue))
    local ratingHex = PartyRatingColorCode(ratingValue)
    tooltip.rioValue:SetTextColor(
        tonumber(ratingHex:sub(1, 2), 16) / 255,
        tonumber(ratingHex:sub(3, 4), 16) / 255,
        tonumber(ratingHex:sub(5, 6), 16) / 255, 1)

    for index, header in ipairs(tooltip.columnHeaders) do
        local column = columns[index]
        header.icon:SetTexture(column and column.texture or 134400)
        header:SetShown(column and column.texture and true or false)
    end

    for playerIndex, line in ipairs(tooltip.playerRows) do
        local member = playerIndex <= memberCount and C_LFGList.GetSearchResultPlayerInfo(searchResultID, playerIndex)
        if member then
            local leaderBase = leaderName and leaderName:match("^([^%-]+)")
            local memberName = SafeString(member.name)
            local classFilename = SafeString(member.classFilename)
            local role = SafeString(member.assignedRole)
            local isLeader = SafeBoolean(member.isLeader) or (leaderBase and memberName and leaderBase:lower() == memberName:lower())
            local mapped = RunsByDungeon(ResolveRaiderRuns(memberName, leaderName, classFilename))
            if isLeader and next(mapped) == nil then mapped = BlizzardRunsByDungeon(info.leaderDungeonScoreInfo, columns) end

            line.name:SetText(("%s %s %s"):format(
                UI.RoleIcon(role, 14),
                UI.ClassIcon(classFilename, 16),
                memberName or L("Игрок")))
            line.name:SetTextColor(UI.ClassColor(classFilename))

            for columnIndex, column in ipairs(columns) do
                local run = mapped[column.key]
                local value, grade
                if run and run.bestRunLevel then value, grade = LeaderKeyValue(run) else value, grade = RaiderKeyValue(run) end
                local cell = line.cells[columnIndex]
                cell:SetText(value)
                local runLevel = RunLevel(run)
                local color = listingKeyLevel and runLevel > 0 and runLevel < listingKeyLevel
                    and BELOW_KEY_COLOR
                    or RUN_GRADE_COLOR[grade] or RUN_GRADE_COLOR.missing
                cell:SetTextColor(color[1], color[2], color[3], 1)
            end
            line:Show()
        else
            line:Hide()
        end
    end

    tooltip:SetHeight(92 + math.max(1, memberCount) * 24)
    tooltip.searchResultID = searchResultID
    PositionGroupTooltip(tooltip, row, placement)
    tooltip:Show()
    if placement == "below" then
        -- Raider.IO and other OnShow hooks can enlarge GameTooltip after our
        -- hook runs. Re-evaluate once on the next frame using final bounds.
        C_Timer.After(0, function()
            if tooltip:IsShown() and tooltip.searchResultID == searchResultID then
                PositionGroupTooltip(tooltip, row, placement)
            end
        end)
    end
end

local function HideGroupTooltip()
    if GroupSearchUI.groupTooltip then GroupSearchUI.groupTooltip:Hide() end
    GameTooltip_Hide()
end

-- Тот же полный тултип доступен и на штатных строках Blizzard. Стандартный
-- GameTooltip остаётся на месте, а таблица участников открывается снизу.
function GroupSearchUI:IsMythicPlusSearchResult(searchResultID, suppliedInfo)
    local info = suppliedInfo or (searchResultID and C_LFGList.GetSearchResultInfo(searchResultID))
    if not info then return false end
    local activityID = UsableNumber(info.activityID) and info.activityID or nil
    if not activityID and type(info.activityIDs) == "table" and not issecretvalue(info.activityIDs) then
        local first = info.activityIDs[1]
        if UsableNumber(first) then activityID = first end
    end
    if not activityID then return false end

    local activity = C_LFGList.GetActivityInfoTable(activityID)
    if not activity then return false end
    for _, field in ipairs({ "isMythicPlusActivity", "isMythicPlus" }) do
        local value = activity[field]
        if type(value) == "boolean" and not issecretvalue(value) then return value end
    end

    -- Рейды находятся в другой категории. Это главный барьер против окна
    -- «участники × ключи» на объявлениях вроде 2/4/14.
    local categoryID = activity.categoryID
    if UsableNumber(categoryID) and categoryID ~= 2 then return false end
    local difficultyID = activity.difficultyID
    if UsableNumber(difficultyID) then return difficultyID == 8 end
    if JP.SeasonMapByActivity and JP.SeasonMapByActivity[activityID] then return true end
    if C_LFGList.GetKeystoneForActivity then
        local ok, level = pcall(C_LFGList.GetKeystoneForActivity, activityID)
        if ok and UsableNumber(level) and level > 0 then return true end
    end
    return false
end

function GroupSearchUI:ShowBlizzardResultTooltip(owner, searchResultID)
    if not owner or not searchResultID then return end
    local info = C_LFGList.GetSearchResultInfo(searchResultID)
    if not info then return end
    if not self:IsMythicPlusSearchResult(searchResultID, info) then
        self:HideBlizzardResultTooltip()
        return
    end
    local activityID = UsableNumber(info.activityID) and info.activityID or nil
    if not activityID and type(info.activityIDs) == "table" and not issecretvalue(info.activityIDs) then
        local first = info.activityIDs[1]
        if UsableNumber(first) then activityID = first end
    end
    local activity = activityID and C_LFGList.GetActivityInfoTable(activityID)
    local dungeonName = activity and SafeString(activity.fullName or activity.shortName) or L("Подземелье")
    -- PVEFrame включает левую навигацию и сам список. Привязка к
    -- LFGListFrame начинала таблицу с середины окна.
    local anchor = _G.PVEFrame or _G.LFGListFrame or owner
    ShowGroupTooltip(anchor, searchResultID, dungeonName, "below")
end

function GroupSearchUI:HideBlizzardResultTooltip()
    if self.groupTooltip then self.groupTooltip:Hide() end
end

---------------------------------------------------------------------------
-- Запрос поиска у Blizzard
---------------------------------------------------------------------------

local SEARCH_COOLDOWN = 3.5

-- Один запрос Blizzard принимает только одну строку поиска. Собираем
-- уникальные следующие уровни выбранных подземелий и запрашиваем их по
-- очереди. Данжи с одинаковой целью используют один запрос.
function GroupSearchUI:GetUpgradeSearchLevels(welcome)
    if not welcome.groupFilters or not welcome.groupFilters.scoreUpgrade then return {} end
    local selected = welcome.groupFilters.dungeons or {}
    local selectedCount = 0
    for _, enabled in pairs(selected) do if enabled then selectedCount = selectedCount + 1 end end
    local found, levels = {}, {}
    for _, dungeon in ipairs(welcome.dungeonData or {}) do
        local enabled = (selectedCount == 0 and welcome.groupFilters.dungeonsNone ~= true)
            or selected[dungeon.mapID] or selected[tostring(dungeon.mapID)]
        local best = enabled and welcome.bestByMap and welcome.bestByMap[dungeon.mapID]
        if best and best > 0 then
            local candidate = best + 1
            if not found[candidate] then
                found[candidate] = true
                levels[#levels + 1] = candidate
            end
        end
    end
    table.sort(levels)
    return levels
end

function GroupSearchUI:GetUpgradeSearchLevel(welcome)
    local levels = self:GetUpgradeSearchLevels(welcome)
    -- One protected Search call can contain only one text target. For mixed
    -- personal records choose the middle requested level: it avoids a broad
    -- list full of irrelevant low keys without biasing the query toward the
    -- rarest maximum. Selecting one dungeon still yields its exact next level.
    return levels[math.max(1, math.ceil(#levels / 2))]
end

local function CopyFilters(welcome, targetLevel)
    local copy = {}
    for key, value in pairs(welcome.groupFilters or {}) do
        if key == "dungeons" then
            copy.dungeons = {}
            for mapID, enabled in pairs(value) do copy.dungeons[mapID] = enabled end
        elseif type(value) ~= "table" then
            copy[key] = value
        end
    end
    copy.searchTargetLevel = targetLevel
    copy.searchExactLevel = targetLevel
    return copy
end

local function ExactSearchTarget(welcome)
    local filters = welcome.groupFilters or {}
    local minimum, maximum = tonumber(filters.keyMin), tonumber(filters.keyMax)
    if minimum and maximum and minimum == maximum and minimum >= 2 then return minimum end
    if filters.scoreUpgrade then
        return GroupSearchUI:GetUpgradeSearchLevel(welcome)
    end
end

local FinishBlizzardSearch

local function NativeSearchBox()
    return LFGListFrame and LFGListFrame.SearchPanel and LFGListFrame.SearchPanel.SearchBox
end

local function ReadNativeSearchText()
    local box = NativeSearchBox()
    if not box or type(box.GetText) ~= "function" then return end
    local ok, value = pcall(box.GetText, box)
    if not ok then return end
    return JP.SafeStringOrEmpty(value)
end

-- Диапазон N-N — штатная возможность защищённого поля Blizzard. MythicBoost
-- не рекламирует и не заполняет её, но если пользователь сам отправил такой
-- запрос, молча принимает его как точный уровень текущей выдачи.
local function NativeExactLevel()
    local text = ReadNativeSearchText()
    if not text then return end
    local from, to = text:match("^%s*(%d+)%s*%-%s*(%d+)%s*$")
    from, to = tonumber(from), tonumber(to)
    if from and from == to and from >= 2 then return from end
end

function GroupSearchUI:CaptureNativeExactSearch(welcome)
    local level = NativeExactLevel()
    self.manualExactLevel = level
    if level then self.lastSearchTarget = level end
    if welcome and welcome.groupFilters then welcome.groupFilters.searchExactLevel = level end
    JP:RequestRefresh(.1)
end

FinishBlizzardSearch = function(welcome, token, message)
    if token and GroupSearchUI.searchToken ~= token then return end
    GroupSearchUI.searchPending = false
    GroupSearchUI.searchAwaitingResults = false
    GroupSearchUI.awaitingNativeExact = false
    GroupSearchUI.waitingForActivities = false
    if welcome.scan then
        welcome.scan:Enable()
        welcome.scan:SetText(L("Обновить"))
    end
    if message then JP:Print(message) end
    -- C_LFGList.Search меняет состояние стандартного поиска. Наши фильтры
    -- живут отдельно и после ответа Blizzard должны остаться ровно такими,
    -- какими были в момент нажатия кнопки.
    local snapshot = GroupSearchUI.searchFilterSnapshot
    if snapshot then
        for key, value in pairs(snapshot) do
            if key == "dungeons" then
                wipe(welcome.groupFilters.dungeons)
                for mapID, enabled in pairs(value) do welcome.groupFilters.dungeons[mapID] = enabled end
            else
                welcome.groupFilters[key] = value
            end
        end
    end
    GroupSearchUI.searchFilterSnapshot = nil
    if GroupSearchUI.batchMatches then
        local merged = {}
        for _, match in pairs(GroupSearchUI.batchMatches) do merged[#merged + 1] = match end
        table.sort(merged, function(a, b)
            local al = a.targetLevel or a.keyLevel or 0
            local bl = b.targetLevel or b.keyLevel or 0
            if al ~= bl then return al < bl end
            if a.score ~= b.score then return a.score > b.score end
            return (a.age or math.huge) < (b.age or math.huge)
        end)
        local excluded = {}
        for searchResultID, match in pairs(GroupSearchUI.batchExcluded or {}) do
            if not GroupSearchUI.batchMatches[searchResultID] then excluded[#excluded + 1] = match end
        end
        table.sort(excluded, function(a, b)
            return (a.sourceOrder or math.huge) < (b.sourceOrder or math.huge)
        end)
        GroupSearchUI.completedBatch = {
            matches = merged,
            excluded = excluded,
            scanned = GroupSearchUI.batchScanned or 0,
            rejected = GroupSearchUI.batchRejected or {},
        }
    end
    GroupSearchUI.batchMatches = nil
    GroupSearchUI.batchExcluded = nil
    GroupSearchUI.batchRejected = nil
    GroupSearchUI.searchQueue = nil
    -- Кэш профилей здесь НЕ чистим: сразу за этим идёт перерисовка, которая
    -- его и наполняет, и сброс заставлял платить полную цену заново.
    -- Актуальность обеспечивает сброс в начале нового поиска.
    JP:RequestRefresh(.1)
end

function GroupSearchUI:CaptureCurrentSearch(welcome)
    local targetLevel = self.currentSearchTarget
    local matches, _, scanned, rejected, excluded = JP.AutoMatch:Scan(
        CopyFilters(welcome, targetLevel), {
            bestByMap = welcome.bestByMap,
            bestByActivity = welcome.bestByActivity,
        })
    self.batchScanned = (self.batchScanned or 0) + (scanned or 0)
    for reason, count in pairs(rejected or {}) do
        self.batchRejected[reason] = (self.batchRejected[reason] or 0) + count
    end
    for _, match in ipairs(matches or {}) do
        self.batchMatches[match.searchResultID] = match
        self.batchExcluded[match.searchResultID] = nil
    end
    for _, match in ipairs(excluded or {}) do
        if not self.batchMatches[match.searchResultID] then self.batchExcluded[match.searchResultID] = match end
    end
end

function GroupSearchUI:ScheduleCurrentSearch(welcome, token)
    local delay = math.max(0, (self.nextSearchAt or 0) - GetTime())
    if delay <= 0 then self:RunDirectSearch(welcome, token); return end
    -- C_LFGList.Search требует живой аппаратный клик. Нельзя откладывать сам
    -- вызов через таймер: после потери hardware event клиент заблокирует его.
    -- Таймер только возвращает кнопку, а пользователь запускает новый запрос.
    self.searchPending = false
    self.searchAwaitingResults = false
    self.waitingForActivities = false
    self.searchQueue = nil
    self.batchMatches = nil
    self.batchExcluded = nil
    self.batchRejected = nil
    self.searchFilterSnapshot = nil
    welcome.scan:SetText((L("Подожди %dс")):format(math.max(1, math.ceil(delay))))
    C_Timer.After(delay, function()
        if not GroupSearchUI.searchPending and GroupSearchUI.searchToken == token then
            welcome.scan:Enable()
            welcome.scan:SetText(L("Обновить"))
        end
    end)
end

---------------------------------------------------------------------------
-- Серверный фильтр Blizzard
--
-- Раньше мы просили у сервера все подземелья подряд и отбирали нужное уже у
-- себя: из сотни присланных групп до выбранного подземелья доживали единицы,
-- а героики и обычные забивали выдачу. Фильтр передаём только в свой
-- запрос. Глобальный SaveAdvancedFilter трогать нельзя: логи показали secret-taint
-- в штатном LFGListSearchEntry_Update после такой записи.
---------------------------------------------------------------------------

local activityGroupByMap
local function ActivityGroupsByDungeon()
    if activityGroupByMap then return activityGroupByMap end
    local map = {}
    for mapID, groupID in pairs(ACTIVITY_GROUP_BY_MAP) do map[mapID] = groupID end
    if type(C_LFGList.GetAvailableActivityGroups) ~= "function"
        or type(C_LFGList.GetActivityGroupInfo) ~= "function" then
        activityGroupByMap = map
        return map
    end

    local filterEnum = Enum and Enum.LFGListFilter or {}
    local flags = 0
    if bit and filterEnum.PvE then
        flags = bit.bor(filterEnum.CurrentSeason or 0, filterEnum.PvE or 0)
    end
    local ok, groups = pcall(C_LFGList.GetAvailableActivityGroups, 2, flags)
    if not ok or type(groups) ~= "table" then
        activityGroupByMap = map
        return map
    end

    local byName = {}
    for _, groupID in ipairs(groups) do
        local name = C_LFGList.GetActivityGroupInfo(groupID)
        if type(name) == "string" and name ~= "" then byName[name:lower()] = groupID end
    end

    local count = 0
    for _, mapID in ipairs(JP.API.GetChallengeMapIDs()) do
        local mapInfo = JP.API.GetChallengeMap(mapID)
        local mapName = mapInfo and mapInfo.name
        if type(mapName) == "string" and mapName ~= "" then
            local lowered = mapName:lower()
            for groupName, groupID in pairs(byName) do
                if groupName == lowered or groupName:find(lowered, 1, true) or lowered:find(groupName, 1, true) then
                    -- Если API знает этот сезон, его значение важнее fallback.
                    map[mapID] = groupID
                    count = count + 1
                    break
                end
            end
        end
    end
    -- Пустое сопоставление не кэшируем: списки активностей приходят не сразу.
    activityGroupByMap = map
    return map
end

function GroupSearchUI:BuildServerFilter(welcome)
    local groups = ActivityGroupsByDungeon()
    local wantedGroups, wantedActivities, seenGroup, seenActivity = {}, {}, {}, {}
    local all = SelectedCount(welcome) == 0 and welcome.groupFilters.dungeonsNone ~= true
    for _, data in ipairs(welcome.dungeonData or {}) do
        local groupID = groups[data.mapID]
        if groupID and (all or IsCardSelected(welcome, data.mapID)) then
            if not seenGroup[groupID] then
                seenGroup[groupID] = true
                wantedGroups[#wantedGroups + 1] = groupID
            end
        end
        if all or IsCardSelected(welcome, data.mapID) then
            for _, activityID in pairs(data.activityIDs or {}) do
                activityID = tonumber(activityID)
                if activityID and not seenActivity[activityID] then
                    seenActivity[activityID] = true
                    wantedActivities[#wantedActivities + 1] = activityID
                end
            end
        end
    end

    local filter = {
        needsTank = false,
        needsHealer = false,
        needsDamage = false,
        needsMyClass = false,
        hasHealer = welcome.groupFilters.requireHealer == true,
        difficultyNormal = false,
        difficultyHeroic = false,
        difficultyMythic = false,
        difficultyMythicPlus = true,
        minimumRating = tonumber(welcome.groupFilters.scoreMin) or 0,
        hasTank = welcome.groupFilters.requireTank == true,
        activities = wantedGroups,
    }
    -- PGF передаёт сюда именно activityGroupID, а не activityID отдельных
    -- сложностей. Для пустого выбора карточек мы уже собрали все восемь групп.
    if all then wantedActivities = {} end

    JP:Log(L("прямой серверный фильтр: groupIDs=%d activityIDs=%d, M+, рейтинг от %d"),
        #wantedGroups, #wantedActivities, filter.minimumRating)
    return filter, nil
end

function GroupSearchUI:RunDirectSearch(welcome, token)
    if not self.searchPending or self.searchToken ~= token then return end
    self.waitingForActivities = false
    local step, total = self.searchIndex or 1, #(self.searchQueue or {})
    welcome.scan:SetText(total > 1 and (L("Поиск %d/%d")):format(step, total) or L("Поиск..."))
    self.nextSearchAt = GetTime() + SEARCH_COOLDOWN

    local targetLevel = self.searchQueue and self.searchQueue[step]
    if targetLevel == false then targetLevel = nil end
    self.currentSearchTarget = targetLevel
    if targetLevel and targetLevel > 0 then self.lastSearchTarget = targetLevel end
    self.searchStep = (self.searchStep or 0) + 1
    local searchStep = self.searchStep
    self.searchAwaitingResults = true
    local ok = false

    -- Сборка фильтра обязана быть защищена: если список активностей ещё
    -- не готов или API конкретной сборки вернул неожиданные данные, кнопка не
    -- должна навечно оставаться в состоянии «Поиск...».
    local built, advancedFilter, activityIDs = pcall(self.BuildServerFilter, self, welcome)
    if not built then
        JP:Log(L("ошибка серверного фильтра: %s"), tostring(advancedFilter))
        FinishBlizzardSearch(welcome, token, L("Не удалось собрать фильтр Blizzard. Нажми «Обновить» ещё раз."))
        return
    end
    local filterEnum = Enum and Enum.LFGListFilter or {}
    local languages = C_LFGList.GetLanguageSearchFilter and C_LFGList.GetLanguageSearchFilter() or nil
    -- Blizzard 12.1 resolves dungeon searches as Recommended in the second
    -- argument and keeps PvE in preferredFilters. Passing PvE | CurrentSeason
    -- as the primary filter is accepted by the C API, but no completion event
    -- is emitted, leaving our request to expire on the timeout below.
    local searchFilter = filterEnum.Recommended or 1
    local preferredFilters = filterEnum.PvE or 4
    -- The fifth argument is a cross-faction boolean, not search text. The
    -- regular MythicBoost button always performs its normal broad Blizzard
    -- refresh; a manually entered N-N belongs only to the native search which
    -- produced it and must not leak into this independent method.
    self.manualExactLevel = nil
    if welcome.groupFilters then welcome.groupFilters.searchExactLevel = nil end
    if C_LFGList.ClearSearchTextFields then pcall(C_LFGList.ClearSearchTextFields) end
    local searchCrossFactionListings = nil
    ok = pcall(C_LFGList.Search, 2, searchFilter, preferredFilters,
        languages, searchCrossFactionListings, advancedFilter, activityIDs)
    JP:Log(L("точный поиск: %s"), targetLevel and (("%d-%d"):format(targetLevel, targetLevel)) or L("без уровня"))
    if not ok then
        FinishBlizzardSearch(welcome, token, L("Blizzard не разрешил выполнить поиск сейчас."))
        return
    end
    C_Timer.After(7, function()
        if GroupSearchUI.searchPending and GroupSearchUI.searchToken == token and GroupSearchUI.searchStep == searchStep then
            FinishBlizzardSearch(welcome, token, L("Поиск Blizzard не ответил. Нажми «Обновить» ещё раз."))
        end
    end)
end

function GroupSearchUI:OnSearchResults(welcome)
    if not self.searchPending or not self.searchAwaitingResults then return end
    self.searchAwaitingResults = false
    self:CaptureCurrentSearch(welcome)
    if (self.searchIndex or 1) < #(self.searchQueue or {}) then
        self.searchIndex = self.searchIndex + 1
        self:ScheduleCurrentSearch(welcome, self.searchToken)
    else
        FinishBlizzardSearch(welcome, self.searchToken)
    end
end

-- В разных сборках Midnight завершение поиска приходит либо как
-- SEARCH_RESULTS_RECEIVED, либо только как UPDATE_SEARCH_RESULTS. Второе
-- событие может сработать до того, как таблицы результатов заполнятся, поэтому
-- даём клиенту небольшое время и схлопываем повторные события одного шага.
function GroupSearchUI:QueueSearchResults(welcome, event)
    if not self.searchPending or not self.searchAwaitingResults then return end
    local token, step = self.searchToken, self.searchStep
    if self.captureScheduledStep == step then return end
    self.captureScheduledStep = step
    C_Timer.After(.65, function()
        if GroupSearchUI.searchPending
            and GroupSearchUI.searchAwaitingResults
            and GroupSearchUI.searchToken == token
            and GroupSearchUI.searchStep == step then
            GroupSearchUI.captureScheduledStep = nil
            GroupSearchUI:OnSearchResults(welcome)
        end
    end)
end

function GroupSearchUI:RequestBlizzardSearch(welcome)
    if SelectedCount(welcome) == 0 and welcome.groupFilters.dungeonsNone == true then
        JP:Print(L("Выбери хотя бы одно подземелье."))
        return
    end
    if self.searchPending then
        -- Кнопка остаётся живой и служит аварийной остановкой. Это особенно
        -- важно, если конкретная версия клиента не прислала финальное событие.
        self.searchToken = (self.searchToken or 0) + 1
        FinishBlizzardSearch(welcome, nil)
        return
    end
    self.searchToken = (self.searchToken or 0) + 1
    local token = self.searchToken
    self.searchPending = true
    welcome.offset = 0
    if welcome.scrollBar then welcome.scrollBar:SetValue(0) end
    -- Сбрасываем профили в начале поиска, а не в конце: к моменту отрисовки
    -- кэш должен уже наполняться, иначе перебор реалмов идёт дважды.
    self:ClearProfileCache()
    -- Blizzard разрешает только один защищённый Search на аппаратный клик.
    -- Для разных личных рекордов берём центральную цель: локальная проверка
    -- затем оставляет любой подтверждённый ключ выше рекорда конкретного данжа.
    self.searchQueue = { ExactSearchTarget(welcome) or false }
    self.searchIndex = 1
    self.batchMatches = {}
    self.batchExcluded = {}
    self.batchRejected = {}
    self.batchScanned = 0
    self.searchFilterSnapshot = {}
    for key, value in pairs(welcome.groupFilters or {}) do
        if key == "dungeons" then
            local selected = {}
            for mapID, enabled in pairs(value) do selected[mapID] = enabled end
            self.searchFilterSnapshot.dungeons = selected
        elseif type(value) ~= "table" then
            self.searchFilterSnapshot[key] = value
        end
    end
    welcome.scan:Enable()

    -- Список активностей подгружаем заранее, но не ждём события: Search
    -- защищён hardware event и обязан выполняться в стеке этого клика.
    if C_LFGList.RequestAvailableActivities then pcall(C_LFGList.RequestAvailableActivities) end
    self:ScheduleCurrentSearch(welcome, token)

end

---------------------------------------------------------------------------
-- Карточки подземелий
---------------------------------------------------------------------------

local function GetDungeonData()
    local byMap = {}
    for _, run in ipairs(PlayerRuns()) do
        local mapID = run and run.dungeon and run.dungeon.keystone_instance
        if mapID then byMap[mapID] = run end
    end

    local available = {}
    for _, mapID in ipairs(JP.API.GetChallengeMapIDs()) do available[mapID] = true end
    local ordered = {}
    for _, mapID in ipairs(SEASON_ORDER) do
        if available[mapID] or byMap[mapID] then ordered[#ordered + 1] = mapID; available[mapID] = nil end
    end
    for mapID in pairs(available) do ordered[#ordered + 1] = mapID end
    if #ordered == 0 then for mapID in pairs(byMap) do ordered[#ordered + 1] = mapID end end

    local result = {}
    for _, mapID in ipairs(ordered) do
        if #result >= 8 then break end
        local mapInfo = JP.API.GetChallengeMap(mapID) or {}
        local name, icon, background = mapInfo.name, mapInfo.icon, mapInfo.background
        local instanceMapID = mapInfo.instanceMapID
        local run = byMap[mapID]
        local rioDungeon = run and run.dungeon
        if rioDungeon and type(rioDungeon.instance_map_ids) == "table" then
            instanceMapID = rioDungeon.instance_map_ids[1] or instanceMapID
        end
        result[#result + 1] = {
            mapID = mapID,
            instanceMapID = instanceMapID,
            name = SafeString(name) or (L("Подземелье ") .. (#result + 1)),
            icon = ValidTexture(icon),
            background = ValidTexture(background),
            activityIDs = rioDungeon and type(rioDungeon.lfd_activity_ids) == "table"
                and rioDungeon.lfd_activity_ids or {},
            run = run,
        }
    end
    return result
end

SelectedCount = function(welcome)
    local count = 0
    for _, enabled in pairs(welcome.groupFilters.dungeons or {}) do if enabled then count = count + 1 end end
    return count
end

function GroupSearchUI:GetScopeText(welcome)
    local selected = welcome and welcome.groupFilters and welcome.groupFilters.dungeons or {}
    local count, chosen
    count = 0
    for _, dungeon in ipairs((welcome and welcome.dungeonData) or {}) do
        if selected[dungeon.mapID] or selected[tostring(dungeon.mapID)] then
            count = count + 1
            chosen = dungeon
        end
    end
    if count == 1 and chosen then
        local best = JP:GetBestLevel(chosen.mapID, chosen.run and chosen.run.level or 0)
        return best > 0
            and ("%s, +%d"):format(chosen.name or L("Подземелье"), best)
            or ("%s, —"):format(chosen.name or L("Подземелье"))
    elseif count > 1 then
        return (L("выбрано подземелий: %d")):format(count)
    end
    if welcome and welcome.groupFilters and welcome.groupFilters.dungeonsNone == true then
        return L("подземелья не выбраны")
    end
    return L("все 8 подземелий")
end

IsCardSelected = function(welcome, mapID)
    local selected = welcome.groupFilters.dungeons
    if SelectedCount(welcome) == 0 then return welcome.groupFilters.dungeonsNone ~= true end
    return (selected[mapID] or selected[tostring(mapID)]) and true or false
end

local function SetCardSelected(card, selected)
    card.selected = selected and true or false
    card:SetBackdropColor(selected and .085 or .050, selected and .105 or .062, selected and .135 or .080, .96)
    if selected and card.isLootBest then
        card:SetBackdropBorderColor(UI.Unpack(C.amber))
    elseif selected then
        card:SetBackdropBorderColor(UI.Unpack(C.accent))
    else
        card:SetBackdropBorderColor(UI.Unpack(C.line))
    end
    card.accent:SetShown(card.selected)
    card.art:SetAlpha(selected and .46 or .24)
    card.art:SetDesaturated(not selected)
    card.icon:SetDesaturated(not selected)
    card.icon:SetAlpha(selected and 1 or .55)
    card.iconBorder:SetBackdropBorderColor(selected and .22 or .14, selected and .46 or .18, selected and .60 or .24, 1)
    card.title:SetTextColor(selected and C.text[1] or .58, selected and C.text[2] or .63, selected and C.text[3] or .70)
    card.bestBadge:SetAlpha(selected and 1 or .48)
    card.loot:SetAlpha(selected and 1 or .55)
    for _, itemButton in ipairs(card.lootItems or {}) do itemButton:SetAlpha(selected and 1 or .45) end
end

local function SetLootItem(button, item)
    button.item = item
    if not item then button.badge:SetText(""); button:Hide(); return end
    local texture = item.icon
    if not texture and item.itemID and C_Item and C_Item.GetItemIconByID then texture = C_Item.GetItemIconByID(item.itemID) end
    button.icon:SetTexture(texture or 134400)
    button.icon:SetTexCoord(.07, .93, .07, .93)
    button.gain:SetText((item.gain or 0) > 0 and ("+" .. item.gain) or "")
    local recommendation = item.recommendation
    if recommendation then
        button.badge:SetText(recommendation.label or (recommendation.kind == "bis" and "BIS" or "TOP"))
        if recommendation.kind == "bis" then
            button.badge:SetTextColor(1, .73, .12, 1)
            button:SetBackdropBorderColor(1, .58, .10, 1)
        else
            button.badge:SetTextColor(.73, .42, 1, 1)
            button:SetBackdropBorderColor(.60, .28, .94, 1)
        end
    else
        button.badge:SetText("")
        button:SetBackdropBorderColor(.25, .32, .40, 1)
    end
    button:Show()
end

local function LayoutCardLoot(card, upgrades)
    upgrades = upgrades or {}
    local available = card:GetWidth() - CARD_COLUMN - CARD_PAD
    local perRow = math.max(1, math.min(#(card.lootItems or {}), math.floor(available / CARD_ITEM_STEP)))
    local capacity = perRow
    for index, button in ipairs(card.lootItems or {}) do
        local column = index - 1
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", CARD_COLUMN + column * CARD_ITEM_STEP, CARD_ROW_ITEMS)
        SetLootItem(button, index <= capacity and upgrades[index] or nil)
    end
end

function GroupSearchUI:RefreshDungeonCards(welcome)
    local data = GetDungeonData()
    welcome.dungeonData = data
    welcome.bestByMap = {}
    welcome.bestByActivity = {}
    welcome.mapByActivity = {}
    for _, dungeon in ipairs(data) do
        local best = JP:GetBestLevel(dungeon.mapID, dungeon.run and dungeon.run.level or 0)
        welcome.bestByMap[dungeon.mapID] = best
        local activities = dungeon.activityIDs
        if type(activities) == "table" then
            for _, activityID in pairs(activities) do
                activityID = tonumber(activityID)
                if activityID and not issecretvalue(activityID) then
                    welcome.bestByActivity[activityID] = best
                    welcome.mapByActivity[activityID] = dungeon.mapID
                end
            end
        end
    end
    -- AutoMatch может получить activityID раньше, чем локализованное имя
    -- активности. Числовая карта надёжно связывает результат с карточкой.
    JP.SeasonMapByActivity = welcome.mapByActivity

    -- Советчик по луту дергает Encounter Journal и может не ответить.
    -- Его сбой не должен оставлять окно с пустыми карточками.
    local loot = {}
    if JP.LootAdvisor and JP.LootAdvisor.Analyze then
        local ok, result = pcall(JP.LootAdvisor.Analyze, JP.LootAdvisor, data)
        if ok and type(result) == "table" then loot = result end
    end
    welcome.lootAnalysis = loot

    local bestMapID, bestName, bestPercent, bestAverage, bestDropLevel, hasLootData, lootPending
    for _, dungeon in ipairs(data) do
        local dungeonLoot = loot[dungeon.mapID]
        if dungeonLoot and (dungeonLoot.total or 0) > 0 then hasLootData = true end
        if dungeonLoot and dungeonLoot.pending then lootPending = true end
        local percent = dungeonLoot and dungeonLoot.percent or 0
        local average = dungeonLoot and dungeonLoot.averageGain or 0
        if dungeonLoot and not dungeonLoot.pending and percent > 0
            and (not bestPercent or percent > bestPercent or (percent == bestPercent and average > bestAverage)) then
            bestMapID, bestName, bestPercent, bestAverage, bestDropLevel = dungeon.mapID, dungeon.name, percent, average,
                dungeonLoot and dungeonLoot.dropLevel
        end
    end
    for index, card in ipairs(welcome.dungeonCards) do
        local dungeon = data[index]
        if dungeon then
            card.mapID = dungeon.mapID
            card.lootData = loot[dungeon.mapID]
            card.title:SetText(dungeon.name)

            if dungeon.background then
                card.art:SetTexture(dungeon.background)
                card.art:SetTexCoord(ART_LEFT, ART_RIGHT, ART_TOP, ART_BOTTOM)
                card.art:Show()
            elseif dungeon.icon then
                card.art:SetTexture(dungeon.icon)
                card.art:SetTexCoord(.10, .90, .10, .90)
                card.art:Show()
            else
                card.art:Hide()
            end

            if dungeon.icon then
                card.icon:SetTexture(dungeon.icon)
                card.icon:SetTexCoord(.07, .93, .07, .93)
                card.icon:Show()
                card.iconLabel:SetText("")
            else
                card.icon:Hide()
                card.iconLabel:SetText(DUNGEON_SHORT[dungeon.mapID] or "M+")
            end

            local level = JP:GetBestLevel(dungeon.mapID, dungeon.run and dungeon.run.level or 0)
            card.best:SetText(level > 0 and ("|cff43d17a+%d|r"):format(level) or "|cff687584—|r")

            local percent = card.lootData and card.lootData.percent or 0
            local analyzed = card.lootData and not card.lootData.pending and (card.lootData.total or 0) > 0
            card.isLootBest = bestMapID == dungeon.mapID
            card.hasUsefulLoot = percent > 0
            card.loot:SetText(analyzed and (percent .. "%") or "...")
            if percent >= 50 then card.loot:SetTextColor(1, .74, .24, 1)
            elseif percent > 0 then card.loot:SetTextColor(.73, .48, 1, 1)
            else card.loot:SetTextColor(UI.Unpack(C.faint)) end

            local upgrades = card.lootData and card.lootData.upgrades or {}
            LayoutCardLoot(card, upgrades)

            SetCardSelected(card, IsCardSelected(welcome, dungeon.mapID))
            card:Show()
        else
            card.mapID = nil
            card:Hide()
        end
    end

    local active = SelectedCount(welcome)
    local displayedActive = active
    if active == 0 and welcome.groupFilters.dungeonsNone ~= true then displayedActive = #data end
    welcome.dungeonSummary:SetText(("%d / %d"):format(displayedActive, #data))
    if welcome.lootSummary then
        local bestLoot = bestMapID and loot[bestMapID]
        welcome.lootSummary:SetText(bestName
            and (L("|cff8a939fДроп +10: %d  лучший шанс|r  |cffffb93d%s|r  |cffb36cff%d%% (%d из %d)|r"))
                :format(bestDropLevel or bestLoot.dropLevel or 0, bestName, bestPercent, bestLoot.useful or 0, bestLoot.total or 0)
            or (lootPending and L("|cff8aa8c4Загружаю уровни предметов...|r")
                or (hasLootData and L("|cff687584Улучшений по ilvl не найдено|r") or L("|cff687584Загружаю таблицу лута...|r"))))
    end
end

local function CardTooltip(card)
    if not card.mapID then return end
    GameTooltip:SetOwner(card, "ANCHOR_RIGHT")
    GameTooltip:SetText(card.title:GetText() or "", 1, .82, 0)

    local loot = card.lootData
    if loot and (loot.total or 0) > 0 then
        GameTooltip:AddDoubleLine(L("Шанс полезного предмета +10"), loot.percent .. "%",
            .45, .75, 1,
            loot.percent >= 50 and 1 or .73, loot.percent >= 50 and .72 or .42, loot.percent >= 50 and .18 or 1)
        local dropLevel = tonumber(loot.dropLevel) or 0
        local dropText = dropLevel > 0 and (L("Дроп +10: %d")):format(dropLevel) or L("Уровень дропа загружается")
        GameTooltip:AddLine((L("%s. %d из %d предметов улучшают %d слота. Средний прирост +%d"))
            :format(dropText, loot.useful or 0, loot.total, loot.slotCount or 0, loot.averageGain or 0), .72, .78, .86)
        for index = 1, math.min(5, #loot.upgrades) do
            local item = loot.upgrades[index]
            local icon = item.icon and ("|T" .. item.icon .. ":16:16:0:0|t ") or ""
            local recommendation = item.recommendation
            local marker = recommendation and (recommendation.kind == "bis"
                and " |cffffb91f[BIS]|r"
                or (" |cffb36cff[TOP %d%%]|r"):format(recommendation.share or 0)) or ""
            GameTooltip:AddDoubleLine(icon .. (item.name or L("Предмет")),
                (("%s  %d -> %d  (+%d)"):format(item.slot or L("Слот"), item.equipped, item.level, item.gain)) .. marker,
                .90, .92, .96, .25, 1, .55)
        end
        GameTooltip:AddLine(L("Процент = полезные предметы / весь доступный твоему спеку пул. Это шанс апгрейда при условии, что предмет достался тебе."), .52, .68, .82, true)
        if (loot.bisCount or 0) > 0 or (loot.topCount or 0) > 0 then
            GameTooltip:AddLine((L("Цели в этом данже: BIS %d, TOP %d.")):format(loot.bisCount or 0, loot.topCount or 0), 1, .72, .22)
        end
        GameTooltip:AddLine(L("BIS — список гайда Wowhead; TOP — самая частая экипировка сильных M+ игроков Murlok.io. Эффекты и твоя конкретная сборка всё равно требуют проверки."), .52, .58, .66, true)
    else
        GameTooltip:AddLine(L("Подходящей добычи для текущей специализации не найдено."), .52, .58, .66, true)
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(card.selected and L("Нажми, чтобы исключить подземелье из поиска.")
        or L("Нажми, чтобы вернуть подземелье в поиск."), .75, .80, .88, true)
    GameTooltip:Show()
end

local function CreateDungeonCard(parent, welcome)
    local card = CreateFrame("Button", nil, parent, "BackdropTemplate")
    card:SetSize(216, CARD_HEIGHT)
    UI.Backdrop(card, C.raised, C.line)

    card.art = card:CreateTexture(nil, "BACKGROUND")
    card.art:SetPoint("TOPLEFT", 1, -1)
    card.art:SetPoint("BOTTOMRIGHT", -1, 1)
    card.art:SetAlpha(.3)

    local scrim = UI.Scrim(card, "BORDER", 0, .34)
    scrim:SetPoint("TOPLEFT", 1, -1)
    scrim:SetPoint("BOTTOMRIGHT", -1, 1)

    card.iconBorder = CreateFrame("Frame", nil, card, "BackdropTemplate")
    card.iconBorder:SetSize(CARD_ICON, CARD_ICON)
    card.iconBorder:SetPoint("TOPLEFT", CARD_PAD, -CARD_PAD)
    UI.Backdrop(card.iconBorder, { .02, .03, .04, 1 }, C.line)

    card.icon = card.iconBorder:CreateTexture(nil, "ARTWORK")
    card.icon:SetPoint("TOPLEFT", 1, -1)
    card.icon:SetPoint("BOTTOMRIGHT", -1, 1)

    card.iconLabel = UI.Text(card.iconBorder, "GameFontNormal", "", C.accentDim)
    card.iconLabel:SetPoint("CENTER", 0, 0)

    card.bestBadge = CreateFrame("Frame", nil, card, "BackdropTemplate")
    card.bestBadge:SetSize(CARD_ICON - 2, CARD_ICON - 2)
    card.bestBadge:SetPoint("CENTER", card.iconBorder, "CENTER", 0, 0)

    card.loot = UI.Text(card, "GameFontNormal", "", C.faint)
    card.loot:SetPoint("TOPRIGHT", -CARD_PAD, CARD_ROW_TITLE)
    card.loot:SetHeight(CARD_BADGE_H)
    card.loot:SetJustifyH("RIGHT")

    card.title = UI.Text(card, "GameFontNormal", "", C.text)
    card.title:SetPoint("TOPLEFT", CARD_COLUMN, CARD_ROW_TITLE)
    card.title:SetPoint("RIGHT", card.loot, "LEFT", -10, 0)
    card.title:SetJustifyH("LEFT")
    card.title:SetJustifyV("MIDDLE")
    card.title:SetHeight(CARD_BADGE_H)
    card.title:SetWordWrap(false)
    card.title:SetShadowColor(0, 0, 0, 1)
    card.title:SetShadowOffset(1, -1)

    card.best = UI.Text(card.bestBadge, "GameFontNormalLarge", "")
    card.best:SetPoint("CENTER", 0, 0)
    card.best:SetWordWrap(false)
    local bestFont = card.best:GetFont()
    if bestFont then card.best:SetFont(bestFont, 22, "THICKOUTLINE") end
    card.best:SetShadowColor(0, 0, 0, 1)
    card.best:SetShadowOffset(2, -2)

    -- Полезные предметы прямо в карточке. Наведение показывает обычный
    -- предметный tooltip Blizzard и окно сравнения с надетой вещью.
    card.lootItems = {}
    for index = 1, 5 do
        local itemButton = CreateFrame("Button", nil, card, "BackdropTemplate")
        itemButton:SetSize(CARD_ITEM_SIZE, CARD_ITEM_SIZE)
        itemButton:SetPoint("TOPLEFT", CARD_COLUMN, CARD_ROW_ITEMS)
        UI.Backdrop(itemButton, { .025, .033, .044, .98 }, { .25, .32, .40, 1 })
        itemButton.icon = itemButton:CreateTexture(nil, "ARTWORK")
        itemButton.icon:SetPoint("TOPLEFT", 2, -2)
        itemButton.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        itemButton.gain = UI.Text(itemButton, "GameFontNormalSmall", "", C.green)
        itemButton.gain:SetPoint("BOTTOMRIGHT", -1, 1)
        itemButton.gain:SetShadowColor(0, 0, 0, 1)
        itemButton.gain:SetShadowOffset(1, -1)
        itemButton.badge = UI.Text(itemButton, "GameFontNormalSmall", "")
        itemButton.badge:SetPoint("TOPLEFT", 1, -1)
        itemButton.badge:SetShadowColor(0, 0, 0, 1)
        itemButton.badge:SetShadowOffset(1, -1)
        itemButton:SetScript("OnEnter", function(self)
            local item = self.item
            if not item then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if item.link then
                GameTooltip:SetHyperlink(item.link)
            else
                GameTooltip:SetText(item.name or L("Предмет"), 1, 1, 1)
            end
            GameTooltip:AddLine((L("Надето: %d   Дроп: %d   Прирост: +%d"))
                :format(item.equipped or 0, item.level or 0, item.gain or 0), .30, .92, .56)
            local recommendation = item.recommendation
            if recommendation and recommendation.kind == "bis" then
                GameTooltip:AddLine(L("BIS Mythic+ по гайду Wowhead"), 1, .72, .12)
                GameTooltip:AddLine((L("Сверено: %s")):format(recommendation.updatedAt or "—"), .62, .68, .76)
            elseif recommendation then
                GameTooltip:AddLine((L("TOP M+ игроков: %d%% из %d")):format(
                    recommendation.share or 0, recommendation.sample or 0), .73, .42, 1)
                GameTooltip:AddLine((L("Murlok.io, сезон %s")):format(recommendation.season or "—"), .62, .68, .76)
            end
            GameTooltip:Show()
            if GameTooltip_ShowCompareItem then GameTooltip_ShowCompareItem(GameTooltip) end
        end)
        itemButton:SetScript("OnLeave", function()
            GameTooltip_Hide()
            if ShoppingTooltip1 then ShoppingTooltip1:Hide() end
            if ShoppingTooltip2 then ShoppingTooltip2:Hide() end
        end)
        itemButton:Hide()
        card.lootItems[index] = itemButton
    end

    card.accent = card:CreateTexture(nil, "OVERLAY")
    card.accent:SetColorTexture(UI.Unpack(C.accent))
    card.accent:SetPoint("BOTTOMLEFT", 1, 1)
    card.accent:SetPoint("BOTTOMRIGHT", -1, 1)
    card.accent:SetHeight(2)

    card:SetScript("OnClick", function(self)
        if not self.mapID then return end
        local selected = welcome.groupFilters.dungeons
        local count = SelectedCount(welcome)
        local isSelected = selected[self.mapID] or selected[tostring(self.mapID)]
        if count == 0 and welcome.groupFilters.dungeonsNone == true then
            selected[self.mapID] = true
            welcome.groupFilters.dungeonsNone = nil
        elseif count == 0 then
            -- Пустая таблица без dungeonsNone — компактное представление
            -- состояния «выбраны все». Клик выключает только эту карточку.
            for _, dungeon in ipairs(welcome.dungeonData or {}) do
                if dungeon.mapID ~= self.mapID then selected[dungeon.mapID] = true end
            end
            welcome.groupFilters.dungeonsNone = SelectedCount(welcome) == 0 and true or nil
        elseif isSelected then
            selected[self.mapID] = nil
            selected[tostring(self.mapID)] = nil
            if SelectedCount(welcome) == 0 then welcome.groupFilters.dungeonsNone = true end
        else
            selected[self.mapID] = true
            welcome.groupFilters.dungeonsNone = nil
            if SelectedCount(welcome) >= #(welcome.dungeonData or {}) then wipe(selected) end
        end
        GroupSearchUI:RefreshDungeonCards(welcome)
        welcome:Refresh()
    end)
    card:SetScript("OnEnter", function(self)
        if not self.mapID then return end
        self:SetBackdropBorderColor(.26, .74, .96, 1)
        CardTooltip(self)
    end)
    card:SetScript("OnLeave", function(self)
        SetCardSelected(self, self.selected)
        GameTooltip_Hide()
    end)
    return card
end

---------------------------------------------------------------------------
-- Строки результатов
---------------------------------------------------------------------------

function GroupSearchUI:GetApplicationState(searchResultID)
    local state = JP.API.GetApplicationState(searchResultID)
    return state.status, state.cancellable, state.active, state.pending, state.duration
end

function GroupSearchUI:IsApplicationListed(searchResultID)
    local _, _, active = self:GetApplicationState(searchResultID)
    return active
end

-- Жадный портфель из пяти заявок. После каждого выбора похожие объявления
-- получают штраф, поэтому все слоты не тратятся на один данж/уровень. Уже
-- поданная сильная заявка получает небольшой бонус, чтобы план не дёргался.
function GroupSearchUI:OptimizeApplicationPlan(matches)
    local visibleIDs, activeOutside = {}, 0
    for _, match in ipairs(matches or {}) do
        match.applicationPlanOrder, match.applicationPlanScore = nil, nil
        local _, _, active = self:GetApplicationState(match.searchResultID)
        match.applicationActive = active
        if type(match.searchResultID) == "number" and not issecretvalue(match.searchResultID) then
            visibleIDs[match.searchResultID] = true
        end
    end
    local applications = JP.API.GetApplicationIDs()
    if applications then
        for _, resultID in ipairs(applications) do
            if JP.UsableNumber(resultID)
                and not visibleIDs[resultID] and self:IsApplicationListed(resultID) then
                activeOutside = activeOutside + 1
            end
        end
    end
    local selected, mapUse, levelUse = {}, {}, {}
    local visibleCapacity = math.max(0, APPLICATION_CAP - activeOutside)
    for slot = 1, math.min(visibleCapacity, #(matches or {})) do
        local bestMatch, bestScore
        for _, match in ipairs(matches) do
            if not match.applicationPlanOrder then
                local mapKey = match.mapID or match.dungeon or "?"
                local levelKey = match.targetLevel or match.keyLevel or 0
                local score = (match.applicationPriority or 0)
                    - (mapUse[mapKey] or 0) * 12
                    - (levelUse[levelKey] or 0) * 5
                    + (match.applicationActive and 4 or 0)
                if not bestScore or score > bestScore then bestMatch, bestScore = match, score end
            end
        end
        if not bestMatch then break end
        bestMatch.applicationPlanOrder, bestMatch.applicationPlanScore = slot, bestScore
        selected[#selected + 1] = bestMatch
        local mapKey = bestMatch.mapID or bestMatch.dungeon or "?"
        local levelKey = bestMatch.targetLevel or bestMatch.keyLevel or 0
        mapUse[mapKey] = (mapUse[mapKey] or 0) + 1
        levelUse[levelKey] = (levelUse[levelKey] or 0) + 1
    end
    self.applicationPlanCount = #selected

    local replacement, weakestActive
    for _, match in ipairs(matches or {}) do
        if match.applicationPlanOrder and not match.applicationActive and not replacement then replacement = match end
        if match.applicationActive and not match.applicationPlanOrder
            and (not weakestActive or (match.applicationPriority or 0) < (weakestActive.applicationPriority or 0)) then
            weakestActive = match
        end
    end
    if replacement and weakestActive then
        self.applicationSuggestion = (L("Замени заявку %s (%d) на %s (%d)")):format(
            weakestActive.dungeon or "—", weakestActive.applicationPriority or 0,
            replacement.dungeon or "—", replacement.applicationPriority or 0)
    elseif activeOutside > 0 then
        self.applicationSuggestion = (L("План: %d здесь + %d активных вне текущего поиска")):format(
            #selected, activeOutside)
    else
        self.applicationSuggestion = (L("План: %d лучших заявок с разными рисками")):format(#selected)
    end

    table.sort(matches, function(a, b)
        if a.applicationPlanOrder and b.applicationPlanOrder then return a.applicationPlanOrder < b.applicationPlanOrder end
        if a.applicationPlanOrder ~= b.applicationPlanOrder then return a.applicationPlanOrder ~= nil end
        return (a.applicationPriority or 0) > (b.applicationPriority or 0)
    end)
end

function GroupSearchUI:UpdateApplicationButton(button)
    local match = button and button.match
    local resultID = match and match.searchResultID
    if not resultID then return end

    if match.rejected and match.actionable == false then
        button:SetText(L("Недоступно"))
        button:Disable()
        button:SetAlpha(.35)
        button.applicationActive = false
        return
    end

    local status, cancellable, active, pending, duration = self:GetApplicationState(resultID)
    local searchSettings = JP.Settings and JP.Settings("search", {
        showRejectedResults = true,
        allowRejectedApplications = true,
    })
    if match.rejected and searchSettings and searchSettings.allowRejectedApplications == false and not cancellable then
        button:SetText(L("Только просмотр"))
        button:Disable()
        button:SetAlpha(.35)
        button.applicationActive = false
        return
    end
    if button.cancelRequestedAt and (not active or GetTime() - button.cancelRequestedAt >= 2) then
        button.cancelRequestedAt = nil
    end
    if cancellable then
        if button.cancelRequestedAt then
            button:SetText(L("Отмена…"))
            button:Disable()
            button:SetAlpha(.55)
            button.applicationActive = false
        else
            local remaining = duration and math.max(0, math.floor(duration + .5))
            local timer = remaining and (remaining >= 60
                and (" %d:%02d"):format(math.floor(remaining / 60), remaining % 60)
                or (L(" %dс")):format(remaining)) or ""
            button:SetText(L("Отменить") .. timer)
            button:Enable()
            button:SetAlpha(1)
            button.applicationActive = true
        end
    elseif pending then
        button:SetText(L("Обработка…"))
        button:Disable()
        button:SetAlpha(.55)
        button.applicationActive = false
    elseif status == "invited" then
        button:SetText(L("Приглашение"))
        button:Disable()
        button:SetAlpha(.75)
        button.applicationActive = false
    else
        button:SetText(L("Заявка…"))
        button:Enable()
        button:SetAlpha(1)
        button.applicationActive = false
    end
    if match.rejected then button:SetAlpha(.58) end
end

local ApplicationCoachTooltip

local function CreateResultRow(parent, index)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(ROW_HEIGHT)
    row:EnableMouse(true)
    row.baseColor = index % 2 == 0 and C.rowAlt or C.row
    UI.Backdrop(row, row.baseColor, C.lineSoft)

    row.sectionLabel = UI.Text(row, "GameFontNormalSmall", "", { .46, .50, .56, 1 })
    row.sectionLabel:SetPoint("CENTER", 0, 0)
    row.sectionLine = UI.Line(row, { .22, .25, .29, .8 })
    row.sectionLine:SetPoint("LEFT", 8, 0)
    row.sectionLine:SetPoint("RIGHT", row.sectionLabel, "LEFT", -10, 0)
    row.sectionLineRight = UI.Line(row, { .22, .25, .29, .8 })
    row.sectionLineRight:SetPoint("LEFT", row.sectionLabel, "RIGHT", 10, 0)
    row.sectionLineRight:SetPoint("RIGHT", -8, 0)
    row.sectionLine:Hide()
    row.sectionLineRight:Hide()
    row.sectionLabel:Hide()

    row.keyBox = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.keyBox:SetSize(COL.keyWidth, COL.keyWidth)
    row.keyBox:SetPoint("LEFT", COL.keyLeft, 0)
    UI.Backdrop(row.keyBox, { .035, .050, .065, 1 }, { .16, .30, .24, 1 })
    row.keyIcon = row.keyBox:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.keyIcon:SetPoint("TOPLEFT", 1, -1)
    row.keyIcon:SetPoint("BOTTOMRIGHT", -1, 1)
    row.keyIcon:SetTexture("Interface\\Icons\\INV_Relics_Hourglass")
    row.keyIcon:SetTexCoord(.10, .90, .22, .78)
    row.keyIcon:SetDesaturated(true)
    row.keyIcon:SetAlpha(.22)
    -- Midnight may mask a FontString as "..." when its text was assembled
    -- from a protected search result. Pre-create every realistic key label
    -- from literal addon-local numbers before any result is read, then only
    -- switch visibility. SetText is never called during result rendering.
    row.keyLabels = {}
    local function KeyLabel(value)
        local label = UI.Text(row.keyBox, "GameFontNormalLarge", value, C.green)
        label:SetPoint("CENTER", 0, 0)
        label:SetSize(COL.keyWidth + 8, 30)
        label:SetJustifyH("CENTER")
        label:SetJustifyV("MIDDLE")
        local keyFont = label:GetFont()
        if keyFont then label:SetFont(keyFont, 20, "THICKOUTLINE") end
        label:SetShadowColor(0, 0, 0, 1)
        label:SetShadowOffset(2, -2)
        label:Hide()
        return label
    end
    row.keyFallback = KeyLabel("+")
    for level = 2, 40 do row.keyLabels[level] = KeyLabel("+" .. level) end
    row.key = row.keyFallback

    row.roles = UI.Text(row, "GameFontHighlight", "")
    row.roles:SetPoint("RIGHT", -COL.rolesRight, 0)
    row.roles:SetWidth(COL.rolesWidth)
    row.roles:SetJustifyH("CENTER")

    row.dungeon = UI.Text(row, "GameFontNormal", "", C.text)
    row.dungeon:SetPoint("TOPLEFT", COL.textLeft, -9)
    row.dungeon:SetPoint("TOPRIGHT", -COL.contentRight, -9)
    row.dungeon:SetJustifyH("LEFT")
    row.dungeon:SetWordWrap(false)

    row.detail = UI.Text(row, "GameFontHighlightSmall", "", C.muted)
    row.detail:SetPoint("BOTTOMLEFT", COL.textLeft, 10)
    row.detail:SetPoint("BOTTOMRIGHT", -COL.contentRight, 10)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(false)

    row.score = UI.Text(row, "GameFontNormal", "", C.amber)
    row.score:SetPoint("RIGHT", -COL.leaderRight, 9)
    row.score:SetWidth(COL.leaderWidth)
    row.score:SetJustifyH("CENTER")

    row.leader = UI.Text(row, "GameFontHighlightSmall", "", C.muted)
    row.leader:SetPoint("TOP", row.score, "BOTTOM", 0, -3)
    row.leader:SetWidth(COL.leaderWidth)
    row.leader:SetJustifyH("CENTER")
    row.leader:SetWordWrap(false)

    row.age = UI.Text(row, "GameFontHighlightSmall", "", { .62, .70, .80, 1 })
    row.age:SetPoint("RIGHT", -COL.ageRight, 0)
    row.age:SetWidth(COL.ageWidth)
    row.age:SetJustifyH("CENTER")

    row.apply = UI.Button(row, L("Заявка"), COL.applyWidth, 26, true)
    row.apply:SetPoint("RIGHT", -COL.applyRight, 0)
    row.apply:HookScript("OnEnter", function(self)
        local coach = ApplicationCoachTooltip(self.match)
        UI.Tooltip(self, L("Заявка в группу"),
            L("Клик — подать сразу с ролью текущей специализации.\nShift+клик — открыть роли и написать комментарий.")
                .. (coach and ("\n\n" .. coach) or ""))
    end)
    row.apply:HookScript("OnLeave", GameTooltip_Hide)
    row.apply:SetScript("OnClick", function(self)
        local resultID = self.match and self.match.searchResultID
        if not resultID then return end
        local _, cancellable = GroupSearchUI:GetApplicationState(resultID)
        if cancellable then
            if JP.AutoMatch:Cancel(self.match) then
                self.applicationActive = false
                self.cancelRequestedAt = GetTime()
                self:SetText(L("Отмена…"))
                self:Disable()
                C_Timer.After(.5, function()
                    if self.match and self.match.searchResultID == resultID then
                        GroupSearchUI:UpdateApplicationButton(self)
                    end
                end)
            end
        else
            -- Read the modifier inside the actual hardware click. The old
            -- handler never inspected it, so both tooltip shortcuts followed
            -- the same path regardless of Shift.
            JP.AutoMatch:Apply(self.match, IsShiftKeyDown and IsShiftKeyDown())
        end
    end)
    row.apply:SetScript("OnUpdate", function(self, elapsed)
        self.updateElapsed = (self.updateElapsed or 0) + elapsed
        if self.updateElapsed < .25 then return end
        self.updateElapsed = 0
        if self.match then GroupSearchUI:UpdateApplicationButton(self) end
    end)

    local function Enter()
        if row.isSection then return end
        row:SetBackdropColor(UI.Unpack(C.rowHover))
        ShowGroupTooltip(row)
    end
    local function Leave()
        if row.isSection then return end
        row:SetBackdropColor(UI.Unpack(row.baseColor))
        HideGroupTooltip()
    end
    row:SetScript("OnEnter", Enter)
    row:SetScript("OnLeave", Leave)
    row.apply:HookScript("OnEnter", Enter)
    row.apply:HookScript("OnLeave", Leave)

    row:Hide()
    return row
end

local function SetResultFieldsShown(row, shown)
    row.keyBox:SetShown(shown)
    row.roles:SetShown(shown)
    row.dungeon:SetShown(shown)
    row.detail:SetShown(shown)
    row.score:SetShown(shown)
    row.leader:SetShown(shown)
    row.age:SetShown(shown)
    row.apply:SetShown(shown)
end

local function ApplicationCoachText(match)
    if not match then return nil end
    local state = match.applicationState
    local labels = {
        ready = L("ПОДХОДИТ"), risky = L("РИСК"),
        applied = L("ПОДАНА"), invited = L("ПРИГЛАШЕНИЕ"),
    }
    return labels[state]
end

ApplicationCoachTooltip = function(match)
    if not match then return end
    local lines = {}
    local reasons = type(match.applicationReasons) == "table" and match.applicationReasons or {}
    local unknowns = type(match.applicationUnknowns) == "table" and match.applicationUnknowns or {}
    for _, value in ipairs(reasons) do if type(value) == "string" and value ~= "" then lines[#lines + 1] = value end end
    for _, value in ipairs(unknowns) do if type(value) == "string" and value ~= "" then lines[#lines + 1] = (L("Неизвестно: %s")):format(value) end end
    local summary = ApplicationCoachText(match)
    if summary then lines[#lines + 1] = summary end
    if #lines == 0 then return end
    return table.concat(lines, "\n")
end

-- Never render a key level taken from a Blizzard search-result table. In
-- Midnight such a value can stay protected even after a type/secret check and
-- FontString then replaces it with literal "...". Build the display only from
-- the player's local filter state and locally stored personal bests.
local function LocalDisplayKeyLevel(welcome, match)
    local filters = welcome and welcome.groupFilters or {}
    if filters.scoreUpgrade then
        local mapID = match and UsableNumber(match.mapID) and match.mapID or nil
        local best = mapID and JP:GetBestLevel(mapID, 0) or nil
        if UsableNumber(best) and best > 0 then return math.floor(best + .5) + 1 end
    end

    local minimum = tonumber(filters.keyMin)
    local maximum = tonumber(filters.keyMax)
    if minimum and maximum and minimum >= 2 and minimum == maximum then
        return math.floor(minimum + .5)
    end

    local searched = GroupSearchUI.lastSearchTarget
    if UsableNumber(searched) and searched >= 2 then return math.floor(searched + .5) end
end

function GroupSearchUI:RenderRows(welcome)
    local matches = welcome.matches or {}
    local offset = welcome.offset or 0
    for index, row in ipairs(welcome.rows) do
        local match = matches[offset + index]
        if match and row.layoutVisible ~= false then
            if match.isSection then
                row.isSection = true
                row.match, row.searchResultID, row.dungeonName = nil, nil, nil
                row.lastResultID = nil
                row.apply.cancelRequestedAt = nil
                row.apply.match = nil
                SetResultFieldsShown(row, false)
                row.sectionLabel:SetText(match.sectionLabel or L("НЕ ПРОШЛИ ФИЛЬТРЫ"))
                row.sectionLabel:Show()
                row.sectionLine:Show()
                row.sectionLineRight:Show()
                row:SetBackdropColor(.025, .030, .036, .72)
                row:SetBackdropBorderColor(.12, .14, .17, .55)
                row:Show()
            else
            row.isSection = false
            row.sectionLabel:Hide()
            row.sectionLine:Hide()
            row.sectionLineRight:Hide()
            SetResultFieldsShown(row, true)
            row.baseColor = match.rejected and { .040, .045, .052, .76 }
                or (index % 2 == 0 and C.rowAlt or C.row)
            row:SetBackdropColor(UI.Unpack(row.baseColor))
            row:SetBackdropBorderColor(UI.Unpack(match.rejected and { .12, .14, .17, .70 } or C.lineSoft))
            local displayedLevel = LocalDisplayKeyLevel(welcome, match)
            -- Only literal local text reaches the FontString. When there is no
            -- honest local number, a single plus is clearer than protected
            -- dots and does not pretend that the listing level is known.
            if row.key then row.key:Hide() end
            row.key = displayedLevel and row.keyLabels[displayedLevel] or row.keyFallback
            if not row.key then row.key = row.keyFallback end
            row.key:Show()
            local keyTexture = DungeonKeyTexture(match.mapID)
            row.keyIcon:SetTexture(keyTexture or "Interface\\Icons\\INV_Relics_Hourglass")
            row.keyIcon:SetTexCoord(keyTexture and .07 or .10, keyTexture and .93 or .90,
                keyTexture and .07 or .22, keyTexture and .93 or .78)
            row.keyIcon:SetDesaturated(match.rejected or not keyTexture)
            row.keyIcon:SetAlpha(match.rejected and .26 or (keyTexture and .92 or .22))
            if match.rejected then
                row.key:SetTextColor(.42, .45, .49, 1)
                row.keyBox:SetBackdropBorderColor(.16, .18, .21, .75)
            elseif displayedLevel then
                -- В режиме повышения показываем именно требуемый уровень
                -- выбранного данжа. Это цель, а не выдуманный уровень группы.
                row.key:SetTextColor(UI.Unpack(C.accent))
                row.keyBox:SetBackdropBorderColor(.10, .42, .58, 1)
            else
                row.key:SetTextColor(UI.Unpack(C.faint))
                row.keyBox:SetBackdropBorderColor(.16, .19, .24, 1)
            end

            row.dungeon:SetText(match.dungeon)
            row.dungeon:SetTextColor(UI.Unpack(match.rejected and { .48, .51, .55, 1 } or C.text))

            -- Имена в LFG иногда догружаются позже основной карточки. Берём
            -- свежие данные перед каждой отрисовкой, а не держим первый nil.
            if match.searchResultID and UsableNumber(match.members) then
                local refreshed = {}
                for memberIndex = 1, match.members do
                    local member = C_LFGList.GetSearchResultPlayerInfo(match.searchResultID, memberIndex)
                    if member then
                        refreshed[#refreshed + 1] = {
                            name = SafeString(member.name),
                            classFilename = SafeString(member.classFilename),
                            assignedRole = SafeString(member.assignedRole),
                            isLeader = SafeBoolean(member.isLeader) or memberIndex == 1,
                        }
                    end
                end
                if #refreshed > 0 then match.memberInfo = refreshed end
            end

            local parts = {}
            for _, member in ipairs(type(match.memberInfo) == "table" and match.memberInfo or {}) do
                local displayName = member.name
                if not displayName and member.isLeader and match.leaderName then
                    displayName = match.leaderName:match("^([^%-]+)")
                end
                if displayName then
                    if match.rejected then
                        parts[#parts + 1] = displayName
                    else
                        parts[#parts + 1] = ("%s |c%s%s|r"):format(
                            UI.ClassIcon(member.classFilename, 16),
                            UI.ClassColorCode(member.classFilename),
                            displayName)
                    end
                end
            end
            local names = table.concat(parts, "  ")
            -- Заголовок группы почти всегда просто «+15» — уровень уже стоит
            -- в отдельной колонке, поэтому убираем его из описания.
            local comment = match.title
            -- Some listings append an AI-generation disclaimer to the title.
            -- It carries no group-selection information and only consumes the
            -- single readable detail line, so omit that title altogether.
            if comment and comment:lower():find("искусственного интеллекта", 1, true) then
                comment = nil
            end
            if comment and match.keyLevel then
                local stripped = comment:gsub("^%s*[%+＋]?%s*%d%d?%s*", "")
                comment = stripped ~= "" and stripped or nil
            end
            if match.rejected then
                local secondary = comment or names
                if secondary then secondary = secondary:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
                row.detail:SetText(("|cff777f89%s: %s|r%s"):format(
                    L("НЕ ПРОШЛО"), match.rejectionReason or L("причина неизвестна"),
                    secondary and ("   |cff555d66—|r   |cff666e78" .. secondary .. "|r") or ""))
            else
                -- The optimizer score and its unknown-state marker are
                -- internal ranking inputs, not player-facing facts. Showing
                -- `[ЦЕЛЬ ?] 55` consumed the only readable line without
                -- explaining a decision. Keep using the score for sorting and
                -- show only information the player can act on.
                local detailParts = {}
                if comment then detailParts[#detailParts + 1] = "|cffa9b4c2" .. comment .. "|r" end
                if names ~= "" then detailParts[#detailParts + 1] = names end
                row.detail:SetText(table.concat(detailParts, "   |cff4c545e—|r   "))
            end

            if match.rejected then
                row.roles:SetText((L("|cff59616b%s  %s  БЛ%s  БР%s|r")):format(
                    match.hasTank and L("Т") or "—", match.hasHealer and L("Л") or "—",
                    match.hasBloodlust and "+" or "—", match.hasBattleRes and "+" or "—"))
            else
                row.roles:SetText(("%s %s %s %s"):format(
                    match.hasTank and UI.RoleIcon("TANK", 16) or "|cff3d434c—|r",
                    match.hasHealer and UI.RoleIcon("HEALER", 16) or "|cff3d434c—|r",
                    match.hasBloodlust and L("|cff28b8f5БЛ|r") or L("|cff3d434cБЛ|r"),
                    match.hasBattleRes and L("|cff43d17aБР|r") or L("|cff3d434cБР|r")))
            end

            local partyAverage = match.partyScoreAverage or match.score or 0
            row.score:SetText(match.rejected and ("|cff59616b[%d]|r"):format(math.floor(partyAverage + .5))
                or ("|cff%s[%d]|r"):format(PartyRatingColorCode(partyAverage), math.floor(partyAverage + .5)))
            row.leader:SetText(match.leaderName or "—")
            row.age:SetText(match.age and SecondsToTime(match.age, false, false, 1) or "—")
            row.leader:SetTextColor(UI.Unpack(match.rejected and { .38, .41, .45, 1 } or C.muted))
            row.age:SetTextColor(UI.Unpack(match.rejected and { .36, .39, .43, 1 } or { .62, .70, .80, 1 }))

            row.dungeonName = match.dungeon
            row.searchResultID = match.searchResultID
            row.match = match
            if row.lastResultID ~= match.searchResultID then
                row.apply.cancelRequestedAt = nil
                row.apply.updateElapsed = 0
                row.lastResultID = match.searchResultID
            end
            row.apply.match = match
            GroupSearchUI:UpdateApplicationButton(row.apply)
            row:Show()
            end
        else
            row.isSection = false
            row.sectionLabel:Hide()
            row.sectionLine:Hide()
            row.sectionLineRight:Hide()
            SetResultFieldsShown(row, true)
            row.searchResultID = nil
            row.match = nil
            row.lastResultID = nil
            row.apply.cancelRequestedAt = nil
            row.apply.match = nil
            row:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Раскладка
---------------------------------------------------------------------------

function GroupSearchUI:Layout(welcome)
    local cards, results = welcome.cardsPanel, welcome.resultsPanel
    if not cards or not results then return end

    local cardsWidth = cards:GetWidth()
    if cardsWidth < 100 and welcome.frame then cardsWidth = welcome.frame:GetWidth() - FILTERS_WIDTH - 76 end
    local available = math.max(560, cardsWidth - 16)
    local cardWidth = math.floor((available - CARD_GAP * 3) / 4)
    for index, card in ipairs(welcome.dungeonCards or {}) do
        local column, row = (index - 1) % 4, math.floor((index - 1) / 4)
        card:ClearAllPoints()
        card:SetSize(cardWidth, CARD_HEIGHT)
        card:SetPoint("TOPLEFT", 8 + column * (cardWidth + CARD_GAP), -30 - row * (CARD_HEIGHT + CARD_GAP))
        LayoutCardLoot(card, card.lootData and card.lootData.upgrades or {})
    end

    if welcome.filterSummary then
        local panel = welcome.filterSummary:GetParent()
        welcome.filterSummary:SetShown(panel:GetHeight() >= 580)
    end

    local visible = math.max(2, math.min(MAX_RESULT_ROWS, math.floor((results:GetHeight() - 70) / ROW_STEP)))
    welcome.visibleRows = visible
    for index, row in ipairs(welcome.rows or {}) do
        row.layoutVisible = index <= visible
        if not row.layoutVisible then row:Hide() end
    end

    if welcome.matches and welcome.scrollBar then
        local maximum = math.max(0, #welcome.matches - visible)
        welcome.scrollBar:SetMinMaxValues(0, maximum)
        welcome.offset = math.min(welcome.offset or 0, maximum)
        welcome.scrollBar:SetValue(welcome.offset)
        welcome.scrollBar:SetShown(maximum > 0)
        self:RenderRows(welcome)
    end
end

---------------------------------------------------------------------------
-- Панель фильтров
---------------------------------------------------------------------------

local function SectionLabel(parent, text, y)
    local label = UI.Text(parent, "GameFontNormalSmall", text, C.accent)
    label:SetPoint("TOPLEFT", 14, y)
    local line = UI.Line(parent, C.lineSoft)
    line:SetPoint("LEFT", label, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", parent, "RIGHT", -14, 0)
    return label
end

local function NumberField(parent, welcome, label, key, default, y)
    local title = UI.Text(parent, "GameFontHighlightSmall", label, C.muted)
    title:SetPoint("TOPLEFT", 14, y - 4)

    local field, box = UI.NumberBox(parent, 60, 21)
    box:SetPoint("TOPRIGHT", -14, y)

    local value = welcome.groupFilters[key]
    if value == nil then value = default; welcome.groupFilters[key] = value end
    field:SetText(tostring(value or ""))
    field:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        welcome.groupFilters[key] = self:GetText()
        JP:RequestRefresh(.25)
    end)
    welcome.filterFields[key] = field
    return field
end

local function BuildFilterPanel(welcome, body)
    local panel = UI.Panel(body, C.panel, C.line)
    panel:SetPoint("TOPLEFT", 10, -10)
    panel:SetPoint("BOTTOMLEFT", 10, 10)
    panel:SetWidth(FILTERS_WIDTH)

    local title = UI.Text(panel, "GameFontNormalLarge", L("ФИЛЬТРЫ"), C.accent)
    title:SetPoint("TOPLEFT", 14, -14)

    -- Вертикальный ритм подобран так, чтобы весь столбец помещался при
    -- минимальной высоте окна и не наезжал на сводку и кнопки внизу.
    local y = -44
    SectionLabel(panel, L("КЛЮЧ"), y); y = y - 20
    welcome.scoreUpgrade = UI.CheckBox(panel, L("Только повышающие рейтинг"), welcome.groupFilters.scoreUpgrade == true)
    welcome.scoreUpgrade:SetPoint("TOPLEFT", 14, y)
    welcome.scoreUpgrade:SetWidth(FILTERS_WIDTH - 28)
    welcome.scoreUpgrade:SetScript("OnEnter", function(self)
        UI.Tooltip(self, L("Только повышающие рейтинг"),
            L("Цель — следующий уровень: при твоём рекорде +10 нужен +11 этого подземелья."),
            L("Midnight скрывает уровень объявления от Lua. Если он защищён, MythicBoost отберёт нужное подземелье и покажет целевой уровень; фактический +ключ проверь в названии группы. Рекорд после прохождения обновляется локально."))
    end)
    welcome.scoreUpgrade:SetScript("OnLeave", GameTooltip_Hide)
    y = y - 28
    NumberField(panel, welcome, L("Ключ от"), "keyMin", "", y); y = y - 24
    NumberField(panel, welcome, L("Ключ до"), "keyMax", "", y); y = y - 30

    SectionLabel(panel, L("ЛИДЕР"), y); y = y - 22
    NumberField(panel, welcome, L("Рейтинг от"), "scoreMin", 0, y); y = y - 24
    NumberField(panel, welcome, L("Рейтинг до"), "scoreMax", "", y); y = y - 24
    -- Счётчик ключей лидера берётся только из Raider.IO. Без него любой порог
    -- выше нуля отсекает вообще все группы, поэтому не ставим эту ловушку по
    -- умолчанию.
    -- A leader-run threshold is useful when explicitly chosen, but it must not
    -- grow from the player's own completions or silently reject fresh groups.
    NumberField(panel, welcome, L("Ключей +10 от"), "runsMin", 0, y); y = y - 30

    SectionLabel(panel, L("ОТБОР"), y); y = y - 22

    local function FilterCheck(key, label, tooltipTitle, tooltipText)
        local check = UI.CheckBox(panel, label, welcome.groupFilters[key] == true, function(checked)
            welcome.groupFilters[key] = checked
            if key == "requireTank" then MythicBoostDB.autoMatch.requireTank = checked end
            welcome:Refresh()
        end)
        check:SetPoint("TOPLEFT", 14, y)
        check:SetWidth(FILTERS_WIDTH - 28)
        if tooltipText then
            check:HookScript("OnEnter", function(self) UI.Tooltip(self, tooltipTitle or label, tooltipText) end)
            check:HookScript("OnLeave", GameTooltip_Hide)
        end
        y = y - 23
        return check
    end

    welcome.roleFit = FilterCheck("roleFit", L("Места для всей пати"), L("Подходящие роли"),
        L("Показывать только группы, где хватает свободных мест под роли всех участников твоей текущей пати."))
    welcome.tank = FilterCheck("requireTank", L("Танк уже в группе"))
    welcome.healer = FilterCheck("requireHealer", L("Лекарь уже в группе"))
    welcome.bloodlust = FilterCheck("bloodlustFit", L("Подходит Bloodlust"), L("Умный Bloodlust"),
        L("Если Bloodlust уже есть у тебя или группы — пропускает её. Иначе оставляет группу только когда после вашего вступления остаётся место лекарю или бойцу с Bloodlust."))
    welcome.battleRes = FilterCheck("battleResFit", L("Подходит боевой рес"), L("Боевое воскрешение"),
        L("Если боевой рес уже есть у тебя или группы — пропускает её. Иначе проверяет, останется ли место классу с боевым воскрешением."))
    welcome.notDeclined = UI.CheckBox(panel, L("Скрыть отказавших"), welcome.groupFilters.notDeclined,
        function(checked) welcome.groupFilters.notDeclined = checked; welcome:Refresh() end)
    welcome.notDeclined:SetPoint("TOPLEFT", 14, y); welcome.notDeclined:SetWidth(FILTERS_WIDTH - 28)
    y = y - 23
    welcome.experiencedParty = FilterCheck("experiencedParty", L("Все проходили этот +ключ"),
        L("Только с подтверждённым опытом"),
        L("Оставляет группы, где каждый текущий участник уже закрывал это подземелье на искомом уровне или выше. Неизвестные профили не считаются подтверждением."))

    -- Диапазон ключа не имеет смысла в режиме «ровно следующий ключ»,
    -- поэтому поля гаснут вместе с состоянием флажка.
    local function UpdateUpgradeMode(refresh)
        local enabled = welcome.scoreUpgrade:GetChecked() and true or false
        welcome.groupFilters.scoreUpgrade = enabled
        for _, key in ipairs({ "keyMin", "keyMax" }) do
            welcome.filterFields[key]:SetFieldEnabled(not enabled)
        end
        if refresh then
            GroupSearchUI:RefreshDungeonCards(welcome)
            welcome:Refresh()
        end
    end
    welcome.scoreUpgrade:HookScript("OnClick", function(self)
        UpdateUpgradeMode(true)
    end)
    UpdateUpgradeMode(false)

    -- Снизу панели всё равно оставалось пустое место, а свой ключ и рейтинг —
    -- первое, на что смотришь перед подбором группы.
    local summary = UI.Panel(panel, { .035, .046, .060, .9 }, C.lineSoft)
    summary:SetPoint("BOTTOMLEFT", 12, 46)
    summary:SetPoint("BOTTOMRIGHT", -12, 46)
    summary:SetHeight(78)
    welcome.filterSummary = summary
    welcome.ownKey = UI.Text(summary, "GameFontHighlightSmall", "", C.text)
    welcome.ownKey:SetPoint("TOPLEFT", 10, -8)
    welcome.ownKey:SetPoint("TOPRIGHT", -10, -8)
    welcome.ownKey:SetJustifyH("LEFT")
    welcome.ownKey:SetWordWrap(false)
    welcome.ownScore = UI.Text(summary, "GameFontHighlightSmall", "", C.muted)
    welcome.ownScore:SetPoint("TOPLEFT", 10, -28)
    welcome.ownScore:SetPoint("TOPRIGHT", -10, -28)
    welcome.ownScore:SetJustifyH("LEFT")
    welcome.ownScore:SetWordWrap(false)

    welcome.createOwnKey = UI.Button(summary, L("Собрать свой ключ"), 190, 22, true)
    welcome.createOwnKey:SetPoint("BOTTOMLEFT", 10, 7)
    welcome.createOwnKey:SetPoint("BOTTOMRIGHT", -10, 7)
    welcome.createOwnKey:SetScript("OnClick", function() GroupSearchUI:OpenListingAction() end)
    welcome.createOwnKey:HookScript("OnEnter", function(self)
        UI.Tooltip(self, L("Собрать свой ключ"),
            L("Открыть «Подземелья и рейды» — там создаётся и меняется само объявление."),
            L("Подземелье и +уровень берутся из камня, режим — «Серьёзный»."))
    end)
    welcome.createOwnKey:HookScript("OnLeave", GameTooltip_Hide)

    local reset = UI.Button(panel, L("Сбросить"), 100, 26)
    reset:SetPoint("BOTTOMLEFT", 12, 12)
    reset:SetScript("OnClick", function()
        local defaults = { keyMin = "", keyMax = "", scoreMin = 0, scoreMax = "", runsMin = 0 }
        for key, value in pairs(defaults) do
            welcome.groupFilters[key] = value
            if welcome.filterFields[key] then welcome.filterFields[key]:SetText(tostring(value)) end
        end
        wipe(welcome.groupFilters.dungeons)
        welcome.groupFilters.dungeonsNone = nil
        local checkDefaults = {
            roleFit = true, requireTank = true, requireHealer = false,
            bloodlustFit = false, battleResFit = false, notDeclined = true,
            experiencedParty = false,
        }
        for key, value in pairs(checkDefaults) do welcome.groupFilters[key] = value end
        MythicBoostDB.autoMatch.requireTank = true
        welcome.roleFit:SetChecked(true)
        welcome.tank:SetChecked(true)
        welcome.healer:SetChecked(false)
        welcome.bloodlust:SetChecked(false)
        welcome.battleRes:SetChecked(false)
        welcome.notDeclined:SetChecked(true)
        if welcome.experiencedParty then welcome.experiencedParty:SetChecked(false) end
        welcome.scoreUpgrade:SetChecked(false)
        UpdateUpgradeMode(false)
        GroupSearchUI:RefreshDungeonCards(welcome)
        welcome:Refresh()
    end)

    local weak = UI.Button(panel, L("Слабые 3"), 100, 26)
    weak:SetPoint("BOTTOMRIGHT", -12, 12)
    weak:HookScript("OnEnter", function(self)
        UI.Tooltip(self, L("Слабые 3"), L("Оставить три подземелья с самым низким личным рекордом — самый быстрый прирост общего рейтинга."))
    end)
    weak:HookScript("OnLeave", GameTooltip_Hide)
    weak:SetScript("OnClick", function()
        local ordered = {}
        for _, data in ipairs(welcome.dungeonData or {}) do ordered[#ordered + 1] = data end
        table.sort(ordered, function(a, b)
            return JP:GetBestLevel(a.mapID, a.run and a.run.level or 0) < JP:GetBestLevel(b.mapID, b.run and b.run.level or 0)
        end)
        wipe(welcome.groupFilters.dungeons)
        welcome.groupFilters.dungeonsNone = nil
        for index = 1, math.min(3, #ordered) do welcome.groupFilters.dungeons[ordered[index].mapID] = true end
        GroupSearchUI:RefreshDungeonCards(welcome)
        welcome:Refresh()
    end)

    return panel
end

---------------------------------------------------------------------------
-- Панели карточек и результатов
---------------------------------------------------------------------------

local function BuildCardsPanel(welcome, body)
    local cards = UI.Panel(body, C.panel, C.line)
    cards:SetPoint("TOPLEFT", FILTERS_WIDTH + 20, -10)
    cards:SetPoint("TOPRIGHT", -10, -10)
    cards:SetHeight(CARDS_HEIGHT)
    welcome.cardsPanel = cards

    local title = UI.Text(cards, "GameFontNormalSmall", L("ПОДЗЕМЕЛЬЯ СЕЗОНА"), C.muted)
    title:SetPoint("TOPLEFT", 12, -11)

    welcome.selectAll = UI.Button(cards, L("Все"), 62, 21)
    welcome.selectAll:SetPoint("TOPRIGHT", -10, -8)
    welcome.selectAll:HookScript("OnEnter", function(self)
        UI.Tooltip(self, L("Все подземелья"),
            L("Одним нажатием выбрать все подземелья. Если уже выбраны все — выключить все."))
    end)
    welcome.selectAll:HookScript("OnLeave", GameTooltip_Hide)
    welcome.selectAll:SetScript("OnClick", function()
        local allSelected = #(welcome.dungeonData or {}) > 0
        for _, dungeon in ipairs(welcome.dungeonData or {}) do
            if not IsCardSelected(welcome, dungeon.mapID) then
                allSelected = false
                break
            end
        end
        wipe(welcome.groupFilters.dungeons)
        welcome.groupFilters.dungeonsNone = allSelected and true or nil
        GroupSearchUI:RefreshDungeonCards(welcome)
        welcome:Refresh()
    end)

    welcome.dungeonSummary = UI.Text(cards, "GameFontHighlightSmall", "", C.accent)
    welcome.dungeonSummary:SetPoint("RIGHT", welcome.selectAll, "LEFT", -10, 0)

    welcome.lootSummary = UI.Text(cards, "GameFontHighlightSmall", "")
    welcome.lootSummary:SetPoint("LEFT", title, "RIGHT", 14, 0)
    welcome.lootSummary:SetPoint("RIGHT", welcome.dungeonSummary, "LEFT", -12, 0)
    welcome.lootSummary:SetJustifyH("LEFT")
    welcome.lootSummary:SetWordWrap(false)

    welcome.dungeonCards = {}
    for index = 1, 8 do welcome.dungeonCards[index] = CreateDungeonCard(cards, welcome) end
    return cards
end

local function BuildResultsPanel(welcome, body)
    local results = UI.Panel(body, C.panel, C.line)
    results:SetPoint("TOPLEFT", FILTERS_WIDTH + 20, -(CARDS_HEIGHT + 18))
    results:SetPoint("BOTTOMRIGHT", -10, 10)
    welcome.resultsPanel = results

    -- Панель инструментов отдельной строкой над заголовками колонок:
    -- раньше кнопка «Обновить» наезжала на подпись «ВОЗРАСТ».
    local heading = UI.Text(results, "GameFontNormalSmall", L("ГРУППЫ"), C.muted)
    heading:SetPoint("TOPLEFT", 12, -12)

    welcome.resultsCount = UI.Text(results, "GameFontHighlightSmall", "", C.accent)
    welcome.resultsCount:SetPoint("LEFT", heading, "RIGHT", 10, 0)

    welcome.scan = UI.Button(results, L("Обновить"), 118, 24, true)
    welcome.scan:SetPoint("TOPRIGHT", -12, -8)
    welcome.scan:SetScript("OnClick", function() GroupSearchUI:RequestBlizzardSearch(welcome) end)
    welcome.scan:HookScript("OnEnter", function(self)
        UI.Tooltip(self, L("Обновить"), L("Запросить у Blizzard свежий список групп и отфильтровать его по твоим настройкам."))
    end)
    welcome.scan:HookScript("OnLeave", GameTooltip_Hide)

    local divider = UI.Line(results, C.lineSoft)
    divider:SetPoint("TOPLEFT", 10, -36)
    divider:SetPoint("TOPRIGHT", -10, -36)

    local function Header(text, width, right)
        local label = UI.Text(results, "GameFontNormalSmall", text, C.faint)
        label:SetPoint("TOPRIGHT", -right, -46)
        label:SetWidth(width)
        label:SetJustifyH("CENTER")
    end
    local keyLabel = UI.Text(results, "GameFontNormalSmall", L("КЛЮЧ"), C.faint)
    keyLabel:SetPoint("TOPLEFT", COL.keyLeft, -46)
    keyLabel:SetWidth(COL.keyWidth)
    keyLabel:SetJustifyH("CENTER")
    local groupLabel = UI.Text(results, "GameFontNormalSmall", L("ГРУППА / ПОДЗЕМЕЛЬЕ"), C.faint)
    groupLabel:SetPoint("TOPLEFT", COL.textLeft, -46)
    groupLabel:SetJustifyH("LEFT")
    Header(L("СОСТАВ"), COL.rolesWidth, COL.rolesRight)
    Header(L("СРЕДНИЙ RIO"), COL.leaderWidth, COL.leaderRight)
    Header(L("ВОЗРАСТ"), COL.ageWidth, COL.ageRight)

    welcome.rows = {}
    for index = 1, MAX_RESULT_ROWS do
        local row = CreateResultRow(results, index)
        row:SetPoint("TOPLEFT", 10, -62 - (index - 1) * ROW_STEP)
        row:SetPoint("TOPRIGHT", -18, -62 - (index - 1) * ROW_STEP)
        welcome.rows[index] = row
    end

    welcome.scrollBar = UI.ScrollBar(results)
    welcome.scrollBar:SetPoint("TOPRIGHT", -6, -62)
    welcome.scrollBar:SetPoint("BOTTOMRIGHT", -6, 12)
    welcome.scrollBar:SetScript("OnValueChanged", function(_, value)
        local offset = math.floor(value + .5)
        if offset ~= welcome.offset then
            welcome.offset = offset
            GroupSearchUI:RenderRows(welcome)
        end
    end)
    welcome.scrollBar:Hide()

    local function OnMouseWheel(_, delta)
        local _, maximum = welcome.scrollBar:GetMinMaxValues()
        welcome.scrollBar:SetValue(math.max(0, math.min(maximum, (welcome.offset or 0) - delta)))
    end
    results:EnableMouseWheel(true)
    results:SetScript("OnMouseWheel", OnMouseWheel)
    for _, row in ipairs(welcome.rows) do
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", OnMouseWheel)
    end

    welcome.empty = UI.Text(results, "GameFontHighlight", "", C.muted)
    welcome.empty:SetPoint("TOPLEFT", 24, -120)
    welcome.empty:SetPoint("TOPRIGHT", -24, -120)
    welcome.empty:SetJustifyH("CENTER")
    welcome.empty:SetSpacing(6)
    return results
end

---------------------------------------------------------------------------
-- Сводка по персонажу
---------------------------------------------------------------------------

function GroupSearchUI:RefreshOwnComposition(welcome)
    if welcome.partySlots then
        local units = { "player" }
        if IsInGroup and IsInGroup() and not (IsInRaid and IsInRaid()) then
            for index = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. index end
        end
        local roleColor = {
            TANK = { .20, .55, .95 }, HEALER = { .20, .86, .45 }, DAMAGER = { .95, .31, .32 },
        }
        for index, slot in ipairs(welcome.partySlots) do
            local unit = units[index]
            if unit and UnitExists(unit) then
                local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
                if (not role or role == "NONE") and unit == "player" then
                    local spec = GetSpecialization and GetSpecialization()
                    role = spec and GetSpecializationRole and GetSpecializationRole(spec) or role
                end
                if role ~= "TANK" and role ~= "HEALER" and role ~= "DAMAGER" then role = "NONE" end
                local known = UI.SetRoleTexture(slot.icon, role)
                slot.icon:SetShown(known)
                slot.unknown:SetShown(not known)
                local color = roleColor[role] or { .45, .51, .59 }
                slot:SetBackdropColor(.045, .065, .085, 1)
                slot:SetBackdropBorderColor(color[1], color[2], color[3], .95)
            else
                slot.icon:Hide()
                slot.unknown:Hide()
                slot:SetBackdropColor(.025, .034, .045, 1)
                slot:SetBackdropBorderColor(.14, .19, .25, 1)
            end
        end
    end

    if welcome.ownKey then
        local mapID = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID and C_MythicPlus.GetOwnedKeystoneChallengeMapID()
        local level = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel()
        local mapInfo = mapID and JP.API.GetChallengeMap(mapID)
        local mapName = mapInfo and mapInfo.name
        if mapName and UsableNumber(level) then
            welcome.ownKey:SetText((L("|cff8a939fтвой ключ|r  |cff43d17a+%d|r  %s")):format(level, mapName))
        else
            welcome.ownKey:SetText(L("|cff8a939fтвой ключ|r  |cff5b6470нет|r"))
        end
    end

    if welcome.createOwnKey then
        local _, _, level = OwnedKeystoneListingInfo()
        local active = C_LFGList.HasActiveEntryInfo and C_LFGList.HasActiveEntryInfo()
        local leader = not (IsInGroup and IsInGroup(LE_PARTY_CATEGORY_HOME))
            or not UnitIsGroupLeader or UnitIsGroupLeader("player", LE_PARTY_CATEGORY_HOME)
        welcome.createOwnKey:SetEnabled(level ~= nil and leader)
        welcome.createOwnKey:SetText(active and L("Открыть объявление") or L("Создать объявление"))
    end

    if welcome.ownScore then
        local score = C_ChallengeMode.GetOverallDungeonScore and C_ChallengeMode.GetOverallDungeonScore() or 0
        local _, equipped = GetAverageItemLevel()
        welcome.ownScore:SetText((L("|cff8a939fрейтинг|r  |cffffb93d%d|r     |cff8a939filvl|r  |cffd4dbe4%.0f|r"))
            :format(math.floor(UsableNumber(score) and score or 0), UsableNumber(equipped) and equipped or 0))
    end
end

---------------------------------------------------------------------------
-- Сборка
---------------------------------------------------------------------------

function GroupSearchUI:Build(welcome, body)
    welcome.groupFilters = MythicBoostDB.groupFilters
    welcome.groupFilters.dungeons = welcome.groupFilters.dungeons or {}
    if welcome.groupFilters.roleFit == nil then welcome.groupFilters.roleFit = true end
    if welcome.groupFilters.requireTank == nil then
        welcome.groupFilters.requireTank = MythicBoostDB.autoMatch.requireTank ~= false
    end
    if welcome.groupFilters.requireHealer == nil then welcome.groupFilters.requireHealer = false end
    if welcome.groupFilters.bloodlustFit == nil then
        welcome.groupFilters.bloodlustFit = MythicBoostDB.autoMatch.requireBloodlust == true
    end
    if welcome.groupFilters.battleResFit == nil then welcome.groupFilters.battleResFit = false end
    if welcome.groupFilters.notDeclined == nil then welcome.groupFilters.notDeclined = true end
    if welcome.groupFilters.experiencedParty == nil then welcome.groupFilters.experiencedParty = false end
    welcome.filterFields = {}

    BuildFilterPanel(welcome, body)
    BuildCardsPanel(welcome, body)
    BuildResultsPanel(welcome, body)

    welcome.searchEvents = CreateFrame("Frame")
    for _, event in ipairs({
        "LFG_LIST_SEARCH_RESULTS_RECEIVED",
        "LFG_LIST_SEARCH_FAILED",
        "LFG_LIST_AVAILABILITY_UPDATE",
        "LFG_LIST_UPDATE_SEARCH_RESULTS",
        "LFG_LIST_APPLICATION_STATUS_UPDATED",
        "GROUP_ROSTER_UPDATE",
        "PLAYER_ROLES_ASSIGNED",
    }) do
        welcome.searchEvents:RegisterEvent(event)
    end
    welcome.searchEvents:SetScript("OnEvent", function(_, event)
        if event == "LFG_LIST_AVAILABILITY_UPDATE" and GroupSearchUI.searchPending and GroupSearchUI.waitingForActivities then
            GroupSearchUI:ScheduleCurrentSearch(welcome, GroupSearchUI.searchToken)
        elseif event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" or event == "LFG_LIST_UPDATE_SEARCH_RESULTS" then
            if GroupSearchUI.searchPending then
                GroupSearchUI:QueueSearchResults(welcome, event)
            else
                GroupSearchUI:CaptureNativeExactSearch(welcome)
            end
        elseif event == "LFG_LIST_SEARCH_FAILED" and GroupSearchUI.searchPending then
            FinishBlizzardSearch(welcome, GroupSearchUI.searchToken, L("Поиск Blizzard завершился ошибкой."))
        else
            JP:RequestRefresh()
        end
    end)

    function welcome:GetGroupFilters()
        -- У выбранных подземелий разные следующие уровни. Один общий target
        -- оставлял только данжи с минимальной целью и скрывал остальные.
        self.groupFilters.searchTargetLevel = nil
        self.groupFilters.searchExactLevel = GroupSearchUI.manualExactLevel
        return self.groupFilters
    end

    self:RefreshDungeonCards(welcome)
    self:RefreshOwnComposition(welcome)
    self:Layout(welcome)
end

JP.GroupSearchUI = GroupSearchUI
