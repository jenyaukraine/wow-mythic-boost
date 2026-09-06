"""Regression tests for the deliberately small talent-source allowlist."""
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
            assert(key == "healing" or key == "damage", "row contains an unsupported metric")
            assert(type(ids) == "table" and #ids > 0, "metric must be a non-empty array")
            for i, spell in ipairs(ids) do
                assert(i == 1 or ids[i - 1] < spell, "metric ids must be sorted and unique")
                assertId(spell, "source spell id")
                assert(not seen[key][spell], "source spell id is attributed to multiple talents for one metric")
                seen[key][spell] = true
            end
        end
    end
end
assert(rowCount == 3, "allowlist should contain exactly the three verified class rows")

assert(#resto[155675].healing == 1 and resto[155675].healing[1] == 155777, "Germination mapping changed")
assert(#resto[200390].healing == 1 and resto[200390].healing[1] == 200389, "Cultivation mapping changed")
assert(#resto[145205].healing == 1 and resto[145205].healing[1] == 81269, "Efflorescence mapping changed")
assert(resto[155675].damage == nil and resto[200390].damage == nil and resto[145205].damage == nil,
    "class mappings must not gain guessed damage sources")
assert(resto[429433] == nil, "Blooming Infusion buff ids must not be treated as combat sources")
'''


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("JP = {}")
    load(lua, "Data/TalentSources.lua")
    lua.execute(CHECK)
    print("test_talent_sources: OK")


if __name__ == "__main__":
    main()
