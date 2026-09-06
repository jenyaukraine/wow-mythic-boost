local _, JP = ...

-- Sources checked 2026-09-06 against the SimulationCraft midnight branch:
-- https://raw.githubusercontent.com/simulationcraft/simc/midnight/engine/class_modules/sc_druid.cpp
-- https://raw.githubusercontent.com/simulationcraft/simc/midnight/engine/dbc/generated/trait_data.inc
--
-- This is intentionally a small allowlist.  A source is listed only when the
-- simulator gives the talent a distinct combat spell id; passive effects and
-- effects merged into the base spell are omitted.
JP.TalentSources = {
    [105] = {
        -- Restoration Druid class talents.
        [155675] = { healing = { 155777 } }, -- Germination -> Rejuvenation (Germination)
        [200390] = { healing = { 200389 } }, -- Cultivation
        [145205] = { healing = { 81269 } },  -- Efflorescence

        -- Keeper of the Grove hero talents are intentionally omitted here.
        -- Blooming Infusion's 429438/429474 records are buff definitions that
        -- modify/consume ordinary heals and damage, not separate combat
        -- actions; attributing them would double-count those base spells.
    },
}
