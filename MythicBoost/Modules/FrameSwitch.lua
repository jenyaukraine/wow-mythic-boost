local _, JP = ...
local FrameSwitch = {}
local UI = JP.UI

-- Подмена штатного окна поиска групп своим.
--
-- Работает как переключатель, а не как захват: кнопка появляется на окне
-- Blizzard, а в нашем окне есть обратная. Если включён режим замены, окно
-- «Подземелья и рейды» само уступает место нашему.
--
-- В бою не вмешиваемся вообще: система панелей Blizzard в это время
-- защищена, и попытка спрятать окно оборвётся ошибкой.

local function Welcome()
    return JP.modules.Welcome
end

local function OpenOurs()
    local welcome = Welcome()
    if not welcome then return end
    if not welcome.frame then welcome:Create() end
    if welcome.frame then welcome.frame:Show() end
end

local function OpenBlizzard()
    if InCombatLockdown() then
        JP:Print("В бою переключать окна нельзя.")
        return
    end
    if type(PVEFrame_ToggleFrame) == "function" then
        pcall(PVEFrame_ToggleFrame, "GroupFinderFrame")
    elseif PVEFrame and type(ShowUIPanel) == "function" then
        pcall(ShowUIPanel, PVEFrame)
    end
end
FrameSwitch.OpenBlizzard = function() OpenBlizzard() end

function FrameSwitch:IsReplacing()
    return MythicBoostDB and MythicBoostDB.replaceGroupFinder == true
end

function FrameSwitch:SetReplacing(enabled)
    MythicBoostDB.replaceGroupFinder = enabled and true or false
    if self.button then
        self.button:SetText(enabled and "Открыть MythicBoost" or "MythicBoost")
    end
    JP:Print(enabled
        and "Окно поиска групп будет заменяться на MythicBoost. Вернуть: |cff28b8f5/mb replace|r"
        or "Штатное окно поиска групп больше не подменяется.")
end

-- Кнопка на окне Blizzard: даже при выключенной замене отсюда можно попасть
-- в наше окно одним кликом.
local function EnsureButton(module)
    if module.button or not PVEFrame then return end
    local button = UI.Button(PVEFrame, module:IsReplacing() and "Открыть MythicBoost" or "MythicBoost", 150, 22, true)
    button:SetPoint("TOPRIGHT", -60, -26)
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
            "Открыть окно подбора групп: фильтры, кандидаты и рейтинг гильдии.",
            "Постоянная замена этого окна включается командой /mb replace")
    end)
    button:HookScript("OnLeave", GameTooltip_Hide)
    module.button = button
end

local function EnsureReplacement(module)
    if module.hooked or not PVEFrame then return end
    module.hooked = true
    PVEFrame:HookScript("OnShow", function()
        if not module:IsReplacing() or InCombatLockdown() then return end
        -- Прячем на следующем кадре: в момент OnShow система панелей ещё
        -- достраивает окно, и вмешательство внутрь этого вызова ломает её.
        C_Timer.After(0, function()
            if not module:IsReplacing() or InCombatLockdown() then return end
            if PVEFrame and PVEFrame:IsShown() and type(HideUIPanel) == "function" then
                pcall(HideUIPanel, PVEFrame)
            end
            OpenOurs()
        end)
    end)
end

function FrameSwitch:Install()
    EnsureButton(self)
    EnsureReplacement(self)
    return self.button ~= nil
end

function FrameSwitch:Create()
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
