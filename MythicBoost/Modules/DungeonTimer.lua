local _, JP = ...
local UI, L, C = JP.UI, JP.L, JP.UI.colors
local Timer = {}
local MAX_BOSSES = 8
local WIDTH = 300
local CLOCK_HEIGHT = 64
local CONTENT_TOP = 32 + CLOCK_HEIGHT + 6
local THRESHOLD_FRACTIONS = {.6, .8}
local EXPIRED_FILL = {.46, .075, .09, 1}
local EXPIRED_TEXT = {1, .52, .48, 1}
local MARKER_COLOR = {.72, .80, .84, 1}
local DEVOURING_RIFT = 440313
local BATTLE_RES = 20484 -- shared encounter/M+ charges, also used by BigWigs BattleRes
local PARTY_UNITS = {"player", "party1", "party2", "party3", "party4"}
local function Font(text, size, flags)
    local face = text:GetFont()
    if face then text:SetFont(face, size, flags or "") end
end
local function Settings() return JP.Settings("dungeonTimer", {enabled=true, affix=true}) end
local function Clock(value)
    value = math.max(0, math.floor(JP.SafeNumber(value) or 0))
    return ("%d:%02d"):format(math.floor(value / 60), value % 60)
end
Timer.Clock = Clock

function Timer.BossName(description, journalName)
    local name = JP.SafeString(journalName)
    if name and name ~= "" then return name end
    name = JP.SafeString(description)
    if not name then return description end -- native text sink handles restricted strings
    return (name:gsub("^Победите%s+", ""):gsub("^Defeat%s+", ""))
end

-- World timer ids are not guaranteed to be 1 (e.g. after an instance change).
-- The challenge world timer already includes the death penalty.
function Timer:ReadElapsed()
    if self.finished then return self.elapsed end
    if type(GetWorldElapsedTimers) ~= "function" or type(GetWorldElapsedTime) ~= "function" then return nil end
    local ids = {GetWorldElapsedTimers()}
    for i = 1, math.min(#ids, 8) do
        local id = JP.SafeNumber(ids[i])
        if id then
            local _, elapsed, kind = GetWorldElapsedTime(id)
            if JP.SafeNumber(kind) == Enum.WorldElapsedTimerTypes.ChallengeMode then
                return JP.SafeNumber(elapsed)
            end
        end
    end
end

function Timer:SyncWidth()
    if not self.frame then return end
    local width = Minimap and JP.SafeNumber(Minimap:GetWidth())
    local mapScale = Minimap and Minimap.GetEffectiveScale and JP.SafeNumber(Minimap:GetEffectiveScale()) or 1
    local ownScale = self.frame.GetEffectiveScale and JP.SafeNumber(self.frame:GetEffectiveScale()) or 1
    width = width and width > 0 and ownScale and ownScale > 0
        and width * (mapScale or 1) / ownScale or WIDTH
    if self.layoutWidth == width then return end
    self.layoutWidth = width
    self.frame:SetWidth(width)
    for i, fraction in ipairs(THRESHOLD_FRACTIONS) do
        local marker, shadow = self.thresholdMarkers[i], self.thresholdShadows[i]
        marker:ClearAllPoints(); marker:SetPoint("TOPLEFT", self.timeBar, "TOPLEFT", (width-2)*fraction-1, -25)
        shadow:ClearAllPoints(); shadow:SetPoint("TOPLEFT", self.timeBar, "TOPLEFT", (width-2)*fraction-2, -25)
        self.thresholds[i]:ClearAllPoints()
        self.thresholds[i]:SetPoint("BOTTOM", self.timeBar, "BOTTOMLEFT", (width-2)*(i==1 and .32 or .77), 4)
    end
    for _, row in ipairs(self.rows) do row.name:SetWidth(math.max(40, width-82)) end
end

function Timer:Layout()
    if not self.frame then return end
    self:SyncWidth()
    local s, f = Settings(), self.frame
    f:ClearAllPoints()
    if s.position then
        local p = s.position
        f:SetPoint(p.point, UIParent, p.relativePoint, p.x, p.y)
    else
        local anchor = JP.MinimalUI and JP.MinimalUI.microMenuAnchor
        if not anchor or not anchor:IsShown() then anchor = Minimap or UIParent end
        f:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -6)
    end
    f:EnableMouse(self.unlocked == true or self.preview == true)
end

function Timer:SyncTracker()
    if InCombatLockdown() then self.trackerPending = true; return end
    self.trackerPending = nil
    local tracker = _G.ObjectiveTrackerFrame
    local hide = self.running and self.active and self.frame and self.frame:IsShown()
        and not self.preview and Settings().enabled ~= false
    if tracker and hide then
        if not self.trackerParent then
            self.trackerParent = tracker:GetParent()
            self.trackerIgnoreManager = tracker.ignoreFramePositionManager
        end
        -- ManagedFrameMixin.OnShow reparents default-position trackers.
        -- Opt out before hiding so it cannot reattach the tracker on Show.
        tracker.ignoreFramePositionManager = true
        local manager = tracker.layoutParent
        if manager and manager.RemoveManagedFrame then manager:RemoveManagedFrame(tracker) end
        if tracker:GetParent() ~= self.trackerHider then tracker:SetParent(self.trackerHider) end
    elseif tracker and not hide and self.trackerParent then
        tracker.ignoreFramePositionManager = self.trackerIgnoreManager
        tracker:SetParent(self.trackerParent)
        local manager = tracker.layoutParent
        if manager and manager.AddManagedFrame then manager:AddManagedFrame(tracker) end
        self.trackerParent, self.trackerIgnoreManager = nil, nil
    end
    -- No native Show/Update hooks, no protected changes during combat.
    if JP.MinimalUI then JP.MinimalUI:StyleObjectiveTracker(MythicBoostDB and MythicBoostDB.minimalUI == true) end
    if not self.running and self.events then self.events:UnregisterAllEvents() end
end

function Timer:ReadAffixes(ids)
    self.affixNames = {}
    for i = 1, math.min(type(ids) == "table" and #ids or 0, 8) do
        local id = JP.SafeNumber(ids[i])
        if id and C_ChallengeMode and C_ChallengeMode.GetAffixInfo then
            local name = JP.SafeString(C_ChallengeMode.GetAffixInfo(id))
            if name then self.affixNames[#self.affixNames + 1] = name end
        end
    end
end

-- A debuff spell is not named after the affix. Query the known aura, without
-- searching restricted names or assuming a TWW spawn schedule in Midnight.
-- References: Blizzard UnitAuraDocumentation/GetUnitAuraBySpellID and the
-- Devouring Rift spell (440313). Unknown/secret values are never compared.
function Timer:ReadDevourAura()
    local api = C_UnitAuras
    if not api or not api.GetUnitAuraBySpellID or not api.GetAuraDuration then return end
    local firstDuration
    for _, unit in ipairs(PARTY_UNITS) do
        local ok, aura = pcall(api.GetUnitAuraBySpellID, unit, DEVOURING_RIFT)
        aura = ok and JP.SafeTable(aura) or nil
        local id = aura and JP.SafeNumber(aura.auraInstanceID)
        if id then
            local success, duration = pcall(api.GetAuraDuration, unit, id)
            if success and type(duration) ~= "nil" then firstDuration = firstDuration or duration end
            local expires, length = JP.SafeNumber(aura.expirationTime), JP.SafeNumber(aura.duration)
            local start = expires and length and expires-length
            -- Only complete public timestamps calibrate the next occurrence.
            if start and (not self.devourWave or start-self.devourWave > 30) then
                local interval = self.devourWave and start-self.devourWave
                self.devourInterval = interval and interval >= 45 and interval <= 180 and interval or nil
                self.devourWave = start
                self.devourNext = self.devourInterval and start+self.devourInterval or nil
            end
        end
    end
    return firstDuration
end

-- Only a positively identified PUBLIC timeline event is an affix timer.
-- Restricted spell ids/names are not keys, and an arbitrary next boss ability
-- is never relabelled as an affix. No old 60/75/90-second schedule is invented.
function Timer:IsAffixEvent(info)
    if not JP.SafeTable(info) then return false end
    if JP.SafeNumber(info.spellID) == DEVOURING_RIFT then return true end
    local name = JP.SafeString(info.spellName)
    if not name then return false end
    for _, affixName in ipairs(self.affixNames or {}) do
        if name == affixName or name:find(affixName, 1, true) then return true end
    end
    return false
end

function Timer:RefreshAffix(removedID)
    self.affixEventID, self.affixDuration, self.affixEstimate = nil, nil, nil
    if not self.frame then return end
    if not self.active or Settings().affix == false or self.finished then self:LayoutRows(); return end
    local auraDuration = self:ReadDevourAura()
    if auraDuration then
        self.affixDuration = auraDuration
        self.affix:SetTimerDuration(auraDuration, Enum.StatusBarInterpolation.Immediate,
            Enum.StatusBarTimerDirection.RemainingTime)
        self.affix.left:SetText(L("Снять аффикс"))
        self.affix:SetStatusBarColor(.64, .24, .09, 1)
        self:LayoutRows(); return
    end
    self.affix:SetStatusBarColor(.30, .20, .46, 1)
    local api = C_EncounterTimeline
    if api and api.GetSortedEventList and api.GetEventInfo and api.GetEventTimer then
        local ids = api.GetSortedEventList(40, nil, true, true)
        for i = 1, math.min(type(ids) == "table" and #ids or 0, 40) do
            local id = JP.SafeNumber(ids[i])
            if id and id ~= removedID then
                local info = api.GetEventInfo(id)
                if self:IsAffixEvent(info) then
                    local duration = api.GetEventTimer(id)
                    if type(duration) ~= "nil" then
                        self.affixEventID, self.affixDuration = id, duration
                        self.affix:SetTimerDuration(duration, Enum.StatusBarInterpolation.Immediate,
                            Enum.StatusBarTimerDirection.RemainingTime)
                        self.affix.left:SetFormattedText(JP.SafeOptionalBoolean(info.isApproximate) == false
                            and "%s" or "~ %s", info.spellName)
                        self:LayoutRows()
                        return
                    end
                end
            end
        end
    end
    if self.devourNext and self.devourNext > GetTime() then
        self.affixEstimate = true
        self.affix:SetMinMaxValues(0, self.devourInterval)
        self.affix:SetValue(self.devourNext-GetTime())
        self.affix.left:SetText(L("~ Следующий разлом"))
        self.affix.right:SetFormattedText("%.1f", self.devourNext-GetTime())
        self:LayoutRows(); return
    end
    self.affix:SetMinMaxValues(0, 1); self.affix:SetValue(0)
    self.affix.left:SetText(""); self.affix.right:SetText("")
    self:LayoutRows()
end

function Timer:RefreshCriteria(initial)
    if not self.active or self.finished or self.preview or not C_Scenario or not C_ScenarioInfo then return end
    local count = JP.SafeNumber(select(3, C_Scenario.GetStepInfo())) or 0
    -- Scenario criteria may disappear BEFORE CHALLENGE_MODE_COMPLETED arrives.
    -- Preserve the last rendered snapshot instead of replacing it with a dash.
    if count == 0 then return end
    local rowIndex = 0
    for index = 1, math.min(count, MAX_BOSSES + 4) do
        local info = JP.SafeTable(C_ScenarioInfo.GetCriteriaInfo(index))
        if info then
            if JP.SafeBoolean(info.isWeightedProgress) then
                local total = JP.SafeNumber(info.totalQuantity)
                local quantity = JP.SafeString(info.quantityString)
                local current = quantity and tonumber((quantity:gsub("%%", "")))
                if current and total and total > 0 then
                    self.forcesTotal = total
                    self.forces:SetMinMaxValues(0, total); self.forces:SetValue(current)
                    self.forces.left:SetText(("%.2f%%"):format(current / total * 100))
                    self.forces.right:SetText(("%d / %d"):format(current, total))
                end
            elseif rowIndex < MAX_BOSSES then
                rowIndex = rowIndex + 1
                local row = self.rows[rowIndex]
                local key = JP.SafeNumber(info.criteriaID) or index
                row.criteriaKey = key
                local complete = JP.SafeBoolean(info.completed)
                if complete and not self.completed[key] and not self.splits[key] then
                    -- Do not invent a kill time when loading into a finished
                    -- step. Live transitions are timestamped once per run.
                    if not initial then self.splits[key] = self:ReadElapsed() end
                end
                self.completed[key] = complete
                local journalName
                if self.journalID and EJ_GetEncounterInfoByIndex then journalName = EJ_GetEncounterInfoByIndex(rowIndex, self.journalID) end
                row.name:SetText(Timer.BossName(info.description, journalName))
                row.name:SetTextColor(UI.Unpack(complete and C.green or C.text))
                row.time:SetText(self.splits[key] and Clock(self.splits[key]) or (complete and "OK" or "—"))
                row:Show()
            end
        end
    end
    if rowIndex > 0 then
        for i = rowIndex + 1, MAX_BOSSES do self.rows[i]:Hide() end
        self.rowCount = rowIndex
    end
    self:LayoutRows()
end

function Timer:LayoutRows()
    self.bres:ClearAllPoints(); self.bres:SetPoint("TOPLEFT", 7, -CONTENT_TOP); self.bres:SetPoint("TOPRIGHT", -7, -CONTENT_TOP)
    local showRes = not self.finished and (self.preview or self.bresKnown == true)
    self.bres:SetShown(showRes)
    local y = CONTENT_TOP + (showRes and 31 or 0)
    for i = 1, self.rowCount or 0 do
        local row = self.rows[i]
        local height = math.max(27, math.min(42, row.name:GetStringHeight() + 10))
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", 8, -y); row:SetPoint("TOPRIGHT", -8, -y)
        row:SetHeight(height); y = y + height
    end
    self.forces:ClearAllPoints(); self.forces:SetPoint("TOPLEFT", 1, -y)
    self.forces:SetPoint("TOPRIGHT", -1, -y)
    self.affix:ClearAllPoints(); self.affix:SetPoint("TOPLEFT", self.forces, "BOTTOMLEFT", 0, -1)
    self.affix:SetPoint("TOPRIGHT", self.forces, "BOTTOMRIGHT", 0, -1)
    local showAffix = Settings().affix ~= false and not self.finished
        and (self.preview or self.affixDuration ~= nil or self.affixEstimate == true)
    self.affix:SetShown(showAffix)
    self.frame:SetHeight(y + (showAffix and 47 or 24))
    self:SyncTracker()
end

function Timer:StyleClock(elapsed, limit)
    local known = elapsed ~= nil and limit ~= nil and limit > 0
    local expired = known and elapsed >= limit
    self.timeBar:SetStatusBarColor(UI.Unpack(expired and EXPIRED_FILL or C.accentDim))
    self.timeBar.left:SetTextColor(UI.Unpack(expired and EXPIRED_TEXT or C.text))
    for i, fraction in ipairs(THRESHOLD_FRACTIONS) do
        local missed = known and elapsed >= limit * fraction
        self.thresholds[i]:SetTextColor(UI.Unpack(missed and EXPIRED_TEXT or C.muted))
        self.thresholdMarkers[i]:SetColorTexture(UI.Unpack(missed and EXPIRED_TEXT or MARKER_COLOR))
    end
end

function Timer:UpdateRemaining(elapsed, limit)
    local known = elapsed ~= nil and limit ~= nil and limit > 0
    local remaining = known and (limit - elapsed) or nil
    local expired = remaining ~= nil and remaining <= 0
    self.remainingLabel:SetText(expired and L("Сверх времени:") or
        (self.finished and L("Запас времени:") or L("До конца:")))
    -- Count down with ceil: a fraction of the final second is still time left.
    -- ReadElapsed already includes death penalties; never add them a second time.
    self.remaining:SetText(remaining and Clock(expired and -remaining or math.ceil(remaining)) or "—")
    self.remaining:SetTextColor(UI.Unpack(expired and EXPIRED_TEXT or
        (remaining and remaining <= 300 and not self.finished and C.amber or C.green)))
    if not known then self.remaining:SetTextColor(UI.Unpack(C.muted)) end
end

function Timer:RefreshBattleRes()
    local wasKnown = self.bresKnown
    self.bresKnown, self.bresEnd, self.bresStart = false, nil, nil
    self.bres.right:SetText(""); self.bres.right:SetAlpha(1)
    self.bres:SetMinMaxValues(0, 1); self.bres:SetValue(0)
    if self.active and not self.finished and C_Spell and C_Spell.GetSpellCharges then
        local ok, info = pcall(C_Spell.GetSpellCharges, BATTLE_RES)
        info = ok and JP.SafeTable(info)
        if info and type(info.currentCharges) ~= "nil" then
            self.bresKnown = true
            -- A restricted number can be rendered, never compared or formatted by Lua.
            self.bres.left:SetFormattedText("BR  %d", info.currentCharges)
            local charges = JP.SafeNumber(info.currentCharges)
            self.bres.left:SetTextColor(UI.Unpack(charges == 0 and EXPIRED_TEXT or C.green))
            -- Read both count AND recharge from the shared charges table.
            -- GetSpellChargeDuration may describe the player's spell (zero
            -- outside its own recharge) rather than the shared encounter pool.
            local start, duration = JP.SafeNumber(info.cooldownStartTime), JP.SafeNumber(info.cooldownDuration)
            local maxCharges = JP.SafeNumber(info.maxCharges)
            if charges and maxCharges and charges >= maxCharges then
                self.bres.right:SetAlpha(0)
            elseif start and duration and duration > 0 then
                self.bresStart, self.bresEnd = start, start+duration
                self.bres:SetMinMaxValues(0, duration)
            else
                self.bres.right:SetText("—") -- do not invent a time from a personal cooldown
            end
        end
    end
    if wasKnown ~= self.bresKnown then self:LayoutRows() end
end

function Timer:UpdateClock()
    if self.preview then return end
    self.elapsed = self:ReadElapsed()
    local elapsed, limit = self.elapsed, self.limit
    self.timeBar.left:SetText(elapsed and (Clock(elapsed) .. " / " .. Clock(limit)) or L("Ожидание старта"))
    self.timeBar:SetMinMaxValues(0, math.max(1, limit or 1)); self.timeBar:SetValue(elapsed or 0)
    self:StyleClock(elapsed, limit)
    self:UpdateRemaining(elapsed, limit)
    if elapsed and limit and limit > 0 then
        for i, fraction in ipairs(THRESHOLD_FRACTIONS) do
            local remaining = limit * fraction - elapsed
            self.thresholds[i]:SetText(("+%d  %s%s"):format(4-i, remaining < 0 and "-" or "", Clock(math.abs(remaining))))
        end
    else
        for _, threshold in ipairs(self.thresholds) do threshold:SetText("") end
    end
    if self.active and not self.finished then
        local now = GetTime()
        if self.bresDirty or not self.bresScanAt or now-self.bresScanAt >= 1 then
            self.bresDirty = nil; self.bresScanAt = now; self:RefreshBattleRes()
        end
        if self.bresEnd then
            self.bres.right:SetFormattedText(L("+1 через %d с"), math.max(0, math.ceil(self.bresEnd-now)))
            self.bres:SetValue(math.max(0, math.min(now-self.bresStart, self.bresEnd-self.bresStart)))
        end
    end
    if self.affixDuration then
        local remaining = self.affixDuration:GetRemainingDuration()
        -- Formatting is an engine sink, not Lua string.format or arithmetic.
        self.affix.right:SetFormattedText("%.1f", remaining)
    end
    if self.active and not self.finished and not self.preview and Settings().affix ~= false then
        local now = GetTime()
        if self.affixDirty and (not self.affixScanAt or now-self.affixScanAt >= .5) then
            self.affixScanAt = now; self.affixDirty = nil; self:RefreshAffix()
        elseif self.affixEstimate then
            local left = math.max(0, self.devourNext-now)
            self.affix:SetValue(left); self.affix.right:SetFormattedText("%.1f", left)
            if left == 0 then self.affixEstimate = nil; self:LayoutRows() end
        end
    end
end

function Timer:RefreshDeaths()
    if self.preview then return end
    local deaths = JP.API.GetChallengeDeaths()
    self.deaths:SetText(tostring(deaths and deaths.count or 0))
    self.deathCount = deaths and deaths.count or 0
    self.deathPenalty = deaths and deaths.timeLost or 0
    self:RefreshDeathTooltip()
end

-- Record only public party identities from the dedicated UNIT_DIED event.
-- Never inspect the restricted combat log or attribute old deaths by guessing.
function Timer:CacheDeathRoster()
    self.deathRoster = {}
    if not self.active or not UnitGUID then return end
    for i = 0, 4 do
        local unit = i == 0 and "player" or "party" .. i
        if UnitExists(unit) then
            local guid = JP.SafeString(UnitGUID(unit))
            local name, realm = UnitName(unit)
            name, realm = JP.SafeString(name), JP.SafeString(realm)
            if guid and name then
                self.deathRoster[guid] = {unit=unit, name=realm and (name .. "-" .. realm) or name}
            end
        end
    end
end

function Timer:LoadDeathRun(newRun)
    local s = Settings()
    local saved = JP.SafeTable(s.deathRun)
    -- Without a stable native start time, do not reuse another run's history.
    if newRun or not self.runStart or not saved or saved.mapID ~= self.mapID
        or saved.startedAt ~= self.runStart or type(saved.players) ~= "table" then
        saved = {mapID=self.mapID, startedAt=self.runStart, players={}}
        s.deathRun = saved
    end
    self.deathRun = saved
    self:CacheDeathRoster()
end

function Timer:RecordDeath(guid)
    if not self.active or self.finished or self.preview or not self.deathRun then return end
    guid = JP.SafeString(guid)
    local member = guid and self.deathRoster and self.deathRoster[guid]
    if not member then return end
    if JP.SafeString(UnitGUID(member.unit)) ~= guid
        or not JP.SafeBoolean(UnitIsPlayer(member.unit))
        or JP.SafeOptionalBoolean(UnitIsFeignDeath(member.unit)) ~= false then return end
    local players = self.deathRun.players
    local entry = players[guid]
    if not entry then
        local count = 0
        for _ in pairs(players) do count = count + 1 end
        if count >= 20 then return end -- bounded, even after roster replacements
        entry = {name=member.name, count=0}; players[guid] = entry
    end
    entry.count = (JP.SafeNumber(entry.count) or 0) + 1
    self:RefreshDeathTooltip()
end

function Timer:ShowDeathTooltip()
    local tip = GameTooltip
    if not tip or not self.deathHover then return end
    tip:SetOwner(self.deathHover, "ANCHOR_LEFT")
    tip:SetText(L("Смерти группы"))
    tip:AddDoubleLine(L("Всего"), tostring(self.deathCount or 0), 1, 1, 1, 1, 1, 1)
    tip:AddDoubleLine(L("Потеря времени"), Clock(self.deathPenalty), .7, .7, .7, 1, .7, .3)
    local rows, tracked = {}, 0
    for _, entry in pairs(self.deathRun and self.deathRun.players or {}) do
        local name, count = JP.SafeString(entry.name), JP.SafeNumber(entry.count)
        if name and count and count > 0 then
            rows[#rows+1] = {name=name, count=count}; tracked = tracked + count
        end
    end
    table.sort(rows, function(a,b) return a.count == b.count and a.name < b.name or a.count > b.count end)
    if #rows > 0 then tip:AddLine(" ") end
    for _, entry in ipairs(rows) do tip:AddDoubleLine(entry.name, tostring(entry.count), .9, .9, .9, 1, .5, .4) end
    local unknown = math.max(0, (self.deathCount or 0) - tracked)
    if unknown > 0 then
        tip:AddLine((L("Не записано по игрокам: %d")):format(unknown), .7, .7, .7)
    elseif tracked == 0 then
        tip:AddLine(L("Смертей пока нет"), .7, .7, .7)
    end
    tip:Show()
end

function Timer:RefreshDeathTooltip()
    if GameTooltip and self.deathHover and GameTooltip:IsOwned(self.deathHover) then self:ShowDeathTooltip() end
end

function Timer:RefreshCombat()
    self:SyncTracker()
end

function Timer:Refresh(newRun)
    if not self.running or not self.frame then return end
    if self.preview then self:Preview(); return end
    if self.finished and not newRun and Settings().enabled ~= false then
        self:Layout(); self:LayoutRows(); self.frame:Show()
        self.frame:SetScript("OnUpdate", nil)
        return
    end
    local active = JP.API.GetActiveChallenge()
    if Settings().enabled == false or not active or not active.mapID or active.active ~= true then
        if Settings().enabled == false or not self.finished or newRun then
            self.active = false; self.frame:Hide(); self.frame:SetScript("OnUpdate", nil)
            self:SyncTracker()
        end
        return
    end
    local changed = newRun or self.mapID ~= active.mapID or self.runStart ~= active.startedAt
    if changed then
        self.splits = {}; self.completed = {}; self.finished = false
        self.rowCount, self.forcesTotal = 0, nil
        for _, row in ipairs(self.rows) do row:Hide(); row.criteriaKey = nil end
        self.forces.left:SetText("—"); self.forces.right:SetText(""); self.forces:SetValue(0)
        self.bresScanAt, self.bresEnd, self.bresKnown = nil, nil, false
        self.devourWave, self.devourInterval, self.devourNext = nil, nil, nil
        self.affixScanAt, self.affixEstimate = nil, nil
    end
    self.mapID, self.runStart, self.active = active.mapID, active.startedAt, true
    if changed or not self.deathRun then self:LoadDeathRun(newRun) end
    local map = JP.API.GetChallengeMap(active.mapID)
    self.journalID = map and map.instanceMapID and C_EncounterJournal and C_EncounterJournal.GetInstanceForGameMap
        and C_EncounterJournal.GetInstanceForGameMap(map.instanceMapID)
    self.limit = map and map.timeLimit or 0
    self.title:SetText(("|cffffbf26+%d|r  %s"):format(active.level or 0, map and map.name or "—"))
    self:ReadAffixes(active.affixes)
    self:RefreshCriteria(changed); self:RefreshDeaths(); self:RefreshCombat(); self:RefreshAffix()
    self:Layout(); self.frame:Show(); self:UpdateClock()
    self:SyncTracker()
    self.frame:SetScript("OnUpdate", self.tick)
end

function Timer:Finish()
    if not self.active then return end
    self.elapsed = self:ReadElapsed()
    local info = JP.API.GetChallengeCompletion()
    if info and info.mapID == self.mapID and info.duration then self.elapsed = info.duration / 1000 end
    self:RefreshCriteria(false); self:RefreshDeaths()
    -- Completion confirms every required boss and enemy forces; only the final
    -- boss can use the finish time. Missing earlier split times stay honest OKs.
    for i = 1, self.rowCount or 0 do
        local row = self.rows[i]
        row.name:SetTextColor(UI.Unpack(C.green))
        if not self.splits[row.criteriaKey] then row.time:SetText(i == self.rowCount and Clock(self.elapsed) or "OK") end
    end
    self.forces:SetMinMaxValues(0, self.forcesTotal or 100); self.forces:SetValue(self.forcesTotal or 100)
    self.forces.left:SetText("100.00%")
    self.forces.right:SetText(self.forcesTotal and ("%d / %d"):format(self.forcesTotal, self.forcesTotal) or L("Завершено"))
    self.finished = true; self.affixDuration, self.affixEstimate, self.bresEnd = nil, nil, nil
    self:UpdateClock(); self:LayoutRows(); self.frame:SetScript("OnUpdate", nil)
end

function Timer:Preview()
    if not self.frame then return end
    self.title:SetText(L("Предпросмотр") .. "  +10")
    self.deaths:SetText("2"); self.timeBar.left:SetText("06:09 / 32:00")
    self.bres.left:SetText("BR  1"); self.bres.left:SetTextColor(UI.Unpack(C.green))
    self.bres.right:SetAlpha(1); self.bres.right:SetFormattedText(L("+1 через %d с"), 87)
    self.bres:SetMinMaxValues(0, 100); self.bres:SetValue(65)
    self.timeBar:SetMinMaxValues(0, 1920); self.timeBar:SetValue(369)
    self:StyleClock(369, 1920)
    self:UpdateRemaining(369, 1920)
    self.thresholds[1]:SetText("+3  13:03"); self.thresholds[2]:SetText("+2  19:27")
    self.rowCount = 4
    for i, row in ipairs(self.rows) do
        row:SetShown(i <= 4); row.name:SetText(L("Босс") .. " " .. i); row.time:SetText(i == 1 and "03:40" or "—")
    end
    self.forces:SetMinMaxValues(0, 100); self.forces:SetValue(38.57)
    self.forces.left:SetText("38.57%"); self.forces.right:SetText("265 / 687")
    self.affix.left:SetText(L("Аффикс: предпросмотр")); self.affix.right:SetText("24.0")
    self.affix:SetMinMaxValues(0, 60); self.affix:SetValue(24)
    self:LayoutRows(); self:Layout(); self.frame:Show(); self.frame:SetScript("OnUpdate", nil)
    self:SyncTracker()
end

function Timer:SetUnlocked(value)
    self.unlocked = value == true
    -- Move a live/completed run as-is. A sample must not erase its summary.
    self.preview = self.unlocked and not self.active and not self.finished
    self:Refresh()
end

function Timer:Create()
    if self.frame then return end
    local f = UI.HUDPanel(UIParent, "MythicBoostDungeonTimer", WIDTH, 180)
    f:SetBackdrop({bgFile="Interface/Buttons/WHITE8x8",edgeFile="Interface/Buttons/WHITE8x8",edgeSize=1})
    f:SetBackdropColor(.018, .026, .034, .98); f:SetBackdropBorderColor(UI.Unpack(C.hudEdge))
    f:SetFrameStrata("MEDIUM"); self.frame = f; f:Hide()
    self.trackerHider = CreateFrame("Frame", nil, UIParent); self.trackerHider:Hide()
    self.splits, self.completed, self.rows, self.thresholds = {}, {}, {}, {}
    self.thresholdMarkers, self.thresholdShadows = {}, {}
    self.title = UI.Text(f, "GameFontNormal", "", C.text)
    self.title:SetPoint("TOPLEFT", 8, -8); self.title:SetPoint("RIGHT", f, "RIGHT", -40, 0)
    self.title:SetWordWrap(false); self.title:SetJustifyH("LEFT")
    Font(self.title, 13)
    local skull = f:CreateTexture(nil, "ARTWORK")
    skull:SetTexture("Interface/TargetingFrame/UI-RaidTargetingIcon_8")
    skull:SetSize(13, 13); skull:SetPoint("TOPRIGHT", -23, -8)
    self.deaths = UI.Text(f, "GameFontHighlightSmall", "0", C.muted)
    self.deaths:SetPoint("LEFT", skull, "RIGHT", 3, 0)
    Font(self.deaths, 12)
    self.deathHover = CreateFrame("Frame", nil, f)
    self.deathHover:SetPoint("TOPRIGHT", -4, -4); self.deathHover:SetSize(36, 22)
    self.deathHover:SetMouseClickEnabled(false); self.deathHover:SetMouseMotionEnabled(true)
    self.deathHover:SetScript("OnEnter", function() self:ShowDeathTooltip() end)
    local function HideDeathTooltip()
        if GameTooltip and GameTooltip:IsOwned(self.deathHover) then GameTooltip:Hide() end
    end
    self.deathHover:SetScript("OnLeave", HideDeathTooltip)
    self.deathHover:SetScript("OnHide", HideDeathTooltip)
    self.timeBar = UI.HUDBar(f, CLOCK_HEIGHT, C.accentDim)
    self.timeBar:SetPoint("TOPLEFT", 1, -32); self.timeBar:SetPoint("TOPRIGHT", -1, -32)
    self.remaining = UI.Text(self.timeBar, "GameFontNormalLarge", "", C.green)
    self.remaining:SetPoint("TOPRIGHT", -9, -2); self.remaining:SetWidth(88)
    self.remaining:SetJustifyH("RIGHT"); self.remaining:SetWordWrap(false)
    Font(self.remaining, 20, "OUTLINE")
    self.remainingLabel = UI.Text(self.timeBar, "GameFontHighlightSmall", L("До конца:"), C.text)
    self.remainingLabel:SetPoint("TOPLEFT", 9, -7)
    self.remainingLabel:SetPoint("TOPRIGHT", self.remaining, "TOPLEFT", -6, -5)
    self.remainingLabel:SetJustifyH("LEFT"); self.remainingLabel:SetWordWrap(false)
    Font(self.remainingLabel, 13, "OUTLINE")
    self.timeBar.left:ClearAllPoints(); self.timeBar.left:SetPoint("TOPLEFT", 9, -28)
    Font(self.timeBar.left, 13, "OUTLINE")
    local gloss = self.timeBar:CreateTexture(nil, "ARTWORK")
    gloss:SetAllPoints(); gloss:SetColorTexture(1, 1, 1, 1)
    gloss:SetGradient("VERTICAL", CreateColor(1,1,1,0), CreateColor(1,1,1,.055))
    local topLine = self.timeBar:CreateTexture(nil, "OVERLAY")
    topLine:SetColorTexture(.40, .49, .54, 1); topLine:SetHeight(1)
    topLine:SetPoint("TOPLEFT"); topLine:SetPoint("TOPRIGHT")
    local bottomLine = self.timeBar:CreateTexture(nil, "OVERLAY")
    bottomLine:SetColorTexture(.40, .49, .54, 1); bottomLine:SetHeight(1)
    bottomLine:SetPoint("BOTTOMLEFT"); bottomLine:SetPoint("BOTTOMRIGHT")
    for i, fraction in ipairs(THRESHOLD_FRACTIONS) do
        local shadow = self.timeBar:CreateTexture(nil, "OVERLAY", nil, -2)
        shadow:SetColorTexture(.015, .02, .025, 1); shadow:SetSize(4, 38)
        shadow:SetPoint("TOPLEFT", self.timeBar, "TOPLEFT", (WIDTH-2)*fraction-2, -25)
        self.thresholdShadows[i] = shadow
        local marker = self.timeBar:CreateTexture(nil, "OVERLAY", nil, -1)
        marker:SetColorTexture(UI.Unpack(MARKER_COLOR)); marker:SetSize(2, 38)
        marker:SetPoint("TOPLEFT", self.timeBar, "TOPLEFT", (WIDTH-2)*fraction-1, -25)
        self.thresholdMarkers[i] = marker
        self.thresholds[i] = UI.Text(self.timeBar, "GameFontHighlightSmall", "", C.muted)
        Font(self.thresholds[i], 12, "OUTLINE")
        self.thresholds[i]:SetPoint("BOTTOM", self.timeBar, "BOTTOMLEFT", (WIDTH-2)*(i==1 and .32 or .77), 4)
    end
    self.bres = UI.HUDBar(f, 26, {.045, .20, .16, 1})
    -- StatusBar fill is ARTWORK and grows beneath the icon. Creating the
    -- icon in the same layer lets that fill cover it as a charge recovers.
    local resIcon = self.bres:CreateTexture(nil, "OVERLAY", nil, 1)
    self.bres.icon = resIcon
    resIcon:SetTexture(C_Spell.GetSpellTexture(BATTLE_RES)); resIcon:SetSize(18, 18)
    resIcon:SetTexCoord(.08, .92, .08, .92); resIcon:SetPoint("LEFT", 5, 0)
    self.bres.left:ClearAllPoints(); self.bres.left:SetPoint("LEFT", 29, 0)
    Font(self.bres.left, 14); Font(self.bres.right, 12)
    self.bres:SetMouseClickEnabled(false); self.bres:SetMouseMotionEnabled(true)
    self.bres:SetScript("OnEnter", function(bar)
        GameTooltip:SetOwner(bar, "ANCHOR_LEFT")
        GameTooltip:AddLine(L("Боевые воскрешения группы"))
        GameTooltip:AddLine(L("Общий запас BR на ключ. Справа — секунды до следующего заряда, не личный КД способности."), .7, .8, .9, true)
        GameTooltip:Show()
    end)
    self.bres:SetScript("OnLeave", GameTooltip_Hide)
    self.bres:SetScript("OnHide", function(bar)
        if GameTooltip and GameTooltip:IsOwned(bar) then GameTooltip:Hide() end
    end)
    for i = 1, MAX_BOSSES do
        local row = CreateFrame("Frame", nil, f); row:SetHeight(21)
        row:SetPoint("TOPLEFT", 9, -78 - (i-1)*21); row:SetPoint("TOPRIGHT", -9, -78 - (i-1)*21)
        row.name = UI.Text(row, "GameFontHighlightSmall", "", C.text)
        local shade = row:CreateTexture(nil, "BACKGROUND")
        shade:SetAllPoints(); shade:SetColorTexture(.15, .21, .25, i%2==1 and .12 or .03)
        row.name:SetPoint("LEFT", 5, 0); row.name:SetWidth(WIDTH-82); Font(row.name, 12)
        row.name:SetWordWrap(true); row.name:SetMaxLines(2); row.name:SetJustifyH("LEFT")
        row.time = UI.Text(row, "GameFontHighlightSmall", "", C.muted); row.time:SetPoint("RIGHT", -4, 0); Font(row.time, 12)
        self.rows[i] = row
    end
    self.forces = UI.HUDBar(f, 23, {.055, .26, .28, 1})
    Font(self.forces.left, 12); Font(self.forces.right, 12)
    self.affix = UI.HUDBar(f, 22, {.30, .20, .46, 1})
    Font(self.affix.left, 12); Font(self.affix.right, 12)
    self.affix.left:SetPoint("RIGHT", -47, 0)
    UI.HUDMover(f, Settings, function() return self.unlocked or self.preview end)
    local elapsed = 0
    self.tick = function(_, delta)
        elapsed = elapsed + delta
        if elapsed < .2 then return end
        elapsed = 0; self:SyncWidth(); self:UpdateClock()
    end
    self.events = CreateFrame("Frame")
    self.events:SetScript("OnEvent", function(_, event, arg)
        if event == "SPELL_UPDATE_CHARGES" then self.bresDirty = true
        elseif event == "UNIT_AURA" then
            if self.active and not self.finished and not self.preview and Settings().affix ~= false then
                self.affixDirty = true
            end
        elseif event == "CHALLENGE_MODE_COMPLETED" then self:Finish()
        elseif event == "UNIT_DIED" then self:RecordDeath(arg)
        elseif event == "GROUP_ROSTER_UPDATE" then self:CacheDeathRoster()
        elseif event == "CHALLENGE_MODE_DEATH_COUNT_UPDATED" then self:RefreshDeaths()
        elseif event == "SCENARIO_CRITERIA_UPDATE" or event == "SCENARIO_UPDATE" then self:RefreshCriteria(false)
        elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then self:RefreshCombat()
        elseif event:find("ENCOUNTER_TIMELINE_", 1, true) then
            self:RefreshAffix(event == "ENCOUNTER_TIMELINE_EVENT_REMOVED" and arg or nil)
        else
            if event == "CHALLENGE_MODE_RESET" or event == "PLAYER_ENTERING_WORLD" then self.finished = false end
            self:Refresh(event == "CHALLENGE_MODE_START" or event == "CHALLENGE_MODE_RESET")
        end
    end)
end

function Timer:Enable()
    if Settings().enabled == false then self:Disable(); return end
    self:Create(); self.running = true
    self.events:RegisterUnitEvent("UNIT_AURA", "player", "party1", "party2", "party3", "party4")
    for _, event in ipairs({"PLAYER_ENTERING_WORLD", "CHALLENGE_MODE_START", "CHALLENGE_MODE_RESET",
        "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_DEATH_COUNT_UPDATED", "WORLD_STATE_TIMER_START",
        "WORLD_STATE_TIMER_STOP", "SCENARIO_CRITERIA_UPDATE", "SCENARIO_UPDATE", "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED", "UNIT_DIED", "GROUP_ROSTER_UPDATE", "SPELL_UPDATE_CHARGES"}) do self.events:RegisterEvent(event) end
    if C_EncounterTimeline then
        for _, event in ipairs({"ENCOUNTER_TIMELINE_EVENT_ADDED", "ENCOUNTER_TIMELINE_EVENT_REMOVED",
            "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED", "ENCOUNTER_TIMELINE_STATE_UPDATED"}) do self.events:RegisterEvent(event) end
    end
    self:Refresh()
end
function Timer:Disable()
    self.running = false
    self.bresEnd, self.bresScanAt, self.bresDirty = nil, nil, nil
    if self.events then self.events:UnregisterAllEvents() end
    if self.frame then self.frame:Hide(); self.frame:SetScript("OnUpdate", nil) end
    self:SyncTracker()
    if self.trackerPending and self.events then self.events:RegisterEvent("PLAYER_REGEN_ENABLED") end
end
function Timer:Destroy() self:Disable() end
JP.DungeonTimer = Timer
JP:RegisterModule("DungeonTimer", Timer)
