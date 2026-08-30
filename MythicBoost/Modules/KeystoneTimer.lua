local _, JP = ...
local L = JP.L
local UI, C = JP.UI, JP.UI.colors
local KeystoneTimer = { bosses = {}, bossRows = {}, pending = {} }

local DEFAULTS = {
    enabled = true,
    hideTracker = true,
    showBosses = true,
    showBossSplits = true,
    showForces = true,
    showDeaths = true,
    showChestTimers = true,
    showAffixes = true,
    autoSlotKey = true,
    closeBags = true,
    autoGossip = true,
    scale = 1,
    width = 330,
}

local function Settings()
    local settings = JP.Settings("keystoneTimer", DEFAULTS) or {}
    settings.best = type(settings.best) == "table" and settings.best or {}
    return settings
end

local UsableNumber, UsableString = UI.UsableNumber, UI.UsableString

local function FormatTime(seconds, decimals)
    if not UsableNumber(seconds) then return "--:--" end
    seconds = math.max(0, seconds)
    local minutes = math.floor(seconds / 60)
    local remainder = seconds - minutes * 60
    if decimals then return ("%d:%04.1f"):format(minutes, remainder) end
    return ("%d:%02d"):format(minutes, math.floor(remainder + .5))
end

local function FormatDelta(seconds)
    if not UsableNumber(seconds) then return "" end
    local prefix = seconds > .05 and "+" or (seconds < -.05 and "-" or "±")
    return prefix .. FormatTime(math.abs(seconds), false)
end

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return end
    local values = { pcall(fn, ...) }
    if not table.remove(values, 1) then return end
    return unpack(values)
end

function KeystoneTimer:IsActive()
    return Settings().enabled and C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
        and C_ChallengeMode.IsChallengeModeActive()
end

function KeystoneTimer:GetElapsed()
    local elapsed = type(GetWorldElapsedTime) == "function" and select(2, GetWorldElapsedTime(1))
    if UsableNumber(elapsed) and elapsed >= 0 then return elapsed end
    if self.startedAt then return math.max(0, GetTime() - self.startedAt) end
    return 0
end

function KeystoneTimer:GetPB()
    local settings = Settings()
    local season = settings.best[self.seasonID or 0]
    local map = season and season[self.mapID]
    if not map then return end
    if map[self.level] then return map[self.level] end
    -- The old profile used LowerKey=true. A lower-key PB is still a useful
    -- comparison when the exact level has not been completed yet.
    for level = (self.level or 0) - 1, 2, -1 do
        if map[level] then return map[level] end
    end
end

local function CopyRun(data)
    if type(data) ~= "table" then return end
    local finish = tonumber(data.finish)
    if finish and finish > 100000 then finish = finish / 1000 end
    local run = { finish = finish, forces = tonumber(data.forces), bosses = {} }
    for index = 1, 8 do
        local value = tonumber(data[index]) or (type(data.bosses) == "table" and tonumber(data.bosses[index]))
        if value then run.bosses[index] = value end
    end
    return run
end

-- One-time migration while MPlusTimer is still installed. We copy only the
-- user's numeric PB data; no source code, UI objects or profile internals.
function KeystoneTimer:ImportMPlusTimerHistory()
    local settings = Settings()
    if settings.mptHistoryImported or type(MPTSV) ~= "table" or type(MPTSV.BestTime) ~= "table" then return end
    local imported = 0
    for seasonID, maps in pairs(MPTSV.BestTime) do
        if type(maps) == "table" then
            settings.best[seasonID] = settings.best[seasonID] or {}
            for mapID, levels in pairs(maps) do
                if type(levels) == "table" then
                    settings.best[seasonID][mapID] = settings.best[seasonID][mapID] or {}
                    for level, data in pairs(levels) do
                        if type(level) == "number" then
                            local run = CopyRun(data)
                            if run then settings.best[seasonID][mapID][level] = run; imported = imported + 1 end
                        end
                    end
                end
            end
        end
    end
    settings.mptHistoryImported = true
    if imported > 0 then
        JP:Print((L("Импортирована история MPlusTimer: %d лучших забегов.")):format(imported))
        -- Импорт разовый, и после него MPlusTimer нужен только как источник
        -- данных, которого больше нет. Пока он загружен, таймера на экране два.
        JP:Print(L("|cffffb93dТеперь MPlusTimer можно отключить|r — рекорды уже у нас, а два таймера рисуются одновременно."))
    end
end

local function MakeText(parent, template, color)
    local text = UI.Text(parent, template or "GameFontHighlightSmall", "", color or C.text)
    text:SetWordWrap(false)
    return text
end

function KeystoneTimer:CreateBossRow(index)
    if self.bossRows[index] then return self.bossRows[index] end
    local row = CreateFrame("Frame", nil, self.frame)
    row:SetHeight(18)
    row.name = MakeText(row, "GameFontHighlightSmall", C.text)
    row.name:SetPoint("LEFT", 2, 0)
    row.name:SetPoint("RIGHT", -104, 0)
    row.name:SetJustifyH("LEFT")
    row.time = MakeText(row, "GameFontHighlightSmall", C.muted)
    row.time:SetPoint("RIGHT", -48, 0)
    row.split = MakeText(row, "GameFontHighlightSmall", C.muted)
    row.split:SetPoint("RIGHT", -2, 0)
    self.bossRows[index] = row
    return row
end

function KeystoneTimer:BuildFrame()
    if self.frame then return end
    local settings = Settings()
    local frame = CreateFrame("Frame", "MythicBoostKeystoneTimer", UIParent)
    frame:SetSize(settings.width, 160)
    frame:SetScale(settings.scale)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    local position = settings.position
    if type(position) == "table" and UsableNumber(position.x) and UsableNumber(position.y) then
        frame:SetPoint(position.point or "RIGHT", UIParent, position.relativePoint or position.point or "RIGHT", position.x, position.y)
    else
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -24, 220)
    end
    frame:SetScript("OnDragStart", function(owner) owner:StartMoving() end)
    frame:SetScript("OnDragStop", function(owner)
        owner:StopMovingOrSizing()
        local point, _, relativePoint, x, y = owner:GetPoint()
        Settings().position = { point = point, relativePoint = relativePoint, x = x, y = y }
    end)

    frame.header = CreateFrame("Frame", nil, frame)
    frame.header:SetPoint("TOPLEFT", 0, 0); frame.header:SetPoint("TOPRIGHT", 0, 0); frame.header:SetHeight(20)
    frame.headerLine = UI.Line(frame.header, C.edge)
    frame.headerLine:SetPoint("BOTTOMLEFT", 0, 0); frame.headerLine:SetPoint("BOTTOMRIGHT", 0, 0)
    frame.title = MakeText(frame.header, "GameFontNormal", C.text)
    frame.title:SetPoint("LEFT", 2, 1); frame.title:SetPoint("RIGHT", -112, 1); frame.title:SetJustifyH("LEFT")
    frame.deaths = MakeText(frame.header, "GameFontHighlightSmall", C.red)
    frame.deaths:SetPoint("RIGHT", -2, 1)

    frame.timer, frame.timerHolder = UI.StatusBar(frame, 23, C.green)
    frame.timerHolder:SetPoint("TOPLEFT", frame.header, "BOTTOMLEFT", 0, -3)
    frame.timerHolder:SetPoint("TOPRIGHT", frame.header, "BOTTOMRIGHT", 0, -3)
    frame.elapsed = MakeText(frame.timer, "GameFontNormal", C.text)
    frame.elapsed:SetPoint("LEFT", 5, 0)
    frame.chests = MakeText(frame.timer, "GameFontHighlightSmall", C.muted)
    frame.chests:SetPoint("RIGHT", -5, 0)

    frame.bossAnchor = CreateFrame("Frame", nil, frame)
    frame.bossAnchor:SetPoint("TOPLEFT", frame.timerHolder, "BOTTOMLEFT", 0, -3)
    frame.bossAnchor:SetPoint("TOPRIGHT", frame.timerHolder, "BOTTOMRIGHT", 0, -3)
    frame.bossAnchor:SetHeight(1)

    frame.forces, frame.forcesHolder = UI.StatusBar(frame, 23, C.accent)
    frame.forcesLabel = MakeText(frame.forces, "GameFontHighlightSmall", C.text)
    frame.forcesLabel:SetPoint("LEFT", 5, 0)
    frame.forcesCount = MakeText(frame.forces, "GameFontHighlightSmall", C.text)
    frame.forcesCount:SetPoint("RIGHT", -5, 0)

    frame.hint = MakeText(frame, "GameFontHighlightSmall", C.muted)
    frame.hint:SetPoint("TOPLEFT", frame.forcesHolder, "BOTTOMLEFT", 2, -3)
    frame.hint:SetPoint("RIGHT", -2, 0)
    frame.hint:SetJustifyH("LEFT")
    frame:Hide()
    self.frame = frame
end

function KeystoneTimer:ReadScenario()
    wipe(self.bosses)
    local _, _, criteriaCount = SafeCall(C_Scenario and C_Scenario.GetStepInfo)
    if not UsableNumber(criteriaCount) or criteriaCount <= 0 then return end
    local elapsed = self:GetElapsed()
    for index = 1, criteriaCount do
        local data = SafeCall(C_ScenarioInfo and C_ScenarioInfo.GetCriteriaInfo, index)
        if type(data) == "table" then
            if data.isWeightedProgress then
                self.forcesData = data
                local current = tonumber(data.quantityString) or tonumber(data.quantity) or 0
                local total = tonumber(data.totalQuantity) or 100
                if current > (self.lastForces or 0) then self.lastForcesGain = current - (self.lastForces or current) end
                self.lastForces = current
                if data.completed and not self.forcesCompletedAt then
                    self.forcesCompletedAt = UsableNumber(data.elapsed) and math.max(0, elapsed - data.elapsed) or elapsed
                end
            else
                local boss = {
                    name = UsableString(data.description) and data.description or (L("Босс ") .. index),
                    completed = data.completed and not issecretvalue(data.completed) or false,
                }
                if boss.completed then
                    if not self.bossTimes[index] then
                        self.bossTimes[index] = UsableNumber(data.elapsed) and math.max(0, elapsed - data.elapsed) or elapsed
                    end
                    boss.time = self.bossTimes[index]
                end
                self.bosses[#self.bosses + 1] = boss
            end
        end
    end
end

function KeystoneTimer:UpdateLayout()
    if not self.frame then return end
    local settings, frame = Settings(), self.frame
    frame:SetWidth(settings.width)
    frame:SetScale(settings.scale)
    local previous = frame.bossAnchor
    local shown = 0
    for index in ipairs(self.bosses) do
        local row = self:CreateBossRow(index)
        if settings.showBosses then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", previous, index == 1 and "TOPLEFT" or "BOTTOMLEFT", 0, index == 1 and 0 or -1)
            row:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
            row:Show(); previous = row; shown = shown + 1
        else row:Hide() end
    end
    for index = #self.bosses + 1, #self.bossRows do self.bossRows[index]:Hide() end
    frame.forcesHolder:ClearAllPoints()
    frame.forcesHolder:SetPoint("TOPLEFT", previous, shown == 0 and "TOPLEFT" or "BOTTOMLEFT", 0, shown == 0 and 0 or -3)
    frame.forcesHolder:SetPoint("TOPRIGHT", previous, shown == 0 and "TOPRIGHT" or "BOTTOMRIGHT", 0, shown == 0 and 0 or -3)
    frame.forcesHolder:SetShown(settings.showForces)
    local height = 20 + 3 + 23 + 3 + shown * 19 + (settings.showForces and 26 or 0) + 18
    frame:SetHeight(height)
end

function KeystoneTimer:UpdateDisplay()
    if not self.frame then return end
    local settings, frame = Settings(), self.frame
    if not (self:IsActive() or self.preview) then frame:Hide(); return end
    local elapsed = self.preview and 735.4 or self:GetElapsed()
    local limit = self.preview and 1800 or self.timeLimit or 1
    local ratio = limit > 0 and elapsed / limit or 0
    frame.timer:SetMinMaxValues(0, math.max(limit, elapsed, 1)); frame.timer:SetValue(elapsed)
    if ratio <= .60 then frame.timer:SetStatusBarColor(C.green[1], C.green[2], C.green[3])
    elseif ratio <= .80 then frame.timer:SetStatusBarColor(C.accent[1], C.accent[2], C.accent[3])
    elseif ratio <= 1 then frame.timer:SetStatusBarColor(C.amber[1], C.amber[2], C.amber[3])
    else frame.timer:SetStatusBarColor(C.red[1], C.red[2], C.red[3]) end
    frame.elapsed:SetText(FormatTime(elapsed, true) .. " / " .. FormatTime(limit))
    frame.chests:SetText(settings.showChestTimers and
        (("+3 %s   +2 %s"):format(FormatTime(limit * .60), FormatTime(limit * .80))) or "")

    local dungeon = self.dungeonName or "Mythic+"
    frame.title:SetText(("+%d  %s"):format(self.level or 0, dungeon))
    local deaths, lost = 0, 0
    if not self.preview and C_ChallengeMode and C_ChallengeMode.GetDeathCount then
        deaths, lost = C_ChallengeMode.GetDeathCount()
    elseif self.preview then deaths, lost = 2, 10 end
    frame.deaths:SetText(settings.showDeaths and deaths and deaths > 0
        and ((L("x%d  -%sс")):format(deaths, tostring(math.floor((tonumber(lost) or 0) + .5)))) or "")

    local pb = self:GetPB()
    for index, boss in ipairs(self.bosses) do
        local row = self.bossRows[index]
        if row then
            row.name:SetText((boss.completed and "|cff47eb8f✓|r  " or "|cff7f8b99•|r  ") .. boss.name)
            row.name:SetTextColor(boss.completed and C.green[1] or C.text[1], boss.completed and C.green[2] or C.text[2], boss.completed and C.green[3] or C.text[3])
            local target = pb and pb.bosses and pb.bosses[index]
            row.time:SetText(boss.time and FormatTime(boss.time) or (target and ("PB " .. FormatTime(target)) or ""))
            local delta = boss.time and target and boss.time - target
            row.split:SetText(settings.showBossSplits and delta and FormatDelta(delta) or "")
            row.split:SetTextColor(delta and delta <= 0 and C.green[1] or C.red[1], delta and delta <= 0 and C.green[2] or C.red[2], delta and delta <= 0 and C.green[3] or C.red[3])
        end
    end

    local data = self.forcesData
    local current = data and (tonumber(data.quantityString) or tonumber(data.quantity)) or 0
    local total = data and tonumber(data.totalQuantity) or 100
    if self.preview then current, total = 342, 550 end
    local percent = total > 0 and current / total * 100 or 0
    frame.forces:SetMinMaxValues(0, math.max(total, 1)); frame.forces:SetValue(current)
    frame.forces:SetStatusBarColor(percent >= 100 and C.green[1] or C.accent[1], percent >= 100 and C.green[2] or C.accent[2], percent >= 100 and C.green[3] or C.accent[3])
    frame.forcesLabel:SetText((L("Враги  %.1f%%")):format(percent))
    frame.forcesCount:SetText(("%d / %d"):format(current, total))
    local pbFinish = pb and tonumber(pb.finish)
    frame.hint:SetText(pbFinish and ((L("Лучший забег: %s   •   текущий прогноз: %s")):format(FormatTime(pbFinish), FormatDelta(elapsed - pbFinish))) or "")
    frame:Show()
end

function KeystoneTimer:ApplyTracker()
    local tracker = _G.ObjectiveTrackerFrame
    if not tracker then return end
    local shouldHide = Settings().hideTracker and (self:IsActive() or self.preview)
    if InCombatLockdown() and tracker.IsProtected and tracker:IsProtected() then
        self.pending.tracker = true; return
    end
    if shouldHide then
        if not self.trackerState then
            self.trackerState = { alpha = tracker:GetAlpha(), mouse = tracker:IsMouseEnabled() }
        end
        tracker:SetAlpha(0); tracker:EnableMouse(false)
    elseif self.trackerState then
        tracker:SetAlpha(self.trackerState.alpha or 1)
        tracker:EnableMouse(self.trackerState.mouse and true or false)
        self.trackerState = nil
    end
end

function KeystoneTimer:Start(preview)
    self.preview = preview and true or false
    self:BuildFrame()
    self.bossTimes, self.forcesCompletedAt, self.lastForces = {}, nil, nil
    if self.preview then
        self.mapID, self.level, self.timeLimit, self.dungeonName = 586, 11, 1800, L("Закоулок душегубов")
        self.bosses = {
            { name = L("Первый босс"), completed = true, time = 410 },
            { name = L("Второй босс"), completed = false },
            { name = L("Финальный босс"), completed = false },
        }
    else
        self.mapID = SafeCall(C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID)
        self.level, self.affixes = SafeCall(C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo)
        self.dungeonName, _, self.timeLimit = SafeCall(C_ChallengeMode and C_ChallengeMode.GetMapUIInfo, self.mapID)
        self.seasonID = SafeCall(C_MythicPlus and C_MythicPlus.GetCurrentSeason) or 0
        self.startedAt = GetTime()
        self:ReadScenario()
    end
    self:UpdateLayout(); self:UpdateDisplay(); self:ApplyTracker()
    if self.ticker then self.ticker:Cancel() end
    self.ticker = C_Timer.NewTicker(.2, function()
        if self:IsActive() or self.preview then self:UpdateDisplay() else self:Stop() end
    end)
end

function KeystoneTimer:StoreCompletedRun()
    if not self.mapID or not self.level then return end
    local info = SafeCall(C_ChallengeMode and C_ChallengeMode.GetChallengeCompletionInfo)
    local finish = info and tonumber(info.time)
    if finish and finish > 100000 then finish = finish / 1000 end
    finish = finish or self:GetElapsed()
    local settings = Settings()
    local seasonID = self.seasonID or SafeCall(C_MythicPlus and C_MythicPlus.GetCurrentSeason) or 0
    settings.best[seasonID] = settings.best[seasonID] or {}
    settings.best[seasonID][self.mapID] = settings.best[seasonID][self.mapID] or {}
    local previous = settings.best[seasonID][self.mapID][self.level]
    if not previous or not previous.finish or finish < previous.finish then
        settings.best[seasonID][self.mapID][self.level] = {
            finish = finish, bosses = CopyTable(self.bossTimes), forces = self.forcesCompletedAt,
            date = date("%Y-%m-%d"),
        }
    end
end

function KeystoneTimer:Stop()
    self.preview = false
    if self.ticker then self.ticker:Cancel(); self.ticker = nil end
    if self.frame then self.frame:Hide() end
    self:ApplyTracker()
end

function KeystoneTimer:SetEnabled(enabled)
    Settings().enabled = enabled and true or false
    if Settings().enabled and C_ChallengeMode.IsChallengeModeActive() then self:Start(false) else self:Stop() end
end

function KeystoneTimer:TogglePreview()
    if self.preview then self:Stop() else self:Start(true) end
end

function KeystoneTimer:AutoSlotKey()
    if not Settings().autoSlotKey or IsShiftKeyDown() or not C_Container
        or type(C_Container.GetContainerNumSlots) ~= "function"
        or type(C_Container.GetContainerItemID) ~= "function"
        or type(C_Container.UseContainerItem) ~= "function" then return end
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local slotCount = C_Container.GetContainerNumSlots(bag)
        slotCount = UI.UsableNumber(slotCount) and slotCount or 0
        for slot = 1, slotCount do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID and C_Item and C_Item.IsItemKeystoneByID and C_Item.IsItemKeystoneByID(itemID) then
                pcall(C_Container.UseContainerItem, bag, slot)
                return
            end
        end
    end
end

function KeystoneTimer:AutoGossip()
    if not Settings().autoGossip or not self:IsActive() or IsControlKeyDown() or not C_GossipInfo then return end
    local options = C_GossipInfo.GetOptions and C_GossipInfo.GetOptions() or {}
    -- Generic automation is safe only when there is exactly one choice. The
    -- original addon carries a dungeon-specific allowlist which would become
    -- stale every season; Ctrl always provides a manual override.
    if #options == 1 and options[1].gossipOptionID then
        pcall(C_GossipInfo.SelectOption, options[1].gossipOptionID)
    end
end

function KeystoneTimer:OnEvent(event, arg1)
    if event == "ADDON_LOADED" and arg1 == "MPlusTimer" then
        C_Timer.After(0, function() self:ImportMPlusTimerHistory() end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1, function()
            self:ImportMPlusTimerHistory()
            if self:IsActive() then self:Start(false) else self:Stop() end
        end)
    elseif event == "CHALLENGE_MODE_START" then
        self:Start(false)
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        self:ReadScenario(); self:StoreCompletedRun(); self:UpdateDisplay()
        C_Timer.After(8, function() self:Stop() end)
    elseif event == "SCENARIO_CRITERIA_UPDATE" or event == "SCENARIO_POI_UPDATE" then
        if self:IsActive() then self:ReadScenario(); self:UpdateLayout(); self:UpdateDisplay() end
    elseif event == "CHALLENGE_MODE_DEATH_COUNT_UPDATED" then
        self:UpdateDisplay()
    elseif event == "CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN" then
        self:AutoSlotKey()
    elseif event == "CHALLENGE_MODE_KEYSTONE_SLOTTED" then
        if Settings().closeBags and not IsShiftKeyDown() and type(CloseAllBags) == "function" then CloseAllBags() end
    elseif event == "GOSSIP_SHOW" then
        self:AutoGossip()
    elseif event == "PLAYER_REGEN_ENABLED" and self.pending.tracker then
        self.pending.tracker = nil; self:ApplyTracker()
    end
end

function KeystoneTimer:Create()
    if self.events then return end
    self:BuildFrame()
    self.events = CreateFrame("Frame")
    for _, event in ipairs({
        "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "CHALLENGE_MODE_START",
        "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_DEATH_COUNT_UPDATED", "SCENARIO_CRITERIA_UPDATE",
        "SCENARIO_POI_UPDATE", "CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN",
        "CHALLENGE_MODE_KEYSTONE_SLOTTED", "GOSSIP_SHOW",
    }) do self.events:RegisterEvent(event) end
    self.events:SetScript("OnEvent", function(_, event, ...) self:OnEvent(event, ...) end)
end

-- Рекорды ложатся в SavedVariables посезонными вёдрами и раньше не чистились
-- никогда: каждый сезон — восемь подземелий на два десятка уровней, и в
-- каждой записи ещё таблица времён по боссам. Прошлый сезон оставляем:
-- сразу после смены сезона с ним ещё сравниваются результаты.
function KeystoneTimer:PruneOldSeasons()
    local current = SafeCall(C_MythicPlus and C_MythicPlus.GetCurrentSeason)
    -- Ноль и nil приходят, пока игра ещё не отдала сезон. Чистить по такому
    -- ответу — значит однажды стереть всё на ровном месте.
    if not UI.UsableNumber(current) or current <= 0 then return end
    local best = Settings().best
    for seasonID in pairs(best) do
        local season = tonumber(seasonID)
        if not season or season < current - 1 then best[seasonID] = nil end
    end
end

function KeystoneTimer:Enable()
    Settings()
    C_Timer.After(1.5, function()
        self:PruneOldSeasons()
        self:ImportMPlusTimerHistory()
        if self:IsActive() then self:Start(false) end
    end)
end

function KeystoneTimer:Disable() self:Stop() end
function KeystoneTimer:Destroy() self:Stop() end

JP.KeystoneTimer = KeystoneTimer
JP:RegisterModule("KeystoneTimer", KeystoneTimer)
