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
    player = { "BOTTOM", -410, 220 },
    target = { "BOTTOM", 410, 220 },
}
local BLIZZARD_FRAMES = { "PlayerFrame", "TargetFrame", "BuffFrame", "DebuffFrame" }
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
        sheen:SetColorTexture(1, 1, 1, .18)
        frame.__mbModernSheen = sheen

        local hollow = frame:CreateTexture(nil, "BORDER", nil, 1)
        hollow:SetPoint("BOTTOMLEFT", 1, 1)
        hollow:SetPoint("BOTTOMRIGHT", -1, 1)
        hollow:SetHeight(1)
        hollow:SetColorTexture(0, 0, 0, .58)
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
    StyleAuraText(frame.timer, 10, C.amber)
    StyleAuraText(frame.count, 11, { 1, 1, 1 })
    if frame.timer then
        frame.timer:ClearAllPoints()
        frame.timer:SetPoint("TOPLEFT", 2, -2)
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
    if db.unitFrames.unlocked == nil then db.unitFrames.unlocked = false end
    -- Revision 5 adopts the balanced lower layout. Only absent positions and
    -- the exact previous defaults are migrated; manually placed frames stay
    -- where the player left them.
    if db.unitFrames.positionRevision ~= 5 then
        local player = db.unitFrames.player
        local target = db.unitFrames.target
        local oldPlayer = type(player) == "table" and player.point == "TOPLEFT"
            and player.x == 28 and player.y == -28
        local oldTarget = type(target) == "table" and target.point == "TOPRIGHT"
            and target.x == -360 and target.y == -28
        if type(player) ~= "table" or oldPlayer then
            db.unitFrames.player = { point = "BOTTOM", x = -410, y = 220 }
        end
        if type(target) ~= "table" or oldTarget then
            db.unitFrames.target = { point = "BOTTOM", x = 410, y = 220 }
        end
        db.unitFrames.positionRevision = 5
    end
    return db.unitFrames
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
    local gap = 2
    local size = (SIZE.panelWidth - (maximum - 1) * gap) / maximum
    for index, pip in ipairs(row.pips) do
        if index <= maximum then
            pip:ClearAllPoints()
            pip:SetSize(size, 10)
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
            pip:Show()
        else pip:Hide() end
    end
    row:Show()
end

local function UpdateIdentity(display)
    local name = UnitName(display.unit)
    display.name:SetText(type(name) == "string" and not issecretvalue(name) and name or "")
    local level = UnitLevel(display.unit)
    display.level:SetText(UI.UsableNumber(level) and tostring(level) or "")
    local _, class = UnitClass(display.unit)
    if display.classIcon then
        display.classIcon:SetText(type(class) == "string" and not issecretvalue(class) and UI.ClassIcon(class, 20) or "")
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

-- Ауры в Midnight из tainted-кода не просто приходят защищёнными — сам вызов
-- GetAuraDataByIndex бросает ошибку прямо из C («Auras cannot be accessed when
-- secret while tainted»). Проверить это заранее нечем, поэтому чтение идёт
-- через pcall. Второе значение отличает «ауры закрыты» от «ауры кончились»:
-- в первом случае перебирать оставшиеся слоты бессмысленно.
local function SafeAura(unit, index, filter)
    if not C_UnitAuras or type(C_UnitAuras.GetAuraDataByIndex) ~= "function" then return nil, true end
    local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
    if not ok then return nil, true end
    return data, false
end

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

local function LayoutRow(row, list)
    for index, icon in ipairs(row.icons) do
        local data = list[index]
        if data then FillIcon(icon, data, row.display)
        else icon:Hide(); icon.auraInstanceID, icon.expires = nil, nil end
    end
    local visible = math.min(#list, #row.icons)
    local lines = math.max(1, math.ceil(visible / row.columns))
    -- Скрытый ряд всё равно держит свою высоту, а следующий ряд привязан к его
    -- нижнему краю — из-за этого под фреймом зияла пустая полоса в высоту
    -- иконки. Пустой ряд схлопываем, чтобы всё под ним подтянулось вверх.
    row:SetHeight(#list > 0 and (lines * SIZE.aura + (lines - 1) * SIZE.auraGap) or .001)
    row:SetShown(#list > 0)
end

local function RefreshAuras(display)
    if not display.debuffRow then return end
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
    LayoutRow(display.debuffRow, debuffs); LayoutRow(display.buffRow, buffs)

    -- Не резервируем невидимую строку. Раньше у дружелюбной цели сначала
    -- стоял скрытый ряд дебаффов, а бафы из-за него висели на 20+ px ниже.
    local function AnchorRow(row, anchor, y)
        row:ClearAllPoints()
        local edgeInset = 0
        row:SetPoint(display.mirror and "TOPRIGHT" or "TOPLEFT", anchor,
            display.mirror and "BOTTOMRIGHT" or "BOTTOMLEFT", edgeInset, y)
    end
    if display.unit == "player" then
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

function UnitFrames:BuildDisplay(unit, mirror, showAuras, ownBuffsOnly)
    local display = { unit = unit, mirror = mirror, cache = {}, ownBuffsOnly = ownBuffsOnly }
    local holder = CreateFrame("Frame", nil, self.container)
    holder:SetSize(SIZE.width, SIZE.height)
    holder:SetMovable(true)
    display.holder = holder

    local saved, default = Settings()[unit], DEFAULT_POSITION[unit]
    if type(saved) == "table" and UI.UsableNumber(saved.x) and UI.UsableNumber(saved.y) then
        holder:SetPoint(saved.point or default[1], UIParent, saved.point or default[1], saved.x, saved.y)
    else holder:SetPoint(default[1], UIParent, default[1], default[2], default[3]) end

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
    display.name = UI.Text(namePanel, "GameFontNormal", "", C.amber)
    display.name:SetPoint("TOPLEFT", 24, 0)
    display.name:SetPoint("BOTTOMRIGHT", -24, 1)
    display.name:SetJustifyH("CENTER")
    display.name:SetWordWrap(false)
    if type(display.name.SetMaxLines) == "function" then display.name:SetMaxLines(1) end

    -- The class/spec badge is the larger companion to the level seal: 28 px
    -- versus 20 px (1.4x), centred over the upper portrait/body junction.
    local levelPanel = CreateFrame("Frame", nil, holder)
    levelPanel:SetSize(28, 28)
    levelPanel:SetPoint("CENTER", display.portrait.ring,
        mirror and "TOPRIGHT" or "TOPLEFT", mirror and -1 or 1, -1)
    levelPanel:SetFrameLevel(display.portrait.ring:GetFrameLevel() + 9)
    local function ClassCircle(size, layer, sublevel)
        local tex = levelPanel:CreateTexture(nil, layer, nil, sublevel)
        tex:SetSize(size, size)
        tex:SetPoint("CENTER")
        tex:SetColorTexture(1, 1, 1, 1)
        tex:SetSnapToPixelGrid(false)
        tex:SetTexelSnappingBias(0)
        local mask = levelPanel:CreateMaskTexture()
        mask:SetTexture("Interface\\Masks\\CircleMaskScalable",
            "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        if not mask:GetTexture() then
            mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask",
                "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        end
        mask:SetSize(size, size)
        mask:SetPoint("CENTER")
        tex:AddMaskTexture(mask)
        return tex
    end
    ClassCircle(28, "BACKGROUND", 0):SetVertexColor(C.edge[1], C.edge[2], C.edge[3], .92)
    ClassCircle(24, "BACKGROUND", 2):SetVertexColor(.012, .020, .028, .98)
    local classGloss = ClassCircle(22, "ARTWORK", 1)
    classGloss:SetBlendMode("ADD")
    classGloss:SetGradient("VERTICAL",
        CreateColor(1, 1, 1, 0),
        CreateColor(.68, .91, 1, .16))
    display.classIcon = UI.Text(levelPanel, "GameFontNormalSmall", "")
    display.classIcon:SetPoint("CENTER", 0, 0)
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
    classPanel:SetPoint("CENTER", display.portrait.ring,
        mirror and "BOTTOMRIGHT" or "BOTTOMLEFT", mirror and -1 or 1, 1)
    classPanel:SetFrameLevel(display.portrait.ring:GetFrameLevel() + 8)
    local function LevelCircle(size, layer, sublevel)
        local tex = classPanel:CreateTexture(nil, layer, nil, sublevel)
        tex:SetSize(size, size)
        tex:SetPoint("CENTER")
        tex:SetColorTexture(1, 1, 1, 1)
        tex:SetSnapToPixelGrid(false)
        tex:SetTexelSnappingBias(0)
        local mask = classPanel:CreateMaskTexture()
        mask:SetTexture("Interface\\Masks\\CircleMaskScalable",
            "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        -- Существование ФАЙЛА текстуры проверяется только так: GetAtlasInfo
        -- знает атласы, но не файлы. Несуществующий путь не даёт ошибки — он
        -- молча оставляет текстуру пустой, маска не применяется, и круг
        -- остаётся квадратом. Именно это и было видно на значке уровня.
        if not mask:GetTexture() then
            mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask",
                "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        end
        mask:SetSize(size, size)
        mask:SetPoint("CENTER")
        tex:AddMaskTexture(mask)
        return tex
    end
    LevelCircle(20, "BACKGROUND", 0):SetVertexColor(C.edge[1], C.edge[2], C.edge[3], .80)
    LevelCircle(16, "BACKGROUND", 2):SetVertexColor(.015, .020, .026, .96)

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
    self.displays[unit] = display
    return display
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
        if Settings().unlocked and not InCombatLockdown() then display.holder:StartMoving() end
    end)
    button:SetScript("OnDragStop", function()
        if not Settings().unlocked or InCombatLockdown() then return end
        display.holder:StopMovingOrSizing()
        local point, _, _, x, y = display.holder:GetPoint()
        Settings()[display.unit] = { point = point, x = x, y = y }
    end)
    ClickCastFrames = ClickCastFrames or {}; ClickCastFrames[button] = true
    RegisterUnitWatch(button)
    display.button = button
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

local function ShowMovePlaceholder(display)
    display.holder:Show()
    display.portrait:SetUnit(nil)
    display.portrait:SetStateAlpha(.82)
    display.name:SetText(L("ЦЕЛЬ"))
    display.group:SetText("")
    display.level:SetText("")
    if display.classIcon then display.classIcon:SetText("") end

    LayoutStats(display, true)
    display.health:SetMinMaxValues(0, 1)
    display.health:SetValue(1)
    display.healthValue:SetText("")
    MatteBarColor(display.health, .18, .46, .34)
    display.power.holder:Show()
    display.power:SetMinMaxValues(0, 1)
    display.power:SetValue(1)
    display.powerValue:SetText("")
    MatteBarColor(display.power, .16, .34, .56)

    wipe(display.cache)
    if display.debuffRow then
        LayoutRow(display.debuffRow, {})
        LayoutRow(display.buffRow, {})
    end
    if display.moveOverlay then display.moveOverlay:Show() end
end

function UnitFrames:RefreshDisplay(display, full)
    local exists = UnitExists(display.unit)
    if IsBoolean(exists, false) then
        if display.unit == "target" and Settings().unlocked then
            ShowMovePlaceholder(display)
            return
        end
        display.holder:Hide()
        if display.resourceRow then display.resourceRow:Hide() end
        wipe(display.cache)
        if display.debuffRow then LayoutRow(display.debuffRow, {}); LayoutRow(display.buffRow, {}) end
        return
    end
    display.holder:Show()
    UpdateIdentity(display); UpdateHealth(display); UpdatePower(display); UpdateResourcePips(display); UpdateState(display)
    if full and display.debuffRow then ReadAuras(display); RefreshAuras(display) end
end

function UnitFrames:RefreshAll()
    for _, display in pairs(self.displays) do self:RefreshDisplay(display, true) end
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
    return true
end

function UnitFrames:SetUnlocked(unlocked)
    Settings().unlocked = unlocked and true or false
    if InCombatLockdown() then
        self.pendingUnlock = Settings().unlocked
        return false
    end
    for _, display in pairs(self.displays or {}) do
        if display.moveOverlay then display.moveOverlay:SetShown(Settings().unlocked) end
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

function UnitFrames:OnEvent(event, unit, updateInfo)
    if event == "PLAYER_REGEN_ENABLED" then
        local pending = self.pending; self.pending = {}
        for _, action in pairs(pending) do action(self) end
        if self.pendingUnlock ~= nil then self:SetUnlocked(self.pendingUnlock) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:RefreshDispelSet(); self:RefreshAll()
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        self:RefreshDispelSet()
        UpdateResourcePips(self.displays.player)
        if self.displays.player and self.displays.player.debuffRow then RefreshAuras(self.displays.player) end
        if self.displays.target then RefreshAuras(self.displays.target) end
    elseif event == "UPDATE_SHAPESHIFT_FORM" or event == "RUNE_POWER_UPDATE" then
        UpdateResourcePips(self.displays.player)
        if event == "UPDATE_SHAPESHIFT_FORM" and self.displays.player.debuffRow then
            RefreshAuras(self.displays.player)
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        self:RefreshDisplay(self.displays.target, true)
    else
        local display = unit and self.displays[unit]
        if not display then return end
        if event == "UNIT_AURA" then
            if display.debuffRow and ApplyAuraUpdate(display, updateInfo) then RefreshAuras(display) end
        elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then UpdateHealth(display); UpdateState(display)
        elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER"
            or event == "UNIT_POWER_POINT_CHARGE" then
            UpdatePower(display)
            if display.unit == "player" then
                UpdateResourcePips(display)
                if event == "UNIT_DISPLAYPOWER" and display.debuffRow then RefreshAuras(display) end
            end
        elseif event == "UNIT_PORTRAIT_UPDATE" or event == "UNIT_MODEL_CHANGED" then display.portrait:SetUnit(display.unit)
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
    if not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid("UNIT_POWER_POINT_CHARGE") then
        events:RegisterUnitEvent("UNIT_POWER_POINT_CHARGE", "player")
    end
    self.container:Show(); self:RefreshAll(); self:SetUnlocked(Settings().unlocked)
    if Settings().hideBlizzard ~= false then self:AfterCombat("hideBlizzard", function(module) module:HideBlizzard() end) end
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
