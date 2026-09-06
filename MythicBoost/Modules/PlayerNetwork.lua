local _, JP = ...
local Network, L = {}, JP.L
JP.PlayerNetwork = Network

-- The wire protocol is intentionally tiny. A D packet contains only an
-- author, target, revision and seven public positive-tag bits. Do not add
-- fields from Reviews, RunHistory or RunStats here.
local PREFIX = "MBNetwork1"
local PROTOCOL = "1"
local TTL, LIMIT = 90 * 86400, 1000
local PRIVATE_LIMIT, QUEUE_LIMIT = 200, 64
local RATE_WINDOW, RATE_LIMIT = 60, 90
local SEND_INTERVAL, MAX_BACKOFF = 1, 60

local function Settings()
    local s = JP.Settings("playerNetwork", {enabled=true, records={}, private={}})
    if type(s.records) ~= "table" then s.records={} end
    if type(s.private) ~= "table" then s.private={} end
    return s
end
local function Full(name,realm) return JP.Reviews and JP.Reviews.FullName and JP.Reviews.FullName(name,realm) end
local function UnitFull(unit)
    if not UnitFullName then return end
    local name,realm=UnitFullName(unit)
    return Full(name,realm)
end
local function Own() return UnitFull("player") end
local function Key(a,b) return a:lower().."\t"..b:lower() end
local function Int(n,max)
    n=JP.SafeNumber(n)
    if n and n==n and n>=0 and n<=max and n%1==0 then return n end
end
local function OutOfCombat() return InCombatLockdown and JP.SafeOptionalBoolean(InCombatLockdown())==false end

Network.tags={
    L("Рекомендую"),L("Хороший танк"),L("Хороший хил"),L("Хороший DPS"),
    L("Хороший лидер"),L("Приятный напарник"),L("Сыграл бы снова"),
}

function Network:Validate(r)
    if not JP.SafeTable(r) then return end
    local author,target=Full(r.author),Full(r.target)
    local stamp,mask=Int(r.stamp,9999999999),Int(r.mask,127)
    if not author or not target or author:lower()==target:lower()
        or not stamp or mask==nil or stamp<time()-TTL or stamp>time()+300 then return end
    return {author=author,target=target,stamp=stamp,mask=mask}
end
local function PrivateNote(value)
    if JP.Reviews and JP.Reviews.CleanText then return JP.Reviews.CleanText(value) end
    return JP.SafeString(value) or ""
end

-- RunHistory versions before the realm-normalisation fix used bare names as
-- map keys. Resolve those keys against the current realm only; an explicit
-- cross-realm key remains distinct.
local function HistoryPlayer(players, target)
    if type(players) ~= "table" or not target then return end
    local direct = players[target:lower()]
    if direct then return direct end
    local checked = 0
    for name, value in pairs(players) do
        if checked >= 200 then break end
        checked = checked + 1
        local normalized = type(name) == "string" and Full(name)
        if normalized and normalized:lower() == target:lower() then return value end
    end
end

function Network:Prune()
    local s,ordered,own=Settings(),{},Own()
    self.byTarget={}
    for key,record in pairs(s.records) do
        local valid=self:Validate(record)
        if not valid or key~=Key(valid.author,valid.target) then s.records[key]=nil
        else
            valid.direct=record.direct==true
            valid.via=valid.direct and nil or Full(record.via)
            s.records[key]=valid
            local targetKey=valid.target:lower()
            self.byTarget[targetKey]=self.byTarget[targetKey] or {}
            self.byTarget[targetKey][#self.byTarget[targetKey]+1]=valid
            ordered[#ordered+1]={key=key,stamp=valid.stamp,mine=own and valid.author:lower()==own:lower()}
        end
    end
    table.sort(ordered,function(a,b)
        if a.mine~=b.mine then return a.mine==true end
        if a.stamp~=b.stamp then return a.stamp>b.stamp end
        return a.key<b.key
    end)
    for i=LIMIT+1,#ordered do s.records[ordered[i].key]=nil end
    -- Rebuild after the cap so the UI index cannot retain pruned records.
    self.byTarget={}
    for _,record in pairs(s.records) do
        local targetKey=record.target:lower()
        self.byTarget[targetKey]=self.byTarget[targetKey] or {}
        self.byTarget[targetKey][#self.byTarget[targetKey]+1]=record
    end
    ordered={}
    for key,note in pairs(s.private) do
        local target=Full(key)
        local stamp=type(note)=="table" and Int(note.stamp,9999999999)
        if type(key)~="string" or not target or key~=target:lower()
            or type(note)~="table" or not stamp then s.private[key]=nil
        else
            local expires=Int(note.avoidUntil,9999999999)
            if expires and expires>0 and expires<=time() then expires=nil end
            s.private[key]={note=PrivateNote(note.note),stamp=stamp,avoidUntil=expires}
            ordered[#ordered+1]={key=key,stamp=stamp}
        end
    end
    table.sort(ordered,function(a,b) if a.stamp~=b.stamp then return a.stamp>b.stamp end; return a.key<b.key end)
    for i=PRIVATE_LIMIT+1,#ordered do s.private[ordered[i].key]=nil end
    self.revision=(self.revision or 0)+1
end

function Network:Store(record,sender,mine)
    local valid=self:Validate(record)
    if not valid then return false end
    local own=Own(); sender=Full(sender)
    if not mine and own and valid.author:lower()==own:lower() then return false end
    local key,records=Key(valid.author,valid.target),Settings().records
    local old=records[key]
    local direct=mine==true or (sender and sender:lower()==valid.author:lower())
    if old then
        if old.stamp>valid.stamp or (old.direct and not direct) then return false end
        if old.stamp==valid.stamp then
            -- Equal revisions are immutable, including tombstones.
            if old.mask~=valid.mask then return false end
            if direct and not old.direct then old.direct,old.via=true,nil; self.revision=(self.revision or 0)+1 end
            return false
        end
    end
    valid.direct=direct==true; valid.via=valid.direct and nil or sender
    records[key]=valid; self:Prune()
    -- Prune canonicalises the table, so identity with `valid` is not stable.
    local stored=records[key]
    return stored and stored.stamp==valid.stamp and stored.mask==valid.mask or false
end

function Network:GetOwn(target)
    target=Full(target); local own=Own()
    return target and own and Settings().records[Key(own,target)] or nil
end
function Network:Recommend(target,mask)
    target,mask=Full(target),Int(mask,127); local own=Own()
    if not target or not own or mask==nil then return false end
    local history=JP.Settings("runHistory",{players={},runs={}})
    if not HistoryPlayer(history.players or {}, target) then return false end
    local old=self:GetOwn(target)
    if not old and mask==0 then return true end
    if old and old.mask==mask then return true end
    local saved=self:Store({author=own,target=target,mask=mask,
        stamp=math.max(time(),old and old.stamp+1 or 0)},own,true)
    if saved then self.manifestAt=0 end
    return saved
end
function Network:Private(target)
    target=Full(target); local r=target and Settings().private[target:lower()]
    if r and r.avoidUntil and r.avoidUntil>0 and r.avoidUntil<=time() then r.avoidUntil=nil end
    return r
end
function Network:SavePrivate(target,note,days)
    target=Full(target)
    if not target or (days~=nil and days~=0 and days~=1 and days~=7 and days~=30) then return false end
    Settings().private[target:lower()]={note=PrivateNote(note),stamp=time(),
        avoidUntil=days and (days==0 and 0 or time()+days*86400) or nil}
    self:Prune(); return true
end

function Network:Context(target)
    target=Full(target)
    if not target then return {knownBy=0,trusted=0,via={}} end
    local key=target:lower(); local history=JP.Settings("runHistory",{players={},runs={}})
    local players=history.players or {}
    local context={history=HistoryPlayer(players,target),private=self:Private(target),knownBy=0,trusted=0,via={},runs={}}
    local own=Own()
    for _,r in ipairs((self.byTarget or {})[key] or {}) do
        if r.target:lower()==key and r.mask>0 and r.stamp>=time()-TTL then
            if own and r.author:lower()==own:lower() then context.recommended=r.mask
            else
                context.knownBy=context.knownBy+1
                if r.direct and HistoryPlayer(players,r.author) then
                    context.trusted=context.trusted+1
                    if #context.via<3 then context.via[#context.via+1]=r.author end
                end
            end
        end
    end
    table.sort(context.via)
    for _,run in ipairs(history.runs or {}) do
        for _,member in ipairs(run.members or {}) do
            local name=Full(member)
            if name and name:lower()==key then context.runs[#context.runs+1]=run; break end
        end
        if #context.runs>=10 then break end
    end
    return context
end
function Network:Summary(target)
    local c=self:Context(target); local parts={}
    if c.history then parts[#parts+1]=(L("Вместе: %d ключей - в таймер: %d")):format(c.history.runs or 0,c.history.timed or 0)
    else parts[#parts+1]=L("Совместных ключей пока нет") end
    if c.recommended then parts[#parts+1]=L("Твоя рекомендация") end
    if c.trusted>0 then
        parts[#parts+1]=(L("Рекомендуют знакомые: %d")):format(c.trusted)
        parts[#parts+1]=L("Ты").." → "..table.concat(c.via,", ").." → "..target
    elseif c.knownBy>0 then parts[#parts+1]=(L("Рекомендации сети: %d - связь не подтверждена")):format(c.knownBy) end
    if c.private and c.private.avoidUntil~=nil then parts[#parts+1]=L("Личная метка: пока не приглашать") end
    if c.private and c.private.note~="" then parts[#parts+1]=c.private.note end
    return table.concat(parts,"\n"),c
end
function Network:AddTooltip(tip,target)
    tip:AddLine(" "); tip:AddLine(L("ПАМЯТЬ ИГРОКА"),.1,.8,1)
    tip:AddLine(self:Summary(target),.85,.9,.92,true)
end

function Network:Enqueue(message)
    message=JP.SafeString(message)
    if not message or #message>255 or #self.outbox>=QUEUE_LIMIT or self.queued[message] then return false end
    self.queued[message]=true; self.outbox[#self.outbox+1]=message; return true
end
function Network:Manifest()
    local records={}
    for _,r in pairs(Settings().records) do if r.stamp>=time()-TTL then records[#records+1]=r end end
    table.sort(records,function(a,b) return Key(a.author,a.target)<Key(b.author,b.target) end)
    if #records==0 then return end
    local cursor=(self.cursor or 0)%#records
    for i=1,math.min(16,#records) do
        local r=records[(cursor+i-1)%#records+1]
        self:Enqueue(table.concat({"I",r.author,r.target,r.stamp},"\t"))
    end
    self.cursor=(cursor+math.min(16,#records))%#records
end

local function GroupChannel()
    local instance=IsInGroup and LE_PARTY_CATEGORY_INSTANCE
        and JP.SafeOptionalBoolean(IsInGroup(LE_PARTY_CATEGORY_INSTANCE))==true
    if instance then return "INSTANCE_CHAT",true end
    local raid=IsInRaid and JP.SafeOptionalBoolean(IsInRaid())==true
    return raid and "RAID" or "PARTY",raid
end
local function AddUnit(peers,unit,own)
    if UnitExists(unit) and (not UnitIsPlayer or UnitIsPlayer(unit)~=false) and UnitFullName then
        local name=UnitFull(unit)
        if name and (not own or name:lower()~=own:lower()) then peers[name:lower()]=true end
    end
end
function Network:ForEachUnit(fn)
    local _,raid=GroupChannel(); local prefix,count=raid and "raid" or "party",raid and 40 or 4
    for i=1,count do fn(prefix..i) end
    if raid and self.channel=="INSTANCE_CHAT" then for i=1,4 do fn("party"..i) end end
end
function Network:IsCurrentPeer(sender)
    local wanted=sender and sender:lower(); if not wanted then return false end
    local found=false
    self:ForEachUnit(function(unit)
        if not found and UnitExists(unit) and (not UnitIsPlayer or UnitIsPlayer(unit)~=false) and UnitFullName then
            local name=UnitFull(unit); if name and name:lower()==wanted then found=true end
        end
    end)
    return found
end
function Network:HasCurrentPeer()
    local found=false
    self:ForEachUnit(function(unit)
        if not found and UnitExists(unit) and (not UnitIsPlayer or UnitIsPlayer(unit)~=false) and UnitFullName then
            local name=UnitFull(unit)
            if name and self.peers[name:lower()] then found=true end
        end
    end)
    return found
end

function Network:Receive(prefix,message,channel,sender)
    prefix,message,channel,sender=JP.SafeString(prefix),JP.SafeString(message),JP.SafeString(channel),Full(sender)
    if not self.running or Settings().enabled==false or prefix~=PREFIX or channel~=self.channel
        or not sender or not self.peers[sender:lower()] or not self:IsCurrentPeer(sender)
        or not message or #message>255 then return end
    local key=sender:lower(); local now=GetTime(); local rate=self.rates[key]
    if not rate or now-rate.at>=RATE_WINDOW then rate={at=now,count=0}; self.rates[key]=rate end
    rate.count=rate.count+1; if rate.count>RATE_LIMIT then return end
    if message=="H\t"..PROTOCOL then
        if not self.discovered[key] then self.discovered[key]=true; self.manifestAt=0 end
        return
    end
    if not self.discovered[key] then return end
    local kind,author,target,stamp,mask=message:match("^([DIQ])\t([^\t]+)\t([^\t]+)\t(%d+)\t?(%d*)$")
    author,target,stamp=Full(author),Full(target),tonumber(stamp)
    if not kind or not author or not target or not stamp then return end
    if kind~="D" and mask~="" then return end
    if kind=="D" and mask=="" then return end
    if not self:Validate({author=author,target=target,stamp=stamp,mask=0}) then return end
    local record=Settings().records[Key(author,target)]
    if kind=="I" then
        local need=not record or record.stamp<stamp
        if record and record.direct and author:lower()~=key then need=false end
        if need then self:Enqueue(table.concat({"Q",author,target,stamp},"\t")) end
    elseif kind=="Q" then
        if record and record.stamp>=stamp then self:Enqueue(table.concat({"D",record.author,record.target,record.stamp,record.mask},"\t")) end
    else
        self:Store({author=author,target=target,stamp=stamp,mask=tonumber(mask)},sender,false)
    end
end

function Network:Pump()
    if not self.running or Settings().enabled==false or not OutOfCombat() then self:UpdatePump(); return end
    local now=GetTime(); if now<(self.retryAt or 0) or now<(self.sendAt or 0) then return end
    if not next(self.peers) or not self:HasCurrentPeer() then self:CachePeers(); return end
    if now>=(self.helloAt or 0) then self.helloAt=now+60; self:Enqueue("H\t"..PROTOCOL) end
    if next(self.discovered) and now>=(self.manifestAt or 0) and #self.outbox==0 then
        self.manifestAt=now+30; self:Manifest()
    end
    local message=self.outbox[1]; if not message then return end
    local api=C_ChatInfo; if not api or type(api.SendAddonMessage)~="function" then return end
    -- Blizzard can temporarily reject all outgoing addon chat.  If a
    -- lockdown API is present, only an explicit false is safe; nil/error is
    -- treated as unknown and leaves the packet queued for a later retry.
    for _,name in ipairs({"InChatMessagingLockdown","AreOutgoingAddonChatMessagesRestricted"}) do
        local gate=api[name]
        if type(gate)=="function" then
            local ok,value=pcall(gate)
            if not ok or JP.SafeOptionalBoolean(value)~=false then return end
        end
    end
    local ok,result=pcall(api.SendAddonMessage,PREFIX,message,self.channel)
    local success=Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success
    if ok and ((success~=nil and JP.SafeNumber(result)==success) or (success==nil and result==nil)) then
        self.queued[message]=nil; table.remove(self.outbox,1); self.retryAt,self.sendAt,self.backoff=nil,now+SEND_INTERVAL,nil
    else
        self.backoff=math.min(MAX_BACKOFF,(self.backoff or 5)*2); self.retryAt=now+self.backoff
    end
end
function Network:UpdatePump()
    local active=self.running and Settings().enabled~=false and next(self.peers or {}) and OutOfCombat()
    if not active then if self.ticker then self.ticker:Cancel(); self.ticker=nil end
    elseif not self.ticker then self.ticker=C_Timer.NewTicker(1,function() self:Pump() end) end
end
function Network:CachePeers()
    local previousChannel=self.channel; local oldPeers=self.peers or {}
    local channel,raid=GroupChannel(); local peers,own={},Own()
    local prefix,count=raid and "raid" or "party",raid and 40 or 4
    for i=1,count do AddUnit(peers,prefix..i,own) end
    if raid and channel=="INSTANCE_CHAT" then for i=1,4 do AddUnit(peers,"party"..i,own) end end
    local samePeers=previousChannel==channel
    if samePeers then
        for key in pairs(oldPeers) do if not peers[key] then samePeers=false; break end end
        if samePeers then for key in pairs(peers) do if not oldPeers[key] then samePeers=false; break end end end
    end
    self.channel,self.peers=channel,peers
    self.discovered,self.rates=self.discovered or {},self.rates or {}
    for key in pairs(self.discovered) do if not peers[key] then self.discovered[key]=nil end end
    for key in pairs(self.rates) do if not peers[key] then self.rates[key]=nil end end
    self.outbox,self.queued=self.outbox or {},self.queued or {}
    if not samePeers then
        self.outbox,self.queued={},{}
        self.retryAt,self.sendAt,self.backoff=nil,nil,nil
    end
    if not samePeers or previousChannel~=channel then self.helloAt,self.manifestAt=0,0 end
    self:UpdatePump()
end
function Network:Status()
    return Settings().enabled==false and L("Обмен рекомендациями выключен")
        or L("Личные заметки не передаются. Обмен: только рекомендации, вне боя.")
end
function Network:SetEnabled(value) Settings().enabled=value==true; self:CachePeers() end
function Network:Enable()
    self.running=true; self:Prune()
    if not self.events then
        self.events=CreateFrame("Frame")
        self.events:SetScript("OnEvent",function(_,event,...)
            if event=="CHAT_MSG_ADDON" then self:Receive(...)
            elseif event=="GROUP_ROSTER_UPDATE" or event=="PLAYER_ENTERING_WORLD" then self:CachePeers()
            else self:UpdatePump() end
        end)
    end
    for _,event in ipairs({"CHAT_MSG_ADDON","GROUP_ROSTER_UPDATE","PLAYER_ENTERING_WORLD","PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED"}) do self.events:RegisterEvent(event) end
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
    self:CachePeers()
end
function Network:Disable()
    self.running=false; self:UpdatePump(); if self.events then self.events:UnregisterAllEvents() end
    self.outbox,self.queued,self.peers,self.discovered,self.rates={}, {}, {}, {}, {}
    self.retryAt,self.sendAt,self.backoff=nil,nil,nil
    if self.frame then self.frame:Hide() end
    if self.rosterFrame then self.rosterFrame:Hide() end
end
function Network:Destroy() self:Disable() end
JP:RegisterModule("PlayerNetwork",Network)
