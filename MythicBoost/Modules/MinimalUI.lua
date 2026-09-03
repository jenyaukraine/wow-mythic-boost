local _, JP = ...
local L = JP.L
local MinimalUI = {}
local UI = JP.UI
local C = UI.colors

local SQUARE_MASK = "Interface\\Buttons\\WHITE8X8"
local FALLBACK_ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- HUD elements should sit directly on the game world. A previous revision put
-- an opaque near-black rectangle behind every skinned frame, which made the
-- interface look like a collection of unrelated boxes.
-- Контур — из общих токенов UI.colors. Фон здесь намеренно
-- прозрачный и таким остаётся: эти панели ложатся на миникарту и чат,
-- и любая заливка там закрывает содержимое.
local PANEL_EDGE = { JP.UI.colors.surfaceEdge[1], JP.UI.colors.surfaceEdge[2], JP.UI.colors.surfaceEdge[3], .82 }

-- Одна визуальная система для всего HUD. Панель живёт рядом с целевым
-- окном на UIParent, поэтому не перекрывается собственными фонами Details,
-- чата или Blizzard UI и при этом следует за окном при его перемещении.
local function IsObject(value)
    return value and type(value.IsShown) == "function" and type(value.SetShown) == "function"
end

local function RememberAndHide(self, object)
    if not IsObject(object) then return end
    self.savedVisibility = self.savedVisibility or UI.WeakKeys()
    if self.savedVisibility[object] == nil then self.savedVisibility[object] = object:IsShown() and true or false end
    object:Hide()
end

local function RestoreVisibility(self)
    for object, shown in pairs(self.savedVisibility or {}) do
        if IsObject(object) then object:SetShown(shown) end
    end
    if self.savedVisibility then wipe(self.savedVisibility) end
    for texture, alpha in pairs(self.savedTextureAlpha or {}) do
        if texture and type(texture.SetAlpha) == "function" then texture:SetAlpha(alpha) end
    end
    if self.savedTextureAlpha then wipe(self.savedTextureAlpha) end
end

local function BasicMinimapIsActive()
    return UI.IsAddOnLoaded("BasicMinimap")
        or UI.IsAddOnLoaded("BasicMinimap_Options")
        or type(_G.BasicMinimap) == "table"
end

-- Minimap ownership is restored independently from the rest of Minimal UI.
-- Restoring the global bucket here would also undo valid action-bar, tracker,
-- bag, and chat styling when BasicMinimap is present.
local function RememberAndHideMinimap(self, object)
    if not IsObject(object) then return end
    self.minimapSavedVisibility = self.minimapSavedVisibility or UI.WeakKeys()
    if self.minimapSavedVisibility[object] == nil then
        self.minimapSavedVisibility[object] = object:IsShown() and true or false
    end
    object:Hide()
end

local function RestoreMinimapVisibility(self)
    for object, shown in pairs(self.minimapSavedVisibility or {}) do
        if IsObject(object) then object:SetShown(shown) end
    end
    if self.minimapSavedVisibility then wipe(self.minimapSavedVisibility) end
end

local function HideTextureRegions(self, owner)
    if not owner or type(owner.GetRegions) ~= "function" then return end
    for _, region in ipairs({ owner:GetRegions() }) do
        if region and type(region.GetObjectType) == "function" and region:GetObjectType() == "Texture" then
            RememberAndHide(self, region)
        end
    end
end

-- Hide() alone is not enough for state textures: Blizzard shows the normal or
-- pushed texture again whenever the objective tracker changes state. Keeping
-- those textures at alpha 0 prevents the old red/gold button from appearing
-- underneath our minimal glyph, while still allowing a clean restore.
local function MuteButtonStateTextures(self, button)
    if not button then return end
    self.savedTextureAlpha = self.savedTextureAlpha or UI.WeakKeys()
    for _, getter in ipairs({
        "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture",
    }) do
        local texture = type(button[getter]) == "function" and button[getter](button)
        if texture and type(texture.SetAlpha) == "function" then
            if self.savedTextureAlpha[texture] == nil then
                self.savedTextureAlpha[texture] = texture:GetAlpha()
            end
            texture:SetAlpha(0)
        end
    end
    HideTextureRegions(self, button)
end

-- Action icons themselves are texture regions, so the broad helper above is
-- intentionally too aggressive for action buttons. Suppress only Blizzard's
-- state overlays; otherwise its rounded gold/green hover art reappears on top
-- of our square cyan edge whenever the mouse enters a button.
local function MuteActionStateTextures(self, button)
    self.savedTextureAlpha = self.savedTextureAlpha or UI.WeakKeys()
    local icon = button.icon or button.Icon
    local function MuteArtifact(texture)
        if not texture or texture == icon or texture.__mbActionDecoration
            or type(texture.SetAlpha) ~= "function" then return end
        if self.savedTextureAlpha[texture] == nil then
            self.savedTextureAlpha[texture] = texture:GetAlpha()
        end
        if not texture.__mbActionArtifactAlphaHooked then
            texture.__mbActionArtifactAlphaHooked = true
            local correcting = false
            hooksecurefunc(texture, "SetAlpha", function(owner, alpha)
                if not correcting and MythicBoostDB and MythicBoostDB.minimalUI
                    and alpha and alpha > 0 then
                    correcting = true
                    owner:SetAlpha(0)
                    correcting = false
                end
            end)
        end
        texture:SetAlpha(0)
    end
    for _, getter in ipairs({
        "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture", "GetCheckedTexture",
    }) do
        local texture = type(button[getter]) == "function" and button[getter](button)
        MuteArtifact(texture)
    end
    -- Retail has moved the tiny corner/slot artwork between named keys over
    -- several action-button templates. Silence every known carrier as well as
    -- the generic state textures above; the alpha hook prevents Blizzard from
    -- bringing the white corner ticks back during an action update.
    for _, texture in pairs({
        button.NormalTexture, button.FloatingBG, button.SlotBackground,
        button.Border, button.SlotArt, button.Background, button.Flash,
        button.NewActionTexture, button.HighlightTexture, button.CheckedTexture,
        button.PushedTexture,
    }) do
        MuteArtifact(texture)
    end
    -- У разных поколений Blizzard_ActionBar круглая подсветка носит разные
    -- имена. Надёжнее убрать все собственные Texture-регионы кнопки, кроме
    -- самой иконки и наших квадратных украшений, чем бесконечно догонять
    -- переименования Normal/Checked/SpellActivationAlert.
    if type(button.GetRegions) == "function" then
        for _, region in ipairs({ button:GetRegions() }) do
            if region ~= icon and not region.__mbActionDecoration
                and type(region.GetObjectType) == "function" and region:GetObjectType() == "Texture"
                and type(region.SetAlpha) == "function" then
                MuteArtifact(region)
            end
        end
    end
end

-- Квадратная рамка кнопки действия держит три состояния сразу, поэтому цвет
-- назначается в одном месте: иначе наведение мышью затирало подсветку
-- подсказанного заклинания, а обновление панели — наведение.
local ACTION_EDGE_IDLE = { .48, .34, .09 }
local ACTION_EDGE_HOVER = { .95, .72, .18, 1 }
local ACTION_EDGE_SUGGESTED = { .24, .96, .48, 1 }

local function ApplyActionBorderColor(button)
    local border = button.__mbMinimalBorder
    if not border then return end
    if button.__mbSpellSuggested then
        border:SetBackdropBorderColor(unpack(ACTION_EDGE_SUGGESTED))
    elseif button.__mbHovered then
        border:SetBackdropBorderColor(unpack(ACTION_EDGE_HOVER))
    else
        border:SetBackdropBorderColor(ACTION_EDGE_IDLE[1], ACTION_EDGE_IDLE[2], ACTION_EDGE_IDLE[3],
            button.__mbEmptyAction and .52 or .92)
    end
end

-- Blizzard подсказывает следующее заклинание круглой зелёной обводкой поверх
-- кнопки. Её не было в списке скрываемого, поэтому она и оставалась круглой
-- поверх нашего квадратного края. Саму подсказку не теряем: гасим штатную
-- картинку и перекладываем её состояние на цвет нашей рамки.
local function MuteSuggestionGlow(self, button, object, animation)
    if not object or type(object.SetAlpha) ~= "function" then return end
    self.savedTextureAlpha = self.savedTextureAlpha or UI.WeakKeys()
    if self.savedTextureAlpha[object] == nil then self.savedTextureAlpha[object] = object:GetAlpha() end

    local muting = false
    local ForceSquareOnly
    local function HookAlpha(node)
        if node.__mbGlowAlphaHooked or type(node.SetAlpha) ~= "function" then return end
        node.__mbGlowAlphaHooked = true
        hooksecurefunc(node, "SetAlpha", function(_, alpha)
            if not muting and MythicBoostDB and MythicBoostDB.minimalUI and alpha and alpha > 0 then
                ForceSquareOnly()
            end
        end)
    end

    local function MuteTree(node, seen, depth)
        if not node or seen[node] or depth > 8 then return end
        seen[node] = true
        if type(node.SetAlpha) == "function" then
            if self.savedTextureAlpha[node] == nil then self.savedTextureAlpha[node] = node:GetAlpha() end
            HookAlpha(node)
        end
        if type(node.GetAnimationGroups) == "function" then
            for _, group in ipairs({ node:GetAnimationGroups() }) do
                if group and type(group.Stop) == "function" then pcall(group.Stop, group) end
            end
        end
        if type(node.GetRegions) == "function" then
            for _, region in ipairs({ node:GetRegions() }) do MuteTree(region, seen, depth + 1) end
        end
        if type(node.GetChildren) == "function" then
            for _, child in ipairs({ node:GetChildren() }) do MuteTree(child, seen, depth + 1) end
        end
        if type(node.SetAlpha) == "function" then node:SetAlpha(0) end
    end

    ForceSquareOnly = function()
        if muting then return end
        if not MythicBoostDB or not MythicBoostDB.minimalUI then return end
        muting = true
        -- AssistedCombatRotationFrame owns its own animation group and may
        -- restore alpha without calling Show(). Stop every group we can see
        -- and mute the child textures as well as the parent frame.
        if animation and type(animation.Stop) == "function" then pcall(animation.Stop, animation) end
        MuteTree(object, {}, 0)
        muting = false
    end

    local function Mirror(shown)
        button.__mbSpellSuggested = shown or nil
        ForceSquareOnly()
        ApplyActionBorderColor(button)
    end

    if not object.__mbGlowHooked then
        object.__mbGlowHooked = true
        hooksecurefunc(object, "Show", function() Mirror(true) end)
        hooksecurefunc(object, "Hide", function() Mirror(false) end)
        hooksecurefunc(object, "SetShown", function(_, shown) Mirror(shown and true or false) end)
        -- The green rotation suggestion animates SetAlpha after Show(). The
        -- hook immediately forces it back to zero while our square border
        -- continues to carry the suggestion state.
        HookAlpha(object)
    end
    ForceSquareOnly()
    Mirror(object:IsShown() and true or false)
end

local function MuteActionSuggestionGlows(self, button)
    MuteSuggestionGlow(self, button, button.SpellHighlightTexture, button.SpellHighlightAnim)
    local seen = {}
    for _, object in pairs({
        button.AssistedCombatRotationFrame,
        button.SpellActivationAlert,
        button.SpellActivationOverlay,
        button.SpellActivationOverlayFrame,
        button.OverlayGlow,
        button.ProcGlow,
        button.Glow,
    }) do
        if object and not seen[object] then
            seen[object] = true
            MuteSuggestionGlow(self, button, object)
        end
    end
    local name = type(button.GetName) == "function" and button:GetName()
    if name then
        for _, suffix in ipairs({ "SpellActivationAlert", "SpellActivationOverlay", "OverlayGlow" }) do
            local object = _G[name .. suffix]
            if object and not seen[object] then
                seen[object] = true
                MuteSuggestionGlow(self, button, object)
            end
        end
    end
end

local function StyleMinimapZoneLabel(self, enabled)
    -- SexyMap прячет штатную кнопку зоны и создаёт собственную. Используем её
    -- первой, иначе мы двигаем невидимый Blizzard-фрейм, а видимая строка так
    -- и остаётся снаружи миникарты.
    local sexyButton = _G.SexyMapZoneTextButton
    local button = sexyButton or _G.MinimapZoneTextButton
        or (_G.MinimapCluster and MinimapCluster.ZoneTextButton)
    local label = button and button.Text
    if not label and not sexyButton then label = _G.MinimapZoneText end
    if not label and button and type(button.GetRegions) == "function" then
        for _, region in ipairs({ button:GetRegions() }) do
            if region and type(region.GetObjectType) == "function"
                and region:GetObjectType() == "FontString" then
                label = region
                break
            end
        end
    end
    if not button then return end
    if enabled and InCombatLockdown() then return end

    if not self.minimapZoneLayout then
        local state = { width = button:GetWidth(), height = button:GetHeight(), parent = button:GetParent(), points = {} }
        for index = 1, button:GetNumPoints() do state.points[index] = { button:GetPoint(index) } end
        if label then
            state.labelPoints = {}
            for index = 1, label:GetNumPoints() do state.labelPoints[index] = { label:GetPoint(index) } end
            state.labelWidth = label:GetWidth()
            state.labelHeight = label:GetHeight()
            state.justify = label:GetJustifyH()
            state.color = { label:GetTextColor() }
            state.labelFont = { label:GetFont() }
        end
        self.minimapZoneLayout = state
    end

    self.minimapWidgetLayouts = self.minimapWidgetLayouts or {}
    local function Place(frame, key, point, relativePoint, x, y)
        if not frame then return end
        if not self.minimapWidgetLayouts[key] then
            local state = {
                frame = frame,
                parent = frame:GetParent(),
                level = frame:GetFrameLevel(),
                strata = frame:GetFrameStrata(),
                points = {},
            }
            for index = 1, frame:GetNumPoints() do state.points[index] = { frame:GetPoint(index) } end
            self.minimapWidgetLayouts[key] = state
        end
        frame:SetParent(Minimap)
        frame:ClearAllPoints()
        frame:SetPoint(point, Minimap, relativePoint, x, y)
    end

    if enabled then
        local width = math.max(120, (Minimap:GetWidth() or 220) - 82)
        button:SetParent(Minimap)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 8, -5)
        button:SetSize(width, 18)
        if type(button.SetClipsChildren) == "function" then button:SetClipsChildren(true) end
        if label then
            label:ClearAllPoints()
            label:SetPoint("LEFT", button, "LEFT", 0, 0)
            label:SetWidth(width)
            label:SetJustifyH("LEFT")
            if self.minimapZoneLayout.labelFont and self.minimapZoneLayout.labelFont[1] then
                label:SetFont(self.minimapZoneLayout.labelFont[1], 13, "OUTLINE")
            end
            label:SetTextColor(.88, .94, 1, 1)
            label:SetShadowColor(0, 0, 0, 1)
            label:SetShadowOffset(1, -1)
            if type(label.SetMaxLines) == "function" then label:SetMaxLines(1) end
            if type(label.SetWordWrap) == "function" then label:SetWordWrap(false) end
        end

        local difficulty = _G.MiniMapInstanceDifficulty
            or (_G.MinimapCluster and MinimapCluster.InstanceDifficulty)
        local guildDifficulty = _G.GuildInstanceDifficulty
            or (_G.MinimapCluster and MinimapCluster.GuildInstanceDifficulty)
        local challengeDifficulty = _G.MiniMapChallengeMode
            or (_G.MinimapCluster and MinimapCluster.ChallengeMode)
        local queueStatus = _G.QueueStatusButton

        Place(_G.GameTimeFrame, "calendar", "TOPRIGHT", "TOPRIGHT", -2, -2)
        Place(difficulty, "difficulty", "TOPRIGHT", "TOPRIGHT", -4, -29)
        Place(guildDifficulty, "guildDifficulty", "TOPRIGHT", "TOPRIGHT", -4, -29)
        Place(challengeDifficulty, "challengeDifficulty", "TOPRIGHT", "TOPRIGHT", -4, -29)
        Place(queueStatus, "queueStatus", "BOTTOMLEFT", "BOTTOMLEFT", 6, 6)
        if queueStatus then queueStatus:SetFrameLevel(Minimap:GetFrameLevel() + 31) end

        -- SexyMap намеренно перехватывает SetPoint штатных часов и возвращает
        -- их наружу. Не боремся с его hooksecurefunc: показываем внутри карты
        -- лёгкую копию актуального TimeManagerClockTicker, сохраняя клик.
        if not self.minimapClock then
            local clock = CreateFrame("Button", nil, Minimap)
            clock:SetSize(52, 18)
            clock:SetFrameLevel(Minimap:GetFrameLevel() + 30)
            local text = clock:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            text:SetPoint("CENTER")
            local fontPath = text:GetFont()
            if fontPath then text:SetFont(fontPath, 12, "OUTLINE") end
            text:SetTextColor(1, 1, 1, 1)
            text:SetShadowColor(0, 0, 0, 1)
            text:SetShadowOffset(1, -1)
            clock.text = text
            clock:SetScript("OnUpdate", function(owner, elapsed)
                owner.elapsed = (owner.elapsed or 0) + elapsed
                if owner.elapsed < .2 then return end
                owner.elapsed = 0
                local ticker = _G.TimeManagerClockTicker
                owner.text:SetText(ticker and ticker:GetText() or date("%H:%M"))
            end)
            clock:SetScript("OnClick", function(_, mouseButton)
                local source = _G.TimeManagerClockButton
                local click = source and source:GetScript("OnClick")
                if click then click(source, mouseButton) end
            end)
            self.minimapClock = clock
        end
        self.minimapClock:ClearAllPoints()
        -- Queue status lives on the left and the addon compartment on the
        -- right.  The clock is the stable visual centre and must not drift
        -- when either corner widget appears or disappears.
        self.minimapClock:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, 5)
        self.minimapClock:Show()

        local sourceClock = _G.TimeManagerClockButton
        if sourceClock then
            if not self.minimapClockSourceLayout then
                self.minimapClockSourceLayout = {
                    alpha = sourceClock:GetAlpha(),
                    scale = sourceClock:GetScale(),
                    mouse = sourceClock:IsMouseEnabled(),
                }
            end
            sourceClock:SetAlpha(0)
            sourceClock:SetScale(.001)
            sourceClock:EnableMouse(false)
        end
    else
        local state = self.minimapZoneLayout
        if state.parent then button:SetParent(state.parent) end
        button:ClearAllPoints()
        for _, point in ipairs(state.points or {}) do button:SetPoint(unpack(point)) end
        button:SetSize(state.width, state.height)
        if label then
            label:ClearAllPoints()
            for _, point in ipairs(state.labelPoints or {}) do label:SetPoint(unpack(point)) end
            if state.labelWidth then label:SetWidth(state.labelWidth) end
            if state.labelHeight then label:SetHeight(state.labelHeight) end
            if state.justify then label:SetJustifyH(state.justify) end
            if state.color then label:SetTextColor(unpack(state.color)) end
            if state.labelFont and state.labelFont[1] then
                label:SetFont(state.labelFont[1], state.labelFont[2], state.labelFont[3])
            end
        end
        for _, widgetState in pairs(self.minimapWidgetLayouts or {}) do
            local frame = widgetState.frame
            if frame then
                if widgetState.parent then frame:SetParent(widgetState.parent) end
                frame:ClearAllPoints()
                for _, point in ipairs(widgetState.points or {}) do frame:SetPoint(unpack(point)) end
                if widgetState.strata then frame:SetFrameStrata(widgetState.strata) end
                if widgetState.level then frame:SetFrameLevel(widgetState.level) end
            end
        end
        if self.minimapClock then self.minimapClock:Hide() end
        local sourceClock, clockState = _G.TimeManagerClockButton, self.minimapClockSourceLayout
        if sourceClock and clockState then
            sourceClock:SetAlpha(clockState.alpha or 1)
            sourceClock:SetScale(clockState.scale or 1)
            sourceClock:EnableMouse(clockState.mouse and true or false)
        end
        self.minimapClockSourceLayout = nil
    end
end

local function HideLooseMinimapAddonButtons(self, enabled)
    self.looseMinimapButtons = self.looseMinimapButtons or UI.WeakKeys()
    self.looseMinimapVisibility = self.looseMinimapVisibility or UI.WeakKeys()

    if not enabled then
        for button, shown in pairs(self.looseMinimapVisibility) do
            if button and type(button.SetShown) == "function" then button:SetShown(shown) end
        end
        wipe(self.looseMinimapVisibility)
        return
    end

    if not self.looseMinimapScanned or self.minimapAddonScanDirty then
        for name, object in pairs(_G) do
            if type(name) == "string" and name:match("^LibDBIcon10_") then
                self.looseMinimapButtons[object] = true
            end
        end
        self.looseMinimapScanned = true
        self.minimapAddonScanDirty = nil
    end
    if type(LibStub) == "table" or type(LibStub) == "function" then
        local ok, lib = pcall(LibStub, "LibDBIcon-1.0", true)
        if ok and type(lib) == "table" and type(lib.objects) == "table" then
            for _, object in pairs(lib.objects) do self.looseMinimapButtons[object] = true end
        end
    end

    local nativeCompartment = _G.AddonCompartmentFrame
    local function IsNativeCompartment(button)
        if not button then return false end
        if button == nativeCompartment or button == _G.AddonCompartmentFrame then return true end
        local name = type(button.GetName) == "function" and button:GetName()
        return name == "AddonCompartmentFrame"
    end
    for button in pairs(self.looseMinimapButtons) do
        if button and not IsNativeCompartment(button) and type(button.Hide) == "function" then
            if self.looseMinimapVisibility[button] == nil then
                self.looseMinimapVisibility[button] = button:IsShown() and true or false
            end
            if type(button.HookScript) == "function" and not button.__mbKeepLooseMinimapHidden then
                button.__mbKeepLooseMinimapHidden = true
                button:HookScript("OnShow", function(owner)
                    -- A foreign minimap addon may synchronously Show() its
                    -- button from OnHide. Calling Hide() again from our
                    -- OnShow without a guard makes the two hooks recurse on
                    -- the UI thread until the client stops responding.
                    if self.minimapOwnershipActive and not IsNativeCompartment(owner)
                        and not owner.__mbLooseMinimapHideActive then
                        owner.__mbLooseMinimapHideActive = true
                        pcall(owner.Hide, owner)
                        owner.__mbLooseMinimapHideActive = nil
                    end
                end)
            end
            button:Hide()
        end
    end

    -- The compartment can be created after our first minimap pass. Explicitly
    -- expose Blizzard's own button after filtering the loose LibDBIcon objects;
    -- this is the supported entry point for the complete addon list.
    nativeCompartment = _G.AddonCompartmentFrame
    if nativeCompartment and type(nativeCompartment.Show) == "function" then
        self.looseMinimapButtons[nativeCompartment] = nil
        self.looseMinimapVisibility[nativeCompartment] = nil
        nativeCompartment:Show()
    end
end

local PlaceNativeAddonCompartment

function MinimalUI:StyleMinimap(enabled)
    if not Minimap then return end

    if enabled and BasicMinimapIsActive() then
        if self.minimapOwnershipActive then self:StyleMinimap(false) end
        self.externalMinimapOwner = "BasicMinimap"
        return
    end
    self.externalMinimapOwner = nil

    -- Do not "restore" a map MythicBoost never owned: even writing a cached
    -- mask in the disabled path would overwrite BasicMinimap's configuration.
    if not enabled and not self.minimapOwnershipActive then return end

    if not self.roundMask then
        local ok, mask = pcall(Minimap.GetMaskTexture, Minimap)
        self.roundMask = ok and mask or FALLBACK_ROUND_MASK
    end

    if enabled then
        self.minimapOwnershipActive = true
        -- Blizzard keeps the map about 70 px below the top of MinimapCluster
        -- to reserve space for its old header. Our zone and clock live inside
        -- the map, so that reservation is just an empty strip. Preserve the
        -- native layout and pin the actual map to the cluster's top edge.
        if not self.minimapMapLayout then
            local layout = {
                parent = Minimap:GetParent(), width = Minimap:GetWidth(), height = Minimap:GetHeight(), points = {},
            }
            for index = 1, Minimap:GetNumPoints() do
                layout.points[index] = { Minimap:GetPoint(index) }
            end
            self.minimapMapLayout = layout
        end
        if not InCombatLockdown() then
            local anchor = _G.MinimapCluster or UIParent
            Minimap:ClearAllPoints()
            Minimap:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -4, -4)
            Minimap:SetSize(265, 265)
        end
        pcall(Minimap.SetMaskTexture, Minimap, SQUARE_MASK)
        -- Круг на присланном скриншоте оказался не рамкой, а кольцом зоны
        -- задания, которое Blizzard рисует поверх нестандартной маски.
        for _, method in ipairs({
            "SetArchBlobRingScalar", "SetArchBlobRingAlpha",
            "SetQuestBlobRingScalar", "SetQuestBlobRingAlpha",
        }) do
            if type(Minimap[method]) == "function" then pcall(Minimap[method], Minimap, 0) end
        end
        for _, object in pairs({
            _G.MinimapBorder,
            _G.MinimapBorderTop,
            _G.MinimapBackdrop,
            _G.MinimapCompassTexture,
            _G.SexyMapCustomBackdrop,
            _G.MinimapZoomIn,
            _G.MinimapZoomOut,
            Minimap.ZoomIn,
            Minimap.ZoomOut,
            _G.TrackingFrame,
            _G.TrackingFrame and TrackingFrame.Button,
            _G.MinimapCluster and MinimapCluster.Tracking,
            _G.MinimapCluster and MinimapCluster.Tracking and MinimapCluster.Tracking.Button,
            _G.MiniMapTracking,
            _G.MinimapNorthTag,
            _G.MiniMapTrackingButtonBorder,
            MinimapCluster and MinimapCluster.BorderTop,
        }) do
            RememberAndHideMinimap(self, object)
            if object and type(object.HookScript) == "function" and not object.__mbKeepMinimapHidden then
                object.__mbKeepMinimapHidden = true
                object:HookScript("OnShow", function(owner)
                    if self.minimapOwnershipActive and not owner.__mbMinimapHideActive then
                        owner.__mbMinimapHideActive = true
                        pcall(owner.Hide, owner)
                        owner.__mbMinimapHideActive = nil
                    end
                end)
            end
        end

        if not self.minimapBorder then
            local border = CreateFrame("Frame", nil, Minimap, "BackdropTemplate")
            border:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -2, 2)
            border:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", 2, -2)
            border:SetFrameLevel(Minimap:GetFrameLevel() + 20)
            border:EnableMouse(false)
            border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            border:SetBackdropBorderColor(PANEL_EDGE[1], PANEL_EDGE[2], PANEL_EDGE[3], 1)
            self.minimapBorder = border
        end
        self.minimapBorder:Show()
        StyleMinimapZoneLabel(self, true)
        -- Keep Blizzard's native Addon Compartment. MythicBoost is listed
        -- there through TOC metadata; no second drawer or custom tooltip.
        HideLooseMinimapAddonButtons(self, true)
        PlaceNativeAddonCompartment(self, true)
        -- The minimap already has its own one-pixel border. A second enclosing
        -- panel only creates a pointless rectangle around it.

        if not self.mouseWheelHooked then
            self.mouseWheelHooked = true
            Minimap:EnableMouseWheel(true)
            Minimap:HookScript("OnMouseWheel", function(map, delta)
                if not self.minimapOwnershipActive then return end
                local zoom = map:GetZoom() + (delta > 0 and 1 or -1)
                local maximum = type(map.GetZoomLevels) == "function" and map:GetZoomLevels() - 1 or 5
                map:SetZoom(math.max(0, math.min(maximum, zoom)))
            end)
        end
    else
        self.minimapOwnershipActive = false
        local layout = self.minimapMapLayout
        if layout and not InCombatLockdown() then
            if layout.parent then Minimap:SetParent(layout.parent) end
            Minimap:ClearAllPoints()
            for _, point in ipairs(layout.points or {}) do Minimap:SetPoint(unpack(point)) end
            if layout.width and layout.height then Minimap:SetSize(layout.width, layout.height) end
        end
        self.minimapMapLayout = nil
        HideLooseMinimapAddonButtons(self, false)
        PlaceNativeAddonCompartment(self, false)
        pcall(Minimap.SetMaskTexture, Minimap, self.roundMask or FALLBACK_ROUND_MASK)
        for _, method in ipairs({
            "SetArchBlobRingScalar", "SetArchBlobRingAlpha",
            "SetQuestBlobRingScalar", "SetQuestBlobRingAlpha",
        }) do
            if type(Minimap[method]) == "function" then pcall(Minimap[method], Minimap, 1) end
        end
        if self.minimapBorder then self.minimapBorder:Hide() end
        if self.minimapZoneLayout then StyleMinimapZoneLabel(self, false) end
        RestoreMinimapVisibility(self)
    end
end

local function RememberFontColor(self, fontString)
    if not fontString or type(fontString.GetTextColor) ~= "function" then return end
    self.questFontColors = self.questFontColors or UI.WeakKeys()
    if not self.questFontColors[fontString] then self.questFontColors[fontString] = { fontString:GetTextColor() } end
end

-- Дерево трекера обходится заново на каждое его обновление, а в подземелье
-- это десятки раз в минуту. Запись ipairs({ owner:GetRegions() }) создавала
-- по таблице на каждый узел — и вторую на его детей. Перебор тех же
-- значений через select не выделяет ничего вовсе.
local RestyleTrackerTree

local function RestyleRegions(self, ...)
    for index = 1, select("#", ...) do
        local region = select(index, ...)
        local regionType = region and type(region.GetObjectType) == "function" and region:GetObjectType()
        if regionType == "FontString" then
            local r, g, b = region:GetTextColor()
            RememberFontColor(self, region)
            if r > .65 and g > .45 and b < .35 then
                region:SetTextColor(.88, .94, 1, 1)
            end
        elseif regionType == "Texture" then
            local width, height = region:GetWidth() or 0, region:GetHeight() or 0
            -- Горизонтальные золотые плашки/завитки секций. Маленькие
            -- квестовые иконки и полосы прогресса не трогаем.
            if width >= 80 and height > 0 and height <= 60 then RememberAndHide(self, region) end
        end
    end
end

local function RestyleChildren(self, depth, ...)
    for index = 1, select("#", ...) do
        RestyleTrackerTree(self, select(index, ...), depth)
    end
end

function RestyleTrackerTree(self, owner, depth)
    if not owner or (depth or 0) > 8 then return end
    local objectType = type(owner.GetObjectType) == "function" and owner:GetObjectType()
    if objectType ~= "StatusBar" and type(owner.GetRegions) == "function" then
        RestyleRegions(self, owner:GetRegions())
    end
    if type(owner.GetChildren) == "function" then
        RestyleChildren(self, (depth or 0) + 1, owner:GetChildren())
    end
end

local function StyleTrackerHeader(self, header)
    if not header then return end
    HideTextureRegions(self, header)
    local minimize = header.MinimizeButton or header.HeaderMenu
    MuteButtonStateTextures(self, minimize)
    if minimize and not InCombatLockdown() then
        self.trackerButtonLayouts = self.trackerButtonLayouts or UI.WeakKeys()
        if not self.trackerButtonLayouts[minimize] then
            local state = { points = {} }
            for index = 1, minimize:GetNumPoints() do state.points[index] = { minimize:GetPoint(index) } end
            self.trackerButtonLayouts[minimize] = state
        end
        minimize:ClearAllPoints()
        minimize:SetPoint("RIGHT", header, "RIGHT", -12, 0)
    end
    for _, object in pairs({
        header.Background, header.HeaderOpen, header.HeaderClosed,
        header.HeaderOpenMouseover, header.HeaderClosedMouseover,
    }) do
        RememberAndHide(self, object)
    end
    local title = header.Text or header.Title
    if title and type(title.SetTextColor) == "function" then
        RememberFontColor(self, title)
        title:SetTextColor(.88, .94, 1, 1)
    end
    if minimize and type(minimize.CreateFontString) == "function" and not minimize.__mbMinimalText then
        local text = minimize:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        text:SetPoint("CENTER")
        text:SetText("–")
        text:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
        minimize.__mbMinimalText = text
        self.trackerToggleTexts = self.trackerToggleTexts or UI.WeakKeys()
        self.trackerToggleTexts[text] = true
    elseif minimize and minimize.__mbMinimalText then
        minimize.__mbMinimalText:Show()
    end
end

function MinimalUI:StyleObjectiveTracker(enabled)
    local tracker = _G.ObjectiveTrackerFrame
    local header = tracker and tracker.Header
    if not header then return end
    if InCombatLockdown() and type(tracker.IsProtected) == "function" and tracker:IsProtected() then return end

    -- Scale the already-laid-out Blizzard root instead of forcing widths on
    -- every objective block. This preserves native wrapping while making the
    -- final on-screen column exactly as wide as the minimap.
    if enabled and Minimap then
        if not self.trackerLayout then
            local state = { scale = tracker:GetScale(), points = {} }
            for index = 1, tracker:GetNumPoints() do
                state.points[index] = { tracker:GetPoint(index) }
            end
            self.trackerLayout = state
        end
        tracker:ClearAllPoints()
        local trackerWidth = tracker:GetWidth() or 0
        local mapWidth = Minimap:GetWidth() or 245
        local fittedScale = trackerWidth > 0 and mapWidth / trackerWidth or .75
        tracker:SetScale(math.max(.70, math.min(1, fittedScale)))
        local microAnchor = self.microMenuAnchor
        if microAnchor and microAnchor:IsShown() then
            tracker:SetPoint("TOPRIGHT", microAnchor, "BOTTOMRIGHT", 0, -8)
        else
            tracker:SetPoint("TOPRIGHT", Minimap, "BOTTOMRIGHT", 0, -14)
        end
    elseif self.trackerLayout then
        tracker:ClearAllPoints()
        for _, point in ipairs(self.trackerLayout.points or {}) do tracker:SetPoint(unpack(point)) end
        tracker:SetScale(self.trackerLayout.scale or 1)
        self.trackerLayout = nil
    end

    -- Панель и линия старой реализации не возвращаются ни в каком режиме.
    if self.questLine then self.questLine:Hide() end

    -- Only the tracker scale and minimap-relative position above are custom.
    -- Blizzard keeps its own fonts, colours, textures and section styling.
    if enabled then return end

    -- Дальше — возврат штатного вида: шрифты, кнопка сворачивания, подписи.
    self.trackerStyled = nil
    for text in pairs(self.trackerToggleTexts or {}) do text:Hide() end
    for button, state in pairs(self.trackerButtonLayouts or {}) do
        if button then
            button:ClearAllPoints()
            for _, point in ipairs(state.points or {}) do button:SetPoint(unpack(point)) end
        end
    end
    wipe(self.trackerButtonLayouts or {})
    local title = header.Text or header.Title or tracker.HeaderText
    if title and self.questTitleColor then title:SetTextColor(unpack(self.questTitleColor)) end
    for fontString, color in pairs(self.questFontColors or {}) do
        if fontString and type(fontString.SetTextColor) == "function" then fontString:SetTextColor(unpack(color)) end
    end
    wipe(self.questFontColors or {})
end

local MICRO_BUTTON_FALLBACK_ORDER = {
    "CharacterMicroButton",
    "ProfessionMicroButton",
    "PlayerSpellsMicroButton",
    "SpellbookMicroButton",
    "TalentMicroButton",
    "AchievementMicroButton",
    "QuestLogMicroButton",
    "HousingMicroButton",
    "GuildMicroButton",
    "LFDMicroButton",
    "CollectionsMicroButton",
    "EJMicroButton",
    "StoreMicroButton",
    "MainMenuMicroButton",
}

local function MicroButtons()
    local buttons, seen = {}, {}
    local function Add(value)
        local button = type(value) == "string" and _G[value] or value
        if button and not seen[button] and type(button.SetPoint) == "function"
            and type(button.GetNumPoints) == "function" then
            seen[button] = true
            buttons[#buttons + 1] = button
        end
    end

    -- Retail exposes the authoritative order through MICRO_BUTTONS. The
    -- fallback keeps the layout working across older clients and UI renames.
    if type(_G.MICRO_BUTTONS) == "table" then
        for _, value in ipairs(_G.MICRO_BUTTONS) do Add(value) end
    end
    if #buttons == 0 then
        for _, name in ipairs(MICRO_BUTTON_FALLBACK_ORDER) do Add(name) end
    end
    -- Retail may create HelpMicroButton outside the authoritative
    -- MICRO_BUTTONS array. Include it explicitly; the red question-mark
    -- artwork itself is MainMenuMicroButton on current Retail builds.
    Add("HelpMicroButton")
    return buttons
end

PlaceNativeAddonCompartment = function(self, enabled)
    local button = _G.AddonCompartmentFrame
    if not button or type(button.SetPoint) ~= "function" or InCombatLockdown() then return end
    if not self.addonCompartmentLayout then
        local state = {
            scale = button:GetScale(),
            strata = button:GetFrameStrata(),
            level = button:GetFrameLevel(),
            shown = button:IsShown(),
            points = {},
        }
        for index = 1, button:GetNumPoints() do state.points[index] = { button:GetPoint(index) } end
        self.addonCompartmentLayout = state
    end
    if enabled then
        button:ClearAllPoints()
        -- Overlay the native count inside the square map instead of treating
        -- it as another footer icon. The inset keeps the circle off the border
        -- and the high level prevents map pins from swallowing mouse input.
        button:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", -8, 8)
        button:SetScale(1.1)
        button:SetFrameStrata("HIGH")
        button:SetFrameLevel(Minimap:GetFrameLevel() + 30)
        button:Show()
    else
        local state = self.addonCompartmentLayout
        button:ClearAllPoints()
        for _, point in ipairs(state.points or {}) do button:SetPoint(unpack(point)) end
        if state.scale then button:SetScale(state.scale) end
        if state.strata then button:SetFrameStrata(state.strata) end
        if state.level then button:SetFrameLevel(state.level) end
        button:SetShown(state.shown)
        self.addonCompartmentLayout = nil
    end
end

-- The Blizzard micro menu is kept as one responsive row immediately below
-- the minimap. Buttons remain owned by Blizzard (and retain all secure
-- behavior), while their anchors and scale are fitted to the map width.
function MinimalUI:StyleMicroMenu(enabled)
    if InCombatLockdown() then return end
    self.microButtonLayouts = self.microButtonLayouts or UI.WeakKeys()

    if not enabled or not Minimap then
        for button, state in pairs(self.microButtonLayouts) do
            button:ClearAllPoints()
            for _, point in ipairs(state.points or {}) do button:SetPoint(unpack(point)) end
            if state.scale then button:SetScale(state.scale) end
            if state.shown ~= nil then button:SetShown(state.shown) end
        end
        wipe(self.microButtonLayouts)
        if self.microMenuAnchor then self.microMenuAnchor:Hide() end
        for _, slot in ipairs(self.microMenuSlots or {}) do slot:Hide() end
        return
    end

    if not self.microMenuAnchor then
        local anchor = CreateFrame("Frame", "MythicBoostMicroMenuAnchor", UIParent)
        anchor:EnableMouse(false)
        anchor.rail = anchor:CreateTexture(nil, "BACKGROUND")
        anchor.rail:SetAllPoints()
        anchor.rail:SetColorTexture(.035, .024, .010, .72)
        anchor.railTop = anchor:CreateTexture(nil, "BORDER")
        anchor.railTop:SetPoint("TOPLEFT", 0, 0)
        anchor.railTop:SetPoint("TOPRIGHT", 0, 0)
        anchor.railTop:SetHeight(1)
        anchor.railTop:SetColorTexture(.98, .76, .22, .82)
        anchor.railBottom = anchor:CreateTexture(nil, "BORDER")
        anchor.railBottom:SetPoint("BOTTOMLEFT", 0, 0)
        anchor.railBottom:SetPoint("BOTTOMRIGHT", 0, 0)
        anchor.railBottom:SetHeight(1)
        anchor.railBottom:SetColorTexture(.20, .11, .025, .90)
        self.microMenuAnchor = anchor
    end

    local anchor = self.microMenuAnchor
    local mapWidth = math.max(120, Minimap:GetWidth() or 245)
    -- Ряд шире карты и почти без промежутка между кнопками. Вся выигранная
    -- ширина уходит в раскладку ниже: чем её больше, тем больше колонок
    -- помещается и тем меньше строк приходится занимать под картой.
    -- Blizzard micro-button frames contain roughly three pixels of transparent
    -- side padding. A numeric gap of zero therefore still produced obvious
    -- visual holes. Compensate that template padding in the slot pitch: the
    -- visible artwork now meets edge-to-edge while each native button retains
    -- its complete clickable frame.
    -- Весь ряд обязан помещаться ровно под квадратом: ни персонаж слева,
    -- ни системная кнопка справа не выходят за вертикали рамки миникарты.
    -- Нулевой шаг: штатные кнопки равномерно делят всю ширину карты без
    -- дополнительного промежутка между кликабельными слотами.
    local rowWidth, gap = mapWidth, 0
    anchor:ClearAllPoints()
    -- The minimap sits against the right screen edge. Any extra footer width
    -- must grow leftward; centring it clipped the final buttons off-screen.
    anchor:SetPoint("TOPRIGHT", Minimap, "BOTTOMRIGHT", 0, -4)
    anchor:SetWidth(rowWidth)
    anchor:Show()

    local visible = {}
    for _, button in ipairs(MicroButtons()) do
        local state = self.microButtonLayouts[button]
        if not state then
            state = { scale = button:GetScale(), shown = button:IsShown(), points = {} }
            for index = 1, button:GetNumPoints() do state.points[index] = { button:GetPoint(index) } end
            self.microButtonLayouts[button] = state
        end
        local buttonName = type(button.GetName) == "function" and button:GetName() or nil
        local isDefaultQuestionButton = button == _G.HelpMicroButton
            or button == _G.MainMenuMicroButton
            or buttonName == "HelpMicroButton"
            or buttonName == "MainMenuMicroButton"
        if isDefaultQuestionButton then
            if type(button.HookScript) == "function" and not button.__mbKeepQuestionHidden then
                button.__mbKeepQuestionHidden = true
                button:HookScript("OnShow", function(owner)
                    if self.minimapOwnershipActive and not owner.__mbQuestionHideActive then
                        owner.__mbQuestionHideActive = true
                        pcall(owner.Hide, owner)
                        owner.__mbQuestionHideActive = nil
                    end
                end)
            end
            button:Hide()
        else
            local visibleOnScreen = type(button.IsVisible) == "function" and button:IsVisible() or button:IsShown()
            if visibleOnScreen then visible[#visible + 1] = button end
        end
    end

    local count = #visible
    if count == 0 then
        anchor:SetHeight(1)
        anchor:Hide()
        return
    end

    local availableWidth = anchor:GetWidth() or rowWidth

    -- Every visible Blizzard micro button stays in one even row below the map.
    local columns, rows = count, 1
    local targetWidth = (availableWidth - gap * (columns - 1)) / columns

    local uiScale = type(UIParent.GetEffectiveScale) == "function" and UIParent:GetEffectiveScale() or 1

    -- Высота строки известна только после расчёта всех масштабов, а разложить
    -- кнопки по строкам без неё нельзя — отсюда два прохода.
    local scales, rowHeight = {}, 1
    for index, button in ipairs(visible) do
        local nativeWidth = math.max(1, button:GetWidth() or 28)
        local nativeHeight = math.max(1, button:GetHeight() or nativeWidth)
        local parent = button:GetParent()
        local parentScale = parent and type(parent.GetEffectiveScale) == "function"
            and parent:GetEffectiveScale() or uiScale
        local scale = (targetWidth / nativeWidth) * (uiScale / math.max(.01, parentScale))
        scale = math.max(.35, math.min(1.35, scale))
        scales[index] = scale
        rowHeight = math.max(rowHeight, nativeHeight * scale * (parentScale / math.max(.01, uiScale)))
    end

    self.microMenuSlots = self.microMenuSlots or {}
    for index, button in ipairs(visible) do
        local column, row = (index - 1) % columns, math.floor((index - 1) / columns)
        local slot = self.microMenuSlots[index]
        if not slot then
            slot = CreateFrame("Frame", nil, anchor)
            slot:EnableMouse(false)
            self.microMenuSlots[index] = slot
        end
        slot:ClearAllPoints()
        slot:SetPoint("TOPLEFT", anchor, "TOPLEFT",
            column * (targetWidth + gap), -row * (rowHeight + gap))
        slot:SetSize(targetWidth, rowHeight)
        slot:Show()

        button:ClearAllPoints()
        button:SetScale(scales[index])
        -- Native micro-button templates use different transparent top/bottom
        -- insets. Centre their full frames in equal slots so the visible
        -- artwork shares one baseline instead of forming a small staircase.
        button:SetPoint("CENTER", slot, "CENTER", 0, 0)
    end
    for index = count + 1, #(self.microMenuSlots or {}) do self.microMenuSlots[index]:Hide() end
    anchor:SetHeight(rows * rowHeight + (rows - 1) * gap)
end

local ACTION_BUTTON_PREFIXES = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button",
    "MultiBar6Button", "MultiBar7Button", "PetActionButton", "StanceButton",
    "PossessButton",
}
local ACTION_ICON_INSET = 1
local ACTION_BORDER_INSET = 0

local function ActionButtons()
    local buttons = {}
    for _, prefix in ipairs(ACTION_BUTTON_PREFIXES) do
        for index = 1, 12 do
            local button = _G[prefix .. index]
            if button then buttons[#buttons + 1] = button end
        end
    end
    for _, button in pairs({ _G.ExtraActionButton1, _G.ZoneAbilityFrame and ZoneAbilityFrame.SpellButton }) do
        if button then buttons[#buttons + 1] = button end
    end
    return buttons
end

local function SaveFont(fontString)
    if not fontString or type(fontString.GetFont) ~= "function" then return end
    local path, size, flags = fontString:GetFont()
    return { path, size, flags, color = { fontString:GetTextColor() } }
end

local function BagFrames()
    local frames, seen = {}, {}
    local function Add(frame)
        if frame and not seen[frame] and type(frame.Hide) == "function" then
            seen[frame] = true
            frames[#frames + 1] = frame
        end
    end
    Add(_G.BagsBar)
    Add(_G.MainMenuBarBagManager)
    Add(_G.MainMenuBarBackpackButton)
    Add(_G.KeyRingButton)
    Add(_G.BagBarExpandToggle)
    for index = 0, 4 do Add(_G["CharacterBag" .. index .. "Slot"]) end
    return frames
end

-- Панель сумок скрывается независимо от Minimal UI. Открытие инвентаря по
-- клавишам и сами ContainerFrame не затрагиваются.
function MinimalUI:StyleBags(hidden)
    if InCombatLockdown() then return end
    self.bagVisibility = self.bagVisibility or UI.WeakKeys()
    for _, frame in ipairs(BagFrames()) do
        local state = self.bagVisibility[frame]
        if hidden then
            if state == nil then self.bagVisibility[frame] = frame:IsShown() and true or false end
            frame:Hide()
            if not frame.__mbHideBagsHook then
                frame.__mbHideBagsHook = true
                frame:HookScript("OnShow", function(owner)
                    local settings = MythicBoostDB and MythicBoostDB.convenience
                    if settings and settings.hideBags ~= false and not InCombatLockdown()
                        and not owner.__mbBagHideActive then
                        owner.__mbBagHideActive = true
                        pcall(owner.Hide, owner)
                        owner.__mbBagHideActive = nil
                    end
                end)
            end
        elseif state ~= nil then
            frame:SetShown(state)
            self.bagVisibility[frame] = nil
        end
    end
end

local function IsEmptyActionButton(button)
    local action = button.action
    if not action and type(button.CalculateAction) == "function" then
        local ok, value = pcall(button.CalculateAction, button)
        if ok then action = value end
    end
    if UI.UsableNumber(action) and type(HasAction) == "function" then
        local ok, present = pcall(HasAction, action)
        if ok and type(present) == "boolean" and not issecretvalue(present) then return not present end
    end
    local icon = button.icon or button.Icon
    return icon and not icon:GetTexture()
end

local function CooldownViewerHasActiveIcon(viewer)
    if not viewer or type(viewer.GetChildren) ~= "function" then return false end
    for _, child in ipairs({ viewer:GetChildren() }) do
        if child and child:IsShown() and child:GetAlpha() > .05 and type(child.GetRegions) == "function" then
            for _, region in ipairs({ child:GetRegions() }) do
                if region and type(region.GetObjectType) == "function"
                    and region:GetObjectType() == "Texture" and region:IsShown()
                    and region:GetAlpha() > .05 and type(region.GetTexture) == "function"
                    and region:GetTexture() then
                    return true
                end
            end
        end
    end
    return false
end

local COOLDOWN_VIEWER_NAMES = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}

-- Очередь и seen создаются один раз на обход, а вот { frame:GetChildren() }
-- выделяла таблицу на каждый из ста шестидесяти узлов — и так каждые
-- 2.5 секунды из страховочного прохода.
local function PushChildren(queue, ...)
    for index = 1, select("#", ...) do
        queue[#queue + 1] = select(index, ...)
    end
end

local function WalkCooldownViewer(root, callback)
    if not root then return end
    local queue, seen = { root }, {}
    local index = 1
    while queue[index] and index <= 160 do
        local frame = queue[index]
        index = index + 1
        if not seen[frame] then
            seen[frame] = true
            callback(frame)
            if type(frame.GetChildren) == "function" then
                PushChildren(queue, frame:GetChildren())
            end
        end
    end
end

local function CreateEffectBarLine(bar, point1, relativePoint1, x1, y1, point2, relativePoint2, x2, y2)
    local line = bar:CreateTexture(nil, "OVERLAY", nil, 7)
    line:SetColorTexture(.08, .54, .62, .96)
    line:SetPoint(point1, bar, relativePoint1, x1, y1)
    line:SetPoint(point2, bar, relativePoint2, x2, y2)
    return line
end

local function EnsureEffectBarSkin(bar)
    if bar.__mbEffectBarSkin then return bar.__mbEffectBarSkin end
    local skin = {}
    skin.background = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
    skin.background:SetPoint("TOPLEFT", 1, -1)
    skin.background:SetPoint("BOTTOMRIGHT", -1, 1)
    skin.background:SetColorTexture(1, 1, 1, 1)
    skin.background:SetGradient("HORIZONTAL",
        CreateColor(.006, .018, .026, .97),
        CreateColor(.055, .030, .070, .96))

    skin.gloss = bar:CreateTexture(nil, "OVERLAY", nil, 5)
    skin.gloss:SetPoint("TOPLEFT", 2, -2)
    skin.gloss:SetPoint("TOPRIGHT", -2, -2)
    skin.gloss:SetHeight(math.max(3, (bar:GetHeight() or 22) * .42))
    skin.gloss:SetColorTexture(1, 1, 1, 1)
    skin.gloss:SetBlendMode("ADD")
    skin.gloss:SetGradient("VERTICAL",
        CreateColor(1, 1, 1, 0),
        CreateColor(.88, .96, 1, .20))

    skin.top = CreateEffectBarLine(bar, "TOPLEFT", "TOPLEFT", 0, 0, "TOPRIGHT", "TOPRIGHT", 0, 0)
    skin.top:SetHeight(1)
    skin.bottom = CreateEffectBarLine(bar, "BOTTOMLEFT", "BOTTOMLEFT", 0, 0, "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0)
    skin.bottom:SetHeight(1)
    skin.left = CreateEffectBarLine(bar, "TOPLEFT", "TOPLEFT", 0, 0, "BOTTOMLEFT", "BOTTOMLEFT", 0, 0)
    skin.left:SetWidth(1)
    skin.right = CreateEffectBarLine(bar, "TOPRIGHT", "TOPRIGHT", 0, 0, "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0)
    skin.right:SetWidth(1)

    skin.spark = bar:CreateTexture(nil, "OVERLAY", nil, 6)
    skin.spark:SetWidth(2)
    skin.spark:SetColorTexture(1, .74, .16, .96)
    skin.spark:SetBlendMode("ADD")
    bar.__mbEffectBarSkin = skin
    return skin
end

local function SetEffectBarSkinShown(skin, shown)
    if not skin then return end
    for _, region in pairs(skin) do
        if region and type(region.SetShown) == "function" then region:SetShown(shown) end
    end
end

local function EnsureEffectIconSkin(owner, icon)
    if owner.__mbEffectIconSkin then return owner.__mbEffectIconSkin end
    local skin = {}
    local function Line()
        local line = owner:CreateTexture(nil, "OVERLAY", nil, 7)
        line:SetColorTexture(.08, .54, .62, .98)
        line.__mbEffectDecoration = true
        skin[#skin + 1] = line
        return line
    end
    local top = Line()
    top:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
    top:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 1, 1)
    top:SetHeight(1)
    local bottom = Line()
    bottom:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", -1, -1)
    bottom:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
    bottom:SetHeight(1)
    local left = Line()
    left:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
    left:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", -1, -1)
    left:SetWidth(1)
    local right = Line()
    right:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 1, 1)
    right:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
    right:SetWidth(1)
    owner.__mbEffectIconSkin = skin
    return skin
end

-- Цвета градиента постоянные, а CreateColor создаёт таблицу. Вызов стоял вне
-- сторожа и шёл на каждый элемент каждый проход — две таблицы в мусор
-- каждые 2.5 секунды на каждую полосу. Создаём один раз.
local EFFECT_FILL_BOTTOM = CreateColor and CreateColor(.48, .13, .015, 1)
local EFFECT_FILL_TOP = CreateColor and CreateColor(1, .45, .035, 1)

local function CooldownViewerIcon(button)
    local icon = button and (button.Icon or button.icon)
    if icon and type(icon.GetTexture) == "function" and icon:GetTexture() then return icon end
end

function MinimalUI:QueueCompactCooldownIcons()
    if self.cooldownIconLayoutQueued or not C_Timer then return end
    self.cooldownIconLayoutQueued = true
    C_Timer.After(0, function()
        self.cooldownIconLayoutQueued = nil
        if MythicBoostDB and MythicBoostDB.minimalUI then self:CompactCooldownIcons(true) end
    end)
end

function MinimalUI:CompactCooldownIcons(enabled)
    local viewer = _G.BuffIconCooldownViewer
    if not viewer or type(viewer.GetChildren) ~= "function" then return end
    self.cooldownIconLayouts = self.cooldownIconLayouts or UI.WeakKeys()

    local buttons, visible = { viewer:GetChildren() }, {}
    for _, button in ipairs(buttons) do
        local icon = CooldownViewerIcon(button)
        if icon and type(button.GetNumPoints) == "function" then
            local state = self.cooldownIconLayouts[button]
            if not state then
                state = { points = {} }
                for index = 1, button:GetNumPoints() do state.points[index] = { button:GetPoint(index) } end
                self.cooldownIconLayouts[button] = state
            end
            if not button.__mbCompactCooldownHooked then
                button.__mbCompactCooldownHooked = true
                button:HookScript("OnShow", function() self:QueueCompactCooldownIcons() end)
                button:HookScript("OnHide", function() self:QueueCompactCooldownIcons() end)
            end
            if enabled and button:IsShown() and button:GetAlpha() > .05 and icon:IsShown()
                and icon:GetAlpha() > .05 then
                visible[#visible + 1] = button
            end
        end
    end

    if not enabled then
        for button, state in pairs(self.cooldownIconLayouts) do
            local protected = button and type(button.IsProtected) == "function" and button:IsProtected()
            if button and not (InCombatLockdown() and protected) then
                button:ClearAllPoints()
                for _, point in ipairs(state.points or {}) do button:SetPoint(unpack(point)) end
            end
        end
        wipe(self.cooldownIconLayouts)
        return
    end
    if #visible == 0 then return end
    for _, button in ipairs(visible) do
        if InCombatLockdown() and type(button.IsProtected) == "function" and button:IsProtected() then return end
    end

    local gap, total = 4, 0
    for index, button in ipairs(visible) do
        total = total + math.max(1, button:GetWidth() or button:GetHeight() or 36)
        if index > 1 then total = total + gap end
    end
    local cursor = -total * .5
    for _, button in ipairs(visible) do
        local width = math.max(1, button:GetWidth() or button:GetHeight() or 36)
        button:ClearAllPoints()
        button:SetPoint("CENTER", viewer, "CENTER", cursor + width * .5, 0)
        cursor = cursor + width + gap
    end
end

function MinimalUI:StyleCooldownEffectBars(enabled)
    self:CompactCooldownIcons(enabled)
    if InCombatLockdown() then return end
    local viewer = _G.BuffBarCooldownViewer
    if not viewer then return end
    self.effectBarStates = self.effectBarStates or UI.WeakKeys()
    self.effectFontStates = self.effectFontStates or UI.WeakKeys()
    self.effectIconStates = self.effectIconStates or UI.WeakKeys()

    if not enabled then
        for bar, state in pairs(self.effectBarStates) do
            if state.texture then bar:SetStatusBarTexture(state.texture) end
            if state.color then bar:SetStatusBarColor(unpack(state.color)) end
            for region, alpha in pairs(state.regionAlpha or {}) do region:SetAlpha(alpha) end
            SetEffectBarSkinShown(bar.__mbEffectBarSkin, false)
        end
        for fontString, state in pairs(self.effectFontStates) do
            if state and state[1] then
                fontString:SetFont(state[1], state[2], state[3])
                if state.color then fontString:SetTextColor(unpack(state.color)) end
            end
        end
        for icon, state in pairs(self.effectIconStates) do
            if state.coords and #state.coords > 0 then icon:SetTexCoord(unpack(state.coords)) end
            SetEffectBarSkinShown(state.skin, false)
        end
        wipe(self.effectBarStates)
        wipe(self.effectFontStates)
        wipe(self.effectIconStates)
        return
    end

    WalkCooldownViewer(viewer, function(frame)
        local objectType = type(frame.GetObjectType) == "function" and frame:GetObjectType()
        if objectType == "StatusBar" then
            local state = self.effectBarStates[frame]
            if not state then
                local fill = frame:GetStatusBarTexture()
                state = {
                    texture = fill and fill:GetTexture(),
                    color = { frame:GetStatusBarColor() },
                    regionAlpha = {},
                }
                self.effectBarStates[frame] = state
            end

            if enabled then
                local fill = frame:GetStatusBarTexture()
                for _, region in ipairs({ frame:GetRegions() }) do
                    if region ~= fill and type(region.GetObjectType) == "function"
                        and region:GetObjectType() == "Texture" and not region.__mbEffectDecoration then
                        if state.regionAlpha[region] == nil then state.regionAlpha[region] = region:GetAlpha() end
                        region:SetAlpha(0)
                    end
                end
                frame:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                frame:SetStatusBarColor(1, 1, 1, 1)
                fill = frame:GetStatusBarTexture()
                if fill and EFFECT_FILL_BOTTOM then
                    fill:SetGradient("VERTICAL", EFFECT_FILL_BOTTOM, EFFECT_FILL_TOP)
                end
                local skin = EnsureEffectBarSkin(frame)
                for _, region in pairs(skin) do
                    if region then region.__mbEffectDecoration = true end
                end
                skin.gloss:SetHeight(math.max(3, (frame:GetHeight() or 22) * .42))
                skin.spark:ClearAllPoints()
                if fill then
                    skin.spark:SetPoint("TOP", fill, "TOPRIGHT", 0, -1)
                    skin.spark:SetPoint("BOTTOM", fill, "BOTTOMRIGHT", 0, 1)
                end
                SetEffectBarSkinShown(skin, true)
            end
        end

        if type(frame.GetRegions) == "function" then
            for _, region in ipairs({ frame:GetRegions() }) do
                if type(region.GetObjectType) == "function" and region:GetObjectType() == "FontString"
                    and type(region.GetFont) == "function" then
                    local state = self.effectFontStates[region]
                    if not state then state = SaveFont(region); self.effectFontStates[region] = state end
                    if state and state[1] and (state[2] or 12) <= 18 then
                        if enabled then
                            region:SetFont(state[1], math.max(13, state[2] or 12), "OUTLINE")
                            region:SetShadowColor(0, 0, 0, .95)
                            region:SetShadowOffset(1, -1)
                        end
                    end
                end
            end
        end

        local icon = frame.Icon or frame.icon
        if icon and type(icon.GetTexCoord) == "function" then
            local state = self.effectIconStates[icon]
            if not state then
                state = { coords = { icon:GetTexCoord() }, skin = EnsureEffectIconSkin(frame, icon) }
                self.effectIconStates[icon] = state
            end
            icon:SetTexCoord(.07, .93, .07, .93)
            SetEffectBarSkinShown(state.skin, true)
        end
    end)
end

function MinimalUI:StyleActionButtons(enabled)
    -- Экшен-кнопки защищены в бою. Настройка уже сохранена, а визуальное
    -- применение/возврат выполнится на PLAYER_REGEN_ENABLED.
    if InCombatLockdown() then
        -- Якоря и размеры в бою не трогаем, но подсветка ротации — обычная
        -- визуальная надстройка. Она как раз создаётся/анимируется в бою, так
        -- что её необходимо заглушать и здесь.
        if enabled then
            for _, button in ipairs(ActionButtons()) do
                MuteActionSuggestionGlows(self, button)
            end
        end
        return
    end
    self.actionState = self.actionState or UI.WeakKeys()
    local parents = {}
    for _, button in ipairs(ActionButtons()) do
        local state = self.actionState[button]
        if enabled then
            local cooldown = button.cooldown or button.Cooldown
            if not state then
                local icon = button.icon or button.Icon
                state = {
                    icon = icon,
                    texCoords = icon and { icon:GetTexCoord() },
                    iconColor = icon and type(icon.GetVertexColor) == "function"
                        and { icon:GetVertexColor() } or nil,
                    iconAlpha = icon and type(icon.GetAlpha) == "function" and icon:GetAlpha() or nil,
                    iconDesaturated = icon and type(icon.IsDesaturated) == "function"
                        and icon:IsDesaturated() or nil,
                    iconPoints = {},
                    hotkey = SaveFont(button.HotKey),
                    count = SaveFont(button.Count),
                    name = SaveFont(button.Name),
                    cooldownSwipe = cooldown and type(cooldown.GetSwipeColor) == "function"
                        and { cooldown:GetSwipeColor() } or nil,
                    cooldownFonts = {},
                }
                if icon then
                    for index = 1, icon:GetNumPoints() do
                        state.iconPoints[index] = { icon:GetPoint(index) }
                    end
                end
                self.actionState[button] = state
            end
            for _, texture in pairs({
                button.NormalTexture, button.FloatingBG, button.SlotBackground,
                button.Border, button.IconMask, button.SlotArt, button.Background,
                type(button.GetNormalTexture) == "function" and button:GetNormalTexture() or nil,
            }) do
                RememberAndHide(self, texture)
            end
            MuteActionStateTextures(self, button)
            if state.icon then
                state.icon:ClearAllPoints()
                state.icon:SetPoint("TOPLEFT", button, "TOPLEFT", ACTION_ICON_INSET, -ACTION_ICON_INSET)
                state.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -ACTION_ICON_INSET, ACTION_ICON_INSET)
                state.icon:SetTexCoord(.06, .94, .06, .94)
                state.icon:SetVertexColor(1, 1, 1, 1)
                state.icon:SetAlpha(1)
                if type(state.icon.SetDesaturated) == "function" then state.icon:SetDesaturated(false) end
            end
            if not button.__mbActionLight then
                local light = button:CreateTexture(nil, "ARTWORK", nil, 6)
                light:SetPoint("TOPLEFT", ACTION_ICON_INSET, -ACTION_ICON_INSET)
                light:SetPoint("BOTTOMRIGHT", -ACTION_ICON_INSET, ACTION_ICON_INSET)
                light:SetColorTexture(.72, .88, 1, .08)
                light:SetBlendMode("ADD")
                light.__mbActionDecoration = true
                button.__mbActionLight = light
            end
            if not button.__mbActionGloss then
                local gloss = button:CreateTexture(nil, "ARTWORK", nil, 7)
                gloss:SetPoint("TOPLEFT", ACTION_ICON_INSET, -ACTION_ICON_INSET)
                gloss:SetPoint("TOPRIGHT", -ACTION_ICON_INSET, -ACTION_ICON_INSET)
                gloss:SetHeight(math.max(3, (button:GetHeight() or 34) * .42))
                gloss:SetColorTexture(1, 1, 1, 1)
                gloss:SetBlendMode("ADD")
                gloss:SetGradient("VERTICAL",
                    CreateColor(.98, .76, .22, 0),
                    CreateColor(.98, .76, .22, .22))
                gloss.__mbActionDecoration = true
                button.__mbActionGloss = gloss
            end
            if not button.__mbEmptyFill then
                local fill = button:CreateTexture(nil, "BACKGROUND", nil, 2)
                fill:SetPoint("TOPLEFT", ACTION_ICON_INSET, -ACTION_ICON_INSET)
                fill:SetPoint("BOTTOMRIGHT", -ACTION_ICON_INSET, ACTION_ICON_INSET)
                -- Пустой слот должен лишь намекать на своё место, а не
                -- выглядеть чёрной заглушкой поверх мира.
                fill:SetColorTexture(.16, .22, .28, .24)
                fill.__mbActionDecoration = true
                button.__mbEmptyFill = fill
            end
            if cooldown and type(cooldown.SetSwipeColor) == "function" then
                -- Blizzard's default cooldown swipe is almost opaque black.
                -- Keep cooldown state visible without crushing the spell art.
                cooldown:SetSwipeColor(0, 0, 0, .42)
            end
            if cooldown and type(cooldown.GetRegions) == "function" then
                for _, region in ipairs({ cooldown:GetRegions() }) do
                    if region and type(region.GetObjectType) == "function"
                        and region:GetObjectType() == "FontString" and type(region.GetFont) == "function" then
                        if not state.cooldownFonts[region] then state.cooldownFonts[region] = SaveFont(region) end
                        local font = state.cooldownFonts[region]
                        if font and font[1] then region:SetFont(font[1], math.max(font[2] or 16, 16), "OUTLINE") end
                    end
                end
            end
            if button.HotKey and state.hotkey and state.hotkey[1] then
                button.HotKey:SetFont(state.hotkey[1], 11, "OUTLINE")
                button.HotKey:SetTextColor(.92, .96, 1, 1)
            end
            if button.Count and state.count and state.count[1] then
                button.Count:SetFont(state.count[1], 12, "OUTLINE")
                button.Count:SetTextColor(1, 1, 1, 1)
            end
            if button.Name and state.name and state.name[1] then
                button.Name:SetFont(state.name[1], 10, "OUTLINE")
                button.Name:SetTextColor(.86, .91, .96, 1)
            end
            if not button.__mbMinimalBorder then
                local border = CreateFrame("Frame", nil, button, "BackdropTemplate")
                border:SetPoint("TOPLEFT", ACTION_BORDER_INSET, -ACTION_BORDER_INSET)
                border:SetPoint("BOTTOMRIGHT", -ACTION_BORDER_INSET, ACTION_BORDER_INSET)
                border:SetFrameLevel(button:GetFrameLevel() + 4)
                border:EnableMouse(false)
                border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
                border:SetBackdropBorderColor(.08, .24, .29, .92)
                button.__mbMinimalBorder = border
                button:HookScript("OnEnter", function(self)
                    self.__mbHovered = true
                    ApplyActionBorderColor(self)
                    if self.HotKey and self.__mbEmptyAction then self.HotKey:SetAlpha(.90) end
                end)
                button:HookScript("OnLeave", function(self)
                    self.__mbHovered = nil
                    ApplyActionBorderColor(self)
                    if self.HotKey and self.__mbEmptyAction then self.HotKey:SetAlpha(.38) end
                end)
            end
            MuteActionSuggestionGlows(self, button)
            button.__mbEmptyAction = IsEmptyActionButton(button)
            button.__mbEmptyFill:SetShown(button.__mbEmptyAction)
            button.__mbActionLight:SetShown(not button.__mbEmptyAction)
            button.__mbActionGloss:SetShown(not button.__mbEmptyAction)
            ApplyActionBorderColor(button)
            if button.HotKey then button.HotKey:SetAlpha(button.__mbEmptyAction and .38 or 1) end
            button.__mbMinimalBorder:Show()
            local parent = button:GetParent()
            if parent and parent ~= UIParent and type(parent.GetWidth) == "function" then
                parents[parent] = (parents[parent] or 0) + 1
            end
        elseif state then
            if state.icon then
                state.icon:ClearAllPoints()
                for _, point in ipairs(state.iconPoints or {}) do state.icon:SetPoint(unpack(point)) end
                if state.texCoords and #state.texCoords > 0 then state.icon:SetTexCoord(unpack(state.texCoords)) end
                if state.iconColor and #state.iconColor > 0 then
                    state.icon:SetVertexColor(unpack(state.iconColor))
                end
                if state.iconAlpha ~= nil then state.icon:SetAlpha(state.iconAlpha) end
                if type(state.icon.SetDesaturated) == "function" then
                    state.icon:SetDesaturated(state.iconDesaturated and true or false)
                end
            end
            if button.HotKey and state.hotkey and state.hotkey[1] then
                button.HotKey:SetFont(state.hotkey[1], state.hotkey[2], state.hotkey[3])
                button.HotKey:SetTextColor(unpack(state.hotkey.color))
            end
            if button.Count and state.count and state.count[1] then
                button.Count:SetFont(state.count[1], state.count[2], state.count[3])
                button.Count:SetTextColor(unpack(state.count.color))
            end
            if button.Name and state.name and state.name[1] then
                button.Name:SetFont(state.name[1], state.name[2], state.name[3])
                button.Name:SetTextColor(unpack(state.name.color))
            end
            if button.__mbMinimalBorder then button.__mbMinimalBorder:Hide() end
            if button.__mbActionGloss then button.__mbActionGloss:Hide() end
            if button.__mbActionLight then button.__mbActionLight:Hide() end
            if button.__mbEmptyFill then button.__mbEmptyFill:Hide() end
            local cooldown = button.cooldown or button.Cooldown
            if cooldown and state.cooldownSwipe and type(cooldown.SetSwipeColor) == "function" then
                cooldown:SetSwipeColor(unpack(state.cooldownSwipe))
            end
            for region, font in pairs(state.cooldownFonts or {}) do
                if region and font and font[1] then region:SetFont(font[1], font[2], font[3]) end
            end
            if button.HotKey then button.HotKey:SetAlpha(1) end
            button.__mbEmptyAction, button.__mbHovered, button.__mbSpellSuggested = nil, nil, nil
        end
    end


    -- Buttons retain their individual one-pixel borders; never draw a large
    -- rectangle around the whole action bar.
end

-- То же самое для строк Details: градиент один и тот же на все полосы.
local DETAILS_FILL_BOTTOM = CreateColor and CreateColor(.36, .36, .36, 1)
local DETAILS_FILL_TOP = CreateColor and CreateColor(1, 1, 1, 1)

local function SafeObjectValue(object, method)
    local callback = object and object[method]
    if type(callback) ~= "function" then return nil end
    local ok, value = pcall(callback, object)
    if ok then return value end
end

local function SafePushObjectChildren(queue, object)
    local callback = object and object.GetChildren
    if type(callback) ~= "function" then return end
    local values = { pcall(callback, object) }
    if not values[1] then return end
    for index = 2, #values do queue[#queue + 1] = values[index] end
end

function MinimalUI:StyleDetails(enabled)
    if not _G.Details or type(Details.GetAllInstances) ~= "function" then return end
    self.detailsState = self.detailsState or UI.WeakKeys()
    for _, instance in ipairs(Details:GetAllInstances() or {}) do
        local base = instance and instance.baseframe
        if base then
            local state = self.detailsState[instance]
            if not state then
                local baseColor = type(base.GetBackdropColor) == "function" and { base:GetBackdropColor() } or nil
                local bgColor = instance.bgdisplay and type(instance.bgdisplay.GetBackdropColor) == "function"
                    and { instance.bgdisplay:GetBackdropColor() } or nil
                state = {
                    bgAlpha = instance.bgdisplay and instance.bgdisplay:GetAlpha(),
                    baseColor = baseColor,
                    bgColor = bgColor,
                    chromeAlpha = instance.color and instance.color[4] or 1,
                    statusAlpha = instance.statusbar_info and instance.statusbar_info.alpha or 1,
                }
                self.detailsState[instance] = state
            end
            if enabled then
                if instance.bgdisplay then instance.bgdisplay:SetAlpha(0) end
                -- SetAlpha(0) у bgdisplay недостаточно: чёрная заливка Details
                -- также находится в backdrop самого baseframe.
                if type(base.SetBackdropColor) == "function" then base:SetBackdropColor(0, 0, 0, 0) end
                if instance.bgdisplay and type(instance.bgdisplay.SetBackdropColor) == "function" then
                    instance.bgdisplay:SetBackdropColor(0, 0, 0, 0)
                end
                -- Details owns several separate pieces of chrome: title strip,
                -- side pins, footer and the main wallpaper. Its own methods
                -- update those layers without hiding text, icons or bar rows.
                if type(instance.InstanceAlpha) == "function" then
                    pcall(instance.InstanceAlpha, instance, 0)
                end
                if type(instance.StatusBarColor) == "function" then
                    pcall(instance.StatusBarColor, instance, nil, nil, nil, 0, true)
                end
                for _, row in ipairs(instance.barras or {}) do
                    if row.textura and type(row.textura.SetStatusBarTexture) == "function" then
                        if not row.__mbTexture then
                            local texture = row.textura:GetStatusBarTexture()
                            row.__mbTexture = texture and texture:GetTexture()
                        end
                        row.textura:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                        local texture = row.textura:GetStatusBarTexture()
                        if texture and DETAILS_FILL_BOTTOM then
                            texture:SetGradient("VERTICAL", DETAILS_FILL_BOTTOM, DETAILS_FILL_TOP)
                        end
                        if not row.__mbGloss then
                            local gloss = row.textura:CreateTexture(nil, "OVERLAY", nil, -7)
                            gloss:SetPoint("TOPLEFT", 0, 0)
                            gloss:SetPoint("TOPRIGHT", 0, 0)
                            gloss:SetHeight(math.max(2, (row.textura:GetHeight() or 12) * .42))
                            gloss:SetColorTexture(1, 1, 1, 1)
                            gloss:SetBlendMode("ADD")
                            gloss:SetGradient("VERTICAL",
                                CreateColor(1, 1, 1, 0),
                                CreateColor(.86, .94, 1, .18))
                            row.__mbGloss = gloss
                        end
                        row.__mbGloss:Show()
                        row.__mbFonts = row.__mbFonts or {}
                        for index = 1, 4 do
                            local text = row["text" .. index]
                            if text and type(text.GetFont) == "function" then
                                if not row.__mbFonts[index] then row.__mbFonts[index] = SaveFont(text) end
                                local font = row.__mbFonts[index]
                                if font and font[1] then
                                    text:SetFont(font[1], math.max(font[2] or 11, index == 1 and 12 or 11), "OUTLINE")
                                end
                            end
                        end
                    end
                end
            else
                if instance.bgdisplay and state.bgAlpha then instance.bgdisplay:SetAlpha(state.bgAlpha) end
                if state.baseColor and type(base.SetBackdropColor) == "function" then
                    base:SetBackdropColor(unpack(state.baseColor))
                end
                if state.bgColor and instance.bgdisplay and type(instance.bgdisplay.SetBackdropColor) == "function" then
                    instance.bgdisplay:SetBackdropColor(unpack(state.bgColor))
                end
                if type(instance.InstanceAlpha) == "function" then
                    pcall(instance.InstanceAlpha, instance, state.chromeAlpha or 1)
                end
                if type(instance.StatusBarColor) == "function" then
                    pcall(instance.StatusBarColor, instance, nil, nil, nil, state.statusAlpha or 1, true)
                end
                for _, row in ipairs(instance.barras or {}) do
                    if row.textura and row.__mbTexture then row.textura:SetStatusBarTexture(row.__mbTexture) end
                    if row.__mbGloss then row.__mbGloss:Hide() end
                    for index = 1, 4 do
                        local text = row["text" .. index]
                        local font = row.__mbFonts and row.__mbFonts[index]
                        if text and font and font[1] then text:SetFont(font[1], font[2], font[3]) end
                    end
                end
            end
        end
    end
end

-- Retail's built-in Damage Meter opens a separate breakdown window when a
-- row is selected.  It is not a Details! instance, so it needs its own small
-- chrome pass.  Keep every Blizzard row/tooltip/scroll handler intact and
-- only replace the oversized black NineSlice/background with the same quiet
-- surface and cyan edge used by the rest of MythicBoost.
local function NativeDamageMeterFrame(frame)
    if not frame or type(frame.GetName) ~= "function" then return false end
    -- DamageMeterEntry exposes a GetName method that can throw while Blizzard
    -- is recycling the row. Discovery must never trust methods on foreign UI
    -- objects, even when their type signature looks correct.
    local name = SafeObjectValue(frame, "GetName")
    if type(name) ~= "string" or not name:find("DamageMeter", 1, true) then return false end
    if name:match("^DamageMeterSessionWindow%d+$") then return false end
    if type(frame.GetWidth) ~= "function" or type(frame.GetHeight) ~= "function" then return false end
    return (SafeObjectValue(frame, "GetWidth") or 0) >= 220
        and (SafeObjectValue(frame, "GetHeight") or 0) >= 110
end

local function SaveAndMuteNativeMeterObject(state, object)
    if not object or type(object.SetAlpha) ~= "function" or state.muted[object] ~= nil then return end
    state.muted[object] = type(object.GetAlpha) == "function" and object:GetAlpha() or 1
    object:SetAlpha(0)
end

local function NativeMeterDecorations(frame, state)
    -- Across retail builds the same chrome moved between named fields and a
    -- NineSlice child.  Named objects are safe to mute; large direct textures
    -- are the fallback and cannot be row icons because those are small.
    for _, key in ipairs({
        "NineSlice", "Border", "Background", "Bg", "BG", "Inset", "InsetFrame",
        "TopTileStreaks", "TitleBg", "TitleBackground",
    }) do
        SaveAndMuteNativeMeterObject(state, frame[key])
    end
    if type(frame.GetRegions) == "function" then
        local frameWidth, frameHeight = frame:GetWidth() or 0, frame:GetHeight() or 0
        for _, region in ipairs({ frame:GetRegions() }) do
            if region and type(region.GetObjectType) == "function" and region:GetObjectType() == "Texture"
                and type(region.GetWidth) == "function" and type(region.GetHeight) == "function"
                and (region:GetWidth() or 0) >= frameWidth * .72
                and (region:GetHeight() or 0) >= frameHeight * .55 then
                SaveAndMuteNativeMeterObject(state, region)
            end
        end
    end
end

local function StyleNativeMeterBars(frame, state, enabled)
    state.bars = state.bars or UI.WeakKeys()
    local queue, index, seen = { frame }, 1, {}
    while queue[index] and index <= 140 do
        local node = queue[index]
        index = index + 1
        if node and not seen[node] then
            seen[node] = true
            local objectType = SafeObjectValue(node, "GetObjectType")
            if objectType == "StatusBar" and type(node.SetStatusBarTexture) == "function" then
                local barState = state.bars[node]
                if not barState then
                    local texture = node:GetStatusBarTexture()
                    barState = {
                        texture = texture and texture:GetTexture(),
                        color = { node:GetStatusBarColor() },
                    }
                    local gloss = node:CreateTexture(nil, "ARTWORK", nil, 7)
                    gloss:SetPoint("TOPLEFT", 1, -1)
                    gloss:SetPoint("TOPRIGHT", -1, -1)
                    gloss:SetHeight(math.max(2, (node:GetHeight() or 14) * .42))
                    gloss:SetColorTexture(1, 1, 1, 1)
                    gloss:SetBlendMode("ADD")
                    gloss:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(.9, .96, 1, .16))
                    barState.gloss = gloss
                    state.bars[node] = barState
                end
                if enabled then
                    node:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                    barState.gloss:Show()
                else
                    if barState.texture then node:SetStatusBarTexture(barState.texture) end
                    if barState.color then node:SetStatusBarColor(unpack(barState.color)) end
                    barState.gloss:Hide()
                end
            end
            SafePushObjectChildren(queue, node)
        end
    end
end

function MinimalUI:SkinNativeDamageMeterFrame(frame, enabled, knownWindow)
    if not knownWindow and not NativeDamageMeterFrame(frame) then return end
    self.nativeMeterState = self.nativeMeterState or UI.WeakKeys()
    local state = self.nativeMeterState[frame]
    if not state then
        state = { muted = UI.WeakKeys() }
        self.nativeMeterState[frame] = state

        local fill = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        fill:SetPoint("TOPLEFT", 2, -2)
        fill:SetPoint("BOTTOMRIGHT", -2, 2)
        fill:SetColorTexture(C.surface[1], C.surface[2], C.surface[3], .94)
        state.fill = fill

        local edge = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        edge:SetAllPoints()
        edge:SetFrameLevel(frame:GetFrameLevel() + 1)
        edge:EnableMouse(false)
        edge:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        edge:SetBackdropBorderColor(C.surfaceEdge[1], C.surfaceEdge[2], C.surfaceEdge[3], .96)
        state.edge = edge

        local accent = frame:CreateTexture(nil, "BORDER", nil, 7)
        accent:SetPoint("TOPLEFT", 2, -2)
        accent:SetPoint("TOPRIGHT", -2, -2)
        accent:SetHeight(2)
        accent:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], .88)
        state.accent = accent
    end

    if enabled then
        NativeMeterDecorations(frame, state)
        state.fill:Show(); state.edge:Show(); state.accent:Show()
        StyleNativeMeterBars(frame, state, true)
        local scrollBar = frame.ScrollBar or frame.scrollBar
        if scrollBar and type(scrollBar.SetAlpha) == "function" then
            if state.scrollAlpha == nil then state.scrollAlpha = scrollBar:GetAlpha() end
            scrollBar:SetAlpha(.72)
        end
    else
        for object, alpha in pairs(state.muted) do
            if object and type(object.SetAlpha) == "function" then object:SetAlpha(alpha) end
        end
        wipe(state.muted)
        if state.fill then state.fill:Hide() end
        if state.edge then state.edge:Hide() end
        if state.accent then state.accent:Hide() end
        StyleNativeMeterBars(frame, state, false)
        local scrollBar = frame.ScrollBar or frame.scrollBar
        if scrollBar and state.scrollAlpha ~= nil then scrollBar:SetAlpha(state.scrollAlpha) end
        state.scrollAlpha = nil
    end
end

function MinimalUI:QueueNativeDamageMeterDetails()
    if self.nativeMeterDetailsQueued or not C_Timer then return end
    self.nativeMeterDetailsQueued = true
    C_Timer.After(.05, function()
        self.nativeMeterDetailsQueued = nil
        if not MythicBoostDB or not MythicBoostDB.minimalUI then return end
        -- Detail windows are named DamageMeter globals. Scanning that table
        -- once after a physical row click is cheap and does not mutate the
        -- live EnumerateFrames list that caused the former client freeze.
        for name, frame in pairs(_G) do
            if type(name) == "string" and name:find("DamageMeter", 1, true)
                and NativeDamageMeterFrame(frame) then
                self:SkinNativeDamageMeterFrame(frame, true, false)
            end
        end
    end)
end

local function HookNativeMeterDetailClicks(module, root)
    local queue, index, seen = { root }, 1, {}
    while queue[index] and index <= 140 do
        local node = queue[index]
        index = index + 1
        if node and not seen[node] then
            seen[node] = true
            local objectType = SafeObjectValue(node, "GetObjectType")
            local mouseEnabled = SafeObjectValue(node, "IsMouseEnabled")
            if (objectType == "Button" or mouseEnabled) and not node.__mbMeterDetailHook
                and type(node.HookScript) == "function" then
                node.__mbMeterDetailHook = true
                pcall(node.HookScript, node, "OnMouseUp", function() module:QueueNativeDamageMeterDetails() end)
            end
            SafePushObjectChildren(queue, node)
        end
    end
end

-- Session windows are already exposed by Blizzard's owner or numbered frame
-- globals. Style only those known objects: no global scan, reparenting,
-- resizing or periodic work is needed.
function MinimalUI:StyleNativeDamageMeterWindows(enabled)
    local windows, seen = {}, {}
    local function Add(frame)
        if frame and not seen[frame] and type(frame.GetWidth) == "function" then
            seen[frame] = true
            windows[#windows + 1] = frame
        end
    end
    local owner = _G.DamageMeter
    if owner and type(owner.ForEachSessionWindow) == "function" then
        pcall(owner.ForEachSessionWindow, owner, Add)
    end
    for index = 1, 10 do Add(_G["DamageMeterSessionWindow" .. index]) end
    if not enabled then
        for frame in pairs(self.nativeMeterState or {}) do self:SkinNativeDamageMeterFrame(frame, false) end
        return
    end
    for _, frame in ipairs(windows) do
        self:SkinNativeDamageMeterFrame(frame, true, true)
        HookNativeMeterDetailClicks(self, frame)
    end
end

function MinimalUI:StyleNativeDamageMeter(enabled)
    if type(EnumerateFrames) ~= "function" then return end
    -- Restore only objects we already own. Never enumerate while disabling.
    if not enabled then
        for frame in pairs(self.nativeMeterState or {}) do self:SkinNativeDamageMeterFrame(frame, false) end
        return
    end
    if not _G.DamageMeter and not UI.IsAddOnLoaded("Blizzard_DamageMeter") then return end

    -- EnumerateFrames walks a live linked list. Creating our edge frame from
    -- inside that loop mutates the same list and can make the retail client
    -- spin forever. Collect candidates first, then skin them after enumeration
    -- has fully ended. A short throttle keeps the fallback discovery cheap.
    local now = type(GetTime) == "function" and GetTime() or 0
    if self.nativeMeterLastScan and now > 0 and now - self.nativeMeterLastScan < 10 then
        for frame in pairs(self.nativeMeterState or {}) do self:SkinNativeDamageMeterFrame(frame, true) end
        return
    end
    self.nativeMeterLastScan = now
    local candidates = {}
    local frame = EnumerateFrames()
    while frame do
        if NativeDamageMeterFrame(frame) then candidates[#candidates + 1] = frame end
        frame = EnumerateFrames(frame)
    end
    for _, candidate in ipairs(candidates) do self:SkinNativeDamageMeterFrame(candidate, true) end
end

local function CaptureFrameLayout(frame)
    if not frame or type(frame.GetNumPoints) ~= "function" then return end
    local state = { scale = frame:GetScale(), points = {} }
    for index = 1, frame:GetNumPoints() do
        state.points[index] = { frame:GetPoint(index) }
    end
    return state
end

local function RestoreFrameLayout(frame, state)
    if not frame or not state then return end
    frame:ClearAllPoints()
    for _, point in ipairs(state.points or {}) do frame:SetPoint(unpack(point)) end
    if state.scale then frame:SetScale(state.scale) end
end

-- Keep the familiar Blizzard aura buttons, only move and scale their native
-- container. This preserves right-click cancellation, durations and tooltips.
function MinimalUI:StylePlayerAuras(enabled)
    local buffs, player = _G.BuffFrame, _G.PlayerFrame
    if not buffs or not player then return end
    if InCombatLockdown() then return end

    local customPlayer = MythicBoostDB and MythicBoostDB.unitFrames and MythicBoostDB.unitFrames.enabled ~= false
        and JP.UnitFrames and JP.UnitFrames.displays and JP.UnitFrames.displays.player
    if customPlayer then
        -- UnitFrames рисует собственные бафы в контейнере шириной с фрейм.
        -- Не перетягиваем поверх него широкую штатную ленту Blizzard.
        if self.playerAuraAnchor then self.playerAuraAnchor:Hide() end
        return
    end

    self.auraLayouts = self.auraLayouts or UI.WeakKeys()
    if not self.auraLayouts[buffs] then self.auraLayouts[buffs] = CaptureFrameLayout(buffs) end

    if enabled then
        if not self.playerAuraAnchor then
            local anchor = CreateFrame("Frame", nil, UIParent)
            anchor:SetSize(190, 180)
            self.playerAuraAnchor = anchor
        end
        local anchor = self.playerAuraAnchor
        anchor:ClearAllPoints()
        anchor:SetPoint("TOPRIGHT", player, "BOTTOMRIGHT", 0, -7)
        anchor:Show()

        buffs:ClearAllPoints()
        buffs:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, 0)
        buffs:SetScale(.68)

        local debuffs = _G.DebuffFrame
        if debuffs and debuffs ~= buffs then
            if not self.auraLayouts[debuffs] then self.auraLayouts[debuffs] = CaptureFrameLayout(debuffs) end
            debuffs:ClearAllPoints()
            debuffs:SetPoint("TOPRIGHT", buffs, "BOTTOMRIGHT", 0, -4)
            debuffs:SetScale(.68)
        end
    else
        for frame, state in pairs(self.auraLayouts) do RestoreFrameLayout(frame, state) end
        wipe(self.auraLayouts)
        if self.playerAuraAnchor then self.playerAuraAnchor:Hide() end
    end
end

function MinimalUI:Apply()
    local enabled = MythicBoostDB and MythicBoostDB.minimalUI == true
    local minimapEnabled = enabled and MythicBoostDB.minimalUIOptions
        and MythicBoostDB.minimalUIOptions.minimap ~= false
    local hideBags = MythicBoostDB and MythicBoostDB.convenience
        and MythicBoostDB.convenience.hideBags ~= false
    if not enabled then
        RestoreVisibility(self)
    end
    self:StyleMinimap(minimapEnabled)
    self:StyleMicroMenu(enabled)
    self:StyleObjectiveTracker(enabled)
    local options = MythicBoostDB and MythicBoostDB.minimalUIOptions or {}
    self:StyleStanceBar(enabled and options.hideStanceBar == true)
    -- Micro-menu placement is the tracker's anchor; bind it once more after
    -- the final micro pass so objective rows never retain a stale position.
    self:StyleObjectiveTracker(enabled)
    self:StyleActionButtons(enabled)
    self:StyleCooldownEffectBars(enabled)
    self:StyleDetails(enabled)
    -- Blizzard's own Damage Meter keeps its complete native artwork. The
    -- addon now blends in through its own gold trim instead of repainting a
    -- protected standard window.
    self:StyleNativeDamageMeterWindows(false)
    self:StylePlayerAuras(enabled)
    self:StyleBags(hideBags)

    -- Страховочный проход для тех слоёв, у которых нет своего события: панель
    -- кулдаунов и окна Details создаются на лету чужим кодом, лента
    -- бафов и миникарта перестраиваются молча.
    --
    -- Микроменю, трекер и панели кнопок отсюда убраны — у каждого
    -- есть точный триггер, и тикер повторял их работу вхолостую:
    --   микроменю — hooksecurefunc("UpdateMicroButtons") ниже в Create;
    --   трекер    — hooksecurefunc(tracker, "Update") в StyleObjectiveTracker;
    --   кнопки    — десяток ACTIONBAR_*/UPDATE_* событий выше плюс
    --                добавленный EDIT_MODE_LAYOUTS_UPDATED.
    -- Это были три самых дорогих прохода: рекурсивный обход всего
    -- дерева трекера и одиннадцать семейств кнопок — двадцать четыре
    -- раза в минуту, всегда, даже когда менять нечего.
    if enabled and not self.maintenanceTicker and C_Timer and C_Timer.NewTicker then
        -- Exact events handle the live interface. This is only a fallback for
        -- foreign frames created silently, so a five-second safety pass is
        -- enough and halves idle work during dungeons and busy cities.
        self.maintenanceTicker = C_Timer.NewTicker(5, function()
            if not MythicBoostDB or not MythicBoostDB.minimalUI then return end
            -- Пока открыт режим редактирования, Blizzard должен свободно
            -- показывать и двигать свои макеты без борьбы с нашим тикером.
            if _G.EditModeManagerFrame and _G.EditModeManagerFrame:IsShown() then return end
            local ownMinimap = MythicBoostDB.minimalUIOptions
                and MythicBoostDB.minimalUIOptions.minimap ~= false
            self:StyleMinimap(ownMinimap)
            self:StyleCooldownEffectBars(true)
            self:StyleDetails(true)
            self:StylePlayerAuras(true)
            self:StyleBags(MythicBoostDB.convenience and MythicBoostDB.convenience.hideBags ~= false)
        end)
    elseif not enabled and self.maintenanceTicker then
        self.maintenanceTicker:Cancel()
        self.maintenanceTicker = nil
    end
end

function MinimalUI:SetEnabled(enabled)
    MythicBoostDB.minimalUI = enabled and true or false
    self:Apply()
end

function MinimalUI:StyleStanceBar(enabled)
    if InCombatLockdown() then return end
    local frames = { _G.StanceBar, _G.StanceBarFrame }
    self.stanceBarLayouts = self.stanceBarLayouts or UI.WeakKeys()
    for _, frame in ipairs(frames) do
        if frame and type(frame.SetShown) == "function" then
            if not self.stanceBarLayouts[frame] then
                self.stanceBarLayouts[frame] = { shown = frame:IsShown(), alpha = frame:GetAlpha() }
            end
            local state = self.stanceBarLayouts[frame]
            if enabled then
                frame:Hide()
                frame:SetAlpha(0)
            else
                frame:SetAlpha(state.alpha or 1)
                frame:SetShown(state.shown)
            end
        end
    end
    if not enabled then wipe(self.stanceBarLayouts) end
end

function MinimalUI:SetMinimapEnabled(enabled)
    MythicBoostDB.minimalUIOptions = MythicBoostDB.minimalUIOptions or {}
    MythicBoostDB.minimalUIOptions.minimap = enabled and true or false
    self:StyleMinimap(MythicBoostDB.minimalUI == true and enabled == true)
end

function MinimalUI:Create()
    if self.events then return end
    if type(_G.UpdateMicroButtons) == "function" and not self.microButtonsUpdateHook then
        self.microButtonsUpdateHook = true
        hooksecurefunc("UpdateMicroButtons", function()
            if MythicBoostDB and MythicBoostDB.minimalUI and C_Timer then
                C_Timer.After(0, function() self:StyleMicroMenu(true) end)
            end
        end)
    end
    self.events = CreateFrame("Frame")
    -- RegisterEvent на событие, которого нет в клиенте, бросает ошибку, а
    -- вместе с ней падает весь Create — и модуль остаётся выключенным
    -- целиком из-за одной переименованной строки в следующем патче.
    -- Регистрируем по одному и переживаем пропажу любого.
    for _, event in ipairs({
        "PLAYER_ENTERING_WORLD", "ADDON_LOADED",
        "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED",
        "SCENARIO_UPDATE", "TRACKED_ACHIEVEMENT_UPDATE",
        "ACTIONBAR_SLOT_CHANGED", "UPDATE_BINDINGS", "ACTIONBAR_PAGE_CHANGED",
        "UPDATE_SHAPESHIFT_FORMS", "UPDATE_SHAPESHIFT_FORM", "PET_BAR_UPDATE",
        "UPDATE_VEHICLE_ACTIONBAR", "UPDATE_OVERRIDE_ACTIONBAR",
        "UPDATE_POSSESS_BAR", "UPDATE_EXTRA_ACTIONBAR",
        -- Правка макета в режиме редактирования меняет и число панелей, и
        -- ширину миникарты. Без этого события их подхватывал только
        -- страховочный тикер — с задержкой до двух с половиной секунд.
        "EDIT_MODE_LAYOUTS_UPDATED",
        "PLAYER_REGEN_ENABLED",
    }) do
        if not pcall(self.events.RegisterEvent, self.events, event) then
                JP:Log(L("MinimalUI: событие %s недоступно в этом клиенте"), event)
        end
    end
    -- Событий здесь два десятка, и часть приходит пачками: ACTIONBAR_SLOT_CHANGED
    -- прилетает по одному на слот, а UPDATE_SHAPESHIFT_FORM у друида — на каждое
    -- перекидывание. Раньше КАЖДОЕ событие заводило свой таймер, и каждый гонял
    -- полную пересборку кластера: кнопки восстанавливались, перемерялись и
    -- расставлялись заново по десятку раз подряд с шагом .2 с. Это и выглядело
    -- как подпрыгивающая панель. Склеиваем всё в один отложенный проход — тем же
    -- приёмом, что JP:RequestRefresh в Core.lua.
    local applyQueued = false
    local function QueueApply()
        if applyQueued then return end
        applyQueued = true
        C_Timer.After(.2, function()
            applyQueued = false
            -- В бою перестановка защищённых кнопок заблокирована, но Apply
            -- состоит из полутора десятков шагов со СВОИМИ проверками боя:
            -- часть отрабатывала, часть выходила раньше времени, и панели
            -- оставались наполовину на старых местах. Поэтому в бою не
            -- начинаем вовсе — PLAYER_REGEN_ENABLED зарегистрирован выше и
            -- сам поставит проход в очередь, когда бой кончится.
            if InCombatLockdown() then return end
            self:Apply()
        end)
    end
    self.events:SetScript("OnEvent", function(_, event)
        if event == "ADDON_LOADED" then self.minimapAddonScanDirty = true end
        QueueApply()
    end)
    QueueApply()
end

function MinimalUI:Enable() self:Create(); self:Apply() end
function MinimalUI:Disable() self:SetEnabled(false) end
function MinimalUI:Destroy() self:SetEnabled(false) end

JP.MinimalUI = MinimalUI
JP:RegisterModule("MinimalUI", MinimalUI)
