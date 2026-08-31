local _, JP = ...
local C = JP.UI.colors
local NameplateMarker = { plates = {} }

local function Enabled()
    local settings = MythicBoostDB and MythicBoostDB.playerAnalysis
    return not settings or (settings.enabled ~= false and settings.nameplateMarkers ~= false)
end

local function FullUnitName(unit)
    local name, realm = UnitFullName(unit)
    if type(name) ~= "string" or name == "" then return end
    return (type(realm) == "string" and realm ~= "") and (name .. "-" .. realm) or name
end

local function CreateMarker(plate)
    local marker = CreateFrame("Frame", nil, plate, "BackdropTemplate")
    marker:SetSize(26, 26)
    marker:SetPoint("BOTTOM", plate, "TOP", 0, 4)
    marker:SetFrameStrata("HIGH")
    marker:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 2,
    })
    marker:SetBackdropColor(C.surface[1], C.surface[2], C.surface[3], .92)
    marker:SetBackdropBorderColor(1, .74, .24, 1)
    marker.text = marker:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    marker.text:SetPoint("CENTER", 0, 1)
    marker.text:SetText("!")
    marker.text:SetTextColor(1, .78, .18, 1)
    marker:Hide()
    return marker
end

function NameplateMarker:Update(unit)
    if not Enabled() then return end
    if not unit or not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then return end
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return end

    local marker = self.plates[plate]
    if not marker then
        marker = CreateMarker(plate)
        self.plates[plate] = marker
    end

    local fullName = FullUnitName(unit)
    local positive = fullName and JP:GetPositivePlayer(fullName)
    if type(positive) == "table" then
        -- Игрок снова попался вживую — двигаем метку времени, чтобы запись
        -- не выпала при чистке базы.
        JP:TouchPositivePlayer(fullName, positive)
        JP:RequestRefresh(.5)
    end
    marker:SetShown(positive and true or false)
    marker.unit = unit
end

function NameplateMarker:RefreshAll()
    for plate, marker in pairs(self.plates) do
        if marker.unit and C_NamePlate.GetNamePlateForUnit(marker.unit) == plate then
            self:Update(marker.unit)
        else
            marker:Hide()
        end
    end
end

function NameplateMarker:Create()
    if self.eventFrame then return end
    local frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function(_, event, unit)
        if event == "NAME_PLATE_UNIT_ADDED" then
            self:Update(unit)
        else
            local plate = C_NamePlate.GetNamePlateForUnit(unit)
            local marker = plate and self.plates[plate]
            if marker then marker:Hide(); marker.unit = nil end
        end
    end)
    self.eventFrame = frame
end

function NameplateMarker:Enable()
    if not Enabled() then self:Disable(); return end
    if not self.eventFrame then self:Create() end
    self.eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    self.eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
end

function NameplateMarker:Disable()
    if self.eventFrame then self.eventFrame:UnregisterAllEvents() end
    for _, marker in pairs(self.plates) do marker:Hide() end
end

function NameplateMarker:Destroy() self:Disable() end

JP:RegisterModule("NameplateMarker", NameplateMarker)
