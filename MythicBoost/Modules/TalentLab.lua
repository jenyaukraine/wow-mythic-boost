local _, JP = ...

-- TalentLab is deliberately parent-driven.  RunStats owns the one bounded
-- timer/event stream; this module only reads Blizzard's native meter while
-- out of combat and keeps one in-memory sample for the current key.
local Lab = {}
JP.TalentLab = Lab

local MAX_NODES, MAX_SPELLS, MAX_RUNS = 256, 256, 30
local TYPES = { healing = "HealingDone", damage = "DamageDone" }

local function PlainNumber(v, max)
    if JP.SafeNumber then v = JP.SafeNumber(v) end
    if type(v) ~= "number" or v ~= v or v < 0 or v > (max or 1e15) then return nil end
    return v
end
local function PlainString(v)
    if JP.SafeString then v = JP.SafeString(v) end
    return type(v) == "string" and v ~= "" and v or nil
end
local function Table(v)
    if JP.SafeTable then v = JP.SafeTable(v) end
    return type(v) == "table" and v or nil
end
local function Secret(v)
    return JP.IsSecret(v)
end
local function OOC()
    return type(InCombatLockdown) == "function" and JP.SafeOptionalBoolean(InCombatLockdown()) == false
end
local function Call(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end

local function SpecID()
    if type(GetSpecialization) == "function" and type(GetSpecializationInfo) == "function" then
        return PlainNumber(Call(GetSpecializationInfo, Call(GetSpecialization)), 100000)
    end
end

local function Build()
    if not OOC() then return end
    if not C_ClassTalents or type(C_ClassTalents.GetActiveConfigID) ~= "function"
        or not C_Traits or type(C_Traits.GetConfigInfo) ~= "function" then return end
    local configID = PlainNumber(Call(C_ClassTalents.GetActiveConfigID), 100000000)
    -- GetNodeInfo includes staged talent previews. Never label measurements
    -- with a build the player has not applied.
    if not configID or JP.SafeOptionalBoolean(Call(C_Traits.ConfigHasStagedChanges,configID))~=false then return end
    local config = configID and Table(Call(C_Traits.GetConfigInfo, configID))
    if not config then return end
    local heroID=PlainNumber(Call(C_ClassTalents.GetActiveHeroTalentSpec),100000000)
    local selected, ids, count, visited = {}, {}, 0, 0
    local trees=Table(config.treeIDs)
    if not trees or #trees==0 or #trees>4 then return end
    for _, rawTreeID in ipairs(trees) do
        local treeID = PlainNumber(rawTreeID, 100000000)
        local nodes = treeID and Table(Call(C_Traits.GetTreeNodes, treeID))
        if not nodes then return end
        for _, rawNodeID in ipairs(nodes or {}) do
            visited=visited+1
            if count >= MAX_NODES or visited>1024 then return end
            local nodeID = PlainNumber(rawNodeID, 100000000)
            local node = nodeID and Table(Call(C_Traits.GetNodeInfo, configID, nodeID))
            if not node then return end
            local active = node and Table(node.activeEntry)
            local rank = node and (PlainNumber(node.activeRank, 1000) or PlainNumber(node.ranksPurchased, 1000))
            local subTree=PlainNumber(node.subTreeID,100000000)
            local included=node.subTreeID==nil or (subTree and subTree==heroID and JP.SafeOptionalBoolean(node.subTreeActive)==true)
            if nodeID and included and active and rank and rank > 0 then
                local entryID = PlainNumber(active.entryID, 100000000)
                local committed=Table(node.entryIDsWithCommittedRanks)
                if committed and #committed>0 and (#committed~=1 or committed[1]~=entryID) then return end
                if entryID then
                    local spellID
                    local entry = Table(Call(C_Traits.GetEntryInfo, configID, entryID))
                    local defID = entry and PlainNumber(entry.definitionID, 100000000)
                    local def = defID and Table(Call(C_Traits.GetDefinitionInfo, defID))
                    spellID = def and PlainNumber(def.spellID, 100000000)
                    selected[nodeID] = { entryID = entryID, rank = rank, spellID = spellID }
                    count = count + 1; ids[count] = nodeID
                end
            end
        end
    end
    table.sort(ids)
    if count == 0 then return nil end
    local key = {}
    for _, nodeID in ipairs(ids) do
        local e = selected[nodeID]
        key[#key + 1] = ("%d:%d:%d"):format(nodeID, e.entryID, e.rank)
    end
    if JP.SafeOptionalBoolean(Call(C_Traits.ConfigHasStagedChanges,configID))~=false then return end
    local buildKey = tostring(SpecID() or 0) .. "|" .. table.concat(key, ";")
    local buildName = PlainString(config.name)
    if buildName and JP.Reviews then buildName=JP.Reviews.CleanText(buildName) end
    local gameBuild
    if type(GetBuildInfo) == "function" then
        local version, build = GetBuildInfo()
        version,build=PlainString(version),PlainString(build)
        gameBuild = version and build and (version..":"..build) or version or build
    end
    return { configID = configID, specID = SpecID(), gameBuild = gameBuild,
        buildKey = buildKey, buildName = buildName, selected = selected }
end

local function PlayerGUID()
    return type(UnitGUID) == "function" and PlainString(Call(UnitGUID, "player"))
end

local function Meter(field, guid)
    if not OOC() or not C_DamageMeter or type(C_DamageMeter.GetCombatSessionSourceFromType) ~= "function" then return end
    local enabled=C_CVar and Call(C_CVar.GetCVarBool,"damageMeterEnabled")
    if enabled==nil then enabled=Call(GetCVarBool,"damageMeterEnabled") end
    if JP.SafeOptionalBoolean(enabled)~=true or
        JP.SafeOptionalBoolean(Call(C_DamageMeter.IsDamageMeterAvailable))~=true then return end
    local sessionType = Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Overall
    local meterType = Enum and Enum.DamageMeterType and Enum.DamageMeterType[TYPES[field]]
    if sessionType == nil or meterType == nil or not guid then return end
    local rawSource = Call(C_DamageMeter.GetCombatSessionSourceFromType, sessionType, meterType, guid, nil)
    if Secret(rawSource) then return nil, true end
    local source = Table(rawSource)
    if not source then return end
    local total = PlainNumber(source.totalAmount, 1e15)
    if not total then return end
    local spells, count, sum = {}, 0, 0
    local rawSpells = Table(source.combatSpells)
    if not rawSpells then return nil, true end
    for _, raw in pairs(rawSpells) do
        if count >= MAX_SPELLS then return nil, true end
        local spell = Table(raw)
        local spellID, amount = spell and PlainNumber(spell.spellID, 100000000), spell and PlainNumber(spell.totalAmount, 1e15)
        if not spellID or spellID<1 or spellID%1~=0 or not amount or spells[spellID] then return nil, true end
        spells[spellID] = amount; count = count + 1; sum=sum+amount
    end
    if math.abs(sum-total)>math.max(1,total*.00001) then return nil,true end
    return { total = total, spells = spells }, false
end

local function Aggregate(runStats)
    local guid = PlayerGUID()
    local players = runStats and Table(runStats.players)
    local p = guid and players and players[guid]
    if not p then return end
    return PlainNumber(p.healing, 1e15), PlainNumber(p.damage, 1e15)
end
local function CopySelected(source)
    local out = {}
    for nodeID, entry in pairs(source or {}) do
        out[nodeID] = { entryID = entry.entryID, rank = entry.rank, spellID = entry.spellID }
    end
    return out
end

function Lab:Begin(run)
    self:Stop()
    self.run, self.build, self.guid = run, Build(), PlayerGUID()
    self.baseline, self.values = {}, { healing = {}, damage = {} }
    self.partial, self.mixed = not self.build or not self.guid or run.trackingPartial == true, false
    for field in pairs(TYPES) do
        self.baseline[field]=Meter(field,self.guid)
        if not self.baseline[field] then self.partial=true end
    end
end

-- Re-evaluate the talent tree only when its native configuration changes,
-- not on every damage-meter update. The build is frozen at key completion.
function Lab:BuildChanged()
    if self.run and not self.finished then self.buildDirty=true end
end
function Lab:CheckBuild()
    if not OOC() then self.buildDirty=true; return end
    local current=Build()
    if not current then self.partial=true
    elseif not self.build then self.build=current; self.partial=true
    elseif current.buildKey~=self.build.buildKey then self.mixed=true; self.partial=true end
    self.buildDirty=nil
end

function Lab:Snapshot(run, result, runStats)
    if run and self.run ~= run then return end
    if not self.run or not self.guid then return end
    if not OOC() then return end
    if self.buildDirty then self:CheckBuild() end
    for field in pairs(TYPES) do
        local current, overflow = Meter(field, self.guid)
        if overflow then self.partial = true
        end
        if current then
            local base = self.baseline[field]
            if not base then
                self.baseline[field] = current; self.baselinePending = true; self.partial = true
            else
                if current.total < base.total then
                    self.partial=true; base={total=0,spells={}}
                end
                    local out = self.values[field]
                    local outCount = 0
                    for _ in pairs(out) do outCount = outCount + 1 end
                    for spellID, amount in pairs(current.spells) do
                        local old = base.spells[spellID] or 0
                        if amount < old then self.partial = true; old = 0 end
                        if out[spellID] or outCount < MAX_SPELLS then
                            if out[spellID]==nil then outCount=outCount+1 end
                            out[spellID] = (out[spellID] or 0) + amount - old
                        else
                            self.partial = true
                        end
                    end
                    self.baseline[field] = current
            end
        else
            self.partial = true
        end
    end
    if result then self:Finish(run, result, runStats) end
end

function Lab:Finish(run, result, runStats)
    if not self.run or (run and self.run ~= run) or not result then return end
    if not self.finished then self:CheckBuild(); self.finished=true end
    local healing, damage = Aggregate(runStats)
    local spells = { healing = {}, damage = {} }
    for field in pairs(TYPES) do
        local count = 0
        for spellID, amount in pairs(self.values[field] or {}) do
            if count >= MAX_SPELLS then self.partial = true; break end
            spells[field][spellID] = math.floor(amount); count = count + 1
        end
    end
    local duration = runStats and PlainNumber(runStats.duration, 86400)
    local complete=not self.partial and not self.mixed and duration and duration>0
        and healing~=nil and damage~=nil and not runStats.durationUnknown
    for _,field in ipairs({"healing","damage"}) do
        local state=runStats and runStats.meters and runStats.meters[field]
        if not state or not state.last or not state.readable or state.partial then complete=false end
        local sum=0; for _,amount in pairs(spells[field]) do sum=sum+amount end
        local overall=field=="healing" and healing or damage
        if not overall or math.abs(sum-overall)>math.max(1,overall*.00001) then complete=false end
    end
    result.talentSample = {
        specID = self.build and self.build.specID, gameBuild = self.build and self.build.gameBuild,
        buildKey = self.build and self.build.buildKey, buildName = self.build and self.build.buildName,
        mapID = PlainNumber(result.mapID, 1000000), level = PlainNumber(result.level, 1000),
        selected = CopySelected(self.build and self.build.selected), spells = spells,
        overallHealing = healing, overallDamage = damage, duration = duration,
        complete = complete==true,
        mixed = self.mixed == true,
    }
end

function Lab:Stop()
    self.run, self.build, self.guid, self.baseline, self.values = nil, nil, nil, nil, nil
    self.partial, self.mixed, self.baselinePending = nil, nil, nil
    self.buildDirty=nil; self.finished=nil
end

function Lab:Reset()
    if not self.run then return end
    self.partial=true
    self.baseline={healing={total=0,spells={}},damage={total=0,spells={}}}
end

function Lab:Rows(sample, metric)
    sample, metric = Table(sample), metric == "healing" and "healing" or "damage"
    local source = sample and Table(sample.spells) and Table(sample.spells[metric])
    local rows = {}
    local count=0
    for rawID, rawAmount in pairs(source or {}) do
        count=count+1; if count>MAX_SPELLS then break end
        local amount = PlainNumber(rawAmount, 1e15)
        local spellID=PlainNumber(rawID,100000000)
        if amount and spellID and spellID>0 and spellID%1==0 then rows[#rows + 1] = { spellID = spellID, amount = amount } end
    end
    table.sort(rows, function(a, b) return a.amount > b.amount end)
    return rows
end

-- These are measured spell-source totals, never the counterfactual gain from
-- spending a point. A passive modifier without a separate source stays unknown.
function Lab:TalentRows(sample,metric)
    sample=Table(sample); metric=metric=="healing" and "healing" or "damage"
    if not sample then return {} end
    local amounts=Table(sample.spells) and Table(sample.spells[metric]) or {}
    local mappings=JP.TalentSources and JP.TalentSources[PlainNumber(sample.specID,100000)] or {}
    local rows,seen,count={},{},0
    for _,raw in pairs(Table(sample.selected) or {}) do
        count=count+1; if count>MAX_NODES then break end
        local entry=Table(raw)
        local id=entry and PlainNumber(entry.spellID,100000000)
        local rank=entry and PlainNumber(entry.rank,1000)
        if id and id>0 and id%1==0 and rank and rank>0 and not seen[id] then
            seen[id]=true
            local mapping=mappings and mappings[id]
            local sources=mapping and mapping[metric]
            local amount=PlainNumber(amounts[id],1e15)
            local kind=amount~=nil and "direct" or "unattributed"
            if sources then
                local sum,found=0,false
                for _,spellID in ipairs(sources) do
                    local observed=PlainNumber(amounts[spellID],1e15)
                    if observed then sum=sum+observed; found=true end
                end
                if found or JP.SafeOptionalBoolean(sample.complete)==true then amount=sum; kind="direct" end
            end
            rows[#rows+1]={spellID=id,talentSpellID=id,rank=rank,amount=amount,kind=kind,sourceSpellIDs=sources}
        end
    end
    table.sort(rows,function(a,b)
        if (a.amount or -1)~=(b.amount or -1) then return (a.amount or -1)>(b.amount or -1) end
        return a.spellID<b.spellID
    end)
    return rows
end

function Lab:Compare(runs, metric)
    runs, metric = Table(runs), metric == "healing" and "healing" or "damage"
    local groups = {}
    for i = 1, math.min(#(runs or {}), MAX_RUNS) do
        local run=Table(runs[i]); local sample=run and Table(run.talentSample)
        local spec=sample and PlainNumber(sample.specID,100000)
        local game=sample and PlainString(sample.gameBuild)
        local map=sample and PlainNumber(sample.mapID,1000000)
        local level=sample and PlainNumber(sample.level,1000)
        local buildKey=sample and PlainString(sample.buildKey)
        local elapsed=sample and PlainNumber(sample.duration,86400)
        if sample and JP.SafeOptionalBoolean(sample.complete)==true and JP.SafeOptionalBoolean(sample.mixed)~=true
            and spec and game and #game<100 and map and level and buildKey and #buildKey<8192 and elapsed and elapsed>0 then
            local key = table.concat({spec, game, map, level, buildKey}, "|")
            local g = groups[key]
            if not g then g={specID=spec,gameBuild=game,mapID=map,level=level,buildKey=buildKey,
                buildName=PlainString(sample.buildName),rows={},duration=0,runs=0,firstIndex=i}; groups[key]=g end
            if elapsed>0 then
                g.runs=g.runs+1; g.duration=g.duration+elapsed
                for _, row in ipairs(self:Rows(sample, metric)) do g.rows[row.spellID]=(g.rows[row.spellID] or 0)+row.amount end
            end
        end
    end
    local out={metric=metric,builds={}}
    for _, g in pairs(groups) do
        local rows={}
        for spellID, amount in pairs(g.rows) do rows[#rows+1]={spellID=tonumber(spellID),amount=amount,rate=amount/g.duration} end
        table.sort(rows,function(a,b)return a.amount>b.amount end); g.rows=rows; out.builds[#out.builds+1]=g
    end
    table.sort(out.builds,function(a,b)return a.firstIndex<b.firstIndex end)
    return out
end

JP:RegisterModule("TalentLab", Lab)

-- Exposure-weighted shares: only keys where this exact talent/rank was selected.
-- Missing attribution is never treated as zero; these are not causal DPS gains.
function Lab:HistoricalShares(runs, metric, specID, gameBuild, includePartial)
    runs = Table(runs) or {}
    local groups, partialGroups = {}, {}
    for i = 1, math.min(#(runs or {}), MAX_RUNS) do
        local run = Table(runs[i])
        local sample = run and Table(run.talentSample)
        local total = sample and PlainNumber(metric == "healing" and sample.overallHealing or sample.overallDamage)
        local complete = sample and JP.SafeOptionalBoolean(sample.complete) == true
        local partialOK = false
        if includePartial and sample and not complete and total and total > 0 then
            local sum = 0
            for _, row in ipairs(self:Rows(sample, metric)) do sum = sum + row.amount end
            partialOK = math.abs(sum-total) <= math.max(1,total*.00001)
        end
        if sample and PlainNumber(sample.specID) == specID and PlainString(sample.gameBuild) == gameBuild
            and (complete or partialOK)
            and JP.SafeOptionalBoolean(sample.mixed) == false and total and total > 0 then
            local destination = complete and groups or partialGroups
            for _, row in ipairs(self:TalentRows(sample, metric)) do
                if row.amount ~= nil then
                    local key = row.spellID .. ":" .. row.rank
                    local g = destination[key] or {amount=0,total=0,runs=0,spellID=row.spellID,rank=row.rank,partial=not complete}
                    g.amount = g.amount + row.amount; g.total = g.total + total; g.runs = g.runs + 1
                    g.percent = g.amount / g.total * 100
                    destination[key] = g
                end
            end
        end
    end
    for key, group in pairs(partialGroups) do if not groups[key] then groups[key] = group end end
    return groups
end
