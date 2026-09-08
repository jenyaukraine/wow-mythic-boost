local _, JP = ...
local L = JP.L
local Tools = { tracked = {}, order = {} }
JP.GroupTools = Tools
local LIMIT = JP.Limits
local number, str = JP.SafeNumber, JP.SafeString
local numeric = { keyMin=40, keyMax=40, scoreMin=10000, scoreMax=10000, runsMin=10000,
    ageMax=120, sizeMin=40, sizeMax=40, killedMax=30, nextBoss=30, raidGroup=100000,
    tanksMin=40,healersMin=40,damageMin=40 }
local flags = { "scoreUpgrade", "roleFit", "requireTank", "requireHealer", "bloodlustFit",
    "battleResFit", "notDeclined", "experiencedParty",
    "friendsOnly", "eligibleOnly", "dungeonsNone", "raidsNone", "difficultyNormal","difficultyHeroic","difficultyMythic",
    "fresh","matchLockout","style1","style2","style3","style4","needsTank","needsHealer","needsDamage",
    "noLeavers","autoAcceptOnly","myRealm","myFaction" }

local function text(value, max)
    value = str(value)
    if value and #value <= max then return value:gsub("|", "") end
end

function Tools:CopyFilters(source)
    source = type(source) == "table" and source or {}
    local out = { dungeons={} }
    out.category=source.category=="raid" and "raid" or "mplus"
    for _,key in ipairs({"bossStates","excludedSpecs","languages","raids"}) do
        if type(source[key])=="table" then
            local dest,count={},0
            for k,v in pairs(source[key]) do
                if count<80 and ((key=="bossStates" and type(k)=="string" and #k<=180 and (v=="alive" or v=="killed"))
                    or (key=="raids" and type(k)=="number" and k>0 and k<100000 and v==true)
                    or (key=="excludedSpecs" and type(k)=="number" and k>0 and k<10000 and v==true)
                    or (key=="languages" and type(k)=="string" and #k<24 and type(v)=="boolean")) then
                    dest[k]=v; count=count+1
                end
            end
            out[key]=dest
        end
    end
    out.roleFit = source.roleFit ~= false
    for key, cap in pairs(numeric) do
        local value = tonumber(source[key])
        if value and value == value and value >= 0 and value <= cap then out[key] = value end
    end
    for _, key in ipairs(flags) do
        if type(source[key]) == "boolean" then out[key] = source[key] end
    end
    local count = 0
    for id, enabled in pairs(type(source.dungeons) == "table" and source.dungeons or {}) do
        if type(id) == "number" and id > 0 and id < 100000 and enabled == true and count < 32 then
            out.dungeons[id] = true; count = count + 1
        end
    end
    self:ClearRemovedFilters(out)
    return out
end

function Tools:Prune(db)
    local now = time()
    db.presets=nil; db.leaders=nil
    local history = {}
    for _, e in ipairs(type(db.history) == "table" and db.history or {}) do
        if type(e)=="table" and number(e.at) and e.at <= now and now-e.at < LIMIT.SEARCH_HISTORY_TTL
            and text(e.status,40) then
            history[#history+1]={at=e.at, started=number(e.started), status=text(e.status,40),
                leader=text(e.leader,100), dungeon=text(e.dungeon,180), score=number(e.score)}
        end
    end
    table.sort(history,function(a,b) return a.at>b.at end)
    while #history>LIMIT.SEARCH_HISTORY do table.remove(history) end
    db.history=history
end

function Tools:DB()
    if self.db then return self.db end
    if type(MythicBoostDB.groupTools) ~= "table" then MythicBoostDB.groupTools={} end
    self.db=MythicBoostDB.groupTools
    self:Prune(self.db)
    return self.db
end

-- Removed controls must not leave invisible constraints in saved filters.
-- Raid age/size/requirements still have controls in the raid sidebar.
function Tools:ClearRemovedFilters(f)
    f.sort="priority"; f.ascending=false
    f.scoreNear, f.favoritesOnly, f.hideMyClass = nil, nil, nil
    if f.category~="raid" then
        f.ageMax, f.sizeMin, f.sizeMax, f.friendsOnly, f.eligibleOnly = nil, nil, nil, nil, nil
    end
end

function Tools:Reject(match, f)
    self:ClearRemovedFilters(f)
    match.favorite=nil
    if match.playstyle and f["style"..match.playstyle]==false then return L("не подходит стиль группы") end
    if f.autoAcceptOnly and match.autoAccept==false then return L("нет автоматического приёма") end
    if f.noLeavers and match.hasLeaver==true then return L("в группе есть покинувший подземелье") end
    if f.myRealm and match.leaderName and GetNormalizedRealmName then
        local realm=match.leaderName:match("%-(.+)$")
        if realm and realm:gsub("[%s%-]",""):lower()~=GetNormalizedRealmName():gsub("[%s%-]",""):lower() then return L("другой сервер") end
    end
    if f.myFaction and match.leaderFaction and UnitFactionGroup then
        local faction=UnitFactionGroup("player"); local own=({Horde=0,Alliance=1})[faction]
        if own and own~=match.leaderFaction then return L("другая фракция") end
    end
    for role,key in pairs({TANK="tanksMin",HEALER="healersMin",DAMAGER="damageMin"}) do
        local min=tonumber(f[key]); local count=match.roleCounts and match.roleCounts[role]
        if min and count and count<min then return L("не подходит состав группы") end
    end
    if f.excludedSpecs then
        local specs=self:Specs()
        for _,member in ipairs(match.memberInfo or {}) do
            local key=(member.classFilename or "")..":"..(member.specName or "")
            local id=specs.byName[key]
            if id and f.excludedSpecs[id] then return L("не подходит специализация") end
        end
    end
    if f.friendsOnly and match.friends~=nil and match.friends==0 then return L("нет друзей в группе") end
    if tonumber(f.ageMax) and tonumber(f.ageMax)>0 and match.age and match.age>tonumber(f.ageMax)*60 then return L("объявление слишком старое") end
    if tonumber(f.sizeMin) and match.members>0 and match.members<tonumber(f.sizeMin) then return L("мало участников") end
    if tonumber(f.sizeMax) and tonumber(f.sizeMax)>0 and match.members>tonumber(f.sizeMax) then return L("много участников") end
    if f.eligibleOnly then
        local overall=GetAverageItemLevel and number(GetAverageItemLevel())
        if overall and match.requiredItemLevel and overall<match.requiredItemLevel then return L("не хватает уровня предметов") end
        local mine=C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore and number(C_ChallengeMode.GetOverallDungeonScore())
        if mine and match.requiredScore and mine<match.requiredScore then return L("не хватает рейтинга для заявки") end
    end
end

function Tools:Specs()
    if self.specs then return self.specs end
    local out={byName={}}
    if not GetNumClasses or not GetNumSpecializationsForClassID or not GetSpecializationInfoForClassID then return out end
    for classID=1,GetNumClasses() do
        local _,file=GetClassInfo(classID)
        for i=1,(GetNumSpecializationsForClassID(classID) or 0) do
            local id,name,_,icon,role=GetSpecializationInfoForClassID(classID,i)
            if number(id) and str(name) and str(file) then
                out[#out+1]={id=id,name=name,icon=icon,role=role,class=file}
                out.byName[file..":"..name]=id
            end
        end
    end
    if #out>0 then self.specs=out end
    return out
end

function Tools:Sort(matches)
    table.sort(matches,function(a,b)
        local av,bv=a.applicationPriority or 0,b.applicationPriority or 0
        if av~=bv then return av>bv end
        local as,bs=a.partyScoreAverage or a.score or 0,b.partyScoreAverage or b.score or 0
        if as~=bs then return as>bs end
        return (a.searchResultID or 0)<(b.searchResultID or 0)
    end)
end

function Tools:OrderResults(matches,excluded)
    local candidates={}
    for _,m in ipairs(matches) do candidates[#candidates+1]=m end
    for _,m in ipairs(excluded) do candidates[#candidates+1]=m end
    local active=self:ActiveMatches(candidates)
    self:Sort(active); self:Sort(matches)
    local seen,ordered,remaining={},{},{}
    for _,m in ipairs(active) do seen[m.searchResultID]=true; ordered[#ordered+1]=m end
    for _,m in ipairs(matches) do if not seen[m.searchResultID] then ordered[#ordered+1]=m end end
    for _,m in ipairs(excluded) do if not seen[m.searchResultID] then remaining[#remaining+1]=m end end
    return ordered,remaining
end

function Tools:Track(match)
    if type(match)~="table" or not number(match.searchResultID) then return end
    local id=match.searchResultID
    if not self.tracked[id] then
        self.order[#self.order+1]=id
        if #self.order>LIMIT.SEARCH_CACHE then self.tracked[table.remove(self.order,1)]=nil end
    end
    local existing=self.tracked[id]
    if existing and existing.leader~=text(match.leaderName,100) then existing=nil end
    self.tracked[id]={leader=text(match.leaderName,100),dungeon=text(match.dungeon,180),score=number(match.score),entry=existing and existing.entry}
end

local statuses={applied=true,invited=true,inviteaccepted=true,invitedeclined=true,declined=true,
    declined_full=true,declined_delisted=true,cancelled=true,timedout=true,failed=true}
function Tools:ApplicationEvent(id,status)
    id=number(id); status=str(status)
    if not id or not statuses[status] then return end
    local tracked=self.tracked[id]
    if not tracked then
        local ok,info=pcall(C_LFGList.GetSearchResultInfo,id)
        info=ok and JP.SafeTable(info)
        self:Track({searchResultID=id,leaderName=info and str(info.leaderName),dungeon=L("Группа"),score=info and number(info.leaderOverallDungeonScore)})
        tracked=self.tracked[id]
    end
    local db=self:DB()
    local entry=tracked.entry
    if entry and entry.status==status then return end
    if not entry or (status=="applied" and entry.status~="applied") then
        entry={started=time(),leader=tracked.leader,dungeon=tracked.dungeon,score=tracked.score}
        tracked.entry=entry
    else
        for i=#db.history,1,-1 do if db.history[i]==entry then table.remove(db.history,i) end end
    end
    entry.status=status; entry.at=time()
    table.insert(db.history,1,entry)
    while #db.history>LIMIT.SEARCH_HISTORY do table.remove(db.history) end
end

function Tools:ActiveMatches(matches)
    local byID={}
    for _,m in ipairs(matches) do byID[m.searchResultID]=m end
    local out={}
    for _,id in ipairs(JP.API.GetApplicationIDs() or {}) do
        if JP.API.GetApplicationState(id).active then
            local m=byID[id]
            if m then
                local copy={}; for k,v in pairs(m) do copy[k]=v end
                m=copy; m.rejected=nil; m.actionable=true
            end
            if not m then
                local old=self.tracked[id] or {}
                m={searchResultID=id,dungeon=old.dungeon or L("Заявка вне текущего поиска"),leaderName=old.leader,
                    score=old.score or 0, members=0,memberInfo={},actionable=true}
            end
            out[#out+1]=m
        end
    end
    return out
end
