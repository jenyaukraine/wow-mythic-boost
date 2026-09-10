local _, JP = ...
local L = JP.L
local CharacterBiS = { buttons = {}, hookedFrames = {} }
local tooltipMarked = setmetatable({}, {__mode = "k"})
local PAIRED_SLOT = { [11] = 12, [12] = 11, [13] = 14, [14] = 13 }
local SLOTS = {
    {1, "HeadSlot"}, {2, "NeckSlot"}, {3, "ShoulderSlot"}, {5, "ChestSlot"},
    {6, "WaistSlot"}, {7, "LegsSlot"}, {8, "FeetSlot"}, {9, "WristSlot"},
    {10, "HandsSlot"}, {11, "Finger0Slot"}, {12, "Finger1Slot"},
    {13, "Trinket0Slot"}, {14, "Trinket1Slot"}, {15, "BackSlot"},
    {16, "MainHandSlot"}, {17, "SecondaryHandSlot"},
}
local function Call(fn, ...) return JP.SafeCall(fn, ...) end
local function Accessible(frame)
    return frame and (not frame.IsForbidden or not frame:IsForbidden())
end
local function Context(record)
    if record.prefix == "Character" then
        return "player", JP.BiSData:GetCurrentSpecID()
    end
    local unit = _G.InspectFrame and JP.SafeString(_G.InspectFrame.unit)
    if not unit then return end
    -- Never apply the viewer's specialization to somebody else's equipment.
    local inspectSpec = C_SpecializationInfo and C_SpecializationInfo.GetInspectSpecialization
        or GetInspectSpecialization
    local specID = JP.SafeNumber(Call(inspectSpec, unit))
    return unit, specID and specID > 0 and specID or nil
end
local function Equipped(unit, slot)
    return unit and JP.SafeNumber(Call(GetInventoryItemID, unit, slot))
end
local function HideBadge(record)
    record.label:Hide(); record.background:Hide()
    for _, line in ipairs(record.border) do line:Hide() end
end
local function CreateBadge(button, prefix, slot)
    local record = { prefix = prefix, slot = slot, border = {} }
    local bg = button:CreateTexture(nil, "OVERLAY", nil, 5)
    bg:SetColorTexture(.025, .018, .005, .94)
    bg:SetPoint("BOTTOMLEFT", 1, 1); bg:SetPoint("BOTTOMRIGHT", -1, 1)
    bg:SetHeight(13)
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetDrawLayer("OVERLAY", 7)
    text:SetPoint("CENTER", bg, "CENTER", 0, 0)
    text:SetTextColor(1, .79, .24); text:SetText("BIS")
    record.label, record.background = text, bg
    for index = 1, 4 do
        local line = button:CreateTexture(nil, "OVERLAY", nil, 6)
        line:SetColorTexture(1, .72, .12, .95)
        if index == 1 or index == 2 then
            local side = index == 1 and "TOP" or "BOTTOM"
            line:SetPoint(side .. "LEFT", 0, 0); line:SetPoint(side .. "RIGHT", 0, 0)
            line:SetHeight(1)
        else
            local side = index == 3 and "LEFT" or "RIGHT"
            line:SetPoint("TOP" .. side, 0, 0); line:SetPoint("BOTTOM" .. side, 0, 0)
            line:SetWidth(1)
        end
        record.border[index] = line
    end
    HideBadge(record)
    return record
end

function CharacterBiS:HookFrames()
    -- Equipment buttons can be protected. Create only artwork, out of combat;
    -- never replace their scripts, attributes, click actions or native borders.
    if InCombatLockdown and InCombatLockdown() then return end
    for _, prefix in ipairs({"Character", "Inspect"}) do
        local parent = _G[prefix == "Character" and "PaperDollFrame" or "InspectFrame"]
        if Accessible(parent) then
            if not self.hookedFrames[parent] then
                self.hookedFrames[parent] = true
                parent:HookScript("OnShow", function() self:Refresh() end)
            end
            for _, slot in ipairs(SLOTS) do
                local button = _G[prefix .. slot[2]]
                if Accessible(button) and not self.buttons[button] then
                    self.buttons[button] = CreateBadge(button, prefix, slot[1])
                end
            end
        end
    end
end

function CharacterBiS:Refresh()
    for button, record in pairs(self.buttons) do
        HideBadge(record)
        if self.running and button:IsShown() then
            local unit, specID = Context(record)
            local itemID = Equipped(unit, record.slot)
            local recommendation = itemID and specID and (JP.BiSData:GetItem(specID, itemID, "overall")
                or JP.BiSData:GetTierItem(specID, itemID))
            if recommendation and (recommendation.kind == "bis" or recommendation.kind == "tier") then
                local isBiS = recommendation.kind == "bis"
                record.label:SetText(isBiS and "BIS" or "TIER")
                record.label:SetTextColor(isBiS and 1 or .35, isBiS and .79 or .82, isBiS and .24 or 1)
                record.label:Show(); record.background:Show()
                if isBiS then for _, line in ipairs(record.border) do line:Show() end end
            end
        end
    end
end

local function SpecName(specID)
    local infoByID = C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfoByID
        or GetSpecializationInfoByID
    if type(infoByID) ~= "function" then return tostring(specID) end
    local ok, _, name = pcall(infoByID, specID)
    return ok and JP.SafeString(name) or tostring(specID)
end
local function ItemName(recommendation)
    local name = C_Item and JP.SafeString(Call(C_Item.GetItemNameByID, recommendation.itemID))
    if not name and C_Item then Call(C_Item.RequestLoadItemDataByID, recommendation.itemID) end
    return name or recommendation.name or ("#" .. recommendation.itemID)
end

function CharacterBiS:AddTooltip(tooltip, data)
    if not self.running or tooltip ~= GameTooltip or not Accessible(tooltip) then return end
    local record = self.buttons[tooltip:GetOwner()]
    if not record or tooltipMarked[tooltip] then return end
    local unit, specID = Context(record)
    local itemID = Equipped(unit, record.slot)
    -- An item tooltip may be rebuilt asynchronously after equipment changes.
    -- Annotate only the item actually displayed in this slot's tooltip.
    if not itemID or itemID ~= (data and JP.SafeNumber(data.id)) then return end
    tooltipMarked[tooltip] = true
    if not specID then
        tooltip:AddLine(" ")
        tooltip:AddLine(L("BIS: специализация осматриваемого игрока пока неизвестна."), .62, .68, .76, true)
        return
    end
    local equipped = JP.BiSData:GetItem(specID, itemID, "overall")
        or JP.BiSData:GetTierItem(specID, itemID)
    local recommendations = {}
    local pairedID = PAIRED_SLOT[record.slot] and Equipped(unit, PAIRED_SLOT[record.slot])
    for _, recommendation in ipairs(JP.BiSData:GetRecommendationsForSlot(specID, record.slot, "overall")) do
        -- A ring/trinket worn in the other slot is already owned. Do not send
        -- the player to obtain a second copy of that same recommendation.
        if recommendation.itemID ~= pairedID then recommendations[#recommendations + 1] = recommendation end
    end
    if not equipped and #recommendations == 0 then return end
    tooltip:AddLine(" ")
    tooltip:AddLine(L("BIS для специализации: %s"):format(SpecName(specID)), 1, .79, .24)
    if equipped and equipped.kind == "bis" then
        tooltip:AddLine(L("Этот предмет входит в общий BIS-список."), .3, 1, .55, true)
        if equipped.isTier then tooltip:AddLine(L("Предмет классового комплекта"), 1, .79, .24) end
    else
        if equipped and equipped.isTier then tooltip:AddLine(L("Предмет классового комплекта"), .35, .82, 1) end
        tooltip:AddLine(L("BIS для этого слота и где его получить:"), .83, .89, .95, true)
        for index = 1, math.min(4, #recommendations) do
            local recommendation = recommendations[index]
            tooltip:AddLine(ItemName(recommendation), 1, .79, .24, true)
            tooltip:AddLine(JP.BiSData:GetSourceText(recommendation), .69, .77, .85, true)
        end
    end
    tooltip:AddLine(L("BIS по гайду Wowhead"), .62, .68, .76)
    tooltip:AddLine(L("Отметка BIS не сравнивает уровень предметов и бонусы комплекта."), .62, .68, .76, true)
end

function CharacterBiS:Create()
    if self.events then return end
    self.events = CreateFrame("Frame")
    self.events:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_SPECIALIZATION_CHANGED" and unit ~= "player" then return end
        self:HookFrames(); self:Refresh()
    end)
    if TooltipDataProcessor and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            self:AddTooltip(tooltip, data)
        end)
        GameTooltip:HookScript("OnTooltipCleared", function(tooltip)
            tooltipMarked[tooltip] = nil
        end)
    end
end
function CharacterBiS:Enable()
    self:Create(); self.running = true
    for _, event in ipairs({"ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED",
        "PLAYER_SPECIALIZATION_CHANGED", "INSPECT_READY", "PLAYER_REGEN_ENABLED"}) do
        self.events:RegisterEvent(event)
    end
    self:HookFrames(); self:Refresh()
end
function CharacterBiS:Disable()
    self.running = false
    if self.events then self.events:UnregisterAllEvents() end
    self:Refresh()
end
function CharacterBiS:Destroy() self:Disable() end
JP:RegisterModule("CharacterBiS", CharacterBiS)
