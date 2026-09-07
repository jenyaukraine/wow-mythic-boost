local _, JP = ...
local A, UI, L = JP.InterruptAssist, JP.UI, JP.L

function A:Build(parent)
    local s = self.Settings()
    local bindingButtons = {}
    local function CurrentKey(focus)
        return self:BindingKey(focus)
    end
    local function RefreshBindings()
        for focus, entry in pairs(bindingButtons) do
            entry.button.label:SetText(entry.label..": "..(CurrentKey(focus) or L("Нет")))
        end
    end
    -- The page scrolls even at minimum window size; the footer stays visible.
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 24, -124); scroll:SetPoint("BOTTOMRIGHT", -32, 56)
    local page = CreateFrame("Frame", nil, scroll)
    page:SetSize(560, 520); scroll:SetScrollChild(page)
    scroll:SetScript("OnSizeChanged", function(_,w) page:SetWidth(math.max(200,w)) end)
    local status = UI.Text(parent,"GameFontHighlightSmall","",UI.colors.accent)
    status:SetPoint("BOTTOMLEFT",24,14); status:SetPoint("BOTTOMRIGHT",-24,14); status:SetHeight(36)
    status:SetJustifyH("LEFT")
    self.status=status
    local capture=CreateFrame("Frame",nil,parent)
    capture:Hide()
    capture:SetScript("OnKeyDown",function(f,key)
        if InCombatLockdown() or key=="ESCAPE" then f:Hide(); return end
        if key=="LSHIFT" or key=="RSHIFT" or key=="LCTRL" or key=="RCTRL" or key=="LALT" or key=="RALT" then return end
        if IsShiftKeyDown() then key="SHIFT-"..key end
        if IsControlKeyDown() then key="CTRL-"..key end
        if IsAltKeyDown() then key="ALT-"..key end
        local ok, mode, conflict=self:BindAction(f.focusAction,key)
        if ok then
            status:SetText((mode=="shared" and L("Общая клавиша фокуса и прерывания") or f.label)..": "..key)
            RefreshBindings()
        elseif mode=="busy" then
            status:SetText(L("Клавиша занята: ")..key.." — "..conflict)
        else
            status:SetText(L("Не удалось назначить клавишу"))
        end
        f:Hide()
    end)
    capture:SetScript("OnShow",function(f) f:EnableKeyboard(true); f:SetPropagateKeyboardInput(false) end)
    capture:SetScript("OnHide",function(f) f:EnableKeyboard(false) end)
    capture:RegisterEvent("PLAYER_REGEN_DISABLED")
    capture:RegisterEvent("UPDATE_BINDINGS")
    capture:SetScript("OnEvent",function(f,event)
        if event=="UPDATE_BINDINGS" then RefreshBindings() else f:Hide() end
    end)
    parent:HookScript("OnShow",RefreshBindings)
    local sections, tabs = {}, {}
    local activeSection, origin = 1, 0
    local function Track(frame)
        sections[activeSection] = sections[activeSection] or {}
        table.insert(sections[activeSection], frame)
        return frame
    end
    local function Text(text,y)
        y = y + origin
        local t=UI.Text(page,"GameFontHighlightSmall",text,UI.colors.text)
        t:SetPoint("TOPLEFT",0,y); t:SetPoint("TOPRIGHT",-8,y); t:SetJustifyH("LEFT")
        return Track(t)
    end
    local function Button(label,y,fn)
        y = y + origin
        local b=UI.Button(page,label,320,30); b:SetPoint("TOPLEFT",0,y)
        b:SetPoint("TOPRIGHT",page,"TOPRIGHT",-8,y)
        b.label:ClearAllPoints(); b.label:SetPoint("LEFT",8,0); b.label:SetPoint("RIGHT",-8,0)
        b.label:SetWordWrap(false)
        b:SetScript("OnClick",function()
            if InCombatLockdown() then status:SetText(L("Доступно вне боя")); return end
            fn(b)
        end)
        return Track(b)
    end
    local function Check(label,key,y,fn)
        y = y + origin
        local c=UI.CheckBox(page,label,s[key],function(value)
            s[key]=value
            if fn then fn() end
            self:UpdateActions()
        end)
        c:SetPoint("TOPLEFT",0,y)
        c:SetPoint("TOPRIGHT",page,"TOPRIGHT",-8,y)
        return Track(c)
    end
    Text(L("1. Подсказка"),0)
    Check(L("Подсказка прерывания по фокусу"),"enabled",-28,function() self:Update(); self:SyncMarks() end)
    local input=CreateFrame("EditBox",nil,page,"InputBoxTemplate")
    Track(input)
    input:SetSize(300,26); input:SetPoint("TOPLEFT",6,-68); input:SetPoint("TOPRIGHT",page,"TOPRIGHT",-12,-68); input:SetAutoFocus(false)
    input:SetMaxLetters(24); input:SetText(self:AlertText())
    input:SetScript("OnEnterPressed",function(f) self:SetAlertText(f:GetText()); f:ClearFocus(); self:Style() end)
    input:SetScript("OnEscapePressed",function(f) f:SetText(self:AlertText()); f:ClearFocus() end)
    input:SetScript("OnEditFocusLost",function(f) self:SetAlertText(f:GetText()); f:SetText(self:AlertText()); self:Style() end)
    local preview=Button(L("Предпросмотр и перемещение"),-106,function(b)
        self.preview=not self.preview; self:Style()
        b.label:SetText(self.preview and L("Закончить перемещение") or L("Предпросмотр и перемещение"))
    end)
    local sizes={22,28,36,44}
    Button(L("Размер текста: ")..s.size,-142,function(b)
        local nextSize=sizes[1]
        for i,v in ipairs(sizes) do if v==s.size then nextSize=sizes[i%#sizes+1]; break end end
        s.size=nextSize; b.label:SetText(L("Размер текста: ")..s.size); self:Style()
    end)
    Button(L("Цвет: белый / золотой / голубой"),-178,function() s.color=s.color%3+1; self:Style() end)
    Button(L("Сбросить положение"),-214,function() s.x=0; s.y=120; self:Style() end)
    Check(L("Звук начала каста фокуса"),"sound",-254)
    Text(L("Звук сообщает о начале каста, даже если прерывание недоступно. Текст учитывает готовность."),-290)
    activeSection, origin = 2, 385
    Text(L("2. Горячие клавиши"),-385)
    local fallbackLabels={target=L("Без фокуса: текущая цель"),none=L("Без фокуса: ничего"),nearby=L("Без фокуса: ближайший враг")}
    local order={target="none",none="nearby",nearby="target"}
    Button(fallbackLabels[s.fallback] or fallbackLabels.target,-415,function(b)
        s.fallback=order[s.fallback] or "target"; b.label:SetText(fallbackLabels[s.fallback]); self:UpdateActions()
    end)
    Text(L("Ближайший враг: временно переключает цель, затем возвращает её. Выбор кастера не гарантирован."),-452)
    Check(L("Останавливать своё заклинание для прерывания"),"stopCasting",-496)
    Text(L("Наведи мышь на врага и нажми фокус. Alt с этой кнопкой снимает фокус."),-536)
    for i,focus in ipairs({true,false}) do
        local label=focus and L("Назначить клавишу фокуса") or L("Назначить клавишу прерывания")
        local keySetting=focus and "focusKey" or "interruptKey"
        local bindButton
        bindButton=Button(label..": "..(CurrentKey(focus) or L("Нет")),-568-i*36,function()
            capture.button=self.actions[focus]
            capture.focusAction=focus
            capture.keySetting=keySetting
            capture.label=label
            capture.uiButton=bindButton
            capture:Show(); status:SetText(L("Одинаковая клавиша объединит фокус и прерывание. Esc — отмена."))
        end)
        bindingButtons[focus]={button=bindButton,label=label}
    end
    Text(L("Общая клавиша: враг под мышью становится фокусом и сразу прерывается. Без наведения — прерывание по фокусу."), -657)
    Text(L("Клавиша не блокируется, если враг не кастует. Нажимай по подсказке."), -713)
    local controlLabel = L("Назначить клавишу цепочки контроля")
    local controlBind = Button(controlLabel, -776, function()
        local controls = JP.ControlAssist
        if not controls or not controls.sequence then return end
        capture.button = controls.sequence; capture.focusAction = "control"
        capture.keySetting = "controlKey"; capture.label = controlLabel
        capture:Show(); status:SetText(L("Нажми сочетание клавиш. Esc — отмена. Занятые клавиши сохраняются."))
    end)
    bindingButtons.control = {button=controlBind, label=controlLabel}
    Text(L("Контроль своего класса и расы. Один успешный каст на шаг; КД не пропускаются. Сброс через 60 сек. Вихрь друида — у ног; остальные области — вручную."), -818)
    RefreshBindings()
    activeSection, origin = 3, 810
    Text(L("3. Метки группы"),-810)
    local marker=Button("",-846,function() self:SetMarker(((self.pendingMarker or s.marker)+1)%9) end)
    Check(L("Не заменять существующую метку"),"preserveMark",-886)
    Check(L("Не ставить метку в рейде"),"skipRaid",-922)
    Check(L("Сообщать мою метку при проверке готовности"),"announceReady",-958)
    Button(L("Выбрать свободную метку"),-998,function() self:FreeMarker() end)
    Button(L("Сообщить мою метку группе"),-1034,function() self:Announce() end)
    local roster=Text("",-1074)
    local function SelectSection(index)
        capture:Hide()
        input:ClearFocus()
        self.preview=false; self:Style()
        preview.label:SetText(L("Предпросмотр и перемещение"))
        for i, widgets in ipairs(sections) do
            for _, widget in ipairs(widgets) do widget:SetShown(i==index) end
            tabs[i]:SetEnabled(i~=index)
        end
        scroll:SetVerticalScroll(0)
    end
    local labels={L("1. Подсказка"),L("2. Горячие клавиши"),L("3. Метки группы")}
    for i,label in ipairs(labels) do
        local tab=UI.Button(parent,label,170,32)
        tabs[i]=tab
        tab.label:ClearAllPoints(); tab.label:SetPoint("LEFT",6,0); tab.label:SetPoint("RIGHT",-6,0)
        tab.label:SetWordWrap(false)
        tab:SetScript("OnClick",function() SelectSection(i) end)
    end
    local function LayoutTabs()
        local width=math.max(90,((parent:GetWidth() or 560)-60)/3)
        for i,tab in ipairs(tabs) do
            tab:ClearAllPoints(); tab:SetPoint("TOPLEFT",24+(i-1)*(width+6),-80); tab:SetWidth(width)
        end
    end
    parent:HookScript("OnSizeChanged",LayoutTabs)
    LayoutTabs()
    SelectSection(1)
    function self:RefreshPanel()
        marker.label:SetText(L("Моя метка: ")..(s.marker==0 and L("Нет") or "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_"..s.marker..":18|t "..s.marker))
        local rows={}
        local members=self:Roster()
        for name in pairs(members) do
            local mark=self.marks and self.marks[name]
            rows[#rows+1]=name..": "..(mark and tostring(mark) or "?")
        end
        table.sort(rows)
        roster:SetText(table.concat(rows,"  /  ").."\n"..L("Синхронизация работает с MythicBoost у участников. ? — метка неизвестна."))
    end
    parent:HookScript("OnShow",function()
        self:RefreshPanel()
        self:UpdateActions()
        input:SetText(self:AlertText())
        status:SetText(self:SpellStatus())
    end)
    parent:HookScript("OnHide",function()
        capture:Hide()
        self.preview=false; self:Style(); preview.label:SetText(L("Предпросмотр и перемещение"))
    end)
    self:RefreshPanel()
end
