local _, JP = ...
local L = JP.L
local LootUI = {}
local UI, C = JP.UI, JP.UI.colors

local MAX_ROWS = 10
-- XLoot держит строку высотой ровно в иконку плюс пара пикселей воздуха, а
-- окно — узким: список добычи читают боковым зрением, и лишняя ширина только
-- отнимает место у игрового экрана.
local ROW_HEIGHT = 42
local FRAME_WIDTH = 320
local MAX_ROLL_ROWS = 4
local ROLL_ROW_HEIGHT = 64
local ROLL_FRAME_WIDTH = 460
local MAX_HISTORY_ROWS = 6
local HISTORY_ROW_HEIGHT = 24
local HISTORY_LIFETIME = 22
local BLIZZARD_LOOT_EVENTS = { "LOOT_OPENED", "LOOT_CLOSED", "LOOT_SLOT_CLEARED" }
local SETTINGS_DEFAULTS = { enabled = false, atCursor = true, showRolls = true, showHistory = true }

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

    local bindLabel = bindType == (LE_ITEM_BIND_ON_ACQUIRE or 1) and L("БоП") or ""
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
            local glowAlpha = quality >= 2 and .82 or .30
            row:SetBackdropBorderColor(r, g, b, quality >= 2 and 1 or .70)
            row.name:SetTextColor(r, g, b, 1)
            -- Тот же цвет на контуре иконки, но приглушённее рамки строки:
            -- два одинаково ярких контура рядом читаются как один толстый.
            row.iconEdge:SetBackdropBorderColor(r * .90, g * .90, b * .90, .96)
            -- Заливка гаснет к правому краю: под названием фон обязан остаться
            -- тёмным, иначе светлый текст по светлому цвету качества пропадает.
            row.tint:SetGradient("HORIZONTAL",
                CreateColor(r, g, b, quality >= 2 and .34 or .07),
                CreateColor(r, g, b, quality >= 2 and .12 or 0))
            for _, glow in ipairs(row.glows) do
                glow:SetColorTexture(r, g, b, glowAlpha)
            end
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
    self.frame:SetHeight(8 + shown * ROW_HEIGHT + (#slots > MAX_ROWS and 18 or 0))
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
    if not frame or not LootUI.blizzardRollsSuppressed then return end
    frame:Hide()
    if _G.GroupLootContainer and type(_G.GroupLootContainer_RemoveFrame) == "function" then
        pcall(_G.GroupLootContainer_RemoveFrame, _G.GroupLootContainer, frame)
    end
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
    row:SetHeight(40)
    row:SetPoint("TOPLEFT", 4, -4 - (index - 1) * ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", index == 1 and -30 or -4, -4 - (index - 1) * ROW_HEIGHT)
    row:RegisterForClicks("AnyUp")
    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 2,
    })
    row.baseAlpha = .98
    row:SetBackdropColor(C.surface[1], C.surface[2], C.surface[3], row.baseAlpha)

    -- Четыре ADD-полосы дают тот самый XLoot glow: он остаётся прямоугольным,
    -- повторяет цвет качества и не размывает иконку/текст поверх строки.
    row.glows = {}
    local function Glow(pointA, pointB, xA, yA, xB, yB)
        local glow = row:CreateTexture(nil, "BACKGROUND", nil, -1)
        glow:SetTexture("Interface\\Buttons\\WHITE8X8")
        glow:SetBlendMode("ADD")
        glow:SetPoint(pointA, row, pointA, xA, yA)
        glow:SetPoint(pointB, row, pointB, xB, yB)
        row.glows[#row.glows + 1] = glow
        return glow
    end
    local top = Glow("TOPLEFT", "TOPRIGHT", -3, 3, 3, 3); top:SetHeight(4)
    local bottom = Glow("BOTTOMLEFT", "BOTTOMRIGHT", -3, -3, 3, -3); bottom:SetHeight(4)
    local left = Glow("TOPLEFT", "BOTTOMLEFT", -3, 3, -3, -3); left:SetWidth(4)
    local right = Glow("TOPRIGHT", "BOTTOMRIGHT", 3, 3, 3, -3); right:SetWidth(4)

    -- XLoot's row is a black glass capsule, not a light card. A very quiet
    -- vertical sheen separates neighboring entries without heavy white bars.
    row.glass = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.glass:SetPoint("TOPLEFT", 1, -1)
    row.glass:SetPoint("BOTTOMRIGHT", -1, 1)
    row.glass:SetColorTexture(1, 1, 1, 1)
    row.glass:SetGradient("VERTICAL",
        CreateColor(.005, .008, .012, 1),
        CreateColor(.25, .25, .25, .88))

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
    row.icon:SetWidth(36)
    row.icon:SetTexCoord(.07, .93, .07, .93)

    -- Подпись XLoot: цвет качества стоит не только на рамке строки, но и
    -- тонким контуром вокруг самой иконки. Так вещь опознаётся по краю
    -- значка, даже когда взгляд не дошёл до названия.
    row.iconEdge = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.iconEdge:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -1, 1)
    row.iconEdge:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 1, -1)
    row.iconEdge:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })

    row.name = UI.Text(row, "GameFontNormal", "")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -3)
    row.name:SetPoint("TOPRIGHT", -7, -3)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.detail = UI.Text(row, "GameFontNormalSmall", "", { 1, .84, 0, 1 })
    row.detail:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -20)
    row.detail:SetPoint("TOPRIGHT", row, "TOPRIGHT", -7, -20)
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

local function BuildAuxiliaryHeader(frame, title, positionKey)
    frame.header = CreateFrame("Button", nil, frame)
    frame.header:SetPoint("TOPLEFT", 1, -1)
    frame.header:SetPoint("TOPRIGHT", -1, -1)
    frame.header:SetHeight(25)
    frame.header:RegisterForDrag("LeftButton")
    frame.header:SetScript("OnDragStart", function()
        if MythicBoostDB.interfaceUnlocked then frame:StartMoving() end
    end)
    frame.header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SaveAuxiliaryPosition(frame, positionKey)
    end)
    frame.title = UI.Text(frame.header, "GameFontNormal", title, C.accent)
    frame.title:SetPoint("LEFT", 8, 0)
    frame.line = UI.Line(frame, C.accent)
    frame.line:SetPoint("TOPLEFT", 1, -25)
    frame.line:SetPoint("TOPRIGHT", -1, -25)
end

local function BuildRollChoice(row, label, rollType)
    local button = UI.Button(row, label, 66, 22, rollType == 1)
    button.rollType = rollType
    button:SetFrameLevel(row:GetFrameLevel() + 4)
    button:SetScript("OnClick", function(owner)
        if not row.rollID or row.selectionMade then return end
        local ok = type(RollOnLoot) == "function" and pcall(RollOnLoot, row.rollID, owner.rollType)
        if not ok then return end
        row.selectionMade = owner.rollType
        if LootUI.rolls and LootUI.rolls[row.rollID] then
            LootUI.rolls[row.rollID].selected = owner.rollType
        end
        for _, choice in ipairs(row.choices) do
            choice:SetEnabled(false)
            choice:SetAlpha(choice == owner and 1 or .32)
        end
        row.result:SetText(owner.label:GetText())
        row.result:Show()
    end)
    row.choices[#row.choices + 1] = button
    return button
end

function LootUI:BuildRollRow(index)
    local row = CreateFrame("Button", nil, self.rollFrame, "BackdropTemplate")
    row:SetHeight(58)
    row:SetPoint("TOPLEFT", 7, -31 - (index - 1) * ROLL_ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", -7, -31 - (index - 1) * ROLL_ROW_HEIGHT)
    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    row:SetBackdropColor(C.surface[1], C.surface[2], C.surface[3], .97)
    row.progress = CreateFrame("StatusBar", nil, row)
    row.progress:SetPoint("TOPLEFT", 1, -1)
    row.progress:SetPoint("BOTTOMRIGHT", -1, 1)
    row.progress:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    row.progress:SetStatusBarColor(.74, .25, .025, .30)
    row.progress:SetFrameLevel(row:GetFrameLevel())
    row.icon = row:CreateTexture(nil, "ARTWORK", nil, 3)
    row.icon:SetPoint("TOPLEFT", 5, -5)
    row.icon:SetSize(47, 47)
    row.icon:SetTexCoord(.07, .93, .07, .93)
    row.name = UI.Text(row, "GameFontNormal", "", C.text)
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -2)
    row.name:SetPoint("RIGHT", -58, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.timer = UI.Text(row, "GameFontNormalLarge", "", C.text)
    row.timer:SetPoint("TOPRIGHT", -7, -4)
    row.timer:SetJustifyH("RIGHT")
    row.result = UI.Text(row, "GameFontNormalSmall", "", C.accent)
    row.result:SetPoint("BOTTOMRIGHT", -8, 7)
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
    table.sort(active, function(a, b) return (a.deadline or 0) < (b.deadline or 0) end)
    for index, row in ipairs(self.rollRows) do
        local data = active[index]
        if data then
            row.rollID, row.link, row.selectionMade = data.rollID, data.link, data.selected
            row.icon:SetTexture(data.icon)
            row.name:SetText((data.count or 1) > 1 and (data.name .. "  ×" .. data.count) or data.name)
            row.progress:SetMinMaxValues(0, math.max(.1, data.duration or 1))
            local r, g, b = QualityColor(data.quality)
            row:SetBackdropBorderColor(r, g, b, .96)
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
                if data.selected == choice.rollType then row.result:SetText(choice.label:GetText()) end
            end
            local choiceWidth, choiceGap = 61, 4
            for choiceIndex, choice in ipairs(visibleChoices) do
                choice:SetWidth(choiceWidth)
                choice:ClearAllPoints()
                choice:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT",
                    8 + (choiceIndex - 1) * (choiceWidth + choiceGap), 0)
            end
            row.result:SetShown(data.selected ~= nil)
            row:Show()
        else
            row.rollID, row.link, row.selectionMade = nil, nil, nil
            row:Hide()
        end
    end
    local shown = math.min(#active, MAX_ROLL_ROWS)
    self.rollFrame:SetHeight(32 + shown * ROLL_ROW_HEIGHT)
    self.rollFrame:SetShown(shown > 0)
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

function LootUI:AddHistoryMessage(message)
    if not Settings().showHistory or IsExternalMonitorLoaded() or type(message) ~= "string"
        or issecretvalue(message) then return end
    local link = message:match("(|c%x+|Hitem:.-|h%[.-%]|h|r)") or message:match("(|Hitem:.-|h%[.-%]|h)")
    if not link or not IsLootAwardMessage(message) then return end
    local icon = 134400
    local quality = 1
    local itemInfoInstant = C_Item and C_Item.GetItemInfoInstant or _G.GetItemInfoInstant
    if type(itemInfoInstant) == "function" then
        local ok, _, _, _, _, texture = pcall(itemInfoInstant, link)
        if ok then icon = SafeValue(texture, icon) end
    end
    local itemInfo = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
    if type(itemInfo) == "function" then
        local ok, _, _, itemQuality = pcall(itemInfo, link)
        if ok then quality = SafeValue(itemQuality, quality) end
    end
    self.history = self.history or {}
    table.insert(self.history, 1, {
        message = message, link = link, icon = icon, quality = quality,
        expires = GetTime() + HISTORY_LIFETIME,
    })
    while #self.history > MAX_HISTORY_ROWS do table.remove(self.history) end
    self:RefreshHistory()
    if C_Timer then C_Timer.After(HISTORY_LIFETIME + .1, function() LootUI:RefreshHistory() end) end
end

function LootUI:RefreshHistory()
    if not self.historyFrame then return end
    if not Settings().showHistory then self.historyFrame:Hide(); return end
    local now = GetTime()
    for index = #self.history, 1, -1 do
        if (self.history[index].expires or 0) <= now then table.remove(self.history, index) end
    end
    for index, row in ipairs(self.historyRows) do
        local data = self.history[index]
        if data then
            row.link = data.link
            row.icon:SetTexture(data.icon)
            row.text:SetText(data.message)
            local r, g, b = QualityColor(data.quality)
            row:SetBackdropBorderColor(r, g, b, .90)
            row:Show()
        else
            row.link = nil
            row:Hide()
        end
    end
    local shown = math.min(#self.history, MAX_HISTORY_ROWS)
    self.historyFrame:SetHeight(32 + shown * HISTORY_ROW_HEIGHT)
    self.historyFrame:SetShown(shown > 0)
end

function LootUI:BuildAuxiliaryFrames()
    local rollFrame = CreateFrame("Frame", "MythicBoostLootRollFrame", UIParent, "BackdropTemplate")
    rollFrame:SetSize(ROLL_FRAME_WIDTH, 96)
    rollFrame:SetFrameStrata("DIALOG")
    rollFrame:SetClampedToScreen(true)
    rollFrame:SetMovable(true)
    UI.Backdrop(rollFrame, { C.surface[1], C.surface[2], C.surface[3], .96 }, { .08, .34, .42, .98 })
    BuildAuxiliaryHeader(rollFrame, L("ГОЛОСОВАНИЕ ЗА ДОБЫЧУ"), "rollPosition")
    -- Над кастбаром: тот стоит на BOTTOM 250, и на 260 окна перекрывались.
    PlaceAuxiliaryFrame(rollFrame, "rollPosition", "BOTTOM", 0, 330)
    self.rollFrame, self.rollRows, self.rolls = rollFrame, {}, {}
    for index = 1, MAX_ROLL_ROWS do self:BuildRollRow(index) end
    rollFrame:SetScript("OnUpdate", function(_, elapsed) LootUI:UpdateRollTimers(elapsed) end)
    rollFrame:Hide()

    local historyFrame = CreateFrame("Frame", "MythicBoostLootHistoryFrame", UIParent, "BackdropTemplate")
    historyFrame:SetSize(430, 96)
    historyFrame:SetFrameStrata("HIGH")
    historyFrame:SetClampedToScreen(true)
    historyFrame:SetMovable(true)
    UI.Backdrop(historyFrame, { C.surface[1], C.surface[2], C.surface[3], .94 }, { .08, .34, .42, .94 })
    BuildAuxiliaryHeader(historyFrame, L("БРОСКИ ГРУППЫ"), "historyPosition")
    -- Нижняя полоса, над левой (чатовой) частью дока. Раньше окно вставало
    -- в левый верх экрана — прямо в игровую зону, которую HUD обязан
    -- оставлять чистой: весь интерфейс живёт снизу и справа.
    PlaceAuxiliaryFrame(historyFrame, "historyPosition", "BOTTOMLEFT", 24, 196)
    self.historyFrame, self.historyRows, self.history = historyFrame, {}, {}
    for index = 1, MAX_HISTORY_ROWS do
        local row = CreateFrame("Button", nil, historyFrame, "BackdropTemplate")
        row:SetHeight(32)
        row:SetPoint("TOPLEFT", 7, -30 - (index - 1) * HISTORY_ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", -7, -30 - (index - 1) * HISTORY_ROW_HEIGHT)
        UI.Backdrop(row, { .008, .012, .020, .88 }, { .06, .22, .28, .86 })
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetPoint("TOPLEFT", 3, -3)
        row.icon:SetSize(26, 26)
        row.icon:SetTexCoord(.07, .93, .07, .93)
        row.text = UI.Text(row, "GameFontHighlightSmall", "", C.text)
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
        "CHAT_MSG_LOOT", "PLAYER_ENTERING_WORLD",
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

    -- XLoot has no title bar: entries begin at the top edge. The invisible
    -- footer remains only as a drag handle while interface moving is enabled.
    frame.header = CreateFrame("Button", nil, frame)
    frame.header:SetPoint("BOTTOMLEFT", 1, 1)
    frame.header:SetPoint("BOTTOMRIGHT", -1, 1)
    frame.header:SetHeight(22)
    frame.header:RegisterForDrag("LeftButton")
    frame.header:SetScript("OnDragStart", function()
        if not Settings().atCursor and MythicBoostDB.interfaceUnlocked then frame:StartMoving() end
    end)
    frame.header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        LootUI:SavePosition()
    end)
    -- Kept as hidden compatibility fields for Refresh; XLoot does not repeat
    -- a title or item counter above every corpse.
    frame.title = UI.Text(frame.header, "GameFontNormalSmall", "", C.accent)
    frame.title:Hide()
    frame.counter = UI.Text(frame.header, "GameFontHighlight", "", C.muted)
    frame.counter:Hide()
    local close = CreateFrame("Button", nil, frame, "BackdropTemplate")
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetFrameLevel(frame:GetFrameLevel() + 20)
    close:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 2,
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
    frame.page:SetPoint("BOTTOM", 0, 3)

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
        elseif event == "CHAT_MSG_LOOT" then LootUI:AddHistoryMessage(arg1)
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
            "CHAT_MSG_LOOT", "PLAYER_ENTERING_WORLD",
        }) do
            self.events:UnregisterEvent(event)
        end
    end
end

function LootUI:Destroy() self:Disable() end

JP.LootUI = LootUI
JP:RegisterModule("LootUI", LootUI)
