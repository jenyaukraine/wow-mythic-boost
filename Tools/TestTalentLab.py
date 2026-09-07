"""Talent samples use real Contracts and RunStats: boundaries, privacy and bounded storage."""
from TestRunStats import fixture as stats_fixture
from TestSocialWorkflows import load


def fixture():
    lua = stats_fixture()
    lua.execute(r'''
        configID=7; treeReads=0; sourceReads=0; sourceBlocked={}
        function GetSpecialization() return 1 end
        function GetSpecializationInfo() return 105 end
        function GetBuildInfo() return '12.1.0','67890','Sep 2026',120100 end
        C_ClassTalents={GetActiveConfigID=function() return configID end,
            GetActiveHeroTalentSpec=function() return 33 end}
        C_Traits={
            ConfigHasStagedChanges=function() return staged or false end,
            GetConfigInfo=function(id) treeReads=treeReads+1; return {name='Build '..id,treeIDs={11,12}} end,
            GetTreeNodes=function(id) return id==11 and {1,2} or {3} end,
            GetNodeInfo=function(_,id) return nodes[id] end,
            GetEntryInfo=function(_,id) return {definitionID=id} end,
            GetDefinitionInfo=function(id) return {spellID=talentIDs[id]} end,
        }
        talentIDs={[1]=155675,[2]=200390,[3]=145205,[4]=999999}
        nodes={[1]={activeRank=1,activeEntry={entryID=1}},
            [2]={activeRank=0},[3]={activeRank=1,activeEntry={entryID=3}}}
        function SetSources(h,d)
            src={[2]={totalAmount=h,combatSpells={{spellID=155777,totalAmount=h}}},
                [0]={totalAmount=d,combatSpells={{spellID=5176,totalAmount=d}}}}
        end
        C_DamageMeter.GetCombatSessionSourceFromType=function(session,kind,guid,pet)
            assert(not combat and session==0 and guid=='Player-Alice' and pet==nil)
            sourceReads=sourceReads+1
            if sourceBlocked[kind] then return Secret({}) end
            return src[kind]
        end
        C_DamageMeter.GetCombatSessionFromType=function(session,kind)
            assert(not combat and session==0)
            if blocked[kind] then return Secret({}) end
            local value=kind==8 and 0 or src[kind].totalAmount
            return {durationSeconds=durations[kind],combatSources={
                {sourceGUID='Player-Alice',totalAmount=value},
                {sourceGUID='Player-Bob',totalAmount=0}}}
        end
        function NativeSample(h,d,dur)
            SetSources(h,d); durations={[0]=dur,[2]=dur,[8]=dur}
        end
        function Stats(h,d,dur)
            return {duration=dur,players={['Player-Alice']={healing=h,damage=d}},
                meters={healing={last={},readable=true},damage={last={},readable=true}}}
        end
        function Count(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end
        SetSources(0,0)
    ''')
    load(lua, 'Data/TalentSources.lua')
    load(lua, 'Modules/TalentLab.lua')
    lua.execute('lab=JP.TalentLab')
    return lua


def test_actual_collector_and_immutable_build():
    lua=fixture()
    lua.execute(r'''
        NativeSample(1000,2000,40); run=NewRun(); s:Start(run)
        assert(lab.build.gameBuild=='12.1.0:67890' and Count(lab.build.selected)==2)
        assert(treeReads==1)
        NativeSample(1300,2600,50); s:Snapshot()
        assert(lab.values.healing[155777]==300 and treeReads==1)
        NativeSample(1600,3200,60); result=Result(); s:Finish(run,result); Tick(.5)
        local a=result.talentSample
        assert(a.complete and a.duration==20 and a.overallHealing==600)
        assert(a.spells.healing[155777]==600 and a.spells.damage[5176]==1200)
        assert(a.selected[1].spellID==155675)
        local rows=lab:TalentRows(a,'healing')
        assert(rows[1].talentSpellID==155675 and rows[1].amount==600)
        assert(rows[2].talentSpellID==145205 and rows[2].amount==0,'complete observed zero is distinct from unknown')
        configID=8; nodes[1].activeEntry.entryID=4
        lab:BuildChanged(); NativeSample(1700,3300,65); s:Snapshot()
        assert(result.talentSample.complete and result.talentSample.selected[1].spellID==155675,
            'post-key talent changes cannot relabel the recorded build')
        assert(a.spells.healing[155777]==600 and a.selected[1].spellID==155675,'snapshot is copied')
        Drain(); assert(not lab.run and not lab.values and not s.players)
    ''')


def test_weighted_compare_and_compatibility():
    lua=fixture()
    lua.execute(r'''
        function Sample(h,d,dur,cfg)
            configID=cfg or 7; SetSources(100,200); local run=NewRun(); lab:Begin(run)
            SetSources(100+h,200+d); lab:Snapshot(run)
            local out=Result(); lab:Finish(run,out,Stats(h,d,dur)); lab:Stop()
            assert(out.talentSample.complete); return out
        end
        a=Sample(100,300,10); b=Sample(200,400,30,8)
        assert(a.talentSample.buildKey==b.talentSample.buildKey,'same build with a different saved name groups together')
        nodes[1].activeEntry.entryID=4; c=Sample(300,600,20)
        d=Sample(300,600,20); d.talentSample.mapID=1
        e=Sample(300,600,20); e.talentSample.gameBuild='12.2.0:70000'
        f=Sample(300,600,20); f.talentSample.complete=false
        g=Sample(300,600,20); g.talentSample.mixed=true
        local cmp=lab:Compare({c,b,a,d,e,f,g},'healing')
        assert(#cmp.builds==4 and cmp.builds[1].runs==1)
        assert(cmp.builds[2].runs==2 and cmp.builds[2].duration==40)
        assert(cmp.builds[2].rows[1].amount==300 and cmp.builds[2].rows[1].rate==7.5)
        local talent=lab:TalentRows(c.talentSample,'healing')
        local unknown; for _,row in ipairs(talent) do if row.spellID==999999 then unknown=row end end
        assert(unknown and unknown.kind=='unattributed' and unknown.amount==nil,'do not invent passive gain')
    ''')


def test_missing_secret_reset_and_build_change():
    lua=fixture()
    lua.execute(r'''
        sourceBlocked[2]=true; run=NewRun(true); lab:Begin(run)
        sourceBlocked[2]=nil; SetSources(10000,200); lab:Snapshot(run)
        SetSources(10200,400); lab:Snapshot(run)
        assert(lab.values.healing[155777]==200 and lab.partial,'late initial baseline excludes old total')
        lab:Reset(); SetSources(50,70); lab:Snapshot(run)
        assert(lab.values.healing[155777]==250 and lab.partial,'reset preserves collected public totals')
        nodes[1].activeEntry.entryID=4; lab:BuildChanged(); lab:Snapshot(run)
        assert(lab.mixed and lab.partial)
        local result=Result(); lab:Finish(run,result,Stats(250,270,20)); assert(not result.talentSample.complete)
        lab:Stop(); disabled=true; local before=sourceReads; lab:Begin(NewRun()); lab:Snapshot(lab.run)
        assert(lab.partial and sourceReads==before,'disabled native meter is not a zero sample')
        lab:Stop(); disabled=false; combat=true; before=sourceReads; local trees=treeReads
        lab:Begin(NewRun()); lab:Snapshot(lab.run)
        assert(sourceReads==before and treeReads==trees and not lab.build,'no secret reads in combat')
        lab:Stop(); combat=false
        for _,bad in ipairs({Secret(10),0/0,math.huge,-1}) do
            SetSources(0,0); lab:Begin(NewRun())
            src[2]={totalAmount=bad,combatSpells={}}
            lab:Snapshot(lab.run); assert(lab.partial); lab:Stop()
        end
        for _,bad in ipairs({Secret(155777),0,1.5}) do
            SetSources(0,0); lab:Begin(NewRun())
            src[2]={totalAmount=10,combatSpells={{spellID=bad,totalAmount=10}}}
            lab:Snapshot(lab.run); assert(lab.partial); lab:Stop()
        end
        SetSources(0,0); lab:Begin(NewRun())
        src[2]={totalAmount=999,combatSpells={{spellID=155777,totalAmount=10}}}
        lab:Snapshot(lab.run); assert(lab.partial and not next(lab.values.healing))
        local out=Result(); lab:Finish(lab.run,out,Stats(10,0,10)); assert(not out.talentSample.complete)
    ''')


def test_bounds_collectibility_and_integrity():
    lua=fixture()
    lua.execute(r'''
        SetSources(0,0); lab:Begin(NewRun())
        local spells={}; for i=1,256 do spells[i]={spellID=i,totalAmount=1} end
        src[2]={totalAmount=256,combatSpells=spells}; lab:Snapshot(lab.run)
        assert(Count(lab.values.healing)==256)
        spells={}; for i=257,512 do spells[#spells+1]={spellID=i,totalAmount=1} end
        src[2]={totalAmount=256,combatSpells=spells}; lab:Snapshot(lab.run)
        assert(Count(lab.values.healing)==256 and lab.partial,'cap applies across all session reads')
        lab:Stop(); SetSources(0,0)
        local allocated=allocations; local weak=setmetatable({},{__mode='v'})
        for i=1,1000 do
            lab:Begin(NewRun()); weak[i]=lab.values; lab:Stop()
        end
        collectgarbage('collect'); assert(next(weak)==nil and allocations==allocated)
        assert(#timers==0,'no standalone sampling timers')
        for _,reason in ipairs({'partial','durationUnknown','totalMismatch'}) do
            SetSources(0,0); local run=NewRun(); lab:Begin(run)
            SetSources(100,200); lab:Snapshot(run)
            local stats=Stats(100,200,10)
            if reason=='partial' then stats.meters.healing.partial=true
            elseif reason=='durationUnknown' then stats.durationUnknown=true
            else stats.players['Player-Alice'].healing=1000 end
            local out=Result(); lab:Finish(run,out,stats)
            assert(not out.talentSample.complete,reason); lab:Stop()
        end
    ''')


def test_applied_not_preview_and_active_hero_only():
    lua=fixture()
    lua.execute(r'''
        staged=true; lab:Begin(NewRun()); assert(not lab.build and lab.partial)
        lab:Stop(); staged=false
        nodes[3].subTreeID=44; nodes[3].subTreeActive=false
        lab:Begin(NewRun()); assert(Count(lab.build.selected)==1,'inactive hero tree must not enter build')
        lab:Stop(); nodes[3].subTreeID=33; nodes[3].subTreeActive=true
        lab:Begin(NewRun()); assert(Count(lab.build.selected)==2)
        lab:Stop(); nodes[1].entryIDsWithCommittedRanks={4}
        lab:Begin(NewRun()); assert(not lab.build,'contradictory preview/committed state is not measured build')
    ''')


def test_observed_run_comparison():
    lua=fixture()
    lua.execute('''
        local a={talentSample={mapID=250,level=10,gameBuild='test',specID=105,
            overallHealing=2000,duration=20,complete=false,mixed=false}}
        local b={talentSample={mapID=250,level=10,gameBuild='test',specID=0,
            overallHealing=500,duration=10,complete=false,mixed=true}}
        local result=lab:ObservedComparison({a,b},a,'healing')
        assert(result.current==100 and result.previous==50 and result.percent==100 and result.uncertain)
        b.talentSample.duration=0; assert(lab:ObservedComparison({a,b},a,'healing')==nil)
        b.talentSample.duration=10; b.talentSample.level=11
        assert(lab:ObservedComparison({a,b},a,'healing')==nil)
    ''')


def test_loading_specialization_does_not_create_zero_or_mixed_build():
    lua=fixture()
    lua.execute('''
        local ready=false
        C_SpecializationInfo={IsInitialized=function() return ready end,
            GetSpecialization=function() return 1 end,
            GetSpecializationInfo=function() return 105 end}
        GetSpecialization=nil; GetSpecializationInfo=nil
        NativeSample(0,0,0); run=NewRun(); s:Start(run)
        assert(not lab.build)
        ready=true; NativeSample(500,100,10); s:Snapshot()
        assert(lab.build.specID==105 and not lab.mixed and lab.values.healing[155777]==500)
        lab:BuildChanged(); s:Snapshot(); assert(not lab.mixed)
        C_SpecializationInfo.GetSpecializationInfo=function() return 0 end
        lab:BuildChanged(); s:Snapshot()
        assert(lab.build.specID==105 and not lab.mixed)
        C_SpecializationInfo.GetSpecializationInfo=function() return 105 end
        nodes[1].activeEntry.entryID=4; lab:BuildChanged(); s:Snapshot()
        assert(lab.mixed,'an actual applied change remains mixed')
    ''')


def test_reload_keeps_totals_sources_and_boundaries():
    lua=fixture()
    lua.execute('''
        function Key(resumed)
            local run=NewRun(resumed)
            run.nativeStart=100; run.mapID=399; run.level=12
            return run
        end
        NativeSample(1000,2000,40); run=Key(); s:Start(run)
        NativeSample(1500,2200,50); s:Snapshot()
        saved=db.runHistory.activeStats
        assert(saved.talent.values.healing[155777]==500 and saved.duration==10)
        assert(saved.talent.values.healing~=lab.values.healing,'no mutable collector references')
        assert(saved.players['Player-Alice'].name==nil,'private checkpoint does not store names')
    ''')
    # Recreate the collectors against the same SavedVariables, as /reload does.
    load(lua,'Modules/RunStats.lua'); load(lua,'Modules/TalentLab.lua')
    lua.execute('''
        s=JP.RunStats; lab=JP.TalentLab
        NativeSample(1800,2600,60); run=Key(true); s:Start(run)
        assert(s.restored and s.duration==20)
        assert(lab.values.healing[155777]==800 and s.players['Player-Alice'].healing==800)
        for i=1,10 do s:Snapshot() end
        assert(s.duration==20 and lab.values.healing[155777]==800,'no duplicate post-reload totals')
        assert(not lab.mixed,'same tree does not become mixed after reload')
        NativeSample(2000,2800,70); result=Result(); s:Finish(run,result)
        assert(result.talentSample.overallHealing==800,'finish publishes the current sample immediately')
        Tick(.5)
        assert(result.talentSample.overallHealing==1000 and result.talentSample.duration==30)
        assert(result.talentSample.spells.healing[155777]==1000 and not result.talentSample.complete)
        assert(db.runHistory.activeStats==nil,'completion consumes checkpoint')
        s:Stop(); db.runHistory.activeStats=saved
        NativeSample(5000,6000,10); run=Key(true); s:Start(run)
        assert(s.restored and lab.values.healing[155777]==5500)
        assert(s.players['Player-Alice'].healing==5500,'a meter reset during reload resets both baselines')
        s:Stop(); db.runHistory.activeStats=saved
        local nextRun=Key(true); nextRun.nativeStart=101
        s:Start(nextRun); assert(not s.restored and s.duration==0 and (lab.values.healing[155777] or 0)==0)
        s:Stop(); db.runHistory.activeStats=saved; saved.guid='Player-Other'
        s:Start(Key(true)); assert(not s.restored,'do not restore another character')
        s:Stop(); saved.guid='Player-Alice'; db.runHistory.activeStats=saved
        saved.talent.values.healing[155777]=Secret(1000)
        s:Start(Key(true)); assert(not s.restored and s.duration==0,'invalid checkpoint fails atomically')
        s:Stop(); saved.talent.values.healing[155777]=500; db.runHistory.activeStats=saved
        saved.at=time()-50000
        s:Start(Key(true)); assert(not s.restored,'expired checkpoint is discarded')
    ''')


def test_legacy_spec_recovery_requires_same_recorded_tree():
    lua=fixture()
    lua.execute('''
        local run=NewRun(); lab:Begin(run)
        local good=Result(); lab:Finish(run,good,Stats(0,0,10))
        local broken={}; for k,v in pairs(good.talentSample) do broken[k]=v end
        broken.specID=0; broken.buildKey=broken.buildKey:gsub('^105|','0|')
        broken.spells={healing={[81269]=162612},damage={}}
        broken.mixed=true; broken.complete=false; broken.duration=18
        local fixed=lab:ResolveSample(broken,{good})
        assert(fixed~=broken and fixed.specID==105 and broken.specID==0)
        assert(fixed.mixed and not fixed.complete and fixed.duration==18,'never rewrite recorded uncertainty/time')
        assert(lab:TalentRows(fixed,'healing')[1].amount==162612)
        assert(lab:ResolveSample(broken,{})==broken)
        good.talentSample.gameBuild='other'; assert(lab:ResolveSample(broken,{good})==broken)
        good.talentSample.gameBuild=broken.gameBuild
        good.talentSample.buildKey=good.talentSample.buildKey..';4:4:1'
        assert(lab:ResolveSample(broken,{good})==broken,'a different tree cannot infer specialization')
    ''')


def test_world_entry_waits_for_player_and_checkpoint_stays_bounded():
    lua=fixture()
    load(lua,'Modules/RunHistory.lua')
    lua.execute('''
        IsLoggedIn=function() return false end
        UnitClass=function() return 'Druid','DRUID' end
        JP.API.GetActiveChallenge=function() return {active=true,mapID=399,level=12,startedAt=100} end
        local history=JP.RunHistory
        history:Create(); history:Enable()
        assert(history.current==nil and history.events.events.PLAYER_ENTERING_WORLD)
        history.events.scripts.OnEvent(nil,'PLAYER_ENTERING_WORLD')
        assert(history.current and s.run==history.current and history.current.nativeStart==100)
        local current=history.current
        history.events.scripts.OnEvent(nil,'PLAYER_ENTERING_WORLD')
        assert(history.current==current,'zone loads do not restart the current key')
        NativeSample(100,200,50); s:Snapshot()
        collectgarbage('collect'); local before=collectgarbage('count')
        for i=1,1000 do s:Snapshot() end
        collectgarbage('collect')
        assert(collectgarbage('count')-before<64,'only one bounded checkpoint survives')
        history:DiscardRun(); assert(db.runHistory.activeStats==nil)
    ''')


if __name__=='__main__':
    test_observed_run_comparison()
    for test in [test_actual_collector_and_immutable_build,test_weighted_compare_and_compatibility,
                 test_missing_secret_reset_and_build_change,test_bounds_collectibility_and_integrity,
                 test_applied_not_preview_and_active_hero_only,
                 test_loading_specialization_does_not_create_zero_or_mixed_build,
                 test_reload_keeps_totals_sources_and_boundaries,
                 test_legacy_spec_recovery_requires_same_recorded_tree,
                 test_world_entry_waits_for_player_and_checkpoint_stays_bounded]:
        test(); print(test.__name__+': OK')
