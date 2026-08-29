local _, JP = ...
local ApplicantHighlighter = {}

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

local function EnsureBorder(frame)
    if frame.__mbApplicantBorder then return frame.__mbApplicantBorder end
    local border = {}
    for index = 1, 4 do
        border[index] = frame:CreateTexture(nil, "OVERLAY", nil, 7)
        border[index]:SetColorTexture(1, 1, 1, 1)
    end
    border[1]:SetPoint("TOPLEFT", 1, -1); border[1]:SetPoint("TOPRIGHT", -1, -1); border[1]:SetHeight(2)
    border[2]:SetPoint("BOTTOMLEFT", 1, 1); border[2]:SetPoint("BOTTOMRIGHT", -1, 1); border[2]:SetHeight(2)
    border[3]:SetPoint("TOPLEFT", 1, -1); border[3]:SetPoint("BOTTOMLEFT", 1, 1); border[3]:SetWidth(3)
    border[4]:SetPoint("TOPRIGHT", -1, -1); border[4]:SetPoint("BOTTOMRIGHT", -1, 1); border[4]:SetWidth(3)
    frame.__mbApplicantBorder = border
    return border
end

local function EnsureLabel(frame)
    if frame.__mbApplicantLabel then return frame.__mbApplicantLabel end
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
    label:SetJustifyH("RIGHT")
    label:SetShadowColor(0, 0, 0, 1)
    label:SetShadowOffset(1, -1)
    label:SetText("")
    frame.__mbApplicantLabel = label
    return label
end

local function EnsureGlow(frame)
    if frame.__mbApplicantGlow then return frame.__mbApplicantGlow end
    local glow = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    glow:SetAllPoints(frame)
    glow:SetColorTexture(1, 1, 1, .12)
    frame.__mbApplicantGlow = glow
    return glow
end

local function ColorMember(frame, status)
    local border = EnsureBorder(frame)
    local label = EnsureLabel(frame)
    local glow = EnsureGlow(frame)
    local r, g, b = .62, .22, 1
    local text = "|cffad65ffПОДХОДИТ|r"
    if status == "best" then
        r, g, b = 1, .52, .06
        text = "|cffff9418ЛУЧШИЙ|r"
    end
    for _, texture in ipairs(border) do
        texture:SetVertexColor(r, g, b, 1)
        texture:SetShown(status ~= nil)
    end
    glow:SetVertexColor(r, g, b, 1)
    glow:SetShown(status ~= nil)
    label:SetText(status and text or "")
    label:SetShown(status ~= nil)
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
    scrollBox:ForEachFrame(function(button)
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
