local _,JP=...
local Market,UI,L=JP.AuctionMarket,JP.UI,JP.L
local C,WIDTH,ROWS,STEP=UI.colors,760,8,42
local function Label(parent,text,x,y,width,color)
    local t=UI.Text(parent,"GameFontHighlightSmall",text,color or C.text)
    t:SetPoint("TOPLEFT",x,y)
    t:SetJustifyH("LEFT")
    if width then t:SetWidth(width); t:SetWordWrap(false) end
    return t
end
local function Money(value)
    if not value then return "—" end
    return GetMoneyString and GetMoneyString(value,true) or ("%.2fg"):format(value/10000)
end
local function TipAvailable()
    return GameTooltip and (not GameTooltip.IsForbidden or not GameTooltip:IsForbidden())
end
local function HideTip(owner)
    if TipAvailable() and GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end
local function Count(value)
    return tostring(math.floor(value or 0)):reverse():gsub("(%d%d%d)","%1 "):reverse():gsub("^ ","")
end
function Market:UpdateScanProgress()
    if not self.scanProgress then return end
    local p,work,result=self.scanProgress,self.work,self.scanResult
    local active=work~=nil or result~=nil
    p:SetShown(active); self.heading:SetShown(not active)
    self.scanButton.label:SetText(work and L("Отмена") or L("Полный скан"))
    self.scanButton:SetEnabled(true)
    p:SetScript("OnUpdate",nil); p.pulse:Hide()
    if not active then return end
    local waiting=work and work.phase=="waiting"
    p.bar:SetStatusBarColor(unpack(result and (result.partial and C.amber or C.green) or C.accent))
    if waiting then
        p.title:SetText(L("Ожидание ответа сервера")); p.value:SetText(L("Получение данных…"))
        p.bar:SetValue(0); p.pulse:Show(); p.elapsed=0
        if self.frame:IsShown() then p:SetScript("OnUpdate",p.animate) end
    else
        local done=work and (work.index-work.pendingCount) or result.total
        local total=work and work.total or result.total
        local percent=total>0 and math.floor(done/total*100) or 0
        p.title:SetText(work and (work.phase=="loading" and L("Догрузка предметов") or L("Обработка лотов")) or L("Скан завершён"))
        p.value:SetText(("%d%%   %s / %s"):format(percent,Count(done),Count(total)))
        p.bar:SetValue(total>0 and done/total or 0)
    end
end
function Market:DrawGraph(row,key)
    local db=self:Database()
    local points,low,high={},nil,nil
    for _,snapshot in ipairs(db.snapshots) do
        local price=snapshot.prices[key]
        if price and snapshot.stamp<=self.snapshot.stamp then
            points[#points+1]={snapshot.stamp,price}; low=math.min(low or price,price); high=math.max(high or price,price)
        end
    end
    local start=points[1] and points[1][1] or 0
    local span=points[#points] and math.max(1,points[#points][1]-start) or 1
    for i,line in ipairs(row.lines) do
        local a,b=points[i],points[i+1]
        line:SetShown(a~=nil and b~=nil)
        if a and b then
            local range=math.max(1,high-low)
            line:SetStartPoint("BOTTOMLEFT",(a[1]-start)/span*108,4+(a[2]-low)/range*22)
            line:SetEndPoint("BOTTOMLEFT",(b[1]-start)/span*108,4+(b[2]-low)/range*22)
            line:SetColorTexture(unpack(b[2]<=a[2] and C.green or C.red))
        end
    end
    row.noGraph:SetShown(#points<2)
    row.noGraph:SetText(#points==1 and L("1 снимок") or "—")
end
function Market:Render()
    if not self.frame or not self.frame:IsShown() then return end
    local db=self:Database()
    if not db then self:SetStatus(L("Несовместимая версия истории цен")); return end
    local items=self.items or {}
    local offset=math.min(self.offset or 0,math.max(0,math.floor((#items-1)/ROWS)*ROWS)); self.offset=offset
    for i,row in ipairs(self.rows) do
        HideTip(row)
        local entry=items[offset+i]; row.entry=entry; row:SetShown(entry~=nil)
        if entry then
            row.icon:SetTexture(entry.info.icon)
            row.name:SetText(entry.info.name)
            row.signal:SetText(entry.signal and L("Сигнал: цена ниже на 10%+") or ("ID "..entry.info.itemKey.itemID))
            row.signal:SetTextColor(unpack(entry.signal and C.green or C.muted))
            row.price:SetText(Money(entry.price))
            row.change:SetText(entry.change and ("%+.1f%%"):format(entry.change) or "—")
            row.change:SetTextColor(unpack(entry.change and entry.change<0 and C.green or C.amber))
            row.buy:SetEnabled(self.atAuction==true and not self.work)
            self:DrawGraph(row,entry.key)
        end
    end
    self.empty:SetShown(#items==0 and not self.work)
    self.empty:SetText(self.snapshot and L("Ничего не найдено") or L("Сделай первый полный скан у аукциониста."))
    self.previous:SetEnabled(offset>0); self.next:SetEnabled(offset+ROWS<#items)
    self.page:SetText((math.floor(offset/ROWS)+1).." / "..math.max(1,math.ceil(#items/ROWS)).."  -  "..#items)
    local snapshot=self.snapshot
    self.version:SetText(snapshot and date("%d.%m.%Y %H:%M",snapshot.stamp) or L("Нет снимков"))
    self.older:SetEnabled(snapshot~=nil and self.versionIndex>1)
    self.newer:SetEnabled(snapshot~=nil and self.versionIndex<#db.snapshots)
    self.compare:SetText(self.comparison and (L("Сравнение со снимком: ")..date("%d.%m %H:%M",self.comparison.stamp)) or L("Нет снимка за 24 часа (допуск ±3 ч.)"))
    if snapshot and snapshot.partial then
        self.compare:SetText(L("Частичный снимок — сигналы отключены"))
        local stats=snapshot.stats
        self.diagnostics:SetText(stats and (L("Пропуски: данные %d / некорректные %d / ошибки %d / лимит %d")):format(
            stats.unloaded or 0,stats.invalid or 0,stats.errors or 0,(stats.itemLimit or 0)+(stats.lotLimit or 0)+(snapshot.trimmed or 0))
            or L("Причины пропусков в старом снимке не сохранены. Нужен новый скан."))
    else self.diagnostics:SetText("") end
    if self.statusText then self.status:SetText(self.statusText) end
    self:UpdateScanProgress()
end
function Market:Create()
    if self.frame then return end
    local f=UI.HUDPanel(UIParent,"MythicBoostAuctionMarket",WIDTH,488); self.frame=f
    f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); f:SetClampedToScreen(true)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart",function() if not InCombatLockdown() then f:StartMoving() end end)
    f:SetScript("OnDragStop",function() f:StopMovingOrSizing() end)
    Label(f,"MythicBoost / "..L("Аукцион"),16,-14,500,C.accent)
    local close=UI.Button(f,"x",25,23); close:SetPoint("TOPRIGHT",-9,-8); close:SetScript("OnClick",function() f:Hide() end)
    self.scanButton=UI.Button(f,L("Полный скан"),130,25); self.scanButton:SetPoint("TOPRIGHT",-43,-8)
    self.scanButton:SetScript("OnClick",function()
        if self.work then self:StopScan(L("Сканирование остановлено")) else self:StartScan() end
        self:Render()
    end)
    self.heading=Label(f,L("Выгодные предложения"),16,-47,540,C.text)
    local p=CreateFrame("Frame",nil,f); self.scanProgress=p
    p:SetPoint("TOPLEFT",16,-40); p:SetSize(WIDTH-32,36)
    p.title=Label(p,"",0,0,345,C.text)
    p.value=Label(p,"",351,0,WIDTH-383,C.accent); p.value:SetJustifyH("RIGHT")
    local font=p.value:GetFont(); p.value:SetFont(font,14,"")
    p.bar=CreateFrame("StatusBar",nil,p); p.bar:SetPoint("BOTTOMLEFT",0,0); p.bar:SetSize(WIDTH-32,9)
    p.bar:SetStatusBarTexture("Interface/Buttons/WHITE8X8"); p.bar:SetMinMaxValues(0,1); p.bar:SetValue(0)
    local back=p.bar:CreateTexture(nil,"BACKGROUND"); back:SetAllPoints(); back:SetColorTexture(.055,.10,.14,.96)
    p.pulse=p.bar:CreateTexture(nil,"OVERLAY"); p.pulse:SetSize(110,9); p.pulse:SetColorTexture(unpack(C.accent))
    p.pulse:SetPoint("LEFT",0,0)
    -- One owned animation, only while visibly waiting for the server. It does
    -- not read auctions, invent a download percentage, or allocate frames.
    p.animate=function(_,elapsed)
        p.elapsed=p.elapsed+elapsed
        if p.elapsed<.05 then return end
        p.elapsed=0
        local work=self.work
        if not work or work.phase~="waiting" or not f:IsShown() then p:SetScript("OnUpdate",nil); return end
        local x=(.5+.5*math.sin((GetTime()-work.started)*2))*(WIDTH-142)
        p.pulse:ClearAllPoints(); p.pulse:SetPoint("LEFT",x,0)
    end
    p:SetScript("OnHide",function() p:SetScript("OnUpdate",nil) end)
    p:Hide()
    self.older=UI.Button(f,"<",24,24); self.older:SetPoint("TOPLEFT",16,-85)
    self.version=Label(f,"",49,-91,163)
    self.newer=UI.Button(f,">",24,24); self.newer:SetPoint("TOPLEFT",218,-85)
    local function Version(delta)
        self.versionIndex=(self.versionIndex or #self:Database().snapshots)+delta
        self.offset=0; self:BuildView(); self:Render()
    end
    self.older:SetScript("OnClick",function() Version(-1) end)
    self.newer:SetScript("OnClick",function() Version(1) end)
    self.compare=Label(f,"",254,-91,488,C.muted)
    local search=CreateFrame("EditBox",nil,f,"InputBoxTemplate")
    search:SetSize(320,23); search:SetPoint("TOPLEFT",22,-116)
    search:SetAutoFocus(false); search:SetMaxLetters(100)
    search:SetScript("OnEnterPressed",function(input)
        self.query=input:GetText(); self.offset=0; self:BuildView(); self:Render(); input:ClearFocus()
    end)
    search:SetScript("OnEscapePressed",function(input) input:ClearFocus() end)
    Label(f,L("Поиск по имени или ID (Enter)"),356,-123,380,C.muted)
    Label(f,L("Предмет"),16,-151,260,C.muted); Label(f,L("Цена / шт."),300,-151,132,C.muted)
    Label(f,"24h",438,-151,72,C.muted); Label(f,L("История"),528,-151,110,C.muted)
    self.rows={}
    for i=1,ROWS do
        local row=CreateFrame("Frame",nil,f); row:SetSize(WIDTH-24,STEP-3); row:SetPoint("TOPLEFT",12,-172-(i-1)*STEP)
        local bg=row:CreateTexture(nil,"BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(.08,.12,.16,.82)
        row.icon=row:CreateTexture(nil,"ARTWORK"); row.icon:SetSize(30,30); row.icon:SetPoint("LEFT",4,0); row.icon:SetTexCoord(.08,.92,.08,.92)
        row.name=Label(row,"",42,-4,230); row.signal=Label(row,"",42,-22,230,C.muted)
        row.price=Label(row,"",282,-12,133,C.amber); row.price:SetJustifyH("RIGHT")
        row.change=Label(row,"",423,-12,73); row.change:SetJustifyH("RIGHT")
        local graph=CreateFrame("Frame",nil,row); graph:SetPoint("TOPLEFT",510,-3); graph:SetSize(108,30)
        row.lines={}
        for j=1,20 do row.lines[j]=graph:CreateLine(nil,"ARTWORK"); row.lines[j]:SetThickness(1.5) end
        row.noGraph=Label(graph,"",2,-9,104,C.muted)
        row.buy=UI.Button(row,L("К лотам"),92,25); row.buy:SetPoint("RIGHT",-8,0)
        row.buy:SetScript("OnClick",function() self:OpenListing(row.entry) end)
        row:EnableMouse(true)
        row:SetScript("OnEnter",function()
            local e=row.entry
            if not e or not TipAvailable() then return end
            GameTooltip:SetOwner(row,"ANCHOR_RIGHT"); GameTooltip:SetHyperlink(e.info.link)
            GameTooltip:AddLine(L("Минимальная цена за штуку в снимке: ")..Money(e.price),1,.8,.2)
            if e.old then GameTooltip:AddLine(L("Цена в предыдущем снимке: ")..Money(e.old),.7,.8,.9) end
            GameTooltip:AddLine(L("Актуальные лоты и подтверждение покупки — в окне Blizzard."),.7,.8,.9,true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave",function() HideTip(row) end)
        row:SetScript("OnHide",function() HideTip(row) end)
        self.rows[i]=row
    end
    -- Eight reusable rows; no frame is created per item or saved snapshot.
    f:SetHeight(172+ROWS*STEP+66)
    self.empty=Label(f,L("Сделай первый полный скан у аукциониста."),22,-196,650,C.muted)
    self.status=UI.Text(f,"GameFontHighlightSmall","",C.muted); self.status:SetPoint("BOTTOMLEFT",16,38); self.status:SetWidth(WIDTH-32); self.status:SetWordWrap(false)
    self.status:SetJustifyH("LEFT")
    self.diagnostics=UI.Text(f,"GameFontHighlightSmall","",C.amber); self.diagnostics:SetPoint("BOTTOMLEFT",16,55)
    self.diagnostics:SetWidth(WIDTH-32); self.diagnostics:SetWordWrap(false); self.diagnostics:SetJustifyH("LEFT")
    self.page=UI.Text(f,"GameFontHighlightSmall","",C.text); self.page:SetPoint("BOTTOM",0,13)
    self.previous=UI.Button(f,"<",30,24); self.previous:SetPoint("BOTTOMLEFT",16,7)
    self.next=UI.Button(f,">",30,24); self.next:SetPoint("BOTTOMRIGHT",-16,7)
    local function Page(delta) self.offset=math.max(0,(self.offset or 0)+delta*ROWS); self:Render() end
    self.previous:SetScript("OnClick",function() Page(-1) end); self.next:SetScript("OnClick",function() Page(1) end)
    f:SetScript("OnHide",function()
        search:ClearFocus(); self:StopScan(self.work and L("Сканирование остановлено") or nil)
        self.scanResult=nil; self:UpdateScanProgress()
        for _,row in ipairs(self.rows) do HideTip(row); row.entry=nil end
        self.items=nil; self.snapshot=nil; self.comparison=nil
    end)
    f:Hide()
end
function Market:AttachButton()
    if not self.running or not self.atAuction or not AuctionHouseFrame or InCombatLockdown() then return end
    if not self.button then
        self.button=UI.Button(AuctionHouseFrame,"MythicBoost",124,23)
        self.button:SetPoint("TOPRIGHT",AuctionHouseFrame,"TOPRIGHT",-42,-3)
        self.button:SetScript("OnClick",function()
            if not self.running or not self.atAuction or InCombatLockdown() then return end
            self:Create()
            if self.frame:IsShown() then self.frame:Hide()
            else self.frame:Show(); self:BuildView(); self:Render() end
        end)
        AuctionHouseFrame:HookScript("OnShow",function() self:AttachButton() end)
        AuctionHouseFrame:HookScript("OnHide",function()
            if self.button then self.button:Hide() end
            if self.frame then self.frame:Hide() end
        end)
    end
    -- The native title/NineSlice are child frames above the auction frame.
    -- A default-level button is covered by their header, leaving only its edge.
    -- Raise only our button; do not restyle or reorder the auction UI.
    local level=AuctionHouseFrame:GetFrameLevel()
    for _,key in ipairs({"TitleContainer","NineSlice"}) do
        local header=AuctionHouseFrame[key]
        if header and header.GetFrameLevel then level=math.max(level,header:GetFrameLevel()) end
    end
    self.button:SetFrameStrata(AuctionHouseFrame:GetFrameStrata() or "HIGH")
    self.button:SetFrameLevel(level+10)
    self.button:Show()
end
