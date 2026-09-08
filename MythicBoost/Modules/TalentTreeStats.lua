local _, JP = ...
local Lab, UI, L = JP.TalentLab, JP.UI, JP.L
local Tree = {cards={}}
local Call = JP.SafeCall
local function Number(v)
    v = JP.SafeNumber(v)
    return type(v)=="number" and v == v and v >= 0 and v < math.huge and v or nil
end
local function OOC()
    local ok, locked = pcall(InCombatLockdown)
    return ok and not JP.IsSecret(locked) and (locked == nil or locked == false)
end

function Tree:LayoutLegend(frame)
    local panel=self.legend
    panel:SetParent(frame)
    local frameScale=Number(Call(frame.GetEffectiveScale,frame)) or 1
    local rootScale=Number(Call(UIParent.GetEffectiveScale,UIParent)) or 1
    if frameScale<=0 then frameScale=1 end
    local rootWidth=Number(Call(UIParent.GetWidth,UIParent))
    local frameWidth=Number(Call(frame.GetWidth,frame))
    local width=math.min(frameWidth and frameWidth>0 and frameWidth or 600,
        rootWidth and rootWidth>0 and rootWidth*rootScale/frameScale or 600)
    local scale=math.min(1,math.max(.3,(width-16)/600))
    panel:SetScale(scale)
    local bottom=Number(Call(frame.GetBottom,frame))
    local rootBottom=Number(Call(UIParent.GetBottom,UIParent)) or 0
    local below=bottom and bottom-rootBottom*rootScale/frameScale or 0
    panel:ClearAllPoints()
    if below>=(96*scale+12) then
        panel:SetPoint("TOP",frame,"BOTTOM",0,-6/scale)
        self.legendDock="outside"
    else
        -- A maximized talent window has no room underneath. Dock in the
        -- empty lower center, above the native loadout/apply controls.
        panel:SetPoint("BOTTOM",frame,"BOTTOM",0,60/scale)
        self.legendDock="inside"
    end
    panel:SetFrameStrata(frame:GetFrameStrata()); panel:SetFrameLevel(frame:GetFrameLevel()+2)
end

local function HideCard(card)
    if GameTooltip and GameTooltip:IsOwned(card.badge) then GameTooltip_Hide() end
    card:Hide(); card:ClearAllPoints(); card.detail = nil
    card.spellID,card.rank=nil,nil
end

function Tree:Clear()
    for _, card in ipairs(self.cards) do HideCard(card) end
    if self.legend then self.legend:Hide() end
end

function Tree:ReleaseHistory()
    self.shares, self.sampleRefs, self.history = nil, nil, nil
    self.pointContext,self.pointContextCached=nil,nil
    self.pointShares=nil
end

function Tree:GetShares(runs, spec, gameBuild)
    runs = JP.SafeTable(runs) or {}
    local count = math.min(#runs, 30)
    local same = self.shares and self.history == runs and self.shareSpec == spec
        and self.shareBuild == gameBuild and self.shareMetric == self.metric
        and #self.sampleRefs == count
    for i = 1, count do
        local run = JP.SafeTable(runs[i])
        if not same or self.sampleRefs[i] ~= (run and run.talentSample or false) then same = false; break end
    end
    if not same then
        self.pointContext,self.pointContextCached=nil,nil
        self.pointShares=nil
        self.shares = Lab:HistoricalShares(runs, self.metric or "healing", spec, gameBuild, true)
        self.sampleRefs = {}
        for i = 1, count do
            local run = JP.SafeTable(runs[i])
            self.sampleRefs[i] = run and run.talentSample or false
        end
        self.history, self.shareSpec, self.shareBuild, self.shareMetric = runs, spec, gameBuild, self.metric
    end
    return self.shares
end

function Tree:CreateLegend()
    if self.legend then return end
    local panel = UI.HUDPanel(UIParent, nil, 600, 96)
    panel:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
    panel:SetBackdropColor(.025, .032, .042, .98)
    panel:SetBackdropBorderColor(.30, .32, .34, .92)
    panel:SetClampedToScreen(true)
    self.legend = panel
    self.metricButtons = {}
    for i, metric in ipairs({"healing", "damage"}) do
        local button = UI.Button(panel, metric == "healing" and "HPS" or "DPS", 48, 26)
        button:SetPoint("TOPLEFT", panel, "TOPLEFT", 8 + (i-1)*52, -7)
        button:SetScript("OnClick", function() self.metric = metric; self:Refresh() end)
        self.metricButtons[metric] = button
    end
    self.pointMode=UI.Button(panel,L("Ценность очка"),130,26)
    self.pointMode:SetPoint("TOPLEFT",116,-7)
    self.pointMode:SetScript("OnClick",function() self.mode="points"; self:Refresh() end)
    self.shareMode=UI.Button(panel,L("Доля таланта от общего"),168,26)
    self.shareMode:SetPoint("TOPLEFT",252,-7)
    self.shareMode:SetScript("OnClick",function() self.mode="shares"; self:Refresh() end)
    local open=UI.Button(panel,L("Подробнее"),168,26)
    open:SetPoint("TOPRIGHT",-8,-7)
    open:SetScript("OnClick",function()
        if self.mode~="shares" and Lab.ShowPoints then Lab:ShowPoints(self.metric); return end
        Lab:CreateUI(); Lab.view="talents"; Lab.metric=self.metric or "healing"; Lab:Show()
    end)
    self.openButton=open
    self.contextText=UI.Text(panel,"GameFontHighlightSmall","")
    self.contextText:SetPoint("TOPLEFT",12,-41); self.contextText:SetWidth(576)
    self.contextText:SetJustifyH("LEFT"); self.contextText:SetWordWrap(false)
    self.note=UI.Text(panel,"GameFontHighlightSmall","")
    self.note:SetPoint("TOPLEFT",12,-60); self.note:SetWidth(576); self.note:SetHeight(30)
    self.note:SetJustifyH("LEFT"); self.note:SetWordWrap(true); self.note:SetTextColor(.76,.81,.85,1)
    panel:EnableMouse(true)
    panel:SetScript("OnEnter", function()
        UI.Tooltip(panel, L("История таланта"), L("Доля = сумма связанных заклинаний / общий результат тех же замеров x 100%."))
    end)
    panel:SetScript("OnLeave", function() if GameTooltip_Hide then GameTooltip_Hide() end end)
    panel:SetScript("OnHide", function()
        if GameTooltip and GameTooltip:IsOwned(panel) then GameTooltip_Hide() end
    end)
end

function Tree:Refresh()
    if not OOC() or not C_Traits then self:Clear(); return end
    local frame = PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
    if not frame or not frame:IsShown() or Call(frame.IsInspecting, frame) ~= false then self:Clear(); return end
    local config = Number(Call(frame.GetConfigID, frame))
    local spec = Number(Call(frame.GetSpecID, frame))
    local currentSpec = Lab.SpecID and Lab.SpecID() or Number(Call(GetSpecializationInfo, Call(GetSpecialization)))
    if not config or spec ~= currentSpec then self:Clear(); return end
    local version, build = GetBuildInfo()
    version, build = JP.SafeString(version), JP.SafeString(build)
    local gameBuild = version and build and (version .. ":" .. build) or version or build
    local settings = JP.Settings("runHistory", {runs={}})
    local shares = self:GetShares(settings.runs, spec, gameBuild)
    local pointMode=self.mode~="shares" and JP.TalentPointValue~=nil
    if pointMode and (not self.pointContextCached or self.pointScope~=JP.TalentPointValue.scope) then
        self.pointContext=JP.TalentPointValue:Context(settings.runs,self.metric or "healing",spec,gameBuild,Lab.CurrentBuild())
        local cohort={}
        for _,record in ipairs(self.pointContext and self.pointContext.records or {}) do cohort[#cohort+1]=record.run end
        self.pointShares=Lab:HistoricalShares(cohort,self.metric or "healing",spec,gameBuild,true)
        self.pointContextCached=true
        self.pointScope=JP.TalentPointValue.scope
    end
    local context=self.pointContext
    local info = JP.SafeTable(Call(C_Traits.GetConfigInfo, config))
    local treeIDs = info and JP.SafeTable(info.treeIDs)
    if not treeIDs then self:Clear(); return end
    self:CreateLegend()
    self:LayoutLegend(frame)
    for metric, button in pairs(self.metricButtons) do
        local active = metric == (self.metric or "healing")
        button:SetBackdropColor(active and .08 or .035, active and .20 or .045, active and .25 or .055, 1)
        button:SetBackdropBorderColor(active and .25 or .22, active and .70 or .25, active and .85 or .28, 1)
        if button.label then button.label:SetTextColor(active and .95 or .58, active and 1 or .64, active and 1 or .70, 1) end
    end
    self.contextText:SetText(L("Доля = сумма связанных заклинаний / общий результат тех же замеров x 100%."))
    self.note:SetText(L("Нажми на процент: отдельные прохождения и заклинания. Без подписи: источник не выделен.")
        .."\n"..L("~ Жёлтый: измеренный вклад, неполный замер"))
    if pointMode then
        self.contextText:SetText(context and (context.scope=="build" and L("Все ключи этой сборки")
            or (L("База: +%d %s")):format(context.level,context.run.mapName or L("Подземелье")))
            .." | "..(L("Замеров: %d")):format(#context.records) or L("Нет замеров"))
        self.note:SetText(context and not context.current
            and L("Расчёт относится к сохранённой сборке; текущая сборка отличается или не проверена.")
            or L("~ Оценка очка. = Доля источника. Без подписи: цена очка не измерена. Причины — в подробностях."))
    end
    self.pointMode:SetBackdropBorderColor(pointMode and .2 or .3,pointMode and .8 or .3,pointMode and 1 or .3,1)
    self.shareMode:SetBackdropBorderColor(not pointMode and .2 or .3,not pointMode and .8 or .3,not pointMode and 1 or .3,1)
    self.legend:Show()
    local count, visited = 0, 0
    for treeIndex = 1, math.min(#treeIDs, 32) do
        local treeID = treeIDs[treeIndex]
        for _, nodeID in ipairs(JP.SafeTable(Call(C_Traits.GetTreeNodes, treeID)) or {}) do
            visited = visited + 1; if visited > 1024 then break end
            local button = Call(frame.GetTalentButtonByNodeID, frame, nodeID)
            local visible = button and JP.SafeOptionalBoolean(Call(button.IsVisible or button.IsShown, button)) == true
            local node = visible and JP.SafeTable(Call(C_Traits.GetNodeInfo, config, nodeID))
            if node and count < 256 then
                local activeEntry, entryIDs = JP.SafeTable(node.activeEntry), JP.SafeTable(node.entryIDs)
                local entryID = Number(Call(button.GetEntryID, button))
                    or (activeEntry and Number(activeEntry.entryID))
                    or (entryIDs and #entryIDs == 1 and Number(entryIDs[1]))
                local entry = entryID and JP.SafeTable(Call(C_Traits.GetEntryInfo, config, entryID))
                local def = entry and JP.SafeTable(Call(C_Traits.GetDefinitionInfo, Number(entry.definitionID)))
                local spellID = def and Number(def.spellID)
                if spellID and spellID > 0 then
                    local rank = Number(node.activeRank) or 0
                    local selected = rank > 0 and activeEntry and Number(activeEntry.entryID) == entryID
                    local observed = shares[spellID .. ":" .. (selected and rank or 1)]
                    count = count + 1
                    local card = self.cards[count]
                    if not card then
                        card = CreateFrame("Frame", nil, button, "BackdropTemplate")
                        card:EnableMouse(false)
                        card:SetBackdrop({edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
                        card.badge = CreateFrame("Button", nil, card, "BackdropTemplate")
                        card.badge:SetSize(56, 15); card.badge:SetPoint("TOP", card, "BOTTOM", 0, 2)
                        card.badge:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"})
                        card.badge:SetBackdropColor(.025,.025,.035,.95)
                        card.text = UI.Text(card.badge, "GameFontNormalSmall", "")
                        card.text:SetAllPoints()
                        card.badge:SetScript("OnEnter", function()
                            UI.Tooltip(card.badge, L("История таланта"), card.detail)
                        end)
                        card.badge:SetScript("OnClick",function()
                            if self.mode~="shares" and Lab.ShowPoints then Lab:ShowPoints(self.metric); return end
                            Lab:ShowContribution(card.spellID,card.rank,self.shareSpec,self.shareBuild,self.metric)
                        end)
                        card.badge:SetScript("OnLeave", function() if GameTooltip_Hide then GameTooltip_Hide() end end)
                        self.cards[count] = card
                    end
                    local r,g,b = .5,.5,.5
                    if observed then
                        if observed.partial then r,g,b=1,.72,.25
                        elseif selected then r,g,b=.2,.95,.45
                        else r,g,b=.3,.75,1 end
                    end
                    card:SetParent(button)
                    card:ClearAllPoints(); card:SetPoint("TOPLEFT", button, "TOPLEFT", -3, 3)
                    card:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 3, -3)
                    card:SetFrameStrata(button:GetFrameStrata()); card:SetFrameLevel(button:GetFrameLevel()+1)
                    card:SetBackdropBorderColor(r,g,b,.95); card.text:SetTextColor(r,g,b,1)
                    card.text:SetText(observed and ((observed.partial and "~" or "") .. ("%.1f%%"):format(observed.percent)) or "—")
                    card.spellID,card.rank=spellID,selected and rank or 1
                    card.detail=observed and Lab:ContributionText(observed,self.metric) or nil
                    if pointMode then
                        -- Keep source shares from the reference cohort distinct
                        -- from modeled point values and unknown conditions.
                        local referenceRank=1
                        for _,e in pairs(context and context.sample.selected or {}) do
                            if e.spellID==spellID then referenceRank=e.rank; break end
                        end
                        local referenceShare=self.pointShares and self.pointShares[spellID..":"..referenceRank]
                        local p=JP.TalentPointValue:Presentation(context,spellID,self.metric or "healing",referenceShare)
                        card.text:SetText(p.badge); card.text:SetTextColor(p.r,p.g,p.b,1)
                        card:SetBackdropBorderColor(p.r,p.g,p.b,p.data and .85 or 0)
                        card.detail=p.detail
                        if p.data or p.share then card:Show() else HideCard(card) end
                    elseif observed then card:Show() else HideCard(card) end
                end
            end
        end
    end
    for index = count + 1, #self.cards do HideCard(self.cards[index]) end
end

function Tree:Enable()
    self.running = true
    if not self.events then self.events = CreateFrame("Frame") end
    self.events:RegisterEvent("ADDON_LOADED")
    self.events:RegisterEvent("PLAYER_REGEN_DISABLED")
    self.events:RegisterEvent("PLAYER_REGEN_ENABLED")
    self.events:RegisterEvent("TRAIT_CONFIG_UPDATED")
    self.events:RegisterEvent("TRAIT_NODE_CHANGED")
    self.events:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    self.events:SetScript("OnEvent", function(_, event, addon)
        if event=="TRAIT_CONFIG_UPDATED" or event=="TRAIT_NODE_CHANGED" or event=="PLAYER_SPECIALIZATION_CHANGED" then self:ReleaseHistory() end
        if event == "PLAYER_REGEN_DISABLED" then self:Clear()
        elseif event ~= "ADDON_LOADED" or addon == "Blizzard_PlayerSpells" then self:Attach() end
    end)
    self:Attach()
end

function Tree:Attach()
    local frame = PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
    if not self.running or not OOC() or not frame then return end
    if not self.driver then
        self.driver = CreateFrame("Frame", nil, frame)
        self.updateDriver = function(_, delta)
            self.elapsed = (self.elapsed or 0) + delta
            if self.elapsed >= .5 then self.elapsed = 0; self:Refresh() end
        end
        self.driver:SetScript("OnHide", function() self:Clear(); self:ReleaseHistory() end)
    end
    self.driver:SetScript("OnUpdate", self.updateDriver)
    self.driver:Show()
end

function Tree:Disable()
    self.running = false
    if self.events then self.events:UnregisterAllEvents() end
    if self.driver then self.driver:SetScript("OnUpdate", nil); self.driver:Hide() end
    self.elapsed = 0; self:Clear(); self:ReleaseHistory()
end

JP.TalentTreeStats = Tree
JP:RegisterModule("TalentTreeStats", Tree)
