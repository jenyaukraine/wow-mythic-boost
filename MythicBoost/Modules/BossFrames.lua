local _, JP = ...
local UI, L, C = JP.UI, JP.L, JP.UI.colors
local Bosses = {}
local function Settings() return JP.Settings("bossFrames", {enabled=true}) end
local MAX_BOSSES, WIDTH, HEIGHT = 5, 244, 74

function Bosses:Layout()
    if not self.frame then return end
    if InCombatLockdown() then self.layoutPending = true; return end
    self.layoutPending = nil
    local f, p = self.frame, Settings().position
    f:ClearAllPoints()
    if p then f:SetPoint(p.point, UIParent, p.relativePoint, p.x, p.y)
    else f:SetPoint("TOPRIGHT", Minimap or UIParent, "TOPLEFT", -12, 0) end
    f:EnableMouse(self.preview == true)
end

function Bosses:UpdateCast(row)
    local duration = UnitCastingDuration and UnitCastingDuration(row.unit)
    local channel = false
    if type(duration) == "nil" then
        duration = UnitChannelDuration and UnitChannelDuration(row.unit)
        channel = true
    end
    if type(duration) == "nil" then row.cast:Hide(); row.duration = nil; return end
    local name, _, texture
    if channel then name, _, texture = UnitChannelInfo(row.unit)
    else name, _, texture = UnitCastingInfo(row.unit) end
    -- Secret names, textures, amounts and duration objects go straight to
    -- rendering APIs. No arithmetic, indexing, sorting or cached target names.
    row.cast.left:SetText(name); row.castIcon:SetTexture(texture)
    row.cast:SetTimerDuration(duration, Enum.StatusBarInterpolation.Immediate,
        channel and Enum.StatusBarTimerDirection.RemainingTime or Enum.StatusBarTimerDirection.ElapsedTime)
    row.duration = duration; row.cast:Show()
end

function Bosses:Update(row, event)
    if self.preview or not self.running then return end
    if not event or event == "UNIT_NAME_UPDATE" or event == "UNIT_PORTRAIT_UPDATE" then
        row.name:SetText(UnitName(row.unit))
        if SetPortraitTexture then SetPortraitTexture(row.portrait, row.unit) end
    end
    if not event or event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        row.health:SetMinMaxValues(0, UnitHealthMax(row.unit)); row.health:SetValue(UnitHealth(row.unit))
        row.health.right:SetFormattedText("%.0f%%", UnitHealthPercent(row.unit, true, self.percentCurve))
    end
    if not event or event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
        row.power:SetMinMaxValues(0, UnitPowerMax(row.unit)); row.power:SetValue(UnitPower(row.unit))
    end
    if not event or event:find("UNIT_SPELLCAST_", 1, true) then self:UpdateCast(row) end
end

function Bosses:NativeVisibility(hide)
    if InCombatLockdown() then self.layoutPending = true; return end
    self.nativeFrames = self.nativeFrames or {}
    if hide then
        for i = 0, MAX_BOSSES do
            local native = i == 0 and _G.BossTargetFrameContainer or _G["Boss"..i.."TargetFrame"]
            if native then
                if not self.nativeFrames[native] then
                    self.nativeFrames[native] = {parent=native:GetParent(), ignore=native.ignoreFramePositionManager}
                end
                -- The managed container's OnShow used to undo reparenting.
                -- Its named child unit frames are hidden as well; no event
                -- handlers are removed, so disabling our module restores them.
                native.ignoreFramePositionManager = true
                if native.layoutParent and native.layoutParent.RemoveManagedFrame then
                    native.layoutParent:RemoveManagedFrame(native)
                end
                if native:GetParent() ~= self.hider then native:SetParent(self.hider) end
            end
        end
    else
        for native, saved in pairs(self.nativeFrames) do
            native.ignoreFramePositionManager = saved.ignore
            if native:GetParent() == self.hider then native:SetParent(saved.parent) end
            if native.layoutParent and native.layoutParent.AddManagedFrame and not saved.ignore then
                native.layoutParent:AddManagedFrame(native)
            end
        end
        wipe(self.nativeFrames)
    end
end

function Bosses:Apply()
    if InCombatLockdown() then self.layoutPending = true; return end
    if not self.frame then self:Create() end
    if not self.frame then return end
    local show = self.running and Settings().enabled ~= false
    self:NativeVisibility(show)
    self:Layout(); self.frame:SetShown(show)
    for i, row in ipairs(self.rows) do
        if self.preview and show then
            UnregisterUnitWatch(row); row:Show()
            row.name:SetText(L("Босс") .. " " .. i)
            row.portrait:SetTexture("Interface/Icons/Achievement_Boss_General_Nazgrim")
            row.health:SetMinMaxValues(0, 100); row.health:SetValue(80-i*9)
            row.health.right:SetText((80-i*9) .. "%")
            row.power:SetMinMaxValues(0, 100); row.power:SetValue(50)
            row.cast:SetMinMaxValues(0, 1); row.cast:SetValue(.6)
            row.cast.left:SetText(L("Предпросмотр каста")); row.castIcon:SetTexture(136048); row.cast:Show()
        else
            RegisterUnitWatch(row); self:Update(row)
        end
    end
end

function Bosses:SetUnlocked(value)
    self.preview = value == true; self:Apply()
end

function Bosses:Create()
    if self.frame or InCombatLockdown() then return end
    self.frame = CreateFrame("Frame", "MythicBoostBossFrames", UIParent)
    self.frame:SetSize(WIDTH, MAX_BOSSES * (HEIGHT+5)); self.frame:SetFrameStrata("MEDIUM")
    self.hider = CreateFrame("Frame", nil, UIParent); self.hider:Hide()
    UI.HUDMover(self.frame, Settings, function() return self.preview end)
    self.percentCurve = C_CurveUtil.CreateCurve()
    self.percentCurve:SetType(Enum.LuaCurveType.Linear)
    self.percentCurve:AddPoint(0, 0); self.percentCurve:AddPoint(1, 100)
    self.rows = {}
    for i = 1, MAX_BOSSES do
        local row = UI.HUDPanel(self.frame, "MythicBoostBoss" .. i, WIDTH, HEIGHT, "SecureUnitButtonTemplate")
        row:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
        row:SetBackdropColor(.025, .035, .047, 1)
        row:SetBackdropBorderColor(UI.Unpack(C.hudEdge))
        row.unit = "boss" .. i
        row:SetPoint("TOPLEFT", 0, -(i-1)*(HEIGHT+5))
        row:SetAttribute("unit", row.unit); row:SetAttribute("*type1", "target")
        row:SetAttribute("*type2", "togglemenu"); row:SetAttribute("*type3", "focus")
        row:RegisterForClicks("AnyUp"); RegisterUnitWatch(row)
        row.portraitBorder = CreateFrame("Frame", nil, row, "BackdropTemplate")
        row.portraitBorder:SetSize(48, 48); row.portraitBorder:SetPoint("TOPLEFT", 5, -5)
        row.portraitBorder:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8",
            edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
        row.portraitBorder:SetBackdropColor(.02, .03, .04, 1)
        row.portraitBorder:SetBackdropBorderColor(UI.Unpack(C.hudEdge))
        row.portrait = row.portraitBorder:CreateTexture(nil, "ARTWORK")
        row.portrait:SetPoint("TOPLEFT", 2, -2); row.portrait:SetPoint("BOTTOMRIGHT", -2, 2)
        row.portrait:SetTexCoord(.08, .92, .08, .92)
        row.name = UI.Text(row, "GameFontHighlightSmall", "", C.amber)
        row.name:SetPoint("TOPLEFT", 60, -7); row.name:SetPoint("TOPRIGHT", -8, -7)
        row.name:SetWordWrap(false); row.name:SetJustifyH("LEFT")
        row.health = UI.HUDBar(row, 21, {.62, .20, .16, 1})
        row.health:SetPoint("TOPLEFT", 59, -25); row.health:SetPoint("TOPRIGHT", -6, -25)
        local gloss = row.health:CreateTexture(nil, "ARTWORK")
        gloss:SetAllPoints(); gloss:SetColorTexture(1, 1, 1, 1)
        gloss:SetGradient("VERTICAL", CreateColor(0, 0, 0, .2), CreateColor(1, 1, 1, .12))
        row.power = UI.HUDBar(row, 3, {.18, .36, .66, 1})
        row.power:SetPoint("TOPLEFT", 59, -48); row.power:SetPoint("TOPRIGHT", -6, -48)
        row.cast = UI.HUDBar(row, 15, {.64, .34, .09, 1})
        row.cast:SetPoint("BOTTOMLEFT", 21, 5); row.cast:SetPoint("BOTTOMRIGHT", -5, 5)
        row.cast.left:SetPoint("RIGHT", -3, 0)
        row.castIcon = row.cast:CreateTexture(nil, "ARTWORK")
        row.castIcon:SetSize(15, 15); row.castIcon:SetPoint("RIGHT", row.cast, "LEFT", -1, 0)
        row.castIcon:SetTexCoord(.08, .92, .08, .92)
        row:SetScript("OnEvent", function(_, event) self:Update(row, event) end)
        self.rows[i] = row
    end
    self.events = CreateFrame("Frame")
    self.events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" or event == "ADDON_LOADED" or event == "EDIT_MODE_LAYOUTS_UPDATED" then self:Apply()
        else for _, row in ipairs(self.rows) do self:Update(row) end end
    end)
end

function Bosses:Enable()
    if Settings().enabled == false then self:Disable(); return end
    if InCombatLockdown() and not self.frame then
        self.pendingEnable = true
        if not self.bootstrap then
            self.bootstrap = CreateFrame("Frame")
            self.bootstrap:SetScript("OnEvent", function()
                self.bootstrap:UnregisterAllEvents()
                if self.pendingEnable then self.pendingEnable = nil; self:Enable() end
            end)
        end
        self.bootstrap:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    self.pendingEnable = nil
    if self.bootstrap then self.bootstrap:UnregisterAllEvents() end
    self.running = true; self:Create()
    if not self.frame then return end
    for _, row in ipairs(self.rows) do
        for _, event in ipairs({"UNIT_NAME_UPDATE", "UNIT_PORTRAIT_UPDATE", "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE",
            "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
            "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_CHANNEL_UPDATE",
            "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED",
            "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_STOP", "UNIT_SPELLCAST_EMPOWER_UPDATE"}) do
            row:RegisterUnitEvent(event, row.unit)
        end
    end
    for _, event in ipairs({"PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
        "ADDON_LOADED", "EDIT_MODE_LAYOUTS_UPDATED"}) do self.events:RegisterEvent(event) end
    self:Apply()
end
function Bosses:Disable()
    self.running = false
    self.pendingEnable = nil
    if self.bootstrap then self.bootstrap:UnregisterAllEvents() end
    if self.events then self.events:UnregisterAllEvents() end
    for _, row in ipairs(self.rows or {}) do row:UnregisterAllEvents() end
    if InCombatLockdown() then
        if self.events then self.events:RegisterEvent("PLAYER_REGEN_ENABLED") end
        return
    end
    self:NativeVisibility(false)
    if self.frame then self.frame:Hide() end
end
function Bosses:Destroy() self:Disable() end
JP.BossFrames = Bosses
JP:RegisterModule("BossFrames", Bosses)
