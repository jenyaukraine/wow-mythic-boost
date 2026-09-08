"""Current raid data, owned-key tab action and row-relative tooltip regression."""
from TestGroupTools import fixture, load
from pathlib import Path


def test_next_alive_portrait():
    lua = fixture()
    lua.execute(r'''
        C_EncounterJournal={GetInstanceForGameMap=function(map) assert(map==555); return 99 end}
        function EJ_GetEncounterInfoByIndex(i,journal)
            assert(journal==99)
            if i<=3 then return 'Boss'..i,'Description',i+100 end
        end
        portraits=0
        function EJ_GetCreatureInfo(index,encounter)
            assert(index==1); portraits=portraits+1
            return 1,'Boss','Description',500,encounter+1000
        end
    ''')
    load(lua, 'Modules/RaidFinder.lua')
    lua.execute(r'''
        local r=JP.RaidFinder
        local m={mapID=555,killedCount=1,killedBosses={Boss2=true}}
        local name,icon=r:NextBoss(m)
        assert(name=='Boss1' and icon==1101,'nonlinear kills must not be treated as a sequential count')
        r:NextBoss(m); assert(portraits==1,'cache portrait metadata')
        m.killedBosses.Boss1=true; m.killedCount=2
        name,icon=r:NextBoss(m); assert(name=='Boss3' and icon==1103)
        m.killedBosses.Boss3=true; m.killedCount=3; assert(r:NextBoss(m)==nil)
        m.killedBosses={Unknown=true}; m.killedCount=1; assert(r:NextBoss(m)==nil)
        m.killedBosses={}; m.killedCount=nil; assert(r:NextBoss(m)==nil,'unknown is not a fresh raid')
        m.killedCount=0; assert(r:NextBoss(m)=='Boss1')
    ''')



def test_raid_journal_without_map_and_artwork():
    lua=fixture()
    lua.execute(r'''
        getmetatable(UIParent).__index.SetDesaturated=function(self,value) self.desaturated=value end
        tier=2; journalReads=0
        function EJ_GetCurrentTier() return tier end
        function EJ_GetNumTiers() return 3 end
        function EJ_SelectTier(t) tier=t end
        function EJ_GetInstanceByIndex(i,raid) if tier==3 and i==1 then return 99,'Raid' end end
        function EJ_GetInstanceInfo(id)
            assert(id==99); journalReads=journalReads+1
            return 'Raid','Description',123,nil,456,789
        end
        function EJ_GetEncounterInfoByIndex(i,id) if i<=3 then return 'Boss'..i,'Description',i+100 end end
        function EJ_GetCreatureInfo(i,id) return 1,'Boss','Description',500,id+1000 end
    ''')
    load(lua,'Modules/RaidFinder.lua')
    lua.execute(r'''
        local r=JP.RaidFinder
        local g={name='Raid'}
        local icon,art=r:Artwork(g)
        assert(icon==789 and art==123 and tier==2,'resolve by name and restore journal selection')
        r:Artwork(g); assert(journalReads==1,'reuse native art metadata')
        local m={raidName='Raid',killedCount=1,killedBosses={Boss2=true},roleCounts={},dungeon='Raid',title='Group'}
        local name,portrait,index=r:NextBoss(m)
        assert(name=='Boss1' and portrait==1101 and index==1,'missing map ID must not hide boss portraits')
        local row={}
        for _,key in ipairs({'partyIcons','key','keyBox','keyIcon','roles','dungeon','detail'}) do row[key]=NewWidget(UIParent) end
        r:RenderRow(row,m)
        assert(row.raidProgress:IsShown() and row.raidProgress.text=='1/3','keep the progress number over the portrait')
        assert(row.keyIcon.alpha==1,'portrait remains visible behind progress')
        local missing={name='Not loaded'}; assert(r:Journal(missing)==nil)
        function EJ_GetInstanceByIndex(i,raid) if tier==3 and i==1 then return 100,'Not loaded' end end
        now=6; assert(r:Journal(missing)==100,'retry journal data after it becomes available')
    ''')



def test_raid_context_and_stationary_hover():
    lua=fixture()
    lua.execute(r'''
        activeInstance=7; activeDifficulty=8; EncounterJournal={instanceID=7}
        function EJ_SelectInstance(id) activeInstance=id end
        function EJ_GetDifficulty() return activeDifficulty end
        function EJ_SetDifficulty(id) activeDifficulty=id end
        C_EncounterJournal={GetInstanceForGameMap=function() return 99 end}
        function EJ_GetEncounterInfoByIndex(i,id)
            if activeInstance~=99 or activeDifficulty~=14 then return end
            if i==1 then return 'Boss1','description',100 end
        end
    ''')
    load(lua,'Modules/RaidFinder.lua')
    lua.execute(r'''
        assert(#JP.RaidFinder:Bosses({mapID=555})==1,'read bosses with raid instance and raid difficulty selected')
        assert(activeInstance==7 and activeDifficulty==8,'restore the previous Mythic+ journal context')
    ''')
    source=(Path(__file__).resolve().parents[1]/'MythicBoost/Modules/GroupSearchUI.lua').read_text(encoding='utf-8')
    helpers=source.split('function GroupSearchUI:RefreshHoveredResult()',1)[1].split('-- Тот же полный тултип',1)[0]
    lua.execute(r'''
        GroupSearchUI={}; C=UI.colors; C.rowHover={.1,.2,.3,1}
        function HideGroupTooltip() tooltip=nil end
        function ShowGroupTooltip(row) tooltip=row.match.searchResultID; shows=(shows or 0)+1 end
    ''')
    lua.execute('function GroupSearchUI:RefreshHoveredResult()'+helpers)
    lua.execute(r'''
        local row=NewWidget(UIParent); row.apply=NewWidget(row); row.baseColor={0,0,0,1}
        row.match={searchResultID=1}; row:Show()
        GroupSearchUI:BindResultHover(row); row.scripts.OnEnter(); assert(tooltip==1)
        row.match={searchResultID=2}; GroupSearchUI:RefreshHoveredResult(); assert(tooltip==2,'recycled row updates without mouse movement')
        row.isSection=true; row.match=nil; GroupSearchUI:RefreshHoveredResult(); assert(tooltip==nil)
        row.isSection=false; row.match={searchResultID=3}; GroupSearchUI:RefreshHoveredResult(); assert(tooltip==3,'scrolling past a section resumes tooltip')
        row.apply.scripts.OnLeave(); GroupSearchUI:RefreshHoveredResult(); assert(tooltip==nil)
        row.apply.scripts.OnEnter(); assert(tooltip==3)
        row:Hide(); assert(tooltip==nil and GroupSearchUI.hoveredResultRow==nil,'empty/hidden rows release tooltip')
    ''')
    render=source.split('function GroupSearchUI:RenderRows(welcome)',1)[1].split('-- Раскладка',1)[0]
    assert 'self:RefreshHoveredResult()' in render


def test_raid_progress_character_scope():
    lua = fixture()
    lua.execute(r'''
        UI.SafeString=JP.SafeString
        UI.UsableNumber=function(n) return JP.SafeNumber(n)~=nil end
        function UI.KeystoneScore(p) return p and p.score end
        function IsInGuild() return true end
        function GetNumGuildMembers() return 1 end
        function GetGuildRosterInfo() return 'Alt-Realm',nil,nil,90,nil,nil,nil,nil,true,nil,'MAGE' end
        function GetMaxLevelForPlayerExpansion() return 90 end
        function JP:Log() end
        local raid={bossCount=9,shortName='RAID',name='Current Raid'}
        profile={name='Alt',realm='Realm',raidProfile={raidProgress={
            {current=false,raid=raid,progress={{difficulty=3,kills=9}}},
            {current=true,isMainProgress=true,raid=raid,progress={{difficulty=3,kills=9}}},
            {current=true,raid=raid,progress={{difficulty=1,kills=9},{difficulty=2,kills=3},{difficulty=3,kills=0}}},
        }}}
        RaiderIO={GetProfile=function() return profile end}
    ''')
    load(lua, 'Modules/GuildBoard.lua')
    lua.execute(r'''
        local g=JP.GuildBoard
        local rows,summary=g:RaidProgress(profile)
        assert(#rows==1 and rows[1].value=='9/9 N   3/9 H   0/9 M' and summary=='RAID 3/9 H')
        local entries=g:Collect(true)
        assert(#entries==1 and entries[1].raidSummary==summary and not entries[1].hasKeystoneScore,'raid-only players remain visible')
        rows,summary=g:RaidProgress({}); assert(#rows==0 and summary=='','missing raid profile is not zero progress')
        profile.raidProfile.raidProgress[3].progress={{difficulty=3,kills=10},{difficulty=1,kills=Secret(5)}}
        rows=g:RaidProgress(profile); assert(#rows==0,'discard invalid or protected counts')
    ''')


def test_applicant_tab_does_not_open_listing():
    lua = fixture()
    load(lua, 'Modules/Welcome.lua')
    lua.execute(r'''
        local w=JP.modules.Welcome
        local opens=0
        w.SwitchPage=function(self,key) self.activePage=key end
        JP.GroupSearchUI.OpenListingAction=function() opens=opens+1 end
        C_LFGList.HasActiveEntryInfo=function() return active end
        w:OnTabClick('applicants'); assert(opens==0 and w.activePage=='applicants')
        active=true; w:OnTabClick('applicants'); assert(opens==0,'existing listing stays in applicant board')
        active=false; w:SwitchPage('applicants'); assert(opens==0,'programmatic navigation must not open a protected form')
        w:OnTabClick('settings'); assert(opens==0)
    ''')


def test_tooltip_under_hovered_row():
    lua = fixture()
    source = (Path(__file__).resolve().parents[1] / 'MythicBoost/Modules/GroupSearchUI.lua').read_text(encoding='utf-8')
    body = source.split('local function PositionGroupTooltip(', 1)[1].split('local function ShowGroupTooltip', 1)[0]
    lua.execute('function Position(' + body)
    lua.execute(r'''
        local row,tip=NewWidget(UIParent),NewWidget(UIParent)
        tip:SetSize(500,200)
        function row:GetBottom() return bottom end
        bottom=400; Position(tip,row)
        assert(tip.points[1][1]=='TOPLEFT' and tip.points[1][2]==row and tip.points[1][3]=='BOTTOMLEFT')
        bottom=50; Position(tip,row)
        assert(tip.points[1][1]=='BOTTOMLEFT' and tip.points[1][2]==row and tip.points[1][3]=='TOPLEFT')
    ''')


if __name__ == '__main__':
    for test in (test_next_alive_portrait,test_raid_journal_without_map_and_artwork,test_raid_context_and_stationary_hover, test_raid_progress_character_scope,
                 test_applicant_tab_does_not_open_listing, test_tooltip_under_hovered_row):
        test()
        print(test.__name__ + ': OK')
