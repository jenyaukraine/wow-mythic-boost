local _, JP = ...

---------------------------------------------------------------------------
-- Единый слой доступа к игровому API
--
-- Midnight помечает часть значений как secret. Такое значение можно
-- использовать в условии, но нельзя сравнивать: `value == 1` бросает
-- «attempt to compare a secret value» и роняет весь обработчик. Часть
-- вызовов вдобавок бросает исключение из C, и его ловит только pcall.
--
-- До этого файла защита была скопирована двадцать одним куском по
-- тринадцати модулям, и копии успели разойтись: SafeString в одном месте
-- пропускала пустую строку, а в четырёх других резала. Ровно эта разница
-- дала «, Хлам» с бессмысленным уровнем предмета в окне добычи — пустая
-- строка в Lua истинна. Пока проверка живёт в тринадцати местах, каждое
-- исправление приходится разносить руками, а каждый новый вызов API —
-- это шанс забыть.
--
-- Модули берут отсюда локальные ссылки и зовут их прежними именами:
--     local UsableNumber, SafeString = JP.API.Number, JP.API.String
-- Так место вызова не меняется, а определение остаётся одно.
---------------------------------------------------------------------------

-- На клиентах без secret-значений подставляем заглушку, чтобы модули могли
-- звать проверку без условий. Core.lua делает то же самое раньше нас, но
-- этот файл обязан быть самостоятельным: он грузится и в тестах, и первым.
if type(issecretvalue) ~= "function" then
    issecretvalue = function() return false end
end

local API = {}
JP.API = API

-- Число, которое можно сравнивать и считать.
function API.Number(value)
    return type(value) == "number" and not issecretvalue(value)
end

-- Непустая строка. Пустую отбрасываем намеренно: в Lua она истинна, и
-- `_G[equipLoc] or nil` на INVTYPE_NON_EQUIP давал видимость значения.
function API.String(value)
    if type(value) ~= "string" or issecretvalue(value) or value == "" then return nil end
    return value
end

function API.Boolean(value)
    return type(value) == "boolean" and not issecretvalue(value) and value or false
end

function API.Table(value)
    return type(value) == "table" and not issecretvalue(value) and value or nil
end

-- Любое значение с запасным вариантом: то, что приходит из GetLootSlotInfo
-- и родственных вызовов, где поле может быть и числом, и строкой.
function API.Value(value, fallback)
    if value == nil or issecretvalue(value) then return fallback end
    return value
end

-- Число или ноль. Отдельно от Number, потому что почти всегда результат
-- сразу идёт в арифметику или в границу цикла.
function API.Count(value)
    return API.Number(value) and value or 0
end

-- Вызов, который может бросить исключение из C. Возвращает результаты
-- как есть, при отказе — ничего.
function API.Call(fn, ...)
    if type(fn) ~= "function" then return end
    local values = { pcall(fn, ...) }
    if not table.remove(values, 1) then return end
    return unpack(values)
end

-- Аура по индексу. Под taint GetAuraDataByIndex бросает из C, поэтому
-- отличаем «ауру прочитать нельзя» от «ауры нет»: первое означает, что
-- перебор надо прекратить, второе — что он просто кончился.
function API.Aura(unit, index, filter)
    if not C_UnitAuras or type(C_UnitAuras.GetAuraDataByIndex) ~= "function" then return nil, true end
    local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
    if not ok then return nil, true end
    return data, false
end

-- Кэш, ключом которого служит чужой объект, обязан быть слабым по ключу:
-- иначе он держит этот объект живым вечно. Живёт здесь, а не в UI, потому
-- что это свойство хранения, а не оформления.
function API.WeakKeys()
    return setmetatable({}, { __mode = "k" })
end
