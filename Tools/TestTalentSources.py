"""Verified source links, inclusive channels and mutually exclusive apex tiers."""
from lupa import LuaRuntime

from TestHudPolish import load


CHECK = r'''
local sources = assert(JP.TalentSources)
local resto = assert(sources[105])

local function assertId(v, label)
    assert(type(v) == "number" and v > 0 and v % 1 == 0, label .. " must be a positive integer spell id")
end

local seen = { healing = {}, damage = {} }
local rowCount = 0
for spec, rows in pairs(sources) do
    assertId(spec, "spec id")
    assert(type(rows) == "table", "spec rows must be tables")
    for talent, row in pairs(rows) do
        assertId(talent, "talent id")
        assert(type(row) == "table", "talent row must be a table")
        rowCount = rowCount + 1
        for key, ids in pairs(row) do
            if key == 'family' then assertId(ids, 'family') else
            assert(key == "healing" or key == "damage", "row contains an unsupported metric")
            assert(type(ids) == "table" and #ids > 0, "metric must be a non-empty array")
            for i, spell in ipairs(ids) do
                assert(i == 1 or ids[i - 1] < spell, "metric ids must be sorted and unique")
                assertId(spell, "source spell id")
                local previous=seen[key][spell]
                assert(not previous or (row.family and previous==row.family), 'unexpected duplicate source')
                seen[key][spell] = row.family or talent
            end
            end
        end
    end
end
assert(rowCount == 19, "verified class and hero source rows")

assert(#resto[155675].healing == 1 and resto[155675].healing[1] == 155777, "Germination mapping changed")
assert(#resto[200390].healing == 1 and resto[200390].healing[1] == 200389, "Cultivation mapping changed")
assert(#resto[145205].healing == 1 and resto[145205].healing[1] == 81269, "Efflorescence mapping changed")
assert(resto[155675].damage == nil and resto[200390].damage == nil and resto[145205].damage == nil,
    "class mappings must not gain guessed damage sources")
assert(resto[429433] == nil, "Blooming Infusion buff ids must not be treated as combat sources")
assert(resto[740].healing[1]==740 and resto[740].healing[2]==157982,'channel ticks and direct record both count')
assert(resto[439528].healing[1]==439530 and resto[439528].damage[1]==439531)
assert(resto[1226140].healing[1]==422090,'treant Nourish uses its own source')
assert(resto[1263879].healing[1]==1264376 and resto[474750].healing[1]==474760)
'''


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("JP = {}")
    load(lua, "Data/TalentSources.lua")
    lua.execute(CHECK)
    from TestTalentLab import fixture
    lua=fixture()
    lua.execute('''
        local sample={specID=105,complete=false,selected={
            [1]={spellID=740,rank=1},[2]={spellID=439528,rank=1},[3]={spellID=1226140,rank=1},
            [4]={spellID=1263879,rank=1},[5]={spellID=1244470,rank=4}},
            spells={healing={[740]=59,[157982]=4194,[439530]=8041,[422090]=8395,[1264376]=2847,[1244341]=6615}}}
        local totals={}
        for _,row in ipairs(lab:TalentRows(sample,'healing')) do totals[row.spellID]=row.amount end
        assert(totals[740]==4253,'direct record plus channel ticks exactly once')
        assert(totals[439528]==8041 and totals[1226140]==8395)
        assert(totals[1263879]==2847 and totals[1244470]==6615)
        sample.spells.healing[157982]=nil
        totals={}; for _,row in ipairs(lab:TalentRows(sample,'healing')) do totals[row.spellID]=row.amount end
        assert(totals[740]==59,'available part is preserved')
        sample.spells.healing[740]=nil
        for _,row in ipairs(lab:TalentRows(sample,'healing')) do
            if row.spellID==740 then assert(row.amount==nil,'missing partial channel is unknown') end
        end
    ''')
    print("test_talent_sources: OK")


if __name__ == "__main__":
    main()
