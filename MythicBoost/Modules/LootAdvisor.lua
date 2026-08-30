local _, JP = ...
local LootAdvisor = { cache = {} }

local PREVIEW_KEY_LEVEL = 10
-- Encounter Journal возвращает для preview Mythic+ ссылку на базовый шаблон
-- предмета. В Midnight её GetDetailedItemLevelInfo может быть равен 63, хотя
-- награда за окончание +10 имеет 311-й уровень. Поэтому ссылку используем для
-- имени, иконки и слота, а сравниваем с реальным уровнем end-of-run награды.
local PREVIEW_DROP_ITEM_LEVEL = 311
local SLOT_IDS = {
    [0] = {1}, [1] = {2}, [2] = {3}, [3] = {15}, [4] = {5},
    [5] = {9}, [6] = {10}, [7] = {6}, [8] = {7}, [9] = {8},
    [10] = {16}, [11] = {17}, [12] = {11,12}, [13] = {13,14},
}

local function UsableNumber(value)
    return type(value) == "number" and not issecretvalue(value)
end

local function ItemLevel(link)
    if not link then return 0 end
    local level = C_Item and C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)
    return UsableNumber(level) and level or 0
end

local function EquippedItemLevel(slotID)
    -- GetCurrentItemLevel читает ItemLocation напрямую и не зависит от того,
    -- успел ли клиент собрать полную item-link. На старых клиентах остаётся
    -- прежний безопасный путь.
    if ItemLocation and ItemLocation.CreateFromEquipmentSlot and C_Item and C_Item.GetCurrentItemLevel then
        local location = ItemLocation:CreateFromEquipmentSlot(slotID)
        if location and location:IsValid() then
            local level = C_Item.GetCurrentItemLevel(location)
            if UsableNumber(level) and level > 0 then return level end
        end
    end
    return ItemLevel(GetInventoryItemLink("player", slotID))
end

local function EquippedLevel(filterType)
    local slots = SLOT_IDS[filterType]
    if not slots then return end
    local lowest
    for _, slotID in ipairs(slots) do
        local level = EquippedItemLevel(slotID)
        if level > 0 and (not lowest or level < lowest) then lowest = level end
    end
    if filterType == 11 and not lowest then lowest = EquippedItemLevel(16) end
    return lowest or 0
end

local function EquipmentSignature()
    local parts = {tostring(GetSpecialization and GetSpecialization() or 0)}
    local pending = false
    for slotID = 1, 17 do
        local level = EquippedItemLevel(slotID)
        if GetInventoryItemID("player", slotID) and level <= 0 then pending = true end
        parts[#parts + 1] = tostring(level)
    end
    return table.concat(parts, ":"), pending
end

local function InstanceMapID(dungeon)
    local runDungeon = dungeon and dungeon.run and dungeon.run.dungeon
    local instanceMaps = runDungeon and runDungeon.instance_map_ids
    return type(instanceMaps) == "table" and instanceMaps[1] or dungeon and dungeon.instanceMapID
end

local function ConfigureJournal()
    if EncounterJournal_LoadUI then EncounterJournal_LoadUI() end
    if not C_EncounterJournal or not C_EncounterJournal.GetInstanceForGameMap then return false end
    local oldClassID, oldSpecID
    if EJ_GetLootFilter then oldClassID, oldSpecID = EJ_GetLootFilter() end
    local state = {
        classID = oldClassID,
        specID = oldSpecID,
        difficulty = EJ_GetDifficulty and EJ_GetDifficulty(),
        slotFilter = C_EncounterJournal.GetSlotFilter and C_EncounterJournal.GetSlotFilter(),
        instanceID = EncounterJournal and EncounterJournal.instanceID,
    }
    local _, _, classID = UnitClass("player")
    local specIndex = GetSpecialization and GetSpecialization()
    local specID = specIndex and GetSpecializationInfo(specIndex)
    if EJ_SetLootFilter and classID and specID then EJ_SetLootFilter(classID, specID) end
    if EJ_SetDifficulty then EJ_SetDifficulty(23) end
    if C_EncounterJournal.ResetSlotFilter then C_EncounterJournal.ResetSlotFilter() end
    if C_EncounterJournal.SetPreviewMythicPlusLevel then C_EncounterJournal.SetPreviewMythicPlusLevel(PREVIEW_KEY_LEVEL) end
    return state
end

local function RestoreJournal(state)
    if not state then return end
    if state.instanceID and EJ_SelectInstance then EJ_SelectInstance(state.instanceID) end
    if state.difficulty and EJ_SetDifficulty then EJ_SetDifficulty(state.difficulty) end
    if EJ_SetLootFilter and state.classID then EJ_SetLootFilter(state.classID, state.specID or 0) end
    if C_EncounterJournal and C_EncounterJournal.SetSlotFilter and state.slotFilter ~= nil then
        C_EncounterJournal.SetSlotFilter(state.slotFilter)
    end
end

local function AnalyzeDungeon(dungeon, specID)
    local instanceMapID = InstanceMapID(dungeon)
    local journalID = instanceMapID and C_EncounterJournal.GetInstanceForGameMap(instanceMapID)
    if not journalID or not EJ_SelectInstance or not EJ_GetNumLoot then return {percent=0,total=0,upgrades={},pending=false} end
    EJ_SelectInstance(journalID)
    local total, upgrades, pending, totalGain = 0, {}, false, 0
    local usefulCount, upgradeCount, bisCount, topCount = 0, 0, 0, 0
    local upgradeSlots = {}
    for lootIndex = 1, EJ_GetNumLoot() do
        local item = C_EncounterJournal.GetLootInfoByIndex(lootIndex)
        if item and (not item.name or not item.link) then
            pending = true
            if item.itemID and C_Item and C_Item.RequestLoadItemDataByID then
                C_Item.RequestLoadItemDataByID(item.itemID)
            end
        end
        local filterType = item and item.filterType
        -- Через "and" без "or nil" сюда попадал false, когда filterType пуст,
        -- и сравнение dropLevel > equipped роняло разбор добычи.
        local equipped
        if filterType ~= nil then equipped = EquippedLevel(filterType) end
        -- В знаменатель попадает только добыча, доступная текущему классу/спеку.
        -- Encounter Journal помечает неподходящие оружие и предметы этими ошибками.
        if item and not item.handError and not item.weaponTypeError and type(equipped) == "number" then
            total = total + 1
            local baseItemLevel = ItemLevel(item.link)
            if baseItemLevel <= 0 then
                pending = true
                if item.itemID and C_Item and C_Item.RequestLoadItemDataByID then
                    C_Item.RequestLoadItemDataByID(item.itemID)
                end
            end
            local dropLevel = PREVIEW_DROP_ITEM_LEVEL
            local recommendation = JP.BiSData and JP.BiSData.GetItem
                and JP.BiSData:GetItem(specID, item.itemID)
            local isUpgrade = dropLevel > equipped
            -- BIS/TOP остаётся полезной целью даже при том же ilvl: именно
            -- ради этого советчик больше не является только сравнением уровня.
            if isUpgrade or recommendation then
                local itemName = item.name
                if not itemName and item.itemID and C_Item and C_Item.GetItemNameByID then itemName = C_Item.GetItemNameByID(item.itemID) end
                local gain = math.max(0, dropLevel - equipped)
                usefulCount = usefulCount + 1
                if isUpgrade then
                    upgradeCount = upgradeCount + 1
                    totalGain = totalGain + gain
                end
                if recommendation and recommendation.kind == "bis" then bisCount = bisCount + 1 end
                if recommendation and recommendation.kind == "top" then topCount = topCount + 1 end
                upgradeSlots[filterType] = true
                upgrades[#upgrades + 1] = {
                    itemID=item.itemID, name=itemName or "Предмет",
                    icon=item.icon, link=item.link, slot=item.slot or "Слот", equipped=equipped,
                    level=dropLevel, gain=gain, isUpgrade=isUpgrade,
                    recommendation=recommendation,
                }
            end
        end
    end
    table.sort(upgrades, function(a,b)
        local aKind = a.recommendation and (a.recommendation.kind == "bis" and 3 or 2) or 1
        local bKind = b.recommendation and (b.recommendation.kind == "bis" and 3 or 2) or 1
        if aKind ~= bKind then return aKind > bKind end
        local aShare = a.recommendation and a.recommendation.share or 0
        local bShare = b.recommendation and b.recommendation.share or 0
        if aShare ~= bShare then return aShare > bShare end
        return (a.gain or 0) > (b.gain or 0)
    end)
    local slotCount = 0
    for _ in pairs(upgradeSlots) do slotCount = slotCount + 1 end
    return {
        percent=total>0 and math.floor(usefulCount/total*100+.5) or 0,
        total=total, useful=usefulCount, upgradeCount=upgradeCount,
        bisCount=bisCount, topCount=topCount, slotCount=slotCount, upgrades=upgrades,
        averageGain=upgradeCount>0 and math.floor(totalGain/upgradeCount+.5) or 0,
        pending=pending,
        keyLevel=PREVIEW_KEY_LEVEL,
        dropLevel=PREVIEW_DROP_ITEM_LEVEL,
    }
end

function LootAdvisor:Analyze(dungeons)
    local signature, equipmentPending = EquipmentSignature()
    -- Не закрепляем навсегда первый неполный ответ Encounter Journal. При
    -- открытии окна ссылки/уровни добычи часто ещё грузятся; такой кэш и давал
    -- ложное "Улучшений по ilvl не найдено" до следующего /reload.
    if not equipmentPending and not self.cache.pending
        and self.cache.signature == signature and self.cache.results then
        return self.cache.results
    end
    local results = {}
    local journalState = ConfigureJournal()
    if not journalState then return results end
    local specID = JP.BiSData and JP.BiSData.GetCurrentSpecID and JP.BiSData:GetCurrentSpecID()
    local pending = false
    for _, dungeon in ipairs(dungeons or {}) do
        results[dungeon.mapID] = AnalyzeDungeon(dungeon, specID)
        pending = results[dungeon.mapID].pending or pending
    end
    RestoreJournal(journalState)
    self.cache = {signature=signature,results=results,pending=pending or equipmentPending}
    return results
end

function LootAdvisor:Invalidate()
    wipe(self.cache)
    local welcome = JP.modules.Welcome
    if welcome and welcome.frame and welcome.frame:IsShown() then C_Timer.After(.15, function() welcome:Refresh() end) end
end

function LootAdvisor:Create()
    if self.events then return end
    self.events = CreateFrame("Frame")
    self.events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    self.events:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    self.events:RegisterEvent("EJ_LOOT_DATA_RECIEVED")
    self.events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    self.events:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.events:SetScript("OnEvent", function(_, event, unit)
        if event == "EJ_LOOT_DATA_RECIEVED" or event == "GET_ITEM_INFO_RECEIVED" then
            -- Данные о предметах приходят пачками, и каждый ответ обнулял кэш,
            -- вызывая новый полный обход журнала. Если после нескольких попыток
            -- таблица так и не собралась, перестаём гоняться за ней: пересчёт
            -- всё равно случится при смене экипировки или специализации.
            if not self.cache.pending or self.refreshQueued then return end
            self.pendingRetries = (self.pendingRetries or 0) + 1
            if self.pendingRetries > 6 then return end
            self.refreshQueued = true
            C_Timer.After(.25, function()
                self.refreshQueued = nil
                self:Invalidate()
            end)
        elseif event ~= "PLAYER_SPECIALIZATION_CHANGED" or unit == "player" then
            self.pendingRetries = 0
            self:Invalidate()
        end
    end)
end

function LootAdvisor:Enable() end
function LootAdvisor:Disable() end
function LootAdvisor:Destroy() end

JP.LootAdvisor = LootAdvisor
JP:RegisterModule("LootAdvisor", LootAdvisor)
