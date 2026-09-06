local _, JP = ...
local UI, L, C = JP.UI, JP.L, JP.UI.colors
local Cards = {}
JP.ApplicantCards = Cards

local POOL_SIZE, MAX_MEMBERS = 14, 5
local TOP, GAP, HEADER, MEMBER_HEIGHT = -230, 8, 56, 36
local STATUS = {
    best = { label = L("ЛУЧШИЙ"), color = C.amber },
    needed = { label = L("ПОДХОДИТ"), color = { .62, .40, .95, 1 } },
    keyReady = { label = L("ПОД КЛЮЧ"), color = C.green },
    keyClose = { label = L("МОЖНО БРАТЬ"), color = C.accent },
    keyRisk = { label = L("МАЛО ОПЫТА"), color = C.red },
    wrongRole = { label = L("НЕ ТА РОЛЬ"), color = C.red },
}

local function Height(package)
    return HEADER + MEMBER_HEIGHT * #package.entries + 8
end

function Cards:Packages(entries)
    local packages, byID = {}, {}
    for _, entry in ipairs(entries or {}) do
        local package = byID[entry.applicantID]
        if not package then
            package = { id = entry.applicantID, entries = {}, size = entry.numMembers or 1 }
            packages[#packages + 1], byID[entry.applicantID] = package, package
        end
        package.entries[#package.entries + 1] = entry
    end
    return packages
end

local function Geometry(width)
    local nameWidth = math.max(210, math.min(330, math.floor(width * .27)))
    local ilvl = 12 + nameWidth + 8
    local rating, dungeons, experience = ilvl + 58, ilvl + 132, width - 108
    return nameWidth, ilvl, rating, dungeons, experience, (experience - 10 - dungeons) / 8
end

local function Place(text, x, y, width, justify)
    text:ClearAllPoints(); text:SetPoint("TOPLEFT", x, y)
    text:SetWidth(width); text:SetJustifyH(justify or "CENTER"); text:SetWordWrap(false)
end

local function MemberTooltip(row)
    local entry = row.entry
    if not entry then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(entry.name)
    if entry.recommendationReason then GameTooltip:AddLine(entry.recommendationReason, .8, .85, .9, true) end
    if JP.Reviews then JP.Reviews:AddTooltip(GameTooltip, entry.name) end
    GameTooltip:Show()
end

local function CreateCard(board)
    local card = CreateFrame("Frame", nil, board.page, "BackdropTemplate")
    card:EnableMouse(true)
    UI.Backdrop(card, C.panel, C.hudEdge)
    card.title = UI.Text(card, "GameFontNormalSmall", "", C.accent)
    card.title:SetPoint("TOPLEFT", 12, -11)
    card.title:SetPoint("TOPRIGHT", -228, -11)
    card.title:SetJustifyH("LEFT"); card.title:SetWordWrap(false)
    card.invite = UI.Button(card, L("Пригласить"), 148, 26, true)
    card.invite:SetPoint("TOPRIGHT", -52, -6)
    card.invite:SetScript("OnClick", function(button)
        if not button.applicantID then return end
        if board.Act("InviteApplicant", button.applicantID, L("Blizzard не принял приглашение. Попробуй ещё раз.")) then
            button:SetText(L("Отправлено"))
        end
    end)
    card.decline = UI.Button(card, "x", 32, 26)
    card.decline:SetPoint("TOPRIGHT", -12, -6)
    card.decline:SetScript("OnClick", function(button)
        if button.applicantID then board.Act("DeclineApplicant", button.applicantID, L("Не удалось отклонить заявку.")) end
    end)
    card.decline:SetScript("OnEnter", function(button) UI.Tooltip(button, L("Отклонить всю заявку")) end)
    card.decline:SetScript("OnLeave", GameTooltip_Hide)
    card.headers = {}
    for _, key in ipairs({"name", "reviews", "ilvl", "rating", "experience"}) do
        card.headers[key] = UI.Text(card, "GameFontNormalSmall", "", C.muted)
    end
    card.headers.name:SetText(L("ИГРОК")); card.headers.ilvl:SetText("ilvl")
    card.headers.reviews:SetText("+/-")
    card.headers.rating:SetText("RIO"); card.headers.experience:SetText(L("ДАНЖ / ЦЕЛЬ"))
    card.dungeons = {}
    for i = 1, 8 do
        local header = CreateFrame("Frame", nil, card, "BackdropTemplate")
        header:SetSize(20, 20); header:EnableMouse(true)
        UI.Backdrop(header, C.row, C.hudEdge)
        header.icon = header:CreateTexture(nil, "ARTWORK")
        header.icon:SetPoint("TOPLEFT",2,-2); header.icon:SetPoint("BOTTOMRIGHT",-2,2)
        header:SetScript("OnEnter", function(owner)
            if owner.dungeonName then UI.Tooltip(owner, owner.dungeonName) end
        end)
        header:SetScript("OnLeave", GameTooltip_Hide)
        card.dungeons[i] = header
    end
    card.members = {}
    for i = 1, MAX_MEMBERS do
        local row = CreateFrame("Frame", nil, card, "BackdropTemplate")
        row:SetPoint("TOPLEFT", 6, -HEADER - (i - 1) * MEMBER_HEIGHT)
        row:SetPoint("TOPRIGHT", -6, -HEADER - (i - 1) * MEMBER_HEIGHT)
        row:SetHeight(MEMBER_HEIGHT - 2); row:EnableMouse(true)
        UI.Backdrop(row, i % 2 == 0 and C.rowAlt or C.row, C.lineSoft)
        row.name = UI.Text(row, "GameFontHighlightSmall", "", C.text)
        row.ilvl = UI.Text(row, "GameFontHighlightSmall", "", C.text)
        row.rating = UI.Text(row, "GameFontHighlightSmall", "", C.text)
        row.reviews = CreateFrame("Button", nil, row)
        row.reviews:SetSize(40, MEMBER_HEIGHT-2); row.reviews:EnableMouse(true)
        row.reviews.value=UI.Text(row.reviews,"GameFontHighlightSmall","",C.muted)
        row.reviews.value:SetAllPoints()
        row.reviews:SetScript("OnEnter",function(owner)
            if row.entry and JP.Reviews and JP.Reviews.ShowPlayerTooltip then JP.Reviews:ShowPlayerTooltip(owner,row.entry.name) end
        end)
        row.reviews:SetScript("OnClick",function()
            if row.entry and JP.PlayerNetwork then JP.PlayerNetwork:ShowMemory(row.entry.name) end
        end)
        local function HideReviews(owner) if JP.Reviews and JP.Reviews.HidePlayerTooltip then JP.Reviews:HidePlayerTooltip(owner) end end
        row.reviews:SetScript("OnLeave",HideReviews); row.reviews:SetScript("OnHide",HideReviews)
        row.experience = UI.Text(row, "GameFontHighlightSmall", "", C.text)
        row.status = UI.Text(row, "GameFontHighlightSmall", "", C.muted)
        row:SetScript("OnEnter", MemberTooltip); row:SetScript("OnLeave", GameTooltip_Hide)
        row.cells = {}
        for j = 1, 8 do
            local cell = CreateFrame("Frame", nil, row)
            cell:SetHeight(MEMBER_HEIGHT - 2); cell:EnableMouse(true)
            cell.value = UI.Text(cell, "GameFontHighlightSmall", "", C.text)
            cell.value:SetAllPoints(); cell.value:SetJustifyH("CENTER"); cell.value:SetWordWrap(false)
            cell:SetScript("OnEnter", board.ShowDungeonTooltip)
            cell:SetScript("OnLeave", GameTooltip_Hide)
            row.cells[j] = cell
        end
        card.members[i] = row
    end
    card:Hide()
    return card
end

function Cards:Build(board, page, act, dungeonTooltip)
    board.page, board.Act, board.ShowDungeonTooltip = page, act, dungeonTooltip
    board.cards = {}
    -- Cards are created lazily up to a fixed viewport-sized pool, then reused.
    board.scrollBar = UI.ScrollBar(page)
    board.scrollBar:SetPoint("TOPRIGHT", -6, TOP)
    board.scrollBar:SetPoint("BOTTOMRIGHT", -6, 12)
    board.scrollBar:SetScript("OnValueChanged", function(_, value)
        local offset = math.floor(value + .5)
        if offset ~= board.offset then board.offset = offset; board:Render() end
    end)
    board.scrollBar:Hide()
    UI.BindScrollWheel(page, board.scrollBar, nil, function() return board.offset end)
end

function Cards:Clear(card)
    card.invite.applicantID, card.decline.applicantID = nil, nil
    for _, row in ipairs(card.members) do
        row.entry = nil
        for _, cell in ipairs(row.cells) do cell.tooltipData, cell.dungeonName = nil, nil end
        row:Hide()
    end
    card:Hide()
end

function Cards:Paint(board, card, package, width, columns, ownMapID, ownLevel)
    local nameWidth, ilvl, rating, dungeons, experience, step = Geometry(width)
    Place(card.headers.reviews, ilvl-52, -39, 40)
    card:SetHeight(Height(package))
    card.title:SetText(#package.entries > 1 and (L("Совместная заявка: %d игроков")):format(package.size) or L("Заявка"))
    card.invite.applicantID, card.decline.applicantID = package.id, package.id
    card.invite:SetText(package.size > 1 and (L("Пригласить ×") .. package.size) or L("Пригласить"))
    Place(card.headers.name, 12, -39, nameWidth, "LEFT")
    Place(card.headers.ilvl, ilvl, -39, 50)
    Place(card.headers.rating, rating, -39, 66)
    Place(card.headers.experience, experience, -39, 96)
    for i, header in ipairs(card.dungeons) do
        local column = columns[i]
        header:ClearAllPoints(); header:SetPoint("TOPLEFT", dungeons + (i - 1) * step + (step - 20) / 2, -33)
        header.icon:SetTexture(column and column.texture or 134400)
        header.dungeonName = column and column.name
        local owned = ownMapID and column and tonumber(column.key) == tonumber(ownMapID)
        header:SetBackdropBorderColor(UI.Unpack(owned and C.amber or C.hudEdge))
    end
    for i, row in ipairs(card.members) do
        local entry = package.entries[i]
        row.entry = entry
        if entry then
            Place(row.name, 6, -11, nameWidth-52, "LEFT")
            row.reviews:ClearAllPoints(); row.reviews:SetPoint("TOPLEFT",ilvl-58,0)
            local score,total=0,0
            if JP.Reviews and JP.Reviews.Rating then score,total=JP.Reviews:Rating(entry.name) end
            row.reviews.value:SetText(total>0 and (score>0 and ("+"..score) or tostring(score)) or "—")
            row.reviews.value:SetTextColor(UI.Unpack(score>0 and C.green or score<0 and C.red or C.muted))
            Place(row.ilvl, ilvl - 6, -11, 50)
            Place(row.rating, rating - 6, -11, 66)
            Place(row.experience, experience - 6, -3, 96)
            Place(row.status, experience - 6, -20, 96)
            local playerLabel=JP.AddonPresence and JP.AddonPresence:Decorate(entry.name) or entry.name
            row.name:SetText(("%s %s %s"):format(UI.RoleIcon(entry.role, 14), UI.ClassIcon(entry.classFile, 14), playerLabel))
            row.name:SetTextColor(UI.ClassColor(entry.classFile))
            if JP.PlayerNetwork then
                local context=JP.PlayerNetwork:Context(entry.name)
                row:SetBackdropBorderColor(UI.Unpack(context.private and context.private.avoidUntil~=nil and C.amber
                    or context.history and C.green or context.trusted>0 and C.accent or C.lineSoft))
            end
            row.ilvl:SetText(entry.itemLevel > 0 and ("%.0f"):format(entry.itemLevel) or "—")
            row.rating:SetText(entry.score > 0 and tostring(math.floor(entry.score)) or "—")
            local keyLevel = 0
            for j, cell in ipairs(row.cells) do
                local column = columns[j]
                local data = entry.dungeonCells and entry.dungeonCells[j]
                local level = data and tonumber(data.level) or 0
                local upgrades = data and tonumber(data.upgrades) or 0
                local owned = ownMapID and column and tonumber(column.key) == tonumber(ownMapID)
                if owned then keyLevel = level end
                cell:ClearAllPoints(); cell:SetPoint("TOPLEFT", dungeons - 6 + (j - 1) * step, 0); cell:SetWidth(step)
                cell.tooltipData, cell.dungeonName = data, column and column.name
                cell.ownedKey, cell.ownedKeyLevel = owned, owned and ownLevel or nil
                cell.value:SetText(level > 0 and (string.rep("+", math.max(0, math.min(3, upgrades))) .. level) or "—")
                cell.value:SetTextColor(UI.Unpack(JP.GroupSearchUI:GetRunGradeColor(data and data.grade)))
            end
            row.experience:SetText(ownLevel and ((keyLevel > 0 and ("+%d"):format(keyLevel) or "—") .. (" / +%d"):format(ownLevel)) or "—")
            row.experience:SetTextColor(UI.Unpack(keyLevel > 0 and C.text or C.muted))
            local status = STATUS[entry.status]
            local unknown = keyLevel == 0 and entry.status ~= "wrongRole"
            row.status:SetText(unknown and L("Нет данных") or status and status.label or "")
            row.status:SetTextColor(UI.Unpack(unknown and C.muted or status and status.color or C.muted))
            row:Show()
        else
            for _, cell in ipairs(row.cells) do cell.tooltipData, cell.dungeonName = nil, nil end
            row:Hide()
        end
    end
    card:Show()
end

function Cards:Render(board, ownMapID, ownLevel)
    if not board.page or not board.cards or board.renderingCards then return end
    board.renderingCards = true
    local packages = self:Packages(board.entries)
    local available = math.max(0, board.page:GetHeight() + TOP - 12)
    local width = math.max(1, board.page:GetWidth() - 30)
    -- Scroll in complete applications, never to member 4/4 of a hidden party.
    local suffix, used = 0, 0
    for i = #packages, 1, -1 do
        local height = Height(packages[i]) + (suffix > 0 and GAP or 0)
        if used + height > available or suffix >= POOL_SIZE then break end
        used, suffix = used + height, suffix + 1
    end
    local maximum = math.max(0, #packages - math.max(1, suffix))
    board.offset = math.max(0, math.min(board.offset or 0, maximum))
    board.scrollBar:SetMinMaxValues(0, maximum); board.scrollBar:SetValue(board.offset)
    board.scrollBar:SetShown(maximum > 0)
    local columns = JP.GroupSearchUI:GetPartyDungeonColumns()
    local shown, y = 0, 0
    for i = board.offset + 1, #packages do
        local package = packages[i]
        if shown >= POOL_SIZE or y + Height(package) > available then break end
        shown = shown + 1
        if not board.cards[shown] then
            board.cards[shown] = CreateCard(board)
            UI.BindScrollWheel(board.cards[shown], board.scrollBar, board.cards[shown].members, function() return board.offset end)
        end
        local card = board.cards[shown]
        card:ClearAllPoints(); card:SetPoint("TOPLEFT", 12, TOP - y); card:SetPoint("TOPRIGHT", -18, TOP - y)
        self:Paint(board, card, package, width, columns, ownMapID, ownLevel)
        y = y + Height(package) + GAP
    end
    for i = shown + 1, #board.cards do self:Clear(board.cards[i]) end
    board.renderingCards = nil
end
