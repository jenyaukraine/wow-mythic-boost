local _, JP = ...
local L, UI = JP.L, JP.UI
local Tools = JP.GroupTools

local function Button(parent,label,x,y,width,fn)
    local b=UI.Button(parent,label,width or 125,24)
    -- Search controls use neutral edges; gold is reserved for the search action.
    UI.Backdrop(b,UI.colors.raised,UI.colors.hudEdge)
    b:HookScript("OnLeave",function() UI.Backdrop(b,UI.colors.raised,UI.colors.hudEdge) end)
    if b.label then b.label:SetWidth((width or 125)-12); b.label:SetWordWrap(false) end
    b:SetPoint("TOPLEFT",x,y); b:SetScript("OnClick",fn)
    return b
end
local function Label(parent,label,x,y)
    local t=UI.Text(parent,"GameFontHighlightSmall",label,UI.colors.text)
    t:SetPoint("TOPLEFT",x,y); return t
end
function Tools:OpenPanel(w)
    if not self.panel then self:BuildPanel(w) end
    local owner=w.resultsPanel:GetParent()
    self.panel:SetScale(math.min(1,math.max(.6,(owner:GetWidth()-24)/720),math.max(.6,(owner:GetHeight()-24)/510)))
    self.panel:Show(); self:RefreshPanel(w)
end

function Tools:RefreshPanel(w)
    if not self.panel or not self.panel:IsShown() then return end
    for key,c in pairs(self.compositionChecks) do
        c:SetChecked(key:match("^style") and w.groupFilters[key]~=false or w.groupFilters[key]==true)
    end
    for key,e in pairs(self.compositionFields) do e:SetText(tostring(w.groupFilters[key] or "")) end
    for id,b in pairs(self.specButtons) do b:SetAlpha((w.groupFilters.excludedSpecs or {})[id] and .3 or 1) end
    for key,c in pairs(self.languageChecks) do c:SetChecked(not w.groupFilters.languages or w.groupFilters.languages[key]~=false) end
end

function Tools:BuildPanel(w)
    local p=UI.Panel(w.resultsPanel,UI.colors.window,UI.colors.line)
    p:SetSize(720,510); p:SetPoint("CENTER",w.resultsPanel:GetParent(),"CENTER",0,0)
    UI.Backdrop(p,UI.colors.window,UI.colors.hudEdge)
    p:SetFrameStrata("DIALOG"); p:EnableMouse(true); self.panel=p
    Label(p,L("Состав / стиль"),16,-14)
    Button(p,"×",676,-8,28,function() p:Hide() end)
    local composition=UI.Panel(p,UI.colors.panel,UI.colors.hudEdge)
    composition:SetPoint("TOPLEFT",12,-38); composition:SetPoint("BOTTOMRIGHT",-12,12)
    self.compositionChecks={}; self.compositionFields={}; self.specButtons={}; self.languageChecks={}
    local function Check(key,label,x,y,width)
        local c=UI.CheckBox(composition,label,false,function(on) w.groupFilters[key]=on; w:Refresh() end)
        c:SetPoint("TOPLEFT",x,y); c:SetWidth(width or 160); self.compositionChecks[key]=c
    end
    for i,label in ipairs({L("Обучение"),L("Непринуждённый"),L("Серьёзный"),L("Помощь игрокам")}) do Check("style"..i,label,12+(i-1)*170,-12) end
    for i,def in ipairs({{"tanksMin",L("Танков от")},{"healersMin",L("Лекарей от")},{"damageMin",L("Бойцов от")}}) do
        local key=def[1]; local x=12+(i-1)*228
        Label(composition,def[2],x,-57)
        local e,b=UI.NumberBox(composition,50,22); b:SetPoint("TOPLEFT",x+135,-50)
        e:SetScript("OnTextChanged",function(field,user) if user then w.groupFilters[key]=field:GetText(); JP:RequestRefresh(.2) end end)
        self.compositionFields[key]=e
    end
    Label(composition,L("Специализации: нажми, чтобы исключить из состава."),12,-92)
    local y=-118
    for _,role in ipairs({"TANK","HEALER","DAMAGER"}) do
        Label(composition,UI.RoleIcon(role,18),12,y-5)
        local n=0
        for _,spec in ipairs(self:Specs()) do
            if spec.role==role then
                local item=spec
                local b=UI.IconButton(composition,spec.icon,26)
                b:SetPoint("TOPLEFT",50+(n%20)*30,y-math.floor(n/20)*30)
                b:SetScript("OnClick",function()
                    local excluded=w.groupFilters.excludedSpecs or {}; w.groupFilters.excludedSpecs=excluded
                    excluded[item.id]=not excluded[item.id] or nil
                    self:RefreshPanel(w); w:Refresh()
                end)
                b:HookScript("OnEnter",function() UI.Tooltip(b,item.name,L("Специализации: нажми, чтобы исключить из состава.")) end)
                b:HookScript("OnLeave",GameTooltip_Hide)
                self.specButtons[item.id]=b; n=n+1
            end
        end
        y=y-math.max(1,math.ceil(n/20))*30-6
    end
    for i,def in ipairs({{"noLeavers",L("Без покидающих группы")},{"autoAcceptOnly",L("Автоматический приём")},
        {"myRealm",L("Мой сервер")},{"myFaction",L("Моя фракция")},
        {"needsTank",L("Нужен танк")},{"needsHealer",L("Нужен лекарь")},{"needsDamage",L("Нужен боец")}}) do
        Check(def[1],def[2],12+((i-1)%3)*225,-290-math.floor((i-1)/3)*27,215)
    end
    Label(composition,L("Языки поиска"),12,-380)
    for i,def in ipairs({{"english","English"},{"russian",L("Русский")},{"german","Deutsch"},{"french","Français"},{"spanish","Español"},{"italian","Italiano"}}) do
        local key=def[1]
        local c=UI.CheckBox(composition,def[2],true,function(on)
            local languages=w.groupFilters.languages or {}; w.groupFilters.languages=languages
            languages[key]=on
        end)
        c:SetPoint("TOPLEFT",12+((i-1)%3)*225,-402-math.floor((i-1)/3)*26); c:SetWidth(210); self.languageChecks[key]=c
    end
end

function Tools:BuildToolbar(w)
    self:ClearRemovedFilters(w.groupFilters)
    local parent=CreateFrame("Frame",nil,w.resultsPanel)
    parent:SetPoint("TOPLEFT",0,0); parent:SetSize(720,72); w.toolsToolbar=parent
    local function Mode(raid)
        if InCombatLockdown() or JP.GroupSearchUI.searchPending then return end
        if JP.RaidFinder and (w.groupFilters.category=="raid")~=raid then JP.RaidFinder:Switch(w,raid) end
        JP.GroupSearchUI:RequestBlizzardSearch(w)
    end
    w.modeButton=Button(parent,L("Рейды"),606,-8,103,function() Mode(true) end)
    w.modeButton:ClearAllPoints(); w.modeButton:SetParent(w.resultsPanel)
    w.modeButton:SetPoint("TOPRIGHT",-12,-8)
    w.mplusModeButton=Button(w.resultsPanel,"Mythic+",0,-8,103,function() Mode(false) end)
    w.mplusModeButton:ClearAllPoints(); w.mplusModeButton:SetPoint("RIGHT",w.modeButton,"LEFT",-6,0)
    w.filtersButton=Button(parent,L("Доп. фильтр"),12,-38,134,function() self:OpenPanel(w) end)
    w.queryButton=Button(parent,L("Любой ключ"),154,-38,200,function() self:EditQuery(w) end)
    w.queryButton.label:ClearAllPoints()
    w.queryButton.label:SetPoint("LEFT",w.queryButton,"LEFT",12,0)
    w.queryButton.label:SetPoint("RIGHT",w.queryButton,"RIGHT",-12,0)
    w.queryButton.label:SetJustifyH("LEFT")
    -- The generic button press animation reanchors its caption to CENTER.
    w.queryButton:SetScript("OnMouseDown",nil)
    w.queryButton:SetScript("OnMouseUp",nil)
    w.queryButton:HookScript("OnEnter",function(b) UI.Tooltip(b,L("Поиск по уровню"),L("Введи 10-10 для +10 или 10-12 для диапазона. Затем нажми «Обновить».")) end)
    w.queryButton:HookScript("OnLeave",GameTooltip_Hide)
    w.clearQueryButton=Button(parent,"x",356,-38,24,function()
        if InCombatLockdown() or JP.GroupSearchUI.searchPending then return end
        self:ClearQuery(w); w:Refresh(); JP.GroupSearchUI:RequestBlizzardSearch(w)
    end)
    if w.scan then
        w.scan:SetParent(parent); w.scan:ClearAllPoints(); w.scan:SetPoint("TOPLEFT",386,-38); w.scan:SetSize(100,24)
    end
    parent:HookScript("OnHide",function() self:EndEdit(); if self.panel then self.panel:Hide() end end)
end

function Tools:UpdateToolbar(w)
    if not w.queryButton then return end
    local width=math.max(720,w.resultsPanel:GetWidth())
    w.toolsToolbar:SetSize(width,72)
    w.toolsToolbar:SetScale(math.min(1,(w.resultsPanel:GetWidth()-8)/720))
    local function Place(button,x,y,size)
        button:ClearAllPoints(); button:SetPoint("TOPLEFT",x,y); button:SetWidth(size)
    end
    local queryWidth=width-300
    Place(w.queryButton,12,-38,queryWidth)
    Place(w.clearQueryButton,16+queryWidth,-38,24)
    if w.scan then Place(w.scan,46+queryWidth,-38,100) end
    Place(w.filtersButton,154+queryWidth,-38,134)
    local query=self:QueryText()
    local raid=w.groupFilters.category=="raid"
    local modeHost=(raid and w.raidCards or w.cardsPanel) or w.resultsPanel
    w.mplusModeButton:SetParent(modeHost); w.mplusModeButton:ClearAllPoints(); w.mplusModeButton:SetPoint("TOPLEFT",8,-8)
    w.modeButton:SetParent(modeHost); w.modeButton:ClearAllPoints(); w.modeButton:SetPoint("LEFT",w.mplusModeButton,"RIGHT",6,0)
    w.modeButton:SetHeight(21); w.mplusModeButton:SetHeight(21)
    UI.Backdrop(w.modeButton,raid and UI.colors.raised or UI.colors.field,raid and UI.colors.accent or UI.colors.hudEdge)
    UI.Backdrop(w.mplusModeButton,not raid and UI.colors.raised or UI.colors.field,not raid and UI.colors.accent or UI.colors.hudEdge)
    w.queryButton:SetText((self.edit or query~="") and query or (raid and L("Название группы") or L("Любой ключ")))
    UI.Backdrop(w.queryButton,UI.colors.field,self.edit and UI.colors.accent or UI.colors.hudEdge)
    w.queryButton.label:SetTextColor(UI.Unpack(query~="" and UI.colors.text or UI.colors.muted))
    -- Native glyphs inherit the parked panel's zero alpha on some clients.
    -- Keep the readable mirror live while the original box handles input.
    w.queryButton.label:SetAlpha(1)
    if self.edit then self:CursorChanged(self.edit.box) end
    self:RefreshPanel(w)
end

function Tools:GetRole()
    local spec=GetSpecialization and GetSpecialization()
    return spec and GetSpecializationRole and GetSpecializationRole(spec) or "DAMAGER"
end

function Tools:QueryText()
    local box=LFGListFrame and LFGListFrame.SearchPanel and LFGListFrame.SearchPanel.SearchBox
    if not box then return "" end
    local ok,value=pcall(box.GetText,box)
    return ok and JP.SafeStringOrEmpty(value) or ""
end

function Tools:ClearQuery(w)
    self:EndEdit()
    if C_LFGList.ClearSearchTextFields then pcall(C_LFGList.ClearSearchTextFields) end
    JP.GroupSearchUI.manualExactLevel=nil; JP.GroupSearchUI.lastSearchTarget=nil
    if w then
        w.groupFilters.searchExactLevel=nil; w.groupFilters.keyMin=nil; w.groupFilters.keyMax=nil
        for _,key in ipairs({"keyMin","keyMax"}) do if w.filterFields[key] then w.filterFields[key]:SetText("") end end
    end
end

function Tools:AcceptQuery(w)
    w.groupFilters.keyMin=nil; w.groupFilters.keyMax=nil
    if w.groupFilters.category=="raid" then return end
    local first,last=self:QueryText():match("^%s*(%d+)%s*%-%s*(%d+)%s*$")
    first,last=tonumber(first),tonumber(last)
    if first and last and first>=2 and last>=first and last<=40 then
        w.groupFilters.keyMin=first; w.groupFilters.keyMax=last
        for _,key in ipairs({"keyMin","keyMax"}) do
            if w.filterFields[key] then w.filterFields[key]:SetText(tostring(w.groupFilters[key])) end
        end
    end
end

-- Input remains the original Blizzard EditBox. Only the ancestor panel is
-- positioned temporarily; no SetText/Insert/reparent is used on secure input.
function Tools:EndEdit()
    local e=self.edit
    if not e then return end
    self.edit=nil
    if self.caret then self.caret:Hide() end
    if e.queryFont[1] then e.w.queryButton.label:SetFont(unpack(e.queryFont)) end
    e.panel:SetAlpha(e.alpha); e.panel:ClearAllPoints()
    e.panel:SetFrameStrata(e.strata)
    for _,point in ipairs(e.points) do e.panel:SetPoint(unpack(point)) end
    for _,state in ipairs(e.raised) do
        state.frame:SetIgnoreParentAlpha(state.ignore)
        state.frame:SetFrameStrata(state.strata); state.frame:SetFrameLevel(state.level)
    end
    if self.blocker then self.blocker:Hide() end
    if e.box:HasFocus() then e.box:ClearFocus() end
    if e.extraShown and LFGListFrame.activePanel~=e.sp then e.sp:Hide() end
    if e.opened and PVEFrame:IsShown() then HideUIPanel(PVEFrame) end
    self:AcceptQuery(e.w); self:UpdateToolbar(e.w)
end

function Tools:CursorChanged(box)
    if not self.edit or self.edit.box~=box then return end
    local position=JP.SafeNumber(box:GetCursorPosition())
    if not position then return end
    local query=self:QueryText()
    position=math.max(0,math.min(#query,math.floor(position)))
    local label=self.edit.w.queryButton.label
    local font,size,flags=label:GetFont()
    if not font or not size then return end
    local caret=self.caret
    -- Native cursor coordinates include a different inset/scroll origin.
    -- Measure the visible prefix with the mirror's own font instead. The
    -- native byte position still owns arrows, Home/End and mouse selection.
    caret.measure:SetFont(font,size,flags)
    caret.measure:SetText(query:sub(1,position))
    local advance=JP.SafeNumber(caret.measure:GetStringWidth())
    if not advance then return end
    caret:SetScale(label:GetEffectiveScale()/UIParent:GetEffectiveScale())
    caret:ClearAllPoints(); caret:SetPoint("LEFT",label,"LEFT",advance,0)
    caret:SetSize(1.5,math.max(12,size))
    if not caret:IsShown() or caret.query~=query or caret.position~=position then
        caret.elapsed=0; caret:SetAlpha(1)
    end
    caret.query=query; caret.position=position; caret:Show()
end

function Tools:EditQuery(w)
    if InCombatLockdown() then JP:Print(L("Ввод поиска доступен вне боя.")); return end
    if self.edit then self:EndEdit(); return end
    if not PVEFrame or not PVEFrame_ShowFrame then JP:Print(L("Открой поиск групп Blizzard один раз и повтори.")); return end
    local opened=not PVEFrame:IsShown()
    -- Other addons may replace the stock opener. Use only the public outer
    -- frame entry point, and verify it actually stayed open before focusing.
    if JP.ListingDefaults then
        if not JP.ListingDefaults:ShowPanel() then return end
    else PVEFrame_ShowFrame("GroupFinderFrame","LFGListPVEStub") end
    local sp=LFGListFrame and LFGListFrame.SearchPanel
    local cs=LFGListFrame and LFGListFrame.CategorySelection
    if not sp or not sp.SearchBox then JP:Print(L("Открой раздел готовых групп Blizzard и повтори.")); return end
    local extraShown=not sp:IsShown()
    local category=w.groupFilters.category=="raid" and 3 or 2
    if sp.categoryID~=category or extraShown then
        local chosen
        for _,b in ipairs(cs and cs.CategoryButtons or {}) do
            if b.categoryID==category and b:IsShown() then
                chosen=chosen or b
                if category==2 or b.filters==1 then chosen=b; break end
            end
        end
        if not chosen or not LFGListSearchPanel_SetCategory then JP:Print(L("Выбери подземелья в штатном поиске Blizzard и повтори.")); return end
        if LFGListCategorySelection_SelectCategory then
            LFGListCategorySelection_SelectCategory(cs,chosen.categoryID,chosen.filters)
        end
        LFGListSearchPanel_SetCategory(sp,chosen.categoryID,chosen.filters,LFGListFrame.baseFilters)
    end
    sp:Show()
    if not PVEFrame:IsShown() then return end
    local box=sp.SearchBox
    local bx,sx=box:GetLeft(),w.queryButton:GetLeft()
    local _,by=box:GetCenter(); local _,sy=w.queryButton:GetCenter()
    local px,py=PVEFrame:GetLeft(),PVEFrame:GetBottom()
    if not bx or not sx or not by or not sy or not px or not py then return end
    local inset=box:GetTextInsets()
    local e={panel=PVEFrame,sp=sp,box=box,w=w,alpha=PVEFrame:GetAlpha(),strata=PVEFrame:GetFrameStrata(),
        points={},raised={},opened=opened,extraShown=extraShown,queryFont={w.queryButton.label:GetFont()}}
    for i=1,PVEFrame:GetNumPoints() do e.points[i]={PVEFrame:GetPoint(i)} end
    self.edit=e
    if not self.caret then
        local caret=CreateFrame("Frame",nil,UIParent)
        caret:SetFrameStrata("TOOLTIP"); caret:SetFrameLevel(110); caret:EnableMouse(false)
        local texture=caret:CreateTexture(nil,"OVERLAY"); texture:SetAllPoints()
        texture:SetColorTexture(.95,.98,1,1)
        caret.measure=caret:CreateFontString(nil,"OVERLAY")
        caret.measure:Hide()
        caret:SetScript("OnUpdate",function(f,elapsed)
            if not self.edit or not self.edit.box:HasFocus() then f:Hide(); return end
            f.elapsed=(f.elapsed or 0)+elapsed; f:SetAlpha(f.elapsed%1<.5 and 1 or 0)
        end)
        caret:Hide(); self.caret=caret
    end
    self.caret:SetScale(box:GetEffectiveScale()/UIParent:GetEffectiveScale())
    local ps,bs,ss=PVEFrame:GetEffectiveScale(),box:GetEffectiveScale(),w.queryButton:GetEffectiveScale()
    local font,size,flags=box:GetFont()
    if font and size then w.queryButton.label:SetFont(font,size*bs/ss,flags) end
    PVEFrame:SetAlpha(0); PVEFrame:ClearAllPoints()
    -- An alpha-zero EditBox cannot accept normal clicks unless it is raised
    -- above the blocker. Preserve each property for focus loss and /reload.
    for _,frame in ipairs({box,sp.AutoCompleteFrame}) do
        e.raised[#e.raised+1]={frame=frame,ignore=frame:IsIgnoringParentAlpha(),strata=frame:GetFrameStrata(),level=frame:GetFrameLevel()}
        frame:SetIgnoreParentAlpha(true); frame:SetFrameStrata("TOOLTIP"); frame:SetFrameLevel(100)
    end
    PVEFrame:SetFrameStrata("LOW")
    -- Align the native text origin, not the centre of its much narrower box,
    -- with the caption's 12 px inset. Keep the native field itself untouched.
    PVEFrame:SetPoint("BOTTOMLEFT",UIParent,"BOTTOMLEFT",px+((sx+12)*ss-(bx+inset)*bs)/ps,py+(sy*ss-by*bs)/ps)
    if not self.blocker then
        self.blocker=CreateFrame("Frame",nil,UIParent); self.blocker:SetFrameStrata("HIGH"); self.blocker:SetFrameLevel(1); self.blocker:EnableMouse(true)
    end
    self.blocker:SetAllPoints(PVEFrame); self.blocker:Show()
    if not self.queryHooks then
        self.queryHooks=true
        box:HookScript("OnTextChanged",function() if self.edit then self:UpdateToolbar(w) end end)
        box:HookScript("OnCursorChanged",function(owner,x,y,width,height) self:CursorChanged(owner,x,y,width,height) end)
        box:HookScript("OnEditFocusLost",function() self:EndEdit() end)
        box:HookScript("OnEscapePressed",function() self:EndEdit() end)
        box:HookScript("OnEnterPressed",function() self:EndEdit() end)
        PVEFrame:HookScript("OnHide",function() self:EndEdit() end)
        local events=CreateFrame("Frame"); self.inputEvents=events
        events:RegisterEvent("PLAYER_REGEN_DISABLED")
        events:SetScript("OnEvent",function() self:EndEdit() end)
    end
    local ok=pcall(box.SetFocus,box)
    if not ok then self:EndEdit(); JP:Print(L("Открой штатный поиск Blizzard для ввода диапазона.")) end
    self:UpdateToolbar(w)
end
