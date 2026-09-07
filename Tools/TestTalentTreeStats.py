from TestTalentLabUI import fixture as ui_fixture
from TestSocialWorkflows import load


def fixture():
    lua = ui_fixture()
    load(lua, 'Modules/TalentLab.lua')
    load(lua, 'Modules/TalentComparison.lua')
    load(lua, 'Modules/TalentLabUI.lua')
    load(lua, 'Modules/TalentContributionUI.lua')
    load(lua, 'Modules/TalentTreeStats.lua')
    lua.execute('''
        lab=JP.TalentLab; tree=JP.TalentTreeStats
        function GetSpecialization() return 1 end
        function GetSpecializationInfo() return 1 end
        function GetBuildInfo() return '12.0','123' end
        for _,run in ipairs(db.runHistory.runs) do
            local sample=run.talentSample
            sample.gameBuild='12.0:123'; sample.mapID=run.mapID; sample.level=run.level
            for id,entry in pairs(sample.selected) do entry.entryID=id end
        end
        PlayerSpellsFrame=NewWidget(UIParent)
        frame=NewWidget(PlayerSpellsFrame); PlayerSpellsFrame.TalentsFrame=frame
        frame:Show(); frame:SetFrameLevel(100)
        function frame:IsInspecting() return inspecting or false end
        function frame:GetConfigID() return 7 end
        function frame:GetSpecID() return 1 end
        buttons={}
        for i=1,3 do
            local button=NewWidget(frame); button:Show()
            function button:GetEntryID() return i end
            buttons[i]=button
        end
        function frame:GetTalentButtonByNodeID(id) return buttons[id] end
        nodes={{activeRank=0},{activeRank=1,activeEntry={entryID=2}}, {activeRank=1,activeEntry={entryID=3}}}
        C_Traits={GetConfigInfo=function() return {treeIDs={1}} end,
            GetTreeNodes=function() return {1,2,3} end,
            GetNodeInfo=function(_,id) return nodes[id] end,
            GetEntryInfo=function(_,id) return {definitionID=id} end,
            GetDefinitionInfo=function(id) return {spellID=1000+id} end}
    ''')
    return lua


def test_weighting_and_unknowns():
    lua=fixture()
    lua.execute('''
        local shares=lab:HistoricalShares(db.runHistory.runs,'healing',1,'12.0:123')
        assert(math.abs(shares['1001:1'].percent-56)<.00001 and shares['1001:1'].runs==2)
        assert(shares['1003:1'].percent==40, 'missing attribution must not dilute share')
        db.runHistory.runs[2].talentSample.complete=false
        shares=lab:HistoricalShares(db.runHistory.runs,'healing',1,'12.0:123')
        assert(shares['1001:1'].percent==50 and shares['1001:1'].runs==1)
        db.runHistory.runs[3].talentSample.mixed=true
        shares=lab:HistoricalShares(db.runHistory.runs,'healing',1,'12.0:123')
        assert(shares['1001:1']==nil)
        assert(next(lab:HistoricalShares(db.runHistory.runs,'healing',2,'12.0:123'))==nil)
        assert(next(lab:HistoricalShares(db.runHistory.runs,'healing',1,'other'))==nil)
    ''')


def test_partial_observations_are_not_recommendations():
    lua=fixture()
    lua.execute('''
        tree.mode='shares'
        db.runHistory.runs={db.runHistory.runs[1]}
        local sample=db.runHistory.runs[1].talentSample
        sample.complete=false
        assert(next(lab:HistoricalShares(db.runHistory.runs,'healing',1,'12.0:123'))==nil)
        tree:Refresh()
        assert(tree.cards[2].text.text=='~60.0%' and tree.cards[2].border[1]==1)
        nodes[2].activeRank=0
        tree:Refresh(); assert(tree.cards[2].text.text=='~60.0%', 'recorded contribution is descriptive even if currently unselected')
        sample.overallHealing=60000; tree:ReleaseHistory(); tree:Refresh()
        assert(tree.cards[3].text.text=='~33.3%','partial source amount uses the recorded overall denominator')
        sample.overallHealing=50000; sample.mixed=true
        tree:ReleaseHistory(); tree:Refresh(); assert(tree.cards[3].text.text=='—')
    ''')


def test_tree_colors_preview_and_lifecycle():
    lua=fixture()
    lua.execute('''
        tree.mode='shares'
        tree:Refresh()
        assert(#tree.cards==3)
        assert(tree.cards[1].text.text=='56.0%' and tree.cards[1].border[3]==1)
        assert(tree.cards[2].text.text=='60.0%' and tree.cards[2].border[2]==.95)
        assert(tree.cards[2].parent==buttons[2])
        assert(tree.cards[2].strata==buttons[2].strata and tree.cards[2].level==buttons[2].level+1,
            'talent decorations follow their own button layer, not a global dialog')
        assert(tree.legend.parent==frame and tree.legend.strata==frame.strata)
        nodes[2].activeRank=2
        tree:Refresh(); assert(not tree.cards[2].shown, 'unknown ranks have no grey rectangle or dash')
        nodes[1].activeRank=1; nodes[1].activeEntry={entryID=1}
        tree:Refresh(); assert(tree.cards[1].border[2]==.95, 'staged selection updates color')
        tree.metricButtons.damage.scripts.OnClick(); assert(tree.cards[1].text.text=='—')
        inspecting=true; tree:Refresh(); assert(not tree.cards[1].shown and not tree.legend.shown)
        inspecting=false; combat=true; tree:Refresh(); assert(not tree.cards[1].shown)
        combat=false; tree:Enable(); tree.driver.scripts.OnUpdate(tree.driver,.6)
        assert(not tree.cards[1].shown,'unknown talents have no floating placeholder')
        tree.driver.scripts.OnHide(); assert(not tree.cards[1].shown)
        tree:Disable(); assert(tree.driver.scripts.OnUpdate==nil)
    ''')


def test_tree_reuses_driver_and_releases_cached_history():
    lua=fixture()
    lua.execute('''
        tree.mode='shares'
        local histories=0
        local original=lab.HistoricalShares
        lab.HistoricalShares=function(...) histories=histories+1; return original(...) end
        tree:Enable(); tree:Refresh()
        local created=allocations; local driver=tree.driver
        tree.cards[1].badge.scripts.OnEnter()
        local tip=tooltip
        for i=1,1000 do tree.driver.scripts.OnUpdate(tree.driver,.6) end
        assert(histories==1, 'do not recalculate thirty keys every half second')
        assert(tooltip==tip, 'visible tooltip survives regular refresh')
        local sample=db.runHistory.runs[1].talentSample
        local replacement={}; for k,v in pairs(sample) do replacement[k]=v end
        db.runHistory.runs[1].talentSample=replacement
        tree:Refresh(); assert(histories==2, 'late saved snapshot invalidates cached shares')
        collectgarbage('collect'); local baseline=collectgarbage('count')
        for i=1,1000 do
            tree:Disable()
            assert(tree.shares==nil and tree.sampleRefs==nil and tree.history==nil)
            assert(not driver.shown and not next(tree.events.events))
            tree:Enable(); tree.driver.scripts.OnUpdate(tree.driver,.6)
        end
        collectgarbage('collect')
        assert(tree.driver==driver and allocations==created, 'no abandoned frame per Enable')
        assert(collectgarbage('count')-baseline<64, 'bounded retained state')
        tree.driver.scripts.OnHide()
        assert(not tree.history and not tree.shares)
        C_Traits=nil; tree:Refresh(); assert(not tree.legend.shown)
        assert(next(lab:HistoricalShares(Secret({}),'healing',1,'12.0:123'))==nil)
        db.runHistory.runs[1]=17
        lab:HistoricalShares(db.runHistory.runs,'healing',1,'12.0:123')
        combat=true; tree:Disable(); tree:Enable()
        assert(tree.driver==driver and tree.driver.scripts.OnUpdate==nil)
        combat=nil; tree.events.scripts.OnEvent(nil,'PLAYER_REGEN_ENABLED')
        assert(tree.driver.scripts.OnUpdate)
    ''')


def test_default_tree_shows_individual_contributions():
    lua=fixture()
    lua.execute("""
        lab.CompareTalents=function() error('cohort HPS must not decorate individual talents') end
        tree:Refresh()
        assert(tree.cards[1].text.text=='56.0%' and tree.cards[2].text.text=='60.0%')
        assert(tree.cards[3].text.text=='40.0%', 'always selected still has its own measured contribution')
        tree.cards[1].badge.scripts.OnEnter()
        assert(tooltip.lines[1]:find('56.0k / 100.0k',1,true))
        assert(tooltip.lines[1]:find('Spell 1001 [1001]',1,true))
        tree.cards[1].badge.scripts.OnClick()
        assert(lab.view=='contribution' and lab.contribution.spellID==1001)
        assert(lab.rows[1].share.text=='60.0%' and lab.rows[2].share.text=='50.0%')
        assert(lab.rows[1].amount.text=='36.0k' and lab.rows[1].rate.text=='60.0k')
        assert(lab.empty.text:find('56.00%',1,true))
        lab.rows[1].scripts.OnEnter()
        assert(tooltip.lines[1]:find('Spell 1001 [1001]: 36.0k / 60.0k = 60.00%',1,true))
        local built=allocations
        for i=1,1000 do tree:Refresh(); lab:Render() end
        assert(allocations==built)
        tree.openButton.scripts.OnClick()
        assert(lab.view=='talents' and lab.rows[1].share.text=='60.0%')
        lab.rows[1].scripts.OnClick()
        assert(lab.view=='contribution' and lab.contribution.spellID==1002)
        tree.metricButtons.damage.scripts.OnClick()
        tree.openButton.scripts.OnClick()
        assert(lab.metric=='damage' and lab.view=='talents')
    """)


def test_source_breakdown_weights_and_partial_history():
    lua=fixture()
    lua.execute("""
        JP.TalentSources={[1]={[1001]={healing={11,12}}}}
        local a=db.runHistory.runs[2].talentSample
        local b=db.runHistory.runs[3].talentSample
        a.spells.healing={[11]=6000,[12]=6000,[99]=48000}
        b.spells.healing={[11]=4000,[12]=0,[99]=16000}; b.complete=false
        local group=lab:HistoricalShares(db.runHistory.runs,'healing',1,'12.0:123',true)['1001:1']
        assert(group.runs==2 and group.partial and group.amount==16000 and group.total==100000)
        assert(group.percent==16 and group.min==10 and group.max==20)
        assert(group.sources[11]==10000 and group.sources[12]==6000)
        assert(group.samples[1].percent==20 and group.samples[2].percent==10)
        for _,r in ipairs(group.samples) do
            local sum=0; for _,amount in pairs(r.sources) do sum=sum+amount end
            assert(sum==r.amount)
        end
        table.insert(db.runHistory.runs,db.runHistory.runs[2])
        assert(lab:HistoricalShares(db.runHistory.runs,'healing',1,'12.0:123',true)['1001:1'].runs==2)
        tree:Refresh(); assert(tree.cards[1].text.text=='~16.0%')
        a.selected[1].rank=2; tree:ReleaseHistory(); tree:Refresh()
        assert(tree.cards[1].text.text=='~10.0%', 'ranks have separate measurements')
        a.spells.healing={[99]=60000}; a.selected[1].rank=1; b.mixed=true
        group=lab:HistoricalShares(db.runHistory.runs,'healing',1,'12.0:123',true)['1001:1']
        assert(group.amount==0 and group.percent==0 and group.runs==1,'confirmed zero is preserved')
        a.complete=false
        assert(not lab:HistoricalShares(db.runHistory.runs,'healing',1,'12.0:123',true)['1001:1'],
            'missing partial sources do not turn into zero')
        assert(not lab:HistoricalShares(db.runHistory.runs,'healing',2,'12.0:123',true)['1001:1'])
        assert(not lab:HistoricalShares(db.runHistory.runs,'healing',1,'other',true)['1001:1'])
    """)


if __name__=='__main__':
    for test in (test_default_tree_shows_individual_contributions,test_source_breakdown_weights_and_partial_history,
                 test_partial_observations_are_not_recommendations,test_weighting_and_unknowns,test_tree_colors_preview_and_lifecycle,
                 test_tree_reuses_driver_and_releases_cached_history):
        test(); print(test.__name__+': OK')
