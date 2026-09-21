local _, JP = ...
local UI = JP.UI
local Prompt = {}
local DEFAULTS = {enabled=true, threshold=30, showPotions=true}
-- Active personal defenses only. IsPlayerSpell resolves spec/talent availability.
-- First group: main defense; second: self-heal or a second defense.
local SURVIVAL_SPELLS = {
    WARRIOR={{871,184364,118038},{202168,184364,118038}},
    PALADIN={{498,184662,642},{633,85673}},
    DEATHKNIGHT={{48792,48707},{48743,55233}},
    HUNTER={{264735,186265},{109304}},
    SHAMAN={{108271},{108270,8004}},
    DRUID={{22812},{108238,22842,8936}},
    MONK={{115203,243435},{122783,122278,116670}},
    ROGUE={{1966,5277},{185311,31224}},
    PRIEST={{19236},{47585,2061}},
    MAGE={{11426,235450,235313},{45438,342245}},
    WARLOCK={{104773},{108416}},
    DEMONHUNTER={{198589,203720},{196555,187827}},
    EVOKER={{363916},{374348,361469}},
}
-- Keep healthstones and healing potions as separate actions.
-- No inventory-dependent secure action is changed while combat is locked.
local ITEM_GROUPS = {
    {224464,5512}, -- Demonic Healthstone / Healthstone; count remaining uses.
    {271884,271883,241304,241305,211880,211879,211878},
}

function Prompt:Settings()
    local s = JP.Settings("survivalPrompt", DEFAULTS)
    s.threshold = math.max(JP.Limits.SURVIVAL_HP_MIN,
        math.min(JP.Limits.SURVIVAL_HP_MAX, JP.SafeNumber(s.threshold) or DEFAULTS.threshold))
    return s
end

function Prompt:BuildCurve()
    self.alertCurve = nil
    if not C_CurveUtil or not UnitHealthPercent then return end
    local curve = C_CurveUtil.CreateCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    curve:AddPoint(0, 1)
    curve:AddPoint(self:Settings().threshold / 100, 0)
    curve:AddPoint(1, 0)
    self.alertCurve = curve
end

function Prompt:CacheActions()
    if InCombatLockdown() then return end
    self.actions = {}
    local _, class = UnitClass("player")
    local chosen = {}
    for _, group in ipairs(SURVIVAL_SPELLS[class] or {}) do
        for _, id in ipairs(group) do
            if not chosen[id] and JP.SafeBoolean(IsPlayerSpell(id))
                and not JP.SafeBoolean(C_Spell.IsSpellPassive(id)) then
                self.actions[#self.actions+1] = {kind="spell", id=id}
                chosen[id] = true; break
            end
        end
    end
    if self:Settings().showPotions then
        for _, items in ipairs(ITEM_GROUPS) do
            for _, id in ipairs(items) do
                local count = JP.SafeNumber(C_Item.GetItemCount(id, false, true)) or 0
                -- Temporary usability (full HP, form, cooldown) must not remove
                -- an owned consumable from the pre-combat secure configuration.
                if count > 0 then
                    self.actions[#self.actions+1] = {kind="item", id=id}; break
                end
            end
        end
    end
    local sequence = {}
    for i, action in ipairs(self.actions) do
        if action.kind == "item" then
            sequence[#sequence+1] = "item:"..action.id
        elseif i == 1 then
            local name = JP.SafeString(C_Spell.GetSpellName(action.id))
            if name then sequence[#sequence+1] = name end
        end
    end
    local macro = #sequence > 0 and ("/castsequence [@player] reset="
        ..JP.Limits.SURVIVAL_SEQUENCE_RESET.." "..table.concat(sequence, ", ")) or nil
    -- Reapplying an identical macro would reset the player's sequence progress.
    if self.sequenceMacro ~= macro then
        self.sequence:SetAttribute("macrotext", macro)
        self.sequenceMacro = macro
    end
    self.sequence:SetAttribute("type", self.running and macro and "macro" or nil)
    for i, button in ipairs(self.buttons) do
        local action = self.actions[i]
        button.action = action
        button:SetAttribute("type", self.running and action and action.kind or nil)
        button:SetAttribute("unit", "player")
        button:SetAttribute("spell", action and action.kind == "spell" and action.id or nil)
        button:SetAttribute("item", action and action.kind == "item" and ("item:"..action.id) or nil)
        button:SetShown(action ~= nil)
        if action then
            local texture
            if action.kind == "spell" then texture = C_Spell.GetSpellTexture(action.id)
            else texture = C_Item.GetItemIconByID(action.id) end
            button.texture:SetTexture(texture or 134400)
        end
    end
    self.frame:SetWidth(16 + (#self.actions > 0 and 64 or 0) + math.max(0, #self.actions-1)*56)
end

function Prompt:ActionInfo(index)
    local action = self.actions and self.actions[index]
    if not action then return nil end
    if action.kind == "spell" then
        local name = C_Spell and C_Spell.GetSpellName and JP.SafeString(C_Spell.GetSpellName(action.id))
        local texture = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(action.id)
        return {kind=action.kind, id=action.id, name=name or tostring(action.id), texture=texture}
    end
    local name = C_Item and C_Item.GetItemNameByID and JP.SafeString(C_Item.GetItemNameByID(action.id))
    local texture = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(action.id)
    return {kind=action.kind, id=action.id, name=name or tostring(action.id), texture=texture}
end

function Prompt:Update()
    if not self.frame then return end
    -- HP goes directly through Blizzard's display curve into decorative alpha.
    -- Never branch on it, read alpha back, or fade the protected click target.
    local alpha = 0
    if self.running and InCombatLockdown() and self.alertCurve
        and JP.SafeOptionalBoolean(UnitIsDeadOrGhost("player")) == false then
        alpha = UnitHealthPercent("player", false, self.alertCurve)
    end
    for _, button in ipairs(self.buttons) do
        button.glow:SetAlpha(alpha)
        local action = button.action
        if action then
            if action.kind == "spell" then
                local duration = C_Spell.GetSpellCooldownDuration(action.id, true)
                if duration then button.cooldown:SetCooldownFromDurationObject(duration)
                else button.cooldown:Clear() end
                local usable = JP.SafeOptionalBoolean(C_Spell.IsSpellUsable(action.id))
                button.texture:SetDesaturated(usable == false)
            else
                local cd = JP.API.SurvivalItemCooldown(action.id)
                if cd then button.cooldown:SetCooldown(cd.start, cd.duration)
                else button.cooldown:Clear() end
                local count = JP.SafeNumber(C_Item.GetItemCount(action.id, false, true))
                -- Keep an exhausted item visible until combat ends; no invisible hitbox.
                button.texture:SetDesaturated(count ~= nil and count == 0)
            end
        end
    end
end

function Prompt:Create()
    if not self.events then
        self.events = UI.EventFrame(function(_, event)
            if event == "PLAYER_REGEN_ENABLED" then
                if self.running then self:Enable() else self:Disable() end
                return
            end
            if not self.running then return end
            if event == "PLAYER_ENTERING_WORLD" or event == "SPELLS_CHANGED"
                or event == "PLAYER_SPECIALIZATION_CHANGED" or event == "BAG_UPDATE_DELAYED"
                or event == "PLAYER_LEVEL_UP" then
                if not InCombatLockdown() then self:Enable(); return end
            end
            self:Update()
        end)
    end
    if self.frame or InCombatLockdown() then return end
    self.frame = UI.HUDPanel(UIParent, "MythicBoostSurvivalPrompt", 192, 80, "SecureHandlerStateTemplate")
    self.frame:SetPoint("TOP", UIParent, "TOP", 0, -240)
    self.frame:SetFrameStrata("HIGH"); self.frame:EnableMouse(false)
    self.frame:Hide(); self.buttons = {}
    self.sequence = UI.SecureAction("MythicBoostSurvivalSequence")
    for i = 1, JP.Limits.SURVIVAL_BUTTONS do
        local button = UI.SurvivalButton(self.frame, "MythicBoostSurvivalAction"..i, i == 1 and 64 or 48)
        button:SetPoint("LEFT", i == 1 and 8 or 80+(i-2)*56, 0)
        button:SetScript("OnEnter", function(owner)
            local action = owner.action
            if not action then return end
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            if action.kind == "spell" then GameTooltip:SetSpellByID(action.id)
            else GameTooltip:SetItemByID(action.id) end
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", GameTooltip_Hide)
        self.buttons[i] = button
    end
end

function Prompt:Enable()
    self:Create()
    self.running = self:Settings().enabled ~= false
    if InCombatLockdown() then
        -- The current visible actions remain intact until the secure state unlocks.
        self.events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    self.events:UnregisterAllEvents()
    self:BuildCurve(); self:CacheActions()
    RegisterStateDriver(self.frame, "visibility",
        self.running and #self.actions > 0 and "[combat,nodead] show; hide" or "hide")
    if not self.running then self:Update(); return end
    for _, event in ipairs({"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
        "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "BAG_UPDATE_COOLDOWN", "BAG_UPDATE_DELAYED",
        "SPELLS_CHANGED", "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_DEAD", "PLAYER_ALIVE"}) do
        self.events:RegisterEvent(event)
    end
    self.events:RegisterUnitEvent("UNIT_HEALTH", "player")
    self.events:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
    self.events:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
    self:Update()
end

function Prompt:Disable()
    self.running = false
    if self.events then self.events:UnregisterAllEvents() end
    if InCombatLockdown() then
        if self.events then self.events:RegisterEvent("PLAYER_REGEN_ENABLED") end
        return
    end
    if self.frame then
        UnregisterStateDriver(self.frame, "visibility")
        self.frame:Hide()
        self.sequence:SetAttribute("type", nil)
        for _, button in ipairs(self.buttons) do button:SetAttribute("type", nil) end
        self:Update()
    end
end
function Prompt:Destroy() self:Disable() end
JP.SurvivalPrompt = Prompt
JP:RegisterModule("SurvivalPrompt", Prompt)
