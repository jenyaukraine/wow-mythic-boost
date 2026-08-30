local _, JP = ...
local Convenience = {}
local UI = JP.UI

local function Settings()
    MythicBoostDB.convenience = type(MythicBoostDB.convenience) == "table" and MythicBoostDB.convenience or {}
    return MythicBoostDB.convenience
end

local function Enabled(key)
    return Settings()[key] == true
end

local function PrintMoney(prefix, copper)
    -- Сумма собирается из цен, которые называет игра, а защищённое значение
    -- нельзя сравнивать. Отсекаем его до «<= 0», а не после.
    if not UI.UsableNumber(copper) or copper <= 0 then return end
    local text = GetMoneyString and GetMoneyString(copper, true) or tostring(copper)
    JP:Print(prefix .. ": " .. text)
end

local function IsKeystone(itemID)
    if type(itemID) ~= "number" or issecretvalue(itemID) then return false end
    if C_Item and type(C_Item.IsItemKeystoneByID) == "function" then
        local ok, result = pcall(C_Item.IsItemKeystoneByID, itemID)
        if ok and type(result) == "boolean" and not issecretvalue(result) then return result end
    end
    if C_Item and type(C_Item.GetItemInfo) == "function" and Enum and Enum.ItemClass and Enum.ItemReagentSubclass then
        -- Один вызов на два поля: GetItemInfo — из самых дорогих в API и при
        -- промахе кэша уходит за данными на сервер.
        local ok, classID, subclassID = pcall(function()
            local _, _, _, _, _, _, _, _, _, _, _, class, subclass = C_Item.GetItemInfo(itemID)
            return class, subclass
        end)
        return ok and classID == Enum.ItemClass.Reagent and subclassID == Enum.ItemReagentSubclass.Keystone
    end
    return false
end

function Convenience:SlotKeystone()
    if not Enabled("autoKeystone") or IsShiftKeyDown() then return false end
    if not C_Container or not C_ChallengeMode or type(C_ChallengeMode.SlotKeystone) ~= "function" then return false end
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local slots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, slots do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if IsKeystone(itemID) then
                local picked = pcall(C_Container.PickupContainerItem, bag, slot)
                if picked then
                    local slotted = pcall(C_ChallengeMode.SlotKeystone)
                    if slotted then return true end
                    if ClearCursor then pcall(ClearCursor) end
                end
            end
        end
    end
    return false
end

function Convenience:SetupKeystoneFrame()
    local frame = _G.ChallengesKeystoneFrame
    if not frame then return end
    if not self.keystoneShowHooked then
        self.keystoneShowHooked = true
        frame:HookScript("OnShow", function()
            C_Timer.After(0, function() self:SlotKeystone() end)
        end)
    end
    if not self.keystoneDragHooked then
        self.keystoneDragHooked = true
        self.keystoneWasMovable = frame:IsMovable() and true or false
        frame:RegisterForDrag("LeftButton")
        frame:HookScript("OnDragStart", function(owner)
            if Enabled("movableKeystoneFrame") and not InCombatLockdown() then owner:StartMoving() end
        end)
        frame:HookScript("OnDragStop", function(owner) owner:StopMovingOrSizing() end)
    end
    if Enabled("movableKeystoneFrame") then
        frame:SetMovable(true)
        frame:SetClampedToScreen(true)
    elseif not self.keystoneWasMovable then
        frame:SetMovable(false)
    end
end

function Convenience:SellJunk()
    if not Enabled("sellJunk") or IsShiftKeyDown() then return end
    if not C_Container or not C_Container.GetContainerNumSlots then return end
    local poor = Enum and Enum.ItemQuality and Enum.ItemQuality.Poor or 0
    local total = 0
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local slots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, UI.UsableNumber(slots) and slots or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            -- Качество приходит от игры и под taint бывает защищённым. Такое
            -- значение можно использовать в условии (isLocked, hasNoValue ниже),
            -- но нельзя сравнивать — а здесь было именно сравнение, и «продать
            -- хлам» падало на торговце с «attempt to compare a secret value».
            local quality = info and UI.UsableNumber(info.quality) and info.quality or nil
            if quality == poor and not info.isLocked and not info.hasNoValue then
                local price = type(GetItemInfo) == "function"
                    and select(11, GetItemInfo(info.itemID or info.hyperlink or "")) or 0
                if not UI.UsableNumber(price) then price = 0 end
                local stack = UI.UsableNumber(info.stackCount) and info.stackCount or 1
                total = total + price * stack
                pcall(C_Container.UseContainerItem, bag, slot)
            end
        end
    end
    if Settings().merchantSummary then PrintMoney("Продано хлама", total) end
end

function Convenience:Repair()
    if not Enabled("repair") or IsShiftKeyDown() or not CanMerchantRepair or not CanMerchantRepair() then return end
    local cost, needed = GetRepairAllCost()
    if not needed or not cost or cost <= 0 then return end
    local useGuild = Enabled("guildRepair") and IsInGuild() and CanGuildBankRepair and CanGuildBankRepair()
    pcall(RepairAllItems, useGuild and true or false)
    if Settings().merchantSummary then PrintMoney("Ремонт", cost) end
end

function Convenience:AutomateQuest(event)
    if not Enabled("autoQuests") then return end
    -- Holding Shift is always a safe manual override.
    if IsShiftKeyDown() then return end
    if event == "QUEST_DETAIL" then
        if AcceptQuest then pcall(AcceptQuest) end
    elseif event == "QUEST_PROGRESS" then
        if IsQuestCompletable and IsQuestCompletable() and CompleteQuest then pcall(CompleteQuest) end
    elseif event == "QUEST_COMPLETE" then
        local choices = GetNumQuestChoices and GetNumQuestChoices() or 0
        if choices == 0 and GetQuestReward then pcall(GetQuestReward, 1) end
    elseif event == "GOSSIP_SHOW" and C_GossipInfo then
        for _, quest in ipairs(C_GossipInfo.GetActiveQuests and C_GossipInfo.GetActiveQuests() or {}) do
            if quest.isComplete and quest.questID then
                pcall(C_GossipInfo.SelectActiveQuest, quest.questID)
                return
            end
        end
        local available = C_GossipInfo.GetAvailableQuests and C_GossipInfo.GetAvailableQuests() or {}
        if available[1] and available[1].questID then
            pcall(C_GossipInfo.SelectAvailableQuest, available[1].questID)
        end
    end
end

function Convenience:AcceptSummon()
    if not Enabled("summon") or InCombatLockdown() then return end
    if ConfirmSummon then pcall(ConfirmSummon) end
    if StaticPopup_Hide then pcall(StaticPopup_Hide, "CONFIRM_SUMMON") end
end

function Convenience:AcceptResurrection()
    if not Enabled("resurrection") then return end
    if Enabled("resNoCombat") and InCombatLockdown() then return end
    if AcceptResurrect then pcall(AcceptResurrect) end
    if StaticPopup_Hide then pcall(StaticPopup_Hide, "RESURRECT") end
end

function Convenience:InviteFromWhisper(message, sender)
    if not Enabled("whisperInvite") or type(message) ~= "string" or type(sender) ~= "string" then return end
    local keyword = tostring(Settings().inviteKeyword or "inv"):lower()
    local clean = message:lower():match("^%s*(.-)%s*$")
    if clean ~= "inv" and clean ~= "123" and clean ~= "+" and clean ~= keyword then return end
    if IsInGroup() and not UnitIsGroupLeader("player") and not UnitIsGroupAssistant("player") then return end
    if C_PartyInfo and C_PartyInfo.InviteUnit then pcall(C_PartyInfo.InviteUnit, sender) end
end

function Convenience:Create()
    if self.events then return end
    self.events = CreateFrame("Frame")
    for _, event in ipairs({
        "MERCHANT_SHOW", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "GOSSIP_SHOW",
        "CONFIRM_SUMMON", "RESURRECT_REQUEST", "CHAT_MSG_WHISPER", "ADDON_LOADED",
        "CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN",
    }) do self.events:RegisterEvent(event) end
    self.events:SetScript("OnEvent", function(_, event, ...)
        if event == "ADDON_LOADED" then
            local addon = ...
            if addon == "Blizzard_ChallengesUI" then self:SetupKeystoneFrame() end
        elseif event == "CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN" then
            C_Timer.After(0, function() self:SetupKeystoneFrame(); self:SlotKeystone() end)
        elseif event == "MERCHANT_SHOW" then
            C_Timer.After(.15, function() self:SellJunk(); self:Repair() end)
        elseif event == "CONFIRM_SUMMON" then
            self:AcceptSummon()
        elseif event == "RESURRECT_REQUEST" then
            self:AcceptResurrection()
        elseif event == "CHAT_MSG_WHISPER" then
            self:InviteFromWhisper(...)
        else
            self:AutomateQuest(event)
        end
    end)
end

function Convenience:Enable() self:Create() end
function Convenience:Disable() end
function Convenience:Destroy() end

JP.Convenience = Convenience
JP:RegisterModule("Convenience", Convenience)
