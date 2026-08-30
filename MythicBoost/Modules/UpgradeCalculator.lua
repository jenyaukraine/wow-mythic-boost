local _, JP = ...
local L = JP.L
local UpgradeCalculator = {}
local UI, C = JP.UI, JP.UI.colors

-- Сколько гербов нужно, чтобы докачать снаряжение до потолка.
--
-- Всё берётся у самой игры. C_ItemUpgrade отдаёт для надетой вещи текущую
-- ступень, потолок и полный список ступеней со стоимостью каждой — а из этих
-- стоимостей видно, какими гербами сейчас платят.
--
-- Ничего про гербы в аддоне не зашито намеренно. ID валют и уровни предметов
-- меняются каждый сезон, и таблица, списанная с прошлого, тихо врёт: показывает
-- «0 нужно» там, где нужно, потому что ищет валюту, которой больше нет в ходу.
-- Поэтому список гербов собирается заново при каждом пересчёте, а порядок
-- треков выводится из того, до какого уровня предмета этот герб докачивает.
--
-- Особенность API: вне окна мастера улучшений часть слотов отвечает nil. Это не
-- ошибка, а отсутствие данных, и таблица говорит об этом прямо, вместо того
-- чтобы выдать неполный итог за полный.

-- Цвет привязан к порядку трека, а не к названию: порядок переживает смену
-- сезона, названия и ID — нет.
local TRACK_COLORS = {
    { .12, 1, 0, 1 },
    { 0, .44, .87, 1 },
    { .64, .21, .93, 1 },
    { 1, .50, 0, 1 },
    { 1, .82, 0, 1 },
    { .95, .95, .95, 1 },
}
local MAX_TRACKS = #TRACK_COLORS

-- Рубаха и гербовая накидка улучшению не подлежат и в таблице только мешают.
local SLOTS = {
    { id = 1,  label = L("Голова") },      { id = 2,  label = L("Шея") },
    { id = 3,  label = L("Плечи") },       { id = 15, label = L("Спина") },
    { id = 5,  label = L("Грудь") },       { id = 9,  label = L("Запястья") },
    { id = 10, label = L("Кисти") },       { id = 6,  label = L("Пояс") },
    { id = 7,  label = L("Ноги") },        { id = 8,  label = L("Ступни") },
    { id = 11, label = L("Кольцо 1") },    { id = 12, label = L("Кольцо 2") },
    { id = 13, label = L("Аксессуар 1") }, { id = 14, label = L("Аксессуар 2") },
    { id = 16, label = L("Правая рука") }, { id = 17, label = L("Левая рука") },
}

local COLUMNS = {
    { key = "slot",   text = L("СЛОТ"),    x = 14,  width = 150, justify = "LEFT" },
    { key = "ilvl",   text = L("УР."),     x = 172, width = 54,  justify = "CENTER" },
    { key = "max",    text = L("МАКС"),    x = 232, width = 54,  justify = "CENTER" },
    { key = "steps",  text = L("СТУПЕНИ"), x = 294, width = 80,  justify = "CENTER" },
    { key = "track",  text = L("ТРЕК"),    x = 384, width = 180, justify = "LEFT" },
    { key = "crests", text = L("ГЕРБЫ"),   x = 572, width = 150, justify = "LEFT" },
    { key = "gold",   text = L("ЗОЛОТО"),  x = 730, width = 130, justify = "RIGHT" },
}

local ROW_HEIGHT, ROW_STEP = 20, 22
-- Заголовок, подпись о режиме, шапка колонок, разделитель, строки. Подпись
-- раньше налезала на шапку: обе стояли в одном интервале.
local HEADER_TOP, ROWS_TOP = -12, -68
local TOTALS_TOP = ROWS_TOP - #SLOTS * ROW_STEP - 18

---------------------------------------------------------------------------
-- Чтение данных игры
---------------------------------------------------------------------------

local PlainNumber, PlainString = UI.SafeNumber, UI.SafeString

local function EquipmentLocation(slotID)
    if not ItemLocation or type(ItemLocation.CreateFromEquipmentSlot) ~= "function" then return nil end
    -- CreateFromEquipmentSlot is a method of ItemLocation, not a plain
    -- function.  Calling it without ItemLocation as self silently produces no
    -- usable location and makes the whole equipment scan come back empty.
    local ok, location = pcall(ItemLocation.CreateFromEquipmentSlot, ItemLocation, slotID)
    if not ok or not location then return nil end
    if type(location.IsValid) == "function" then
        local validOK, valid = pcall(location.IsValid, location)
        if not validOK or not valid then return nil end
    end
    return location
end

-- Совпадает ли то, что вернула игра, с вещью в этом слоте. Проверка нужна
-- потому, что запрос без аргументов отдаёт «текущую выбранную» вещь, а она
-- могла не смениться.
local function MatchesSlot(slotID, info)
    if type(info) ~= "table" then return false end
    local link = GetInventoryItemLink and GetInventoryItemLink("player", slotID)
    if not PlainString(link) then return false end
    local infoID = PlainNumber(info.itemID)
    local itemID = GetItemInfoInstant and GetItemInfoInstant(link)
    if infoID and itemID then return tonumber(itemID) == infoID end
    -- Some builds omit itemID.  A non-empty name alone is not a match: after
    -- changing the NPC selection the API can briefly return the previous
    -- item's info.  Compare the actual names so stale data is never copied to
    -- every equipment slot.
    local infoName = PlainString(info.name)
    local itemName = GetItemInfo and GetItemInfo(link)
    itemName = PlainString(itemName)
    return infoName ~= nil and itemName ~= nil and infoName == itemName
end

-- Выбрать вещь в окне мастера. Без этого GetItemUpgradeItemInfo молчит: данные
-- об улучшении игра отдаёт только для вещи, лежащей в окне. Курсор не трогаем.
local function SelectIntoUpgrader(location)
    if not C_ItemUpgrade then return false end
    if type(C_ItemUpgrade.ClearItemUpgrade) == "function" then pcall(C_ItemUpgrade.ClearItemUpgrade) end
    local frame = _G.ItemUpgradeFrame
    if frame and type(frame.ClearAllItems) == "function" then
        pcall(frame.ClearAllItems, frame)
    end
    if type(C_ItemUpgrade.SetItemUpgradeFromItemLocation) == "function"
        and pcall(C_ItemUpgrade.SetItemUpgradeFromItemLocation, location) then return true end
    if type(C_ItemUpgrade.SetItemUpgradeFromLocation) == "function"
        and pcall(C_ItemUpgrade.SetItemUpgradeFromLocation, location) then return true end
    return false
end

local function UpgradeInfoForSlot(slotID, location)
    if not C_ItemUpgrade or type(C_ItemUpgrade.GetItemUpgradeItemInfo) ~= "function" then return nil end
    local ok, info = pcall(C_ItemUpgrade.GetItemUpgradeItemInfo, location)
    if ok and MatchesSlot(slotID, info) then return info end
    return nil
end

local function CurrencyName(currencyID)
    if not C_CurrencyInfo or type(C_CurrencyInfo.GetCurrencyInfo) ~= "function" then return nil end
    local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
    if not ok or type(info) ~= "table" then return nil end
    return PlainString(info.name), PlainNumber(info.quantity) or 0,
        PlainNumber(info.quality), PlainNumber(info.iconFileID)
end

local function CurrencyLink(currencyID)
    if not C_CurrencyInfo or type(C_CurrencyInfo.GetCurrencyLink) ~= "function" then return nil end
    local ok, link = pcall(C_CurrencyInfo.GetCurrencyLink, currencyID)
    return ok and PlainString(link) or nil
end

local function LinkColor(link)
    if not link then return nil end
    local hex = link:match("|cff(%x%x%x%x%x%x)")
    if not hex then return nil end
    return {
        tonumber(hex:sub(1, 2), 16) / 255,
        tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255,
        1,
    }
end

local function OwnedCrests(currencyID)
    local _, quantity = CurrencyName(currencyID)
    return quantity or 0
end

local function ItemLevel(slotID)
    local link = GetInventoryItemLink and GetInventoryItemLink("player", slotID)
    if not PlainString(link) then return nil end
    if C_Item and type(C_Item.GetDetailedItemLevelInfo) == "function" then
        local ok, level = pcall(C_Item.GetDetailedItemLevelInfo, link)
        if ok then return PlainNumber(level) end
    end
    return nil
end

-- Стоимость добора от текущей ступени до потолка. Ступени ниже текущей уже
-- оплачены — иначе таблица требует гербы за пройденное.
local function RemainingCost(info)
    local current = PlainNumber(info.currUpgrade) or 0
    local crests, gold = {}, 0
    for _, step in ipairs(info.upgradeLevelInfos or {}) do
        local level = PlainNumber(step.upgradeLevel) or 0
        if level > current then
            gold = gold + (PlainNumber(step.moneyCost) or 0)
            for _, cost in ipairs(step.currencyCostsToUpgrade or {}) do
                local currencyID, amount = PlainNumber(cost.currencyID), PlainNumber(cost.cost)
                if currencyID and amount and amount > 0 then
                    crests[currencyID] = (crests[currencyID] or 0) + amount
                end
            end
        end
    end
    return crests, gold
end

-- Герб последней ступени и есть трек вещи: именно им платят за верх трека.
local function TrackCurrency(info)
    local best, bestLevel
    for _, step in ipairs(info.upgradeLevelInfos or {}) do
        local level = PlainNumber(step.upgradeLevel) or 0
        for _, cost in ipairs(step.currencyCostsToUpgrade or {}) do
            local currencyID = PlainNumber(cost.currencyID)
            if currencyID and (not bestLevel or level >= bestLevel) then
                best, bestLevel = currencyID, level
            end
        end
    end
    return best
end

function UpgradeCalculator:UpgraderOpen()
    local frame = _G.ItemUpgradeFrame
    return frame and type(frame.IsShown) == "function" and frame:IsShown() and true or false
end

---------------------------------------------------------------------------
-- Пересчёт
---------------------------------------------------------------------------

-- Замеры хранятся между сессиями. Данные об улучшении игра отдаёт только у
-- мастера, и заставлять бегать к нему ради каждого пересчёта незачем: сходил
-- один раз — считаем по сохранённому, пока вещь в слоте не сменилась.
local function SavedSlots()
    local store = JP.Settings("upgradeCalculator") or {}
    -- Schema 2 introduces strict per-slot matching.  Older records may all
    -- contain the first selected item because the old matcher accepted any
    -- non-empty item name.
    if store.schema ~= 2 then
        store.slots = {}
        store.schema = 2
    end
    store.slots = type(store.slots) == "table" and store.slots or {}
    return store.slots
end

local function EquippedStamp(slotID)
    local link = GetInventoryItemLink and GetInventoryItemLink("player", slotID)
    if not PlainString(link) then return nil end
    local itemID = GetItemInfoInstant and GetItemInfoInstant(link)
    return PlainNumber(tonumber(itemID)), ItemLevel(slotID)
end

-- Из ответа игры сразу вынимаем плоскую запись: сама таблица info живёт до
-- следующего выбора в окне мастера и полагаться на неё нельзя.
local function RecordFrom(info, slotID)
    local itemID, itemLevel = EquippedStamp(slotID)
    local crests, gold = RemainingCost(info)
    return {
        itemID = itemID,
        itemLevel = itemLevel,
        current = PlainNumber(info.currUpgrade) or 0,
        maximum = PlainNumber(info.maxUpgrade) or 0,
        maxItemLevel = PlainNumber(info.maxItemLevel),
        trackName = PlainString(info.customUpgradeString),
        trackCurrency = TrackCurrency(info),
        crests = crests,
        gold = gold,
    }
end

-- Запись годится, только если в слоте лежит та же вещь того же уровня.
local function RecordFresh(record, slotID)
    if type(record) ~= "table" then return false end
    local itemID, itemLevel = EquippedStamp(slotID)
    if not itemID then return false end
    return record.itemID == itemID and record.itemLevel == itemLevel
end

-- Пошаговый обход у мастера.
--
-- Синхронно это не работает: после подстановки вещи окно обновляется не в том
-- же кадре, и чтение сразу после выбора возвращает прошлую вещь или пустоту.
-- Поэтому между слотами держим паузу и читаем уже после неё.
function UpgradeCalculator:ScanAtUpgrader()
    if self.scanning or not self:UpgraderOpen() then return end
    if not C_ItemUpgrade or type(C_ItemUpgrade.GetItemUpgradeItemInfo) ~= "function" then return end

    self.scanning, self.scanned = true, 0
    local saved, index = SavedSlots(), 1

    local function Finish()
        if C_ItemUpgrade and type(C_ItemUpgrade.ClearItemUpgrade) == "function" then
            pcall(C_ItemUpgrade.ClearItemUpgrade)
        end
        self.scanning = nil
        -- Обход за этот подход к мастеру сделан. Без этой отметки Refresh
        -- увидит оставшиеся незамеренными слоты и запустит обход снова: у
        -- вещей без улучшений данных не будет никогда, и цикл не кончится.
        self.autoScanned = true
        self:Refresh()
    end

    local function Step()
        if not self.scanning then return end
        -- Окно закрыли посреди обхода: показываем то, что успели собрать.
        if not self:UpgraderOpen() then Finish(); return end

        local slot = SLOTS[index]
        if not slot then Finish(); return end
        index = index + 1

        local location = EquipmentLocation(slot.id)
        if not location then Step(); return end

        -- Some client builds can answer directly from an ItemLocation.  Keep
        -- this fast path; selecting the item in the NPC frame remains the
        -- fallback for builds which only answer for the current selection.
        local direct = UpgradeInfoForSlot(slot.id, location)
        if direct then
            saved[slot.id] = RecordFrom(direct, slot.id)
            self.scanned = (self.scanned or 0) + 1
            if self.page then self:RenderProgress(index - 1, #SLOTS) end
            Step()
            return
        end

        SelectIntoUpgrader(location)

        local attempts = 0
        local function CompleteSlot(info)
            if info and MatchesSlot(slot.id, info) then
                saved[slot.id] = RecordFrom(info, slot.id)
                self.scanned = (self.scanned or 0) + 1
            else
                -- Вещь мастеру показали, а он про неё ничего не сказал: она не
                -- улучшается вовсе. Это тоже результат замера, и записать его
                -- надо — иначе слот вечно числится незамеренным.
                local itemID, itemLevel = EquippedStamp(slot.id)
                saved[slot.id] = { itemID = itemID, itemLevel = itemLevel, none = true }
            end
            if self.page then self:RenderProgress(index - 1, #SLOTS) end
            Step()
        end

        local function ReadSelection()
            C_Timer.After(.12, function()
                if not self.scanning then return end
                attempts = attempts + 1
                local ok, info = pcall(C_ItemUpgrade.GetItemUpgradeItemInfo)
                if not ok or not MatchesSlot(slot.id, info) then
                    info = UpgradeInfoForSlot(slot.id, location)
                end
                if info and MatchesSlot(slot.id, info) then
                    CompleteSlot(info)
                elseif attempts < 5 then
                    -- The NPC frame updates asynchronously.  Never accept the
                    -- previous item's data; give this slot a few frames to
                    -- become the actual selection instead.
                    ReadSelection()
                else
                    CompleteSlot(nil)
                end
            end)
        end
        ReadSelection()
    end

    Step()
end

function UpgradeCalculator:Scan()
    local rows, needed, gold, unknown = {}, {}, 0, 0
    local saved = SavedSlots()
    -- Какие гербы вообще в ходу — узнаём по стоимостям, которые называет игра.
    local seen = {}

    local function Note(currencyID, peak, quality, distance)
        if not currencyID then return end
        local entry = seen[currencyID]
        if not entry then
            entry = { currencyID = currencyID, peak = 0 }
            seen[currencyID] = entry
        end
        if peak and peak > entry.peak then entry.peak = peak end
        if quality then entry.quality = quality end
        if distance and (not entry.distance or distance < entry.distance) then entry.distance = distance end
    end

    for _, slot in ipairs(SLOTS) do
        local link = GetInventoryItemLink and GetInventoryItemLink("player", slot.id)
        if PlainString(link) then
            local entry = {
                slotID = slot.id,
                label = slot.label,
                icon = GetInventoryItemTexture and GetInventoryItemTexture("player", slot.id) or nil,
                ilvl = ItemLevel(slot.id),
            }
            local record = saved[slot.id]
            if RecordFresh(record, slot.id) and record.none then
                entry.none = true
            elseif RecordFresh(record, slot.id) then
                entry.current, entry.maximum = record.current, record.maximum
                entry.maxItemLevel, entry.trackName = record.maxItemLevel, record.trackName
                entry.trackCurrency = record.trackCurrency
                entry.crests, entry.gold = record.crests or {}, record.gold or 0
                gold = gold + entry.gold
                for currencyID, amount in pairs(entry.crests) do
                    needed[currencyID] = (needed[currencyID] or 0) + amount
                    Note(currencyID, entry.maxItemLevel)
                end
                -- Вещь на потолке ничего не стоит, но её герб всё равно
                -- называет трек — иначе доделанные треки исчезают из итога.
                Note(entry.trackCurrency, entry.maxItemLevel)
            else
                -- Вещь сменилась или её ещё не замеряли: старую запись держать
                -- нельзя, она соврёт числами от прошлого предмета.
                saved[slot.id] = nil
                entry.unknown = true
                unknown = unknown + 1
            end
            rows[#rows + 1] = entry
        end
    end

    -- Стоимость текущей экипировки обычно содержит только один тип герба.
    -- Остальные гербы того же сезона лежат рядом в таблице валют Blizzard.
    -- Находим соседние валюты с «герб»/"crest" в локализованном названии,
    -- чтобы итог показывал весь сезонный набор, в том числе нужные сейчас в 0.
    local anchors = {}
    for currencyID in pairs(seen) do anchors[#anchors + 1] = currencyID end
    for _, anchorID in ipairs(anchors) do
        for currencyID = math.max(1, anchorID - 4), anchorID + 4 do
            local name, _, quality = CurrencyName(currencyID)
            local lower = name and name:lower() or ""
            if lower:find(L("герб"), 1, true) or lower:find("crest", 1, true) then
                Note(currencyID, nil, quality, math.abs(currencyID - anchorID))
            end
        end
    end

    for _, entry in pairs(seen) do
        local _, _, quality = CurrencyName(entry.currencyID)
        entry.quality = entry.quality or quality or 0
    end

    -- Порядок треков — по уровню предмета, до которого герб докачивает. Это
    -- единственный признак старшинства, который не зависит от сезона.
    local unique = {}
    for _, entry in pairs(seen) do
        local name, quantity = CurrencyName(entry.currencyID)
        local key = name and name:lower() or tostring(entry.currencyID)
        local previous = unique[key]
        local prefer = not previous
            or (entry.peak > 0 and previous.peak <= 0)
            or (entry.peak == previous.peak and (entry.distance or 99) < (previous.distance or 99))
            or (entry.peak == previous.peak and (entry.distance or 99) == (previous.distance or 99)
                and quantity > (previous.quantity or 0))
        entry.quantity = quantity
        if prefer then unique[key] = entry end
    end

    local tracks = {}
    for _, entry in pairs(unique) do tracks[#tracks + 1] = entry end
    table.sort(tracks, function(a, b)
        if a.quality ~= b.quality then return a.quality < b.quality end
        if a.peak ~= b.peak and a.peak > 0 and b.peak > 0 then return a.peak < b.peak end
        return a.currencyID < b.currencyID
    end)

    local byCurrency = {}
    for index, track in ipairs(tracks) do
        track.order = index
        track.link = CurrencyLink(track.currencyID)
        track.color = LinkColor(track.link) or TRACK_COLORS[math.min(index, MAX_TRACKS)]
        track.label = CurrencyName(track.currencyID) or (L("Герб #") .. track.currencyID)
        byCurrency[track.currencyID] = track
    end

    for _, entry in ipairs(rows) do
        entry.track = entry.trackCurrency and byCurrency[entry.trackCurrency] or nil
    end

    self.rows, self.needed, self.gold, self.unknown = rows, needed, gold, unknown
    self.tracks, self.trackByCurrency = tracks, byCurrency
    self.scannedAtUpgrader = self:UpgraderOpen()
    return rows
end

---------------------------------------------------------------------------
-- Интерфейс
---------------------------------------------------------------------------

local function HideComparisonTooltips()
    for index = 1, 3 do
        local shopping = _G["ShoppingTooltip" .. index]
        if shopping then shopping:Hide() end
        local itemRef = _G["ItemRefShoppingTooltip" .. index]
        if itemRef then itemRef:Hide() end
    end
end

local function BuildRow(page, index)
    local row = CreateFrame("Frame", nil, page, "BackdropTemplate")
    row:SetPoint("TOPLEFT", 8, ROWS_TOP - (index - 1) * ROW_STEP)
    row:SetPoint("TOPRIGHT", -8, ROWS_TOP - (index - 1) * ROW_STEP)
    row:SetHeight(ROW_HEIGHT)
    row.baseColor = index % 2 == 0 and C.rowAlt or C.row
    UI.Backdrop(row, row.baseColor, C.lineSoft)

    -- Тултип надетой вещи — тот же, что в окне персонажа, вместе со сравнением
    -- по Shift. Без него строка называет слот, но не говорит, что в нём лежит.
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(C.rowHover))
        if not self.slotID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", self.slotID) then
            GameTooltip:Hide()
            return
        end
        GameTooltip:Show()
        -- Для колец и аксессуаров Blizzard при включённом автосравнении
        -- открывает ещё два окна. Здесь строка уже показывает надетую вещь,
        -- поэтому эти дубликаты только закрывают таблицу.
        HideComparisonTooltips()
    end)
    row:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(self.baseColor))
        GameTooltip_Hide()
        HideComparisonTooltips()
    end)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:SetSize(16, 16)
    row.icon:SetTexCoord(.08, .92, .08, .92)

    row.cells = {}
    for _, column in ipairs(COLUMNS) do
        local indent = column.key == "slot" and 10 or 0
        local text = UI.Text(row, "GameFontHighlightSmall", "")
        text:SetPoint("LEFT", column.x + indent, 0)
        text:SetWidth(column.width - indent)
        text:SetJustifyH(column.justify)
        text:SetWordWrap(false)
        row.cells[column.key] = text
    end
    return row
end

local function BuildTrackTotals(page)
    page.totals = {}
    page.totalsArea = UI.Panel(page, { .045, .055, .070, .72 }, C.lineSoft)
    page.totalsArea:SetHeight(92)

    for index = 1, MAX_TRACKS do
        local block = UI.Panel(page.totalsArea, { .052, .064, .080, .96 }, C.lineSoft)
        block:SetHeight(78)

        block.accent = block:CreateTexture(nil, "OVERLAY")
        block.accent:SetPoint("TOPLEFT", 1, -1)
        block.accent:SetPoint("TOPRIGHT", -1, -1)
        block.accent:SetHeight(2)

        block.iconBorder = CreateFrame("Frame", nil, block, "BackdropTemplate")
        block.iconBorder:SetPoint("LEFT", 8, 0)
        block.iconBorder:SetSize(44, 44)
        block.iconBorder:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        block.iconBorder:SetBackdropColor(.03, .04, .055, 1)

        block.icon = block.iconBorder:CreateTexture(nil, "ARTWORK")
        block.icon:SetPoint("TOPLEFT", block.iconBorder, "TOPLEFT", 3, -3)
        block.icon:SetPoint("BOTTOMRIGHT", block.iconBorder, "BOTTOMRIGHT", -3, 3)
        block.icon:SetTexCoord(.07, .93, .07, .93)

        block.name = UI.Text(block, "GameFontNormal", "", C.text)
        block.name:SetPoint("TOPLEFT", 60, -7)
        block.name:SetPoint("TOPRIGHT", -8, -7)
        block.name:SetJustifyH("LEFT")
        block.name:SetWordWrap(false)

        block.need = UI.Text(block, "GameFontHighlightSmall", "", C.text)
        block.need:SetPoint("TOPLEFT", 60, -27)
        block.need:SetJustifyH("LEFT")

        block.have = UI.Text(block, "GameFontHighlightSmall", "", C.muted)
        block.have:SetPoint("TOPLEFT", 60, -43)
        block.have:SetJustifyH("LEFT")
        block.have:SetWordWrap(false)

        block.shortage = UI.Text(block, "GameFontHighlightSmall", "", C.muted)
        block.shortage:SetPoint("TOPLEFT", 60, -59)
        block.shortage:SetJustifyH("LEFT")
        block.shortage:SetWordWrap(false)

        block:EnableMouse(true)
        if type(block.SetHyperlinksEnabled) == "function" then block:SetHyperlinksEnabled(true) end
        block:SetScript("OnEnter", function(self)
            if not self.currencyID then return end
            self:SetBackdropColor(.075, .090, .110, 1)
            UI.Tooltip(self, self.label or L("Герб"),
                (L("Нужно: %d")):format(self.needed or 0),
                (L("Есть: %d")):format(self.owned or 0),
                (L("Не хватает: %d")):format(self.missing or 0))
        end)
        block:SetScript("OnLeave", function(self)
            self:SetBackdropColor(.052, .064, .080, .96)
            GameTooltip_Hide()
        end)
        block:SetScript("OnHyperlinkClick", function(self, link, text, button)
            if SetItemRef then SetItemRef(link, text, button, self) end
        end)

        block:Hide()
        page.totals[index] = block
    end
end

local function LayoutTrackTotals(page, count)
    count = math.max(1, math.min(count or 1, MAX_TRACKS))
    local pageWidth = math.max(760, page:GetWidth() or 760)
    local gap = 8
    local width = math.floor(math.min(228, (pageWidth - 32 - (count - 1) * gap) / count))
    local totalWidth = count * width + (count - 1) * gap
    local startX = math.floor((pageWidth - totalWidth) / 2)

    page.summary:ClearAllPoints()
    page.totalsArea:ClearAllPoints()
    if (page:GetHeight() or 0) >= 590 then
        page.summary:SetPoint("TOPLEFT", 14, TOTALS_TOP)
        page.totalsArea:SetPoint("TOPLEFT", 8, TOTALS_TOP - 26)
        page.totalsArea:SetPoint("TOPRIGHT", -8, TOTALS_TOP - 26)
    else
        -- В минимальном размере оставляем старую безопасную привязку снизу,
        -- чтобы блок не вышел за границу окна.
        page.summary:SetPoint("BOTTOMLEFT", 14, 107)
        page.totalsArea:SetPoint("BOTTOMLEFT", 8, 8)
        page.totalsArea:SetPoint("BOTTOMRIGHT", -8, 8)
    end

    for index, block in ipairs(page.totals) do
        block:ClearAllPoints()
        block:SetPoint("TOPLEFT", page.totalsArea, "TOPLEFT",
            startX - 8 + (index - 1) * (width + gap), -7)
        block:SetWidth(width)
    end
end

local function ShortCrestName(name)
    if not name then return L("Герб") end
    local short = name:gsub(L("^Маревый герб%s+"), "")
    short = short:gsub("%s+[Mm]istcrest$", "")
    local lower = short:lower()
    if lower:find(L("искател"), 1, true) then return L("Искатель") end
    if lower:find(L("ветеран"), 1, true) then return L("Ветеран") end
    if lower:find(L("защитник"), 1, true) then return L("Защитник") end
    if lower:find(L("геро"), 1, true) then return L("Герой") end
    if lower:find(L("эпох"), 1, true) then return L("Эпоха") end
    return short ~= "" and short or name
end

local function LinkWithText(link, text)
    if not link or not text then return link end
    return (link:gsub("(|h)%b[](|h)", "%1[" .. text .. "]%2", 1))
end

function UpgradeCalculator:Build(welcome, page)
    self.page, self.welcome = page, welcome

    page.title = UI.Text(page, "GameFontNormal", L("До потолка улучшений"), C.text)
    page.title:SetPoint("TOPLEFT", 14, HEADER_TOP + 2)

    page.mode = UI.Text(page, "GameFontHighlightSmall", "", C.muted)
    page.mode:SetPoint("TOPLEFT", 14, HEADER_TOP - 16)
    page.mode:SetPoint("TOPRIGHT", -160, HEADER_TOP - 16)
    page.mode:SetJustifyH("LEFT")
    page.mode:SetWordWrap(false)

    page.refresh = UI.Button(page, L("Сканировать"), 120, 20, true)
    page.refresh:SetPoint("TOPRIGHT", -14, HEADER_TOP + 4)
    page.refresh:SetScript("OnClick", function()
        if UpgradeCalculator.scanning then return end
        UpgradeCalculator.autoScanned = nil
        if UpgradeCalculator:UpgraderOpen() then
            UpgradeCalculator:RenderProgress(0, #SLOTS)
            UpgradeCalculator:ScanAtUpgrader()
        else
            UpgradeCalculator:Refresh()
        end
    end)

    page.headers = {}
    for _, column in ipairs(COLUMNS) do
        local text = UI.Text(page, "GameFontNormalSmall", column.text, C.faint)
        text:SetPoint("TOPLEFT", 8 + column.x, ROWS_TOP + 20)
        text:SetWidth(column.width)
        text:SetJustifyH(column.justify)
        page.headers[column.key] = text
    end

    page.divider = UI.Line(page, C.lineSoft)
    page.divider:SetPoint("TOPLEFT", 8, ROWS_TOP + 6)
    page.divider:SetPoint("TOPRIGHT", -8, ROWS_TOP + 6)

    page.rows = {}
    for index = 1, #SLOTS do page.rows[index] = BuildRow(page, index) end

    page.summary = UI.Text(page, "GameFontNormal", "", C.text)
    page.summary:SetJustifyH("LEFT")

    BuildTrackTotals(page)
    LayoutTrackTotals(page, 1)
    page:SetScript("OnSizeChanged", function()
        LayoutTrackTotals(page, #(UpgradeCalculator.tracks or {}))
    end)
    self.built = true
end

local function ColorCode(color)
    return ("|cff%02x%02x%02x"):format(color[1] * 255, color[2] * 255, color[3] * 255)
end

function UpgradeCalculator:FormatCrests(entry)
    if not entry.crests then return "—" end
    local parts = {}
    for _, track in ipairs(self.tracks or {}) do
        local amount = entry.crests[track.currencyID]
        if amount and amount > 0 then
            parts[#parts + 1] = ("%s%d|r"):format(ColorCode(track.color), amount)
        end
    end
    return #parts > 0 and table.concat(parts, " ") or "—"
end

local function FormatGold(copper)
    if not copper or copper <= 0 then return "—" end
    if type(GetCoinTextureString) == "function" then
        local ok, text = pcall(GetCoinTextureString, copper)
        if ok and text then return text end
    end
    return (L("%d з")):format(math.floor(copper / 10000))
end

function UpgradeCalculator:RenderProgress(done, total)
    if not self.page then return end
    self.page.mode:SetFormattedText(L("Замеряю у мастера: %d из %d…"), done, total)
end

function UpgradeCalculator:Refresh()
    if not self.built or not self.page then return end
    local page = self.page
    self:Scan()

    -- У мастера сразу добираем недостающее: данные об улучшении игра отдаёт
    -- только там, и просить нажать кнопку ещё раз — лишний шаг.
    if self.unknown > 0 and not self.scanning and not self.autoScanned and self:UpgraderOpen() then
        self:ScanAtUpgrader()
    end

    for index, row in ipairs(page.rows) do
        local entry = self.rows[index]
        if not entry then row.slotID = nil; row:Hide() else
            row.slotID = entry.slotID
            row.icon:SetTexture(entry.icon)
            row.cells.slot:SetText(entry.label)
            row.cells.ilvl:SetText(entry.ilvl and tostring(entry.ilvl) or "—")

            if entry.unknown then
                row.cells.max:SetText("—")
                row.cells.steps:SetText(L("нет данных"))
                row.cells.steps:SetTextColor(C.amber[1], C.amber[2], C.amber[3], 1)
                row.cells.track:SetText("")
                row.cells.crests:SetText("")
                row.cells.gold:SetText("")
                row:SetAlpha(.72)
            elseif entry.none then
                -- Замер был, улучшений у вещи нет вовсе. Это не «готово»:
                -- готово значит докачано до потолка, а тут потолка не бывает.
                row.cells.max:SetText(entry.ilvl and tostring(entry.ilvl) or "—")
                row.cells.steps:SetText(L("не улучшается"))
                row.cells.steps:SetTextColor(C.faint[1], C.faint[2], C.faint[3], 1)
                row.cells.track:SetText("—")
                row.cells.track:SetTextColor(C.faint[1], C.faint[2], C.faint[3], 1)
                row.cells.crests:SetText("—")
                row.cells.gold:SetText("—")
                row:SetAlpha(1)
            else
                row.cells.max:SetText(entry.maxItemLevel and tostring(entry.maxItemLevel) or "—")
                if (entry.maximum or 0) - (entry.current or 0) > 0 then
                    row.cells.steps:SetFormattedText("%d/%d", entry.current, entry.maximum)
                    row.cells.steps:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
                else
                    row.cells.steps:SetText(L("готово"))
                    row.cells.steps:SetTextColor(C.green[1], C.green[2], C.green[3], 1)
                end
                local track = entry.track
                row.cells.track:SetText(entry.trackName or (track and track.label) or "—")
                if track then row.cells.track:SetTextColor(unpack(track.color))
                else row.cells.track:SetTextColor(C.faint[1], C.faint[2], C.faint[3], 1) end
                row.cells.crests:SetText(self:FormatCrests(entry))
                row.cells.gold:SetText(FormatGold(entry.gold))
                row:SetAlpha(1)
            end
            row:Show()
        end
    end

    local missingTotal = 0
    for index, block in ipairs(page.totals) do
        local track = self.tracks[index]
        if not track then block:Hide() else
            local need = self.needed[track.currencyID] or 0
            local have = OwnedCrests(track.currencyID)
            local missing = math.max(0, need - have)
            missingTotal = missingTotal + missing
            local link = track.link or CurrencyLink(track.currencyID)
            block.name:SetText(link and LinkWithText(link, ShortCrestName(track.label)) or track.label)
            if link then block.name:SetTextColor(1, 1, 1, 1)
            else block.name:SetTextColor(unpack(track.color)) end
            block.currencyID = track.currencyID
            block.label = track.label
            block.needed, block.owned, block.missing = need, have, missing
            local _, _, _, icon = CurrencyName(track.currencyID)
            block.icon:SetTexture(icon)
            block.icon:SetShown(icon ~= nil)
            block.need:SetFormattedText(L("Нужно: |cffffffff%d|r"), need)
            block.have:SetFormattedText(L("Есть: %d"), have)
            block.shortage:SetFormattedText(L("Не хватает: %d"), missing)
            block:SetBackdropBorderColor(track.color[1], track.color[2], track.color[3], .70)
            block.iconBorder:SetBackdropBorderColor(track.color[1], track.color[2], track.color[3], 1)
            block.accent:SetColorTexture(track.color[1], track.color[2], track.color[3], .92)
            if missing > 0 then
                block.have:SetTextColor(C.amber[1], C.amber[2], C.amber[3], 1)
                block.shortage:SetTextColor(C.amber[1], C.amber[2], C.amber[3], 1)
            else
                block.have:SetTextColor(C.green[1], C.green[2], C.green[3], 1)
                block.shortage:SetTextColor(C.green[1], C.green[2], C.green[3], 1)
            end
            block:Show()
        end
    end

    page.summary:SetFormattedText(L("Не хватает гербов: %d      Золото: %s"),
        missingTotal, FormatGold(self.gold))
    LayoutTrackTotals(page, #self.tracks)

    if self.scanning then
        -- Подпись ведёт RenderProgress, не затираем её.
    elseif self.unknown > 0 then
        page.mode:SetFormattedText(
            L("|cffffbb33Неполный расчёт:|r по %d предметам замеров нет. ")
            .. L("Данные об улучшении игра отдаёт только у мастера — подойди к нему, ")
            .. L("остальное аддон снимет сам и запомнит."), self.unknown)
    elseif #self.tracks == 0 then
        page.mode:SetText(L("Улучшать нечего: игра не назвала ни одного герба для надетых вещей."))
    else
        page.mode:SetText(L("Расчёт по сохранённым замерам. Сменишь вещь — этот слот замерится заново у мастера."))
    end
end

---------------------------------------------------------------------------
-- Жизненный цикл модуля
---------------------------------------------------------------------------

function UpgradeCalculator:Create()
    if self.events then return end
    self.events = CreateFrame("Frame")
    -- Защищённо: событие, которого нет в этой версии клиента, роняет Create и
    -- убивает модуль целиком. Потерять одно событие дешевле, чем модуль.
    for _, event in ipairs({
        "PLAYER_EQUIPMENT_CHANGED",
        "CURRENCY_DISPLAY_UPDATE",
        -- Подошёл к мастеру — замер начнётся сам, руками жать нечего.
        "ITEM_UPGRADE_MASTER_OPENED",
        "ITEM_UPGRADE_MASTER_CLOSED",
    }) do
        pcall(self.events.RegisterEvent, self.events, event)
    end
    self.events:SetScript("OnEvent", function(_, event)
        -- Новый подход к мастеру и новая вещь — повод замерить заново.
        if event == "ITEM_UPGRADE_MASTER_CLOSED" or event == "PLAYER_EQUIPMENT_CHANGED" then
            self.autoScanned = nil
        end
        -- Пересчитываем только при открытой вкладке: считать в фоне на каждую
        -- смену валюты незачем, данные всё равно берутся заново при показе.
        if self.built and self.welcome and self.welcome.currentPage == "upgrades" then
            self:Refresh()
        end
    end)
end

function UpgradeCalculator:Enable() end
function UpgradeCalculator:Disable() end
function UpgradeCalculator:Destroy() end

JP.UpgradeCalculator = UpgradeCalculator
JP:RegisterModule("UpgradeCalculator", UpgradeCalculator)
