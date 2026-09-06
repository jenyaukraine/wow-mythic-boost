local _, JP = ...
local Stats, L = {}, JP.L
JP.RunStats = Stats

-- Only primitive, public values cross this boundary. No native session,
-- unit token, frame, spell list or mutable meter table is kept in SavedVariables.
local function Number(value, ceiling)
    value = JP.SafeNumber(value)
    if value and value == value and value >= 0 and value <= ceiling then return value end
end
local FIELDS = {"damage", "healing", "avoidable"}
local TYPES = {damage="DamageDone", healing="HealingDone", avoidable="AvoidableDamageTaken"}
local function PublicCombat()
    return InCombatLockdown and JP.SafeOptionalBoolean(InCombatLockdown()) == false
end
local function Call(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, value = pcall(fn, ...)
    if ok then return value end
end

function Stats:Validate(value)
    if not JP.SafeTable(value) or JP.SafeNumber(value.version) ~= 1 then return end
    local at = Number(value.runAt, 9999999999)
    if not at or at < 1 or at%1 ~= 0 then return end
    local role = JP.SafeString(value.role)
    if role ~= "HEALER" and role ~= "TANK" and role ~= "DAMAGER" then role = "NONE" end
    local out = {version=1, runAt=at, role=role,
        complete=JP.SafeOptionalBoolean(value.complete)==true}
    for _, field in ipairs(FIELDS) do
        local n = Number(value[field], 1e15)
        if n then out[field] = math.floor(n) end
    end
    local duration = Number(value.duration, 86400)
    if duration and duration > 0 then out.duration = math.floor(duration*1000+.5)/1000 end
    local ilvl = Number(value.itemLevel, 10000)
    if ilvl and ilvl > 0 then out.itemLevel = math.floor(ilvl*10+.5)/10 end
    return out
end

-- Bounded primitive snapshot for comparisons and the shared review protocol.
-- Native meter objects and private PlayerNetwork notes are never serialized.
function Stats:Encode(value)
    local s = self:Validate(value)
    if not s then return "" end
    local fields = {"S1", s.runAt, s.role, s.complete and "1" or "0"}
    for _, key in ipairs({"damage","healing","avoidable","duration","itemLevel"}) do
        fields[#fields+1] = s[key] and tostring(s[key]) or "-"
    end
    return table.concat(fields, ",")
end
function Stats:Decode(text)
    text = JP.SafeString(text)
    if not text or #text > 160 then return end
    local at,role,complete,d,h,a,t,i = text:match("^S1,(%d+),([A-Z]+),([01]),([%d%.%-]+),([%d%.%-]+),([%d%.%-]+),([%d%.%-]+),([%d%.%-]+)$")
    if not at then return end
    local s = {version=1,runAt=tonumber(at),role=role,complete=complete=="1"}
    for key,raw in pairs({damage=d,healing=h,avoidable=a,duration=t,itemLevel=i}) do
        if raw ~= "-" then
            local n = tonumber(raw)
            if not n then return end
            s[key] = n
        end
    end
    local valid = self:Validate(s)
    -- Reject out-of-range supplied fields rather than silently blessing them.
    if not valid then return end
    for key in pairs(s) do if valid[key] == nil then return end end
    return valid
end
function Stats:ForMember(run, target)
    local data = run and JP.SafeTable(run.performance)
    return data and self:Validate(data[target:lower()])
end
local function Compact(n)
    if not n then return "—" end
    if n >= 1e9 then return ("%.2fB"):format(n/1e9) end
    if n >= 1e6 then return ("%.2fM"):format(n/1e6) end
    if n >= 1000 then return ("%.1fk"):format(n/1000) end
    return ("%.0f"):format(n)
end
function Stats:Text(value, detailed)
    local s = self:Validate(value)
    if not s then return L("Статистика ключа недоступна") end
    local dps = s.damage and s.duration and s.duration > 0 and s.damage/s.duration or nil
    local hps = s.healing and s.duration and s.duration > 0 and s.healing/s.duration or nil
    local parts = {"ilvl " .. (s.itemLevel and ("%.1f"):format(s.itemLevel) or "—")}
    if s.role=="HEALER" then parts[#parts+1]="HPS "..Compact(hps) end
    parts[#parts+1]="DPS "..Compact(dps)
    if detailed then
        parts[#parts+1]=L("Общий урон")..": "..Compact(s.damage)
        parts[#parts+1]=L("Общее исцеление")..": "..Compact(s.healing)
        if s.role~="HEALER" then parts[#parts+1]="HPS "..Compact(hps) end
    end
    parts[#parts+1]=L("Избегаемый урон")..": "..Compact(s.avoidable)
    if not s.complete then parts[#parts+1]=L("Неполная сводка") end
    return table.concat(parts, detailed and "\n" or "  -  ")
end

function Stats:ReadMeter(field)
    if not PublicCombat() then return end
    local api = C_DamageMeter
    local enabled = C_CVar and Call(C_CVar.GetCVarBool, "damageMeterEnabled")
    if enabled == nil and GetCVarBool then enabled = Call(GetCVarBool, "damageMeterEnabled") end
    if not api or JP.SafeOptionalBoolean(enabled) ~= true
        or JP.SafeOptionalBoolean(Call(api.IsDamageMeterAvailable)) ~= true then return end
    local meter = Enum and Enum.DamageMeterType and Enum.DamageMeterType[TYPES[field]]
    local overall = Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Overall
    if not meter or overall == nil then return end
    local session = JP.SafeTable(Call(api.GetCombatSessionFromType, overall, meter))
    local sources = session and JP.SafeTable(session.combatSources)
    if not sources then return end
    local duration = Number(session.durationSeconds, 1e8)
    local amounts, count = {}, 0
    for _, raw in pairs(sources) do
        count = count+1
        if count > 160 then return end
        local source = JP.SafeTable(raw)
        if not source then return end
        local guid = JP.SafeString(source.sourceGUID)
        if JP.IsSecret(source.sourceGUID) then return end
        if guid and self.players[guid] then
            local amount = Number(source.totalAmount, 1e15)
            if not amount or amounts[guid] then return end
            amounts[guid] = amount
        end
    end
    return amounts, duration
end

function Stats:ReadGear()
    if not PublicCombat() then return end
    for _,unit in ipairs({"player","party1","party2","party3","party4"}) do
        local guid = JP.SafeString(Call(UnitGUID, unit))
        local member = guid and self.players[guid]
        if member then
            local ilvl
            if unit=="player" and type(GetAverageItemLevel)=="function" then
                local ok, _, equipped = pcall(GetAverageItemLevel)
                if ok then ilvl=Number(equipped,10000) end
            elseif C_PaperDollInfo then
                ilvl=Number(Call(C_PaperDollInfo.GetInspectItemLevel,unit),10000)
            end
            -- No NotifyInspect spam and no old tooltip/LFG cache from another run.
            if ilvl and ilvl>0 then member.itemLevel=ilvl end
        end
    end
end

function Stats:Snapshot(initial)
    if not self.players or not PublicCombat() then return end
    if not self.result then self:ReadGear() end
    for _,field in ipairs(FIELDS) do
        local amounts,duration = self:ReadMeter(field)
        local state = self.meters[field]
        state.readable = amounts ~= nil
        if amounts then
            if state.last then
                local reset = duration and state.lastDuration and duration < state.lastDuration
                if reset then state.partial=true end
                for guid,member in pairs(self.players) do
                    local current, previous = amounts[guid] or 0, state.last[guid] or 0
                    -- A disappearing row is not proof that an existing total
                    -- reset to zero. Keep its baseline so a later reappearance
                    -- cannot count the whole old total for a second time.
                    if not reset and amounts[guid]==nil and previous>0 then
                        current=previous; amounts[guid]=previous; state.partial=true
                    end
                    local delta = current-previous
                    if reset or delta<0 then delta=current; state.partial=true end
                    member[field] = (member[field] or 0)+delta
                end
                if field=="damage" then
                    if duration and state.lastDuration then
                        local delta=duration-state.lastDuration
                        self.duration=(self.duration or 0)+(delta>=0 and delta or duration)
                    else self.durationUnknown=true end
                end
            elseif not initial then
                -- A missing start boundary cannot be reconstructed from Overall.
                state.partial=true
            end
            state.last, state.lastDuration = amounts, duration
        end
    end
    if JP.TalentLab then JP.TalentLab:Snapshot(self.run,self.result,self) end
    if self.result then self:Publish() end
end

function Stats:Publish()
    local result = self.result
    if not result or not self.players or not self.meters then return end
    local performance, complete = {}, not self.resumed
    for _,field in ipairs(FIELDS) do
        local m=self.meters[field]
        if not m.last or not m.readable or m.partial then complete=false end
    end
    if self.durationUnknown or not self.duration or self.duration<=0 then complete=false end
    local allowed={}
    for _,name in ipairs(result.members or {}) do
        local full=JP.Reviews and JP.Reviews.FullName(name) or name
        if full then allowed[full:lower()]=true end
    end
    for _,member in pairs(self.players) do
        local name=JP.Reviews and JP.Reviews.FullName(member.name) or member.name
        if name and allowed[name:lower()] then
            local entry={version=1,runAt=result.completedAt,role=member.role,itemLevel=member.itemLevel,
                damage=member.damage,healing=member.healing,avoidable=member.avoidable,
                duration=not self.durationUnknown and self.duration or nil,complete=complete}
            performance[name:lower()]=self:Validate(entry)
        end
    end
    result.performance=performance
    result.combatStatsAvailable=complete
    if JP.Reviews and JP.Reviews.UpdateRunStats then JP.Reviews:UpdateRunStats(result) end
end

-- Registered only while tracking one key (and at most 45 seconds afterwards).
-- A single coalesced timer; no OnUpdate, combat log, ticker or spell histories.
function Stats:CancelTimer()
    if self.timer then self.timer:Cancel(); self.timer=nil end
    self.timerAt=nil
end
function Stats:Stop()
    if JP.TalentLab then JP.TalentLab:Stop(self.run) end
    self:CancelTimer()
    if self.events then self.events:UnregisterAllEvents() end
    self.players=nil; self.meters=nil; self.result=nil; self.run=nil; self.deadline=nil
end
function Stats:Queue(delay)
    if not self.players then return end
    delay=delay or .35
    local due=GetTime()+delay
    if self.timer then
        if self.timerAt and self.timerAt<=due then return end
        self:CancelTimer()
    end
    local timer
    timer=C_Timer.NewTimer(delay,function()
        if self.timer~=timer then return end
        self.timer=nil; self.timerAt=nil
        if not self.players then return end
        self:Snapshot()
        if self.deadline then
            if GetTime()>=self.deadline then self:Stop()
            else self:Queue(math.min(5,self.deadline-GetTime())) end
        end
    end)
    self.timer=timer; self.timerAt=due
end
function Stats:Start(run)
    self:Stop()
    self.run=run; self.players={}; self.meters={}; self.resumed=run.trackingPartial==true
    self.duration=0; self.durationUnknown=nil
    for index,member in ipairs(run.members or {}) do
        if index>5 then break end
        if JP.SafeString(member.guid) and JP.SafeString(member.name) then
            self.players[member.guid]={name=member.name,role=JP.SafeString(member.role)}
        end
    end
    for _,field in ipairs(FIELDS) do self.meters[field]={} end
    if not self.events then
        self.events=CreateFrame("Frame")
        self.events:SetScript("OnEvent",function(_,event,...)
            if event=="PLAYER_REGEN_DISABLED" then
                if self.result then self:Publish(); self:Stop() end
            elseif event=="DAMAGE_METER_RESET" then
                if JP.TalentLab then JP.TalentLab:Reset() end
                for _,m in pairs(self.meters) do m.last={}; m.lastDuration=0; m.partial=true end
                self:Queue()
            elseif event=="TRAIT_CONFIG_UPDATED" or event=="ACTIVE_TALENT_GROUP_CHANGED" then
                if JP.TalentLab then JP.TalentLab:BuildChanged() end
                if PublicCombat() then self:Queue() end
            elseif event=="PLAYER_ENTERING_WORLD" then
                -- Loading during a finished-key grace period must not append
                -- another zone's data. In-key reloads are labelled partial.
                if self.result then self:Publish(); self:Stop() end
            elseif event=="PLAYER_REGEN_ENABLED" or PublicCombat() then self:Queue() end
        end)
    end
    for _,event in ipairs({"PLAYER_REGEN_ENABLED","PLAYER_REGEN_DISABLED","DAMAGE_METER_RESET",
        "DAMAGE_METER_COMBAT_SESSION_UPDATED","DAMAGE_METER_CURRENT_SESSION_UPDATED",
        "INSPECT_READY","PLAYER_ENTERING_WORLD","TRAIT_CONFIG_UPDATED","ACTIVE_TALENT_GROUP_CHANGED"}) do self.events:RegisterEvent(event) end
    if JP.TalentLab then JP.TalentLab:Begin(run) end
    self:Snapshot(true)
end
function Stats:Finish(run,result)
    if self.run~=run then return end
    -- Freeze the last known equipped ilvl at completion. Equipping loot during
    -- delayed meter delivery must not rewrite what the player wore in the key.
    self:ReadGear()
    for _,member in ipairs(run.members or {}) do
        local player=self.players[member.guid]
        if player then player.role=JP.SafeString(member.role) or player.role end
    end
    self.result=result; self.deadline=GetTime()+45
    if JP.TalentLab then JP.TalentLab:Finish(run,result) end
    self:Publish(); self:CancelTimer(); self:Queue(.5)
end
