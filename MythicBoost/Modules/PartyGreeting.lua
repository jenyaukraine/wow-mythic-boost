local _, JP = ...
local Greeting = {}
local function Settings()
    return JP.Settings("convenience", {autoHi=true, greetingText="hi"}) or {}
end
local function Enabled()
    return Settings().autoHi == true
end
function Greeting:NormalizeText(value)
    local text=JP.SafeString(value) or ""
    -- One plain chat line, no embedded control/formatting sequences. Keep
    -- below the chat byte limit without splitting a UTF-8 character.
    -- Explicit ASCII ranges avoid locale-dependent %c/%s classes treating
    -- UTF-8 continuation bytes as whitespace/control characters.
    text=text:gsub("[%z\1-\31\127|]"," "):gsub(" +"," "):match("^ *(.-) *$")
    if #text>240 then
        local limit=240
        while limit>0 do
            local byte=text:byte(limit+1)
            if byte<128 or byte>191 then break end
            limit=limit-1
        end
        text=text:sub(1,limit):gsub(" +$","")
    end
    return text~="" and text or "hi"
end
function Greeting:GetText()
    return self:NormalizeText(Settings().greetingText)
end
function Greeting:SetText(value)
    local text=self:NormalizeText(value)
    Settings().greetingText=text
    return text
end
local function InHomeParty()
    return JP.SafeOptionalBoolean(IsInGroup(LE_PARTY_CATEGORY_HOME)) == true
        and JP.SafeOptionalBoolean(IsInRaid(LE_PARTY_CATEGORY_HOME)) == false
end
function Greeting:Cancel()
    if self.pending then self.pending:Cancel(); self.pending = nil end
    self.deadline = nil
end
function Greeting:Schedule(delay)
    if self.pending then return end
    self.pending = C_Timer.NewTimer(delay, function()
        self.pending = nil
        self:TrySend()
    end)
end
function Greeting:TrySend()
    if not self.running or not self.deadline or GetTime() >= self.deadline or not Enabled()
        or JP.SafeOptionalBoolean(IsInRaid(LE_PARTY_CATEGORY_HOME)) == true then
        self:Cancel(); return
    end
    -- GROUP_JOINED can precede the roster. A temporary combat/chat lock must
    -- not consume the greeting; keep only one bounded timer for this join.
    local leader = JP.SafeOptionalBoolean(UnitIsGroupLeader("player"))
    if InHomeParty() and leader == true then self:Cancel(); return end
    if not InHomeParty() or leader == nil or InCombatLockdown()
        or (C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
            and JP.SafeOptionalBoolean(C_ChatInfo.InChatMessagingLockdown()) ~= false) then
        self:Schedule(2); return
    end
    self:Cancel()
    local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
    if type(send) == "function" then
        -- One API attempt only: its nil return does not confirm delivery, so
        -- retrying after an ambiguous send could greet the same party twice.
        local ok = pcall(send, self:GetText(), "PARTY")
        if ok then self.lastSent = GetTime() end
    end
end
function Greeting:Joined()
    if self.grouped then return end
    self.grouped = true
    if not Enabled() or (self.lastSent and GetTime() - self.lastSent < 30) then return end
    self.deadline = GetTime() + 60
    self:Schedule(1.5)
end
function Greeting:OnEvent(event, category)
    if event == "PLAYER_ENTERING_WORLD" then
        if not self.ready then self.ready = true; self.grouped = InHomeParty() end
        return
    end
    if not self.ready then return end
    if event == "GROUP_ROSTER_UPDATE" then
        if InHomeParty() then
            self:Joined()
        elseif JP.SafeOptionalBoolean(IsInGroup(LE_PARTY_CATEGORY_HOME)) == false and not self.deadline then
            self.grouped = false
        end
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        if self.deadline then
            if self.pending then self.pending:Cancel(); self.pending = nil end
            self:Schedule(.5)
        end
        return
    end
    if JP.SafeNumber(category) ~= LE_PARTY_CATEGORY_HOME then return end
    if event == "GROUP_LEFT" then self:Cancel(); self.grouped = false; return end
    -- FORMED is not proof that the player is the leader. Decide from the
    -- settled roster instead, including an invite that creates a two-person party.
    if event == "GROUP_JOINED" or event == "GROUP_FORMED" then self:Joined() end
end
function Greeting:Enable()
    self.running = true
    if not self.frame then
        self.frame = CreateFrame("Frame")
        self.frame:SetScript("OnEvent", function(_, ...) self:OnEvent(...) end)
    end
    self.grouped = InHomeParty()
    self.ready = self.ready or (IsLoggedIn and IsLoggedIn()) or false
    for _, event in ipairs({"PLAYER_ENTERING_WORLD", "GROUP_JOINED", "GROUP_FORMED", "GROUP_LEFT",
        "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED"}) do
        self.frame:RegisterEvent(event)
    end
end
function Greeting:Disable()
    self.running = false; self:Cancel()
    if self.frame then self.frame:UnregisterAllEvents() end
end
function Greeting:Destroy() self:Disable() end
JP.PartyGreeting = Greeting
JP:RegisterModule("PartyGreeting", Greeting)
