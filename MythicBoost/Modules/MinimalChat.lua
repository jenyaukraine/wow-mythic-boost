local _, JP = ...
local MinimalChat = {}

-- Prat owns timestamps, links and copying. MythicBoost only retains the
-- transparent chat skin, without message filters, backgrounds or popups.
local function RememberAndHide(self, object)
    if not object or type(object.IsShown) ~= "function" or type(object.SetShown) ~= "function" then return end
    self.savedVisibility = self.savedVisibility or {}
    if self.savedVisibility[object] == nil then self.savedVisibility[object] = object:IsShown() and true or false end
    object:Hide()
end

local function Restore(self)
    for object, shown in pairs(self.savedVisibility or {}) do
        if object and type(object.SetShown) == "function" then object:SetShown(shown) end
    end
    if self.savedVisibility then wipe(self.savedVisibility) end
end

local function Skin(self, chat, index, enabled)
    if not chat then return end
    -- Hide gradient frames created by older MythicBoost revisions. Creating a
    -- panel for every ChatFrame also exposed empty undocked tabs as large black
    -- rectangles, so chat now deliberately has no custom background at all.
    local oldFade = self.chatFades and self.chatFades[chat]
    if oldFade then oldFade:Hide() end
    if enabled then
        self.chatFonts = self.chatFonts or {}
        if not self.chatFonts[chat] and type(chat.GetFont) == "function" then
            self.chatFonts[chat] = { chat:GetFont() }
        end
        local font = self.chatFonts[chat]
        if font and font[1] then chat:SetFont(font[1], math.max(font[2] or 12, 12), font[3] or "") end
        RememberAndHide(self, chat.Background)
        RememberAndHide(self, _G["ChatFrame" .. index .. "ButtonFrame"])
        local tab = _G["ChatFrame" .. index .. "Tab"]
        if tab then
            for _, suffix in ipairs({
                "Left", "Middle", "Right", "SelectedLeft", "SelectedMiddle", "SelectedRight",
                "HighlightLeft", "HighlightMiddle", "HighlightRight",
            }) do RememberAndHide(self, _G["ChatFrame" .. index .. "Tab" .. suffix]) end
            local text = tab.Text or _G["ChatFrame" .. index .. "TabText"]
            if text then
                self.tabColors = self.tabColors or {}
                if not self.tabColors[text] then self.tabColors[text] = { text:GetTextColor() } end
                text:SetTextColor(.80, .88, .96, 1)
            end
        end
    else
        local font = self.chatFonts and self.chatFonts[chat]
        if font and font[1] then chat:SetFont(font[1], font[2], font[3]) end
        if self.chatFonts then self.chatFonts[chat] = nil end
    end
    -- Also removes a button left by version 1.2.0 until the next full reload.
    if chat.__mbCopyButton then chat.__mbCopyButton:Hide() end
end

function MinimalChat:Apply()
    local enabled = MythicBoostDB and MythicBoostDB.minimalUI == true
    if not enabled then
        Restore(self)
        for text, color in pairs(self.tabColors or {}) do text:SetTextColor(unpack(color)) end
        if self.tabColors then wipe(self.tabColors) end
    end
    for index = 1, (NUM_CHAT_WINDOWS or 10) do Skin(self, _G["ChatFrame" .. index], index, enabled) end
end

function MinimalChat:Create()
    if self.created then return end
    self.created = true
    self.events = CreateFrame("Frame")
    self.events:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.events:RegisterEvent("UPDATE_CHAT_WINDOWS")
    self.events:SetScript("OnEvent", function() C_Timer.After(.1, function() self:Apply() end) end)
    C_Timer.After(.2, function() self:Apply() end)
end

function MinimalChat:Enable() self:Create(); self:Apply() end
function MinimalChat:Disable()
    Restore(self)
    for index = 1, (NUM_CHAT_WINDOWS or 10) do Skin(self, _G["ChatFrame" .. index], index, false) end
end
function MinimalChat:Destroy() self:Disable() end

JP.MinimalChat = MinimalChat
JP:RegisterModule("MinimalChat", MinimalChat)
