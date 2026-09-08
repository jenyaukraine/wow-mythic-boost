local _, JP = ...
local Presence = {}
local PREFIX, TTL, CAP = "MBPresence1", 600, 256
local ICON = "|TInterface/AddOns/MythicBoost/Media/MythicBoostIcon.tga:12:12:0:0|t"
local function FullName(name)
    if not JP.Reviews then return end
    return JP.Reviews.FullName(name)
end
local function ChannelAvailable(channel)
    if channel == "GUILD" then return IsInGuild and IsInGuild() end
    if channel == "INSTANCE_CHAT" then
        return IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
    end
    if channel == "RAID" then return IsInRaid and IsInRaid() end
    if channel == "PARTY" then return IsInGroup and IsInGroup() and not (IsInRaid and IsInRaid()) end
    return false
end
local function Trim(map, age)
    local now, count, oldest, oldestAt = GetTime(), 0
    for key, at in pairs(map) do
        if now-at >= age then map[key]=nil
        else
            count=count+1
            if not oldestAt or at<oldestAt then oldest,oldestAt=key,at end
        end
    end
    if count>=CAP and oldest then map[oldest]=nil end
end

local function EnsureTicker(self)
    if not self.ticker then self.ticker=C_Timer.NewTicker(1,function() self:Pump() end) end
end

local function StopTicker(self)
    if self.ticker then self.ticker:Cancel(); self.ticker=nil end
end

function Presence:Notify()
    if self.notifyQueued then return end
    self.notifyQueued=true
    C_Timer.After(.1,function()
        self.notifyQueued=nil
        if not self.running then return end
        local board=JP.ApplicantBoard
        if board and board.page and board.page:IsShown() then board:Render(); board:RefreshParty() end
        local welcome=JP.Welcome
        if welcome and welcome.frame and welcome.frame:IsShown() and JP.GroupSearchUI then
            JP.GroupSearchUI:RenderRows(welcome)
        end
        local reviews=JP.Reviews
        if reviews and reviews.playerTip and reviews.playerTip:IsShown() and reviews.playerTip.owner then
            reviews:ShowPlayerTooltip(reviews.playerTip.owner,reviews.playerTip.target)
        end
    end)
end

function Presence:Mark(name)
    if not self.running then return end
    name=FullName(name)
    if not name then return end
    self.seen=self.seen or {}; Trim(self.seen,TTL)
    local key=name:lower(); local fresh=not self.seen[key] or GetTime()-self.seen[key]>=TTL
    self.seen[key]=GetTime()
    EnsureTicker(self)
    if fresh then self:Notify() end
end

function Presence:IsUser(name)
    name=JP.SafeString(name)
    if not name or not name:find("-",1,true) then return false end
    name=FullName(name)
    if not name then return false end
    local own=JP.Reviews.FullName(UnitFullName("player"))
    if own and name:lower()==own:lower() then return true end
    local at=self.seen and self.seen[name:lower()]
    return at~=nil and GetTime()-at<TTL
end

function Presence:Queue(channel, packet)
    if not self.running or not ChannelAvailable(channel) then return end
    self.queue=self.queue or {}; self.announced=self.announced or {}
    local key, now=channel..":"..packet,GetTime()
    local last=self.announced[key]
    if #self.queue>=8 or (last and now-last<(packet=="Q1" and 120 or 5)) then return end
    self.announced[key]=now
    self.queue[#self.queue+1]={channel=channel,packet=packet,tries=0}
    EnsureTicker(self)
end

function Presence:Request()
    -- Discovery uses joined channels, never a whisper to a roster/search
    -- name. Offline or delisted characters otherwise produce system errors.
    if ChannelAvailable("INSTANCE_CHAT") then self:Queue("INSTANCE_CHAT","Q1")
    elseif ChannelAvailable("RAID") then self:Queue("RAID","Q1")
    elseif ChannelAvailable("PARTY") then self:Queue("PARTY","Q1") end
    self:Queue("GUILD","Q1")
end

function Presence:Decorate(name, label)
    return (self:IsUser(name) and (ICON.." ") or "") .. (JP.SafeString(label) or JP.SafeString(name) or "—")
end

function Presence:Pump()
    local now=GetTime()
    -- A quiet party can stay together longer than the presence TTL. Renew
    -- discovery while joined, including when the first handshake was missed.
    local joined=ChannelAvailable("INSTANCE_CHAT") or ChannelAvailable("RAID")
        or ChannelAvailable("PARTY") or ChannelAvailable("GUILD")
    if self.running and joined and now>=(self.discoveryAt or 0) then
        self.discoveryAt=now+120
        self:Request()
    end
    if self.running and (not self.expiryAt or now>=self.expiryAt) then
        self.expiryAt=now+10
        local changed=false
        for key,at in pairs(self.seen or {}) do
            if now-at>=TTL then self.seen[key]=nil; changed=true end
        end
        if changed then self:Notify() end
    end
    if not self.running or (not joined and (not self.queue or #self.queue==0) and not next(self.seen or {})) then
        StopTicker(self)
        return
    end
    if not self.queue or #self.queue==0 then return end
    if not self.windowAt or now-self.windowAt>=60 then self.windowAt=now; self.sentCount=0 end
    if self.sentCount>=16 or now<(self.retryAt or 0) then return end
    if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then self.retryAt=now+5; return end
    local entry=self.queue[1]
    if not ChannelAvailable(entry.channel) then table.remove(self.queue,1); return end
    -- Presence only: never attach reviews, account IDs or player data to a
    -- discovery packet. Bounded queue, no loops and no ordinary chat text.
    local ok,result=pcall(C_ChatInfo.SendAddonMessage,PREFIX,entry.packet,entry.channel)
    self.sentCount=self.sentCount+1
    local success=Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success
    if ok and ((success~=nil and JP.SafeNumber(result)==success) or (success==nil and result==nil)) then
        table.remove(self.queue,1); self.retryAt=nil
    else
        entry.tries=entry.tries+1; self.retryAt=now+5
        if entry.tries>=3 then table.remove(self.queue,1) end
    end
    if not joined and #self.queue==0 and not next(self.seen or {}) then StopTicker(self) end
end

function Presence:Receive(prefix,message,channel,sender)
    prefix,message,channel=JP.SafeString(prefix),JP.SafeString(message),JP.SafeString(channel)
    if not self.running or prefix~=PREFIX or (message~="Q1" and message~="A1") then return end
    if channel~="WHISPER" and not ChannelAvailable(channel) then return end
    sender=FullName(sender); if not sender then return end
    local own=JP.Reviews.FullName(UnitFullName("player"))
    if sender==own then return end
    self:Mark(sender)
    -- Older clients may whisper us. Remember them without sending a whisper
    -- back; current clients discover each other through shared channels.
    if message=="Q1" and channel~="WHISPER" then self:Queue(channel,"A1") end
end

function Presence:Enable()
    self.running=true
    if not self.events then
        self.events=CreateFrame("Frame")
        self.events:SetScript("OnEvent",function(_,event,...)
            if event=="CHAT_MSG_ADDON" then self:Receive(...)
            else self:Request() end
        end)
    end
    for _,event in ipairs({"CHAT_MSG_ADDON","GROUP_ROSTER_UPDATE","PLAYER_ENTERING_WORLD","PLAYER_GUILD_UPDATE"}) do self.events:RegisterEvent(event) end
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
    self:Request()
end

function Presence:Disable()
    self.running=false; self.queue={}; self.seen={}; self.announced={}; self.discoveryAt=nil
    StopTicker(self)
    if self.events then self.events:UnregisterAllEvents() end
end
function Presence:Destroy() self:Disable() end
JP.AddonPresence=Presence
JP:RegisterModule("AddonPresence",Presence)
