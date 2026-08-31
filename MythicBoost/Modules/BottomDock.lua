local _, JP = ...

local BottomDock = {}
local UI, C, L = JP.UI, JP.UI.colors, JP.L
local ICON = "Interface\\AddOns\\MythicBoost\\Media\\MythicBoostIcon"

local function Options()
    MythicBoostDB.minimalUIOptions = type(MythicBoostDB.minimalUIOptions) == "table"
        and MythicBoostDB.minimalUIOptions or {}
    if MythicBoostDB.minimalUIOptions.bottomDock == nil then
        MythicBoostDB.minimalUIOptions.bottomDock = false
    end
    return MythicBoostDB.minimalUIOptions
end

local function Active()
    return MythicBoostDB and MythicBoostDB.minimalUI == true and Options().bottomDock ~= false
end

local function CaptureFrame(frame)
    local state = {
        parent = frame:GetParent(), points = {}, width = frame:GetWidth(), height = frame:GetHeight(),
        alpha = frame:GetAlpha(), shown = frame:IsShown(),
        strata = type(frame.GetFrameStrata) == "function" and frame:GetFrameStrata() or nil,
        level = type(frame.GetFrameLevel) == "function" and frame:GetFrameLevel() or nil,
        clamped = type(frame.IsClampedToScreen) == "function" and frame:IsClampedToScreen() or nil,
    }
    for index = 1, frame:GetNumPoints() do state.points[index] = { frame:GetPoint(index) } end
    if type(frame.GetDamageMeterType) == "function" then
        local ok, meterType = pcall(frame.GetDamageMeterType, frame)
        if ok then state.meterType = meterType end
    end
    return state
end

local function RestoreFrame(frame, state, created)
    if not frame or not state then return end
    frame:ClearAllPoints()
    if state.parent then frame:SetParent(state.parent) end
    for _, point in ipairs(state.points or {}) do frame:SetPoint(unpack(point)) end
    if #state.points == 0 then frame:SetPoint("CENTER", UIParent, "CENTER") end
    if state.width and state.height then frame:SetSize(state.width, state.height) end
    if state.strata and type(frame.SetFrameStrata) == "function" then frame:SetFrameStrata(state.strata) end
    if state.level and type(frame.SetFrameLevel) == "function" then frame:SetFrameLevel(state.level) end
    if state.clamped ~= nil and type(frame.SetClampedToScreen) == "function" then
        frame:SetClampedToScreen(state.clamped)
    end
    frame:SetAlpha(state.alpha or 1)
    if state.meterType ~= nil and type(frame.SetDamageMeterType) == "function" then
        pcall(frame.SetDamageMeterType, frame, state.meterType)
    end
    frame:SetShown(not created and state.shown == true)
end

local function NativeMeterWindows()
    local windows = {}
    local owner = _G.DamageMeter
    if owner and type(owner.ForEachSessionWindow) == "function" then
        pcall(owner.ForEachSessionWindow, owner, function(window)
            if window then windows[#windows + 1] = window end
        end)
    end
    if #windows == 0 then
        for index = 1, 10 do
            local frame = _G["DamageMeterSessionWindow" .. index]
            if frame then windows[#windows + 1] = frame end
        end
    end
    table.sort(windows, function(a, b)
        return (tonumber(a.sessionWindowIndex) or 99) < (tonumber(b.sessionWindowIndex) or 99)
    end)
    return windows
end

function BottomDock:EnsureNativeMeters()
    if not _G.DamageMeter and C_AddOns and type(C_AddOns.LoadAddOn) == "function" then
        pcall(C_AddOns.LoadAddOn, "Blizzard_DamageMeter")
    end
    local windows = NativeMeterWindows()
    local owner = _G.DamageMeter
    if #windows < 2 and owner and type(owner.ShowNewSessionWindow) == "function" then
        self.creatingMeters = true
        for _ = #windows + 1, 2 do pcall(owner.ShowNewSessionWindow, owner) end
        local refreshed = NativeMeterWindows()
        local known = {}
        for _, frame in ipairs(windows) do known[frame] = true end
        self.createdMeters = self.createdMeters or UI.WeakKeys()
        for _, frame in ipairs(refreshed) do
            if not known[frame] then self.createdMeters[frame] = true end
        end
        windows = refreshed
        self.creatingMeters = nil
    end
    return windows[1], windows[2]
end

function BottomDock:Build()
    if self.root then return end
    local root = UI.Panel(UIParent, { C.surface[1], C.surface[2], C.surface[3], .88 }, C.surfaceEdge)
    root:SetFrameStrata("LOW")
    root:SetHeight(176)
    root:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 8, 8)
    root:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -8, 8)
    root:EnableMouse(false)

    local top = UI.Line(root, C.edge)
    top:SetPoint("TOPLEFT", 1, -1); top:SetPoint("TOPRIGHT", -1, -1); top:SetHeight(2)

    local left = UI.Panel(root, { .020, .029, .040, .78 }, C.line)
    left:SetPoint("TOPLEFT", 8, -8); left:SetPoint("BOTTOMLEFT", 8, 8)
    left:EnableMouse(false)
    local chatTitle = UI.Text(left, "GameFontNormalSmall", L("ЧАТ"), C.accent)
    chatTitle:SetPoint("TOPLEFT", 10, -7)

    local right = UI.Panel(root, { .020, .029, .040, .78 }, C.line)
    right:SetPoint("TOPRIGHT", -8, -8); right:SetPoint("BOTTOMRIGHT", -8, 8)
    right:EnableMouse(false)
    local healingTab = UI.Tab(right, L("ИСЦЕЛЕНИЕ"), 112)
    healingTab:SetPoint("TOPLEFT", 6, -5)
    local damageTab = UI.Tab(right, L("УРОН"), 112)
    damageTab:SetPoint("LEFT", healingTab, "RIGHT", 4, 0)

    local healingArea = CreateFrame("Frame", nil, right)
    local damageArea = CreateFrame("Frame", nil, right)
    healingArea:EnableMouse(false); damageArea:EnableMouse(false)

    local brand = root:CreateTexture(nil, "ARTWORK")
    brand:SetTexture(ICON); brand:SetSize(34, 34); brand:SetPoint("TOP", 0, -8)
    local brandText = UI.Text(root, "GameFontNormalSmall", "MYTHICBOOST", C.muted)
    brandText:SetPoint("TOP", brand, "BOTTOM", 0, -2)
    local centerLineLeft = UI.Line(root, C.lineSoft)
    centerLineLeft:SetPoint("LEFT", left, "RIGHT", 14, 0); centerLineLeft:SetPoint("RIGHT", brand, "LEFT", -12, 0)
    local centerLineRight = UI.Line(root, C.lineSoft)
    centerLineRight:SetPoint("LEFT", brand, "RIGHT", 12, 0); centerLineRight:SetPoint("RIGHT", right, "LEFT", -14, 0)

    damageTab:SetScript("OnClick", function() self:SetMeterTab("damage") end)
    healingTab:SetScript("OnClick", function() self:SetMeterTab("healing") end)

    self.root, self.chatArea, self.meterArea = root, left, right
    self.healingArea, self.damageArea = healingArea, damageArea
    self.damageTab, self.healingTab = damageTab, healingTab
    self:Layout()
    root:Hide()
end

function BottomDock:Layout()
    if not self.root then return end
    local width = math.max(900, (UIParent:GetWidth() or 1280) - 16)
    local chatWidth = math.min(440, math.max(310, width * .23))
    local meterWidth = math.min(740, math.max(360, width * .36))
    self.chatArea:SetWidth(chatWidth)
    self.meterArea:SetWidth(meterWidth)
    self.wideMeters = width >= 1450

    self.healingTab:ClearAllPoints(); self.damageTab:ClearAllPoints()
    self.healingArea:ClearAllPoints(); self.damageArea:ClearAllPoints()
    if self.wideMeters then
        local tabWidth = math.max(112, (meterWidth - 16) * .5)
        self.healingTab:SetWidth(tabWidth)
        self.damageTab:SetWidth(tabWidth)
        self.healingTab:SetPoint("TOPLEFT", self.meterArea, "TOPLEFT", 6, -5)
        self.damageTab:SetPoint("TOPRIGHT", self.meterArea, "TOPRIGHT", -6, -5)
        self.healingArea:SetPoint("TOPLEFT", self.meterArea, "TOPLEFT", 3, -35)
        self.healingArea:SetPoint("BOTTOMRIGHT", self.meterArea, "BOTTOM", -2, 3)
        self.damageArea:SetPoint("TOPLEFT", self.meterArea, "TOP", 2, -35)
        self.damageArea:SetPoint("BOTTOMRIGHT", self.meterArea, "BOTTOMRIGHT", -3, 3)
    else
        self.healingTab:SetWidth(112); self.damageTab:SetWidth(112)
        self.healingTab:SetPoint("TOPLEFT", self.meterArea, "TOPLEFT", 6, -5)
        self.damageTab:SetPoint("LEFT", self.healingTab, "RIGHT", 4, 0)
        self.healingArea:SetPoint("TOPLEFT", self.meterArea, "TOPLEFT", 3, -35)
        self.healingArea:SetPoint("BOTTOMRIGHT", self.meterArea, "BOTTOMRIGHT", -3, 3)
        self.damageArea:SetAllPoints(self.healingArea)
    end
end

function BottomDock:Remember(frame)
    if not frame then return end
    self.states = self.states or UI.WeakKeys()
    if not self.states[frame] then self.states[frame] = CaptureFrame(frame) end
end

function BottomDock:Dock(frame, area, topInset)
    if not frame then return end
    self:Remember(frame)
    frame:SetParent(area)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", area, "TOPLEFT", 7, -(topInset or 34))
    frame:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -7, 7)
    if type(frame.SetFrameStrata) == "function" then frame:SetFrameStrata("LOW") end
    if type(frame.SetFrameLevel) == "function" then frame:SetFrameLevel(area:GetFrameLevel() + 3) end
    if type(frame.SetClampedToScreen) == "function" then frame:SetClampedToScreen(false) end
    frame:SetAlpha(1)
end

function BottomDock:SetMeterType(frame, meterType)
    if not frame or not meterType or type(frame.SetDamageMeterType) ~= "function" then return end
    pcall(frame.SetDamageMeterType, frame, meterType)
    if type(frame.Refresh) == "function" then pcall(frame.Refresh, frame) end
end

function BottomDock:SetMeterTab(tab)
    self.activeTab = tab == "healing" and "healing" or "damage"
    Options().bottomDockTab = self.activeTab
    if self.damageTab then self.damageTab:SetActive(self.wideMeters or self.activeTab == "damage") end
    if self.healingTab then self.healingTab:SetActive(self.wideMeters or self.activeTab == "healing") end
    if self.damageFrame then self.damageFrame:SetShown(self.active and (self.wideMeters or self.activeTab == "damage")) end
    if self.healingFrame then self.healingFrame:SetShown(self.active and (self.wideMeters or self.activeTab == "healing")) end
end

function BottomDock:Restore()
    self.active = false
    for frame, state in pairs(self.states or {}) do
        RestoreFrame(frame, state, self.createdMeters and self.createdMeters[frame])
    end
    if self.states then wipe(self.states) end
    self.chatFrame, self.damageFrame, self.healingFrame = nil, nil, nil
    if self.root then self.root:Hide() end
end

function BottomDock:Apply(forceMeters)
    if InCombatLockdown() then self.pendingApply = forceMeters and true or self.pendingApply; return false end
    self:Build(); self:Layout()
    if not Active() then self:Restore(); return true end

    self.active = true
    self.root:Show()
    local chat = _G.ChatFrame1
    if chat then self:Dock(chat, self.chatArea, 25); chat:Show(); self.chatFrame = chat end

    local damage, healing = self:EnsureNativeMeters()
    self.damageFrame, self.healingFrame = damage, healing
    if damage then
        self:Dock(damage, self.damageArea, 2)
        self:SetMeterType(damage, Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageDone)
    end
    if healing then
        self:Dock(healing, self.healingArea, 2)
        self:SetMeterType(healing, Enum and Enum.DamageMeterType and Enum.DamageMeterType.HealingDone)
    end
    self:SetMeterTab(Options().bottomDockTab)
    return true
end

function BottomDock:SetEnabled(enabled)
    Options().bottomDock = enabled and true or false
    self:Apply(enabled)
end

function BottomDock:ShowOnboarding()
    if not MythicBoostDB or (MythicBoostDB.layoutOnboardingRevision or 0) >= 1 then return end
    MythicBoostDB.layoutOnboardingRevision = 1
    StaticPopupDialogs.MYTHICBOOST_COMPACT_HUD = {
        text = L("Применить компактный нижний HUD MythicBoost? Чат и штатные окна урона и исцеления будут собраны в одну панель. Всё можно отключить с полным возвратом раскладки Blizzard."),
        button1 = L("ПРИМЕНИТЬ"), button2 = L("ПОЗЖЕ"), timeout = 0, whileDead = true,
        hideOnEscape = true, preferredIndex = 3,
        OnAccept = function()
            MythicBoostDB.minimalUI = true
            Options().bottomDock = true
            Options().compactActionBars = true
            if JP.MinimalUI then JP.MinimalUI:SetEnabled(true) end
            BottomDock:Apply(true)
        end,
    }
    StaticPopup_Show("MYTHICBOOST_COMPACT_HUD")
end

function BottomDock:Create()
    if self.events then return end
    self.events = CreateFrame("Frame")
    for _, event in ipairs({
        "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "UPDATE_CHAT_WINDOWS",
        "DISPLAY_SIZE_CHANGED", "ADDON_LOADED",
    }) do self.events:RegisterEvent(event) end
    self.events:SetScript("OnEvent", function(_, event, addon)
        if event == "PLAYER_REGEN_ENABLED" and self.pendingApply ~= nil then
            local force = self.pendingApply; self.pendingApply = nil; self:Apply(force)
        elseif event == "ADDON_LOADED" and addon ~= "Blizzard_DamageMeter" then
            return
        else
            C_Timer.After(.15, function()
                self:Apply()
                if event == "PLAYER_REGEN_ENABLED" then self:ShowOnboarding() end
            end)
        end
    end)
    C_Timer.After(1.2, function()
        self:Apply()
        if not InCombatLockdown() then self:ShowOnboarding() end
    end)
end

function BottomDock:Enable() self:Create(); self:Apply() end
function BottomDock:Disable() self:Restore() end
function BottomDock:Destroy() self:Restore() end

JP.BottomDock = BottomDock
JP:RegisterModule("BottomDock", BottomDock)
