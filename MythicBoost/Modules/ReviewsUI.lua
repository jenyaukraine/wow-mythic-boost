local _, JP = ...
local Reviews, UI, L, C = JP.Reviews, JP.UI, JP.L, JP.UI.colors

-- One shared, fixed-size tooltip pool for every applicant, not one panel
-- per player or per review. The database remains the full-text view.
function Reviews:ShowPlayerTooltip(owner, target)
    if not self.playerTip then
        local tip = UI.HUDPanel(UIParent, "MythicBoostPlayerReviews", 640, 110)
        tip:SetFrameStrata("TOOLTIP"); tip:SetClampedToScreen(true); tip:EnableMouse(false)
        tip.title = UI.Text(tip, "GameFontHighlight", "", C.accent)
        tip.title:SetPoint("TOPLEFT", 10, -9); tip.title:SetPoint("TOPRIGHT", -10, -9)
        tip.title:SetJustifyH("LEFT"); tip.title:SetWordWrap(false)
        tip.summary = UI.Text(tip, "GameFontHighlightSmall", "", C.muted)
        tip.summary:SetPoint("TOPLEFT", 10, -31)
        tip.memory=UI.Text(tip,"GameFontHighlightSmall","",C.text)
        tip.memory:SetPoint("TOPLEFT",10,-53); tip.memory:SetWidth(620)
        tip.memory:SetHeight(62); tip.memory:SetJustifyH("LEFT"); tip.memory:SetWordWrap(true)
        tip.rows = {}
        for i=1,10 do
            local row = CreateFrame("Frame", nil, tip)
            row:SetPoint("TOPLEFT", 6, -54-(i-1)*30); row:SetPoint("TOPRIGHT", -6, -54-(i-1)*30)
            row:SetHeight(29)
            local shade = row:CreateTexture(nil,"BACKGROUND")
            shade:SetAllPoints(); shade:SetColorTexture(.14,.20,.24,i%2==0 and .14 or .04)
            row.vote = UI.Text(row,"GameFontHighlightSmall","",C.text)
            row.vote:SetPoint("LEFT",4,0); row.vote:SetWidth(26)
            row.author = UI.Text(row,"GameFontHighlightSmall","",C.text)
            row.author:SetPoint("LEFT",34,0); row.author:SetWidth(190)
            row.comment = UI.Text(row,"GameFontHighlightSmall","",C.text)
            row.comment:SetPoint("LEFT",230,0); row.comment:SetPoint("RIGHT",-58,0)
            row.stamp = UI.Text(row,"GameFontHighlightSmall","",C.muted)
            row.stamp:SetPoint("RIGHT",-4,0); row.stamp:SetWidth(49)
            for _, text in ipairs({row.author,row.comment}) do text:SetJustifyH("LEFT"); text:SetWordWrap(false) end
            tip.rows[i]=row
        end
        tip.footer = UI.Text(tip,"GameFontHighlightSmall","",C.muted)
        tip.footer:SetPoint("BOTTOMLEFT",10,8); tip.footer:SetPoint("BOTTOMRIGHT",-10,8)
        tip.footer:SetJustifyH("LEFT"); tip.footer:SetWordWrap(false)
        tip:Hide(); self.playerTip=tip
    end
    local score,total,likes,dislikes,records = self:Rating(target)
    local tip=self.playerTip
    tip.owner,tip.target=owner,target
    tip.title:SetText(JP.AddonPresence and JP.AddonPresence:Decorate(target) or target)
    tip.summary:SetText((L("Отзывы: %+d  |  лайки %d / дизлайки %d")):format(score,likes,dislikes))
    local memoryHeight=JP.PlayerNetwork and 72 or 0
    tip.memory:SetText(JP.PlayerNetwork and JP.PlayerNetwork:Summary(target) or "")
    for i,row in ipairs(tip.rows) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",6,-54-memoryHeight-(i-1)*30)
        row:SetPoint("TOPRIGHT",-6,-54-memoryHeight-(i-1)*30)
        local record=records[i]
        row:SetShown(record~=nil)
        if record then
            row.vote:SetText(record.vote>0 and "+1" or tostring(record.vote))
            row.vote:SetTextColor(UI.Unpack(record.vote>0 and C.green or record.vote<0 and C.red or C.muted))
            row.author:SetText(record.author .. (not record.direct and " *" or ""))
            row.comment:SetText(record.text~="" and record.text or "—")
            row.stamp:SetText(date("%d.%m",record.stamp))
        end
    end
    tip.footer:SetText((L("Последние %d из %d авторов; * переслано, автор не подтверждён.")):format(#records,total))
    tip:SetHeight(80+memoryHeight+#records*30)
    tip:ClearAllPoints(); tip:SetPoint("TOPRIGHT",owner,"BOTTOMRIGHT",0,-5)
    GameTooltip_Hide(); tip:Show()
end

function Reviews:HidePlayerTooltip(owner)
    local tip=self.playerTip
    if tip and (not owner or tip.owner==owner) then tip:Hide(); tip.owner=nil; tip.target=nil end
end

local function Paint(row)
    row.like:SetBackdropBorderColor(UI.Unpack(row.vote==1 and C.green or C.lineSoft))
    row.dislike:SetBackdropBorderColor(UI.Unpack(row.vote==-1 and C.red or C.lineSoft))
end

function Reviews:CreatePanel()
    if self.frame then return end
    local f = UI.Panel(UIParent,C.window,C.lineSoft)
    f:SetSize(480,408); f:SetPoint("BOTTOMLEFT",UIParent,"BOTTOMLEFT",30,90)
    f:SetFrameStrata("DIALOG"); f:SetClampedToScreen(true); f:EnableMouse(true)
    f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart",function() f:StartMoving() end)
    f:SetScript("OnDragStop",function() f:StopMovingOrSizing() end)
    local title = UI.Text(f,"GameFontNormalLarge",L("Отзывы после ключа"),C.text)
    title:SetPoint("TOPLEFT",16,-14)
    self.reviewSubtitle = UI.Text(f,"GameFontHighlightSmall","",C.muted)
    self.reviewSubtitle:SetPoint("TOPLEFT",16,-38); self.reviewSubtitle:SetWidth(448)
    self.reviewSubtitle:SetJustifyH("LEFT"); self.reviewSubtitle:SetWordWrap(false)
    local close = UI.Button(f,"x",24,24); close:SetPoint("TOPRIGHT",-8,-8)
    close:SetScript("OnClick",function() f:Hide() end)
    self.reviewRows={}
    for i=1,4 do
        -- Keep the consent control, editor and read-only meter on distinct
        -- rows. The extra vertical space is fixed and reused with the panel.
        local height=JP.RunStats and 100 or 78
        local row=CreateFrame("Frame",nil,f); row:SetSize(448,height-4); row:SetPoint("TOPLEFT",16,-64-(i-1)*height)
        row.label=UI.Text(row,"GameFontHighlightSmall","",C.text)
        row.label:SetPoint("TOPLEFT",0,-3); row.label:SetWidth(222); row.label:SetJustifyH("LEFT"); row.label:SetWordWrap(false)
        row.like=UI.Button(row,L("Лайк"),72,22); row.like:SetPoint("TOPRIGHT",-126,0)
        row.dislike=UI.Button(row,L("Дизлайк"),92,22); row.dislike:SetPoint("TOPRIGHT",-28,0)
        local clear=UI.Button(row,"x",22,22); clear:SetPoint("TOPRIGHT",0,0)
        row.shared=UI.CheckBox(row,L("В общую базу"),false,function(value)
            row.sharedValue=value==true; row.dirty=true
        end)
        row.shared:SetPoint("TOPLEFT",228,-28)
        row.shared:HookScript("OnEnter",function(check)
            UI.Tooltip(check,L("В общую базу"),L("Отзыв, оценка и статистика будут переданы другим пользователям MythicBoost. Скрытие в интерфейсе не делает эти данные приватными."))
        end)
        row.shared:HookScript("OnLeave",GameTooltip_Hide)
        row.edit=UI.NumberBox(row,448,25); row.edit.frame:SetPoint("TOPLEFT",0,-54)
        row.edit:SetNumeric(false); row.edit:SetMaxLetters(120); row.edit:SetJustifyH("LEFT")
        row.stats=UI.Text(row,"GameFontHighlightSmall","",C.amber)
        row.stats:SetPoint("TOPLEFT",0,-84); row.stats:SetWidth(448)
        row.stats:SetJustifyH("LEFT"); row.stats:SetWordWrap(false)
        row.edit:SetScript("OnTextChanged",function(_,user) if user then row.dirty=true end end)
        row.like:SetScript("OnClick",function() row.vote=row.vote==1 and 0 or 1; row.dirty=true; Paint(row) end)
        row.dislike:SetScript("OnClick",function() row.vote=row.vote==-1 and 0 or -1; row.dirty=true; Paint(row) end)
        clear:SetScript("OnClick",function()
            row.vote=0; row.edit:SetText(""); row.sharedValue=false
            row.shared:SetChecked(false); row.dirty=true; Paint(row)
        end)
        clear:SetScript("OnEnter",function() UI.Tooltip(clear,L("Удалить мой отзыв")) end)
        clear:SetScript("OnLeave",GameTooltip_Hide)
        row:EnableMouse(true)
        row:SetScript("OnEnter",function()
            GameTooltip:SetOwner(row,"ANCHOR_RIGHT"); GameTooltip:SetText(row.target)
            self:AddTooltip(GameTooltip,row.target); GameTooltip:Show()
            if JP.RunStats then
                GameTooltip:AddLine(JP.RunStats:Text(JP.RunStats:ForMember(self.reviewRun,row.target),true),.95,.8,.5,true)
                GameTooltip:AddLine(L("DPS/HPS: сумма за ключ / время счётчика Blizzard. Статистика только для чтения."),.6,.65,.7,true)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave",GameTooltip_Hide)
        row:SetScript("OnMouseUp",function(_,button)
            if button=="LeftButton" and row.target and JP.PlayerNetwork then JP.PlayerNetwork:ShowMemory(row.target) end
        end)
        self.reviewRows[i]=row
    end
    self.syncLabel=UI.Text(f,"GameFontHighlightSmall",L("Обмен работает постоянно, включая бой"),C.muted)
    self.syncLabel:SetPoint("BOTTOMLEFT",16,58)
    local note=UI.Text(f,"GameFontHighlightSmall",
        L("«В общую базу» — отзывы и статистика. Личные заметки остаются у тебя."),C.muted)
    note:SetPoint("BOTTOMLEFT",16,13); note:SetWidth(300); note:SetWordWrap(true); note:SetJustifyH("LEFT")
    self.note=note
    local save=UI.Button(f,L("Сохранить"),126,28,true); save:SetPoint("BOTTOMRIGHT",-16,14)
    self.saveButton=save
    save:SetScript("OnClick",function()
        local failed=false
        for _,row in ipairs(self.reviewRows) do
            if row.target and row.dirty then
                if self:Save(row.target,row.vote,row.edit:GetText(),self.reviewRun,row.sharedValue==true) then row.dirty=false
                else failed=true end
            end
            row.edit:ClearFocus()
        end
        if failed then JP:Print(L("Не удалось сохранить отзыв: проверь имя игрока и данные забега."))
        else f:Hide() end
    end)
    self.frame=f; f:Hide()
end

function Reviews:ShowRun(run)
    if not run or not self.running then return end
    if InCombatLockdown() then self.pendingRun=run; return end
    self.pendingRun=nil; self:CreatePanel(); self.reviewRun=run
    local own=self.FullName(UnitFullName("player"))
    local names,seen={},{}
    for _,member in ipairs(run.members or {}) do
        local name=self.FullName(member)
        if name and name~=own and not seen[name] and #names<4 then names[#names+1]=name; seen[name]=true end
    end
    if #names==0 then return end
    self.reviewSubtitle:SetText(("+%d  %s  /  +%d"):format(run.level or 0,run.mapName or L("Подземелье"),run.upgrades or 0))
    for i,row in ipairs(self.reviewRows) do
        row.target=names[i]; row.dirty=false
        if row.target then
            local saved=self:GetOwn(row.target)
            row.label:SetText(row.target); row.vote=saved and saved.vote or 0
            -- New reviews default to the common database by product choice;
            -- an existing explicit shared=false record remains local.
            row.sharedValue=saved == nil and true or saved.shared==true
            row.shared:SetChecked(row.sharedValue)
            row.edit:SetText(saved and saved.text or ""); Paint(row); row:Show()
        else row:Hide() end
    end
    self.syncLabel:SetText(self:SyncStatus())
    self:RefreshRunStats(run)
    self.frame:SetHeight(152+#names*(JP.RunStats and 100 or 78)); self.frame:Show()
end

function Reviews:RefreshRunStats(run)
    if self.reviewRun~=run or not self.reviewRows or not JP.RunStats then return end
    for _,row in ipairs(self.reviewRows) do
        row.stats:SetText(row.target and JP.RunStats:Text(JP.RunStats:ForMember(run,row.target)) or "")
    end
end

function Reviews:OfferRun(run)
    self.offerToken=(self.offerToken or 0)+1
    local token=self.offerToken
    C_Timer.After(2,function() if self.running and token==self.offerToken then self:ShowRun(run) end end)
end
