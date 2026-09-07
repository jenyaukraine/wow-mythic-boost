# Talent point scenarios (2.4.104)

The default tree mode distinguishes three quantities:

- `~2.4%`: modeled effect of changing **one rank** of a verified constant healing multiplier.
- `=10.2%`: measured share of a linked source; **not** the benefit of removing or replacing a point.
- No badge: no defensible marginal estimate or measured share. The unscored list
  in Details explains the missing inputs without filling the tree with questions.

The Details window ranks modeled points and cycles through invested points,
unselected modeled candidates, and talents without a marginal estimate. It shows
native refund/purchase/path status without changing any talent. Free points and
prerequisites are not automatically proposed as removable points. This is a
limited scenario model, not a full build optimizer or proof of the best build.

## Formula and cohort

For a spell subtotal `S`, overall `T`, current rank multiplier `1 + p[r]`,
and the adjacent rank `q`, the estimate is:

`100 * (S / T) * abs(p[q] - p[r]) / (1 + p[r])`

Removing an already selected +30% Swiftmend talent uses `30/130`, not `30/100`.
Adding the first rank uses `30/100`. This scenario assumes that the specified
modifier is independently multiplicative and that other modifiers and spell use
stay fixed. For healing, the effective/overheal proportion is also held fixed.
Actual effective healing can differ substantially when health deficits, timing,
procs, targets or overheal change. The displayed run range is an observed range
of model estimates, not a confidence interval. Independent point estimates must
not be summed, especially when their affected sources overlap.

By default all recorded keys for the applied build, specialization and exact game
build are included, across maps and levels. The Details scope button can narrow
this to the latest map and key level. Both modes weight spell amounts by the
matching overalls, never compare overall HPS between unlike keys. The window
shows the included sample count and total saved history count. If the applied build has no
measurements, the latest recorded build is explicitly labeled as the reference;
its rank is used in the formula, never the current or staged rank. Duplicated
runs and mixed builds are excluded. Numerators and denominators are summed before
division. Complete missing sources are zero; missing partial sources are unknown.
Partial rows include only recorded amounts and carry a warning. No history or
SavedVariables is rewritten; old records are reinterpreted at display time.

## Audited data: 12.1.0.69587, 2026-09-07

Primary exported spell/effect data:

- [Spell descriptions](https://raw.githubusercontent.com/simulationcraft/simc/midnight/engine/dbc/generated/spelltext_data.inc)
- [Spell/effect records](https://raw.githubusercontent.com/simulationcraft/simc/midnight/engine/dbc/generated/sc_spell_data.inc)
- [Trait records](https://raw.githubusercontent.com/simulationcraft/simc/midnight/engine/dbc/generated/trait_data.inc)
- [Native trait API](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/SharedTraitsDocumentation.lua)

All seven initial models are Restoration Druid (105), one verified rank. Other
specs, damage, unknown ranks and different game builds receive no reused coefficient.

| Talent ID | Coefficient | Affected source IDs included | Evidence / scope |
| --- | --- | --- | --- |
| 470549 Improved Swiftmend | 30% | 18562 | effect 1185949 |
| 455797 Cenarius' Might | 20% | 18562 | effect 1271618, Restoration branch |
| 429402 Grove's Inspiration | 9% | 8936, 18562, 48438 | effects 1113584/1113585; player heals only |
| 439926 Wildstalker's Power | 10% | 774, 33763, 81269, 155777 | effects 1133516/1133519/1133520 |
| 400533 Wild Synthesis | 30% | 81269, 422090 | **limited**: Efflorescence and treant Nourish; other summons excluded |
| 429215 Bounteous Bloom | 30% | 422090 | effect 1113274, Grove Guardian creature 54983 |
| 1217941 Lifetreading | 25% | 81269 | **limited**: effect 1202352; automatic placement/uptime not modeled |

New direct-source links: Ysera's Gift 145108 -> 145109/145110; Embrace of the Dream
392124 -> 392147; Verdancy 392325 -> 392329; Dream Surge 433831 -> 434141; Spirit of
the Thicket 1264899 -> 1264905. These are source shares, never passive modifiers.
Dryad Regrowth is deliberately not assigned to player Regrowth modifiers.

Conditional healing, received-healing bonuses, mana, HoT/mastery interactions,
crit, health thresholds, control, mitigation and haste are not assigned fabricated
percentages. Nurturing Instinct's rank curves remain unverified; its raw maximum
coefficient is not assumed to be a per-rank bonus.

## Verification

`Tools/TestTalentPointValue.py` exercises removing an existing modifier, adding a
new one, differing spell mixes, weighted aggregation, build/map/patch/rank gates,
complete zero vs partial unknown, invalid boolean values, duplicate runs, native
availability, UI navigation, row reuse and combat hiding. Existing source-history,
comparison, talent-tree and full release checks also remain required.
