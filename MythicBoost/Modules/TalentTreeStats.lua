local _, JP = ...
local Lab, UI, L = JP.TalentLab, JP.UI, JP.L
local Tree = {cards={}}
local function Call(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, value = pcall(fn, ...)
    if ok then return value end
end
local function Number(v)
    v = JP.SafeNumber(v)
    return v and v == v and v >= 0 and v < math.huge and v or nil
end
local function OOC()
    local ok, locked = pcall(InCombatLockdown)
    return ok and not JP.IsSecret(locked) and (locked == nil or locked == false)
end

local function HideCard(card)
    if GameTooltip and GameTooltip:IsOwned(card.badge) then GameTooltip_Hide() end
    card:Hide(); card:ClearAllPoints(); card.detail = nil
end

function Tree:Clear()
    for _, card in ipairs(self.cards) do HideCard(card) end
    if self.legend then self.legend:Hide() end
end

function Tree:ReleaseHistory()
    self.shares, self.sampleRefs, self.history = nil, nil, nil
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
    local panel = UI.HUDPanel(UIParent, nil, 460, 58)
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
    local labels = {
        {L("Вклад"), .2, .95, .45, 128, 62},
        {L("Попробовать"), 1, .22, .22, 211, 105},
        {L("Нет данных"), .5, .5, .5, 339, 101},
    }
    for _, item in ipairs(labels) do
        local swatch = panel:CreateTexture(nil, "ARTWORK")
        swatch:SetSize(6, 6); swatch:SetPoint("TOPLEFT", item[5], -17)
        swatch:SetColorTexture(item[2], item[3], item[4], 1)
        local label = UI.Text(panel, "GameFontHighlightSmall", item[1])
        label:SetPoint("TOPLEFT", item[5]+12, -14); label:SetWidth(item[6])
        label:SetJustifyH("LEFT"); label:SetWordWrap(false)
        label:SetTextColor(.76, .81, .85, 1)
    end
    local partialNote = UI.Text(panel, "GameFontHighlightSmall", L("~ Жёлтый: измеренный вклад, неполный замер"))
    partialNote:SetPoint("BOTTOMLEFT", 12, 8); partialNote:SetTextColor(1, .72, .25, 1)
    panel:EnableMouse(true)
    panel:SetScript("OnEnter", function()
        UI.Tooltip(panel, L("История таланта"),
            L("Доля измеренного исцеления/урона в ключах с этим талантом. Это не прирост от очка. Состав группы и подземелье влияют на результат."))
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
    local currentSpec = Number(Call(GetSpecializationInfo, Call(GetSpecialization)))
    if not config or spec ~= currentSpec then self:Clear(); return end
    local version, build = GetBuildInfo()
    version, build = JP.SafeString(version), JP.SafeString(build)
    local gameBuild = version and build and (version .. ":" .. build) or version or build
    local settings = JP.Settings("runHistory", {runs={}})
    local shares = self:GetShares(settings.runs, spec, gameBuild)
    local info = JP.SafeTable(Call(C_Traits.GetConfigInfo, config))
    local treeIDs = info and JP.SafeTable(info.treeIDs)
    if not treeIDs then self:Clear(); return end
    self:CreateLegend()
    self.legend:ClearAllPoints()
    self.legend:SetPoint("TOP", frame, "BOTTOM", 0, -6)
    self.legend:SetFrameStrata("DIALOG")
    for metric, button in pairs(self.metricButtons) do
        local active = metric == (self.metric or "healing")
        button:SetBackdropColor(active and .08 or .035, active and .20 or .045, active and .25 or .055, 1)
        button:SetBackdropBorderColor(active and .25 or .22, active and .70 or .25, active and .85 or .28, 1)
        if button.label then button.label:SetTextColor(active and .95 or .58, active and 1 or .64, active and 1 or .70, 1) end
    end
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
                    if observed and observed.partial and not selected then observed = nil end
                    count = count + 1
                    local card = self.cards[count]
                    if not card then
                        card = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
                        card:EnableMouse(false)
                        card:SetBackdrop({edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=2})
                        card.badge = CreateFrame("Button", nil, card, "BackdropTemplate")
                        card.badge:SetSize(48, 15); card.badge:SetPoint("TOP", card, "BOTTOM", 0, 2)
                        card.badge:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"})
                        card.badge:SetBackdropColor(.025,.025,.035,.95)
                        card.text = UI.Text(card.badge, "GameFontNormalSmall", "")
                        card.text:SetAllPoints()
                        card.badge:SetScript("OnEnter", function()
                            UI.Tooltip(card.badge, L("История таланта"), card.detail,
                                L("Доля измеренного исцеления/урона в ключах с этим талантом. Это не прирост от очка. Состав группы и подземелье влияют на результат."))
                        end)
                        card.badge:SetScript("OnLeave", function() if GameTooltip_Hide then GameTooltip_Hide() end end)
                        self.cards[count] = card
                    end
                    local r,g,b = .5,.5,.5
                    if observed then
                        if observed.partial then r,g,b=1,.72,.25
                        elseif selected then r,g,b=.2,.95,.45
                        elseif observed.percent > 0 then r,g,b=1,.22,.22 end
                    end
                    card:ClearAllPoints(); card:SetPoint("TOPLEFT", button, "TOPLEFT", -3, 3)
                    card:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 3, -3)
                    card:SetFrameStrata("DIALOG"); card:SetFrameLevel(frame:GetFrameLevel()+200)
                    card:SetBackdropBorderColor(r,g,b,.95); card.text:SetTextColor(r,g,b,1)
                    card.text:SetText(observed and ((observed.partial and "~" or "") .. ("%.1f%%"):format(observed.percent)) or "—")
                    card.detail = observed and (L("Ключей: %d | Ранг: %d")):format(observed.runs, observed.rank)
                        or L("Нет полных измерений для этого таланта и ранга.")
                    if observed and observed.partial then
                        card.detail = card.detail .. "\n" .. L("Неполный замер: доля сохранённых данных, не оценка всей сборки.")
                    end
                    card:Show()
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
    self.events:SetScript("OnEvent", function(_, event, addon)
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
