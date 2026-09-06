local _, JP = ...
local UI, C = JP.UI, JP.UI.colors
local Effects = {}
JP.TempleHealerEffects = Effects

local ICON, GAP, BUFFS = 22, 3, 8
local FLOATS, LIFE, INTERVAL = 6, 1.25, .08
local OFFSETS = {-12, 14, -24, 26, -4, 6}

local function InitializeBuff(button)
    button:SetSize(ICON, ICON)
    -- Tooltip motion remains native; clicks pass through to the heal button.
    button:SetMouseClickEnabled(false); button:SetMouseMotionEnabled(true)
    local border = button:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints(); border:SetColorTexture(.18, .58, .44, .95)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1); icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(.08, .92, .08, .92); button:SetIcon(icon)
    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(icon); cooldown:SetDrawEdge(false); cooldown:SetHideCountdownNumbers(true)
    button:SetDurationCooldown(cooldown)
    local overlay = CreateFrame("Frame", nil, button)
    overlay:SetAllPoints(); overlay:EnableMouse(false)
    overlay:SetFrameLevel(cooldown:GetFrameLevel() + 1)
    local count = overlay:CreateFontString(nil, "OVERLAY")
    count:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE"); count:SetPoint("BOTTOMRIGHT", -1, 0)
    button:SetApplicationCount(count, {})
    local duration = overlay:CreateFontString(nil, "OVERLAY")
    duration:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE"); duration:SetPoint("TOPLEFT", 1, -1)
    duration:SetTextColor(.90, 1, .93); button:SetDurationText(duration, {})
    button:SetTooltipAnchorPoint("ANCHOR_RIGHT", 0, 0)
end

function Effects:ConfigureAuras(frame, enabled)
    if InCombatLockdown() then return end
    -- The mixins live in Blizzard's secure environment, not addon globals.
    -- AuraContainerInbound is the public bridge exported with the templates.
    if enabled and not frame.healAuras and AuraContainerInbound and AnchorUtil then
        frame.healAuras = {}
        for i = 1, 5 do
            local holder = CreateFrame("Frame", nil, frame)
            holder:SetSize(BUFFS * ICON + (BUFFS - 1) * GAP, ICON)
            holder:SetPoint("TOPLEFT", 45, -29); holder:EnableMouse(false); holder:Hide()
            local container = CreateFrame("AuraContainer", nil, holder, "CustomAuraContainerTemplate")
            container:SetEnabled(false); container:SetUnit("boss" .. i)
            container:SetPoint("TOPLEFT", holder, "TOPLEFT")
            container:SetMouseClickEnabled(false)
            container:SetFlowLayoutMaximumLineSize(BUFFS * ICON + (BUFFS - 1) * GAP)
            container:SetFlowLayoutAnchorPoint("TOPLEFT")
            container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
            container:AddAuraGroup("healingBuffs", "HELPFUL", {
                maxFrameCount = BUFFS, initializeFrame = InitializeBuff,
                layout = {elementSpacing = GAP, lineSpacing = GAP},
            })
            holder.container = container
            frame.healAuras[i] = holder
            -- Fixed tokens avoid retargeting a restricted aura display mid-pull.
            -- Only the secure heal-target driver changes these holders' visibility.
            frame:SetFrameRef("healAuras" .. i, holder)
        end
    end
    for _, holder in ipairs(frame.healAuras or {}) do
        holder.container:SetEnabled(enabled)
        if not enabled then holder:Hide() end
    end
end

function Effects:Clear(frame)
    local fx = frame and frame.healEffects
    if not fx then return end
    fx:SetScript("OnUpdate", nil); fx.nextAt = nil; fx.pulseAt = nil
    fx.glow:SetAlpha(0)
    for _, slot in ipairs(fx.slots) do
        slot.started = nil; slot.text:SetText(""); slot.text:Hide()
    end
end

function Effects:Tick(fx)
    local now, active = GetTime(), false
    for _, slot in ipairs(fx.slots) do
        if slot.started then
            local age = now - slot.started
            if age >= LIFE then
                slot.started = nil; slot.text:SetText(""); slot.text:Hide()
            else
                active = true
                slot.text:SetAlpha(math.min(1, age / .10, (LIFE - age) / .35))
                slot.text:ClearAllPoints()
                slot.text:SetPoint("BOTTOM", fx.owner.portrait, "TOP", slot.x, -4 + 32 * age / LIFE)
            end
        end
    end
    local pulse = fx.pulseAt and math.max(0, 1 - (now - fx.pulseAt) / .45) or 0
    fx.glow:SetAlpha(pulse * .65)
    if not active then fx:SetScript("OnUpdate", nil); fx.pulseAt = nil end
end

function Effects:Create(frame)
    if frame.healEffects then return end
    local fx = CreateFrame("Frame", nil, frame)
    frame.healEffects = fx; fx.owner = frame; fx.slots = {}
    fx:SetAllPoints(); fx:EnableMouse(false); fx:SetFrameLevel(frame:GetFrameLevel() + 8)
    fx.glow = fx:CreateTexture(nil, "ARTWORK")
    fx.glow:SetTexture("Interface/Buttons/UI-ActionButton-Border")
    fx.glow:SetBlendMode("ADD"); fx.glow:SetVertexColor(.22, 1, .54)
    fx.glow:SetSize(66, 66); fx.glow:SetPoint("CENTER", frame.portrait, "CENTER")
    fx.glow:SetAlpha(0)
    for i = 1, FLOATS do
        local text = UI.Text(fx, "GameFontNormalLarge", "", C.green)
        text:SetJustifyH("CENTER"); text:SetWordWrap(false)
        text:SetShadowColor(0, 0, 0, 1); text:SetShadowOffset(1, -1); text:Hide()
        fx.slots[i] = {text = text, x = OFFSETS[i]}
    end
    fx.tick = function() self:Tick(fx) end
    fx:SetScript("OnHide", function() self:Clear(frame) end)
end

function Effects:Heal(frame, flags, amount)
    local fx = frame and frame.healEffects
    if not fx or JP.SafeOptionalBoolean(frame:IsShown()) ~= true then return end
    local secret, value = JP.IsSecret(amount), JP.SafeNumber(amount)
    if not secret and (not value or value <= 0 or value ~= value or value == math.huge) then return end
    local now = GetTime()
    -- A display pool, not a combat log: no per-hit tables, timers or backlog.
    if fx.nextAt and now < fx.nextAt then return end
    fx.nextAt = now + INTERVAL
    fx.cursor = (fx.cursor or 0) % FLOATS + 1
    local slot = fx.slots[fx.cursor]
    local critical = JP.SafeString(flags) == "CRITICAL"
    slot.text:SetFont(STANDARD_TEXT_FONT, critical and 19 or 15, "OUTLINE")
    slot.text:SetTextColor(critical and .86 or .35, 1, critical and .44 or .64)
    if secret then
        -- Render-only sink: never subtract health, aggregate opaque amounts,
        -- infer the source, or let the value control targeting/click-casting.
        slot.text:SetFormattedText("+%.0f", amount)
    elseif value >= 1000000 then slot.text:SetFormattedText("+%.2fM", value / 1000000)
    elseif value >= 1000 then slot.text:SetFormattedText("+%.1fk", value / 1000)
    else slot.text:SetFormattedText("+%.0f", value) end
    slot.started = now; slot.text:SetAlpha(0); slot.text:Show()
    slot.text:ClearAllPoints(); slot.text:SetPoint("BOTTOM", frame.portrait, "TOP", slot.x, -4)
    fx.pulseAt = now; fx:SetScript("OnUpdate", fx.tick)
end

function Effects:Preview(frame)
    self:Create(frame); self:Clear(frame)
    if not frame.previewBuffs then
        frame.previewBuffs = {}
        for i, spellID in ipairs({774, 8936, 33763, 48438}) do
            local icon = frame:CreateTexture(nil, "ARTWORK")
            icon:SetSize(ICON, ICON); icon:SetPoint("TOPLEFT", 45 + (i - 1) * (ICON + GAP), -29)
            icon:SetTexCoord(.08, .92, .08, .92)
            icon:SetTexture(C_Spell.GetSpellTexture(spellID) or 136081)
            frame.previewBuffs[i] = icon
        end
    end
    local fx = frame.healEffects
    local text = fx.slots[1].text
    text:SetFont(STANDARD_TEXT_FONT, 19, "OUTLINE"); text:SetTextColor(.86, 1, .44)
    text:SetText("+124.5k"); text:SetAlpha(1)
    text:ClearAllPoints(); text:SetPoint("BOTTOM", frame.portrait, "TOP", 0, 4); text:Show()
    fx.glow:SetAlpha(.40)
end
