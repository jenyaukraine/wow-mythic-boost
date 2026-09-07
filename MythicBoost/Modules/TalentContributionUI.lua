local _, JP = ...
local Lab, UI, L = JP.TalentLab, JP.UI, JP.L

local function Compact(n)
    if n>=1000000 then return ("%.2fM"):format(n/1000000) end
    if n>=1000 then return ("%.1fk"):format(n/1000) end
    return ("%.0f"):format(n)
end

local function Spell(id)
    local ok,info=pcall(C_Spell.GetSpellInfo,id)
    info=ok and JP.SafeTable(info)
    return info and JP.SafeString(info.name) or (L("ID заклинания %d")):format(id),info and info.iconID
end

function Lab:ContributionText(data,metric)
    if not data or data.amount==nil or not data.total or data.total<=0 then return L("Нет привязанных данных") end
    local lines={L("Доля = сумма связанных заклинаний / общий результат тех же замеров x 100%."),
        ("%s / %s x 100%% = %.2f%%"):format(Compact(data.amount),Compact(data.total),data.amount/data.total*100)}
    if data.runs then
        lines[#lines+1]=(L("Ключей: %d | Ранг: %d")):format(data.runs,data.rank)
        lines[#lines+1]=(L("Доля по прохождениям: %.2f%% - %.2f%%")):format(data.min,data.max)
    end
    lines[#lines+1]=L("Источники")..":"
    local sources={}
    for id,amount in pairs(data.sources or {}) do sources[#sources+1]={id=id,amount=amount} end
    table.sort(sources,function(a,b) return a.amount>b.amount or a.amount==b.amount and a.id<b.id end)
    for _,source in ipairs(sources) do
        lines[#lines+1]=("%s [%d]: %s / %s = %.2f%%"):format(Spell(source.id),source.id,
            Compact(source.amount),Compact(data.total),source.amount/data.total*100)
    end
    if data.partial then lines[#lines+1]=L("Неполный замер: показана только записанная часть вклада.") end
    lines[#lines+1]=L("Пассивное усиление без отдельного источника: вклад не выделен.")
    return table.concat(lines,"\n")
end

function Lab:RenderContribution(runs)
    self:StyleButtons(); self.comparisonContexts=nil; self.sampleRuns=nil
    local selected=self.contribution or {}
    local shares=self:HistoricalShares(runs,self.metric,selected.specID,selected.gameBuild,true)
    local group=selected.spellID and shares[selected.spellID..":"..selected.rank]
    local name,icon
    if selected.spellID then name,icon=Spell(selected.spellID) end
    self.uiSubtitle:SetText(name or L("Талант"))
    self.uiDate:SetText(group and (L("Ключей: %d | Ранг: %d")):format(group.runs,group.rank) or L("Нет замеров"))
    self.uiBuild:SetText(L("Доля таланта от общего"))
    self.keyPicker:SetText(L("Все замеры")); self.keyPicker:SetEnabled(false)
    self.keyPickerMenu:Hide(); self.allTalentsButton:Hide()
    self.sourceHeader:SetText(L("Прохождение")); self.amountHeader:SetText(L("Талант"))
    self.rateHeader:SetText(L("Общий итог")); self.shareHeader:SetText(L("Доля"))
    local records=group and group.samples or {}
    table.sort(records,function(a,b) return (a.stamp or 0)>(b.stamp or 0) end)
    while #self.rows<#records do self.rows[#self.rows+1]=self.createRow(#self.rows+1) end
    self.rowCanvas:SetSize(568,math.max(270,#records*48)); self.rowScroll:SetVerticalScroll(0)
    for i,row in ipairs(self.rows) do
        local record=records[i]; row:SetShown(record~=nil); row.comparisonDetail=nil; row.meta:Hide()
        if record then
            row:SetHeight(44); row:ClearAllPoints(); row:SetPoint("TOPLEFT",0,-(i-1)*48)
            row.spellID=selected.spellID; row.spellName=name; row.kind=nil
            row.icon:SetTexture(icon or "Interface/Icons/INV_Misc_QuestionMark")
            row.nameText:SetText(("+%d %s"):format(record.level or 0,record.mapName or L("Подземелье")))
            row.amount:SetWidth(86); row.amount:SetText(Compact(record.amount)); row.amount:SetTextColor(.9,.95,1,1)
            row.rate:SetText(Compact(record.total))
            row.share:SetText((record.partial and "~" or "")..("%.1f%%"):format(record.percent))
            row.share:SetTextColor(record.partial and 1 or .2,record.partial and .72 or .95,record.partial and .25 or .45,1)
            row.meta:Show(); row.meta:SetText((record.stamp and date("%d.%m %H:%M",record.stamp) or "—")
                .." | "..L("Наведи: заклинания и расчёт доли."))
            row.comparisonDetail=self:ContributionText(record,self.metric)
        else row.spellID=nil end
    end
    self.empty:SetText(group and (L("Итого: %s / %s = %.2f%%")):format(Compact(group.amount),Compact(group.total),group.percent)
        or L("Нет привязанных данных"))
    self.coverage:SetText(group and (L("Доля по прохождениям: %.2f%% - %.2f%%")):format(group.min,group.max) or "")
    self.compare:SetText(L("Доля = сумма связанных заклинаний / общий результат тех же замеров x 100%.")
        .."\n"..L("Пассивное усиление без отдельного источника: вклад не выделен."))
end

function Lab:ShowContribution(spellID,rank,specID,gameBuild,metric)
    if JP.SafeOptionalBoolean(InCombatLockdown())~=false then return end
    self:CreateUI(); self.view="contribution"
    self.contribution={spellID=spellID,rank=rank,specID=specID,gameBuild=gameBuild}
    self.metric=metric=="damage" and "damage" or "healing"
    self:Show()
    local owner=PlayerSpellsFrame
    if owner and owner:IsShown() then self.uiFrame:SetFrameLevel(owner:GetFrameLevel()+20) end
end
