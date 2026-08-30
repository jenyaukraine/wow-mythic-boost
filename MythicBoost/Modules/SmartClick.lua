local _, JP = ...
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

local BUFF = {
    DRUID = 1126,        -- Знак дикой природы
    PRIEST = 21562,      -- Слово силы: Стойкость
    MAGE = 1459,         -- Чародейский интеллект
    WARRIOR = 6673,      -- Боевой крик
}

function SmartClick:GetSettings()
    if type(MythicBoostDB) ~= "table" then return nil end
    MythicBoostDB.smartClick = type(MythicBoostDB.smartClick) == "table" and MythicBoostDB.smartClick or {}
    local settings = MythicBoostDB.smartClick
    if settings.buff == nil then settings.buff = false end
    if settings.res == nil then settings.res = false end
    return settings
end

-- Имя нужно ровно то, что понимает макрос. Заклинание, которого игрок не
-- знает, в макрос не попадает: иначе клик молча ничего не делает, и человек
-- считает, что сломана галочка, а не отсутствует способность.
local function SpellName(spellID)
    if not spellID then return end
    local known = false
    if type(IsPlayerSpell) == "function" then
        local ok, result = pcall(IsPlayerSpell, spellID)
        known = ok and result == true
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
        JP:Print("|cffff6b6bНе удалось создать макрос " .. MACRO_NAME .. "|r: " .. tostring(err))
        self.macroBody = nil
        return
    end

    -- Проверяем ФАКТ, а не возврат: CreateMacro может отработать без ошибки и
    -- всё равно не создать запись, если общий список макросов переполнен.
    if (GetMacroIndexByName(MACRO_NAME) or 0) <= 0 then
        JP:Print("|cffff6b6bМакрос " .. MACRO_NAME .. " не появился|r — вероятно, кончились слоты макросов.")
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
        JP:Print("Настройка применится после боя: менять клик защищённой кнопки в бою нельзя.")
        return
    end
    -- Говорим вслух, что получилось. Молчаливая галочка неотличима от
    -- сломанной: если у класса нет нужного заклинания или игрок его ещё не
    -- выучил, клауза в макрос не попадает — и без этой строки человек видит
    -- только то, что клик ничего не делает.
    if not settings.buff and not settings.res then
        JP:Print("Умный клик выключен, макрос MBSmartClick удалён.")
        return
    end
    local sample = self:BuildMacro("mouseover")
    if sample then
        JP:Print("Макрос MBSmartClick готов: " .. sample:gsub("^/cast ", ""))
        -- Без этой строки человек включает галочку и ждёт, что заработает
        -- само. Оно не заработает: макрос создан, но никуда не привязан.
        JP:Print("|cffffb93dОсталось привязать его|r — перетащи макрос " ..
            "|cff28b8f5MBSmartClick|r на панель способностей, либо укажи его в клик-касте DandersFrames.")
    else
        JP:Print("Умный клик включён, но подходящих заклинаний не найдено — " .. self:Describe())
    end
end

-- Описание для подсказки: показывает ровно те заклинания, которые реально
-- попадут в макрос у этого персонажа.
function SmartClick:Describe()
    local _, class = UnitClass("player")
    if type(class) ~= "string" then return "класс не определён" end
    local parts = {}
    local battle, normal, buff = SpellName(BATTLE_RES[class]), SpellName(NORMAL_RES[class]), SpellName(BUFF[class])
    parts[#parts + 1] = "в бою: " .. (battle or "нет боевого воскрешения")
    parts[#parts + 1] = "вне боя: " .. (normal or battle or "нет воскрешения")
    parts[#parts + 1] = "бафф: " .. (buff or "нет группового баффа")
    return table.concat(parts, "    ")
end

-- Полный разбор в чат. Причин «клик не кастует» ровно три — нет заклинания,
-- нет кнопок, не применился атрибут — и различить их снаружи невозможно.
-- Команда отвечает на все три сразу.
function SmartClick:Diagnose()
    local settings = self:GetSettings()
    local _, class = UnitClass("player")
    JP:Print("--- Умный клик ---")
    JP:Print("класс: " .. tostring(class) .. "    бафф: " ..
        tostring(settings and settings.buff) .. "    воскрешение: " .. tostring(settings and settings.res))

    for label, id in pairs({
        ["боевое воскрешение"] = BATTLE_RES[class],
        ["обычное воскрешение"] = NORMAL_RES[class],
        ["групповой бафф"] = BUFF[class],
    }) do
        if not id then
            JP:Print(("  %s: у класса нет"):format(label))
        else
            local known = type(IsPlayerSpell) == "function" and select(2, pcall(IsPlayerSpell, id)) == true
            local name = SpellName(id)
            JP:Print(("  %s: id %d, изучено: %s, имя: %s"):format(
                label, id, tostring(known), tostring(name or "не получено")))
        end
    end

    -- Висит ли бафф прямо сейчас. Без этой строки проверка вслепую: игрок
    -- жмёт по себе, Знак дикой природы уже висит час, каст молча не проходит
    -- — и выглядит это ровно как «ничего не работает».
    local buffID = BUFF[class]
    if buffID and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, buffID)
        JP:Print("  бафф на тебе сейчас: " ..
            ((ok and aura) and "|cffff6b6bДА — повторный каст ничего не покажет|r" or "нет"))
    end

    local index = type(GetMacroIndexByName) == "function" and GetMacroIndexByName(MACRO_NAME) or 0
    if index and index > 0 then
        local _, _, body = GetMacroInfo(index)
        JP:Print(("  макрос %s: слот %d"):format(MACRO_NAME, index))
        -- Тело макроса многострочное, а JP:Print печатает одной строкой:
        -- склеиваем переводы строк в разделитель, иначе видно только «#showtooltip».
        JP:Print("     " .. (tostring(body):gsub("\n", " | ")))
    else
        JP:Print("  |cffff6b6bмакрос не создан|r — включи хотя бы одну галочку")
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
                local data = C_UnitAuras.GetAuraDataByIndex(unit, index, "HELPFUL")
                if not data then break end
                if data.spellId == buffID then found = true; break end
            end
            -- Вне радиуса бафф не наложить, и в список такие не идут: иначе
            -- кнопка горела бы вечно из-за отставшего на другом конце данжа.
            if not found and UnitInRange(unit) ~= false then
                missing[#missing + 1] = UnitName(unit) or unit
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

    local button = CreateFrame("Button", "MythicBoostBuffButton", UIParent, "SecureActionButtonTemplate")
    button:SetSize(BUFF_BUTTON_SIZE, BUFF_BUTTON_SIZE)
    button:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
    button:SetFrameStrata("HIGH")
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("type", "macro")
    button:SetAttribute("macrotext", "/cast " .. name)

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
        UI.Tooltip(owner, name, "Бафф нужен: " .. (owner.missingText or "—"),
            "Заклинание групповое — один каст закрывает всех в радиусе.")
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
    if not missing then button:Hide(); return end

    button.missingText = table.concat(missing, ", ")
    button.label:SetText(#missing > 1 and ("без баффа: " .. #missing) or button.missingText)
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
