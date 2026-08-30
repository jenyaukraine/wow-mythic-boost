local _, JP = ...
local L = JP.L
local UI = JP.UI
local C = JP.UI.colors

local CastBar = {}
local XPERL_BAR = "Interface\\TargetingFrame\\UI-StatusBar"
local CAPSULE_EDGE = "Interface\\AddOns\\MythicBoost\\Media\\XPerl_ThinEdge"
local SPARK = "Interface\\CastingBar\\UI-CastingBar-Spark"

local CAST_COLOR = { 1.00, .49, 0 }
local CHANNEL_COLOR = { .32, .30, 1 }
local COMPLETE_COLOR = { .12, .86, .15 }
local FAILED_COLOR = { 1, .09, 0 }
local TIME_PANEL_WIDTH = 58
local SETTINGS_DEFAULTS = { enabled = true, unlocked = false }

local function MatteBarColor(bar, color)
    local r, g, b = unpack(color)
    bar:SetStatusBarColor(1, 1, 1, 1)
    local texture = bar:GetStatusBarTexture()
    if texture then
        texture:SetGradient("VERTICAL",
            CreateColor(r * .36, g * .36, b * .36, 1),
            CreateColor(r, g, b, 1))
    end
end

local function Settings()
    local settings = JP.Settings("castBar", SETTINGS_DEFAULTS) or {}
    if settings.layoutRevision ~= 2 then
        settings.point, settings.relativePoint = "BOTTOM", "BOTTOM"
        settings.x, settings.y = 0, 250
        settings.layoutRevision = 2
    end
    return settings
end

local PlainNumber = UI.UsableNumber

local function UnitMatches(unit)
    return unit == "player" or unit == "vehicle"
end

local function UpdateTimeDisplay(frame, remaining)
    local urgent = remaining <= 1.5
    if frame.timeUrgent ~= urgent then
        frame.timeUrgent = urgent
        if frame.timeFont then frame.time:SetFont(frame.timeFont, urgent and 15 or 14, "OUTLINE") end
    end
    -- Continuous, readable urgency: neutral above three seconds, then a
    -- smooth white -> amber -> red transition with no distracting flashing.
    local r, g, b
    if remaining >= 3 then
        r, g, b = .96, .98, 1
    elseif remaining >= 1.5 then
        local t = (3 - remaining) / 1.5
        r = .96 + (.04 * t)
        g = .98 + (.72 - .98) * t
        b = 1 + (.12 - 1) * t
    else
        local t = math.max(0, math.min(1, (1.5 - remaining) / 1.5))
        r = 1
        g = .72 + (.18 - .72) * t
        b = .12 + (.06 - .12) * t
    end
    frame.time:SetTextColor(r, g, b, 1)
    frame.time:SetAlpha(1)
    frame.time:SetFormattedText("%.1f", remaining)
end

local function ApplyBackdrop(frame)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = CAPSULE_EDGE,
        tile = true,
        tileSize = 16,
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    -- Общие токены UI.colors вместо собственного тёмного:
    -- эта панель стоит на экране рядом с остальными.
    frame:SetBackdropColor(C.surface[1], C.surface[2], C.surface[3], .97)
    frame:SetBackdropBorderColor(.34, .39, .45, 1)
    if not frame.__mbCapsuleGradient then
        local gradient = frame:CreateTexture(nil, "ARTWORK", nil, -5)
        gradient:SetColorTexture(1, 1, 1, 1)
        gradient:SetBlendMode("ADD")
        gradient:SetPoint("TOPLEFT", 2, -2)
        gradient:SetPoint("BOTTOMRIGHT", -2, 2)
        gradient:SetGradient("VERTICAL",
            CreateColor(0, 0, 0, 0),
            CreateColor(.42, .52, .62, .24))
        frame.__mbCapsuleGradient = gradient
    end
end

local function ReadCast(channel)
    if channel then
        local name, displayName, icon, startMS, endMS, _, notInterruptible, spellID, _, stages = UnitChannelInfo("player")
        return name, displayName or name, icon, startMS, endMS, notInterruptible, spellID, stages
    end
    local name, displayName, icon, startMS, endMS, _, _, notInterruptible, spellID = UnitCastingInfo("player")
    return name, displayName or name, icon, startMS, endMS, notInterruptible, spellID
end

function CastBar:SavePosition()
    local point, _, relativePoint, x, y = self.frame:GetPoint()
    local settings = Settings()
    settings.point, settings.relativePoint, settings.x, settings.y = point, relativePoint, x, y
end

function CastBar:RestorePosition()
    local frame, settings = self.frame, Settings()
    frame:ClearAllPoints()
    if type(settings.point) == "string" and PlainNumber(settings.x) and PlainNumber(settings.y) then
        frame:SetPoint(settings.point, UIParent, settings.relativePoint or settings.point, settings.x, settings.y)
    else
        frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 250)
    end
end

function CastBar:UpdateLatency(duration)
    local frame = self.frame
    local _, _, homeMS, worldMS = GetNetStats()
    local networkMS = PlainNumber(worldMS) and worldMS
        or (PlainNumber(homeMS) and homeMS or 0)
    if not self.castLatency then
        local measured = self.sentAt and math.max(0, GetTime() - self.sentAt) or 0
        self.castLatency = math.max(networkMS / 1000, measured)
    end
    local latency = math.min(duration, self.castLatency or 0)
    local latencyMS = math.max(0, math.floor(latency * 1000 + .5))
    frame.latencyText:Hide()
    if latency <= 0 or duration <= 0 then frame.latency:Hide(); return end
    local fraction = math.min(1, latency / duration)
    frame.latency:ClearAllPoints()
    if self.channeling then
        frame.latency:SetPoint("TOPLEFT", frame.bar, "TOPLEFT", 0, 0)
        frame.latency:SetPoint("BOTTOMLEFT", frame.bar, "BOTTOMLEFT", 0, 0)
    else
        frame.latency:SetPoint("TOPRIGHT", frame.bar, "TOPRIGHT", 0, 0)
        frame.latency:SetPoint("BOTTOMRIGHT", frame.bar, "BOTTOMRIGHT", 0, 0)
    end
    frame.latency:SetWidth(math.max(1, frame.bar:GetWidth() * fraction))
    frame.latency:Show()
end

function CastBar:Start(channel, empower)
    -- Quartz может создать свой Player bar позже MythicBoost. Проверяем
    -- конкурирующие полосы перед каждым новым кастом, чтобы дубликат не успел
    -- появиться даже при необычном порядке загрузки аддонов.
    self:ParkBlizzard()
    local name, displayName, icon, startMS, endMS = ReadCast(channel or empower)
    if not name or not PlainNumber(startMS) or not PlainNumber(endMS) or endMS <= startMS then return end

    local wasActive = self.active and true or false
    self.startTime, self.endTime = startMS / 1000, endMS / 1000
    self.empowering = empower and true or nil
    self.channeling = channel and not empower
    self.casting = not self.channeling
    self.active, self.fadeUntil = true, nil
    self.appearUntil = not wasActive and GetTime() + .12 or nil
    self.flashUntil = nil
    if not wasActive then self.castLatency = nil end
    local duration = self.endTime - self.startTime

    local frame = self.frame
    frame:SetAlpha(wasActive and 1 or 0)
    frame.icon:SetTexture(icon or 136243)
    local target = self.targetName
    if type(target) == "string" and not issecretvalue(target) and target ~= "" and target ~= UnitName("player") then
        frame.name:SetFormattedText("%s  |cff8fa1b5→ %s|r", displayName or name, target)
    else
        frame.name:SetText(displayName or name)
    end
    frame.bar:SetMinMaxValues(0, duration)
    frame.bar:SetValue(self.channeling and duration or 0)
    MatteBarColor(frame.bar, self.channeling and CHANNEL_COLOR or CAST_COLOR)
    frame.spark:SetAlpha(.80)
    frame.spark:Show()
    frame.sweep:Show()
    frame.flash:SetAlpha(0)
    frame.timeUrgent = nil
    frame.time:SetAlpha(1)
    if frame.sparkPulse and not frame.sparkPulse:IsPlaying() then frame.sparkPulse:Play() end
    self:UpdateLatency(duration)
    frame:Show()
end

function CastBar:RefreshCast()
    if self.empowering then self:Start(false, true)
    elseif self.channeling then self:Start(true, false)
    elseif self.casting then self:Start(false, false) end
end

function CastBar:Finish(success)
    if not self.frame then return end
    self.active, self.casting, self.channeling, self.empowering = nil, nil, nil, nil
    MatteBarColor(self.frame.bar, success and COMPLETE_COLOR or FAILED_COLOR)
    local _, maximum = self.frame.bar:GetMinMaxValues()
    self.frame.bar:SetValue(maximum)
    self.frame.spark:Hide()
    self.frame.sweep:Hide()
    if self.frame.sparkPulse then self.frame.sparkPulse:Stop() end
    self.frame.time:SetAlpha(1)
    self.frame.latency:Hide()
    self.frame.latencyText:Hide()
    local now = GetTime()
    self.fadeDuration = success and .72 or .90
    self.fadeUntil = now + self.fadeDuration
    self.flashUntil = success and now + .20 or nil
    if success then self.frame.flash:SetAlpha(.48) end
end

function CastBar:OnUpdate()
    local frame = self.frame
    if self.flashUntil then
        local flashLeft = self.flashUntil - GetTime()
        if flashLeft <= 0 then
            self.flashUntil = nil
            frame.flash:SetAlpha(0)
        else
            frame.flash:SetAlpha(.48 * flashLeft / .20)
        end
    end
    if self.active and self.startTime and self.endTime then
        local now = GetTime()
        if self.appearUntil then
            local appearLeft = self.appearUntil - now
            if appearLeft <= 0 then
                self.appearUntil = nil
                frame:SetAlpha(1)
            else
                frame:SetAlpha(1 - appearLeft / .12)
            end
        end
        local duration = self.endTime - self.startTime
        local elapsed = math.max(0, math.min(duration, now - self.startTime))
        local remaining = math.max(0, self.endTime - now)
        local value = self.channeling and remaining or elapsed
        frame.bar:SetValue(value)
        UpdateTimeDisplay(frame, remaining)
        frame.spark:ClearAllPoints()
        frame.spark:SetPoint("CENTER", frame.bar, "LEFT", frame.bar:GetWidth() * (value / duration), 0)
        frame.sweep:ClearAllPoints()
        frame.sweep:SetPoint("RIGHT", frame.spark, "CENTER", 0, 0)
        if now >= self.endTime then self:Finish(true) end
    elseif self.fadeUntil then
        local left = self.fadeUntil - GetTime()
        if left <= 0 then
            self.fadeUntil = nil
            if not Settings().unlocked then frame:Hide() end
            frame:SetAlpha(1)
        else
            frame:SetAlpha(math.min(1, left / (self.fadeDuration or .72)))
        end
    elseif not Settings().unlocked then
        frame:Hide()
    end
end

function CastBar:OnEvent(event, unit, arg2)
    if event == "ADDON_LOADED" then
        if unit == "Quartz" then self:ParkBlizzard() end
        return
    end
    if event == "UNIT_SPELLCAST_SENT" then
        if UnitMatches(unit) then self.sentAt, self.targetName = GetTime(), arg2 end
        return
    end
    if unit and not UnitMatches(unit) then return end
    if event == "UNIT_SPELLCAST_START" then self:Start(false, false)
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then self:Start(true, false)
    elseif event == "UNIT_SPELLCAST_EMPOWER_START" then self:Start(false, true)
    elseif event == "UNIT_SPELLCAST_DELAYED" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE"
        or event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then self:RefreshCast()
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then self:Finish(false)
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP"
        or event == "UNIT_SPELLCAST_EMPOWER_STOP" then self:Finish(true)
    end
end

function CastBar:SetUnlocked(unlocked)
    local settings = Settings()
    settings.unlocked = unlocked and true or false
    local frame = self.frame
    frame:EnableMouse(settings.unlocked)
    if settings.unlocked then
        self.active, self.fadeUntil = nil, nil
        frame:SetAlpha(1)
        frame.icon:SetTexture("Interface\\Icons\\Spell_Holy_MagicalSentry")
        frame.name:SetText(L("Перетащи кастбар"))
        frame.time:SetText("1.5")
        frame.time:SetTextColor(1, .72, .12, 1)
        frame.bar:SetMinMaxValues(0, 1); frame.bar:SetValue(.72)
        MatteBarColor(frame.bar, CAST_COLOR)
        frame.spark:Hide(); frame.sweep:Hide(); frame.flash:SetAlpha(0)
        if frame.sparkPulse then frame.sparkPulse:Stop() end
        frame.latency:Hide()
        frame.latencyText:Hide()
        frame:Show()
    elseif not self.active then frame:Hide() end
end

function CastBar:ParkBlizzard()
    self.enabled = true
    self.hider = self.hider or CreateFrame("Frame", nil, UIParent)
    self.hider:Hide()
    self.parkedBars = self.parkedBars or UI.WeakKeys()

    local seen = {}
    for _, bar in ipairs({
        _G.PlayerCastingBarFrame,
        _G.CastingBarFrame,
        _G.Quartz3CastBarPlayer,
    }) do
        if bar and bar ~= self.frame and not seen[bar] then
            seen[bar] = true
            if not self.parkedBars[bar] then
                self.parkedBars[bar] = { parent = bar:GetParent() or UIParent }
            end
            if not bar.__mbCustomCastBarHook then
                bar.__mbCustomCastBarHook = true
                bar:HookScript("OnShow", function(owner)
                    if CastBar.enabled and MythicBoostDB and MythicBoostDB.castBar
                        and MythicBoostDB.castBar.enabled ~= false then
                        owner:Hide()
                    end
                end)
            end
            bar:SetParent(self.hider)
            bar:Hide()
        end
    end
end

function CastBar:RestoreBlizzard()
    self.enabled = false
    for bar, state in pairs(self.parkedBars or {}) do
        if bar and state.parent then bar:SetParent(state.parent) end
    end
    if self.parkedBars then wipe(self.parkedBars) end
end

function CastBar:Create()
    if self.frame then return end
    local frame = CreateFrame("Frame", "MythicBoostCastBar", UIParent, "BackdropTemplate")
    frame:SetSize(380, 32)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    ApplyBackdrop(frame)

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetPoint("TOPLEFT", 3, -3)
    frame.icon:SetPoint("BOTTOMLEFT", 3, 3)
    frame.icon:SetWidth(26)
    frame.icon:SetTexCoord(.07, .93, .07, .93)

    frame.timePanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.timePanel:SetPoint("TOPRIGHT", -3, -3)
    frame.timePanel:SetPoint("BOTTOMRIGHT", -3, 3)
    frame.timePanel:SetWidth(TIME_PANEL_WIDTH)
    frame.timePanel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    frame.timePanel:SetBackdropColor(0, 0, 0, 0)
    frame.timePanel:SetFrameLevel(frame:GetFrameLevel() + 6)
    frame.timePanel.scrim = frame.timePanel:CreateTexture(nil, "BACKGROUND", nil, 0)
    frame.timePanel.scrim:SetAllPoints()
    frame.timePanel.scrim:SetColorTexture(1, 1, 1, 1)
    frame.timePanel.scrim:SetGradient("HORIZONTAL",
        CreateColor(.004, .006, .010, .08),
        CreateColor(.004, .006, .010, .76))
    frame.timePanel.danger = frame.timePanel:CreateTexture(nil, "BACKGROUND", nil, 1)
    frame.timePanel.danger:SetPoint("BOTTOMLEFT", 0, 0)
    frame.timePanel.danger:SetPoint("BOTTOMRIGHT", 0, 0)
    frame.timePanel.danger:SetHeight(10)
    frame.timePanel.danger:SetColorTexture(1, 1, 1, 1)
    frame.timePanel.danger:SetGradient("VERTICAL",
        CreateColor(.30, .015, .010, .72),
        CreateColor(.08, .005, .004, .08))
    frame.timePanel.divider = frame.timePanel:CreateTexture(nil, "OVERLAY")
    frame.timePanel.divider:SetPoint("TOPLEFT", 0, 0)
    frame.timePanel.divider:SetPoint("BOTTOMLEFT", 0, 0)
    frame.timePanel.divider:SetWidth(1)
    frame.timePanel.divider:SetColorTexture(.62, .10, .06, 0)

    frame.bar = CreateFrame("StatusBar", nil, frame)
    frame.bar:SetPoint("TOPLEFT", 32, -3)
    frame.bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
    frame.bar:SetStatusBarTexture(XPERL_BAR)
    frame.bar:SetClipsChildren(true)
    frame.bar.background = frame.bar:CreateTexture(nil, "BACKGROUND")
    frame.bar.background:SetAllPoints()
    frame.bar.background:SetColorTexture(.008, .012, .018, .94)
    frame.bar.depth = frame.bar:CreateTexture(nil, "OVERLAY", nil, -8)
    frame.bar.depth:SetAllPoints()
    frame.bar.depth:SetColorTexture(0, 0, 0, 1)
    frame.bar.depth:SetGradient("VERTICAL",
        CreateColor(0, 0, 0, .34),
        CreateColor(0, 0, 0, .02))
    frame.bar.gloss = frame.bar:CreateTexture(nil, "OVERLAY", nil, -7)
    frame.bar.gloss:SetPoint("TOPLEFT", 0, 0)
    frame.bar.gloss:SetPoint("TOPRIGHT", 0, 0)
    frame.bar.gloss:SetHeight(10)
    frame.bar.gloss:SetColorTexture(1, 1, 1, 1)
    frame.bar.gloss:SetBlendMode("ADD")
    frame.bar.gloss:SetGradient("VERTICAL",
        CreateColor(1, 1, 1, 0),
        CreateColor(.86, .94, 1, .25))

    frame.barBorder = CreateFrame("Frame", nil, frame.bar, "BackdropTemplate")
    frame.barBorder:SetAllPoints()
    frame.barBorder:SetFrameLevel(frame.bar:GetFrameLevel() + 3)
    frame.barBorder:EnableMouse(false)
    frame.barBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    frame.barBorder:SetBackdropBorderColor(.28, .34, .40, .90)

    frame.latency = frame.bar:CreateTexture(nil, "OVERLAY", nil, 1)
    frame.latency:SetColorTexture(1, .05, .02, .48)
    frame.latency:Hide()
    frame.spark = frame.bar:CreateTexture(nil, "OVERLAY", nil, 2)
    frame.spark:SetTexture(SPARK)
    frame.spark:SetBlendMode("ADD")
    frame.spark:SetSize(16, 38)
    frame.spark:SetVertexColor(1, .94, .70, .90)
    frame.spark:SetAlpha(.80)
    frame.sparkPulse = frame.spark:CreateAnimationGroup()
    frame.sparkPulse:SetLooping("REPEAT")
    local pulseUp = frame.sparkPulse:CreateAnimation("Alpha")
    pulseUp:SetFromAlpha(.38); pulseUp:SetToAlpha(1); pulseUp:SetDuration(.34); pulseUp:SetOrder(1)
    pulseUp:SetSmoothing("IN_OUT")
    local pulseDown = frame.sparkPulse:CreateAnimation("Alpha")
    pulseDown:SetFromAlpha(1); pulseDown:SetToAlpha(.38); pulseDown:SetDuration(.34); pulseDown:SetOrder(2)
    pulseDown:SetSmoothing("IN_OUT")

    frame.sweep = frame.bar:CreateTexture(nil, "OVERLAY", nil, 1)
    frame.sweep:SetSize(44, 24)
    frame.sweep:SetColorTexture(1, 1, 1, 1)
    frame.sweep:SetBlendMode("ADD")
    frame.sweep:SetGradient("HORIZONTAL",
        CreateColor(1, .48, .08, 0),
        CreateColor(1, .92, .62, .24))
    frame.sweep:Hide()

    frame.flash = frame.bar:CreateTexture(nil, "OVERLAY", nil, 2)
    frame.flash:SetAllPoints()
    frame.flash:SetColorTexture(1, 1, 1, 1)
    frame.flash:SetBlendMode("ADD")
    frame.flash:SetAlpha(0)

    frame.name = UI.Text(frame.bar, "GameFontHighlight", "")
    frame.name:SetPoint("LEFT", 5, 0)
    frame.name:SetPoint("RIGHT", frame.bar, "RIGHT", -TIME_PANEL_WIDTH - 6, 0)
    frame.name:SetJustifyH("LEFT")
    frame.name:SetWordWrap(false)
    local nameFont = frame.name:GetFont()
    if nameFont then frame.name:SetFont(nameFont, 12, "OUTLINE") end
    frame.time = UI.Text(frame.timePanel, "GameFontHighlightSmall", "")
    frame.time:SetPoint("CENTER", 0, 0)
    frame.time:SetWidth(TIME_PANEL_WIDTH - 8)
    frame.time:SetJustifyH("CENTER")
    local timeFont = frame.time:GetFont()
    frame.timeFont = timeFont
    if timeFont then frame.time:SetFont(timeFont, 14, "OUTLINE") end
    frame.latencyText = UI.Text(frame.timePanel, "GameFontNormalSmall", "")
    frame.latencyText:SetPoint("BOTTOMRIGHT", -5, 3)
    frame.latencyText:SetWidth(TIME_PANEL_WIDTH - 10)
    frame.latencyText:SetJustifyH("RIGHT")
    local latencyFont = frame.latencyText:GetFont()
    if latencyFont then frame.latencyText:SetFont(latencyFont, 9, "OUTLINE") end
    frame.latencyText:SetTextColor(1, .28, .20, 1)
    frame.latencyText:Hide()

    frame:SetScript("OnUpdate", function() CastBar:OnUpdate() end)
    frame:SetScript("OnDragStart", function(self) if Settings().unlocked then self:StartMoving() end end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); CastBar:SavePosition() end)
    frame:Hide()
    self.frame = frame
    self:RestorePosition()
end

function CastBar:Enable()
    if Settings().enabled == false then self:Disable(); return end
    self:ParkBlizzard()
    self.events = self.events or CreateFrame("Frame")
    self.events:SetScript("OnEvent", function(_, event, ...) self:OnEvent(event, ...) end)
    for _, event in ipairs({
        "ADDON_LOADED",
        "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
        "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
        "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
        "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_UPDATE", "UNIT_SPELLCAST_EMPOWER_STOP",
    }) do pcall(self.events.RegisterEvent, self.events, event) end
    self:SetUnlocked(Settings().unlocked)
end

function CastBar:Disable()
    if self.events then self.events:UnregisterAllEvents() end
    self.active, self.fadeUntil = nil, nil
    if self.frame then self.frame:Hide() end
    self:RestoreBlizzard()
end

function CastBar:Destroy() self:Disable() end

JP.CastBar = CastBar
JP:RegisterModule("CastBar", CastBar)
