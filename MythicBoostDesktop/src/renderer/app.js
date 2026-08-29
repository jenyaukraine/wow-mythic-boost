function browserPreviewState() {
  const applicants = [
    { name: 'Aeloria', realm: 'Tarren Mill', region: 'eu', role: 2, classId: 2, itemLevel: 317, rating: 3214, id: 'preview' },
    { name: 'Velmora', realm: 'Draenor', region: 'eu', role: 8, classId: 8, itemLevel: 314, rating: 2988, id: 'preview' },
    { name: 'Sythrael', realm: 'Silvermoon', region: 'eu', role: 8, classId: 12, itemLevel: 312, rating: 2871, id: 'preview' },
  ];
  const dungeonNames = ['Алтарь Клыков', 'Спелящая долина', 'Берлога Налоракка', 'Закоулок душегубов', 'Арена Шрама Бездны', 'Рубиновые Омуты Жизни', 'Храм Сетралисс', 'Гробница королей'];
  const bossNames = ['Императрица Некслора', 'Разрушитель Бездны', 'Архонт Таэлис', 'Совет Перерождённых', 'Ночной страж', 'Сердце полуночи'];
  const profiles = {};
  applicants.forEach((applicant, index) => {
    const key = `${applicant.region}:${applicant.realm}:${applicant.name}`.toLowerCase();
    profiles[key] = {
      loading: false,
      errors: [],
      rio: {
        ...applicant,
        className: ['Paladin', 'Mage', 'Demon Hunter'][index],
        spec: ['Protection', 'Frost', 'Havoc'][index],
        score: applicant.rating,
        runs: dungeonNames.map((dungeon, runIndex) => ({ dungeon, level: 14 - Math.floor(runIndex / 2) - index, upgrades: runIndex === 6 ? 0 : (runIndex % 3) + 1, timed: runIndex !== 6, score: 178 - runIndex * 7 - index * 5 })),
        raidProgression: [{ slug: 'citadel-of-midnight', summary: index ? '8/8 H' : '6/8 M', totalBosses: 8, normal: 8, heroic: 8, mythic: index ? 0 : 6 }],
        profileUrl: 'https://raider.io',
      },
      logs: {
        available: true,
        bestAverage: 92 - index * 10,
        medianAverage: 79 - index * 8,
        bosses: bossNames.map((boss, bossIndex) => ({ boss, percent: 96 - bossIndex * 5 - index * 8, amount: 1642380 - bossIndex * 92000, kills: 9 - bossIndex })),
      },
    };
  });
  return { applicants, profiles, settings: { region: 'eu', autoOpen: true, alwaysOnTop: true }, source: 'mock' };
}

let browserState = browserPreviewState();
const api = window.mythicBoost || {
  getState: async () => browserState,
  saveSettings: async (settings) => { browserState.settings = settings; return settings; },
  refresh: async () => true,
  demo: async () => true,
  windowAction: async () => true,
  openExternal: (url) => window.open(url, '_blank', 'noopener'),
  onState: () => () => {},
  onStatus: () => () => {},
};

const CLASS = {
  1: ['Воин', '#c79c6e'], 2: ['Паладин', '#f58cba'], 3: ['Охотник', '#abd473'],
  4: ['Разбойник', '#fff569'], 5: ['Жрец', '#ffffff'], 6: ['Рыцарь смерти', '#c41f3b'],
  7: ['Шаман', '#0070de'], 8: ['Маг', '#40c7eb'], 9: ['Чернокнижник', '#8787ed'],
  10: ['Монах', '#00ff96'], 11: ['Друид', '#ff7d0a'], 12: ['Охотник на демонов', '#a330c9'],
  13: ['Пробудитель', '#33937f'],
};
const ROLE = { 2: 'ТАНК', 4: 'ЛЕКАРЬ', 8: 'БОЕЦ' };

let state = { applicants: [], profiles: {}, settings: {} };
let selectedKey = '';

const $ = (id) => document.getElementById(id);
const esc = (value) => String(value ?? '').replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
const profileKey = (applicant) => `${applicant.region}:${applicant.realm}:${applicant.name}`.toLowerCase();
const number = (value) => Number(value || 0).toLocaleString('ru-RU');
const compact = (value) => {
  value = Number(value || 0);
  if (value >= 1000000) return `${(value / 1000000).toFixed(2)}m`;
  if (value >= 1000) return `${(value / 1000).toFixed(1)}k`;
  return number(value);
};

function classInfo(id) { return CLASS[id] || ['Класс', '#9aa7b4']; }
function parseClass(percent) {
  if (percent >= 95) return 'legendary';
  if (percent >= 75) return 'epic';
  if (percent >= 50) return 'rare';
  return 'good';
}

function selectedApplicant() {
  return state.applicants.find((item) => profileKey(item) === selectedKey) || state.applicants[0];
}

function renderParty() {
  const strip = $('partyStrip');
  strip.innerHTML = state.applicants.map((applicant) => {
    const key = profileKey(applicant);
    const [className, color] = classInfo(applicant.classId);
    return `<button class="party-member ${key === selectedKey ? 'active' : ''}" data-key="${esc(key)}" style="--class-color:${color}">
      <span class="class-dot"></span><span><strong>${esc(applicant.name)}</strong><small>${esc(className)} · ${number(applicant.itemLevel)} ilvl</small></span>
      <span class="role-pill">${esc(ROLE[applicant.role] || 'РОЛЬ')}</span>
    </button>`;
  }).join('');
  strip.querySelectorAll('.party-member').forEach((button) => button.addEventListener('click', () => {
    selectedKey = button.dataset.key;
    render();
  }));
}

function bestRaid(progress) {
  return [...(progress || [])].sort((a, b) => (b.mythic * 100 + b.heroic * 10 + b.normal) - (a.mythic * 100 + a.heroic * 10 + a.normal))[0];
}

function renderKeys(rio) {
  const runs = rio?.runs || [];
  $('keysBody').innerHTML = runs.length ? runs.map((run) => `<tr>
    <td title="${esc(run.dungeon)}">${esc(run.dungeon)}</td>
    <td class="key-level">+${number(run.level)}</td>
    <td class="${run.timed ? 'timed' : 'depleted'}">${run.timed ? `вовремя +${run.upgrades}` : 'не в таймер'}</td>
    <td>${number(run.score)}</td>
  </tr>`).join('') : '<tr><td colspan="4">Записанных ключей не найдено</td></tr>';
}

function renderLogs(logs) {
  const notice = $('logsNotice');
  const body = $('bossesBody');
  if (!logs?.available) {
    $('logsBadge').textContent = logs?.reason === 'not-found' ? 'профиль не найден' : 'не настроено';
    $('logsBadge').classList.remove('online');
    notice.classList.remove('hidden');
    notice.textContent = logs?.reason === 'not-found'
      ? 'В Warcraft Logs нет публичного профиля этого персонажа.'
      : 'Добавь Warcraft Logs Client ID и Secret в настройках — после этого здесь появятся перцентили и урон по каждому боссу.';
    body.innerHTML = '';
    return;
  }
  notice.classList.add('hidden');
  $('logsBadge').textContent = logs.hidden ? 'логи скрыты' : 'подключено';
  $('logsBadge').classList.toggle('online', !logs.hidden);
  body.innerHTML = logs.bosses?.length ? logs.bosses.map((boss) => `<tr>
    <td title="${esc(boss.boss)}">${esc(boss.boss)}</td>
    <td><span class="parse ${parseClass(boss.percent)}">${number(boss.percent)}</span></td>
    <td>${compact(boss.amount)}</td><td>${number(boss.kills)}</td>
  </tr>`).join('') : '<tr><td colspan="4">Публичных разборов в текущем рейде нет</td></tr>';
}

function renderRaid(rio) {
  const progress = rio?.raidProgression || [];
  $('raidProgress').innerHTML = progress.length ? progress.map((raid) => `<article class="raid-chip">
    <strong>${esc(raid.summary)}</strong><small>${esc(raid.slug.replaceAll('-', ' '))} · M ${raid.mythic}/${raid.totalBosses} · H ${raid.heroic}/${raid.totalBosses}</small>
  </article>`).join('') : '<span class="panel-notice">Рейдовый прогресс не найден</span>';
}

function verdict(applicant, rio, logs) {
  const score = rio?.score || applicant.rating || 0;
  const ilvl = rio?.itemLevel || applicant.itemLevel || 0;
  const parse = logs?.bestAverage || 0;
  if (score >= 3000 && ilvl >= 312 && (!logs?.available || parse >= 70)) return ['Сильный кандидат', 'Высокий M+ опыт, хороший экипировочный порог и уверенные логи.'];
  if (score >= 2700 && ilvl >= 308) return ['Стоит рассмотреть', 'Опыт соответствует группе; проверь нужную роль и конкретные подземелья.'];
  return ['Нужна проверка', 'Оценка не заменяет просмотр ключей, состава и прогресса по боссам.'];
}

function renderProfile(applicant) {
  const entry = state.profiles[profileKey(applicant)] || { loading: true, applicant };
  const rio = entry.rio;
  const logs = entry.logs;
  const [className, color] = classInfo(applicant.classId);
  document.documentElement.style.setProperty('--class-color', color);

  $('applicantGroup').textContent = `ЗАЯВКА ${applicant.id || ''} · УЧАСТНИКОВ ${state.applicants.length}`;
  $('loadingBar').classList.toggle('hidden', !entry.loading);
  $('characterName').textContent = rio?.name || applicant.name;
  $('characterRealm').textContent = `— ${rio?.realm || applicant.realm}`;
  $('characterMeta').textContent = `${rio?.spec || className} · ${ROLE[applicant.role] || rio?.role || 'роль не указана'} · ${String(applicant.region).toUpperCase()}`;
  $('classMonogram').textContent = (rio?.className || className).slice(0, 1);
  $('classMonogram').classList.toggle('hidden', Boolean(rio?.thumbnailUrl));
  $('portrait').classList.toggle('hidden', !rio?.thumbnailUrl);
  if (rio?.thumbnailUrl) $('portrait').src = rio.thumbnailUrl;
  $('mainScore').textContent = number(rio?.score || applicant.rating) || '—';
  $('itemLevel').textContent = number(rio?.itemLevel || applicant.itemLevel) || '—';
  $('bestParse').textContent = logs?.available ? number(logs.bestAverage) : '—';

  const [title, reason] = verdict(applicant, rio, logs);
  $('verdict').textContent = entry.loading ? 'Собираю данные' : title;
  $('verdictReason').textContent = entry.loading ? 'Raider.IO и Warcraft Logs загружаются параллельно.' : reason;
  const raid = bestRaid(rio?.raidProgression);
  $('raidSummary').textContent = raid?.summary || '—';
  $('raidDetail').textContent = raid ? raid.slug.replaceAll('-', ' ') : 'Прогресс не найден';
  $('logsAverage').textContent = logs?.available ? `${number(logs.bestAverage)} best` : '—';
  $('logsMedian').textContent = logs?.available ? `${number(logs.medianAverage)} median` : 'Warcraft Logs не подключён';

  renderKeys(rio);
  renderLogs(logs);
  renderRaid(rio);
  $('rioLink').classList.toggle('hidden', !rio?.profileUrl);
  $('rioLink').onclick = () => rio?.profileUrl && api.openExternal(rio.profileUrl);

  const errors = entry.errors || [];
  $('errors').classList.toggle('hidden', !errors.length);
  $('errors').textContent = errors.join(' · ');
}

function render() {
  const hasApplicants = state.applicants?.length > 0;
  $('emptyState').classList.toggle('hidden', hasApplicants);
  $('dashboard').classList.toggle('hidden', !hasApplicants);
  $('sourceLabel').textContent = state.source === 'overwolf' ? 'WoW GEP подключён' : 'desktop / mock';
  if (!hasApplicants) return;
  if (!selectedKey || !state.applicants.some((item) => profileKey(item) === selectedKey)) selectedKey = profileKey(state.applicants[0]);
  renderParty();
  renderProfile(selectedApplicant());
}

function openSettings() {
  const value = state.settings || {};
  $('regionInput').value = value.region || 'eu';
  $('wclIdInput').value = value.wclClientId || '';
  $('wclSecretInput').value = value.wclClientSecret || '';
  $('autoOpenInput').checked = value.autoOpen !== false;
  $('alwaysTopInput').checked = value.alwaysOnTop !== false;
  $('settingsModal').classList.remove('hidden');
}

$('settingsBtn').addEventListener('click', openSettings);
$('settingsClose').addEventListener('click', () => $('settingsModal').classList.add('hidden'));
$('settingsForm').addEventListener('submit', async (event) => {
  event.preventDefault();
  await api.saveSettings({
    region: $('regionInput').value,
    wclClientId: $('wclIdInput').value.trim(),
    wclClientSecret: $('wclSecretInput').value.trim(),
    autoOpen: $('autoOpenInput').checked,
    alwaysOnTop: $('alwaysTopInput').checked,
  });
  $('settingsModal').classList.add('hidden');
});
$('refreshBtn').addEventListener('click', () => api.refresh());
$('demoBtn').addEventListener('click', () => api.demo());
$('minimizeBtn').addEventListener('click', () => api.windowAction('minimize'));
$('closeBtn').addEventListener('click', () => api.windowAction('close'));

api.onState((next) => { state = next; render(); });
api.onStatus((status) => { $('sourceLabel').textContent = status.text; });
api.getState().then((initial) => { state = initial; render(); });
