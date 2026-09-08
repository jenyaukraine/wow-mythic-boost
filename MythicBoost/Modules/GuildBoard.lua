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

-- Raider.IO raidProgress groups are character progress for current raids;
-- main-character and previous-tier records must not be attributed to this alt.
function GuildBoard:RaidProgress(profile)
    local raidProfile=profile and JP.SafeTable(profile.raidProfile)
    local source=raidProfile and JP.SafeTable(raidProfile.raidProgress)
    local rows,summary={},{}
    for _,record in ipairs(source or {}) do
        record=JP.SafeTable(record)
        local raid=record and JP.SafeTable(record.raid)
        local total=raid and JP.SafeNumber(raid.bossCount)
        if record and JP.SafeBoolean(record.current) and not JP.SafeBoolean(record.isMainProgress)
            and total and total>0 then
            local byDifficulty={}
            for _,group in ipairs(JP.SafeTable(record.progress) or {}) do
                group=JP.SafeTable(group)
                local diff=group and JP.SafeNumber(group.difficulty)
                local kills=group and JP.SafeNumber(group.kills)
                if diff and diff>=1 and diff<=3 and diff==math.floor(diff) and kills and kills>=0 and kills<=total then
                    byDifficulty[diff]=math.max(byDifficulty[diff] or 0,kills)
                end
            end
            local parts,best={},nil
            local suffix={"N","H","M"}
            for diff=1,3 do
                if byDifficulty[diff] then
                    local value=("%d/%d %s"):format(byDifficulty[diff],total,suffix[diff])
                    parts[#parts+1]=value
                    if not best or byDifficulty[diff]>0 then best=value end
                end
            end
            if best then
                local dungeon=JP.SafeTable(raid.dungeon)
                local name=(dungeon and SafeString(dungeon.name)) or SafeString(raid.name) or SafeString(raid.shortName) or L("Рейд")
                local short=SafeString(raid.shortName) or name
                rows[#rows+1]={name=name,value=table.concat(parts,"   ")}
                summary[#summary+1]=short.." "..best
                if #rows==8 then break end
            end
        end
    end
    return rows,table.concat(summary,"  /  ")
end

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
    return ok and type(profile) == "table" and profile or nil
end

function GuildBoard:HideKeyTooltip(owner)
    local tip = self.keyTooltip
    if tip and (not owner or tip.owner == owner) then
        tip.owner = nil
        tip:Hide()
    end
end

function GuildBoard:ShowKeyTooltip(owner)
    local entry, search = owner.entry, JP.GroupSearchUI
    if not entry or not search then self:HideKeyTooltip(); return end
    local columns = search:GetPartyDungeonColumns()
    -- Reuse the exact profile that supplied the score. A second name lookup
    -- can disagree with Raider.IO's own name/realm normalization.
    local cells = search:GetDungeonCells(entry.fullName, entry.classFile, entry.profile)
    if not self.keyTooltip then
        local tip = UI.Panel(UIParent, C.surface, C.hudEdge)
        tip:SetWidth(440)
        tip:SetFrameStrata("TOOLTIP")
        tip:SetClampedToScreen(true)
        tip:EnableMouse(false)
        tip.title = UI.Text(tip, "GameFontNormalLarge", "", C.text)
        tip.title:SetPoint("TOPLEFT", 12, -12)
        tip.title:SetPoint("TOPRIGHT", -90, -12)
        tip.title:SetJustifyH("LEFT"); tip.title:SetWordWrap(false)
        tip.score = UI.Text(tip, "GameFontNormalLarge", "", C.text)
        tip.score:SetPoint("TOPRIGHT", -12, -12)
        local label = UI.Text(tip, "GameFontNormalSmall", L("ПОДЗЕМЕЛЬЯ СЕЗОНА"), C.muted)
        label:SetPoint("TOPLEFT", 12, -42)
        local best = UI.Text(tip, "GameFontNormalSmall", L("ЛУЧШИЙ КЛЮЧ"), C.muted)
        best:SetPoint("TOPRIGHT", -12, -42)
        tip.rows = {}
        for index = 1, 8 do
            local row = UI.Panel(tip, index % 2 == 0 and C.rowAlt or C.row, C.hudEdge)
            row:SetPoint("TOPLEFT", 10, -62 - (index-1)*30)
            row:SetPoint("TOPRIGHT", -10, -62 - (index-1)*30)
            row:SetHeight(28)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(24, 24); row.icon:SetPoint("LEFT", 2, 0)
            row.icon:SetTexCoord(.06, .94, .06, .94)
            row.name = UI.Text(row, "GameFontHighlightSmall", "", C.text)
            row.name:SetPoint("LEFT", 34, 0); row.name:SetPoint("RIGHT", -80, 0)
            row.name:SetJustifyH("LEFT"); row.name:SetWordWrap(false)
            row.value = UI.Text(row, "GameFontNormal", "", C.text)
            row.value:SetPoint("RIGHT", -8, 0)
            tip.rows[index] = row
        end
        tip.raidLabel=UI.Text(tip,"GameFontNormalSmall",L("РЕЙДОВЫЙ ПРОГРЕСС"),C.accent)
        tip.raidRows={}
        for i=1,8 do
            local row=UI.Text(tip,"GameFontHighlightSmall","",C.text)
            row:SetWidth(416); row:SetJustifyH("LEFT"); row:SetWordWrap(false)
            tip.raidRows[i]=row
        end
        tip.footer = UI.Text(tip, "GameFontHighlightSmall", "", C.muted)
        tip.footer:SetPoint("BOTTOMLEFT", 12, 9)
        self.keyTooltip = tip
    end
    local tip = self.keyTooltip
    tip.owner = owner
    tip.title:SetText(UI.ClassIcon(entry.classFile, 20) .. "  " .. entry.fullName)
    tip.title:SetTextColor(UI.ClassColor(entry.classFile))
    tip.score:SetText(entry.hasKeystoneScore==false and "—" or math.floor(entry.score))
    local count = math.min(8, #columns)
    for index, row in ipairs(tip.rows) do
        local column, cell = columns[index], cells and cells[index]
        if column then
            row.icon:SetTexture(column.texture or 134400)
            row.name:SetText(column.name or column.label)
            row.value:SetText(cell and cell.value or "—")
            row.value:SetTextColor(UI.Unpack(search:GetRunGradeColor(cell and cell.grade or "missing")))
            row:Show()
        else
            row:Hide()
        end
    end
    local raids=entry.raids or self:RaidProgress(entry.profile)
    tip.raidLabel:ClearAllPoints(); tip.raidLabel:SetPoint("TOPLEFT",12,-(72+count*30))
    for i,row in ipairs(tip.raidRows) do
        row:ClearAllPoints(); row:SetPoint("TOPLEFT",12,-(94+count*30+(i-1)*20))
        local raid=raids[i]
        row:SetText(raid and (raid.name.."  /  "..raid.value) or (i==1 and L("Нет рейдовых данных Raider.IO") or ""))
        row:SetShown(raid~=nil or i==1)
    end
    tip.footer:SetText((cells or #raids>0) and "Raider.IO" or L("Нет данных"))
    tip:SetHeight(124 + count*30+math.max(1,#raids)*20)
    tip:ClearAllPoints()
    tip:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -6)
    tip:Show()
end

local function HookKeyTooltip(frame)
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(owner) GuildBoard:ShowKeyTooltip(owner) end)
    frame:SetScript("OnLeave", function(owner) GuildBoard:HideKeyTooltip(owner) end)
    frame:HookScript("OnHide", function(owner) GuildBoard:HideKeyTooltip(owner) end)
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
            local profile = MemberProfile(fullName)
            local keystone = profile and profile.mythicKeystoneProfile
            local score = UI.KeystoneScore(keystone)
            local raids,raidSummary=self:RaidProgress(profile)
            if score or #raids>0 then
                local profileName = SafeString(profile.name)
                local profileRealm = SafeString(profile.realm)
                if profileName and profileRealm then fullName = profileName .. "-" .. profileRealm end
                entries[#entries + 1] = {
                    name = name:match("^([^%-]+)") or name,
                    fullName = fullName,
                    profile = profile,
                    classFile = classFile,
                    score = score or 0,
                    hasKeystoneScore=score~=nil,
                    raids=raids,raidSummary=raidSummary,
                    bestKey = keystone and BestKeyLevel(keystone) or 0,
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
    local card = UI.Panel(parent, C.raised, C.hudEdge)
    card.place = place
    HookKeyTooltip(card)

    local medal = UI.Text(card, "GameFontNormalHuge", tostring(place), MEDAL_COLORS[place])
    medal:SetPoint("TOPLEFT", 14, -12)
    card.medal = medal

    card.name = UI.Text(card, "GameFontNormalLarge", "", C.text)
    card.name:SetPoint("TOPLEFT", 46, -14)
    card.name:SetPoint("TOPRIGHT", -14, -14)
    card.name:SetJustifyH("LEFT")
    card.name:SetWordWrap(false)

    card.score = UI.Text(card, "GameFontNormalHuge", "", C.text)
    card.score:SetPoint("BOTTOMLEFT", 14, 14)

    card.detail = UI.Text(card, "GameFontHighlightSmall", "", C.muted)
    card.detail:SetPoint("BOTTOMRIGHT", -14, 18)
    card.detail:SetJustifyH("RIGHT")
    card.raid=UI.Text(card,"GameFontHighlightSmall","",C.muted)
    card.raid:SetPoint("TOPLEFT",14,-42); card.raid:SetPoint("TOPRIGHT",-14,-42)
    card.raid:SetJustifyH("LEFT"); card.raid:SetWordWrap(false)

    local glow = card:CreateTexture(nil, "OVERLAY")
    glow:SetColorTexture(unpack(MEDAL_COLORS[place]))
    glow:SetPoint("TOPLEFT", 1, -1)
    glow:SetPoint("TOPRIGHT", -1, -1)
    glow:SetHeight(2)

    card:Hide()
    return card
end

local function CreateListRow(parent, index)
    local row = UI.Panel(parent, index % 2 == 0 and C.rowAlt or C.row, C.hudEdge)
    HookKeyTooltip(row)
    row:SetHeight(26)

    row.rank = UI.Text(row, "GameFontHighlightSmall", "", C.faint)
    row.rank:SetPoint("LEFT", 12, 0)
    row.rank:SetWidth(28)
    row.rank:SetJustifyH("CENTER")

    row.name = UI.Text(row, "GameFontHighlightSmall", "", C.text)
    row.name:SetPoint("LEFT", 46, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -450, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.raid=UI.Text(row,"GameFontHighlightSmall","",C.text)
    row.raid:SetPoint("RIGHT",-220,0); row.raid:SetWidth(220)
    row.raid:SetJustifyH("LEFT"); row.raid:SetWordWrap(false)

    row.best = UI.Text(row, "GameFontHighlightSmall", "", C.muted)
    row.best:SetPoint("RIGHT", -130, 0)
    row.best:SetWidth(80)
    row.best:SetJustifyH("CENTER")

    row.status = UI.Text(row, "GameFontHighlightSmall", "", C.faint)
    row.status:SetPoint("RIGHT", -84, 0)
    row.status:SetWidth(44)
    row.status:SetJustifyH("CENTER")

    row.score = UI.Text(row, "GameFontNormalSmall", "", C.text)
    row.score:SetPoint("RIGHT", -14, 0)
    row.score:SetWidth(64)
    row.score:SetJustifyH("RIGHT")

    row:Hide()
    return row
end

function GuildBoard:Build(welcome, page)
    page:HookScript("OnHide", function() self:HideKeyTooltip() end)
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
    local raidHeader=UI.Text(page,"GameFontNormalSmall",L("РЕЙДОВЫЙ ПРОГРЕСС"),C.faint)
    raidHeader:SetPoint("TOPRIGHT",-220,-142); raidHeader:SetWidth(220); raidHeader:SetJustifyH("LEFT")

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
        if row.entry ~= entry then self:HideKeyTooltip(row) end
        row.entry = entry
        if entry then
            row.rank:SetText(tostring(entryIndex))
            row.name:SetText(UI.ClassIcon(entry.classFile, 16) .. "  " .. entry.name)
            row.name:SetTextColor(UI.ClassColor(entry.classFile))
            row.best:SetText(entry.bestKey > 0 and ("+" .. entry.bestKey) or "—")
            row.status:SetText(entry.online and L("|cff43d17aонлайн|r") or "")
            row.score:SetText(entry.hasKeystoneScore==false and "—" or math.floor(entry.score))
            row.raid:SetText(entry.raidSummary and entry.raidSummary~="" and entry.raidSummary or "—")
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
        if card.entry ~= entry then self:HideKeyTooltip(card) end
        card.entry = entry
        if entry then
            card.name:SetText(UI.ClassIcon(entry.classFile, 20) .. "  " .. entry.name)
            card.name:SetTextColor(UI.ClassColor(entry.classFile))
            card.score:SetText(entry.hasKeystoneScore==false and "—" or math.floor(entry.score))
            card.raid:SetText(entry.raidSummary and entry.raidSummary~="" and entry.raidSummary or L("Нет рейдовых данных Raider.IO"))
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
function GuildBoard:Disable() self:HideKeyTooltip() end
function GuildBoard:Destroy() self:Disable() end

JP.GuildBoard = GuildBoard
JP:RegisterModule("GuildBoard", GuildBoard)
