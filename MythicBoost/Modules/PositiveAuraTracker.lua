local _, JP = ...

local L = JP.L
local UI, C = JP.UI, JP.UI.colors
local PositiveAuraTracker = {}
local Settings

local DEFAULTS = {
    enabled = false,
    spellIDs = {},
    showWhenMissing = false,
    showSeconds = true,
    showStacks = true,
    showIcon = true,
    barHeight = 190,
    barWidth = 72,
    sideGap = 110,
    barSpacing = 12,
    colorPreset = 2,
    texturePreset = 1,
    fontSize = 24,
    pulse = true,
    pulseSpeed = .8,
    maxIcons = 8,
    iconOverride = nil,
    x = 0,
    y = -20,
    unlocked = false,
}

local WING_TEXTURE = "Interface\\AddOns\\MythicBoost\\Media\\AuraWingMask"
local LUNAR_TEXTURE = "Interface\\AddOns\\MythicBoost\\Media\\AuraLunarMask"
local TEXTURE_PRESETS = {
    { WING_TEXTURE, L("Крыло") },
    { LUNAR_TEXTURE, L("Вихрь") },
}
local COLOR_PRESETS = {
    { 1.00, .78, .20, L("Золото") },
    { .20, .82, 1.00, L("Лёд") },
    { .32, 1.00, .48, L("Природа") },
    { .72, .34, 1.00, L("Тайная магия") },
    { 1.00, .30, .18, L("Огонь") },
    { 1.00, 1.00, 1.00, L("Свет") },
}

function PositiveAuraTracker:GetColorName(index)
    local preset = COLOR_PRESETS[tonumber(index) or 2] or COLOR_PRESETS[2]
    return preset[4]
end

function PositiveAuraTracker:GetBarTexture()
    local settings = Settings()
    local preset = TEXTURE_PRESETS[tonumber(settings.texturePreset) or 1] or TEXTURE_PRESETS[1]
    return settings.barTexture or preset[1]
end

function PositiveAuraTracker:GetTextureName(index)
    local preset = TEXTURE_PRESETS[tonumber(index) or 1] or TEXTURE_PRESETS[1]
    return preset[2]
end

function PositiveAuraTracker:SetTexturePreset(index)
    local settings = Settings()
    settings.texturePreset = math.max(1, math.min(#TEXTURE_PRESETS, tonumber(index) or 1))
    settings.barTexture = nil
    self:ApplySettings()
    self:Refresh()
end

Settings = function()
    local settings = JP.Settings("positiveAuraTracker", DEFAULTS)
    settings.spellIDs = type(settings.spellIDs) == "table" and settings.spellIDs or {}
    return settings
end

local function SpellInfo(identifier)
    if not C_Spell or type(C_Spell.GetSpellInfo) ~= "function" then return end
    local ok, info = pcall(C_Spell.GetSpellInfo, identifier)
    if not ok or type(info) ~= "table" then return end
    local spellID = UI.SafeNumber(info.spellID)
    local name = UI.SafeString(info.name)
    local iconID = UI.SafeNumber(info.iconID) or UI.SafeNumber(info.originalIconID)
    if not spellID or not name then return end
    return spellID, name, iconID
end

local function Trim(value)
    return type(value) == "string" and value:match("^%s*(.-)%s*$") or ""
end

-- Accept one spell link, an ID, an exact localized name, or a comma/newline
-- separated list. Whitespace-separated IDs are also convenient for pasting.
function PositiveAuraTracker:ResolveInput(text)
    text = Trim(text)
    local resolved, rejected, seen = {}, {}, {}
    if text == "" then return resolved, rejected end

    local parts = {}
    for part in text:gmatch("[^,;\r\n]+") do parts[#parts + 1] = Trim(part) end
    if #parts == 1 and parts[1]:match("^%d+[%s%d]+$") then
        parts = {}
        for id in text:gmatch("%d+") do parts[#parts + 1] = id end
    end

    for _, part in ipairs(parts) do
        local linkID = part:match("|Hspell:(%d+)")
        local identifier = tonumber(linkID or part) or part
        local spellID, name, iconID = SpellInfo(identifier)
        if spellID and not seen[spellID] then
            seen[spellID] = true
            resolved[#resolved + 1] = { spellID = spellID, name = name, iconID = iconID }
        elseif not spellID then
            rejected[#rejected + 1] = part
        end
    end
    return resolved, rejected
end

function PositiveAuraTracker:AddFromInput(text)
    local resolved, rejected = self:ResolveInput(text)
    local settings = Settings()
    local existing = {}
    for _, spellID in ipairs(settings.spellIDs) do
        if UI.UsableNumber(spellID) then existing[spellID] = true end
    end
    local added = 0
    for _, spell in ipairs(resolved) do
        if #settings.spellIDs >= 24 then break end
        if not existing[spell.spellID] then
            settings.spellIDs[#settings.spellIDs + 1] = spell.spellID
            existing[spell.spellID] = true
            added = added + 1
        end
    end
    self:ApplySettings()
    return added, rejected
end

function PositiveAuraTracker:ClearSpells()
    wipe(Settings().spellIDs)
    self:ApplySettings()
end

function PositiveAuraTracker:ResolveBarTexture(text)
    text = Trim(text)
    if text == "" then return nil, true end
    local fileID = text:match("^[Ff][Ii][Ll][Ee]:%s*(%d+)$")
    if fileID then return tonumber(fileID), true end
    if text:match("^%d+$") then return tonumber(text), true end
    if text:find("Interface", 1, true) then
        return text:gsub("/", "\\"), true
    end
    local linkID = text:match("|Hspell:(%d+)")
    local _, _, iconID = SpellInfo(tonumber(linkID or text) or text)
    return iconID, iconID ~= nil
end

function PositiveAuraTracker:SetBarTexture(texture)
    if type(texture) ~= "number" and type(texture) ~= "string" then texture = nil end
    Settings().barTexture = texture
    self:ApplySettings()
    self:Refresh()
end

local function CreateIcon(parent)
    local button = CreateFrame("Frame", nil, parent)
    button.back = button:CreateTexture(nil, "BACKGROUND")
    button.back:SetAllPoints()
    button.back:SetTexture(WING_TEXTURE)
    button.back:SetBlendMode("ADD")
    button.back:SetAlpha(.16)

    button.fill = button:CreateTexture(nil, "ARTWORK")
    button.fill:SetTexture(WING_TEXTURE)
    button.fill:SetBlendMode("ADD")

    button.glow = button:CreateTexture(nil, "OVERLAY")
    button.glow:SetAllPoints()
    button.glow:SetTexture(WING_TEXTURE)
    button.glow:SetBlendMode("ADD")
    button.glow:SetAlpha(.18)

    button.texture = button:CreateTexture(nil, "OVERLAY")
    button.texture:SetSize(28, 28)
    button.texture:SetTexCoord(.07, .93, .07, .93)
    button.texture:Hide()

    button.textureBorder = button:CreateTexture(nil, "ARTWORK")
    button.textureBorder:SetColorTexture(0, 0, 0, .9)
    button.textureBorder:SetSize(32, 32)
    button.textureBorder:Hide()

    button.seconds = UI.Text(button, "GameFontNormalLarge", "", C.text)
    button.seconds:SetPoint("CENTER", 0, 0)
    button.seconds:SetShadowColor(0, 0, 0, 1)
    button.seconds:SetShadowOffset(1, -1)
    button.stacks = UI.Text(button, "GameFontNormalSmall", "", C.text)
    button.stacks:SetPoint("BOTTOM", button.texture, "TOP", 0, 1)
    button:Hide()
    return button
end

function PositiveAuraTracker:Create()
    if self.frame then return end
    local frame = CreateFrame("Frame", "MythicBoostPositiveAuraTracker", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(owner)
        if Settings().unlocked then owner:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(owner)
        owner:StopMovingOrSizing()
        local x, y = owner:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if UI.UsableNumber(x) and UI.UsableNumber(y) and UI.UsableNumber(ux) and UI.UsableNumber(uy) then
            Settings().x, Settings().y = x - ux, y - uy
        end
    end)

    frame.move = UI.Panel(frame, { .05, .07, .09, .92 }, C.edge)
    frame.move:SetSize(190, 32)
    frame.move:SetPoint("CENTER")
    frame.moveText = UI.Text(frame.move, "GameFontNormalSmall", L("ПЕРЕТАЩИ ТРЕКЕР БАФОВ"), C.amber)
    frame.moveText:SetPoint("CENTER")
    frame.move:Hide()

    frame.icons = {}
    for index = 1, 8 do frame.icons[index] = CreateIcon(frame) end
    frame:SetScript("OnUpdate", function(_, elapsed)
        self.elapsed = (self.elapsed or 0) + elapsed
        if self.elapsed >= .10 then self.elapsed = 0; self:UpdateTimers() end
    end)
    self.frame = frame

    self.events = CreateFrame("Frame")
    self.events:SetScript("OnEvent", function(_, event, unit)
        if event ~= "UNIT_AURA" or unit == "player" then self:Refresh() end
    end)
    self.events:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.events:RegisterEvent("PLAYER_REGEN_ENABLED")
    self.events:RegisterUnitEvent("UNIT_AURA", "player")
end

function PositiveAuraTracker:SetUnlocked(value)
    local settings = Settings()
    settings.unlocked = value == true
    if not self.frame then return end
    self.frame:EnableMouse(settings.unlocked)
    self.frame.move:SetShown(settings.unlocked)
    self:Refresh()
end

function PositiveAuraTracker:ApplySettings()
    if not self.frame then return end
    local settings = Settings()
    settings.barHeight = math.max(100, math.min(300, tonumber(settings.barHeight) or 190))
    settings.barWidth = math.max(36, math.min(120, tonumber(settings.barWidth) or 72))
    settings.sideGap = math.max(40, math.min(240, tonumber(settings.sideGap) or 110))
    settings.barSpacing = math.max(0, math.min(40, tonumber(settings.barSpacing) or 12))
    settings.colorPreset = math.max(1, math.min(#COLOR_PRESETS, tonumber(settings.colorPreset) or 2))
    settings.texturePreset = math.max(1, math.min(#TEXTURE_PRESETS, tonumber(settings.texturePreset) or 1))
    settings.fontSize = math.max(12, math.min(48, tonumber(settings.fontSize) or 24))
    settings.pulseSpeed = math.max(.3, math.min(2, tonumber(settings.pulseSpeed) or .8))
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", UIParent, "CENTER", tonumber(settings.x) or 0, tonumber(settings.y) or -20)
    -- Only the small central handle captures the mouse in layout mode. The
    -- decorative bars may extend outside the parent without creating an
    -- invisible screen-wide click blocker.
    self.frame:SetSize(190, 32)
    local preset = COLOR_PRESETS[settings.colorPreset]
    local barTexture = self:GetBarTexture()
    for index, icon in ipairs(self.frame.icons) do
        local slot = math.ceil(index / 2)
        local right = index % 2 == 0
        local distance = settings.sideGap + settings.barWidth / 2
            + (slot - 1) * (settings.barWidth + settings.barSpacing)
        icon:ClearAllPoints()
        icon:SetSize(settings.barWidth, settings.barHeight)
        icon:SetPoint("CENTER", self.frame, "CENTER", right and distance or -distance, 0)
        icon.rightSide = right
        icon.back:SetTexture(barTexture)
        icon.fill:SetTexture(barTexture)
        icon.glow:SetTexture(barTexture)
        local leftCoord, rightCoord = right and 1 or 0, right and 0 or 1
        icon.back:SetTexCoord(leftCoord, rightCoord, 0, 1)
        icon.glow:SetTexCoord(leftCoord, rightCoord, 0, 1)
        icon.fill:SetVertexColor(preset[1], preset[2], preset[3], 1)
        icon.glow:SetVertexColor(preset[1], preset[2], preset[3], 1)
        icon.texture:ClearAllPoints()
        icon.texture:SetPoint("BOTTOM", icon, "BOTTOM", right and -8 or 8, 12)
        icon.textureBorder:ClearAllPoints()
        icon.textureBorder:SetPoint("CENTER", icon.texture)
        icon.seconds:ClearAllPoints()
        icon.seconds:SetPoint("CENTER", icon, "CENTER", right and -8 or 8, 0)
        icon.seconds:SetFont("Fonts\\FRIZQT__.TTF", settings.fontSize, "OUTLINE")
    end
    self:SetUnlocked(settings.unlocked or MythicBoostDB.interfaceUnlocked == true)
end

function PositiveAuraTracker:UpdateTimers()
    if not self.frame or not self.frame:IsShown() then return end
    local settings, now = Settings(), GetTime()
    local expired
    local pulseAlpha, glowAlpha = 1, .18
    if settings.pulse ~= false then
        local phase = (now % settings.pulseSpeed) / settings.pulseSpeed
        local wave = .5 + .5 * math.cos(phase * math.pi * 2)
        pulseAlpha = .68 + .32 * wave
        glowAlpha = .12 + .22 * wave
    end
    for _, icon in ipairs(self.frame.icons) do
        if icon:IsShown() then
            icon.fill:SetAlpha(pulseAlpha)
            icon.glow:SetAlpha(glowAlpha)
            local progress, remaining = 1, nil
            if icon.expiration and icon.duration and icon.duration > 0 then
                remaining = math.max(0, icon.expiration - now)
                progress = math.max(0, math.min(1, remaining / icon.duration))
                if remaining <= 0 then expired = true end
            end
            local height = math.max(1, settings.barHeight * progress)
            icon.fill:ClearAllPoints()
            icon.fill:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 0, 0)
            icon.fill:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
            icon.fill:SetHeight(height)
            local top = 1 - progress
            icon.fill:SetTexCoord(icon.rightSide and 1 or 0, icon.rightSide and 0 or 1, top, 1)
            if icon.missing then
                icon.seconds:SetText(icon.missingCount and icon.missingCount > 1
                    and ("! " .. icon.missingCount) or "!")
            elseif settings.showSeconds and remaining then
                icon.seconds:SetText(remaining >= 60 and math.ceil(remaining / 60) .. L("м") or tostring(math.ceil(remaining)))
            else
                icon.seconds:SetText("")
            end
        end
    end
    if expired then self:Refresh() end
end

function PositiveAuraTracker:Refresh()
    if not self.frame then return end
    local settings = Settings()
    for _, icon in ipairs(self.frame.icons) do
        icon:Hide(); icon.expiration = nil; icon.duration = nil
        icon.missing = nil; icon.missingCount = nil
        icon.seconds:SetText(""); icon.stacks:SetText("")
    end
    if settings.enabled ~= true or #settings.spellIDs == 0 then
        self.frame:SetShown(settings.unlocked == true)
        return
    end

    local visible, missing = 0, {}
    for _, spellID in ipairs(settings.spellIDs) do
        if visible >= math.min(8, tonumber(settings.maxIcons) or 8) then break end
        if UI.UsableNumber(spellID) then
            local aura, blocked = UI.SafeUnitAura("player", spellID)
            if not blocked then
                local _, spellName, spellTexture = SpellInfo(spellID)
                if settings.showWhenMissing and aura == nil then
                    missing[#missing + 1] = { spellID, spellName, spellTexture }
                elseif not settings.showWhenMissing and aura ~= nil then
                    visible = visible + 1
                    local icon = self.frame.icons[visible]
                    local auraTexture = aura and UI.SafeNumber(aura.icon)
                    icon.texture:SetTexture(settings.iconOverride or auraTexture or spellTexture or 134400)
                    icon.texture:SetShown(settings.showIcon ~= false)
                    icon.textureBorder:SetShown(settings.showIcon ~= false)
                    icon.spellID, icon.spellName = spellID, spellName
                    local duration = aura and UI.SafeNumber(aura.duration)
                    local expiration = aura and UI.SafeNumber(aura.expirationTime)
                    icon.duration, icon.expiration = duration, expiration
                    if settings.showStacks and aura then
                        local count = UI.SafeNumber(aura.applications)
                        icon.stacks:SetText(count and count > 1 and tostring(count) or "")
                    end
                    icon:Show()
                end
            end
        end
    end
    -- Missing mode is an aggregate check, not one identical full-size wing per
    -- absent spell. The count still communicates that several configured buffs
    -- are absent, while the optional game icon identifies the first one.
    if settings.showWhenMissing and #missing > 0 then
        visible = 1
        local icon, entry = self.frame.icons[1], missing[1]
        icon.texture:SetTexture(settings.iconOverride or entry[3] or 134400)
        icon.texture:SetShown(settings.showIcon ~= false)
        icon.textureBorder:SetShown(settings.showIcon ~= false)
        icon.spellID, icon.spellName = entry[1], entry[2]
        icon.missing, icon.missingCount = true, #missing
        icon:Show()
    end
    self.frame:SetShown(visible > 0 or settings.unlocked == true)
    self:UpdateTimers()
end

function PositiveAuraTracker:GetSpellSummary()
    local names = {}
    local spellIDs = Settings().spellIDs
    for index, spellID in ipairs(spellIDs) do
        if index > 6 then break end
        local _, name = SpellInfo(spellID)
        names[#names + 1] = name and (name .. " (" .. spellID .. ")") or tostring(spellID)
    end
    if #spellIDs > #names then names[#names + 1] = (L("ещё %d")):format(#spellIDs - #names) end
    return #names > 0 and table.concat(names, ", ") or L("Список пуст")
end

function PositiveAuraTracker:Enable()
    if not self.frame then self:Create() end
    self:ApplySettings()
    self:Refresh()
end

function PositiveAuraTracker:Disable()
    if self.frame then self.frame:Hide() end
    if self.events then self.events:UnregisterAllEvents() end
end

function PositiveAuraTracker:Destroy() self:Disable() end

JP.PositiveAuraTracker = PositiveAuraTracker
JP:RegisterModule("PositiveAuraTracker", PositiveAuraTracker)
