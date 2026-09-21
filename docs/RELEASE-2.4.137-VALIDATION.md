# MythicBoost 2.4.137 validation

Date: 2026-09-21

- Normal `Tools/BuildRelease.ps1` completed without `-SkipTests`.
- All 53 `Tools/Test*.py` files are included in the build and passed.
- Architecture: 80 TOC entries. Localization: 1290 keys in RU/EN/DE.
- Release ZIP verification passed. SHA256: `1FF3487BE61200E5DBF3B82E25935A7D25723842EC7EB169B5C7DEDC1E006F0B`.
- Installed addon files were compared with repository files using SHA256.

Updated obsolete fixtures supply launch badge widgets, journal children and encounter ownership, Contracts helpers and loot tooltip colors. Journal selection preserves a supported difficulty. UI expectations follow the new binding rows and Help route. Existing shared-key target fallback, opaque aura refresh and hidden healer target behavior are now reflected in tests. Production behavior was not changed to make these fixtures pass.

Survival tests cover both consumables together, rank 1 Silvermoon potion, remaining healthstone uses, temporary unusability, macro order, disable/re-enable, binding conflicts, combat lock and secret health rendering. Settings tests cover empty search, Cyrillic case folding, navigation, scrolling and reusable glow layers.

Limit: offline Lua mocks do not execute the live Blizzard secure action engine or verify visual appearance in WoW. No claim of zero possible in-game errors. The Blizzard cash shop was not modified.
