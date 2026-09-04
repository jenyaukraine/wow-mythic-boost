local _, JP = ...
local L = JP.L
local UI, C = JP.UI, JP.UI.colors
local UnitFrames = { displays = {}, parked = {}, pending = {} }

local SIZE = {
    panelWidth = 168, panelHeight = 58, portraitW = 58, portraitH = 58, ring = 1,
    gap = -1, headerH = 22, statsH = 36, healthH = 15, powerH = 15,
    aura = 22, auraGap = 2, maxDebuffs = 8, maxBuffs = 8, maxPlayerBuffs = 16,
}
SIZE.width = 225
SIZE.height = 58

local DEFAULT_POSITION = {
    player = { "BOTTOM", -269, 2 },
    target = { "BOTTOM", 269, 2 },
}
local DEFAULT_BADGE_POSITION = {
    player = { class = { 64.89, 45.62 }, level = { 11.90, 11.85 } },
    target = { class = { 160.11, 45.62 }, level = { 213.10, 11.85 } },
}
-- BuffFrame and DebuffFrame are independent Edit Mode systems. They are not
-- children of the player capsule and must remain owned by Blizzard even when
-- our replacement unit frames are enabled.
local BLIZZARD_FRAMES = { "PlayerFrame", "TargetFrame" }
local XPERL_BACK = "Interface\\AddOns\\MythicBoost\\Media\\XPerl_FrameBack"
local XPERL_THIN = "Interface\\AddOns\\MythicBoost\\Media\\XPerl_ThinEdge"
-- The bundled Perl v2 texture has a cloudy/noisy fill. The original 2.4.3
-- client status texture is cleaner while retaining the classic vertical 3D
-- lighting, and is also Z-Perl's own fallback texture.
local XPERL_BAR = "Interface\\Buttons\\WHITE8X8"

-- A single quiet shell replaces the three heavy Blizzard/X-Perl boxes. The
-- one-pixel edge keeps the silhouette crisp; the restrained gradient gives it
-- depth without the plastic shine that made the previous build look bulky.
local function ModernBackdrop(frame, alpha)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    -- Цвета берём из общих токенов UI.colors, а не объявляем свои: рядом на
    -- экране живут панели MinimalUI, окно добычи и тултип, и пять чуть разных
    -- тёмных серых читаются как пять разных аддонов.
    frame:SetBackdropColor(C.surface[1], C.surface[2], C.surface[3], alpha or C.surface[4])
    frame:SetBackdropBorderColor(UI.Unpack(C.surfaceEdge))
    if not frame.__mbModernDepth then
        -- Объём делается НЕЙТРАЛЬНО. Раньше тут лежали оранжево-бирюзовые
        -- градиенты, один поверх в режиме ADD: это давало пластиковый блеск и
        -- тащило в кадр второй акцентный цвет. Но и голая заливка не годится —
        -- панель без объёма читается наклейкой. Три слоя, у каждого своя роль:
        --
        --   1) подъём: верх панели светлее низа. Базовый признак объёма, без
        --      него остальное не спасает;
        --   2) блик в один пиксель по верхней кромке — именно он читается как
        --      фаска, а не как нарисованный прямоугольник;
        --   3) тень в один пиксель по нижней кромке: панель отрывается от
        --      игрового фона, не требуя внешнего ореола.
        local lift = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
        lift:SetPoint("TOPLEFT", 1, -1)
        lift:SetPoint("BOTTOMRIGHT", -1, 1)
        lift:SetColorTexture(1, 1, 1, 1)
        lift:SetGradient("VERTICAL",
            CreateColor(0, 0, 0, .38),
            CreateColor(.36, .43, .52, .17))
        frame.__mbModernDepth = lift

        local sheen = frame:CreateTexture(nil, "BORDER", nil, 1)
        sheen:SetPoint("TOPLEFT", 1, -1)
        sheen:SetPoint("TOPRIGHT", -1, -1)
        sheen:SetHeight(1)
        sheen:SetColorTexture(.98, .76, .22, .82)
        frame.__mbModernSheen = sheen

        local hollow = frame:CreateTexture(nil, "BORDER", nil, 1)
        hollow:SetPoint("BOTTOMLEFT", 1, 1)
        hollow:SetPoint("BOTTOMRIGHT", -1, 1)
        hollow:SetHeight(1)
        hollow:SetColorTexture(.20, .11, .025, .88)
        frame.__mbModernHollow = hollow
    end
end

local function XPerlAuraBackdrop(frame)
    frame:SetBackdrop({
        bgFile = XPERL_BACK,
        edgeFile = XPERL_THIN,
        tile = true,
        tileSize = 16,
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame:SetBackdropColor(.02, .025, .035, .48)
    frame:SetBackdropBorderColor(.46, .50, .55, .92)
    if not frame.__mbGloss then
        local gloss = frame:CreateTexture(nil, "OVERLAY", nil, -1)
        gloss:SetPoint("TOPLEFT", 2, -2)
        gloss:SetPoint("TOPRIGHT", -2, -2)
        gloss:SetHeight(SIZE.aura * .42)
        gloss:SetColorTexture(1, 1, 1, 1)
        gloss:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(.72, .90, 1, .17))
        gloss:SetBlendMode("ADD")
        frame.__mbGloss = gloss
    end
    -- The generic aura helper inherits Blizzard's relatively large number
    -- font.  At 20 px it covered most of the spell art, so keep both labels
    -- compact, outlined and locked into opposite corners.
    local function StyleAuraText(text, size, color)
        if not text or type(text.GetFont) ~= "function" then return end
        local font = text:GetFont()
        if font then text:SetFont(font, size, "OUTLINE") end
        if color then text:SetTextColor(color[1], color[2], color[3], 1) end
        text:SetShadowOffset(0, 0)
    end
    StyleAuraText(frame.timer, 11, { .94, .97, 1 })
    StyleAuraText(frame.count, 11, { 1, 1, 1 })
    if frame.timer then
        frame.timer:ClearAllPoints()
        frame.timer:SetPoint("CENTER", 0, 0)
    end
    if frame.count then
        frame.count:ClearAllPoints()
        frame.count:SetPoint("BOTTOMRIGHT", -2, 2)
    end
end

local function BadgeBackdrop(frame)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(C.surface[1], C.surface[2], C.surface[3], .92)
    frame:SetBackdropBorderColor(.30, .34, .38, .96)
end

-- Прямая копия геометрии XPerlStatusBar. Универсальный UI.StatusBar добавлял
-- лишнюю плоскую рамку и съедал по пикселю с каждой стороны, из-за чего полосы
-- выглядели толще и современнее оригинала.
local function MatteBarColor(bar, r, g, b)
    bar:SetStatusBarColor(1, 1, 1, 1)
    local texture = bar:GetStatusBarTexture()
    if texture then
        -- Размах шире прежнего .44→1: на полосе высотой 15 px слабый перепад
        -- неразличим, и она читается плоской заливкой. Верх при этом НЕ
        -- доводим до чистого цвета, а слегка уводим к белому — открытый
        -- зелёный и синий рядом с нейтральной панелью выглядят дёшево.
        texture:SetGradient("VERTICAL",
            CreateColor(r * .26, g * .26, b * .26, 1),
            CreateColor(r * .88 + .10, g * .88 + .10, b * .88 + .10, 1))
    end
    -- Блик здесь НЕ рисуем. Он живёт в XPerlStatusBar вместе с остальными
    -- тремя слоями стекла: два независимых блика на одной полосе давали
    -- двойную светлую полоску поперёк и выдавали подделку.
end

local function XPerlStatusBar(parent, color)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetSize(124, SIZE.healthH)
    bar:SetStatusBarTexture(XPERL_BAR)
    MatteBarColor(bar, UI.Unpack(color))
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)

    local background = bar:CreateTexture(nil, "BORDER")
    background:SetAllPoints()
    background:SetColorTexture(.012, .016, .022, .95)

    -- Стекло собирается из четырёх слоёв. Ни один из них не «украшение»: так
    -- глаз читает выпуклую поверхность, и убери любой — вернётся плоская
    -- заливка. Порядок снизу вверх.
    --
    -- 1. Ложе. Тень идёт сверху вниз, а не наоборот: свет в интерфейсе падает
    --    сверху, значит верх утоплённого жёлоба должен быть темнее.
    local depth = bar:CreateTexture(nil, "ARTWORK", nil, 1)
    depth:SetAllPoints()
    depth:SetColorTexture(0, 0, 0, 1)
    depth:SetGradient("VERTICAL",
        CreateColor(0, 0, 0, .04),
        CreateColor(0, 0, 0, .42))
    bar.depth = depth

    -- 2. Блик по верхней половине — главный признак стекла.
    local shine = bar:CreateTexture(nil, "OVERLAY", nil, -5)
    shine:SetPoint("TOPLEFT")
    shine:SetPoint("TOPRIGHT")
    shine:SetHeight(math.max(3, math.floor(SIZE.healthH * .48)))
    shine:SetColorTexture(1, 1, 1, 1)
    shine:SetGradient("VERTICAL",
        CreateColor(1, 1, 1, .02),
        CreateColor(1, 1, 1, .26))
    bar.shine = shine

    -- 3. Отражение снизу. У настоящего стекла бликов два: верхний от источника
    --    света и нижний, отражённый от подложки. Без него полоса выглядит
    --    наклейкой с градиентом, а не объёмом.
    local reflect = bar:CreateTexture(nil, "OVERLAY", nil, -4)
    reflect:SetPoint("BOTTOMLEFT")
    reflect:SetPoint("BOTTOMRIGHT")
    reflect:SetHeight(math.max(2, math.floor(SIZE.healthH * .22)))
    reflect:SetColorTexture(1, 1, 1, 1)
    reflect:SetGradient("VERTICAL",
        CreateColor(1, 1, 1, .10),
        CreateColor(1, 1, 1, 0))
    bar.reflect = reflect

    -- 4. Кант в один пиксель: светлый сверху, тёмный снизу. Именно он даёт
    --    ощущение толщины стекла, а не нарисованного прямоугольника.
    local rimTop = bar:CreateTexture(nil, "OVERLAY", nil, -3)
    rimTop:SetPoint("TOPLEFT"); rimTop:SetPoint("TOPRIGHT"); rimTop:SetHeight(1)
    rimTop:SetColorTexture(1, 1, 1, .30)
    local rimBottom = bar:CreateTexture(nil, "OVERLAY", nil, -3)
    rimBottom:SetPoint("BOTTOMLEFT"); rimBottom:SetPoint("BOTTOMRIGHT"); rimBottom:SetHeight(1)
    rimBottom:SetColorTexture(0, 0, 0, .62)

    -- Скруглённые торцы. Настоящая «пилюля» требует маски-капсулы отдельным
    -- файлом текстуры, которого в Media нет. Мягкая маска краёв — ближайшее,
    -- что даёт штатный клиент. Существование файла проверяем по GetTexture:
    -- несуществующий путь не даёт ошибки, он молча оставляет маску пустой, и
    -- тогда её лучше не применять вовсе, чем получить невидимую полосу.
    local fill = bar:GetStatusBarTexture()
    if fill and type(bar.CreateMaskTexture) == "function" then
        local mask = bar:CreateMaskTexture()
        mask:SetTexture("Interface\\Masks\\SoftEdgeSquare",
            "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        if mask:GetTexture() then
            mask:SetAllPoints(bar)
            fill:AddMaskTexture(mask)
            background:AddMaskTexture(mask)
            bar.pillMask = mask
        else
            mask:Hide()
        end
    end

    bar.holder = bar -- совместимость с обновлением/скрытием полосы
    return bar
end

local function Settings()
    local db = JP.db or MythicBoostDB
    if type(db) ~= "table" then return {} end
    db.unitFrames = type(db.unitFrames) == "table" and db.unitFrames or {}
    local settings = db.unitFrames
    local defaults = {
        unlocked = false, scale = 1.5, opacity = 1,
        showHealthText = true, showPowerText = true,
        animatedPortrait = true, showBadges = true, badgesUnlocked = false, badgeShape = 1,
        alwaysShowTarget = true,
        showPlayerAuras = true, showTargetAuras = true,
        aurasAbove = true,
        showResourcePips = true, showEmptyResources = false,
        resourceHeight = 10, resourceGap = 2, resourceOpacity = 1,
    }
    for key, value in pairs(defaults) do
        if settings[key] == nil then settings[key] = value end
    end
    local function Clamp(key, minimum, maximum)
        local value = settings[key]
        if not UI.UsableNumber(value) then value = defaults[key] end
        value = math.max(minimum, math.min(maximum, value))
        settings[key] = value
    end
    Clamp("scale", .75, 2.00)
    Clamp("badgeShape", 1, 4)
    Clamp("opacity", .55, 1)
    Clamp("resourceHeight", 6, 16)
    Clamp("resourceGap", 0, 6)
    Clamp("resourceOpacity", .30, 1)
    -- Revision 6 adopts the approved bottom-centre layout. Only absent positions and
    -- the exact previous defaults are migrated; manually placed frames stay
    -- where the player left them.
    if db.unitFrames.positionRevision ~= 6 then
        local player = db.unitFrames.player
        local target = db.unitFrames.target
        local oldPlayer = type(player) == "table"
            and ((player.point == "TOPLEFT" and player.x == 28 and player.y == -28)
                or (player.point == "BOTTOM" and player.x == -410 and player.y == 220))
        local oldTarget = type(target) == "table"
            and ((target.point == "TOPRIGHT" and target.x == -360 and target.y == -28)
                or (target.point == "BOTTOM" and target.x == 410 and target.y == 220))
        if type(player) ~= "table" or oldPlayer then
            db.unitFrames.player = { point = "BOTTOM", x = -269, y = 2 }
        end
        if type(target) ~= "table" or oldTarget then
            db.unitFrames.target = { point = "BOTTOM", x = 269, y = 2 }
        end
        db.unitFrames.positionRevision = 6
    end
    return settings
end

local APPEARANCE_KEYS = {
    "scale", "opacity", "showHealthText", "showPowerText", "animatedPortrait", "showBadges",
    "badgesUnlocked", "badgeShape",
    "alwaysShowTarget",
    "showPlayerAuras", "showTargetAuras", "showResourcePips", "showEmptyResources",
    "aurasAbove", "resourceHeight", "resourceGap", "resourceOpacity",
}

-- Database values change as soon as a settings control is clicked. During
-- combat, however, the secure unit-button tree must continue using the last
-- fully applied configuration until PLAYER_REGEN_ENABLED runs the queued job.
local function ActiveSettings()
    return UnitFrames.appliedSettings or Settings()
end

local function IsUnlocked()
    if UnitFrames.appliedUnlocked ~= nil then return UnitFrames.appliedUnlocked end
    return Settings().unlocked == true
end

function UnitFrames:AfterCombat(key, action)
    if not InCombatLockdown() then action(self); return true end
    self.pending[key] = action
    return false
end

local function SafeRange(current, maximum)
    if not UI.UsableNumber(current) or not UI.UsableNumber(maximum) or maximum <= 0 then return end
    return current, maximum
end

local function IsBoolean(value, expected)
    return type(value) == "boolean" and not issecretvalue(value) and value == expected
end

local function IsPlainNumber(value)
    return type(value) == "number" and not issecretvalue(value)
end

local function UnitBarColor(unit)
    local dead, connected = UnitIsDeadOrGhost(unit), UnitIsConnected(unit)
    if IsBoolean(dead, true) or IsBoolean(connected, false) then return .30, .32, .36 end
    -- На своём фрейме здоровье всегда зелёное: цвет класса остаётся в
    -- имени/портрете и не превращает полосу друида в оранжевую.
    if unit == "player" then return .05, .78, .08 end
    local isPlayer = UnitIsPlayer(unit)
    if IsBoolean(isPlayer, true) then
        local _, class = UnitClass(unit)
        if type(class) == "string" and not issecretvalue(class) then return UI.ClassColor(class) end
    end
    local reaction = UnitReaction(unit, "player")
    local color = UI.UsableNumber(reaction) and FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
    if color then return color.r, color.g, color.b end
    return C.green[1], C.green[2], C.green[3]
end

local function UpdateHealth(display)
    if IsBoolean(UnitExists(display.unit), false) then return end
    local current, maximum = UnitHealth(display.unit), UnitHealthMax(display.unit)

    -- Midnight помечает здоровье как secret number. Его нельзя делить или
    -- сравнивать в Lua, но Blizzard разрешает передавать значение прямо в
    -- StatusBar и собственные форматтеры.
    local percent, hasPercent
    if type(UnitHealthPercent) == "function" and CurveConstants and CurveConstants.ScaleTo100 then
        local ok, value = pcall(UnitHealthPercent, display.unit, true, CurveConstants.ScaleTo100)
        if ok and type(value) == "number" then percent, hasPercent = value, true end
    end
    if hasPercent then
        display.health:SetMinMaxValues(0, 100)
        display.health:SetValue(percent)
    else
        local usableCurrent, usableMaximum = SafeRange(current, maximum)
        if usableCurrent then
            display.health:SetMinMaxValues(0, usableMaximum)
            display.health:SetValue(usableCurrent)
        else
            display.health:SetMinMaxValues(0, maximum)
            display.health:SetValue(current)
        end
    end
    local currentOK, currentText = pcall(AbbreviateNumbers, current)
    local maximumOK, maximumText = pcall(AbbreviateNumbers, maximum)
    if currentOK and maximumOK then display.healthValue:SetFormattedText("%s/%s", currentText, maximumText)
    else display.healthValue:SetText("") end
    MatteBarColor(display.health, UnitBarColor(display.unit))
end

local function LayoutStats(display, hasPower)
    if not display.statsPanel or not display.health or not display.power then return end
    display.statsPanel:SetHeight(SIZE.statsH)

    display.health:ClearAllPoints()
    if hasPower then
        display.health:SetHeight(SIZE.healthH)
        if display.health.shine then display.health.shine:SetHeight(math.max(3, math.floor(SIZE.healthH * .48))) end
        if display.health.reflect then display.health.reflect:SetHeight(math.max(2, math.floor(SIZE.healthH * .22))) end
        display.health:SetPoint("TOPLEFT", display.statsPanel, "TOPLEFT", 1, -2)
        display.health:SetPoint("TOPRIGHT", display.statsPanel, "TOPRIGHT", -1, -2)
    else
        local fullHeight = SIZE.statsH - 2
        display.health:SetHeight(fullHeight)
        if display.health.shine then display.health.shine:SetHeight(math.max(3, math.floor(fullHeight * .48))) end
        if display.health.reflect then display.health.reflect:SetHeight(math.max(2, math.floor(fullHeight * .22))) end
        display.health:SetPoint("LEFT", display.statsPanel, "LEFT", 1, 0)
        display.health:SetPoint("RIGHT", display.statsPanel, "RIGHT", -1, 0)
    end

    display.power:ClearAllPoints()
    display.power:SetPoint("TOPLEFT", display.health, "BOTTOMLEFT", 0, -2)
    display.power:SetPoint("TOPRIGHT", display.health, "BOTTOMRIGHT", 0, -2)
end

local function UpdatePower(display)
    if IsBoolean(UnitExists(display.unit), false) then return end
    local powerType = UnitPowerType(display.unit)
    local current, maximum = UnitPower(display.unit, powerType), UnitPowerMax(display.unit, powerType)
    local targetIsPlayer = IsBoolean(UnitIsPlayer(display.unit), true)
    if (UI.UsableNumber(maximum) and maximum <= 0)
        or (display.unit ~= "player" and not targetIsPlayer and not UI.UsableNumber(maximum)) then
        display.power.holder:Hide()
        if display.unit ~= "player" and display.statsPanel then
            LayoutStats(display, false)
        end
        return
    end
    display.power.holder:Show()
    LayoutStats(display, true)
    display.power:SetMinMaxValues(0, maximum)
    display.power:SetValue(current)
    local currentOK, currentText = pcall(AbbreviateNumbers, current)
    local maximumOK, maximumText = pcall(AbbreviateNumbers, maximum)
    if currentOK and maximumOK then display.powerValue:SetFormattedText("%s/%s", currentText, maximumText)
    else display.powerValue:SetText("") end
    local _, token = UnitPowerType(display.unit)
    local usableToken = type(token) == "string" and not issecretvalue(token)
    local color = usableToken and PowerBarColor and PowerBarColor[token]
    if color and color.r then MatteBarColor(display.power, color.r, color.g, color.b)
    else MatteBarColor(display.power, UI.Unpack(C.accentDim)) end
end

---------------------------------------------------------------------------
-- Discrete class resources. Energy/mana/rage still belong in the status
-- bar; things the player spends one at a time are much easier to read as a
-- short row of pips. The row is deliberately separate from auras so neither
-- system can push or overlap the other.
---------------------------------------------------------------------------

local POWER = Enum and Enum.PowerType or {}
local SPEC_RESOURCE = {
    -- Rogue / feral druid.
    [259] = POWER.ComboPoints, [260] = POWER.ComboPoints, [261] = POWER.ComboPoints,
    [103] = POWER.ComboPoints, [1447] = POWER.ComboPoints, [1453] = POWER.ComboPoints,
    -- Death knight.
    [250] = POWER.Runes, [251] = POWER.Runes, [252] = POWER.Runes,
    -- Warlock.
    [265] = POWER.SoulShards, [266] = POWER.SoulShards,
    [267] = POWER.SoulShards, [1454] = POWER.SoulShards,
    -- Paladin, monk, arcane mage and evoker.
    [65] = POWER.HolyPower, [66] = POWER.HolyPower, [70] = POWER.HolyPower,
    [1451] = POWER.HolyPower, [269] = POWER.Chi, [62] = POWER.ArcaneCharges,
    [1465] = POWER.Essence, [1467] = POWER.Essence,
    [1468] = POWER.Essence, [1473] = POWER.Essence,
}

local RESOURCE_COLORS = {
    [POWER.ComboPoints or -1] = { 1.00, .33, .13 },
    [POWER.Runes or -2] = { .22, .72, 1.00 },
    [POWER.SoulShards or -3] = { .69, .23, 1.00 },
    [POWER.HolyPower or -4] = { 1.00, .77, .08 },
    [POWER.Chi or -5] = { .18, .93, .60 },
    [POWER.ArcaneCharges or -6] = { .20, .72, 1.00 },
    [POWER.Essence or -7] = { .13, .88, 1.00 },
}

local function PlayerResourceType()
    local specIndex = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization
        and C_SpecializationInfo.GetSpecialization()
    local specID = specIndex and C_SpecializationInfo.GetSpecializationInfo
        and C_SpecializationInfo.GetSpecializationInfo(specIndex)
    local kind = specID and SPEC_RESOURCE[specID]
    if kind then return kind end

    -- Forms can change a druid's usable resource without changing spec. This
    -- also gives new specializations a safe fallback when Blizzard adds one.
    local _, class = UnitClass("player")
    local fallback = {
        ROGUE = POWER.ComboPoints, DEATHKNIGHT = POWER.Runes,
        WARLOCK = POWER.SoulShards, PALADIN = POWER.HolyPower,
        EVOKER = POWER.Essence,
    }
    kind = fallback[class]
    if kind then return kind end
    if class == "DRUID" and POWER.ComboPoints then
        local maximum = UnitPowerMax("player", POWER.ComboPoints)
        if IsPlainNumber(maximum) and maximum > 0 then return POWER.ComboPoints end
    end
end

local function SetPipTexture(texture, r, g, b, alpha)
    texture:SetColorTexture(1, 1, 1, 1)
    texture:SetGradient("VERTICAL",
        CreateColor(r * .34, g * .34, b * .34, alpha),
        CreateColor(r, g, b, alpha))
end

local function BuildResourcePips(display)
    local row = CreateFrame("Frame", nil, display.holder)
    row:SetSize(SIZE.panelWidth, 10)
    -- Resource points form one segmented rail across the entire name plate.
    -- Its segment count changes by class while the outer start/end stay fixed.
    row:SetPoint("BOTTOMLEFT", display.panel, "TOPLEFT", 0, -1)
    row:SetFrameLevel(display.panel:GetFrameLevel() + 7)
    row.pips = {}
    for index = 1, 8 do
        local pip = CreateFrame("Frame", nil, row)
        pip:SetSize(14, 10)

        local ring = pip:CreateTexture(nil, "ARTWORK")
        ring:SetAllPoints()
        ring:SetColorTexture(.12, .47, .63, 1)

        local fill = pip:CreateTexture(nil, "OVERLAY")
        fill:SetPoint("TOPLEFT", 1, -1)
        fill:SetPoint("BOTTOMRIGHT", -1, 1)

        local shine = pip:CreateTexture(nil, "OVERLAY", nil, 1)
        shine:SetPoint("TOPLEFT", 2, -2)
        shine:SetPoint("TOPRIGHT", -2, -2)
        shine:SetHeight(2)
        shine:SetColorTexture(1, 1, 1, .50)

        pip.ring, pip.fill, pip.shine = ring, fill, shine
        pip:Hide()
        row.pips[index] = pip
    end
    row:Hide()
    display.resourceRow = row
end

local function UpdateResourcePips(display)
    local row = display and display.resourceRow
    if not row then return end
    local settings = ActiveSettings()
    if settings.showResourcePips == false then
        row:Hide()
        for _, pip in ipairs(row.pips) do pip:Hide() end
        return
    end
    local kind = PlayerResourceType()
    if not kind then row:Hide(); return end

    local maximum, current, ready = 0, 0, {}
    if kind == POWER.Runes then
        maximum = 6
        for index = 1, maximum do
            local ok, _, _, available = pcall(GetRuneCooldown, index)
            -- pcall прикрывает только сам вызов: сравнение защищённого boolean
            -- за его пределами упало бы точно так же, как UnitInRange.
            ready[index] = ok and IsBoolean(available, true)
            if ready[index] then current = current + 1 end
        end
    else
        current, maximum = UnitPower("player", kind), UnitPowerMax("player", kind)
        if not IsPlainNumber(current) or not IsPlainNumber(maximum) then row:Hide(); return end
        local displayMod = type(UnitPowerDisplayMod) == "function" and UnitPowerDisplayMod(kind) or 1
        if not IsPlainNumber(displayMod) or displayMod < 1 then displayMod = 1 end
        current, maximum = current / displayMod, maximum / displayMod
    end
    maximum = IsPlainNumber(maximum) and math.min(8, math.max(0, math.floor(maximum + .01))) or 0
    current = IsPlainNumber(current) and math.max(0, current) or 0
    if maximum == 0 then row:Hide(); return end

    local color = RESOURCE_COLORS[kind] or { .18, .76, 1 }
    local charged = type(GetUnitChargedPowerPoints) == "function" and GetUnitChargedPowerPoints("player")
    local chargedSet = {}
    if type(charged) == "table" then
        for _, index in ipairs(charged) do chargedSet[index] = true end
    end
    local gap = settings.resourceGap
    local height = settings.resourceHeight
    local showEmpty = settings.showEmptyResources ~= false
    row:SetHeight(height)
    row:SetAlpha(settings.resourceOpacity)
    local size = (SIZE.panelWidth - (maximum - 1) * gap) / maximum
    local anyVisible = false
    for index, pip in ipairs(row.pips) do
        if index <= maximum then
            pip:ClearAllPoints()
            pip:SetSize(size, height)
            pip:SetPoint("LEFT", row, "LEFT", (index - 1) * (size + gap), 0)
            local active = kind == POWER.Runes and ready[index] or index <= current
            local r, g, b = color[1], color[2], color[3]
            if chargedSet[index] then r, g, b = .18, .92, 1 end
            if active then
                pip.ring:SetColorTexture(r * .72, g * .72, b * .72, 1)
                SetPipTexture(pip.fill, r, g, b, 1)
                pip.shine:SetAlpha(.62)
            else
                pip.ring:SetColorTexture(.13, .24, .30, .92)
                SetPipTexture(pip.fill, .055, .075, .09, .96)
                pip.shine:SetAlpha(.08)
            end
            pip:SetShown(active or showEmpty)
            anyVisible = anyVisible or active or showEmpty
        else pip:Hide() end
    end
    row:SetShown(anyVisible)
end

local function ReadUnitName(unit, fallback)
    -- У encounter-юнитов один API иногда возвращает secret value, хотя
    -- другой всё ещё отдаёт обычную строку. Не оставляем пустую шапку цели.
    for _, getter in ipairs({ UnitName, GetUnitName, UnitNameUnmodified }) do
        if type(getter) == "function" then
            local ok, name = pcall(getter, unit)
            if ok and type(name) == "string" and not issecretvalue(name) and name ~= "" then
                return name
            end
        end
    end
    return fallback or ""
end

local function ReadUnitCast(unit)
    for _, source in ipairs({
        { getter = UnitChannelInfo, channel = true },
        { getter = UnitCastingInfo, channel = false },
    }) do
        if type(source.getter) == "function" then
            local result = { pcall(source.getter, unit) }
            local name, displayName, icon, startMS, endMS = result[2], result[3], result[4], result[5], result[6]
            if result[1] and type(name) == "string" and not issecretvalue(name)
                and name ~= "" and IsPlainNumber(startMS) and IsPlainNumber(endMS)
                and endMS > startMS then
                if type(displayName) ~= "string" or issecretvalue(displayName) or displayName == "" then
                    displayName = name
                end
                return displayName, startMS / 1000, endMS / 1000, source.channel, icon
            end
        end
    end
end

local SUCCESSFUL_CAST_STOP = {
    UNIT_SPELLCAST_STOP = true,
    UNIT_SPELLCAST_CHANNEL_STOP = true,
    UNIT_SPELLCAST_EMPOWER_STOP = true,
}

local FAILED_CAST_STOP = {
    UNIT_SPELLCAST_FAILED = true,
    UNIT_SPELLCAST_INTERRUPTED = true,
}

-- The large corner medallion belongs to the class/cast icon itself.  NPCs and
-- other units without a readable class must not leave its decorative rim
-- floating empty beside the portrait.
local function UpdateClassBadgePanelVisibility(display)
    if not display or not display.levelPanel then return end
    local settings = ActiveSettings()
    local badgesEnabled = settings.showBadges ~= false and settings.badgeShape ~= 4
    local hasContents = display.hasClassIcon == true or display.hasCastIcon == true
    display.levelPanel:SetShown(badgesEnabled and hasContents)
end

local function CastLatency(duration)
    if type(GetNetStats) ~= "function" then return 0 end
    local ok, _, _, homeMS, worldMS = pcall(GetNetStats)
    if not ok then return 0 end
    local milliseconds = math.max(IsPlainNumber(homeMS) and homeMS or 0,
        IsPlainNumber(worldMS) and worldMS or 0)
    return math.min(math.max(0, duration or 0) * .35, .45, milliseconds / 1000)
end

local function HideUnitCast(display)
    display.casting = nil
    display.castChanneling = nil
    display.castDuration = nil
    display.castLatency = nil
    display.castCompleteUntil = nil
    display.castBar:Hide()
    display.name:Show()
    display.hasCastIcon = false
    if display.castIcon then display.castIcon:Hide() end
    if display.classIcon then display.classIcon:SetShown(display.hasClassIcon == true) end
    UpdateClassBadgePanelVisibility(display)
end

function UnitFrames:UpdateCast(display, event)
    if not display or not display.castBar then return end
    local now = GetTime()

    if FAILED_CAST_STOP[event] then
        HideUnitCast(display)
        return
    end
    if SUCCESSFUL_CAST_STOP[event] and display.casting and display.castDuration then
        display.castBar:SetValue(display.castChanneling and 0 or display.castDuration)
        display.castCompleteUntil = now + math.max(.06, display.castLatency or 0)
        display.castBar:Show()
        display.name:Hide()
        return
    end
    if display.castCompleteUntil then
        if now < display.castCompleteUntil then return end
        HideUnitCast(display)
        return
    end

    local name, startTime, endTime, channeling, icon = ReadUnitCast(display.unit)
    if not name then
        HideUnitCast(display)
        return
    end

    local duration = endTime - startTime
    local latency = CastLatency(duration)
    local value = channeling and (endTime - now - latency) or (now - startTime + latency)
    value = math.max(0, math.min(duration, value))
    display.casting = true
    display.castChanneling = channeling and true or nil
    display.castDuration = duration
    display.castLatency = latency
    display.name:Hide()
    display.castName:SetText(name)
    local texture = display.castBar:GetStatusBarTexture()
    if texture then
        if channeling then
            texture:SetGradient("VERTICAL", CreateColor(.09, .07, .34, .98), CreateColor(.44, .36, 1, .96))
        else
            texture:SetGradient("VERTICAL", CreateColor(.34, .11, .01, .98), CreateColor(1, .49, 0, .96))
        end
    end
    display.hasCastIcon = false
    if display.castIcon then display.castIcon:Hide() end
    local iconType = type(icon)
    if display.castIcon and (iconType == "number" or iconType == "string") and not issecretvalue(icon) then
        display.castIcon:SetTexture(icon)
        display.castIcon:Show()
        display.hasCastIcon = true
        display.classIcon:Hide()
    end
    UpdateClassBadgePanelVisibility(display)
    display.castBar:SetMinMaxValues(0, duration)
    display.castBar:SetValue(value)
    display.castBar:Show()
end

local function UpdateIdentity(display)
    local name = ReadUnitName(display.unit, display.cachedName)
    if name ~= "" then display.cachedName = name end
    display.name:SetText(name)
    local level = UnitLevel(display.unit)
    display.level:SetText(UI.UsableNumber(level) and tostring(level) or "")
    local _, class = UnitClass(display.unit)
    if display.classIcon then
        display.hasClassIcon = type(class) == "string" and not issecretvalue(class)
            and UI.SetClassIconTexture(display.classIcon, class) or false
        display.classIcon:SetShown(display.hasClassIcon and not display.casting)
        UpdateClassBadgePanelVisibility(display)
    end
    if display.group then
        local groupText = ""
        local raidIndex = UnitInRaid(display.unit)
        if UI.UsableNumber(raidIndex) then
            local _, _, subgroup = GetRaidRosterInfo(raidIndex)
            if UI.UsableNumber(subgroup) then groupText = "G" .. subgroup end
        elseif display.unit == "player" and IsInGroup and IsBoolean(IsInGroup(), true) then groupText = "G1" end
        display.group:SetText(groupText)
    end
    display.portrait:SetUnit(display.unit)
end

local function UpdateState(display)
    local alpha = .94
    local exists = UnitExists(display.unit)
    local dead, connected = UnitIsDeadOrGhost(display.unit), UnitIsConnected(display.unit)
    if IsBoolean(exists, false) or IsBoolean(dead, true) or IsBoolean(connected, false) then
        alpha = .55
    else
        local inRange, checked = UnitInRange(display.unit)
        -- Midnight может вернуть secret boolean даже для checked. Любое
        -- прямое `if checked` в tainted addon падает, поэтому сначала снимаем метку.
        if IsBoolean(checked, true) and IsBoolean(inRange, false) then alpha = .62 end
    end
    if display.hovered and alpha > .62 then alpha = 1 end
    display.portrait:SetStateAlpha(alpha)
    if display.highlight then display.highlight:SetShown(display.hovered and true or false) end
    for _, frame in ipairs(display.xperlPanels or {}) do
        frame:SetBackdropBorderColor(.25, .29, .34, .96)
    end
end

---------------------------------------------------------------------------
-- Auras. The player owns a fixed-width X-Perl-style container instead of
-- borrowing Blizzard's wide BuffFrame, so icons never escape the unit frame.
---------------------------------------------------------------------------

local DISPEL_RULES = { DRUID = { Curse = true, Poison = true, Magic = 4 } }

function UnitFrames:RefreshDispelSet()
    local set, _, class = {}, UnitClass("player")
    local rules = class and DISPEL_RULES[class]
    local getter = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
    local ok, spec = type(getter) == "function" and pcall(getter)
    spec = ok and spec or nil
    for dispelName, requirement in pairs(rules or {}) do
        if requirement == true or requirement == spec then set[dispelName] = true end
    end
    self.dispelSet = set
end

local function TimeText(remaining)
    if remaining >= 3600 then return (L("%dч")):format(math.floor(remaining / 3600)) end
    if remaining >= 60 then return (L("%dм")):format(math.floor(remaining / 60)) end
    -- Только целые секунды. Дробь вида «6.2» на иконке в 22 пикселя нечитаема
    -- и вдобавок меняется каждый кадр: глаз цепляется за мельтешение вместо
    -- того, чтобы считывать порядок величины. Округляем ВВЕРХ — остаток в .4 с
    -- это всё ещё секунда, а «0» на живой ауре выглядел бы ошибкой.
    return tostring(math.max(1, math.ceil(remaining)))
end

local function CanDispel(data)
    return type(data.dispelName) == "string" and not issecretvalue(data.dispelName)
        and UnitFrames.dispelSet and UnitFrames.dispelSet[data.dispelName] or false
end

local function SortAuras(a, b)
    local da, db = CanDispel(a), CanDispel(b)
    if da ~= db then return da end
    local bossA, bossB = IsBoolean(a.isBossAura, true), IsBoolean(b.isBossAura, true)
    if bossA ~= bossB then return bossA end
    local ea = UI.UsableNumber(a.expirationTime) and a.expirationTime > 0 and a.expirationTime or math.huge
    local eb = UI.UsableNumber(b.expirationTime) and b.expirationTime > 0 and b.expirationTime or math.huge
    if ea ~= eb then return ea < eb end
    return (a.auraInstanceID or 0) < (b.auraInstanceID or 0)
end

local function AuraTooltip(icon)
    if not icon.display or not icon.auraInstanceID then return end
    -- Anchoring to the individual icon made the tooltip walk across the
    -- resource pips and unit frame as the aura order changed. The outside
    -- edge of the complete unit frame is stable and leaves the HUD readable.
    GameTooltip:SetOwner(icon.display.holder,
        icon.display.mirror and "ANCHOR_LEFT" or "ANCHOR_RIGHT", 8, 0)
    local setter = icon.harmful and GameTooltip.SetUnitDebuffByAuraInstanceID or GameTooltip.SetUnitBuffByAuraInstanceID
    local shown = type(setter) == "function" and pcall(setter, GameTooltip, icon.display.unit, icon.auraInstanceID)
    if not shown and icon.spellId and type(GameTooltip.SetSpellByID) == "function" then
        shown = pcall(GameTooltip.SetSpellByID, GameTooltip, icon.spellId)
    end
    if shown then
        if icon.display.unit == "player" and not icon.harmful then
            GameTooltip:AddLine(L("Правый клик — снять эффект"), C.muted[1], C.muted[2], C.muted[3])
        end
        GameTooltip:Show()
    else GameTooltip:Hide() end
end

local SafeAura = UI.SafeAura

local function CancelPlayerBuff(icon, mouseButton)
    if mouseButton ~= "RightButton" or not icon.display or icon.display.unit ~= "player"
        or icon.harmful or not icon.auraInstanceID or type(CancelUnitBuff) ~= "function" then return end
    -- CancelUnitBuff still accepts an aura index, while the modern aura API
    -- gives our stable button an instance ID. Resolve the current index at the
    -- moment of the hardware click so sorting/removal cannot cancel a neighbor.
    for index = 1, 40 do
        local data, blocked = SafeAura("player", index, "HELPFUL")
        if blocked or not data then break end
        local instanceID = data.auraInstanceID
        if not issecretvalue(instanceID) and instanceID == icon.auraInstanceID then
            pcall(CancelUnitBuff, "player", index)
            GameTooltip:Hide()
            return
        end
    end
end

local function AuraTicker(row, elapsed)
    row.elapsed = (row.elapsed or 0) + elapsed
    if row.elapsed < .1 then return end
    row.elapsed = 0
    local now = GetTime()
    for _, icon in ipairs(row.icons) do
        if icon:IsShown() and icon.expires then
            local remaining = icon.expires - now
            icon.timer:SetText(remaining > 0 and TimeText(remaining) or "")
        end
    end
end

local function BuildAuraRow(display, count, anchor, y, columns)
    columns = columns or count
    local lineCount = math.ceil(count / columns)
    local row = CreateFrame("Frame", nil, display.holder)
    row:SetSize(columns * SIZE.aura + (columns - 1) * SIZE.auraGap,
        lineCount * SIZE.aura + (lineCount - 1) * SIZE.auraGap)
    -- Keep the aura row aligned with the visible edge of the rounded portrait.
    local edgeInset = 0
    row:SetPoint(display.mirror and "TOPRIGHT" or "TOPLEFT", anchor,
        display.mirror and "BOTTOMRIGHT" or "BOTTOMLEFT", edgeInset, y)
    row.icons, row.display, row.columns = {}, display, columns
    for index = 1, count do
        local icon = UI.AuraIcon(row, SIZE.aura)
        XPerlAuraBackdrop(icon)
        local column = (index - 1) % columns
        local line = math.floor((index - 1) / columns)
        local offset = column * (SIZE.aura + SIZE.auraGap)
        -- X-Perl зеркалит не только сам target frame, но и направление его
        -- аур: ближайший/первый эффект находится у правого края портрета.
        icon:SetPoint(display.mirror and "TOPRIGHT" or "TOPLEFT",
            display.mirror and -offset or offset, -line * (SIZE.aura + SIZE.auraGap))
        icon:SetScript("OnEnter", AuraTooltip)
        icon:SetScript("OnLeave", GameTooltip_Hide)
        icon:SetScript("OnClick", CancelPlayerBuff)
        icon:Hide()
        row.icons[index] = icon
    end
    row:SetScript("OnUpdate", AuraTicker)
    row:Hide()
    return row
end

local function ReadAuras(display)
    -- Indexed aura enumeration is restricted in combat on Retail 12.1.
    -- Preserve the last safe snapshot instead of wiping it and making a
    -- forbidden API call. PLAYER_REGEN_ENABLED rebuilds it immediately.
    if type(InCombatLockdown) == "function" and InCombatLockdown() then return false end
    wipe(display.cache)
    if not C_UnitAuras or IsBoolean(UnitExists(display.unit), false) then return end
    for _, filter in ipairs({ "HARMFUL", "HELPFUL" }) do
        for index = 1, 40 do
            local data, blocked = SafeAura(display.unit, index, filter)
            -- Ауры закрыты целиком: ряд останется с тем, что уже прочитано,
            -- вместо сорока подряд падающих вызовов на каждое UNIT_AURA.
            if blocked then return end
            if not data then break end
            local instanceID = data.auraInstanceID
            if instanceID and not issecretvalue(instanceID) then display.cache[instanceID] = data end
        end
    end
end

local function ApplyAuraUpdate(display, updateInfo)
    -- updateInfo and aura-instance lookups are protected in restricted combat.
    -- Never inspect them from addon code; keep the pre-combat snapshot.
    if type(InCombatLockdown) == "function" and InCombatLockdown() then return false end
    if not updateInfo then ReadAuras(display); return true end
    -- isFullUpdate в Midnight приходит ЗАЩИЩЁННЫМ булевым, и прямая проверка
    -- `if updateInfo.isFullUpdate` на нём падает. Читать поле можно, нельзя
    -- только использовать его как условие, поэтому сначала снимаем метку.
    --
    -- IsBoolean здесь не годится: он вернул бы false и для защищённого
    -- значения, то есть увёл бы в инкрементальный разбор ровно тогда, когда
    -- мы не знаем, что произошло. При нечитаемом значении пересобираем ауры
    -- целиком — лишний пересбор дешевле потерянной ауры.
    local full = updateInfo.isFullUpdate
    local readable = type(full) == "boolean" and not issecretvalue(full)
    if not readable or full == true then ReadAuras(display); return true end
    local changed = false
    for _, data in ipairs(updateInfo.addedAuras or {}) do
        if data.auraInstanceID then display.cache[data.auraInstanceID] = data; changed = true end
    end
    for _, id in ipairs(updateInfo.updatedAuraInstanceIDs or {}) do
        display.cache[id] = C_UnitAuras.GetAuraDataByAuraInstanceID(display.unit, id); changed = true
    end
    for _, id in ipairs(updateInfo.removedAuraInstanceIDs or {}) do
        display.cache[id] = nil; changed = true
    end
    return changed
end

local function FillIcon(icon, data, display)
    -- В Midnight часть значений приходит защищёнными, и icon у ауры — одно из
    -- них. SetTexture на таком значении не падает, а молча ставит пустоту:
    -- на экране остаётся тёмный кадр с рамкой, который выглядит как пустой
    -- слот. Показывать ауру без значка бессмысленно — прячем кадр целиком.
    local texture = data.icon
    if issecretvalue(texture) or not texture then
        icon:Hide(); icon.auraInstanceID, icon.expires = nil, nil
        return
    end
    icon.texture:SetTexture(texture)
    icon.auraInstanceID, icon.spellId = data.auraInstanceID, data.spellId
    icon.harmful, icon.display = IsBoolean(data.isHarmful, true), display
    local stacks = data.applications
    icon.count:SetText(UI.UsableNumber(stacks) and stacks > 1 and stacks or "")
    local duration, expires = data.duration, data.expirationTime
    if UI.UsableNumber(duration) and duration > 0 and UI.UsableNumber(expires) and expires > 0 then
        local rate = UI.UsableNumber(data.timeMod) and data.timeMod > 0 and data.timeMod or 1
        icon.cooldown:SetCooldown(expires - duration, duration, rate)
        icon.cooldown:Show(); icon.expires = expires
    else
        icon.cooldown:Clear(); icon.cooldown:Hide(); icon.expires = nil; icon.timer:SetText("")
    end
    if IsBoolean(data.isHarmful, true) then
        local color = DebuffTypeColor and (DebuffTypeColor[data.dispelName or "none"] or DebuffTypeColor.none)
        if color then icon:SetBackdropBorderColor(color.r, color.g, color.b, 1) end
    elseif IsBoolean(data.isFromPlayerOrPlayerPet, true) then icon:SetBackdropBorderColor(.48, .50, .52, 1)
    else icon:SetBackdropBorderColor(.32, .34, .36, 1) end
    icon.dispel:SetShown(IsBoolean(data.isHarmful, true) and CanDispel(data)); icon:Show()
end

local function LayoutRow(row, list, gravityToFrame)
    local visible = math.min(#list, #row.icons)
    local lines = math.max(1, math.ceil(visible / row.columns))
    for index, icon in ipairs(row.icons) do
        local data = list[index]
        if data then
            local column = (index - 1) % row.columns
            local sourceLine = math.floor((index - 1) / row.columns)
            local line = gravityToFrame and (lines - 1 - sourceLine) or sourceLine
            local offset = column * (SIZE.aura + SIZE.auraGap)
            icon:ClearAllPoints()
            icon:SetPoint(row.display.mirror and "TOPRIGHT" or "TOPLEFT",
                row.display.mirror and -offset or offset, -line * (SIZE.aura + SIZE.auraGap))
            FillIcon(icon, data, row.display)
        else icon:Hide(); icon.auraInstanceID, icon.expires = nil, nil end
    end
    -- Скрытый ряд всё равно держит свою высоту, а следующий ряд привязан к его
    -- нижнему краю — из-за этого под фреймом зияла пустая полоса в высоту
    -- иконки. Пустой ряд схлопываем, чтобы всё под ним подтянулось вверх.
    row:SetHeight(#list > 0 and (lines * SIZE.aura + (lines - 1) * SIZE.auraGap) or .001)
    row:SetShown(#list > 0)
end

local function RefreshAuras(display)
    if not display.debuffRow then return end
    local settings = ActiveSettings()
    local enabled = display.unit == "player" and settings.showPlayerAuras ~= false
        or display.unit == "target" and settings.showTargetAuras ~= false
    if not enabled then
        LayoutRow(display.debuffRow, {})
        LayoutRow(display.buffRow, {})
        return
    end
    local debuffs, buffs = {}, {}
    for _, data in pairs(display.cache) do
        if data then
            if IsBoolean(data.isHarmful, true) then debuffs[#debuffs + 1] = data
            elseif IsBoolean(data.isHelpful, true)
                and (not display.ownBuffsOnly or IsBoolean(data.isFromPlayerOrPlayerPet, true)) then
                buffs[#buffs + 1] = data
            end
        end
    end
    table.sort(debuffs, SortAuras); table.sort(buffs, SortAuras)
    local gravityToFrame = settings.aurasAbove == true
    LayoutRow(display.debuffRow, debuffs, gravityToFrame)
    LayoutRow(display.buffRow, buffs, gravityToFrame)

    -- Не резервируем невидимую строку. Раньше у дружелюбной цели сначала
    -- стоял скрытый ряд дебаффов, а бафы из-за него висели на 20+ px ниже.
    local function AnchorRow(row, anchor, y)
        row:ClearAllPoints()
        local edgeInset = 0
        row:SetPoint(display.mirror and "TOPRIGHT" or "TOPLEFT", anchor,
            display.mirror and "BOTTOMRIGHT" or "BOTTOMLEFT", edgeInset, y)
    end
    local function AnchorRowAbove(row, anchor, y)
        row:ClearAllPoints()
        local edgeInset = 0
        row:SetPoint(display.mirror and "BOTTOMRIGHT" or "BOTTOMLEFT", anchor,
            display.mirror and "TOPRIGHT" or "TOPLEFT", edgeInset, y)
    end
    if settings.aurasAbove == true then
        if display.unit == "player" then
            -- Сегменты ресурса уже занимают верхнюю грань. Если они видимы,
            -- начинаем ауры над ними, а не рисуем два слоя друг поверх друга.
            local base = display.resourceRow and display.resourceRow:IsShown()
                and display.resourceRow or display.holder
            AnchorRowAbove(display.buffRow, base, 4)
            AnchorRowAbove(display.debuffRow, #buffs > 0 and display.buffRow or base,
                #buffs > 0 and SIZE.auraGap or 4)
        else
            AnchorRowAbove(display.debuffRow, display.holder, 4)
            AnchorRowAbove(display.buffRow, #debuffs > 0 and display.debuffRow or display.holder,
                #debuffs > 0 and SIZE.auraGap or 4)
        end
    elseif display.unit == "player" then
        -- Resource points now live above the frame, so auras always sit flush
        -- beneath its lower edge regardless of the active class mechanic.
        local firstAnchor = display.holder
        local firstGap = -2
        AnchorRow(display.buffRow, firstAnchor, firstGap)
        AnchorRow(display.debuffRow, #buffs > 0 and display.buffRow or firstAnchor,
            #buffs > 0 and -SIZE.auraGap or firstGap)
    else
        AnchorRow(display.debuffRow, display.holder, -4)
        AnchorRow(display.buffRow, #debuffs > 0 and display.debuffRow or display.holder,
            #debuffs > 0 and -SIZE.auraGap or -4)
    end
end

---------------------------------------------------------------------------
-- Construction and secure click layer
---------------------------------------------------------------------------

local function CreateBadgeLayer(panel, size, layer, sublevel)
    local texture = panel:CreateTexture(nil, layer, nil, sublevel)
    texture:SetSize(size, size)
    texture:SetPoint("CENTER")
    texture:SetColorTexture(1, 1, 1, 1)
    texture:SetSnapToPixelGrid(false)
    texture:SetTexelSnappingBias(0)
    local mask = panel:CreateMaskTexture()
    mask:SetTexture("Interface\\Masks\\CircleMaskScalable",
        "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    if not mask:GetTexture() then
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask",
            "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    end
    mask:SetSize(size, size)
    mask:SetPoint("CENTER")
    texture:AddMaskTexture(mask)
    panel.__mbBadgeLayers = panel.__mbBadgeLayers or {}
    panel.__mbBadgeLayers[#panel.__mbBadgeLayers + 1] = {
        texture = texture, mask = mask, size = size, masked = true,
    }
    return texture
end

local function ApplyBadgeShape(panel, shape)
    shape = math.max(1, math.min(4, tonumber(shape) or 1))
    if not panel or panel.__mbBadgeShape == shape then return end
    panel.__mbBadgeShape = shape
    for _, layer in ipairs(panel.__mbBadgeLayers or {}) do
        local texture, mask = layer.texture, layer.mask
        if layer.masked and type(texture.RemoveMaskTexture) == "function" then
            texture:RemoveMaskTexture(mask); layer.masked = false
        end
        texture:SetRotation(shape == 3 and math.rad(45) or 0)
        local size = shape == 3 and layer.size * .72 or layer.size
        texture:SetSize(size, size)
        mask:SetSize(size, size)
        if shape == 1 then texture:AddMaskTexture(mask); layer.masked = true end
    end
end

local function BadgePanel(display, key)
    return key == "class" and display.levelPanel or display.classPanel
end

function UnitFrames:BuildDisplay(unit, mirror, showAuras, ownBuffsOnly, options)
    options = options or {}
    local display = { unit = unit, mirror = mirror, cache = {}, ownBuffsOnly = ownBuffsOnly }
    local holder = CreateFrame("Frame", nil, options.parent or self.container)
    holder:SetSize(SIZE.width, SIZE.height)
    holder:SetMovable(true)
    holder:SetClampedToScreen(true)
    display.holder = holder

    if not options.preview then
        local saved, default = Settings()[unit], DEFAULT_POSITION[unit]
        if type(saved) == "table" and UI.UsableNumber(saved.x) and UI.UsableNumber(saved.y) then
            holder:SetPoint(saved.point or default[1], UIParent, saved.point or default[1], saved.x, saved.y)
        else holder:SetPoint(default[1], UIParent, default[1], default[2], default[3]) end
    end

    -- The animated 3D head remains the visual anchor, but is now flush with a
    -- compact body instead of sitting between several unrelated bevels.
    display.portrait = UI.Portrait(holder, SIZE.portraitW - SIZE.ring * 2, SIZE.ring)
    display.portrait.ring:SetSize(SIZE.portraitW, SIZE.portraitH)
    display.portrait.ring:SetPoint(mirror and "TOPRIGHT" or "TOPLEFT", holder,
        mirror and "TOPRIGHT" or "TOPLEFT", 0, 0)

    ModernBackdrop(display.portrait.ring, .98)

    local namePanel = UI.Panel(holder)
    ModernBackdrop(namePanel, .95)
    namePanel:SetSize(SIZE.panelWidth, SIZE.headerH)
    namePanel:SetPoint(mirror and "TOPRIGHT" or "TOPLEFT", display.portrait.ring,
        mirror and "TOPLEFT" or "TOPRIGHT", mirror and 1 or SIZE.gap, 0)
    display.panel = namePanel

    display.group = UI.Text(namePanel, "GameFontNormalSmall", "", C.muted)
    display.group:SetPoint(mirror and "LEFT" or "RIGHT", namePanel,
        mirror and "LEFT" or "RIGHT", mirror and 7 or -7, 0)
    display.group:SetWidth(24)
    display.group:SetJustifyH(mirror and "LEFT" or "RIGHT")
    display.name = UI.Text(namePanel, "GameFontNormalSmall", "", C.amber)
    local nameFont, _, nameFlags = display.name:GetFont()
    if nameFont then display.name:SetFont(nameFont, 11, nameFlags or "OUTLINE") end
    display.name:SetPoint("TOPLEFT", 10, 0)
    display.name:SetPoint("BOTTOMRIGHT", -10, 1)
    display.name:SetJustifyH("CENTER")
    display.name:SetWordWrap(false)
    if type(display.name.SetMaxLines) == "function" then display.name:SetMaxLines(1) end

    -- Casting reuses the name plate instead of creating another HUD block.
    -- Its spell artwork temporarily occupies the existing class medallion.
    local castBar = CreateFrame("StatusBar", nil, namePanel)
    castBar:SetPoint("TOPLEFT", namePanel, "TOPLEFT", 1, -1)
    castBar:SetPoint("BOTTOMRIGHT", namePanel, "BOTTOMRIGHT", -1, 1)
    castBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    castBar:SetStatusBarColor(1, 1, 1, 1)
    castBar:SetMinMaxValues(0, 1)
    castBar:SetValue(0)
    castBar:SetFrameLevel(namePanel:GetFrameLevel() + 2)
    local castFill = castBar:GetStatusBarTexture()
    if castFill then
        castFill:SetGradient("VERTICAL",
            CreateColor(.34, .11, .01, .98),
            CreateColor(1, .49, 0, .96))
    end
    local castBed = castBar:CreateTexture(nil, "BACKGROUND")
    castBed:SetAllPoints()
    castBed:SetColorTexture(.006, .012, .018, .76)
    local castShine = castBar:CreateTexture(nil, "OVERLAY", nil, -3)
    castShine:SetPoint("TOPLEFT")
    castShine:SetPoint("TOPRIGHT")
    castShine:SetHeight(math.max(3, math.floor(SIZE.headerH * .48)))
    castShine:SetColorTexture(1, 1, 1, 1)
    castShine:SetBlendMode("ADD")
    castShine:SetGradient("VERTICAL",
        CreateColor(1, 1, 1, .02),
        CreateColor(.72, .94, 1, .24))
    local castReflect = castBar:CreateTexture(nil, "OVERLAY", nil, -2)
    castReflect:SetPoint("BOTTOMLEFT")
    castReflect:SetPoint("BOTTOMRIGHT")
    castReflect:SetHeight(4)
    castReflect:SetColorTexture(.45, .86, 1, .10)
    local castRimTop = castBar:CreateTexture(nil, "OVERLAY", nil, -1)
    castRimTop:SetPoint("TOPLEFT"); castRimTop:SetPoint("TOPRIGHT"); castRimTop:SetHeight(1)
    castRimTop:SetColorTexture(1, 1, 1, .28)
    local castRimBottom = castBar:CreateTexture(nil, "OVERLAY", nil, -1)
    castRimBottom:SetPoint("BOTTOMLEFT"); castRimBottom:SetPoint("BOTTOMRIGHT"); castRimBottom:SetHeight(1)
    castRimBottom:SetColorTexture(0, 0, 0, .66)
    display.castName = UI.Text(castBar, "GameFontNormal", "", C.text)
    display.castName:SetPoint("TOPLEFT", 8, 0)
    display.castName:SetPoint("BOTTOMRIGHT", -8, 1)
    display.castName:SetJustifyH("CENTER")
    display.castName:SetWordWrap(false)
    if type(display.castName.SetMaxLines) == "function" then display.castName:SetMaxLines(1) end
    castBar:SetScript("OnUpdate", function(_, elapsed)
        display.castElapsed = (display.castElapsed or 0) + elapsed
        if display.castElapsed < .02 then return end
        display.castElapsed = 0
        UnitFrames:UpdateCast(display)
    end)
    castBar:Hide()
    display.castBar = castBar

    -- The class/spec badge is the larger companion to the level seal: 28 px
    -- versus 20 px (1.4x), centred over the upper portrait/body junction.
    local levelPanel = CreateFrame("Frame", nil, holder)
    levelPanel:SetSize(28, 28)
    local classDefault = DEFAULT_BADGE_POSITION[unit].class
    levelPanel:SetPoint("CENTER", holder, "BOTTOMLEFT", classDefault[1], classDefault[2])
    display.classBadgeDefault = {
        "CENTER", holder, "BOTTOMLEFT", classDefault[1], classDefault[2],
    }
    levelPanel:SetFrameLevel(display.portrait.ring:GetFrameLevel() + 9)
    CreateBadgeLayer(levelPanel, 28, "BACKGROUND", 0):SetVertexColor(C.edge[1], C.edge[2], C.edge[3], .92)
    CreateBadgeLayer(levelPanel, 24, "BACKGROUND", 2):SetVertexColor(.012, .020, .028, .98)
    local classGloss = CreateBadgeLayer(levelPanel, 22, "ARTWORK", 1)
    classGloss:SetBlendMode("ADD")
    classGloss:SetGradient("VERTICAL",
        CreateColor(1, 1, 1, 0),
        CreateColor(.68, .91, 1, .16))
    -- The class art is a real texture layer, not inline font markup, so the
    -- same medallion mask can trim it exactly like the temporary spell icon.
    display.classIcon = CreateBadgeLayer(levelPanel, 22, "OVERLAY", 6)
    display.classIcon:Hide()
    -- Register the spell texture as a badge layer too. This gives it exactly
    -- the same circular mask as the medallion instead of laying a square icon
    -- over the cyan ring. The 22 px inset leaves the dark seat and rim visible.
    display.castIcon = CreateBadgeLayer(levelPanel, 22, "OVERLAY", 7)
    display.castIcon:SetTexCoord(.08, .92, .08, .92)
    display.castIcon:Hide()
    display.levelPanel = levelPanel

    -- Значок уровня круглый, а не квадратный: рядом с круглым
    -- портретом квадрат выбивался из силуэта. Круг делаем маской:
    -- заливка и кольцо — две текстуры под CircleMaskScalable, где кольцо
    -- просто на 4 px больше заливки. Готовые атласы Blizzard не годятся —
    -- они несут золото и бевель, а SetVertexColor тинтует умножением.
    local classPanel = CreateFrame("Frame", nil, holder)
    classPanel:SetSize(20, 20)
    -- Seat the level medallion across the portrait corner. Besides reading as
    -- a deliberate corner seal, this hides the tiny junction where the
    -- portrait and the lower frame edge meet.
    local levelDefault = DEFAULT_BADGE_POSITION[unit].level
    classPanel:SetPoint("CENTER", holder, "BOTTOMLEFT", levelDefault[1], levelDefault[2])
    display.levelBadgeDefault = {
        "CENTER", holder, "BOTTOMLEFT", levelDefault[1], levelDefault[2],
    }
    classPanel:SetFrameLevel(display.portrait.ring:GetFrameLevel() + 8)
    CreateBadgeLayer(classPanel, 20, "BACKGROUND", 0):SetVertexColor(C.edge[1], C.edge[2], C.edge[3], .80)
    CreateBadgeLayer(classPanel, 16, "BACKGROUND", 2):SetVertexColor(.015, .020, .026, .96)

    display.level = UI.Text(classPanel, "GameFontNormalSmall", "", C.amber)
    display.level:SetPoint("CENTER", 0, 0)
    do  -- чуть мельче штатного: в круг 16 px две цифры иначе упираются в край
        local font, _, flags = display.level:GetFont()
        if font then display.level:SetFont(font, 9, flags) end
    end
    display.classPanel = classPanel

    local statsPanel = UI.Panel(holder)
    ModernBackdrop(statsPanel, .95)
    statsPanel:SetSize(SIZE.panelWidth, SIZE.statsH)
    statsPanel:SetPoint("TOPLEFT", namePanel, "BOTTOMLEFT", 0, 0)
    display.statsPanel = statsPanel
    display.xperlPanels = { display.portrait.ring, namePanel, statsPanel }

    local moveOverlay = CreateFrame("Frame", nil, holder, "BackdropTemplate")
    moveOverlay:SetAllPoints(holder)
    moveOverlay:SetFrameLevel(statsPanel:GetFrameLevel() + 30)
    moveOverlay:EnableMouse(false)
    moveOverlay:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    moveOverlay:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
    local moveText = UI.Text(moveOverlay, "GameFontNormalSmall",
        unit == "player" and L("ПЕРЕТАЩИ: ИГРОК") or L("ПЕРЕТАЩИ: ЦЕЛЬ"), C.accent)
    moveText:SetPoint("TOP", moveOverlay, "BOTTOM", 0, -4)
    moveOverlay:Hide()
    display.moveOverlay = moveOverlay

    local highlightFrame = CreateFrame("Frame", nil, holder, "BackdropTemplate")
    highlightFrame:SetFrameLevel(statsPanel:GetFrameLevel() + 1)
    highlightFrame:SetAllPoints(holder)
    highlightFrame:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    highlightFrame:SetBackdropBorderColor(.30, .76, 1, .58)
    highlightFrame:Hide()
    display.highlight = highlightFrame

    display.health = XPerlStatusBar(statsPanel, C.green)
    display.healthValue = UI.Text(display.health, "GameFontNormalSmall", "")
    display.healthValue:SetPoint("TOPLEFT", 0, 0)
    display.healthValue:SetPoint("BOTTOMRIGHT", 0, 1)

    display.power = XPerlStatusBar(statsPanel, C.accentDim)
    display.powerValue = UI.Text(display.power, "GameFontNormalSmall", "")
    display.powerValue:SetPoint("TOPLEFT", 0, 0)
    display.powerValue:SetPoint("BOTTOMRIGHT", 0, 1)
    LayoutStats(display, true)

    if unit == "player" then BuildResourcePips(display) end

    if showAuras then
        if unit == "player" then
            display.buffRow = BuildAuraRow(display, SIZE.maxPlayerBuffs, holder, -8, SIZE.maxBuffs)
            display.debuffRow = BuildAuraRow(display, SIZE.maxDebuffs, display.buffRow, -SIZE.auraGap)
        else
            display.debuffRow = BuildAuraRow(display, SIZE.maxDebuffs, holder, -4)
            display.buffRow = BuildAuraRow(display, SIZE.maxBuffs, display.debuffRow, -SIZE.auraGap)
        end
    end
    if not options.preview then self:ConfigureBadgeDisplay(display) end
    if not options.preview then self.displays[unit] = display end
    return display
end

local function NormalizeBadgePosition(panel, holder)
    local centerX, centerY = panel:GetCenter()
    local left, bottom = holder:GetLeft(), holder:GetBottom()
    if not centerX or not centerY or not left or not bottom then return end
    local panelScale = panel:GetEffectiveScale() or 1
    local holderScale = holder:GetEffectiveScale() or 1
    local x = (centerX * panelScale - left * holderScale) / math.max(.01, holderScale)
    local y = (centerY * panelScale - bottom * holderScale) / math.max(.01, holderScale)
    panel:ClearAllPoints()
    panel:SetPoint("CENTER", holder, "BOTTOMLEFT", x, y)
    return x, y
end

function UnitFrames:ConfigureBadgeDisplay(display)
    local settings = Settings()
    settings.badgePositions = type(settings.badgePositions) == "table" and settings.badgePositions or {}
    local positions = settings.badgePositions[display.unit]
    local badges = {
        class = { panel = display.levelPanel, default = display.classBadgeDefault },
        level = { panel = display.classPanel, default = display.levelBadgeDefault },
    }
    for key, badge in pairs(badges) do
        -- Lua 5.1 closes over the loop variable; capture a per-panel key so
        -- dragging class and level badges cannot overwrite one another.
        local badgeKey = key
        local panel, saved = badge.panel, type(positions) == "table" and positions[key] or nil
        panel:ClearAllPoints()
        if type(saved) == "table" and UI.UsableNumber(saved.x) and UI.UsableNumber(saved.y) then
            panel:SetPoint("CENTER", display.holder, "BOTTOMLEFT", saved.x, saved.y)
        else
            panel:SetPoint(unpack(badge.default))
        end
        ApplyBadgeShape(panel, settings.badgeShape)
        local shown = settings.showBadges ~= false and settings.badgeShape ~= 4
        if badgeKey == "class" then
            shown = shown and (display.hasClassIcon == true or display.hasCastIcon == true)
        end
        panel:SetShown(shown)
        panel:SetMovable(true)
        panel:RegisterForDrag("LeftButton")
        panel:EnableMouse(settings.badgesUnlocked == true)
        if not panel.__mbBadgeDragBound then
            panel.__mbBadgeDragBound = true
            panel:SetScript("OnDragStart", function(owner)
                if not InCombatLockdown() and Settings().badgesUnlocked == true then owner:StartMoving() end
            end)
            panel:SetScript("OnDragStop", function(owner)
                if InCombatLockdown() then return end
                owner:StopMovingOrSizing()
                local x, y = NormalizeBadgePosition(owner, display.holder)
                if x and y then
                    local active = Settings()
                    active.badgePositions = type(active.badgePositions) == "table" and active.badgePositions or {}
                    active.badgePositions[display.unit] = active.badgePositions[display.unit] or {}
                    active.badgePositions[display.unit][badgeKey] = { x = x, y = y }
                    local otherUnit = display.unit == "player" and "target" or "player"
                    local otherDisplay = UnitFrames.displays and UnitFrames.displays[otherUnit]
                    if otherDisplay and otherDisplay.holder then
                        local mirroredX = (otherDisplay.holder:GetWidth() or SIZE.width) - x
                        active.badgePositions[otherUnit] = active.badgePositions[otherUnit] or {}
                        active.badgePositions[otherUnit][badgeKey] = { x = mirroredX, y = y }
                        local otherPanel = BadgePanel(otherDisplay, badgeKey)
                        if otherPanel then
                            otherPanel:ClearAllPoints()
                            otherPanel:SetPoint("CENTER", otherDisplay.holder, "BOTTOMLEFT", mirroredX, y)
                        end
                    end
                end
            end)
        end
    end
end

function UnitFrames:ResetBadgePositions()
    local settings = Settings()
    settings.badgePositions = {}
    for _, display in pairs(self.displays or {}) do self:ConfigureBadgeDisplay(display) end
end

local function UnitTooltip(button)
    GameTooltip_SetDefaultAnchor(GameTooltip, button); GameTooltip:SetUnit(button.unit)
    local display = UnitFrames.displays[button.unit]
    if display then display.hovered = true; UpdateState(display) end
end

local function UnitTooltipHide(button)
    GameTooltip_Hide()
    local display = UnitFrames.displays[button.unit]
    if display then display.hovered = false; UpdateState(display) end
end

-- Edit Mode remains the owner of Blizzard action bars.  We only read their
-- final on-screen rectangle when a capsule drag ends and offer one magnetic
-- landing position on either side.  Nothing is polled or forced afterwards,
-- so moving the action bars later never starts a tug-of-war between addons.
local ACTION_BUTTON_PREFIXES = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarLeftButton", "MultiBarRightButton", "MultiBar5Button",
    "MultiBar6Button", "MultiBar7Button",
}

local function ScreenRect(frame)
    if not frame or type(frame.GetLeft) ~= "function" or not frame:IsVisible() then return end
    local left, right, bottom, top = frame:GetLeft(), frame:GetRight(), frame:GetBottom(), frame:GetTop()
    if not left or not right or not bottom or not top then return end
    local uiScale = UIParent:GetEffectiveScale() or 1
    local scale = type(frame.GetEffectiveScale) == "function" and frame:GetEffectiveScale() or uiScale
    local factor = scale / math.max(.01, uiScale)
    return left * factor, right * factor, bottom * factor, top * factor
end

local function ActionClusterRect()
    local left, right, bottom, top
    for _, prefix in ipairs(ACTION_BUTTON_PREFIXES) do
        for index = 1, 12 do
            local x1, x2, y1, y2 = ScreenRect(_G[prefix .. index])
            if x1 then
                left = left and math.min(left, x1) or x1
                right = right and math.max(right, x2) or x2
                bottom = bottom and math.min(bottom, y1) or y1
                top = top and math.max(top, y2) or y2
            end
        end
    end
    return left, right, bottom, top
end

function UnitFrames:MagnetizeToActionBars(display)
    local clusterLeft, clusterRight, clusterBottom, clusterTop = ActionClusterRect()
    local frameLeft, frameRight, frameBottom, frameTop = ScreenRect(display and display.holder)
    if not clusterLeft or not frameLeft then return false end

    local horizontalDistance = display.unit == "player"
        and math.abs(frameRight - clusterLeft) or math.abs(frameLeft - clusterRight)
    local frameCenter = (frameBottom + frameTop) * .5
    local clusterCenter = (clusterBottom + clusterTop) * .5
    -- The vertical allowance is deliberately generous: the visible action
    -- cluster may have one, two or three rows, while the capsule has a fixed
    -- height.  Horizontal proximity is what expresses the snap intention.
    if horizontalDistance > 44 or math.abs(frameCenter - clusterCenter) > 92 then return false end

    local holder = display.holder
    local visibleWidth = frameRight - frameLeft
    local visibleHeight = frameTop - frameBottom
    local x = display.unit == "player" and (clusterLeft - visibleWidth - 2) or (clusterRight + 2)
    local y = clusterBottom + ((clusterTop - clusterBottom) - visibleHeight) * .5
    local uiScale = UIParent:GetEffectiveScale() or 1
    local holderScale = (holder:GetEffectiveScale() or uiScale) / math.max(.01, uiScale)
    holder:ClearAllPoints()
    holder:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / holderScale, y / holderScale)
    return true
end

function UnitFrames:BuildButton(display, name)
    if display.button then return end
    local button = CreateFrame("Button", name, display.holder, "SecureUnitButtonTemplate")
    button:SetAllPoints(display.holder); button:SetFrameLevel(display.statsPanel:GetFrameLevel() + 10)
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("unit", display.unit)
    button:SetAttribute("*type1", "target")
    button:SetAttribute("*type2", "togglemenu")
    button:SetAttribute("*type3", "focus")
    button:SetAttribute("toggleForVehicle", true)
    button.unit = display.unit
    button:SetScript("OnEnter", UnitTooltip); button:SetScript("OnLeave", UnitTooltipHide)
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function()
        if IsUnlocked() and not InCombatLockdown() then display.holder:StartMoving() end
    end)
    button:SetScript("OnDragStop", function()
        if not IsUnlocked() or InCombatLockdown() then return end
        display.holder:StopMovingOrSizing()
        self:MagnetizeToActionBars(display)
        local point, _, _, x, y = display.holder:GetPoint()
        Settings()[display.unit] = { point = point, x = x, y = y }
    end)
    ClickCastFrames = ClickCastFrames or {}; ClickCastFrames[button] = true
    RegisterUnitWatch(button)
    display.button = button
    if display.levelPanel then display.levelPanel:SetFrameLevel(button:GetFrameLevel() + 2) end
    if display.classPanel then display.classPanel:SetFrameLevel(button:GetFrameLevel() + 2) end
end

function UnitFrames:Hider()
    if not self.hider then self.hider = CreateFrame("Frame", "MythicBoostFrameHider", UIParent); self.hider:Hide() end
    return self.hider
end

function UnitFrames:HideBlizzard()
    if InCombatLockdown() then return false end
    for _, name in ipairs(BLIZZARD_FRAMES) do
        local frame = _G[name]
        if frame and not self.parked[name] then
            self.parked[name] = frame:GetParent() or UIParent
            frame:SetParent(self:Hider())
        end
    end
    return true
end

function UnitFrames:RestoreBlizzard()
    if InCombatLockdown() then return false end
    for name, parent in pairs(self.parked) do
        local frame = _G[name]
        if frame then frame:SetParent(parent) end
        self.parked[name] = nil
    end
    return true
end

local function ShowTargetPlaceholder(display, moving)
    if not InCombatLockdown() then display.holder:Show() end
    display.placeholder = true
    display.portrait:SetUnit(nil)
    display.portrait.face:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    display.portrait.face:SetTexCoord(0, 1, 0, 1)
    if type(display.portrait.face.SetDesaturated) == "function" then
        display.portrait.face:SetDesaturated(true)
    end
    display.portrait.face:SetVertexColor(.82, .65, .26, .92)
    display.portrait.face:Show()
    display.portrait.model:Hide()
    display.portrait.ring:Show()
    display.portrait:SetStateAlpha(.76)
    display.levelPanel:Hide()
    display.classPanel:Hide()
    display.statsPanel:Show()
    display.panel:ClearAllPoints()
    display.panel:SetSize(SIZE.panelWidth, SIZE.headerH)
    display.panel:SetPoint(display.mirror and "TOPRIGHT" or "TOPLEFT", display.portrait.ring,
        display.mirror and "TOPLEFT" or "TOPRIGHT", display.mirror and 1 or SIZE.gap, 0)
    ModernBackdrop(display.panel, .82)
    display.statsPanel:ClearAllPoints()
    display.statsPanel:SetSize(SIZE.panelWidth, SIZE.statsH)
    display.statsPanel:SetPoint("TOPLEFT", display.panel, "BOTTOMLEFT", 0, 0)
    LayoutStats(display, true)
    display.health:SetMinMaxValues(0, 1)
    display.health:SetValue(1)
    display.health:SetAlpha(.46)
    MatteBarColor(display.health, .34, .25, .08)
    display.healthValue:SetText("")
    display.power:SetMinMaxValues(0, 1)
    display.power:SetValue(1)
    display.power:SetAlpha(.40)
    MatteBarColor(display.power, .10, .12, .15)
    display.powerValue:SetText("")
    display.name:SetText(moving and L("Цель") or L("Цель не выбрана"))
    display.name:Show()
    if display.castBar then display.castBar:Hide() end
    display.name:SetTextColor(C.muted[1], C.muted[2], C.muted[3], .92)
    display.group:SetText("")
    display.level:SetText("")
    display.hasClassIcon = false
    display.hasCastIcon = false
    if display.classIcon then display.classIcon:Hide() end
    if display.castIcon then display.castIcon:Hide() end
    UpdateClassBadgePanelVisibility(display)

    wipe(display.cache)
    if display.debuffRow then
        LayoutRow(display.debuffRow, {})
        LayoutRow(display.buffRow, {})
    end
    if display.moveOverlay then display.moveOverlay:SetShown(moving == true) end
end

local function RestoreTargetPlaceholder(display)
    if not display.placeholder then return end
    display.placeholder = nil
    local mirror = display.mirror
    display.portrait.ring:Show()
    display.panel:ClearAllPoints()
    display.panel:SetSize(SIZE.panelWidth, SIZE.headerH)
    display.panel:SetPoint(mirror and "TOPRIGHT" or "TOPLEFT", display.portrait.ring,
        mirror and "TOPLEFT" or "TOPRIGHT", mirror and 1 or SIZE.gap, 0)
    ModernBackdrop(display.panel, .95)
    display.name:Show()
    display.statsPanel:ClearAllPoints()
    display.statsPanel:SetSize(SIZE.panelWidth, SIZE.statsH)
    display.statsPanel:SetPoint("TOPLEFT", display.panel, "BOTTOMLEFT", 0, 0)
    display.statsPanel:Show()
    display.health:SetAlpha(1)
    display.power:SetAlpha(1)
    local settings = ActiveSettings()
    local showBadges = settings.showBadges ~= false and settings.badgeShape ~= 4
    display.levelPanel:SetShown(showBadges)
    display.classPanel:SetShown(showBadges)
    display.name:SetTextColor(C.amber[1], C.amber[2], C.amber[3], 1)
end

function UnitFrames:RefreshDisplay(display, full)
    local exists = UnitExists(display.unit)
    if IsBoolean(exists, false) then
        local keepTarget = display.unit == "target" and ActiveSettings().alwaysShowTarget == true
        if display.unit == "target" and (IsUnlocked() or keepTarget) then
            ShowTargetPlaceholder(display, IsUnlocked())
            return
        end
        -- В holder живёт SecureUnitButton. Show/Hide его родителя в бою
        -- вызывает ADDON_ACTION_BLOCKED при обычной смене цели. Сам holder
        -- всегда подготовлен заранее, а отсутствие юнита обозначаем alpha=0;
        -- RegisterUnitWatch отдельно отключает защищённую область клика.
        display.holder:SetAlpha(0)
        if display.resourceRow and not InCombatLockdown() then display.resourceRow:Hide() end
        wipe(display.cache)
        if display.debuffRow and not InCombatLockdown() then
            LayoutRow(display.debuffRow, {}); LayoutRow(display.buffRow, {})
        end
        return
    end
    if not InCombatLockdown() then display.holder:Show() end
    if display.unit == "target" then RestoreTargetPlaceholder(display) end
    display.holder:SetAlpha(1)
    UpdateIdentity(display); UpdateHealth(display); UpdatePower(display); UpdateResourcePips(display); UpdateState(display)
    self:UpdateCast(display)
    if full and display.debuffRow then
        local settings = ActiveSettings()
        local aurasEnabled = display.unit == "player" and settings.showPlayerAuras ~= false
            or display.unit == "target" and settings.showTargetAuras ~= false
        if aurasEnabled then ReadAuras(display) else wipe(display.cache) end
        RefreshAuras(display)
    end
end

function UnitFrames:RefreshAll()
    for _, display in pairs(self.displays) do self:RefreshDisplay(display, true) end
end

function UnitFrames:ApplySettings()
    if InCombatLockdown() then
        return self:AfterCombat("appearance", function(module) module:ApplySettings() end)
    end
    local source = Settings()
    local settings = {}
    for _, key in ipairs(APPEARANCE_KEYS) do settings[key] = source[key] end
    settings.enabled, settings.hideBlizzard = source.enabled, source.hideBlizzard
    self.appliedSettings = settings
    for _, display in pairs(self.displays or {}) do
        display.holder:SetScale(settings.scale)
        display.holder:SetAlpha(settings.opacity)
        display.healthValue:SetShown(settings.showHealthText ~= false)
        display.powerValue:SetShown(settings.showPowerText ~= false)
        if display.portrait and display.portrait.SetAnimated then
            display.portrait:SetAnimated(settings.animatedPortrait ~= false)
        end
        if display.levelPanel then UpdateClassBadgePanelVisibility(display) end
        if display.classPanel then display.classPanel:SetShown(settings.showBadges ~= false) end
        self:ConfigureBadgeDisplay(display)
        UpdateResourcePips(display)
        if display.debuffRow then
            local aurasEnabled = display.unit == "player" and settings.showPlayerAuras ~= false
                or display.unit == "target" and settings.showTargetAuras ~= false
            if aurasEnabled then ReadAuras(display) else wipe(display.cache) end
            RefreshAuras(display)
        end
    end
    if settings.enabled ~= false and settings.hideBlizzard ~= false then self:HideBlizzard()
    else self:RestoreBlizzard() end
    return true
end

---------------------------------------------------------------------------
-- Anonymous screenshot showcase
---------------------------------------------------------------------------

local DEMO_PRESETS = {
    {
        title = L("1 - ОБЩИЙ ВИД"),
        caption = L("Игрок и цель в спокойном боевом состоянии"),
        player = {
            name = "Astraforge", class = "PALADIN", portrait = "Interface\\Icons\\Spell_Holy_AuraOfLight",
            health = 8420, healthMax = 10000, healthText = "8.42K/10.0K", healthColor = { .08, .78, .12 },
            power = 71, powerMax = 100, powerText = "71/100", powerColor = { .95, .76, .08 },
            resource = { current = 3, maximum = 5, color = { 1.00, .77, .08 } },
            buffs = {
                { icon = "Interface\\Icons\\Spell_Holy_WordFortitude", duration = 126, stacks = 1 },
                { icon = "Interface\\Icons\\Spell_Holy_DevotionAura", duration = 42, stacks = 1 },
            },
        },
        target = {
            name = "Voidwarden", class = "WARRIOR", portrait = "Interface\\Icons\\Ability_Warrior_DefensiveStance",
            health = 7680, healthMax = 12000, healthText = "7.68K/12.0K", healthColor = { .77, .18, .12 },
            power = 38, powerMax = 100, powerText = "38/100", powerColor = { .82, .18, .12 },
            debuffs = {
                { icon = "Interface\\Icons\\Spell_Holy_SealOfVengeance", duration = 18, stacks = 3 },
                { icon = "Interface\\Icons\\Ability_Creature_Disease_03", duration = 9, stacks = 1 },
            },
        },
    },
    {
        title = L("2 - ТАНК ПОД ДАВЛЕНИЕМ"),
        caption = L("Низкое здоровье, защитные эффекты и руны"),
        player = {
            name = "Ironbloom", class = "DEATHKNIGHT", portrait = "Interface\\Icons\\Spell_DeathKnight_FrostPresence",
            health = 3740, healthMax = 10000, healthText = "3.74K/10.0K", healthColor = { .90, .23, .10 },
            power = 84, powerMax = 100, powerText = "84/100", powerColor = { .18, .72, 1.00 },
            resource = { current = 4, maximum = 6, color = { .22, .72, 1.00 } },
            buffs = {
                { icon = "Interface\\Icons\\Spell_DeathKnight_IceBoundFortitude", duration = 7, stacks = 1 },
                { icon = "Interface\\Icons\\Spell_DeathKnight_AntiMagicZone", duration = 4, stacks = 1 },
            },
            debuffs = {
                { icon = "Interface\\Icons\\Ability_Creature_Poison_05", duration = 11, stacks = 2 },
            },
        },
        target = {
            name = "Dread Colossus", class = "WARRIOR", portrait = "Interface\\Icons\\Achievement_Boss_General_Nazgrim",
            health = 9180, healthMax = 15000, healthText = "9.18K/15.0K", healthColor = { .72, .14, .10 },
            power = 62, powerMax = 100, powerText = "62/100", powerColor = { .78, .16, .10 },
            buffs = { { icon = "Interface\\Icons\\Spell_Shadow_UnholyFrenzy", duration = 14, stacks = 1 } },
            debuffs = { { icon = "Interface\\Icons\\Spell_DeathKnight_BloodPlague", duration = 21, stacks = 1 } },
        },
    },
    {
        title = L("3 - ЛЕКАРЬ И ОПАСНАЯ ЦЕЛЬ"),
        caption = L("Мана, критическое здоровье цели и эффект для рассеивания"),
        player = {
            name = "Lumenweave", class = "PRIEST", portrait = "Interface\\Icons\\Spell_Holy_GreaterHeal",
            health = 9340, healthMax = 10000, healthText = "9.34K/10.0K", healthColor = { .08, .78, .12 },
            power = 6340, powerMax = 10000, powerText = "6.34K/10.0K", powerColor = { .18, .42, .92 },
            buffs = {
                { icon = "Interface\\Icons\\Spell_Holy_PowerWordShield", duration = 12, stacks = 1 },
                { icon = "Interface\\Icons\\Spell_Holy_Renew", duration = 8, stacks = 1 },
            },
        },
        target = {
            name = "Ashen Ravager", class = "MAGE", portrait = "Interface\\Icons\\Spell_Fire_Fire",
            health = 2240, healthMax = 10000, healthText = "2.24K/10.0K", healthColor = { .94, .18, .08 },
            power = 73, powerMax = 100, powerText = "73/100", powerColor = { .55, .22, .88 },
            buffs = { { icon = "Interface\\Icons\\Spell_Shadow_Possession", duration = 10, stacks = 1 } },
            debuffs = {
                { icon = "Interface\\Icons\\Spell_Holy_Dizzy", duration = 5, stacks = 1 },
                { icon = "Interface\\Icons\\Spell_Nature_NullifyDisease", duration = 13, stacks = 1 },
            },
        },
    },
    {
        title = L("4 - КОМБО И ДЕБАФФЫ"),
        caption = L("Семь комбо-поинтов и плотная строка эффектов"),
        player = {
            name = "Nightquill", class = "ROGUE", portrait = "Interface\\Icons\\Ability_Stealth",
            health = 8860, healthMax = 10000, healthText = "8.86K/10.0K", healthColor = { .08, .78, .12 },
            power = 58, powerMax = 100, powerText = "58/100", powerColor = { .95, .86, .18 },
            resource = { current = 5, maximum = 7, color = { 1.00, .33, .13 } },
            buffs = {
                { icon = "Interface\\Icons\\Ability_Rogue_Sprint", duration = 6, stacks = 1 },
                { icon = "Interface\\Icons\\Ability_Rogue_SliceDice", duration = 24, stacks = 1 },
            },
        },
        target = {
            name = "Runebound Horror", class = "WARLOCK", portrait = "Interface\\Icons\\Spell_Shadow_SummonVoidWalker",
            health = 6210, healthMax = 10000, healthText = "6.21K/10.0K", healthColor = { .74, .12, .16 },
            power = 46, powerMax = 100, powerText = "46/100", powerColor = { .58, .22, .86 },
            debuffs = {
                { icon = "Interface\\Icons\\Ability_Rogue_Rupture", duration = 17, stacks = 1 },
                { icon = "Interface\\Icons\\Ability_Rogue_DeadlyBrew", duration = 9, stacks = 5 },
                { icon = "Interface\\Icons\\Ability_Rogue_FindWeakness", duration = 4, stacks = 1 },
            },
        },
    },
    {
        title = L("5 - ЧИСТЫЙ МИНИМАЛ"),
        caption = L("Капсулы без лишних эффектов — для обложки и сравнения"),
        player = {
            name = "Dawnkeeper", class = "DRUID", portrait = "Interface\\Icons\\Ability_Druid_Maul",
            health = 10000, healthMax = 10000, healthText = "10.0K/10.0K", healthColor = { .08, .78, .12 },
            power = 100, powerMax = 100, powerText = "100/100", powerColor = { .96, .54, .12 },
        },
        target = {
            name = "Training Construct", class = "WARRIOR", portrait = "Interface\\Icons\\INV_Gizmo_GoblinBoomBox_01",
            health = 10000, healthMax = 10000, healthText = "10.0K/10.0K", healthColor = { .68, .16, .12 },
            power = 0, powerMax = 0, powerText = "", powerColor = { .40, .40, .40 },
        },
    },
}

local function DemoResourcePips(display, data, settings)
    local row = display.resourceRow
    if not row then return end
    if not data or settings.showResourcePips == false then
        row:Hide()
        for _, pip in ipairs(row.pips) do pip:Hide() end
        return
    end
    local maximum = math.max(1, math.min(8, data.maximum or 5))
    local current = math.max(0, math.min(maximum, data.current or 0))
    local gap, height = settings.resourceGap, settings.resourceHeight
    local size = (SIZE.panelWidth - (maximum - 1) * gap) / maximum
    local color = data.color or { .18, .76, 1 }
    local showEmpty = settings.showEmptyResources ~= false
    row:SetHeight(height); row:SetAlpha(settings.resourceOpacity)
    for index, pip in ipairs(row.pips) do
        if index <= maximum then
            pip:ClearAllPoints(); pip:SetSize(size, height)
            pip:SetPoint("LEFT", row, "LEFT", (index - 1) * (size + gap), 0)
            local active = index <= current
            if active then
                pip.ring:SetColorTexture(color[1] * .72, color[2] * .72, color[3] * .72, 1)
                SetPipTexture(pip.fill, color[1], color[2], color[3], 1)
                pip.shine:SetAlpha(.62)
            else
                pip.ring:SetColorTexture(.13, .24, .30, .92)
                SetPipTexture(pip.fill, .055, .075, .09, .96)
                pip.shine:SetAlpha(.08)
            end
            pip:SetShown(active or showEmpty)
        else pip:Hide() end
    end
    row:SetShown(current > 0 or showEmpty)
end

local function DemoAuras(display, data)
    wipe(display.cache)
    local now, nextID = GetTime(), 900000
    local function Add(list, harmful)
        for _, aura in ipairs(list or {}) do
            nextID = nextID + 1
            display.cache[nextID] = {
                auraInstanceID = nextID,
                icon = aura.icon,
                applications = aura.stacks or 1,
                duration = aura.duration or 30,
                expirationTime = now + (aura.duration or 30),
                timeMod = 1,
                isHarmful = harmful,
                isHelpful = not harmful,
                isFromPlayerOrPlayerPet = true,
            }
        end
    end
    Add(data.buffs, false); Add(data.debuffs, true)
    RefreshAuras(display)
end

local function DemoDisplay(display, data, settings)
    display.holder:SetScale(settings.scale)
    display.holder:SetAlpha(settings.opacity)
    display.holder:Show()
    display.placeholder = nil
    display.castBar:Hide()
    display.castIcon:Hide()
    display.hasClassIcon = UI.SetClassIconTexture(display.classIcon, data.class)
    display.classIcon:SetShown(display.hasClassIcon)
    display.name:Show()
    display.name:SetText(data.name)
    display.group:SetText(data.group or "G1")
    display.level:SetText("80")
    display.levelPanel:SetShown(settings.showBadges ~= false)
    display.classPanel:SetShown(settings.showBadges ~= false)
    display.portrait:SetAnimated(false)
    display.portrait.face:SetTexture(data.portrait)
    display.portrait.face:SetTexCoord(.08, .92, .08, .92)
    display.portrait.face:SetVertexColor(1, 1, 1, 1)
    display.portrait.face:Show(); display.portrait.model:Hide()
    display.portrait:SetStateAlpha(1)

    display.health:SetMinMaxValues(0, data.healthMax)
    display.health:SetValue(data.health)
    display.healthValue:SetText(data.healthText)
    display.healthValue:SetShown(settings.showHealthText ~= false)
    MatteBarColor(display.health, data.healthColor[1], data.healthColor[2], data.healthColor[3])
    if data.powerMax and data.powerMax > 0 then
        display.power.holder:Show(); LayoutStats(display, true)
        display.power:SetMinMaxValues(0, data.powerMax); display.power:SetValue(data.power)
        display.powerValue:SetText(data.powerText)
        display.powerValue:SetShown(settings.showPowerText ~= false)
        MatteBarColor(display.power, data.powerColor[1], data.powerColor[2], data.powerColor[3])
    else
        display.power.holder:Hide(); LayoutStats(display, false)
    end
    if display.highlight then display.highlight:Hide() end
    if display.moveOverlay then display.moveOverlay:Hide() end
    DemoResourcePips(display, data.resource, settings)
    DemoAuras(display, data)
end

function UnitFrames:BuildScreenshotStage()
    if self.screenshotStage then return self.screenshotStage end
    local stage = CreateFrame("Frame", "MythicBoostScreenshotDemo", UIParent, "BackdropTemplate")
    stage:SetAllPoints(UIParent)
    stage:SetFrameStrata("FULLSCREEN_DIALOG")
    stage:SetFrameLevel(500)
    stage:EnableMouse(true)
    UI.Backdrop(stage, { .006, .010, .016, 1 }, { .12, .40, .52, 1 }, 1)

    local glow = stage:CreateTexture(nil, "BACKGROUND")
    glow:SetPoint("CENTER", 0, 20); glow:SetSize(900, 430)
    glow:SetColorTexture(.025, .055, .075, .96)
    glow:SetGradient("VERTICAL", CreateColor(.006, .010, .016, 0), CreateColor(.06, .16, .22, .62))

    local brand = UI.Text(stage, "GameFontNormalHuge", "MYTHICBOOST - UNIT FRAMES", C.accent)
    brand:SetPoint("TOP", 0, -64)
    stage.presetTitle = UI.Text(stage, "GameFontNormalLarge", "", C.text)
    stage.presetTitle:SetPoint("TOP", brand, "BOTTOM", 0, -18)
    stage.presetCaption = UI.Text(stage, "GameFontHighlightSmall", "", C.muted)
    stage.presetCaption:SetPoint("TOP", stage.presetTitle, "BOTTOM", 0, -8)

    local anonymous = UI.Text(stage, "GameFontNormalSmall",
        L("ДЕМО - ВЫМЫШЛЕННЫЕ ИМЕНА - ЛИЧНЫЕ ДАННЫЕ СКРЫТЫ"), C.green)
    anonymous:SetPoint("BOTTOM", 0, 38)
    local hint = UI.Text(stage, "GameFontHighlightSmall",
        L("Выбери сцену кнопками 1-5 - Esc закрывает демо"), C.muted)
    hint:SetPoint("BOTTOM", anonymous, "TOP", 0, 8)

    local close = UI.CloseButton(stage)
    close:SetPoint("TOPRIGHT", -30, -28)
    close:SetFrameLevel(stage:GetFrameLevel() + 50)
    close:SetScript("OnClick", function() UnitFrames:HideScreenshotDemo() end)

    stage.player = self:BuildDisplay("player", false, true, false, { parent = stage, preview = true })
    stage.target = self:BuildDisplay("target", true, true, true, { parent = stage, preview = true })
    stage.player.holder:SetPoint("CENTER", stage, "CENTER", -170, 38)
    stage.target.holder:SetPoint("CENTER", stage, "CENTER", 170, 38)
    stage.player.holder:SetFrameLevel(stage:GetFrameLevel() + 10)
    stage.target.holder:SetFrameLevel(stage:GetFrameLevel() + 10)

    stage.buttons = {}
    for index = 1, #DEMO_PRESETS do
        local button = UI.Button(stage, tostring(index), 38, 28, true)
        button:SetPoint("BOTTOM", stage, "BOTTOM", (index - 3) * 48, 82)
        button:SetFrameLevel(stage:GetFrameLevel() + 50)
        button:SetScript("OnClick", function() UnitFrames:ShowScreenshotDemo(index) end)
        stage.buttons[index] = button
    end
    if UISpecialFrames then table.insert(UISpecialFrames, stage:GetName()) end
    stage:SetScript("OnHide", function() UnitFrames.screenshotPreset = nil end)
    stage:Hide()
    self.screenshotStage = stage
    return stage
end

function UnitFrames:ShowScreenshotDemo(index)
    index = math.max(1, math.min(#DEMO_PRESETS, tonumber(index) or 1))
    local stage, preset = self:BuildScreenshotStage(), DEMO_PRESETS[index]
    if GameTooltip then GameTooltip:Hide() end
    local settings = Settings()
    stage.presetTitle:SetText(L(preset.title))
    stage.presetCaption:SetText(L(preset.caption))
    for buttonIndex, button in ipairs(stage.buttons) do
        button:SetText(buttonIndex == index and ("[" .. buttonIndex .. "]") or tostring(buttonIndex))
    end
    DemoDisplay(stage.player, preset.player, settings)
    DemoDisplay(stage.target, preset.target, settings)
    stage:Show()
    self.screenshotPreset = index
end

function UnitFrames:HideScreenshotDemo()
    if self.screenshotStage then self.screenshotStage:Hide() end
    self.screenshotPreset = nil
end

function UnitFrames:ResetPositions()
    if InCombatLockdown() then return false end
    local settings = Settings()
    for unit, display in pairs(self.displays) do
        local position = DEFAULT_POSITION[unit]
        display.holder:ClearAllPoints()
        display.holder:SetPoint(position[1], UIParent, position[1], position[2], position[3])
        settings[unit] = { point = position[1], x = position[2], y = position[3] }
    end
    self:ResetBadgePositions()
    return true
end

function UnitFrames:SetUnlocked(unlocked)
    Settings().unlocked = unlocked and true or false
    if InCombatLockdown() then
        self.pendingUnlock = Settings().unlocked
        return false
    end
    self.appliedUnlocked = Settings().unlocked
    for _, display in pairs(self.displays or {}) do
        if display.moveOverlay then display.moveOverlay:SetShown(self.appliedUnlocked) end
    end
    self:RefreshAll()
    self.pendingUnlock = nil
    return true
end

function UnitFrames:Create()
    if self.container then return end
    self.container = CreateFrame("Frame", "MythicBoostUnitFrames", UIParent)
    self.container:SetAllPoints(); self.container:SetFrameStrata("MEDIUM")
    self:BuildDisplay("player", false, true, false)
    self:BuildDisplay("target", true, true, true)
    self:RefreshDispelSet()
    self.events = CreateFrame("Frame")
    self.events:SetScript("OnEvent", function(_, event, ...) self:OnEvent(event, ...) end)
    self.events:RegisterEvent("PLAYER_REGEN_ENABLED")
    self:AfterCombat("secure", function(module)
        module:BuildButton(module.displays.player, "MythicBoostPlayerButton")
        module:BuildButton(module.displays.target, "MythicBoostTargetButton")
    end)
end

function UnitFrames:QueuePortraitRefresh(display)
    if not display or not display.portrait then return end
    display.portraitRefreshToken = (display.portraitRefreshToken or 0) + 1
    local token = display.portraitRefreshToken
    if not C_Timer or type(C_Timer.After) ~= "function" then
        display.portrait:SetUnit(display.unit, true)
        return
    end
    -- Model/portrait events commonly arrive in bursts inside a key. Rebuild
    -- once after the burst: a real form/target change still refreshes, while
    -- repeated ClearModel calls can no longer starve OnModelLoaded.
    C_Timer.After(.05, function()
        if display.portraitRefreshToken ~= token or not display.portrait then return end
        display.portraitRefreshToken = nil
        display.portrait:SetUnit(display.unit, true)
    end)
end

function UnitFrames:OnEvent(event, unit, updateInfo)
    if event == "PLAYER_REGEN_ENABLED" then
        local pending = self.pending; self.pending = {}
        for _, action in pairs(pending) do action(self) end
        if self.pendingUnlock ~= nil then self:SetUnlocked(self.pendingUnlock) end
        for _, display in pairs(self.displays or {}) do
            -- Do not clear/recreate PlayerModel during the combat transition;
            -- this races OnModelLoaded and leaves the 2D fallback visible.
            if display.portrait and display.portrait.unit ~= display.unit then
                display.portrait:SetUnit(display.unit)
            end
            if display.debuffRow then
                ReadAuras(display)
                RefreshAuras(display)
            end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:RefreshDispelSet(); self:RefreshAll()
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        self:RefreshDispelSet()
        UpdateResourcePips(self.displays.player)
        if self.displays.player and self.displays.player.debuffRow then RefreshAuras(self.displays.player) end
        if self.displays.target then RefreshAuras(self.displays.target) end
    elseif event == "UPDATE_SHAPESHIFT_FORM" or event == "RUNE_POWER_UPDATE" then
        UpdateResourcePips(self.displays.player)
        if event == "UPDATE_SHAPESHIFT_FORM" and self.displays.player.portrait then
            self:QueuePortraitRefresh(self.displays.player)
        end
        if event == "UPDATE_SHAPESHIFT_FORM" and self.displays.player.debuffRow then
            RefreshAuras(self.displays.player)
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        self:RefreshDisplay(self.displays.target, true)
        self:QueuePortraitRefresh(self.displays.target)
    else
        local display = unit and self.displays[unit]
        if not display then return end
        if event == "UNIT_AURA" then
            local settings = ActiveSettings()
            local aurasEnabled = display.unit == "player" and settings.showPlayerAuras ~= false
                or display.unit == "target" and settings.showTargetAuras ~= false
            if display.debuffRow and aurasEnabled and ApplyAuraUpdate(display, updateInfo) then
                RefreshAuras(display)
            end
        elseif event:find("^UNIT_SPELLCAST") then self:UpdateCast(display, event)
        elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then UpdateHealth(display); UpdateState(display)
        elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER"
            or event == "UNIT_POWER_POINT_CHARGE" then
            UpdatePower(display)
            if display.unit == "player" then
                UpdateResourcePips(display)
                if event == "UNIT_DISPLAYPOWER" and display.debuffRow then RefreshAuras(display) end
            end
        elseif event == "UNIT_PORTRAIT_UPDATE" or event == "UNIT_MODEL_CHANGED" then
            self:QueuePortraitRefresh(display)
        else UpdateIdentity(display); UpdateState(display) end
    end
end

function UnitFrames:Enable()
    if not self.container then self:Create() end
    if Settings().enabled == false then self:Disable(); return end
    local events = self.events
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("PLAYER_TARGET_CHANGED")
    events:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    events:RegisterEvent("RUNE_POWER_UPDATE")
    for _, event in ipairs({
        "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
        "UNIT_AURA", "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_NAME_UPDATE",
        "UNIT_FACTION", "UNIT_CONNECTION",
    }) do events:RegisterUnitEvent(event, "player", "target") end
    for _, event in ipairs({
        "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
        "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
        "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_UPDATE", "UNIT_SPELLCAST_EMPOWER_STOP",
    }) do pcall(events.RegisterUnitEvent, events, event, "player", "target") end
    if not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid("UNIT_POWER_POINT_CHARGE") then
        events:RegisterUnitEvent("UNIT_POWER_POINT_CHARGE", "player")
    end
    self.container:Show(); self:ApplySettings(); self:RefreshAll(); self:SetUnlocked(Settings().unlocked)
    if JP.MinimalUI and JP.MinimalUI.Apply then C_Timer.After(0, function() JP.MinimalUI:Apply() end) end
end

function UnitFrames:Disable()
    if self.events then self.events:UnregisterAllEvents(); self.events:RegisterEvent("PLAYER_REGEN_ENABLED") end
    if self.container then self.container:Hide() end
    for _, display in pairs(self.displays or {}) do
        if display.moveOverlay then display.moveOverlay:Hide() end
    end
    self:AfterCombat("restoreBlizzard", function(module) module:RestoreBlizzard() end)
end

function UnitFrames:Destroy() self:Disable() end

JP.UnitFrames = UnitFrames
JP:RegisterModule("UnitFrames", UnitFrames)
