let tokenCache = null;

function realmSlug(realm) {
  return String(realm || '')
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9а-яё]+/gi, '-')
    .replace(/^-|-$/g, '');
}

async function getToken(clientId, clientSecret) {
  if (tokenCache && tokenCache.clientId === clientId && tokenCache.expiresAt > Date.now() + 30000) {
    return tokenCache.token;
  }
  const auth = Buffer.from(`${clientId}:${clientSecret}`).toString('base64');
  const response = await fetch('https://www.warcraftlogs.com/oauth/token', {
    method: 'POST',
    headers: {
      Authorization: `Basic ${auth}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: 'grant_type=client_credentials',
    signal: AbortSignal.timeout(12000),
  });
  if (!response.ok) throw new Error(`Warcraft Logs OAuth ${response.status}`);
  const data = await response.json();
  tokenCache = {
    clientId,
    token: data.access_token,
    expiresAt: Date.now() + Number(data.expires_in || 3600) * 1000,
  };
  return tokenCache.token;
}

function normalizeRankings(character) {
  const zone = character?.zoneRankings || {};
  const rankings = Array.isArray(zone.rankings) ? zone.rankings : [];
  const bosses = rankings.map((rank) => ({
    boss: rank.encounter?.name || rank.encounterName || rank.name || `Босс ${rank.encounterID || ''}`.trim(),
    percent: Math.round(Number(rank.rankPercent ?? rank.percentile ?? rank.percent ?? 0)),
    amount: Math.round(Number(rank.amount ?? rank.total ?? rank.bestAmount ?? 0)),
    kills: Number(rank.totalKills ?? rank.kills ?? 0),
    spec: rank.spec || rank.specName || '',
  }));
  return {
    available: true,
    hidden: Boolean(character?.hidden),
    bestAverage: Math.round(Number(zone.bestPerformanceAverage || 0)),
    medianAverage: Math.round(Number(zone.medianPerformanceAverage || 0)),
    difficulty: zone.difficulty || null,
    bosses,
  };
}

async function fetchWarcraftLogs(character, settings) {
  if (!settings.wclClientId || !settings.wclClientSecret) {
    return { available: false, reason: 'credentials' };
  }
  const token = await getToken(settings.wclClientId, settings.wclClientSecret);
  const query = `
    query CharacterOverlay($name: String!, $serverSlug: String!, $serverRegion: String!) {
      characterData {
        character(name: $name, serverSlug: $serverSlug, serverRegion: $serverRegion) {
          id
          name
          classID
          level
          hidden
          zoneRankings
        }
      }
    }
  `;
  const response = await fetch('https://www.warcraftlogs.com/api/v2/client', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      query,
      variables: {
        name: character.name,
        serverSlug: realmSlug(character.realm),
        serverRegion: character.region.toUpperCase(),
      },
    }),
    signal: AbortSignal.timeout(12000),
  });
  if (!response.ok) throw new Error(`Warcraft Logs ${response.status}`);
  const payload = await response.json();
  if (payload.errors?.length) throw new Error(payload.errors[0].message || 'Warcraft Logs query failed');
  const found = payload.data?.characterData?.character;
  if (!found) return { available: false, reason: 'not-found' };
  return normalizeRankings(found);
}

module.exports = { fetchWarcraftLogs, realmSlug, normalizeRankings };
