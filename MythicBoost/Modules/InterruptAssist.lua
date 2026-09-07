-- Inspired by ItruliaQoL FocusInterruptIndicator (MIT); see licenses/ItruliaQoL.txt.
local _, JP = ...
local L, UI = JP.L, JP.UI
local Assist = {}
local DEFAULTS = {enabled=true, size=44, x=0, y=120,
    marker=7, preserveMark=true, skipRaid=true, fallback="target", stopCasting=true,
    sound=true, announceReady=true, color=2}
local defaultTexts = {["ПРЕРВИ КАСТ"]=true, INTERRUPT=true, UNTERBRECHEN=true}
local function Settings()
    local s=JP.Settings("interruptAssist", DEFAULTS)
    if s and not s.alertStyle2 then
        if s.size==28 and s.color==1 then s.size=44; s.color=2 end
        s.alertStyle2=true
    end
    -- Older builds persisted the translated default as a custom caption.
    if s and defaultTexts[s.text] then s.text=nil end
    return s
end
Assist.Settings = Settings
function Assist:AlertText()
    local text = Settings().text
    return text and text ~= "" and text or (self.spellKind == "stun" and L("ОГЛУШЕНИЕ ПО ФОКУСУ") or L("ПРЕРВИ КАСТ"))
end
function Assist:SetAlertText(text)
    Settings().text = text ~= "" and not defaultTexts[text] and text ~= L("ОГЛУШЕНИЕ ПО ФОКУСУ") and text or nil
end
local spells = {SHAMAN={57994}, WARRIOR={6552}, PALADIN={96231}, HUNTER={147362,187707},
    ROGUE={1766}, PRIEST={15487}, DEATHKNIGHT={47528}, MAGE={2139}, WARLOCK={119914,19647,132409,119910},
    MONK={116705}, DRUID={106839,78675,5211}, DEMONHUNTER={183752}, EVOKER={351338}}
local function Known(value)
    return not (issecretvalue and issecretvalue(value)) and value == true
end
local function Learned(id)
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        if Known(C_SpellBook.IsSpellKnown(id)) then return true end
        local banks = Enum and Enum.SpellBookSpellBank
        return banks and Known(C_SpellBook.IsSpellKnown(id, banks.Pet)) or false
    end
    return (IsPlayerSpell and Known(IsPlayerSpell(id)))
        or (IsSpellKnown and (Known(IsSpellKnown(id)) or Known(IsSpellKnown(id, true))))
end
function Assist:CacheSpell()
    -- Keep the displayed spell and the protected action in sync through combat.
    if InCombatLockdown() then self.actionsDirty=true; return end
    self.spell, self.spellKind = nil, nil
    for _, id in ipairs(spells[select(2, UnitClass("player"))] or {}) do
        if Learned(id) then
            -- Mighty Bash is a fallback stop, never a school-locking interrupt.
            self.spell, self.spellKind = id, id == 5211 and "stun" or "interrupt"; break
        end
    end
end
function Assist:SpellStatus()
    local info = self.spell and C_Spell.GetSpellInfo(self.spell)
    if not info then return L("Прерывание или оглушение не изучено для текущей специализации") end
    return info.name .. (self.spellKind == "stun" and (" | " .. L("Оглушение: иммунитет цели не проверяется.")) or "")
end
function Assist:ActionBody(focus)
    self:CacheSpell()
    local info = self.spell and C_Spell.GetSpellInfo(self.spell)
    local s = Settings()
    if focus == true then
        local body = "/clearfocus [mod:alt]\n/stopmacro [mod:alt]\n/focus [@mouseover,harm,nodead][harm,nodead]"
        if s.skipRaid then body = body .. "\n/stopmacro [group:raid]" end
        if s.marker > 0 then body = body .. "\n/tm [@focus,harm,nodead] " .. (s.preserveMark and "~" or "") .. s.marker end
        return body
    end
    local body = info and ("#showtooltip " .. info.name) or ""
    if focus == "shared" then
        -- Both protected operations run on the same hardware click. Friendly,
        -- dead or absent mouseover units leave the current focus unchanged.
        body = body .. "\n/focus [@mouseover,harm,nodead]"
        if s.marker > 0 then
            body = body .. "\n/tm [@focus,harm,nodead" .. (s.skipRaid and ",nogroup:raid" or "")
                .. "] " .. (s.preserveMark and "~" or "") .. s.marker
        end
    end
    if not info then return focus == "shared" and body or nil end
    if s.stopCasting then body = body .. "\n/stopcasting" end
    if s.fallback == "nearby" then
        return body .. "\n/cast [@focus,harm,nodead] " .. info.name
            .. "\n/stopmacro [@focus,harm,nodead]\n/cleartarget\n/targetenemy\n/cast "
            .. info.name .. "\n/targetlasttarget"
    end
    return body .. "\n/cast [@focus,harm,nodead]" .. (s.fallback == "target" and "[]" or "") .. " " .. info.name
end
function Assist:UpdateActions()
    if InCombatLockdown() then self.actionsDirty=true; return end
    self.actionsDirty=nil
    for focus, button in pairs(self.actions or {}) do
        local body=self:ActionBody(focus)
        button:SetAttribute("type", body and "macro" or nil)
        button:SetAttribute("macrotext", body)
    end
    if self.frame then self.frame.text:SetText(self:AlertText()) end
    if self.status then self.status:SetText(self:SpellStatus()) end
end
function Assist:HintUnit()
    local shared = GetBindingKey and GetBindingKey("CLICK MythicBoostFocusInterruptAction:LeftButton")
    if shared and UnitExists("mouseover") and UnitCanAttack("player", "mouseover")
        and not Known(UnitIsDeadOrGhost("mouseover")) then return "mouseover" end
    if UnitExists("focus") and UnitCanAttack("player", "focus")
        and not Known(UnitIsDeadOrGhost("focus")) then return "focus" end
    if shared and Settings().fallback == "target" and UnitExists("target") and UnitCanAttack("player", "target")
        and not Known(UnitIsDeadOrGhost("target")) then return "target" end
end
function Assist:Update()
    local f = self.frame
    if not f then return end
    if not self.running then f:Hide(); return end
    if self.preview then f:SetAlpha(1); f.text:SetAlpha(1); f:Show(); return end
    local unit = self:HintUnit()
    if not Settings().enabled or not self.spell or not unit then f:Hide(); return end
    local name, _, _, _, _, _, _, locked = UnitCastingInfo(unit)
    if not name then
        name, _, _, _, _, _, locked = UnitChannelInfo(unit)
    end
    if not name then f:Hide(); return end
    local duration = C_Spell.GetSpellCooldownDuration(self.spell, true)
    if not duration then f:Hide(); return end
    -- Pass restricted booleans directly to Blizzard's rendering API.
    -- Never branch on cooldown/interruptibility or derive sound from alpha.
    f:Show()
    -- Conservatively suppress every stop hint on shielded casts, including
    -- stuns: we cannot establish that this particular enemy can be stunned.
    f:SetAlphaFromBoolean(locked, 0, 1)
    f.text:SetAlphaFromBoolean(duration:IsZero(), 1, 0)
end
function Assist:Style()
    if not self.frame then return end
    local s, f = Settings(), self.frame
    f:ClearAllPoints(); f:SetPoint("CENTER", UIParent, "CENTER", s.x, s.y)
    local font = GameFontNormal:GetFont()
    f.text:SetFont(font, s.size, "THICKOUTLINE")
    f.text:SetText(self:AlertText())
    local colors = {{.95,.98,1}, {1,.8,.12}, {.1,.8,1}}
    f.text:SetTextColor(unpack(colors[s.color] or colors[1]))
    f:EnableMouse(self.preview == true)
    self:Update()
end
function Assist:Enable()
    self.running=true
    if not self.frame then
        local f = CreateFrame("Frame", "MythicBoostInterruptHint", UIParent)
        self.frame = f
        f:SetSize(640, 64); f:SetFrameStrata("HIGH"); f:SetMovable(true)
        f:SetClampedToScreen(true); f:RegisterForDrag("LeftButton")
        f.text = f:CreateFontString(nil, "OVERLAY")
        f.text:SetAllPoints(); f.text:SetTextColor(.95, .98, 1)
        f:SetScript("OnDragStart", function() if self.preview and not InCombatLockdown() then f:StartMoving() end end)
        f:SetScript("OnDragStop", function()
            f:StopMovingOrSizing()
            local x,y = f:GetCenter(); local cx,cy = UIParent:GetCenter()
            Settings().x, Settings().y = x-cx, y-cy
        end)
    end
    if not self.actions then
        self.actions={}
        for focus,name in pairs({[true]="MythicBoostFocusAction",[false]="MythicBoostInterruptAction",
            shared="MythicBoostFocusInterruptAction"}) do
            local button=CreateFrame("Button",name,UIParent,"SecureActionButtonTemplate")
            -- SecureActionButton selects the active phase using ActionButtonUseKeyDown.
            button:RegisterForClicks("AnyDown","AnyUp")
            button:SetSize(1,1); button:SetPoint("BOTTOMLEFT",UIParent,"BOTTOMLEFT",0,0)
            button:SetAlpha(0); button:EnableMouse(false); button:Show()
            self.actions[focus]=button
        end
    end
    local f = self.frame
    for _, event in ipairs({"PLAYER_ENTERING_WORLD", "PLAYER_SPECIALIZATION_CHANGED", "SPELLS_CHANGED",
        "PLAYER_FOCUS_CHANGED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "UPDATE_BINDINGS",
        "SPELL_UPDATE_COOLDOWN", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
        "GROUP_ROSTER_UPDATE", "CHAT_MSG_ADDON", "READY_CHECK"}) do f:RegisterEvent(event) end
    for _, event in ipairs({"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_START",
        "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE"}) do f:RegisterUnitEvent(event, "focus", "mouseover", "target") end
    f:RegisterUnitEvent("UNIT_PET", "player")
    C_ChatInfo.RegisterAddonMessagePrefix("MBFocus1")
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_REGEN_DISABLED" then
            self.preview=false; f:StopMovingOrSizing(); f:EnableMouse(false)
        end
        if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_SPECIALIZATION_CHANGED" or event == "SPELLS_CHANGED" or event == "UNIT_PET" then
            self:UpdateActions()
        end
        if event == "PLAYER_REGEN_ENABLED" then
            if self.pendingMarker ~= nil then
                Settings().marker = self.pendingMarker
                self.pendingMarker = nil
                self.actionsDirty = true
            end
            if self.actionsDirty then self:UpdateActions() end
            if self.markConflictDirty then self.markConflictDirty = nil; self:SyncMarks() end
        end
        if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then self:SyncMarks() end
        if event == "CHAT_MSG_ADDON" then self:ReceiveMark(...) end
        if event == "READY_CHECK" and Settings().enabled and Settings().announceReady then self:Announce() end
        if (event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START")
            and Settings().enabled and Settings().sound and self.spellKind ~= "stun" and (...) == self:HintUnit() then
            -- Same limitation as ItruliaQoL: audio announces cast START, not
            -- interrupt readiness, because the latter can be a secret value.
            -- Do not emit this unfiltered sound for stun hints hidden by a shield.
            PlaySound(8959, "Master")
        end
        self:Update()
    end)
    self:UpdateActions(); self:Style()
end
function Assist:Disable()
    self.preview=false; self.running=false; self.marks=nil
    self.pendingMarker=nil; self.markConflictDirty=nil
    if self.frame then
        self.frame:StopMovingOrSizing(); self.frame:EnableMouse(false)
        self.frame:UnregisterAllEvents(); self.frame:SetScript("OnEvent", nil); self.frame:Hide()
    end
end
local function PlainText(value)
    return type(value) == "string" and not (type(issecretvalue) == "function" and issecretvalue(value))
end
local function FullName(unit)
    local name, realm = UnitFullName(unit)
    if not PlainText(name) or name == "" then return nil end
    realm = (PlainText(realm) and realm ~= "") and realm or GetNormalizedRealmName()
    if not PlainText(realm) or realm == "" then return nil end
    return name .. "-" .. realm
end
function Assist:Roster()
    local roster = {}
    local me = FullName("player")
    if me then roster[me] = true end
    if IsInGroup() and not IsInRaid() then
        for i=1,4 do local name=FullName("party"..i); if name then roster[name]=true end end
    end
    return roster
end
local MARKER_ORDER = {7, 6, 5, 4, 3, 2, 1, 8}
function Assist:FindFreeMarker(after, roster)
    roster = roster or self:Roster()
    local occupied, me, start = {}, FullName("player"), 0
    for name, marker in pairs(self.marks or {}) do
        if name ~= me and roster[name] then occupied[marker] = true end
    end
    for index, marker in ipairs(MARKER_ORDER) do if marker == after then start = index; break end end
    for offset = 1, #MARKER_ORDER do
        local marker = MARKER_ORDER[(start + offset - 1) % #MARKER_ORDER + 1]
        if not occupied[marker] then return marker end
    end
end
function Assist:ResolveMarkerConflict(roster)
    local s, me = Settings(), FullName("player")
    if not me or not s.enabled or s.marker == 0 or not IsInGroup() or IsInRaid() then return false end
    roster = roster or self:Roster()
    for name, marker in pairs(self.marks or {}) do
        -- A stable winner prevents both clients from changing to the same
        -- next marker forever. Never change another member's setting.
        if roster[name] and name < me and marker == s.marker then
            if InCombatLockdown() then self.markConflictDirty = true; return false end
            local free = self:FindFreeMarker(nil, roster)
            if free and free ~= s.marker then
                s.marker = free
                self:UpdateActions()
                return true
            end
        end
    end
    return false
end
function Assist:SetMarker(marker)
    if type(marker) ~= "number" or (type(issecretvalue) == "function" and issecretvalue(marker))
        or marker < 0 or marker > 8 or marker % 1 ~= 0 then return end
    if InCombatLockdown() then
        self.pendingMarker = marker
        self.markConflictDirty = true
        return
    end
    Settings().marker = marker
    self.pendingMarker = nil
    self:UpdateActions()
    self:SyncMarks()
end
function Assist:CycleMarker()
    local nextMarker = self:FindFreeMarker(self.pendingMarker or Settings().marker)
    if nextMarker then self:SetMarker(nextMarker) end
end
function Assist:SyncMarks(reply)
    local roster = self:Roster()
    self.marks = self.marks or {}
    for name in pairs(self.marks) do if not roster[name] then self.marks[name]=nil end end
    local me = FullName("player")
    self:ResolveMarkerConflict(roster)
    if me then self.marks[me] = Settings().marker end
    if Settings().enabled and IsInGroup() and not IsInRaid() then
        C_ChatInfo.SendAddonMessage("MBFocus1", (reply and "S:" or "Q:") .. Settings().marker,
            IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT" or "PARTY")
    end
    if JP.UnitFrames and JP.UnitFrames.RefreshInterruptMarker then JP.UnitFrames:RefreshInterruptMarker() end
    if self.RefreshPanel then self:RefreshPanel() end
end
function Assist:ReceiveMark(prefix, message, channel, sender)
    if not PlainText(prefix) or not PlainText(message) or not PlainText(channel) or not PlainText(sender) then return end
    if prefix ~= "MBFocus1" or (channel ~= "PARTY" and channel ~= "INSTANCE_CHAT") then return end
    if not Settings().enabled or IsInRaid() then return end
    if not sender:find("-",1,true) then
        local realm = GetNormalizedRealmName()
        if not PlainText(realm) or realm == "" then return end
        sender=sender.."-"..realm
    end
    if sender == FullName("player") or not self:Roster()[sender] then return end
    local kind, marker = message:match("^([QS]):([0-8])$")
    if not kind then return end
    self.marks = self.marks or {}; self.marks[sender]=tonumber(marker)
    -- One response at most per second, never an echo of another response.
    local changed = self:ResolveMarkerConflict()
    if changed or (kind == "Q" and (not self.lastReply or GetTime()-self.lastReply>=1)) then
        self.lastReply=GetTime(); self:SyncMarks(true)
    elseif self.RefreshPanel then self:RefreshPanel() end
end
function Assist:FreeMarker()
    local marker = self:FindFreeMarker()
    if marker then self:SetMarker(marker) end
end
function Assist:Announce()
    if not IsInGroup() or IsInRaid() or Settings().marker == 0 then return end
    if self.lastAnnouncement and GetTime()-self.lastAnnouncement < 10 then return end
    self.lastAnnouncement=GetTime()
    SendChatMessage("[MythicBoost] My interrupt focus: {rt" .. Settings().marker .. "}",
        IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT" or "PARTY")
end
JP.InterruptAssist=Assist
JP:RegisterModule("InterruptAssist",Assist)
