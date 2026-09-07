local _, JP = ...
local Lab, L = JP.TalentLab, JP.L
local Points = {}
JP.TalentPointValue = Points

local function Number(v)
    v=JP.SafeNumber(v)
    return type(v)=="number" and v==v and v>=0 and v<1e15 and v or nil
end
local function Call(fn,...)
    if type(fn)~="function" then return end
    local ok,value=pcall(fn,...); if ok then return value end
end
local function Rank(sample,spellID)
    local count,unknown=0,false
    for _,raw in pairs(JP.SafeTable(sample.selected) or {}) do
        count=count+1; if count>256 then return end
        local entry=JP.SafeTable(raw)
        if not entry then return end
        if Number(entry.spellID)==spellID then return Number(entry.rank) end
        if not Number(entry.spellID) then unknown=true end
    end
    if not unknown then return 0 end
end

-- One unchanged build, same map and key level. Never copy a whole-build HPS
-- difference to its individual talents. Prefer the applied build; if it has
-- no recorded runs, present the last recorded build explicitly as a reference.
function Points:Context(runs,metric,spec,gameBuild,current)
    local candidates,seen={},{}
    for i=1,math.min(#(JP.SafeTable(runs) or {}),30) do
        local run=JP.SafeTable(runs[i])
        local sample=run and JP.SafeTable(run.talentSample)
        if sample then sample=Lab:ResolveSample(sample,runs) end
        local total=sample and Number(metric=="damage" and sample.overallDamage or sample.overallHealing)
        local key=sample and JP.SafeString(sample.buildKey)
        local map=sample and Number(sample.mapID or run.mapID)
        local level=sample and Number(sample.level or run.level)
        local duration=sample and Number(sample.duration)
        local stamp=run and Number(run.completedAt or run.startedAt)
        local spells=sample and JP.SafeTable(sample.spells)
        spells=spells and JP.SafeTable(spells[metric])
        local sum,valid=0,spells~=nil
        local values,count={},0
        for id,raw in pairs(spells or {}) do
            local amount=Number(raw); count=count+1
            if not Number(id) or id%1~=0 or id<1 or not amount or count>256 then valid=false; break end
            values[id]=amount; sum=sum+amount
        end
        local complete=sample and JP.SafeOptionalBoolean(sample.complete)==true
        local selected=sample and JP.SafeTable(sample.selected)
        local selectedCount=0
        for _,raw in pairs(selected or {}) do
            selectedCount=selectedCount+1
            local e=JP.SafeTable(raw)
            if selectedCount>256 or not e or not Number(e.rank) then valid=false; break end
        end
        if sample and sample.specID==spec and sample.gameBuild==gameBuild and key and #key<8192
            and selected and map and level and stamp and duration and duration>0 and total and total>0 and valid
            and sum>0 and sum<=total+math.max(1,total*.00001)
            and (not complete or math.abs(sum-total)<=math.max(1,total*.00001))
            and JP.SafeOptionalBoolean(sample.mixed)==false then
            local fingerprint=table.concat({stamp,key,map,level,duration},"|")
            if not seen[fingerprint] then
                seen[fingerprint]=true
                candidates[#candidates+1]={sample=sample,run=run,stamp=stamp,total=total,spells=values,
                    complete=complete,map=map,level=level,key=key,duration=duration}
            end
        end
    end
    table.sort(candidates,function(a,b) return a.stamp>b.stamp end)
    local reference=candidates[1]
    if current then
        for _,record in ipairs(candidates) do
            if record.key==current.buildKey then reference=record; break end
        end
    end
    if not reference then return end
    local context={sample=reference.sample,run=reference.run,records={},total=0,duration=0,
        partial=false,stamp=reference.stamp,map=reference.map,level=reference.level,
        current=current and reference.key==current.buildKey or false}
    for _,record in ipairs(candidates) do
        if record.key==reference.key and record.map==reference.map and record.level==reference.level then
            context.records[#context.records+1]=record
            context.total=context.total+record.total; context.duration=context.duration+record.duration
            context.partial=context.partial or not record.complete
        end
    end
    return context
end

-- Returns a scenario for changing ONE rank of a verified constant multiplier.
-- Healing assumes unchanged spell use and effective/overheal proportion.
-- Each row owns its denominator: absent sources in partial records are unknown.
function Points:Evaluate(context,spellID,metric)
    if not context then return end
    local catalog=JP.TalentPointModels
    if not catalog or context.sample.gameBuild~=catalog.gameBuild then return end
    local models=catalog[context.sample.specID]
    local model=models and models[spellID]
    local sources=model and model[metric]
    if not sources then return end
    local rank=Rank(context.sample,spellID)
    if not rank or rank%1~=0 or rank>#model.ranks then return end
    local current=rank==0 and 0 or model.ranks[rank]
    local other=rank>0 and (rank==1 and 0 or model.ranks[rank-1]) or model.ranks[1]
    local factor=math.abs(other-current)/(1+current)
    local out={spellID=spellID,rank=rank,selected=rank>0,limited=model.limited,
        coefficient=current,other=other,factor=factor,amount=0,total=0,runs=0,
        sources={},samples={},partial=false}
    for _,record in ipairs(context.records) do
        local amount,known=0,record.complete
        for _,id in ipairs(sources) do
            local value=record.spells[id]
            if value~=nil then amount=amount+value; known=true end
        end
        if known then
            out.amount=out.amount+amount; out.total=out.total+record.total; out.runs=out.runs+1
            out.partial=out.partial or not record.complete
            local percent=amount*factor/record.total*100
            out.min=math.min(out.min or percent,percent); out.max=math.max(out.max or percent,percent)
            out.samples[#out.samples+1]={stamp=record.stamp,amount=amount,total=record.total,percent=percent}
            for _,id in ipairs(sources) do
                if record.spells[id]~=nil or record.complete then
                    out.sources[id]=(out.sources[id] or 0)+(record.spells[id] or 0)
                end
            end
        end
    end
    if out.runs==0 then return end
    out.percent=out.amount*factor/out.total*100
    return out
end

function Points:UnknownReason(spellID,context,metric)
    if not context then return L("Нужен сохранённый замер с заклинаниями и неизменной сборкой.") end
    if context.sample.gameBuild~=JP.TalentPointModels.gameBuild then
        return L("Коэффициенты для этой версии игры ещё не проверены.")
    end
    local model=(JP.TalentPointModels[context.sample.specID] or {})[spellID]
    local rank=Rank(context.sample,spellID)
    if model and (not rank or rank>#model.ranks) then
        return L("Нужны проверенные коэффициенты каждого ранга и список затронутых эффектов.")
    end
    if model and model[metric] then return L("Затронутые заклинания не записаны; отсутствие данных не означает ноль.") end
    if spellID==377796 then return L("Усиливает получаемое лечение: нужен разбор по получателям, общий HPS не подходит.") end
    if spellID==33873 then return L("Нужны проверенные коэффициенты каждого ранга и список затронутых эффектов.") end
    if spellID==158478 or spellID==207383 or spellID==392220 or spellID==231032 or spellID==383191
        or spellID==392256 or spellID==428731 or spellID==439882 or spellID==440119
        or spellID==439890 or spellID==1264649 or spellID==1270592 then
        return L("Нужны условия срабатывания: активные HoT, проки, критические исцеления или здоровье цели.")
    end
    return L("Отдельный источник или постоянный множитель не подтверждён. Полезность контроля, защиты и синергий по общему HPS/DPS не определяется.")
end

-- Read-only native tree facts, outside combat. No purchases/refunds, no secure
-- attributes, no guesses that a full build can buy a point immediately.
function Points:Availability(config,node,entryID,contextCurrent,selected)
    if not contextCurrent then return L("Сохранённая сборка") end
    if not node or not Number(node.ID) then return L("Путь не проверен") end
    if selected then
        if Number(node.ranksPurchased)==0 then return L("Выдано бесплатно") end
        if JP.SafeOptionalBoolean(Call(C_Traits.CanRefundRank,config,node.ID))==true then return L("Можно снять очко") end
        return L("Связано с другими очками")
    end
    if JP.SafeOptionalBoolean(node.isAvailable)==false or JP.SafeOptionalBoolean(node.meetsEdgeRequirements)==false
        or JP.SafeOptionalBoolean(node.subTreeActive)==false then return L("Сначала открой путь") end
    if JP.SafeOptionalBoolean(Call(C_Traits.CanPurchaseRank,config,node.ID,entryID))==true then return L("Можно вложить очко") end
    return L("Нужны очко и доступный путь")
end

function Points:Describe(data,context,metric)
    if not data then return "" end
    local lines={data.selected and L("Модель: потеря при снятии последнего очка.") or L("Модель: прибавка при вложении одного очка."),
        (L("Затронутые заклинания: %.2f%% от общего; множитель изменения: %.4f.")):format(data.amount/data.total*100,data.factor),
        ("%.0f x %.4f / %.0f x 100%% = ~%.2f%%"):format(data.amount,data.factor,data.total,data.percent),
        (L("Замеров: %d | Разброс оценки: %.2f%% - %.2f%%")):format(data.runs,data.min,data.max)}
    local ids={}; for id in pairs(data.sources) do ids[#ids+1]=id end; table.sort(ids)
    for _,id in ipairs(ids) do
        local info=C_Spell and JP.SafeTable(Call(C_Spell.GetSpellInfo,id))
        lines[#lines+1]=("%s [%d]: %.0f"):format(info and JP.SafeString(info.name) or tostring(id),id,data.sources[id])
    end
    if data.limited then lines[#lines+1]=L("Оценена только постоянная часть эффекта; дополнительные механики не включены.") end
    if data.partial then lines[#lines+1]=L("Неполный замер: показана только записанная часть вклада.") end
    lines[#lines+1]=metric=="healing" and L("Модель сохраняет частоту заклинаний и долю избыточного лечения. Реальный прирост может отличаться.")
        or L("Модель сохраняет частоту заклинаний, цели и остальные усиления.")
    lines[#lines+1]=L("Оценки разных талантов нельзя складывать: их эффекты могут усиливать одни и те же заклинания.")
    if not context.current then lines[#lines+1]=L("Расчёт относится к сохранённой сборке; текущая сборка отличается или не проверена.") end
    return table.concat(lines,"\n")
end
