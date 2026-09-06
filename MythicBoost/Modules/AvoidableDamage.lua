local _, JP = ...
local Monitor = {}
local MAX_PLAYERS, MAX_RECAPS, MAX_SESSIONS, MAX_SOURCES = 40, 512, 24, 160
local UNITS = {"player", "party1", "party2", "party3", "party4"}

-- Native Midnight meter, not an imported combat-log parser or spell database.
-- Only public snapshots enter our model. Never reset the user's damage meter,
-- change its CVar, or turn missing data into a hit counter. Sharing lives in
-- the UI and requires an explicit click; collection never sends chat.
local function Call(owner, key, ...)
    local fn = owner and owner[key]
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn, ...)
    if ok then return result end
end
local function Number(value)
    value = JP.SafeNumber(value)
    if value and value == value and value >= 0 and value < math.huge then return value end
end
local function Sources(session)
    session = JP.SafeTable(session)
    return session and JP.SafeTable(session.combatSources)
end
local function Overall(meterType)
    local types = Enum and Enum.DamageMeterSessionType
    return types and Call(C_DamageMeter, "GetCombatSessionFromType", types.Overall, meterType)
end
function Monitor:Settings() return JP.Settings("avoidableDamage", {enabled=true}) end

-- InCombatLockdown is a Lua flag, not an optional boolean: older/native
-- paths can return nil when unlocked. Unknown/secret/error still fails closed.
function Monitor:IsCombatLocked()
    if type(InCombatLockdown)~="function" then return true end
    local ok,value=pcall(InCombatLockdown)
    if not ok or JP.IsSecret(value) then return true end
    return value~=nil and value~=false
end

function Monitor:RefreshRoster()
    if not self.players then return end
    self.roster = {}
    for _, unit in ipairs(UNITS) do
        if JP.SafeBoolean(UnitExists(unit)) then
            local guid = JP.SafeString(UnitGUID(unit))
            if guid then
                local record = self.players[guid]
                if not record and self.playerCount < MAX_PLAYERS then
                    record = {guid=guid, amount=0, fatal=0, spellBaselinePending=true}
                    self.players[guid] = record; self.playerCount = self.playerCount + 1
                    if self:IsCombatLocked() then self.keySpellPartial=true end
                end
                if record then
                    record.unit=unit
                    record.name = JP.SafeString(UnitName(unit)) or record.name
                    local _, class = UnitClass(unit)
                    record.class = JP.SafeString(class) or record.class
                    self.roster[#self.roster+1] = record
                else self.partial = true end
            end
        end
    end
end

function Monitor:Begin(scope)
    self:CancelSnapshot()
    self:CancelCombatReport()
    self.lastReport, self.reportExpected = nil, false
    self.keySpells, self.keySpellCount, self.keySpellPartial = {}, 0, scope ~= "key"
    self.spellSnapshotComplete=false
    self.keyFinalized = false
    self.players, self.roster, self.recaps = {}, {}, {}
    self.recapIDs, self.recapCursor = {}, 0
    self.playerCount, self.recapCount = 0, 0
    self.partial, self.completed, self.frozen, self.resetPending = false, false, false, false
    self.scope, self.active, self.stale = scope, true, true
    self:RefreshRoster()
    self:Snapshot()
    self:UpdateKeySpells(true)
    self.reportExpected=self:IsCombatLocked() and not self.completed
    if self.reportExpected then self:CapturePullBaseline() end
    if self.stale then self.partial = true end
end

function Monitor:ReadAmounts()
    local types = Enum and Enum.DamageMeterType
    local sources = types and Sources(Overall(types.AvoidableDamageTaken))
    if not sources then return false end
    local amounts, complete = {}, true
    if #sources > MAX_SOURCES then complete = false end
    for i = 1, math.min(#sources, MAX_SOURCES) do
        local source = JP.SafeTable(sources[i])
        local guid = source and JP.SafeString(source.sourceGUID)
        local amount = source and Number(source.totalAmount)
        if guid and amount then amounts[guid] = amount else complete = false end
    end
    for _, record in ipairs(self.roster) do
        local amount = amounts[record.guid]
        -- Missing source means zero only in a completely readable snapshot.
        if amount == nil and complete then amount = 0 end
        if amount ~= nil then
            if record.last == nil then
                -- First observation establishes a baseline: no previous pulls
                -- or another group's damage can leak into this dungeon.
                record.last = self.resetPending and 0 or amount
                record.known = true
            end
            if amount >= record.last then
                record.amount = record.amount + amount - record.last
            else
                -- Unannounced reset/session change: keep confirmed damage,
                -- establish a new baseline, and disclose partial coverage.
                self.partial = true
            end
            record.last = amount
        end
    end
    self.resetPending = false
    return complete
end

function Monitor:ReadCombatReport(overall)
    if self:IsCombatLocked() then return end
    local sessions, types = Enum and Enum.DamageMeterSessionType, Enum and Enum.DamageMeterType
    if not sessions or not types then return end
    if JP.SafeOptionalBoolean(Call(C_DamageMeter, "IsDamageMeterAvailable")) ~= true then return end
    if C_CVar and JP.SafeOptionalBoolean(Call(C_CVar, "GetCVarBool", "damageMeterEnabled")) == false then return end
    local sessionType = overall and sessions.Overall or sessions.Current
    local sources = Sources(Call(C_DamageMeter, "GetCombatSessionFromType", sessionType, types.AvoidableDamageTaken))
    if not sources then return end
    local report, seen, members = {entries={}, ready={}, complete=#sources<=MAX_SOURCES}, {}, {}
    local listComplete=report.complete
    local entryLimit=overall and 512 or 128
    for _, record in ipairs(self.roster or {}) do members[record.guid]=record end
    for i=1,math.min(#sources,MAX_SOURCES) do
        local source = JP.SafeTable(sources[i])
        local guid = source and JP.SafeString(source.sourceGUID)
        local record = guid and members[guid]
        local amount = source and Number(source.totalAmount)
        if not source or not guid then listComplete=false end
        if not source or not guid or amount == nil then report.complete=false end
        if record and report.ready[guid]==nil then report.ready[guid]=amount~=nil end
        if record and amount and amount>0 and not seen[guid] then
            seen[guid]=true
            local maxHealth
            if not overall and record.unit and JP.SafeString(UnitGUID(record.unit))==guid then
                maxHealth=Number(Call(_G,"UnitHealthMax",record.unit))
                if maxHealth==0 then maxHealth=nil end
            end
            local detail = JP.SafeTable(Call(C_DamageMeter, "GetCombatSessionSourceFromType",
                sessionType, types.AvoidableDamageTaken, guid, nil))
            local spells = detail and JP.SafeTable(detail.combatSpells)
            if not spells or #spells==0 then report.complete=false; report.ready[guid]=false
            else
                if #spells>128 then report.complete=false; report.ready[guid]=false end
                local ids, accounted={}, 0
                for j=1,math.min(#spells,128) do
                    local spell=JP.SafeTable(spells[j])
                    local id=spell and Number(spell.spellID)
                    local damage=spell and Number(spell.totalAmount)
                    -- This source is already filtered by AvoidableDamageTaken.
                    -- Blizzard's source window displays all of its combatSpells;
                    -- an extra isAvoidable flag is not a second inclusion gate.
                    if not id or id==0 or damage==nil then report.complete=false; report.ready[guid]=false
                    elseif damage>0 and not ids[id] then
                        ids[id]=true
                        accounted=accounted+damage
                        if #report.entries<entryLimit then
                            report.entries[#report.entries+1]={spellID=id,amount=damage,
                                name=record.name or JP.SafeString(source.name),class=record.class,guid=guid,
                                healthRatio=maxHealth and damage/maxHealth or nil}
                        else report.complete=false; report.ready[guid]=false end
                    end
                end
                if accounted < amount then report.complete=false; report.ready[guid]=false end
            end
        end
    end
    -- A readable zero/absent source is a valid per-player boundary. A missing
    -- spell breakdown for somebody else must not suppress this player's feed.
    if listComplete then
        for guid in pairs(members) do
            if report.ready[guid]==nil then report.ready[guid]=true end
        end
    end
    table.sort(report.entries,function(a,b)
        if a.amount~=b.amount then return a.amount>b.amount end
        if a.spellID~=b.spellID then return a.spellID<b.spellID end
        return a.guid<b.guid
    end)
    return report
end

-- Track differences in the native overall spell totals, not sums of Current:
-- leaving/re-entering combat can expose the same native session more than once.
function Monitor:UpdateKeySpells(baseline)
    if not self.active or self.frozen then return end
    local report=self:ReadCombatReport(true)
    self.spellSnapshotComplete=report and report.complete==true or false
    if not report then
        self.keySpellPartial=true
        for _,player in ipairs(self.roster or {}) do player.spellSnapshotReady=false end
        return false
    end
    if not report.complete then self.keySpellPartial=true end
    for _, entry in ipairs(report.entries) do
        local key=entry.guid..":"..entry.spellID
        local record=self.keySpells[key]
        if not record and self.keySpellCount<512 then
            record={guid=entry.guid,name=entry.name,class=entry.class,spellID=entry.spellID,amount=0,last=0}
            self.keySpells[key]=record; self.keySpellCount=self.keySpellCount+1
        end
        if record then
            local player=self.players[entry.guid]
            if baseline or (player and player.spellBaselinePending) then record.last=entry.amount
            elseif entry.amount>=record.last then record.amount=record.amount+entry.amount-record.last
            else self.keySpellPartial=true end
            record.last=entry.amount
        else self.keySpellPartial=true end
    end
    for _, player in ipairs(self.roster or {}) do
        player.spellSnapshotReady=report.ready[player.guid]==true
        if player.spellSnapshotReady then player.spellBaselinePending=false end
    end
    return report.complete==true
end

function Monitor:FinishKeyReport()
    if not self.completed or self.keyFinalized then return end
    self.keyFinalized=true
    local report={entries={},players={},complete=not self.keySpellPartial and not self.partial,key=true,created=GetTime()}
    for _, record in pairs(self.keySpells or {}) do
        if record.amount>0 then
            report.entries[#report.entries+1]={guid=record.guid,name=record.name,class=record.class,
                spellID=record.spellID,amount=record.amount}
        end
    end
    for _, record in pairs(self.players or {}) do
        report.players[#report.players+1]={guid=record.guid,name=record.name,class=record.class,
            amount=record.amount,known=record.known==true,fatal=record.fatal,deathUnknown=record.deathUnknown}
    end
    table.sort(report.players,function(a,b) return a.amount>b.amount end)
    table.sort(report.entries,function(a,b)
        if a.name~=b.name then return (a.name or "")<(b.name or "") end
        return a.amount>b.amount
    end)
    self.keyReport, self.lastReport, self.reportOffset, self.reportExpires = report, report, 0, nil
    self.reportView="players"
end

-- Current can be a combined Mythic+ session. A pull is the difference from
-- the last public pre-combat totals, not another copy of the whole key.
function Monitor:CapturePullBaseline()
    local baseline={totals={},ready={}}
    for key, record in pairs(self.keySpells or {}) do baseline.totals[key]=record.last end
    for _, player in ipairs(self.roster or {}) do
        baseline.ready[player.guid]=player.spellBaselinePending==false and player.spellSnapshotReady==true
    end
    self.pullBaseline=baseline
end
function Monitor:ReadPullReport()
    local baseline=self.pullBaseline
    if not baseline then return self:ReadCombatReport() end
    local overall=self:ReadCombatReport(true)
    if not overall then return end
    local report={entries={},complete=overall.complete and not baseline.partial}
    for _, entry in ipairs(overall.entries) do
        if baseline.ready[entry.guid] then
            local previous=baseline.totals[entry.guid..":"..entry.spellID] or 0
            local delta=entry.amount-previous
            if delta>0 then
                if #report.entries<128 then
                    local player=self.players[entry.guid]
                    local hp=player and player.unit and JP.SafeString(UnitGUID(player.unit))==entry.guid
                        and Number(Call(_G,"UnitHealthMax",player.unit))
                    report.entries[#report.entries+1]={guid=entry.guid,name=entry.name,class=entry.class,
                        spellID=entry.spellID,amount=delta,healthRatio=hp and hp>0 and delta/hp or nil}
                else report.complete=false end
            elseif delta<0 then report.complete=false end
        else report.complete=false end
    end
    table.sort(report.entries,function(a,b)
        if a.amount~=b.amount then return a.amount>b.amount end
        if a.spellID~=b.spellID then return a.spellID<b.spellID end
        return a.guid<b.guid
    end)
    return report
end

function Monitor:CancelCombatReport()
    if self.reportTimer then self.reportTimer:Cancel(); self.reportTimer=nil end
    self.awaitingReport, self.reportDeadline, self.reportRetryAt = nil, nil, nil
    self.reportExhausted, self.reportNoticeShown, self.pullBaseline = nil, nil, nil
    self.pullSnapshotReady=nil
    self.pullSnapshotReadyPlayers=nil
end

function Monitor:QueueCombatReport(attempt)
    if not self.running or not self.active or self.frozen or self.reportTimer then return end
    if self.completed and self.keyFinalized then return end
    if not self.awaitingReport then
        self.awaitingReport=true; self.reportDeadline=GetTime()+45
    end
    if GetTime()>self.reportDeadline then self:CancelCombatReport(); return end
    attempt=attempt or (self.reportExhausted and 6 or 1)
    -- Five quick attempts, then wake only on native meter updates. The player
    -- combat event can precede both lockdown release and public spell details.
    local delay=attempt==1 and .35 or (attempt==2 and .65 or (attempt==3 and 1 or (attempt==4 and 2 or (attempt==5 and 3 or .25))))
    delay=math.max(delay,(self.reportRetryAt or 0)-GetTime())
    local timer
    timer=C_Timer.NewTimer(delay,function()
        if self.reportTimer~=timer then return end
        self.reportTimer=nil
        if not self.running or not self.active or self.frozen then return end
        if GetTime()>self.reportDeadline then self:CancelCombatReport(); return end
        self.reportRetryAt=GetTime()+.25
        if self:IsCombatLocked() then
            if attempt<5 then self:QueueCombatReport(attempt+1)
            else self.reportExhausted=true end
            return
        end
        local report=self:ReadPullReport()
        if (not report or not report.complete or #report.entries==0) and attempt<5 then
            self:QueueCombatReport(attempt+1); return
        end
        report=report or {entries={},complete=false}
        if #report.entries==0 and not self.completed then
            -- An empty response can be stale while Blizzard finishes the pull.
            -- Do not discard the pending pull or repeatedly replay a placeholder.
            self.reportExhausted=true
            -- Establish a baseline for the NEXT fight even if this one began
            -- before loading/enabling the addon, when its starting totals were unknown.
            self.pullSnapshotReady=self:UpdateKeySpells(); self:Snapshot()
            self.pullSnapshotReadyPlayers={}
            for _,player in ipairs(self.roster or {}) do
                self.pullSnapshotReadyPlayers[player.guid]=player.spellSnapshotReady==true
            end
            if not report.complete and not self.reportNoticeShown then
                self.reportNoticeShown=true; report.created=GetTime()
                self.lastReport,self.reportOffset,self.reportExpires=report,0,GetTime()+30
                self.reportView="spells"; self:Render()
            end
            return
        end
        report.created=GetTime()
        self.lastReport, self.reportOffset, self.reportExpires = report, 0, GetTime()+30
        self.reportView="spells"
        self:UpdateKeySpells()
        self:Snapshot()
        if self.completed then self:FinishKeyReport() end
        self:CancelCombatReport()
        self:Render()
    end)
    self.reportTimer=timer
end

function Monitor:ReadRecap(id)
    local events = JP.SafeTable(Call(C_DeathRecap, "GetRecapEvents", id))
    if not events or #events == 0 then return nil end
    -- Blizzard_DeathRecap.lua BuildDataProvider marks index 1 as causedDeath.
    -- That field is synthesized by the UI, NOT returned by GetRecapEvents.
    -- Use the same native killing-blow order and require a public avoidable
    -- flag on that event. `deadly` merely describes a dangerous ability.
    local killingBlow = JP.SafeTable(events[1])
    if killingBlow then return JP.SafeOptionalBoolean(killingBlow.avoidable) end
end

function Monitor:ReadDeaths()
    local types = Enum and Enum.DamageMeterType
    if not types then return false end
    local found, complete = {}, true
    local function Collect(session)
        local sources = Sources(session)
        if not sources then complete = false; return end
        if #sources > MAX_SOURCES then complete = false end
        for i = 1, math.min(#sources, MAX_SOURCES) do
            local source = JP.SafeTable(sources[i])
            local id = source and Number(source.deathRecapID)
            local guid = source and JP.SafeString(source.sourceGUID)
            if id and id > 0 and guid then found[id] = guid
            elseif not source or not guid or not id then complete = false end
        end
    end
    Collect(Overall(types.Deaths))
    local sessions = JP.SafeTable(Call(C_DamageMeter, "GetAvailableCombatSessions"))
    if sessions then
        -- Deaths can appear in both the combined key and individual pulls.
        -- Recap IDs, not session totals, are deduplicated across all of them.
        local ids = {}
        for i = 1, math.min(#sessions, 128) do
            local session = JP.SafeTable(sessions[i])
            local id = session and Number(session.sessionID)
            if id then ids[#ids+1] = id end
        end
        table.sort(ids, function(a,b) return a > b end)
        for i = 1, math.min(#ids, MAX_SESSIONS) do
            Collect(Call(C_DamageMeter, "GetCombatSessionFromID", ids[i], types.Deaths))
        end
    end
    for id, guid in pairs(found) do
        local record = self.players[guid]
        if record and not self.recaps[id] then
            if self.recapCount < MAX_RECAPS then
                self.recaps[id] = {guid=guid, done=not record.deathsReady}
                self.recapIDs[#self.recapIDs+1] = id
                self.recapCount = self.recapCount + 1
            else self.partial = true; complete = false end
        end
    end
    -- Bounded retries allow a recap to arrive after its meter row. Unknown
    -- flags remain unknown; they are never guessed from overkill or damage.
    local pending, scanned, budget = {}, 0, 32
    -- Round-robin: unresolved early recaps must not starve later deaths.
    -- Never perform hundreds of native recap calls in a single UI update.
    while scanned < #self.recapIDs and budget > 0 do
        self.recapCursor = self.recapCursor % #self.recapIDs + 1
        local id = self.recapIDs[self.recapCursor]
        local recap = self.recaps[id]
        scanned = scanned + 1
        if not recap.done then
            budget = budget - 1
            local result = self:ReadRecap(id)
            if result ~= nil then
                recap.done = true
                if result then
                    local record = self.players[recap.guid]
                    if record then record.fatal = record.fatal + 1 end
                end
            end
        end
    end
    for _, recap in pairs(self.recaps) do
        if not recap.done then pending[recap.guid] = true end
    end
    for _, record in ipairs(self.roster) do
        record.deathUnknown = not complete or pending[record.guid] == true
        if complete then record.deathsReady = true end
    end
    return complete
end

function Monitor:Snapshot()
    if not self.active or self.frozen then return end
    if self:IsCombatLocked() then
        self.stale = true; return
    end
    local available = JP.SafeOptionalBoolean(Call(C_DamageMeter, "IsDamageMeterAvailable"))
    if available ~= true then self.unavailable, self.stale = true, true; return end
    -- Availability is capability, not whether the user has enabled recording.
    if C_CVar and C_CVar.GetCVarBool and JP.SafeOptionalBoolean(Call(C_CVar, "GetCVarBool", "damageMeterEnabled")) == false then
        self.unavailable, self.stale = true, true; return
    end
    self.unavailable = false
    local amounts = self:ReadAmounts()
    self:ReadDeaths()
    self.stale = not amounts
    if not amounts then self.partial = true end
end

function Monitor:MeterReset()
    -- Preserve our last public totals without modifying the native meter.
    -- If reset happened during combat, unread damage is explicitly partial.
    if self.stale then self.partial = true end
    for _, record in pairs(self.players or {}) do
        record.last = 0
    end
    self.resetPending = true
    for _, record in pairs(self.keySpells or {}) do record.last=0 end
    if self.pullBaseline then
        self.pullBaseline.totals={}; self.pullBaseline.partial=true
    end
    -- Recap IDs may still be referenced by retained sessions after a reset;
    -- keep the bounded dedupe set for the lifetime of this dungeon.
end

function Monitor:CheckZone(force, scope)
    local inside, kind = IsInInstance()
    local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    instanceID = Number(instanceID)
    local eligible = JP.SafeBoolean(inside) and JP.SafeString(kind) == "party" and instanceID ~= nil
    if not eligible then
        self:CancelCombatReport(); self.reportExpected=false; self.lastReport=nil
        self:CancelSnapshot()
        self.active, self.instanceID = false, nil
    elseif force or not self.active or self.instanceID ~= instanceID then
        self.instanceID = instanceID
        self:Begin(scope or "joined")
    end
end

function Monitor:OnEvent(event, meterType)
    if not self.running then return end
    if event == "PLAYER_ENTERING_WORLD" then self:CheckZone()
    elseif event == "CHALLENGE_MODE_START" then self:CheckZone(true, "key")
    elseif event == "CHALLENGE_MODE_RESET" then self:CheckZone(true, "joined")
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        self.completed = true
        -- Completion may arrive before or after PLAYER_REGEN_ENABLED.
        if not self:IsCombatLocked() then self:QueueCombatReport() end
    elseif event == "GROUP_ROSTER_UPDATE" then
        self:RefreshRoster(); self:UpdateKeySpells()
    elseif event == "DAMAGE_METER_RESET" and self.active and not self.frozen then self:MeterReset()
    elseif event == "PLAYER_REGEN_DISABLED" then
        local unreadPull=self.awaitingReport and not self.pullSnapshotReady
        local readyPlayers=self.pullSnapshotReadyPlayers
        if self.reportTimer or unreadPull then self.keySpellPartial=true end
        self:CancelCombatReport()
        if not self.completed then self.lastReport=nil end
        if self.completed then self:FinishKeyReport(); self.frozen = true end
        self.reportExpected = self.active and not self.frozen
        if self.reportExpected then self:CapturePullBaseline() end
        if unreadPull and self.pullBaseline then
            -- With no public boundary between two pulls, their combined damage
            -- cannot truthfully be attributed to the second pull alone.
            for guid in pairs(self.pullBaseline.ready) do
                if not readyPlayers or not readyPlayers[guid] then self.pullBaseline.ready[guid]=false end
            end
            self.pullBaseline.partial=true
        end
        self.stale = true
    elseif event == "PLAYER_REGEN_ENABLED" and self.active and not self.frozen and not self.keyFinalized then
        if not self.pullBaseline then self:CapturePullBaseline() end
        self.reportExpected=false
        self:QueueCombatReport()
    elseif event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" then
        local value = Number(meterType)
        local types = Enum and Enum.DamageMeterType
        if not types or (value ~= types.AvoidableDamageTaken and value ~= types.Deaths) then return end
    end
    if event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" or event == "DAMAGE_METER_CURRENT_SESSION_UPDATED" then
        if self.awaitingReport and not self:IsCombatLocked() then
            self:QueueCombatReport()
        end
        self:QueueSnapshot()
        return
    end
    self:CancelSnapshot()
    self:Snapshot()
    self:Render()
end

-- A meter event burst used to rescan 24 sessions and up to 512 recaps for
-- every notification. One trailing snapshot reads the latest state. Urgent
-- lifecycle/combat-end events above remain synchronous public-data reads.
function Monitor:CancelSnapshot()
    if self.snapshotTimer then self.snapshotTimer:Cancel(); self.snapshotTimer = nil end
end

-- Manual, local-only diagnostics: no names, GUIDs, secret values or saved log.
-- Do not change baselines or trigger playback just to inspect the live client.
function Monitor:Diagnose()
    local function Flag(value)
        value=JP.SafeOptionalBoolean(value)
        return value==nil and "?" or tostring(value)
    end
    local ok,lockdown=pcall(InCombatLockdown)
    local lockState=not ok and "error" or (JP.IsSecret(lockdown) and "secret" or type(lockdown))
    if ok and not JP.IsSecret(lockdown) and type(lockdown)=="boolean" then lockState=tostring(lockdown) end
    local ready=0
    for _,player in ipairs(self.roster or {}) do if player.spellSnapshotReady then ready=ready+1 end end
    JP:Print(("Feed %s: enabled=%s running=%s dungeon=%s lockdown=%s frozen=%s ready=%d waiting=%s shown=%s"):format(
        JP:GetVersion(),Flag(self:Settings().enabled),Flag(self.running==true),Flag(self.active==true),lockState,
        Flag(self.frozen==true),ready,Flag(self.awaitingReport==true),Flag(self.frame and self.frame:IsShown())))
    if self:IsCombatLocked() then return end
    local report=self:ReadCombatReport(true)
    local types=Enum and Enum.DamageMeterType
    local sources=types and Sources(Overall(types.AvoidableDamageTaken))
    JP:Print(("Feed meter: available=%s enabled=%s sources=%s spells=%s complete=%s last=%s"):format(
        Flag(Call(C_DamageMeter,"IsDamageMeterAvailable")),Flag(Call(C_CVar,"GetCVarBool","damageMeterEnabled")),
        sources and tostring(#sources) or "?",report and tostring(#report.entries) or "?",
        Flag(report and report.complete),self.lastReport and tostring(#self.lastReport.entries) or "none"))
end
function Monitor:QueueSnapshot()
    if not self.active or self.frozen or self.snapshotTimer or self:IsCombatLocked() then return end
    self.snapshotTimer = C_Timer.NewTimer(.25, function()
        self.snapshotTimer = nil
        if not self.running or not self.active then return end
        self:Snapshot(); self:Render()
    end)
end

function Monitor:Enable()
    if self:Settings().enabled == false then return end
    self:Create(); self.running = true
    self:SetUnlocked(MythicBoostDB.interfaceUnlocked == true)
    for _, event in ipairs({"PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "CHALLENGE_MODE_START",
        "CHALLENGE_MODE_RESET", "CHALLENGE_MODE_COMPLETED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED"}) do
        self.events:RegisterEvent(event)
    end
    if C_DamageMeter then
        for _, event in ipairs({"DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_CURRENT_SESSION_UPDATED", "DAMAGE_METER_RESET"}) do
            self.events:RegisterEvent(event)
        end
    end
    self:CheckZone(true); self:Render()
end
function Monitor:Disable()
    self:CancelSnapshot()
    self:CancelCombatReport(); self.reportExpected=false
    self:SetUnlocked(false)
    self.running, self.active = false, false
    if self.events then self.events:UnregisterAllEvents() end
    if self.frame then self.frame:Hide() end
    if self.tooltip then self.tooltip:Hide() end
end
function Monitor:Destroy() self:Disable() end
JP.AvoidableDamage = Monitor
JP:RegisterModule("AvoidableDamage", Monitor)
