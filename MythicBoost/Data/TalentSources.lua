local _, JP = ...

-- Sources checked 2026-09-07 against Blizzard data for 12.1.0.69587
-- exported by SimulationCraft (spell descriptions and effect triggers):
-- https://raw.githubusercontent.com/simulationcraft/simc/midnight/engine/dbc/generated/spelltext_data.inc
-- https://raw.githubusercontent.com/simulationcraft/simc/midnight/engine/dbc/generated/sc_spell_data.inc
-- https://raw.githubusercontent.com/simulationcraft/simc/midnight/engine/class_modules/sc_druid.cpp
-- https://raw.githubusercontent.com/simulationcraft/simc/midnight/engine/dbc/generated/trait_data.inc
--
-- IDs must be connected by spell text/triggers, never just similar names.
-- Lists are inclusive: Tranquility counts both its direct record and ticks.
-- Everbloom tiers share a node; only its active entry appears in a snapshot.
JP.TalentSources = {
    [105] = {
        -- Restoration Druid class talents.
        [155675] = { healing = { 155777 } }, -- Germination -> Rejuvenation (Germination)
        [200390] = { healing = { 200389 } }, -- Cultivation
        [145205] = { healing = { 81269 } },  -- Efflorescence
        [740] = { healing = { 740, 157982 } }, -- Tranquility, effect 293 -> 157982
        [385786] = { healing = { 385787 } }, -- Matted Fur, effect 1019276 -> absorb
        [439528] = { healing = { 439530 }, damage = { 439531 } }, -- Thriving Growth text
        [439901] = { healing = { 439902 } }, -- Flower Walk text
        [440120] = { healing = { 440121 }, damage = { 440122 } }, -- Bursting Growth text
        [474678] = { healing = { 474683 } }, -- Aessina's Renewal trigger and text
        [474750] = { healing = { 474760 } }, -- Child spell description references 474750
        [1226140] = { healing = { 422090 } }, -- Grove Guardians text -> treant Nourish
        [1244331] = { healing = { 1244341 }, family = 1244331 }, -- Everbloom's earlier tier
        [1244470] = { healing = { 1244341 }, family = 1244331 }, -- Same node, retains earlier tiers
        [1263879] = { healing = { 1264376 } }, -- Child spell description references 1263879
        [145108] = { healing = { 145109, 145110 } }, -- Ysera's Gift: self and other target
        [392124] = { healing = { 392147 } }, -- Embrace of the Dream: child description
        [392325] = { healing = { 392329 } }, -- Verdancy: talent text -> triggered heal
        [433831] = { healing = { 434141 } }, -- Dream Surge -> Dream Bloom
        [1264899] = { healing = { 1264905 } }, -- Spirit of the Thicket: talent text -> beam

        -- Keeper of the Grove hero talents are intentionally omitted here.
        -- Blooming Infusion's 429438/429474 records are buff definitions that
        -- modify/consume ordinary heals and damage, not separate combat
        -- actions; attributing them would double-count those base spells.
    },
}
