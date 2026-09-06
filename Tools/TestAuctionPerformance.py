"""Large synthetic native snapshots: throughput, bounded caches and cold-item fairness.

These are deterministic work/call-count tests, not claims about live WoW FPS.
"""
from TestAuctionMarket import fixture


def test_large_warm_snapshot_caches_identity_and_keeps_frame_budget():
    lua = fixture()
    lua.execute(r'''
        nativeCount=452163; infoCalls=0; identityCalls=0; profile=0
        function debugprofilestop() return profile end
        C_AuctionHouse.GetNumReplicateItems=function() return nativeCount end
        C_AuctionHouse.GetReplicateItemInfo=function(i)
            infoCalls=infoCalls+1; profile=profile+.001
            return 'Item',123,2,nil,nil,nil,nil,nil,nil,2000-(i%2)*100,
                nil,nil,nil,nil,nil,nil,1000+(i%512),true
        end
        C_AuctionHouse.GetReplicateItemLink=function(i)
            return '|Hitem:'..(1000+i%512)..':0:0:0:0:0:0:0:0|h[Item]|h'
        end
        local identify=m.Identity
        m.Identity=function(self,...)
            identityCalls=identityCalls+1; return identify(self,...)
        end
        assert(m:StartScan()); Event('REPLICATE_ITEM_LIST_UPDATE')
        local weak=setmetatable({m.work,m.work.linkKeys,m.work.linkRing},{__mode='v'})
        m:ProcessBatch()
        assert(m.work.index==1000, 'warm scans are no longer arbitrarily capped at 200 lots per frame')
        while m.work do
            local before=profile; m:ProcessBatch(); assert(profile-before<=2.01)
            now=now+1/60
        end
        local snapshot=MythicBoostMarketDB.snapshots[1]
        assert(infoCalls==nativeCount and snapshot.stats.priced==nativeCount)
        assert(identityCalls==512 and snapshot.count==512 and not snapshot.partial,
            'one identity decode per repeated exact link, every lot price still read')
        assert(snapshot.prices['1001:0:0']==950)
        collectgarbage('collect'); collectgarbage('collect'); assert(next(weak)==nil)

        epoch=epoch+900; profile=0; nativeCount=10000
        local read=C_AuctionHouse.GetReplicateItemInfo
        C_AuctionHouse.GetReplicateItemInfo=function(i) profile=profile+.25; return read(i) end
        assert(m:StartScan()); Event('REPLICATE_ITEM_LIST_UPDATE')
        m:ProcessBatch(); assert(m.work.index<=8 and profile<2.3,
            'a slow native API still yields at the 2 ms guard, not the 1000-step cap')
        m:StopScan()
    ''')


def test_cold_snapshot_does_not_block_readable_lots_or_allocate_per_lot():
    lua = fixture()
    lua.execute(r'''
        nativeCount=452163; profile=0; cacheReady=false
        function debugprofilestop() return profile end
        C_AuctionHouse.GetNumReplicateItems=function() return nativeCount end
        C_AuctionHouse.GetReplicateItemInfo=function(i)
            profile=profile+.001
            local id=i<nativeCount-1 and 10 or 20
            return 'Item',123,1,nil,nil,nil,nil,nil,nil,i==123456 and 50 or 100,
                nil,nil,nil,nil,nil,nil,id,id==20 or cacheReady
        end
        C_AuctionHouse.GetReplicateItemLink=function(i)
            if i<nativeCount-1 and not cacheReady then return nil end
            return '|Hitem:'..(i<nativeCount-1 and 10 or 20)..':0:0:0:0:0:0:0:0|h[Item]|h'
        end
        assert(m:StartScan()); Event('REPLICATE_ITEM_LIST_UPDATE')
        while m.work.index<nativeCount do m:ProcessBatch(); now=now+1/60 end
        assert(m.work.prices['20:0:0']==100 and m.work.pendingCount==nativeCount-1,
            'the readable last lot is processed even with 450k cold earlier lots')
        local chunks=0; for _,bits in pairs(m.work.pending) do
            chunks=chunks+1; assert(type(bits)=='number' and bits>=1 and bits<2^32)
        end
        assert(chunks<=math.ceil(nativeCount/32) and loadRequests[10]<=3)
        local weak=setmetatable({m.work,m.work.pending,m.work.loads},{__mode='v'})
        cacheReady=true; now=now+.6
        while m.work do m:ProcessBatch(); now=now+1/60 end
        local snapshot=MythicBoostMarketDB.snapshots[1]
        assert(not snapshot.partial and snapshot.stats.priced==nativeCount)
        assert(snapshot.prices['10:0:0']==50 and snapshot.stats.unloaded==0)
        collectgarbage('collect'); collectgarbage('collect'); assert(next(weak)==nil)
    ''')


def test_identity_cache_bound_and_exact_variants():
    lua = fixture()
    lua.execute(r'''
        for i=1,6000 do lots[i]={id=i,price=10000+i} end
        assert(m:StartScan()); Event('REPLICATE_ITEM_LIST_UPDATE')
        while m.work.index<5800 do m:ProcessBatch() end
        local count=0; for _ in pairs(m.work.linkKeys) do count=count+1 end
        assert(count==4096 and #m.work.linkRing==4096)
        m:StopScan(); epoch=epoch+900
        gear=true
        local a='|Hitem:10:0:0:0:0:0:-7:999:100|h[A]|h'
        local b='|Hitem:10:0:0:0:0:0:-7:999:200|h[B]|h'
        C_Item.GetDetailedItemLevelInfo=function(link) return link==a and 100 or 200 end
        lots={{id=10,price=900,link=a},{id=10,price=100,link=b},{id=10,price=800,link=a}}
        Scan(); local snapshot=MythicBoostMarketDB.snapshots[1]
        assert(snapshot.count==2 and snapshot.prices['10:100:-7']==800
            and snapshot.prices['10:200:-7']==100, 'same item ID with a different level is never merged by cache')
    ''')


if __name__ == '__main__':
    for test in (test_large_warm_snapshot_caches_identity_and_keeps_frame_budget,
                 test_cold_snapshot_does_not_block_readable_lots_or_allocate_per_lot,
                 test_identity_cache_bound_and_exact_variants):
        test()
        print(test.__name__ + ': OK')
