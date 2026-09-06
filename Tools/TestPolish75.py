"""Settings polish, safe profile sharing and public-only aura filters."""
from lupa import LuaRuntime
from TestDungeonHUD import runtime
from TestHudPolish import source, load
from TestAvoidableDamage import fixture


def test_refresh_coalescing():
    lua=LuaRuntime()
    method=source('Core.lua').split('function JP:RequestRefresh',1)[1].split('\nend',1)[0]
    lua.execute('''
        calls=0; shown=true; timers={}
        JP={modules={Welcome={frame={IsShown=function() return shown end},
            Refresh=function() calls=calls+1 end}}}
        C_Timer={After=function(delay,fn) timers[#timers+1]=fn end}
    ''')
    lua.execute('function JP:RequestRefresh'+method+'\nend')
    lua.execute('''
        for i=1,10000 do JP:RequestRefresh() end
        assert(#timers==1); timers[1](); assert(calls==1)
        JP:RequestRefresh(); shown=false; timers[2](); assert(calls==1)
        JP:RequestRefresh(); assert(#timers==2)
        shown=true; JP:RequestRefresh(); timers[3](); assert(calls==2)
    ''')


def test_meter_burst():
    lua=fixture()
    lua.execute('''
        m=JP.AvoidableDamage; m:Enable(); autoFlush=false
        local before=reads
        for i=1,10000 do Damage(i); Fire('DAMAGE_METER_COMBAT_SESSION_UPDATED',8) end
        assert(#timers==1 and reads==before)
        Flush(); assert(m.players.P1.amount==10000)
        Fire('DAMAGE_METER_CURRENT_SESSION_UPDATED'); m:Disable()
        before=reads; Flush(); assert(reads==before)
        m:Enable(); Damage(10500); Fire('DAMAGE_METER_CURRENT_SESSION_UPDATED')
        local trailing=m.snapshotTimer
        Fire('PLAYER_REGEN_ENABLED'); assert(m.players.P1.amount==500)
        assert(trailing.cancelled and not m.snapshotTimer,'combat-end snapshot replaces trailing scan')
        assert(m.reportTimer,'combat-end also requests the separate post-pull feed')
        m:CancelCombatReport() -- isolate snapshot coalescing; feed retries have their own regression suite
        before=reads; Flush(); assert(reads==before,'urgent refresh cancels trailing scan')
        combat=true
        for i=1,1000 do Fire('DAMAGE_METER_CURRENT_SESSION_UPDATED') end
        assert(#timers==0 and reads==before)
    ''')
    lua=fixture()
    lua.execute('''
        m=JP.AvoidableDamage; m:Enable(); attempts={}; recapReads=0
        C_DeathRecap.GetRecapEvents=function(id)
            attempts[id]=(attempts[id] or 0)+1; recapReads=recapReads+1
            return nil
        end
        overall[9]={combatSources={}}
        for i=1,64 do overall[9].combatSources[i]=Death(i) end
        m:Snapshot(); assert(recapReads==32)
        m:Snapshot(); assert(recapReads==64)
        for i=1,64 do assert(attempts[i]==1,'every unresolved recap gets a turn') end
    ''')


def test_moving_completed_timer_keeps_result():
    lua=LuaRuntime()
    method=source('Modules/DungeonTimer.lua').split('function Timer:SetUnlocked',1)[1].split('\nend',1)[0]
    lua.execute('Timer={active=true,finished=true,elapsed=1921,rowCount=4,Refresh=function() end}')
    lua.execute('function Timer:SetUnlocked'+method+'\nend')
    lua.execute('''
        Timer:SetUnlocked(true); assert(not Timer.preview and Timer.unlocked)
        Timer:SetUnlocked(false); assert(Timer.finished and Timer.elapsed==1921 and Timer.rowCount==4)
        Timer.active=false; Timer.finished=false; Timer:SetUnlocked(true); assert(Timer.preview)
    ''')


def aura_fixture():
    lua=runtime()
    lua.execute('''
        function IsInGroup() return grouped end
        function IsInInstance() return inside,instanceType or 'none' end
        function IsMounted() return mounted==true end
        function UnitExists() return exists~=false end
        function UnitIsVisible() return visible~=false end
        function UnitCanAssist() return friendly~=false end
        function UnitIsDeadOrGhost() return dead==true end
        grouped=false; visible=true; mounted=false
        UI.SafeNumber=JP.SafeNumber; UI.SafeString=JP.SafeString
    ''')
    load(lua,'Modules/AuraFilters.lua')
    return lua


def test_aura_filters():
    lua=aura_fixture()
    lua.execute('''
        f=JP.AuraFilters
        s=JP.Settings('positiveAuraTracker'); s.filters={[0]={minStacks=2,maxRemaining=10},[123]={minStacks=3}}
        local r=f:Rules(123)
        assert(r.minStacks==3 and r.maxRemaining==10)
        assert(f:Rules(456).minStacks==2)
        a={applications=3,duration=30,expirationTime=20,sourceUnit='player',isHelpful=true}
        assert(f:Matches(r,a,12))
        local ok,unknown=f:Matches(r,a,0); assert(not ok and not unknown)
        assert(f:NextBoundary(r,a,0)>10 and f:NextBoundary(r,a,0)<10.1)
        a.applications={secret=true}
        ok,unknown=f:Matches(r,a,12); assert(not ok and unknown)
        a.applications=3; a.duration={secret=true}; a.expirationTime={secret=true}
        ok,unknown=f:Matches(r,a,12); assert(not ok and unknown)
        s.filters={[0]={own='mine'}}; f:Invalidate(); r=f:Rules(123)
        a={sourceUnit='pet'}; assert(f:Matches(r,a,0))
        a.sourceUnit='party1'; assert(not f:Matches(r,a,0))
        a.sourceUnit={secret=true}; ok,unknown=f:Matches(r,a,0); assert(not ok and unknown)
        s.filters={[0]={auraType='buff',stealable=true,dispel='Magic'}}; f:Invalidate(); r=f:Rules(123)
        assert(f:Matches(r,{isHelpful=true,isStealable=true,dispelName='Magic'},0))
        ok,unknown=f:Matches(r,{isHelpful=false,isHarmful=true},0); assert(not ok and not unknown)
        ok,unknown=f:Matches(r,{isHelpful={secret=true}},0); assert(not ok and unknown)
        s.filters={[0]={combat='in',group='group',unit='party1',alive=true,unmounted=true,instance='party'}}
        f:Invalidate(); r=f:Rules(1)
        assert(not f:CanLoad(r)); combat=true; grouped=true; instanceType='party'
        assert(f:CanLoad(r)); visible=false; assert(not f:CanLoad(r)); visible=true
        friendly=false; assert(not f:CanLoad(r)); friendly=true
        dead=true; assert(not f:CanLoad(r)); dead=false
        mounted=true; assert(not f:CanLoad(r))
        -- Defaults do not consult unnecessary unit state or alter settings.
        s.filters={}; f:Invalidate(); assert(f:CanLoad(f:Rules(1)))
        local cached=f:Rules(1); for i=1,10000 do assert(f:Rules(1)==cached) end
    ''')


def test_tracker_lifecycle_and_hidden_boundary():
    lua=aura_fixture()
    load(lua,'Modules/PositiveAuraTracker.lua')
    lua.execute('''
        local methods=getmetatable(UIParent).__index
        timers={}; afters={}; reads=0
        C_Timer={After=function(_,fn) afters[#afters+1]=fn end,
            NewTimer=function(delay,fn)
                local t={fn=fn,delay=delay}; function t:Cancel() self.cancelled=true end
                timers[#timers+1]=t; return t
            end}
        C_Spell={GetSpellInfo=function(id) return {spellID=id,name='Buff',iconID=1} end}
        function UI.SafeUnitAura(unit,id)
            reads=reads+1
            return {duration=20,expirationTime=20,applications=1,sourceUnit='player'},false
        end
        m=JP.PositiveAuraTracker; s=JP.Settings('positiveAuraTracker')
        s.enabled=true; s.spellIDs={123}; s.maxIcons=8; s.pulse=false; s.barHeight=190
        s.filters={[0]={maxRemaining=10}}; JP.AuraFilters:Invalidate()
        m.frame=NewWidget(); m.frame.icons={}
        for i=1,8 do
            local w=NewWidget(m.frame)
            for _,key in ipairs({'seconds','stacks','texture','textureBorder','fill','glow'}) do w[key]=NewWidget(w) end
            m.frame.icons[i]=w
        end
        m.frame.move=NewWidget(m.frame); m.events=NewWidget()
        m:Refresh(); assert(not m.frame.shown and #timers==1)
        now=10.03; timers[1].fn(); assert(m.frame.shown and m.frame.icons[1].shown)
        now=0; m:Refresh(); local t=m.filterTimer
        m:Disable(); assert(t.cancelled and not m.frame.shown)
        -- Re-enabling must restore events without reallocating the tracker.
        m.ApplySettings=function() end
        local before=allocations; m:Enable()
        assert(m.events.events.UNIT_AURA and m.events.events.PLAYER_REGEN_DISABLED)
        assert(allocations==before)
        local calls=reads
        for i=1,1000 do m:QueueRefresh() end
        assert(#afters==1 and reads==calls)
        m:Disable(); afters[1](); assert(reads==calls)
        m:Enable(); s.enabled=false; m:BindEvents(); assert(next(m.events.events)==nil)
    ''')


def test_layout_is_inert():
    lua=runtime()
    lua.execute('''
        function Fail() error('unexpected external mutation') end
        C_EditMode=setmetatable({},{__index=function() return Fail end})
        SetBinding=Fail; SaveBindings=Fail; SetCVar=Fail
        local methods=getmetatable(UIParent).__index
        function methods:SetFontObject() end
        function methods:SetAutoFocus() end
        function methods:GetText() return self.text end
        function methods:SetCursorPosition(value) self.cursor=value end
        function methods:HighlightText() self.selected=true end
        function methods:ClearFocus() self.focus=false end
        function methods:SetFocus() self.focus=true end
        function UI.Button(p,text,w,h) local f=NewWidget(p); f:SetSize(w,h); f:SetText(text); return f end
        function UI.Panel(p) return NewWidget(p) end
    ''')
    load(lua,'Modules/LayoutPresets.lua')
    lua.execute('''
        local p=JP.LayoutPresets
        assert(p.Main:sub(1,4)=='2 52' and #p.Main>2000)
        assert(not p.Main:find('[\\r\\n]'))
        p:Build(NewWidget()); assert(p.field.cursor==0)
        assert(not p.codeBox.shown)
        p.copyButton.scripts.OnClick()
        assert(p.codeBox.shown and p.field.selected and p.field.focus and p.field.cursor==0)
        local n=allocations; p:Build(NewWidget()); assert(allocations==n+1)
        p.field.text='edited'; p.field.scripts.OnTextChanged(p.field,true)
        assert(p.field.text==p.Main and p.field.selected and p.field.cursor==0)
    ''')
    lua=LuaRuntime()
    lua.execute("GetLocale=function() return 'enUS' end; JP={}")
    load(lua,'Localization.lua')
    assert lua.eval('JP.L("Заявок пока нет.\\nОни появятся здесь, как только кто-то откликнется.")').startswith('There are no')


def test_disabled_theme_owns_nothing():
    lua=LuaRuntime()
    apply=source('Modules/MinimalUI.lua').split('function MinimalUI:Apply()',1)[1].split('function MinimalUI:SetEnabled',1)[0]
    lua.execute('''
        calls=0; combat=false; JP={}; C_Timer={}
        function InCombatLockdown() return combat end
        function RestoreVisibility() calls=calls+1 end
        MythicBoostDB={minimalUI=false,minimalUIOptions={},convenience={hideBags=true}}
        MinimalUI=setmetatable({},{__index=function(_,key)
            if key:find('Style')==1 then return function(_,value)
                calls=calls+1
                if key=='StyleBags' then bags=value end
            end end
        end})
    ''')
    lua.execute('function MinimalUI:Apply()'+apply)
    lua.execute('''
        for i=1,1000 do MinimalUI:Apply() end
        assert(calls==0,'disabled first install must not restore foreign frames')
        MythicBoostDB.minimalUI=true; combat=true; MinimalUI:Apply(); assert(calls==0)
        combat=false; MinimalUI:Apply(); assert(calls>0 and MinimalUI.appliedActive)
        MythicBoostDB.minimalUI=false; MinimalUI:Apply()
        assert(bags==false and not MinimalUI.appliedActive)
        local before=calls; MinimalUI:Apply(); assert(calls==before,'restore owned state once')
    ''')


if __name__=='__main__':
    test_refresh_coalescing()
    test_meter_burst()
    test_moving_completed_timer_keeps_result()
    test_aura_filters()
    test_tracker_lifecycle_and_hidden_boundary()
    test_layout_is_inert()
    test_disabled_theme_owns_nothing()
    print('Polish 75: bounded queues, public-only filters, hidden thresholds, lifecycle, inert profile export and multiline locales passed')
