local _, JP = ...
local L = JP.L
local RCLootBridge = {}
local UI, C = JP.UI, JP.UI.colors

---------------------------------------------------------------------------
-- Мост к RCLootCouncil
--
-- Задача одна: когда мастер лута разыгрывает вещь, показать её со СВОИМ
-- вердиктом — BiS это для текущей специализации или нет — и отправить ответ
-- обратно. Знание о BiS есть у нас и нет у RCLootCouncil, в этом весь смысл
-- моста; всё остальное он делает сам.
--
-- Протокол у них внутренний, поэтому здесь реализован МИНИМУМ, без которого
-- ответ не дойдёт, и ни строчкой больше:
--   входящее  lootTable  — что разыгрывают;
--   исходящее lootAck    — «я здесь», иначе ML ждёт таймаута;
--   исходящее response   — сам ответ.
-- Остальную дюжину команд (совет, сравнение гира, статусы обмена) сознательно
-- не трогаем: они необязательны, а каждая — лишний повод разойтись с их
-- следующей версией.
--
-- Формат провода снят с их Comms.lua и повторён точно:
--   Serialize(command, {данные}) → CompressDeflate(level 3) → EncodeForWoWAddonChannel
---------------------------------------------------------------------------

local PREFIX = "RCLC"
local COMPRESS = { level = 3 }
local SETTINGS_DEFAULTS = { enabled = false }

-- Значения ответов из их Core/Defaults.lua: массивная часть таблицы responses.
local RESPONSE = { NEED = 1, GREED = 2, MINOR = 3, PASS = "PASS" }

local AceComm, AceSerializer, LibDeflate

local function LoadLibs()
    if AceComm then return true end
    if not LibStub then return false end
    local okComm, comm = pcall(LibStub, "AceComm-3.0")
    local okSer, ser = pcall(LibStub, "AceSerializer-3.0")
    local okDef, def = pcall(LibStub, "LibDeflate")
    if not (okComm and okSer and okDef and comm and ser and def) then return false end
    AceComm, AceSerializer, LibDeflate = comm, ser, def
    return true
end

function RCLootBridge:GetSettings()
    return JP.Settings("rcLoot", SETTINGS_DEFAULTS)
end

function RCLootBridge:IsEnabled()
    local settings = self:GetSettings()
    return settings and settings.enabled == true
end

---------------------------------------------------------------------------
-- Провод
---------------------------------------------------------------------------

local function Encode(command, ...)
    local serialized = AceSerializer:Serialize(command, { ... })
    local compressed = LibDeflate:CompressDeflate(serialized, COMPRESS)
    return LibDeflate:EncodeForWoWAddonChannel(compressed)
end

local function Decode(payload)
    local decoded = LibDeflate:DecodeForWoWAddonChannel(payload)
    if not decoded then return end
    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then return end
    local ok, command, data = AceSerializer:Deserialize(decompressed)
    if not ok then return end
    return command, data
end

function RCLootBridge:Send(target, command, ...)
    if not LoadLibs() then return end
    local encoded = Encode(command, ...)
    if not encoded then return end
    -- Ответ идёт лично мастеру лута, а не в группу: так делает и оригинал.
    if target and target ~= "group" then
        AceComm:SendCommMessage(PREFIX, encoded, "WHISPER", target, "NORMAL")
    else
        local channel = IsInRaid() and "RAID" or "PARTY"
        AceComm:SendCommMessage(PREFIX, encoded, channel, nil, "NORMAL")
    end
end

---------------------------------------------------------------------------
-- Вердикт
---------------------------------------------------------------------------

-- Единственное, что мы приносим сверх RCLootCouncil. Возвращает подпись и
-- цвет; nil означает «в наших списках вещи нет», и это честнее выдуманной
-- рекомендации.
function RCLootBridge:Verdict(itemLink)
    if not JP.BiSData or not itemLink then return end
    local itemID = tonumber(itemLink:match("item:(%d+)"))
    if not itemID then return end
    local specID = JP.BiSData:GetCurrentSpecID()
    if not specID then return end
    return JP.BiSData:GetItem(specID, itemID)
end

---------------------------------------------------------------------------
-- Окно
---------------------------------------------------------------------------

local ROW_HEIGHT = 44

function RCLootBridge:BuildWindow()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", "MythicBoostRCLootFrame", UIParent, "BackdropTemplate")
    frame:SetSize(420, 120)
    frame:SetPoint("CENTER", 0, 160)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    UI.MakeMovable(frame)
    UI.Backdrop(frame, C.surface, C.surfaceEdge)

    frame.title = UI.Text(frame, "GameFontNormal", L("РОЗЫГРЫШ ДОБЫЧИ"), C.accent)
    frame.title:SetPoint("TOPLEFT", 12, -10)

    local close = UI.CloseButton(frame)
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() frame:Hide() end)

    frame.rows = {}
    frame:Hide()
    self.frame = frame
    return frame
end

function RCLootBridge:BuildRow(index)
    local frame = self.frame
    local row = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    row:SetHeight(ROW_HEIGHT - 4)
    row:SetPoint("TOPLEFT", 10, -32 - (index - 1) * ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", -10, -32 - (index - 1) * ROW_HEIGHT)
    UI.Backdrop(row, C.row, C.lineSoft)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:SetSize(32, 32)
    row.icon:SetTexCoord(.07, .93, .07, .93)

    row.name = UI.Text(row, "GameFontHighlightSmall", "", C.text)
    row.name:SetPoint("TOPLEFT", 42, -5)
    row.name:SetPoint("RIGHT", -160, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.verdict = UI.Text(row, "GameFontNormalSmall", "", C.muted)
    row.verdict:SetPoint("BOTTOMLEFT", 42, 6)
    row.verdict:SetJustifyH("LEFT")

    row:SetScript("OnEnter", function(owner)
        if not owner.link then return end
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(owner.link)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)

    local function Button(label, width, offset, response)
        local button = UI.Button(row, label, width, 22, response == RESPONSE.NEED)
        button:SetPoint("RIGHT", -offset, 0)
        button:SetScript("OnClick", function()
            RCLootBridge:Respond(row.session, response)
            row.answered = true
            row:SetAlpha(.45)
        end)
        return button
    end
    Button(L("Пас"), 44, 6, RESPONSE.PASS)
    Button(L("Гриди"), 52, 54, RESPONSE.GREED)
    Button(L("Нужно"), 56, 110, RESPONSE.NEED)

    frame.rows[index] = row
    return row
end

function RCLootBridge:ShowSessions(lootTable)
    local frame = self:BuildWindow()
    local shown = 0
    for index, entry in ipairs(lootTable or {}) do
        local row = frame.rows[index] or self:BuildRow(index)
        local link = entry.link or entry.string or entry
        if type(link) ~= "string" then link = nil end
        row.session, row.link, row.answered = entry.session or index, link, false
        row:SetAlpha(1)

        local icon, name = 134400, link or L("Предмет")
        if link and C_Item and C_Item.GetItemInfoInstant then
            local ok, _, _, _, _, texture = pcall(C_Item.GetItemInfoInstant, link)
            if ok and texture then icon = texture end
        end
        row.icon:SetTexture(icon)
        row.name:SetText(name)

        local verdict = self:Verdict(link)
        if verdict and verdict.label == "BIS" then
            row.verdict:SetText(L("|cff4deb8fBIS для твоего спека|r   ") .. (verdict.slot or ""))
        elseif verdict then
            row.verdict:SetText((L("|cffb35cffTOP|r   носят %d%% лучших   %s"))
                :format(math.floor(tonumber(verdict.share) or 0), verdict.slot or ""))
        else
            row.verdict:SetText(L("|cff6a7078в списках BiS не значится|r"))
        end
        row:Show()
        shown = index
    end
    for index = shown + 1, #frame.rows do frame.rows[index]:Hide() end
    if shown == 0 then frame:Hide(); return end
    frame:SetHeight(40 + shown * ROW_HEIGHT)
    frame:Show()
end

---------------------------------------------------------------------------
-- Приём и ответ
---------------------------------------------------------------------------

function RCLootBridge:Respond(session, response)
    if not session or not self.masterLooter then return end
    -- Формат payload снят с их SendResponse: все поля кроме response
    -- необязательны, поэтому шлём только его. Гир и ilvl сознательно не
    -- прикладываем — это чужая зона ответственности, а лишнее поле не
    -- того типа испортило бы разбор у мастера лута.
    self:Send(self.masterLooter, "response", session, { response = response })
end

function RCLootBridge:OnComm(prefix, payload, _, sender)
    if prefix ~= PREFIX or not self:IsEnabled() then return end
    local ok, command, data = pcall(Decode, payload)
    if not ok or not command then return end

    if command == "lootTable" then
        self.masterLooter = sender
        -- lootAck обязателен: без него мастер лута ждёт нас до таймаута и
        -- держит всю раздачу.
        self:Send(sender, "lootAck")
        self:ShowSessions(data and data[1])
    elseif command == "session_end" then
        if self.frame then self.frame:Hide() end
    end
end

---------------------------------------------------------------------------
-- Жизненный цикл
---------------------------------------------------------------------------

function RCLootBridge:SetEnabled(value)
    local settings = self:GetSettings()
    if not settings then return end
    settings.enabled = value and true or false
    if settings.enabled then
        if not self:Register() then
            JP:Print(L("Мост к RCLootCouncil не запустился: не нашлись библиотеки Ace. Нужен |cff28b8f5/reload|r."))
            return
        end
        JP:Print(L("Мост к RCLootCouncil включён. Если у тебя стоит сам RCLootCouncil — отключи его, иначе ответите оба."))
    else
        if self.frame then self.frame:Hide() end
        JP:Print(L("Мост к RCLootCouncil выключен."))
    end
end

function RCLootBridge:Register()
    if self.registered then return true end
    if not LoadLibs() then return false end
    AceComm.RegisterComm(self, PREFIX, function(_, prefix, payload, distribution, sender)
        RCLootBridge:OnComm(prefix, payload, distribution, sender)
    end)
    self.registered = true
    return true
end

function RCLootBridge:Create()
    if self:IsEnabled() then self:Register() end
end

function RCLootBridge:Enable() end
function RCLootBridge:Disable() if self.frame then self.frame:Hide() end end
function RCLootBridge:Destroy() if self.frame then self.frame:Hide() end end

JP.RCLootBridge = RCLootBridge
JP:RegisterModule("RCLootBridge", RCLootBridge)
