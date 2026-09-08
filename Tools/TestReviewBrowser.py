"""Review database UI and complete applicant cards: bounded, read-only fixtures."""
from TestSocialWorkflows import client, load
from TestHudPolish import source


def fixture():
    lua = client()
    lua.execute('''
        local m=getmetatable(UIParent).__index
        function m:EnableMouseWheel(v) self.wheel=v end
        function m:SetSpacing(v) self.spacing=v end
        function UI.Backdrop() end
        function UI.ScrollBar(p) local f=NewWidget(p); f:SetMinMaxValues(0,0); return f end
        function UI.ClassIcon(c) return c or '' end
        function UI.ClassColor() return 1,1,1 end
        function UI.RoleIcon(role) return role end
        function UI.Tooltip() end
        UI.colors.row={0,0,0,1}; UI.colors.rowAlt={.01,.01,.01,1}; UI.colors.panel={0,0,0,1}
        UI.colors.faint={.4,.4,.4,1}; UI.colors.accent={.2,.8,1,1}
    ''')
    bind = source('UI.lua').split('function UI.BindScrollWheel', 1)[1].split('-- Кэш', 1)[0]
    lua.execute('function UI.BindScrollWheel' + bind)
    return lua


def test_database_browser():
    lua = fixture()
    load(lua, 'Modules/ReviewBrowser.lua')
    lua.execute('''
        local b=JP.ReviewBrowser
        page=NewWidget(UIParent); page:SetSize(976,532)
        b:Build(nil,page); b:Refresh()
        assert(b.empty.shown and b.stats.total==0 and #b.rows==0)
        assert(#sent==0, 'browsing an empty database never sends test comments')
        local function record(author,target,vote,text)
            return {author=author,target=target,stamp=time(),vote=vote,text=text,map=399,level=13}
        end
        assert(r:Store(record('Alice-Realm','Tank-Realm',1,'Great pull'),'Alice-Realm',true))
        assert(r:Store(record('Bob-Realm','Tank-Realm',-1,'Slow run'),'Bob-Realm',false))
        assert(r:Store(record('Charlie-Realm','Healer-Realm',0,'Good healing'),'Bob-Realm',false))
        assert(r:Store(record('Alice-Realm','Removed-Realm',0,''),'Alice-Realm',true))
        local revision=r.revision
        b:Refresh()
        assert(r.revision==revision and b.stats.total==3 and b.stats.mine==1 and b.stats.direct==1 and b.stats.forwarded==1)
        assert(b.stats.deleted==1 and not b.empty.shown and #sent==0)
        assert(#b.entries==3 and b.rows[1].record.author=='Alice-Realm' and b.rows[1].record.target=='Tank-Realm')
        b.search:SetText('sLoW'); b:Refresh()
        assert(#b.entries==1 and b.entries[1].author=='Bob-Realm')
        b.search:SetText('Healer-Realm'); b:Refresh()
        assert(#b.entries==1 and b.entries[1].origin=='forwarded')
        b.search:SetText('Charlie'); b:Refresh(); assert(#b.entries==1)
        b.search:SetText('absent'); b:Refresh(); assert(#b.entries==0 and b.empty.shown and b.stats.total==3)
        b.search:SetText(''); b:Refresh()
        local count=allocations
        for i=1,1000 do b:Refresh() end
        assert(allocations==count and r.revision==revision and #sent==0)
        assert(r:SyncStatus():find('постоянно',1,true))
        combat=true; assert(r:SyncStatus():find('бой',1,true)); combat=false
        db.reviews.sync=false; assert(r:SyncStatus():find('постоянно',1,true)); db.reviews.sync=true
        for i=1,1000 do
            local a='User'..i..'-Realm'
            db.reviews.records[a:lower()..'\\ttank-realm']=record(a,'Tank-Realm',1,'Record '..i)
        end
        r:Prune(); b:Refresh()
        assert(b.stats.total+b.stats.deleted==1000 and #b.rows<=32)
        b.offset=10000; b:Render()
        local visible=math.floor((page:GetHeight()-170-12)/44)
        assert(b.offset==#b.entries-visible and b.rows[visible].record==b.entries[#b.entries])
        count=allocations
        for i=1,1000 do b.offset=i%990; b:Render() end
        assert(count==allocations, 'scroll reuses a bounded row pool')
        page.scripts.OnHide(); page:Hide()
        assert(#b.entries==0 and b.rows[1].record==nil)
        local previous=b.stats.total
        db.reviews.records={}; r:Prune(); page:Show(); page.scripts.OnShow()
        assert(previous>0 and b.stats.total==0 and b.empty.shown)
        assert(#sent==0, 'database browsing must not change transport behavior')
    ''')


def test_applicant_cards():
    lua = fixture()
    lua.execute('''
        local columns={}; for i=1,8 do columns[i]={key=i,name='Dungeon '..i,texture=i} end
        JP.GroupSearchUI={GetPartyDungeonColumns=function() return columns end,
            GetRunGradeColor=function() return {.2,.9,.4,1} end}
        function JP.Reviews:AddTooltip() end
        page=NewWidget(UIParent); page:SetSize(976,532); actions={}
        b={offset=0,entries={}}
        function b:Render() JP.ApplicantCards:Render(self,4,12) end
    ''')
    load(lua, 'Modules/ApplicantCards.lua')
    lua.execute('''
        JP.ApplicantCards:Build(b,page,function(action,id) actions[#actions+1]={action,id}; return true end,function() end)
        local function member(id,index,size)
            local cells={}
            for j=1,8 do cells[j]={mapID=j,level=index+8,upgrades=index%4} end
            return {applicantID=id,numMembers=size,name='Candidate'..index..'-Realm',memberIdx=index,
                role=index==1 and 'HEALER' or 'DAMAGER',classFile='MAGE',itemLevel=310+index,score=2400+index,
                status='keyReady',dungeonCells=cells}
        end
        for i=1,4 do b.entries[i]=member(77,i,4) end
        b.entries[5]=member(78,1,1)
        b:Render()
        assert(#b.cards==1 and b.cards[1].invite.applicantID==77)
        for i=1,4 do
            local row=b.cards[1].members[i]
            assert(row.shown and row.name.text:find('Candidate'..i..'-Realm',1,true))
            assert(row.rating.text==tostring(2400+i) and row.ilvl.text==tostring(310+i))
            assert(row.experience.text=='+'..(i+8)..' / +12')
            assert(row.cells[4].value.text==string.rep('+',i%4)..(i+8))
            assert(row.cells[4].ownedKey and not row.cells[3].ownedKey)
            assert(row.cells[1]:GetWidth()>30)
        end
        assert(not b.cards[1].members[5].shown and #actions==0)
        b.cards[1].invite.scripts.OnClick(b.cards[1].invite)
        assert(#actions==1 and actions[1][1]=='InviteApplicant' and actions[1][2]==77)
        b.offset=1; b:Render()
        assert(b.cards[1].invite.applicantID==78 and not b.cards[1].members[2].shown)
        b.entries={}; for i=1,5 do b.entries[i]=member(90,i,5) end
        b:Render(); assert(b.cards[1].members[5].shown and b.cards[1]:GetHeight()<=page:GetHeight()-242)
        b.entries[2].dungeonCells[4].level=0; b.entries[2].status='wrongRole'; b:Render()
        assert(b.cards[1].members[2].status.text=='НЕ ТА РОЛЬ')
        b.entries[2].status='keyRisk'; b:Render(); assert(b.cards[1].members[2].status.text=='Нет данных')
        local count=allocations
        for i=1,1000 do page:SetWidth(i%2==0 and 976 or 1800); b:Render() end
        assert(allocations==count and #actions==1)
        page:SetHeight(1182); b.entries={}
        for i=1,100 do b.entries[i]=member(i,1,1) end
        b:Render(); assert(#b.cards<=14)
        b.offset=99; b:Render(); assert(b.cards[#b.cards].invite.applicantID==100)
        b.entries={}; b:Render()
        for _,card in ipairs(b.cards) do
            assert(not card.shown and card.invite.applicantID==nil)
            for _,row in ipairs(card.members) do assert(row.entry==nil) end
        end
    ''')


def test_review_rating_tooltip():
    lua = fixture()
    lua.execute('''
        for i=1,13 do
            local author=('Author%02d-Realm'):format(i)
            assert(r:Store({author=author,target='Tank-Realm',stamp=time()+i,vote=i%2==0 and -1 or 1,
                text='Comment '..i,map=250,level=12},author,false))
        end
        local score,total,likes,dislikes,recent=r:Rating('Tank-Realm')
        assert(score==1 and total==13 and likes==7 and dislikes==6 and #recent==10)
        assert(recent[1].author=='Author13-Realm' and recent[10].author=='Author04-Realm')
        assert(r:Store({author='Author13-Realm',target='Tank-Realm',stamp=time()+20,vote=0,
            text='Updated',map=250,level=12},'Author13-Realm',false))
        score,total=r:Rating('Tank-Realm'); assert(score==0 and total==13)
        local owner=NewWidget(UIParent)
        r:ShowPlayerTooltip(owner,'Tank-Realm'); local tip=r.playerTip; local count=allocations
        assert(#tip.rows==10 and tip.rows[1].comment.text=='Updated' and tip.height==380)
        for i=1,1000 do r:ShowPlayerTooltip(owner,'Tank-Realm') end
        assert(allocations==count and #r.playerTip.rows==10)
        r:HidePlayerTooltip(NewWidget()); assert(tip.shown)
        r:HidePlayerTooltip(owner); assert(not tip.shown and not tip.owner)
        r:ShowPlayerTooltip(owner,'Unknown-Realm'); assert(tip.height==80 and not tip.rows[1].shown)
        r:Disable(); assert(not tip.shown and not r.ratingCache)
    ''')


def test_listing_taint_boundary():
    lua = fixture()
    lua.execute('''
        opened=0; printed=0
        JP.Print=function() printed=printed+1 end
        JP.ListingDefaults={OpenOwned=function() opened=opened+1; return true end}
        function LFGListEntryCreation_Show() error('native prefill must never run') end
        function LFGListEntryCreation_Select() error('native prefill must never run') end
        C_LFGList={SetEntryTitle=function() error('restricted title must never run') end}
    ''')
    load(lua, 'Modules/GroupSearchUI.lua')
    lua.execute('''
        assert(JP.GroupSearchUI:OpenListingAction() and opened==1)
        combat=true; assert(not JP.GroupSearchUI:OpenListingAction() and opened==1)
        combat=false; JP.ListingDefaults=nil; assert(not JP.GroupSearchUI:OpenListingAction())
    ''')
    search = source('Modules/GroupSearchUI.lua')
    for forbidden in ('LFGListEntryCreation_Show(', 'LFGListEntryCreation_Select(', 'SetEntryTitle('):
        assert forbidden not in search
    welcome=source('Modules/Welcome.lua')
    assert 'key = "reviews", label = L("ОТЗЫВЫ")' in welcome
    assert 'self:LayoutTabs()' in welcome and 'JP.ReviewBrowser:Build(self, reviews)' in welcome


if __name__ == '__main__':
    for test in (test_database_browser, test_applicant_cards, test_review_rating_tooltip, test_listing_taint_boundary):
        test()
        print(test.__name__ + ': OK')
