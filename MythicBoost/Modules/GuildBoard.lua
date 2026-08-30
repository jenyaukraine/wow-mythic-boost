local _, JP = ...
local L = JP.L
local GuildBoard = {}
local UI = JP.UI
local C = UI.colors

local PODIUM_COUNT = 3      -- тройка лидеров крупно
local LIST_ROW_POOL = 60    -- виртуальные строки; данные листаются независимо от высоты окна
local CACHE_SECONDS = 60
local MEDAL_COLORS = {
    { 1, .82, .28, 1 },
    { .78, .82, .88, 1 },
    { .80, .55, .32, 1 },
}

local UsableNumber, SafeString = UI.UsableNumber, UI.SafeString

---------------------------------------------------------------------------
-- Данные гильдии
---------------------------------------------------------------------------

local function BestKeyLevel(keystone)
    local best = 0
    for _, run in ipairs(keystone.sortedDungeons or {}) do
        local level = UsableNumber(run.level) and run.level or 0
        if level > best then best = level end
    end
    return best
end

local function MemberProfile(name)
    if not RaiderIO or type(RaiderIO.GetProfile) ~= "function" then return end
    local ok, profile = pcall(RaiderIO.GetProfile, name)
    return ok and profile and profile.mythicKeystoneProfile or nil
end

function GuildBoard:Collect(force)
    if not IsInGuild or not IsInGuild() then
        return nil, L("Ты не состоишь в гильдии.")
    end
    if not RaiderIO or type(RaiderIO.GetProfile) ~= "function" then
        return nil, L("Нужен аддон Raider.IO — рейтинг гильдейцев берётся из его базы.")
    end
    if not force and self.cache and (GetTime() - self.cacheTime) < CACHE_SECONDS then
        return self.cache
    end

    local total = GetNumGuildMembers()
    if not total or total == 0 then
        return nil, L("Список гильдии ещё не загружен. Нажми «Обновить».")
    end

    local maxLevel = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion() or 0
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    local entries, scanned = {}, 0

    for index = 1, total do
        local name, _, _, level, _, _, _, _, online, _, classFile = GetGuildRosterInfo(index)
        name = SafeString(name)
        if name
            and (not self.onlyOnline or online)
            and (maxLevel == 0 or (UsableNumber(level) and level >= maxLevel)) then
            scanned = scanned + 1
            -- Имена гильдейцев однозначны: свой реалм либо явный суффикс.
            local fullName = name:find("-", 1, true) and name or (realm and (name .. "-" .. realm)) or name
            local keystone = MemberProfile(fullName)
            local score = UI.KeystoneScore(keystone)
            if score then
                entries[#entries + 1] = {
                    name = name:match("^([^%-]+)") or name,
                    fullName = fullName,
                    classFile = classFile,
                    score = score,
                    bestKey = BestKeyLevel(keystone),
                    online = online and true or false,
                }
            end
        end
    end

    table.sort(entries, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.bestKey ~= b.bestKey then return a.bestKey > b.bestKey end
        return a.name < b.name
    end)

    self.cache, self.cacheTime, self.scanned = entries, GetTime(), scanned
    JP:Log(L("гильдия: %d из %d персонажей с рейтингом"), #entries, scanned)
    return entries
end

---------------------------------------------------------------------------
-- Интерфейс
---------------------------------------------------------------------------

local function CreatePodiumCard(parent, place)
    local card = UI.Panel(parent, C.raised, C.line)
    card.place = place

    local medal = UI.Text(card, "GameFontNormalHuge", tostring(place), MEDAL_COLORS[place])
    medal:SetPoint("TOPLEFT", 14, -12)
    card.medal = medal

    card.name = UI.Text(card, "GameFontNormalLarge", "", C.text)
    card.name:SetPoint("TOPLEFT", 46, -14)
    card.name:SetPoint("TOPRIGHT", -14, -14)
    card.name:SetJustifyH("LEFT")
    card.name:SetWordWrap(false)

    card.score = UI.Text(card, "GameFontNormalHuge", "", C.amber)
    card.score:SetPoint("BOTTOMLEFT", 14, 14)

    card.detail = UI.Text(card, "GameFontHighlightSmall", "", C.muted)
    card.detail:SetPoint("BOTTOMRIGHT", -14, 18)
    card.detail:SetJustifyH("RIGHT")

    local glow = card:CreateTexture(nil, "OVERLAY")
    glow:SetColorTexture(unpack(MEDAL_COLORS[place]))
    glow:SetPoint("TOPLEFT", 1, -1)
    glow:SetPoint("TOPRIGHT", -1, -1)
    glow:SetHeight(2)

    card:Hide()
    return card
end

local function CreateListRow(parent, index)
    local row = UI.Panel(parent, index % 2 == 0 and C.rowAlt or C.row, C.lineSoft)
    row:SetHeight(26)

    row.rank = UI.Text(row, "GameFontHighlightSmall", "", C.faint)
    row.rank:SetPoint("LEFT", 12, 0)
    row.rank:SetWidth(28)
    row.rank:SetJustifyH("CENTER")

    row.name = UI.Text(row, "GameFontHighlightSmall", "", C.text)
    row.name:SetPoint("LEFT", 46, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -220, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.best = UI.Text(row, "GameFontHighlightSmall", "", C.muted)
    row.best:SetPoint("RIGHT", -130, 0)
    row.best:SetWidth(80)
    row.best:SetJustifyH("CENTER")

    row.status = UI.Text(row, "GameFontHighlightSmall", "", C.faint)
    row.status:SetPoint("RIGHT", -84, 0)
    row.status:SetWidth(44)
    row.status:SetJustifyH("CENTER")

    row.score = UI.Text(row, "GameFontNormalSmall", "", C.amber)
    row.score:SetPoint("RIGHT", -14, 0)
    row.score:SetWidth(64)
    row.score:SetJustifyH("RIGHT")

    row:Hide()
    return row
end

function GuildBoard:Build(welcome, page)
    local title = UI.Text(page, "GameFontNormalSmall", L("РЕЙТИНГ ГИЛЬДИИ"), C.muted)
    title:SetPoint("TOPLEFT", 16, -14)

    self.guildName = UI.Text(page, "GameFontHighlightSmall", "", C.accent)
    self.guildName:SetPoint("LEFT", title, "RIGHT", 12, 0)

    -- Для мгновенной фильтрации загружаем полный ростер, но сам фильтр
    -- «Только онлайн» при каждом запуске выключен.
    self.onlyOnline = false
    self.cache = nil
    if SetGuildRosterShowOffline then
        SetGuildRosterShowOffline(true)
        self.awaitingFullRoster = true
    end
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster()
    elseif GuildRoster then GuildRoster() end
    self.onlineOnly = UI.CheckBox(page, L("Только онлайн"), false,
        function(checked)
            self.onlyOnline = checked and true or false
            self.cache = nil
            self:Refresh()
    end)
    self.onlineOnly:SetSize(150, 22)
    self.onlineOnly:SetPoint("TOPRIGHT", -14, -11)

    self.podium = {}
    for place = 1, PODIUM_COUNT do
        local card = CreatePodiumCard(page, place)
        self.podium[place] = card
    end

    self.listHeader = UI.Text(page, "GameFontNormalSmall", L("ОСНОВНОЙ СОСТАВ"), C.faint)
    self.listHeader:SetPoint("TOPLEFT", 16, -142)
    local scoreHeader = UI.Text(page, "GameFontNormalSmall", L("РЕЙТИНГ"), C.faint)
    scoreHeader:SetPoint("TOPRIGHT", -14, -142)
    scoreHeader:SetWidth(64)
    scoreHeader:SetJustifyH("RIGHT")
    local bestHeader = UI.Text(page, "GameFontNormalSmall", L("ЛУЧШИЙ КЛЮЧ"), C.faint)
    bestHeader:SetPoint("TOPRIGHT", -130, -142)
    bestHeader:SetWidth(80)
    bestHeader:SetJustifyH("CENTER")

    self.rows = {}
    for index = 1, LIST_ROW_POOL do
        local row = CreateListRow(page, index)
        row:SetPoint("TOPLEFT", 14, -162 - (index - 1) * 28)
        row:SetPoint("TOPRIGHT", -18, -162 - (index - 1) * 28)
        self.rows[index] = row
    end

    self.scrollBar = UI.ScrollBar(page)
    self.scrollBar:SetPoint("TOPRIGHT", -6, -162)
    self.scrollBar:SetPoint("BOTTOMRIGHT", -6, 34)
    self.scrollBar:SetScript("OnValueChanged", function(_, value)
        local offset = math.floor(value + .5)
        if offset ~= self.offset then
            self.offset = offset
            self:RenderRows()
        end
    end)
    self.scrollBar:Hide()

    UI.BindScrollWheel(page, self.scrollBar, self.rows, function() return self.offset end)

    self.message = UI.Text(page, "GameFontHighlight", "", C.muted)
    self.message:SetPoint("TOPLEFT", 24, -190)
    self.message:SetPoint("TOPRIGHT", -24, -190)
    self.message:SetJustifyH("CENTER")
    self.message:SetSpacing(6)

    self.footer = UI.Text(page, "GameFontHighlightSmall", "", C.faint)
    self.footer:SetPoint("BOTTOMLEFT", 16, 12)
    self.footer:SetPoint("BOTTOMRIGHT", -16, 12)
    self.footer:SetJustifyH("LEFT")

    self.page = page
    self.welcome = welcome
    self:Layout()
end

function GuildBoard:Layout()
    if not self.page then return end
    local width = self.page:GetWidth()
    if width < 100 then return end
    local gap = 10
    local cardWidth = math.floor((width - 28 - gap * 2) / 3)
    for place, card in ipairs(self.podium) do
        card:ClearAllPoints()
        card:SetSize(cardWidth, 84)
        card:SetPoint("TOPLEFT", 14 + (place - 1) * (cardWidth + gap), -44)
    end
    local visible = math.max(3, math.min(LIST_ROW_POOL, math.floor((self.page:GetHeight() - 200) / 28)))
    self.visibleRows = visible
    for index, row in ipairs(self.rows or {}) do
        row.layoutVisible = index <= visible
        if not row.layoutVisible then row:Hide() end
    end
    if self.entries then
        local maximum = math.max(0, #self.entries - PODIUM_COUNT - visible)
        self.scrollBar:SetMinMaxValues(0, maximum)
        self.offset = math.min(self.offset or 0, maximum)
        self.scrollBar:SetValue(self.offset)
        self.scrollBar:SetShown(maximum > 0)
        self:RenderRows()
    end
end

function GuildBoard:RenderRows()
    local entries = self.entries or {}
    local offset = self.offset or 0
    for index, row in ipairs(self.rows or {}) do
        local entryIndex = PODIUM_COUNT + offset + index
        local entry = row.layoutVisible ~= false and entries[entryIndex]
        if entry then
            row.rank:SetText(tostring(entryIndex))
            row.name:SetText(UI.ClassIcon(entry.classFile, 16) .. "  " .. entry.name)
            row.name:SetTextColor(UI.ClassColor(entry.classFile))
            row.best:SetText(entry.bestKey > 0 and ("+" .. entry.bestKey) or "—")
            row.status:SetText(entry.online and L("|cff43d17aонлайн|r") or "")
            row.score:SetText(math.floor(entry.score))
            row:Show()
        else
            row:Hide()
        end
    end
end

function GuildBoard:Refresh()
    if not self.page then return end
    self:Layout()

    local guild = GetGuildInfo and GetGuildInfo("player")
    self.guildName:SetText(SafeString(guild) or "")

    local entries, message = self:Collect()
    local count = entries and #entries or 0
    self.entries = entries or {}

    for place, card in ipairs(self.podium) do
        local entry = entries and entries[place]
        if entry then
            card.name:SetText(UI.ClassIcon(entry.classFile, 20) .. "  " .. entry.name)
            card.name:SetTextColor(UI.ClassColor(entry.classFile))
            card.score:SetText(math.floor(entry.score))
            card.detail:SetText((L("|cff8a939fлучший ключ|r  |cff43d17a+%d|r")):format(entry.bestKey))
            card:Show()
        else
            card:Hide()
        end
    end

    local visible = self.visibleRows or 3
    local maximum = math.max(0, count - PODIUM_COUNT - visible)
    self.scrollBar:SetMinMaxValues(0, maximum)
    self.offset = math.min(self.offset or 0, maximum)
    self.scrollBar:SetValue(self.offset)
    self.scrollBar:SetShown(maximum > 0)
    self.listHeader:SetText((L("ОСНОВНОЙ СОСТАВ  |cff28c8f5%d|r")):format(math.max(0, count - PODIUM_COUNT)))
    self:RenderRows()

    if count == 0 then
        self.message:SetText(message or L("В базе Raider.IO пока нет рейтингов для твоей гильдии."))
        self.message:Show()
    else
        self.message:Hide()
    end

    if count > 0 then
        self.footer:SetText((L("|cff687584Данные Raider.IO — персонажей с рейтингом: %d из %d просмотренных|r"))
            :format(count, self.scanned or count))
    else
        self.footer:SetText("")
    end
end

function GuildBoard:Create()
    if self.events then return end
    self.events = CreateFrame("Frame")
    self.events:RegisterEvent("GUILD_ROSTER_UPDATE")
    self.events:RegisterEvent("PLAYER_GUILD_UPDATE")
    -- GUILD_ROSTER_UPDATE прилетает пачками, и каждое событие обнуляло кэш,
    -- сводя на нет минутную выдержку: пересчёт рейтингов по всей гильдии
    -- запускался заново. Склеиваем события в одно обновление.
    self.events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_GUILD_UPDATE" or self.awaitingFullRoster then
            self.cache = nil
            self.awaitingFullRoster = nil
        end
        if self.updateQueued then return end
        self.updateQueued = true
        C_Timer.After(1, function()
            self.updateQueued = nil
            local welcome = JP.modules.Welcome
            if welcome and welcome.currentPage == "guild" and welcome.frame and welcome.frame:IsShown() then
                self:Refresh()
            end
        end)
    end)
end

function GuildBoard:Enable() end
function GuildBoard:Disable() end
function GuildBoard:Destroy() end

JP.GuildBoard = GuildBoard
JP:RegisterModule("GuildBoard", GuildBoard)
