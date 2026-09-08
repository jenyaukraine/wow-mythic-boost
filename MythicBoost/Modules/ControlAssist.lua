local _, JP = ...
local UI, L, C = JP.UI, JP.L, JP.UI.colors
local Assist = {}
-- Curated manual crowd control, cross-checked against OmniCD Spells_Mainline.
-- IsPlayerSpell filters class, spec, talents and race; never infer usability
-- from combat cooldowns. Do not include taunts or passive proc talents.
-- Entry: spell ID, optional target unit, optional alternate learned spell ID.
local SPELLS = {
    {102793}, {132469}, {99}, {5211, "target"}, {22570, "target"}, -- druid
    {207167}, {221562, "target"}, {108199, "target"}, -- death knight
    {179057}, {207684}, {202137}, {217832, "target"}, {211881, "target"}, {202138}, -- demon hunter
    {19577, "target", 474421}, {187650}, {186387}, {213691, "target"}, {109248}, -- hunter
    {31661}, {157981}, {113724}, {157980, "target"}, {449700, "target"}, -- mage
    {119381}, {116844}, {115078, "target"}, -- monk
    {853, "target"}, {115750}, {20066, "target"}, -- paladin
    {8122}, {88625, "target"}, {64044, "target"}, -- priest
    {408, "target"}, {2094, "target"}, {1776, "target"}, -- rogue
    {192058}, {51490}, {197214}, {51514, "target"}, -- shaman
    {30283}, {5484}, {6789, "target"}, -- warlock
    {46968}, {107570, "target"}, {5246, "target"}, -- warrior
    {20549}, {255654}, {107079, "target"}, {287712, "target"}, -- racial
    {368970}, {357214}, -- evoker / dracthyr knock-ups and knockbacks
}
local DRUID_SEQUENCE = {102793, 132469, 99, 20549, 255654, 368970, 357214}
local ICON_SIZE, STEP, INSET, COLUMNS, MAX_ICONS = 42, 50, 8, 5, 8
local function ShortName(id)
    if id == 132469 then return L("Тайфун") end
    if id == 102793 then return L("Вихрь") end
    if id == 99 then return L("Рык") end
    if id == 5211 then return L("Стан") end
    if id == 20549 then return L("Топот") end
    return C_Spell.GetSpellName(id)
end
local function Settings() return JP.Settings("controlAssist", {enabled=true}) end

function Assist:CacheSpells()
    if InCombatLockdown() then self.spellsPending = true; return end
    self.spellsPending = nil
    self.spells, self.spellUnits = {}, {}
    for _, entry in ipairs(SPELLS) do
        local id = entry[1]
        if not JP.SafeBoolean(IsPlayerSpell(id)) and entry[3] then id = entry[3] end
        if #self.spells < MAX_ICONS and JP.SafeBoolean(IsPlayerSpell(id)) and JP.SafeString(C_Spell.GetSpellName(id)) then
            self.spells[#self.spells+1] = id
            self.spellUnits[id] = entry[2]
        end
    end
    if self.frame then
        local width = math.max(66, math.min(COLUMNS, #self.spells) * STEP - (STEP-ICON_SIZE) + INSET*2)
        self.frame:SetWidth(width)
        self.frame:SetHeight(#self.spells > COLUMNS and 132 or 70)
        for i, icon in ipairs(self.icons) do
            local id = self.spells[i]
            icon.spellID = id; icon:SetShown(id ~= nil)
            icon:ClearAllPoints(); icon:SetPoint("TOPLEFT", INSET+((i-1)%COLUMNS)*STEP, -INSET-math.floor((i-1)/COLUMNS)*62)
            -- AoE stays self-centred; ground spells retain the targeting cursor.
            icon:SetAttribute("unit", id and self.spellUnits[id] or nil)
            icon:SetAttribute("spell", id)
            if id and not self.preview then icon:SetAttribute("type", "spell") else icon:SetAttribute("type", nil) end
            if id then
                icon.texture:SetTexture(C_Spell.GetSpellTexture(id))
                icon.name:SetText(ShortName(id))
            end
        end
        local sequence = {}
        local druid = JP.SafeBoolean(IsPlayerSpell(102793)) or JP.SafeBoolean(IsPlayerSpell(132469))
            or JP.SafeBoolean(IsPlayerSpell(99))
        for _, id in ipairs(druid and DRUID_SEQUENCE or self.spells) do
            if JP.SafeBoolean(IsPlayerSpell(id)) then
                local name = JP.SafeString(C_Spell.GetSpellName(id))
                if name then sequence[#sequence+1] = name end
            end
        end
        self.sequence:SetAttribute("type", self.running and not self.preview and #sequence > 0 and "macro" or nil)
        self.sequence:SetAttribute("macrotext", #sequence > 0
            and ("/castsequence " .. (druid and "[@player] " or "") .. "reset=60 " .. table.concat(sequence, ", ")) or nil)
    end
end

function Assist:Layout()
    if not self.frame or InCombatLockdown() then return end
    local p = Settings().position
    self.frame:ClearAllPoints()
    if p then self.frame:SetPoint(p.point, UIParent, p.relativePoint, p.x, p.y)
    else self.frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 225) end
    self.frame:EnableMouse(self.preview == true)
end

function Assist:Update()
    local unit = "target"
    for i, id in ipairs(self.spells or {}) do
        local icon = self.icons[i]
        local duration = C_Spell.GetSpellCooldownDuration(id, true)
        if type(duration) ~= "nil" then
            icon.cooldown:SetCooldownFromDurationObject(duration)
            icon.ready:SetAlphaFromBoolean(duration:IsZero(), 1, 0)
        else icon.cooldown:Clear(); icon.ready:SetAlpha(0) end
        local inRange = JP.SafeOptionalBoolean(C_Spell.IsSpellInRange(id, unit))
        -- Unknown AoE reach is not a failed or successful range check.
        icon.range:SetText(inRange == nil and "" or (inRange and "OK" or L("Далеко")))
        icon.range:SetTextColor(UI.Unpack(inRange == nil and C.muted or (inRange and C.green or C.red)))
    end
end

function Assist:Refresh()
    if not self.frame then return end
    local enabled = self.running and Settings().enabled ~= false and #(self.spells or {}) > 0
    local shown = enabled and (self.preview or InCombatLockdown())
    if not InCombatLockdown() then
        local visibility = enabled and (self.preview and "show" or "[combat] show; hide") or "hide"
        if self.visibility ~= visibility then RegisterStateDriver(self.frame, "visibility", visibility); self.visibility = visibility end
        self.frame:SetShown(shown)
        self:Layout()
    end
    self.ticker:SetScript("OnUpdate", shown and self.tick or nil)
    if shown then self:Update() end
end

function Assist:SetUnlocked(value)
    if InCombatLockdown() then return end
    self.preview = value == true; self:CacheSpells(); self:Refresh()
end
function Assist:Create()
    if self.frame then return end
    if InCombatLockdown() then return end
    -- Actual manual spell buttons. Secure visibility owns combat Show/Hide;
    -- attributes, spell list, parent layout and preview change only out of combat.
    local f = UI.HUDPanel(UIParent, "MythicBoostControlAssist", 208, 70, "SecureHandlerStateTemplate")
    f:SetFrameStrata("MEDIUM"); self.frame = f; self.icons = {}
    self.sequence = CreateFrame("Button", "MythicBoostControlSequence", UIParent, "SecureActionButtonTemplate")
    self.sequence:SetSize(1, 1); self.sequence:Hide()
    self.sequence:RegisterForClicks("AnyDown", "AnyUp")
    self.sequence:SetAttribute("useOnKeyDown", false)
    for i = 1, MAX_ICONS do
        local icon = CreateFrame("Button", "MythicBoostControlSpell"..i, f, "SecureActionButtonTemplate")
        icon:SetSize(ICON_SIZE, ICON_SIZE)
        icon:SetFrameLevel(f:GetFrameLevel()+5)
        icon:SetAttribute("useOnKeyDown", false)
        icon:SetPoint("TOPLEFT", INSET+(i-1)*STEP, -INSET)
        icon.texture = icon:CreateTexture(nil, "ARTWORK"); icon.texture:SetAllPoints()
        icon.texture:SetTexCoord(.08, .92, .08, .92)
        icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
        icon.cooldown:SetAllPoints(); icon.cooldown:SetDrawEdge(false)
        icon:RegisterForClicks("AnyDown", "AnyUp"); icon:EnableMouse(true); icon.cooldown:EnableMouse(false)
        icon.cooldown:SetMouseClickEnabled(false); icon.cooldown:SetMouseMotionEnabled(false)
        icon:SetHighlightTexture("Interface/Buttons/ButtonHilight-Square", "ADD")
        icon.cooldown:SetHideCountdownNumbers(false)
        icon.ready = icon:CreateTexture(nil, "OVERLAY")
        icon.ready:SetPoint("BOTTOMLEFT", 0, -2); icon.ready:SetPoint("BOTTOMRIGHT", 0, -2)
        icon.ready:SetHeight(2); icon.ready:SetColorTexture(.28, .92, .56, 1)
        icon.range = UI.Text(icon, "GameFontHighlightSmall", "", C.muted)
        icon.range:SetPoint("CENTER", 0, 0)
        icon.name = UI.Text(icon, "GameFontHighlightSmall", "", C.text)
        icon.name:SetPoint("TOP", icon, "BOTTOM", 0, -5); icon.name:SetWidth(STEP)
        icon.name:SetWordWrap(false)
        icon:SetScript("OnEnter", function(button)
            if not button.spellID then return end
            GameTooltip:SetOwner(button, "ANCHOR_TOP"); GameTooltip:SetSpellByID(button.spellID)
            GameTooltip:AddLine(L("ЛКМ: применить способность. Для наземной области выбери место."), .7, .8, .9, true)
            GameTooltip:Show()
        end)
        icon:SetScript("OnLeave", GameTooltip_Hide)
        self.icons[i] = icon
    end
    UI.HUDMover(f, Settings, function() return self.preview end)
    self.ticker = CreateFrame("Frame")
    local elapsed = 0
    self.tick = function(_, dt)
        elapsed = elapsed + dt
        if elapsed < .25 then return end
        elapsed = 0; self:Update()
    end
    f:SetScript("OnShow", function() if self.running then self.ticker:SetScript("OnUpdate", self.tick); self:Update() end end)
    f:SetScript("OnHide", function() self.ticker:SetScript("OnUpdate", nil) end)
    self.events = CreateFrame("Frame")
    self.events:SetScript("OnEvent", function(_, event)
        if not self.running then
            if not InCombatLockdown() then self:CacheSpells() end
            self:Refresh()
            if not InCombatLockdown() then self.events:UnregisterAllEvents() end
            return
        end
        if event == "SPELLS_CHANGED" or event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_ENTERING_WORLD"
            or (event == "PLAYER_REGEN_ENABLED" and self.spellsPending) then self:CacheSpells() end
        self:Refresh()
    end)
end
function Assist:Enable()
    self.running = true
    if not self.frame and InCombatLockdown() then
        if not self.bootstrap then
            self.bootstrap = CreateFrame("Frame")
            self.bootstrap:SetScript("OnEvent", function()
                self.bootstrap:UnregisterAllEvents()
                if self.running then self:Enable() end
            end)
        end
        self.bootstrap:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    self:Create(); self:CacheSpells()
    for _, event in ipairs({"PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
        "SPELLS_CHANGED", "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
        "SPELL_UPDATE_COOLDOWN"}) do self.events:RegisterEvent(event) end
    self:Refresh()
end
function Assist:Disable()
    self.running = false
    if not InCombatLockdown() and self.sequence then self.sequence:SetAttribute("type", nil) end
    if self.events then self.events:UnregisterAllEvents() end
    if self.bootstrap then self.bootstrap:UnregisterAllEvents() end
    if self.frame then self:Refresh() end
    if InCombatLockdown() and self.events then self.events:RegisterEvent("PLAYER_REGEN_ENABLED") end
end
function Assist:Destroy() self:Disable() end
JP.ControlAssist = Assist
JP:RegisterModule("ControlAssist", Assist)
