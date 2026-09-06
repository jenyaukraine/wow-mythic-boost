"""Key-bound performance snapshots: native secrets, boundaries, persistence and bounds."""
from TestSocialWorkflows import client, load


def fixture():
    lua = client()
    lua.execute(r'''
        local old=C_Timer
        timers={}; reads=0; gearReads=0; disabled=false; unavailable=false
        C_Timer.NewTimer=function(delay,fn)
            local t={due=now+delay,fn=fn}
            function t:Cancel() self.cancelled=true end
            timers[#timers+1]=t; return t
        end
        function Tick(seconds)
            now=now+seconds
            local queue=timers; timers={}
            for _,t in ipairs(queue) do
                if not t.cancelled then
                    if t.due<=now then t.fn() else timers[#timers+1]=t end
                end
            end
        end
        function Drain() for i=1,50 do Tick(1) end end
        Enum.DamageMeterSessionType={Overall=0,Current=1}
        Enum.DamageMeterType={DamageDone=0,HealingDone=2,AvoidableDamageTaken=8}
        C_CVar={GetCVarBool=function() return not disabled end}
        durations={[0]=40,[2]=40,[8]=40}
        amounts={[0]=1000,[2]=2000,[8]=500}; blocked={}
        C_DamageMeter={IsDamageMeterAvailable=function() return not unavailable end,
            GetCombatSessionFromType=function(session,typ)
                reads=reads+1; assert(not combat and session==0)
                if blocked[typ] then return Secret({}) end
                return {durationSeconds=durations[typ],combatSources={
                    {sourceGUID='Player-Bob',totalAmount=amounts[typ]},
                    {sourceGUID='Player-Stranger',totalAmount=999999999}}}
            end}
        C_PaperDollInfo={GetInspectItemLevel=function(u)
            gearReads=gearReads+1; assert(not combat)
            return u=='party1' and (gear or 310.25) or 0
        end}
        function GetAverageItemLevel() return 999,300 end
        function Native(d,h,a,duration)
            amounts={[0]=d,[2]=h,[8]=a}
            durations={[0]=duration,[2]=duration,[8]=duration}
        end
        function NewRun(resumed)
            return {trackingPartial=resumed,members={
                {guid='Player-Alice',name='Alice-Realm',role='DAMAGER'},
                {guid='Player-Bob',name='Bob-Realm',role='HEALER'}}}
        end
        function Result()
            return {completedAt=time(),members={'Alice-Realm','Bob-Realm'},mapID=399,level=12,mapName='Test'}
        end
    ''')
    load(lua, 'Modules/RunStats.lua')
    lua.execute('s=JP.RunStats')
    return lua


def test_key_baseline_rates_and_readonly_review():
    lua=fixture()
    lua.execute(r'''
        run=NewRun(); s:Start(run)
        assert(s.players['Player-Bob'].damage==nil)
        Native(31000,62000,5500,100); s:Snapshot()
        Native(46000,92000,7500,130)
        result=Result(); s:Finish(run,result); Tick(.5)
        local stats=result.performance['bob-realm']
        assert(stats.damage==45000 and stats.healing==90000 and stats.avoidable==7000)
        assert(stats.duration==90 and stats.itemLevel==310.3 and stats.complete)
        assert(s:Text(stats,true):find('DPS 500',1,true))
        assert(s:Text(stats,true):find('HPS 1.0k',1,true))
        assert(r:Save('Bob-Realm',1,'great',result))
        local review=r:GetOwn('Bob-Realm')
        assert(review.stats.damage==45000 and review.stats~=stats)
        stats.damage=999999; assert(review.stats.damage==45000,'copied metadata, not shared mutable references')
        Native(51000,102000,8000,140); s:Snapshot()
        assert(review.stats.damage==50000 and review.stats.avoidable==7500,'late native data upgrades exact review')
        assert(r:Database()[1].stats.damage==50000)
        r:ShowRun(result); assert(r.reviewRows[1].stats.text:find('HPS',1,true))
        local allocationsBefore=allocations
        for i=1,1000 do r:ShowRun(result) end
        assert(allocations==allocationsBefore,'one editor with fixed rows')
        Drain(); assert(not s.players and not s.timer and not next(s.events.events))
        assert(result.performance['bob-realm'].damage==50000,'saved snapshot survives collector disposal')
        assert(r:Save('Bob-Realm',0,'',result))
    ''')


def test_partial_missing_resets_and_secrets():
    lua=fixture()
    lua.execute(r'''
        run=NewRun(); combat=true; s:Start(run)
        assert(reads==0 and gearReads==0)
        local before=reads; s:Snapshot(); assert(reads==before)
        combat=false; gear=Secret(313); s:Snapshot()
        Native(2000,4000,800,50); result=Result(); s:Finish(run,result); Tick(.5)
        local stats=result.performance['bob-realm']
        assert(stats.damage==1000 and stats.healing==2000 and stats.avoidable==300)
        assert(not stats.complete and stats.itemLevel==nil,'unknown initial boundary is not full key')
        blocked[2]=true; s:Snapshot(); assert(not result.performance['bob-realm'].complete)
        blocked[2]=nil
        s.events.scripts.OnEvent(nil,'DAMAGE_METER_RESET'); Native(100,200,30,2); Tick(.5)
        assert(result.performance['bob-realm'].damage==1100 and not result.performance['bob-realm'].complete)
        assert(s:Validate({version=1,runAt=time(),damage=Secret(500),duration=Secret(10)}).damage==nil)
        assert(s:Validate(Secret({}))==nil)
        local clean=s:Validate({version=1,runAt=time(),damage=0/0,healing=math.huge,avoidable=-1,itemLevel=-2})
        assert(clean.damage==nil and clean.healing==nil and clean.avoidable==nil and clean.itemLevel==nil)
        s:Stop(); disabled=true; s:Start(NewRun()); s:Snapshot()
        result=Result(); s:Finish(s.run,result); Tick(.5)
        stats=result.performance['bob-realm']
        assert(stats.damage==nil and stats.healing==nil and stats.avoidable==nil and not stats.complete)
        Drain()
    ''')


def test_lifecycle_bounds_and_boundaries():
    lua=fixture()
    lua.execute(r'''
        run=NewRun(); s:Start(run); Native(2000,3000,600,50); s:Snapshot()
        result=Result(); s:Finish(run,result); local old=s.timer
        combat=true; s.events.scripts.OnEvent(nil,'PLAYER_REGEN_DISABLED')
        assert(not s.players and old.cancelled)
        combat=false; Native(90000,90000,90000,900)
        run=NewRun(); s:Start(run); old.fn()
        assert(s.run==run and not s.result,'stale timer cannot finalize next key')
        Native(91000,92000,90100,910); s:Snapshot()
        result=Result(); s:Finish(run,result); Tick(.5)
        assert(result.performance['bob-realm'].damage==1000)
        assert(r:Save('Bob-Realm',1,'saved',result))
        local review=r:GetOwn('Bob-Realm')
        assert(r:Save('Bob-Realm',0,'',result)); assert(not r:GetOwn('Bob-Realm').stats)
        Native(92000,93000,90200,920); s:Snapshot()
        assert(not r:GetOwn('Bob-Realm').stats,'late data cannot resurrect deleted review')
        s:Stop(); timers={}
        local built=allocations; local weak=setmetatable({},{__mode='v'})
        for i=1,1000 do
            local run=NewRun(); s:Start(run)
            for j=1,100 do s:Queue() end
            assert(#timers==1,'event burst coalesced')
            weak[i]=s.players
            s:Stop(); timers={}
        end
        collectgarbage('collect')
        assert(next(weak)==nil and allocations==built,'bounded frames, snapshots collectible')
        assert(not next(s.events.events))
    ''')


def test_validation_and_history_integration():
    lua=fixture()
    lua.execute(r'''
        local stats={version=1,runAt=time(),role='HEALER',damage=0,healing=90000,
            avoidable=7000,itemLevel=310.3,duration=90,complete=true}
        local text=s:Encode(stats); assert(#text<160)
        assert(s:Encode(s:Decode(text))==text)
        assert(not s:Decode('S1,1788580800,HEALER,1,-1,4,3,9,300'))
        assert(not s:Decode('S1,1788580800,HEALER,1,5,4,3,9,999999'))
        s:Start(NewRun()); local old=s.run
        s:Finish(NewRun(),Result()); assert(not s.result,'run identity cannot be swapped')
        s:Stop()
    ''')
    from pathlib import Path
    source=(Path(__file__).resolve().parents[1]/'MythicBoost/Modules/RunHistory.lua').read_text(encoding='utf-8-sig')
    assert 'JP.RunStats:Start(self.current)' in source
    assert 'JP.RunStats:Finish(run,result)' in source
    assert 'self:DiscardRun(true)' in source


def test_temporarily_missing_native_row_does_not_double_count():
    lua=fixture()
    lua.execute(r'''
        s:Start(NewRun()); Native(2000,3000,600,50); s:Snapshot()
        local original=C_DamageMeter.GetCombatSessionFromType
        C_DamageMeter.GetCombatSessionFromType=function() return {durationSeconds=50,combatSources={}} end
        s:Snapshot()
        C_DamageMeter.GetCombatSessionFromType=original
        Native(2100,3100,650,55); s:Snapshot()
        assert(s.players['Player-Bob'].damage==1100 and s.players['Player-Bob'].healing==1100)
        assert(s.meters.damage.partial,'an incomplete intermediate native row is not a complete sample')
        s:Stop()
    ''')


if __name__=='__main__':
    for test in [test_key_baseline_rates_and_readonly_review,test_partial_missing_resets_and_secrets,
                 test_lifecycle_bounds_and_boundaries,test_validation_and_history_integration,
                 test_temporarily_missing_native_row_does_not_double_count]:
        test(); print(test.__name__+': OK')
