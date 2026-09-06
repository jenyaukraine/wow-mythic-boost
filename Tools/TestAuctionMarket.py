"""Independent auction snapshots: transactional scan, bounds, history and native buy handoff."""
from TestAvoidableDamage import fixture as base
from TestHudPolish import load, source


def fixture():
    lua=base()
    lua.execute(r'''
        local methods=getmetatable(UIParent).__index
        function methods:SetEnabled(v) self.enabled=v end
        function methods:UnregisterEvent(e) self.events[e]=nil end
        function methods:SetAutoFocus() end
        function methods:SetMaxLetters() end
        function methods:GetText() return self.text or '' end
        function methods:ClearFocus() end
        function methods:CreateLine() return NewWidget(self) end
        function methods:SetThickness(v) self.thickness=v end
        function methods:SetStartPoint(...) self.start={...} end
        function methods:SetEndPoint(...) self.finish={...} end
        -- Native Show/Hide callbacks, important for cancellation and retained rows.
        function methods:Hide()
            local was=self.shown; self.shown=false
            if was and self.scripts.OnHide then self.scripts.OnHide(self) end
        end
        function strsplit(delim,text)
            local out={}; for value in (text..delim):gmatch('(.-)'..delim) do out[#out+1]=value end
            return table.unpack(out)
        end
        epoch=1000000; function time() return epoch end
        function date(_,t) return tostring(t) end
        AuctionHouseFrame=NewWidget(); queries={}; selected={}
        AuctionHouseSearchContext={BuyItems=1,BuyCommodities=2}
        function AuctionHouseFrame:SelectBrowseResult(v) selected[#selected+1]=v end
        function AuctionHouseFrame:QueryItem(context,key) queries[#queries+1]={context,key} end
        lots={}; requests=0; commodity=true; ready=true
        C_AuctionHouse={
            ReplicateItems=function() requests=requests+1 end,
            IsThrottledMessageSystemReady=function() return ready end,
            GetNumReplicateItems=function() return #lots end,
            GetReplicateItemInfo=function(i)
                local v=lots[i+1]; return v.name or 'Item',123,v.count or 1,1,nil,nil,nil,nil,nil,v.price,nil,nil,nil,nil,nil,nil,v.id,not cold[v.id]
            end,
            GetReplicateItemLink=function(i)
                if cold[lots[i+1].id] then return nil end
                return lots[i+1].link or ('|Hitem:'..lots[i+1].id..':0:0:0:0:0:0:0:0|h[Item]|h')
            end,
            GetItemKeyInfo=function() if missing then return nil end; return {isCommodity=commodity} end,
            PlaceBid=function() error('automatic purchase') end,
            StartCommoditiesPurchase=function() error('automatic purchase') end,
            ConfirmCommoditiesPurchase=function() error('automatic purchase') end,
        }
        loadRequests={}; cold={}
        C_Item={GetItemInfoInstant=function(link) return tonumber(link:match('item:(%d+)')),nil,nil,gear and 'INVTYPE_HEAD' or '' end,
            DoesItemExistByID=function(id) return id~=9999999 end,
            RequestLoadItemDataByID=function(id) loadRequests[id]=(loadRequests[id] or 0)+1 end,
            GetDetailedItemLevelInfo=function() return ilvl or 100 end}
    ''')
    load(lua,'Modules/AuctionMarket.lua'); load(lua,'Modules/AuctionMarketUI.lua')
    lua.execute(r'''
        m=JP.AuctionMarket; m:Enable()
        function Event(e) m.events.scripts.OnEvent(nil,e) end
        function Open() Event('AUCTION_HOUSE_SHOW'); if not m.frame or not m.frame.shown then m.button.scripts.OnClick() end end
        function Scan()
            assert(m:StartScan()); Event('REPLICATE_ITEM_LIST_UPDATE')
            local steps=0
            while m.work do steps=steps+1; assert(steps<10000); now=now+1/60; m:ProcessBatch() end
        end
        Open()
    ''')
    return lua


def test_scan_and_signals():
    lua=fixture()
    lua.execute(r'''
        assert(requests==0 and not m.events.scripts.OnUpdate,'opening does not scan')
        lots={{id=10,price=20000,count=2},{id=10,price=9000},{id=20,price=5000},{id=30,price=0}}
        Scan(); local db=MythicBoostMarketDB
        assert(#db.snapshots==1 and db.snapshots[1].prices['10:0:0']==9000)
        assert(not db.snapshots[1].partial and db.snapshots[1].count==2 and not m.comparison)
        assert(not m:StartScan() and requests==1,'15 minute cooldown')
        epoch=epoch+86400; lots={{id=10,price=6000},{id=20,price=7000}}; Scan()
        assert(#db.snapshots==2 and m.items[1].signal and m.items[1].key=='10:0:0')
        assert(math.abs(m.items[1].change+33.333333)<.001 and m.comparison==db.snapshots[1])
        local built=allocations
        for i=1,1000 do m:Render() end
        assert(allocations==built and #m.rows==8 and #m.rows[1].lines==20)
        local item=m.items[1]
        assert(m:OpenListing(item) and #queries==1 and selected[1].minPrice==0)
        assert(queries[1][1]==2 and not m.frame.shown and not m.items,'native current query, not a purchase')
        Open(); commodity=false; assert(m:OpenListing(m.items[1]) and queries[2][1]==1)
        Open(); missing=true; assert(not m:OpenListing(m.items[1])); missing=false
        ready=false; assert(not m:OpenListing(m.items[1])); ready=true
        epoch=epoch+900; assert(m:StartScan()); local timer=m.timeout
        m.frame:Hide(); assert(not m.work and timer.cancelled and not m.events.scripts.OnUpdate)
        Event('REPLICATE_ITEM_LIST_UPDATE'); assert(#db.snapshots==2,'late response cannot commit cancelled scan')
        Open(); epoch=epoch+900; lots={}; assert(m:StartScan()); Event('REPLICATE_ITEM_LIST_UPDATE')
        assert(#db.snapshots==2 and not m.work,'empty server reply never overwrites history')
        epoch=epoch+900; assert(m:StartScan()); timer=m.timeout; timer.fn()
        assert(not m.work and #db.snapshots==2)
        m:Disable(); assert(not next(m.events.events) and not m.events.scripts.OnUpdate)
    ''')


def test_bounds_variants_and_retention():
    lua=fixture()
    lua.execute(r'''
        gear=true; ilvl=100
        local a=m:Identity('|Hitem:10:0:0:0:0:0:-7:999:80|h[A]|h',10)
        ilvl=200; local b=m:Identity('|Hitem:10:0:0:0:0:0:-7:999:80|h[A]|h',10)
        assert(a=='10:100:-7' and b=='10:200:-7','gear variants stay separate')
        assert(m:Identity('|Hbattlepet:39:25:3:1|h[Pet]|h',82800)=='p:39:25:3')
        gear=false
        for i=1,22000 do lots[i]={id=i,price=10000+i} end
        Scan(); local db=MythicBoostMarketDB
        assert(db.snapshots[1].count==20000 and db.snapshots[1].partial)
        local count=0; for _ in pairs(db.catalog) do count=count+1 end; assert(count==20000)
        assert(not m.items[1].signal,'partial scans cannot create strong signals')
        local snapshots={}; local stamp=epoch
        for i=1,1000 do
            stamp=stamp+900; snapshots[#snapshots+1]={stamp=stamp,prices={},count=0}
            snapshots=m:RetainSnapshots(snapshots,stamp)
            assert(#snapshots<=21)
            for _,v in ipairs(snapshots) do assert(stamp-v.stamp<=7*86400) end
        end
        db.snapshots=snapshots
        local comparison=m:Comparison(snapshots[#snapshots])
        assert(comparison and math.abs(stamp-comparison.stamp-86400)<=10800,'frequent scans keep yesterday')
        epoch=epoch+900; lots={{id=10,price=Secret(10)}}; Scan()
        assert(#db.snapshots==#snapshots,'unreadable scan does not save false zero')
        local before=allocations
        for i=1,1000 do m:Disable(); m:Enable(); Open(); Event('AUCTION_HOUSE_CLOSED') end
        assert(allocations==before and not m.work and not m.timeout and not m.events.scripts.OnUpdate)
    ''')


def test_progress_cold_cache_and_release():
    lua=fixture()
    lua.execute(r'''
        assert(not m.scanProgress.shown and m.heading.shown)
        cold[10]=true
        for i=1,6000 do lots[i]={id=10,price=i==6000 and 500 or 1000} end
        assert(m:StartScan())
        assert(m.scanProgress.shown and m.scanProgress.bar.value==0 and m.scanProgress.scripts.OnUpdate)
        assert(not m.scanProgress.value.text:find('%%') and m.scanButton.label.text=='Отмена')
        local built=allocations
        for i=1,1000 do now=now+.001; m.scanProgress.scripts.OnUpdate(m.scanProgress,.001) end
        assert(allocations==built and requests==1,'waiting animation makes no new requests or frames')
        Event('REPLICATE_ITEM_LIST_UPDATE')
        assert(not m.scanProgress.scripts.OnUpdate and not m.scanProgress.pulse.shown)
        for i=1,80 do m:ProcessBatch(); assert(m.work.pendingCount<=6000) end
        assert(m.work.index==6000 and m.work.pendingCount==6000,'cold items no longer stop the first pass')
        local chunks=0; for _ in pairs(m.work.pending) do chunks=chunks+1 end
        assert(chunks<=math.ceil(6000/32),'pending indices use bounded numeric bit masks')
        assert(loadRequests[10]==1,'duplicate item IDs share a bounded load request')
        local weak=setmetatable({m.work,m.work.pending,m.work.loads},{__mode='v'})
        cold[10]=nil; now=now+.6
        while m.work do now=now+1/60; m:ProcessBatch() end
        local snapshot=MythicBoostMarketDB.snapshots[1]
        assert(snapshot.prices['10:0:0']==500 and snapshot.stats.priced==6000 and not snapshot.partial)
        assert(m.scanProgress.bar.value==1 and m.scanProgress.value.text:find('100%%'))
        assert(not m.scanProgress.scripts.OnUpdate and m.scanResult.skipped==0)
        collectgarbage('collect'); collectgarbage('collect')
        assert(next(weak)==nil,'completed work, pending entries and request registry must be collectible')
        epoch=epoch+900; cold[20]=true; lots={{id=20,price=20},{id=10,price=1000},{id=10,price=0},{id=9999999,price=20}}
        Scan(); snapshot=MythicBoostMarketDB.snapshots[2]
        assert(snapshot.partial and snapshot.stats.unloaded==1 and snapshot.stats.invalid==1)
        assert(snapshot.stats.noBuyout==1 and m.scanResult.skipped==2 and loadRequests[20]<=3)
        assert(m.diagnostics.text:find('данные 1',1,true) and m.diagnostics.text:find('некорректные 1',1,true))
        epoch=epoch+900; assert(m:StartScan()); Event('REPLICATE_ITEM_LIST_UPDATE'); m:ProcessBatch()
        weak=setmetatable({m.work,m.work.pending,m.work.loads},{__mode='v'})
        local timer=m.timeout
        m.scanButton.scripts.OnClick()
        collectgarbage('collect'); collectgarbage('collect')
        assert(not m.work and next(weak)==nil and timer.cancelled)
        assert(not m.events.scripts.OnUpdate and not m.scanProgress.scripts.OnUpdate and not m.scanProgress.shown)
        assert(#MythicBoostMarketDB.snapshots==2,'cancel cannot commit a half-built snapshot')
        -- Old snapshots remain readable; no reasons may be invented retroactively.
        snapshot.stats=nil; m:Render()
        assert(m.diagnostics.text:find('старом снимке',1,true))
        epoch=epoch+900; assert(m:StartScan()); timer=m.timeout
        m.frame:Hide(); assert(not m.scanProgress.scripts.OnUpdate and timer.cancelled)
        Open(); assert(not m.work and not m.scanProgress.shown)
    ''')


def test_repeated_cancel_memory():
    lua=fixture()
    lua.execute(r'''
        cold[10]=true; lots={{id=10,price=200}}
        local before=allocations
        local weak=setmetatable({},{__mode='v'})
        local memory
        for i=1,400 do
            epoch=epoch+900; Open(); assert(m:StartScan()); Event('REPLICATE_ITEM_LIST_UPDATE'); m:ProcessBatch()
            weak[i]=m.work
            m.frame:Hide(); Event('REPLICATE_ITEM_LIST_UPDATE')
            assert(not m.work and not m.events.scripts.OnUpdate and not m.scanProgress.scripts.OnUpdate)
            -- Test scheduler drops cancelled callbacks just as the engine does.
            timers={}
            if i==100 then collectgarbage('collect'); memory=collectgarbage('count') end
        end
        collectgarbage('collect'); collectgarbage('collect')
        assert(next(weak)==nil and allocations==before)
        assert(collectgarbage('count')-memory<96,'cancel cycles must not retain work tables')
        assert(#MythicBoostMarketDB.snapshots==0)
    ''')


if __name__=='__main__':
    for test in (test_scan_and_signals,test_bounds_variants_and_retention,
                 test_progress_cold_cache_and_release,test_repeated_cancel_memory):
        test(); print(test.__name__+': OK')
    code=source('Modules/AuctionMarket.lua')+source('Modules/AuctionMarketUI.lua')
    assert 'PlaceBid(' not in code and 'ConfirmCommoditiesPurchase(' not in code
    assert 'Падение цены — сигнал, не гарантия перепродажи.' not in code
