"""Marginal constant-multiplier scenarios, provenance, unknowns and native UI."""
from TestTalentTreeStats import fixture as base
from TestSocialWorkflows import load


def fixture():
    lua = base()
    for path in ('Data/TalentSources.lua', 'Data/TalentPointModels.lua',
                 'Modules/TalentPointValue.lua', 'Modules/TalentPointUI.lua'):
        load(lua, path)
    lua.execute('''
        points=JP.TalentPointValue
        function GetSpecializationInfo() return 105 end
        function GetBuildInfo() return '12.1.0','69587' end
        function frame:GetSpecID() return 105 end
        function sample(key,selected,spells,total,complete)
            return {specID=105,gameBuild='12.1.0:69587',buildKey=key,buildName=key,
                selected=selected,spells={healing=spells},overallHealing=total,
                complete=complete,mixed=false,mapID=1,level=10,duration=100}
        end
        picked={[1]={spellID=470549,entryID=1,rank=1},[2]={spellID=429402,entryID=2,rank=1}}
        local a=sample('A',picked,{[18562]=130,[8936]=70,[48438]=100,[774]=700},1000,true)
        local b=sample('A',picked,{[18562]=390,[8936]=210,[48438]=300,[774]=3100},4000,true)
        local other=sample('B',{}, {[18562]=900},900,true)
        db.runHistory.runs={{completedAt=200,talentSample=a},{completedAt=100,talentSample=b},
            {completedAt=300,talentSample=other}}
        current={specID=105,gameBuild=a.gameBuild,buildKey='A',configID=7}
        lab.CurrentBuild=function() return current end
        function ctx() return points:Context(db.runHistory.runs,'healing',105,'12.1.0:69587',current) end
        C_Traits.GetDefinitionInfo=function(id) return {spellID=({470549,429402,439926})[id]} end
        C_Traits.CanRefundRank=function() return true end
        C_Traits.CanPurchaseRank=function() return false end
        for i,node in ipairs(nodes) do
            node.ID=i; node.entryIDs={i}; node.isAvailable=true; node.meetsEdgeRequirements=true
            node.ranksPurchased=i==3 and 0 or 1
        end
    ''')
    return lua


def test_marginal_math_cohort_and_range():
    lua=fixture()
    lua.execute('''
        local c=ctx(); assert(c.current and #c.records==2 and c.total==5000)
        local d=points:Evaluate(c,470549,'healing')
        assert(d.selected and d.rank==1 and d.amount==520)
        assert(math.abs(d.percent-2.4)<1e-9,'remove 30% boost divides by 1.3; not 30% of overall')
        assert(math.abs(d.min-2.25)<1e-9 and math.abs(d.max-3)<1e-9,'per-run range, not confidence interval')
        local add=points:Evaluate(c,439926,'healing')
        assert(not add.selected and math.abs(add.percent-7.6)<1e-9,'add only affects Rejuvenation here')
        assert(points:Evaluate(c,429402,'healing').percent~=d.percent,'different talents do not inherit cohort HPS delta')
        assert(points:Evaluate(c,470549,'damage')==nil,'healing coefficient cannot leak into DPS')
        assert(points:Evaluate(c,207383,'healing')==nil,'conditional talent must remain unknown')
        assert(points:Describe(d,c,'healing'):find('130',1,true)==nil or d.factor<.30)
        table.insert(db.runHistory.runs,1,db.runHistory.runs[1]); assert(#ctx().records==2,'deduplicate saved runs')
        current.buildKey='unrecorded'; c=ctx(); assert(not c.current and c.sample.buildKey=='B')
        local info=points:Describe(points:Evaluate(c,470549,'healing'),c,'healing')
        assert(info:find('сохранённой сборке',1,true),'fallback build must be explicit')
    ''')


def test_partial_zero_malformed_and_version():
    lua=fixture()
    lua.execute('''
        db.runHistory.runs={db.runHistory.runs[1]}
        local s=db.runHistory.runs[1].talentSample
        s.spells.healing={[774]=1000}
        assert(points:Evaluate(ctx(),470549,'healing').percent==0,'complete absence is a measured zero')
        s.complete=false
        assert(points:Evaluate(ctx(),470549,'healing')==nil,'partial absence is unknown')
        s.spells.healing[18562]=130; s.overallHealing=1500
        local d=points:Evaluate(ctx(),470549,'healing'); assert(d.partial and math.abs(d.percent-2)<1e-9)
        s.overallHealing=true; assert(ctx()==nil,'boolean overall cannot enter arithmetic')
        s.overallHealing=1500; s.spells.healing[18562]=true; assert(ctx()==nil)
        s.spells.healing[18562]=130; s.mixed=true; assert(ctx()==nil)
        s.mixed=false; s.gameBuild='12.1.1:99999'
        local c=points:Context(db.runHistory.runs,'healing',105,s.gameBuild,current)
        assert(points:Evaluate(c,470549,'healing')==nil,'unknown patch cannot reuse coefficients')
        s.gameBuild='12.1.0:69587'; s.selected[1].rank=2
        assert(points:Evaluate(ctx(),470549,'healing')==nil,'unverified rank is not extrapolated')
    ''')


def test_point_ui_tree_navigation_and_lifecycle():
    lua=fixture()
    lua.execute('''
        lab:ShowPoints('healing')
        assert(lab.view=='points' and lab.pointContext.current and lab.uiFrame.shown)
        assert(lab.rows[1].shown and lab.rows[1].meta.shown)
        assert(lab.rows[1].rate.text~='—','passive model shows its affected spell share without a separate source')
        assert(lab.uiBuild.width==302,'build label must stop before the point button')
        local count=allocations
        for i=1,20 do lab:Render() end
        assert(count==allocations,'reuse row pool')
        lab.allTalentsButton.scripts.OnClick(); assert(lab.pointFilter==2)
        lab.rows[1].scripts.OnEnter(); assert(tooltip.lines[1]:find('Модель:',1,true))
        lab.allTalentsButton.scripts.OnClick(); assert(lab.pointFilter==3)
        lab.pointFilter=1
        tree:Refresh()
        assert(tree.cards[1].text.text:sub(1,1)=='~' and tree.cards[1].detail:find('Модель:',1,true))
        tree.openButton.scripts.OnClick(); assert(lab.view=='points')
        tree.shareMode.scripts.OnClick(); assert(tree.mode=='shares')
        tree.openButton.scripts.OnClick(); assert(lab.view=='talents')
        tree.pointMode.scripts.OnClick(); tree.cards[1].badge.scripts.OnClick(); assert(lab.view=='points')
        tree:Enable(); tree.events.scripts.OnEvent(nil,'TRAIT_CONFIG_UPDATED')
        assert(not tree.pointContextCached,'config changes invalidate reference build')
        combat=true; tree:Refresh(); assert(not tree.cards[1].shown)
        tree:Disable(); assert(not tree.pointContextCached)
        assert(points:Availability(7,{ID=1,ranksPurchased=0},1,true,true)=='Выдано бесплатно')
        assert(points:Availability(7,{ID=1,ranksPurchased=1},1,true,true)=='Можно снять очко')
        assert(points:Availability(7,{ID=1,isAvailable=false},1,true,false)=='Сначала открой путь')
    ''')


def main():
    test_marginal_math_cohort_and_range()
    test_partial_zero_malformed_and_version()
    test_point_ui_tree_navigation_and_lifecycle()
    print('Talent point model tests OK: marginal math, same cohort, patch/rank gates, zero/unknown and UI')


if __name__ == '__main__':
    main()
