"""Executable regression checks for per-item upgrade currency shortages."""
from pathlib import Path
from lupa import LuaRuntime


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "MythicBoost/Modules/UpgradeCalculator.lua").read_text(encoding="utf-8-sig")


def test_per_item_shortage_and_unknown_balance():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
        function issecretvalue(v) return type(v) == 'table' and v.secret end
        JP = {L=function(s) return s end, UI={colors={}}}
        JP.UI.SafeNumber = function(v) return type(v) == 'number' and v end
        JP.UI.SafeString = function(v) return type(v) == 'string' and v end
        JP.Settings=function() return {} end
        JP.RegisterModule=function() end
        C_CurrencyInfo={GetCurrencyInfo=function(id)
            if id == 2 then return {name='Crest', quantity=5, quality=2, iconFileID=7} end
            if id == 3 then return {name='Unknown', quantity=Secret({}), quality=3, iconFileID=8} end
        end}
        function Secret(v) return setmetatable({secret=true, visual=v}, {__tostring=function() error('secret') end}) end
    ''')
    loader = lua.eval("function(code) return assert(load(code))('MythicBoost', JP) end")
    loader(SOURCE)
    lua.execute(r'''
        local s=JP.UpgradeCalculator
        s.tracks={{currencyID=2,color={1,1,1},label='Crest'},
                  {currencyID=3,color={1,1,1},label='Unknown'}}
        local known=s:FormatCrests({crests={[2]=12}})
        assert(known == '|cffffffff12|r')
        local knownReason=s:FormatCrestShortages({crests={[2]=12}})
        assert(knownReason == 'Crest: 7', knownReason)
        local unknown=s:FormatCrestShortages({crests={[3]=12}})
        assert(unknown == 'Unknown: —', unknown)
    ''')


def test_forecast_real_scan_cumulative_steps_and_shared_wallet():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
        JP={L=function(s) return s end, UI={colors={}}}
        function JP.UI.SafeNumber(v) return type(v)=='number' and v==v and v~=math.huge and v or nil end
        function JP.UI.SafeString(v) return type(v)=='string' and v or nil end
        store={schema=2,slots={}}
        JP.Settings=function() return store end; JP.RegisterModule=function() end
        levels={}; items={}; wallet={[2]=60}; money=1000; current=1; badCost=false
        for _,slot in ipairs({1,2,3,15,5,9,10,6,7,8,11,12,13,14,16,17}) do
            items[slot]=slot; levels[slot]=600
        end
        function GetInventoryItemLink(_,slot) return items[slot] and 'item:'..items[slot] end
        function GetInventoryItemTexture() return 1 end
        function GetItemInfoInstant(link)
            local id=tonumber(link:match('item:(%d+)'))
            return id,nil,nil,id==16 and (twoHand and 'INVTYPE_2HWEAPON' or 'INVTYPE_WEAPON') or 'INVTYPE_HEAD'
        end
        C_Item={GetDetailedItemLevelInfo=function(link) return levels[GetItemInfoInstant(link)] end}
        C_CurrencyInfo={GetCurrencyInfo=function(id)
            if wallet[id]~=nil then return {name='Crest',quantity=wallet[id],quality=1} end
        end}
        function GetMoney() return money end
        ItemLocation={CreateFromEquipmentSlot=function(_,slot)
            return {slot=slot,IsValid=function() return items[slot]~=nil end}
        end}
        ItemUpgradeFrame={IsShown=function() return true end}
        C_ItemUpgrade={GetItemUpgradeItemInfo=function(location)
            local slot=location.slot
            local canUpgrade=slot==1 or slot==2 or slot==16
            local rows={{upgradeLevel=1,itemLevelIncrement=0,currencyCostsToUpgrade={}}}
            if canUpgrade then
                for i=2,4 do rows[#rows+1]={upgradeLevel=i,itemLevelIncrement=(i-1)*3,
                    currencyCostsToUpgrade={{currencyID=2,cost=badCost and {} or 10}},moneyCost=1} end
            end
            return {itemID=items[slot],currUpgrade=1,maxUpgrade=canUpgrade and 4 or 1,
                maxItemLevel=canUpgrade and 609 or 600,upgradeLevelInfos=rows}
        end}
    ''')
    lua.eval("function(code) assert(load(code))('MythicBoost',JP) end")(SOURCE)
    lua.execute(r'''
        local m=JP.UpgradeCalculator
        m:ScanAtUpgrader(); m:Scan()
        assert(m.forecastCurrent==600, 'read row.ilvl, not nonexistent itemLevel')
        assert(m.forecastAfter==601.125, 'shared wallet / cumulative increment: '..tostring(m.forecastAfter))
        assert(wallet[2]==60 and money==1000, 'forecast never mutates live funds')
        local before=store.slots[1].upgradeLevels[4].itemLevelIncrement
        collectgarbage('collect'); local baseline=collectgarbage('count')
        for i=1,1000 do m:Scan() end
        collectgarbage('collect'); assert(collectgarbage('count')-baseline<64)
        assert(before==store.slots[1].upgradeLevels[4].itemLevelIncrement)
        wallet[2]=0; m:Scan(); assert(m.forecastAfter==600)
        wallet[2]=60; money=1; m:Scan(); assert(m.forecastAfter==600+3/16)
        money=1000; wallet[2]=nil; m:Scan(); assert(m.forecastAfter==nil, 'unknown wallet is not zero')
        wallet[2]=60; store.slots[1].upgradeLevels=nil; m:Scan()
        assert(m.forecastAfter==nil, 'old snapshots need a fresh NPC scan')
        badCost=true; m:ScanAtUpgrader(); m:Scan()
        assert(m.forecastAfter==nil, 'unknown cost cannot become a free upgrade')
        badCost=false; m:ScanAtUpgrader()
        levels[1]=603; m:Scan(); assert(m.forecastAfter==nil, 'stale gear invalidates projection')
        levels[1]=600; twoHand=true; items[17]=nil; wallet[2]=90
        m:ScanAtUpgrader(); m:Scan()
        assert(m.forecastCurrent==600 and m.forecastAfter==602.25, 'two hand weapon fills two ilvl slots')
        store.slots[1].upgradeLevels[2].blocked=true; m:Scan()
        assert(m.forecastAfter==600+27/16, 'native upgrade restriction must stop that item')
    ''')


if __name__ == "__main__":
    for test in (test_per_item_shortage_and_unknown_balance,
                 test_forecast_real_scan_cumulative_steps_and_shared_wallet):
        test()
        print(test.__name__ + ": OK")
