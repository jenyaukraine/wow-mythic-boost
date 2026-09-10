local _, JP = ...
local UI, L, C = JP.UI, JP.L, JP.UI.colors
local Alert = {}
local UNITS = {"party1", "party2", "party3", "party4"}
local function Settings() return JP.Settings("convenience", {warnDifferentInstance=true}) end
local function Position() return JP.Settings("instanceAlert") end
local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok and not JP.IsSecret(value) then return value end
end
local function InDungeon()
    if type(IsInInstance) ~= "function" then return false end
    local ok, inside, kind = pcall(IsInInstance)
    return ok and JP.SafeBoolean(inside) and JP.SafeString(kind) == "party"
end

function Alert:InContext()
    return self.running and Settings().warnDifferentInstance == true and not self.loading
        and InDungeon() and JP.SafeBoolean(Read(IsInGroup))
        and JP.SafeOptionalBoolean(Read(IsInRaid)) == false
end

-- Follow the public phase signal used by Blizzard's party indicator. A
-- missing map (or a different dungeon floor) must not hide that signal.
-- Map IDs and distance alone cannot identify a different dungeon copy.
function Alert:FindOtherShard()
    if InCombatLockdown() or not Enum or not Enum.PhaseReason then return nil end
    for _, unit in ipairs(UNITS) do
        local phase = JP.SafeNumber(Read(UnitPhaseReason, unit))
        local separated = phase ~= nil and (phase == Enum.PhaseReason.Sharding or phase == Enum.PhaseReason.Phasing)
        if JP.SafeBoolean(Read(UnitExists, unit)) and JP.SafeBoolean(Read(UnitIsConnected, unit))
            and JP.SafeOptionalBoolean(Read(UnitIsDeadOrGhost, unit)) == false
            and separated then
            return JP.SafeString(Read(UnitGUID, unit))
        end
    end
end

function Alert:Together()
    if JP.SafeOptionalBoolean(Read(UnitInPartyShard, "player")) ~= true then return false end
    local seen = false
    for _, unit in ipairs(UNITS) do
        local exists = JP.SafeOptionalBoolean(Read(UnitExists, unit))
        if exists == nil then return false end
        if exists then
            -- Unknown/secret phase is not the same thing as "no phase".
            local ok, phase
            if type(UnitPhaseReason) == "function" then ok, phase = pcall(UnitPhaseReason, unit) end
            if not JP.SafeBoolean(Read(UnitIsConnected, unit))
                or not JP.SafeBoolean(Read(UnitIsVisible, unit))
                or not ok or JP.IsSecret(phase) or phase ~= nil then return false end
            seen = true
        end
    end
    return seen
end

function Alert:CancelTimer()
    if self.pending then self.pending:Cancel(); self.pending = nil end
end
function Alert:Reset()
    self:CancelTimer()
    self.deadline, self.source, self.candidate, self.candidateSince = nil, nil, nil, nil
    self:Render()
end
function Alert:Schedule(delay)
    if self.pending or not self.running or not C_Timer or not C_Timer.NewTimer then return end
    local timer
    timer = C_Timer.NewTimer(delay, function()
        if self.pending ~= timer then return end
        self.pending = nil
        self:Check()
    end)
    self.pending = timer
end
function Alert:StartChecks()
    if not self.running or Settings().warnDifferentInstance ~= true then self:Reset(); return end
    self.deadline = GetTime() + 12
    self:Schedule(.5)
end
function Alert:Check()
    if not self.running or Settings().warnDifferentInstance ~= true then self:Reset(); return end
    -- Loading screens do not need a polling timer. ENTERING_WORLD resumes us.
    if self.loading then self:Render(); return end
    if not self:InContext() then
        self:Render()
        if InDungeon() and self.deadline and GetTime() < self.deadline then self:Schedule(1)
        else self:Reset() end
        return
    end
    if self.source and self:Together() then self:Reset(); return end
    local candidate = self:FindOtherShard()
    if candidate then
        if self.candidate ~= candidate then self.candidate, self.candidateSince = candidate, GetTime() end
        if GetTime() - self.candidateSince >= 2 and not self.source then self.source = "shard" end
    else
        self.candidate, self.candidateSince = nil, nil
        -- A native notification stays latched until resolution/exit. A fallback
        -- warning disappears as soon as its readable evidence is lost.
        if self.source == "shard" then self.source = nil end
    end
    self:Render()
    if self.source then self:Schedule(3)
    elseif self.deadline and GetTime() < self.deadline then self:Schedule(1)
    elseif self.candidateSince and GetTime() - self.candidateSince < 2 then self:Schedule(1)
    else self.deadline, self.candidate, self.candidateSince = nil, nil, nil end
end

function Alert:Render()
    if not self.frame then return end
    local shown = self.running and Settings().warnDifferentInstance == true
        and (self.preview or (self.source ~= nil and self:InContext()))
    self.frame:SetShown(shown == true)
    if self.title then
        self.title:SetText(self.source == "shard" and L("Группа в разных копиях или фазах") or L("Другая копия подземелья"))
        self.message:SetText(self.source == "shard"
            and L("Проверьте вход в подземелье и фазу у участников группы.")
            or L("Выйди из подземелья и зайди снова к группе."))
    end
    self.frame:EnableMouse(self.preview == true)
end
function Alert:Layout()
    local p = JP.SafeTable(Position().position)
    local points = {TOP=true, TOPLEFT=true, TOPRIGHT=true, LEFT=true, CENTER=true,
        RIGHT=true, BOTTOM=true, BOTTOMLEFT=true, BOTTOMRIGHT=true}
    local point = p and JP.SafeString(p.point)
    local relative = p and JP.SafeString(p.relativePoint)
    local x, y = p and JP.SafeNumber(p.x), p and JP.SafeNumber(p.y)
    self.frame:ClearAllPoints()
    if points[point or ""] and points[relative or ""] and x and y
        and math.abs(x) < 1000000 and math.abs(y) < 1000000 then
        self.frame:SetPoint(point, UIParent, relative, x, y)
    else self.frame:SetPoint("TOP", UIParent, "TOP", 0, -UIParent:GetHeight()*.18) end
end
function Alert:SetUnlocked(value)
    self.preview = value == true
    self:Render()
end
function Alert:Create()
    if self.frame then return end
    local f = UI.HUDPanel(UIParent, "MythicBoostInstanceAlert", 420, 72)
    self.frame = f
    f:SetFrameStrata("HIGH"); f:EnableMouse(false)
    f:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
    f:SetBackdropColor(.018, .026, .034, .98)
    f:SetBackdropBorderColor(UI.Unpack(C.hudEdge))
    local accent = f:CreateTexture(nil, "ARTWORK")
    accent:SetColorTexture(1, .68, .12, 1); accent:SetWidth(3)
    accent:SetPoint("TOPLEFT", 2, -3); accent:SetPoint("BOTTOMLEFT", 2, 3)
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface/TargetingFrame/UI-PhasingIcon")
    icon:SetTexCoord(.15625, .84375, .15625, .84375)
    icon:SetSize(30, 30); icon:SetPoint("LEFT", 14, 0)
    local title = UI.Text(f, "GameFontNormalLarge", L("Другая копия подземелья"), C.amber)
    title:SetPoint("TOPLEFT", 56, -11); title:SetPoint("RIGHT", -12, 0)
    title:SetJustifyH("LEFT"); title:SetWordWrap(false)
    local message = UI.Text(f, "GameFontHighlight", L("Выйди из подземелья и зайди снова к группе."), C.text)
    self.title, self.message = title, message
    message:SetPoint("TOPLEFT", 56, -33); message:SetPoint("RIGHT", -12, 0)
    message:SetJustifyH("LEFT"); message:SetWordWrap(true)
    self:Layout()
    UI.HUDMover(f, Position, function() return self.preview end)
    f:Hide()
    self.events = CreateFrame("Frame")
    self.events:SetScript("OnEvent", function(_, event) self:OnEvent(event) end)
end
function Alert:OnEvent(event)
    if not self.running or Settings().warnDifferentInstance ~= true then return end
    if event == "PLAYER_LEAVING_WORLD" then self.loading = true; self:Reset(); return end
    if event == "GROUP_LEFT" then self:Reset(); return end
    if event == "PLAYER_ENTERING_WORLD" then self.loading = false end
    if event == "ENTERED_DIFFERENT_INSTANCE_FROM_PARTY" then
        -- Blizzard's explicit mismatch notification is authoritative. It can
        -- arrive before the new roster/world state has finished settling.
        if self.loading or InDungeon() then self.source = "event" end
    end
    if not self.loading and not InDungeon() then self:Reset(); return end
    if self.source and self:InContext() then self:Render() end
    self:StartChecks()
end
function Alert:ApplySettings()
    if not self.events then return end
    self.events:UnregisterAllEvents(); self:Reset()
    if not self.running or Settings().warnDifferentInstance ~= true then return end
    for _, event in ipairs({"PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "GROUP_JOINED",
        "GROUP_FORMED", "GROUP_LEFT", "GROUP_ROSTER_UPDATE", "PARTY_MEMBER_ENABLE", "PARTY_MEMBER_DISABLE", "PLAYER_REGEN_ENABLED",
        "ZONE_CHANGED_NEW_AREA", "ENTERED_DIFFERENT_INSTANCE_FROM_PARTY"}) do
        self.events:RegisterEvent(event)
    end
    for _, event in ipairs({"UNIT_PHASE", "UNIT_CONNECTION", "UNIT_FLAGS", "UNIT_OTHER_PARTY_CHANGED"}) do
        self.events:RegisterUnitEvent(event, "player", "party1", "party2", "party3", "party4")
    end
    if InDungeon() then self:StartChecks() end
    self:Render()
end
function Alert:Enable()
    self:Create(); self.running = true; self.loading = false
    self:ApplySettings()
end
function Alert:Disable()
    self.running, self.preview, self.loading = false, false, false
    if self.events then self.events:UnregisterAllEvents() end
    self:Reset()
end
function Alert:Destroy() self:Disable() end
JP.InstanceAlert = Alert
JP:RegisterModule("InstanceAlert", Alert)
