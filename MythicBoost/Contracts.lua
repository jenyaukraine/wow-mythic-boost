local _, JP = ...

-- Единственная точка владения техническими ограничениями аддона. Модули не
-- должны копировать эти числа: при изменении лимита меняется только контракт.
JP.Contracts = {
    VERSION = 1,
    DATABASE_VERSION = 6,
}

JP.Limits = {
    LOG_ENTRIES = 200,
    SCANNED_PLAYERS = 300,
    SCANNED_PLAYER_TTL = 30 * 24 * 60 * 60,
    PROFILE_CACHE_ENTRIES = 500,
    HISTORY_TEAMMATES = 200,
    HISTORY_RUNS = 30,
    ACTIVE_APPLICATIONS = 5,
}

-- Midnight помечает часть данных как secret. На клиентах без этого API
-- заглушка сохраняет один и тот же контракт для тестов и старых клиентов.
if type(issecretvalue) ~= "function" then
    issecretvalue = function() return false end
end

function JP.IsSecret(value)
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret == true
end

function JP.UsableNumber(value)
    return type(value) == "number" and not JP.IsSecret(value)
end

function JP.SafeNumber(value)
    return JP.UsableNumber(value) and value or nil
end

function JP.SafeString(value)
    if type(value) ~= "string" or JP.IsSecret(value) or value == "" then return nil end
    return value
end

function JP.SafeStringOrEmpty(value)
    return type(value) == "string" and not JP.IsSecret(value) and value or nil
end

function JP.UsableString(value)
    return JP.SafeString(value) ~= nil
end

function JP.SafeOptionalBoolean(value)
    if type(value) == "boolean" and not JP.IsSecret(value) then return value end
end

function JP.SafeBoolean(value)
    return JP.SafeOptionalBoolean(value) == true
end

function JP.SafeTable(value)
    return type(value) == "table" and not JP.IsSecret(value) and value or nil
end

local API = {}
JP.API = API

local function Call(owner, methodName, ...)
    local method = type(owner) == "table" and owner[methodName]
    if type(method) ~= "function" then return false end
    return pcall(method, ...)
end

-- Нормализует актуальную структуру Midnight и старый tuple API. Только этот
-- файл имеет право знать позиции возврата GetCompletionInfo().
function API.GetChallengeCompletion()
    local api = C_ChallengeMode
    if not api then return nil end

    local function FromTable(info)
        info = JP.SafeTable(info)
        if not info then return nil end
        return {
            mapID = JP.SafeNumber(info.mapChallengeModeID or info.mapID),
            level = JP.SafeNumber(info.level),
            duration = JP.SafeNumber(info.time or info.duration),
            onTime = JP.SafeOptionalBoolean(info.onTime),
            upgrades = JP.SafeNumber(info.keystoneUpgradeLevels) or 0,
            practiceRun = JP.SafeBoolean(info.practiceRun),
            members = JP.SafeTable(info.members),
        }
    end

    local ok, info = Call(api, "GetChallengeCompletionInfo")
    local normalized = ok and FromTable(info)
    if normalized then return normalized end

    local mapID, level, duration, onTime, upgrades, practiceRun
    ok, mapID, level, duration, onTime, upgrades, practiceRun = Call(api, "GetCompletionInfo")
    if not ok then return nil end
    if type(mapID) == "table" then return FromTable(mapID) end
    return {
        mapID = JP.SafeNumber(mapID),
        level = JP.SafeNumber(level),
        duration = JP.SafeNumber(duration),
        onTime = JP.SafeOptionalBoolean(onTime),
        upgrades = JP.SafeNumber(upgrades) or 0,
        practiceRun = JP.SafeBoolean(practiceRun),
    }
end

-- Первый результат GetActiveKeystoneInfo() — уровень, второй — аффиксы.
-- Возвращаем именованные поля, чтобы их невозможно было случайно переставить.
function API.GetActiveChallenge()
    local api = C_ChallengeMode
    if not api then return nil end
    local _, mapID = Call(api, "GetActiveChallengeMapID")
    local _, level = Call(api, "GetActiveKeystoneInfo")
    local _, startedAt = Call(api, "GetStartTime")
    local _, active = Call(api, "IsChallengeModeActive")
    return {
        mapID = JP.SafeNumber(mapID),
        level = JP.SafeNumber(level),
        startedAt = JP.SafeNumber(startedAt),
        active = JP.SafeOptionalBoolean(active),
    }
end

function API.GetChallengeMap(mapID)
    if not JP.UsableNumber(mapID) then return nil end
    local ok, name, id, timeLimit, icon, background, instanceMapID =
        Call(C_ChallengeMode, "GetMapUIInfo", mapID)
    if not ok then return nil end
    return {
        name = JP.SafeString(name),
        mapID = JP.SafeNumber(id) or mapID,
        timeLimit = JP.SafeNumber(timeLimit),
        icon = (JP.UsableNumber(icon) or JP.UsableString(icon)) and icon or nil,
        background = (JP.UsableNumber(background) or JP.UsableString(background)) and background or nil,
        instanceMapID = JP.SafeNumber(instanceMapID),
    }
end

function API.GetChallengeMapIDs()
    local ok, source = Call(C_ChallengeMode, "GetMapTable")
    source = ok and JP.SafeTable(source) or nil
    local result = {}
    for _, mapID in ipairs(source or {}) do
        if JP.UsableNumber(mapID) then result[#result + 1] = mapID end
    end
    return result
end

function API.GetChallengeDeaths()
    local ok, count, timeLost = Call(C_ChallengeMode, "GetDeathCount")
    if not ok then return nil end
    return { count = JP.SafeNumber(count) or 0, timeLost = JP.SafeNumber(timeLost) or 0 }
end

local DECLINED = {
    declined = true,
    declined_full = true,
    declined_delisted = true,
}

-- Возвращает объект, а не пять позиционных значений. Это сохраняет различие
-- между pendingStatus=nil и строкой "none" и не теряет приглашения.
function API.GetApplicationState(searchResultID)
    local state = {
        status = "none", pendingStatus = nil, readable = false,
        pending = false, cancellable = false, active = false, declined = false,
    }
    if not JP.UsableNumber(searchResultID) then return state end
    local ok, _, status, pendingStatus, duration =
        Call(C_LFGList, "GetApplicationInfo", searchResultID)
    if not ok or JP.IsSecret(status) or JP.IsSecret(pendingStatus) then return state end

    state.readable = true
    state.status = JP.SafeStringOrEmpty(status) or "none"
    state.pendingStatus = JP.SafeStringOrEmpty(pendingStatus)
    state.pending = state.pendingStatus ~= nil and state.pendingStatus ~= "none"
    state.cancellable = state.status == "applied" and not state.pending
    state.active = state.status == "applied" or state.status == "invited" or state.pending
    state.declined = DECLINED[state.status] == true or DECLINED[state.pendingStatus] == true
    state.duration = JP.SafeNumber(duration)
    return state
end

function API.GetApplicationIDs()
    local ok, applications = Call(C_LFGList, "GetApplications")
    return ok and JP.SafeTable(applications) or nil
end

-- Совместимый фасад для старых модулей и сторонних обращений. Новый код
-- использует JP.API.GetChallengeCompletion() напрямую.
function JP:GetChallengeCompletionData()
    return API.GetChallengeCompletion()
end
