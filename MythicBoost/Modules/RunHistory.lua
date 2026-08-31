local _, JP = ...
local L = JP.L
local UI = JP.UI
local C = UI.colors

local RunHistory = {}
local MAX_TEAMMATES = JP.Limits.HISTORY_TEAMMATES
local MAX_RUNS = JP.Limits.HISTORY_RUNS
local MAX_ROWS = 14
local ROW_HEIGHT = 32
local BASE_EVENTS = { "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_RESET" }
local TRACKING_EVENTS = { "COMBAT_LOG_EVENT_UNFILTERED", "ENCOUNTER_END" }

local function PrunePlayers(players)
    local ordered = {}
    for key, record in pairs(players) do
        if type(record) == "table" and type(record.name) == "string" and record.name ~= "" then
            ordered[#ordered + 1] = { key = key, at = tonumber(record.lastAt) or 0 }
        else
            players[key] = nil
        end
    end
    table.sort(ordered, function(a, b) return a.at > b.at end)
    for index = MAX_TEAMMATES + 1, #ordered do players[ordered[index].key] = nil end
end

local function Settings()
    local settings = JP.Settings("runHistory", { players = {}, runs = {} })
    if not settings then return nil end
    settings.players = type(settings.players) == "table" and settings.players or {}
    settings.runs = type(settings.runs) == "table" and settings.runs or {}
    for index = #settings.runs, 1, -1 do
        if type(settings.runs[index]) ~= "table" then table.remove(settings.runs, index) end
    end
    while #settings.runs > MAX_RUNS do table.remove(settings.runs) end
    PrunePlayers(settings.players)
    return settings
end

local SafeNumber, SafeText = JP.SafeNumber, JP.SafeString

local function FullUnitName(unit)
    local name, realm = UnitFullName(unit)
    name, realm = SafeText(name), SafeText(realm)
    if not name then return end
    return realm and realm ~= "" and (name .. "-" .. realm) or name
end

local function MapName(mapID)
    local info = JP.API.GetChallengeMap(mapID)
    return info and info.name or L("Неизвестное подземелье")
end

local function FormatDuration(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

local PLAY_INVITE_MESSAGE = "Hi! I'd like to invite you to play some Mythic+ keys! (c) Sent from the MythicBoost addon"

local function InviteToPlay(name)
    if type(name) ~= "string" or name == "" or issecretvalue(name) then return end
    -- record.name хранится как Имя-Realm, поэтому шёпот сразу уходит именно
    -- тому персонажу, с которым был пройден ключ. Отправка выполняется только
    -- по физическому клику пользователя.
    if type(SendChatMessage) ~= "function" then return end
    SendChatMessage(PLAY_INVITE_MESSAGE, "WHISPER", nil, name)
end

local function CurrentRoster()
    local members, byGUID = {}, {}
    local units = { "player" }
    for index = 1, 4 do
        local unit = "party" .. index
        if UnitExists(unit) then units[#units + 1] = unit end
    end
    for _, unit in ipairs(units) do
        local name = FullUnitName(unit)
        local guid = UnitGUID(unit)
        if name and guid then
            local _, classFile = UnitClass(unit)
            local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or "NONE"
            local profile = JP.GroupSearchUI and JP.GroupSearchUI.GetPartyMemberProfile
                and JP.GroupSearchUI:GetPartyMemberProfile(unit)
            local record = {
                name = name, guid = guid, classFile = SafeText(classFile), role = role,
                rating = profile and SafeNumber(profile.score) or 0, deaths = 0, interrupts = 0,
                isPlayer = UnitIsUnit and UnitIsUnit(unit, "player") or unit == "player",
            }
            members[#members + 1] = record
            byGUID[guid] = record
        end
    end
    return members, byGUID
end

function RunHistory:StartRun(resumed)
    local active = JP.API.GetActiveChallenge()
    local mapID, level = active and active.mapID, active and active.level
    if not SafeNumber(mapID) then return end
    local members, byGUID = CurrentRoster()
    local now, startedAt = GetTime(), GetTime()
    local apiStartedAt = active and active.startedAt
    if apiStartedAt and apiStartedAt > 0 and apiStartedAt <= now then startedAt = apiStartedAt end
    self.current = {
        mapID = mapID, mapName = MapName(mapID), level = SafeNumber(level) or 0,
        startedAt = startedAt, startedEpoch = time() - math.max(0, math.floor(now - startedAt)),
        members = members, byGUID = byGUID, encounters = {}, trackingPartial = resumed == true,
    }
    if self.events then
        for _, event in ipairs(TRACKING_EVENTS) do pcall(self.events.RegisterEvent, self.events, event) end
    end
end

function RunHistory:DiscardRun()
    self.current = nil
    if self.events then
        for _, event in ipairs(TRACKING_EVENTS) do pcall(self.events.UnregisterEvent, self.events, event) end
    end
end

function RunHistory:OnCombatLog()
    local run = self.current
    if not run or type(CombatLogGetCurrentEventInfo) ~= "function" then return end
    local _, event, _, sourceGUID, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
    if event == "SPELL_INTERRUPT" and run.byGUID[sourceGUID] then
        run.byGUID[sourceGUID].interrupts = run.byGUID[sourceGUID].interrupts + 1
    elseif event == "UNIT_DIED" and run.byGUID[destGUID] then
        run.byGUID[destGUID].deaths = run.byGUID[destGUID].deaths + 1
    end
end

function RunHistory:OnEncounterEnd(encounterID, encounterName, _, _, success)
    local run = self.current
    if not run or success ~= 1 then return end
    run.encounters[#run.encounters + 1] = {
        id = SafeNumber(encounterID), name = SafeText(encounterName) or L("Босс"),
        at = math.max(0, GetTime() - run.startedAt), success = true,
    }
end

local function CompletionInfo(run)
    local info = JP.API.GetChallengeCompletion()
    local mapID, level = info and info.mapID, info and info.level
    local duration, onTime = info and info.duration, info and info.onTime
    duration = duration and duration > 10000 and duration / 1000 or duration
    duration = duration or math.max(0, GetTime() - run.startedAt)
    return {
        mapID = mapID or run.mapID,
        level = level or run.level,
        duration = duration,
        onTime = onTime,
        upgrades = info and info.upgrades or 0,
        practiceRun = info and info.practiceRun == true,
        members = info and info.members,
    }
end

function RunHistory:FinishRun()
    local run = self.current
    if not run then return end
    self:DiscardRun()
    local completion = CompletionInfo(run)
    local mapID = SafeNumber(completion.mapID) or run.mapID
    local level = SafeNumber(completion.level) or run.level or 0
    local duration, onTime = completion.duration, completion.onTime
    local deathInfo = JP.API.GetChallengeDeaths()
    local deaths = deathInfo and deathInfo.count or 0
    local deathTime = deathInfo and deathInfo.timeLost or 0
    -- Некоторые версии API возвращали длительности в миллисекундах.
    if deathTime > math.max(10000, duration * 10) then deathTime = deathTime / 1000 end
    local mapInfo = JP.API.GetChallengeMap(mapID)
    local timeLimit = mapInfo and mapInfo.timeLimit
    if onTime == nil and timeLimit then onTime = duration <= timeLimit end

    -- В актуальном API Blizzard перечисляет именно завершивших забег. Если
    -- кто-то вышел раньше, не записываем ему чужой таймер как совместный успех.
    local completedGUIDs, completedCount = {}, 0
    for _, memberInfo in ipairs(type(completion.members) == "table" and completion.members or {}) do
        local guid = type(memberInfo) == "table" and SafeText(memberInfo.memberGUID)
        if guid and not completedGUIDs[guid] then
            completedGUIDs[guid], completedCount = true, completedCount + 1
        end
    end
    if completedCount > 0 then
        local completedMembers = {}
        for _, member in ipairs(run.members) do
            if completedGUIDs[member.guid] then completedMembers[#completedMembers + 1] = member end
        end
        run.members = completedMembers
    end

    -- Профиль Raider.IO мог ещё не быть готов на старте. Перед сохранением
    -- повторяем дешёвое чтение для тех же GUID, пока группа ещё существует.
    local _, finalRosterByGUID = CurrentRoster()
    for _, member in ipairs(run.members) do
        local latest = finalRosterByGUID[member.guid]
        if latest then
            if (tonumber(latest.rating) or 0) > 0 then member.rating = latest.rating end
            member.classFile = latest.classFile or member.classFile
            member.role = latest.role or member.role
        end
    end

    local interrupts = 0
    for _, member in ipairs(run.members) do interrupts = interrupts + (member.interrupts or 0) end
    local result = {
        mapID = mapID, mapName = MapName(mapID), level = level, duration = duration,
        onTime = onTime == true, upgrades = completion.upgrades, deaths = deaths,
        deathTime = deathTime, interrupts = interrupts, completedAt = time(),
        encounters = run.encounters, members = {}, practiceRun = completion.practiceRun,
        trackingPartial = run.trackingPartial == true,
    }

    local settings = Settings()
    if not settings then return end
    for _, member in ipairs(run.members) do
        result.members[#result.members + 1] = member.name
        if not member.isPlayer then
            local key = member.name:lower()
            local saved = settings.players[key] or {
                name = member.name, classFile = member.classFile, role = member.role,
                runs = 0, timed = 0, totalLevels = 0, bestLevel = 0,
                interrupts = 0, deaths = 0,
            }
            saved.name, saved.classFile, saved.role = member.name, member.classFile, member.role
            -- Рейтинг в таблице означает последнее увиденное значение, а не
            -- исторический максимум, который со временем стал бы вводить в заблуждение.
            if (tonumber(member.rating) or 0) > 0 then
                saved.rating, saved.ratingAt = tonumber(member.rating), result.completedAt
            end
            saved.runs = (saved.runs or 0) + 1
            saved.timed = (saved.timed or 0) + (result.onTime and 1 or 0)
            saved.totalLevels = (saved.totalLevels or 0) + level
            saved.bestLevel = math.max(saved.bestLevel or 0, level)
            saved.interrupts = (saved.interrupts or 0) + (member.interrupts or 0)
            saved.deaths = (saved.deaths or 0) + (member.deaths or 0)
            saved.lastMap, saved.lastLevel = result.mapName, level
            saved.lastAt, saved.lastTimed = result.completedAt, result.onTime
            settings.players[key] = saved
        end
    end
    table.insert(settings.runs, 1, result)
    while #settings.runs > MAX_RUNS do table.remove(settings.runs) end
    PrunePlayers(settings.players)
    self.lastRun = result
    self:Refresh()
end

local function CreateHistoryRow(parent, index)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(ROW_HEIGHT - 2)
    UI.Backdrop(row, index % 2 == 0 and C.rowAlt or C.row, C.lineSoft)
    row.name = UI.Text(row, "GameFontHighlightSmall", "", C.text)
    row.name:SetPoint("LEFT", 10, 0); row.name:SetWidth(250); row.name:SetJustifyH("LEFT")
    row.rating = UI.Text(row, "GameFontNormal", "—", C.amber)
    row.rating:SetPoint("LEFT", 270, 0); row.rating:SetWidth(90); row.rating:SetJustifyH("CENTER")
    row.runs = UI.Text(row, "GameFontHighlightSmall", "", C.text)
    row.runs:SetPoint("LEFT", 370, 0); row.runs:SetWidth(90); row.runs:SetJustifyH("CENTER")
    row.success = UI.Text(row, "GameFontHighlightSmall", "", C.green)
    row.success:SetPoint("LEFT", 470, 0); row.success:SetWidth(90); row.success:SetJustifyH("CENTER")
    row.last = UI.Text(row, "GameFontHighlightSmall", "", C.muted)
    row.last:SetPoint("LEFT", 570, 0); row.last:SetPoint("RIGHT", -250, 0); row.last:SetJustifyH("LEFT")
    row.date = UI.Text(row, "GameFontHighlightSmall", "", C.faint)
    row.date:SetPoint("RIGHT", -108, 0); row.date:SetWidth(132); row.date:SetJustifyH("RIGHT")
    row.whisper = UI.Button(row, L("Позвать"), 90, 22, true)
    row.whisper:SetPoint("RIGHT", -8, 0)
    row.whisper:SetScript("OnClick", function(owner)
        local record = owner:GetParent().record
        if record then InviteToPlay(record.name) end
    end)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        self:SetBackdropColor(UI.Unpack(C.rowHover))
        if self.record then
            local runs = tonumber(self.record.runs) or 0
            local timed = tonumber(self.record.timed) or 0
            local bestLevel = tonumber(self.record.bestLevel) or 0
            UI.Tooltip(self, self.record.name,
                (L("Вместе: %d ключей, в таймер %d, лучший +%d")):format(runs, timed, bestLevel),
                (L("Прерывания: %d, смерти: %d")):format(
                    tonumber(self.record.interrupts) or 0, tonumber(self.record.deaths) or 0))
        end
    end)
    row:SetScript("OnLeave", function(self) self:SetBackdropColor(UI.Unpack(self.baseColor or C.row)); GameTooltip_Hide() end)
    row.baseColor = index % 2 == 0 and C.rowAlt or C.row
    row:Hide()
    return row
end

function RunHistory:Build(_, page)
    self.page = page
    local report = UI.Panel(page, C.panel, C.line)
    report:SetPoint("TOPLEFT", 10, -10); report:SetPoint("TOPRIGHT", -10, -10); report:SetHeight(112)
    local title = UI.Text(report, "GameFontNormalLarge", L("ПОСЛЕДНИЙ КЛЮЧ"), C.accent)
    title:SetPoint("TOPLEFT", 14, -12)
    self.reportTitle = UI.Text(report, "GameFontNormal", L("Пока нет записанных прохождений"), C.text)
    self.reportTitle:SetPoint("TOPLEFT", 14, -42)
    self.reportSummary = UI.Text(report, "GameFontHighlightSmall", "", C.muted)
    self.reportSummary:SetPoint("TOPLEFT", 14, -66); self.reportSummary:SetPoint("RIGHT", -14, 0)
    self.reportDetail = UI.Text(report, "GameFontHighlightSmall", "", C.faint)
    self.reportDetail:SetPoint("TOPLEFT", 14, -88); self.reportDetail:SetPoint("RIGHT", -14, 0)

    local heading = UI.Text(page, "GameFontNormalSmall", L("ИСТОРИЯ НАПАРНИКОВ - СОРТИРОВКА ПО RIO"), C.accent)
    heading:SetPoint("TOPLEFT", 16, -140)
    local headers = {
        { L("ИГРОК"), 22, 250, "LEFT" }, { "RIO", 280, 90 }, { L("ВМЕСТЕ"), 380, 90 },
        { L("В ТАЙМЕР"), 480, 90 }, { L("ПОСЛЕДНИЙ КЛЮЧ"), 580, 220, "LEFT" }, { L("КОГДА"), -118, 130, "RIGHT", true },
    }
    for _, data in ipairs(headers) do
        local text = UI.Text(page, "GameFontNormalSmall", data[1], C.faint)
        if data[5] then text:SetPoint("TOPRIGHT", data[2], -162) else text:SetPoint("TOPLEFT", data[2], -162) end
        text:SetWidth(data[3]); text:SetJustifyH(data[4] or "CENTER")
    end
    self.rows = {}
    for index = 1, MAX_ROWS do
        local row = CreateHistoryRow(page, index)
        row:SetPoint("TOPLEFT", 12, -180 - (index - 1) * ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", -12, -180 - (index - 1) * ROW_HEIGHT)
        self.rows[index] = row
    end
    self.scrollBar = UI.ScrollBar(page)
    self.scrollBar:SetPoint("TOPRIGHT", -5, -180)
    self.scrollBar:SetPoint("BOTTOMRIGHT", -5, 12)
    self.scrollBar:SetScript("OnValueChanged", function(_, value)
        local offset = math.floor(value + .5)
        if offset ~= (self.offset or 0) then self.offset = offset; self:RenderPlayers() end
    end)
    self.scrollBar:Hide()
    UI.BindScrollWheel(page, self.scrollBar, self.rows, function() return self.offset or 0 end)
    self:Layout()
    self:Refresh()
end

function RunHistory:Layout()
    if not self.page or not self.rows then return end
    local height = self.page:GetHeight()
    if height < 100 then return end
    self.visibleRows = math.max(2, math.min(MAX_ROWS, math.floor((height - 198) / ROW_HEIGHT)))
    for index, row in ipairs(self.rows) do
        row.layoutVisible = index <= self.visibleRows
        if not row.layoutVisible then row:Hide() end
    end
end

function RunHistory:RenderPlayers()
    local players = self.sortedPlayers or {}
    local offset = self.offset or 0
    for index, row in ipairs(self.rows or {}) do
        local record = players[offset + index]
        if record and row.layoutVisible ~= false then
            row.record = record
            row.name:SetText(("%s  %s"):format(UI.ClassIcon(record.classFile, 16), record.name))
            row.name:SetTextColor(UI.ClassColor(record.classFile))
            local rating = tonumber(record.rating) or 0
            local runs, timed = tonumber(record.runs) or 0, tonumber(record.timed) or 0
            row.rating:SetText(rating > 0 and tostring(math.floor(rating + .5)) or "—")
            row.runs:SetText(tostring(runs))
            local rate = runs > 0 and math.floor(timed / runs * 100 + .5) or 0
            row.success:SetText(("%d%%"):format(rate))
            row.last:SetText(("%s  +%d"):format(record.lastMap or "—", tonumber(record.lastLevel) or 0))
            local lastAt = tonumber(record.lastAt)
            row.date:SetText(lastAt and date("%d.%m.%Y", lastAt) or "—")
            row:Show()
        else row.record = nil; row:Hide() end
    end
end

local function LongestSegment(run)
    local longest, label, previous = 0, nil, 0
    for _, encounter in ipairs(type(run.encounters) == "table" and run.encounters or {}) do
        local at = tonumber(encounter.at)
        if at and at >= previous then
            local segment = at - previous
            if segment > longest then
                longest, label = segment, (L("до %s")):format(encounter.name or L("босса"))
            end
            previous = at
        end
    end
    local finish = math.max(0, (tonumber(run.duration) or 0) - previous)
    if finish > longest then
        longest = finish
        label = previous > 0 and L("от последнего босса до финиша") or L("от старта до финиша")
    end
    return label, longest
end

function RunHistory:Refresh()
    if not self.page then return end
    self:Layout()
    local settings = Settings()
    if not settings then return end
    local last = settings.runs[1]
    if last then
        local status = last.practiceRun and L("ТРЕНИРОВОЧНЫЙ")
            or (last.onTime and L("В ТАЙМЕР") or L("НЕ В ТАЙМЕР"))
        self.reportTitle:SetText(("%s  +%d  %s"):format(
            last.mapName or L("Неизвестное подземелье"), tonumber(last.level) or 0, status))
        self.reportSummary:SetText((L("Время %s   -   смерти %d (%s штрафа)   -   прерывания %d")):format(
            FormatDuration(last.duration), tonumber(last.deaths) or 0,
            FormatDuration(last.deathTime), tonumber(last.interrupts) or 0)
            .. (last.trackingPartial and L("   -   прерывания записаны после /reload") or ""))
        local duration, deathTime = tonumber(last.duration) or 0, tonumber(last.deathTime) or 0
        local deathShare = duration > 0 and math.min(100, math.floor(deathTime / duration * 100 + .5)) or 0
        local loss = deathTime > 0
            and (L("Главная измеримая потеря: смерти — %s (%d%% времени)")):format(FormatDuration(deathTime), deathShare)
            or L("Штрафа за смерти не было — ищи потери в маршруте, простоях и уроне.")
        local segmentLabel, segmentTime = LongestSegment(last)
        local segment = segmentLabel and (L("самый длинный отрезок: %s — %s")):format(segmentLabel, FormatDuration(segmentTime))
        self.reportDetail:SetText(segment and (loss .. "   -   " .. segment) or loss)
    else
        self.reportTitle:SetText(L("Пока нет записанных прохождений")); self.reportSummary:SetText(""); self.reportDetail:SetText("")
    end

    local players = {}
    for _, record in pairs(settings.players) do players[#players + 1] = record end
    table.sort(players, function(a, b)
        local ar, br = tonumber(a.rating) or 0, tonumber(b.rating) or 0
        if ar ~= br then return ar > br end
        local at, bt = tonumber(a.timed) or 0, tonumber(b.timed) or 0
        if at ~= bt then return at > bt end
        local aa, ba = tonumber(a.lastAt) or 0, tonumber(b.lastAt) or 0
        if aa ~= ba then return aa > ba end
        return tostring(a.name or "") < tostring(b.name or "")
    end)
    self.sortedPlayers = players
    local maximum = math.max(0, #players - (self.visibleRows or MAX_ROWS))
    self.offset = math.min(self.offset or 0, maximum)
    self.scrollBar:SetMinMaxValues(0, maximum)
    self.scrollBar:SetValue(self.offset)
    self.scrollBar:SetShown(maximum > 0)
    self:RenderPlayers()
end

function RunHistory:Create()
    if self.events then return end
    self.events = CreateFrame("Frame")
    self.events:SetScript("OnEvent", function(_, event, ...)
        if event == "CHALLENGE_MODE_START" then self:StartRun()
        elseif event == "CHALLENGE_MODE_COMPLETED" then self:FinishRun()
        elseif event == "CHALLENGE_MODE_RESET" then self:DiscardRun()
        elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then self:OnCombatLog()
        elseif event == "ENCOUNTER_END" then self:OnEncounterEnd(...) end
    end)
end

function RunHistory:Enable()
    Settings()
    if not self.events then return end
    for _, event in ipairs(BASE_EVENTS) do pcall(self.events.RegisterEvent, self.events, event) end
    local active = JP.API.GetActiveChallenge()
    if active and active.active then self:StartRun(true) end
end
function RunHistory:Disable()
    if self.events then self.events:UnregisterAllEvents() end
    self.current = nil
end
function RunHistory:Destroy() self:DiscardRun() end

JP.RunHistory = RunHistory
JP:RegisterModule("RunHistory", RunHistory)
