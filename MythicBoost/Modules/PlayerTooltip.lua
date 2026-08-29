local _, JP = ...
local PlayerTooltip = {}

local function IsUsableNumber(value)
    return type(value) == "number" and not issecretvalue(value)
end

-- Цвет показывает именно качество прохождения, а не величину ключа:
-- сломанный серый, +1 белый, +2 зелёный, +3 фиолетовый.
local RUN_COLOR = {
    [0] = "7a7f89",
    [1] = "ffffff",
    [2] = "4deb8f",
    [3] = "b35cff",
}

local function FormatRun(level, chests)
    level = IsUsableNumber(level) and level or 0
    chests = IsUsableNumber(chests) and math.max(0, math.min(3, chests)) or 0
    if level <= 0 then return "|cff4d5766—|r" end
    local prefix = chests > 0 and string.rep("+", chests) or ""
    return ("|cff%s%s%d|r"):format(RUN_COLOR[chests], prefix, level)
end

local function GearCeiling(itemLevel)
    if not IsUsableNumber(itemLevel) then return end
    if itemLevel >= 311 then return 13 end
    if itemLevel >= 308 then return 12 end
    if itemLevel >= 304 then return 10 end
    if itemLevel >= 300 then return 8 end
    if itemLevel >= 296 then return 6 end
    if itemLevel >= 292 then return 4 end
    return 2
end

local function AddPotential(tooltip, runs, itemLevel, fullName, saveRecent)
    local gear = GearCeiling(itemLevel)
    local confirmed = IsUsableNumber(runs[1] and runs[1].level) and runs[1].level or 0
    local breadthIndex = math.min(3, #runs)
    local breadth = IsUsableNumber(runs[breadthIndex] and runs[breadthIndex].level) and runs[breadthIndex].level or 0
    local experience = math.min(confirmed + 2, breadth + 2)
    local potential = gear and math.min(gear, math.max(confirmed, experience)) or experience
    local isStrongCandidate = gear and gear >= confirmed + 2 and breadth > 0

    tooltip:AddLine(" ")
    if gear then
        tooltip:AddDoubleLine("Item level", string.format("%.1f", itemLevel), .75, .78, .82, 1, 1, 1)
        if isStrongCandidate then
            tooltip:AddDoubleLine("РЕАЛЬНО ПЕРСПЕКТИВНЫЙ", "+" .. potential, .72, .30, 1, 1, .58, .10)
        else
            tooltip:AddDoubleLine("Прогноз по гиру и опыту", "+" .. potential, .20, .80, 1, .25, 1, .55)
        end
        tooltip:AddDoubleLine("Экипировка / опыт", ("+%d / +%d"):format(gear, experience), .60, .64, .70, .75, .80, .86)
    else
        tooltip:AddDoubleLine("Прогноз по опыту", "+" .. potential, .20, .80, 1, .25, 1, .55)
        tooltip:AddLine("Item level скрыт в этом окне", .48, .55, .63)
    end
    if isStrongCandidate then
        tooltip:AddLine("RIO может занижать возможности игрока", .30, 1, .55)
        JP:MarkPositivePlayer(fullName, {
            potential = potential,
            itemLevel = itemLevel,
            confirmed = confirmed,
            experience = experience,
            gearCeiling = gear,
        }, saveRecent)
    end
end

local function AddRunCount(tooltip, keystone)
    local total, capped = 0, false
    for _, level in ipairs({ 10, 12, 15 }) do
        local count = keystone["keystoneMilestone" .. level]
        if IsUsableNumber(count) then
            total = total + count
            if count >= 255 then capped = true end
        end
    end
    tooltip:AddDoubleLine("Пройдено ключей +10 и выше", tostring(total) .. (capped and "+" or ""), .75, .78, .82, 1, .82, .25)
end

local function AppendProfile(tooltip, profile, itemLevel, uniqueKey, fullName, saveRecent)
    local keystone = profile and profile.mythicKeystoneProfile
    local runs = keystone and keystone.sortedDungeons
    if not runs or #runs == 0 or tooltip.__jpDungeonKey == uniqueKey then return end
    if not IsUsableNumber(itemLevel) and fullName then
        local cached = JP:GetPositivePlayer(fullName)
        if type(cached) == "table" and IsUsableNumber(cached.itemLevel) then itemLevel = cached.itemLevel end
    end
    tooltip.__jpDungeonKey = uniqueKey

    tooltip:AddLine(" ")
    tooltip:AddLine("MythicBoost • Лучшие ключи", .15, .75, 1)
    for index = 1, math.min(8, #runs) do
        local run = runs[index]
        local dungeon = run.dungeon
        local dungeonName = dungeon and (dungeon.shortNameLocale or dungeon.shortName or dungeon.name) or ("Подземелье " .. index)
        local level = IsUsableNumber(run.level) and run.level or 0
        local chests = IsUsableNumber(run.chests) and run.chests or 0
        tooltip:AddDoubleLine(dungeonName, FormatRun(level, chests), .86, .89, .93, 1, 1, 1)
    end
    AddRunCount(tooltip, keystone)
    AddPotential(tooltip, runs, itemLevel, fullName, saveRecent)
    tooltip:Show()
end

-- В Midnight подсказка отдаёт имя и юнит защищёнными значениями. Наш аддон
-- помечает выполнение как tainted, и после этого любая попытка передать такое
-- значение в UnitIsPlayer или склеить его в строку бросает ошибку — она
-- повторялась на каждой подсказке, больше двух тысяч раз за сессию.
-- Поэтому здесь ничего не предполагаем: непригодное значение просто пропускаем.
local function IsUsableString(value)
    return type(value) == "string" and value ~= "" and not issecretvalue(value)
end

local function AddUnitProfile(tooltip)
    if not RaiderIO or type(RaiderIO.GetProfile) ~= "function" then return end
    local playerName, unit = tooltip:GetUnit()
    if not IsUsableString(playerName) or not IsUsableString(unit) then return end
    if not UnitIsPlayer(unit) then return end

    local itemLevel
    if C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
        local ok, value = pcall(C_PaperDollInfo.GetInspectItemLevel, unit)
        if ok and IsUsableNumber(value) and value > 0 then itemLevel = value end
    end

    local name, realm = UnitFullName(unit)
    local fullName = playerName
    if IsUsableString(name) then
        fullName = IsUsableString(realm) and (name .. "-" .. realm) or name
    end
    AppendProfile(tooltip, RaiderIO.GetProfile(unit), itemLevel, "unit:" .. playerName, fullName, true)
end

local function AddApplicantProfile(tooltip)
    if not RaiderIO or type(RaiderIO.GetProfile) ~= "function" then return end
    local owner = tooltip:GetOwner()
    if not owner or not owner.memberIdx then return end
    local parent = owner:GetParent()
    local applicantID = owner.applicantID or (parent and parent.applicantID)
    if not applicantID then return end
    local fullName, _, _, _, itemLevel = C_LFGList.GetApplicantMemberInfo(applicantID, owner.memberIdx)
    if not IsUsableString(fullName) then return end
    AppendProfile(tooltip, RaiderIO.GetProfile(fullName), itemLevel, "lfg:" .. applicantID .. ":" .. owner.memberIdx, fullName)
end

local function AddGenericRaiderIOProfile(tooltip)
    if tooltip.__jpDungeonKey or not RaiderIO or type(RaiderIO.GetProfile) ~= "function" then return end
    local tooltipName = tooltip:GetName()
    local firstLine = tooltipName and _G[tooltipName .. "TextLeft1"]
    local fullName = firstLine and firstLine:GetText()
    if not IsUsableString(fullName) then return end

    -- Raider.IO character tooltips begin with Name-Realm. Strip color codes and
    -- ignore every other kind of tooltip by requiring a valid local profile.
    fullName = fullName:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*([^%s]+%-%S+)")
    if not fullName then return end
    local profile = RaiderIO.GetProfile(fullName)
    if not profile or not profile.mythicKeystoneProfile then return end
    AppendProfile(tooltip, profile, nil, "generic:" .. fullName, fullName)
end

local function AddSearchResultProfile(tooltip, searchResultID)
    if JP.GroupSearchUI and JP.GroupSearchUI.ShowBlizzardResultTooltip then
        pcall(JP.GroupSearchUI.ShowBlizzardResultTooltip, JP.GroupSearchUI, tooltip:GetOwner(), searchResultID)
    end
    if not RaiderIO or type(RaiderIO.GetProfile) ~= "function" then return end
    local info = C_LFGList.GetSearchResultInfo(searchResultID)
    if not info then return end
    local fullName = info.leaderName
    if type(fullName) ~= "string" or issecretvalue(fullName) then return end
    local profile = RaiderIO.GetProfile(fullName)
    if not profile or not profile.mythicKeystoneProfile then return end
    AppendProfile(tooltip, profile, nil, "search:" .. tostring(searchResultID), fullName)
end

local function AddFriendProfile()
    if not FriendsTooltip or not FriendsTooltip.button or not RaiderIO or type(RaiderIO.GetProfile) ~= "function" then return end
    local button = FriendsTooltip.button
    local characterName, realmName
    if button.buttonType == FRIENDS_BUTTON_TYPE_BNET then
        local accountInfo = C_BattleNet.GetFriendAccountInfo(button.id)
        local friendIndex = accountInfo and accountInfo.bnetAccountID and BNGetFriendIndex(accountInfo.bnetAccountID) or button.id
        if not friendIndex then return end
        local bestLevel = -1
        for index = 1, C_BattleNet.GetFriendNumGameAccounts(friendIndex) do
            local gameInfo = C_BattleNet.GetFriendGameAccountInfo(friendIndex, index)
            local isWoW = gameInfo and (gameInfo.clientProgram == BNET_CLIENT_WOW or gameInfo.clientProgram == "WoW")
            local isRetail = gameInfo and (not gameInfo.wowProjectID or gameInfo.wowProjectID == WOW_PROJECT_MAINLINE)
            local level = gameInfo and gameInfo.characterLevel or 0
            if isWoW and isRetail and gameInfo.characterName and level > bestLevel then
                characterName, realmName, bestLevel = gameInfo.characterName, gameInfo.realmName, level
            end
        end
    elseif button.buttonType == FRIENDS_BUTTON_TYPE_WOW then
        local friendInfo = C_FriendList.GetFriendInfoByIndex(button.id)
        if friendInfo then characterName = friendInfo.name end
    end
    if type(characterName) ~= "string" or characterName == "" then return end
    local fullName = characterName
    if type(realmName) == "string" and realmName ~= "" then fullName = characterName .. "-" .. realmName end
    local profile = RaiderIO.GetProfile(characterName, realmName)
    if not profile or not profile.mythicKeystoneProfile then return end
    AppendProfile(GameTooltip, profile, nil, "friend:" .. fullName, fullName)
end

local function HookFriendsTooltip(module)
    if module.friendsHooked or not FriendsTooltip then return end
    hooksecurefunc(FriendsTooltip, "Show", function()
        C_Timer.After(0, AddFriendProfile)
    end)
    module.friendsHooked = true
end

-- LFGListUtil_SetSearchEntryTooltip живёт в Blizzard_GroupFinder и на момент
-- входа в игру ещё не существует. Слепой hooksecurefunc по имени падал прямо
-- здесь и обрывал Create: подсказка по своим ключам не ставилась вовсе, а
-- повторный /mb reload вешал дубликаты уже установленных хуков, потому что
-- registered так и оставался false.
local function HookSearchEntryTooltip(module)
    if module.searchHooked or type(LFGListUtil_SetSearchEntryTooltip) ~= "function" then return end
    hooksecurefunc("LFGListUtil_SetSearchEntryTooltip", AddSearchResultProfile)
    module.searchHooked = true
end

function PlayerTooltip:Create()
    if self.registered then return end
    self.registered = true

    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, AddUnitProfile)
    GameTooltip:HookScript("OnShow", AddApplicantProfile)
    GameTooltip:HookScript("OnShow", AddGenericRaiderIOProfile)
    GameTooltip:HookScript("OnTooltipCleared", function(tooltip) tooltip.__jpDungeonKey = nil end)
    GameTooltip:HookScript("OnHide", function()
        if JP.GroupSearchUI and JP.GroupSearchUI.HideBlizzardResultTooltip then
            JP.GroupSearchUI:HideBlizzardResultTooltip()
        end
    end)

    HookSearchEntryTooltip(self)
    HookFriendsTooltip(self)
    if not self.searchHooked or not self.friendsHooked then
        self.loader = CreateFrame("Frame")
        self.loader:RegisterEvent("ADDON_LOADED")
        self.loader:SetScript("OnEvent", function(_, _, addonName)
            if addonName == "Blizzard_GroupFinder" then HookSearchEntryTooltip(self) end
            if addonName == "Blizzard_FriendsFrame" then HookFriendsTooltip(self) end
        end)
    end
end

function PlayerTooltip:Enable() end
function PlayerTooltip:Disable() end
function PlayerTooltip:Destroy() end
JP:RegisterModule("PlayerTooltip", PlayerTooltip)
