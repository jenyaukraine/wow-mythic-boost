local _, JP = ...
local L = JP.L
local LootUI = {}
local UI, C = JP.UI, JP.UI.colors

local MAX_ROWS = 10
-- XLoot держит строку высотой ровно в иконку плюс пара пикселей воздуха, а
-- окно — узким: список добычи читают боковым зрением, и лишняя ширина только
-- отнимает место у игрового экрана.
local ROW_HEIGHT = 36
local FRAME_WIDTH = 300
local MAIN_FOOTER_HEIGHT = 20
local MAX_ROLL_ROWS = 4
local ROLL_HEADER_HEIGHT = 20
local ROLL_ROW_HEIGHT = 50
local ROLL_FRAME_WIDTH = 420
local MAX_HISTORY_ROWS = 6
local HISTORY_ROW_HEIGHT = 34
local HISTORY_FOOTER_HEIGHT = 22
local HISTORY_LIFETIME = 22
local TEST_ROLL_ID = -2147483647
local LOOT_GLASS_TEXTURE = "Interface\\AddOns\\MythicBoost\\Media\\LootGlass.tga"
local LOOT_GLOW_TEXTURE = "Interface\\AddOns\\MythicBoost\\Media\\LootGlow.tga"
local BLIZZARD_LOOT_EVENTS = { "LOOT_OPENED", "LOOT_CLOSED", "LOOT_SLOT_CLEARED" }
local SETTINGS_DEFAULTS = { enabled = true, atCursor = true, showRolls = true, showHistory = true }

local function Settings()
    return JP.Settings("lootUI", SETTINGS_DEFAULTS) or {}
end

local function SafeValue(value, fallback)
    if issecretvalue(value) then return fallback end
    if value == nil then return fallback end
    return value
end

local function IsExternalFrameLoaded() return UI.IsAddOnLoaded("XLoot_Frame") end
local function IsExternalRollLoaded() return UI.IsAddOnLoaded("XLoot_Group") end
local function IsExternalMonitorLoaded() return UI.IsAddOnLoaded("XLoot_Monitor") end

local function QualityColor(quality, quest)
    if quest then return 1, .80, .16 end
    quality = tonumber(SafeValue(quality, 1)) or 1
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color then return color.r or 1, color.g or 1, color.b or 1 end
    return .78, .84, .92
end

local function ItemMeta(link, currencyID, quest, slotType)
    local moneyType = Enum and Enum.LootSlotType and Enum.LootSlotType.Money
    if slotType ~= nil and (slotType == moneyType or slotType == _G.LOOT_SLOT_MONEY) then
        return "", ""
    end
    if currencyID then return L("Валюта"), "" end
    if not link or type(GetItemInfo) ~= "function" then
        return quest and L("Задание") or L("Предмет"), ""
    end

    local ok, _, _, _, itemLevel, _, itemType, itemSubType, _, equipLoc,
        _, _, _, _, bindType = pcall(GetItemInfo, link)
    if not ok then return quest and L("Задание") or L("Предмет"), "" end

    itemType, itemSubType = SafeValue(itemType), SafeValue(itemSubType)
    equipLoc, itemLevel, bindType = SafeValue(equipLoc), SafeValue(itemLevel), SafeValue(bindType)
    -- INVTYPE_NON_EQUIP существует в игре, но равен пустой строке. Пустая
    -- строка в Lua истинна, поэтому хлам получал ведущую запятую (", Хлам")
    -- и бессмысленный уровень предмета. Носибельность определяет непустой
    -- перевод слота, а не сам факт наличия глобальной переменной.
    local equipText = type(equipLoc) == "string" and equipLoc ~= "" and _G[equipLoc] or nil
    if equipText == "" then equipText = nil end
    local detail
    if quest then
        detail = L("Задание")
    elseif equipText and itemSubType then
        detail = equipText .. ", " .. itemSubType
    else
        detail = itemSubType or itemType or L("Предмет")
    end
    if equipText and type(itemLevel) == "number" and itemLevel > 1 then
        detail = detail .. "  -  " .. itemLevel
    end

    local bindLabel = ""
    if bindType == (LE_ITEM_BIND_ON_ACQUIRE or 1) then
        bindLabel = L("БоП")
    elseif bindType == (LE_ITEM_BIND_ON_EQUIP or 2) then
        bindLabel = L("БоЕ")
    elseif bindType == (LE_ITEM_BIND_ON_USE or 3) then
        bindLabel = L("БоИ")
    end
    return detail, bindLabel
end

function LootUI:GetSlots()
    local slots = {}
    local count = type(GetNumLootItems) == "function" and GetNumLootItems() or 0
    count = tonumber(SafeValue(count, 0)) or 0
    for slot = 1, count do
        local ok, icon, name, quantity, currencyID, quality, locked, isQuestItem = pcall(GetLootSlotInfo, slot)
        if ok and (SafeValue(icon) or SafeValue(name)) then
            local slotType
            if type(GetLootSlotType) == "function" then
                local typeOK, result = pcall(GetLootSlotType, slot)
                if typeOK then slotType = SafeValue(result) end
            end
            local link
            if type(GetLootSlotLink) == "function" then
                local linkOK, result = pcall(GetLootSlotLink, slot)
                if linkOK then link = SafeValue(result) end
            end
            slots[#slots + 1] = {
                slot = slot,
                icon = SafeValue(icon, 134400),
                name = tostring(SafeValue(name, L("Добыча"))),
                quantity = tonumber(SafeValue(quantity, 1)) or 1,
                currencyID = SafeValue(currencyID),
                quality = SafeValue(quality, 1),
                locked = SafeValue(locked, false) == true,
                quest = SafeValue(isQuestItem, false) == true,
                link = link,
                slotType = slotType,
            }
            local data = slots[#slots]
            data.detail, data.bind = ItemMeta(link, data.currencyID, data.quest, data.slotType)
        end
    end
    return slots
end

function LootUI:SavePosition()
    if not self.frame or Settings().atCursor then return end
    local point, _, relativePoint, x, y = self.frame:GetPoint()
    if type(point) == "string" and type(x) == "number" and type(y) == "number" then
        Settings().position = { point = point, relativePoint = relativePoint, x = x, y = y }
    end
end

function LootUI:PlaceFrame()
    local frame, settings = self.frame, Settings()
    frame:ClearAllPoints()
    if settings.atCursor and type(GetCursorPosition) == "function" then
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + 14, y / scale - 14)
        return
    end
    local position = settings.position
    if type(position) == "table" and type(position.point) == "string"
        and type(position.x) == "number" and type(position.y) == "number" then
        frame:SetPoint(position.point, UIParent, position.relativePoint or position.point, position.x, position.y)
    else
        -- Запасное место, когда «у курсора» выключено и окно ещё не
        -- перетаскивали: нижняя полоса, а не центр игровой зоны.
        frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 330)
    end
end

function LootUI:TakeSlot(row)
    if not row or not row.slot or row.locked then return end
    if row.link and type(HandleModifiedItemClick) == "function" and HandleModifiedItemClick(row.link) then return end
    if type(LootSlot) == "function" then pcall(LootSlot, row.slot) end
end

function LootUI:Refresh()
    if not self.frame or not Settings().enabled or self.externalConflict then return end
    local slots = self:GetSlots()
    self.slots = slots
    if #slots == 0 then self.frame:Hide(); return end

    local maximumOffset = math.max(0, #slots - MAX_ROWS)
    self.scrollOffset = math.max(0, math.min(self.scrollOffset or 0, maximumOffset))
    local shown = math.min(MAX_ROWS, #slots)
    for index, row in ipairs(self.rows) do
        local data = slots[self.scrollOffset + index]
        if data then
            row.slot, row.link, row.locked = data.slot, data.link, data.locked
            row.icon:SetTexture(data.icon)
            row.name:SetText(data.name)
            row.detail:SetText(data.detail or "")
            row.bind:SetText(data.bind or "")
            row.count:SetText(data.quantity > 1 and ("×" .. data.quantity) or "")
            local r, g, b = QualityColor(data.quality, data.quest)
            local quality = tonumber(SafeValue(data.quality, 1)) or 1
            row:SetBackdropBorderColor(r, g, b, quality >= 2 and 1 or .70)
            row.name:SetTextColor(r, g, b, 1)
            -- Тот же цвет на контуре иконки, но приглушённее рамки строки:
            -- два одинаково ярких контура рядом читаются как один толстый.
            row.iconEdge:SetBackdropBorderColor(r * .90, g * .90, b * .90, .96)
            -- Заливка гаснет к правому краю: под названием фон обязан остаться
            -- тёмным, иначе светлый текст по светлому цвету качества пропадает.
            row.tint:SetGradient("HORIZONTAL",
                CreateColor(r, g, b, quality >= 2 and .18 or .025),
                CreateColor(r, g, b, quality >= 2 and .04 or 0))
            row.glowFrame:SetVertexColor(r, g, b, quality >= 2 and .30 or .04)
            row:SetAlpha(data.locked and .48 or 1)
            row:Show()
        else
            row.slot, row.link, row.locked = nil, nil, nil
            row:Hide()
        end
    end
    self.frame.counter:SetFormattedText("%d", #slots)
    if #slots > MAX_ROWS then
        self.frame.page:SetFormattedText(L("%d-%d / %d  -  колесо мыши"),
            self.scrollOffset + 1, math.min(#slots, self.scrollOffset + MAX_ROWS), #slots)
        self.frame.page:Show()
    else
        self.frame.page:Hide()
    end
    self.frame.title:SetShown(#slots <= MAX_ROWS)
    self.frame:SetHeight(4 + shown * ROW_HEIGHT + MAIN_FOOTER_HEIGHT)
end

function LootUI:ShowLoot()
    if not Settings().enabled then return end
    if IsExternalFrameLoaded() then
        self.externalConflict = true
        if not self.conflictReported then
            self.conflictReported = true
            JP:Print(L("Встроенное окно добычи не запущено: отключи XLoot_Frame и сделай /reload."))
        end
        return
    end
    self.externalConflict = nil
    self.scrollOffset = 0
    self:Refresh()
    if not self.slots or #self.slots == 0 then
        self.showAttempts = (self.showAttempts or 0) + 1
        if self.showAttempts <= 4 and C_Timer then
            C_Timer.After(.05, function()
                if LootUI.lootSessionOpen then LootUI:ShowLoot() end
            end)
        end
        return
    end
    self.showAttempts = 0
    self:PlaceFrame()
    self.frame:Show()
    local blizzard = _G.LootFrame
    if blizzard and self.blizzardLootSuppressed then blizzard:SetAlpha(0) end
end

function LootUI:ParkBlizzard()
    local frame = _G.LootFrame
    if not frame then return end
    self.blizzardLootEventState = self.blizzardLootEventState or {}
    if not frame.__mbLootHook then
        frame.__mbLootHook = true
        frame:HookScript("OnShow", function(owner)
            if LootUI.blizzardLootSuppressed then
                owner:SetAlpha(0)
                owner:EnableMouse(false)
            end
        end)
    end
    if self.blizzardLootSuppressed then return end
    self.blizzardLootSuppressed = true
    self.blizzardLootAlpha = frame:GetAlpha()
    self.blizzardLootMouse = frame:IsMouseEnabled()
    for _, event in ipairs(BLIZZARD_LOOT_EVENTS) do
        local registered = type(frame.IsEventRegistered) == "function" and frame:IsEventRegistered(event)
        self.blizzardLootEventState[event] = registered == true
        if registered then frame:UnregisterEvent(event) end
    end
    if frame:IsShown() then
        frame:SetAlpha(0)
        frame:EnableMouse(false)
    end
end

function LootUI:RestoreBlizzard()
    local frame = _G.LootFrame
    if not frame or not self.blizzardLootSuppressed then return end
    self.blizzardLootSuppressed = nil
    for _, event in ipairs(BLIZZARD_LOOT_EVENTS) do
        if self.blizzardLootEventState and self.blizzardLootEventState[event] then frame:RegisterEvent(event) end
    end
    frame:SetAlpha(self.blizzardLootAlpha or 1)
    frame:EnableMouse(self.blizzardLootMouse ~= false)
    wipe(self.blizzardLootEventState or {})
end

local function HideDefaultRollFrame(frame)
    if not frame or not LootUI.blizzardRollsSuppressed or frame.__mbRollHideActive then return end
    frame.__mbRollHideActive = true
    pcall(frame.Hide, frame)
    if _G.GroupLootContainer and type(_G.GroupLootContainer_RemoveFrame) == "function" then
        pcall(_G.GroupLootContainer_RemoveFrame, _G.GroupLootContainer, frame)
    end
    frame.__mbRollHideActive = nil
end

function LootUI:SuppressBlizzardRolls()
    if Settings().showRolls == false or IsExternalRollLoaded() then return end
    if not self.blizzardRollsSuppressed then
        self.blizzardRollsSuppressed = true
        self.blizzardRollEventState = self.blizzardRollEventState or {}
        for _, event in ipairs({ "START_LOOT_ROLL", "CANCEL_LOOT_ROLL" }) do
            local registered = type(UIParent.IsEventRegistered) == "function" and UIParent:IsEventRegistered(event)
            self.blizzardRollEventState[event] = registered == true
            if registered then UIParent:UnregisterEvent(event) end
        end
    end
    for index = 1, (_G.NUM_GROUP_LOOT_FRAMES or 4) do
        local frame = _G["GroupLootFrame" .. index]
        if frame then
            if not frame.__mbRollHook then
                frame.__mbRollHook = true
                hooksecurefunc(frame, "Show", HideDefaultRollFrame)
            end
            HideDefaultRollFrame(frame)
        end
    end
end

function LootUI:RestoreBlizzardRolls()
    if not self.blizzardRollsSuppressed then return end
    self.blizzardRollsSuppressed = nil
    for _, event in ipairs({ "START_LOOT_ROLL", "CANCEL_LOOT_ROLL" }) do
        if self.blizzardRollEventState and self.blizzardRollEventState[event] then UIParent:RegisterEvent(event) end
    end
    wipe(self.blizzardRollEventState or {})
end

function LootUI:BuildRow(index)
    local row = CreateFrame("Button", nil, self.frame, "BackdropTemplate")
    row:SetHeight(34)
    row:SetPoint("TOPLEFT", 2, -2 - (index - 1) * ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", -2, -2 - (index - 1) * ROW_HEIGHT)
    row:RegisterForClicks("AnyUp")
    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    row.baseAlpha = .98
    row:SetBackdropColor(C.surface[1], C.surface[2], C.surface[3], row.baseAlpha)

    -- Оригинальная AI-текстура MythicBoost: тёмное стекло без заимствованных
    -- файлов XLoot. Растягивается по строке и сохраняет читаемый правый край.
    row.glass = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.glass:SetPoint("TOPLEFT", 1, -1)
    row.glass:SetPoint("BOTTOMRIGHT", -1, 1)
    row.glass:SetTexture(LOOT_GLASS_TEXTURE)
    row.glass:SetVertexColor(.40, .46, .52, .82)

    row.glowFrame = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    row.glowFrame:SetPoint("TOPLEFT", -1, 1)
    row.glowFrame:SetPoint("BOTTOMRIGHT", 1, -1)
    row.glowFrame:SetTexture(LOOT_GLOW_TEXTURE)
    row.glowFrame:SetBlendMode("ADD")

    -- Главная примета XLoot: цвет качества не только на рамке, но и заливкой,
    -- утекающей от левого края в темноту. Именно она позволяет опознать
    -- редкость боковым зрением, не читая название.
    row.tint = row:CreateTexture(nil, "BORDER")
    row.tint:SetPoint("TOPLEFT", 1, -1)
    row.tint:SetPoint("BOTTOMLEFT", 1, 1)
    row.tint:SetPoint("BOTTOMRIGHT", -1, 1)
    row.tint:SetColorTexture(1, 1, 1, 1)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("TOPLEFT", 2, -2)
    row.icon:SetPoint("BOTTOMLEFT", 2, 2)
    row.icon:SetWidth(30)
    row.icon:SetTexCoord(.07, .93, .07, .93)

    -- Подпись XLoot: цвет качества стоит не только на рамке строки, но и
    -- тонким контуром вокруг самой иконки. Так вещь опознаётся по краю
    -- значка, даже когда взгляд не дошёл до названия.
    row.iconEdge = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.iconEdge:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -1, 1)
    row.iconEdge:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 1, -1)
    row.iconEdge:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })

    row.name = UI.Text(row, "GameFontNormal", "")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
    row.name:SetPoint("TOPRIGHT", -5, -1)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.detail = UI.Text(row, "GameFontNormalSmall", "", { 1, .84, 0, 1 })
    row.detail:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -17)
    row.detail:SetPoint("TOPRIGHT", row, "TOPRIGHT", -5, -17)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(false)

    row.bind = UI.Text(row, "GameFontNormalSmall", "", C.amber)
    row.bind:SetPoint("TOPLEFT", row.icon, "TOPLEFT", 1, -1)
    row.bind:SetShadowColor(0, 0, 0, 1)
    row.bind:SetShadowOffset(1, -1)

    -- Количество у XLoot лежит В УГЛУ ИКОНКИ, а не отдельной колонкой справа:
    -- колонка съедала ширину у названия ради числа, которое почти всегда пустое.
    row.count = UI.Text(row, "GameFontNormalSmall", "", C.text)
    row.count:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 1, -1)
    row.count:SetJustifyH("RIGHT")
    row.count:SetShadowColor(0, 0, 0, 1)
    row.count:SetShadowOffset(1, -1)
    row:SetScript("OnClick", function(owner) LootUI:TakeSlot(owner) end)
    row:SetScript("OnEnter", function(owner)
        -- Подсветку даём всегда, даже когда слот пуст: строка кликабельна, и
        -- она обязана отзываться на курсор, иначе список кажется неживым.
        owner:SetBackdropColor(.08, .08, .08, 1)
        if not owner.slot then return end
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        local ok = type(GameTooltip.SetLootItem) == "function"
            and pcall(GameTooltip.SetLootItem, GameTooltip, owner.slot)
        if not ok and owner.link then GameTooltip:SetHyperlink(owner.link) end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(owner)
        owner:SetBackdropColor(C.surface[1], C.surface[2], C.surface[3], owner.baseAlpha or .96)
        GameTooltip_Hide()
    end)
    self.rows[index] = row
end

local function SaveAuxiliaryPosition(frame, key)
    if not frame then return end
    local point, _, relativePoint, x, y = frame:GetPoint()
    if type(point) == "string" and type(x) == "number" and type(y) == "number" then
        Settings()[key] = { point = point, relativePoint = relativePoint, x = x, y = y }
    end
end

local function PlaceAuxiliaryFrame(frame, key, defaultPoint, defaultX, defaultY)
    frame:ClearAllPoints()
    local position = Settings()[key]
    if type(position) == "table" and type(position.point) == "string"
        and type(position.x) == "number" and type(position.y) == "number" then
        frame:SetPoint(position.point, UIParent, position.relativePoint or position.point, position.x, position.y)
    else
        frame:SetPoint(defaultPoint, UIParent, defaultPoint, defaultX, defaultY)
    end
end

local function BuildAuxiliaryHeader(frame, title, positionKey, height)
    height = height or 25
    frame.header = CreateFrame("Button", nil, frame, "BackdropTemplate")
    frame.header:SetPoint("TOPLEFT", 1, -1)
    frame.header:SetPoint("TOPRIGHT", -1, -1)
    frame.header:SetHeight(height)
    frame.header:RegisterForDrag("LeftButton")
    frame.header:SetScript("OnDragStart", function()
        if MythicBoostDB.interfaceUnlocked or frame.testMoveUnlocked then frame:StartMoving() end
    end)
    frame.header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SaveAuxiliaryPosition(frame, positionKey)
    end)
    frame.title = UI.Text(frame.header, "GameFontNormal", title, C.accent)
    frame.title:SetPoint("LEFT", 8, 0)
    frame.line = UI.Line(frame, C.accent)
    frame.line:SetPoint("TOPLEFT", 1, -height)
    frame.line:SetPoint("TOPRIGHT", -1, -height)
end

local ROLL_CHOICE_TEXTURES = {
    [0] = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
    [1] = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",
    [2] = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
    [3] = "Interface\\Buttons\\UI-GroupLoot-DE-Up",
    [4] = "Interface\\MINIMAP\\TRACKING\\Transmogrifier",
}

local ROLL_CHOICE_COLORS = {
    [0] = { .48, .54, .62 },
    [1] = { .22, .92, .48 },
    [2] = { 1.00, .72, .16 },
    [3] = { .72, .32, 1.00 },
    [4] = { .18, .78, 1.00 },
}

local function BuildRollChoice(row, label, rollType)
    local button = CreateFrame("Button", nil, row, "BackdropTemplate")
    button:SetSize(24, 24)
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    local choiceColor = ROLL_CHOICE_COLORS[rollType] or ROLL_CHOICE_COLORS[0]
    button:SetBackdropColor(choiceColor[1] * .08, choiceColor[2] * .08, choiceColor[3] * .08, .98)
    button:SetBackdropBorderColor(choiceColor[1], choiceColor[2], choiceColor[3], .82)
    button.glass = button:CreateTexture(nil, "BACKGROUND", nil, 2)
    button.glass:SetPoint("TOPLEFT", 1, -1); button.glass:SetPoint("BOTTOMRIGHT", -1, 1)
    button.glass:SetColorTexture(1, 1, 1, 1)
    button.glass:SetGradient("VERTICAL",
        CreateColor(choiceColor[1] * .18, choiceColor[2] * .18, choiceColor[3] * .18, .14),
        CreateColor(choiceColor[1], choiceColor[2], choiceColor[3], .34))
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 2, -2)
    button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    button.icon:SetTexture(ROLL_CHOICE_TEXTURES[rollType])
    button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
    button.highlight:SetAllPoints(button.icon)
    button.highlight:SetColorTexture(choiceColor[1], choiceColor[2], choiceColor[3], .34)
    button.rollType = rollType
    button.choiceLabel = label
    button:SetFrameLevel(row:GetFrameLevel() + 4)
    button:SetScript("OnEnter", function(owner)
        owner:SetBackdropBorderColor(choiceColor[1], choiceColor[2], choiceColor[3], 1)
        GameTooltip:SetOwner(owner, "ANCHOR_TOP")
        GameTooltip:SetText(owner.choiceLabel)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(owner)
        owner:SetBackdropBorderColor(choiceColor[1], choiceColor[2], choiceColor[3], .82)
        GameTooltip_Hide()
    end)
    button:SetScript("OnClick", function(owner)
        if not row.rollID or row.selectionMade then return end
        -- A preview roll is local-only: it exercises layout and choice states
        -- but must never call Blizzard's protected loot API.
        local ok = row.testRoll == true
            or (type(RollOnLoot) == "function" and pcall(RollOnLoot, row.rollID, owner.rollType))
        if not ok then return end
        row.selectionMade = owner.rollType
        if LootUI.rolls and LootUI.rolls[row.rollID] then
            LootUI.rolls[row.rollID].selected = owner.rollType
        end
        for _, choice in ipairs(row.choices) do
            choice:SetEnabled(false)
            choice:SetAlpha(choice == owner and 1 or .32)
        end
        row.result:SetText(owner.choiceLabel)
        row.result:Show()
        if row.testRoll == true and C_Timer then
            C_Timer.After(.35, function()
                if row.rollID == TEST_ROLL_ID then LootUI:RemoveRoll(TEST_ROLL_ID) end
            end)
        end
    end)
    row.choices[#row.choices + 1] = button
    return button
end

function LootUI:BuildRollRow(index)
    local row = CreateFrame("Button", nil, self.rollFrame, "BackdropTemplate")
    row:SetHeight(46)
    row:SetPoint("TOPLEFT", 5, -(ROLL_HEADER_HEIGHT + 3) - (index - 1) * ROLL_ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", -5, -(ROLL_HEADER_HEIGHT + 3) - (index - 1) * ROLL_ROW_HEIGHT)
    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    row:SetBackdropColor(.004, .007, .011, .98)
    row.qualityWash = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.qualityWash:SetPoint("TOPLEFT", 1, -1); row.qualityWash:SetPoint("BOTTOMRIGHT", -1, 1)
    row.qualityWash:SetColorTexture(1, 1, 1, 1)
    row.glassTop = row:CreateTexture(nil, "ARTWORK", nil, 1)
    row.glassTop:SetPoint("TOPLEFT", 1, -1); row.glassTop:SetPoint("TOPRIGHT", -1, -1)
    row.glassTop:SetHeight(20)
    row.glassTop:SetColorTexture(1, 1, 1, 1)
    row.glassTop:SetGradient("VERTICAL",
        CreateColor(.55, .70, .84, 0), CreateColor(.88, .95, 1, .16))
    row.qualityEdge = row:CreateTexture(nil, "OVERLAY", nil, 1)
    row.qualityEdge:SetPoint("TOPLEFT", 1, -1); row.qualityEdge:SetPoint("BOTTOMLEFT", 1, 3)
    row.qualityEdge:SetWidth(3)
    row.progress = CreateFrame("StatusBar", nil, row)
    row.progress:SetPoint("BOTTOMLEFT", 1, 1)
    row.progress:SetPoint("BOTTOMRIGHT", -1, 1)
    row.progress:SetHeight(3)
    row.progress:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    row.progress:SetStatusBarColor(C.accent[1], C.accent[2], C.accent[3], .90)
    row.progress:SetFrameLevel(row:GetFrameLevel())
    row.iconFrame = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.iconFrame:SetPoint("TOPLEFT", 5, -4); row.iconFrame:SetSize(39, 39)
    row.iconFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    row.iconFrame:SetBackdropColor(.01, .014, .020, .98)
    row.icon = row.iconFrame:CreateTexture(nil, "ARTWORK", nil, 3)
    row.icon:SetPoint("TOPLEFT", 2, -2); row.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    row.icon:SetTexCoord(.07, .93, .07, .93)
    row.name = UI.Text(row, "GameFontNormal", "", C.text)
    row.name:SetPoint("TOPLEFT", row.iconFrame, "TOPRIGHT", 8, 0)
    row.name:SetPoint("RIGHT", -54, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.timerPanel = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.timerPanel:SetPoint("TOPRIGHT", -5, -4); row.timerPanel:SetSize(43, 20)
    row.timerPanel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    row.timerPanel:SetBackdropColor(.025, .035, .050, .90)
    row.timer = UI.Text(row.timerPanel, "GameFontNormal", "", C.text)
    row.timer:SetPoint("CENTER")
    row.timer:SetJustifyH("CENTER")
    row.result = UI.Text(row, "GameFontNormalSmall", "", C.accent)
    row.result:SetPoint("BOTTOMRIGHT", -6, 5)
    row.result:Hide()
    row.choices = {}
    BuildRollChoice(row, L("НУЖНО"), 1)
    BuildRollChoice(row, L("ХОЧУ"), 2)
    BuildRollChoice(row, L("РАСПЫЛ."), 3)
    BuildRollChoice(row, L("ОБЛИК"), 4)
    BuildRollChoice(row, L("ПАС"), 0)
    row:SetScript("OnEnter", function(owner)
        if owner.link then
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(owner.link)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", function(owner)
        if owner.link and type(HandleModifiedItemClick) == "function" then HandleModifiedItemClick(owner.link) end
    end)
    self.rollRows[index] = row
end

function LootUI:RefreshRolls()
    if not self.rollFrame then return end
    local settings = Settings()
    if not settings.showRolls then self.rollFrame:Hide(); return end
    local active = {}
    for _, data in pairs(self.rolls or {}) do active[#active + 1] = data end
    table.sort(active, function(a, b)
        if a.test ~= b.test then return a.test == true end
        return (a.deadline or 0) < (b.deadline or 0)
    end)
    for index, row in ipairs(self.rollRows) do
        local data = active[index]
        if data then
            row.rollID, row.link, row.selectionMade = data.rollID, data.link, data.selected
            row.testRoll = data.test == true
            row.icon:SetTexture(data.icon)
            row.name:SetText((data.count or 1) > 1 and (data.name .. "  ×" .. data.count) or data.name)
            row.progress:SetMinMaxValues(0, math.max(.1, data.duration or 1))
            local r, g, b = QualityColor(data.quality)
            row:SetBackdropBorderColor(r, g, b, .96)
            row:SetBackdropColor(r * .025, g * .025, b * .025, .98)
            row.qualityWash:SetGradient("HORIZONTAL",
                CreateColor(r, g, b, .22), CreateColor(r, g, b, .015))
            row.qualityEdge:SetColorTexture(r, g, b, .98)
            row.iconFrame:SetBackdropBorderColor(r, g, b, 1)
            row.timerPanel:SetBackdropBorderColor(r, g, b, .72)
            row.progress:SetStatusBarColor(r, g, b, .96)
            row.name:SetTextColor(r, g, b, 1)
            -- Права на бросок приходят от API и могут быть защищёнными, а
            -- сравнивать такое значение нельзя. Снимаем защиту сразу здесь,
            -- чтобы ниже сравнение шло с обычным булевым.
            local availability = {
                SafeValue(data.canNeed, false), SafeValue(data.canGreed, false),
                SafeValue(data.canDisenchant, false), SafeValue(data.canTransmog, false), true,
            }
            local visibleChoices = {}
            for choiceIndex, choice in ipairs(row.choices) do
                choice:SetShown(availability[choiceIndex] == true)
                choice:SetEnabled(not data.selected)
                choice:SetAlpha(data.selected and (data.selected == choice.rollType and 1 or .32) or 1)
                if availability[choiceIndex] == true then visibleChoices[#visibleChoices + 1] = choice end
                if data.selected == choice.rollType then row.result:SetText(choice.choiceLabel) end
            end
            local choiceWidth, choiceGap = 24, 1
            for choiceIndex, choice in ipairs(visibleChoices) do
                choice:SetSize(choiceWidth, choiceWidth)
                choice:ClearAllPoints()
                choice:SetPoint("BOTTOMLEFT", row.iconFrame, "BOTTOMRIGHT",
                    8 + (choiceIndex - 1) * (choiceWidth + choiceGap), 0)
            end
            row.result:SetShown(data.selected ~= nil)
            row:Show()
        else
            row.rollID, row.link, row.selectionMade, row.testRoll = nil, nil, nil, nil
            row:Hide()
        end
    end
    local shown = math.min(#active, MAX_ROLL_ROWS)
    self.rollFrame:SetHeight(ROLL_HEADER_HEIGHT + 6 + shown * ROLL_ROW_HEIGHT)
    self.rollFrame:SetShown(shown > 0)
end

function LootUI:ShowTestRoll()
    local settings = Settings()
    if settings.enabled == false or settings.showRolls == false then
        JP:Print(L("Сначала включи встроенное окно добычи и голосование за групповую добычу."))
        return false
    end
    self:Create()
    self.rolls = self.rolls or {}
    local duration = 300
    self.rolls[TEST_ROLL_ID] = {
        rollID = TEST_ROLL_ID,
        test = true,
        icon = 134400,
        name = L("Тестовый предмет — перетащи заголовок"),
        count = 1,
        quality = 4,
        canNeed = true,
        canGreed = true,
        canDisenchant = true,
        canTransmog = true,
        duration = duration,
        deadline = GetTime() + duration,
    }
    self.rollFrame.testMoveUnlocked = true
    self:RefreshRolls()
    return true
end

function LootUI:StartRoll(rollID, rollTime)
    if not Settings().showRolls or IsExternalRollLoaded() or type(GetLootRollItemInfo) ~= "function" then return end
    local result = { pcall(GetLootRollItemInfo, rollID) }
    if not result[1] then return end
    if issecretvalue(result[3]) then return end
    if not result[3] then
        self.pendingRollAttempts = self.pendingRollAttempts or {}
        local attempt = (self.pendingRollAttempts[rollID] or 0) + 1
        self.pendingRollAttempts[rollID] = attempt
        if attempt <= 5 and C_Timer then
            C_Timer.After(.12, function()
                local remaining = type(GetLootRollTimeLeft) == "function" and GetLootRollTimeLeft(rollID) or 0
                if tonumber(SafeValue(remaining, 0)) > 0 then LootUI:StartRoll(rollID, remaining) end
            end)
        end
        return
    end
    if self.pendingRollAttempts then self.pendingRollAttempts[rollID] = nil end
    local link
    if type(GetLootRollItemLink) == "function" then
        local ok, value = pcall(GetLootRollItemLink, rollID)
        if ok then link = SafeValue(value) end
    end
    local duration = math.max(.1, (tonumber(SafeValue(rollTime, 0)) or 0) / 1000)
    self.rolls = self.rolls or {}
    self.rolls[rollID] = {
        rollID = rollID,
        icon = SafeValue(result[2], 134400),
        name = tostring(SafeValue(result[3], link or L("Предмет"))),
        count = tonumber(SafeValue(result[4], 1)) or 1,
        quality = SafeValue(result[5], 1),
        canNeed = SafeValue(result[7], false) == true,
        canGreed = SafeValue(result[8], false) == true,
        canDisenchant = SafeValue(result[9], false) == true,
        canTransmog = SafeValue(result[14], false) == true,
        link = link,
        duration = duration,
        deadline = GetTime() + duration,
    }
    self:RefreshRolls()
end

function LootUI:RecoverRolls()
    if not Settings().showRolls or IsExternalRollLoaded() or type(GetLootRollTimeLeft) ~= "function" then return end
    for rollID = 1, 200 do
        local ok, remaining = pcall(GetLootRollTimeLeft, rollID)
        remaining = ok and tonumber(SafeValue(remaining, 0)) or 0
        if remaining and remaining > 0 then self:StartRoll(rollID, remaining) end
    end
end

function LootUI:RemoveRoll(rollID)
    if self.rolls then self.rolls[rollID] = nil end
    if self.pendingRollAttempts then self.pendingRollAttempts[rollID] = nil end
    if rollID == TEST_ROLL_ID and self.rollFrame then self.rollFrame.testMoveUnlocked = nil end
    self:RefreshRolls()
end

function LootUI:UpdateRollTimers(elapsed)
    self.rollElapsed = (self.rollElapsed or 0) + elapsed
    if self.rollElapsed < .08 then return end
    self.rollElapsed = 0
    local now, expired = GetTime(), {}
    for _, row in ipairs(self.rollRows or {}) do
        if row:IsShown() and row.rollID and self.rolls[row.rollID] then
            local data = self.rolls[row.rollID]
            local remaining = math.max(0, (data.deadline or now) - now)
            row.progress:SetValue(remaining)
            row.timer:SetFormattedText(remaining < 10 and "%.1f" or "%d", remaining)
            local ratio = remaining / math.max(.1, data.duration or 1)
            local glassWave = .68 + .18 * math.sin(now * 2.4 + (row.rollID or 0) % 7)
            row.glassTop:SetAlpha(glassWave)
            row.qualityWash:SetAlpha(.82 + .12 * math.sin(now * 1.7))
            if ratio > .45 then row.timer:SetTextColor(.90, .96, 1, 1)
            elseif ratio > .18 then row.timer:SetTextColor(1, .72, .18, 1)
            else row.timer:SetTextColor(1, .24, .18, 1) end
            if remaining <= 0 then expired[#expired + 1] = row.rollID end
        end
    end
    for _, rollID in ipairs(expired) do self:RemoveRoll(rollID) end
end

-- Панель показывает ТОЛЬКО то, чего нет в окне добычи: броски участников
-- и чужую добычу. Свои подборы (LOOT_ITEM_SELF и родня) убраны
-- нарочно: они дублировали список, который игрок только что видел.
local LOOT_AWARD_FORMATS = {
    -- Кто сколько выкинул и на что.
    "LOOT_ROLL_ROLLED_NEED", "LOOT_ROLL_ROLLED_GREED",
    "LOOT_ROLL_ROLLED_DE", "LOOT_ROLL_ROLLED_TRANSMOG",
    "LOOT_ROLL_ROLLED_NEED_ROLE_BONUS", "LOOT_ROLL_ROLLED_GREED_ROLE_BONUS",
    -- Итог броска.
    "LOOT_ROLL_WON", "LOOT_ROLL_YOU_WON",
    "LOOT_ROLL_PASSED", "LOOT_ROLL_ALL_PASSED",
    -- Добыча ДРУГИХ игроков: LOOT_ITEM без суффикса _SELF — это
    -- чужой подбор, и в группе его видеть полезно.
    "LOOT_ITEM", "LOOT_ITEM_MULTIPLE",
    -- Собственная добыча нужна именно в мониторе: основное окно закрывается
    -- сразу после подбора, а короткая история остаётся ещё несколько секунд.
    "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE",
    "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE",
    "LOOT_ITEM_CREATED_SELF", "LOOT_ITEM_CREATED_SELF_MULTIPLE",
}

local OWN_LOOT_FORMATS = {
    "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE",
    "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE",
    "LOOT_ITEM_CREATED_SELF", "LOOT_ITEM_CREATED_SELF_MULTIPLE",
}

local function MatchesGlobalFormat(message, format)
    if type(format) ~= "string" then return false end
    local pattern = format:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    pattern = pattern:gsub("%%%%", "\001")
    pattern = pattern:gsub("%%%d+%$s", "\002")
    pattern = pattern:gsub("%%%d+%$d", "\003")
    pattern = pattern:gsub("%%s", ".-")
    pattern = pattern:gsub("%%d", "%%d+")
    pattern = pattern:gsub("\002", ".-")
    pattern = pattern:gsub("\003", "%%d+")
    pattern = pattern:gsub("\001", "%%%%")
    return message:match("^" .. pattern .. "$") ~= nil
end

local function IsLootAwardMessage(message)
    for _, globalName in ipairs(LOOT_AWARD_FORMATS) do
        if MatchesGlobalFormat(message, _G[globalName]) then return true end
    end
    return false
end

local function IsOwnLootMessage(message)
    for _, globalName in ipairs(OWN_LOOT_FORMATS) do
        if MatchesGlobalFormat(message, _G[globalName]) then return true end
    end
    return false
end

function LootUI:AddHistoryMessage(message, event)
    if not Settings().showHistory or IsExternalMonitorLoaded() or type(message) ~= "string"
        or issecretvalue(message) then return end
    local itemLink = message:match("(|c%x+|Hitem:.-|h%[.-%]|h|r)")
        or message:match("(|Hitem:.-|h%[.-%]|h)")
    local currencyLink = message:match("(|c%x+|Hcurrency:.-|h%[.-%]|h|r)")
        or message:match("(|Hcurrency:.-|h%[.-%]|h)")
    if event == "CHAT_MSG_LOOT" and (not itemLink or not IsLootAwardMessage(message)) then return end
    if event == "CHAT_MSG_CURRENCY" and not currencyLink then return end
    if event ~= "CHAT_MSG_LOOT" and event ~= "CHAT_MSG_MONEY" and event ~= "CHAT_MSG_CURRENCY" then return end

    local link = itemLink or currencyLink
    local icon = event == "CHAT_MSG_MONEY" and 133784 or 134400
    local quality = 1
    if itemLink then
        local itemInfoInstant = C_Item and C_Item.GetItemInfoInstant or _G.GetItemInfoInstant
        if type(itemInfoInstant) == "function" then
            local ok, _, _, _, _, texture = pcall(itemInfoInstant, itemLink)
            if ok then icon = SafeValue(texture, icon) end
        end
        local itemInfo = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
        if type(itemInfo) == "function" then
            local ok, _, _, itemQuality = pcall(itemInfo, itemLink)
            if ok then quality = SafeValue(itemQuality, quality) end
        end
    elseif currencyLink and C_CurrencyInfo and type(C_CurrencyInfo.GetCurrencyInfoFromLink) == "function" then
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfoFromLink, currencyLink)
        if ok and type(info) == "table" then icon = SafeValue(info.iconFileID, icon) end
    end
    local displayMessage = message
    if event == "CHAT_MSG_LOOT" and itemLink and IsOwnLootMessage(message) then
        -- Системный текст «Ваша добыча: …» в компактной строке только
        -- повторяет очевидное. Цветная ссылка уже содержит имя и качество.
        displayMessage = itemLink
    end
    self.history = self.history or {}
    table.insert(self.history, 1, {
        message = displayMessage, link = link, icon = icon, quality = quality,
        expires = GetTime() + HISTORY_LIFETIME,
    })
    while #self.history > MAX_HISTORY_ROWS do table.remove(self.history) end
    self:RefreshHistory()
    self:ScheduleHistoryExpiry()
end

-- Loot chat can arrive in large bursts.  A timer per message survived for the
-- full 22-second lifetime even though the monitor retains at most six rows.
-- Keep one timer aimed at the oldest visible expiry and reschedule only after
-- it fires; memory and callback count are therefore bounded by one.
function LootUI:ScheduleHistoryExpiry()
    if self.historyExpiryQueued or not C_Timer or type(C_Timer.After) ~= "function" then return end
    local nextExpiry
    for _, entry in ipairs(self.history or {}) do
        local expires = tonumber(entry.expires)
        if expires and (not nextExpiry or expires < nextExpiry) then nextExpiry = expires end
    end
    if not nextExpiry then return end
    self.historyExpiryQueued = true
    C_Timer.After(math.max(.1, nextExpiry - GetTime() + .1), function()
        LootUI.historyExpiryQueued = nil
        LootUI:RefreshHistory()
        if Settings().showHistory then LootUI:ScheduleHistoryExpiry() end
    end)
end

function LootUI:RefreshHistory()
    if not self.historyFrame then return end
    if not Settings().showHistory then self.historyFrame:Hide(); return end
    self.history = self.history or {}
    local display = self.monitorPreview or self.history
    local now = GetTime()
    if not self.monitorPreview then
        for index = #self.history, 1, -1 do
            if (self.history[index].expires or 0) <= now then table.remove(self.history, index) end
        end
    end
    local maximumWidth = 220
    for index, row in ipairs(self.historyRows) do
        local data = display[index]
        if data then
            row.link = data.link
            row.icon:SetTexture(data.icon)
            row.text:SetText(data.message)
            local r, g, b = QualityColor(data.quality)
            row:SetBackdropBorderColor(r, g, b, .90)
            row.glow:SetVertexColor(r, g, b, (data.quality or 1) >= 2 and .26 or .04)
            local textWidth = type(row.text.GetStringWidth) == "function" and row.text:GetStringWidth() or 180
            local rowWidth = math.max(150, math.min(430, 48 + (textWidth or 180)))
            row:SetWidth(rowWidth)
            maximumWidth = math.max(maximumWidth, rowWidth)
            row:Show()
        else
            row.link = nil
            row:Hide()
        end
    end
    local shown = math.min(#display, MAX_HISTORY_ROWS)
    self.historyFrame:SetWidth(maximumWidth)
    self.historyFrame:SetHeight(HISTORY_FOOTER_HEIGHT + 4 + shown * HISTORY_ROW_HEIGHT)
    self.historyFrame:SetShown(shown > 0)
end

function LootUI:SetUnlocked(unlocked)
    if not self.frame then self:Create() end
    if not self.historyFrame then return end
    self.historyFrame.testMoveUnlocked = unlocked == true
    if unlocked and Settings().showHistory ~= false then
        self.monitorPreview = {
            { message = (type(GetMoneyString) == "function" and GetMoneyString(71261) or "7 Gold 12 Silver 61 Copper"), icon = 133784, quality = 1 },
            { message = L("Игрок") .. "  [" .. L("Тестовый предмет") .. "]", icon = 134400, quality = 4 },
            { message = "[" .. L("Добыча") .. "]  ×15", icon = 463447, quality = 2 },
        }
    else
        self.monitorPreview = nil
    end
    self:RefreshHistory()
end

function LootUI:BuildAuxiliaryFrames()
    local rollFrame = CreateFrame("Frame", "MythicBoostLootRollFrame", UIParent, "BackdropTemplate")
    rollFrame:SetSize(ROLL_FRAME_WIDTH, ROLL_HEADER_HEIGHT + 6 + ROLL_ROW_HEIGHT)
    rollFrame:SetFrameStrata("DIALOG")
    rollFrame:SetClampedToScreen(true)
    rollFrame:SetMovable(true)
    UI.Backdrop(rollFrame, C.surface, C.surfaceEdge)
    BuildAuxiliaryHeader(rollFrame, L("БРОСКИ ГРУППЫ"), "rollPosition", ROLL_HEADER_HEIGHT)
    UI.Backdrop(rollFrame.header, C.raised, C.surfaceEdge)
    rollFrame.headerGlass = rollFrame.header:CreateTexture(nil, "ARTWORK", nil, 1)
    rollFrame.headerGlass:SetPoint("TOPLEFT", 1, -1); rollFrame.headerGlass:SetPoint("BOTTOMRIGHT", -1, 1)
    rollFrame.headerGlass:SetColorTexture(1, 1, 1, 1)
    rollFrame.headerGlass:SetGradient("HORIZONTAL",
        CreateColor(C.accent[1], C.accent[2], C.accent[3], .20),
        CreateColor(C.amber[1], C.amber[2], C.amber[3], .06))
    rollFrame.close = UI.CloseButton(rollFrame)
    rollFrame.close:SetSize(18, 18)
    rollFrame.close:SetPoint("TOPRIGHT", -1, -1)
    rollFrame.close:SetScript("OnClick", function()
        if LootUI.rolls and LootUI.rolls[TEST_ROLL_ID] then LootUI:RemoveRoll(TEST_ROLL_ID) end
        rollFrame:Hide()
    end)
    -- Над кастбаром: тот стоит на BOTTOM 250, и на 260 окна перекрывались.
    PlaceAuxiliaryFrame(rollFrame, "rollPosition", "BOTTOM", 0, 330)
    self.rollFrame, self.rollRows, self.rolls = rollFrame, {}, {}
    for index = 1, MAX_ROLL_ROWS do self:BuildRollRow(index) end
    rollFrame:SetScript("OnUpdate", function(_, elapsed) LootUI:UpdateRollTimers(elapsed) end)
    rollFrame:Hide()

    local historyFrame = CreateFrame("Frame", "MythicBoostLootHistoryFrame", UIParent)
    historyFrame:SetSize(300, 96)
    historyFrame:SetFrameStrata("HIGH")
    historyFrame:SetClampedToScreen(true)
    historyFrame:SetMovable(true)
    -- Монитор — не большое окно, а стопка отдельных коротких строк. Нижняя
    -- плашка остаётся на месте, новые записи растут вверх как в старых UI.
    historyFrame.header = CreateFrame("Button", nil, historyFrame, "BackdropTemplate")
    historyFrame.header:SetPoint("BOTTOMLEFT", 0, 0)
    historyFrame.header:SetPoint("BOTTOMRIGHT", 0, 0)
    historyFrame.header:SetHeight(HISTORY_FOOTER_HEIGHT)
    historyFrame.header:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    historyFrame.header:SetBackdropColor(.018, .014, .009, .96)
    historyFrame.header:SetBackdropBorderColor(.34, .25, .08, .92)
    historyFrame.header:RegisterForDrag("LeftButton")
    historyFrame.header:SetScript("OnDragStart", function()
        if MythicBoostDB.interfaceUnlocked or historyFrame.testMoveUnlocked then historyFrame:StartMoving() end
    end)
    historyFrame.header:SetScript("OnDragStop", function()
        historyFrame:StopMovingOrSizing()
        SaveAuxiliaryPosition(historyFrame, "historyPosition")
    end)
    historyFrame.header.glass = historyFrame.header:CreateTexture(nil, "BACKGROUND")
    historyFrame.header.glass:SetAllPoints()
    historyFrame.header.glass:SetTexture(LOOT_GLASS_TEXTURE)
    historyFrame.header.glass:SetVertexColor(.42, .34, .18, .54)
    historyFrame.title = UI.Text(historyFrame.header, "GameFontNormalSmall", L("МОНИТОР ДОБЫЧИ"), { 1, .78, .10, 1 })
    historyFrame.title:SetPoint("CENTER", 0, 0)
    historyFrame.close = CreateFrame("Button", nil, historyFrame.header, "BackdropTemplate")
    historyFrame.close:SetSize(18, 18)
    historyFrame.close:SetPoint("RIGHT", -2, 0)
    historyFrame.close:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    historyFrame.close:SetBackdropColor(.28, .015, .015, 1)
    historyFrame.close:SetBackdropBorderColor(.72, .48, .02, 1)
    historyFrame.close.glyph = UI.Text(historyFrame.close, "GameFontNormal", "×", { 1, .82, 0, 1 })
    historyFrame.close.glyph:SetAllPoints()
    historyFrame.close:SetScript("OnClick", function() historyFrame:Hide() end)
    -- Нижняя полоса, над левой (чатовой) частью дока. Раньше окно вставало
    -- в левый верх экрана — прямо в игровую зону, которую HUD обязан
    -- оставлять чистой: весь интерфейс живёт снизу и справа.
    PlaceAuxiliaryFrame(historyFrame, "historyPosition", "BOTTOMLEFT", 24, 196)
    self.historyFrame, self.historyRows, self.history = historyFrame, {}, {}
    for index = 1, MAX_HISTORY_ROWS do
        local row = CreateFrame("Button", nil, historyFrame, "BackdropTemplate")
        row:SetHeight(32)
        row:SetWidth(260)
        row:SetPoint("BOTTOMLEFT", 0, HISTORY_FOOTER_HEIGHT + 2 + (index - 1) * HISTORY_ROW_HEIGHT)
        UI.Backdrop(row, { .008, .012, .020, .88 }, { .06, .22, .28, .86 })
        row.glass = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        row.glass:SetPoint("TOPLEFT", 1, -1)
        row.glass:SetPoint("BOTTOMRIGHT", -1, 1)
        row.glass:SetTexture(LOOT_GLASS_TEXTURE)
        row.glass:SetVertexColor(.38, .43, .48, .80)
        row.glow = row:CreateTexture(nil, "BACKGROUND", nil, 2)
        row.glow:SetPoint("TOPLEFT", -1, 1)
        row.glow:SetPoint("BOTTOMRIGHT", 1, -1)
        row.glow:SetTexture(LOOT_GLOW_TEXTURE)
        row.glow:SetBlendMode("ADD")
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetPoint("TOPLEFT", 3, -3)
        row.icon:SetSize(26, 26)
        row.icon:SetTexCoord(.07, .93, .07, .93)
        row.text = UI.Text(row, "GameFontHighlight", "", C.text)
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
        row.text:SetPoint("RIGHT", -6, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row:SetScript("OnEnter", function(owner)
            if owner.link then
                GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(owner.link)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
        row:SetScript("OnClick", function(owner)
            if owner.link and type(HandleModifiedItemClick) == "function" then HandleModifiedItemClick(owner.link) end
        end)
        self.historyRows[index] = row
    end
    historyFrame:Hide()
end

function LootUI:RegisterLootEvents()
    if not self.events then return end
    for _, event in ipairs({
        "LOOT_READY", "LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_CLOSED",
        "START_LOOT_ROLL", "CANCEL_LOOT_ROLL", "CANCEL_ALL_LOOT_ROLLS",
        "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "CHAT_MSG_CURRENCY", "PLAYER_ENTERING_WORLD",
    }) do
        self.events:RegisterEvent(event)
    end
end

function LootUI:Create()
    if self.frame then return end
    local frame = CreateFrame("Frame", "MythicBoostLootFrame", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_WIDTH, 102)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    UI.Backdrop(frame, { .025, .025, .030, .98 }, { .30, .30, .32, 1 })

    -- Строки начинаются у верхнего края, а компактная нижняя плашка служит
    -- одновременно подписью, местом закрытия и ручкой перемещения.
    frame.header = CreateFrame("Button", nil, frame, "BackdropTemplate")
    frame.header:SetPoint("BOTTOMLEFT", 1, 1)
    frame.header:SetPoint("BOTTOMRIGHT", -1, 1)
    frame.header:SetHeight(MAIN_FOOTER_HEIGHT - 2)
    frame.header:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame.header:SetBackdropColor(.015, .012, .008, .96)
    frame.header:SetBackdropBorderColor(.28, .22, .10, .90)
    frame.headerGlass = frame.header:CreateTexture(nil, "BACKGROUND")
    frame.headerGlass:SetAllPoints()
    frame.headerGlass:SetTexture(LOOT_GLASS_TEXTURE)
    frame.headerGlass:SetVertexColor(.42, .34, .18, .52)
    frame.header:RegisterForDrag("LeftButton")
    frame.header:SetScript("OnDragStart", function()
        if not Settings().atCursor and MythicBoostDB.interfaceUnlocked then frame:StartMoving() end
    end)
    frame.header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        LootUI:SavePosition()
    end)
    frame.title = UI.Text(frame.header, "GameFontNormalSmall", L("ДОБЫЧА"), { 1, .78, .12, 1 })
    frame.title:SetPoint("CENTER", 0, 0)
    frame.counter = UI.Text(frame.header, "GameFontHighlight", "", C.muted)
    frame.counter:Hide()
    local close = CreateFrame("Button", nil, frame, "BackdropTemplate")
    close:SetSize(18, 18)
    close:SetPoint("BOTTOMRIGHT", -1, 1)
    close:SetFrameLevel(frame:GetFrameLevel() + 20)
    close:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    close:SetBackdropColor(.28, .015, .015, 1)
    close:SetBackdropBorderColor(.72, .48, .02, 1)
    close.glyph = UI.Text(close, "GameFontNormalLarge", "×", { 1, .82, 0, 1 })
    close.glyph:SetAllPoints(close)
    close.glyph:SetJustifyH("CENTER")
    close.glyph:SetJustifyV("MIDDLE")
    close:SetScript("OnEnter", function(owner)
        owner:SetBackdropColor(.56, .025, .025, 1)
        owner:SetBackdropBorderColor(1, .78, .05, 1)
    end)
    close:SetScript("OnLeave", function(owner)
        owner:SetBackdropColor(.28, .015, .015, 1)
        owner:SetBackdropBorderColor(.72, .48, .02, 1)
    end)
    close:SetScript("OnClick", function()
        if type(CloseLoot) == "function" then CloseLoot() else frame:Hide() end
    end)
    frame.page = UI.Text(frame, "GameFontHighlightSmall", "", C.muted)
    frame.page:SetPoint("CENTER", frame.header, "CENTER", 0, 0)

    self.frame, self.rows = frame, {}
    for index = 1, MAX_ROWS do self:BuildRow(index) end
    frame:SetScript("OnMouseWheel", function(_, delta)
        local maximum = math.max(0, #(LootUI.slots or {}) - MAX_ROWS)
        LootUI.scrollOffset = math.max(0, math.min(maximum, (LootUI.scrollOffset or 0) - delta))
        LootUI:Refresh()
    end)
    frame:Hide()
    UISpecialFrames = UISpecialFrames or {}
    local registered
    for _, name in ipairs(UISpecialFrames) do
        if name == frame:GetName() then registered = true; break end
    end
    if not registered then
        UISpecialFrames[#UISpecialFrames + 1] = frame:GetName()
    end

    self:BuildAuxiliaryFrames()

    self.events = CreateFrame("Frame")
    self.events:RegisterEvent("ADDON_LOADED")
    self:RegisterLootEvents()
    self.events:SetScript("OnEvent", function(_, event, arg1, arg2)
        if event == "LOOT_OPENED" then
            LootUI.lootSessionOpen = true
            LootUI.showAttempts = 0
            LootUI:ShowLoot()
        elseif event == "LOOT_READY" then
            LootUI.lootSessionOpen = true
            C_Timer.After(.03, function()
                if LootUI.lootSessionOpen and not LootUI.frame:IsShown() then LootUI:ShowLoot() end
            end)
        elseif event == "LOOT_SLOT_CLEARED" then
            if LootUI.frame:IsShown() then C_Timer.After(0, function() LootUI:Refresh() end) end
        elseif event == "LOOT_CLOSED" then
            LootUI.lootSessionOpen = nil
            LootUI.showAttempts = 0
            LootUI.frame:Hide()
        elseif event == "START_LOOT_ROLL" then LootUI:StartRoll(arg1, arg2)
        elseif event == "CANCEL_LOOT_ROLL" then LootUI:RemoveRoll(arg1)
        elseif event == "CANCEL_ALL_LOOT_ROLLS" then
            wipe(LootUI.rolls or {})
            LootUI:RefreshRolls()
        elseif event == "CHAT_MSG_LOOT" or event == "CHAT_MSG_MONEY" or event == "CHAT_MSG_CURRENCY" then
            LootUI:AddHistoryMessage(arg1, event)
        elseif event == "PLAYER_ENTERING_WORLD" then
            LootUI:SuppressBlizzardRolls()
            C_Timer.After(.4, function() LootUI:RecoverRolls() end)
        elseif event == "ADDON_LOADED" then
            if arg1 == "Blizzard_LootUI" and Settings().enabled and not IsExternalFrameLoaded() then
                LootUI:ParkBlizzard()
            end
            if Settings().showRolls and not IsExternalRollLoaded() then
                C_Timer.After(0, function() LootUI:SuppressBlizzardRolls() end)
            end
        end
    end)
    if not IsExternalFrameLoaded() then self:ParkBlizzard() end
end

function LootUI:Enable()
    if Settings().enabled == false then self:Disable(); return end
    self:Create()
    self:RegisterLootEvents()
    if (IsExternalFrameLoaded() or IsExternalRollLoaded() or IsExternalMonitorLoaded())
        and not self.externalSuiteReported then
        self.externalSuiteReported = true
        JP:Print(L("Модуль добычи: отключи XLoot_Frame, XLoot_Group и XLoot_Monitor, чтобы окна не дублировались."))
    end
    if not IsExternalFrameLoaded() then self:ParkBlizzard() end
    self:SuppressBlizzardRolls()
end

function LootUI:Disable()
    if self.frame then self.frame:Hide() end
    if self.rollFrame then self.rollFrame:Hide() end
    if self.historyFrame then self.historyFrame:Hide() end
    self:RestoreBlizzard()
    self:RestoreBlizzardRolls()
    if self.events then
        for _, event in ipairs({
            "LOOT_READY", "LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_CLOSED",
            "START_LOOT_ROLL", "CANCEL_LOOT_ROLL", "CANCEL_ALL_LOOT_ROLLS",
            "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "CHAT_MSG_CURRENCY", "PLAYER_ENTERING_WORLD",
        }) do
            self.events:UnregisterEvent(event)
        end
    end
end

function LootUI:Destroy() self:Disable() end

JP.LootUI = LootUI
JP:RegisterModule("LootUI", LootUI)
