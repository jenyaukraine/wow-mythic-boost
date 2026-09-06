local _, JP = ...
local UI, L, C = JP.UI, JP.L, JP.UI.colors
local Effects = JP.TempleHealerEffects
local Healer = {}
local TEMPLE_INSTANCE = 1877
local TARGETS = "[@boss1,exists,help] boss1; [@boss2,exists,help] boss2; [@boss3,exists,help] boss3; [@boss4,exists,help] boss4; [@boss5,exists,help] boss5; none"
local DEFAULTS = {enabled=true}
local function Settings() return JP.Settings("templeHealer", DEFAULTS) end

local function Place(frame, position)
    frame:ClearAllPoints()
    if position then frame:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
    else frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", UIParent:GetWidth()*.4375, UIParent:GetHeight()*.606) end
end

local function BuildVisuals(f)
    f.portrait = f:CreateTexture(nil, "OVERLAY")
    f.portrait:SetSize(32, 32); f.portrait:SetPoint("TOPLEFT", 7, -9)
    f.portrait:SetTexCoord(.08, .92, .08, .92)
    f.name = UI.Text(f, "GameFontHighlight", "", C.green)
    f.name:SetPoint("TOPLEFT", 45, -9); f.name:SetPoint("TOPRIGHT", -7, -9)
    f.name:SetJustifyH("LEFT"); f.name:SetWordWrap(false)
    f.health = UI.HUDBar(f, 24, {.08, .40, .24, 1})
    f.health:SetPoint("BOTTOMLEFT", 6, 6); f.health:SetPoint("BOTTOMRIGHT", -6, 6)
    f.health.left:SetText(L("Лечение"))
    f.health:SetMouseClickEnabled(false); f.health:SetMouseMotionEnabled(false)
end

function Healer:ShowPreview(position)
    if not self.previewFrame then
        -- Plain display only: never register with ClickCastFrames or inherit a
        -- secure unit template. A sample has no real unit to execute bindings on.
        local preview = UI.HUDPanel(UIParent, "MythicBoostTempleHealerPreview", 250, 86)
        preview:SetFrameStrata("DIALOG")
        preview:SetBackdropColor(.018, .040, .035, .98)
        preview:SetBackdropBorderColor(.18, .58, .44, 1)
        BuildVisuals(preview)
        UI.HUDMover(preview, Settings, function() return self.preview == true end)
        preview:EnableMouse(true)
        self.previewFrame = preview
    end
    local preview = self.previewFrame
    Place(preview, position)
    preview.name:SetText(L("Аватара Сетралисс"))
    preview.portrait:SetTexture("Interface/Icons/Spell_Nature_HealingWaveGreater")
    preview.health:SetMinMaxValues(0, 100); preview.health:SetValue(65)
    preview.health.right:SetText("65%")
    if Effects then Effects:Preview(preview) end
    preview:Show()
end


function Healer:Update()
    local f = self.frame
    if not f or not self.running or self.preview then return end
    local unit = JP.SafeString(f:GetAttribute("unit"))
    if not unit then return end
    -- Public, fixed boss tokens select the unit. Secret health/name values
    -- only reach native rendering sinks, never determine click behaviour.
    f.name:SetText(UnitName(unit))
    if SetPortraitTexture then SetPortraitTexture(f.portrait, unit) end
    f.health:SetMinMaxValues(0, UnitHealthMax(unit)); f.health:SetValue(UnitHealth(unit))
    f.health.right:SetFormattedText("%.0f%%", UnitHealthPercent(unit, true, self.percentCurve))
end

function Healer:Apply()
    if InCombatLockdown() then self.pending = true; return end
    self.pending = nil
    self:Create()
    local f, settings = self.frame, Settings()
    local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    local enabled = self.running and settings.enabled ~= false
    if Effects then Effects:ConfigureAuras(f, enabled and not self.preview and JP.SafeNumber(instanceID) == TEMPLE_INSTANCE) end
    f:SetAttribute("mb-enabled", enabled and not self.preview and JP.SafeNumber(instanceID) == TEMPLE_INSTANCE)
    local p = settings.position
    Place(f, p)
    UnregisterStateDriver(f, "healtarget")
    if enabled and self.preview then
        f:Hide(); f:SetAttribute("unit", nil)
        self:ShowPreview(p)
    else
        if self.previewFrame then self.previewFrame:Hide() end
        -- Install before the pull. The secure driver can select/show a
        -- friendly boss in combat without parsing its name, GUID or aura.
        -- Unregistering a driver retains its last state attribute. Reset it
        -- so leaving preview/reapplying cannot hide an unchanged boss forever.
        f:SetAttribute("state-healtarget", "none")
        f:Hide(); RegisterStateDriver(f, "healtarget", TARGETS)
        self:Update()
    end
    if not self.running then self.events:UnregisterAllEvents() end
end

function Healer:Create()
    if not self.events then
        self.events = CreateFrame("Frame")
        self.events:SetScript("OnEvent", function(_, event, unit, action, flags, amount)
            if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_ENTERING_WORLD"
                or event == "ZONE_CHANGED_NEW_AREA" then self:Apply()
            elseif event == "UNIT_COMBAT" then
                local target = self.frame and JP.SafeString(self.frame:GetAttribute("unit"))
                if Effects and self.running and not self.preview and Settings().enabled ~= false
                    and target and JP.SafeString(unit) == target and JP.SafeString(action) == "HEAL" then
                    Effects:Heal(self.frame, flags, amount)
                end
            else self:Update() end
        end)
    end
    if self.frame or InCombatLockdown() then return end
    local f = UI.HUDPanel(UIParent, "MythicBoostTempleHealer", 250, 86,
        "SecureUnitButtonTemplate, SecureHandlerStateTemplate")
    self.frame = f
    f:SetFrameStrata("MEDIUM"); f:SetClampedToScreen(true)
    f:SetBackdropColor(.018, .040, .035, .98)
    f:SetBackdropBorderColor(.18, .58, .44, 1)
    f:SetAttribute("*type1", "target"); f:SetAttribute("*type3", "focus")
    f:SetAttribute("useOnKeyDown", false); f:RegisterForClicks("AnyUp", "AnyDown")
    f:SetAttribute("mb-enabled", false)
    f:SetAttribute("_onstate-healtarget", [[
        local active = self:GetAttribute("mb-enabled") and (newstate == "boss1" or newstate == "boss2"
            or newstate == "boss3" or newstate == "boss4" or newstate == "boss5")
        for i = 1, 5 do
            local holder = self:GetFrameRef("healAuras" .. i)
            if holder then
                if active and newstate == "boss" .. i then holder:Show() else holder:Hide() end
            end
        end
        if active then
            self:SetAttribute("unit", newstate)
            self:Show()
        else
            self:Hide()
            self:SetAttribute("unit", nil)
        end
    ]])
    BuildVisuals(f)
    if Effects then Effects:Create(f) end
    self.percentCurve = C_CurveUtil.CreateCurve()
    self.percentCurve:SetType(Enum.LuaCurveType.Linear)
    self.percentCurve:AddPoint(0, 0); self.percentCurve:AddPoint(1, 100)
    UI.HUDMover(f, Settings, function() return self.preview == true end)
    -- SecureHandlerStateTemplate owns OnAttributeChanged: it dispatches
    -- state-healtarget to _onstate-healtarget. Replacing that script disables
    -- the entire secure show/unit-selection path, even with the setting on.
    f:HookScript("OnAttributeChanged", function(_, attribute)
        if attribute == "unit" then
            if Effects then Effects:Clear(f) end
            self:Update()
        end
    end)
    f:SetScript("OnShow", function() self:Update() end)
    f:SetScript("OnHide", function() if Effects then Effects:Clear(f) end end)
    f:SetScript("OnEnter", function(owner)
        UI.Tooltip(owner, L("Аватара Сетралисс"), L("Лечите наведением или клик-кастами. Левый клик выбирает цель."))
    end)
    f:SetScript("OnLeave", GameTooltip_Hide)
    -- Same public integration as our player/target frames. No edits to
    -- DandersFrames/Clique internals or the user's click-cast assignments.
    ClickCastFrames = ClickCastFrames or {}; ClickCastFrames[f] = true
    f:Hide()
end

function Healer:SetUnlocked(value)
    self.preview = value == true; self:Apply()
end

function Healer:Enable()
    self.running = true; self.preview = MythicBoostDB.interfaceUnlocked == true; self:Create()
    for _, event in ipairs({"PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
        "INSTANCE_ENCOUNTER_ENGAGE_UNIT", "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE", "UNIT_PORTRAIT_UPDATE", "UNIT_COMBAT"}) do
        if event:sub(1,5) == "UNIT_" then
            self.events:RegisterUnitEvent(event, "boss1", "boss2", "boss3", "boss4", "boss5")
        else self.events:RegisterEvent(event) end
    end
    self:Apply()
end

function Healer:Disable()
    self.running = false
    if Effects then Effects:Clear(self.frame) end
    if self.events then self:Apply() end
end

function Healer:Destroy() self:Disable() end
JP.TempleHealer = Healer
JP:RegisterModule("TempleHealer", Healer)
