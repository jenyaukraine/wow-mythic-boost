local _, JP = ...
local L = JP.L
local SmartClick = {}
local UI, C = JP.UI, JP.UI.colors

---------------------------------------------------------------------------
-- Умный клик: макрос MBSmartClick, который ведёт аддон
--
-- Две галочки в настройках:
--   1. клик даёт недостающий бафф;
--   2. клик поднимает мёртвого — в бою боевым воскрешением, вне боя обычным.
--
-- Модуль НЕ трогает атрибуты кнопок, и это главное решение здесь.
--
-- UnitFrames регистрирует свои кнопки в ClickCastFrames, то есть сам просит
-- DandersFrames или Clique ими управлять. А DandersFrames
-- (ClickCasting/Bindings.lua) перебирает ВСЕ сочетания модификаторов — alt,
-- ctrl, shift, meta и их пары с тройками — и обнуляет там type/spell/macrotext
-- на своих кнопках. Свободного слота не остаётся ни одного: что бы мы ни
-- записали, ближайший его проход это сотрёт. Проверено тремя попытками.
--
-- Поэтому работаем не против клик-каста, а через него: держим готовый макрос,
-- который игрок один раз привязывает в его настройках. Выбор заклинания по
-- классу и состоянию боя остаётся нашим, владение кликом — его.
--
-- Условники [combat] и [dead] вычисляет сама игра в момент нажатия, поэтому
-- макрос достаточно переписать при смене специализации, а не каждый бой.
-- Кастовать из Lua всё равно нельзя: CastSpellByName и родня защищены.
---------------------------------------------------------------------------

-- Идентификаторы, а не локализованные названия: имена заклинаний в макросе
-- обязаны совпадать с языком клиента, и хардкод "Возрождение" сломался бы на
-- любой другой локали. ID стабильны, имя достаём из API.
local BATTLE_RES = {
    DRUID = 20484,       -- Возрождение
    DEATHKNIGHT = 61999, -- Воскрешение союзника
    PALADIN = 391054,    -- Заступничество
    WARLOCK = 20707,     -- Камень души
    EVOKER = 361227,     -- Возврат
}

local NORMAL_RES = {
    DRUID = 50769,       -- Оживление
    PRIEST = 2006,       -- Воскрешение
    PALADIN = 7328,      -- Искупление
    SHAMAN = 2008,       -- Дух предков
    MONK = 115178,       -- Реанимация
    EVOKER = 361227,
}

-- Классы, у которых есть настоящий групповой бафф — тот, что накладывается
-- одним кастом и виден аурой на каждом участнике.
--
-- Паладина здесь намеренно нет. Его ауры (Аура преданности, Аура усердия,
-- Аура сосредоточения) — переключатели на самом паладине, а не заклинание,
-- которым добаффывают отставших. В модели «кому не досталось» они дали бы
-- вечный список из всей группы и кнопку, которая ничего не исправляет.
local BUFF = {
    DRUID = 1126,        -- Знак дикой природы
    PRIEST = 21562,      -- Слово силы: Стойкость
    MAGE = 1459,         -- Чародейский интеллект
    WARRIOR = 6673,      -- Боевой крик
    SHAMAN = 462854,     -- Небесная ярость
    EVOKER = 381732,     -- Благословение Бронзы
}

-- Заклинание, которым баффают, и аура, которая ложится на союзника, — разные
-- вещи. У Благословения Бронзы вариант ауры зависит от класса цели, у
-- Интеллекта и Знака дикой природы есть вторая версия. Сравнение по одному ID
-- считало бы забаффанных незабаффанными, и кнопка горела бы всегда.
local BUFF_AURAS = {
    [1126]   = { 1126, 432661 },
    [21562]  = { 21562 },
    [1459]   = { 1459, 432778 },
    [6673]   = { 6673 },
    [462854] = { 462854 },
    [381732] = {
        381732, 381741, 381746, 381748, 381749, 381750, 381751,
        381752, 381753, 381754, 381756, 381757, 381758,
    },
}

local BUFF_AURA_SET = {}
for buffID, list in pairs(BUFF_AURAS) do
    local set = {}
    for _, id in ipairs(list) do set[id] = true end
    BUFF_AURA_SET[buffID] = set
end

function SmartClick:GetSettings()
    if type(MythicBoostDB) ~= "table" then return nil end
    MythicBoostDB.smartClick = type(MythicBoostDB.smartClick) == "table" and MythicBoostDB.smartClick or {}
    local settings = MythicBoostDB.smartClick
    if settings.buff == nil then settings.buff = false end
    if settings.res == nil then settings.res = false end
    return settings
end

-- Правда ли значение, которое может прийти защищённым. Защищённый boolean
-- нельзя сравнивать (`== true` бросает ошибку), поэтому сначала проверяем сам
-- факт защищённости, и только потом сравниваем.
local function IsTrue(value)
    return not issecretvalue(value) and value == true
end

-- Ауры в Midnight из tainted-кода не просто приходят защищёнными — сам вызов
-- GetAuraDataByIndex бросает ошибку прямо из C. Проверить это заранее нечем,
-- поэтому единственный рабочий способ — pcall. Второе значение говорит, что
-- ауры закрыты вообще, а не что их просто не осталось.
local function SafeAura(unit, index, filter)
    if not C_UnitAuras or type(C_UnitAuras.GetAuraDataByIndex) ~= "function" then return nil, true end
    local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
    if not ok then return nil, true end
    return data, false
end

-- Каст всегда на себя. Все эти баффы групповые — один каст закрывает всех в
-- радиусе, и цель для них роли не играет. Без [@player] заклинание уходит в
-- текущую цель, и стоит выбрать дальнего или враждебного — игра отвечает «Вне
-- зоны действия», хотя группу забаффать было можно.
local function BuffMacro(name)
    return ("/cast [@player] %s"):format(name)
end

-- Имя нужно ровно то, что понимает макрос. Заклинание, которого игрок не
-- знает, в макрос не попадает: иначе клик молча ничего не делает, и человек
-- считает, что сломана галочка, а не отсутствует способность.
local function SpellName(spellID)
    if not spellID then return end
    local known = false
    if type(IsPlayerSpell) == "function" then
        local ok, result = pcall(IsPlayerSpell, spellID)
        known = ok and IsTrue(result)
    end
    if not known then return end
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
            return info.name
        end
    end
    return nil
end

-- Собираем одну строку /cast с условниками. Порядок важен: игра берёт первый
-- подошедший вариант, поэтому мёртвые проверяются раньше живых, а бой раньше
-- «вне боя» — иначе обычное воскрешение перехватило бы боевую ситуацию.
function SmartClick:BuildMacro(unit)
    local settings = self:GetSettings()
    if not settings then return nil end
    local _, class = UnitClass("player")
    if type(class) ~= "string" then return nil end

    local clauses = {}
    if settings.res then
        local battle = SpellName(BATTLE_RES[class])
        local normal = SpellName(NORMAL_RES[class])
        -- В бою годится только боевое воскрешение. Если его у класса нет,
        -- клаузу не пишем вовсе: обычный рес в бою всё равно не сработает, а
        -- в макросе он бы перехватил условие и клик выглядел бы сломанным.
        if battle then
            clauses[#clauses + 1] = ("[@%s,help,dead,combat] %s"):format(unit, battle)
        end
        if normal then
            clauses[#clauses + 1] = ("[@%s,help,dead,nocombat] %s"):format(unit, normal)
        elseif battle then
            clauses[#clauses + 1] = ("[@%s,help,dead] %s"):format(unit, battle)
        end
    end
    if settings.buff then
        local buff = SpellName(BUFF[class])
        if buff then
            clauses[#clauses + 1] = ("[@%s,help,nodead] %s"):format(unit, buff)
        end
    end
    if #clauses == 0 then return nil end
    return "/cast " .. table.concat(clauses, "; ")
end

local MACRO_NAME = "MBSmartClick"
local MACRO_ICON = "INV_Misc_QuestionMark"

-- Пишем макрос в общий список персонажа. CreateMacro/EditMacro защищены от
-- вызова в бою, поэтому вся работа откладывается до выхода из него.
function SmartClick:Apply()
    if InCombatLockdown() then
        self.pending = true
        return
    end
    self.pending = false
    if type(GetMacroIndexByName) ~= "function" then return end

    -- @mouseover, а не @unit: макрос один на все фреймы, и цель определяется
    -- тем, над чем курсор в момент клика. Клик-каст DandersFrames наводит
    -- mouseover на фрейм сам, поэтому этого достаточно и для его кнопок.
    local macro = self:BuildMacro("mouseover")
    local index = GetMacroIndexByName(MACRO_NAME)

    if not macro then
        -- Обе галочки сняты: макрос убираем, чтобы не оставлять в списке
        -- пустышку, которая ничего не делает.
        if index and index > 0 and type(DeleteMacro) == "function" then
            pcall(DeleteMacro, index)
        end
        return
    end

    local body = "#showtooltip\n" .. macro
    local ok, err
    if index and index > 0 then
        ok, err = pcall(EditMacro, index, MACRO_NAME, MACRO_ICON, body)
    else
        ok, err = pcall(CreateMacro, MACRO_NAME, MACRO_ICON, body, false)
    end

    -- Результат pcall ОБЯЗАТЕЛЬНО проверяем. Прежде он игнорировался, и если
    -- CreateMacro не проходил — кончились слоты, не понравилась иконка — то
    -- не происходило ровным счётом ничего и никто об этом не сообщал.
    if not ok then
        JP:Print(L("|cffff6b6bНе удалось создать макрос ") .. MACRO_NAME .. "|r: " .. tostring(err))
        self.macroBody = nil
        return
    end

    -- Проверяем ФАКТ, а не возврат: CreateMacro может отработать без ошибки и
    -- всё равно не создать запись, если общий список макросов переполнен.
    if (GetMacroIndexByName(MACRO_NAME) or 0) <= 0 then
        JP:Print(L("|cffff6b6bМакрос ") .. MACRO_NAME .. L(" не появился|r — вероятно, кончились слоты макросов."))
        self.macroBody = nil
        return
    end
    self.macroBody = body
end


function SmartClick:SetOption(key, value)
    local settings = self:GetSettings()
    if not settings then return end
    settings[key] = value and true or false
    self:Apply()
    self:RefreshBuffButton()
    if InCombatLockdown() then
        JP:Print(L("Настройка применится после боя: менять клик защищённой кнопки в бою нельзя."))
        return
    end
    -- Говорим вслух, что получилось. Молчаливая галочка неотличима от
    -- сломанной: если у класса нет нужного заклинания или игрок его ещё не
    -- выучил, клауза в макрос не попадает — и без этой строки человек видит
    -- только то, что клик ничего не делает.
    if not settings.buff and not settings.res then
        JP:Print(L("Умный клик выключен, макрос MBSmartClick удалён."))
        return
    end
    local sample = self:BuildMacro("mouseover")
    if sample then
        JP:Print(L("Макрос MBSmartClick готов: ") .. sample:gsub("^/cast ", ""))
        -- Без этой строки человек включает галочку и ждёт, что заработает
        -- само. Оно не заработает: макрос создан, но никуда не привязан.
        JP:Print(L("|cffffb93dОсталось привязать его|r — перетащи макрос ") ..
            L("|cff28b8f5MBSmartClick|r на панель способностей, либо укажи его в клик-касте DandersFrames."))
    else
        JP:Print(L("Умный клик включён, но подходящих заклинаний не найдено — ") .. self:Describe())
    end
end

-- Описание для подсказки: показывает ровно те заклинания, которые реально
-- попадут в макрос у этого персонажа.
function SmartClick:Describe()
    local _, class = UnitClass("player")
    if type(class) ~= "string" then return L("класс не определён") end
    local parts = {}
    local battle, normal, buff = SpellName(BATTLE_RES[class]), SpellName(NORMAL_RES[class]), SpellName(BUFF[class])
    parts[#parts + 1] = L("в бою: ") .. (battle or L("нет боевого воскрешения"))
    parts[#parts + 1] = L("вне боя: ") .. (normal or battle or L("нет воскрешения"))
    parts[#parts + 1] = L("бафф: ") .. (buff or L("нет группового баффа"))
    return table.concat(parts, "    ")
end

-- Полный разбор в чат. Причин «клик не кастует» ровно три — нет заклинания,
-- нет кнопок, не применился атрибут — и различить их снаружи невозможно.
-- Команда отвечает на все три сразу.
function SmartClick:Diagnose()
    local settings = self:GetSettings()
    local _, class = UnitClass("player")
    JP:Print(L("--- Умный клик ---"))
    JP:Print(L("класс: ") .. tostring(class) .. L("    бафф: ") ..
        tostring(settings and settings.buff) .. L("    воскрешение: ") .. tostring(settings and settings.res))

    for label, id in pairs({
        [L("боевое воскрешение")] = BATTLE_RES[class],
        [L("обычное воскрешение")] = NORMAL_RES[class],
        [L("групповой бафф")] = BUFF[class],
    }) do
        if not id then
            JP:Print((L("  %s: у класса нет")):format(label))
        else
            local known = type(IsPlayerSpell) == "function" and IsTrue(select(2, pcall(IsPlayerSpell, id)))
            local name = SpellName(id)
            JP:Print((L("  %s: id %d, изучено: %s, имя: %s")):format(
                label, id, tostring(known), tostring(name or L("не получено"))))
        end
    end

    -- Висит ли бафф прямо сейчас. Без этой строки проверка вслепую: игрок
    -- жмёт по себе, Знак дикой природы уже висит час, каст молча не проходит
    -- — и выглядит это ровно как «ничего не работает».
    local buffID = BUFF[class]
    if buffID and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, buffID)
        JP:Print(L("  бафф на тебе сейчас: ") ..
            ((ok and aura) and L("|cffff6b6bДА — повторный каст ничего не покажет|r") or L("нет")))
    end

    local index = type(GetMacroIndexByName) == "function" and GetMacroIndexByName(MACRO_NAME) or 0
    if index and index > 0 then
        local _, _, body = GetMacroInfo(index)
        JP:Print((L("  макрос %s: слот %d")):format(MACRO_NAME, index))
        -- Тело макроса многострочное, а JP:Print печатает одной строкой:
        -- склеиваем переводы строк в разделитель, иначе видно только «#showtooltip».
        JP:Print("     " .. (tostring(body):gsub("\n", " | ")))
    else
        JP:Print(L("  |cffff6b6bмакрос не создан|r — включи хотя бы одну галочку"))
    end
end

---------------------------------------------------------------------------
-- Кнопка баффа по центру экрана
--
-- Появляется, только когда бафф кому-то в группе действительно нужен, и
-- гаснет, когда все закрыты. Это СВОЯ кнопка, а не юнит-фрейм, поэтому
-- клик-каст DandersFrames её не трогает — все прошлые попытки разбивались
-- именно об это.
--
-- Знак дикой природы и его аналоги в современной игре групповые: один каст
-- закрывает всех в радиусе на час. Поэтому кнопка не «на кого-то», а просто
-- «нажми» — цель ей не нужна.
---------------------------------------------------------------------------

local BUFF_BUTTON_SIZE = 64

-- Кому бафф не достался. Считаем и себя: соло-игрок тоже должен видеть кнопку.
function SmartClick:MissingBuff()
    local _, class = UnitClass("player")
    local buffID = class and BUFF[class]
    if not buffID or not C_UnitAuras then return nil end
    local wanted = BUFF_AURA_SET[buffID] or { [buffID] = true }

    local units = { "player" }
    if IsInRaid() then
        for index = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. index end
    elseif IsInGroup() then
        for index = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. index end
    end

    local missing = {}
    for _, unit in ipairs(units) do
        if UnitExists(unit) and not UnitIsDeadOrGhost(unit) and UnitIsConnected(unit) then
            local found = false
            for index = 1, 40 do
                local data, blocked = SafeAura(unit, index, "HELPFUL")
                -- Ауры закрыты целиком — подсказка по баффу сейчас невозможна,
                -- и перебирать оставшиеся тридцать девять слотов незачем.
                if blocked then return nil end
                if not data then break end
                local spellID = data.spellId
                if not issecretvalue(spellID) and wanted[spellID] then found = true; break end
            end
            -- Вне радиуса бафф не наложить, и в список такие не идут: иначе
            -- кнопка горела бы вечно из-за отставшего на другом конце данжа.
            --
            -- UnitInRange под taint возвращает защищённый boolean. В условии
            -- такое значение работает, а сравнивать его нельзя — на этом
            -- падало. Неизвестность считаем «в радиусе»: лучше лишнее имя в
            -- подсказке, чем молча потерянный игрок.
            local inRange = UnitInRange(unit)
            local outOfRange = false
            if not issecretvalue(inRange) then outOfRange = inRange == false end
            if not found and not outOfRange then
                local name = UnitName(unit)
                missing[#missing + 1] = (not issecretvalue(name) and name) or unit
            end
        end
    end
    if #missing == 0 then return nil end
    return missing
end

function SmartClick:BuildBuffButton()
    if self.buffButton then return self.buffButton end
    local _, class = UnitClass("player")
    local buffID = class and BUFF[class]
    if not buffID then return nil end
    local name = SpellName(buffID)
    if not name then return nil end

    -- BackdropTemplate обязателен: без него у кнопки нет SetBackdrop, и
    -- UI.Backdrop ниже падает. Раньше это не всплывало, потому что MissingBuff
    -- обрывалась ошибкой раньше и до создания кнопки дело не доходило.
    local button = CreateFrame("Button", "MythicBoostBuffButton", UIParent,
        "SecureActionButtonTemplate, BackdropTemplate")
    button:SetSize(BUFF_BUTTON_SIZE, BUFF_BUTTON_SIZE)
    -- Прямо под строкой системных сообщений: там же, где игра пишет «Вне зоны
    -- действия». Привязываемся к самому UIErrorsFrame, а не к координатам —
    -- его двигают и аддоны, и настройки интерфейса, и кнопка должна ехать за
    -- ним, а не оставаться там, где он был когда-то.
    local errors = _G.UIErrorsFrame
    if errors then
        button:SetPoint("TOP", errors, "BOTTOM", 0, -10)
    else
        button:SetPoint("TOP", UIParent, "TOP", 0, -180)
    end
    button:SetFrameStrata("HIGH")
    -- И нажатие, и отпускание. У клиента есть настройка «применять способность
    -- по нажатию клавиши», и при ней кнопка, зарегистрированная только на
    -- отпускание, молчит: наведение работает, тултип есть, а каста нет.
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetAttribute("type", "macro")
    button:SetAttribute("macrotext", BuffMacro(name))
    button.spellName = name

    UI.Backdrop(button, C.surface, C.edge)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 2, -2)
    button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    button.icon:SetTexCoord(.07, .93, .07, .93)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, texture = pcall(C_Spell.GetSpellTexture, buffID)
        if ok and texture then button.icon:SetTexture(texture) end
    end

    button.label = UI.Text(button, "GameFontNormalSmall", "", C.amber)
    button.label:SetPoint("TOP", button, "BOTTOM", 0, -4)

    button:SetScript("OnEnter", function(owner)
        UI.Tooltip(owner, name, L("Бафф нужен: ") .. (owner.missingText or "—"),
            L("Заклинание групповое — один каст закрывает всех в радиусе."))
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)

    button:Hide()
    self.buffButton = button
    return button
end

function SmartClick:RefreshBuffButton()
    local settings = self:GetSettings()
    if not settings or not settings.buff then
        if self.buffButton and not InCombatLockdown() then self.buffButton:Hide() end
        return
    end
    -- Show/Hide на secure-кнопке в бою заблокированы. Не трогаем её вовсе:
    -- бафф — занятие мирное, а мигать кнопкой посреди пула незачем.
    if InCombatLockdown() then return end

    local missing = self:MissingBuff()
    local button = self:BuildBuffButton()
    if not button then return end

    -- Макрос собирается один раз при создании кнопки, а заклинание у персонажа
    -- может смениться вместе со специализацией. Переписываем вне боя, иначе
    -- кнопка останется с прошлым кастом.
    local _, class = UnitClass("player")
    local current = class and BUFF[class] and SpellName(BUFF[class])
    if current and current ~= button.spellName then
        button:SetAttribute("macrotext", BuffMacro(current))
        button.spellName = current
    end

    if not missing then button:Hide(); return end

    button.missingText = table.concat(missing, ", ")
    button.label:SetText(#missing > 1 and (L("без баффа: ") .. #missing) or button.missingText)
    button:Show()
end

function SmartClick:Create()
    if self.events then return end
    self.events = CreateFrame("Frame")
    -- Регистрируем защищённо. RegisterEvent на событии, которого нет в этой
    -- версии клиента, бросает ошибку и обрывает Create — модуль тогда не
    -- создаётся целиком. Так уже случилось с LEARNED_SPELL_IN_TAB: его в
    -- Midnight нет, набор известных заклинаний отдаёт SPELLS_CHANGED.
    -- Пропустить одно событие не страшно; потерять модуль — страшно.
    for _, event in ipairs({
        "PLAYER_ENTERING_WORLD",
        "PLAYER_REGEN_ENABLED",
        "PLAYER_SPECIALIZATION_CHANGED",
        "SPELLS_CHANGED",
        "GROUP_ROSTER_UPDATE",
        "UNIT_AURA",
    }) do
        pcall(self.events.RegisterEvent, self.events, event)
    end
    -- Один отложенный проход на пачку событий: смена специализации приходит
    -- вместе с переучиванием заклинаний, и собирать макрос десять раз подряд
    -- незачем.
    local queued = false
    self.events:SetScript("OnEvent", function()
        if queued then return end
        queued = true
        C_Timer.After(.3, function()
            queued = false
            SmartClick:Apply()
            SmartClick:RefreshBuffButton()
        end)
    end)
end

function SmartClick:Enable() self:Apply() end
function SmartClick:Disable() end
function SmartClick:Destroy() end

JP.SmartClick = SmartClick
JP:RegisterModule("SmartClick", SmartClick)
