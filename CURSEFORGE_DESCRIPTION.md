# MythicBoost

**Build smarter Mythic+ groups with complete LFG results, applicant analysis, teammate history, loot planning, and an optional compact UI.**

MythicBoost turns the Retail Group Finder into a complete Mythic+ workflow: find a suitable group, build a team for your own Keystone, compare every applicant dungeon by dungeon, review the run, and remember the teammates worth inviting again.

The addon is not just a unit-frame replacement. Group search, applicant analysis, run history, teammate tracking, loot planning, and upgrades form the core. HUD replacements and automatic conveniences are optional and disabled on a fresh profile.

## Find the right group

- Search all eight seasonal dungeons from one screen.
- See your personal best, next rating target, and useful-loot chance on each dungeon card.
- Filter by key range, leader rating, completed +10 runs, free party slots, tank, healer, Bloodlust, battle resurrection, previous declines, and full-party dungeon experience.
- Use **Only rating upgrades** to focus on keys above your personal record.
- Keep the real Blizzard result set visible: matching groups stay on top, while everything else moves to a grey section with a concrete rejection reason.
- Allow or disable manual applications from the grey section without changing the filter calculation.
- Inspect every listed member's dungeon history in a full party-by-dungeon table.
- Use the five-application optimizer to avoid wasting limited active application slots.

When the Retail API protects a listing's exact key level, MythicBoost does not invent a value or silently delete the row. Confirmed low keys are marked below the filters; unknown results remain visible with an honest fallback.

## Build a group for your Keystone

- Your current Keystone dungeon is highlighted with a gold column through the entire applicant table.
- Compare role, item level, rating, and best run in every seasonal dungeon for each applicant.
- Package applications such as duos and trios stay together, show the complete roster, and give every member a separate indexed dungeon table.
- See missing roles and likely class utility such as Bloodlust, battle resurrection, dispels, purge, and soothe.
- Get a conservative safe-level estimate, confidence value, and weakest-link warning based on dungeon-specific experience rather than one overall score.
- Optionally require that every current member has already completed the target key; this strict filter is always off by default.

## Learn from completed runs

MythicBoost stores compact local summaries after Mythic+ runs: duration, timer result, deaths and penalty, interrupts, and route checkpoints. The teammate history ranks people by their latest known Raider.IO score and shows runs together, timed-run rate, last shared dungeon, and last-played time. Storage is capped at 200 players and 30 runs.

## Gear, loot, and guild progress

- Scan equipped slots to see upgrade steps, crest track, missing crests, and gold cost.
- Compare Mythic+ drops and highlight potentially useful dungeon loot.
- View a guild Raider.IO leaderboard with the top three and a scrollable roster.
- Optionally mark promising players whose gear is ahead of their current rating.

## Optional compact HUD

The dedicated **Unit Frames** settings page controls player and target frame scale, opacity, health and resource numbers, portrait animation, class/level badges, auras, and class-resource segments. Resource height, spacing, brightness, and empty segments can all be tuned independently.

Optional modules also include a compact cast bar, loot window, Minimal UI layout, smart clicks, RCLootCouncil bridge, and error log. They are opt-in so MythicBoost can coexist with an existing interface.

An anonymous screenshot mode provides five fictional player/target scenes without reading character, realm, or chat data.

## Compatibility and safety

- World of Warcraft Retail, Interface 12.1.0.
- Russian, English, and German UI text.
- Raider.IO is optional and recommended for richer dungeon history, guild ranking, and strict party-experience checks.
- Protected Blizzard actions still require a real player click and applications use Blizzard's standard dialog.
- No executable downloads, advertisements, donations, external tracking, or addon-owned network service.

## Commands

- `/mb` - open or close MythicBoost
- `/mb filter` - open group filters
- `/mb modules` - show module status
- `/mb players` - show the number of saved promising players
- `/mb log` - show the diagnostic log
- `/mb reload` - reload the interface

