local _, JP = ...
local L = JP.L
local PlayerTooltip = {}
local C = JP.UI.colors

-- Единые токены из UI.colors: панели этого модуля стоят на экране
-- рядом с юнит-фреймами и окном добычи и обязаны совпадать с ними точно.
local TOOLTIP_BG = { JP.UI.colors.surface[1], JP.UI.colors.surface[2], JP.UI.colors.surface[3], .97 }
local TOOLTIP_EDGE = { JP.UI.colors.surfaceEdge[1], JP.UI.colors.surfaceEdge[2], JP.UI.colors.surfaceEdge[3], .96 }

local function PlayerAnalysisEnabled()
    local settings = MythicBoostDB and MythicBoostDB.playerAnalysis
    return not settings or settings.enabled ~= false
end

local function TooltipSkinEnabled()
    return MythicBoostDB and MythicBoostDB.minimalUI == true
end

local function RestoreTooltipSkin(tooltip)
    if not tooltip.__mbSkinApplied then return end
    if tooltip.NineSlice then
        local original = tooltip.__mbNineSliceOriginal
        if tooltip.NineSlice.SetAlpha then tooltip.NineSlice:SetAlpha(original and original.alpha or 1) end
        tooltip.NineSlice:SetShown(not original or original.shown ~= false)
    end
    for _, region in ipairs({ tooltip.__mbBackdrop, tooltip.__mbBackdropShade, tooltip.__mbTopAccent }) do
        if region then region:Hide() end
    end
    for _, edge in ipairs(tooltip.__mbBackdropEdges or {}) do edge:Hide() end
    tooltip.__mbSkinApplied = false
end

local function ApplyTooltipSkin(tooltip)
    if not tooltip then return end
    -- Tooltip enrichment is part of the player-analysis core, but replacing
    -- every Blizzard tooltip is visual customization. Keep that replacement
    -- coupled to the explicit Minimal UI opt-in and restore the native skin
    -- when it is disabled.
    if not TooltipSkinEnabled() then RestoreTooltipSkin(tooltip); return end
    tooltip.__mbSkinApplied = true
    if tooltip.NineSlice and type(tooltip.NineSlice.SetAlpha) == "function" then
        if not tooltip.__mbNineSliceOriginal then
            tooltip.__mbNineSliceOriginal = {
                alpha = tooltip.NineSlice:GetAlpha(),
                shown = tooltip.NineSlice:IsShown(),
            }
        end
        tooltip.NineSlice:SetAlpha(0)
        tooltip.NineSlice:Hide()
    end
    -- Фон и рамку тултипа в современном Retail рисует NineSlice, а метода
    -- SetBackdrop у GameTooltip больше нет. Прежняя проверка type(...) всегда
    -- была ложной: NineSlice выше гасился, замена не ставилась, и тултип
    -- оставался полностью прозрачным — сквозь него просвечивал трекер задач.
    -- Рисуем подложку текстурами на самом тултипе: они привязаны к его краям и
    -- переживают любое изменение размера, а BACKGROUND с отрицательным
    -- подуровнем гарантированно оказывается под строками текста.
    if not tooltip.__mbBackdrop then
        local background = tooltip:CreateTexture(nil, "BACKGROUND", nil, -8)
        background:SetPoint("TOPLEFT")
        background:SetPoint("BOTTOMRIGHT")
        background:SetColorTexture(unpack(TOOLTIP_BG))
        tooltip.__mbBackdrop = background

        local shade = tooltip:CreateTexture(nil, "BACKGROUND", nil, -6)
        shade:SetPoint("TOPLEFT", 1, -1)
        shade:SetPoint("BOTTOMRIGHT", -1, 1)
        shade:SetColorTexture(1, 1, 1, 1)
        shade:SetGradient("HORIZONTAL",
            CreateColor(1, .24, .02, .11),
            CreateColor(.02, .78, 1, .08))
        tooltip.__mbBackdropShade = shade

        local edges = {}
        for index = 1, 4 do
            edges[index] = tooltip:CreateTexture(nil, "BACKGROUND", nil, -7)
            edges[index]:SetColorTexture(unpack(TOOLTIP_EDGE))
        end
        edges[1]:SetPoint("TOPLEFT");    edges[1]:SetPoint("TOPRIGHT");    edges[1]:SetHeight(1)
        edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(1)
        edges[3]:SetPoint("TOPLEFT");    edges[3]:SetPoint("BOTTOMLEFT");  edges[3]:SetWidth(1)
        edges[4]:SetPoint("TOPRIGHT");   edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(1)
        tooltip.__mbBackdropEdges = edges
    end
    tooltip.__mbBackdrop:Show()
    tooltip.__mbBackdropShade:Show()
    for _, edge in ipairs(tooltip.__mbBackdropEdges or {}) do edge:Show() end
    if not tooltip.__mbTopAccent then
        local accent = tooltip:CreateTexture(nil, "OVERLAY", nil, 7)
        accent:SetPoint("TOPLEFT", 1, -1)
        accent:SetPoint("TOPRIGHT", -1, -1)
        accent:SetHeight(2)
        accent:SetColorTexture(1, 1, 1, 1)
        -- Один фирменный цвет, а не переход из оранжевого в бирюзовый:
        -- два акцентных цвета в одной полоске — это два разных бренда
        -- рядом, и именно они ломали целостность вместе с ModernBackdrop.
        accent:SetGradient("HORIZONTAL",
            CreateColor(C.accent[1], C.accent[2], C.accent[3], .30),
            CreateColor(C.accent[1], C.accent[2], C.accent[3], .95))
        tooltip.__mbTopAccent = accent
    end
    tooltip.__mbTopAccent:Show()
end

local function HookTooltipSkin(tooltip)
    if not tooltip or tooltip.__mbSkinHooked then return end
    tooltip.__mbSkinHooked = true
    tooltip:HookScript("OnShow", function(owner)
        ApplyTooltipSkin(owner)
        C_Timer.After(0, function()
            if owner:IsShown() then ApplyTooltipSkin(owner) end
        end)
    end)
    ApplyTooltipSkin(tooltip)
end

-- Raider.IO uses separate GameTooltipTemplate instances for the movable
-- profile card and character search. They are not children of GameTooltip,
-- so skinning only the Blizzard singleton leaves exactly the large default
-- black/grey card visible in Group Finder.
local RAIDERIO_TOOLTIPS = {
    "RaiderIO_ProfileTooltip",
    "RaiderIO_SearchTooltip",
    "LibDBIconTooltip",
}

local function HookRaiderIOTooltips()
    local profileReady = false
    for _, name in ipairs(RAIDERIO_TOOLTIPS) do
        local tooltip = _G[name]
        if tooltip then
            HookTooltipSkin(tooltip)
            ApplyTooltipSkin(tooltip)
            if name == "RaiderIO_ProfileTooltip" then profileReady = true end
        end
    end
    return profileReady
end

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
            tooltip:AddDoubleLine(L("РЕАЛЬНО ПЕРСПЕКТИВНЫЙ"), "+" .. potential, .72, .30, 1, 1, .58, .10)
        else
            tooltip:AddDoubleLine(L("Прогноз по гиру и опыту"), "+" .. potential, .20, .80, 1, .25, 1, .55)
        end
        tooltip:AddDoubleLine(L("Экипировка / опыт"), ("+%d / +%d"):format(gear, experience), .60, .64, .70, .75, .80, .86)
    else
        tooltip:AddDoubleLine(L("Прогноз по опыту"), "+" .. potential, .20, .80, 1, .25, 1, .55)
        tooltip:AddLine(L("Item level скрыт в этом окне"), .48, .55, .63)
    end
    if isStrongCandidate then
        tooltip:AddLine(L("RIO может занижать возможности игрока"), .30, 1, .55)
        JP:MarkPositivePlayer(fullName, {
            potential = potential,
            itemLevel = itemLevel,
            confirmed = confirmed,
            experience = experience,
            gearCeiling = gear,
        }, saveRecent)
    end
end

local function AddRunCount(tooltip, runs)
    -- Считаем прямо из того же свежего списка Raider.IO, который показан
    -- строками выше. Milestone-поля профиля обновляются отдельно и могли
    -- показывать старое «2», когда в списке уже восемь рекордов +10.
    local total = 0
    for _, run in ipairs(type(runs) == "table" and runs or {}) do
        if IsUsableNumber(run.level) and run.level >= 10 then total = total + 1 end
    end
    tooltip:AddDoubleLine(L("Подземелий с рекордом +10 и выше"), tostring(total), .75, .78, .82, 1, .82, .25)
end

local function AppendProfile(tooltip, profile, itemLevel, uniqueKey, fullName, saveRecent)
    if not PlayerAnalysisEnabled() then return end
    local keystone = profile and profile.mythicKeystoneProfile
    local runs = keystone and keystone.sortedDungeons
    if not runs or #runs == 0 or tooltip.__jpDungeonKey == uniqueKey then return end
    if not IsUsableNumber(itemLevel) and fullName then
        local cached = JP:GetPositivePlayer(fullName)
        if type(cached) == "table" and IsUsableNumber(cached.itemLevel) then itemLevel = cached.itemLevel end
    end
    tooltip.__jpDungeonKey = uniqueKey

    tooltip:AddLine(" ")
    tooltip:AddLine(L("MythicBoost - Лучшие ключи"), .15, .75, 1)
    for index = 1, math.min(8, #runs) do
        local run = runs[index]
        local dungeon = run.dungeon
        local dungeonName = dungeon and (dungeon.shortNameLocale or dungeon.shortName or dungeon.name) or (L("Подземелье ") .. index)
        local level = IsUsableNumber(run.level) and run.level or 0
        local chests = IsUsableNumber(run.chests) and run.chests or 0
        tooltip:AddDoubleLine(dungeonName, FormatRun(level, chests), .86, .89, .93, 1, 1, 1)
    end
    AddRunCount(tooltip, runs)
    AddPotential(tooltip, runs, itemLevel, fullName, saveRecent)
    tooltip:Show()
end

-- В Midnight подсказка отдаёт имя и юнит защищёнными значениями. Наш аддон
-- помечает выполнение как tainted, и после этого любая попытка передать такое
-- значение в UnitIsPlayer или склеить его в строку бросает ошибку — она
-- повторялась на каждой подсказке, больше двух тысяч раз за сессию.
-- Поэтому здесь ничего не предполагаем: непригодное значение просто пропускаем.
local function IsUsableString(value)
    -- Даже сравнение secret-строки с "" запрещено. Сначала проверяем метку,
    -- и только после этого выполняем любые операции со значением.
    return type(value) == "string" and not issecretvalue(value) and value ~= ""
end

local function AddUnitProfile(tooltip)
    if not PlayerAnalysisEnabled() then return end
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
    if not PlayerAnalysisEnabled() then return end
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
    if not PlayerAnalysisEnabled() then return end
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
    if JP.GroupSearchUI and JP.GroupSearchUI.IsMythicPlusSearchResult
        and not JP.GroupSearchUI:IsMythicPlusSearchResult(searchResultID) then
        JP.GroupSearchUI:HideBlizzardResultTooltip()
        return
    end
    if JP.GroupSearchUI and JP.GroupSearchUI.ShowBlizzardResultTooltip then
        pcall(JP.GroupSearchUI.ShowBlizzardResultTooltip, JP.GroupSearchUI, tooltip:GetOwner(), searchResultID)
    end
    if not PlayerAnalysisEnabled() then return end
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
    if not PlayerAnalysisEnabled() then return end
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

    HookTooltipSkin(_G.GameTooltip)
    HookTooltipSkin(_G.ItemRefTooltip)
    HookTooltipSkin(_G.ShoppingTooltip1)
    HookTooltipSkin(_G.ShoppingTooltip2)
    HookTooltipSkin(_G.EmbeddedItemTooltip)
    HookTooltipSkin(_G.FriendsTooltip)
    HookRaiderIOTooltips()

    -- The profile tooltip is created when Raider.IO enables its profile
    -- module, which can happen after our ADDON_LOADED callback. A short,
    -- bounded retry catches that late construction without a permanent poll.
    if C_Timer and C_Timer.NewTicker then
        self.raiderSkinTicker = C_Timer.NewTicker(.5, HookRaiderIOTooltips, 20)
    end

    HookSearchEntryTooltip(self)
    HookFriendsTooltip(self)
    if not self.searchHooked or not self.friendsHooked then
        self.loader = CreateFrame("Frame")
        self.loader:RegisterEvent("ADDON_LOADED")
        self.loader:SetScript("OnEvent", function(_, _, addonName)
            if addonName == "Blizzard_GroupFinder" then HookSearchEntryTooltip(self) end
            if addonName == "RaiderIO" then HookRaiderIOTooltips() end
            if addonName == "Blizzard_FriendsFrame" then
                HookFriendsTooltip(self)
                HookTooltipSkin(_G.FriendsTooltip)
            end
        end)
    end
end

function PlayerTooltip:Enable() end
function PlayerTooltip:Disable() end
function PlayerTooltip:Destroy() end
JP:RegisterModule("PlayerTooltip", PlayerTooltip)
