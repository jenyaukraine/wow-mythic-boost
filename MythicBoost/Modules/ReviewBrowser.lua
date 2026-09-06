local _, JP = ...
local UI, L, C = JP.UI, JP.L, JP.UI.colors
local Browser = {rows={}, offset=0}
JP.ReviewBrowser = Browser
local TOP, HEIGHT, MAX_ROWS = 170, 44, 32

local function Origin(record)
    return record.origin == "mine" and L("Мой отзыв")
        or record.origin == "direct" and L("Получено от автора")
        or L("Переслано; автор не подтверждён")
end
local function Vote(record)
    return record.vote == 1 and L("Лайк") or record.vote == -1 and L("Дизлайк") or L("Комментарий")
end
local function RowTooltip(row)
    local r = row.record
    if not r then return end
    UI.Tooltip(row, r.target, (L("Автор: %s")):format(r.author), Vote(r),
        r.text ~= "" and r.text or L("Без комментария"), Origin(r),
        date("%d.%m.%Y %H:%M",r.stamp),
        JP.RunStats and JP.RunStats:Text(r.stats,true),
        r.via and (L("Источник: %s")):format(r.via),
        L("Это мнения игроков, не автоматическая оценка."))
end
local function MakeRow(self)
    local row = UI.Panel(self.page, C.row, C.hudEdge)
    row:SetHeight(HEIGHT-4); row:EnableMouse(true)
    row.player = UI.Text(row,"GameFontHighlightSmall","",C.accent)
    row.player:SetPoint("TOPLEFT",10,-5); row.player:SetJustifyH("LEFT"); row.player:SetWordWrap(false)
    row.author = UI.Text(row,"GameFontHighlightSmall","",C.muted)
    row.author:SetPoint("TOPRIGHT",-10,-23)
    row.author:SetJustifyH("RIGHT"); row.author:SetWordWrap(false)
    row.vote = UI.Text(row,"GameFontNormalSmall","",C.text)
    row.vote:SetPoint("TOPRIGHT",-10,-5); row.vote:SetJustifyH("RIGHT")
    row.vote:SetWidth(184); row.vote:SetWordWrap(false)
    row.origin = UI.Text(row,"GameFontHighlightSmall","",C.muted)
    row.origin:SetPoint("TOPRIGHT",-206,-5); row.origin:SetJustifyH("RIGHT")
    row.origin:SetWidth(230); row.origin:SetWordWrap(false)
    row.text = UI.Text(row,"GameFontHighlightSmall","",C.text)
    row.text:SetPoint("TOPLEFT",10,-23)
    row.text:SetJustifyH("LEFT"); row.text:SetWordWrap(false)
    row.stats = UI.Text(row,"GameFontHighlightSmall","",C.amber)
    row.stats:SetPoint("TOPLEFT",10,-41); row.stats:SetPoint("TOPRIGHT",-10,-41)
    row.stats:SetJustifyH("LEFT"); row.stats:SetWordWrap(false)
    row:SetScript("OnEnter",RowTooltip); row:SetScript("OnLeave",GameTooltip_Hide)
    UI.BindScrollWheel(row,self.scrollBar,nil,function() return self.offset end)
    return row
end

function Browser:Build(_, page)
    self.page=page
    local title=UI.Text(page,"GameFontNormalLarge",L("БАЗА ОТЗЫВОВ"),C.accent)
    title:SetPoint("TOPLEFT",16,-16)
    local refresh=UI.Button(page,L("Обновить"),120,26)
    refresh:SetPoint("TOPRIGHT",-16,-12)
    refresh:SetScript("OnClick",function() self:Refresh() end)
    self.count=UI.Text(page,"GameFontHighlightSmall","",C.text)
    self.count:SetPoint("TOPLEFT",16,-48); self.count:SetPoint("TOPRIGHT",-16,-48)
    self.count:SetJustifyH("LEFT"); self.count:SetWordWrap(false)
    self.sync=UI.Text(page,"GameFontHighlightSmall","",C.muted)
    self.sync:SetPoint("TOPLEFT",16,-70); self.sync:SetPoint("TOPRIGHT",-16,-70)
    self.sync:SetJustifyH("LEFT"); self.sync:SetWordWrap(false)
    self.received=UI.Text(page,"GameFontHighlightSmall","",C.muted)
    self.received:SetPoint("TOPLEFT",16,-90)
    local hint=UI.Text(page,"GameFontHighlightSmall",L("Поиск: игрок, автор или текст"),C.muted)
    hint:SetPoint("TOPLEFT",16,-119)
    self.search=UI.NumberBox(page,330,26)
    self.search.frame:SetPoint("TOPLEFT",240,-112)
    self.search:SetNumeric(false); self.search:SetMaxLetters(100); self.search:SetJustifyH("LEFT")
    self.search:SetScript("OnTextChanged",function() self.offset=0; self:Refresh() end)
    self.found=UI.Text(page,"GameFontHighlightSmall","",C.muted)
    self.found:SetPoint("LEFT",self.search.frame,"RIGHT",14,0)
    self.note=UI.Text(page,"GameFontHighlightSmall",L("Хранение: до 1000 записей, 90 дней. Наведи на строку, чтобы прочитать отзыв целиком."),C.faint)
    self.note:SetPoint("TOPLEFT",16,-148)
    self.scrollBar=UI.ScrollBar(page)
    self.scrollBar:SetPoint("TOPRIGHT",-6,-TOP); self.scrollBar:SetPoint("BOTTOMRIGHT",-6,12)
    self.scrollBar:SetScript("OnValueChanged",function(_,value)
        local offset=math.floor(value+.5)
        if offset~=self.offset then self.offset=offset; self:Render() end
    end)
    UI.BindScrollWheel(page,self.scrollBar,nil,function() return self.offset end)
    self.empty=UI.Text(page,"GameFontHighlight","",C.muted)
    self.empty:SetPoint("TOPLEFT",30,-TOP-40); self.empty:SetPoint("TOPRIGHT",-30,-TOP-40)
    self.empty:SetJustifyH("CENTER"); self.empty:SetSpacing(6)
    page:SetScript("OnShow",function() self.elapsed=0; self:Refresh() end)
    page:HookScript("OnSizeChanged",function() self:Render() end)
    -- Runs only while the page is visible. No permanent ticker, growing event
    -- subscriptions or frame creation on each refresh.
    page:SetScript("OnUpdate",function(_,elapsed)
        self.elapsed=(self.elapsed or 0)+elapsed
        if self.elapsed<1 then return end
        self.elapsed=0
        if self.revision~=JP.Reviews.revision then self:Refresh() else self:Status() end
    end)
    page:SetScript("OnHide",function()
        self.entries={}; self.revision=nil
        for _,row in ipairs(self.rows) do row.record=nil; row:Hide() end
        GameTooltip_Hide()
    end)
end

function Browser:Status()
    self.sync:SetText(JP.Reviews:SyncStatus())
    local received=JP.Reviews.lastReceived
    self.received:SetText((L("Последний новый отзыв от группы в этой сессии: %s")):format(
        received and date("%d.%m.%Y %H:%M",received) or L("ещё не получен")))
end

function Browser:Refresh()
    if not self.page or not self.page:IsShown() then return end
    local entries,stats=JP.Reviews:Database(self.search:GetText())
    self.entries,self.stats,self.revision=entries,stats,JP.Reviews.revision
    self.count:SetText((L("Отзывов: %d   Мои: %d   От авторов: %d   Пересланные: %d   Метки удаления: %d")):format(
        stats.total,stats.mine,stats.direct,stats.forwarded,stats.deleted))
    self.found:SetText((L("Найдено: %d")):format(#entries))
    self:Status(); self:Render()
end

function Browser:Render()
    if not self.page or not self.entries or self.rendering then return end
    self.rendering=true
    local height=JP.RunStats and 62 or HEIGHT
    local visible=math.max(0,math.min(MAX_ROWS,math.floor((self.page:GetHeight()-TOP-12)/height)))
    local maximum=math.max(0,#self.entries-visible)
    self.offset=math.max(0,math.min(self.offset,maximum))
    self.scrollBar:SetMinMaxValues(0,maximum); self.scrollBar:SetValue(self.offset)
    self.scrollBar:SetShown(maximum>0)
    for i=1,visible do
        local r=self.entries[self.offset+i]
        local row=self.rows[i]
        if r then
            if not row then row=MakeRow(self); self.rows[i]=row end
            row.record=r; row:ClearAllPoints()
            row:SetHeight(height-4)
            row:SetPoint("TOPLEFT",12,-TOP-(i-1)*height); row:SetPoint("TOPRIGHT",-18,-TOP-(i-1)*height)
            local width = self.page:GetWidth()-30
            local authorWidth = math.min(290, math.max(180, width*.3))
            row.player:SetWidth(math.max(80,width-456))
            row.author:SetWidth(authorWidth)
            row.text:SetWidth(math.max(80,width-authorWidth-36))
            row.player:SetText(r.target); row.author:SetText((L("Автор: %s")):format(r.author))
            row.vote:SetText(Vote(r).."   "..date("%d.%m %H:%M",r.stamp))
            row.vote:SetTextColor(UI.Unpack(r.vote==1 and C.green or r.vote==-1 and C.red or C.text))
            row.origin:SetText(Origin(r)); row.text:SetText(r.text~="" and r.text or L("Без комментария"))
            row.stats:SetText(JP.RunStats and JP.RunStats:Text(r.stats) or "")
            row:Show()
        elseif row then row.record=nil; row:Hide() end
    end
    for i=visible+1,#self.rows do self.rows[i].record=nil; self.rows[i]:Hide() end
    self.empty:SetText(self.stats and self.stats.total==0
        and (L("База отзывов пока пуста.") .. "\n"
            .. L("После завершённого ключа сохрани отзыв через «Напарники» — «Оценить последний ключ».") .. "\n"
            .. L("Чужие отзывы появятся после обмена с участниками группы, у которых установлен MythicBoost."))
        or L("По этому запросу отзывов нет."))
    self.empty:SetShown(#self.entries==0)
    self.rendering=nil
end
