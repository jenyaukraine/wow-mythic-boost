local _, JP = ...
local ApplicantHighlighter = {}
local UI = JP.UI
local C = UI.colors

local TARGET = { TANK = 1, HEALER = 1, DAMAGER = 3 }
local REFRESH_INTERVAL = 1
local selected = {}

local function UsableNumber(value)
    return type(value) == "number" and not issecretvalue(value)
end

local function PlayerRole(unit)
    local role = UnitGroupRolesAssigned(unit)
    if role == "TANK" or role == "HEALER" or role == "DAMAGER" then return role end
    if unit == "player" then
        local spec = GetSpecialization and GetSpecialization()
        role = spec and GetSpecializationRole(spec)
        if role == "TANK" or role == "HEALER" or role == "DAMAGER" then return role end
    end
    return "DAMAGER"
end

local function MissingRoles()
    local current = { TANK = 0, HEALER = 0, DAMAGER = 0 }
    for _, unit in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
        if UnitExists(unit) then
            local role = PlayerRole(unit)
            current[role] = current[role] + 1
        end
    end
    return {
        TANK = math.max(0, TARGET.TANK - current.TANK),
        HEALER = math.max(0, TARGET.HEALER - current.HEALER),
        DAMAGER = math.max(0, TARGET.DAMAGER - current.DAMAGER),
    }
end

local function AddForRole(byRole, role, applicantID, memberIdx, itemLevel)
    if role ~= "TANK" and role ~= "HEALER" and role ~= "DAMAGER" then return end
    byRole[role][#byRole[role] + 1] = { applicantID = applicantID, memberIdx = memberIdx, itemLevel = itemLevel }
end

local function BuildSelection()
    wipe(selected)
    local missing = MissingRoles()
    local byRole = { TANK = {}, HEALER = {}, DAMAGER = {} }

    for _, applicantID in ipairs(C_LFGList.GetApplicants() or {}) do
        local applicant = C_LFGList.GetApplicantInfo(applicantID)
        if applicant and applicant.applicationStatus == "applied" then
            for memberIdx = 1, (applicant.numMembers or 0) do
                local _, _, _, _, itemLevel, _, tank, healer, damage, assignedRole = C_LFGList.GetApplicantMemberInfo(applicantID, memberIdx)
                if UsableNumber(itemLevel) then
                    if assignedRole == "TANK" or assignedRole == "HEALER" or assignedRole == "DAMAGER" then
                        AddForRole(byRole, assignedRole, applicantID, memberIdx, itemLevel)
                    else
                        if tank then AddForRole(byRole, "TANK", applicantID, memberIdx, itemLevel) end
                        if healer then AddForRole(byRole, "HEALER", applicantID, memberIdx, itemLevel) end
                        if damage then AddForRole(byRole, "DAMAGER", applicantID, memberIdx, itemLevel) end
                    end
                end
            end
        end
    end

    for role, candidates in pairs(byRole) do
        table.sort(candidates, function(a, b) return a.itemLevel > b.itemLevel end)
        for index = 1, math.min(missing[role], #candidates) do
            local candidate = candidates[index]
            local key = candidate.applicantID .. ":" .. candidate.memberIdx
            if index == 1 then
                selected[key] = "best"
            elseif selected[key] ~= "best" then
                selected[key] = "needed"
            end
        end
    end
end

---------------------------------------------------------------------------
-- Оформление списка кандидатов
--
-- Штатная панель нарисована в золотой теме Blizzard, и наша подсветка
-- смотрелась на ней чужеродно: рамка в три пикселя со всех сторон плюс
-- заливка поверх. Приводим панель к языку окна аддона — тёмный фон, тонкие
-- линии, акцент слева у выделенной строки.
--
-- Трогаем только текстуры и цвета. Кнопки «Пригласить» и «Отклонить» и любые
-- защищённые действия не затрагиваются: их поведение остаётся близзардовским.
---------------------------------------------------------------------------

local STATUS_COLORS = {
    best = { color = C.amber, label = "ЛУЧШИЙ" },
    needed = { color = { .62, .40, .95, 1 }, label = "ПОДХОДИТ" },
}

local function HideRegion(region)
    if region and region.SetAlpha then region:SetAlpha(0) end
end

-- Цветная полоса слева вместо рамки по периметру: читается так же ясно,
-- но не спорит с сеткой строк.
local function EnsureAccent(frame)
    if frame.__mbAccent then return frame.__mbAccent end
    local accent = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    accent:SetPoint("TOPLEFT", 0, -1)
    accent:SetPoint("BOTTOMLEFT", 0, 1)
    accent:SetWidth(3)
    frame.__mbAccent = accent
    return accent
end

local function EnsureFill(frame)
    if frame.__mbFill then return frame.__mbFill end
    local fill = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    fill:SetPoint("TOPLEFT", 0, -1)
    fill:SetPoint("BOTTOMRIGHT", 0, 1)
    frame.__mbFill = fill
    return fill
end

local function EnsureLabel(frame)
    if frame.__mbApplicantLabel then return frame.__mbApplicantLabel end
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
    label:SetJustifyH("RIGHT")
    label:SetShadowColor(0, 0, 0, 1)
    label:SetShadowOffset(1, -1)
    frame.__mbApplicantLabel = label
    return label
end

local function ColorMember(frame, status)
    local accent, fill, label = EnsureAccent(frame), EnsureFill(frame), EnsureLabel(frame)
    local style = status and STATUS_COLORS[status]
    if not style then
        accent:Hide(); fill:Hide(); label:Hide()
        return
    end
    local r, g, b = style.color[1], style.color[2], style.color[3]
    accent:SetColorTexture(r, g, b, 1); accent:Show()
    fill:SetColorTexture(r, g, b, .10); fill:Show()
    label:SetText(("|cff%02x%02x%02x%s|r"):format(
        math.floor(r * 255 + .5), math.floor(g * 255 + .5), math.floor(b * 255 + .5), style.label))
    label:Show()
end

-- Панель перекрашивается один раз: фон, врезка и заголовки колонок.
local function SkinPanel(viewer)
    if viewer.__mbSkinned then return end
    viewer.__mbSkinned = true

    local inset = viewer.Inset
    if inset then
        if inset.Bg and inset.Bg.SetColorTexture then inset.Bg:SetColorTexture(UI.Unpack(C.panel)) end
        if inset.NineSlice then HideRegion(inset.NineSlice) end
    end

    for _, key in ipairs({ "NameColumnHeader", "RoleColumnHeader", "ItemLevelColumnHeader", "RatingColumnHeader" }) do
        local header = viewer[key]
        if header then
            for index = 1, select("#", header:GetRegions()) do
                local region = select(index, header:GetRegions())
                if region and region.GetObjectType then
                    if region:GetObjectType() == "Texture" then
                        HideRegion(region)
                    elseif region:GetObjectType() == "FontString" then
                        region:SetTextColor(UI.Unpack(C.muted))
                    end
                end
            end
        end
    end
end

-- Строка кандидата: тёмная подложка с чередованием и тонкий разделитель.
local function SkinRow(button, index)
    if not button.__mbRowBg then
        local background = button:CreateTexture(nil, "BACKGROUND", nil, 1)
        background:SetAllPoints(button)
        button.__mbRowBg = background

        local separator = button:CreateTexture(nil, "BORDER")
        separator:SetPoint("BOTTOMLEFT", 0, 0)
        separator:SetPoint("BOTTOMRIGHT", 0, 0)
        separator:SetHeight(1)
        separator:SetColorTexture(UI.Unpack(C.lineSoft))
        button.__mbRowLine = separator

        -- Штатная подложка строки нарисована под золотую тему.
        for regionIndex = 1, select("#", button:GetRegions()) do
            local region = select(regionIndex, button:GetRegions())
            if region and region.GetObjectType and region:GetObjectType() == "Texture"
                and region ~= background and region ~= separator then
                local _, _, _, alpha = region:GetVertexColor()
                if alpha and alpha > 0 and not region:GetTexture() then HideRegion(region) end
            end
        end
    end
    local tone = index % 2 == 0 and C.rowAlt or C.row
    button.__mbRowBg:SetColorTexture(UI.Unpack(tone))
end

local function ApplicantIDForButton(button)
    if button.applicantID then return button.applicantID end
    if button.GetElementData then
        local data = button:GetElementData()
        if type(data) == "table" then return data.applicantID end
    end
end

function ApplicantHighlighter:Refresh()
    local viewer = LFGListFrame and LFGListFrame.ApplicationViewer
    local scrollBox = viewer and viewer.ScrollBox
    if not scrollBox or not viewer:IsVisible() then return end
    BuildSelection()
    SkinPanel(viewer)
    local rowIndex = 0
    scrollBox:ForEachFrame(function(button)
        rowIndex = rowIndex + 1
        SkinRow(button, rowIndex)
        local applicantID = ApplicantIDForButton(button)
        for index, member in pairs(button.Members or {}) do
            local memberIdx = member.memberIdx or member.MemberIdx or index
            local status = applicantID and selected[applicantID .. ":" .. memberIdx]
            ColorMember(member, status)
        end
    end)
end

-- События списка кандидатов приходят пачками, а кадры переиспользуются:
-- одна отложенная перерисовка вместо трёх таймеров на каждое событие.
function ApplicantHighlighter:QueueRefresh()
    if self.refreshQueued then return end
    self.refreshQueued = true
    C_Timer.After(.1, function()
        self.refreshQueued = false
        self:Refresh()
    end)
end

function ApplicantHighlighter:Create()
    if self.created then return end

    local function Install()
        local viewer = LFGListFrame and LFGListFrame.ApplicationViewer
        local scrollBox = viewer and viewer.ScrollBox
        if not scrollBox or self.created then return end
        self.created = true

        -- ScrollBoxUtil приходит от Raider.IO, а не от Blizzard. Без него
        -- обходимся периодическим обновлением, вместо падения модуля.
        if ScrollBoxUtil and type(ScrollBoxUtil.OnViewFramesChanged) == "function" then
            pcall(ScrollBoxUtil.OnViewFramesChanged, ScrollBoxUtil, scrollBox, function() self:QueueRefresh() end)
        end

        viewer:HookScript("OnShow", function() self:QueueRefresh() end)
        viewer:HookScript("OnUpdate", function(_, elapsed)
            self.refreshElapsed = (self.refreshElapsed or 0) + elapsed
            if self.refreshElapsed >= REFRESH_INTERVAL then
                self.refreshElapsed = 0
                self:Refresh()
            end
        end)

        self.events = CreateFrame("Frame")
        for _, event in ipairs({ "LFG_LIST_APPLICANT_LIST_UPDATED", "LFG_LIST_APPLICANT_UPDATED", "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED" }) do
            self.events:RegisterEvent(event)
        end
        self.events:SetScript("OnEvent", function() self:QueueRefresh() end)
        self:QueueRefresh()
    end

    Install()
    if not self.created then
        self.loader = CreateFrame("Frame")
        self.loader:RegisterEvent("ADDON_LOADED")
        self.loader:SetScript("OnEvent", function(_, _, name)
            if name == "Blizzard_GroupFinder" then Install() end
        end)
    end
end

function ApplicantHighlighter:Enable() end
function ApplicantHighlighter:Disable() end
function ApplicantHighlighter:Destroy() end

JP:RegisterModule("ApplicantHighlighter", ApplicantHighlighter)
