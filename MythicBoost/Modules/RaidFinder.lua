local _, JP = ...
local L,UI=JP.L,JP.UI
local R={groups={},bosses={},bossRetryAt={},bossDetails={}}
JP.RaidFinder=R
local num,str,plain=JP.SafeNumber,JP.SafeString,JP.SafeTable
local DIFFICULTIES={{14,"difficultyNormal"},{15,"difficultyHeroic"},{16,"difficultyMythic"}}
local BOSS_ROW_HEIGHT,BOSS_ROW_STEP=32,38
local BOSS_STYLES={
    alive={fill={.045,.20,.13,1},edge={.28,.92,.56,1},badge={.06,.36,.21,1}},
    killed={fill={.25,.075,.085,1},edge={.98,.43,.43,1},badge={.48,.12,.15,1}},
}
local function BossButtonVisual(b)
    local style=BOSS_STYLES[b.state]
    b:SetBackdropColor(UI.Unpack(style and style.fill or UI.colors.field))
    b:SetBackdropBorderColor(UI.Unpack(style and style.edge or (b.hovered and UI.colors.accent or UI.colors.hudEdge)))
    b.marker:SetShown(style~=nil)
    if style then b.marker:SetColorTexture(UI.Unpack(style.edge)) end
    b.badge:SetColorTexture(UI.Unpack(style and style.badge or UI.colors.raised))
    b.stateLabel:SetTextColor(UI.Unpack(style and UI.colors.text or UI.colors.muted))
    b.label:SetTextColor(UI.Unpack(style and UI.colors.text or UI.colors.muted))
    b.hover:SetShown(b.hovered==true)
end

local function Read(fn,...)
    if type(fn)~="function" then return end
    local ok,value=pcall(fn,...)
    if ok and not JP.IsSecret(value) then return value end
end

function R:Discover()
    if #self.groups>0 then return self.groups end
    local flags=Enum and Enum.LFGListFilter or {}
    local base=flags.PvE or 4
    local filters=bit and bit.bor(base,flags.Recommended or 1) or 5
    local ids=plain(Read(C_LFGList.GetAvailableActivityGroups,3,filters)) or {}
    if #ids==0 then filters=base; ids=plain(Read(C_LFGList.GetAvailableActivityGroups,3,filters)) or {} end
    for _,id in ipairs(ids) do
        if num(id) then
            local group={id=id,name=str(Read(C_LFGList.GetActivityGroupInfo,id)),activities={}}
            for _,activityID in ipairs(plain(Read(C_LFGList.GetAvailableActivities,3,id,filters)) or {}) do
                local info=plain(Read(C_LFGList.GetActivityInfoTable,activityID))
                if info and JP.SafeOptionalBoolean(info.isCurrentRaidActivity)==true then
                    group.activities[#group.activities+1]=activityID
                    group.mapID=num(info.mapID)
                end
            end
            if group.name and #group.activities>0 then self.groups[#self.groups+1]=group end
        end
    end
    return self.groups
end

function R:Selection(f)
    if type(f.raids)~="table" then
        f.raids={}
        if num(f.raidGroup) then f.raids[f.raidGroup]=true end
    end
    f.raidGroup=nil
    return f.raids
end

function R:IsSelected(f,id)
    local selected=self:Selection(f)
    if next(selected)==nil then return not f.raidsNone end
    return id and selected[id]==true or false
end

function R:Toggle(w,id)
    local f=w.groupFilters
    local selected=self:Selection(f)
    if not id then
        local all=#self:Discover()>0
        for _,g in ipairs(self.groups) do if not self:IsSelected(f,g.id) then all=false end end
        wipe(selected); f.raidsNone=all or nil
    elseif next(selected)==nil and not f.raidsNone then
        for _,g in ipairs(self:Discover()) do if g.id~=id then selected[g.id]=true end end
        f.raidsNone=next(selected)==nil or nil
    elseif selected[id] then
        selected[id]=nil; f.raidsNone=next(selected)==nil or nil
    else
        selected[id]=true; f.raidsNone=nil
        local all=true
        for _,g in ipairs(self:Discover()) do if not selected[g.id] then all=false end end
        if all then wipe(selected) end
    end
    f.bossStates={}; w.offset=0
    self:Refresh(w); w:Refresh()
end

local function GroupKey(group)
    return group and ((num(group.mapID) and group.mapID>0 and group.mapID) or group.name)
end

function R:Journal(group)
    local key=GroupKey(group)
    if not key then return end
    self.journals=self.journals or {}
    self.journalRetryAt=self.journalRetryAt or {}
    if self.journals[key] then return self.journals[key] end
    local now=GetTime()
    if self.journalRetryAt[key] and now<self.journalRetryAt[key] then return end
    self.journalRetryAt[key]=now+5
    local journal=num(group.mapID) and group.mapID>0 and C_EncounterJournal and num(Read(C_EncounterJournal.GetInstanceForGameMap,group.mapID))
    if not journal and EJ_GetNumTiers and EJ_GetInstanceByIndex then
        local tier=Read(EJ_GetCurrentTier)
        pcall(function()
            for t=(num(Read(EJ_GetNumTiers)) or 0),1,-1 do
                EJ_SelectTier(t)
                for i=1,40 do
                    local id,name=EJ_GetInstanceByIndex(i,true)
                    if not num(id) then break end
                    if str(name)==group.name then journal=id; return end
                end
            end
        end)
        if num(tier) then pcall(EJ_SelectTier,tier) end
    end
    if journal then self.journals[key]=journal end
    return journal
end

function R:Artwork(group)
    if group.icon then return group.icon,group.art end
    local journal=self:Journal(group)
    if not journal or not EJ_GetInstanceInfo then return end
    local ok,_,_,background,_,_,buttonImage=pcall(EJ_GetInstanceInfo,journal)
    if ok then
        group.icon=num(buttonImage) or str(buttonImage)
        group.art=num(background) or str(background)
    end
    return group.icon,group.art
end

function R:Bosses(group)
    local key=GroupKey(group)
    if not key then return {} end
    if self.bosses[key] then return self.bosses[key] end
    local now=GetTime()
    if self.bossRetryAt[key] and now<self.bossRetryAt[key] then return {} end
    self.bossRetryAt[key]=now+5
    local journal=self:Journal(group)
    if not journal or not EJ_GetEncounterInfoByIndex then return {} end
    local names,details={},{}
    local oldDifficulty=Read(EJ_GetDifficulty)
    local oldInstance=EncounterJournal and num(EncounterJournal.instanceID)
    if EJ_GetInstanceInfo and C_EncounterJournal then
        local ok,_,_,_,_,_,_,_,_,_,map=pcall(EJ_GetInstanceInfo)
        local current=ok and num(map) and num(Read(C_EncounterJournal.GetInstanceForGameMap,map))
        oldInstance=current or oldInstance
    end
    local ok=pcall(function()
        if EJ_SelectInstance then EJ_SelectInstance(journal) end
        if EJ_SetDifficulty then EJ_SetDifficulty(14) end
        for i=1,30 do
            local name,_,encounterID=EJ_GetEncounterInfoByIndex(i,journal)
            name=str(name)
            if not name then break end
            names[#names+1]=name; details[name]={id=num(encounterID)}
        end
    end)
    if oldInstance and EJ_SelectInstance then pcall(EJ_SelectInstance,oldInstance) end
    if num(oldDifficulty) and EJ_SetDifficulty then pcall(EJ_SetDifficulty,oldDifficulty) end
    if not ok then return {} end
    if #names>0 then self.bosses[key]=names; self.bossDetails[key]=details end
    return names
end

function R:NextBoss(m)
    if m.killedCount==nil then return end
    local group={mapID=m.mapID,name=m.raidName or m.dungeon}
    local names=self:Bosses(group)
    local details=self.bossDetails[GroupKey(group)]
    if not details then return end
    -- A localized-name mismatch cannot safely identify the remaining boss.
    for name in pairs(m.killedBosses or {}) do if not details[name] then return end end
    for index,name in ipairs(names) do
        if not (m.killedBosses or {})[name] then
            local detail=details[name]
            if detail and detail.id and not detail.icon and EJ_GetCreatureInfo
                and (not detail.retryAt or GetTime()>=detail.retryAt) then
                detail.retryAt=GetTime()+5
                local ok,_,_,_,_,icon=pcall(EJ_GetCreatureInfo,1,detail.id)
                detail.icon=ok and num(icon) and icon>0 and icon or nil
            end
            return name,detail and detail.icon or nil,index
        end
    end
end

function R:Lockout(mapID,difficulty)
    if not GetNumSavedInstances or not GetSavedInstanceInfo then return end
    for i=1,(num(Read(GetNumSavedInstances)) or 0) do
        local _,_,_,diff,locked,extended,_,raid,_,_,total,_,_,instanceID=GetSavedInstanceInfo(i)
        if num(instanceID)==mapID and num(diff)==difficulty and JP.SafeBoolean(raid)
            and (JP.SafeBoolean(locked) or JP.SafeBoolean(extended)) then
            local kills={}
            for j=1,(num(total) or 0) do
                local name,_,killed=GetSavedInstanceEncounterInfo(i,j)
                name=str(name)
                if name and JP.SafeBoolean(killed) then kills[name]=true end
            end
            return kills
        end
    end
end

function R:ServerFilter(f)
    local activities={}
    for id,on in pairs(self:Selection(f)) do if on then activities[#activities+1]=id end end
    table.sort(activities)
    return {activities=activities,minimumRating=tonumber(f.scoreMin) or 0,
        needsTank=f.needsTank==true,needsHealer=f.needsHealer==true,needsDamage=f.needsDamage==true,
        needsMyClass=false,hasTank=f.requireTank==true,hasHealer=f.requireHealer==true,
        difficultyNormal=f.difficultyNormal==true,difficultyHeroic=f.difficultyHeroic==true,
        difficultyMythic=f.difficultyMythic==true,difficultyMythicPlus=false,
        generalPlaystyle1=f.style1~=false,generalPlaystyle2=f.style2~=false,
        generalPlaystyle3=f.style3~=false,generalPlaystyle4=f.style4~=false}
end

local function Reject(m,reason,actionable)
    m.rejected=true; m.rejectionReason=reason
    if actionable==false then m.actionable=false end
    return nil,reason,m
end

function R.BuildMatch(id,f,runtime,party)
    local info=plain(Read(C_LFGList.GetSearchResultInfo,id))
    if not info then return end
    local activityIDs=plain(info.activityIDs)
    local activityID=activityIDs and num(activityIDs[1]) or num(info.activityID)
    local a=activityID and plain(Read(C_LFGList.GetActivityInfoTable,activityID))
    if not a or num(a.categoryID)~=3 or JP.SafeOptionalBoolean(a.isCurrentRaidActivity)~=true then return end
    local counts={TANK=0,HEALER=0,DAMAGER=0}
    local members={}; local lust,res,leaver=false,false,false
    local total=num(info.numMembers) or 0
    for i=1,math.min(40,total) do
        local member=plain(Read(C_LFGList.GetSearchResultPlayerInfo,id,i))
        if member then
            local class,role=str(member.classFilename),str(member.assignedRole)
            members[#members+1]={classFilename=class,assignedRole=role,name=str(member.name),specName=str(member.specName),isLeader=i==1}
            if counts[role] then counts[role]=counts[role]+1 end
            if JP.SafeBoolean(member.isLeaver) then leaver=true end
            if class=="SHAMAN" or class=="MAGE" or class=="HUNTER" or class=="EVOKER" then lust=true end
            if class=="DRUID" or class=="DEATHKNIGHT" or class=="WARLOCK" or class=="PALADIN" then res=true end
        end
    end
    local kills=plain(Read(C_LFGList.GetSearchResultEncounterInfo,id))
    local killed,count={},0
    if kills then
        for _,name in ipairs(kills) do
            name=str(name)
            if name then killed[name]=true; count=count+1 else kills=nil; break end
        end
    end
    local score=num(info.leaderOverallDungeonScore) or 0
    local bnet,char=num(info.numBNetFriends),num(info.numCharFriends)
    local friends=bnet and char and bnet+char or (bnet or char)
    local m={raid=true,searchResultID=id,activityID=activityID,mapID=num(a.mapID),
        raidName=str(Read(C_LFGList.GetActivityGroupInfo,num(a.groupFinderActivityGroupID))),
        dungeon=str(a.fullName) or str(a.shortName) or L("Рейд"),title=str(info.name),comment=str(info.comment),
        leaderName=str(info.leaderName),score=score,partyScoreAverage=score,bestLevel=0,
        members=total,memberInfo=members,roleCounts=counts,hasTank=counts.TANK>0,hasHealer=counts.HEALER>0,
        hasBloodlust=lust,hasBattleRes=res,age=num(info.age),friends=friends,
        requiredItemLevel=num(info.requiredItemLevel),requiredScore=num(info.requiredDungeonScore),
        difficultyID=num(a.difficultyID),killedBosses=killed,killedCount=kills and count or nil,
        playstyle=num(info.generalPlaystyle),leaderFaction=num(info.leaderFactionGroup),
        autoAccept=JP.SafeOptionalBoolean(info.autoAccept),hasLeaver=leaver,actionable=true}
    if JP.SafeBoolean(info.isDelisted) then return Reject(m,L("Группа закрыта"),false) end
    local capacity=num(a.maxNumPlayers) or num(a.maxPlayers) or 40
    if total>=capacity then return Reject(m,L("Группа полная"),false) end
    if not R:IsSelected(f,num(a.groupFinderActivityGroupID)) then return Reject(m,L("другое подземелье")) end
    for _,diff in ipairs(DIFFICULTIES) do
        if m.difficultyID==diff[1] and f[diff[2]]~=true then return Reject(m,L("другая сложность")) end
    end
    if tonumber(f.nextBoss) then
        local _,_,index=R:NextBoss(m)
        if not index then return Reject(m,L("Неизвестен следующий босс")) end
        if index~=tonumber(f.nextBoss) then return Reject(m,L("другой следующий босс")) end
    end
    if f.fresh and m.killedCount and m.killedCount>0 then return Reject(m,L("рейд уже начат")) end
    local max=tonumber(f.killedMax)
    if max and m.killedCount and m.killedCount>max then return Reject(m,L("слишком много убитых боссов")) end
    if kills then
        for name,state in pairs(f.bossStates or {}) do
            if (state=="alive" and killed[name]) or (state=="killed" and not killed[name]) then return Reject(m,L("не подходит прогресс боссов")) end
        end
        if f.matchLockout then
            local own=R:Lockout(m.mapID,m.difficultyID)
            if own then
                for name in pairs(own) do if not killed[name] then return Reject(m,L("не совпадает сохранение")) end end
                for name in pairs(killed) do if not own[name] then return Reject(m,L("не совпадает сохранение")) end end
            end
        end
    end
    if f.roleFit~=false and total+(GetNumGroupMembers and math.max(1,GetNumGroupMembers()) or 1)>capacity then return Reject(m,L("мало мест для пати")) end
    if f.requireTank and not m.hasTank then return Reject(m,L("нет танка")) end
    if f.requireHealer and not m.hasHealer then return Reject(m,L("нет лекаря")) end
    if f.bloodlustFit and not lust then return Reject(m,L("нет Bloodlust")) end
    if f.battleResFit and not res then return Reject(m,L("нет боевого воскрешения")) end
    if tonumber(f.scoreMin) and score<tonumber(f.scoreMin) then return Reject(m,L("рейтинг ниже фильтра")) end
    if tonumber(f.scoreMax) and score>tonumber(f.scoreMax) then return Reject(m,L("рейтинг выше фильтра")) end
    local reason=JP.GroupTools:Reject(m,f)
    if reason then return Reject(m,reason) end
    if f.notDeclined then
        local state=JP.API.GetApplicationState(id)
        if state.status and state.status:find("declined",1,true) then return Reject(m,L("Отказ"),false) end
    end
    return m
end

function R:Switch(w,raid)
    if InCombatLockdown() then return end
    JP.GroupTools:EndEdit()
    if JP.GroupSearchUI.searchPending then return end
    JP.GroupTools:ClearQuery(w)
    if raid then
        w.mplusFilters=w.groupFilters; w.mplusFields=w.filterFields
        MythicBoostDB.raidFilters=MythicBoostDB.raidFilters or {category="raid",difficultyHeroic=true,eligibleOnly=true,notDeclined=true}
        w.groupFilters=MythicBoostDB.raidFilters; w.filterFields=self.fields
    else
        w.groupFilters=w.mplusFilters or MythicBoostDB.groupFilters; w.filterFields=w.mplusFields or {}
    end
    JP.GroupTools:ClearRemovedFilters(w.groupFilters)
    w.offset=0
    JP.GroupSearchUI.completedBatch=nil; JP.GroupSearchUI.resultsExactLevel=nil; w.matches={}
    if RequestRaidInfo then RequestRaidInfo() end
    if C_LFGList.RequestAvailableActivities then C_LFGList.RequestAvailableActivities() end
    self:Refresh(w); w:Refresh()
end

function R:Build(w,body)
    self.fields={}
    local side=UI.Panel(body,UI.colors.panel,UI.colors.hudEdge)
    side:SetPoint("TOPLEFT",10,-10); side:SetPoint("BOTTOMLEFT",10,10); side:SetWidth(238); side:Hide(); w.raidSide=side
    local heading=UI.Text(side,"GameFontNormalLarge",L("ФИЛЬТРЫ РЕЙДА"),UI.colors.accent)
    heading:SetPoint("TOPLEFT",14,-14)
    self.checks={}
    local function Check(key,label,y)
        local c=UI.CheckBox(side,label,false,function(on) w.groupFilters[key]=on; w:Refresh() end)
        c:SetPoint("TOPLEFT",14,y); c:SetWidth(210); self.checks[key]=c
    end
    Check("difficultyNormal",L("Обычный"),-48); Check("difficultyHeroic",L("Героический"),-74); Check("difficultyMythic",L("Эпохальный"),-100)
    local function Field(key,label,y)
        local t=UI.Text(side,"GameFontHighlightSmall",label,UI.colors.muted); t:SetPoint("TOPLEFT",14,y-5)
        local e,b=UI.NumberBox(side,60,22); b:SetPoint("TOPRIGHT",-14,y)
        e:SetScript("OnTextChanged",function(field,user) if user then w.groupFilters[key]=field:GetText(); JP:RequestRefresh(.2) end end)
        self.fields[key]=e
    end
    Field("scoreMin",L("Рейтинг от"),-140); Field("scoreMax",L("Рейтинг до"),-168)
    Field("sizeMin",L("Участников от"),-206); Field("sizeMax",L("Участников до"),-234)
    Field("ageMax",L("Возраст до, мин"),-272); Field("killedMax",L("Убито боссов до"),-300)
    Field("nextBoss",L("Следующий босс №"),-328)
    Check("fresh",L("Свежий рейд"),-370); Check("matchLockout",L("Моё сохранение"),-396)
    Check("eligibleOnly",L("Прохожу требования ilvl / RIO"),-432)
    Check("friendsOnly",L("С друзьями в группе"),-458)
    Check("notDeclined",L("Скрывать отказавших"),-484)
    local edit=UI.Button(side,L("Состав / стиль"),210,26)
    edit:SetPoint("BOTTOMLEFT",14,14); edit:SetScript("OnClick",function() JP.GroupTools:OpenPanel(w,"composition") end)
    local cards,heading,all,summary=UI.ActivityCardsPanel(body,L("Рейды"))
    cards:SetHeight(72); cards:Hide(); w.raidCards=cards
    cards:HookScript("OnHide",function()
        if self.metadataTimer then self.metadataTimer:Cancel(); self.metadataTimer=nil end
        self.pendingKey=nil; self.metadataAttempts=0
    end)
    self.groupButton=all; self.groupSummary=summary
    self.groupButton:SetScript("OnClick",function()
        self:Toggle(w)
    end)
    self.groupChoices={}
    for i=1,8 do
        local b=UI.ActivityCard(cards); b:Hide(); self.groupChoices[i]=b
        b.label=UI.Text(b,"GameFontNormal","",UI.colors.text)
        b.label:SetPoint("LEFT",80,0); b.label:SetPoint("RIGHT",-12,0); b.label:SetJustifyH("LEFT"); b.label:SetWordWrap(true)
        b.label:SetShadowColor(0,0,0,1); b.label:SetShadowOffset(1,-1)
        b.selectedLine=b:CreateTexture(nil,"OVERLAY"); b.selectedLine:SetColorTexture(UI.Unpack(UI.colors.accent))
        b.selectedLine:SetHeight(3); b.selectedLine:SetPoint("BOTTOMLEFT",1,1); b.selectedLine:SetPoint("BOTTOMRIGHT",-1,1)
        b:SetScript("OnEnter",function() b:SetBackdropBorderColor(UI.Unpack(UI.colors.accent)) end)
        b:SetScript("OnLeave",function() b:SetBackdropBorderColor(UI.Unpack(b.selected and UI.colors.accent or UI.colors.hudEdge)) end)
        b:SetScript("OnClick",function()
            self:Toggle(w,b.groupID)
        end)
    end
    self.hint=UI.Text(cards,"GameFontHighlightSmall","",UI.colors.muted)
    self.hint:SetPoint("TOPLEFT",12,-46)
    self.bossButtons={}
    for i=1,12 do
        local b=CreateFrame("Button",nil,cards,"BackdropTemplate"); b:SetSize(280,BOSS_ROW_HEIGHT)
        UI.Backdrop(b,UI.colors.field,UI.colors.hudEdge)
        b.marker=b:CreateTexture(nil,"ARTWORK"); b.marker:SetWidth(4)
        b.marker:SetPoint("TOPLEFT",1,-1); b.marker:SetPoint("BOTTOMLEFT",1,1)
        b.badge=b:CreateTexture(nil,"ARTWORK"); b.badge:SetWidth(84)
        b.badge:SetPoint("TOPRIGHT",-5,-5); b.badge:SetPoint("BOTTOMRIGHT",-5,5)
        b.stateLabel=UI.Text(b,"GameFontHighlightSmall","")
        b.stateLabel:SetPoint("CENTER",b.badge,"CENTER")
        b.label=UI.Text(b,"GameFontHighlightSmall","")
        b.label:SetPoint("LEFT",14,0); b.label:SetPoint("RIGHT",-100,0); b.label:SetJustifyH("LEFT"); b.label:SetWordWrap(false)
        b.hover=b:CreateTexture(nil,"OVERLAY"); b.hover:SetAllPoints(); b.hover:SetColorTexture(1,1,1,.06); b.hover:Hide()
        b:SetScript("OnEnter",function() b.hovered=true; BossButtonVisual(b) end)
        b:SetScript("OnLeave",function() b.hovered=false; BossButtonVisual(b) end)
        b:SetScript("OnHide",function() b.hovered=false; b.hover:Hide() end)
        b:SetScript("OnClick",function()
            if not b.boss then return end
            local states=w.groupFilters.bossStates or {}; w.groupFilters.bossStates=states
            states[b.boss]=states[b.boss]==nil and "alive" or (states[b.boss]=="alive" and "killed" or nil)
            self:Refresh(w); w:Refresh()
        end); b:Hide(); self.bossButtons[i]=b
    end
end

function R:Refresh(w)
    local raid=w.groupFilters.category=="raid"
    w.raidSide:SetShown(raid); w.raidCards:SetShown(raid)
    w.mplusSide:SetShown(not raid); w.cardsPanel:SetShown(not raid)
    w.keyHeader:SetText(raid and L("БОССЫ") or L("КЛЮЧ"))
    w.groupHeader:SetText(raid and L("ГРУППА / РЕЙД") or L("ГРУППА / ПОДЗЕМЕЛЬЕ"))
    if w.scoreHeader then w.scoreHeader:SetText(raid and L("RIO ЛИДЕРА") or L("СРЕДНИЙ RIO")) end
    if not raid then return end
    for key,c in pairs(self.checks) do c:SetChecked(w.groupFilters[key]==true) end
    for key,e in pairs(self.fields) do e:SetText(tostring(w.groupFilters[key] or "")) end
    local selected,count=nil,0
    local groups=self:Discover()
    for _,g in ipairs(groups) do if self:IsSelected(w.groupFilters,g.id) then selected=g; count=count+1 end end
    if count~=1 then selected=nil end
    local gridHeight=UI.LayoutActivityCards(w.raidCards,self.groupChoices,math.min(8,#groups))
    self.groupSummary:SetText(count.." / "..#groups)
    UI.Backdrop(self.groupButton,UI.colors.field,count==#groups and UI.colors.accent or UI.colors.hudEdge)
    for i,b in ipairs(self.groupChoices) do
        local group=groups[i]; b:SetShown(group~=nil)
        if group then
            b.groupID=group.id; b.label:SetText(group.name)
            local icon,art=self:Artwork(group)
            b.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_Map_01"); b.art:SetTexture(art)
            b.selected=self:IsSelected(w.groupFilters,group.id); b.selectedLine:SetShown(b.selected)
            b.icon:SetDesaturated(not b.selected); b.icon:SetAlpha(b.selected and 1 or .55)
            b.art:SetDesaturated(not b.selected); b.art:SetAlpha(b.selected and .46 or .24)
            UI.Backdrop(b,UI.colors.raised,b.selected and UI.colors.accent or UI.colors.hudEdge)
        end
    end
    local bosses=self:Bosses(selected)
    local pendingKey=selected and #bosses==0 and GroupKey(selected)
    if pendingKey~=self.pendingKey then
        if self.metadataTimer then self.metadataTimer:Cancel(); self.metadataTimer=nil end
        self.pendingKey=pendingKey; self.metadataAttempts=0
    end
    if pendingKey and not self.metadataTimer and (self.metadataAttempts or 0)<3 and C_Timer.NewTimer then
        self.metadataAttempts=(self.metadataAttempts or 0)+1
        self.metadataTimer=C_Timer.NewTimer(5.1,function()
            self.metadataTimer=nil
            if w.raidCards:IsShown() and w.groupFilters.category=="raid" then w:Refresh() end
        end)
    end
    local hintY=gridHeight
    self.hint:ClearAllPoints(); self.hint:SetPoint("TOPLEFT",12,-hintY)
    self.hint:SetText(#groups==0 and L("Данные рейдов загружаются") or (selected and (#bosses>0 and L("Боссы: любой / жив / убит") or L("Нет данных боссов в атласе")) or L("Оставь один рейд, чтобы настроить боссов")))
    w.raidHeaderHeight=hintY+24+(#bosses>0 and math.ceil(math.min(12,#bosses)/2)*BOSS_ROW_STEP+4 or 0)
    w.raidCards:SetHeight(w.raidHeaderHeight)
    local column=math.max(200,(w.raidCards:GetWidth()-36)/2)
    for i,b in ipairs(self.bossButtons) do
        b:ClearAllPoints(); b:SetWidth(column)
        b:SetPoint("TOPLEFT",12+((i-1)%2)*(column+12),-hintY-22-math.floor((i-1)/2)*BOSS_ROW_STEP)
        b.boss=bosses[i]; b:SetShown(b.boss~=nil)
        if b.boss then
            b.state=(w.groupFilters.bossStates or {})[b.boss]
            b.label:SetText(i..". "..b.boss)
            b.stateLabel:SetText(b.state=="alive" and L("Жив") or (b.state=="killed" and L("Убит") or L("Любой")))
            BossButtonVisual(b)
        end
    end
end

function R:RenderRow(row,m)
    row.partyIcons:Hide()
    if row.key then row.key:Hide() end
    if not row.raidProgress then
        row.raidProgress=UI.Text(row.keyBox,"GameFontNormalLarge","",UI.colors.accent)
        row.raidProgress:SetPoint("CENTER")
        local font,size=row.raidProgress:GetFont()
        if font then row.raidProgress:SetFont(font,size,"THICKOUTLINE") end
        row.raidProgress:SetShadowColor(0,0,0,1); row.raidProgress:SetShadowOffset(1,-1)
    end
    local bosses=self:Bosses({mapID=m.mapID,name=m.raidName or m.dungeon})
    local progress=m.killedCount and (tostring(m.killedCount)..(#bosses>0 and ("/"..#bosses) or "")) or "?"
    row.raidProgress:SetText(progress); row.raidProgress:Show()
    local nextBoss,portrait=self:NextBoss(m)
    if portrait then
        row.keyIcon:SetTexture(portrait); row.keyIcon:SetTexCoord(0,1,0,1)
        row.keyIcon:SetDesaturated(false); row.keyIcon:SetAlpha(1)
    else row.keyIcon:SetAlpha(0) end
    UI.Backdrop(row.keyBox,UI.colors.field,UI.colors.hudEdge)
    UI.Backdrop(row,row.baseColor,UI.colors.hudEdge)
    local roles=m.roleCounts or {}
    row.roles:SetText(UI.RoleIcon("TANK",13).." "..(roles.TANK or 0).." "..UI.RoleIcon("HEALER",13).." "..(roles.HEALER or 0).." "..UI.RoleIcon("DAMAGER",13).." "..(roles.DAMAGER or 0))
    row.dungeon:SetText(m.title or m.dungeon)
    row.detail:SetText((m.rejected and (m.rejectionReason.." - ") or "")..m.dungeon.."  "..(m.killedCount and (L("Убито: %d")):format(m.killedCount) or L("Прогресс неизвестен")))
end

function R:Tooltip(row)
    local m=row.match
    GameTooltip:SetOwner(row,"ANCHOR_CURSOR")
    GameTooltip:SetClampedToScreen(true)
    GameTooltip:SetText(m.title or m.dungeon)
    GameTooltip:AddLine(m.dungeon,.6,.7,.8)
    local nextBoss=self:NextBoss(m)
    if nextBoss then GameTooltip:AddLine((L("Следующий по атласу: %s")):format(nextBoss),.3,.8,1,true) end
    if m.comment then GameTooltip:AddLine(m.comment,1,1,1,true) end
    if m.killedCount then
        GameTooltip:AddLine((L("Убито: %d")):format(m.killedCount),.9,.75,.4)
        for name in pairs(m.killedBosses) do GameTooltip:AddLine("x "..name,.6,.6,.6) end
    else GameTooltip:AddLine(L("Прогресс неизвестен"),.6,.6,.6) end
    GameTooltip:Show()
end
