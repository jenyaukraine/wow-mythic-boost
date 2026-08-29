local _, JP = ...
local GroupSearchUI = {}
local UI = JP.UI
local C = UI.colors

local SEASON_ORDER = { 588, 584, 586, 587, 585, 399, 250, 249 }
local DUNGEON_SHORT = { [588] = "АК", [584] = "СД", [586] = "БН", [587] = "ЗД", [585] = "АШ", [399] = "РО", [250] = "ХС", [249] = "ГК" }
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
local ROW_HEIGHT, ROW_STEP = 62, 68
local CARD_HEIGHT, CARD_GAP = 84, 8
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

local function UsableNumber(value)
    return type(value) == "number" and not issecretvalue(value)
end

local function SafeString(value)
    if type(value) ~= "string" or issecretvalue(value) or value == "" then return nil end
    return value
end

-- fileID = 0 приходит от API как «текстуры нет». Без этой проверки
-- SetTexture(0) рисует чёрный прямоугольник вместо карточки.
local function ValidTexture(value)
    if type(value) == "number" and not issecretvalue(value) and value > 0 then return value end
    if type(value) == "string" and value ~= "" then return value end
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

local function ProfileRuns(name, classFilename)
    local profile = ProfileForName(name, classFilename)
    local keystone = profile and profile.mythicKeystoneProfile
    local runs = keystone and keystone.sortedDungeons
    if type(runs) ~= "table" or #runs == 0 then return end
    return runs
end

local function ProfileScore(profile)
    local keystone = profile and profile.mythicKeystoneProfile
    if type(keystone) ~= "table" then return end
    local function Pick(value)
        return UsableNumber(value) and value > 0 and value or nil
    end
    return Pick(keystone.currentScore)
        or Pick(keystone.score)
        or Pick(type(keystone.mplusCurrent) == "table" and keystone.mplusCurrent.score or nil)
end

-- Имя участника приходит без реалма, а группы кросс-реалмовые. Раньше брался
-- первый попавшийся профиль — и в таблицу попадали ключи однофамильца с
-- соседнего реалма. Теперь догадка принимается только если она одна:
-- при нескольких совпадениях показываем прочерк, а не чужие данные.
local profileRunCache, resolvedProfileCache = {}, {}

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
        resolvedProfileCache[cacheKey] = profile or false
        return profile
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
        if hits > 1 then JP:Log("реалм выбран приблизительно: %s (%d профилей)", name, hits) end
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
    profileRunCache[cacheKey] = type(runs) == "table" and #runs > 0 and runs or false
    return profileRunCache[cacheKey] or nil
end

function GroupSearchUI:ClearProfileCache()
    wipe(profileRunCache)
    wipe(resolvedProfileCache)
end

local function PartyRatingColorCode(value)
    value = tonumber(value) or 0
    if value >= 3000 then return "ffb93d" end
    if value >= 2500 then return "b36cff" end
    if value >= 2000 then return "32b6ff" end
    return "43d17a"
end

-- Считаем силу всей уже собранной группы. Точный общий рейтинг лидера
-- приходит от Blizzard, остальные профили берём из локальной базы Raider.IO.
-- Делитель — фактическое количество людей, как и ожидается от среднего.
function GroupSearchUI:EnrichPartyRatings(matches)
    for _, match in ipairs(type(matches) == "table" and matches or {}) do
        local members = type(match.memberInfo) == "table" and match.memberInfo or {}
        local memberCount = math.max(tonumber(match.members) or 0, #members)
        local total, known, leaderCounted = 0, 0, false

        for _, member in ipairs(members) do
            local memberName = SafeString(member.name)
            local leaderBase = match.leaderName and match.leaderName:match("^([^%-]+)")
            local isLeader = member.isLeader
                or (leaderBase and memberName and leaderBase:lower() == memberName:lower())
            local score
            if isLeader and UsableNumber(match.score) and match.score > 0 then
                score, leaderCounted = match.score, true
            else
                local lookupName = memberName or (isLeader and match.leaderName)
                score = ProfileScore(ResolveRaiderProfile(lookupName, match.leaderName, member.classFilename))
            end
            if UsableNumber(score) and score > 0 then
                total, known = total + score, known + 1
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
        match.partyScoreAverage = total / memberCount
    end

    table.sort(matches, function(a, b)
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

local function LeaderKeyValue(entry)
    return TimedValue(entry and entry.bestRunLevel, entry and entry.bestLevelIncrement, entry and entry.finishedSuccess)
end

local function RaiderKeyValue(run)
    return TimedValue(run and run.level, run and run.chests, false)
end

local function DungeonKey(dungeon)
    return dungeon and (dungeon.keystone_instance or dungeon.id or dungeon.shortNameLocale or dungeon.shortName or dungeon.name)
end

local function DungeonColumns()
    local columns = {}
    for index, run in ipairs(PlayerRuns()) do
        if #columns >= 8 then break end
        local dungeon = run and run.dungeon
        local key = DungeonKey(dungeon)
        columns[#columns + 1] = {
            key = key or index,
            label = DUNGEON_SHORT[key] or (dungeon and (dungeon.shortNameLocale or dungeon.shortName)) or tostring(index),
            name = dungeon and dungeon.name,
        }
    end
    if #columns == 0 then
        for index, mapID in ipairs(SEASON_ORDER) do
            columns[#columns + 1] = { key = mapID, label = DUNGEON_SHORT[mapID] or tostring(index), name = C_ChallengeMode.GetMapUIInfo(mapID) }
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
    local runs = ResolveRaiderRuns(fullName, nil, classFilename)
    if type(runs) ~= "table" or #runs == 0 then return nil end
    local mapped = RunsByDungeon(runs)
    local parts = {}
    for _, column in ipairs(DungeonColumns()) do
        local value, timed = RaiderKeyValue(mapped[column.key])
        local color = timed and "|cff43d17a" or value == "—" and "|cff454b54" or "|cff8a8f98"
        parts[#parts + 1] = ("|cff5b6470%s|r %s%s|r"):format(column.label, color, value)
    end
    return table.concat(parts, "   ")
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
    local cells = {}
    for index, column in ipairs(DungeonColumns()) do
        local run = mapped[column.key]
        local value, grade = RaiderKeyValue(run)
        cells[index] = { value = value, grade = grade, level = RunLevel(run), label = column.label }
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

function GroupSearchUI:GetBelowKeyColor()
    return BELOW_KEY_COLOR
end

local function BlizzardRunsByDungeon(scoreInfo, columns)
    local mapped = {}
    for index, entry in ipairs(type(scoreInfo) == "table" and scoreInfo or {}) do
        local key = entry.challengeModeID or entry.mapChallengeModeID
        if not key and entry.mapName then
            for _, column in ipairs(columns) do if column.name == entry.mapName then key = column.key break end end
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
    frame.meta:SetPoint("TOPRIGHT", -14, -32)
    frame.meta:SetJustifyH("LEFT")
    frame.meta:SetWordWrap(false)

    local divider = UI.Line(frame, C.accentDim)
    divider:SetPoint("TOPLEFT", 12, -54)
    divider:SetPoint("TOPRIGHT", -12, -54)

    frame.playerHeader = UI.Text(frame, "GameFontNormalSmall", "ИГРОК", C.faint)
    frame.playerHeader:SetPoint("TOPLEFT", 14, -66)
    frame.playerHeader:SetWidth(TIP_NAME_WIDTH)
    frame.playerHeader:SetJustifyH("LEFT")

    frame.columnHeaders = {}
    for index = 1, 8 do
        local header = UI.Text(frame, "GameFontNormalSmall", "", C.accent)
        header:SetPoint("TOPLEFT", 14 + TIP_NAME_WIDTH + (index - 1) * TIP_CELL_WIDTH, -66)
        header:SetWidth(TIP_CELL_WIDTH)
        header:SetJustifyH("CENTER")
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

local function ShowGroupTooltip(row, externalResultID, externalDungeonName, placement)
    local searchResultID = externalResultID or row.searchResultID
    local dungeonName = externalDungeonName or row.dungeonName
    if not searchResultID then return end
    local info = C_LFGList.GetSearchResultInfo(searchResultID)
    if not info then return end
    local tooltip = GetGroupTooltip()
    local columns = DungeonColumns()

    tooltip:ClearAllPoints()
    if placement == "below" then
        -- On Blizzard rows the normal GameTooltip and Raider.IO already take
        -- the right side of the screen. Put our full table in one clean block
        -- below the Group Finder instead of stacking a third tooltip there.
        tooltip:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 0, -8)
    else
        local spaceRight = (UIParent:GetRight() or 0) - (row:GetRight() or 0)
        if spaceRight > tooltip:GetWidth() + 18 then
        tooltip:SetPoint("TOPLEFT", row, "TOPRIGHT", 8, 0)
        else
            tooltip:SetPoint("TOPRIGHT", row, "TOPLEFT", -8, 0)
        end
    end

    local leaderName = SafeString(info.leaderName)
    tooltip.title:SetText(SafeString(info.name) or dungeonName or "Группа")
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
    local ratingText
    if match and match.partyScoreAverage then
        ratingText = ("средний RIO %d · найдено %d/%d"):format(
            math.floor(match.partyScoreAverage + .5),
            match.partyScoreKnown or 0,
            match.partyScoreMembers or info.numMembers or 0)
    else
        ratingText = ("RIO лидера %d"):format(
            math.floor(UsableNumber(info.leaderOverallDungeonScore) and info.leaderOverallDungeonScore or 0))
    end
    tooltip.meta:SetText(("%s   —   %s   —   %s"):format(
        dungeonName or "Подземелье", leaderName or "лидер неизвестен", ratingText))

    for index, header in ipairs(tooltip.columnHeaders) do
        header:SetText(columns[index] and columns[index].label or "")
    end

    for playerIndex, line in ipairs(tooltip.playerRows) do
        local member = playerIndex <= (info.numMembers or 0) and C_LFGList.GetSearchResultPlayerInfo(searchResultID, playerIndex)
        if member then
            local leaderBase = leaderName and leaderName:match("^([^%-]+)")
            local memberName = SafeString(member.name)
            local isLeader = member.isLeader or (leaderBase and memberName and leaderBase:lower() == memberName:lower())
            local mapped = RunsByDungeon(ResolveRaiderRuns(member.name, leaderName, member.classFilename))
            if isLeader and next(mapped) == nil then mapped = BlizzardRunsByDungeon(info.leaderDungeonScoreInfo, columns) end

            line.name:SetText(("%s %s %s"):format(
                UI.RoleIcon(member.assignedRole, 14),
                UI.ClassIcon(member.classFilename, 16),
                memberName or "Игрок"))
            line.name:SetTextColor(UI.ClassColor(member.classFilename))

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

    tooltip:SetHeight(92 + math.max(1, info.numMembers or 0) * 24)
    tooltip:Show()
end

local function HideGroupTooltip()
    if GroupSearchUI.groupTooltip then GroupSearchUI.groupTooltip:Hide() end
    GameTooltip_Hide()
end

-- Тот же полный тултип доступен и на штатных строках Blizzard. Стандартный
-- GameTooltip остаётся на месте, а таблица участников открывается снизу.
function GroupSearchUI:ShowBlizzardResultTooltip(owner, searchResultID)
    if not owner or not searchResultID then return end
    local info = C_LFGList.GetSearchResultInfo(searchResultID)
    if not info then return end
    local activityID = UsableNumber(info.activityID) and info.activityID or nil
    if not activityID and type(info.activityIDs) == "table" and not issecretvalue(info.activityIDs) then
        local first = info.activityIDs[1]
        if UsableNumber(first) then activityID = first end
    end
    local activity = activityID and C_LFGList.GetActivityInfoTable(activityID)
    local dungeonName = activity and SafeString(activity.fullName or activity.shortName) or "Подземелье"
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
        local enabled = selectedCount == 0 or selected[dungeon.mapID] or selected[tostring(dungeon.mapID)]
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
    return levels[1]
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
    copy.roleFit = true
    copy.searchTargetLevel = targetLevel
    return copy
end

local function FinishBlizzardSearch(welcome, token, message)
    if token and GroupSearchUI.searchToken ~= token then return end
    GroupSearchUI.searchPending = false
    GroupSearchUI.searchAwaitingResults = false
    GroupSearchUI.waitingForActivities = false
    if welcome.scan then
        welcome.scan:Enable()
        welcome.scan:SetText("Обновить")
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
        GroupSearchUI.completedBatch = {
            matches = merged,
            scanned = GroupSearchUI.batchScanned or 0,
            rejected = GroupSearchUI.batchRejected or {},
        }
    end
    GroupSearchUI.batchMatches = nil
    GroupSearchUI.batchRejected = nil
    GroupSearchUI.searchQueue = nil
    -- Кэш профилей здесь НЕ чистим: сразу за этим идёт перерисовка, которая
    -- его и наполняет, и сброс заставлял платить полную цену заново.
    -- Актуальность обеспечивает сброс в начале нового поиска.
    JP:RequestRefresh(.1)
end

function GroupSearchUI:CaptureCurrentSearch(welcome)
    local targetLevel = self.currentSearchTarget
    local matches, _, scanned, rejected = JP.AutoMatch:Scan(
        welcome.tank:GetChecked(), welcome.bloodlust:GetChecked(), CopyFilters(welcome, targetLevel), {
            bestByMap = welcome.bestByMap,
            bestByActivity = welcome.bestByActivity,
        })
    self.batchScanned = (self.batchScanned or 0) + (scanned or 0)
    for reason, count in pairs(rejected or {}) do
        self.batchRejected[reason] = (self.batchRejected[reason] or 0) + count
    end
    for _, match in ipairs(matches or {}) do self.batchMatches[match.searchResultID] = match end
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
    self.batchRejected = nil
    self.searchFilterSnapshot = nil
    welcome.scan:SetText(("Подожди %dс"):format(math.max(1, math.ceil(delay))))
    C_Timer.After(delay, function()
        if not GroupSearchUI.searchPending and GroupSearchUI.searchToken == token then
            welcome.scan:Enable()
            welcome.scan:SetText("Обновить")
        end
    end)
end

---------------------------------------------------------------------------
-- Серверный фильтр Blizzard
--
-- Раньше мы просили у сервера все подземелья подряд и отбирали нужное уже у
-- себя: из сотни присланных групп до выбранного подземелья доживали единицы,
-- а героики и обычные забивали выдачу. C_LFGList.SaveAdvancedFilter — тот же
-- фильтр, что стоит за кнопкой «Фильтр» в стандартном окне, и он доступен
-- аддонам без taint, в отличие от строки поиска.
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
    for _, mapID in ipairs(C_ChallengeMode.GetMapTable and C_ChallengeMode.GetMapTable() or {}) do
        local mapName = C_ChallengeMode.GetMapUIInfo(mapID)
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
    local all = SelectedCount(welcome) == 0
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
        hasHealer = false,
        difficultyNormal = false,
        difficultyHeroic = false,
        difficultyMythic = false,
        difficultyMythicPlus = true,
        minimumRating = tonumber(welcome.groupFilters.scoreMin) or 0,
        hasTank = welcome.tank and welcome.tank:GetChecked() and true or false,
        activities = wantedGroups,
    }
    -- PGF передаёт сюда именно activityGroupID, а не activityID отдельных
    -- сложностей. Для пустого выбора карточек мы уже собрали все восемь групп.
    if all then wantedActivities = {} end

    JP:Log("прямой серверный фильтр: groupIDs=%d activityIDs=%d, M+, рейтинг от %d",
        #wantedGroups, #wantedActivities, filter.minimumRating)
    return filter, nil
end

function GroupSearchUI:RunDirectSearch(welcome, token)
    if not self.searchPending or self.searchToken ~= token then return end
    self.waitingForActivities = false
    local step, total = self.searchIndex or 1, #(self.searchQueue or {})
    welcome.scan:SetText(total > 1 and ("Поиск %d/%d"):format(step, total) or "Поиск...")
    self.nextSearchAt = GetTime() + SEARCH_COOLDOWN

    local targetLevel = self.searchQueue and self.searchQueue[step]
    if targetLevel == false then targetLevel = nil end
    self.currentSearchTarget = targetLevel
    self.searchStep = (self.searchStep or 0) + 1
    local searchStep = self.searchStep
    self.searchAwaitingResults = true
    local ok = false

    -- SearchBox стандартного LFG защищён, поэтому SetText("+11") делать
    -- нельзя. Зато C_LFGList.Search принимает advancedFilter и отдельный
    -- activityIDsFilter: передаём выбранные карточки прямо в запрос, не
    -- открывая и не меняя стандартный Blizzard-фрейм.
    -- Сборка фильтра тоже обязана быть защищена: если список активностей ещё
    -- не готов или API конкретной сборки вернул неожиданные данные, кнопка не
    -- должна навечно оставаться в состоянии «Поиск...».
    local built, advancedFilter, activityIDs = pcall(self.BuildServerFilter, self, welcome)
    if not built then
        JP:Log("ошибка серверного фильтра: %s", tostring(advancedFilter))
        FinishBlizzardSearch(welcome, token, "Не удалось собрать фильтр Blizzard. Нажми «Обновить» ещё раз.")
        return
    end
    -- SaveAdvancedFilter — ровно тот путь, которым PGF устанавливает фильтр
    -- подземелий. Благодаря этому стандартное окно (если оно открыто) тоже
    -- отображает тот же whitelist, а не старую смешанную выдачу.
    if type(C_LFGList.SaveAdvancedFilter) == "function" then
        -- Мы перезаписываем настройку стандартного окна, поэтому исходную
        -- сохраняем один раз: без этого /mb restorefilter вернуть уже нечего.
        if not MythicBoostDB.blizzardFilterBackup and type(C_LFGList.GetAdvancedFilter) == "function" then
            local okBackup, previous = pcall(C_LFGList.GetAdvancedFilter)
            if okBackup and type(previous) == "table" and CopyTable then
                MythicBoostDB.blizzardFilterBackup = CopyTable(previous)
            end
        end
        local saved = pcall(C_LFGList.SaveAdvancedFilter, advancedFilter)
        if not saved then
            FinishBlizzardSearch(welcome, token, "Blizzard не принял фильтр подземелий.")
            return
        end
    end
    local filterEnum = Enum and Enum.LFGListFilter or {}
    local languages = C_LFGList.GetLanguageSearchFilter and C_LFGList.GetLanguageSearchFilter() or nil
    local searchFilter = filterEnum.PvE or 4
    if bit and filterEnum.CurrentSeason then searchFilter = bit.bor(searchFilter, filterEnum.CurrentSeason) end
    ok = pcall(C_LFGList.Search, 2, searchFilter, 0, languages, nil, advancedFilter, activityIDs)
    if not ok then
        FinishBlizzardSearch(welcome, token, "Blizzard не разрешил выполнить поиск сейчас.")
        return
    end
    C_Timer.After(7, function()
        if GroupSearchUI.searchPending and GroupSearchUI.searchToken == token and GroupSearchUI.searchStep == searchStep then
            FinishBlizzardSearch(welcome, token, "Поиск Blizzard не ответил. Нажми «Обновить» ещё раз.")
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
function GroupSearchUI:QueueSearchResults(welcome)
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
    -- Сбрасываем профили в начале поиска, а не в конце: к моменту отрисовки
    -- кэш должен уже наполняться, иначе перебор реалмов идёт дважды.
    self:ClearProfileCache()
    -- Серверный перебор строк "+11", "+12" запрещён защищённым SearchBox.
    -- Один широкий запрос не дублирует те же 100 результатов и не ловит taint.
    self.searchQueue = { false }
    self.searchIndex = 1
    self.batchMatches = {}
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
    for _, mapID in ipairs(C_ChallengeMode.GetMapTable and C_ChallengeMode.GetMapTable() or {}) do available[mapID] = true end
    local ordered = {}
    for _, mapID in ipairs(SEASON_ORDER) do
        if available[mapID] or byMap[mapID] then ordered[#ordered + 1] = mapID; available[mapID] = nil end
    end
    for mapID in pairs(available) do ordered[#ordered + 1] = mapID end
    if #ordered == 0 then for mapID in pairs(byMap) do ordered[#ordered + 1] = mapID end end

    local result = {}
    for _, mapID in ipairs(ordered) do
        if #result >= 8 then break end
        local name, _, _, icon, background, instanceMapID = C_ChallengeMode.GetMapUIInfo(mapID)
        local run = byMap[mapID]
        local rioDungeon = run and run.dungeon
        if rioDungeon and type(rioDungeon.instance_map_ids) == "table" then
            instanceMapID = rioDungeon.instance_map_ids[1] or instanceMapID
        end
        result[#result + 1] = {
            mapID = mapID,
            instanceMapID = instanceMapID,
            name = SafeString(name) or ("Подземелье " .. (#result + 1)),
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
        return ("%s • цель +%d"):format(chosen.name or "Подземелье", math.max(1, best + 1))
    elseif count > 1 then
        return ("выбрано подземелий: %d"):format(count)
    end
    return "все 8 подземелий"
end

IsCardSelected = function(welcome, mapID)
    local selected = welcome.groupFilters.dungeons
    if SelectedCount(welcome) == 0 then return true end
    return (selected[mapID] or selected[tostring(mapID)]) and true or false
end

local function SetCardSelected(card, selected)
    card.selected = selected and true or false
    card:SetBackdropColor(selected and .085 or .050, selected and .105 or .062, selected and .135 or .080, .96)
    if selected and card.isLootBest then
        card:SetBackdropBorderColor(1, .58, .12, 1)
    elseif selected and card.hasUsefulLoot then
        card:SetBackdropBorderColor(.58, .25, .92, 1)
    else
        card:SetBackdropBorderColor(selected and .18 or .12, selected and .58 or .16, selected and .78 or .21, 1)
    end
    card.accent:SetShown(card.selected)
    card.art:SetAlpha(selected and .32 or .10)
    card.art:SetDesaturated(not selected)
    card.icon:SetDesaturated(not selected)
    card.icon:SetAlpha(selected and 1 or .55)
    card.iconBorder:SetBackdropBorderColor(selected and .22 or .14, selected and .46 or .18, selected and .60 or .24, 1)
    card.title:SetTextColor(selected and C.text[1] or .58, selected and C.text[2] or .63, selected and C.text[3] or .70)
    card.best:SetAlpha(selected and 1 or .55)
    card.loot:SetAlpha(selected and 1 or .55)
    for _, itemButton in ipairs(card.lootItems or {}) do itemButton:SetAlpha(selected and 1 or .45) end
end

local function SetLootItem(button, item)
    button.item = item
    if not item then button:Hide(); return end
    local texture = item.icon
    if not texture and item.itemID and C_Item and C_Item.GetItemIconByID then texture = C_Item.GetItemIconByID(item.itemID) end
    button.icon:SetTexture(texture or 134400)
    button.icon:SetTexCoord(.07, .93, .07, .93)
    button.gain:SetText(item.gain and ("+" .. item.gain) or "")
    button:Show()
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
                card.art:SetTexCoord(.08, .92, .18, .82)
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
            if level > 0 then
                card.best:SetText(("|cff8a939fтвой|r |cff43d17a+%d|r    |cff8a939fцель|r |cff28b8f5+%d|r")
                    :format(level, level + 1))
            else
                card.best:SetText("|cff8a939fрезультата ещё нет|r")
            end

            local percent = card.lootData and card.lootData.percent or 0
            local analyzed = card.lootData and not card.lootData.pending and (card.lootData.total or 0) > 0
            card.isLootBest = bestMapID == dungeon.mapID
            card.hasUsefulLoot = percent > 0
            card.loot:SetText(analyzed and (percent .. "%") or "...")
            if percent >= 50 then card.loot:SetTextColor(1, .74, .24, 1)
            elseif percent > 0 then card.loot:SetTextColor(.73, .48, 1, 1)
            else card.loot:SetTextColor(UI.Unpack(C.faint)) end

            local upgrades = card.lootData and card.lootData.upgrades or {}
            local visibleItems = math.max(1, math.min(#card.lootItems, math.floor((card:GetWidth() - 72) / 28)))
            for itemIndex, itemButton in ipairs(card.lootItems) do
                SetLootItem(itemButton, itemIndex <= visibleItems and upgrades[itemIndex] or nil)
            end

            SetCardSelected(card, IsCardSelected(welcome, dungeon.mapID))
            card:Show()
        else
            card.mapID = nil
            card:Hide()
        end
    end

    local active = SelectedCount(welcome)
    welcome.dungeonSummary:SetText(("%d / %d"):format(active == 0 and #data or active, #data))
    if welcome.lootSummary then
        local bestLoot = bestMapID and loot[bestMapID]
        welcome.lootSummary:SetText(bestName
            and ("|cff8a939fДроп +10: %d  лучший шанс|r  |cffffb93d%s|r  |cffb36cff%d%% (%d из %d)|r")
                :format(bestDropLevel or bestLoot.dropLevel or 0, bestName, bestPercent, bestLoot.useful or 0, bestLoot.total or 0)
            or (lootPending and "|cff8aa8c4Загружаю уровни предметов...|r"
                or (hasLootData and "|cff687584Улучшений по ilvl не найдено|r" or "|cff687584Загружаю таблицу лута...|r")))
    end
end

local function CardTooltip(card)
    if not card.mapID then return end
    GameTooltip:SetOwner(card, "ANCHOR_RIGHT")
    GameTooltip:SetText(card.title:GetText() or "", 1, .82, 0)

    local loot = card.lootData
    if loot and (loot.total or 0) > 0 then
        GameTooltip:AddDoubleLine("Шанс полезного предмета +10", loot.percent .. "%",
            .45, .75, 1,
            loot.percent >= 50 and 1 or .73, loot.percent >= 50 and .72 or .42, loot.percent >= 50 and .18 or 1)
        local dropLevel = tonumber(loot.dropLevel) or 0
        local dropText = dropLevel > 0 and ("Дроп +10: %d"):format(dropLevel) or "Уровень дропа загружается"
        GameTooltip:AddLine(("%s. %d из %d предметов улучшают %d слота. Средний прирост +%d")
            :format(dropText, loot.useful or 0, loot.total, loot.slotCount or 0, loot.averageGain or 0), .72, .78, .86)
        for index = 1, math.min(5, #loot.upgrades) do
            local item = loot.upgrades[index]
            local icon = item.icon and ("|T" .. item.icon .. ":16:16:0:0|t ") or ""
            GameTooltip:AddDoubleLine(icon .. (item.name or "Предмет"),
                ("%s  %d -> %d  (+%d)"):format(item.slot or "Слот", item.equipped, item.level, item.gain),
                .90, .92, .96, .25, 1, .55)
        end
        GameTooltip:AddLine("Процент = полезные предметы / весь доступный твоему спеку пул. Это шанс апгрейда при условии, что предмет достался тебе.", .52, .68, .82, true)
        GameTooltip:AddLine("Эффекты аксессуаров и вторичные характеристики пока не учитываются.", .52, .58, .66, true)
    else
        GameTooltip:AddLine("Подходящей добычи для текущей специализации не найдено.", .52, .58, .66, true)
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(card.selected and "Нажми, чтобы исключить подземелье из поиска."
        or "Нажми, чтобы вернуть подземелье в поиск.", .75, .80, .88, true)
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

    local scrim = UI.Scrim(card, "BORDER", 0, .55)
    scrim:SetPoint("TOPLEFT", 1, -1)
    scrim:SetPoint("BOTTOMRIGHT", -1, 1)

    card.iconBorder = CreateFrame("Frame", nil, card, "BackdropTemplate")
    card.iconBorder:SetSize(42, 42)
    card.iconBorder:SetPoint("TOPLEFT", 10, -19)
    UI.Backdrop(card.iconBorder, { .02, .03, .04, 1 }, C.line)

    card.icon = card.iconBorder:CreateTexture(nil, "ARTWORK")
    card.icon:SetPoint("TOPLEFT", 1, -1)
    card.icon:SetPoint("BOTTOMRIGHT", -1, 1)

    card.iconLabel = UI.Text(card.iconBorder, "GameFontNormal", "", C.accentDim)
    card.iconLabel:SetPoint("CENTER", 0, 0)

    card.loot = UI.Text(card, "GameFontNormalSmall", "", C.faint)
    card.loot:SetPoint("BOTTOMLEFT", 10, 6)
    card.loot:SetWidth(42)
    card.loot:SetJustifyH("CENTER")

    card.title = UI.Text(card, "GameFontNormal", "", C.text)
    card.title:SetPoint("TOPLEFT", 62, -8)
    card.title:SetPoint("RIGHT", card, "RIGHT", -8, 0)
    card.title:SetJustifyH("LEFT")
    card.title:SetJustifyV("TOP")
    card.title:SetHeight(32)
    card.title:SetShadowColor(0, 0, 0, 1)
    card.title:SetShadowOffset(1, -1)

    card.best = UI.Text(card, "GameFontHighlightSmall", "")
    card.best:SetPoint("BOTTOMLEFT", 62, 7)
    card.best:SetPoint("RIGHT", card, "RIGHT", -10, 0)
    card.best:SetJustifyH("LEFT")
    card.best:SetWordWrap(false)
    card.best:SetShadowColor(0, 0, 0, 1)
    card.best:SetShadowOffset(1, -1)

    -- Полезные предметы прямо в карточке. Наведение показывает обычный
    -- предметный tooltip Blizzard и окно сравнения с надетой вещью.
    card.lootItems = {}
    for index = 1, 5 do
        local itemButton = CreateFrame("Button", nil, card, "BackdropTemplate")
        itemButton:SetSize(24, 24)
        itemButton:SetPoint("TOPLEFT", 62 + (index - 1) * 28, -34)
        UI.Backdrop(itemButton, { .025, .033, .044, .98 }, { .25, .32, .40, 1 })
        itemButton.icon = itemButton:CreateTexture(nil, "ARTWORK")
        itemButton.icon:SetPoint("TOPLEFT", 2, -2)
        itemButton.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        itemButton.gain = UI.Text(itemButton, "GameFontNormalSmall", "", C.green)
        itemButton.gain:SetPoint("BOTTOMRIGHT", 3, -2)
        itemButton.gain:SetShadowColor(0, 0, 0, 1)
        itemButton.gain:SetShadowOffset(1, -1)
        itemButton:SetScript("OnEnter", function(self)
            local item = self.item
            if not item then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if item.link then
                GameTooltip:SetHyperlink(item.link)
            else
                GameTooltip:SetText(item.name or "Предмет", 1, 1, 1)
            end
            GameTooltip:AddLine(("Надето: %d   Дроп: %d   Прирост: +%d")
                :format(item.equipped or 0, item.level or 0, item.gain or 0), .30, .92, .56)
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
        -- Пустой набор означает «все», но первый клик должен вести себя как
        -- Premade Groups Filter: оставить только нажатое подземелье.
        if SelectedCount(welcome) == 0 then
            selected[self.mapID] = true
        else
            selected[self.mapID] = not selected[self.mapID] or nil
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

GroupSearchUI.applicationStartedAt = GroupSearchUI.applicationStartedAt or {}

function GroupSearchUI:IsApplicationListed(searchResultID)
    if not searchResultID or type(C_LFGList.GetApplications) ~= "function" then return false end
    local ok, applications = pcall(C_LFGList.GetApplications)
    if not ok or type(applications) ~= "table" then return false end
    for _, resultID in ipairs(applications) do
        if resultID == searchResultID then return true end
    end
    return false
end

function GroupSearchUI:UpdateApplicationButton(button)
    local match = button and button.match
    local resultID = match and match.searchResultID
    if not resultID then return end

    local started = self.applicationStartedAt[resultID]
    local listed = self:IsApplicationListed(resultID)
    if listed and not started then
        started = GetTime()
        self.applicationStartedAt[resultID] = started
    elseif not listed and started and GetTime() - started > 3 then
        self.applicationStartedAt[resultID] = nil
        started = nil
    end

    if listed or started then
        -- CancelApplication разрешён только из hardware event. Не изображаем
        -- ложную автоматическую отмену таймером: кнопка доступна сразу и
        -- каждый её клик напрямую отменяет именно эту заявку.
        button:SetText("Отменить")
        button:Enable()
        button:SetAlpha(1)
        button.applicationActive = true
    else
        button:SetText("Заявка")
        button:Enable()
        button:SetAlpha(1)
        button.applicationActive = false
    end
end

local function CreateResultRow(parent, index)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(ROW_HEIGHT)
    row:EnableMouse(true)
    row.baseColor = index % 2 == 0 and C.rowAlt or C.row
    UI.Backdrop(row, row.baseColor, C.lineSoft)

    row.keyBox = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.keyBox:SetSize(COL.keyWidth, 30)
    row.keyBox:SetPoint("LEFT", COL.keyLeft, 0)
    UI.Backdrop(row.keyBox, { .035, .050, .065, 1 }, { .16, .30, .24, 1 })
    row.key = UI.Text(row.keyBox, "GameFontNormalLarge", "", C.green)
    row.key:SetPoint("CENTER", 0, 0)

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

    row.apply = UI.Button(row, "Заявка", COL.applyWidth, 26, true)
    row.apply:SetPoint("RIGHT", -COL.applyRight, 0)
    row.apply:SetScript("OnClick", function(self)
        local resultID = self.match and self.match.searchResultID
        if not resultID then return end
        if self.applicationActive or GroupSearchUI:IsApplicationListed(resultID) then
            if JP.AutoMatch:Cancel(self.match) then
                GroupSearchUI.applicationStartedAt[resultID] = nil
                self.applicationActive = false
                self:SetText("Отменено")
                C_Timer.After(.8, function()
                    if self.match and self.match.searchResultID == resultID then
                        GroupSearchUI:UpdateApplicationButton(self)
                    end
                end)
            end
        elseif JP.AutoMatch:Apply(self.match) then
            GroupSearchUI.applicationStartedAt[resultID] = GetTime()
            GroupSearchUI:UpdateApplicationButton(self)
        end
    end)
    row.apply:SetScript("OnUpdate", function(self, elapsed)
        self.updateElapsed = (self.updateElapsed or 0) + elapsed
        if self.updateElapsed < .25 then return end
        self.updateElapsed = 0
        if self.match then GroupSearchUI:UpdateApplicationButton(self) end
    end)

    local function Enter()
        row:SetBackdropColor(UI.Unpack(C.rowHover))
        ShowGroupTooltip(row)
    end
    local function Leave()
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

function GroupSearchUI:RenderRows(welcome)
    local matches = welcome.matches or {}
    local offset = welcome.offset or 0
    for index, row in ipairs(welcome.rows) do
        local match = matches[offset + index]
        if match and row.layoutVisible ~= false then
            local exactLevelKnown = match.keyLevel and not match.keyApprox
            local displayedLevel = (match.targetLevel and not exactLevelKnown) and match.targetLevel
                or match.keyLevel or match.targetLevel
            local raises = displayedLevel and displayedLevel > match.bestLevel
            -- «~» означает оценку по результату лидера: точный уровень ключа
            -- Blizzard в Midnight аддонам не отдаёт, заголовок приходит токеном.
            row.key:SetText(displayedLevel and (((match.keyApprox and not match.targetLevel) and "~" or "+") .. displayedLevel) or "—")
            if match.targetLevel and not exactLevelKnown then
                -- В режиме повышения показываем именно требуемый уровень
                -- выбранного данжа. Это цель, а не выдуманный уровень группы.
                row.key:SetTextColor(UI.Unpack(C.accent))
                row.keyBox:SetBackdropBorderColor(.10, .42, .58, 1)
            elseif match.keyLevel and match.keyApprox then
                row.key:SetTextColor(UI.Unpack(raises and C.green or C.amber))
                row.keyBox:SetBackdropBorderColor(.30, .26, .14, 1)
            elseif match.keyLevel then
                row.key:SetTextColor(UI.Unpack(raises and C.green or C.text))
                row.keyBox:SetBackdropBorderColor(raises and .16 or .18, raises and .44 or .22, raises and .32 or .28, 1)
            else
                row.key:SetTextColor(UI.Unpack(C.faint))
                row.keyBox:SetBackdropBorderColor(.16, .19, .24, 1)
            end

            row.dungeon:SetText(match.dungeon)

            -- Имена в LFG иногда догружаются позже основной карточки. Берём
            -- свежие данные перед каждой отрисовкой, а не держим первый nil.
            if match.searchResultID and UsableNumber(match.members) then
                local refreshed = {}
                for memberIndex = 1, match.members do
                    local member = C_LFGList.GetSearchResultPlayerInfo(match.searchResultID, memberIndex)
                    if member then
                        refreshed[#refreshed + 1] = {
                            name = SafeString(member.name),
                            classFilename = member.classFilename,
                            assignedRole = member.assignedRole,
                            isLeader = member.isLeader or memberIndex == 1,
                        }
                    end
                end
                if #refreshed > 0 then match.memberInfo = refreshed end
            end

            local parts, hidden = {}, 0
            for _, member in ipairs(type(match.memberInfo) == "table" and match.memberInfo or {}) do
                local displayName = member.name
                if not displayName and member.isLeader and match.leaderName then
                    displayName = match.leaderName:match("^([^%-]+)")
                end
                if displayName then
                    parts[#parts + 1] = ("%s |c%s%s|r"):format(
                        UI.ClassIcon(member.classFilename, 16),
                        UI.ClassColorCode(member.classFilename),
                        displayName)
                else
                    hidden = hidden + 1
                end
            end
            if hidden > 0 then parts[#parts + 1] = ("|cff657181+%d скрыт.|r"):format(hidden) end
            local names = table.concat(parts, "  ")
            -- Заголовок группы почти всегда просто «+15» — уровень уже стоит
            -- в отдельной колонке, поэтому убираем его из описания.
            local comment = match.title
            if comment and match.keyLevel then
                local stripped = comment:gsub("^%s*[%+＋]?%s*%d%d?%s*", "")
                comment = stripped ~= "" and stripped or nil
            end
            if comment and names ~= "" then
                row.detail:SetText(("|cffa9b4c2%s|r   |cff4c545e—|r   %s"):format(comment, names))
            else
                row.detail:SetText(comment and ("|cffa9b4c2" .. comment .. "|r") or names)
            end

            row.roles:SetText(("%s  %s  %s"):format(
                match.hasTank and UI.RoleIcon("TANK", 16) or "|cff3d434c—|r",
                match.hasHealer and UI.RoleIcon("HEALER", 16) or "|cff3d434c—|r",
                match.hasBloodlust and "|cff28b8f5БЛ|r" or "|cff3d434cБЛ|r"))

            local partyAverage = match.partyScoreAverage or match.score or 0
            row.score:SetText(("|cff%s[%d]|r"):format(PartyRatingColorCode(partyAverage), math.floor(partyAverage + .5)))
            row.leader:SetText(match.leaderName or "—")
            row.age:SetText(match.age and SecondsToTime(match.age, false, false, 1) or "—")

            row.dungeonName = match.dungeon
            row.searchResultID = match.searchResultID
            row.match = match
            row.apply.match = match
            GroupSearchUI:UpdateApplicationButton(row.apply)
            row:Show()
        else
            row.searchResultID = nil
            row.match = nil
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

    local title = UI.Text(panel, "GameFontNormalLarge", "ФИЛЬТРЫ", C.accent)
    title:SetPoint("TOPLEFT", 14, -14)

    local partyLabel = UI.Text(panel, "GameFontNormalSmall", "ТВОЯ ГРУППА", C.faint)
    partyLabel:SetPoint("TOPLEFT", 14, -44)
    welcome.partyComposition = UI.Text(panel, "GameFontHighlight", "")
    welcome.partyComposition:SetPoint("TOPLEFT", 14, -60)
    welcome.partyComposition:SetPoint("TOPRIGHT", -14, -60)
    welcome.partyComposition:SetJustifyH("LEFT")

    -- Вертикальный ритм подобран так, чтобы весь столбец помещался при
    -- минимальной высоте окна и не наезжал на сводку и кнопки внизу.
    local y = -92
    SectionLabel(panel, "КЛЮЧ", y); y = y - 20
    welcome.scoreUpgrade = UI.CheckBox(panel, "Только повышающие рейтинг", welcome.groupFilters.scoreUpgrade == true)
    welcome.scoreUpgrade:SetPoint("TOPLEFT", 14, y)
    welcome.scoreUpgrade:SetWidth(FILTERS_WIDTH - 28)
    welcome.scoreUpgrade:SetScript("OnEnter", function(self)
        UI.Tooltip(self, "Только повышающие рейтинг",
            "Цель — следующий уровень: при твоём рекорде +10 нужен +11 этого подземелья.",
            "Midnight скрывает уровень объявления от Lua. Если он защищён, MythicBoost отберёт нужное подземелье и покажет целевой уровень; фактический +ключ проверь в названии группы. Рекорд после прохождения обновляется локально.")
    end)
    welcome.scoreUpgrade:SetScript("OnLeave", GameTooltip_Hide)
    y = y - 28
    NumberField(panel, welcome, "Ключ от", "keyMin", "", y); y = y - 24
    NumberField(panel, welcome, "Ключ до", "keyMax", "", y); y = y - 30

    SectionLabel(panel, "ЛИДЕР", y); y = y - 22
    NumberField(panel, welcome, "Рейтинг от", "scoreMin", 0, y); y = y - 24
    NumberField(panel, welcome, "Рейтинг до", "scoreMax", "", y); y = y - 24
    -- Счётчик ключей лидера берётся только из Raider.IO. Без него любой порог
    -- выше нуля отсекает вообще все группы, поэтому не ставим эту ловушку по
    -- умолчанию.
    local defaultRuns = MythicBoostDB.minimumKeystoneRuns or 20
    if not (RaiderIO and type(RaiderIO.GetProfile) == "function") then defaultRuns = 0 end
    NumberField(panel, welcome, "Ключей +10 от", "runsMin", defaultRuns, y); y = y - 30

    SectionLabel(panel, "ОТБОР", y); y = y - 22
    welcome.tank = UI.CheckBox(panel, "Танк уже в группе", MythicBoostDB.autoMatch.requireTank ~= false,
        function(checked) MythicBoostDB.autoMatch.requireTank = checked; welcome:Refresh() end)
    welcome.tank:SetPoint("TOPLEFT", 14, y); welcome.tank:SetWidth(FILTERS_WIDTH - 28); y = y - 23
    welcome.bloodlust = UI.CheckBox(panel, "Нужен Bloodlust", MythicBoostDB.autoMatch.requireBloodlust == true,
        function(checked) MythicBoostDB.autoMatch.requireBloodlust = checked; welcome:Refresh() end)
    welcome.bloodlust:SetPoint("TOPLEFT", 14, y); welcome.bloodlust:SetWidth(FILTERS_WIDTH - 28); y = y - 23
    welcome.notDeclined = UI.CheckBox(panel, "Скрыть отказавших", welcome.groupFilters.notDeclined,
        function(checked) welcome.groupFilters.notDeclined = checked; welcome:Refresh() end)
    welcome.notDeclined:SetPoint("TOPLEFT", 14, y); welcome.notDeclined:SetWidth(FILTERS_WIDTH - 28)

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
    summary:SetHeight(44)
    welcome.filterSummary = summary
    welcome.ownKey = UI.Text(summary, "GameFontHighlightSmall", "", C.text)
    welcome.ownKey:SetPoint("TOPLEFT", 10, -8)
    welcome.ownKey:SetPoint("TOPRIGHT", -10, -8)
    welcome.ownKey:SetJustifyH("LEFT")
    welcome.ownKey:SetWordWrap(false)
    welcome.ownScore = UI.Text(summary, "GameFontHighlightSmall", "", C.muted)
    welcome.ownScore:SetPoint("BOTTOMLEFT", 10, 8)
    welcome.ownScore:SetPoint("BOTTOMRIGHT", -10, 8)
    welcome.ownScore:SetJustifyH("LEFT")
    welcome.ownScore:SetWordWrap(false)

    local reset = UI.Button(panel, "Сбросить", 100, 26)
    reset:SetPoint("BOTTOMLEFT", 12, 12)
    reset:SetScript("OnClick", function()
        local defaults = { keyMin = "", keyMax = "", scoreMin = 0, scoreMax = "", runsMin = 20 }
        for key, value in pairs(defaults) do
            welcome.groupFilters[key] = value
            if welcome.filterFields[key] then welcome.filterFields[key]:SetText(tostring(value)) end
        end
        wipe(welcome.groupFilters.dungeons)
        welcome.groupFilters.notDeclined = true
        welcome.notDeclined:SetChecked(true)
        welcome.scoreUpgrade:SetChecked(false)
        UpdateUpgradeMode(false)
        GroupSearchUI:RefreshDungeonCards(welcome)
        welcome:Refresh()
    end)

    local weak = UI.Button(panel, "Слабые 3", 100, 26)
    weak:SetPoint("BOTTOMRIGHT", -12, 12)
    weak:HookScript("OnEnter", function(self)
        UI.Tooltip(self, "Слабые 3", "Оставить три подземелья с самым низким личным рекордом — самый быстрый прирост общего рейтинга.")
    end)
    weak:HookScript("OnLeave", GameTooltip_Hide)
    weak:SetScript("OnClick", function()
        local ordered = {}
        for _, data in ipairs(welcome.dungeonData or {}) do ordered[#ordered + 1] = data end
        table.sort(ordered, function(a, b)
            return JP:GetBestLevel(a.mapID, a.run and a.run.level or 0) < JP:GetBestLevel(b.mapID, b.run and b.run.level or 0)
        end)
        wipe(welcome.groupFilters.dungeons)
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

    local title = UI.Text(cards, "GameFontNormalSmall", "ПОДЗЕМЕЛЬЯ СЕЗОНА", C.muted)
    title:SetPoint("TOPLEFT", 12, -11)

    welcome.selectAll = UI.Button(cards, "Все", 62, 21)
    welcome.selectAll:SetPoint("TOPRIGHT", -10, -8)
    welcome.selectAll:HookScript("OnEnter", function(self)
        UI.Tooltip(self, "Все подземелья", "Снять ограничение и искать группы во все восемь подземелий сезона.")
    end)
    welcome.selectAll:HookScript("OnLeave", GameTooltip_Hide)
    welcome.selectAll:SetScript("OnClick", function()
        wipe(welcome.groupFilters.dungeons)
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
    local heading = UI.Text(results, "GameFontNormalSmall", "ПОДХОДЯЩИЕ ГРУППЫ", C.muted)
    heading:SetPoint("TOPLEFT", 12, -12)

    welcome.resultsCount = UI.Text(results, "GameFontHighlightSmall", "", C.accent)
    welcome.resultsCount:SetPoint("LEFT", heading, "RIGHT", 10, 0)

    welcome.scan = UI.Button(results, "Обновить", 118, 24, true)
    welcome.scan:SetPoint("TOPRIGHT", -12, -8)
    welcome.scan:SetScript("OnClick", function() GroupSearchUI:RequestBlizzardSearch(welcome) end)
    welcome.scan:HookScript("OnEnter", function(self)
        UI.Tooltip(self, "Обновить", "Запросить у Blizzard свежий список групп и отфильтровать его по твоим настройкам.")
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
    local keyLabel = UI.Text(results, "GameFontNormalSmall", "КЛЮЧ", C.faint)
    keyLabel:SetPoint("TOPLEFT", COL.keyLeft, -46)
    keyLabel:SetWidth(COL.keyWidth)
    keyLabel:SetJustifyH("CENTER")
    local groupLabel = UI.Text(results, "GameFontNormalSmall", "ГРУППА / ПОДЗЕМЕЛЬЕ", C.faint)
    groupLabel:SetPoint("TOPLEFT", COL.textLeft, -46)
    groupLabel:SetJustifyH("LEFT")
    Header("СОСТАВ", COL.rolesWidth, COL.rolesRight)
    Header("СРЕДНИЙ RIO", COL.leaderWidth, COL.leaderRight)
    Header("ВОЗРАСТ", COL.ageWidth, COL.ageRight)

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
    if welcome.partyComposition then
        local units = { "player" }
        if IsInGroup and IsInGroup() and not (IsInRaid and IsInRaid()) then
            for index = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. index end
        end
        local roles = { TANK = 0, HEALER = 0, DAMAGER = 0, NONE = 0 }
        for _, unit in ipairs(units) do
            if UnitExists(unit) then
                local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
                if (not role or role == "NONE") and unit == "player" then
                    local spec = GetSpecialization and GetSpecialization()
                    role = spec and GetSpecializationRole and GetSpecializationRole(spec) or role
                end
                if role ~= "TANK" and role ~= "HEALER" and role ~= "DAMAGER" then role = "NONE" end
                roles[role] = roles[role] + 1
            end
        end
        local parts = {}
        for _, role in ipairs({ "TANK", "HEALER", "DAMAGER", "NONE" }) do
            for _ = 1, roles[role] do parts[#parts + 1] = UI.RoleIcon(role, 22) end
        end
        for _ = #parts + 1, 5 do parts[#parts + 1] = "|cff3d4652○|r" end
        welcome.partyComposition:SetText(#parts > 0 and table.concat(parts, "   ") or "|cff5b6470нет данных|r")
    end

    if welcome.ownKey then
        local mapID = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID and C_MythicPlus.GetOwnedKeystoneChallengeMapID()
        local level = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel()
        local mapName = mapID and SafeString(C_ChallengeMode.GetMapUIInfo(mapID))
        if mapName and UsableNumber(level) then
            welcome.ownKey:SetText(("|cff8a939fтвой ключ|r  |cff43d17a+%d|r  %s"):format(level, mapName))
        else
            welcome.ownKey:SetText("|cff8a939fтвой ключ|r  |cff5b6470нет|r")
        end
    end

    if welcome.ownScore then
        local score = C_ChallengeMode.GetOverallDungeonScore and C_ChallengeMode.GetOverallDungeonScore() or 0
        local _, equipped = GetAverageItemLevel()
        welcome.ownScore:SetText(("|cff8a939fрейтинг|r  |cffffb93d%d|r     |cff8a939filvl|r  |cffd4dbe4%.0f|r")
            :format(math.floor(UsableNumber(score) and score or 0), UsableNumber(equipped) and equipped or 0))
    end
end

---------------------------------------------------------------------------
-- Сборка
---------------------------------------------------------------------------

function GroupSearchUI:Build(welcome, body)
    welcome.groupFilters = MythicBoostDB.groupFilters
    welcome.groupFilters.dungeons = welcome.groupFilters.dungeons or {}
    welcome.groupFilters.roleFit = true
    if welcome.groupFilters.notDeclined == nil then welcome.groupFilters.notDeclined = true end
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
        elseif (event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" or event == "LFG_LIST_UPDATE_SEARCH_RESULTS")
            and GroupSearchUI.searchPending then
            GroupSearchUI:QueueSearchResults(welcome)
        elseif event == "LFG_LIST_SEARCH_FAILED" and GroupSearchUI.searchPending then
            FinishBlizzardSearch(welcome, GroupSearchUI.searchToken, "Поиск Blizzard завершился ошибкой.")
        else
            JP:RequestRefresh()
        end
    end)

    function welcome:GetGroupFilters()
        self.groupFilters.roleFit = true
        -- У выбранных подземелий разные следующие уровни. Один общий target
        -- оставлял только данжи с минимальной целью и скрывал остальные.
        self.groupFilters.searchTargetLevel = nil
        return self.groupFilters
    end

    self:RefreshDungeonCards(welcome)
    self:RefreshOwnComposition(welcome)
    self:Layout(welcome)
end

JP.GroupSearchUI = GroupSearchUI
