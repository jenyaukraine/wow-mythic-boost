local _, JP = ...

local L = JP.L
-- Небольшое единое окно сумок: только то, ради чего обычно ставят Bagnon.
-- Никакой базы других персонажей, банка и категорий — предметы читаются
-- напрямую из C_Container и не создают тяжёлых SavedVariables.
local BagUI = {}
local UI, C = JP.UI, JP.UI.colors

local CELL_SIZE = 38
local CELL_STEP = 41
local MIN_COLUMNS = 10
local MAX_COLUMNS = 14
local HEADER_HEIGHT = 48
local FOOTER_HEIGHT = 42
local SIDE_PADDING = 12
local EMPTY_TEXTURE = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"
local REFRESH_DELAY = .08

local function Settings()
    MythicBoostDB.bagUI = type(MythicBoostDB.bagUI) == "table" and MythicBoostDB.bagUI or {}
    if MythicBoostDB.bagUI.enabled == nil then MythicBoostDB.bagUI.enabled = true end
    return MythicBoostDB.bagUI
end

local function IsAddonLoadedSafe(name)
    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
        local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, name)
        return ok and loaded == true
    end
    return type(IsAddOnLoaded) == "function" and IsAddOnLoaded(name) == true
end

local function BagIDs()
    local maximum = tonumber(NUM_TOTAL_EQUIPPED_BAG_SLOTS) or tonumber(NUM_BAG_SLOTS) or 4
    local reagent = Enum and Enum.BagIndex and tonumber(Enum.BagIndex.ReagentBag)
    if reagent and reagent > maximum then maximum = reagent end
    maximum = math.max(4, math.min(maximum, 5))
    local ids = {}
    for bag = 0, maximum do ids[#ids + 1] = bag end
    return ids
end

local function BagName(bag)
    if bag == 0 then return BACKPACK_TOOLTIP or L("Рюкзак") end
    if C_Container and type(C_Container.GetBagName) == "function" then
        local ok, name = pcall(C_Container.GetBagName, bag)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return bag == 5 and L("Сумка реагентов") or (L("Сумка %d")):format(bag)
end

local function BagInventorySlot(bag)
    if not bag or bag <= 0 then return end
    local convert = C_Container and C_Container.ContainerIDToInventoryID or _G.ContainerIDToInventoryID
    if type(convert) == "function" then
        local ok, value = pcall(convert, bag)
        if ok and type(value) == "number" then return value end
    end
end

local function BagIcon(bag)
    if bag == 0 then return "Interface\\Buttons\\Button-Backpack-Up" end
    local inventoryID = BagInventorySlot(bag)
    if inventoryID and type(GetInventoryItemTexture) == "function" then
        local texture = GetInventoryItemTexture("player", inventoryID)
        if texture then return texture end
    end
    return EMPTY_TEXTURE
end

local function QualityColor(quality)
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[tonumber(quality) or 1]
    if color then return color.r or 1, color.g or 1, color.b or 1 end
    return .28, .34, .42
end

local function SafeCount(value)
    return UI.UsableNumber(value) and value or 0
end

function BagUI:CollectSlots()
    local slots, used, total = {}, 0, 0
    if not C_Container or type(C_Container.GetContainerNumSlots) ~= "function" then
        return slots, used, total
    end
    for _, bag in ipairs(BagIDs()) do
        local count = SafeCount(C_Container.GetContainerNumSlots(bag))
        total = total + count
        for slot = 1, count do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then used = used + 1 end
            slots[#slots + 1] = { bag = bag, slot = slot, info = info }
        end
    end
    return slots, used, total
end

-- Сортировка и перенос предметов порождают большие пачки событий. Полная
-- перерисовка на каждое ITEM_LOCK_CHANGED раньше умножяла 186 слотов на
-- сотни событий и подвешивала клиент. Все пачки схлопываются в один кадр.
function BagUI:RequestRefresh(delay)
    if not self.frame or not self.frame:IsShown() then return end
    if self.refreshPending then return end
    self.refreshPending = true
    if not C_Timer or type(C_Timer.After) ~= "function" then
        self.refreshPending = nil
        self:Refresh()
        return
    end
    C_Timer.After(delay or REFRESH_DELAY, function()
        BagUI.refreshPending = nil
        if BagUI.frame and BagUI.frame:IsShown() then BagUI:Refresh() end
    end)
end

function BagUI:RefreshCooldowns()
    if not C_Container or type(C_Container.GetContainerItemCooldown) ~= "function" then return end
    for _, button in ipairs(self.itemButtons or {}) do
        if button:IsShown() and button.bag ~= nil and button.slot ~= nil then
            local start, duration, enabled = C_Container.GetContainerItemCooldown(button.bag, button.slot)
            CooldownFrame_Set(button.cooldown, start or 0, duration or 0, enabled or 0)
        end
    end
end

function BagUI:SavePosition()
    if not self.frame then return end
    local point, _, relativePoint, x, y = self.frame:GetPoint()
    if type(point) == "string" and type(x) == "number" and type(y) == "number" then
        Settings().position = { point = point, relativePoint = relativePoint, x = x, y = y }
    end
end

function BagUI:PlaceFrame()
    local frame, position = self.frame, Settings().position
    frame:ClearAllPoints()
    if type(position) == "table" and type(position.point) == "string"
        and type(position.x) == "number" and type(position.y) == "number" then
        frame:SetPoint(position.point, UIParent, position.relativePoint or position.point, position.x, position.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

function BagUI:CreateItemButton(index)
    -- Blizzard container template owns the protected right-click/use path.
    -- Calling C_Container.UseContainerItem from an ordinary addon button
    -- taints hearthstones, consumables and other protected item actions.
    local button = CreateFrame("ItemButton", nil, self.frame,
        "ContainerFrameItemButtonTemplate,BackdropTemplate")
    button:SetSize(CELL_SIZE, CELL_SIZE)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button.GetBag = function(owner) return owner.bag end
    button.GetSlot = function(owner) return owner.bag, owner:GetID() end
    UI.Backdrop(button, { .075, .095, .120, .68 }, { .30, .40, .49, .90 }, 1)
    -- Шаблон ставит UI-PassiveHighlight обычной NormalTexture. На нашей
    -- сетке она превращает каждую ячейку в яркий голубой квадрат. nil клиент
    -- не принимает, поэтому подменяем её валидной прозрачной текстурой.
    button:SetNormalTexture("Interface\\Buttons\\WHITE8X8")
    local normal = button.GetNormalTexture and button:GetNormalTexture()
    if normal then normal:SetVertexColor(0, 0, 0, 0); normal:SetAlpha(0) end
    button:SetPushedTexture("Interface\\Buttons\\WHITE8X8")
    local pushed = button.GetPushedTexture and button:GetPushedTexture()
    if pushed then pushed:SetVertexColor(0, 0, 0, 0); pushed:SetAlpha(0) end

    button.empty = button:CreateTexture(nil, "BACKGROUND")
    button.empty:SetPoint("TOPLEFT", 3, -3)
    button.empty:SetPoint("BOTTOMRIGHT", -3, 3)
    button.empty:SetTexture(EMPTY_TEXTURE)
    button.empty:SetDesaturated(true)
    button.empty:SetVertexColor(.44, .50, .57, .36)

    button.icon = button.Icon or button.icon or button:CreateTexture(nil, "ARTWORK")
    button.icon:ClearAllPoints()
    button.icon:SetPoint("TOPLEFT", 3, -3)
    button.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    button.icon:SetTexCoord(.07, .93, .07, .93)

    button.count = button.Count or button.count or UI.Text(button, "NumberFontNormal", "", C.text)
    button.count:ClearAllPoints()
    button.count:SetPoint("BOTTOMRIGHT", -3, 3)
    button.count:SetJustifyH("RIGHT")

    button.locked = button:CreateTexture(nil, "OVERLAY")
    button.locked:SetAllPoints(button.icon)
    button.locked:SetColorTexture(0, 0, 0, .58)
    button.locked:Hide()

    button.cooldown = button.Cooldown or button.cooldown
        or CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:ClearAllPoints()
    button.cooldown:SetAllPoints(button.icon)
    button.cooldown:SetDrawEdge(false)
    button.cooldown:SetDrawBling(false)

    button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
    button.highlight:SetPoint("TOPLEFT", 1, -1)
    button.highlight:SetPoint("BOTTOMRIGHT", -1, 1)
    button.highlight:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], .20)

    button:SetScript("OnEnter", function(owner)
        if owner.bag == nil or owner.slot == nil then return end
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        local shown = GameTooltip:SetBagItem(owner.bag, owner.slot)
        if not shown then GameTooltip:SetText(BagName(owner.bag)) end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    -- Не подменяем OnClick/OnDragStart/OnReceiveDrag: их безопасно даёт
    -- ContainerFrameItemButtonTemplate, включая modified-click и swapping.
    self.itemButtons[index] = button
    return button
end

function BagUI:UpdateItemButton(button, data)
    local info = data.info
    -- Button state can show inherited textures again after clicks/dragging;
    -- keep the Blizzard interaction scripts but never its visual skin.
    local normal = button.GetNormalTexture and button:GetNormalTexture()
    if normal then normal:SetAlpha(0) end
    local pushed = button.GetPushedTexture and button:GetPushedTexture()
    if pushed then pushed:SetAlpha(0) end
    if button.NewItemTexture then button.NewItemTexture:Hide() end
    if button.BattlepayItemTexture then button.BattlepayItemTexture:Hide() end
    if button.flashAnim and button.flashAnim:IsPlaying() then button.flashAnim:Stop() end
    if button.newitemglowAnim and button.newitemglowAnim:IsPlaying() then button.newitemglowAnim:Stop() end
    button.bag, button.slot = data.bag, data.slot
    button:SetID(data.slot)
    button.hasItem = info and info.itemID and true or false
    button.readable = info and info.isReadable or false
    button.link = info and info.hyperlink or nil
    if info and info.iconFileID then
        local stackCount = SafeCount(info.stackCount)
        local locked = info.isLocked == true
        local quality = tonumber(info.quality) or 1
        if button.cachedItemID ~= info.itemID or button.cachedIcon ~= info.iconFileID
            or button.cachedCount ~= stackCount or button.cachedLocked ~= locked
            or button.cachedQuality ~= quality then
            button.icon:SetTexture(info.iconFileID)
            button.icon:Show()
            button.empty:Hide()
            button.count:SetText(stackCount > 1 and stackCount or "")
            button.locked:SetShown(locked)
            local r, g, b = QualityColor(quality)
            button:SetBackdropBorderColor(r * .92, g * .92, b * .92, 1)
            button.cachedItemID, button.cachedIcon = info.itemID, info.iconFileID
            button.cachedCount, button.cachedLocked, button.cachedQuality = stackCount, locked, quality
        end
        local start, duration, enabled = 0, 0, 0
        if C_Container and type(C_Container.GetContainerItemCooldown) == "function" then
            start, duration, enabled = C_Container.GetContainerItemCooldown(data.bag, data.slot)
        end
        CooldownFrame_Set(button.cooldown, start or 0, duration or 0, enabled or 0)
    else
        if button.cachedItemID ~= false then
            button.icon:SetTexture(nil)
            button.icon:Hide()
            button.empty:Show()
            button.count:SetText("")
            button.locked:Hide()
            button:SetBackdropColor(.075, .095, .120, .68)
            button:SetBackdropBorderColor(.30, .40, .49, .90)
            button.cachedItemID, button.cachedIcon, button.cachedCount = false, nil, nil
            button.cachedLocked, button.cachedQuality = nil, nil
        end
        CooldownFrame_Set(button.cooldown, 0, 0, 0)
    end
    button:Show()
end

function BagUI:RefreshBagTabs()
    for bag, button in pairs(self.bagButtons or {}) do
        button.icon:SetTexture(BagIcon(bag))
        button:SetBackdropColor(.085, .11, .14, .76)
        button:SetBackdropBorderColor(.31, .42, .51, .92)
    end
end

function BagUI:Refresh()
    if not self.frame then return end
    local slots, used, total = self:CollectSlots()
    local availableHeight = math.max(420, UIParent:GetHeight() - 150)
    local maximumRows = math.max(1, math.floor((availableHeight - HEADER_HEIGHT - FOOTER_HEIGHT) / CELL_STEP))
    local columns = math.max(MIN_COLUMNS, math.ceil(math.max(1, #slots) / maximumRows))
    columns = math.min(MAX_COLUMNS, columns)
    local rows = math.max(1, math.ceil(math.max(1, #slots) / columns))
    local width = SIDE_PADDING * 2 + columns * CELL_STEP - (CELL_STEP - CELL_SIZE)
    local height = HEADER_HEIGHT + FOOTER_HEIGHT + rows * CELL_STEP - (CELL_STEP - CELL_SIZE)
    local layoutChanged = self.layoutSlots ~= #slots or self.layoutColumns ~= columns
    if layoutChanged then
        self.layoutSlots, self.layoutColumns = #slots, columns
        self.frame:SetSize(width, height)
    end

    -- Не создаём 186 сложных кнопок в одном кадре: это было второй причиной
    -- зависания при самом первом открытии. Сетка наполняется за несколько кадров.
    local createdThisPass, complete = 0, true
    for index = 1, #slots do
        if not self.itemButtons[index] and createdThisPass >= 24 then
            complete = false
            break
        end
        local button = self.itemButtons[index] or self:CreateItemButton(index)
        if not button.layoutReady then createdThisPass = createdThisPass + 1 end
        if layoutChanged or not button.layoutReady then
            button:ClearAllPoints()
            local column = (index - 1) % columns
            local row = math.floor((index - 1) / columns)
            button:SetPoint("TOPLEFT", self.frame, "TOPLEFT", SIDE_PADDING + column * CELL_STEP,
                -HEADER_HEIGHT - row * CELL_STEP)
            button.layoutReady = true
        end
        self:UpdateItemButton(button, slots[index])
    end
    for index = #slots + 1, #self.itemButtons do
        self.itemButtons[index].bag, self.itemButtons[index].slot = nil, nil
        self.itemButtons[index]:Hide()
    end

    self.frame.capacity:SetFormattedText("|cff28b8f5%d|r/%d", used, total)
    self.frame.money:SetText(type(GetCoinTextureString) == "function" and GetCoinTextureString(GetMoney() or 0) or "")
    self:RefreshBagTabs()
    if not complete then self:RequestRefresh(0) end
end

function BagUI:HideBlizzardContainers()
    local combined = _G.ContainerFrameCombinedBags
    if combined and combined:IsShown() then combined:Hide() end
    local maximum = tonumber(NUM_CONTAINER_FRAMES) or 13
    for index = 1, maximum do
        local frame = _G["ContainerFrame" .. index]
        if frame and frame:IsShown() then frame:Hide() end
    end
end

function BagUI:CloseNativeBags()
    self.suppressCloseHook = true
    if type(CloseAllBags) == "function" then pcall(CloseAllBags) end
    self.suppressCloseHook = nil
    self:HideBlizzardContainers()
end

function BagUI:Show()
    if not Settings().enabled or self.externalConflict then return end
    self:CloseNativeBags()
    self.frame:Show()
    self:Refresh()
end

function BagUI:Hide()
    if self.frame then self.frame:Hide() end
end

function BagUI:Toggle()
    if not self.frame then self:Create() end
    if self.frame:IsShown() then self:Hide() else self:Show() end
end

function BagUI:BuildBagButton(parent, bag, x)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(34, 34)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -7)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button.inventorySlot = BagInventorySlot(bag)
    UI.Backdrop(button, C.field, C.line)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 3, -3)
    button.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    button.icon:SetTexCoord(.07, .93, .07, .93)
    button.icon:SetTexture(BagIcon(bag))
    local function PickupEquippedBag()
        if not button.inventorySlot or (CursorHasItem and CursorHasItem()) then return end
        if type(PickupBagFromSlot) == "function" then
            PickupBagFromSlot(button.inventorySlot)
        elseif type(PickupInventoryItem) == "function" then
            PickupInventoryItem(button.inventorySlot)
        end
        BagUI:RequestRefresh(.12)
    end
    local function PlaceCursorBag()
        if not CursorHasItem or not CursorHasItem() then return end
        if button.inventorySlot and type(PutItemInBag) == "function" then
            PutItemInBag(button.inventorySlot)
        elseif bag == 0 and type(PutItemInBackpack) == "function" then
            PutItemInBackpack()
        end
        BagUI:RequestRefresh(.12)
    end
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton ~= "LeftButton" then return end
        if CursorHasItem and CursorHasItem() then PlaceCursorBag()
        else PickupEquippedBag() end
    end)
    button:SetScript("OnReceiveDrag", PlaceCursorBag)
    button:SetScript("OnDragStart", PickupEquippedBag)
    button:SetScript("OnEnter", function(owner)
        GameTooltip:SetOwner(owner, "ANCHOR_TOP")
        local shown
        if button.inventorySlot and type(GameTooltip.SetInventoryItem) == "function" then
            shown = GameTooltip:SetInventoryItem("player", button.inventorySlot)
        end
        if not shown then GameTooltip:SetText(BagName(bag)) end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    self.bagButtons[bag] = button
end

function BagUI:Create()
    if self.frame then return end
    local frame = CreateFrame("Frame", "MythicBoostBagFrame", UIParent, "BackdropTemplate")
    frame:SetSize(431, 300)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    UI.Backdrop(frame, { .095, .115, .14, .74 }, { .10, .62, .76, 1 }, 2)
    self.frame, self.itemButtons, self.bagButtons = frame, {}, {}

    frame.header = CreateFrame("Button", nil, frame)
    frame.header:SetPoint("TOPLEFT", 1, -1)
    frame.header:SetPoint("TOPRIGHT", -1, -1)
    frame.header:SetHeight(48)
    frame.header:RegisterForDrag("LeftButton")
    frame.header:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame.header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        BagUI:SavePosition()
    end)
    local headerLine = UI.Line(frame, C.accent)
    headerLine:SetPoint("TOPLEFT", frame.header, "BOTTOMLEFT", 0, 0)
    headerLine:SetPoint("TOPRIGHT", frame.header, "BOTTOMRIGHT", 0, 0)
    frame.title = UI.Text(frame.header, "GameFontNormal", L("Инвентарь"), C.amber)
    frame.title:SetPoint("LEFT", 12, 0)
    frame.title:SetText("")
    frame.title:Hide()

    local close = UI.Button(frame.header, "×", 28, 26)
    close:SetPoint("RIGHT", -3, 0)
    close:SetScript("OnClick", function() BagUI:Hide() end)

    local sort = UI.Button(frame.header, L("СОРТ"), 54, 24)
    self.sortButton = sort
    sort:SetPoint("RIGHT", close, "LEFT", -5, 0)
    sort:SetScript("OnClick", function()
        if not C_Container or type(C_Container.SortBags) ~= "function" or BagUI.sorting then return end
        BagUI.sorting = true
        sort:Disable()
        if PlaySound and SOUNDKIT and SOUNDKIT.UI_BAG_SORTING_01 then PlaySound(SOUNDKIT.UI_BAG_SORTING_01) end
        pcall(C_Container.SortBags)
        BagUI:RequestRefresh(.20)
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(.75, function()
                BagUI.sorting = nil
                if BagUI.sortButton then BagUI.sortButton:Enable() end
                BagUI:RequestRefresh(0)
            end)
        else
            BagUI.sorting = nil
            sort:Enable()
        end
    end)
    sort:SetScript("OnEnter", function(owner)
        GameTooltip:SetOwner(owner, "ANCHOR_TOP")
        GameTooltip:SetText(L("Сортировать сумки"))
        GameTooltip:Show()
    end)
    sort:SetScript("OnLeave", GameTooltip_Hide)

    for index, bag in ipairs(BagIDs()) do self:BuildBagButton(frame, bag, 12 + (index - 1) * 38) end

    frame.capacity = UI.Text(frame, "GameFontHighlight", "0/0", C.text)
    frame.capacity:SetPoint("BOTTOMLEFT", 14, 14)
    frame.money = UI.Text(frame, "GameFontHighlight", "", C.text)
    frame.money:SetPoint("BOTTOMRIGHT", -14, 14)

    frame:SetScript("OnShow", function()
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_BACKPACK_OPEN then PlaySound(SOUNDKIT.IG_BACKPACK_OPEN) end
    end)
    frame:SetScript("OnHide", function()
        GameTooltip_Hide()
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_BACKPACK_CLOSE then PlaySound(SOUNDKIT.IG_BACKPACK_CLOSE) end
    end)
    frame:Hide()
    self:PlaceFrame()

    UISpecialFrames = UISpecialFrames or {}
    local found
    for _, name in ipairs(UISpecialFrames) do if name == frame:GetName() then found = true; break end end
    if not found then UISpecialFrames[#UISpecialFrames + 1] = frame:GetName() end

    self.events = CreateFrame("Frame")
    for _, event in ipairs({
        "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN", "PLAYER_MONEY", "PLAYER_ENTERING_WORLD",
    }) do self.events:RegisterEvent(event) end
    self.events:SetScript("OnEvent", function(_, event)
        if not BagUI.frame or not BagUI.frame:IsShown() then return end
        if event == "BAG_UPDATE_COOLDOWN" then
            BagUI:RefreshCooldowns()
        elseif event == "PLAYER_MONEY" then
            BagUI.frame.money:SetText(type(GetCoinTextureString) == "function"
                and GetCoinTextureString(GetMoney() or 0) or "")
        else
            BagUI:RequestRefresh()
        end
    end)

    if type(ToggleAllBags) == "function" and not self.toggleHooked then
        self.toggleHooked = true
        hooksecurefunc("ToggleAllBags", function()
            if BagUI.suppressCloseHook or not MythicBoostDB or not Settings().enabled or BagUI.externalConflict then return end
            BagUI:Toggle()
            BagUI:HideBlizzardContainers()
        end)
    end
    if type(CloseAllBags) == "function" and not self.closeHooked then
        self.closeHooked = true
        hooksecurefunc("CloseAllBags", function()
            if not BagUI.suppressCloseHook then BagUI:Hide() end
        end)
    end
end

function BagUI:Enable()
    self:Create()
    self.externalConflict = IsAddonLoadedSafe("Bagnon")
        or IsAddonLoadedSafe("AdiBags") or IsAddonLoadedSafe("BetterBags")
    if self.externalConflict and Settings().enabled and not self.conflictReported then
        self.conflictReported = true
        JP:Print(L("Единый инвентарь готов. Отключи Bagnon/AdiBags/BetterBags и сделай /reload, чтобы окна не дублировались."))
    end
end

function BagUI:Disable() self:Hide() end
function BagUI:Destroy() self:Disable() end

JP.BagUI = BagUI
JP:RegisterModule("BagUI", BagUI)
