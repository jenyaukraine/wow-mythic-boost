"""Bounded review transport, trust boundaries, gossip and filter regression tests."""
from TestDungeonHUD import runtime, load, source


def client(name='Alice', peer='Bob'):
    lua=runtime()
    lua.globals().my_name=name
    lua.globals().peer_name=peer
    lua.execute(r'''
        epoch=1788580800; sent={}; tickers={}; messages={}
        function time() return epoch+math.floor(now) end
        function date() return '05.09.2026' end
        function GetNormalizedRealmName() return 'Realm' end
        function UnitFullName(u) local v=units[u]; return v and v.name,v and v.realm end
        units.player={name=my_name,realm='Realm',guid='Player-'..my_name}
        units.party1={name=peer_name,realm='Realm',guid='Player-'..peer_name}
        function JP:Print(s) messages[#messages+1]=s end
        Enum.SendAddonMessageResult={Success=0}
        C_ChatInfo={RegisterAddonMessagePrefix=function() end,
            InChatMessagingLockdown=function() return lockdown or false end,
            AreOutgoingAddonChatMessagesRestricted=function() return restricted or false end,
            SendAddonMessage=function(prefix,msg,channel)
                assert(#msg<=255 and (channel=='PARTY' or channel=='RAID' or channel=='INSTANCE_CHAT'))
                if apiFailure then return 1 end
                sent[#sent+1]=msg; sentChannel=channel; return 0
            end}
        C_Timer={NewTicker=function(_,fn)
            local t={fn=fn}; function t:Cancel() self.cancelled=true end
            tickers[#tickers+1]=t; return t
        end,After=function(_,fn) delayed=fn end}
        GameTooltip=NewWidget(UIParent)
        local methods=getmetatable(GameTooltip).__index
        function methods:SetOwner(owner) self.owner=owner; self.lines={} end
        function methods:IsOwned(owner) return self.owner==owner end
        function methods:AddLine(text) self.lines[#self.lines+1]=text end
        function methods:AddDoubleLine(a,b) self:AddLine(a..': '..b) end
        function methods:SetChecked(v) self.checked=v end
        function methods:SetNumeric(v) self.numeric=v end
        function methods:SetMaxLetters(v) self.letters=v end
        function methods:GetText() return self.text end
        function methods:ClearFocus() end
        function UI.Panel(p) return NewWidget(p) end
        function UI.Button(p,text,w,h) local f=NewWidget(p); f.text=text; f:SetSize(w,h); return f end
        function UI.NumberBox(p,w,h) local f=NewWidget(p); f.frame=NewWidget(p); f.frame:SetSize(w,h); return f end
        function UI.CheckBox(p,text,checked,fn) local f=NewWidget(p); f.toggle=fn; f.checked=checked; return f end
        UI.colors.lineSoft={.1,.1,.1,1}; UI.colors.window={0,0,0,1}
    ''')
    load(lua,'Modules/Reviews.lua')
    load(lua,'Modules/ReviewsUI.lua')
    lua.execute('r=JP.Reviews; r:Enable()')
    return lua


def packets(lua):
    lua.execute('r:QueueRound()')
    return list(lua.globals().r.outbox.values())


def deliver(lua, messages, sender):
    receive=lua.eval("function(msg,sender) r:Receive('MBReviews2',msg,'PARTY',sender) end")
    for msg in reversed(messages):
        receive(msg,sender)


def test_reviews():
    a,b,c=client(),client('Bob','Alice'),client('Charlie','Bob')
    a.execute(r'''
        run={mapID=399,level=13,upgrades=2,mapName='Dungeon',members={'Alice-Realm','Bob-Realm'}}
        assert(not r:Save('Stranger-Realm',1,'bad target',run))
        assert(not r:Save('Alice-Realm',1,'self',run))
        assert(r:Save('Bob-Realm',1,'Хорошо играл |Tfake|t |cffffffffтекст|r',run))
        assert(#r:Get('Bob-Realm')==1 and #r:Get('Bob')==0, 'do not merge cross-realm names')
        local got=r:GetOwn('Bob-Realm').text
        local hex={}; for i=1,#got do hex[#hex+1]=('%02x'):format(got:byte(i)) end
        assert(got=='Хорошо играл  текст',table.concat(hex,' '))
        assert(#r.CleanText(string.rep('я',140))==240)
        assert(r:Save('Bob-Realm',1,'Хорошо играл  текст',run))
        assert(#r:Get('Bob-Realm')==1, 'same author/target does not multiply votes')
    ''')
    wire=packets(a)
    deliver(b,wire,'Alice-Realm')
    deliver(b,wire,'Alice-Realm')
    b.execute("assert(#r:Get('Bob-Realm')==1 and r:Get('Bob-Realm')[1].direct)")
    deliver(c,packets(b),'Bob-Realm')
    c.execute("assert(#r:Get('Bob-Realm')==1 and not r:Get('Bob-Realm')[1].direct and r:Get('Bob-Realm')[1].via=='Bob-Realm')")
    b.execute(r'''
        assert(r:Store({author='Alice-Realm',target='Bob-Realm',stamp=time()+1,vote=-1,text='relay copy',shared=true},'Other-Realm',false))
        assert(r:Get('Bob-Realm')[1].vote==-1 and not r:Get('Bob-Realm')[1].direct, 'newer relayed revision is retained as forwarded')
    ''')
    a.execute("now=2; assert(r:Save('Bob-Realm',0,'',run)); assert(#r:Get('Bob-Realm')==0)")
    deliver(b,packets(a),'Alice-Realm')
    deliver(c,packets(b),'Bob-Realm')
    b.execute("assert(#r:Get('Bob-Realm')==0)")
    c.execute("assert(#r:Get('Bob-Realm')==0)")
    deliver(b,wire,'Alice-Realm')
    b.execute("assert(#r:Get('Bob-Realm')==0, 'old copies must not resurrect deleted reviews')")
    a.execute(r'''
        assert(not r:Store({author='Alice-Realm',target='Bob-Realm',stamp=time()+1,vote=-1,text='forged',shared=true},'Bob-Realm',false))
        r:Receive(Secret('MBReviews1'),Secret('payload'),Secret('PARTY'),Secret('Bob-Realm'))
        for i=1,10000 do r:Receive('MBReviews2','D\t'..i..'\t1\t4\tpart','PARTY','Bob-Realm') end
        local count=0; for _ in pairs(r.incoming) do count=count+1 end
        assert(count<=16 and #sent==0, 'bounded fragments; receiving does not broadcast')
        for i=1,1500 do
            local author='User'..i..'-Realm'
            db.reviews.records[string.lower(author)..'\tbob-realm']={author=author,target='Bob-Realm',stamp=time()-i,vote=1,text='',map=399,level=13}
        end
        r:Prune(); count=0; for _ in pairs(db.reviews.records) do count=count+1 end
        assert(count==1000 and r:GetOwn('Bob-Realm'), 'cap preserves own records first')
        r:QueueRound(); assert(#r.outbox<=64)
        for _,packet in ipairs(r.outbox) do assert(#packet<=255) end
        local before=allocations; r:Pump(); assert(allocations==before)
        combat=true; r:Pump(); assert(r.ticker)
        lockdown=true; restricted=true; r:Pump(); assert(#sent<=1, 'chat lockdown blocks addon packets and preserves queue')
        local queued=#r.outbox; local first=r.outbox[1]; local ticker=r.ticker
        apiFailure=true; r:Pump(); assert(#r.outbox==queued and r.outbox[1]==first and r.ticker==ticker)
        assert(r:SyncStatus():find('очередь сохранена',1,true))
        r:Pump(); assert(#sent<=1 and #r.outbox==queued)
        lockdown=false; restricted=false; apiFailure=false; now=now+5; r:Pump()
        combat=false; lockdown=false; restricted=false; r:UpdatePump()
        db.reviews.sync=false; r:UpdatePump()
        r:Disable(); assert(not r.running and not r.ticker)
        db.reviews.sync=true; r:Enable(); assert(r.ticker)
        for _,t in ipairs(tickers) do if t~=r.ticker then assert(t.cancelled) end end
        r:ShowRun(run); local built=allocations
        for i=1,1000 do r:ShowRun(run) end
        assert(allocations==built and #r.reviewRows>=1)
        combat=true; r:ShowRun(run)
        r:Disable(); combat=false
    ''')

    d=client('Dan','Alice')
    d.execute("combat=true; lockdown=true; restricted=true")
    deliver(d,wire,'Alice-Realm')
    d.execute("assert(#r:Get('Bob-Realm')==1,'receiving is independent of outgoing restrictions')")
    d.execute('''
        raid=true; units.raid1={name='Dan',realm='Realm'}; units.raid2={name='Alice',realm='Realm'}
        r:CachePeers(); assert(r.channel=='RAID' and r.ticker)
        r:QueueRound(); r:Pump(); assert(not sentChannel or sentChannel=='RAID')
    ''')


def test_addon_presence():
    lua=client()
    load(lua,'Modules/AddonPresence.lua')
    lua.execute(r'''
        local p=JP.AddonPresence; packets={}; grouped=false; guild=false
        function IsInGroup(category) return grouped and category==nil end
        function IsInGuild() return guild end
        C_ChatInfo.SendAddonMessage=function(prefix,msg,channel,target)
            assert(prefix=='MBPresence1' and channel~='WHISPER' and target==nil)
            packets[#packets+1]={msg,channel}; return 0
        end
        p:Enable()
        assert(p:IsUser('Alice-Realm') and not p:IsUser('Bob-Realm') and not p:IsUser('Bob'))
        for i=1,10000 do p:Decorate('Offline'..i..'-Realm','Peer') end
        assert(not p.queue and #packets==0 and not p.ticker, 'browsing never probes players or starts a ticker')
        grouped=true; guild=true; p:Request()
        for i=1,1000 do p:Request() end
        assert(#p.queue==2 and p.ticker)
        local activeTicker=p.ticker; local tickerCount=#tickers
        p:Pump(); p:Pump(); assert(#packets==2)
        p:Receive('MBPresence1','A1','WHISPER','Bob-Realm')
        assert(p:IsUser('Bob-Realm') and p.ticker==activeTicker and #tickers==tickerCount)
        p:Receive('MBPresence1','Q1','WHISPER','Carol-Realm')
        assert(#p.queue==0, 'legacy whisper discovery never sends a whisper back')
        for i=1,10000 do p:Receive('MBPresence1','Q1','PARTY','Peer'..i..'-Realm') end
        local count=0; for _ in pairs(p.seen) do count=count+1 end
        assert(count<=256 and #p.queue==1)
        p:Pump(); assert(#packets==3 and packets[3][1]=='A1')
        now=121; p:Request(); grouped=false; guild=false
        p:Pump(); p:Pump(); assert(#packets==3 and #p.queue==0, 'drop departed channels')
        local built=allocations
        for i=1,1000 do p:Pump() end
        assert(allocations==built and #packets==3)
        p:Receive(Secret('MBPresence1'),Secret('Q1'),Secret('WHISPER'),Secret('Name'))
        now=800; p:Pump(); assert(not p:IsUser('Bob-Realm') and not p.ticker)
        assert(activeTicker.cancelled, 'expiry must cancel the original ticker')
        grouped=true; p:Request(); p:Pump()
        local sentBefore=#packets
        for i=1,12 do
            now=now+121; p:Pump()
            p:Receive('MBPresence1','A1','PARTY','Bob-Realm')
            assert(p:IsUser('Bob-Realm') and p.ticker)
        end
        assert(#packets==sentBefore+12,'quiet groups renew discovery beyond the ten-minute TTL')
        activeTicker=p.ticker; tickerCount=#tickers
        p:Disable(); p:Disable(); p:Pump()
        assert(not next(p.events.events) and not p.ticker and activeTicker.cancelled)
        assert(#tickers==tickerCount, 'disabled pump must not restart a ticker')
    ''')


def test_manual_attendant():
    lua=client()
    load(lua,'Modules/Convenience.lua')
    lua.execute(r'''
        selected={}; repairs=0
        -- Existing saved profiles must not bring back the removed automation.
        db.convenience={repair=true,attendantAssist=true,autoQuests=true}
        units.npc={guid='Creature-0-1-1-1-198927-1'}
        Enum.GossipOptionStatus={Available=0}
        function IsShiftKeyDown() return shift or false end
        options={{gossipOptionID=11,name='Мне надо починить снаряжение.',status=0},
            {gossipOptionID=12,name='Можешь меня подлатать?',status=0}}
        C_GossipInfo={GetOptions=function() error('must not inspect service options') end,
            GetActiveQuests=function() return {} end,GetAvailableQuests=function() return {} end,
            SelectOption=function(id) selected[#selected+1]=id end}
        local m=JP.Convenience; m:Enable()
        assert(m.AssistAttendant==nil and not m.events.events.GOSSIP_CLOSED)
        for i=1,10 do m.events.scripts.OnEvent(nil,'GOSSIP_SHOW') end
        combat=true; m.events.scripts.OnEvent(nil,'GOSSIP_SHOW'); combat=false
        assert(#selected==0 and not m.attendantRepair, 'service choices must remain manual')
        function CanMerchantRepair() return true end
        function GetRepairAllCost() return 100,true end
        function RepairAllItems() repairs=repairs+1 end
        function IsInInstance() return false,'none' end
        m.events.scripts.OnEvent(nil,'MERCHANT_SHOW'); assert(repairs==0)
        delayed(); assert(repairs==1, 'ordinary merchant auto-repair must remain available')
        shift=true; m:Repair(); assert(repairs==1)
    ''')


def test_death_tooltip():
    lua=client()
    load(lua,'Modules/DungeonTimer.lua')
    lua.execute(r'''
        local t=JP.DungeonTimer; t:Create()
        t.deathCount=3; t.deathPenalty=45
        t.deathRun={players={a={name='Alice-Realm',count=2}}}
        t.deathHover.scripts.OnEnter()
        assert(GameTooltip:IsOwned(t.deathHover) and GameTooltip.shown)
        assert(GameTooltip.lines[1]=='Всего: 3' and GameTooltip.lines[2]=='Потеря времени: 0:45')
        assert(GameTooltip.lines[4]=='Alice-Realm: 2' and GameTooltip.lines[5]=='Не записано по игрокам: 1')
        t.deathHover.scripts.OnLeave(); assert(not GameTooltip.shown)
        assert(not t.deathHover.mouseClicks and t.deathHover.mouseMotion)
    ''')


def test_filter_bridge():
    lua=client()
    lua.execute(r'''
        UI.SafeString=JP.SafeString; UI.SafeTable=JP.SafeTable; UI.SafeBoolean=JP.SafeBoolean
        native={activities={382,139}}; writes=0; refreshes=0
        C_LFGList={GetAdvancedFilter=function() return native end,SaveAdvancedFilter=function() writes=writes+1; error('must not write') end}
        LFGListFrame={SearchPanel={categoryID=2}}
        function JP:RequestRefresh() refreshes=refreshes+1 end
        function JP:Log() end
        function LFGListSearchPanel_DoSearch() end
        function hooksecurefunc(name,fn) nativeHook=fn end
    ''')
    load(lua,'Modules/GroupSearchUI.lua')
    lua.execute(r'''
        local ui=JP.GroupSearchUI
        local w={groupFilters={dungeons={[399]=true,[588]=true},scoreMin=0},dungeonData={{mapID=584},{mapID=250},{mapID=399}}}
        ui:HookNativeDungeonSelection(w); nativeHook()
        assert(w.groupFilters.dungeons[584] and w.groupFilters.dungeons[250] and not w.groupFilters.dungeons[399])
        assert(writes==0)
        local filter=ui:BuildServerFilter(w)
        assert(#filter.activities==2 and filter.activities[1]==382 and filter.activities[2]==139)
        native={activities={999999}}; nativeHook(); assert(w.groupFilters.dungeonsNone)
        native={activities={}}; nativeHook(); assert(not w.groupFilters.dungeonsNone and w.groupFilters.dungeons[399])
        native={activities={Secret(382)}}; local selection=w.groupFilters.dungeons
        nativeHook(); assert(w.groupFilters.dungeons==selection and writes==0)
    ''')


def test_lfg_diagnostics():
    lua=client()
    diagnostic=source('Core.lua').split('local function DescribeValue',1)[1].split('local function ShowHelp',1)[0]
    lua.execute('local L=JP.L\nlocal function DescribeValue'+diagnostic+'\nJP.DumpSearchResults=DumpSearchResults')
    lua.execute(r'''
        function JP:GetVersion() return '2.4.67' end
        JP.modules.PlayerTooltip={searchHooked=true}
        JP.GroupSearchUI={IsMythicPlusSearchResult=function(_,id) return id==2 end}
        activityCalls=0; memberCalls=0
        C_LFGList={GetSearchResults=function() return 3,{1,2,3} end,
            GetSearchResultInfo=function(id)
                if id==3 then return Secret('whole result') end
                return {activityIDs={id==1 and Secret(123) or 123},name=Secret('+11'),
                    leaderName='Bob-Realm',numMembers=1}
            end,
            GetActivityInfoTable=function(id) assert(not issecretvalue(id)); activityCalls=activityCalls+1; return {isMythicPlusActivity=true} end,
            GetSearchResultPlayerInfo=function(id)
                memberCalls=memberCalls+1
                return {name=id==1 and Secret('HiddenName') or 'Bob-Realm',assignedRole='TANK'}
            end}
        lockdown=true; JP.DumpSearchResults()
        local d=db.diagnostics
        assert(d.tooltipHooked and d.chatMessagingLockdown.text=='true')
        assert(d.results[1].activityID.secret==true and not d.results[1].activityInfo)
        assert(d.results[1].searchResultInfo.name.text=='<secret>')
        assert(d.results[1].players[1].name.text=='<secret>')
        assert(d.results[2].players[1].name.text=='Bob-Realm' and d.results[2].players[1].name.secret==false)
        assert(d.results[2].mythicPlusDetected.text=='true')
        assert(d.results[3].searchResultInfo.text=='<secret>' and #d.results[3].players==0)
        assert(activityCalls==1 and memberCalls==2, 'secret activities must not be passed to another API')
    ''')


def test_tooltip_unknown_rating():
    lua=client()
    lua.execute(r'''
        tooltip=NewWidget(UIParent)
        for _,key in ipairs({'title','meta','rioLabel','rioValue','reviews'}) do tooltip[key]=NewWidget(tooltip) end
        tooltip.columnHeaders={}; tooltip.playerRows={}
        function GetGroupTooltip() return tooltip end
        function DungeonColumns() return {} end
        function PositionGroupTooltip() end
        function PartyRatingColorCode() return '00ff00' end
        C_LFGList={GetSearchResultInfo=function() return data end}
        data={numMembers=0}
    ''')
    fragment=source('Modules/GroupSearchUI.lua').split('local function ShowGroupTooltip',1)[1].split('local function HideGroupTooltip',1)[0]
    lua.execute('local UI,L,C=JP.UI,JP.L,JP.UI.colors\nlocal SafeString,UsableNumber=JP.SafeString,JP.UsableNumber\nlocal function ShowGroupTooltip'+fragment+'\nJP.ShowGroupTooltip=ShowGroupTooltip')
    lua.execute(r'''
        local row={searchResultID=1,dungeonName='Dungeon',match={rejected=true,partyScoreKnown=0,partyScoreMembers=0,partyScoreAverage=0}}
        JP.ShowGroupTooltip(row)
        assert(tooltip.rioValue.text=='—' and not tooltip.meta.text:find('0/0',1,true))
        data.leaderOverallDungeonScore=1426; JP.ShowGroupTooltip(row)
        assert(tooltip.rioValue.text=='1426' and tooltip.rioLabel.text=='RIO лидера')
        row.match.partyScoreKnown=2; row.match.partyScoreAverage=1500; row.match.partyScoreMembers=2
        JP.ShowGroupTooltip(row)
        assert(tooltip.rioValue.text=='1500' and tooltip.rioLabel.text=='СР. RIO')
        row.match.partyScoreKnown=0; data.leaderOverallDungeonScore=Secret(3000)
        JP.ShowGroupTooltip(row); assert(tooltip.rioValue.text=='—')
        data.leaderOverallDungeonScore=0; JP.ShowGroupTooltip(row)
        assert(tooltip.rioValue.text=='0', 'a public real zero is different from unknown')
    ''')


if __name__=='__main__':
    for test in (test_reviews,test_addon_presence,test_manual_attendant,test_death_tooltip,test_filter_bridge,test_lfg_diagnostics,test_tooltip_unknown_rating):
        test()
        print(test.__name__+': OK')
