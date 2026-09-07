local _, JP = ...
local Lab = JP.TalentLab
local MAX_RUNS, MAX_TALENTS = 30, 256

local function Number(value, maximum)
    value=JP.SafeNumber(value)
    if value and value==value and value>=0 and value<=(maximum or 1e15) then return value end
end
local function ID(value)
    value=Number(value,100000000)
    if value and value>0 and value%1==0 then return value end
end
local function Text(value, maximum)
    value=JP.SafeString(value)
    if value and #value<=(maximum or 8192) then return value end
end
local function Ranks(sample)
    local selected=JP.SafeTable(sample.selected)
    if not selected then return end
    local ranks,nodes,unknown,count={},{},{},0
    local mappings=JP.TalentSources and JP.TalentSources[sample.specID] or {}
    for nodeID,raw in pairs(selected) do
        count=count+1; if count>MAX_TALENTS then return end
        local entry=JP.SafeTable(raw)
        local spell=entry and ID(entry.spellID)
        local rank=entry and ID(entry.rank)
        if not ID(nodeID) or not entry or not ID(entry.entryID) or not rank or rank>1000 then return end
        if spell then
            local mapping=mappings[spell]
            spell=mapping and ID(mapping.family) or spell
            ranks[spell]=math.max(ranks[spell] or 0,rank)
            nodes[spell]=nodes[spell] or {}; nodes[spell][nodeID]=true
        else
            -- Hero selectors may have no spell. Do not reject the entire
            -- build, or treat an unresolved node as a known absent talent.
            unknown[nodeID]=true
        end
    end
    if count>0 and next(ranks) then return ranks,nodes,unknown end
end
local function Roster(run)
    local members=JP.SafeTable(run.members)
    if not members or #members==0 or #members>5 then return end
    local names={}
    for _,raw in ipairs(members) do
        local name=Text(raw,160)
        if not name then return end
        names[#names+1]=name:lower()
    end
    table.sort(names)
    return table.concat(names,"|")
end

-- Descriptive cohort comparison only. A run, not a spell or a pair of runs,
-- is one observation. No source mapping, significance claim or causal score.
local function Summary(observations)
    local result={runs=#observations,partial=0,total=0,duration=0}
    if result.runs==0 then return result end
    local sum=0
    for _,observation in ipairs(observations) do
        local rate=observation.rate
        sum=sum+rate
        result.min=math.min(result.min or rate,rate)
        result.max=math.max(result.max or rate,rate)
        result.total=result.total+observation.total
        result.duration=result.duration+observation.duration
        if observation.partial then result.partial=result.partial+1 end
    end
    result.mean=sum/result.runs
    -- A single observation has no observed between-run spread.
    result.hasSpread=result.runs>1
    return result
end
local function OtherChanges(a,b,focus)
    local count=0
    for id,rank in pairs(a) do
        if id~=focus and rank~=(b[id] or 0) then count=count+1 end
    end
    for id in pairs(b) do if id~=focus and not a[id] then count=count+1 end end
    return count
end

function Lab:CompareTalents(runs,metric)
    runs=JP.SafeTable(runs) or {}
    metric=metric=="damage" and "damage" or "healing"
    local result={contexts={},excluded={mixed=0,invalid=0},metric=metric}
    local contexts,seen={},{ }
    for index=1,math.min(#runs,MAX_RUNS) do
        local run=JP.SafeTable(runs[index])
        local sample=run and JP.SafeTable(run.talentSample)
        if sample then
            sample=self:ResolveSample(sample,runs)
            local spec,map,level=ID(sample.specID),ID(sample.mapID),ID(sample.level)
            local game,key=Text(sample.gameBuild,128),Text(sample.buildKey)
            local duration=Number(sample.duration,86400)
            local total=Number(metric=="healing" and sample.overallHealing or sample.overallDamage)
            local rate=duration and duration>0 and total and Number(total/duration)
            local ranks,nodes,unknown=Ranks(sample)
            local mixed=JP.SafeOptionalBoolean(sample.mixed)
            if mixed==true then result.excluded.mixed=result.excluded.mixed+1
            elseif not spec or not map or not level or not game or not key or not ranks
                or rate==nil or mixed~=false then
                result.excluded.invalid=result.excluded.invalid+1
            else
                local contextKey=table.concat({spec,game,map,level},"|")
                local stamp=Number(run.completedAt,9999999999) or 0
                local fingerprint=table.concat({contextKey,stamp,key,duration,total},"|")
                if not seen[fingerprint] then
                    seen[fingerprint]=true
                    local context=contexts[contextKey]
                    if not context then
                        context={key=contextKey,specID=spec,mapID=map,level=level,gameBuild=game,
                            mapName=Text(run.mapName,256),observations={},talents={},talentCount=0,at=stamp}
                        contexts[contextKey]=context; result.contexts[#result.contexts+1]=context
                    end
                    context.at=math.max(context.at,stamp)
                    context.observations[#context.observations+1]={ranks=ranks,unknown=unknown,rate=rate,
                        total=total,duration=duration,partial=JP.SafeOptionalBoolean(sample.complete)~=true,
                        buildKey=key,roster=Roster(run)}
                    for spell,rank in pairs(ranks) do
                        local talentKey=spell..":"..rank
                        if not context.talents[talentKey] and context.talentCount<MAX_TALENTS then
                            context.talents[talentKey]={spellID=spell,rank=rank,nodes={}}
                            context.talentCount=context.talentCount+1
                        end
                        local talent=context.talents[talentKey]
                        if talent then for node in pairs(nodes[spell]) do talent.nodes[node]=true end end
                    end
                end
            end
        end
    end
    for _,context in ipairs(result.contexts) do
        context.rows={}; context.pairs=0
        -- Compare each pair of builds once, not again for every talent row.
        local differences={}
        for _,observation in ipairs(context.observations) do differences[observation]={} end
        for i,a in ipairs(context.observations) do
            for j=i+1,#context.observations do
                local b=context.observations[j]
                local count=OtherChanges(a.ranks,b.ranks)
                differences[a][b]=count; differences[b][a]=count
            end
        end
        for _,talent in pairs(context.talents) do
            local with,without={},{}
            for _,observation in ipairs(context.observations) do
                local rank=observation.ranks[talent.spellID] or 0
                if rank==talent.rank then with[#with+1]=observation
                elseif rank==0 then
                    local absent=true
                    for node in pairs(talent.nodes) do if observation.unknown[node] then absent=false end end
                    if absent then without[#without+1]=observation end
                end
            end
            talent.with=Summary(with); talent.without=Summary(without)
            talent.comparable=#with>0 and #without>0
            talent.smallSample=#with<3 or #without<3
            talent.partial=talent.with.partial+talent.without.partial>0
            if talent.comparable then
                context.pairs=context.pairs+1
                talent.delta=talent.with.mean-talent.without.mean
                if talent.without.mean>0 then talent.percent=talent.delta/talent.without.mean*100 end
                talent.otherChangesMin,talent.otherChangesMax=MAX_TALENTS*2,0
                for _,a in ipairs(with) do
                    for _,b in ipairs(without) do
                        local changed=differences[a][b]-1 -- Exclude the focus talent's presence difference.
                        talent.otherChangesMin=math.min(talent.otherChangesMin,changed)
                        talent.otherChangesMax=math.max(talent.otherChangesMax,changed)
                        if not a.roster or not b.roster then talent.rosterUnknown=true
                        elseif a.roster~=b.roster then talent.rosterChanged=true end
                    end
                end
            end
            context.rows[#context.rows+1]=talent
            talent.nodes=nil
        end
        table.sort(context.rows,function(a,b)
            if a.comparable~=b.comparable then return a.comparable end
            if a.spellID~=b.spellID then return a.spellID<b.spellID end
            return a.rank<b.rank
        end)
        context.runs=#context.observations
        context.partial=0
        for _,o in ipairs(context.observations) do if o.partial then context.partial=context.partial+1 end end
        context.observations=nil; context.talents=nil
    end
    table.sort(result.contexts,function(a,b)
        if (a.pairs>0)~=(b.pairs>0) then return a.pairs>0 end
        if a.at~=b.at then return a.at>b.at end
        return a.key<b.key
    end)
    return result
end
