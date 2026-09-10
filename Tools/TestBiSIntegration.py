"""Execute real BiS data, context selection, active-spec changes and raid advice."""
from pathlib import Path
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


def load(lua, path):
    lua.eval("function(s) assert(load(s))('MythicBoost', JP) end")(
        (ROOT / 'MythicBoost' / path).read_text(encoding='utf-8-sig'))


def test_guide():
    lua = LuaRuntime()
    lua.execute('''JP={}; spec=105
        function GetSpecialization() return 1 end
        function GetSpecializationInfo() return spec end
        function issecretvalue() return false end''')
    for path in ('Data/SeasonTop.lua', 'Data/AutoBiS.lua', 'Modules/BiSData.lua'):
        load(lua, path)
    lua.execute('''
        local b=JP.BiSData
        local count=0; for _ in pairs(JP.AutoBiSData.specs) do count=count+1 end
        assert(count==40 and JP.AutoBiSData.specs[1480] and not JP.AutoBiSData.specs[1456])
        local slots={head=true,neck=true,shoulder=true,chest=true,waist=true,legs=true,
            feet=true,wrist=true,hands=true,ring=true,trinket=true,back=true,
            ['main-hand']=true,['off-hand']=true}
        for specID, guide in pairs(JP.AutoBiSData.specs) do
            assert(type(specID)=='number' and specID>0 and specID==math.floor(specID))
            assert(type(guide.slug)=='string' and guide.slug~='' and #guide.variants>0)
            for _,variant in ipairs(guide.variants) do
                assert(type(variant.name)=='string' and variant.name~='')
                assert(variant.context=='overall' or variant.context=='raid' or variant.context=='mplus')
                assert(next(variant.items), 'every advertised variant must contain recommendations')
                for itemID,item in pairs(variant.items) do
                    assert(type(itemID)=='number' and itemID>0 and itemID==math.floor(itemID))
                    assert(slots[item.slot] and type(item.name)=='string' and item.name~='')
                    assert(type(item.dropSource)=='string' and type(item.dropKind)=='string')
                end
            end
        end
        assert(b:GetItem(105,250214,'mplus').variant=='Mythic+ Only')
        assert(not b:GetItem(105,250214,'raid'), 'M+-only list must not mark raid BiS')
        assert(b:GetItem(105,270162,'raid').dropSource~='')
        assert(not b:GetItem(105,270162,'mplus'), 'dedicated M+ overrides overall')
        assert(b:GetItem(270,193763,'raid'))
        assert(b:GetItem(270,193763).variant=='Raid BiS', 'generic lookup preserves variant labels')
        assert(not b:GetItem(270,193763,'mplus'))
        assert(b:GetItem(270,268253,'mplus'))
        assert(not b:GetItem(270,268253,'raid'))
        assert(not b:GetItem(105,999999,'raid'))
        local guide,top=b:GetSourceStatus(); assert(guide.updatedAt=='2026-09-08' and top==nil)
        spec=1480; assert(b:GetCurrentSpecID()==1480)
        assert(b:GetItem(b:GetCurrentSpecID(),270164,'raid'))
        -- No stale Murlok or old curated fallback for a fully covered spec.
        JP.SeasonTopData.specs[105].items[999999]={share=100}
        assert(not b:GetItem(105,999999,'mplus'))
    ''')


def test_raid_advice():
    lua = LuaRuntime()
    lua.execute('''
        JP={L=function(s) return s end,UI={UsableNumber=function(n) return type(n)=='number' end},
            RegisterModule=function() end,modules={}}
        function wipe(t) for k in pairs(t) do t[k]=nil end end
        function issecretvalue() return false end
        spec=105; difficulty=8; previewCalls=0; scans=0; fail=false; empty=false; bagOwned=false
        function GetSpecialization() return 1 end
        function GetSpecializationInfo() return spec end
        function UnitClass() return 'Druid','DRUID',11 end
        function GetInventoryItemID(_,slot) return slot==13 and 900 or slot==14 and 901 end
        function GetInventoryItemLink(_,slot) if slot==13 or slot==14 then return '300' end end
        function GetTime() return 10 end
        C_Item={GetDetailedItemLevelInfo=function(link) return tonumber(link) or 0 end,
            GetItemInfoInstant=function(id) return id,nil,nil,'INVTYPE_TRINKET' end}
        C_Container={GetContainerNumSlots=function(bag) return bag==0 and bagOwned and 1 or 0 end,
            GetContainerItemID=function() return 270162 end,GetContainerItemLink=function() return '330' end}
        EncounterJournal={instanceID=99}; selected=99; classFilter=1; specFilter=71; slotFilter=12
        function EJ_GetDifficulty() return difficulty end
        function EJ_SetDifficulty(d) difficulty=d end
        function EJ_SelectInstance(id) selected=id; difficulty=1 end
        function EJ_GetLootFilter() return classFilter,specFilter end
        function EJ_SetLootFilter(c,s) classFilter=c; specFilter=s end
        function EJ_GetNumLoot() scans=scans+1; return empty and 0 or 3 end
        C_EncounterJournal={GetInstanceForGameMap=function() return 77 end,
            GetSlotFilter=function() return slotFilter end,SetSlotFilter=function(s) slotFilter=s end,
            ResetSlotFilter=function() slotFilter=0 end,
            SetPreviewMythicPlusLevel=function() previewCalls=previewCalls+1 end,
            GetLootInfoByIndex=function(i)
                assert(selected==77 and (difficulty==14 or difficulty==15))
                assert(classFilter==11 and specFilter==spec and slotFilter==0)
                if fail then error('bad journal') end
                if missing and i==2 then return nil end
                local id=i==2 and 270167 or 270162
                return {itemID=id,name='item'..id,link=tostring((difficulty==15 and 320 or 305)+(i==2 and 7 or 0)),
                    encounterID=i==2 and 202 or 201,filterType=13}
            end}
    ''')
    for path in ('Contracts.lua', 'Data/AutoBiS.lua', 'Modules/BiSData.lua', 'Modules/LootAdvisor.lua'):
        load(lua, path)
    lua.execute('''
        local a=JP.LootAdvisor; local raids={{mapID=55,journalID=77}}
        local r=a:Analyze(raids,nil,14)[55]
        assert(r.total==2 and r.bisCount==2 and #r.upgrades==2, 'deduplicate journal entries')
        local levels={}; for _,i in ipairs(r.upgrades) do levels[i.itemID]=i.level; assert(i.encounterID) end
        assert(levels[270162]==305 and levels[270167]==312, 'use per-boss raid ilvl')
        assert(previewCalls==0, 'never invoke M+ preview for a raid')
        assert(selected==99 and difficulty==8 and classFilter==1 and specFilter==71 and slotFilter==12)
        local before=scans; a:Analyze(raids,nil,14); assert(scans==before)
        r=a:Analyze(raids,nil,15)[55]; assert(r.upgrades[1].level==327)
        spec=1480; r=a:Analyze(raids,nil,15)[55]; assert(r.bisCount==1,'active spec must invalidate cache')
        spec=105; bagOwned=true; a:Invalidate(); r=a:Analyze(raids,nil,15)[55]
        assert(r.useful==1 and r.upgrades[1].itemID==270167, 'owned raid goal hidden')
        empty=true; a:Invalidate(); r=a:Analyze(raids,nil,15)[55]; assert(r.pending and a.cache.pending)
        empty=false; missing=true; a:Invalidate(); r=a:Analyze(raids,nil,15)[55]
        assert(r.pending and a.cache.pending, 'nil journal row must not become a complete cached result')
        missing=false; r=a:Analyze(raids,nil,15)[55]
        assert(r.total==2 and not r.pending, 'retry missing journal rows once their data arrives')
        empty=false; fail=true; a:Invalidate(); assert(not pcall(a.Analyze,a,raids,nil,15))
        assert(selected==99 and difficulty==8 and classFilter==1 and specFilter==71 and slotFilter==12,
            'restore journal even after failure')
    ''')


def test_raid_tooltip():
    from TestGroupTools import fixture
    lua = fixture()
    load(lua, 'Modules/RaidFinder.lua')
    lua.execute('''
        lines={}
        GameTooltip={SetOwner=function() end,SetText=function(_,s) lines={s} end,
            AddLine=function(_,s) lines[#lines+1]=s end,Show=function() end}
        JP.BiSData={GetSourceStatus=function() return {source='AutoBiS',updatedAt='2026-09-08'} end}
        JP.GroupSearchUI={LootDelta=function(item) return tostring(item.level) end}
        local r=JP.RaidFinder; r.lootDifficulty=15
        r.loot={[55]={pending=false,upgrades={
            {name='First boss item',encounterID=201,level=320,recommendation={variant='Raid BiS',dropSource='First boss'}},
            {name='Second boss item',encounterID=202,level=327}}}}
        r:LootTooltip({groupID=55,boss='First boss',encounterID=201})
        local text=table.concat(lines,'|')
        assert(text:find('First boss item',1,true) and text:find('Raid BiS',1,true))
        assert(not text:find('Second boss item',1,true),'boss tooltip must filter the actual encounter')
        r:LootTooltip({groupID=55,boss='Unknown boss'})
        assert(not table.concat(lines,'|'):find('First boss item',1,true),'unknown encounter must not show entire raid loot')
        r:LootTooltip({groupID=55,groupName='Raid'})
        assert(table.concat(lines,'|'):find('Second boss item',1,true))
    ''')


if __name__ == '__main__':
    test_guide()
    test_raid_advice()
    test_raid_tooltip()
    print('BiS integration: 40 specs, M+/raid variants, active-spec changes, ownership and raid journal passed')
