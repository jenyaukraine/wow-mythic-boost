local _, JP = ...
local L = JP.L
local UI = JP.UI
local C = JP.UI.colors

local CastBar = {}
local XPERL_BAR = "Interface\\TargetingFrame\\UI-StatusBar"
local SOFT_EDGE = "Interface\\AddOns\\MythicBoost\\Media\\XPerl_ThinEdge"
local SPARK = "Interface\\CastingBar\\UI-CastingBar-Spark"

local CAST_COLOR = { 1.00, .49, 0 }
local CHANNEL_COLOR = { .32, .30, 1 }
local COMPLETE_COLOR = { .12, .86, .15 }
local FAILED_COLOR = { 1, .09, 0 }
local BAR_WIDTH = 400
local TIME_TEXT_WIDTH = 82
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
    if settings.layoutRevision ~= 3 then
        local oldDefault = settings.layoutRevision == 2 and settings.point == "BOTTOM"
            and settings.x == 0 and settings.y == 250
        if type(settings.point) ~= "string" or oldDefault then
            settings.point, settings.relativePoint = "BOTTOM", "BOTTOM"
            settings.x, settings.y = 2, 161
        end
        settings.layoutRevision = 3
    end
    return settings
end

local PlainNumber = UI.UsableNumber

local function PlainToken(value)
    local kind = type(value)
    return (kind == "string" or kind == "number") and not issecretvalue(value)
end

local function MatchesActiveCast(self, castGUID, spellID)
    if not self.active then return false end
    if PlainToken(self.castGUID) then
        return PlainToken(castGUID) and self.castGUID == castGUID
    end
    if PlainNumber(self.castSpellID) then
        return PlainNumber(spellID) and self.castSpellID == spellID
    end
    return not PlainToken(castGUID) and not PlainNumber(spellID)
end

local function UnitMatches(unit)
    return unit == "player" or unit == "vehicle"
end

local function UpdateTimeDisplay(frame, elapsed, duration, channeling)
    local current = channeling and math.max(0, duration - elapsed) or elapsed
    -- Both values share the bar; no separate time box or changing font size.
    frame.time:SetFormattedText("%.1f / %.1f", current, duration)
end

local function ApplyBackdrop(frame)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = SOFT_EDGE,
        tile = false,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    -- Общие токены UI.colors вместо собственного тёмного:
    -- эта панель стоит на экране рядом с остальными.
    frame:SetBackdropColor(C.surface[1], C.surface[2], C.surface[3], .97)
    frame:SetBackdropBorderColor(.22, .24, .25, .92)
    if not frame.__mbCapsuleGradient then
        local gradient = frame:CreateTexture(nil, "ARTWORK", nil, -5)
        gradient:SetColorTexture(1, 1, 1, 1)
        gradient:SetBlendMode("ADD")
        gradient:SetPoint("TOPLEFT", 4, -4)
        gradient:SetPoint("BOTTOMRIGHT", -4, 4)
        gradient:SetGradient("VERTICAL",
            CreateColor(0, 0, 0, 0),
            CreateColor(.36, .39, .43, .16))
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
        frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 2, 161)
    end
end

function CastBar:UpdateLatency(duration)
    local frame = self.frame
    local _, _, homeMS, worldMS = GetNetStats()
    local networkMS = PlainNumber(worldMS) and math.max(0, worldMS)
        or (PlainNumber(homeMS) and math.max(0, homeMS) or nil)
    if not self.castLatency then
        self.latencyKnown = networkMS ~= nil or self.sentDelay ~= nil
        self.castLatency = math.max((networkMS or 0) / 1000, self.sentDelay or 0)
    end
    self.sentDelay = nil
    if self.latencyKnown then
        frame.latencyText:SetFormattedText("%d ms", math.floor(self.castLatency * 1000 + .5))
    else
        frame.latencyText:SetText("— ms")
    end
    local latency = math.min(duration, self.castLatency or 0)
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

function CastBar:Start(channel, empower, castGUID, eventSpellID)
    -- Only the Blizzard player bar is replaced; other addons stay untouched.
    self:ParkBlizzard()
    local name, displayName, icon, startMS, endMS, _, readSpellID = ReadCast(channel or empower)
    if not name or not PlainNumber(startMS) or not PlainNumber(endMS) or endMS <= startMS then return end

    local wasActive = self.active and true or false
    self.startTime, self.endTime = startMS / 1000, endMS / 1000
    self.empowering = empower and true or nil
    self.channeling = channel and not empower
    self.casting = not self.channeling
    self.active, self.fadeUntil = true, nil
    self.castGUID = PlainToken(castGUID) and castGUID or nil
    self.castSpellID = PlainNumber(eventSpellID) and eventSpellID
        or (PlainNumber(readSpellID) and readSpellID or nil)
    self.appearUntil = not wasActive and GetTime() + .12 or nil
    self.flashUntil = nil
    if not wasActive then self.castLatency = nil end
    local duration = self.endTime - self.startTime

    local frame = self.frame
    frame:SetAlpha(wasActive and 1 or 0)
    frame.icon:SetTexture(icon or 136243)
    local sentMatches = PlainToken(self.sentGUID) and PlainToken(self.castGUID)
        and self.sentGUID == self.castGUID
    if not sentMatches and PlainNumber(self.sentSpellID) and PlainNumber(self.castSpellID) then
        sentMatches = self.sentSpellID == self.castSpellID
    end
    local target = sentMatches and self.targetName or nil
    -- A SENT event can belong to a cancelled or previous cast. Never turn its
    -- stale timestamp into a full-bar latency zone on the next spell.
    self.sentDelay = sentMatches and PlainNumber(self.sentAt) and math.max(0, GetTime() - self.sentAt) or nil
    self.sentGUID, self.sentSpellID, self.targetName, self.sentAt = nil, nil, nil, nil
    if type(target) == "string" and not issecretvalue(target) and target ~= "" and target ~= UnitName("player") then
        frame.name:SetFormattedText("%s  |cff8fa1b5> %s|r", displayName or name, target)
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
    frame.time:SetAlpha(1)
    UpdateTimeDisplay(frame, 0, duration, self.channeling)
    if frame.sparkPulse and not frame.sparkPulse:IsPlaying() then frame.sparkPulse:Play() end
    self:UpdateLatency(duration)
    frame:Show()
end

function CastBar:RefreshCast(castGUID, spellID)
    if self.empowering then self:Start(false, true, castGUID, spellID)
    elseif self.channeling then self:Start(true, false, castGUID, spellID)
    elseif self.casting then self:Start(false, false, castGUID, spellID) end
end

function CastBar:Finish(success)
    if not self.frame or not self.active then return end
    local channeling = self.channeling
    self.active, self.casting, self.channeling, self.empowering = nil, nil, nil, nil
    self.castGUID, self.castSpellID = nil, nil
    MatteBarColor(self.frame.bar, success and COMPLETE_COLOR or FAILED_COLOR)
    local _, maximum = self.frame.bar:GetMinMaxValues()
    self.frame.bar:SetValue(maximum)
    if success then UpdateTimeDisplay(self.frame, maximum, maximum, channeling) end
    self.frame.spark:Hide()
    self.frame.sweep:Hide()
    if self.frame.sparkPulse then self.frame.sparkPulse:Stop() end
    self.frame.time:SetAlpha(1)
    self.frame.latency:Hide()
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
        UpdateTimeDisplay(frame, elapsed, duration, self.channeling)
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

function CastBar:OnEvent(event, unit, arg2, arg3, arg4)
    if event == "UNIT_SPELLCAST_SENT" then
        if UnitMatches(unit) then
            self.sentAt, self.targetName = GetTime(), arg2
            self.sentGUID = PlainToken(arg3) and arg3 or nil
            self.sentSpellID = PlainNumber(arg4) and arg4 or nil
        end
        return
    end
    if unit and not UnitMatches(unit) then return end
    if event == "UNIT_SPELLCAST_START" then self:Start(false, false, arg2, arg3)
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then self:Start(true, false, arg2, arg3)
    elseif event == "UNIT_SPELLCAST_EMPOWER_START" then self:Start(false, true, arg2, arg3)
    elseif event == "UNIT_SPELLCAST_DELAYED" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE"
        or event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
        if MatchesActiveCast(self, arg2, arg3) then self:RefreshCast(arg2, arg3) end
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
        if MatchesActiveCast(self, arg2, arg3) then self:Finish(false) end
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP"
        or event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        if MatchesActiveCast(self, arg2, arg3) then self:Finish(true) end
    end
end

function CastBar:SetUnlocked(unlocked)
    local settings = Settings()
    settings.unlocked = unlocked and true or false
    local frame = self.frame
    frame:EnableMouse(settings.unlocked)
    if settings.unlocked then
        self.active, self.fadeUntil = nil, nil
        self.castGUID, self.castSpellID = nil, nil
        frame:SetAlpha(1)
        frame.icon:SetTexture("Interface\\Icons\\Spell_Holy_MagicalSentry")
        frame.name:SetText(L("Перетащи кастбар"))
        frame.time:SetText("1.1 / 1.5")
        frame.latencyText:SetText("78 ms")
        frame.bar:SetMinMaxValues(0, 1); frame.bar:SetValue(.72)
        MatteBarColor(frame.bar, CAST_COLOR)
        frame.spark:Hide(); frame.sweep:Hide(); frame.flash:SetAlpha(0)
        if frame.sparkPulse then frame.sparkPulse:Stop() end
        frame.latency:Hide()
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
                        and MythicBoostDB.castBar.enabled ~= false
                        and not owner.__mbCastBarHideActive then
                        owner.__mbCastBarHideActive = true
                        pcall(owner.Hide, owner)
                        owner.__mbCastBarHideActive = nil
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
    frame:SetSize(BAR_WIDTH, 32)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    ApplyBackdrop(frame)

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetPoint("TOPLEFT", 4, -4)
    frame.icon:SetPoint("BOTTOMLEFT", 4, 4)
    frame.icon:SetWidth(24)
    frame.icon:SetTexCoord(.07, .93, .07, .93)

    frame.bar = CreateFrame("StatusBar", nil, frame)
    frame.bar:SetPoint("TOPLEFT", 30, -4)
    frame.bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
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
    frame.bar.gloss:SetHeight(6)
    frame.bar.gloss:SetColorTexture(1, 1, 1, 1)
    frame.bar.gloss:SetBlendMode("ADD")
    frame.bar.gloss:SetGradient("VERTICAL",
        CreateColor(1, 1, 1, 0),
            CreateColor(.86, .90, .92, .16))

    frame.latency = frame.bar:CreateTexture(nil, "OVERLAY", nil, 1)
    frame.latency:SetColorTexture(1, .05, .02, .48)
    frame.latency:Hide()
    frame.spark = frame.bar:CreateTexture(nil, "OVERLAY", nil, 2)
    frame.spark:SetTexture(SPARK)
    frame.spark:SetBlendMode("ADD")
    frame.spark:SetSize(12, 26)
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

    -- A dedicated text layer stays above the fill, latency tint and border.
    -- It has no background: the progress texture continues under both labels.
    frame.labels = CreateFrame("Frame", nil, frame.bar)
    frame.labels:SetAllPoints()
    frame.labels:SetFrameLevel(frame.bar:GetFrameLevel() + 4)
    frame.labels:EnableMouse(false)
    frame.name = UI.Text(frame.labels, "GameFontHighlight", "")
    frame.name:SetPoint("LEFT", 5, 0)
    frame.name:SetPoint("RIGHT", frame.labels, "RIGHT", -TIME_TEXT_WIDTH - 12, 0)
    frame.name:SetJustifyH("LEFT")
    frame.name:SetWordWrap(false)
    local nameFont = frame.name:GetFont()
    if nameFont then frame.name:SetFont(nameFont, 13, "") end
    frame.name:SetShadowColor(0, 0, 0, .85)
    frame.name:SetShadowOffset(1, -1)
    frame.time = UI.Text(frame.labels, "GameFontHighlightSmall", "", C.text)
    frame.time:SetPoint("TOPRIGHT", -5, -1)
    frame.time:SetWidth(TIME_TEXT_WIDTH)
    frame.time:SetHeight(14)
    frame.time:SetJustifyH("RIGHT")
    frame.time:SetWordWrap(false)
    local timeFont = frame.time:GetFont()
    if timeFont then frame.time:SetFont(timeFont, 13, "") end
    frame.time:SetShadowColor(0, 0, 0, .85)
    frame.time:SetShadowOffset(1, -1)
    frame.latencyText = UI.Text(frame.labels, "GameFontHighlightSmall", "", C.muted)
    frame.latencyText:SetPoint("BOTTOMRIGHT", -5, 0)
    frame.latencyText:SetSize(TIME_TEXT_WIDTH, 8)
    frame.latencyText:SetJustifyH("RIGHT")
    frame.latencyText:SetWordWrap(false)
    if timeFont then frame.latencyText:SetFont(timeFont, 8, "") end
    frame.latencyText:SetShadowColor(0, 0, 0, .8)
    frame.latencyText:SetShadowOffset(1, -1)

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
    self.castGUID, self.castSpellID = nil, nil
    if self.frame then self.frame:Hide() end
    self:RestoreBlizzard()
end

function CastBar:Destroy() self:Disable() end

JP.CastBar = CastBar
JP:RegisterModule("CastBar", CastBar)
