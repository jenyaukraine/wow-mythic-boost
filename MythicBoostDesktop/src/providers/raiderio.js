const CACHE_TTL = 5 * 60 * 1000;
const cache = new Map();

function cacheKey(character) {
  return `${character.region}:${character.realm}:${character.name}`.toLowerCase();
}

function bestRuns(profile) {
  const sources = [
    profile.mythic_plus_best_runs,
    profile.mythic_plus_highest_level_runs,
    profile.mythic_plus_recent_runs,
  ];
  const byDungeon = new Map();
  for (const source of sources) {
    for (const run of source || []) {
      const name = run.dungeon || run.short_name;
      if (!name) continue;
      const current = byDungeon.get(name);
      if (!current || Number(run.mythic_level || 0) > Number(current.mythic_level || 0)) {
        byDungeon.set(name, run);
      }
    }
  }
  return [...byDungeon.values()]
    .sort((a, b) => Number(b.mythic_level || 0) - Number(a.mythic_level || 0))
    .slice(0, 8)
    .map((run) => ({
      dungeon: run.dungeon || run.short_name || 'Подземелье',
      shortName: run.short_name || '',
      level: Number(run.mythic_level || 0),
      score: Math.round(Number(run.score || 0)),
      upgrades: Number(run.num_keystone_upgrades || 0),
      timed: Boolean(run.num_keystone_upgrades > 0),
      completedAt: run.completed_at || null,
      url: run.url || '',
    }));
}

function normalize(profile) {
  const season = (profile.mythic_plus_scores_by_season || [])[0] || {};
  const gear = profile.gear || {};
  const progression = Object.entries(profile.raid_progression || {}).map(([slug, raid]) => ({
    slug,
    summary: raid.summary || '0/0',
    totalBosses: Number(raid.total_bosses || 0),
    normal: Number(raid.normal_bosses_killed || 0),
    heroic: Number(raid.heroic_bosses_killed || 0),
    mythic: Number(raid.mythic_bosses_killed || 0),
  }));
  return {
    name: profile.name,
    realm: profile.realm,
    region: profile.region,
    race: profile.race,
    className: profile.class,
    spec: profile.active_spec_name,
    role: profile.active_spec_role,
    faction: profile.faction,
    achievementPoints: profile.achievement_points || 0,
    itemLevel: Number(gear.item_level_equipped || gear.item_level_total || 0),
    score: Math.round(Number(profile.mythic_plus_scores_by_season?.[0]?.scores?.all || 0)),
    roleScores: season.scores || {},
    runs: bestRuns(profile),
    raidProgression: progression,
    profileUrl: profile.profile_url || '',
    thumbnailUrl: profile.thumbnail_url || '',
    raw: profile,
  };
}

async function fetchRaiderIO(character, options = {}) {
  const key = cacheKey(character);
  const cached = cache.get(key);
  if (!options.force && cached && Date.now() - cached.at < CACHE_TTL) return cached.value;

  const query = new URLSearchParams({
    region: character.region,
    realm: character.realm,
    name: character.name,
    fields: [
      'gear',
      'mythic_plus_scores_by_season:current',
      'mythic_plus_best_runs',
      'mythic_plus_highest_level_runs',
      'mythic_plus_recent_runs',
      'raid_progression',
    ].join(','),
  });
  const response = await fetch(`https://raider.io/api/v1/characters/profile?${query}`, {
    headers: { 'User-Agent': 'MythicBoostDesktop/0.1' },
    signal: AbortSignal.timeout(12000),
  });
  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Raider.IO ${response.status}: ${body.slice(0, 160)}`);
  }
  const value = normalize(await response.json());
  cache.set(key, { at: Date.now(), value });
  return value;
}

module.exports = { fetchRaiderIO, normalize };
