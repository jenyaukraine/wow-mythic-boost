local _, JP = ...

-- WoW 12.1: the addon owns presentation, the secure container owns aura data.
-- Never read, cache, sort or poll its buttons after initialization. In particular,
-- this is NOT the Blizzard BuffFrame/AuraContainer that belongs to Edit Mode.
local AuraDisplay = {}
JP.AuraDisplay = AuraDisplay
local WHITE = "Interface/Buttons/WHITE8X8"
local SIZE, GAP, COLUMNS, PLAYER_COLUMNS = 22, 3, 9, 4

local function InitializeButton(button)
    button:SetSize(SIZE, SIZE)
    local border = button:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(.42, .48, .54, 1)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(.06, .94, .06, .94)
    button:SetIcon(icon)

    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(icon)
    cooldown:SetDrawEdge(false)
    cooldown:SetHideCountdownNumbers(true)
    button:SetDurationCooldown(cooldown)

    local overlay = CreateFrame("Frame", nil, button)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(cooldown:GetFrameLevel() + 1)
    local count = overlay:CreateFontString(nil, "OVERLAY")
    count:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    count:SetPoint("BOTTOMRIGHT", -1, 1)
    button:SetApplicationCount(count, {})
    local duration = overlay:CreateFontString(nil, "OVERLAY")
    duration:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
    duration:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    duration:SetTextColor(.9, .93, .97)
    button:SetDurationText(duration, {})

    -- A thin engine-colored dispel indicator; no dispelName table lookup in Lua.
    local dispel = button:CreateTexture(nil, "OVERLAY")
    dispel:SetTexture(WHITE)
    dispel:SetPoint("TOPLEFT")
    dispel:SetPoint("TOPRIGHT")
    dispel:SetHeight(2)
    button:AddDispelTypeTexture(dispel, {
        style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset,
        showWhenHelpful = true, showWhenHarmful = true,
    })
    button:SetTooltipAnchorPoint("ANCHOR_RIGHT", 0, 0)
    button:SetCancelAuraButtons("RightButtonUp")
end

function AuraDisplay:Create(display)
    if display.auraContainer then return display.auraReady and display.auraContainer or nil end
    if InCombatLockdown() then return nil end
    display.auraAnchor = CreateFrame("Frame", nil, display.holder)
    display.auraAnchor:SetSize(1, 1)
    local container = CreateFrame("AuraContainer", nil, display.holder, "CustomAuraContainerTemplate")
    display.auraContainer = container
    container:SetEnabled(false)
    container:SetUnit(display.unit)
    local columns = display.unit == "player" and PLAYER_COLUMNS or COLUMNS
    container:SetFlowLayoutMaximumLineSize(columns * SIZE + (columns - 1) * GAP)
    -- First group lies closest to the capsule. The engine collapses empty
    -- groups and grows the second group above it, including during combat.
    for _, group in ipairs({ { "buffs", "HELPFUL", 18 }, { "debuffs", "HARMFUL", 18 } }) do
        container:AddAuraGroup(group[1], group[2], {
            maxFrameCount = group[3], initializeFrame = InitializeButton,
            layout = { elementSpacing = GAP, lineSpacing = GAP,
                groupLineSpacing = GAP, forceNewLine = true },
        })
    end
    display.auraReady = true
    return container
end

function AuraDisplay:Position(display, settings)
    if not display.auraAnchor then return end
    local beside = display.unit == "player" and settings.playerAurasBeside == true
    if beside then
        display.auraPositionSide = true
        display.auraPositionY, display.auraPositionAbove = nil, nil
        display.auraAnchor:ClearAllPoints()
        display.auraAnchor:SetPoint("TOPLEFT", display.holder,
            display.mirror and "TOPLEFT" or "TOPRIGHT", display.mirror and -GAP or GAP, 0)
        return
    end
    display.auraPositionSide = false
    local above = settings.aurasAbove ~= false
    local y = above and GAP or -GAP
    local row = display.resourceRow
    -- This row is entirely addon-owned; no secret aura bounds are queried.
    -- It is anchored one pixel below the capsule's top edge by UnitFrames.
    if above and row and row:IsShown() then y = row:GetHeight() - 1 + GAP end
    if display.auraPositionY == y and display.auraPositionAbove == above then return end
    display.auraPositionY, display.auraPositionAbove = y, above
    local relative = above and (display.mirror and "TOPRIGHT" or "TOPLEFT")
        or (display.mirror and "BOTTOMRIGHT" or "BOTTOMLEFT")
    -- Move only our plain anchor on resource events, never the restricted
    -- aura container or its buttons in combat. No timer/layout hooks needed.
    display.auraAnchor:ClearAllPoints()
    display.auraAnchor:SetPoint("TOPLEFT", display.holder, relative, 0, y)
end

function AuraDisplay:Configure(display, settings)
    if InCombatLockdown() then return end
    local container = self:Create(display)
    if not container then return end
    local beside = display.unit == "player" and settings.playerAurasBeside == true
    -- Cancel the holder's scale so changing the capsule does not resize auras.
    local frameScale = settings.scale or 1.5
    local auraScale = settings.auraScale or frameScale
    container:SetScale(auraScale / frameScale)
    local columns = beside and PLAYER_COLUMNS or COLUMNS
    container:SetFlowLayoutMaximumLineSize(columns * SIZE + (columns - 1) * GAP)
    local above = settings.aurasAbove ~= false
    local anchor = beside and (display.mirror and "TOPRIGHT" or "TOPLEFT")
        or above and (display.mirror and "BOTTOMRIGHT" or "BOTTOMLEFT")
        or (display.mirror and "TOPRIGHT" or "TOPLEFT")
    self:Position(display, settings)
    container:ClearAllPoints()
    container:SetPoint(anchor, display.auraAnchor, "TOPLEFT", 0, 0)
    container:SetFlowLayoutAnchorPoint(anchor)
    container:SetFlowLayoutGrowthDirection(
        display.mirror and AnchorUtil.FlowDirection.Left or AnchorUtil.FlowDirection.Right,
        beside and AnchorUtil.FlowDirection.Down
            or (above and AnchorUtil.FlowDirection.Up or AnchorUtil.FlowDirection.Down))
    local enabled = settings.enabled ~= false and (display.unit == "player"
        and settings.showPlayerAuras ~= false or display.unit == "target" and settings.showTargetAuras ~= false)
    container:SetEnabled(enabled)
    container:SetShown(enabled)
end

function AuraDisplay:Refresh(display)
    -- Public inbound method: the secure implementation schedules the scan.
    -- A target change must refresh even when the token is still "target".
    if display.auraReady then display.auraContainer:UpdateAllAuras() end
end

function AuraDisplay:StyleTooltip(enabled)
    if InCombatLockdown() or not AuraContainerInbound or self.tooltipStyled == enabled then return end
    if enabled then
        local colors = JP.UI.colors
        -- Public delegate configures the private tooltip without exposing or
        -- changing its frame, scripts, aura data or Blizzard layout fields.
        AuraContainerInbound.SetTooltipBackdrop({
            backdropInfo = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 } },
            borderColor = CreateColor(unpack(colors.surfaceEdge)),
            centerColor = CreateColor(unpack(colors.surface)),
            anchorOffsets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
    elseif self.tooltipStyled then
        AuraContainerInbound.ResetTooltipStyle()
    end
    self.tooltipStyled = enabled
end
