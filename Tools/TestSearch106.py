"""Regression tests for native input, owned-key forms and raid filtering."""
from TestGroupTools import fixture, load


def test_owned_key_form_and_coexistence():
    lua=fixture()
    lua.execute(r'''
        JP.modules={}; JP.Log=function() end
        capturedErrors={}
        function geterrorhandler() return function(err) capturedErrors[#capturedErrors+1]=err end end
        PVEFrame=NewWidget(UIParent); PVEFrame:Hide()
        LFGListFrame={EntryCreation=NewWidget(PVEFrame),CategorySelection=NewWidget(PVEFrame)}
        LFGListFrame.activePanel=LFGListFrame.CategorySelection
        local ec=LFGListFrame.EntryCreation; ec.Name=NewWidget(ec); ec.Label=NewWidget(ec)
        ShortlistDB={autoOpen=true}; stolen=0; selects=0; cleared=0; submitted=0
        hooks={}
        function hooksecurefunc(name,fn) hooks[name]=fn end
        function LFGListFrame_SetActivePanel() end
        function LFGListEntryCreationCancelButton_OnClick() end
        function PVEFrame_ShowFrame()
            PVEFrame:Show()
            if ShortlistDB.autoOpen then stolen=stolen+1 end
        end
        Enum.LFGEntryGeneralPlaystyle={FunSerious=3}
        C_LFGList.HasActiveEntryInfo=function() return active or false end
        C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel=function() return 142,306,keyLevel or 12 end
        C_LFGList.GetLfgCategoryInfo=function() return {name='Dungeons'} end
        C_LFGList.CreateListing=function() submitted=submitted+1 end
        function IsInGroup() return grouped or false end
        function UnitIsGroupLeader() return leader or false end
        function LFGListEntryCreation_SetBaseFilters(p,base) p.baseFilters=base end
        function LFGListEntryCreation_SetEditMode(p,edit)
            p.editMode=edit
            -- Native SetEditMode reads activity info even after Clear.
            assert(type(p.selectedActivity)=='number','GetActivityInfoTable requires a selected activity')
            if not edit and p.selectedCategory==2 and p.selectedActivity then
                LFGListEntryCreation_Select(p,1,2,306,142)
            end
        end
        function LFGListEntryCreation_Clear(p)
            cleared=cleared+1; p.selectedActivity=nil; p.selectedCategory=nil
        end
        function LFGListEntryCreation_Select(p,filters,category,group,activity)
            assert(p.generalPlaystyle==3 and group==306 and activity==142)
            selects=selects+1; p.selectedCategory=category; p.selectedActivity=activity
        end
        function LFGListEntryCreation_UpdateValidState() end
        function LFGListEntryCreation_Show() error('must not taint native activePanel dispatcher') end
    ''')
    load(lua,'Modules/ListingDefaults.lua')
    lua.execute(r'''
        local d=JP.ListingDefaults
        local previous=LFGListFrame.activePanel
        assert(d:OpenOwned()); assert(selects==1 and cleared==1 and submitted==0)
        assert(stolen==0 and ShortlistDB.autoOpen==true,'restore Shortlist preference')
        assert(LFGListFrame.activePanel==previous,'do not own the native event dispatcher')
        assert(LFGListFrame.EntryCreation:IsShown() and not previous:IsShown())
        hooks.LFGListFrame_SetActivePanel(LFGListFrame,previous)
        assert(LFGListFrame.EntryCreation:IsShown() and not previous:IsShown(),'background availability updates must not dismiss the prepared form')
        hooks.LFGListEntryCreationCancelButton_OnClick()
        assert(not LFGListFrame.EntryCreation:IsShown() and previous:IsShown(),'explicit Back dismisses the form')
        assert(d:OpenOwned() and selects==1,'preserve same-key draft')
        keyLevel=13; assert(d:OpenOwned() and selects==2,'refresh title after key level changes')
        active=true; hooks.LFGListFrame_SetActivePanel(LFGListFrame,previous)
        assert(not d.formVisible and not LFGListFrame.EntryCreation:IsShown(),'publication releases the form to the native viewer')
        active=false; assert(d:OpenOwned()); PVEFrame:Hide()
        assert(not d.formVisible and not LFGListFrame.EntryCreation:IsShown(),'closing the outer window releases the form')
        local savedFrame=LFGListFrame; LFGListFrame=nil; local loads=0
        C_AddOns={LoadAddOn=function(name)
            assert(name=='Blizzard_GroupFinder'); loads=loads+1; LFGListFrame=savedFrame
        end}
        assert(d:OpenOwned() and loads==1,'load the native creation UI before checking availability')
        combat=true; assert(not d:OpenOwned() and selects==2); combat=false
        grouped=true; leader=false; assert(not d:OpenOwned()); grouped=false
        local ok=d:Call(function() d.guard.scripts.OnEvent(nil,'ADDON_ACTION_BLOCKED','MythicBoost') end)
        assert(not ok,'blocked actions can return without throwing')
        ok=d:Call(function() error('native form failure') end)
        assert(not ok and #capturedErrors==1 and capturedErrors[1]:find('native form failure',1,true),'caught failures reach the normal error collector with debug logging off')
        function PVEFrame_ShowFrame() error('failed open') end
        assert(not d:ShowPanel() and ShortlistDB.autoOpen,'failure must restore preference')
    ''')


def test_raid_filters_and_unknown_progress():
    lua=fixture()
    lua.execute(r'''
        JP.API.GetApplicationState=function() return {status='none'} end
        function GetNumGroupMembers() return 1 end
        info={activityIDs={100},numMembers=8,leaderName='Bob-Realm',leaderOverallDungeonScore=2700,age=80,generalPlaystyle=3}
        activity={categoryID=3,isCurrentRaidActivity=true,mapID=555,groupFinderActivityGroupID=777,difficultyID=15,maxNumPlayers=30,fullName='Raid Heroic'}
        kills={'First boss'}
        C_LFGList.GetSearchResultInfo=function() return info end
        C_LFGList.GetActivityInfoTable=function() return activity end
        C_LFGList.GetSearchResultEncounterInfo=function() return kills end
        C_LFGList.GetSearchResultPlayerInfo=function(_,i)
            return {classFilename=i==1 and 'DRUID' or 'MAGE',assignedRole=i==1 and 'TANK' or 'DAMAGER'}
        end
    ''')
    load(lua,'Modules/RaidFinder.lua')
    lua.execute(r'''
        local r=JP.RaidFinder
        local f={category='raid',difficultyHeroic=true,raidGroup=777}
        local m=r.BuildMatch(1,f); assert(m and m.members==8 and m.killedCount==1,'raids are not five-player groups')
        f.fresh=true; local _,reason=r.BuildMatch(1,f); assert(reason=='рейд уже начат')
        f.fresh=nil; f.bossStates={['First boss']='alive'}; assert(not r.BuildMatch(1,f))
        f.bossStates={['First boss']='killed'}; assert(r.BuildMatch(1,f))
        r.bosses[555]={'First boss','Second boss','Third boss'}
        r.bossDetails[555]={['First boss']={},['Second boss']={},['Third boss']={}}
        f.nextBoss=2; assert(r.BuildMatch(1,f),'next boss filter follows journal order')
        f.nextBoss=3; assert(not r.BuildMatch(1,f))
        kills={'Second boss'}; f.bossStates={}; f.nextBoss=1; assert(r.BuildMatch(1,f),'nonlinear kills keep first boss eligible')
        kills=Secret({}); assert(not r.BuildMatch(1,f),'unknown progress cannot match a specific boss')
        f.nextBoss=nil; kills={'First boss'}
        f.killedMax=0; assert(not r.BuildMatch(1,f)); f.killedMax=nil
        kills=Secret({}); local unknown=r.BuildMatch(1,f); assert(unknown and unknown.killedCount==nil,'unknown is not a fresh raid')
        kills={}; f.bossStates={}; f.difficultyHeroic=false; assert(not r.BuildMatch(1,f))
        f.difficultyHeroic=true; activity.categoryID=2; assert(not r.BuildMatch(1,f),'discard previous category result set')
        local filter=r:ServerFilter(f); assert(filter.difficultyHeroic and not filter.difficultyMythicPlus and filter.activities[1]==777)
        local saved=g:CopyFilters({category='raid',bossStates={Boss='alive'},sizeMax=30,difficultyHeroic=true,languages={english=true}})
        assert(saved.category=='raid' and saved.bossStates.Boss=='alive' and saved.sizeMax==30)
    ''')


def test_live_role_and_completed_exact_badges():
    lua=fixture()
    lua.execute(r'''
        function GetSpecialization() return 1 end
        function GetSpecializationRole() return role end
        role='HEALER'; g.applyRole='TANK'; assert(g:GetRole()=='HEALER')
        role='DAMAGER'; assert(g:GetRole()=='DAMAGER','specialization changes require no manual reset')
    ''')
    from pathlib import Path
    source=(Path(__file__).resolve().parents[1]/'MythicBoost/Modules/GroupSearchUI.lua').read_text(encoding='utf-8')
    body=source.split('local function LocalDisplayKeyLevel(welcome, match)',1)[1].split('function GroupSearchUI:RenderRows',1)[0]
    lua.execute('function Badge(welcome,match)'+body)
    lua.execute(r'''
        UsableNumber=JP.UsableNumber; GroupSearchUI={}
        local w={groupFilters={keyMin=10,keyMax=10}}
        assert(Badge(w,{})==nil,'local fields cannot label an unsent search')
        GroupSearchUI.resultsExactLevel=10
        assert(Badge(w,{})==10 and Badge(w,{keyLevel=15,keyApprox=true})==10)
        assert(Badge(w,{keyLevel=16})==16,'a readable title wins over search fallback')
        assert(Badge(w,{raid=true})==nil)
        w.groupFilters.keyMin=12; assert(Badge(w,{})==10,'unsent edits do not relabel results')
        GroupSearchUI.resultsExactLevel=nil; assert(Badge(w,{})==nil,'a range cannot invent a level')
    ''')


def test_raid_panel_switch_and_presets():
    lua=fixture()
    lua.execute(r'''
        UI.colors.accent={.16,.72,.96,1}; UI.colors.hudEdge={.3,.32,.34,1}
        w.keyHeader=NewWidget(UIParent); w.groupHeader=NewWidget(UIParent)
        w.mplusSide=NewWidget(UIParent); w.cardsPanel=NewWidget(UIParent)
        C_LFGList.GetAvailableActivityGroups=function() return {777,778,779} end
        C_LFGList.GetActivityGroupInfo=function(id) return 'Raid'..id end
        C_LFGList.GetAvailableActivities=function(_,id) return {id} end
        C_LFGList.GetActivityInfoTable=function(id) return {isCurrentRaidActivity=true,mapID=id-222} end
    ''')
    load(lua,'Modules/RaidFinder.lua')
    lua.execute(r'''
        local r=JP.RaidFinder; local original=w.groupFilters
        r.bosses[555]={'First','Second'}
        r:Build(w,UIParent); w.raidCards:SetWidth(900); r:Switch(w,true)
        assert(w.groupFilters.category=='raid' and w.raidSide:IsShown() and not w.mplusSide:IsShown())
        assert(w.groupFilters.difficultyHeroic and r.checks.difficultyHeroic.checked)
        assert(r.groupButton.text=='Все' and r.groupButton.width==62,'use the Mythic+ header control')
        assert(r.groupChoices[1].height==80 and r.groupChoices[1].iconBorder.width==56,'use the common activity card geometry')
        assert(w.raidHeaderHeight==144,'all raids must not reserve an empty boss grid')
        r.groupChoices[2].scripts.OnClick()
        assert(r:IsSelected(w.groupFilters,777) and not r:IsSelected(w.groupFilters,778) and r:IsSelected(w.groupFilters,779),'click excludes just one raid from all')
        local server=r:ServerFilter(w.groupFilters)
        assert(#server.activities==2 and server.activities[1]==777 and server.activities[2]==779)
        r.groupChoices[3].scripts.OnClick(); assert(r:IsSelected(w.groupFilters,777) and not r:IsSelected(w.groupFilters,779))
        assert(w.raidHeaderHeight==186,'selected boss grid sizes to content')
        local boss=r.bossButtons[1]
        assert(boss.stateLabel.text=='Любой' and not boss.marker:IsShown())
        r.bossButtons[1].scripts.OnClick(); assert(w.groupFilters.bossStates.First=='alive')
        local green=table.concat(boss.background,',')
        boss.scripts.OnEnter(); boss.scripts.OnLeave()
        assert(boss.stateLabel.text=='Жив' and boss.marker:IsShown() and table.concat(boss.background,',')==green,'hover must preserve selected state')
        r.bossButtons[1].scripts.OnClick(); assert(w.groupFilters.bossStates.First=='killed')
        assert(boss.stateLabel.text=='Убит' and table.concat(boss.background,',')~=green,'alive and killed need distinct persistent fills')
        local saved=g:CopyFilters(w.groupFilters)
        assert(saved.bossStates.First=='killed' and saved.raids[777])
        local allocationsBefore=allocations
        for i=1,100 do r:Refresh(w) end
        assert(allocations==allocationsBefore,'raid controls are pooled')
        r:Switch(w,false); assert(w.groupFilters==original and w.mplusSide:IsShown() and not w.raidSide:IsShown())
        r:Switch(w,true); assert(w.groupFilters.bossStates.First=='killed','mode switches retain independent raid filters')
        r.groupButton.scripts.OnClick(); assert(r:IsSelected(w.groupFilters,778),'All enables all raids')
        r.groupButton.scripts.OnClick(); assert(w.groupFilters.raidsNone and not r:IsSelected(w.groupFilters,777),'All again clears selection')
        local copied=g:CopyFilters(w.groupFilters); assert(copied.raidsNone)
        r.groupChoices[1].scripts.OnClick(); assert(r:IsSelected(w.groupFilters,777) and not r:IsSelected(w.groupFilters,778),'click from none selects only clicked raid')
    ''')


if __name__=='__main__':
    for test in (test_owned_key_form_and_coexistence,test_raid_filters_and_unknown_progress,test_live_role_and_completed_exact_badges,test_raid_panel_switch_and_presets):
        test(); print(test.__name__+': OK')
