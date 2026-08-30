local _, JP = ...
local L = JP.L
local FrameSwitch = {}
local UI = JP.UI

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
        return
    end
    local welcome = Welcome()
    if welcome and welcome.frame then welcome.frame:Hide() end
    if type(PVEFrame_ToggleFrame) == "function" then
        pcall(PVEFrame_ToggleFrame, "GroupFinderFrame")
    elseif PVEFrame and type(ShowUIPanel) == "function" then
        pcall(ShowUIPanel, PVEFrame)
    end
end
FrameSwitch.OpenBlizzard = function() OpenBlizzard() end

function FrameSwitch:IsReplacing()
    return false
end

function FrameSwitch:SetReplacing()
    if MythicBoostDB then MythicBoostDB.replaceGroupFinder = false end
    if self.button then self.button:SetText("MB") end
    JP:Print(L("Штатная кнопка «Поиск группы» не подменяется. MythicBoost открывается кнопкой внутри окна Blizzard."))
end

-- Кнопка на окне Blizzard: даже при выключенной замене отсюда можно попасть
-- в наше окно одним кликом.
local function EnsureButton(module)
    if module.button or not PVEFrame then return end
    local button = UI.Button(PVEFrame, "MB", 38, 22, true)
    -- Keep it flush with the right end of the secondary header row. The
    -- close button occupies the row above, so this does not overlap it.
    button:SetPoint("TOPRIGHT", -8, -26)
    button:SetFrameStrata("HIGH")
    button:SetScript("OnClick", function()
        if InCombatLockdown() then
            OpenOurs()
            return
        end
        if PVEFrame and PVEFrame:IsShown() and type(HideUIPanel) == "function" then
            pcall(HideUIPanel, PVEFrame)
        end
        OpenOurs()
    end)
    button:HookScript("OnEnter", function(self)
        UI.Tooltip(self, "MythicBoost",
            L("Открыть окно подбора групп: фильтры, кандидаты и рейтинг гильдии."),
            L("Штатная кнопка «Поиск группы» всегда продолжает открывать окно Blizzard."))
    end)
    button:HookScript("OnLeave", GameTooltip_Hide)
    module.button = button
end

function FrameSwitch:Install()
    EnsureButton(self)
    return self.button ~= nil
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

function FrameSwitch:Enable() end
function FrameSwitch:Disable() end
function FrameSwitch:Destroy() end

JP.FrameSwitch = FrameSwitch
JP:RegisterModule("FrameSwitch", FrameSwitch)
