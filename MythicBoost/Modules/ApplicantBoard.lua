local _, JP = ...
local L = JP.L
local ApplicantBoard = {}
local UI = JP.UI
local C = UI.colors

-- Своя таблица кандидатов вместо штатной панели Blizzard.
--
-- В родной сетке колонки стоят вплотную, и любая наша пометка неизбежно
-- наезжала на «Ур. пр.» или «Рейтинг». Здесь мы владеем раскладкой целиком и
-- показываем ровно то, по чему принимают решение: кто это, какая роль,
-- экипировка, рейтинг и нужен ли он группе прямо сейчас.

local MAX_ROWS = 14
local ROW_HEIGHT, ROW_STEP = 62, 66
local PARTY_ROWS, PARTY_ROW_HEIGHT = 5, 26
local PARTY_TOP, PARTY_SECTION_BOTTOM = -52, -190
local ROW_LEFT_INSET, ROW_RIGHT_INSET = 12, 18

-- Одна таблица геометрии на заголовки и на строки, чтобы колонки не разъехались.
local COL = {
    declineWidth = 34, declineRight = 12,
    inviteWidth = 104, inviteRight = 52,
    statusWidth = 104, statusRight = 162,
    ratingWidth = 74, ratingRight = 272,
    ilvlWidth = 62, ilvlRight = 350,
    roleWidth = 52, roleRight = 416,
    contentRight = 474,
    nameLeft = 16,
}

local STATUS = {
    best = { label = L("ЛУЧШИЙ"), color = C.amber },
    needed = { label = L("ПОДХОДИТ"), color = { .62, .40, .95, 1 } },
    keyReady = { label = L("ПОД КЛЮЧ"), color = C.green },
    keyClose = { label = L("МОЖНО БРАТЬ"), color = C.accent },
    keyRisk = { label = L("МАЛО ОПЫТА"), color = { .95, .38, .30, 1 } },
    wrongRole = { label = L("НЕ ТА РОЛЬ"), color = { .95, .38, .30, 1 } },
}

-- Возможность помечается как потенциальная: часть диспелов и контроля зависит
-- от специализации/таланта, которых LFG API не раскрывает. Гарантированными
-- считаем только BL/BR на уровне класса, остальные помогают не забыть проверить.
local UTILITY_BY_CLASS = {
    DEATHKNIGHT = { "battleRes" },
    DEMONHUNTER = { "purge" },
    DRUID = { "battleRes", "curse", "poison", "soothe" },
    EVOKER = { "bloodlust", "poison", "purge" },
    HUNTER = { "bloodlust", "soothe", "purge" },
    MAGE = { "bloodlust", "curse", "purge" },
    MONK = { "disease", "poison" },
    PALADIN = { "battleRes", "disease", "poison" },
    PRIEST = { "disease", "purge" },
    ROGUE = { "soothe" },
    SHAMAN = { "bloodlust", "curse", "poison", "purge" },
    WARLOCK = { "battleRes" },
}
local UTILITY_ORDER = { "bloodlust", "battleRes", "curse", "poison", "disease", "soothe", "purge" }
local UTILITY_LABEL = {
    bloodlust = "BL", battleRes = "BR", curse = L("проклятия"), poison = L("яды"),
    disease = L("болезни"), soothe = "soothe", purge = "purge",
}

local function AddClassUtilities(target, classFile)
    for _, key in ipairs(UTILITY_BY_CLASS[classFile] or {}) do target[key] = true end
end

local function UtilityGain(classFile, missing)
    local gained = {}
    for _, key in ipairs(UTILITY_BY_CLASS[classFile] or {}) do
        if missing and missing[key] then gained[#gained + 1] = UTILITY_LABEL[key] end
    end
    return gained
end

local UsableNumber, SafeString = UI.UsableNumber, UI.SafeString
local SafeBoolean = UI.SafeBoolean

local function OwnKeyContext()
    local mapID = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID
        and C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    local level = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneLevel
        and C_MythicPlus.GetOwnedKeystoneLevel()
    return UsableNumber(mapID) and mapID or nil, UsableNumber(level) and level or nil
end

local function CellForMap(cells, mapID)
    for _, cell in ipairs(cells or {}) do
        if tonumber(cell.mapID) == tonumber(mapID) then return cell end
    end
end

local function PackagePresentation(entry)
    local roster = entry.packageRoster
    if type(roster) ~= "table" or #roster <= 1 then return "", nil end
    local peers, full = {}, {}
    for _, member in ipairs(roster) do
        local classIcon = UI.ClassIcon(member.classFile, 14)
        local roleIcon = UI.RoleIcon(member.role, 14)
        local color = UI.ClassColorCode(member.classFile)
        local identity = ("%s |c%s%s|r"):format(classIcon, color, member.name)
        full[#full + 1] = ("%s %s"):format(roleIcon, identity)
        if member.memberIdx ~= entry.memberIdx then peers[#peers + 1] = identity end
    end
    local visiblePeers = {}
    for index = 1, math.min(2, #peers) do visiblePeers[index] = peers[index] end
    if #peers > 2 then visiblePeers[#visiblePeers + 1] = "+" .. (#peers - 2) end
    -- Every package member owns a separate row and a separate dungeon table.
    -- Make that relationship explicit instead of leaving the companion names
    -- looking like decorative text on the leader's row.
    local inline = ("  |cffffb93d[%d/%d] ×%d|r  |cff8a939f%s|r %s"):format(
        entry.memberIdx or 1, #roster, #roster, L("вместе с"), table.concat(visiblePeers, ", "))
    local tooltip = L("Состав пакетной заявки:") .. "\n" .. table.concat(full, "\n")
    return inline, tooltip
end

-- Консервативная сила игрока для конкретного подземелья. Закрытие с запасом
-- добавляет не больше одного уровня. Точный маленький sample слегка снижает
-- уверенность, но не стирает сам факт закрытого ключа. Важно: стандартная
-- локальная база Raider.IO не хранит число проходок, поэтому nil означает
-- «неизвестно», а не «одна случайная проходка».
local function EvidenceForPlayer(name, cells, mapID, targetLevel)
    local cell = CellForMap(cells, mapID)
    local level = cell and tonumber(cell.level) or 0
    local runs = cell and tonumber(cell.runCount)
    if level <= 0 then
        return { name = name, strength = math.max(2, (targetLevel or 6) - 4), known = false, level = 0, runs = 0 }
    end
    local upgrades = tonumber(cell.upgrades) or 0
    local timerBonus = upgrades >= 3 and 1 or upgrades == 2 and .65 or upgrades == 1 and .3 or -.35
    local samplePenalty = runs and runs > 0 and (.35 / math.sqrt(runs)) or 0
    return {
        name = name, strength = level + timerBonus - samplePenalty,
        known = true, level = level, runs = runs,
    }
end


-- M+ чаще ломается на слабейшем звене, поэтому обычное среднее завышает
-- прогноз. Берём 55% минимума, 30% второго снизу и только 15% медианы.
local function TeamReadiness(records)
    if not records or #records == 0 then return 0, nil, 0 end
    local ordered, known = {}, 0
    for _, record in ipairs(records) do
        ordered[#ordered + 1] = record
        if record.known then known = known + 1 end
    end
    table.sort(ordered, function(a, b) return a.strength < b.strength end)
    local weakest = ordered[1]
    local second = ordered[math.min(2, #ordered)]
    local median = ordered[math.ceil(#ordered / 2)]
    local value = weakest.strength * .55 + second.strength * .30 + median.strength * .15
    return math.max(2, math.floor(value + .25)), weakest, math.floor(known / #ordered * 100 + .5)
end

local function CandidateRecommendation(entry, missing, mapID, targetLevel, partyEvidence)
    local roleNeeded = missing and (missing[entry.role] or 0) > 0
    local rolesMissing = missing and ((missing.TANK or 0) + (missing.HEALER or 0) + (missing.DAMAGER or 0)) > 0
    if targetLevel and mapID then
        local candidate = EvidenceForPlayer(entry.name, entry.dungeonCells, mapID, targetLevel)
        local combined = {}
        for _, record in ipairs(partyEvidence or {}) do combined[#combined + 1] = record end
        local before = TeamReadiness(combined)
        combined[#combined + 1] = candidate
        local forecast, weakest, confidence = TeamReadiness(combined)
        entry.safeLevel, entry.readinessDelta, entry.readinessConfidence = forecast, forecast - before, confidence
        entry.bottleneck = weakest and weakest.name
        local model = (L("Безопасный прогноз группы +%d (%s%d к текущему), уверенность %d%%. Слабое звено: %s."))
            :format(forecast, entry.readinessDelta >= 0 and "+" or "", entry.readinessDelta, confidence, entry.bottleneck or "—")
        if rolesMissing and not roleNeeded then
            return "wrongRole", 8, (L("Не закрывает свободную роль. %s")):format(model)
        end
        if candidate.level >= targetLevel then
            -- Статус строки описывает кандидата, а не слабейшего участника уже
            -- собранной группы. Командный риск остаётся видимым в подсказке.
            local status = forecast >= targetLevel and "keyReady" or "keyClose"
            return status, status == "keyReady" and 0 or 1,
                (L("Опыт этого данжа +%d. %s")):format(candidate.level, model)
        elseif candidate.level >= targetLevel - 1 then
            -- Один уровень до цели — нормальный кандидат на следующий шаг,
            -- особенно когда это последний незакрытый уровень сезона.
            return "keyClose", 1, (L("Опыт этого данжа +%d. %s")):format(candidate.level, model)
        elseif candidate.level >= targetLevel - 2 and forecast >= targetLevel - 1 then
            return "keyClose", 2, (L("Опыт этого данжа +%d. %s")):format(candidate.level, model)
        else
            return "keyRisk", 4, (L("Опыт этого данжа +%d при цели +%d. %s")):format(candidate.level, targetLevel, model)
        end
    end
    if roleNeeded then return entry.status or "needed", 2, L("Закрывает роль, которой не хватает группе") end
    if entry.status == "best" then return "best", 3, L("Лучший по экипировке среди кандидатов нужной роли") end
    return entry.status, 5, L("Сравни опыт по восьми подземельям перед приглашением")
end

local function RelevantMilestone(milestones, level)
    for _, entry in ipairs(type(milestones) == "table" and milestones or {}) do
        if level >= (tonumber(entry.level) or math.huge) then return entry end
    end
end

local function ShowDungeonTooltip(tile)
    local data = tile.tooltipData or {}
    if not tile.dungeonName and not data.label then return end

    GameTooltip:SetOwner(tile, "ANCHOR_RIGHT")
    if tile.ownedKey then
        GameTooltip:SetText(tile.dungeonName or data.label or L("Подземелье"), 1, .78, .20)
        GameTooltip:AddDoubleLine(L("ТВОЙ КЛЮЧ"),
            tile.ownedKeyLevel and ("+" .. tile.ownedKeyLevel) or "", 1, .72, .16, 1, .82, .28)
    else
        GameTooltip:SetText(tile.dungeonName or data.label or L("Подземелье"), .15, .78, .96)
    end

    local level = tonumber(data.level) or 0
    if level <= 0 then
        GameTooltip:AddLine(L("Нет записанных прохождений"), .55, .58, .63)
        GameTooltip:Show()
        return
    end

    GameTooltip:AddDoubleLine(L("Лучший ключ"), "+" .. level, 1, 1, 1, 1, .75, .18)
    local upgrades = tonumber(data.upgrades) or 0
    if upgrades > 0 then
        GameTooltip:AddDoubleLine(L("Повышение ключа"), "+" .. upgrades, 1, 1, 1, .30, .92, .56)
    else
        GameTooltip:AddDoubleLine(L("Таймер"), L("не закрыт"), 1, 1, 1, .62, .64, .68)
    end

    if data.runCount ~= nil then
        GameTooltip:AddDoubleLine(L("Проходок этого данжа"), tostring(data.runCount), 1, 1, 1, 1, 1, 1)
    end

    local milestone = RelevantMilestone(data.milestones, level)
    if milestone then
        GameTooltip:AddDoubleLine(milestone.label, milestone.text, .72, .75, .80, .30, .92, .56)
    end
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Данные
---------------------------------------------------------------------------

function ApplicantBoard:Collect()
    if type(C_LFGList.GetApplicants) ~= "function" then return {}, nil end
    local ok, applicantIDs = pcall(C_LFGList.GetApplicants)
    if not ok or type(applicantIDs) ~= "table" or issecretvalue(applicantIDs) then return {}, nil end

    local highlighter = JP.modules.ApplicantHighlighter
    local selected = highlighter and highlighter.GetSelection and highlighter:GetSelection() or {}
    local missing = self.missingRoles
        or (highlighter and highlighter.GetMissingRoles and highlighter:GetMissingRoles())

    local entries = {}
    for _, applicantID in ipairs(applicantIDs) do
        local applicant = C_LFGList.GetApplicantInfo(applicantID)
        local status = applicant and SafeString(applicant.applicationStatus)
        local numMembers = applicant and UsableNumber(applicant.numMembers) and applicant.numMembers or 0
        if applicant and status == "applied" then
            local packageEntries, packageRoster = {}, {}
            for memberIdx = 1, numMembers do
                local name, classFile, _, _, itemLevel, _, tank, healer, damage, assignedRole, _, score =
                    C_LFGList.GetApplicantMemberInfo(applicantID, memberIdx)
                name, classFile = SafeString(name), SafeString(classFile)
                local role = SafeString(assignedRole)
                if role ~= "TANK" and role ~= "HEALER" and role ~= "DAMAGER" then
                    role = SafeBoolean(tank) and "TANK" or SafeBoolean(healer) and "HEALER" or SafeBoolean(damage) and "DAMAGER" or "DAMAGER"
                end
                local entry = {
                    applicantID = applicantID,
                    memberIdx = memberIdx,
                    name = name or (L("Участник %d")):format(memberIdx),
                    classFile = classFile,
                    role = role,
                    itemLevel = UsableNumber(itemLevel) and itemLevel or 0,
                    score = UsableNumber(score) and score or 0,
                    status = selected[applicantID .. ":" .. memberIdx],
                    dungeonCells = JP.GroupSearchUI and JP.GroupSearchUI.GetDungeonCells
                        and JP.GroupSearchUI:GetDungeonCells(name, classFile) or nil,
                    numMembers = numMembers,
                }
                packageEntries[#packageEntries + 1] = entry
                packageRoster[#packageRoster + 1] = {
                    memberIdx = memberIdx, name = entry.name, classFile = classFile, role = role,
                }
            end
            for _, entry in ipairs(packageEntries) do
                entry.packageRoster = packageRoster
                entries[#entries + 1] = entry
            end
        end
    end

    local ownMapID, ownLevel = OwnKeyContext()
    for _, entry in ipairs(entries) do
        entry.status, entry.recommendationWeight, entry.recommendationReason =
            CandidateRecommendation(entry, missing, ownMapID, ownLevel, self.partyEvidence)
        entry.utilityGain = UtilityGain(entry.classFile, self.missingUtilities)
        if #entry.utilityGain > 0 then
            entry.recommendationWeight = math.max(0, (entry.recommendationWeight or 5) - math.min(1, #entry.utilityGain * .35))
            entry.recommendationReason = entry.recommendationReason .. " "
                .. (L("Добавляет группе: %s.")):format(table.concat(entry.utilityGain, ", "))
        end
    end

    -- Blizzard invites the entire applicantID at once. Sort at that same
    -- package boundary so duo/trio members can never drift to opposite ends of
    -- the list even when their individual score or recommendation differs.
    local packages, byApplicant = {}, {}
    for _, entry in ipairs(entries) do
        local package = byApplicant[entry.applicantID]
        if not package then
            package = { entries = {}, weight = math.huge, itemLevel = 0, name = entry.name }
            byApplicant[entry.applicantID] = package
            packages[#packages + 1] = package
        end
        package.entries[#package.entries + 1] = entry
        package.weight = math.min(package.weight, entry.recommendationWeight or 9)
        package.itemLevel = math.max(package.itemLevel, entry.itemLevel or 0)
    end
    table.sort(packages, function(a, b)
        if a.weight ~= b.weight then return a.weight < b.weight end
        if a.itemLevel ~= b.itemLevel then return a.itemLevel > b.itemLevel end
        return a.name < b.name
    end)
    local ordered = {}
    for _, package in ipairs(packages) do
        table.sort(package.entries, function(a, b) return a.memberIdx < b.memberIdx end)
        for _, entry in ipairs(package.entries) do
            entry.packageInline, entry.packageTooltip = PackagePresentation(entry)
            ordered[#ordered + 1] = entry
        end
    end
    return ordered, missing
end

local function Act(action, applicantID, failure)
    if type(C_LFGList[action]) ~= "function" then
        JP:Print(L("Это действие недоступно: API поиска групп не отвечает."))
        return false
    end
    local ok = pcall(C_LFGList[action], applicantID)
    if not ok then JP:Print(failure) end
    return ok
end

---------------------------------------------------------------------------
-- Строки
---------------------------------------------------------------------------

local function CreateRow(parent, index)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(ROW_HEIGHT)
    row:EnableMouse(true)
    row.baseColor = index % 2 == 0 and C.rowAlt or C.row
    UI.Backdrop(row, row.baseColor, C.lineSoft)

    row.accent = row:CreateTexture(nil, "OVERLAY")
    row.accent:SetPoint("TOPLEFT", 1, -1)
    row.accent:SetPoint("BOTTOMLEFT", 1, 1)
    row.accent:SetWidth(3)

    row.name = UI.Text(row, "GameFontHighlight", "", C.text)
    row.name:SetPoint("TOPLEFT", COL.nameLeft, -6)
    row.name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -COL.contentRight, -6)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    -- Компактная таблица ключей: названия и значения больше не слипаются в
    -- одну длинную строку и всегда стоят строго друг под другом.
    row.dungeonGrid = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.dungeonGrid:SetPoint("BOTTOMLEFT", COL.nameLeft, 3)
    row.dungeonGrid:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -COL.contentRight, 3)
    row.dungeonGrid:SetHeight(34)
    row.dungeonTiles = {}
    for cellIndex = 1, 8 do
        local tile = CreateFrame("Frame", nil, row.dungeonGrid, "BackdropTemplate")
        tile:EnableMouse(true)
        UI.Backdrop(tile, { .015, .022, .030, 1 }, C.lineSoft)
        tile.image = tile:CreateTexture(nil, "ARTWORK")
        tile.image:SetPoint("TOPLEFT", 1, -1)
        tile.image:SetPoint("BOTTOMRIGHT", -1, 1)
        tile.image:SetTexCoord(.07, .93, .07, .93)
        tile.shade = tile:CreateTexture(nil, "OVERLAY")
        tile.shade:SetAllPoints(tile.image)
        tile.shade:SetColorTexture(0, 0, 0, .54)
        tile.upgrades = UI.Text(tile, "GameFontNormalSmall", "", C.text)
        tile.upgrades:SetPoint("TOP", 0, -1)
        local upgradesFont = tile.upgrades:GetFont()
        if upgradesFont then tile.upgrades:SetFont(upgradesFont, 10, "THICKOUTLINE") end
        tile.upgrades:SetShadowColor(0, 0, 0, 1)
        tile.upgrades:SetShadowOffset(1, -1)
        tile.value = UI.Text(tile, "GameFontNormalHuge", "—", C.muted)
        tile.value:SetPoint("BOTTOM", 0, 1)
        local fontPath = tile.value:GetFont()
        if fontPath then tile.value:SetFont(fontPath, 16, "THICKOUTLINE") end
        tile.value:SetShadowColor(0, 0, 0, 1)
        tile.value:SetShadowOffset(2, -2)
        tile.valueFont = fontPath

        -- The player's owned Keystone is a decision column, not merely one of
        -- eight equal dungeon pictures. A separate two-pixel ring survives
        -- green/purple run-grade borders and remains readable on every icon.
        tile.ownedGlow = CreateFrame("Frame", nil, tile, "BackdropTemplate")
        tile.ownedGlow:SetPoint("TOPLEFT", -1, 1)
        tile.ownedGlow:SetPoint("BOTTOMRIGHT", 1, -1)
        tile.ownedGlow:SetFrameLevel(tile:GetFrameLevel() + 8)
        tile.ownedGlow:EnableMouse(false)
        tile.ownedGlow:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
        tile.ownedGlow:SetBackdropBorderColor(1, .67, .10, 1)
        tile.ownedGlow:Hide()
        tile:SetScript("OnEnter", function(self)
            row:SetBackdropColor(UI.Unpack(C.rowHover))
            ShowDungeonTooltip(self)
        end)
        tile:SetScript("OnLeave", function()
            row:SetBackdropColor(UI.Unpack(row.baseColor))
            GameTooltip_Hide()
        end)
        row.dungeonTiles[cellIndex] = tile
    end

    row.role = UI.Text(row, "GameFontHighlight", "")
    row.role:SetPoint("RIGHT", -COL.roleRight, 0)
    row.role:SetWidth(COL.roleWidth)
    row.role:SetJustifyH("CENTER")

    row.ilvl = UI.Text(row, "GameFontHighlightSmall", "", C.text)
    row.ilvl:SetPoint("RIGHT", -COL.ilvlRight, 0)
    row.ilvl:SetWidth(COL.ilvlWidth)
    row.ilvl:SetJustifyH("CENTER")

    row.rating = UI.Text(row, "GameFontNormal", "", C.amber)
    row.rating:SetPoint("RIGHT", -COL.ratingRight, 0)
    row.rating:SetWidth(COL.ratingWidth)
    row.rating:SetJustifyH("CENTER")

    row.status = UI.Text(row, "GameFontNormalSmall", "")
    row.status:SetPoint("RIGHT", -COL.statusRight, 0)
    row.status:SetWidth(COL.statusWidth)
    row.status:SetJustifyH("CENTER")

    row.invite = UI.Button(row, L("Пригласить"), COL.inviteWidth, 24, true)
    row.invite:SetPoint("RIGHT", -COL.inviteRight, 0)
    row.invite:SetScript("OnClick", function(self)
        if not self.applicantID then return end
        if Act("InviteApplicant", self.applicantID, L("Blizzard не принял приглашение. Попробуй ещё раз.")) then
            self:SetText(L("Отправлено"))
        end
    end)

    row.decline = UI.Button(row, "×", COL.declineWidth, 24)
    row.decline:SetPoint("RIGHT", -COL.declineRight, 0)
    row.decline:SetScript("OnClick", function(self)
        if self.applicantID then Act("DeclineApplicant", self.applicantID, L("Не удалось отклонить заявку.")) end
    end)
    row.decline:HookScript("OnEnter", function(self) UI.Tooltip(self, L("Отклонить заявку")) end)
    row.decline:HookScript("OnLeave", GameTooltip_Hide)

    row:SetScript("OnEnter", function(self)
        self:SetBackdropColor(UI.Unpack(C.rowHover))
        if self.packageSize and self.packageSize > 1 then
            UI.Tooltip(self, (L("Пакетная заявка ×%d")):format(self.packageSize),
                self.packageTooltip, self.recommendationReason)
        elseif self.recommendationReason then
            UI.Tooltip(self, L("Почему такая оценка"), self.recommendationReason)
        end
    end)
    row:SetScript("OnLeave", function(self)
        self:SetBackdropColor(UI.Unpack(self.baseColor))
        GameTooltip_Hide()
    end)

    row:Hide()
    return row
end

---------------------------------------------------------------------------
-- Сборка
---------------------------------------------------------------------------

local function HeaderIconButton(parent, texture, tooltipTitle, tooltipLines)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(28, 28)
    UI.Backdrop(button, { .035, .055, .070, .96 }, { .10, .48, .62, .90 })

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 3, -3)
    button.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    button.icon:SetTexture(texture)
    button.icon:SetTexCoord(.08, .92, .08, .92)

    button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
    button.highlight:SetAllPoints(button.icon)
    button.highlight:SetColorTexture(.18, .78, 1, .22)

    button:SetScript("OnEnter", function(self)
        self:SetBackdropColor(.055, .105, .130, 1)
        self:SetBackdropBorderColor(.18, .76, .94, 1)
        local lines = type(tooltipLines) == "function" and tooltipLines() or tooltipLines
        UI.Tooltip(self, tooltipTitle, unpack(lines or {}))
    end)
    button:SetScript("OnLeave", function(self)
        self:SetBackdropColor(.035, .055, .070, .96)
        self:SetBackdropBorderColor(.10, .48, .62, .90)
        GameTooltip_Hide()
    end)
    return button
end

function ApplicantBoard:Build(welcome, page)
    self.page = page
    self.welcome = welcome

    local partyTitle = UI.Text(page, "GameFontNormalSmall", L("ТВОЯ ПАТИ"), C.accent)
    partyTitle:SetPoint("TOPLEFT", 16, -14)

    self.partyPower = UI.Text(page, "GameFontHighlightSmall", "", C.muted)
    self.partyPower:SetPoint("LEFT", partyTitle, "RIGHT", 14, 0)
    self.partyPower:SetJustifyH("LEFT")

    self.forecastHelp = HeaderIconButton(page,
        "Interface\\Icons\\INV_Relics_Hourglass",
        L("Прогноз готовности группы"), {
            L("Опыт: текущее подземелье."),
            L("Модель: 55% слабейший / 30% второй / 15% медиана."),
            L("Малая выборка снижает уверенность. Прогноз не является гарантией."),
        })
    self.forecastHelp:SetPoint("TOPRIGHT", -14, -5)

    self.utilityHelp = HeaderIconButton(page,
        "Interface\\Icons\\Spell_Holy_AuraMastery",
        L("Возможности группы"), function()
            local covered = self.utilityCoveredText
            local missing = self.utilityMissingText
            if not covered and not missing then
                return { L("Добавь участников, чтобы оценить возможности состава.") }
            end
            return {
                (L("Есть: %s")):format(covered or "—"),
                (L("Не хватает: %s")):format(missing or "—"),
                L("Таланты и специализацию проверь перед стартом."),
            }
        end)
    self.utilityHelp:SetPoint("RIGHT", self.forecastHelp, "LEFT", -6, 0)

    local partyHeaders = {
        { text = L("ИГРОК"), x = 16, width = 210, justify = "LEFT" },
        { text = L("РОЛЬ"), x = 230, width = 54 },
        { text = "RIO", x = 290, width = 72 },
    }
    for _, data in ipairs(partyHeaders) do
        local label = UI.Text(page, "GameFontNormalSmall", data.text, C.faint)
        label:SetPoint("TOPLEFT", data.x, -34)
        label:SetWidth(data.width)
        label:SetJustifyH(data.justify or "CENTER")
    end

    self.partyDungeonHeaders = {}
    for index = 1, 8 do
        local header = CreateFrame("Frame", nil, page, "BackdropTemplate")
        header:SetSize(20, 20)
        header:SetPoint("TOPLEFT", 391 + (index - 1) * 58, -29)
        header:EnableMouse(true)
        UI.Backdrop(header, { .015, .022, .030, 1 }, { .18, .38, .48, .85 })
        header.icon = header:CreateTexture(nil, "ARTWORK")
        header.icon:SetPoint("TOPLEFT", 1, -1)
        header.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        header.icon:SetTexCoord(.07, .93, .07, .93)
        header.fallback = UI.Text(header, "GameFontNormalSmall", "", C.accent)
        header.fallback:SetPoint("CENTER", 0, 0)
        header.ownedGlow = CreateFrame("Frame", nil, header, "BackdropTemplate")
        header.ownedGlow:SetPoint("TOPLEFT", -2, 2)
        header.ownedGlow:SetPoint("BOTTOMRIGHT", 2, -2)
        header.ownedGlow:SetFrameLevel(header:GetFrameLevel() + 5)
        header.ownedGlow:EnableMouse(false)
        header.ownedGlow:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
        header.ownedGlow:SetBackdropBorderColor(1, .67, .10, 1)
        header.ownedGlow:Hide()
        header:SetScript("OnEnter", function(self)
            if not self.dungeonName then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.dungeonName,
                self.ownedKey and 1 or .15, self.ownedKey and .78 or .78, self.ownedKey and .20 or .96)
            if self.ownedKey then
                GameTooltip:AddDoubleLine(L("ТВОЙ КЛЮЧ"),
                    self.ownedKeyLevel and ("+" .. self.ownedKeyLevel) or "",
                    1, .72, .16, 1, .82, .28)
            end
            GameTooltip:Show()
        end)
        header:SetScript("OnLeave", GameTooltip_Hide)
        self.partyDungeonHeaders[index] = header
    end

    self.partyRows = {}
    for index = 1, PARTY_ROWS do
        local row = CreateFrame("Frame", nil, page, "BackdropTemplate")
        row:SetPoint("TOPLEFT", 12, PARTY_TOP - (index - 1) * PARTY_ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", -12, PARTY_TOP - (index - 1) * PARTY_ROW_HEIGHT)
        row:SetHeight(PARTY_ROW_HEIGHT - 2)
        UI.Backdrop(row, index % 2 == 0 and C.rowAlt or C.row, C.lineSoft)

        row.name = UI.Text(row, "GameFontHighlightSmall", "", C.text)
        row.name:SetPoint("LEFT", 6, 0)
        row.name:SetWidth(208)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.role = UI.Text(row, "GameFontHighlightSmall", "")
        row.role:SetPoint("LEFT", 218, 0)
        row.role:SetWidth(54)
        row.role:SetJustifyH("CENTER")
        row.score = UI.Text(row, "GameFontNormalSmall", "—", C.muted)
        row.score:SetPoint("LEFT", 278, 0)
        row.score:SetWidth(72)
        row.score:SetJustifyH("CENTER")
        row.cells = {}
        for cellIndex = 1, 8 do
            local cell = UI.Text(row, "GameFontHighlightSmall", "—", C.muted)
            cell:SetPoint("LEFT", 362 + (cellIndex - 1) * 58, 0)
            cell:SetWidth(54)
            cell:SetJustifyH("CENTER")
            cell.baseFont, cell.baseFontSize, cell.baseFontFlags = cell:GetFont()
            row.cells[cellIndex] = cell
        end
        self.partyRows[index] = row
    end

    local partyDivider = UI.Line(page, C.accentDim)
    partyDivider:SetPoint("TOPLEFT", 12, PARTY_SECTION_BOTTOM)
    partyDivider:SetPoint("TOPRIGHT", -12, PARTY_SECTION_BOTTOM)

    local title = UI.Text(page, "GameFontNormalSmall", L("КАНДИДАТЫ"), C.muted)
    title:SetPoint("TOPLEFT", 16, PARTY_SECTION_BOTTOM - 16)

    self.count = UI.Text(page, "GameFontHighlightSmall", "", C.accent)
    self.count:SetPoint("LEFT", title, "RIGHT", 10, 0)

    self.needs = UI.Text(page, "GameFontHighlightSmall", "", C.muted)
    self.needs:SetPoint("LEFT", self.count, "RIGHT", 16, 0)
    self.needs:SetJustifyH("LEFT")

    local divider = UI.Line(page, C.lineSoft)
    divider:SetPoint("TOPLEFT", 12, PARTY_SECTION_BOTTOM - 38)
    divider:SetPoint("TOPRIGHT", -12, PARTY_SECTION_BOTTOM - 38)

    local function Header(text, width, right)
        local label = UI.Text(page, "GameFontNormalSmall", text, C.faint)
        -- Значения привязаны к правому краю строки, а сама строка отступает
        -- от страницы. Шапка обязана учитывать тот же отступ.
        label:SetPoint("TOPRIGHT", -(right + ROW_RIGHT_INSET), PARTY_SECTION_BOTTOM - 50)
        label:SetWidth(width)
        label:SetJustifyH("CENTER")
    end
    local nameHeader = UI.Text(page, "GameFontNormalSmall", L("ИГРОК"), C.faint)
    nameHeader:SetPoint("TOPLEFT", ROW_LEFT_INSET + COL.nameLeft, PARTY_SECTION_BOTTOM - 50)
    nameHeader:SetJustifyH("LEFT")
    Header(L("РОЛЬ"), COL.roleWidth, COL.roleRight)
    Header("iLvL", COL.ilvlWidth, COL.ilvlRight)
    Header(L("РЕЙТИНГ"), COL.ratingWidth, COL.ratingRight)
    Header(L("ОТБОР"), COL.statusWidth, COL.statusRight)

    self.rows = {}
    for index = 1, MAX_ROWS do
        local row = CreateRow(page, index)
        row:SetPoint("TOPLEFT", ROW_LEFT_INSET, PARTY_SECTION_BOTTOM - 66 - (index - 1) * ROW_STEP)
        row:SetPoint("TOPRIGHT", -ROW_RIGHT_INSET, PARTY_SECTION_BOTTOM - 66 - (index - 1) * ROW_STEP)
        self.rows[index] = row
    end

    self.scrollBar = UI.ScrollBar(page)
    self.scrollBar:SetPoint("TOPRIGHT", -6, PARTY_SECTION_BOTTOM - 66)
    self.scrollBar:SetPoint("BOTTOMRIGHT", -6, 12)
    self.scrollBar:SetScript("OnValueChanged", function(_, value)
        local offset = math.floor(value + .5)
        if offset ~= self.offset then
            self.offset = offset
            self:Render()
        end
    end)
    self.scrollBar:Hide()

    UI.BindScrollWheel(page, self.scrollBar, self.rows, function() return self.offset end)

    self.message = UI.Text(page, "GameFontHighlight", "", C.muted)
    self.message:SetPoint("TOPLEFT", 24, PARTY_SECTION_BOTTOM - 120)
    self.message:SetPoint("TOPRIGHT", -24, PARTY_SECTION_BOTTOM - 120)
    self.message:SetJustifyH("CENTER")
    self.message:SetSpacing(6)

    self.emptyAction = UI.Button(page, L("Создать объявление"), 190, 28, true)
    self.emptyAction:SetPoint("TOP", self.message, "BOTTOM", 0, -16)
    self.emptyAction:SetScript("OnClick", function()
        if JP.GroupSearchUI and JP.GroupSearchUI.OpenListingAction then
            JP.GroupSearchUI:OpenListingAction()
        elseif JP.FrameSwitch then
            JP.FrameSwitch.OpenBlizzard()
        end
    end)
    self.emptyAction:Hide()

    self:Layout()
end

function ApplicantBoard:Layout()
    if not self.page then return end
    local height = self.page:GetHeight()
    if height < 100 then return end
    local visible = math.max(2, math.min(MAX_ROWS, math.floor((height + PARTY_SECTION_BOTTOM - 72) / ROW_STEP)))
    self.visibleRows = visible
    for index, row in ipairs(self.rows or {}) do
        row.layoutVisible = index <= visible
        if not row.layoutVisible then row:Hide() end
        local gridWidth = math.max(240, row.dungeonGrid:GetWidth())
        local tileGap = 2
        local tileSize = math.min(34, math.floor((gridWidth - tileGap * 7) / 8))
        local startX = 0
        local startY = -math.max(0, math.floor((34 - tileSize) / 2))
        for cellIndex = 1, 8 do
            local tile = row.dungeonTiles[cellIndex]
            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT", startX + (cellIndex - 1) * (tileSize + tileGap), startY)
            tile:SetSize(tileSize, tileSize)
        end
    end
end

local function UnitRole(unit)
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
    if role == "NONE" or not role then
        if unit == "player" then
            local spec = GetSpecialization and GetSpecialization()
            role = spec and GetSpecializationRole and GetSpecializationRole(spec) or nil
        end
    end
    if role == "TANK" or role == "HEALER" or role == "DAMAGER" then return role end
end

function ApplicantBoard:RefreshParty()
    if not self.partyRows then return end
    local partyMembers = { { unit = "player" } }
    local present = {}
    local playerName = UnitName("player")
    if playerName then present[playerName:lower()] = true end
    for index = 1, 4 do
        local unit = "party" .. index
        if UnitExists(unit) then
            partyMembers[#partyMembers + 1] = { unit = unit }
            local name = UnitName(unit)
            if name then present[name:lower()] = true end
        end
    end

    -- Blizzard keeps invited/accepted applicants outside party1..party4 until
    -- they actually join. Show them in the party preview immediately so the
    -- addon agrees with the native applicant list.
    if #partyMembers < PARTY_ROWS and C_LFGList and type(C_LFGList.GetApplicants) == "function" then
        local ok, applicantIDs = pcall(C_LFGList.GetApplicants)
        if ok and type(applicantIDs) == "table" and not issecretvalue(applicantIDs) then
            for _, applicantID in ipairs(applicantIDs) do
                local applicant = C_LFGList.GetApplicantInfo(applicantID)
                local status = applicant and SafeString(applicant.applicationStatus)
                if status == "invited" or status == "inviteaccepted" then
                    local count = UsableNumber(applicant.numMembers) and applicant.numMembers or 0
                    for memberIndex = 1, count do
                        local name, classFilename, _, _, _, _, tank, healer, damage, assignedRole, _, score =
                            C_LFGList.GetApplicantMemberInfo(applicantID, memberIndex)
                        name, classFilename = SafeString(name), SafeString(classFilename)
                        local baseName = name and name:match("^([^%-]+)")
                        if name and baseName and not present[baseName:lower()] and #partyMembers < PARTY_ROWS then
                            local role = SafeString(assignedRole)
                            if role ~= "TANK" and role ~= "HEALER" and role ~= "DAMAGER" then
                                role = SafeBoolean(tank) and "TANK" or SafeBoolean(healer) and "HEALER"
                                    or SafeBoolean(damage) and "DAMAGER" or nil
                            end
                            partyMembers[#partyMembers + 1] = {
                                name = name, classFilename = classFilename, role = role,
                                score = UsableNumber(score) and score or 0,
                                cells = JP.GroupSearchUI:GetDungeonCells(name, classFilename) or {},
                                pending = status == "invited",
                            }
                            present[baseName:lower()] = true
                        end
                    end
                end
            end
        end
    end

    local columns = JP.GroupSearchUI:GetPartyDungeonColumns()
    local ownMapID, ownLevel = OwnKeyContext()
    for index, header in ipairs(self.partyDungeonHeaders) do
        local column = columns[index]
        local isOwnedKey = ownMapID and column and tonumber(column.key) == tonumber(ownMapID)
        header.dungeonName = column and column.name
        header.ownedKey, header.ownedKeyLevel = isOwnedKey and true or false, isOwnedKey and ownLevel or nil
        header.icon:SetTexture(column and column.texture or nil)
        header.icon:SetShown(column and column.texture and true or false)
        header.fallback:SetText(column and not column.texture and (column.label or "M+") or "")
        header:SetBackdropColor(isOwnedKey and .11 or .015, isOwnedKey and .055 or .022,
            isOwnedKey and .006 or .030, 1)
        header:SetBackdropBorderColor(isOwnedKey and 1 or .18, isOwnedKey and .67 or .38,
            isOwnedKey and .10 or .48, isOwnedKey and 1 or .85)
        header.ownedGlow:SetShown(isOwnedKey and true or false)
        header:SetShown(column and true or false)
    end

    local total, known = 0, 0
    local memberStrengths = {}
    self.partyEvidence = {}
    self.partyUtilities = {}
    local partyRoleCounts = { TANK = 0, HEALER = 0, DAMAGER = 0 }
    for index, row in ipairs(self.partyRows) do
        local member = partyMembers[index]
        if member then
            local unit = member.unit
            local name = unit and UnitName(unit) or member.name or L("Игрок")
            local classFilename = member.classFilename
            if unit then
                local _, unitClass = UnitClass(unit)
                classFilename = unitClass
            end
            local assignedRole = unit and UnitRole(unit) or member.role
            if partyRoleCounts[assignedRole] ~= nil then
                partyRoleCounts[assignedRole] = partyRoleCounts[assignedRole] + 1
            end
            AddClassUtilities(self.partyUtilities, classFilename)
            local profile = unit and JP.GroupSearchUI:GetPartyMemberProfile(unit)
                or { score = member.score or 0, cells = member.cells or {} }
            profile = profile or { score = 0, cells = {} }
            local score = tonumber(profile.score) or 0
            if score > 0 then total, known = total + score, known + 1 end

            -- Прогноз строится по трём сильнейшим подземельям игрока. +2/+3
            -- дают небольшой запас, но не превращаются в обещание нескольких
            -- уровней сверху. Затем усредняем силу всех найденных участников.
            local runs = {}
            local gradeBonus = { plusTwo = .5, plusThree = 1 }
            for _, data in ipairs(profile.cells or {}) do
                local level = tonumber(data.level) or tonumber(tostring(data.value or ""):match("(%d+)") or "")
                if level and level > 0 then runs[#runs + 1] = level + (gradeBonus[data.grade] or 0) end
            end
            table.sort(runs, function(a, b) return a > b end)
            if #runs > 0 then
                local count, strength = math.min(3, #runs), 0
                for runIndex = 1, count do strength = strength + runs[runIndex] end
                memberStrengths[#memberStrengths + 1] = strength / count
            end
            if ownMapID and ownLevel then
                self.partyEvidence[#self.partyEvidence + 1] = EvidenceForPlayer(name, profile.cells, ownMapID, ownLevel)
            end

            row.name:SetText(('%s  %s%s'):format(
                UI.ClassIcon(classFilename, 16),
                name .. (member.pending and ("  |cffd9a441" .. L("ожидает") .. "|r") or ""),
                unit and UnitIsGroupLeader(unit)
                    and "  |TInterface\\GroupFrame\\UI-Group-LeaderIcon:14:14:0:0|t" or ""))
            row.name:SetTextColor(UI.ClassColor(classFilename))
            row.role:SetText(UI.RoleIcon(assignedRole, 16))
            row.score:SetText(score > 0 and tostring(math.floor(score + .5)) or "—")
            if score > 0 then
                local code = JP.GroupSearchUI:GetPartyRatingColor(score)
                row.score:SetTextColor(tonumber(code:sub(1, 2), 16) / 255, tonumber(code:sub(3, 4), 16) / 255, tonumber(code:sub(5, 6), 16) / 255)
            else
                row.score:SetTextColor(UI.Unpack(C.muted))
            end
            for cellIndex, cell in ipairs(row.cells) do
                local data = profile.cells and profile.cells[cellIndex]
                local column = columns[cellIndex]
                local isOwnedKey = ownMapID and column and tonumber(column.key) == tonumber(ownMapID)
                cell:SetText(data and data.value or "—")
                local color = JP.GroupSearchUI:GetRunGradeColor(data and data.grade)
                if isOwnedKey then
                    cell:SetTextColor(1, .80, .22, 1)
                    if cell.baseFont then cell:SetFont(cell.baseFont, 14, "THICKOUTLINE") end
                    cell:SetShadowColor(.65, .24, 0, 1); cell:SetShadowOffset(1, -1)
                else
                    cell:SetTextColor(color[1], color[2], color[3], 1)
                    if cell.baseFont then
                        cell:SetFont(cell.baseFont, cell.baseFontSize, cell.baseFontFlags)
                    end
                    cell:SetShadowColor(0, 0, 0, 1); cell:SetShadowOffset(1, -1)
                end
            end
            row:Show()
        else
            row:Hide()
        end
    end

    local members = math.max(1, #partyMembers)
    self.missingRoles = {
        TANK = math.max(0, 1 - partyRoleCounts.TANK),
        HEALER = math.max(0, 1 - partyRoleCounts.HEALER),
        DAMAGER = math.max(0, 3 - partyRoleCounts.DAMAGER),
    }
    local average = total / members
    local forecast = 0
    for _, strength in ipairs(memberStrengths) do forecast = forecast + strength end
    if #memberStrengths > 0 then forecast = math.max(2, math.floor(forecast / #memberStrengths)) end
    local safeLevel, weakest, confidence = TeamReadiness(self.partyEvidence)
    if ownMapID and ownLevel and #self.partyEvidence > 0 then
        self.partyPowerBaseText = (L("|cff8a939fучастников|r %d   |cff%sсредний RIO %d|r   |cff28c8f5безопасно ~+%d|r   |cff8a939fуверенность %d%%|r   |cffff9966риск: %s|r")):format(
            members, JP.GroupSearchUI:GetPartyRatingColor(average), math.floor(average + .5), safeLevel, confidence,
            weakest and weakest.name or "—")
        self.forecastHelp:Show()
    else
        self.partyPowerBaseText = (L("|cff8a939fучастников|r %d   |cff8a939fсумма RIO|r %d   |cff%sсредний %d|r   |cff8a939fнайдено|r %d/%d   |cff28c8f5общий прогноз ~+%d|r")):format(
            members, math.floor(total + .5), JP.GroupSearchUI:GetPartyRatingColor(average), math.floor(average + .5), known, members, forecast)
        self.forecastHelp:Hide()
    end

    local covered, missingUtility = {}, {}
    self.missingUtilities = {}
    for _, key in ipairs(UTILITY_ORDER) do
        if self.partyUtilities[key] then
            covered[#covered + 1] = UTILITY_LABEL[key]
        else
            missingUtility[#missingUtility + 1] = UTILITY_LABEL[key]
            self.missingUtilities[key] = true
        end
    end
    self.utilityCoveredText = #covered > 0 and table.concat(covered, ", ") or L("ничего не подтверждено")
    self.utilityMissingText = #missingUtility > 0 and table.concat(missingUtility, ", ") or L("основные возможности закрыты")
    self.partyMemberCount, self.partySafeLevel, self.partyConfidence = members, safeLevel, confidence
    self.partyPower:SetText(self.partyPowerBaseText or "")
end

function ApplicantBoard:UpdateLaunchDecision(entries)
    local members = self.partyMemberCount or 1
    local _, targetLevel = OwnKeyContext()
    local advice, color = L("ЖДИ ЗАЯВКИ"), "ffff9966"
    local rolesMissing = self.missingRoles and (
        (self.missingRoles.TANK or 0) + (self.missingRoles.HEALER or 0) + (self.missingRoles.DAMAGER or 0)) or 0
    if not targetLevel then
        advice, color = L("НЕТ СВОЕГО КЛЮЧА"), "ff8a939f"
    elseif members >= 5 then
        if rolesMissing > 0 then
            advice, color = L("ПОДОЖДИ: НЕВЕРНЫЙ СОСТАВ РОЛЕЙ"), "ffff5f66"
        elseif (self.partySafeLevel or 0) >= targetLevel and (self.partyConfidence or 0) >= 60 then
            advice, color = L("ЗАПУСКАЙ"), "ff43d17a"
        elseif (self.partySafeLevel or 0) >= targetLevel - 1 then
            advice, color = L("МОЖНО ЗАПУСКАТЬ, НО ЕСТЬ РИСК"), "ffffb93d"
        else
            advice, color = L("ПОДОЖДИ: СОСТАВ НИЖЕ КЛЮЧА"), "ffff5f66"
        end
    elseif #(entries or {}) > 0 then
        local needed = 5 - members
        local packages, packageByKey, bestSingle = {}, {}, nil
        for _, entry in ipairs(entries) do
            local packageSize = math.max(1, tonumber(entry.numMembers) or 1)
            local applicantKey = entry.applicantID or entry.name
            if applicantKey then
                local package = packageByKey[applicantKey]
                if not package then
                    package = { size = packageSize, roles = { TANK = 0, HEALER = 0, DAMAGER = 0 } }
                    packageByKey[applicantKey] = package
                    packages[#packages + 1] = package
                end
                if package.roles[entry.role] ~= nil then
                    package.roles[entry.role] = package.roles[entry.role] + 1
                end
            end
            local roleNeeded = (self.missingRoles and self.missingRoles[entry.role] or 0) > 0
            if not bestSingle and packageSize == 1 and roleNeeded
                and (entry.safeLevel or 0) >= targetLevel - 1 then
                bestSingle = entry
            end
        end
        local remaining = {
            TANK = self.missingRoles and self.missingRoles.TANK or 0,
            HEALER = self.missingRoles and self.missingRoles.HEALER or 0,
            DAMAGER = self.missingRoles and self.missingRoles.DAMAGER or 0,
        }
        local availablePeople = 0
        for _, package in ipairs(packages) do
            local fits = package.size <= needed - availablePeople
            for role, count in pairs(package.roles) do
                if count > (remaining[role] or 0) then fits = false; break end
            end
            if fits then
                availablePeople = availablePeople + package.size
                for role, count in pairs(package.roles) do remaining[role] = remaining[role] - count end
            end
        end
        if needed == 1 and bestSingle then
            advice, color = (L("БЕРИ %s")):format(bestSingle.name), "ff43d17a"
        elseif availablePeople >= needed then
            advice, color = (L("ЕСТЬ %d КАНДИДАТОВ — ДОБЕРИ РОЛИ")):format(availablePeople), "ffffb93d"
        else
            advice, color = (L("ЖДИ ЕЩЁ %d")):format(needed - availablePeople), "ffff9966"
        end
    end
    self.launchAdvice = advice
    self.partyPower:SetText(("|c%s%s|r   -   %s"):format(color, advice, self.partyPowerBaseText or ""))
end

function ApplicantBoard:Render()
    local entries = self.entries or {}
    local offset = self.offset or 0
    local dungeonColumns = JP.GroupSearchUI:GetPartyDungeonColumns()
    local ownMapID, ownLevel = OwnKeyContext()
    for index, row in ipairs(self.rows) do
        local entry = entries[offset + index]
        if entry and row.layoutVisible ~= false then
            local style = entry.status and STATUS[entry.status]

            row.name:SetText(("%s  %s%s"):format(
                UI.ClassIcon(entry.classFile, 18), entry.name, entry.packageInline or ""))
            row.name:SetTextColor(UI.ClassColor(entry.classFile))
            row.role:SetText(UI.RoleIcon(entry.role, 18))
            row.ilvl:SetText(entry.itemLevel > 0 and ("%.0f"):format(entry.itemLevel) or "—")
            row.rating:SetText(entry.score > 0 and tostring(math.floor(entry.score)) or "—")
            for cellIndex = 1, 8 do
                local data = entry.dungeonCells and entry.dungeonCells[cellIndex]
                local column = dungeonColumns[cellIndex]
                local tile = row.dungeonTiles[cellIndex]
                tile.tooltipData = data
                tile.dungeonName = column and column.name
                tile.image:SetTexture(column and column.texture or 134400)
                tile.image:SetShown(column and column.texture and true or false)
                local level = data and tonumber(data.level) or 0
                tile.value:SetText(level > 0 and tostring(level) or "—")
                local color = JP.GroupSearchUI:GetRunGradeColor(data and data.grade)
                local isOwnedKey = ownMapID and column and tonumber(column.key) == tonumber(ownMapID)
                tile.ownedKey, tile.ownedKeyLevel = isOwnedKey and true or false, isOwnedKey and ownLevel or nil
                if tile.valueFont then tile.value:SetFont(tile.valueFont, isOwnedKey and 20 or 16, "THICKOUTLINE") end
                local upgrades = data and tonumber(data.upgrades) or 0
                tile.upgrades:SetText(upgrades > 0 and string.rep("+", math.min(3, upgrades)) or "")
                tile.upgrades:SetTextColor(color[1], color[2], color[3], 1)
                tile.value:SetTextColor(color[1], color[2], color[3], 1)
                if level <= 0 then
                    tile:SetBackdropBorderColor(.12, .17, .22, .55)
                elseif upgrades >= 2 then
                    tile:SetBackdropBorderColor(color[1], color[2], color[3], .95)
                elseif upgrades == 1 then
                    tile:SetBackdropBorderColor(.18, .34, .42, .82)
                else
                    tile:SetBackdropBorderColor(.42, .15, .18, .78)
                end
                if isOwnedKey then
                    tile.value:SetTextColor(1, .82, .28, 1)
                    tile.upgrades:SetTextColor(1, .70, .12, 1)
                    tile:SetBackdropBorderColor(1, .66, .12, 1)
                    tile:SetBackdropColor(.10, .050, .005, 1)
                    tile.shade:SetColorTexture(.18, .08, 0, .28)
                    tile.value:SetShadowColor(.72, .26, 0, 1)
                    tile.value:SetShadowOffset(1, -1)
                    tile.ownedGlow:Show()
                else
                    tile:SetBackdropColor(.015, .022, .030, 1)
                    tile.shade:SetColorTexture(0, 0, 0, .54)
                    tile.value:SetShadowColor(0, 0, 0, 1)
                    tile.value:SetShadowOffset(2, -2)
                    tile.ownedGlow:Hide()
                end
            end

            if style then
                row.accent:SetColorTexture(unpack(style.color))
                row.accent:Show()
                row.status:SetText(style.label)
                row.status:SetTextColor(unpack(style.color))
            else
                row.accent:Hide()
                row.status:SetText("")
            end
            row.recommendationReason = entry.recommendationReason
            row.packageSize, row.packageTooltip = entry.numMembers, entry.packageTooltip

            row.invite.applicantID = entry.applicantID
            row.invite:SetText(entry.numMembers > 1 and (L("Пригласить ×") .. entry.numMembers) or L("Пригласить"))
            row.decline.applicantID = entry.applicantID
            row:Show()
        else
            row.invite.applicantID = nil
            row.decline.applicantID = nil
            row.recommendationReason = nil
            row.packageSize, row.packageTooltip = nil, nil
            for _, tile in ipairs(row.dungeonTiles) do
                tile.tooltipData = nil
                tile.dungeonName = nil
            end
            row:Hide()
        end
    end
end

function ApplicantBoard:Refresh()
    if not self.page then return end
    self:Layout()

    self:RefreshParty()
    local entries, missing = self:Collect()
    self.entries = entries
    self:UpdateLaunchDecision(entries)

    local visible = self.visibleRows or MAX_ROWS
    local maximum = math.max(0, #entries - visible)
    self.scrollBar:SetMinMaxValues(0, maximum)
    self.offset = math.min(self.offset or 0, maximum)
    self.scrollBar:SetValue(self.offset)
    self.scrollBar:SetShown(maximum > 0)
    self:Render()

    self.count:SetText(#entries > 0 and tostring(#entries) or "")
    if missing then
        self.needs:SetText((L("|cff8a939fнужно|r  %s %d   %s %d   %s %d")):format(
            UI.RoleIcon("TANK", 14), missing.TANK,
            UI.RoleIcon("HEALER", 14), missing.HEALER,
            UI.RoleIcon("DAMAGER", 14), missing.DAMAGER))
    else
        self.needs:SetText("")
    end

    if #entries == 0 then
        local listed = C_LFGList.GetActiveEntryInfo and C_LFGList.GetActiveEntryInfo()
        self.message:SetText(listed
            and L("Заявок пока нет.\nОни появятся здесь, как только кто-то откликнется.")
            or L("Ты сейчас не собираешь группу.\nСоздай объявление в поиске групп — заявки придут сюда."))
        self.message:Show()
        self.emptyAction:SetShown(not listed)
    else
        self.message:Hide()
        self.emptyAction:Hide()
    end
end

function ApplicantBoard:Create()
    if self.events then return end
    self.events = CreateFrame("Frame")
    for _, event in ipairs({ "LFG_LIST_APPLICANT_LIST_UPDATED", "LFG_LIST_APPLICANT_UPDATED", "GROUP_ROSTER_UPDATE" }) do
        self.events:RegisterEvent(event)
    end
    self.events:SetScript("OnEvent", function()
        local welcome = JP.modules.Welcome
        if welcome and welcome.currentPage == "applicants" and welcome.frame and welcome.frame:IsShown() then
            self:Refresh()
        end
    end)
end

function ApplicantBoard:Enable() end
function ApplicantBoard:Disable() end
function ApplicantBoard:Destroy() end

JP.ApplicantBoard = ApplicantBoard
JP:RegisterModule("ApplicantBoard", ApplicantBoard)
