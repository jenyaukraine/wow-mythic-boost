local _, JP = ...
local L, Module = JP.L, {}
local EVENTS={"CHAT_MSG_CHANNEL","CHAT_MSG_SAY","CHAT_MSG_YELL"}
local PATTERNS={" wts "," wtb "," wtt "," платно "," продажа "," продам "," за золото "}
local LIMIT, DELAY = 128, 1.2

local function PublicText(value,max)
    value=JP.SafeString(value)
    if value and #value<=max then return value end
end
local function IsAdvertisement(message)
    local normalized=" "..message:lower():gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r",""):gsub("[%p%s]+"," ").." "
    for _,pattern in ipairs(PATTERNS) do if normalized:find(pattern,1,true) then return true end end
end

function Module:Flush(key,expected)
    local entry=self.pending and self.pending[key]
    if not entry or (expected and expected~=entry) then return end
    self.pending[key]=nil
    if entry.timer then entry.timer:Cancel(); entry.timer=nil end
    local channel=entry.channel~="" and entry.channel or L("CHAT SPAM")
    local sender="|Hplayer:"..entry.sender.."|h["..entry.sender.."]|h"
    local text="["..channel.."] "..sender..": "..entry.text
    if entry.count>1 then text=text..("   |cff7a8496x%d|r"):format(entry.count) end
    entry.frame:AddMessage(text,entry.r,entry.g,entry.b)
end

function Module:OnChatMessage(frame,event,message,sender,language,channelName,...)
    if not self.enabled or frame~=DEFAULT_CHAT_FRAME then return false end
    local text=PublicText(message,1024)
    local author=PublicText(sender,100)
    local channel=PublicText(channelName,150)
    event=PublicText(event,64)
    if not text or not author or not channel or not event or author=="" or
        author:find("[|%z\1-\31\127]") or channel:find("[|%z\1-\31\127]") or not IsAdvertisement(text) then return false end
    -- Exact text only; prices, punctuation, authors and channels remain distinct.
    local key=table.concat({event,channel,author,text},"\031")
    local entry=self.pending[key]
    if not entry then
        local count,oldest,oldTime=0,nil,math.huge
        for pendingKey,pending in pairs(self.pending) do
            count=count+1
            if pending.at<oldTime then oldest,oldTime=pendingKey,pending.at end
        end
        if count>=LIMIT then self:Flush(oldest) end
        local color=ChatTypeInfo and ChatTypeInfo[event:gsub("^CHAT_MSG_","")]
        entry={frame=frame,text=text,sender=author,channel=channel,count=0,at=GetTime(),
            r=color and JP.SafeNumber(color.r) or 1,g=color and JP.SafeNumber(color.g) or .92,
            b=color and JP.SafeNumber(color.b) or .55}
        self.pending[key]=entry
        -- Fixed deadline: continuous spam cannot postpone display forever.
        entry.timer=C_Timer.NewTimer(DELAY,function() self:Flush(key,entry) end)
    end
    entry.count=math.min(entry.count+1,999999)
    return true
end

function Module:Enable()
    if self.enabled then return end
    if not ChatFrame_AddMessageEventFilter or not ChatFrame_RemoveMessageEventFilter or not C_Timer.NewTimer then
        JP:Log(L("Чат конденсер не получил событий для WTS-фильтра.")); return
    end
    self.enabled=true; self.pending={}
    self.filter=self.filter or function(...) return self:OnChatMessage(...) end
    for _,event in ipairs(EVENTS) do ChatFrame_AddMessageEventFilter(event,self.filter) end
end
function Module:Disable()
    self.enabled=false
    if self.filter and ChatFrame_RemoveMessageEventFilter then
        for _,event in ipairs(EVENTS) do ChatFrame_RemoveMessageEventFilter(event,self.filter) end
    end
    for key in pairs(self.pending or {}) do self:Flush(key) end
    self.pending={}
end
function Module:Destroy() self:Disable() end
JP.ChatSpamCondenser=Module
JP:RegisterModule("ChatSpamCondenser",Module)
