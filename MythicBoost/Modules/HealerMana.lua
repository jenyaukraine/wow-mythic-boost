local _, JP = ...
local UI, L, C = JP.UI, JP.L, JP.UI.colors
local Mana = {}
local MAX_HEALERS = 8
local function Settings() return JP.Settings("healerMana", {enabled=true, threshold=20}) end

function Mana:BuildCurves()
    local threshold = math.max(5, math.min(50, JP.SafeNumber(Settings().threshold) or 20)) / 100
    -- The engine evaluates restricted mana against the display curve. Lua
    -- never compares the value or reads alpha back. This is visual only.
    self.alertCurve = C_CurveUtil.CreateCurve()
    self.alertCurve:SetType(Enum.LuaCurveType.Step)
    self.alertCurve:AddPoint(0, 1); self.alertCurve:AddPoint(threshold + .00001, 0)
    self.alertCurve:AddPoint(1, 0)
    self.percentCurve = C_CurveUtil.CreateCurve()
    self.percentCurve:SetType(Enum.LuaCurveType.Linear)
    self.percentCurve:AddPoint(0, 0); self.percentCurve:AddPoint(1, 100)
end

function Mana:IsTank()
    local spec = GetSpecialization and GetSpecialization()
    local role = spec and GetSpecializationRole and GetSpecializationRole(spec)
    return JP.SafeString(role) == "TANK"
end

function Mana:RefreshRoster()
    self.healers = {}
    if self:IsTank() then
        local raid = JP.SafeBoolean(IsInRaid())
        local count = raid and math.min(JP.SafeNumber(GetNumGroupMembers()) or 0, 40) or 4
        for i = 1, count do
            local unit = (raid and "raid" or "party") .. i
            if JP.SafeBoolean(UnitExists(unit)) and JP.SafeString(UnitGroupRolesAssigned(unit)) == "HEALER"
                and #self.healers < MAX_HEALERS then self.healers[#self.healers+1] = unit end
        end
    end
    self:Refresh()
end

function Mana:Update()
    for i, row in ipairs(self.rows) do
        local unit = self.healers[i]
        if self.preview then
            row:SetShown(i == 1); row:SetAlpha(1)
            row.name:SetText(L("Лекарь")); row.value:SetText("18%"); row.mana:SetValue(18)
        elseif unit then
            -- Offline/dead/phase-unknown healers are not low-mana alerts.
            local available = JP.SafeBoolean(UnitIsConnected(unit))
                and JP.SafeOptionalBoolean(UnitIsDeadOrGhost(unit)) == false
                and JP.SafeBoolean(UnitIsVisible(unit))
            row:SetShown(available)
            if available then
                row.name:SetText(UnitName(unit))
                local percent = UnitPowerPercent(unit, Enum.PowerType.Mana, false, self.percentCurve)
                row.value:SetFormattedText("%.0f%%", percent)
                row.mana:SetValue(percent)
                row:SetAlpha(UnitPowerPercent(unit, Enum.PowerType.Mana, false, self.alertCurve))
            end
        else row:Hide() end
    end
end

function Mana:Layout()
    if not self.frame then return end
    local p = Settings().position
    self.frame:ClearAllPoints()
    if p then self.frame:SetPoint(p.point, UIParent, p.relativePoint, p.x, p.y)
    else self.frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", UIParent:GetWidth()*.02, -UIParent:GetHeight()*.636) end
    self.frame:EnableMouse(self.preview == true)
end

function Mana:Refresh()
    if not self.frame then return end
    local shown = self.running and Settings().enabled ~= false and (self.preview or #(self.healers or {}) > 0)
    self.frame:SetShown(shown); self:Layout()
    if shown then self:Update() end
end
function Mana:SetUnlocked(value) self.preview = value == true; self:Refresh() end

function Mana:Create()
    if self.frame then return end
    self.frame = CreateFrame("Frame", "MythicBoostHealerMana", UIParent)
    self.frame:SetSize(300, 48); self.frame:SetFrameStrata("HIGH")
    self.rows, self.healers = {}, {}
    for i = 1, MAX_HEALERS do
        local row = UI.HUDPanel(self.frame, nil, 300, 48)
        row:SetPoint("TOP", 0, -(i-1)*52); row:EnableMouse(false)
        row:SetBackdropColor(.018, .028, .040, .96)
        row:SetBackdropBorderColor(.23, .28, .31, .9)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(32, 32); row.icon:SetPoint("LEFT", 9, 0)
        row.icon:SetTexture("Interface/Icons/INV_Potion_76")
        row.icon:SetTexCoord(.08, .92, .08, .92)
        row.title = UI.Text(row, "GameFontNormal", L("Мало маны"), C.amber)
        row.title:SetPoint("TOPLEFT", 51, -7)
        row.name = UI.Text(row, "GameFontHighlightSmall", "", C.muted)
        row.name:SetPoint("BOTTOMLEFT", 51, 9); row.name:SetPoint("RIGHT", -66, 0)
        row.name:SetJustifyH("LEFT"); row.name:SetWordWrap(false)
        row.value = UI.Text(row, "GameFontNormalLarge", "", C.amber)
        row.value:SetPoint("RIGHT", -12, 1)
        row.mana = CreateFrame("StatusBar", nil, row)
        row.mana:SetPoint("BOTTOMLEFT", 51, 3); row.mana:SetPoint("BOTTOMRIGHT", -12, 3)
        row.mana:SetHeight(2); row.mana:SetMinMaxValues(0, 100)
        row.mana:SetStatusBarTexture("Interface/Buttons/WHITE8X8")
        row.mana:SetStatusBarColor(.20, .59, .90, 1)
        row.mana:EnableMouse(false)
        self.rows[i] = row
    end
    UI.HUDMover(self.frame, Settings, function() return self.preview end)
    self.events = CreateFrame("Frame")
    self.events:SetScript("OnEvent", function(_, event, unit, power)
        if event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" then
            if JP.SafeString(power) ~= "MANA" then return end
            for _, healer in ipairs(self.healers) do if unit == healer then self:Update(); return end end
        elseif event == "UNIT_CONNECTION" or event == "UNIT_FLAGS" or event == "UNIT_PHASE" then self:Update()
        else self:RefreshRoster() end
    end)
end
function Mana:Enable()
    if not UnitPowerPercent or not C_CurveUtil then return end
    self:Create(); self.running = true; self:BuildCurves()
    for _, event in ipairs({"PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED",
        "PLAYER_SPECIALIZATION_CHANGED", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_CONNECTION",
        "UNIT_FLAGS", "UNIT_PHASE", "PLAYER_REGEN_ENABLED"}) do self.events:RegisterEvent(event) end
    self:RefreshRoster()
end
function Mana:Disable()
    self.running = false
    if self.events then self.events:UnregisterAllEvents() end
    if self.frame then self.frame:Hide() end
end
function Mana:Destroy() self:Disable() end
JP.HealerMana = Mana
JP:RegisterModule("HealerMana", Mana)
