local _, JP = ...

local L = JP.L
-- Единый визуальный язык аддона. Все панели, кнопки, поля и списки
-- создаются только через эти конструкторы, поэтому окно выглядит цельно
-- и не зависит от стандартных шаблонов Blizzard.
local UI = {}
JP.UI = UI

UI.colors = {
    edge      = { .16, .80, .86, 1 },
    accent    = { .16, .72, .96, 1 },
    accentSoft= { .16, .72, .96, .18 },
    accentDim = { .10, .40, .55, 1 },
    text      = { .90, .93, .97, 1 },
    muted     = { .50, .57, .66, 1 },
    faint     = { .33, .38, .45, 1 },
    green     = { .28, .92, .56, 1 },
    amber     = { 1, .74, .24, 1 },
    red       = { .93, .38, .38, 1 },
    window    = { .043, .055, .075, .97 },
    panel     = { .063, .079, .102, .95 },
    raised    = { .090, .112, .140, .96 },
    field     = { .028, .036, .048, .95 },
    row       = { .075, .093, .118, .92 },
    rowAlt    = { .058, .073, .095, .92 },
    rowHover  = { .112, .150, .190, .95 },
    line      = { .15, .20, .26, 1 },
    lineSoft  = { .12, .16, .21, .85 },

    -- Канонические поверхности. Любая панель аддона — и в окне, и поверх
    -- игрового мира — обязана брать фон и контур ОТСЮДА, а не объявлять свои
    -- рядом с собой. До этого каждый модуль держал собственный почти-такой-же
    -- тёмный: UnitFrames .012/.017/.024, MinimalUI .018/.026/.034, LootUI
    -- .008/.012/.018, PlayerTooltip .008/.012/.020. Пять чуть разных серых с
    -- пятью разными контурами на одном экране глаз читает как пять разных
    -- аддонов; одинаковые — как один интерфейс.
    surface     = { .014, .020, .028, .94 },
    surfaceEdge = { .16, .21, .27, .96 },
}

local C = UI.colors
local WHITE = "Interface/Buttons/WHITE8X8"

function UI.UsableNumber(value)
    return type(value) == "number" and not issecretvalue(value)
end

local function Unpack(color)
    return color[1], color[2], color[3], color[4] or 1
end
UI.Unpack = Unpack

---------------------------------------------------------------------------
-- Базовые примитивы
---------------------------------------------------------------------------

function UI.Backdrop(frame, background, border, edgeSize)
    frame:SetBackdrop({
        bgFile = WHITE,
        edgeFile = border and WHITE or nil,
        edgeSize = edgeSize or 1,
    })
    frame:SetBackdropColor(Unpack(background or C.panel))
    if border then frame:SetBackdropBorderColor(Unpack(border)) end
end

function UI.Panel(parent, background, border)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    UI.Backdrop(frame, background or C.panel, border or C.line)
    return frame
end

function UI.Text(parent, template, value, color)
    local text = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    text:SetText(value or "")
    -- Цвет проверяем, а не доверяем. Один лишний аргумент у вызывающего — и
    -- сюда прилетает строка вместо таблицы, Unpack отдаёт nil, а SetTextColor
    -- роняет весь модуль на этапе Create. Так уже случилось с KeystoneTimer,
    -- и стоило это целой мёртвой функции: модуль просто не создавался.
    if type(color) == "table" and type(color[1]) == "number"
        and type(color[2]) == "number" and type(color[3]) == "number" then
        text:SetTextColor(Unpack(color))
    end
    return text
end

function UI.Line(parent, color)
    local texture = parent:CreateTexture(nil, "ARTWORK")
    texture:SetColorTexture(Unpack(color or C.lineSoft))
    texture:SetHeight(1)
    return texture
end

-- Вертикальная затемняющая подложка: делает текст читаемым поверх арта.
function UI.Scrim(parent, layer, topAlpha, bottomAlpha)
    local texture = parent:CreateTexture(nil, layer or "ARTWORK")
    texture:SetColorTexture(1, 1, 1, 1)
    texture:SetGradient("VERTICAL",
        CreateColor(.02, .03, .04, bottomAlpha or .88),
        CreateColor(.02, .03, .04, topAlpha or 0))
    return texture
end

---------------------------------------------------------------------------
-- Иконки классов и ролей
---------------------------------------------------------------------------

local CLASS_ATLAS = {
    WARRIOR = "classicon-warrior", PALADIN = "classicon-paladin", HUNTER = "classicon-hunter",
    ROGUE = "classicon-rogue", PRIEST = "classicon-priest", DEATHKNIGHT = "classicon-deathknight",
    SHAMAN = "classicon-shaman", MAGE = "classicon-mage", WARLOCK = "classicon-warlock",
    MONK = "classicon-monk", DRUID = "classicon-druid", DEMONHUNTER = "classicon-demonhunter",
    EVOKER = "classicon-evoker",
}

local ROLE_ATLAS = {
    TANK = "roleicon-tiny-tank", HEALER = "roleicon-tiny-healer", DAMAGER = "roleicon-tiny-dps",
}

local ROLE_FALLBACK_COORDS = {
    TANK = { 0 / 64, 19 / 64, 22 / 64, 41 / 64 },
    HEALER = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 },
    DAMAGER = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 },
}

local atlasCache = {}
local function AtlasMarkup(atlas, size)
    if not atlas or not CreateAtlasMarkup then return end
    if atlasCache[atlas] == nil then
        atlasCache[atlas] = (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)) and true or false
    end
    if not atlasCache[atlas] then return end
    return CreateAtlasMarkup(atlas, size, size)
end

-- Атлас — основной путь: старые glue-текстуры в Midnight отдаются не всегда.
function UI.ClassIcon(classFilename, size)
    if type(classFilename) ~= "string" then return "" end
    size = size or 18
    local markup = AtlasMarkup(CLASS_ATLAS[classFilename], size)
    if markup then return markup end
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFilename]
    if not coords then return "" end
    return ("|TInterface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES:%d:%d:0:0:256:256:%d:%d:%d:%d|t"):format(
        size, size,
        math.floor(coords[1] * 256 + .5), math.floor(coords[2] * 256 + .5),
        math.floor(coords[3] * 256 + .5), math.floor(coords[4] * 256 + .5))
end

local ROLE_LETTER = { TANK = L("Т"), HEALER = L("Х"), DAMAGER = L("Б") }

function UI.RoleIcon(role, size)
    local markup = AtlasMarkup(ROLE_ATLAS[role], size or 16)
    if markup then return markup end
    -- Не выдаём неизвестную роль за бойца: у гибридных классов это особенно
    -- заметно и даёт ложное представление о составе группы.
    return "|cff8292a3" .. (ROLE_LETTER[role] or "?") .. "|r"
end

-- FontString-разметка атласов удобна внутри таблиц, но пустые места группы
-- раньше рисовались символом «○», которого нет в некоторых WoW-шрифтах —
-- вместо него игрок видел квадрат. В шапке используем настоящие Texture.
function UI.SetRoleTexture(texture, role)
    if not texture then return false end
    local atlas = ROLE_ATLAS[role]
    if atlas and texture.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        texture:SetAtlas(atlas, false)
        texture:SetTexCoord(0, 1, 0, 1)
        return true
    end
    local coords = ROLE_FALLBACK_COORDS[role]
    if coords then
        texture:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
        texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        return true
    end
    texture:SetTexture(nil)
    return false
end

function UI.ClassColor(classFilename)
    local color = classFilename and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFilename]
    if color then return color.r, color.g, color.b end
    return C.text[1], C.text[2], C.text[3]
end

function UI.ClassColorCode(classFilename)
    local color = classFilename and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFilename]
    return color and color.colorStr or "ffe6ecf5"
end

---------------------------------------------------------------------------
-- Кнопка
---------------------------------------------------------------------------

-- Кнопки повторяют язык панелей действий DandersFrames: тёмная заливка и
-- тонкая яркая бирюзовая обводка вместо залитого прямоугольника. Состояние
-- читается по яркости контура, а не по смене цвета фона.
local function ButtonVisual(button)
    local enabled = button:IsEnabled()
    local hovered = button.hovered and enabled
    if not enabled then
        button:SetBackdropColor(.055, .066, .080, .95)
        button:SetBackdropBorderColor(.16, .20, .23, .8)
        button.label:SetTextColor(.36, .40, .45, 1)
    elseif button.primary then
        button:SetBackdropColor(hovered and .055 or .035, hovered and .135 or .100, hovered and .150 or .115, 1)
        button:SetBackdropBorderColor(C.edge[1], C.edge[2], C.edge[3], hovered and 1 or .92)
        button.label:SetTextColor(hovered and 1 or .88, 1, 1, 1)
    else
        button:SetBackdropColor(hovered and .062 or .040, hovered and .085 or .052, hovered and .098 or .064, 1)
        button:SetBackdropBorderColor(C.edge[1], C.edge[2], C.edge[3], hovered and .95 or .55)
        button.label:SetTextColor(hovered and .94 or .78, hovered and .98 or .86, hovered and 1 or .90, 1)
    end
end

function UI.Button(parent, label, width, height, primary)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width or 96, height or 26)
    UI.Backdrop(button, C.raised, C.line)
    button.primary = primary and true or false
    button.label = UI.Text(button, "GameFontNormalSmall", label)
    button.label:SetPoint("CENTER", 0, 0)
    button:SetFontString(button.label)
    button:SetScript("OnEnter", function(self) self.hovered = true; ButtonVisual(self) end)
    button:SetScript("OnLeave", function(self) self.hovered = false; ButtonVisual(self) end)
    button:SetScript("OnEnable", ButtonVisual)
    button:SetScript("OnDisable", ButtonVisual)
    button:SetScript("OnMouseDown", function(self) if self:IsEnabled() then self.label:SetPoint("CENTER", 0, -1) end end)
    button:SetScript("OnMouseUp", function(self) self.label:SetPoint("CENTER", 0, 0) end)
    ButtonVisual(button)
    return button
end

function UI.CloseButton(parent)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(24, 24)
    UI.Backdrop(button, { .10, .12, .15, 0 }, { .10, .12, .15, 0 })
    local glyph = UI.Text(button, "GameFontNormalLarge", "×", C.muted)
    glyph:SetAllPoints(button)
    glyph:SetJustifyH("CENTER")
    glyph:SetJustifyV("MIDDLE")
    button:SetScript("OnEnter", function(self)
        self:SetBackdropColor(.42, .14, .16, .9); self:SetBackdropBorderColor(.72, .24, .26, 1)
        glyph:SetTextColor(1, .88, .88, 1)
    end)
    button:SetScript("OnLeave", function(self)
        self:SetBackdropColor(.10, .12, .15, 0); self:SetBackdropBorderColor(.10, .12, .15, 0)
        glyph:SetTextColor(Unpack(C.muted))
    end)
    return button
end

---------------------------------------------------------------------------
-- Флажок
---------------------------------------------------------------------------

local function CheckVisual(check)
    local hovered = check.hovered
    local checked = check:GetChecked() and true or false
    check.markA:SetShown(checked)
    check.markB:SetShown(checked)
    check.box:SetBackdropColor(
        checked and .035 or (hovered and .10 or .055),
        checked and .17 or (hovered and .14 or .075),
        checked and .22 or (hovered and .19 or .100), 1)
    check.box:SetBackdropBorderColor(
        checked and .10 or (hovered and .28 or .20),
        checked and .78 or (hovered and .34 or .26),
        checked and 1.00 or (hovered and .43 or .33), 1)
    check.label:SetTextColor(
        checked and C.text[1] or (hovered and .78 or .62),
        checked and C.text[2] or (hovered and .83 or .68),
        checked and C.text[3] or (hovered and .89 or .75), 1)
end

function UI.CheckBox(parent, label, checked, onToggle)
    local check = CreateFrame("CheckButton", nil, parent)
    check:SetSize(200, 22)
    check:SetHitRectInsets(0, 0, 0, 0)

    local box = CreateFrame("Frame", nil, check, "BackdropTemplate")
    box:SetSize(16, 16); box:SetPoint("LEFT", 0, 0)
    UI.Backdrop(box, C.field, C.line)
    check.box = box

    -- Рисуем галочку двумя линиями прямо внутри box. Так она не зависит от
    -- Blizzard-текстуры и не оказывается под дочерним Frame.
    local markA = box:CreateLine(nil, "OVERLAY", nil, 7)
    markA:SetThickness(2.4)
    markA:SetColorTexture(.20, .90, 1, 1)
    markA:SetStartPoint("BOTTOMLEFT", box, 3, 8)
    markA:SetEndPoint("BOTTOMLEFT", box, 7, 4)
    markA:Hide()
    check.markA = markA

    local markB = box:CreateLine(nil, "OVERLAY", nil, 7)
    markB:SetThickness(2.4)
    markB:SetColorTexture(.20, .90, 1, 1)
    markB:SetStartPoint("BOTTOMLEFT", box, 7, 4)
    markB:SetEndPoint("BOTTOMLEFT", box, 14, 13)
    markB:Hide()
    check.markB = markB

    check.label = UI.Text(check, "GameFontHighlightSmall", label)
    check.label:SetPoint("LEFT", box, "RIGHT", 8, 0)
    check.label:SetPoint("RIGHT", check, "RIGHT", -2, 0)
    check.label:SetJustifyH("LEFT")
    check.label:SetWordWrap(false)

    check:SetChecked(checked and true or false)
    check:SetScript("OnEnter", function(self) self.hovered = true; CheckVisual(self) end)
    check:SetScript("OnLeave", function(self) self.hovered = false; CheckVisual(self) end)
    check:SetScript("OnClick", function(self)
        if SOUNDKIT then PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF) end
        CheckVisual(self)
        if onToggle then onToggle(self:GetChecked() and true or false, self) end
    end)
    hooksecurefunc(check, "SetChecked", CheckVisual)
    CheckVisual(check)
    return check
end

---------------------------------------------------------------------------
-- Числовое поле
---------------------------------------------------------------------------

local function FieldVisual(field)
    local enabled = field:IsEnabled()
    field.frame:SetBackdropColor(Unpack(C.field))
    field.frame:SetBackdropBorderColor(
        not enabled and .12 or (field.focused and .18 or (field.hovered and .26 or .18)),
        not enabled and .15 or (field.focused and .70 or (field.hovered and .33 or .23)),
        not enabled and .19 or (field.focused and .92 or (field.hovered and .42 or .30)), 1)
    field:SetTextColor(enabled and .92 or .40, enabled and .95 or .44, enabled and .99 or .50, 1)
end

function UI.NumberBox(parent, width, height)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(width or 62, height or 22)
    UI.Backdrop(frame, C.field, C.line)

    local field = CreateFrame("EditBox", nil, frame)
    field:SetAllPoints(frame)
    field:SetFontObject("GameFontHighlightSmall")
    field:SetAutoFocus(false)
    field:SetNumeric(true)
    field:SetMaxLetters(4)
    field:SetJustifyH("CENTER")
    field:SetTextInsets(4, 4, 0, 0)
    field.frame = frame

    field:SetScript("OnEnter", function(self) self.hovered = true; FieldVisual(self) end)
    field:SetScript("OnLeave", function(self) self.hovered = false; FieldVisual(self) end)
    field:SetScript("OnEditFocusGained", function(self) self.focused = true; self:HighlightText(); FieldVisual(self) end)
    field:SetScript("OnEditFocusLost", function(self) self.focused = false; self:HighlightText(0, 0); FieldVisual(self) end)
    field:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    field:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    function field:SetFieldEnabled(enabled)
        if enabled then self:Enable() else self:ClearFocus(); self:Disable() end
        frame:SetAlpha(enabled and 1 or .45)
        FieldVisual(self)
    end
    FieldVisual(field)
    return field, frame
end

---------------------------------------------------------------------------
-- Полоса прокрутки
---------------------------------------------------------------------------

function UI.ScrollBar(parent)
    local bar = CreateFrame("Slider", nil, parent, "BackdropTemplate")
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(6)
    UI.Backdrop(bar, { .03, .04, .05, .8 }, { .10, .13, .17, .8 })
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(.22, .40, .52, 1)
    thumb:SetSize(6, 46)
    bar:SetThumbTexture(thumb)
    bar:SetValueStep(1)
    bar:SetObeyStepOnDrag(true)
    bar:SetMinMaxValues(0, 0)
    bar:SetValue(0)
    bar:SetScript("OnEnter", function() thumb:SetColorTexture(Unpack(C.accent)) end)
    bar:SetScript("OnLeave", function() thumb:SetColorTexture(.22, .40, .52, 1) end)
    return bar
end

---------------------------------------------------------------------------
-- Подсказки
---------------------------------------------------------------------------

function UI.Tooltip(owner, title, ...)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, .82, 0)
    for index = 1, select("#", ...) do
        local line = select(index, ...)
        if line then GameTooltip:AddLine(line, .72, .78, .86, true) end
    end
    GameTooltip:Show()
end

function UI.AttachTooltip(frame, title, ...)
    local lines = { ... }
    frame:SetScript("OnEnter", function(self) UI.Tooltip(self, title, unpack(lines)) end)
    frame:SetScript("OnLeave", GameTooltip_Hide)
end

---------------------------------------------------------------------------
-- Вкладки
---------------------------------------------------------------------------

local function TabVisual(tab)
    local active = tab.active
    tab:SetBackdropColor(
        active and .090 or (tab.hovered and .070 or .045),
        active and .140 or (tab.hovered and .092 or .058),
        active and .185 or (tab.hovered and .120 or .076), 1)
    tab:SetBackdropBorderColor(
        active and .18 or .12, active and .58 or .16, active and .78 or .21, 1)
    tab.label:SetTextColor(
        active and C.text[1] or (tab.hovered and .78 or .58),
        active and C.text[2] or (tab.hovered and .83 or .64),
        active and C.text[3] or (tab.hovered and .89 or .71), 1)
    tab.underline:SetShown(active)
end

function UI.Tab(parent, label, width)
    local tab = CreateFrame("Button", nil, parent, "BackdropTemplate")
    tab:SetSize(width or 150, 26)
    UI.Backdrop(tab, C.raised, C.line)
    tab.label = UI.Text(tab, "GameFontNormalSmall", label)
    tab.label:SetPoint("CENTER", 0, 0)
    tab.underline = tab:CreateTexture(nil, "OVERLAY")
    tab.underline:SetColorTexture(Unpack(C.accent))
    tab.underline:SetPoint("BOTTOMLEFT", 1, 1)
    tab.underline:SetPoint("BOTTOMRIGHT", -1, 1)
    tab.underline:SetHeight(2)
    tab:SetScript("OnEnter", function(self) self.hovered = true; TabVisual(self) end)
    tab:SetScript("OnLeave", function(self) self.hovered = false; TabVisual(self) end)
    function tab:SetActive(active)
        self.active = active and true or false
        TabVisual(self)
    end
    tab:SetActive(false)
    return tab
end

---------------------------------------------------------------------------
-- Портреты, полосы и ауры
---------------------------------------------------------------------------

-- Настоящий живой портрет, как в X-Perl 2.4.3. Двумерная текстура остаётся
-- под моделью как запасной вариант для невидимых/ещё не загруженных юнитов.
function UI.Portrait(parent, size, thickness)
    size, thickness = size or 38, math.max(thickness or 2, 1)
    local portrait = {}
    local ring = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    ring:SetSize(size + thickness * 2, size + thickness * 2)
    UI.Backdrop(ring, C.field, C.edge, thickness)

    local face = ring:CreateTexture(nil, "ARTWORK")
    -- XPerl_Portrait_Template из 2.4.3: 50x50 внутри рамки 60x62.
    -- Смещения намеренно несимметричны — это часть старого объёмного канта.
    face:SetPoint("TOPLEFT", 6, -5)
    face:SetPoint("BOTTOMRIGHT", -4, 4)
    face:SetTexCoord(0, 1, 0, 1)
    local model = CreateFrame("PlayerModel", nil, ring)
    -- Геометрия актуального Z-Perl: живая модель заполняет портрет плотнее
    -- двумерной запасной текстуры и не оставляет чёрную круглую «дырку».
    model:SetPoint("TOPLEFT", 3, -3)
    model:SetPoint("BOTTOMRIGHT", -4, 4)
    model:SetFrameLevel(ring:GetFrameLevel() + 1)
    model:EnableMouse(false)
    model:SetScript("OnModelLoaded", function(self)
        -- SetPortraitZoom(1) — тот же путь, которым пользуется современный
        -- Z-Perl. Camera 0 в Midnight у некоторых обликов показывает всё тело.
        pcall(self.SetPortraitZoom, self, 1)
    end)
    portrait.ring, portrait.face, portrait.model = ring, face, model

    function portrait:SetUnit(unit)
        self.face:SetVertexColor(1, 1, 1, 1)
        local exists = unit and UnitExists(unit)
        local missing = type(exists) == "boolean" and not issecretvalue(exists) and not exists
        local textureOK = false
        if unit and not missing and type(SetPortraitTexture) == "function" then
            textureOK = pcall(SetPortraitTexture, self.face, unit)
        end
        if not textureOK or not self.face:GetTexture() then
            self.face:SetTexture(WHITE)
            self.face:SetVertexColor(.09, .11, .14, 1)
        end

        if unit and not missing then
            pcall(self.model.ClearModel, self.model)
            local modelOK = pcall(self.model.SetUnit, self.model, unit)
            if modelOK then
                pcall(self.model.SetPortraitZoom, self.model, 1)
                -- 2D SetPortraitTexture имеет круглую альфа-маску. Она должна
                -- быть видна только как fallback, а не просвечивать под 3D.
                self.face:Hide()
                self.model:Show()
            else
                self.model:Hide()
                self.face:Show()
            end
        else
            pcall(self.model.ClearModel, self.model)
            self.model:Hide()
            self.face:Show()
        end
    end

    function portrait:SetStateAlpha(alpha)
        self.ring:SetBackdropBorderColor(.50, .50, .50, alpha or 1)
        self.ring:SetAlpha(math.max(alpha or 1, .55))
    end
    return portrait
end

function UI.StatusBar(parent, height, color)
    local holder = UI.Panel(parent, { .02, .03, .04, .72 }, C.line)
    holder:SetHeight(height or 12)
    local bar = CreateFrame("StatusBar", nil, holder)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("BOTTOMRIGHT", -1, 1)
    bar:SetStatusBarTexture(WHITE)
    bar:SetStatusBarColor(Unpack(color or C.accent))
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    local void = bar:CreateTexture(nil, "BACKGROUND")
    void:SetAllPoints()
    void:SetColorTexture(.02, .03, .04, .76)
    bar.holder = holder
    return bar, holder
end

function UI.AuraIcon(parent, size)
    size = size or 24
    local icon = CreateFrame("Button", nil, parent, "BackdropTemplate")
    icon:SetSize(size, size)
    icon:EnableMouse(true)
    icon:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    UI.Backdrop(icon, { .02, .03, .04, .35 }, C.line, 1)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetPoint("TOPLEFT", 1, -1)
    icon.texture:SetPoint("BOTTOMRIGHT", -1, 1)
    icon.texture:SetTexCoord(.08, .92, .08, .92)
    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cooldown:SetAllPoints(icon.texture)
    icon.cooldown:SetDrawEdge(false)
    icon.cooldown:SetHideCountdownNumbers(true)
    local overlay = CreateFrame("Frame", nil, icon)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(icon.cooldown:GetFrameLevel() + 1)
    icon.count = UI.Text(overlay, "NumberFontNormalSmall", "")
    icon.count:SetPoint("BOTTOMRIGHT", -1, 1)
    icon.timer = UI.Text(overlay, "NumberFontNormalSmall", "", C.amber)
    icon.timer:SetPoint("TOPLEFT", 1, -1)
    icon.dispel = CreateFrame("Frame", nil, icon, "BackdropTemplate")
    icon.dispel:SetPoint("TOPLEFT", -2, 2)
    icon.dispel:SetPoint("BOTTOMRIGHT", 2, -2)
    UI.Backdrop(icon.dispel, { 0, 0, 0, 0 }, C.edge, 2)
    icon.dispel:Hide()
    return icon
end
