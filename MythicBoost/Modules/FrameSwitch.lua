local _, JP = ...
local L = JP.L
local FrameSwitch = {}
local UI = JP.UI
local ICON = "Interface\\AddOns\\MythicBoost\\Media\\MythicBoostIcon.tga"

-- MythicBoost больше не перехватывает штатную кнопку «Поиск группы».
-- Она всегда открывает Blizzard Group Finder, а переход в наше окно живёт
-- отдельной кнопкой непосредственно внутри этого окна.

local function Welcome()
    return JP.modules.Welcome
end

local function OpenOurs()
    local welcome = Welcome()
    if not welcome then return end
    if not welcome.frame then welcome:Create() end
    if welcome.frame then
        local listed = C_LFGList.GetActiveEntryInfo and C_LFGList.GetActiveEntryInfo()
        if listed and welcome.pages and welcome.pages.applicants then welcome:SwitchPage("applicants") end
        welcome.frame:Show()
    end
end

local function OpenBlizzard()
    if InCombatLockdown() then
        JP:Print(L("В бою переключать окна нельзя."))
        return false
    end
    if not PVEFrame or type(ShowUIPanel) ~= "function" then
        JP:Print(L("Окно заявки Blizzard сейчас недоступно. Открой поиск подземелий и попробуй ещё раз."))
        return false
    end
    local welcome = Welcome()
    if welcome and welcome.frame then welcome.frame:Hide() end
    -- Do not run GroupFinder's internal panel/selection helpers or toggle an
    -- already open window closed. The player selects the native tab/action.
    if not PVEFrame:IsShown() then
        local ok = pcall(ShowUIPanel, PVEFrame)
        if not ok then
            if welcome and welcome.frame then welcome.frame:Show() end
            JP:Print(L("Окно заявки Blizzard сейчас недоступно. Открой поиск подземелий и попробуй ещё раз."))
            return false
        end
    end
    return true
end
FrameSwitch.OpenBlizzard = function() return OpenBlizzard() end

function FrameSwitch:IsReplacing()
    return false
end

function FrameSwitch:SetReplacing()
    if MythicBoostDB then MythicBoostDB.replaceGroupFinder = false end
    JP:Print(L("Штатная кнопка «Поиск группы» не подменяется. MythicBoost открывается кнопкой внутри окна Blizzard."))
end

-- Кнопка на окне Blizzard: даже при выключенной замене отсюда можно попасть
-- в наше окно одним кликом.
local function EnsureButton(module)
    if module.button or not PVEFrame then return end
    local button = UI.IconButton(PVEFrame, ICON, 28)
    -- Keep it flush with the right end of the secondary header row. The
    -- close button occupies the row above, so this does not overlap it.
    button:SetPoint("TOPRIGHT", -8, -23)
    button:SetFrameStrata("HIGH")
    -- MythicBoost — вспомогательное окно поверх штатного поиска. Не
    -- закрываем PVEFrame: пользователь должен вернуться ровно к тому
    -- списку или форме, поверх которой открыл аддон.
    button:SetScript("OnClick", OpenOurs)
    button:HookScript("OnEnter", function(self)
        UI.Tooltip(self, "MythicBoost",
            L("Открыть окно подбора групп: фильтры, кандидаты и рейтинг гильдии."),
            L("Штатная кнопка «Поиск группы» всегда продолжает открывать окно Blizzard."))
    end)
    button:HookScript("OnLeave", GameTooltip_Hide)
    module.button = button
end

-- Both footer buttons start at the same XML anchor. Blizzard moves Delist
-- only near the end of UpdateInfo, which may return before activity data is
-- available. Restore that same native layout without reading listing fields,
-- changing button visibility, or replacing any protected click handler.
function FrameSwitch:LayoutApplicantFooter()
    if self.layoutDisabled or InCombatLockdown() then return end
    local viewer = self.applicantViewer
    if not viewer or not UI.SafeBoolean(viewer:IsVisible()) then return end
    local browse, remove = viewer.BrowseGroupsButton, viewer.RemoveEntryButton
    if not browse or not remove then return end
    if not UI.SafeBoolean(browse:IsShown()) or not UI.SafeBoolean(remove:IsShown()) then return end
    if remove:GetNumPoints() == 1 then
        local point, relative, relativePoint, x, y = remove:GetPoint(1)
        if issecretvalue(point) or issecretvalue(relative) or issecretvalue(relativePoint)
            or issecretvalue(x) or issecretvalue(y) then return end
        if point == "LEFT" and relative == browse and relativePoint == "RIGHT" and x == 15 and y == 0 then return end
    end
    remove:ClearAllPoints()
    remove:SetPoint("LEFT", browse, "RIGHT", 15, 0)
end

function FrameSwitch:QueueApplicantLayout()
    if self.layoutDisabled or self.layoutQueued or InCombatLockdown() then return end
    self.layoutQueued = true
    C_Timer.After(0, function()
        self.layoutQueued = false
        self:LayoutApplicantFooter()
    end)
end

function FrameSwitch:InstallApplicantLayout()
    if self.applicantViewer then return true end
    local viewer = _G.LFGListFrame and LFGListFrame.ApplicationViewer
    if not viewer or not viewer.BrowseGroupsButton or not viewer.RemoveEntryButton then return false end
    self.applicantViewer = viewer
    local queue = function() self:QueueApplicantLayout() end
    viewer:HookScript("OnShow", queue)
    viewer.BrowseGroupsButton:HookScript("OnShow", queue)
    viewer.RemoveEntryButton:HookScript("OnShow", queue)
    -- An independent event path still runs when the native info refresh
    -- returns early. Burst events share one callback; there is no polling.
    self.layoutEvents = CreateFrame("Frame")
    for _, event in ipairs({ "LFG_LIST_ACTIVE_ENTRY_UPDATE", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED" }) do
        self.layoutEvents:RegisterEvent(event)
    end
    self.layoutEvents:SetScript("OnEvent", queue)
    queue()
    return true
end

function FrameSwitch:Install()
    EnsureButton(self)
    local footerInstalled = self:InstallApplicantLayout()
    local installed = self.button ~= nil and footerInstalled
    if installed and self.loader then
        self.loader:UnregisterAllEvents()
        self.loader:SetScript("OnEvent", nil)
        self.loader = nil
    end
    return installed
end

function FrameSwitch:Create()
    -- Миграция старой настройки: даже если подмена была сохранена включённой,
    -- после обновления штатная микрокнопка немедленно освобождается.
    if MythicBoostDB then MythicBoostDB.replaceGroupFinder = false end
    if self:Install() then return end
    if self.loader then return end
    self.loader = CreateFrame("Frame")
    self.loader:RegisterEvent("ADDON_LOADED")
    self.loader:SetScript("OnEvent", function(_, _, name)
        if name == "Blizzard_GroupFinder" or name == "Blizzard_PVEFrame" then self:Install() end
    end)
end

function FrameSwitch:Enable()
    self.layoutDisabled = nil
    if self.layoutEvents then
        for _, event in ipairs({ "LFG_LIST_ACTIVE_ENTRY_UPDATE", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED" }) do
            self.layoutEvents:RegisterEvent(event)
        end
    end
    self:QueueApplicantLayout()
end
function FrameSwitch:Disable()
    self.layoutDisabled = true
    if self.layoutEvents then self.layoutEvents:UnregisterAllEvents() end
end
function FrameSwitch:Destroy() end

JP.FrameSwitch = FrameSwitch
JP:RegisterModule("FrameSwitch", FrameSwitch)
