"""Search parity: presets, bounded journal, filters, native input restoration.

The widget fixture checks lifecycle and actions, not WoW's live taint engine.
"""
from TestSocialWorkflows import client, load
from pathlib import Path


def fixture():
    lua=client()
    lua.execute(r'''
        db.autoMatch={}; db.search={showRejectedResults=true}; db.groupFilters={dungeons={}}
        C_LFGList={}; JP.RequestRefresh=function() end
        C_ChallengeMode={GetOverallDungeonScore=function() return 2500 end}
        function UnitClass() return 'Druid','DRUID' end
        function GetAverageItemLevel() return 310,305 end
        local methods=getmetatable(UIParent).__index
        function methods:IsIgnoringParentAlpha() return self.ignoreAlpha or false end
        function methods:SetIgnoreParentAlpha(v) self.ignoreAlpha=v end
        function methods:GetFrameStrata() return self.strata or 'MEDIUM' end
        function methods:SetFrameStrata(v) self.strata=v end
        function methods:GetFrameLevel() return self.level or 1 end
        function methods:SetFrameLevel(v) self.level=v end
        function UI.Backdrop() end
        function UI.RoleIcon(role) return role end
        function UI.Button(p,text,width,height)
            local f=NewWidget(p); f.text=text; f.label=NewWidget(f); f:SetSize(width,height); return f
        end
        function methods:Enable() self.enabled=true end
        function methods:Disable() self.enabled=false end
        function methods:SetEnabled(v) self.enabled=v end
        function methods:IsEnabled() return self.enabled~=false end
        function methods:SetFieldEnabled(v) self.enabled=v end
        function methods:SetFocus() self.focus=true end
        function methods:HasFocus() return self.focus end
        function methods:ClearFocus()
            local previous=self.focus; self.focus=false
            if previous and self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end
        end
        function methods:GetCenter() return self.cx or 300,self.cy or 300 end
        function methods:GetLeft() return 100 end
        function methods:GetBottom() return 100 end
        function methods:GetTextInsets() return 8,8,0,0 end
        function methods:GetFont() return self.font or 'Default',self.fontSize or 12,self.fontFlags or '' end
        function methods:SetFont(font,size,flags) self.font=font; self.fontSize=size; self.fontFlags=flags end
        function methods:GetCursorPosition() return self.cursor or #(self.text or '') end
        function methods:SetDesaturated(value) self.desaturated=value end
        function methods:GetStringWidth() return #(self.text or '')*(self.fontSize or 12)/2 end
        function methods:HookScript(key,fn)
            local old=self.scripts[key]
            self.scripts[key]=function(...) if old then old(...) end; fn(...) end
        end
        function methods:Hide()
            local was=self.shown; self.shown=false
            if was and self.scripts.OnHide then self.scripts.OnHide(self) end
        end
        function UI.NumberBox(p,w,h)
            local box=NewWidget(p); box:SetSize(w,h)
            local f=NewWidget(box); f.frame=box
            return f,box
        end
        w={resultsPanel=NewWidget(UIParent),filterFields={},groupFilters=db.groupFilters,
            Refresh=function() refreshes=(refreshes or 0)+1 end}
        w.resultsPanel:SetSize(700,350)
        for _,key in ipairs({'keyMin','keyMax','scoreMin','scoreMax','runsMin'}) do w.filterFields[key]=NewWidget(UIParent) end
        JP.GroupSearchUI={RefreshDungeonCards=function() end}
        C_LFGList.GetAvailableRoles=function() return true,true,true end
    ''')
    shared=(Path(__file__).resolve().parents[1]/'MythicBoost/UI.lua').read_text(encoding='utf-8-sig')
    shared=shared.split('-- Shared activity cards:',1)[1].split('-- End shared activity cards.',1)[0]
    shared=shared.split('\n',1)[1]
    lua.execute('''
        UI.colors.field={.028,.036,.048,1}; UI.colors.accent={.16,.72,.96,1}
        UI.colors.hudEdge={.3,.32,.34,1}
        UI.colors.raised={.09,.112,.14,.96}
        UI.Scrim=function(p) return NewWidget(p) end
    ''')
    lua.execute('local UI=JP.UI; local C=UI.colors; local L=JP.L; '+shared)
    load(lua,'Modules/GroupTools.lua')
    load(lua,'Modules/GroupToolsUI.lua')
    lua.execute('g=JP.GroupTools')
    return lua


def test_removed_filters_and_priority():
    lua=fixture()
    lua.execute(r'''
        local f={ageMax=1,sizeMax=1,scoreNear=1,favoritesOnly=true,hideMyClass=true,eligibleOnly=true,friendsOnly=true,
            sort='age',ascending=true,style3=false,tanksMin=1,excludedSpecs={[123]=true}}
        g:ClearRemovedFilters(f)
        assert(not f.ageMax and not f.sizeMax and not f.favoritesOnly and not f.eligibleOnly and not f.hideMyClass)
        assert(f.sort=='priority' and not f.ascending and f.style3==false and f.tanksMin==1 and f.excludedSpecs[123])
        assert(g:Reject({members=3,playstyle=3},f)=='не подходит стиль группы')
        local raid=g:CopyFilters({category='raid',ageMax=10,sizeMin=8,eligibleOnly=true,scoreNear=1})
        assert(raid.ageMax==10 and raid.sizeMin==8 and raid.eligibleOnly and not raid.scoreNear)
        local rows={{searchResultID=1,applicationPriority=2,age=1},{searchResultID=2,applicationPriority=9,age=50}}
        g:Sort(rows,{sort='age',ascending=true}); assert(rows[1].searchResultID==2)
        local broken={presets={{name='old'}},leaders={bad={kind='blocked',at=time()}},history={{at=time()+1,status='applied'}}}
        g:Prune(broken); assert(not broken.presets and not broken.leaders and #broken.history==0)
        JP.API.GetApplicationIDs=function() return {3,4} end
        JP.API.GetApplicationState=function() return {active=true} end
        g:Track({searchResultID=4,leaderName='Outside-Realm',dungeon='Outside'})
        local ordered,excluded=g:OrderResults(rows,{{searchResultID=3,rejected=true,actionable=false,applicationPriority=1}})
        assert(#ordered==4 and #excluded==0 and ordered[1].searchResultID==3 and ordered[2].searchResultID==4)
        assert(not ordered[1].rejected and ordered[1].actionable and ordered[3].searchResultID==2)
        local again=g:OrderResults(ordered,{})
        assert(#again==4,'active applications must not duplicate rows')
    ''')


def test_journal_records_confirmed_events_and_active_outside_search():
    lua=fixture()
    lua.execute(r'''
        g:Track({searchResultID=1,leaderName='Bob-Realm',dungeon='Dungeon',score=2500})
        local store=g:DB(); assert(#store.history==0,'click alone is not a sent application')
        g:ApplicationEvent(1,'applied'); now=10; g:ApplicationEvent(1,'invited')
        assert(#store.history==1 and store.history[1].status=='invited' and store.history[1].started<store.history[1].at)
        g:ApplicationEvent(1,'invited'); assert(#store.history==1)
        g:ApplicationEvent(1,'declined'); g:ApplicationEvent(1,'applied'); assert(#store.history==2)
        g:ApplicationEvent(Secret(1),'applied'); g:ApplicationEvent(1,Secret('applied'))
        assert(#store.history==2)
        for id=2,230 do
            g:Track({searchResultID=id,leaderName='Bob-Realm',dungeon='Dungeon'})
            g:ApplicationEvent(id,'applied')
        end
        assert(#store.history==JP.Limits.SEARCH_HISTORY and #g.order==JP.Limits.SEARCH_CACHE)
        JP.API.GetApplicationIDs=function() return {230,229} end
        JP.API.GetApplicationState=function(id) return {active=id==230} end
        local out=g:ActiveMatches({})
        assert(#out==1 and out[1].searchResultID==230 and out[1].leaderName=='Bob-Realm')
        assert(#sent==0,'search metadata is local')
    ''')


def test_panel_actions_and_native_query_restoration():
    lua=fixture()
    lua.execute(r'''
        g:BuildToolbar(w); g:UpdateToolbar(w)
        assert(w.toolsToolbar.scale<1,'toolbar fits minimum window width')
        g:OpenPanel(w); local created=allocations
        for i=1,30 do g:OpenPanel(w) end
        assert(not g.panels and not g.presetRows and not g.leaderInput and not g.extraFields)
        assert(not w.autoRole and not w.showAllButton and not w.historyButton and not w.activeButton and not w.sortButton)
        assert(g.compositionChecks.style1 and g.languageChecks.english and g.compositionFields.tanksMin)
        assert(allocations==created,'composition controls are pooled')
        PVEFrame=NewWidget(UIParent); PVEFrame:SetPoint('CENTER',UIParent,'CENTER',25,30); PVEFrame:Hide()
        LFGListFrame={SearchPanel=NewWidget(PVEFrame)}
        local sp=LFGListFrame.SearchPanel; sp.categoryID=2; sp.SearchBox=NewWidget(sp)
        local box=sp.SearchBox; box.text='10-10'
        box:SetFont('NativeSearch',14,'')
        function box:GetEffectiveScale() return 1 end
        function PVEFrame:GetEffectiveScale() return 1 end
        function w.queryButton:GetEffectiveScale() return 1 end
        function box:SetText() error('protected text must never be written') end
        function box:Insert() error('protected text must never be written') end
        function PVEFrame_ShowFrame() PVEFrame:Show() end
        function HideUIPanel(f) f:Hide() end
        C_LFGList.ClearSearchTextFields=function() box.text='' end
        g.panel:Hide(); g:EditQuery(w)
        assert(g.edit and box.focus and PVEFrame.alpha==0)
        assert(PVEFrame.points[1][4]==104,'align the text inset to the left edge, independent of field width')
        assert(w.queryButton.label.points[1][1]=='LEFT' and w.queryButton.label.points[1][4]==12)
        assert(box.ignoreAlpha and box.strata=='TOOLTIP' and box.level==100,'native input must be above the click blocker')
        box.scripts.OnCursorChanged(box,24,-4,1,16)
        assert(g.caret.shown and g.caret.points[1][2]==w.queryButton.label and g.caret.points[1][4]==35,'end cursor follows the displayed five-character prefix, not native x')
        g.caret.scripts.OnUpdate(g.caret,.6); assert(g.caret.alpha==0)
        g:UpdateToolbar(w); assert(g.caret.alpha==0,'unrelated refresh must not restart the blink')
        box.cursor=2; box.scripts.OnCursorChanged(box,8,-4,1,16)
        assert(g.caret.alpha==1 and g.caret.elapsed==0 and g.caret.points[1][4]==14)
        box.cursor=0; box.scripts.OnCursorChanged(box,100,-4,1,16)
        assert(g.caret.points[1][4]==0,'Home goes to the same origin as the text')
        box.cursor=nil
        box.text='10-12'; box.scripts.OnTextChanged(box)
        assert(w.queryButton.text=='10-12' and w.queryButton.label.alpha==1,'typed characters remain visible while focused')
        assert(w.queryButton.label.font=='NativeSearch' and w.queryButton.label.fontSize==14,'mirror uses native glyph metrics for the cursor')
        box.text=''; box.scripts.OnTextChanged(box)
        assert(w.queryButton.text=='','no placeholder under the active cursor')
        assert(g.caret.points[1][4]==0,'deleting text moves the cursor immediately')
        box.text='10-12'; box.scripts.OnTextChanged(box)
        g:EndEdit(); assert(not g.edit and PVEFrame.alpha==1 and not g.blocker:IsShown())
        assert(not g.caret.shown,'cursor disappears on focus loss')
        assert(w.queryButton.label.font=='Default' and w.queryButton.label.fontSize==12,'restore caption font after editing')
        assert(not box.ignoreAlpha and box.strata=='MEDIUM' and box.level==1,'restore native input properties')
        assert(PVEFrame.points[1][1]=='CENTER' and PVEFrame.points[1][4]==25)
        g:AcceptQuery(w); assert(w.groupFilters.keyMin==10 and w.groupFilters.keyMax==12)
        function w.queryButton:GetEffectiveScale() return .8 end
        g:EditQuery(w)
        assert(math.abs(PVEFrame.points[1][4]-81.6)<.001,'left origin stays aligned at a different toolbar scale')
        assert(w.queryButton.label.fontSize==17.5,'native glyph width is preserved across scales')
        assert(g.caret.points[1][4]==43.75,'cursor uses the scaled mirror font')
        box:ClearFocus(); assert(not g.edit and PVEFrame.alpha==1)
        g:EditQuery(w); PVEFrame:Hide(); assert(not g.edit and PVEFrame.alpha==1)
        g:ClearQuery(w); assert(g:QueryText()=='' and not w.groupFilters.keyMin)
        combat=true; g:EditQuery(w); assert(not g.edit)
    ''')


def test_automatch_weekly_unknown_level_and_zero_runs():
    # Reuse the production scan fixture; add independent cases to its setup.
    from TestMythicBoost import test_rejected_search_results
    test_rejected_search_results()
    lua=fixture()
    lua.execute(r'''
        UI.SafeString=JP.SafeString; UI.SafeNumber=JP.SafeNumber; UI.SafeTable=JP.SafeTable
        UI.SafeBoolean=JP.SafeBoolean; UI.UsableNumber=JP.UsableNumber
        JP.IsTest=true; JP.GetBestLevel=function() return 15 end
        JP.API.GetChallengeMapIDs=function() return {399} end
        JP.API.GetChallengeMap=function() return {name='Dungeon'} end
        JP.SeasonMapByActivity={[10]=399}
        C_LFGList.GetActivityInfoTable=function() return {fullName='Dungeon'} end
        C_LFGList.GetSearchResultPlayerInfo=function() return nil end
        info={activityID=10,numMembers=2,name='+10',leaderName='Bob-Realm',leaderOverallDungeonScore=2200}
        C_LFGList.GetSearchResultInfo=function() return info end
        C_LFGList.GetSearchResultMemberCounts=function() return {} end
    ''')
    load(lua,'Modules/AutoMatch.lua')
    lua.execute(r'''
        local party={roles={TANK=0,HEALER=0,DAMAGER=1}}
        local weekly=JP.AutoMatch.TestBuildMatch(1,{runsMin=0,roleFit=false},{},party)
        assert(not weekly.rejected,'weekly below personal best and no Raider.IO must be visible')
        info.numBNetFriends=0; info.numCharFriends=1
        local friends=JP.AutoMatch.TestBuildMatch(1,{friendsOnly=true,runsMin=0,roleFit=false},{},party)
        assert(friends and friends.friends==1,'character friends count even with zero BNet friends')
        local _,_,push=JP.AutoMatch.TestBuildMatch(1,{scoreUpgrade=true,runsMin=0,roleFit=false},{},party)
        assert(push.rejected and push.rejectionReason=='ключ ниже твоего рекорда')
        info.name=nil; info.leaderDungeonScoreInfo={{mapChallengeModeID=399,bestRunLevel=15}}
        local unknown=JP.AutoMatch.TestBuildMatch(1,{keyMin=10,keyMax=10,runsMin=0,roleFit=false},{},party)
        assert(not unknown.rejected,'leader record must not be filtered as the advertised level')
    ''')


def test_direct_search_preserves_text_and_uses_actual_query_target():
    lua=fixture()
    lua.execute(r'''
        UI.SafeString=JP.SafeString; UI.SafeTable=JP.SafeTable; UI.SafeBoolean=JP.SafeBoolean
        UI.UsableNumber=JP.UsableNumber
        JP.Log=function() end
        Enum.LFGListFilter={Recommended=1,PvE=4}
        LFGListFrame={SearchPanel={SearchBox={GetText=function() return query end}}}
        query='10-10'; searches=0; cleared=0
        C_LFGList.ClearSearchTextFields=function() cleared=cleared+1; query='' end
        C_LFGList.Search=function(category,filter,preferred,languages,cross,advanced,ids)
            searches=searches+1; assert(category==2 and filter==5 and preferred==0)
            assert(query=='10-10' or query=='' or query=='10-12')
            assert(cross==nil and advanced.difficultyMythicPlus)
        end
        w.scan=NewWidget(UIParent)
    ''')
    load(lua,'Modules/GroupSearchUI.lua')
    lua.execute(r'''
        local s=JP.GroupSearchUI
        s.BuildServerFilter=function() return {difficultyMythicPlus=true} end
        s.searchPending=true; s.searchToken=1; s.searchQueue={false}; s.searchIndex=1
        s:RunDirectSearch(w,1)
        assert(searches==1 and cleared==0 and query=='10-10')
        assert(s.currentSearchTarget==10 and s.manualExactLevel==10)
        query=''; s:RunDirectSearch(w,1)
        assert(searches==2 and not s.manualExactLevel and not s.lastSearchTarget)
        query='10-12'; s:RunDirectSearch(w,1)
        assert(searches==3 and not s.manualExactLevel and cleared==0)
    ''')


if __name__=='__main__':
    for test in [test_removed_filters_and_priority,
                 test_journal_records_confirmed_events_and_active_outside_search,
                 test_panel_actions_and_native_query_restoration,
                 test_automatch_weekly_unknown_level_and_zero_runs,
                 test_direct_search_preserves_text_and_uses_actual_query_target]:
        test(); print(test.__name__+': OK')
