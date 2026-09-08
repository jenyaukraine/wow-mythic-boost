local _, JP = ...
local Lab, Points, UI, L = JP.TalentLab, JP.TalentPointValue, JP.UI, JP.L

local Call = JP.SafeCall
local function Spell(id)
    local info=C_Spell and JP.SafeTable(Call(C_Spell.GetSpellInfo,id))
    return info and JP.SafeString(info.name) or tostring(id),info and info.iconID
end

-- Presentation shared by the tree badge and the ranked table.
function Points:Presentation(context,spellID,metric,share)
    local data=self:Evaluate(context,spellID,metric)
    if data then
        return {data=data,badge=("~%.1f%%"):format(data.percent),detail=self:Describe(data,context,metric),
            r=.35,g=.8,b=1}
    end
    local reason=self:UnknownReason(spellID,context,metric)
    if share then
        return {share=share,badge=("=%.1f%%"):format(share.percent),
            detail=L("Это доля отдельного источника. Цена снятого очка и ценность замены не измерены.")
                .."\n"..Lab:ContributionText(share,metric).."\n"..reason,r=.7,g=.75,b=.8}
    end
    return {badge="?",detail=reason,r=.6,g=.65,b=.7}
end

function Lab:ShowPoints(metric)
    if JP.SafeOptionalBoolean(InCombatLockdown())~=false then return end
    self:CreateUI(); self.view="points"; self.metric=metric=="damage" and "damage" or "healing"; self:Show()
end

function Lab:RenderPoints(runs)
    if JP.SafeOptionalBoolean(InCombatLockdown())~=false then self:Hide(); return end
    self:StyleButtons(); self.keyPickerMenu:Hide(); self.comparisonContexts=nil; self.sampleRuns=nil
    local current=self.CurrentBuild and self.CurrentBuild()
    local spec=current and current.specID or self.SpecID()
    local version,build=GetBuildInfo()
    version,build=JP.SafeString(version),JP.SafeString(build)
    local game=version and build and version..":"..build
    local context=Points:Context(runs,self.metric,spec,game,current)
    self.pointContext=context
    local filters={L("Вложенные очки"),L("Кандидаты"),L("Без оценки очка")}
    local filter=self.pointFilter or 1
    self.allTalentsButton:Show(); self.allTalentsButton:SetText(filters[filter])
    self.keyPicker:SetText(Points.scope=="key" and L("Карта и уровень") or L("Все ключи сборки")); self.keyPicker:SetEnabled(true)
    self.uiSubtitle:SetText(context and (context.scope=="build" and L("Все ключи этой сборки")
        or (L("База: +%d %s")):format(context.level,context.run.mapName or L("Подземелье"))) or L("Нет замеров"))
    self.uiDate:SetText(context and ((L("Замеров: %d")):format(#context.records).." | "..date("%d.%m %H:%M",context.stamp)) or "")
    self.uiBuild:SetWidth(302)
    self.uiBuild:SetText(context and (JP.SafeString(context.sample.buildName) or L("Сборка без названия")) or "")
    self.sourceHeader:SetText(filters[filter]); self.amountHeader:SetText(L("Очко"))
    self.rateHeader:SetText(L("Доля")); self.shareHeader:SetText(L("Оценка"))
    local rows,known,unknown={},0,0
    local sample=context and context.sample
    -- Shares use the same reference cohort as the point model, not all builds.
    local cohort={}; for _,record in ipairs(context and context.records or {}) do cohort[#cohort+1]=record.run end
    local shares=sample and self:HistoricalShares(cohort,self.metric,sample.specID,sample.gameBuild,true) or {}
    local talents={}
    for nodeID,entry in pairs(sample and sample.selected or {}) do
        if entry.spellID then talents[entry.spellID]={nodeID=nodeID,entryID=entry.entryID,rank=entry.rank} end
    end
    for id in pairs((JP.TalentPointModels[spec] or {})) do
        if not talents[id] then talents[id]={rank=0} end
    end
    -- Find native nodes for modeled alternatives too. Availability is displayed,
    -- never used to mutate the tree or imply a legal automatic replacement.
    if current and C_Traits then
        local config=JP.SafeTable(Call(C_Traits.GetConfigInfo,current.configID))
        local visited=0
        for _,treeID in ipairs(config and config.treeIDs or {}) do
            for _,nodeID in ipairs(JP.SafeTable(Call(C_Traits.GetTreeNodes,treeID)) or {}) do
                visited=visited+1; if visited>1024 then break end
                local node=JP.SafeTable(Call(C_Traits.GetNodeInfo,current.configID,nodeID))
                for _,entryID in ipairs(node and node.entryIDs or {}) do
                    local entry=JP.SafeTable(Call(C_Traits.GetEntryInfo,current.configID,entryID))
                    local def=entry and JP.SafeTable(Call(C_Traits.GetDefinitionInfo,entry.definitionID))
                    local t=def and talents[def.spellID]
                    if t then t.nodeID=nodeID; t.entryID=entryID; t.node=node end
                end
            end
        end
    end
    for id,t in pairs(talents) do
        local share=shares[id..":"..math.max(1,t.rank)]
        local p=Points:Presentation(context,id,self.metric,share)
        if p.data then known=known+1 else unknown=unknown+1 end
        local include=filter==3 and not p.data or p.data and ((filter==1 and t.rank>0) or (filter==2 and t.rank==0))
        if include then
            local name,icon=Spell(id)
            rows[#rows+1]={spellID=id,name=name,icon=icon,p=p,share=share,rank=t.rank,
                status=Points:Availability(current and current.configID,t.node,t.entryID,context and context.current,t.rank>0)}
        end
    end
    table.sort(rows,function(a,b)
        local av=a.p.data and a.p.data.percent or -1; local bv=b.p.data and b.p.data.percent or -1
        if av~=bv then return av>bv end
        return a.spellID<b.spellID
    end)
    while #self.rows<#rows do self.rows[#self.rows+1]=self.createRow(#self.rows+1) end
    self.rowCanvas:SetSize(568,math.max(270,#rows*48)); self.rowScroll:SetVerticalScroll(0)
    for i,row in ipairs(self.rows) do
        local data=rows[i]; row:SetShown(data~=nil); row.meta:Hide(); row.comparisonDetail=nil
        if data then
            local p=data.p
            row:SetHeight(44); row:ClearAllPoints(); row:SetPoint("TOPLEFT",0,-(i-1)*48)
            row.spellID=data.spellID; row.spellName=data.name; row.kind=nil
            row.nameText:SetText(data.name); row.icon:SetTexture(data.icon or "Interface/Icons/INV_Misc_QuestionMark")
            row.amount:SetWidth(86); row.amount:SetText(data.rank>0 and L("Снять 1") or L("Вложить 1"))
            row.amount:SetTextColor(.9,.95,1,1)
            local affectedShare=p.data and p.data.amount/p.data.total*100 or (data.share and data.share.percent)
            row.rate:SetText(affectedShare and ("%.1f%%"):format(affectedShare) or "—")
            row.share:SetText(p.data and p.badge or "?"); row.share:SetTextColor(p.r,p.g,p.b,1)
            row.meta:Show(); row.meta:SetText(data.status..(p.data and p.data.limited and (" | "..L("Часть эффекта")) or ""))
            row.comparisonDetail=p.detail.."\n"..data.status
        else row.spellID=nil end
    end
    self.empty:SetText(context and L("Выше в списке: больше расчётный эффект одного очка. Кнопка справа переключает вложенные очки, кандидатов и таланты без оценки.")
        or L("Нужен сохранённый замер с заклинаниями и неизменной сборкой."))
    self.coverage:SetText(context and (L("Замеров сборки: %d | Всего ключей в истории: %d")):format(#context.records,context.historyCount)
        or (L("Моделей с данными: %d | Без оценки: %d")):format(known,unknown))
    self.compare:SetText(context and not context.current
        and L("Расчёт относится к сохранённой сборке; текущая сборка отличается или не проверена.")
        or L("~ Оценка постоянного усиления. Наведи для формулы. Контроль, защита и зависимости дерева требуют отдельной проверки."))
end
