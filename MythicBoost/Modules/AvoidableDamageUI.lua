local _, JP = ...
local Monitor, UI, L = JP.AvoidableDamage, JP.UI, JP.L
local C, WIDTH, STEP = UI.colors, 360, 44
-- Five reused rows: pace arrivals so every card gets its full reading time.
local FEED_GAP, FEED_LIFE = 3, 15
local HEAT={{1,.73,.20},{1,.40,.08},{1,.16,.08}}
local function Amount(n)
    if n >= 1000000 then return ("%.2fM"):format(n/1000000) end
    if n >= 1000 then return ("%.1fk"):format(n/1000) end
    return ("%.0f"):format(n)
end
local function Text(parent,font,value,color,x,y,width)
    local t=UI.Text(parent,font,value,color)
    t:SetPoint("TOPLEFT",x,y)
    t:SetJustifyH("LEFT")
    if width then t:SetWidth(width); t:SetWordWrap(false) end
    return t
end
local PREVIEW={
    {name="MythicBoost",class="DRUID",amount=1285000,spellID=133,healthRatio=1.28},
    {name="Guardian",class="WARRIOR",amount=742000,spellID=116,healthRatio=.74},
    {name="Arcane",class="MAGE",amount=358000,spellID=118,healthRatio=.35},
}
local function Spell(id)
    local info
    if id and C_Spell and C_Spell.GetSpellInfo then
        local ok,value=pcall(C_Spell.GetSpellInfo,id)
        if ok then info=JP.SafeTable(value) end
    end
    return info and JP.SafeString(info.name) or (L("Способность").." "..tostring(id or "")),
        info and JP.SafeNumber(info.iconID) or 134400
end
local function TooltipAllowed()
    return GameTooltip and (not GameTooltip.IsForbidden or not GameTooltip:IsForbidden())
end
local function HideTip(row)
    if TooltipAllowed() and GameTooltip:IsOwned(row) then GameTooltip:Hide() end
end
local function ShowSpellTip(row)
    local record=row.record
    if not record or not record.spellID or not TooltipAllowed() then return end
    GameTooltip:SetOwner(row,"ANCHOR_RIGHT")
    GameTooltip:SetSpellByID(record.spellID)
    GameTooltip:AddLine(L("Избегаемый урон")..": "..(record.known==false and "—" or Amount(record.amount)),1,.78,.22)
    if record.name then GameTooltip:AddLine(record.name,.7,.75,.8) end
    if record.healthRatio then GameTooltip:AddLine((L("За бой: %.0f%% максимального HP от этой способности")):format(record.healthRatio*100),1,.65,.2) end
    GameTooltip:Show()
end
function Monitor:HidePlayerSpells()
    if self.playerTip then self.playerTip:Hide() end
end
function Monitor:ShowPlayerSpells(owner,offset)
    local record,report=owner.record,self.lastReport
    if not record or record.spellID or not report or not report.key then return end
    self:HidePlayerSpells()
    if not self.playerTip then
        local tip=UI.HUDPanel(UIParent,nil,350,100); self.playerTip=tip
        tip:SetFrameStrata("TOOLTIP"); tip:SetClampedToScreen(true); tip:EnableMouse(true)
        tip.title=Text(tip,"GameFontHighlight", "",C.text,10,-10,328)
        Text(tip,"GameFontHighlightSmall",L("Способности"),C.muted,10,-31,328)
        tip.empty=Text(tip,"GameFontHighlightSmall",L("Подробности по способностям недоступны"),C.muted,10,-57,328)
        tip.rows={}
        for i=1,5 do
            local row=CreateFrame("Frame",nil,tip)
            row:SetSize(330,32); row:SetPoint("TOPLEFT",10,-49-(i-1)*34)
            local bg=row:CreateTexture(nil,"BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(.10,.14,.18,.78)
            row.icon=row:CreateTexture(nil,"ARTWORK"); row.icon:SetSize(26,26); row.icon:SetPoint("LEFT",3,0)
            row.icon:SetTexCoord(.08,.92,.08,.92)
            row.name=Text(row,"GameFontHighlightSmall","",C.text,35,-9,218)
            row.amount=Text(row,"GameFontHighlightSmall","",C.amber,256,-9,70); row.amount:SetJustifyH("RIGHT")
            row:SetMouseClickEnabled(false); row:SetMouseMotionEnabled(true)
            row:SetScript("OnEnter",ShowSpellTip); row:SetScript("OnLeave",HideTip)
            row:SetScript("OnHide",HideTip); tip.rows[i]=row
        end
        tip.footer=UI.Text(tip,"GameFontHighlightSmall","",C.muted); tip.footer:SetPoint("BOTTOMLEFT",10,9)
        tip.previous=UI.Button(tip,"<",24,22); tip.previous:SetPoint("BOTTOMRIGHT",-38,4)
        tip.next=UI.Button(tip,">",24,22); tip.next:SetPoint("BOTTOMRIGHT",-10,4)
        tip.previous:SetScript("OnClick",function() if tip.owner then self:ShowPlayerSpells(tip.owner,tip.offset-5) end end)
        tip.next:SetScript("OnClick",function() if tip.owner then self:ShowPlayerSpells(tip.owner,tip.offset+5) end end)
        tip:SetScript("OnHide",function()
            tip:SetScript("OnUpdate",nil); tip.owner=nil; tip.away=nil
            for _,row in ipairs(tip.rows) do HideTip(row); row.record=nil end
        end)
        tip.tick=function()
            if tip:IsMouseOver() or (tip.owner and tip.owner:IsShown() and tip.owner:IsMouseOver()) then tip.away=nil
            else
                tip.away=tip.away or GetTime()
                if GetTime()-tip.away>.18 then tip:Hide() end
            end
        end
    end
    -- Reuse five rows; never retain a second copy of a run or create per-hover timers.
    local entries={}
    for _,entry in ipairs(report.entries or {}) do
        if record.guid and entry.guid==record.guid and entry.spellID then entries[#entries+1]=entry end
    end
    local tip=self.playerTip
    tip.owner=owner; tip.offset=math.max(0,math.min(offset or 0,math.max(0,math.floor((#entries-1)/5)*5)))
    tip.title:SetText(record.name or "?")
    tip:ClearAllPoints(); tip:SetPoint("TOPLEFT",owner,"TOPRIGHT",6,0)
    tip:SetHeight(83+math.max(1,math.min(5,#entries))*34)
    for i,row in ipairs(tip.rows) do
        local entry=entries[tip.offset+i]; row.record=entry; row:SetShown(entry~=nil)
        if entry then
            local name,icon=Spell(entry.spellID)
            row.name:SetText(name); row.icon:SetTexture(icon); row.amount:SetText(Amount(entry.amount))
        end
    end
    tip.empty:SetShown(#entries==0)
    tip.footer:SetText((report.complete and "" or L("Неполная сводка").."  ")..
        (math.floor(tip.offset/5)+1).."/"..math.max(1,math.ceil(#entries/5)))
    tip.previous:SetShown(tip.offset>0); tip.next:SetShown(tip.offset+5<#entries)
    tip:SetScript("OnUpdate",tip.tick); tip:Show()
end
function Monitor:ShowHelp()
    if not self.tooltip then
        self.tooltip=UI.HUDPanel(UIParent,nil,320,120)
        self.tooltip:SetFrameStrata("TOOLTIP"); self.tooltip:EnableMouse(false)
        local t=Text(self.tooltip,"GameFontHighlightSmall",L("Сводка избегаемого урона после боя. Наведи на способность для описания. Итог ключа содержит суммы по игрокам и способностям. Прокручивай список колёсиком. Поделиться можно только вручную; отправляются видимые строки."),C.text,12,-12,296)
        t:SetWordWrap(true); self.tooltip:SetHeight(24+t:GetStringHeight())
    end
    self.tooltip:ClearAllPoints(); self.tooltip:SetPoint("TOPLEFT",self.frame,"TOPRIGHT",8,0)
    self.tooltip:SetClampedToScreen(true); self.tooltip:Show()
end
function Monitor:Layout()
    if self.dragging then return end
    local p=self:Settings().position
    self.frame:ClearAllPoints()
    if p then self.frame:SetPoint(p.point,UIParent,p.relativePoint,p.x,p.y)
    else self.frame:SetPoint("TOPLEFT",UIParent,"TOPLEFT",UIParent:GetWidth()*.04,-UIParent:GetHeight()*.42) end
    self.frame:SetMouseClickEnabled(self.preview==true)
    self.frame:SetMouseMotionEnabled(true)
end
function Monitor:SetUnlocked(value)
    if self.dragging and not InCombatLockdown() then
        self.frame:StopMovingOrSizing()
        local point,_,relativePoint,x,y=self.frame:GetPoint()
        self:Settings().position={point=point,relativePoint=relativePoint,x=x,y=y}; self.dragging=false
    end
    self.preview=value==true
    if self.preview then self:Create() end
    if self.frame then
        self.frame:SetMouseClickEnabled(self.preview)
        self.frame:SetFrameStrata(self.preview and "DIALOG" or "MEDIUM")
        if self.tooltip then self.tooltip:Hide() end
        if self.sharePanel then self.sharePanel:Hide() end
        self:Render()
    end
end
function Monitor:ReportRows()
    if self.preview then return PREVIEW end
    local report=self.lastReport
    if not report then return {} end
    return report.key and self.reportView=="players" and report.players or report.entries
end
function Monitor:SetReportOffset(value)
    if self.preview or not self.lastReport or not self.lastReport.key or self:IsCombatLocked() then return end
    value=JP.SafeNumber(value)
    if not value or value~=value then return end
    local maximum=math.max(0,#self:ReportRows()-5)
    local offset=math.max(0,math.min(maximum,math.floor(value+.5)))
    if offset~=(self.reportOffset or 0) then self.reportOffset=offset; self:Render() end
end
function Monitor:OpenKeyReport()
    if not self.keyReport then return false end
    self:Create()
    self.lastReport,self.reportOffset,self.reportExpires,self.reportView=self.keyReport,0,nil,"players"
    self:Render(); return true
end
-- Sharing requires a hardware click. No automatic chat, discovery whisper,
-- retry queue or timer is permitted on this path.
function Monitor:ShareReport(channel,target)
    if self.preview or not self.lastReport then return false end
    if InCombatLockdown() then return false,L("Недоступно в бою") end
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok,locked=pcall(C_ChatInfo.InChatMessagingLockdown)
        if not ok or JP.SafeOptionalBoolean(locked)~=false then return false,L("Чат недоступен") end
    end
    if channel=="PARTY" then
        if not IsInGroup() then return false,L("Нет группы") end
        if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then channel="INSTANCE_CHAT"
        elseif IsInRaid() then channel="RAID" end
    elseif channel=="WHISPER" then
        target=JP.SafeString(target); target=target and target:match("^%s*(.-)%s*$")
        if not target or target=="" or #target>100 or target:find("[%s|%c]") then
            return false,L("Укажи имя получателя: Имя-Сервер")
        end
    else return false end
    local now=GetTime()
    if self.lastShare and now-self.lastShare<5 then return false,L("Повтори через 5 секунд") end
    local send=C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
    if not send then return false,L("Чат недоступен") end
    local rows,report=self:ReportRows(),self.lastReport
    local offset=self.reportOffset or 0
    local readable=false
    for i=offset+1,math.min(offset+5,#rows) do
        local row=rows[i]
        if row.known~=false or (row.fatal or 0)>0 then readable=true; break end
    end
    if not readable and not (#rows==0 and report.complete) then
        return false,L("Нет доступных данных")
    end
    local lines={"[MythicBoost] "..(report.key and "Keystone" or "Combat").." avoidable damage"..
        (report.complete and "" or " (partial data)").." - "..(self.reportView=="players" and "players" or "spells")..
        " ["..(#rows>0 and offset+1 or 0).."-"..math.min(offset+5,#rows).."/"..#rows.."]"}
    for i=offset+1,math.min(offset+5,#rows) do
        local row=rows[i]
        if row.known~=false or (row.fatal or 0)>0 then
        local name=(row.name or "?"):gsub("|"," "):gsub("[%c]"," ")
        -- Unit names are short; reject corrupted data rather than truncating UTF-8.
        if #name>100 then name="?" end
        local label=row.spellID and (" - |Hspell:"..row.spellID.."|h[Spell "..row.spellID.."]|h") or ""
        lines[#lines+1]="[MythicBoost] "..name..label..": "..(row.known==false and "unknown" or Amount(row.amount))..
            (not row.spellID and ("; confirmed fatal: "..tostring(row.fatal or 0)..(row.deathUnknown and "+?" or "")) or "")
        end
    end
    if #rows==0 then lines[#lines+1]="[MythicBoost] "..(report.complete and "No avoidable damage recorded." or "No readable data.") end
    self.lastShare=now
    for _,line in ipairs(lines) do
        local ok=pcall(send,line,channel,nil,target)
        if not ok then return false,L("Не удалось отправить отчёт") end
    end
    return true,L("Отчёт отправлен")
end
function Monitor:ShowShare()
    if not self.sharePanel then
        local p=UI.HUDPanel(self.frame,nil,WIDTH,108); self.sharePanel=p
        p:SetPoint("TOPLEFT",self.frame,"BOTTOMLEFT",0,-4); p:SetFrameStrata("DIALOG")
        Text(p,"GameFontHighlightSmall",L("Отправить видимые строки (до 5)"),C.muted,10,-9)
        local party=UI.Button(p,"Party",82,25); party:SetPoint("TOPLEFT",10,-29)
        local whisper=UI.Button(p,L("В личку"),82,25); whisper:SetPoint("TOPRIGHT",-10,-29)
        local input=CreateFrame("EditBox",nil,p,"InputBoxTemplate")
        input:SetSize(160,25); input:SetPoint("LEFT",party,"RIGHT",12,0)
        input:SetAutoFocus(false); input:SetMaxLetters(100)
        input:SetScript("OnEscapePressed",function(f) f:ClearFocus(); p:Hide() end)
        Text(p,"GameFontHighlightSmall",L("Имя-Сервер для личного сообщения"),C.muted,10,-61)
        local status=Text(p,"GameFontHighlightSmall","",C.text,10,-82,WIDTH-20)
        local function Send(channel)
            local ok,message=self:ShareReport(channel,input:GetText())
            status:SetText(message or ""); status:SetTextColor(unpack(ok and C.green or C.amber)); input:ClearFocus()
        end
        party:SetScript("OnClick",function() Send("PARTY") end)
        whisper:SetScript("OnClick",function() Send("WHISPER") end)
        self.shareInput=input
        p:SetScript("OnHide",function() input:ClearFocus() end)
        p:Hide()
    end
    self.sharePanel:SetShown(not self.sharePanel:IsShown())
end
function Monitor:PaintReportRow(row,record)
    HideTip(row); row.record=record
    if not record then return end
    local name,icon=Spell(record.spellID)
    row.icon:SetTexture(icon); row.icon:SetShown(record.spellID~=nil)
    row.classIcon:SetText(record.spellID and "" or UI.ClassIcon(record.class,30))
    row.spell:SetText(record.spellID and name or (record.name or "?"))
    row.name:SetText(record.spellID and (record.name or "?") or
        (L("Смертельные ошибки: %s")):format(tostring(record.fatal or 0)..(record.deathUnknown and "+?" or "")))
    local color=RAID_CLASS_COLORS and RAID_CLASS_COLORS[record.class]
    if color then row.name:SetTextColor(color.r,color.g,color.b) else row.name:SetTextColor(unpack(C.muted)) end
    row.amount:SetText(record.known==false and "—" or Amount(record.amount))
    local ratio=record.healthRatio
    row.severity=ratio and (ratio>=1 and 3 or (ratio>=.5 and 2 or 1)) or 1
    local color=HEAT[row.severity]
    row.accent:SetColorTexture(color[1],color[2],color[3],.95)
    row.accent:SetWidth(row.severity==3 and 3 or 2)
    row.glow:SetColorTexture(color[1],color[2],color[3],1)
    row.amount:SetTextColor(unpack(color))
end
function Monitor:UpdateFeed()
    local report=self.lastReport
    if self:IsCombatLocked() then
        self.frame:Hide(); self.frame:SetScript("OnUpdate",nil); return
    end
    if self.preview or not report or report.key or not self.running or not self.active then
        self.frame:SetScript("OnUpdate",nil); return
    end
    local now=GetTime()
    local hovered=false
    for _,row in ipairs(self.rows) do if row:IsShown() and row:IsMouseOver() then hovered=true end end
    if not hovered then self.feedClock=(self.feedClock or 0)+math.max(0,now-(self.feedLast or now)) end
    self.feedLast=now
    local entries=report.entries
    local duration=math.max(0,#entries-1)*FEED_GAP+FEED_LIFE
    self.reportExpires=now+math.max(0,duration-self.feedClock)
    if self.feedClock>=duration or (#entries==0 and report.complete) then
        self.frame:Hide(); self.frame:SetScript("OnUpdate",nil)
        for _,row in ipairs(self.rows) do HideTip(row); row.record=nil; row:Hide() end
        return
    end
    local first=math.max(1,math.floor((self.feedClock-FEED_LIFE)/FEED_GAP)+2)
    local last=math.min(#entries,math.floor(self.feedClock/FEED_GAP)+1)
    for i,row in ipairs(self.rows) do
        local index=first+i-1
        local record=index<=last and entries[index] or nil
        if row.record~=record then self:PaintReportRow(row,record) end
        row:SetShown(record~=nil)
        if record then
            local age=self.feedClock-(index-1)*FEED_GAP
            local alpha=math.max(0,math.min(1,age/.18,(FEED_LIFE-age)/.35))
            row:SetAlpha(alpha)
            row.glow:SetAlpha(row.severity>1 and math.max(0,1-age/.7)*.23 or 0)
            row:ClearAllPoints(); row:SetPoint("TOPLEFT",8,-(i-1)*STEP-7*(1-math.min(1,age/.18)))
        end
    end
end
function Monitor:RenderFeed()
    local f=self.frame
    f:SetBackdropColor(0,0,0,0); f:SetBackdropBorderColor(0,0,0,0); f:SetAlpha(1)
    self.title:Hide(); self.brand:Hide(); self.close:Hide(); self.share:Hide(); self.view:Hide()
    self.footer:Hide(); self.empty:Hide(); self.scrollBar:Hide(); f:EnableMouseWheel(false)
    if self.sharePanel then self.sharePanel:Hide() end
    if self.tooltip then self.tooltip:Hide() end
    local rows=self:ReportRows()
    f:SetHeight(math.max(1,math.min(5,#rows))*STEP)
    if not self.preview and #rows==0 and not self.lastReport.complete then
        self.empty:ClearAllPoints(); self.empty:SetPoint("TOPLEFT",12,-12)
        self.empty:SetText(L("Подробности по способностям недоступны")); self.empty:Show()
    end
    for _,row in ipairs(self.rows) do
        row:SetWidth(WIDTH-16); row.amount:SetWidth(82); row:EnableMouseWheel(false)
        row.accent:Show(); row.shade:SetColorTexture(.075,.065,.035,.86)
    end
    if self.preview then
        f:SetScript("OnUpdate",nil)
        for i,row in ipairs(self.rows) do
            self:PaintReportRow(row,rows[i]); row:SetShown(rows[i]~=nil); row:SetAlpha(1)
            row.glow:SetAlpha(rows[i] and row.severity>1 and .10 or 0)
            row:ClearAllPoints(); row:SetPoint("TOPLEFT",8,-(i-1)*STEP)
        end
    else
        self:UpdateFeed()
        if f:IsShown() then f:SetScript("OnUpdate",self.feedTick) end
    end
end
function Monitor:Render()
    if not self.frame then return end
    self:HidePlayerSpells()
    local report=self.lastReport
    if not self.preview and report and not report.key and self.feedReport~=report then
        self.feedReport,self.feedClock,self.feedLast=report,0,GetTime()
        self.reportExpires=GetTime()+math.max(0,#report.entries-1)*FEED_GAP+FEED_LIFE
    elseif not report then self.feedReport=nil; self.feedLast=nil end
    local visible=not self:IsCombatLocked() and (self.preview or
        (report and self:Settings().enabled~=false and (report.key or (self.running and self.active))
            and (not self.reportExpires or GetTime()<self.reportExpires)))
    self.frame:SetShown(visible)
    if not visible then
        self.frame:SetScript("OnUpdate",nil)
        self.scrollBar:Hide()
        if self.sharePanel then self.sharePanel:Hide() end
        for _,row in ipairs(self.rows) do HideTip(row); row.record=nil; row:Hide() end
        return
    end
    self:Layout()
    self.empty:SetText(report and report.complete and L("Избегаемого урона нет") or L("Нет доступных данных"))
    if self.preview or not report.key then self:RenderFeed(); return end
    self.feedReport=nil; self.feedLast=nil
    self.frame:SetBackdropColor(unpack(C.surface)); self.frame:SetBackdropBorderColor(unpack(C.hudEdge))
    self.title:Show(); self.footer:Show()
    self.brand:SetShown(not self.preview)
    self.close:SetShown(not self.preview); self.share:SetShown(not self.preview)
    self.view:SetShown(not self.preview and report.key==true)
    self.title:SetText(report and report.key and not self.preview and L("Итог ключа") or L("После боя"))
    self.view.label:SetText(self.reportView=="players" and L("Способности") or L("Игроки"))
    local rows=self:ReportRows()
    local maximum=math.max(0,#rows-5)
    local offset=math.max(0,math.min(self.reportOffset or 0,maximum))
    self.reportOffset=offset
    self.frame:EnableMouseWheel(true)
    self.scrollBar:SetMinMaxValues(0,maximum); self.scrollBar:SetValue(offset)
    self.scrollBar:SetShown(maximum>0)
    for i,row in ipairs(self.rows) do
        local record=rows[offset+i]; self:PaintReportRow(row,record); row:SetShown(record~=nil)
        row:SetWidth(WIDTH-28); row.amount:SetWidth(70); row:EnableMouseWheel(true)
        row:SetAlpha(1); row.accent:Hide(); row.shade:SetColorTexture(.10,.14,.18,.78)
        row.glow:SetAlpha(0); row.amount:SetTextColor(unpack(C.amber))
        row:ClearAllPoints(); row:SetPoint("TOPLEFT",8,-35-(i-1)*STEP)
    end
    self.frame:SetHeight(91+math.max(1,math.min(5,#rows))*STEP)
    self.empty:SetShown(#rows==0)
    self.empty:ClearAllPoints(); self.empty:SetPoint("TOPLEFT",16,-50)
    self.empty:SetText(report and report.complete and L("Избегаемого урона нет") or L("Нет доступных данных"))
    self.footer:SetText((report.complete and L("Избегаемый урон") or L("Неполная сводка"))..
        (#rows>5 and ("  "..(offset+1).."-"..math.min(offset+5,#rows).." / "..#rows) or ""))
    self.frame:SetAlpha(1)
    self.frame:SetScript("OnUpdate",nil)
end
function Monitor:Create()
    if self.frame then return end
    local f=UI.HUDPanel(UIParent,"MythicBoostAvoidableDamage",WIDTH,223)
    self.frame,self.rows=f,{}; f:SetFrameStrata("MEDIUM")
    self.feedTick=function() self:UpdateFeed() end
    self.title=Text(f,"GameFontNormal",L("После боя"),C.text,12,-11)
    self.brand=Text(f,"GameFontHighlightSmall","MythicBoost",C.muted,233,-13)
    self.close=UI.Button(f,"x",22,22); self.close:SetPoint("TOPRIGHT",-7,-7)
    self.close:SetScript("OnClick",function() self.lastReport=nil; self:Render() end)
    for i=1,5 do
        local row=CreateFrame("Frame",nil,f)
        row:SetSize(WIDTH-16,STEP-3); row:SetPoint("TOPLEFT",8,-35-(i-1)*STEP)
        local shade=row:CreateTexture(nil,"BACKGROUND"); row.shade=shade
        shade:SetAllPoints(); shade:SetColorTexture(.10,.14,.18,.78)
        row.glow=row:CreateTexture(nil,"BACKGROUND",nil,1); row.glow:SetAllPoints(); row.glow:SetAlpha(0)
        row.accent=row:CreateTexture(nil,"ARTWORK"); row.accent:SetSize(2,STEP-3)
        row.accent:SetPoint("LEFT",0,0); row.accent:SetColorTexture(1,.73,.20,.92)
        row.icon=row:CreateTexture(nil,"ARTWORK"); row.icon:SetSize(30,30); row.icon:SetPoint("LEFT",5,0)
        row.icon:SetTexCoord(.08,.92,.08,.92)
        row.classIcon=Text(row,"GameFontHighlight","",C.text,5,-5)
        row.spell=Text(row,"GameFontHighlightSmall","",C.text,44,-5,205)
        row.name=Text(row,"GameFontHighlightSmall","",C.muted,44,-23,205)
        row.amount=Text(row,"GameFontNormalLarge","",C.amber,254,-10,82); row.amount:SetJustifyH("RIGHT")
        row.amount:ClearAllPoints(); row.amount:SetPoint("RIGHT",row,"RIGHT",-8,0)
        row:SetMouseClickEnabled(false); row:SetMouseMotionEnabled(true)
        row:SetScript("OnEnter",function()
            local record=row.record
            if not record then return end
            self:HidePlayerSpells()
            if record.spellID then ShowSpellTip(row)
            else HideTip(row); self:ShowPlayerSpells(row) end
        end)
        row:SetScript("OnLeave",function() HideTip(row) end)
        row:SetScript("OnHide",function() HideTip(row) end)
        self.rows[i]=row
    end
    self.empty=Text(f,"GameFontHighlightSmall","",C.muted,16,-50)
    self.footer=UI.Text(f,"GameFontHighlightSmall","",C.muted)
    self.footer:SetPoint("BOTTOMLEFT",12,38); self.footer:SetWidth(WIDTH-24); self.footer:SetWordWrap(false)
    self.scrollBar=UI.ScrollBar(f)
    self.scrollBar:SetPoint("TOPRIGHT",-6,-35); self.scrollBar:SetPoint("BOTTOMRIGHT",-6,58)
    self.scrollBar:SetScript("OnValueChanged",function(_,value) self:SetReportOffset(value) end)
    UI.BindScrollWheel(f,self.scrollBar,self.rows,function() return self.reportOffset end)
    self.share=UI.Button(f,L("Поделиться"),130,23); self.share:SetPoint("BOTTOMRIGHT",-9,6)
    self.share:SetScript("OnClick",function() self:ShowShare() end)
    self.view=UI.Button(f,L("Способности"),130,23); self.view:SetPoint("BOTTOMLEFT",9,6)
    self.view:SetScript("OnClick",function()
        self.reportView=self.reportView=="players" and "spells" or "players"; self.reportOffset=0; self:Render()
    end)
    UI.HUDMover(f,function() return self:Settings() end,function() return self.preview end)
    f:HookScript("OnDragStart",function() if self.preview and not InCombatLockdown() then self.dragging=true end end)
    f:HookScript("OnDragStop",function() self.dragging=false; self:Render() end)
    f:SetScript("OnEnter",function() if not self.preview and self.lastReport and self.lastReport.key then self:ShowHelp() end end)
    f:SetScript("OnLeave",function() if self.tooltip then self.tooltip:Hide() end end)
    f:SetScript("OnHide",function()
        f:SetScript("OnUpdate",nil)
        self:HidePlayerSpells()
        if self.tooltip then self.tooltip:Hide() end
        if self.sharePanel then self.sharePanel:Hide() end
        for _,row in ipairs(self.rows) do HideTip(row); row.record=nil end
    end)
    self.events=CreateFrame("Frame")
    self.events:SetScript("OnEvent",function(_,event,...) self:OnEvent(event,...) end)
    f:Hide()
end
