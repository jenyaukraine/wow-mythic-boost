local _, JP = ...
local L = JP.L
local WarcraftLogs = {}

local REGION_SLUGS = { [1] = "us", [2] = "kr", [3] = "eu", [4] = "tw", [5] = "cn" }
local VALID_MENU_TYPES = {
    ARENAENEMY = true, BN_FRIEND = true, CHAT_ROSTER = true,
    COMMUNITIES_GUILD_MEMBER = true, COMMUNITIES_WOW_MEMBER = true,
    ENEMY_PLAYER = true, FOCUS = true, FRIEND = true, GUILD = true,
    GUILD_OFFLINE = true, PARTY = true, PLAYER = true, RAID = true,
    RAID_PLAYER = true, SELF = true, TARGET = true, WORLD_STATE_SCORE = true,
}
local VALID_MENU_TAGS = {
    MENU_LFG_FRAME_SEARCH_ENTRY = true,
    MENU_LFG_FRAME_MEMBER_APPLY = true,
}

local function SafeString(value)
    return type(value) == "string" and not issecretvalue(value) and value ~= "" and value or nil
end

local function SplitNameRealm(fullName, fallbackRealm)
    fullName = SafeString(fullName)
    fallbackRealm = SafeString(fallbackRealm)
    if not fullName then return end
    local name, realm = fullName:match("^([^-]+)%-(.+)$")
    return name or fullName, realm or fallbackRealm
end

local function EncodePath(value)
    -- Use an explicit ASCII allow-list. Locale-aware %w can treat individual
    -- UTF-8 bytes as letters and leave a malformed half-character in the URL.
    return (value:gsub("[^A-Za-z0-9%-_%.~]", function(character)
        return ("%%%02X"):format(character:byte())
    end))
end

local function FallbackRealmSlug(realm)
    realm = SafeString(realm)
    if not realm then return end
    return realm:lower():gsub("[’']", ""):gsub("%s+", "-")
end

local function RaiderIORealmSlug(name, realm)
    if not RaiderIO or type(RaiderIO.GetProfile) ~= "function" then return end
    local ok, profile = pcall(RaiderIO.GetProfile, name, realm)
    if not ok or type(profile) ~= "table" then return end
    return SafeString(profile.realm)
end

function WarcraftLogs:BuildURL(name, realm, region)
    name, realm = SplitNameRealm(name, realm)
    if not name or not realm then return end
    local regionSlug = SafeString(region)
        or REGION_SLUGS[type(GetCurrentRegion) == "function" and GetCurrentRegion() or 3]
        or "eu"
    local realmSlug = RaiderIORealmSlug(name, realm) or FallbackRealmSlug(realm)
    if not realmSlug then return end
    return ("https://www.warcraftlogs.com/character/%s/%s/%s"):format(
        EncodePath(regionSlug:lower()), EncodePath(realmSlug:lower()), EncodePath(name))
end

local function ResolveOwner(owner)
    if not owner then return end
    if owner.resultID and C_LFGList and C_LFGList.GetSearchResultInfo then
        local info = C_LFGList.GetSearchResultInfo(owner.resultID)
        if info and not issecretvalue(info.leaderName) then return SplitNameRealm(info.leaderName) end
    end
    if owner.memberIdx and owner.GetParent and C_LFGList and C_LFGList.GetApplicantMemberInfo then
        local parent = owner:GetParent()
        local applicantID = parent and parent.applicantID
        if applicantID then
            local fullName = C_LFGList.GetApplicantMemberInfo(applicantID, owner.memberIdx)
            return SplitNameRealm(fullName)
        end
    end
end

local function ResolveContext(owner, contextData)
    if not contextData then return ResolveOwner(owner) end
    local unit = SafeString(contextData.unit)
    if unit and UnitExists(unit) and UnitIsPlayer(unit) then
        local name, realm = UnitFullName(unit)
        return SplitNameRealm(name, realm or GetNormalizedRealmName())
    end
    local account = contextData.accountInfo
    local game = account and account.gameAccountInfo
    if game then
        return SplitNameRealm(game.characterName, game.realmName)
    end
    local name, realm = SplitNameRealm(contextData.name, contextData.server)
    if name then return name, realm or GetNormalizedRealmName() end
    return ResolveOwner(owner)
end

local COPY_DIALOG = "MYTHICBOOST_COPY_WARCRAFTLOGS_URL"

local function InstallCopyDialog()
    if not StaticPopupDialogs or StaticPopupDialogs[COPY_DIALOG] then return end
    StaticPopupDialogs[COPY_DIALOG] = {
        text = L("Ссылка Warcraft Logs — %s"),
        button2 = CLOSE,
        hasEditBox = true,
        hasWideEditBox = true,
        editBoxWidth = 420,
        maxLetters = 0,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnShow = function(self)
            local editBox = self.GetEditBox and self:GetEditBox() or self.EditBox or self.editBox
            if not editBox then return end
            editBox:SetText(self.data or "")
            editBox:SetFocus()
            editBox:HighlightText()
        end,
        EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
    }
end

function WarcraftLogs:ShowCopyURL(name, realm)
    local url = self:BuildURL(name, realm)
    if not url then return end
    InstallCopyDialog()
    local popup = StaticPopup_Show and StaticPopup_Show(COPY_DIALOG, name .. "-" .. realm, nil, url)
    if popup then
        popup.data = url
        local editBox = popup.GetEditBox and popup:GetEditBox() or popup.EditBox or popup.editBox
        if editBox then editBox:SetText(url); editBox:SetFocus(); editBox:HighlightText() end
    elseif ChatFrame_OpenChat then
        local editBox = ChatFrame_OpenChat(url, DEFAULT_CHAT_FRAME)
        if editBox then editBox:HighlightText() end
    end
end

function WarcraftLogs:AddMenu(owner, rootDescription, contextData)
    local which = contextData and contextData.which
    if contextData and (not which or not VALID_MENU_TYPES[which]) then return end
    if not contextData and not VALID_MENU_TAGS[rootDescription.tag] then return end
    local name, realm = ResolveContext(owner, contextData)
    if not name or not realm then return end
    rootDescription:CreateDivider()
    rootDescription:CreateTitle("Warcraft Logs")
    rootDescription:CreateButton(L("Копировать ссылку Warcraft Logs"), function()
        self:ShowCopyURL(name, realm)
    end)
end

function WarcraftLogs:Install()
    if self.installed or not Menu or type(Menu.ModifyMenu) ~= "function" then return false end
    local callback = function(owner, rootDescription, contextData)
        self:AddMenu(owner, rootDescription, contextData)
    end
    for which in pairs(VALID_MENU_TYPES) do Menu.ModifyMenu("MENU_UNIT_" .. which, callback) end
    for tag in pairs(VALID_MENU_TAGS) do Menu.ModifyMenu(tag, callback) end
    self.installed = true
    return true
end

function WarcraftLogs:Create()
    InstallCopyDialog()
    local manager = Menu and Menu.GetManager and Menu.GetManager()
    if not manager then self:Install(); return end
    if self.menuHooked then return end
    self.menuHooked = true
    -- Blizzard must open one native menu before addons modify menu tags. Doing
    -- this during ADDON_LOADED can taint the secure dropdown state.
    local function InstallAfterFirstMenu() self:Install() end
    hooksecurefunc(manager, "OpenMenu", InstallAfterFirstMenu)
    hooksecurefunc(manager, "OpenContextMenu", InstallAfterFirstMenu)
end

function WarcraftLogs:Enable() end
function WarcraftLogs:Disable() end
function WarcraftLogs:Destroy() end

JP.WarcraftLogs = WarcraftLogs
JP:RegisterModule("WarcraftLogs", WarcraftLogs)
