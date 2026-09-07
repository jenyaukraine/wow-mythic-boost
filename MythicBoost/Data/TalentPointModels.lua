local _, JP = ...

-- Audited against the 12.1.0.69587 spell/effect export on 2026-09-07.
-- Sources and limitations: docs/talent-point-models.md (repository).
-- These are explicit constant-multiplier scenarios, not source aliases.
-- Never infer coefficients, ranks, or affected spells from translated names.
JP.TalentPointModels = {
    gameBuild = "12.1.0:69587",
    [105] = {
        [470549] = { healing={18562}, ranks={.30} }, -- Improved Swiftmend, effect 1185949
        [455797] = { healing={18562}, ranks={.20} }, -- Cenarius' Might, effect 1271618
        [429402] = { healing={8936,18562,48438}, ranks={.09} }, -- Grove's Inspiration, 1113584/5
        [439926] = { healing={774,33763,81269,155777}, ranks={.10} }, -- Wildstalker's Power, 1133516/19/20
        [400533] = { healing={81269,422090}, ranks={.30}, limited=true }, -- Wild Synthesis: verified Efflo + treant only
        [429215] = { healing={422090}, ranks={.30} }, -- Bounteous Bloom, 1113274 (creature 54983)
        [1217941] = { healing={81269}, ranks={.25}, limited=true }, -- Lifetreading: constant part only, 1202352
    },
}
