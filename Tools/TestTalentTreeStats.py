from TestTalentLabUI import fixture as ui_fixture
from TestSocialWorkflows import load


def fixture():
    lua = ui_fixture()
    load(lua, 'Modules/TalentLab.lua')
    load(lua, 'Modules/TalentTreeStats.lua')
    lua.execute('''
        lab=JP.TalentLab; tree=JP.TalentTreeStats
        function GetSpecialization() return 1 end
        function GetSpecializationInfo() return 1 end
        function GetBuildInfo() return '12.0','123' end
        for _,run in ipairs(db.runHistory.runs) do run.talentSample.gameBuild='12.0:123' end
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
        db.runHistory.runs={db.runHistory.runs[1]}
        local sample=db.runHistory.runs[1].talentSample
        sample.complete=false
        assert(next(lab:HistoricalShares(db.runHistory.runs,'healing',1,'12.0:123'))==nil)
        tree:Refresh()
        assert(tree.cards[2].text.text=='~60.0%' and tree.cards[2].border[1]==1)
        nodes[2].activeRank=0
        tree:Refresh(); assert(tree.cards[2].text.text=='—', 'partial data cannot recommend an unselected talent')
        sample.overallHealing=60000; tree:ReleaseHistory(); tree:Refresh()
        assert(tree.cards[3].text.text=='—','mismatched totals are not usable shares')
        sample.overallHealing=50000; sample.mixed=true
        tree:ReleaseHistory(); tree:Refresh(); assert(tree.cards[3].text.text=='—')
    ''')


def test_tree_colors_preview_and_lifecycle():
    lua=fixture()
    lua.execute('''
        tree:Refresh()
        assert(#tree.cards==3)
        assert(tree.cards[1].text.text=='56.0%' and tree.cards[1].border[1]==1)
        assert(tree.cards[2].text.text=='60.0%' and tree.cards[2].border[2]==.95)
        nodes[2].activeRank=2
        tree:Refresh(); assert(tree.cards[2].text.text=='—', 'rank evidence must match')
        nodes[1].activeRank=1; nodes[1].activeEntry={entryID=1}
        tree:Refresh(); assert(tree.cards[1].border[2]==.95, 'staged selection updates color')
        tree.metricButtons.damage.scripts.OnClick(); assert(tree.cards[1].text.text=='—')
        inspecting=true; tree:Refresh(); assert(not tree.cards[1].shown and not tree.legend.shown)
        inspecting=false; combat=true; tree:Refresh(); assert(not tree.cards[1].shown)
        combat=false; tree:Enable(); tree.driver.scripts.OnUpdate(tree.driver,.6)
        assert(tree.cards[1].shown)
        tree.driver.scripts.OnHide(); assert(not tree.cards[1].shown)
        tree:Disable(); assert(tree.driver.scripts.OnUpdate==nil)
    ''')


def test_tree_reuses_driver_and_releases_cached_history():
    lua=fixture()
    lua.execute('''
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


if __name__=='__main__':
    for test in (test_partial_observations_are_not_recommendations,test_weighting_and_unknowns,test_tree_colors_preview_and_lifecycle,
                 test_tree_reuses_driver_and_releases_cached_history):
        test(); print(test.__name__+': OK')
