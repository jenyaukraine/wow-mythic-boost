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
local PANEL_BG = { 0, 0, 0, 0 }
-- Контур — из общих токенов UI.colors. Фон здесь намеренно
-- прозрачный и таким остаётся: эти панели ложатся на миникарту и чат,
-- и любая заливка там закрывает содержимое.
local PANEL_EDGE = { JP.UI.colors.surfaceEdge[1], JP.UI.colors.surfaceEdge[2], JP.UI.colors.surfaceEdge[3], .82 }

local function SyncPanelLayer(panel, target)
    if not panel or not target then return end
    if type(target.GetFrameStrata) == "function" then panel:SetFrameStrata(target:GetFrameStrata()) end
    if type(target.GetFrameLevel) == "function" then panel:SetFrameLevel(math.max(0, target:GetFrameLevel() - 1)) end
end

-- Одна визуальная система для всего HUD. Панель живёт рядом с целевым
-- окном на UIParent, поэтому не перекрывается собственными фонами Details,
-- чата или Blizzard UI и при этом следует за окном при его перемещении.
function MinimalUI:EnsurePanel(target, key, options)
    if not target or type(target.SetPoint) ~= "function" then return end
    key = key or "default"
    options = options or {}
    self.unifiedPanels = self.unifiedPanels or UI.WeakKeys()
    local bucket = self.unifiedPanels[target]
    if not bucket then bucket = {}; self.unifiedPanels[target] = bucket end
    local panel = bucket[key]
    if not panel then
        panel = CreateFrame("Frame", nil, target:GetParent() or UIParent, "BackdropTemplate")
        panel:EnableMouse(false)
        panel:SetClampedToScreen(false)
        panel:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        panel:SetBackdropColor(unpack(PANEL_BG))
        panel:SetBackdropBorderColor(unpack(PANEL_EDGE))
        panel.accent = panel:CreateTexture(nil, "OVERLAY")
        panel.accent:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], .92)
        panel.accent:SetPoint("TOPLEFT", 1, -1)
        panel.accent:SetPoint("TOPRIGHT", -1, -1)
        panel.accent:SetHeight(options.accentHeight or 1)
        bucket[key] = panel

        if not target.__mbUnifiedPanelHooks then
            target.__mbUnifiedPanelHooks = true
            target:HookScript("OnShow", function(owner)
                if MythicBoostDB and MythicBoostDB.minimalUI then
                    for _, ownedPanel in pairs((self.unifiedPanels or {})[owner] or {}) do
                        SyncPanelLayer(ownedPanel, owner)
                        ownedPanel:Show()
                    end
                end
            end)
            target:HookScript("OnHide", function(owner)
                for _, ownedPanel in pairs((self.unifiedPanels or {})[owner] or {}) do ownedPanel:Hide() end
            end)
        end
    end

    local left = options.left or options.padding or 3
    local right = options.right or options.padding or 3
    local top = options.top or options.padding or 3
    local bottom = options.bottom or options.padding or 3
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", target, "TOPLEFT", -left, top)
    panel:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", right, -bottom)
    -- Intentionally ignore the old per-widget bgAlpha values. They are kept in
    -- callers for compatibility, but Minimal UI panels are border-only now.
    panel:SetBackdropColor(PANEL_BG[1], PANEL_BG[2], PANEL_BG[3], PANEL_BG[4])
    SyncPanelLayer(panel, target)
    local visible = type(target.IsVisible) == "function" and target:IsVisible() or target:IsShown()
    panel:SetShown(MythicBoostDB and MythicBoostDB.minimalUI == true and visible)
    return panel
end

function MinimalUI:HideUnifiedPanels()
    for _, bucket in pairs(self.unifiedPanels or {}) do
        for _, panel in pairs(bucket) do panel:Hide() end
    end
end

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
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        local texture = type(button[getter]) == "function" and button[getter](button)
        if texture and type(texture.SetAlpha) == "function" then
            if self.savedTextureAlpha[texture] == nil then self.savedTextureAlpha[texture] = texture:GetAlpha() end
            texture:SetAlpha(0)
        end
    end
end

-- Квадратная рамка кнопки действия держит три состояния сразу, поэтому цвет
-- назначается в одном месте: иначе наведение мышью затирало подсветку
-- подсказанного заклинания, а обновление панели — наведение.
local ACTION_EDGE_IDLE = { .08, .24, .29 }
local ACTION_EDGE_HOVER = { .16, .80, .86, 1 }
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

    local function Mirror(shown)
        button.__mbSpellSuggested = shown or nil
        if shown then
            -- Анимация гоняет альфу сама и перебила бы разовый SetAlpha(0).
            if animation and type(animation.Stop) == "function" then pcall(animation.Stop, animation) end
            object:SetAlpha(0)
        end
        ApplyActionBorderColor(button)
    end

    if not object.__mbGlowHooked then
        object.__mbGlowHooked = true
        hooksecurefunc(object, "Show", function() Mirror(true) end)
        hooksecurefunc(object, "Hide", function() Mirror(false) end)
        hooksecurefunc(object, "SetShown", function(_, shown) Mirror(shown and true or false) end)
    end
    object:SetAlpha(0)
    Mirror(object:IsShown() and true or false)
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
            local state = { frame = frame, parent = frame:GetParent(), points = {} }
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
                label:SetFont(self.minimapZoneLayout.labelFont[1], 11, "OUTLINE")
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

        Place(_G.GameTimeFrame, "calendar", "TOPRIGHT", "TOPRIGHT", -2, -2)
        Place(difficulty, "difficulty", "TOPRIGHT", "TOPRIGHT", -4, -29)
        Place(guildDifficulty, "guildDifficulty", "TOPRIGHT", "TOPRIGHT", -4, -29)
        Place(challengeDifficulty, "challengeDifficulty", "TOPRIGHT", "TOPRIGHT", -4, -29)

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
            if fontPath then text:SetFont(fontPath, 10, "OUTLINE") end
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
        self.minimapClock:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", 5, 5)
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

local function StyleMinimapAddonButtons(self, enabled)
    self.minimapAddonLayouts = self.minimapAddonLayouts or UI.WeakKeys()
    self.minimapButtonSlots = self.minimapButtonSlots or UI.WeakKeys()
    if not enabled then
        for button, state in pairs(self.minimapAddonLayouts) do
            if button and type(button.SetPoint) == "function" then
                if state.parent then button:SetParent(state.parent) end
                button:ClearAllPoints()
                for _, point in ipairs(state.points or {}) do button:SetPoint(unpack(point)) end
                if state.scale then button:SetScale(state.scale) end
                if state.alpha then button:SetAlpha(state.alpha) end
                if type(button.EnableMouse) == "function" then button:EnableMouse(state.mouse and true or false) end
                if state.strata then button:SetFrameStrata(state.strata) end
                if state.level then button:SetFrameLevel(state.level) end
                button:SetShown(state.shown)
            end
            if state.slot then state.slot:Hide() end
        end
        if self.minimapButtonMenu then self.minimapButtonMenu:Hide() end
        if self.minimapButtonLauncher then self.minimapButtonLauncher:Hide() end
        wipe(self.minimapAddonLayouts)
        return
    end

    local buttons, seen = {}, {}
    local function HasIcon(button)
        local icon = button and (button.icon or button.Icon)
        if icon and type(icon.GetTexture) == "function" and icon:GetTexture() then return true end
        if button and type(button.GetRegions) == "function" then
            for _, region in ipairs({ button:GetRegions() }) do
                if region and type(region.GetObjectType) == "function"
                    and region:GetObjectType() == "Texture"
                    and type(region.GetTexture) == "function" and region:GetTexture() then
                    return true
                end
            end
        end
        return false
    end
    local function Add(button)
        if button and button ~= self.minimapButtonLauncher
            and type(button.SetPoint) == "function" and not seen[button]
            and button:IsShown() and HasIcon(button) then
            seen[button] = true
            buttons[#buttons + 1] = button
        end
    end
    -- AddonCompartmentFrame already represents the whole addon collection.
    -- Including it in our own collection produced a second count button.
    for name, object in pairs(_G) do
        if type(name) == "string" and name:match("^LibDBIcon10_") then Add(object) end
    end
    table.sort(buttons, function(a, b)
        return (a:GetName() or "") < (b:GetName() or "")
    end)

    local function EnsureSlot(button)
        local slot = self.minimapButtonSlots[button]
        if not slot then
            slot = CreateFrame("Frame", nil, Minimap, "BackdropTemplate")
            slot:SetSize(24, 24)
            slot:EnableMouse(false)
            slot:SetClipsChildren(true)
            slot:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
            slot:SetBackdropColor(JP.UI.colors.surface[1], JP.UI.colors.surface[2], JP.UI.colors.surface[3], .96)
            slot:SetBackdropBorderColor(.27, .33, .39, 1)

            -- ElvUI's clean square silhouette with a restrained XPerl-like
            -- upper light. It reads as depth but never becomes glossy.
            local depth = slot:CreateTexture(nil, "ARTWORK")
            depth:SetPoint("TOPLEFT", 1, -1)
            depth:SetPoint("BOTTOMRIGHT", -1, 1)
            depth:SetColorTexture(1, 1, 1, 1)
            depth:SetGradient("VERTICAL",
                CreateColor(.34, .44, .54, .13),
                CreateColor(0, 0, 0, .24))
            slot.depth = depth

            button.__mbMinimapSlot = slot
            if type(button.HookScript) == "function" and not button.__mbMinimapHoverHook then
                button.__mbMinimapHoverHook = true
                button:HookScript("OnEnter", function(owner)
                    local ownerSlot = owner.__mbMinimapSlot
                    if ownerSlot then ownerSlot:SetBackdropBorderColor(.24, .72, .92, 1) end
                end)
                button:HookScript("OnLeave", function(owner)
                    local ownerSlot = owner.__mbMinimapSlot
                    if ownerSlot then ownerSlot:SetBackdropBorderColor(.27, .33, .39, 1) end
                end)
            end
            self.minimapButtonSlots[button] = slot
        end
        return slot
    end

    if not self.minimapButtonMenu then
        local launcher = CreateFrame("Button", "MythicBoostMinimapButtonLauncher", Minimap, "BackdropTemplate")
        launcher:SetSize(24, 18)
        launcher:SetFrameStrata("HIGH")
        launcher:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        launcher:SetBackdropColor(0, 0, 0, 0)
        launcher:SetBackdropBorderColor(0, 0, 0, 0)
        launcher.count = launcher:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        launcher.count:SetPoint("CENTER", 0, 0)
        launcher.count:SetTextColor(.95, .78, .20, 1)
        launcher.count:SetShadowColor(0, 0, 0, 1)
        launcher.count:SetShadowOffset(1, -1)

        local menu = CreateFrame("Frame", "MythicBoostMinimapButtonMenu", UIParent, "BackdropTemplate")
        menu:SetFrameStrata("DIALOG")
        menu:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        menu:SetBackdropColor(JP.UI.colors.surface[1], JP.UI.colors.surface[2], JP.UI.colors.surface[3], .97)
        menu:SetBackdropBorderColor(.25, .31, .37, 1)
        menu:Hide()
        launcher:SetScript("OnClick", function()
            menu:SetShown(not menu:IsShown())
        end)
        launcher:SetScript("OnEnter", function(owner)
            owner.count:SetTextColor(.35, .86, 1, 1)
            GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
            GameTooltip:SetText(L("Меню аддонов"))
            GameTooltip:AddLine(L("Нажмите, чтобы показать иконки"), .72, .78, .84)
            GameTooltip:Show()
        end)
        launcher:SetScript("OnLeave", function(owner)
            owner.count:SetTextColor(.95, .78, .20, 1)
            GameTooltip_Hide()
        end)
        self.minimapButtonLauncher = launcher
        self.minimapButtonMenu = menu
        UISpecialFrames = UISpecialFrames or {}
        table.insert(UISpecialFrames, menu:GetName())

        if not self.minimapDrawerCloseHooks then
            self.minimapDrawerCloseHooks = true
            if WorldFrame and type(WorldFrame.HookScript) == "function" then
                WorldFrame:HookScript("OnMouseDown", function()
                    if self.minimapButtonMenu then self.minimapButtonMenu:Hide() end
                end)
            end
            if type(Minimap.HookScript) == "function" then
                Minimap:HookScript("OnMouseDown", function()
                    if self.minimapButtonMenu then self.minimapButtonMenu:Hide() end
                end)
            end
        end
    end

    local launcher, menu = self.minimapButtonLauncher, self.minimapButtonMenu
    for _, slot in pairs(self.minimapButtonSlots) do slot:Hide() end
    launcher:SetParent(Minimap)
    launcher:ClearAllPoints()
    launcher:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", -5, 5)
    launcher.count:SetText(tostring(#buttons))
    launcher:SetShown(#buttons > 0)
    if #buttons == 0 then menu:Hide(); return end
    local columns = math.min(4, math.max(1, #buttons))
    local rows = math.max(1, math.ceil(#buttons / columns))
    menu:ClearAllPoints()
    menu:SetPoint("BOTTOMRIGHT", launcher, "TOPRIGHT", 0, 4)
    menu:SetSize(columns * 27 + 7, rows * 27 + 7)

    for index, button in ipairs(buttons) do
        if not self.minimapAddonLayouts[button] then
            local state = {
                parent = button:GetParent(), scale = button:GetScale(),
                alpha = button:GetAlpha(), mouse = button:IsMouseEnabled(), shown = button:IsShown(),
                strata = button:GetFrameStrata(), level = button:GetFrameLevel(), points = {},
            }
            for pointIndex = 1, button:GetNumPoints() do
                state.points[pointIndex] = { button:GetPoint(pointIndex) }
            end
            self.minimapAddonLayouts[button] = state
        end
        local slot = EnsureSlot(button)
        self.minimapAddonLayouts[button].slot = slot
        local column = (index - 1) % columns
        local row = math.floor((index - 1) / columns)
        slot:SetParent(menu)
        slot:SetFrameStrata(menu:GetFrameStrata())
        slot:SetFrameLevel(menu:GetFrameLevel() + 2)
        slot:ClearAllPoints()
        slot:SetPoint("TOPLEFT", menu, "TOPLEFT", 5 + column * 27, -5 - row * 27)
        slot:Show()
        button:Show()
        button:SetParent(slot)
        button:SetFrameStrata(slot:GetFrameStrata())
        button:SetFrameLevel(slot:GetFrameLevel() + 1)
        button:SetScale(.68)
        button:SetAlpha(1)
        button:EnableMouse(true)
        button:ClearAllPoints()
        button:SetPoint("CENTER", slot, "CENTER", 0, 0)
        button.__mbMinimapMenu = menu
        if type(button.HookScript) == "function" and not button.__mbMinimapMenuCloseHook then
            button.__mbMinimapMenuCloseHook = true
            button:HookScript("OnClick", function(owner)
                if owner.__mbMinimapMenu then owner.__mbMinimapMenu:Hide() end
            end)
        end
    end
    menu:Hide()
end

-- Keep Blizzard's native addon compartment intact. We only anchor its button
-- inside the square minimap; Blizzard continues to own the text dropdown,
-- click handling, tooltip, and addon registration.
local function StyleAddonCompartment(self, enabled)
    local frame = _G.AddonCompartmentFrame
    if not frame then return end
    if enabled then
        if not self.addonCompartmentLayout then
            local state = { shown = frame:IsShown(), points = {} }
            for index = 1, frame:GetNumPoints() do state.points[index] = { frame:GetPoint(index) } end
            self.addonCompartmentLayout = state
        end
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", -5, 5)
        frame:Show()
    elseif self.addonCompartmentLayout then
        local state = self.addonCompartmentLayout
        frame:ClearAllPoints()
        for _, point in ipairs(state.points or {}) do frame:SetPoint(unpack(point)) end
        frame:SetShown(state.shown)
        self.addonCompartmentLayout = nil
    end
end

function MinimalUI:StyleMinimap(enabled)
    if not Minimap then return end
    if not self.roundMask then
        local ok, mask = pcall(Minimap.GetMaskTexture, Minimap)
        self.roundMask = ok and mask or FALLBACK_ROUND_MASK
    end

    if enabled then
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
            Minimap:SetSize(245, 245)
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
            RememberAndHide(self, object)
            if object and type(object.HookScript) == "function" and not object.__mbKeepMinimapHidden then
                object.__mbKeepMinimapHidden = true
                object:HookScript("OnShow", function(owner)
                    if MythicBoostDB and MythicBoostDB.minimalUI then owner:Hide() end
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
        StyleMinimapAddonButtons(self, false)
        StyleAddonCompartment(self, true)
        -- The minimap already has its own one-pixel border. A second enclosing
        -- panel only creates a pointless rectangle around it.
        local panel = self.unifiedPanels and self.unifiedPanels[Minimap] and self.unifiedPanels[Minimap].minimap
        if panel then panel:Hide() end

        -- Keep LibDBIcon buttons visible. SexyMap already knows how to dock
        -- them; hiding them here removed the user's addon shortcuts entirely.

        if not self.mouseWheelHooked then
            self.mouseWheelHooked = true
            Minimap:EnableMouseWheel(true)
            Minimap:HookScript("OnMouseWheel", function(map, delta)
                if not MythicBoostDB or not MythicBoostDB.minimalUI then return end
                local zoom = map:GetZoom() + (delta > 0 and 1 or -1)
                local maximum = type(map.GetZoomLevels) == "function" and map:GetZoomLevels() - 1 or 5
                map:SetZoom(math.max(0, math.min(maximum, zoom)))
            end)
        end
    else
        local layout = self.minimapMapLayout
        if layout and not InCombatLockdown() then
            if layout.parent then Minimap:SetParent(layout.parent) end
            Minimap:ClearAllPoints()
            for _, point in ipairs(layout.points or {}) do Minimap:SetPoint(unpack(point)) end
            if layout.width and layout.height then Minimap:SetSize(layout.width, layout.height) end
        end
        self.minimapMapLayout = nil
        StyleMinimapAddonButtons(self, false)
        StyleAddonCompartment(self, false)
        pcall(Minimap.SetMaskTexture, Minimap, self.roundMask or FALLBACK_ROUND_MASK)
        for _, method in ipairs({
            "SetArchBlobRingScalar", "SetArchBlobRingAlpha",
            "SetQuestBlobRingScalar", "SetQuestBlobRingAlpha",
        }) do
            if type(Minimap[method]) == "function" then pcall(Minimap[method], Minimap, 1) end
        end
        if self.minimapBorder then self.minimapBorder:Hide() end
        StyleMinimapZoneLabel(self, false)
        local panel = self.unifiedPanels and self.unifiedPanels[Minimap] and self.unifiedPanels[Minimap].minimap
        if panel then panel:Hide() end
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
    local panel = self.unifiedPanels and self.unifiedPanels[tracker] and self.unifiedPanels[tracker].tracker
    if panel then panel:Hide() end
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
    return buttons
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
        end
        wipe(self.microButtonLayouts)
        if self.microMenuAnchor then self.microMenuAnchor:Hide() end
        for _, slot in ipairs(self.microMenuSlots or {}) do slot:Hide() end
        return
    end

    if not self.microMenuAnchor then
        local anchor = CreateFrame("Frame", "MythicBoostMicroMenuAnchor", UIParent)
        anchor:EnableMouse(false)
        self.microMenuAnchor = anchor
    end

    local anchor = self.microMenuAnchor
    local mapWidth = math.max(120, Minimap:GetWidth() or 245)
    -- Ряд шире карты и почти без промежутка между кнопками. Вся выигранная
    -- ширина уходит в раскладку ниже: чем её больше, тем больше колонок
    -- помещается и тем меньше строк приходится занимать под картой.
    local rowWidth, gap = mapWidth + 14, .5
    anchor:ClearAllPoints()
    -- Центром под картой, а не по правому краю: ряд может оказаться шире
    -- карты, и тогда он должен свисать одинаково с обеих сторон.
    anchor:SetPoint("TOP", Minimap, "BOTTOM", 0, -4)
    anchor:SetWidth(rowWidth)
    anchor:Show()

    local visible = {}
    for _, button in ipairs(MicroButtons()) do
        local state = self.microButtonLayouts[button]
        if not state then
            state = { scale = button:GetScale(), points = {} }
            for index = 1, button:GetNumPoints() do state.points[index] = { button:GetPoint(index) } end
            self.microButtonLayouts[button] = state
        end
        local visibleOnScreen = type(button.IsVisible) == "function" and button:IsVisible() or button:IsShown()
        if visibleOnScreen then visible[#visible + 1] = button end
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
        scale = math.max(.35, math.min(1.25, scale))
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
        button:SetPoint("TOP", slot, "TOP", 0, 0)
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
                    if settings and settings.hideBags ~= false and not InCombatLockdown() then owner:Hide() end
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

local function ClusterActionButtons()
    -- ExtraActionButton and ZoneAbilityFrame have custom size, animations and
    -- secure owners. Mixing them into the regular grid is what used to distort
    -- its scale, so only homogeneous bar buttons are packed here.
    local buttons = {}
    for _, prefix in ipairs(ACTION_BUTTON_PREFIXES) do
        for index = 1, 12 do
            local button = _G[prefix .. index]
            if button then buttons[#buttons + 1] = button end
        end
    end
    return buttons
end

local function RestoreClusterButton(button, state)
    if not button or not state then return end
    button:ClearAllPoints()
    for _, point in ipairs(state.points or {}) do button:SetPoint(unpack(point)) end
    if state.scale then button:SetScale(state.scale) end
end

local function CaptureClusterFrame(frame)
    local state = { scale = frame:GetScale(), alpha = frame:GetAlpha(), points = {} }
    for index = 1, frame:GetNumPoints() do state.points[index] = { frame:GetPoint(index) } end
    return state
end

local function RestoreClusterFrame(frame, state)
    if not frame or not state then return end
    frame:ClearAllPoints()
    for _, point in ipairs(state.points or {}) do frame:SetPoint(unpack(point)) end
    if state.scale then frame:SetScale(state.scale) end
    if state.alpha then frame:SetAlpha(state.alpha) end
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

function MinimalUI:StyleCooldownEffectBars(enabled)
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

function MinimalUI:LayoutActionCluster(enabled)
    if InCombatLockdown() then return end
    -- Кластер выключен намеренно, и это не временная заглушка.
    --
    -- Он стаскивал В ОДНУ сетку внизу экрана вообще все кнопки: панели
    -- действий, стойки друида, панель питомца и PossessButton. Тем самым он
    -- переопределял раскладку Edit Mode — что бы игрок ни выставил руками,
    -- следующее же событие перекладывало это по-своему. А поскольку
    -- перестановка защищённых кнопок в бою заблокирована, проходы, начатые
    -- в бою, применялись частично и оставляли отдельные панели на чужих
    -- местах. Положение и масштаб панелей теперь целиком за Edit Mode.
    --
    -- Ветка `not enabled` ниже намеренно оставлена рабочей: она возвращает
    -- всё, что кластер успел сдвинуть за текущую сессию, и прячет якорь.
    -- Чтобы вернуть кластер, достаточно убрать одну строку ниже.
    enabled = false
    self.actionClusterState = self.actionClusterState or UI.WeakKeys()

    if not enabled then
        for button, state in pairs(self.actionClusterState) do RestoreClusterButton(button, state) end
        wipe(self.actionClusterState)
        for viewer, state in pairs(self.cooldownViewerLayouts or {}) do
            RestoreClusterFrame(viewer, state)
        end
        wipe(self.cooldownViewerLayouts or {})
        if self.actionClusterAnchor then self.actionClusterAnchor:Hide() end
        return
    end

    local mainButton = _G.ActionButton1
    if not mainButton then return end
    if not self.actionClusterAnchor then
        local anchor = CreateFrame("Frame", "MythicBoostActionCluster", UIParent)
        anchor:SetSize(369, 28)
        anchor:EnableMouse(false)
        self.actionClusterAnchor = anchor
    end
    local anchor = self.actionClusterAnchor
    anchor:ClearAllPoints()
    anchor:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 18)
    anchor:Show()

    local visible = {}
    for _, button in ipairs(ClusterActionButtons()) do
        local state = self.actionClusterState[button]
        if not state then
            state = { scale = button:GetScale(), points = {} }
            for index = 1, button:GetNumPoints() do state.points[index] = { button:GetPoint(index) } end
            self.actionClusterState[button] = state
        else
            RestoreClusterButton(button, state)
        end
        if button:IsVisible() then visible[#visible + 1] = button end
    end

    -- targetSize — сторона кнопки на экране в единицах UIParent. Штатная
    -- кнопка Blizzard — 45; ниже 30 перестают читаться подписи бинда.
    local columns, targetSize = 12, 36
    local columnGap, rowGap = 4, 5
    local rowCount = math.max(1, math.ceil(#visible / columns))
    local widestRow = math.min(columns, math.max(1, #visible))
    local clusterWidth = widestRow * targetSize + math.max(0, widestRow - 1) * columnGap
    local clusterHeight = rowCount * targetSize + math.max(0, rowCount - 1) * rowGap
    anchor:SetSize(clusterWidth, clusterHeight)
    local uiScale = type(UIParent.GetEffectiveScale) == "function" and UIParent:GetEffectiveScale() or 1
    for index, button in ipairs(visible) do
        local column = (index - 1) % columns
        local row = math.floor((index - 1) / columns)
        local rowStart = row * columns + 1
        local rowItems = math.min(columns, #visible - rowStart + 1)
        local rowWidth = rowItems * targetSize + math.max(0, rowItems - 1) * columnGap
        local rowOffset = (clusterWidth - rowWidth) * .5
        local width = button:GetWidth() or targetSize
        local parent = button:GetParent()
        local parentScale = parent and type(parent.GetEffectiveScale) == "function"
            and parent:GetEffectiveScale() or uiScale
        local scale = width > 0 and (targetSize / width) * (uiScale / math.max(.01, parentScale)) or 1
        local appliedScale = math.max(.35, math.min(2, scale))
        button:ClearAllPoints()
        button:SetScale(appliedScale)
        -- Смещения SetPoint измеряются в системе координат САМОЙ кнопки, а она
        -- уменьшена до targetSize. Шаг сетки посчитан в единицах UIParent,
        -- поэтому без обратного пересчёта на экране он выходит меньше ширины
        -- кнопки, и соседние кнопки наезжают друг на друга. Делим именно на
        -- appliedScale, а не на сырой scale: после клампа кнопка стоит в другом
        -- масштабе, чем тот, из которого считался шаг.
        local unit = uiScale / math.max(.01, appliedScale * parentScale)
        button:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT",
            (rowOffset + column * (targetSize + columnGap)) * unit,
            (row * (targetSize + rowGap)) * unit)
    end

    -- Blizzard's Cooldown Manager is a separate Edit Mode family. Anchor its
    -- visible viewers to the same dynamic container so action rows can never
    -- grow underneath them or drift to another part of the screen.
    self.cooldownViewerLayouts = self.cooldownViewerLayouts or UI.WeakKeys()
    local viewerOffset = 9
    local editMode = _G.EditModeManagerFrame and _G.EditModeManagerFrame:IsShown()
    for _, name in ipairs(COOLDOWN_VIEWER_NAMES) do
        local viewer = _G[name]
        if viewer and type(viewer.GetNumPoints) == "function" then
            if not self.cooldownViewerLayouts[viewer] then
                self.cooldownViewerLayouts[viewer] = CaptureClusterFrame(viewer)
            end
            local active = editMode or CooldownViewerHasActiveIcon(viewer)
            viewer:SetAlpha(active and (self.cooldownViewerLayouts[viewer].alpha or 1) or 0)
            if active and viewer:IsShown() then
                viewer:ClearAllPoints()
                viewer:SetPoint("BOTTOM", anchor, "TOP", 0, viewerOffset)
                viewerOffset = viewerOffset + math.max(1, viewer:GetHeight() or 1) + 6
            end
        end
    end
end

function MinimalUI:StyleActionButtons(enabled)
    -- Экшен-кнопки защищены в бою. Настройка уже сохранена, а визуальное
    -- применение/возврат выполнится на PLAYER_REGEN_ENABLED.
    if InCombatLockdown() then return end
    self.actionState = self.actionState or UI.WeakKeys()
    local parents = {}
    for _, button in ipairs(ActionButtons()) do
        local state = self.actionState[button]
        if enabled then
            if not state then
                local icon = button.icon or button.Icon
                state = {
                    icon = icon,
                    texCoords = icon and { icon:GetTexCoord() },
                    hotkey = SaveFont(button.HotKey),
                    count = SaveFont(button.Count),
                    name = SaveFont(button.Name),
                    cooldownFonts = {},
                }
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
            if state.icon then state.icon:SetTexCoord(.06, .94, .06, .94) end
            if not button.__mbActionGloss then
                local gloss = button:CreateTexture(nil, "ARTWORK", nil, 7)
                gloss:SetPoint("TOPLEFT", 1, -1)
                gloss:SetPoint("TOPRIGHT", -1, -1)
                gloss:SetHeight(math.max(3, (button:GetHeight() or 34) * .42))
                gloss:SetColorTexture(1, 1, 1, 1)
                gloss:SetBlendMode("ADD")
                gloss:SetGradient("VERTICAL",
                    CreateColor(1, 1, 1, 0),
                    CreateColor(.82, .94, 1, .19))
                button.__mbActionGloss = gloss
            end
            if not button.__mbEmptyFill then
                local fill = button:CreateTexture(nil, "BACKGROUND", nil, 2)
                fill:SetPoint("TOPLEFT", 1, -1)
                fill:SetPoint("BOTTOMRIGHT", -1, 1)
                fill:SetColorTexture(.008, .014, .022, .76)
                button.__mbEmptyFill = fill
            end
            local cooldown = button.cooldown or button.Cooldown
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
                border:SetPoint("TOPLEFT", 0, 0)
                border:SetPoint("BOTTOMRIGHT", 0, 0)
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
            MuteSuggestionGlow(self, button, button.SpellHighlightTexture, button.SpellHighlightAnim)
            MuteSuggestionGlow(self, button, button.AssistedCombatRotationFrame)
            button.__mbEmptyAction = IsEmptyActionButton(button)
            button.__mbEmptyFill:SetShown(button.__mbEmptyAction)
            button.__mbActionGloss:SetShown(not button.__mbEmptyAction)
            ApplyActionBorderColor(button)
            if button.HotKey then button.HotKey:SetAlpha(button.__mbEmptyAction and .38 or 1) end
            button.__mbMinimalBorder:Show()
            local parent = button:GetParent()
            if parent and parent ~= UIParent and type(parent.GetWidth) == "function" then
                parents[parent] = (parents[parent] or 0) + 1
            end
        elseif state then
            if state.icon and state.texCoords and #state.texCoords > 0 then state.icon:SetTexCoord(unpack(state.texCoords)) end
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
            if button.__mbEmptyFill then button.__mbEmptyFill:Hide() end
            for region, font in pairs(state.cooldownFonts or {}) do
                if region and font and font[1] then region:SetFont(font[1], font[2], font[3]) end
            end
            if button.HotKey then button.HotKey:SetAlpha(1) end
            button.__mbEmptyAction, button.__mbHovered, button.__mbSpellSuggested = nil, nil, nil
        end
    end


    -- Buttons retain their individual one-pixel borders; never draw a large
    -- rectangle around the whole action bar.
    for _, bucket in pairs(self.unifiedPanels or {}) do
        if bucket.actionbar then bucket.actionbar:Hide() end
    end
    self:LayoutActionCluster(enabled)
end

-- То же самое для строк Details: градиент один и тот же на все полосы.
local DETAILS_FILL_BOTTOM = CreateColor and CreateColor(.36, .36, .36, 1)
local DETAILS_FILL_TOP = CreateColor and CreateColor(1, 1, 1, 1)

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
                local panel = self.unifiedPanels and self.unifiedPanels[base] and self.unifiedPanels[base].details
                if panel then panel:Hide() end
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
                local panel = self.unifiedPanels and self.unifiedPanels[base] and self.unifiedPanels[base].details
                if panel then panel:Hide() end
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
    local hideBags = MythicBoostDB and MythicBoostDB.convenience
        and MythicBoostDB.convenience.hideBags ~= false
    if not enabled then
        RestoreVisibility(self)
        self:HideUnifiedPanels()
    end
    self:StyleMinimap(enabled)
    self:StyleMicroMenu(enabled)
    self:StyleObjectiveTracker(enabled)
    self:StyleActionButtons(enabled)
    self:StyleCooldownEffectBars(enabled)
    self:StyleDetails(enabled)
    self:StylePlayerAuras(enabled)
    self:StyleBags(hideBags)
    if JP.MinimalChat then JP.MinimalChat:Apply() end

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
        self.maintenanceTicker = C_Timer.NewTicker(2.5, function()
            if not MythicBoostDB or not MythicBoostDB.minimalUI then return end
            -- Пока открыт режим редактирования, Blizzard должен свободно
            -- показывать и двигать свои макеты без борьбы с нашим тикером.
            if _G.EditModeManagerFrame and _G.EditModeManagerFrame:IsShown() then return end
            self:StyleMinimap(true)
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
            JP:Log("MinimalUI: событие %s недоступно в этом клиенте", event)
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
    self.events:SetScript("OnEvent", QueueApply)
    QueueApply()
end

function MinimalUI:Enable() self:Create(); self:Apply() end
function MinimalUI:Disable() self:SetEnabled(false) end
function MinimalUI:Destroy() self:SetEnabled(false) end

JP.MinimalUI = MinimalUI
JP:RegisterModule("MinimalUI", MinimalUI)
