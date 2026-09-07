"""Owned dungeon HUD: executable engine-sink, lifecycle and secret-value fixtures.

Mocks cannot certify live WoW combat/taint. They fail on protected mutations,
forbidden discovery, opaque arithmetic and frame allocation during updates.
"""
from lupa import LuaRuntime
from TestHudPolish import WIDGETS, source, load


FIXTURE = r'''
local methods=getmetatable(UIParent).__index
function methods:RegisterUnitEvent(e,...) self.events[e]={...} end
function methods:UnregisterAllEvents() wipe(self.events) end
function methods:CreateFontString() return NewWidget(self) end
function methods:GetStringHeight() return 14 end
function methods:SetMaxLines(v) self.maxLines=v end
function methods:SetMouseClickEnabled(v) self.mouseClicks=v end
function methods:SetMouseMotionEnabled(v) self.mouseMotion=v end
function methods:SetParent(p) assert(not combat, 'parent mutation in combat'); self.parent=p end
function methods:SetTimerDuration(d,_,direction) self.timer=d; self.direction=direction end
function methods:SetCooldownFromDurationObject(d) self.timer=d end
function methods:Clear() self.timer=nil end
function methods:SetDrawEdge() end
function methods:SetHighlightTexture(texture) self.highlight=texture end
function methods:SetHideCountdownNumbers() end
function methods:SetAlpha(v) self.alpha=v end -- native secret-capable sink
function methods:SetAlphaFromBoolean(v,a,b) self.alpha=issecretvalue(v) and v or (v and a or b) end
function methods:SetFormattedText(fmt,...)
    local values={...}; self.formatted=values
    for _,v in ipairs(values) do if issecretvalue(v) then self.text=v; return end end
    self.text=string.format(fmt,...)
end
function methods:StartMoving() assert(not combat); self.moving=true end
function methods:StopMovingOrSizing() assert(not combat); self.moving=false end
local create=CreateFrame
function CreateFrame(kind,name,parent,template)
    local f=create(kind,name,parent); f.kind=kind; f.template=template
    f.protected=template and template:find('Secure',1,true)
    assert(not combat or not f.protected, 'secure frame creation in combat')
    return f
end
for _,key in ipairs({'Show','Hide','SetPoint','ClearAllPoints','SetSize','EnableMouse'}) do
    local original=methods[key]
    methods[key]=function(self,...) assert(not self.protected or not combat or engine,'protected '..key); return original(self,...) end
end
function RegisterUnitWatch(f) engine=true; f.watched=true; f:SetShown(UnitExists(f.unit)); engine=false end
function UnregisterUnitWatch(f) assert(not combat); f.watched=false end
function Secret(v)
    return setmetatable({secret=true,visual=v}, {__index=function() error('secret indexed') end,
        __add=function() error('secret arithmetic') end,__sub=function() error('secret arithmetic') end,
        __lt=function() error('secret comparison') end,__concat=function() error('secret concatenated') end,
        __tostring=function() error('secret formatted by Lua') end})
end
function Duration(value)
    return {GetRemainingDuration=function() return value end,IsZero=function() return issecretvalue(value) and value or value==0 end}
end
Enum={WorldElapsedTimerTypes={ChallengeMode=1},StatusBarInterpolation={Immediate=0},
    StatusBarTimerDirection={ElapsedTime=0,RemainingTime=1},PowerType={Mana=0},LuaCurveType={Linear=0,Step=1}}
C_CurveUtil={CreateCurve=function()
    return {points={},SetType=function(self,t) self.type=t end,
        AddPoint=function(self,x,y) self.points[#self.points+1]={x,y} end,
        Evaluate=function(self,x)
            if issecretvalue(x) then return Secret('curve render') end
            for i=2,#self.points do
                local p,q=self.points[i-1],self.points[i]
                if x<q[1] then
                    return self.type==1 and p[2] or p[2]+(q[2]-p[2])*(x-p[1])/(q[1]-p[1])
                end
            end
            return self.points[#self.points][2]
        end}
end}
db={}; MythicBoostDB=db
function JP.Settings(k,defaults)
    db[k]=db[k] or {}
    for key,v in pairs(defaults or {}) do if db[k][key]==nil then db[k][key]=v end end
    return db[k]
end
UI.colors.green={.2,.9,.5,1}; UI.colors.red={.9,.3,.3,1}; UI.colors.amber={1,.7,.2,1}; UI.colors.accentDim={.1,.4,.5,1}
units={}; learned={}; role='TANK'; cast=nil
function UnitExists(u) return units[u]~=nil end
function UnitName(u) return units[u] and units[u].name end
function UnitGUID(u) return units[u] and units[u].guid end
function UnitIsPlayer(u) return units[u] and not units[u].pet or false end
function UnitIsFeignDeath(u) return units[u] and units[u].feign or false end
function UnitHealthMax() return Secret(100) end
function UnitHealth() return Secret(50) end
function UnitHealthPercent() return Secret(50) end
function UnitPowerMax() return Secret(100) end
function UnitPower() return Secret(20) end
function UnitPowerPercent(u,_,_,curve) return curve:Evaluate(units[u].mana) end
function UnitIsConnected(u) return units[u].connected~=false end
function UnitIsDeadOrGhost(u) return units[u].dead or false end
function UnitIsVisible(u) return units[u].visible~=false end
function UnitGroupRolesAssigned(u) return units[u] and units[u].role end
function UnitCastingDuration() return cast end
function UnitChannelDuration() return channel end
function UnitCastingInfo() return Secret('Spell'),nil,Secret(123) end
UnitChannelInfo=UnitCastingInfo
function GetSpecialization() return 1 end
function GetSpecializationRole() return role end
function IsInRaid() return raid or false end
function GetNumGroupMembers() return 5 end
function IsPlayerSpell(id) return learned[id] or false end
C_Spell={GetSpellTexture=function(id) return id end,GetSpellCooldownDuration=function() return cooldown or Duration(0) end,
    GetSpellName=function(id) return 'Spell'..id end,
    IsSpellInRange=function(id) return range end}
Minimap=NewWidget(UIParent); BossTargetFrameContainer=NewWidget(UIParent)
function RegisterStateDriver(f,state,condition) f.state=state; f.condition=condition end
function GameTooltip_Hide() end
'''


def runtime():
    lua = LuaRuntime()
    lua.execute(WIDGETS)
    lua.execute(FIXTURE)
    load(lua, 'Contracts.lua')
    hud = source('UI.lua').split('function UI.HUDPanel', 1)[1].split('function UI.Scrim', 1)[0]
    lua.execute('local C,Unpack,WHITE=UI.colors,table.unpack,"white"\nfunction UI.HUDPanel' + hud)
    return lua


def test_dungeon_timer():
    lua = runtime()
    lua.execute(r'''
        active=true; mapID=55; worldTime=123; completed=false; removed={}; queries=0
        ObjectiveTrackerFrame=NewWidget(UIParent); ObjectiveTrackerFrame.protected=true
        trackerManager={RemoveManagedFrame=function(self,f) self.managed=nil end,
            AddManagedFrame=function(self,f)
                if f.ignoreFramePositionManager then return end
                self.managed=f; f:SetParent(UIParent)
            end}
        ObjectiveTrackerFrame.layoutParent=trackerManager
        function GetWorldElapsedTimers() return 9,7 end
        function GetWorldElapsedTime(id) return 'Timer',id==7 and worldTime or 999,id==7 and 1 or 2 end
        C_ChallengeMode={GetActiveChallengeMapID=function() return mapID end,
            GetActiveKeystoneInfo=function() return 10,{165} end,IsChallengeModeActive=function() return active end,
            GetMapUIInfo=function() return 'Dungeon',55,1800 end,GetDeathCount=function() return 2,30 end,
            GetStartTime=function() return 100 end,
            GetAffixInfo=function() return 'Affix',nil,123 end,
            GetChallengeCompletionInfo=function() return {mapChallengeModeID=55,level=10,time=345000} end}
        C_Scenario={GetStepInfo=function() return nil,nil,3 end}
        C_ScenarioInfo={GetCriteriaInfo=function(i)
            if i==3 then return {isWeightedProgress=true,totalQuantity=200,quantityString='70',quantity=35} end
            return {description='Boss '..i,criteriaID=i,completed=i==1 or completed}
        end}
        timeline={1,2}; infos={[1]={spellName='Boss ability'},[2]={spellName='Affix',isApproximate=false}}
        C_EncounterTimeline={GetSortedEventList=function() return timeline end,
            GetEventInfo=function(id) assert(not removed[id], 'removed id queried'); queries=queries+1; return infos[id] end,
            GetEventTimer=function(id) return Duration(Secret(24)) end}
    ''')
    load(lua, 'Modules/DungeonTimer.lua')
    lua.execute(r'''
        local t=JP.DungeonTimer; t:Enable()
        local originalWidth=Minimap:GetWidth()
        Minimap:SetWidth(245)
        function Minimap:GetEffectiveScale() return 1.2 end
        function t.frame:GetEffectiveScale() return .8 end
        t:SyncWidth()
        assert(math.abs(t.frame.width*.8-245*1.2)<.0001)
        assert(math.abs(t.rows[1].name.width-(t.frame.width-82))<.0001)
        Minimap.GetEffectiveScale=nil; t.frame.GetEffectiveScale=nil
        Minimap:SetWidth(originalWidth); t:SyncWidth()
        assert(t.frame.width==Minimap:GetWidth() and ObjectiveTrackerFrame.parent==t.trackerHider)
        trackerManager:AddManagedFrame(ObjectiveTrackerFrame)
        assert(ObjectiveTrackerFrame.parent==t.trackerHider and not trackerManager.managed,
            'Blizzard managed OnShow must not reparent the hidden tracker')
        assert(t.BossName('Победите Мелидруссу Истощенную Холодом')=='Мелидруссу Истощенную Холодом')
        assert(t.BossName('Defeat Boss', 'Native encounter')=='Native encounter')
        assert(issecretvalue(t.BossName(Secret('Boss'))))
        assert(t.elapsed==123, 'must find challenge timer, not use timer 1 or proving grounds')
        assert(t.timeBar.left.text=='2:03 / 30:00', 'death penalty must not be counted twice')
        assert(t.remainingLabel.text=='До конца:' and t.remaining.text=='27:57', 'remaining uses the same penalized world timer')
        assert(t.timeBar.height==64 and t.remaining.font[2]>t.timeBar.left.font[2])
        assert(t.bres.points[1][3]==-102, 'battle res and bosses must move below the taller clock')
        worldTime=1610; combat=true; t.tick(t.frame,.2)
        assert(t.remaining.text=='3:10' and t.timeBar.left.text=='26:50 / 30:00', 'screenshot case updates during combat')
        assert(t.remaining.color[1]==UI.colors.amber[1], 'last five minutes are highlighted')
        combat=false
        local function red(region) return region.color[1] > region.color[2]*1.5 end
        assert(not red(t.timeBar) and not red(t.timeBar.left))
        for i=1,2 do
            assert(t.thresholdMarkers[i].width==2 and t.thresholdMarkers[i].color[4]==1,
                'stage dividers must remain thick and opaque over the fill')
            assert(t.thresholds[i].font[3]=='OUTLINE')
        end
        for _,phase in ipairs({{1079.9,false,false,false},{1080,true,false,false},
            {1439.9,true,false,false},{1440,true,true,false},
            {1799.9,true,true,false},{1800,true,true,true}}) do
            worldTime=phase[1]; t:UpdateClock()
            assert(red(t.thresholds[1])==phase[2] and red(t.thresholdMarkers[1])==phase[2])
            assert(red(t.thresholds[2])==phase[3] and red(t.thresholdMarkers[2])==phase[3])
            assert(red(t.timeBar)==phase[4] and red(t.timeBar.left)==phase[4], 'whole bar red only at full limit')
        end
        assert(t.remainingLabel.text=='Сверх времени:' and t.remaining.text=='0:00' and red(t.remaining))
        worldTime=1799.9; t:UpdateClock()
        assert(t.remainingLabel.text=='До конца:' and t.remaining.text=='0:01', 'last fractional second is not expired')
        worldTime=1815; t:UpdateClock()
        assert(t.remainingLabel.text=='Сверх времени:' and t.remaining.text=='0:15')
        t.limit=1680; worldTime=5350; t:UpdateClock()
        assert(t.timeBar.left.text=='89:10 / 28:00' and red(t.timeBar) and red(t.timeBar.left))
        assert(t.thresholds[1].text=='+3  -72:22' and t.thresholds[2].text=='+2  -66:46')
        t.limit=nil; t:UpdateClock()
        assert(not red(t.timeBar) and t.thresholds[1].text=='' and t.thresholds[2].text=='')
        assert(t.remaining.text=='—', 'unknown limit cannot look like zero time left')
        t.limit=1800; worldTime=Secret(5350); t:UpdateClock()
        assert(t.timeBar.left.text=='Ожидание старта' and not red(t.timeBar.left))
        assert(t.remaining.text=='—', 'secret elapsed cannot become a fabricated countdown')
        assert(t.thresholds[1].text=='' and not red(t.thresholdMarkers[1]))
        assert(t.forces.left.text=='35.00%' and t.forces.value==70)
        assert(t.splits[1]==nil and t.rows[1].time.text=='OK')
        worldTime=2998; t:UpdateClock()
        assert(t.timeBar.left.text=='49:58 / 30:00')
        assert(t.thresholds[1].text=='+3  -31:58' and t.thresholds[2].text=='+2  -25:58')
        worldTime=123; t:UpdateClock()
        assert(not red(t.timeBar) and not red(t.timeBar.left) and not red(t.thresholds[1]), 'new elapsed resets all colors')
        assert(t.deathHover.mouseMotion and not t.deathHover.mouseClicks)
        units.party1={name='Friend-Realm',guid='Player-1-A'}
        units.party2={name='Pet',guid='Pet-1',pet=true}
        t:CacheDeathRoster(); combat=true
        t:RecordDeath(Secret('Player-1-A')); t:RecordDeath('Enemy'); t:RecordDeath('Pet-1')
        assert(next(t.deathRun.players)==nil)
        units.party1.feign=true; t:RecordDeath('Player-1-A'); assert(next(t.deathRun.players)==nil)
        units.party1.feign=false; t:RecordDeath('Player-1-A'); combat=false
        assert(t.deathRun.players['Player-1-A'].count==1)
        t:LoadDeathRun(false); assert(t.deathRun.players['Player-1-A'].count==1, 'reload history')
        t:LoadDeathRun(true); assert(next(t.deathRun.players)==nil, 'new run reset')
        t:RefreshCriteria(false); assert(t.splits[1]==nil, 'reload must not invent boss split')
        completed=true; worldTime=200; t:RefreshCriteria(false); assert(t.splits[2]==200)
        t:RefreshCriteria(false); assert(t.splits[2]==200)
        assert(t.affixEventID==2 and t.affix.timer)
        local built=allocations; t:Create(); assert(allocations==built)
        for i=1,10000 do t:UpdateClock() end
        assert(allocations==built and queries==2, 'clock must not scan frames or timeline on every tick')
        assert(issecretvalue(t.affix.right.text), 'duration must go to native format sink')
        local fullHeight=t.frame.height
        removed[2]=true; t:RefreshAffix(2)
        assert(t.affixEventID==nil and t.affix.right.text=='' and not t.affix.shown)
        assert(t.frame.height==fullHeight-23, 'unavailable affix must reserve no space')
        infos[1]={spellName=Secret('Affix'),spellID=Secret(123)}; timeline={1}
        t:RefreshAffix(); assert(t.affixEventID==nil, 'a secret event must not be classified as an affix')
        t:Finish(); assert(t.elapsed==345 and not t.frame.scripts.OnUpdate and not t.affix.shown)
        assert(t.remainingLabel.text=='Запас времени:' and t.remaining.text=='24:15')
        worldTime=2000; t:UpdateClock()
        assert(t.remaining.text=='24:15', 'completed key keeps its final time margin')
        db.dungeonTimer.enabled=false; t:Refresh(); assert(not t.frame.shown)
        db.dungeonTimer.enabled=true; active=false; t.finished=false; t:Refresh(); assert(not t.frame.shown)
        t:SetUnlocked(true); assert(t.frame.shown and not t.frame.scripts.OnUpdate)
        t:StyleClock(2998,1800); t:Preview()
        assert(t.remainingLabel.text=='До конца:' and t.remaining.text=='25:51')
        assert(not red(t.timeBar) and not red(t.thresholds[1]) and not red(t.thresholdMarkers[2]), 'preview resets expired colors')
        assert(ObjectiveTrackerFrame.parent==UIParent and t.affix.shown)
        t:SetUnlocked(false); assert(not t.frame.shown)
        active=true; worldTime=10; t:Refresh(true); assert(t.splits[2]==nil and t.frame.scripts.OnUpdate)
        assert(t.remainingLabel.text=='До конца:' and t.remaining.text=='29:50')
        assert(not red(t.timeBar) and not red(t.timeBar.left) and not red(t.thresholds[2]))
        combat=true; t:Disable()
        assert(ObjectiveTrackerFrame.parent==t.trackerHider and t.trackerPending)
        combat=false; t.events.scripts.OnEvent(nil,'PLAYER_REGEN_ENABLED')
        assert(ObjectiveTrackerFrame.parent==UIParent and not t.trackerPending)
        assert(ObjectiveTrackerFrame.ignoreFramePositionManager==nil and trackerManager.managed==ObjectiveTrackerFrame)
        assert(not next(t.events.events) and not t.frame.scripts.OnUpdate)
    ''')


def test_boss_frames():
    lua = runtime()
    load(lua, 'Modules/BossFrames.lua')
    lua.execute(r'''
        local b=JP.BossFrames; b:Enable()
        assert(#b.rows==5 and BossTargetFrameContainer.parent==b.hider)
        assert(b.frame.points[1][2]==Minimap and b.frame.points[1][3]=='TOPLEFT')
        local built=allocations; b:Enable(); assert(allocations==built)
        units.boss1={name=Secret('Boss')}; cast=Duration(Secret(2)); combat=true
        for i=1,10000 do b:Update(b.rows[1]) end
        assert(allocations==built and issecretvalue(b.rows[1].name.text))
        assert(b.rows[1].cast.timer==cast and issecretvalue(b.rows[1].health.value))
        cast=nil; channel=Duration(Secret(1)); b:Update(b.rows[1],'UNIT_SPELLCAST_CHANNEL_START')
        assert(b.rows[1].cast.direction==1)
        channel=nil; b:Update(b.rows[1],'UNIT_SPELLCAST_STOP'); assert(not b.rows[1].cast.shown)
        b:Layout(); assert(b.layoutPending)
        combat=false; b.events.scripts.OnEvent(nil,'PLAYER_REGEN_ENABLED'); assert(not b.layoutPending)
        b:SetUnlocked(true); assert(not b.rows[1].watched and b.rows[5].shown)
        b:SetUnlocked(false); assert(b.rows[1].watched)
        b:Disable(); assert(BossTargetFrameContainer.parent==UIParent and not b.frame.shown)
    ''')
    lua = runtime()
    load(lua, 'Modules/BossFrames.lua')
    lua.execute('combat=true; JP.BossFrames:Enable(); assert(not JP.BossFrames.frame); combat=false; JP.BossFrames.bootstrap.scripts.OnEvent(); assert(JP.BossFrames.frame)')


def test_healer_mana():
    lua = runtime()
    load(lua, 'Modules/HealerMana.lua')
    lua.execute(r'''
        units.party1={name='Healer',mana=.2,role='HEALER'}
        units.party2={name='DPS',mana=0,role='DAMAGER'}
        local m=JP.HealerMana; m:Enable(); local r=m.rows[1]
        assert(#m.healers==1 and r.alpha==1 and r.value.text=='20%')
        units.party1.mana=.21; m.events.scripts.OnEvent(nil,'UNIT_POWER_UPDATE','party1','MANA'); assert(r.alpha==0)
        units.party1.mana=.01; m:Update(); assert(r.alpha==1)
        combat=true; units.party1.mana=Secret(.1); units.party1.name=Secret('Name')
        local built=allocations
        for i=1,10000 do m:Update() end
        assert(allocations==built and issecretvalue(r.alpha) and issecretvalue(r.value.text) and issecretvalue(r.name.text))
        assert(not r.mouse and not m.frame.mouse, 'invisible visual alert must not catch clicks')
        units.party1.dead=true; m:Update(); assert(not r.shown)
        units.party1.dead=false; units.party1.connected=false; m:Update(); assert(not r.shown)
        role='HEALER'; m:RefreshRoster(); assert(not m.frame.shown)
        role='DAMAGER'; m:RefreshRoster(); assert(not m.frame.shown)
        combat=false; m:SetUnlocked(true); assert(m.frame.shown and r.alpha==1)
        m:SetUnlocked(false); assert(not m.frame.shown)
        m:Disable(); assert(not next(m.events.events))
    ''')


def test_controls():
    lua = runtime()
    load(lua, 'Modules/ControlAssist.lua')
    lua.execute(r'''
        learned[132469]=true; learned[20549]=true
        local c=JP.ControlAssist; c:Enable(); assert(#c.spells==2 and not c.frame.shown)
        assert(c.frame.condition=='[combat] show; hide' and c.icons[1]:GetAttribute('type')=='spell')
        assert(c.icons[1]:GetAttribute('spell')==132469 and c.icons[1]:GetAttribute('unit')==nil)
        assert(c.icons[1]:GetAttribute('useOnKeyDown')==false and c.icons[1].width==42)
        assert(c.label==nil and c.frame.height==70 and c.frame.width==108)
        assert(c.icons[1].highlight and c.icons[1].cooldown.mouseClicks==false)
        combat=true; engine=true; c.frame:Show(); engine=false; range=nil; c:Refresh()
        assert(c.frame.shown and c.icons[1].range.text=='')
        assert(not c.frame.mouse and c.icons[1].mouse and not c.icons[1].cooldown.mouse)
        assert(c.icons[1].name.text=='Тайфун')
        local built=allocations; cooldown=Duration(Secret(10)); range=Secret(true)
        for i=1,10000 do c:Update() end
        assert(built==allocations and c.icons[1].range.text=='' and issecretvalue(c.icons[1].ready.alpha))
        range=false; c:Update(); assert(c.icons[1].range.text=='Далеко')
        range=true; c:Update(); assert(c.icons[1].range.text=='OK')
        learned[132469]=false; c:CacheSpells(); assert(c.spellsPending and c.icons[1]:GetAttribute('spell')==132469)
        combat=false; c.events.scripts.OnEvent(nil,'PLAYER_REGEN_ENABLED')
        assert(not c.spellsPending and c.icons[1]:GetAttribute('spell')==20549)
        c:Refresh(); assert(not c.frame.shown and not c.ticker.scripts.OnUpdate)
        c:SetUnlocked(true); assert(c.frame.shown and c.icons[1]:GetAttribute('type')==nil, 'preview must never cast')
        c:SetUnlocked(false); assert(c.icons[1]:GetAttribute('type')=='spell')
        c:Disable(); assert(not next(c.events.events))
    ''')
    text = source('Modules/ControlAssist.lua')
    assert 'SecureActionButtonTemplate' in text and 'CastSpell' not in text and 'RunMacro' not in text
    assert '·' not in text and '✓' not in text and '×' not in text
    lua = runtime()
    load(lua, 'Modules/ControlAssist.lua')
    lua.execute('combat=true; JP.ControlAssist:Enable(); assert(not JP.ControlAssist.frame); combat=false; JP.ControlAssist.bootstrap.scripts.OnEvent(); assert(JP.ControlAssist.frame)')


def test_whisper_and_dialog():
    lua = runtime()
    lua.execute("db.convenience={whisperInvite=true}; invites={}; function IsInGroup() return false end; C_PartyInfo={InviteUnit=function(name) invites[#invites+1]=name end}")
    load(lua, 'Modules/Convenience.lua')
    lua.execute(r'''
        local c=JP.Convenience
        c:InviteFromWhisper(Secret('inv'),'Player'); c:InviteFromWhisper('inv',Secret('Player')); assert(#invites==0)
        combat=true; c:InviteFromWhisper('inv','Player'); assert(#invites==0)
        assert(c:SlotKeystone()==false); c:SetupKeystoneFrame()
        combat=false; c:InviteFromWhisper(' INV ','Player'); assert(#invites==1 and invites[1]=='Player')
        c:InviteFromWhisper('hello','Player'); assert(#invites==1)
    ''')
    text = source('Modules/Welcome.lua').split('function Welcome:Create()', 1)[1]
    assert 'frame:SetFrameStrata("HIGH")' in text and 'frame:SetFrameStrata("DIALOG")' not in text


def test_secure_buff_driver():
    lua = runtime()
    lua.execute(r'''
        local methods=getmetatable(UIParent).__index
        function methods:SetAttribute(k,v)
            assert(not combat or engine,'only the secure state driver may change attributes in combat')
            self.attrs=self.attrs or {}; self.attrs[k]=v
        end
        db.smartClick={buff=true}; learned[1126]=true; function UnitClass() return 'Druid','DRUID' end
        C_Spell.GetSpellName=function() return 'Buff' end
        C_Spell.GetSpellInfo=function() return {name='Buff'} end
        function UI.Backdrop() end
    ''')
    load(lua, 'Modules/SmartClick.lua')
    lua.execute(r'''
        local m=JP.SmartClick; local b=m:BuildBuffButton(); assert(b and not b.shown and b.alpha==1)
        assert(b.condition=='[combat] 1; 0')
        b:SetAttribute('mb-enabled',true); b:SetAttribute('mb-visible',false); b:Hide()
        local driver=assert(load('return function(self,newstate) '..b:GetAttribute('_onstate-combat')..' end'))()
        combat=true; engine=true; driver(b,'1'); engine=false; assert(not b.shown)
        local built=allocations
        for i=1,1000 do m:RefreshBuffButton() end
        assert(not b.shown and allocations==built, 'combat cannot invent a missing-buff warning')
        combat=false; driver(b,'0'); assert(not b.shown)
        b:SetAttribute('mb-visible',true); driver(b,'0'); assert(b.shown)
        combat=true; engine=true; driver(b,'1'); engine=false
        assert(not b.shown and not b:GetAttribute('mb-visible'), 'combat clears a stale pre-pull reminder')
        combat=false; driver(b,'0'); assert(not b.shown, 'wait for a fresh aura check after combat')
        b:SetAttribute('mb-enabled',false); driver(b,'1'); assert(not b.shown)
        driver(b,'0'); assert(not b.shown, 'disabled buff stays hidden even with stale reminder')
        assert(b:GetAttribute('useOnKeyDown')==false)
    ''')


if __name__ == '__main__':
    for test in (test_dungeon_timer, test_boss_frames, test_healer_mana, test_controls, test_whisper_and_dialog, test_secure_buff_driver):
        test()
        print(test.__name__ + ': OK')
