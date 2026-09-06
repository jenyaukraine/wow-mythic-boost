local _, JP = ...
local Reviews = {}
local L = JP.L
local PREFIX = "MBReviews2"
local MAX_RECORDS, MAX_TEXT = JP.Limits.REVIEW_RECORDS, JP.Limits.REVIEW_TEXT_BYTES
local MAX_WIRE, CHUNK, MAX_PARTS = 768, 200, 4
local TTL, ROUND = 90 * 86400, 120
local MAX_QUEUE, MAX_INCOMING = 64, 16

local function Settings()
    local s = JP.Settings("reviews", {sync=true, records={}, sharedRecords={}})
    if type(s.records) ~= "table" then s.records = {} end
    if type(s.sharedRecords) ~= "table" then s.sharedRecords = {} end
    -- The pre-MBReviews2 database was the public gossip database.  Migrate it
    -- once, while preserving records explicitly marked shared=false as local
    -- opt-outs.  PlayerNetwork's private store is a different SavedVariables
    -- key and is never touched here.
    if s.sharedMigration ~= 1 then
        for id, record in pairs(s.records) do
            if type(record) == "table" and record.shared ~= false then
                record.shared = true
                s.sharedRecords[id] = record
                s.records[id] = nil
            end
        end
        s.sharedMigration = 1
    end
    return s
end

function Reviews.CleanText(value)
    value = JP.SafeString(value) or ""
    value = value:gsub("|T.-|t", ""):gsub("|A.-|a", "")
        :gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|", ""):gsub("[%z\1-\31\127]", " "):match("^ *(.-) *$")
    local last = math.min(#value, MAX_TEXT)
    while last > 0 and value:byte(last+1) and value:byte(last+1) >= 128 and value:byte(last+1) < 192 do last = last-1 end
    return value:sub(1,last)
end

function Reviews.FullName(value, realm)
    value, realm = JP.SafeString(value), JP.SafeString(realm)
    if not value then return end
    if not value:find("-",1,true) then
        realm = realm or (GetNormalizedRealmName and JP.SafeString(GetNormalizedRealmName()))
        if not realm then return end
        value = value .. "-" .. realm
    end
    local name, server = value:match("^([^%-]+)%-(.+)$")
    if not name or name:find("[ %z\1-\31\127|]") or server:find("[%z\1-\31\127|]") or #value > 100 then return end
    return name .. "-" .. server:gsub(" ", "")
end

local function Key(name) return name:lower() end
local function ID(author,target) return Key(author) .. "\t" .. Key(target) end
local function OwnName()
    if not UnitFullName then return end
    local name, realm = UnitFullName("player")
    return Reviews.FullName(name, realm)
end

function Reviews:Validate(record)
    if not JP.SafeTable(record) then return end
    local author, target = self.FullName(record.author), self.FullName(record.target)
    local stamp, vote = JP.SafeNumber(record.stamp), JP.SafeNumber(record.vote)
    if not author or not target or not stamp or stamp ~= math.floor(stamp)
        or stamp < time()-TTL or stamp > time()+300 or (vote ~= -1 and vote ~= 0 and vote ~= 1) then return end
    local map, level = JP.SafeNumber(record.map) or 0, JP.SafeNumber(record.level) or 0
    if map < 0 or map > 100000 or level < 0 or level > 100 or map%1 ~= 0 or level%1 ~= 0 then return end
    local runAt=JP.SafeNumber(record.runAt)
    if not runAt or runAt<1 or runAt>9999999999 or runAt%1~=0 then runAt=nil end
    return {author=author, target=target, stamp=stamp, vote=vote,
        text=self.CleanText(record.text), map=map, level=level,
        stats=JP.RunStats and JP.RunStats:Validate(record.stats) or nil,
        runAt=runAt,
        shared=record.shared == true}
end

function Reviews:Prune()
    local settings = Settings()
    local records, ordered, own = settings.records, {}, OwnName()
    for id, record in pairs(records) do
        local valid = self:Validate(record)
        if not valid or valid.shared or id ~= ID(valid.author,valid.target) then records[id] = nil
        else
            record.stats=valid.stats
            ordered[#ordered+1] = {id=id, stamp=record.stamp, mine=own and Key(record.author)==Key(own)}
        end
    end
    table.sort(ordered, function(a,b)
        if a.mine ~= b.mine then return a.mine == true end
        if a.stamp ~= b.stamp then return a.stamp > b.stamp end
        return a.id < b.id
    end)
    for i=MAX_RECORDS+1,#ordered do records[ordered[i].id] = nil end
    local public, publicOrdered = settings.sharedRecords, {}
    for id, record in pairs(public) do
        local valid = self:Validate(record)
        if not valid or not valid.shared or id ~= ID(valid.author,valid.target)
            or record.stamp < time()-TTL then public[id] = nil
        else
            record.stats=valid.stats; record.shared=true
            publicOrdered[#publicOrdered+1] = {id=id, stamp=record.stamp, mine=own and Key(record.author)==Key(own)}
        end
    end
    table.sort(publicOrdered, function(a,b)
        if a.mine ~= b.mine then return a.mine == true end
        if a.stamp ~= b.stamp then return a.stamp > b.stamp end
        return a.id < b.id
    end)
    for i=MAX_RECORDS+1,#publicOrdered do public[publicOrdered[i].id] = nil end
    self.index = nil
    self.revision = (self.revision or 0) + 1
end

function Reviews:Store(record, sender, mine)
    local valid = self:Validate(record)
    if not valid then return false end
    local settings, own = Settings(), OwnName()
    local records = valid.shared and settings.sharedRecords or settings.records
    local id = ID(valid.author, valid.target)
    local old = records[id]
    local direct = sender and Key(sender) == Key(valid.author)
    if mine and (not own or Key(valid.author) ~= Key(own)) then return false end
    if not mine and own and Key(valid.author) == Key(own) then return false end
    if old then
        if old.stamp > valid.stamp then return false end
        if old.stamp == valid.stamp then
            -- Equal revision conflicts are not allowed to replace content.
            local oldStats = JP.RunStats and JP.RunStats:Encode(old.stats) or ""
            local newStats = JP.RunStats and JP.RunStats:Encode(valid.stats) or ""
            if old.vote ~= valid.vote or old.text ~= valid.text or old.map ~= valid.map or old.level ~= valid.level
                or oldStats ~= newStats or old.shared ~= valid.shared then return false end
            if direct and not old.direct then
                old.direct=true; old.via=sender; self.index=nil
                self.revision=(self.revision or 0)+1
            end
            return false
        end
    end
    valid.direct = mine or direct or false
    valid.via = not mine and sender or nil
    valid.statsTrusted = mine == true
    records[id] = valid
    if mine and valid.shared then
        -- Discard already queued fragments of a superseded public revision.
        -- The next round starts with the changed record, not an old cursor.
        self.outbox={}; self.cursor=0; self.nextRound=0
        if valid.vote~=0 or valid.text~="" then settings.records[id]=nil end
    end
    self:Prune()
    if not mine and records[id] == valid then self.lastReceived = time() end
    if records[id] == valid and JP.AddonPresence then JP.AddonPresence:Notify() end
    return records[id] == valid
end

-- Read-only snapshot for the database browser. Tombstones are counted, but
-- are not displayed as empty reviews; they prevent older relays resurrecting
-- deleted comments. Opening this view never sends or creates a review.
function Reviews:Database(query)
    local rows, stats, own = {}, {total=0, mine=0, direct=0, forwarded=0, deleted=0}, OwnName()
    local lower = strlower or string.lower
    query = lower(self.CleanText(query))
    local all, settings = {}, Settings()
    for _, record in pairs(settings.records) do all[#all+1] = record end
    for _, record in pairs(settings.sharedRecords) do all[#all+1] = record end
    for _, record in ipairs(all) do
        local valid = self:Validate(record)
        if valid then
            if valid.vote == 0 and valid.text == "" then stats.deleted=stats.deleted+1
            else
                local origin = own and Key(valid.author)==Key(own) and "mine"
                    or record.direct and "direct" or "forwarded"
                stats.total=stats.total+1; stats[origin]=stats[origin]+1
                if query == "" or lower(valid.target .. " " .. valid.author .. " " .. valid.text):find(query,1,true) then
                    valid.origin, valid.via = origin, self.FullName(record.via)
                    rows[#rows+1] = valid
                end
            end
        end
    end
    table.sort(rows,function(a,b)
        if a.stamp ~= b.stamp then return a.stamp>b.stamp end
        return ID(a.author,a.target)<ID(b.author,b.target)
    end)
    return rows, stats
end

function Reviews:Save(target, vote, text, run, shared)
    local own = OwnName()
    target = self.FullName(target)
    if not own or not target or Key(own) == Key(target) or not run then return false end
    local allowed = false
    for _, member in ipairs(run.members or {}) do
        if self.FullName(member) == target then allowed=true; break end
    end
    if not allowed then return false end
    -- Public by default for compatibility with the old gossip database;
    -- callers must pass false to keep a new review local-only.
    shared = shared ~= false
    local settings = Settings()
    local publicOld = settings.sharedRecords[ID(own,target)]
    local records = shared and settings.sharedRecords or settings.records
    local old = records[ID(own,target)]
    local cleaned = self.CleanText(text)
    local stats=JP.RunStats and JP.RunStats:ForMember(run,target)
    if old and old.vote == vote and old.text == cleaned
        and (not JP.RunStats or JP.RunStats:Encode(old.stats)==JP.RunStats:Encode(stats))
        and (shared or not publicOld or (publicOld.vote==0 and publicOld.text=="")) then return true end
    local record = {author=own,target=target,vote=vote,text=cleaned,shared=shared,
        stamp=math.max(time(), old and old.stamp+1 or 0),map=run.mapID or 0,level=run.level or 0,
        stats=(vote~=0 or cleaned~="") and stats or nil,runAt=run.completedAt}
    local saved = self:Store(record,own,true)
    if saved then
        if not shared and publicOld and not (publicOld.vote==0 and publicOld.text=="") then
            local withdrawn=self:Store({author=own,target=target,stamp=math.max(time(),publicOld.stamp+1),
                vote=0,text="",map=publicOld.map or 0,level=publicOld.level or 0,shared=true},own,true)
            if not withdrawn then return false end
        end
        self.nextRound=0; self:UpdatePump()
    end
    return saved
end

-- Explicitly publish an existing own review. This is intentionally separate
-- from Save so old/private records cannot leak merely by being read.
function Reviews:Publish(record)
    local own = OwnName()
    local valid = self:Validate(record)
    if not own or not valid or Key(valid.author) ~= Key(own) then return false end
    valid.shared = true
    local old = Settings().sharedRecords[ID(valid.author,valid.target)]
    valid.stamp = math.max(valid.stamp or 0, time(), old and old.stamp + 1 or 0)
    local saved = self:Store(valid, own, true)
    if saved then
        Settings().records[ID(valid.author,valid.target)] = nil
        self.index=nil
        self:UpdatePump()
    end
    return saved
end

-- Withdraw only the public copy. A tombstone prevents stale relays from
-- resurrecting it, while the local record (if any) remains available.
function Reviews:Withdraw(target)
    local own = OwnName(); target = self.FullName(target)
    if not own or not target or Key(own) == Key(target) then return false end
    local id, old = ID(own,target), Settings().sharedRecords[ID(own,target)]
    if not old then return false end
    local saved=self:Store({author=own,target=target,stamp=math.max(time(),old.stamp+1),vote=0,
        text="",map=old.map or 0,level=old.level or 0,shared=true}, own, true)
    if saved then self:UpdatePump() end
    return saved
end

-- Late native meter data refreshes only an exact-run review. Public reviews
-- receive a new revision so their bounded stats snapshot can be relayed.
function Reviews:UpdateRunStats(run)
    local settings = Settings()
    for _,member in ipairs(run.members or {}) do
        local target=self.FullName(member)
        local localOld=target and settings.records[ID(OwnName() or "",target)]
        local publicOld=target and settings.sharedRecords[ID(OwnName() or "",target)]
        local candidates = {}
        if localOld then candidates[#candidates+1] = localOld end
        if publicOld then candidates[#candidates+1] = publicOld end
        for _, old in ipairs(candidates) do
            local at=old.stats and old.stats.runAt or old.runAt
            if at and at==run.completedAt and (old.vote~=0 or old.text~="") then
                local stats=JP.RunStats:ForMember(run,target)
                if JP.RunStats:Encode(old.stats)~=JP.RunStats:Encode(stats) then
                    old.stats=stats
                    if old.shared then
                        old.stamp=math.max(time(),old.stamp+1)
                        old.statsTrusted=true
                        self.index=nil; self.revision=(self.revision or 0)+1
                        self.outbox={}; self.cursor=0; self.nextRound=0; self:UpdatePump()
                    else
                        self.index=nil; self.revision=(self.revision or 0)+1
                    end
                end
            end
        end
    end
    if self.RefreshRunStats then self:RefreshRunStats(run) end
end

function Reviews:GetOwn(target)
    local own = OwnName(); target=self.FullName(target)
    if not own or not target then return end
    local settings = Settings()
    local public = settings.sharedRecords[ID(own,target)]
    if public and not (public.vote==0 and public.text=="") then return public end
    return settings.records[ID(own,target)] or public
end

function Reviews:Get(target)
    -- Never attach another realm's review to a bare LFG member name.
    if not JP.SafeString(target) or not target:find("-",1,true) then return {} end
    target = self.FullName(target)
    if not target then return {} end
    if not self.index then
        self.index = {}
        local settings, public = Settings(), {}
        for _, record in pairs(settings.sharedRecords) do
            if record.stamp >= time()-TTL and (record.vote ~= 0 or record.text ~= "") then
                public[ID(record.author,record.target)] = record
            end
        end
        for _, record in pairs(settings.records) do
            if record.stamp >= time()-TTL and (record.vote ~= 0 or record.text ~= "")
                and not public[ID(record.author,record.target)] then
                local key = Key(record.target)
                self.index[key] = self.index[key] or {}
                table.insert(self.index[key],record)
            end
        end
        for _, record in pairs(settings.sharedRecords) do
            if record.stamp >= time()-TTL and (record.vote ~= 0 or record.text ~= "") then
                local key = Key(record.target)
                self.index[key] = self.index[key] or {}
                table.insert(self.index[key],record)
            end
        end
        for _, rows in pairs(self.index) do
            table.sort(rows,function(a,b) return a.stamp == b.stamp and a.author < b.author or a.stamp > b.stamp end)
        end
    end
    return self.index[Key(target)] or {}
end

function Reviews:Summary(target)
    local record = self:Get(target)[1]
    if not record then return end
    local rating = record.vote==1 and L("Лайк") or record.vote==-1 and L("Дизлайк") or L("Комментарий")
    local source = record.direct and L("Получено от автора") or L("Переслано; автор не подтверждён")
    return ("%s: %s / %s\n%s%s"):format(target, rating, record.author,
        record.text ~= "" and (record.text .. "\n") or "", source)
end

function Reviews:Rating(target)
    local key=JP.SafeString(target)
    if key then key=Key(key) end
    if self.ratingRevision~=self.revision then self.ratingCache={}; self.ratingRevision=self.revision end
    self.ratingCache=self.ratingCache or {}
    local cached=key and self.ratingCache[key]
    if cached then return unpack(cached) end
    local score, likes, dislikes, seen, recent, total = 0, 0, 0, {}, {}, 0
    for _, record in ipairs(self:Get(target)) do
        local author = Key(record.author)
        if not seen[author] then
            seen[author] = true; total = total+1; score = score+record.vote
            if record.vote == 1 then likes=likes+1 elseif record.vote == -1 then dislikes=dislikes+1 end
            if #recent < 10 then recent[#recent+1] = record end
        end
    end
    -- Only reviewed targets are cached: at most the record limit, never
    -- an unbounded history of every unknown applicant searched for.
    if key and total>0 then self.ratingCache[key]={score,total,likes,dislikes,recent} end
    return score, total, likes, dislikes, recent
end

function Reviews:AddTooltip(tip, target)
    if JP.PlayerNetwork then JP.PlayerNetwork:AddTooltip(tip,target) end
    local score, total, likes, dislikes, records = self:Rating(target)
    if total == 0 then return false end
    tip:AddLine(" "); tip:AddLine((L("Отзывы: %+d  |  лайки %d / дизлайки %d")):format(score, likes, dislikes), .2,.8,1)
    local own = OwnName()
    for _, record in ipairs(records) do
        local marker = record.vote==1 and "+1" or record.vote==-1 and "-1" or "0"
        local forwarded = not record.direct and not (own and Key(record.author)==Key(own))
        tip:AddDoubleLine(marker .. "  " .. record.author .. (forwarded and " *" or ""), date("%d.%m", record.stamp),
            .95,.85,.6, .55,.6,.65)
        if record.text ~= "" then tip:AddLine(record.text, .85,.9,.92, true) end
    end
    tip:AddLine((L("Последние %d из %d авторов; * переслано, автор не подтверждён.")):format(#records,total), .55,.6,.65,true)
    return true
end

local function CommsAllowed()
    -- These are addon-prefix packets, not player-authored chat messages.
    -- The send API reports its own failure/throttling result; normal chat
    -- lockdown and the player's combat flag must not discard the queue.
    return C_ChatInfo and type(C_ChatInfo.SendAddonMessage) == "function"
end

local function ChatGateAllowed()
    local api = C_ChatInfo
    if not api then return false end
    for _, name in ipairs({"InChatMessagingLockdown", "AreOutgoingAddonChatMessagesRestricted"}) do
        local fn = api[name]
        if type(fn) == "function" then
            local ok, value = pcall(fn)
            if not ok or JP.SafeOptionalBoolean(value) ~= false then return false end
        end
    end
    return true
end

function Reviews:SyncStatus()
    if not self.running then return L("Обмен выключен") end
    if not CommsAllowed() or not ChatGateAllowed() or self.sendFailed then return L("Обмен ожидает отправку; очередь сохранена") end
    if not next(self.peers or {}) then return L("Обмен ожидает группу или рейд") end
    return L("Обмен работает постоянно, включая бой")
end

function Reviews:CachePeers()
    self.peers = {}; self.incoming = {}; self.rates = {}
    local raid = JP.SafeOptionalBoolean(IsInRaid()) == true
    local instanceGroup = IsInGroup and LE_PARTY_CATEGORY_INSTANCE
        and JP.SafeOptionalBoolean(IsInGroup(LE_PARTY_CATEGORY_INSTANCE)) == true
    self.channel = instanceGroup and "INSTANCE_CHAT" or raid and "RAID" or "PARTY"
    local own = OwnName()
    for i=1,(raid and math.min(40, JP.SafeNumber(GetNumGroupMembers()) or 0) or 4) do
        local unit = (raid and "raid" or "party") .. i
        if JP.SafeOptionalBoolean(UnitExists(unit)) == true then
            local n, r = UnitFullName(unit)
            local name = self.FullName(n, r)
            if name and name ~= own then self.peers[Key(name)] = true end
        end
    end
    self:UpdatePump()
end

function Reviews:IsCurrentPeer(sender)
    local wanted=Key(sender)
    local raid=JP.SafeOptionalBoolean(IsInRaid())==true
    for i=1,(raid and math.min(40,JP.SafeNumber(GetNumGroupMembers()) or 0) or 4) do
        local unit=(raid and "raid" or "party")..i
        if JP.SafeOptionalBoolean(UnitExists(unit))==true
            and (not UnitIsPlayer or JP.SafeOptionalBoolean(UnitIsPlayer(unit))==true) then
            local name,realm=UnitFullName(unit)
            name=self.FullName(name,realm)
            if name and Key(name)==wanted then return true end
        end
    end
    return false
end

local function Encode(record)
    if not record or record.shared ~= true then return end
    local stats = JP.RunStats and JP.RunStats:Encode(record.stats) or ""
    return table.concat({record.author,record.target,record.stamp,record.vote,record.map,record.level,
        record.text or "",stats,"1"}, "\t")
end

function Reviews:QueueRound()
    self:Prune()
    local records, own = {}, OwnName()
    for _, record in pairs(Settings().sharedRecords) do records[#records+1] = record end
    table.sort(records,function(a,b)
        local am,bm = a.author==own,b.author==own
        if am ~= bm then return am end
        if a.stamp ~= b.stamp then return a.stamp>b.stamp end
        return ID(a.author,a.target)<ID(b.author,b.target)
    end)
    self.outbox = {}
    if #records == 0 then return end
    local start = (self.cursor or 0) % #records
    for i=1,math.min(16,#records) do
        local record = records[(start+i-1)%#records+1]
        local wire = Encode(record)
        if #wire <= MAX_WIRE then
            self.sequence = (self.sequence or 0)+1
            local id = time() .. ":" .. self.sequence
            local parts = math.ceil(#wire/CHUNK)
            for part=1,parts do
                if #self.outbox >= MAX_QUEUE then break end
                self.outbox[#self.outbox+1] = table.concat({"D",id,part,parts,wire:sub((part-1)*CHUNK+1,part*CHUNK)},"\t")
            end
        end
    end
    self.cursor = (start+math.min(16,#records)) % #records
end

function Reviews:Pump()
    if not self.running or not next(self.peers or {}) then self:UpdatePump(); return end
    local now = GetTime()
    for key, buffer in pairs(self.incoming or {}) do if now-buffer.at > 10 then self.incoming[key]=nil end end
    if not CommsAllowed() or not ChatGateAllowed() or now < (self.retryAt or 0)
        or now < (self.lastSentAt or -math.huge) + 1 then return end
    if now >= (self.nextRound or 0) and (not self.outbox or #self.outbox == 0) then
        self.nextRound=now+ROUND; self:QueueRound()
    end
    if self.outbox and #self.outbox > 0 then
        -- At most one <=255-byte packet per second; no retry loops or whispers.
        local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, self.outbox[1], self.channel or "PARTY")
        local success = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success
        if ok and ((success ~= nil and JP.SafeNumber(result) == success) or (success == nil and result == nil)) then
            table.remove(self.outbox,1); self.sendFailed=nil; self.retryAt=nil; self.lastSentAt=now
        else
            self.sendFailed=true; self.retryAt=now+5
        end
    end
end

function Reviews:UpdatePump()
    local enabled = self.running and next(self.peers or {})
    if not enabled then
        if self.ticker then self.ticker:Cancel(); self.ticker=nil end
        self.outbox={}; self.incoming={}; self.sendFailed=nil; self.retryAt=nil; self.lastSentAt=nil
    elseif not self.ticker then
        self.nextRound=0
        self.ticker=C_Timer.NewTicker(1,function() self:Pump() end)
    end
end

function Reviews:Receive(prefix, message, channel, sender)
    if not self.running then return end
    prefix, message, channel, sender = JP.SafeString(prefix), JP.SafeString(message), JP.SafeString(channel), self.FullName(sender)
    if prefix ~= PREFIX or channel ~= (self.channel or "PARTY") or not message or #message > 255
        or not sender or not (self.peers or {})[Key(sender)] or not self:IsCurrentPeer(sender) then return end
    local now = GetTime()
    local rate = self.rates[Key(sender)]
    if not rate or now-rate.at >= 60 then rate={at=now,count=0}; self.rates[Key(sender)]=rate end
    rate.count=rate.count+1; if rate.count>64 then return end
    local id, part, total, payload = message:match("^D\t([%d:]+)\t(%d)\t(%d)\t(.*)$")
    part,total=tonumber(part),tonumber(total)
    if not id or #id>32 or not part or not total or part<1 or total<1 or part>total or total>MAX_PARTS or #payload>CHUNK then return end
    local key = Key(sender) .. ":" .. id
    local buffer = self.incoming[key]
    if buffer and now-buffer.at > 10 then self.incoming[key]=nil; buffer=nil end
    if not buffer then
        local count=0; for _ in pairs(self.incoming) do count=count+1 end
        if count>=MAX_INCOMING then return end
        buffer={at=now,parts={},total=total}; self.incoming[key]=buffer
    end
    if total~=buffer.total then self.incoming[key]=nil; return end
    buffer.parts[part]=payload
    for i=1,total do if not buffer.parts[i] then return end end
    self.incoming[key]=nil
    local wire = table.concat(buffer.parts)
    if #wire>MAX_WIRE then return end
    local author,target,stamp,vote,map,level,text,stats,shared = wire:match("^([^\t]+)\t([^\t]+)\t(%d+)\t([%-]?%d+)\t(%d+)\t(%d+)\t([^\t]*)\t([^\t]*)\t(1)$")
    if not author or not shared then return end
    local decoded = stats ~= "" and JP.RunStats and JP.RunStats:Decode(stats) or nil
    if stats ~= "" and not decoded then return end
    local record={author=author,target=target,stamp=tonumber(stamp),vote=tonumber(vote),map=tonumber(map),level=tonumber(level),text=text,stats=decoded,shared=true}
    if self:Validate(record) and JP.AddonPresence then JP.AddonPresence:Mark(sender) end
    self:Store(record,sender,false)
end

function Reviews:Enable()
    self.running=true; Settings().sync=true; self:Prune()
    if not self.events then
        self.events=CreateFrame("Frame")
        self.events:SetScript("OnEvent",function(_,event,...)
            if event=="CHAT_MSG_ADDON" then self:Receive(...)
            elseif event=="GROUP_ROSTER_UPDATE" or event=="PLAYER_ENTERING_WORLD" then self:CachePeers()
            else self:UpdatePump() end
            if event=="PLAYER_REGEN_ENABLED" and self.pendingRun and self.ShowRun then self:ShowRun(self.pendingRun) end
        end)
    end
    for _,event in ipairs({"GROUP_ROSTER_UPDATE","PLAYER_ENTERING_WORLD","PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED"}) do self.events:RegisterEvent(event) end
    -- MBReviews1 text gossip is retired; migrated records are sent as
    -- MBReviews2 and existing records remain readable locally.
    self.events:RegisterEvent("CHAT_MSG_ADDON")
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
    self:CachePeers()
end
function Reviews:Disable()
    self.running=false
    if self.events then self.events:UnregisterAllEvents() end
    self:UpdatePump(); self.index=nil; self.ratingCache=nil; self.ratingRevision=nil; self.pendingRun=nil
    if self.HidePlayerTooltip then self:HidePlayerTooltip() end
    if self.frame then self.frame:Hide() end
    if self.rosterFrame then self.rosterFrame:Hide() end
end
function Reviews:Destroy() self:Disable() end
JP.Reviews=Reviews
JP:RegisterModule("Reviews",Reviews)
