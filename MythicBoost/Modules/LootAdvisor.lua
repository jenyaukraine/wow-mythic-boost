local _, JP = ...
local L = JP.L
local LootAdvisor = { cache = {} }

local DEFAULT_PREVIEW_KEY_LEVEL = 10
local MYTHIC_PLUS_DIFFICULTY_ID = 8
local EQUIPMENT_SLOTS = {1,2,3,5,6,7,8,9,10,11,12,13,14,15,16,17}
local SLOT_IDS = {
    [0] = {1}, [1] = {2}, [2] = {3}, [3] = {15}, [4] = {5},
    [5] = {9}, [6] = {10}, [7] = {6}, [8] = {7}, [9] = {8},
    [10] = {16}, [11] = {17}, [12] = {11,12}, [13] = {13,14},
}

local UsableNumber = JP.UI.UsableNumber

local function PreviewKeyLevel(value)
    value = tonumber(value)
    return UsableNumber(value) and value >= 2 and math.floor(value) or DEFAULT_PREVIEW_KEY_LEVEL
end

local function RewardItemLevel(keyLevel)
    return JP.API.GetRewardLevel(keyLevel).level
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

local function EquippedLevel(filterType, equipment)
    local slots = SLOT_IDS[filterType]
    if not slots then return end
    local lowest
    for _, slotID in ipairs(slots) do
        local level = equipment.levels[slotID]
        if level == nil then return nil end
        if level > 0 and (not lowest or level < lowest) then lowest = level end
    end
    if filterType == 11 and not lowest then return equipment.levels[16] end
    return lowest or 0
end

local function EquipmentSnapshot()
    local specIndex = GetSpecialization and GetSpecialization()
    local specID = specIndex and GetSpecializationInfo and GetSpecializationInfo(specIndex)
    local parts = {tostring(specID or specIndex or 0)}
    local equipment = {levels={}, ids={}, loaded=0, total=0, pending=false}
    for _, slotID in ipairs(EQUIPMENT_SLOTS) do
        local itemID = GetInventoryItemID("player", slotID)
        local level = itemID and EquippedItemLevel(slotID) or 0
        equipment.ids[slotID] = itemID
        if itemID then
            equipment.total = equipment.total + 1
            if level > 0 then
                equipment.loaded = equipment.loaded + 1
            else
                equipment.pending = true
                level = nil -- An unread equipped item is not an empty slot.
            end
        end
        equipment.levels[slotID] = level
        parts[#parts + 1] = tostring(itemID or 0) .. "@" .. tostring(level)
    end
    equipment.signature = table.concat(parts, ":")
    return equipment
end

local function OwnedItemLevels(equipment)
    local owned, pending = {}, false
    local function Remember(itemID, level)
        if not itemID then return end
        if level and level > 0 then
            owned[itemID] = math.max(owned[itemID] or 0, level)
        else
            -- Never hide a possible upgrade on an incomplete item response.
            pending = true
            owned[itemID] = owned[itemID] or 0 -- Ownership is known even without ilvl.
            if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
        end
    end
    for _, slotID in ipairs(EQUIPMENT_SLOTS) do
        Remember(equipment.ids[slotID], equipment.levels[slotID])
    end
    -- One inventory snapshot per analysis, not one bag scan per journal item.
    if C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemID then
        for bag = 0, NUM_BAG_SLOTS or 4 do
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                local itemID = C_Container.GetContainerItemID(bag, slot)
                local equipLoc
                if itemID and C_Item and C_Item.GetItemInfoInstant then
                    local _, _, _, location = C_Item.GetItemInfoInstant(itemID)
                    equipLoc = location
                end
                -- Skip consumables/reagents before requesting item-level data.
                if equipLoc and equipLoc ~= "" then
                    local level = 0
                    if ItemLocation and ItemLocation.CreateFromBagAndSlot and C_Item and C_Item.GetCurrentItemLevel then
                        local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
                        if location:IsValid() then
                            local value = C_Item.GetCurrentItemLevel(location)
                            if UsableNumber(value) then level = value end
                        end
                    end
                    if level <= 0 and C_Container.GetContainerItemLink then
                        level = ItemLevel(C_Container.GetContainerItemLink(bag, slot))
                    end
                    Remember(itemID, level)
                end
            end
        end
    end
    return owned, pending
end

local function InstanceMapID(dungeon)
    local runDungeon = dungeon and dungeon.run and dungeon.run.dungeon
    local instanceMaps = runDungeon and runDungeon.instance_map_ids
    return type(instanceMaps) == "table" and instanceMaps[1] or dungeon and dungeon.instanceMapID
end

local function ConfigureJournal()
    if not C_EncounterJournal and EncounterJournal_LoadUI then EncounterJournal_LoadUI() end
    if not C_EncounterJournal or not C_EncounterJournal.GetInstanceForGameMap then return false end
    local oldClassID, oldSpecID
    if EJ_GetLootFilter then oldClassID, oldSpecID = EJ_GetLootFilter() end
    local state = {
        classID = oldClassID,
        specID = oldSpecID,
        difficulty = EJ_GetDifficulty and EJ_GetDifficulty(),
        slotFilter = C_EncounterJournal.GetSlotFilter and C_EncounterJournal.GetSlotFilter(),
        instanceID = EncounterJournal and EncounterJournal.instanceID,
        encounterID = EncounterJournal and EncounterJournal.encounterID,
    }
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
    -- Filter/difficulty events can reselect the visible journal's encounter.
    if state.instanceID and EJ_SelectInstance then EJ_SelectInstance(state.instanceID) end
    if state.encounterID and EJ_SelectEncounter then EJ_SelectEncounter(state.encounterID) end
end

local function AnalyzeDungeon(dungeon, specID, owned, equipment, keyLevel, dropLevel, raidDifficulty)
    local instanceMapID = InstanceMapID(dungeon)
    local journalID = dungeon.journalID or (instanceMapID and C_EncounterJournal.GetInstanceForGameMap(instanceMapID))
    if not UsableNumber(journalID) or journalID <= 0 or not EJ_SelectInstance
        or not EJ_GetNumLoot or not EJ_GetEncounterInfoByIndex then
        return {percent=0,total=0,upgrades={},pending=true}
    end
    EJ_SelectInstance(journalID)
    -- Selecting an instance can reset an unsupported previous difficulty.
    -- Apply ALL preview settings after the selection, for every dungeon.
    if EJ_SetDifficulty then EJ_SetDifficulty(raidDifficulty or MYTHIC_PLUS_DIFFICULTY_ID) end
    if not raidDifficulty and C_EncounterJournal.SetPreviewMythicPlusLevel then C_EncounterJournal.SetPreviewMythicPlusLevel(keyLevel) end
    local _, _, classID = UnitClass("player")
    local specIndex = GetSpecialization and GetSpecialization()
    local lootSpecID = specIndex and GetSpecializationInfo(specIndex)
    if EJ_SetLootFilter and classID and lootSpecID then EJ_SetLootFilter(classID, lootSpecID) end
    if C_EncounterJournal.ResetSlotFilter then C_EncounterJournal.ResetSlotFilter() end
    -- EJ_DIFFICULTY_UPDATE refreshes Blizzard's visible journal synchronously
    -- and can select its old boss again. Select our instance AFTER those events.
    EJ_SelectInstance(journalID)
    if EJ_GetDifficulty and EJ_GetDifficulty() ~= (raidDifficulty or MYTHIC_PLUS_DIFFICULTY_ID) then
        return {percent=0,total=0,upgrades={},pending=true}
    end
    local encounters = {}
    local encounterIndex = 1
    while true do
        local name, _, encounterID = EJ_GetEncounterInfoByIndex(encounterIndex, journalID)
        if not name then break end
        if UsableNumber(encounterID) and encounterID > 0 then encounters[encounterID] = true end
        encounterIndex = encounterIndex + 1
    end
    local total, upgrades, pending, totalGain = 0, {}, false, 0
    local usefulCount, upgradeCount, bisCount, topCount = 0, 0, 0, 0
    local upgradeSlots = {}
    local lootCount = EJ_GetNumLoot()
    if lootCount == 0 then pending = true end
    local seen = {}
    for lootIndex = 1, lootCount do
        local item = C_EncounterJournal.GetLootInfoByIndex(lootIndex)
        -- Loaded item data alone does not prove the global loot list is ours.
        -- Do not cache a foreign boss's BiS item under every dungeon card.
        if item and not encounters[item.encounterID] then
            pending = true
            item = nil
        end
        if not item or not item.name or not item.link then
            pending = true
            if item and item.itemID and C_Item and C_Item.RequestLoadItemDataByID then
                C_Item.RequestLoadItemDataByID(item.itemID)
            end
        end
        local filterType = item and item.filterType
        -- Через "and" без "or nil" сюда попадал false, когда filterType пуст,
        -- и сравнение dropLevel > equipped роняло разбор добычи.
        local equipped
        if filterType ~= nil then equipped = EquippedLevel(filterType, equipment) end
        -- В знаменатель попадает только добыча, доступная текущему классу/спеку.
        -- Encounter Journal помечает неподходящие оружие и предметы этими ошибками.
        local lootKey = item and item.itemID and (tostring(item.itemID) .. ":" .. tostring(item.encounterID or 0))
        if item and lootKey and not seen[lootKey] and not item.handError and not item.weaponTypeError and filterType ~= nil and SLOT_IDS[filterType] then
            seen[lootKey] = true
            total = total + 1
            local baseItemLevel = ItemLevel(item.link)
            -- Raid bosses can drop different ilvls at the same difficulty.
            -- Never use the Mythic+ reward table or one raid-wide level here.
            local dropLevel = raidDifficulty and (baseItemLevel > 0 and baseItemLevel or nil) or dropLevel
            local scaledLink = dropLevel and baseItemLevel == dropLevel and item.link or nil
            -- A cached base/Heroic link may never become a scaled M+ link.
            -- The reward level still gives valid recommendations. Do not
            -- keep the entire panel loading for an unavailable tooltip.
            if baseItemLevel <= 0 then
                pending = true
                if item.itemID and C_Item and C_Item.RequestLoadItemDataByID then
                    C_Item.RequestLoadItemDataByID(item.itemID)
                end
            end
            local recommendation = JP.BiSData and JP.BiSData.GetItem
                and JP.BiSData:GetItem(specID, item.itemID, raidDifficulty and "raid" or "mplus")
            local isUpgrade = dropLevel and equipped ~= nil and dropLevel > equipped
            -- A different BIS can help at equal ilvl, but another copy of an
            -- already owned item at this level (or better) is not a goal.
            local ownedLevel = owned[item.itemID]
            local alreadyOwned = ownedLevel ~= nil and (not dropLevel or ownedLevel >= dropLevel)
            if not alreadyOwned and (isUpgrade or recommendation) then
                local itemName = item.name
                if not itemName and item.itemID and C_Item and C_Item.GetItemNameByID then itemName = C_Item.GetItemNameByID(item.itemID) end
                local gain = dropLevel and equipped ~= nil and (dropLevel - equipped) or nil
                usefulCount = usefulCount + 1
                if isUpgrade then
                    upgradeCount = upgradeCount + 1
                    totalGain = totalGain + gain
                end
                if recommendation and recommendation.kind == "bis" then bisCount = bisCount + 1 end
                if recommendation and recommendation.kind == "top" then topCount = topCount + 1 end
                upgradeSlots[filterType] = true
                upgrades[#upgrades + 1] = {
                    itemID=item.itemID, name=itemName or L("Предмет"),
                    icon=item.icon, link=scaledLink, tooltipLink=item.link,
                    slot=item.slot or L("Слот"), equipped=equipped,
                    level=dropLevel, keyLevel=keyLevel, gain=gain, isUpgrade=isUpgrade,
                    recommendation=recommendation,
                    encounterID=item.encounterID, difficultyID=raidDifficulty,
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
        keyLevel=keyLevel,
        difficultyID=raidDifficulty,
        dropLevel=dropLevel,
        rewardUnknown=not dropLevel,
        equipmentLoaded=equipment.loaded, equipmentTotal=equipment.total,
        equipmentPending=equipment.pending,
    }
end

function LootAdvisor:Analyze(dungeons, requestedKeyLevel, raidDifficulty)
    if raidDifficulty and raidDifficulty ~= 14 and raidDifficulty ~= 15 and raidDifficulty ~= 16 then return {} end
    local keyLevel = not raidDifficulty and PreviewKeyLevel(requestedKeyLevel) or nil
    local dropLevel = keyLevel and RewardItemLevel(keyLevel)
    -- The startup request can precede the reward service being ready. Retry
    -- only while advice is requested, at most once per 30 sec (no polling timer).
    if not raidDifficulty and not dropLevel and GetTime and C_MythicPlus and C_MythicPlus.RequestRewards then
        local now = GetTime()
        if not self.rewardRequestAt or now-self.rewardRequestAt >= 30 then
            self.rewardRequestAt = now
            C_MythicPlus.RequestRewards()
            if C_MythicPlus.RequestMapInfo then C_MythicPlus.RequestMapInfo() end
        end
    end
    local equipment = EquipmentSnapshot()
    local signature = equipment.signature
    local dungeonIDs = {}
    for _, dungeon in ipairs(dungeons or {}) do
        dungeonIDs[#dungeonIDs + 1] = tostring(dungeon.mapID) .. "@" .. tostring(dungeon.journalID or InstanceMapID(dungeon))
    end
    signature = signature .. (raidDifficulty and ":raid:" or ":mplus:") .. tostring(raidDifficulty or keyLevel)
        .. ":" .. tostring(dropLevel) .. ":" .. table.concat(dungeonIDs, ",")
    -- Не закрепляем навсегда первый неполный ответ Encounter Journal. При
    -- открытии окна ссылки/уровни добычи часто ещё грузятся; такой кэш и давал
    -- ложное "Улучшений по ilvl не найдено" до следующего /reload.
    if not equipment.pending and not self.cache.pending
        and self.cache.signature == signature and self.cache.results then
        return self.cache.results
    end
    local results = {}
    local journalState = ConfigureJournal()
    if not journalState then return results end
    local specID = JP.BiSData and JP.BiSData.GetCurrentSpecID and JP.BiSData:GetCurrentSpecID()
    local owned, pending = OwnedItemLevels(equipment)
    local ok, err = pcall(function()
        for _, dungeon in ipairs(dungeons or {}) do
            results[dungeon.mapID] = AnalyzeDungeon(dungeon, specID, owned, equipment, keyLevel, dropLevel, raidDifficulty)
            pending = results[dungeon.mapID].pending or pending
        end
    end)
    -- Restore filters even when an asynchronous journal response is malformed.
    RestoreJournal(journalState)
    if not ok then error(err, 0) end
    self.cache = {signature=signature,results=results,pending=pending or equipment.pending or (not raidDifficulty and not dropLevel)}
    return results
end

function LootAdvisor:Invalidate()
    wipe(self.cache)
    local welcome = JP.modules.Welcome
    if welcome and welcome.frame and welcome.frame:IsShown() and not self.uiRefreshQueued then
        self.uiRefreshQueued = true
        C_Timer.After(.15, function()
            self.uiRefreshQueued = nil
            if welcome.frame:IsShown() then welcome:Refresh() end
        end)
    end
end

function LootAdvisor:Create()
    if self.events then return end
    if C_MythicPlus and C_MythicPlus.RequestRewards then C_MythicPlus.RequestRewards() end
    self.events = CreateFrame("Frame")
    self.events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    self.events:RegisterEvent("BAG_UPDATE_DELAYED")
    self.events:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    self.events:RegisterEvent("EJ_LOOT_DATA_RECIEVED")
    self.events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    self.events:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.events:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
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
            if event == "PLAYER_ENTERING_WORLD" then self.rewardRequestAt = nil end
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
