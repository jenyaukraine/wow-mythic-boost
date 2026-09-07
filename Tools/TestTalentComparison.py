"""Descriptive with/without cohorts, confounding, malformed data and UI routing."""
from TestTalentLab import fixture as collector_fixture
from TestTalentLabUI import fixture as ui_fixture
from TestSocialWorkflows import load


def fixture():
    lua=collector_fixture()
    load(lua,'Modules/TalentComparison.lua')
    lua.execute('''
        function Run(at,rate,has,rank)
            return {completedAt=at,members={'Alice-Realm','Bob-Realm'},mapID=250,level=10,mapName='Temple',
                talentSample={mapID=250,level=10,specID=105,gameBuild='12.1.0:69587',buildKey=has and 'with' or 'without',
                    complete=true,mixed=false,duration=100,overallHealing=rate*100,overallDamage=0,
                    selected={ [1]={entryID=1,rank=1,spellID=100},
                        [2]=has and {entryID=2,rank=rank or 1,spellID=200} or nil }}}
        end
        function Row(context,id,rank)
            for _,row in ipairs(context.rows) do
                if row.spellID==id and row.rank==(rank or 1) then return row end
            end
        end
    ''')
    return lua


def test_cohort_means_spread_counts_and_other_changes():
    lua=fixture()
    lua.execute('''
        local a,b,c,d=Run(4,120,true),Run(3,180,true),Run(2,80,false),Run(1,120,false)
        a.talentSample.duration=200; a.talentSample.overallHealing=24000
        b.talentSample.selected[3]={entryID=3,rank=1,spellID=300}
        b.members={'Alice-Realm','Other-Realm'}
        local context=lab:CompareTalents({a,b,c,d},'healing').contexts[1]
        local row=Row(context,200)
        assert(row.with.mean==150 and row.without.mean==100 and row.percent==50)
        assert(row.with.runs==2 and row.without.runs==2 and row.with.hasSpread)
        assert(row.with.min==120 and row.with.max==180)
        assert(row.otherChangesMin==0 and row.otherChangesMax==1 and row.rosterChanged)
        assert(not Row(context,100).comparable,'always selected cannot be compared to fabricated absence')
        assert(row.smallSample and not row.partial)
    ''')


def test_partial_mixed_rank_dedup_and_context_isolation():
    lua=fixture()
    lua.execute('''
        local a,b,c=Run(3,120,true),Run(2,80,false),Run(1,900,true,2)
        b.talentSample.complete=false
        local mixed=Run(4,99999,true); mixed.talentSample.mixed=true
        local map=Run(5,99999,true); map.talentSample.mapID=399
        local level=Run(6,99999,true); level.talentSample.level=11
        local spec=Run(7,99999,true); spec.talentSample.specID=104
        local patch=Run(8,99999,true); patch.talentSample.gameBuild='other'
        local result=lab:CompareTalents({a,b,c,mixed,map,level,spec,patch,a},'healing')
        assert(#result.contexts==5 and result.excluded.mixed==1)
        local row=Row(result.contexts[1],200)
        assert(row.with.runs==1 and row.without.runs==1 and row.with.mean==120)
        assert(row.partial and not row.with.hasSpread and row.percent==50)
        assert(Row(result.contexts[1],200,2).with.mean==900,'other ranks are separate cohorts')
        b.talentSample.overallHealing=0
        row=Row(lab:CompareTalents({a,b},'healing').contexts[1],200)
        assert(row.comparable and row.percent==nil and row.delta==120,'zero baseline is no infinite percent')
        for _,bad in ipairs({Secret(100),0/0,math.huge,-1,'100'}) do
            b.talentSample.overallHealing=bad
            local result=lab:CompareTalents({a,b},'healing')
            assert(result.excluded.invalid==1 and result.contexts[1].pairs==0)
        end
    ''')


def test_unknown_nodes_and_no_mutation_or_source_dependency():
    lua=fixture()
    lua.execute('''
        local a,b=Run(2,100,true),Run(1,50,false)
        a.talentSample.selected[99]={entryID=99,rank=1}
        b.talentSample.selected[99]={entryID=99,rank=1}
        local row=Row(lab:CompareTalents({a,b},'healing').contexts[1],200)
        assert(row.percent==100,'hero selector without spell does not invalidate known talents')
        b.talentSample.selected[2]={entryID=2,rank=1}
        row=Row(lab:CompareTalents({a,b},'healing').contexts[1],200)
        assert(not row.comparable and row.without.runs==0,'unknown talent at the same node is not absence')
        assert(a.talentSample.spells==nil and b.talentSample.specID==105)
        assert(#lab:CompareTalents(Secret({}),'healing').contexts==0)
        local runs={}; for i=1,100 do runs[i]=Run(i,100,i%2==0) end
        assert(lab:CompareTalents(runs,'healing').contexts[1].runs==30)
        a.talentSample.selected[2]={entryID=2,rank=4,spellID=1244470}
        b.talentSample.selected[2]={entryID=3,rank=3,spellID=1244331}
        local context=lab:CompareTalents({a,b},'healing').contexts[1]
        assert(not Row(context,1244331,4).comparable,'earlier apex tier is not absence of that talent')
    ''')


def test_zero_duration_saved_run_does_not_crash_comparison():
    lua=fixture()
    lua.execute('''
        local zero,a,b=Run(3,0,true),Run(2,120,true),Run(1,80,false)
        zero.talentSample.duration=0
        local result=lab:CompareTalents({zero,a,b},'healing')
        assert(result.excluded.invalid==1 and #result.contexts==1)
        assert(result.contexts[1].runs==2 and Row(result.contexts[1],200).percent==50)
        assert(lab:CompareTalents({zero},'damage').excluded.invalid==1)
    ''')


def test_ui_comparison_is_reachable_and_restores_source_rows():
    lua=ui_fixture()
    load(lua,'Modules/TalentLab.lua'); load(lua,'Modules/TalentComparison.lua'); load(lua,'Modules/TalentLabUI.lua')
    lua.execute('''
        lab=JP.TalentLab
        for _,run in ipairs(db.runHistory.runs) do
            run.talentSample.mapID=run.mapID; run.talentSample.level=run.level
            for id,entry in pairs(run.talentSample.selected) do entry.entryID=id end
        end
        lab:Show(); lab.comparisonButton.scripts.OnClick()
        assert(lab.view=='comparison' and lab.keyPicker.text=='Выбрать условия')
        assert(lab.amountHeader.text=='С талантом' and lab.rateHeader.text=='Без таланта')
        assert(lab.rows[1].shown and lab.rows[1].height==44 and lab.rows[1].meta.shown)
        lab.rows[1].scripts.OnEnter(); assert(tooltip.lines[1]:find('Диапазон:',1,true))
        assert(lab.rows[1].share.text~='—')
        lab.keyPicker.scripts.OnClick(); assert(lab.keyPickerMenu.shown)
        lab.keyPickerOptions[1].scripts.OnClick(); assert(not lab.keyPickerMenu.shown)
        lab.allTalentsButton.scripts.OnClick(); local created=allocations
        for i=1,500 do lab:Render() end
        assert(allocations==created,'comparison reuses the existing list and picker')
        lab.sourceButton.scripts.OnClick()
        assert(lab.view=='sources' and lab.rows[1].height==31 and not lab.rows[1].meta.shown)
        assert(lab.rows[1].comparisonDetail==nil and lab.shareHeader.text=='Доля')
        lab.uiFrame.scripts.OnHide(); assert(lab.comparisonContexts==nil)
    ''')


if __name__=='__main__':
    for test in (test_zero_duration_saved_run_does_not_crash_comparison,test_cohort_means_spread_counts_and_other_changes,
                 test_partial_mixed_rank_dedup_and_context_isolation,
                 test_unknown_nodes_and_no_mutation_or_source_dependency,
                 test_ui_comparison_is_reachable_and_restores_source_rows):
        test(); print(test.__name__+': OK')
