const path = require('node:path');
const { app, BrowserWindow, ipcMain, shell } = require('electron');
const { fetchRaiderIO } = require('./providers/raiderio');
const { fetchWarcraftLogs } = require('./providers/warcraftlogs');
const { loadSettings, saveSettings, publicSettings } = require('./settings');

const WOW_GAME_ID = 765;
const TERMINAL_STATUSES = new Set([3, 4, 5, 6, 7, 8, 9]);
const ROLE_FROM_CODE = { 2: 'tank', 4: 'healer', 8: 'dps' };
const MOCK_MODE = process.argv.includes('--mock');

let desktopWindow;
let overlayWindow;
let overlayApi;
let settings;
let applicants = [];
const profiles = new Map();

function windowOptions(overrides = {}) {
  return {
    width: 980,
    height: 720,
    minWidth: 720,
    minHeight: 520,
    frame: false,
    transparent: false,
    backgroundColor: '#080d13',
    resizable: true,
    show: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
    },
    ...overrides,
  };
}

async function loadRenderer(win) {
  await win.loadFile(path.join(__dirname, 'renderer', 'index.html'));
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (/^https:\/\/(raider\.io|www\.warcraftlogs\.com)\//i.test(url)) shell.openExternal(url);
    return { action: 'deny' };
  });
}

async function createDesktopWindow() {
  desktopWindow = new BrowserWindow(windowOptions({
    title: 'MythicBoost Desktop',
    alwaysOnTop: Boolean(settings.alwaysOnTop),
  }));
  await loadRenderer(desktopWindow);
  desktopWindow.once('ready-to-show', () => desktopWindow.show());
  desktopWindow.on('closed', () => { desktopWindow = null; });
}

function allWindows() {
  const windows = [];
  if (desktopWindow && !desktopWindow.isDestroyed()) windows.push(desktopWindow);
  if (overlayWindow?.window && !overlayWindow.window.isDestroyed()) windows.push(overlayWindow.window);
  return windows;
}

function send(channel, payload) {
  for (const win of allWindows()) win.webContents.send(channel, payload);
}

function state() {
  return {
    applicants,
    profiles: Object.fromEntries(profiles.entries()),
    settings: publicSettings(settings),
    source: app.overwolf && !MOCK_MODE ? 'overwolf' : 'mock',
  };
}

function broadcastState() {
  send('mb:state', state());
}

function showCandidateWindow() {
  const target = overlayWindow?.window || desktopWindow;
  if (!target || target.isDestroyed()) return;
  if (settings.autoOpen) {
    target.show();
    target.moveTop();
  }
}

function applicantKey(value) {
  return `${value.region}:${value.realm}:${value.name}`.toLowerCase();
}

function normalizeApplicant(raw, fallbackName) {
  const name = raw.player_name || raw.name || fallbackName || '';
  const realm = raw.server_name || raw.realm || '';
  if (!name || !realm) return null;
  return {
    id: String(raw.applicant_id || raw.id || `${name}-${realm}`),
    key: `${String(raw.applicant_id || 'solo')}:${name}-${realm}`.toLowerCase(),
    name,
    realm,
    region: String(raw.region || settings?.region || 'eu').toLowerCase(),
    role: Number(raw.role || 0),
    classId: Number(raw.class || raw.class_id || 0),
    itemLevel: Number(raw.item_level || 0),
    rating: Number(raw.rating || 0),
    level: Number(raw.level || 0),
    status: Number(raw.application_status ?? 1),
  };
}

function decodePayload(value) {
  if (typeof value === 'string') {
    try { return JSON.parse(value); } catch (_) { return null; }
  }
  return value;
}

function extractApplicantPayload(data) {
  const candidates = [
    data?.info?.game_info?.group_applicants,
    data?.game_info?.group_applicants,
    data?.group_applicants,
    data?.data?.info?.game_info?.group_applicants,
  ];
  return decodePayload(candidates.find((value) => value != null));
}

function flattenApplicants(payload) {
  const result = [];
  const visit = (value, key) => {
    value = decodePayload(value);
    if (!value || typeof value !== 'object') return;
    if (value.player_name || value.name) {
      const applicant = normalizeApplicant(value, key);
      if (applicant && !TERMINAL_STATUSES.has(applicant.status)) result.push(applicant);
      return;
    }
    for (const [childKey, child] of Object.entries(value)) visit(child, childKey);
  };
  visit(payload, '');
  return result;
}

async function enrichApplicant(applicant, force = false) {
  const key = applicantKey(applicant);
  profiles.set(key, { loading: true, applicant, rio: null, logs: null, errors: [] });
  broadcastState();
  const errors = [];
  let rio = null;
  let logs = null;
  try {
    rio = await fetchRaiderIO(applicant, { force });
  } catch (error) {
    errors.push(error.message);
  }
  const lookup = rio ? { ...applicant, realm: rio.realm || applicant.realm, region: rio.region || applicant.region } : applicant;
  try {
    logs = await fetchWarcraftLogs(lookup, settings);
  } catch (error) {
    errors.push(error.message);
  }
  profiles.set(key, { loading: false, applicant, rio, logs, errors });
  broadcastState();
}

function setApplicants(next) {
  const oldKeys = new Set(applicants.map(applicantKey));
  applicants = next;
  broadcastState();
  for (const applicant of next) {
    const key = applicantKey(applicant);
    if (!profiles.has(key)) enrichApplicant(applicant);
    if (!oldKeys.has(key)) showCandidateWindow();
  }
}

function onGepInfo(data) {
  const payload = extractApplicantPayload(data);
  if (payload == null) return;
  setApplicants(flattenApplicants(payload));
}

async function createOverlayWindow() {
  if (!overlayApi || overlayWindow?.window) return;
  overlayWindow = await overlayApi.createWindow({
    name: 'mythicboost-applicants',
    width: 980,
    height: 720,
    minWidth: 720,
    minHeight: 520,
    transparent: false,
    resizable: true,
    show: true,
    dpiAware: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
    },
  });
  await loadRenderer(overlayWindow.window);
  overlayWindow.window.show();
}

function initializeGep() {
  const gep = app.overwolf?.packages?.gep;
  if (!gep) return;
  gep.removeAllListeners();
  gep.on('game-detected', async (event, gameId) => {
    if (gameId !== WOW_GAME_ID) return;
    event.enable();
    await gep.setRequiredFeatures(gameId, ['game_info']);
    try { onGepInfo(await gep.getInfo(gameId)); } catch (_) {}
  });
  gep.on('new-info-update', (_event, gameId, data) => {
    if (gameId === WOW_GAME_ID) onGepInfo(data);
  });
  gep.on('error', (_event, gameId, error) => {
    if (gameId === WOW_GAME_ID) send('mb:status', { type: 'error', text: String(error) });
  });
}

function initializeOverlay() {
  overlayApi = app.overwolf?.packages?.overlay;
  if (!overlayApi) return;
  overlayApi.registerGames({ gamesIds: [WOW_GAME_ID], all: false });
  overlayApi.on('game-launched', (event, gameInfo) => {
    if (gameInfo.id === WOW_GAME_ID || gameInfo.classId === WOW_GAME_ID) event.inject();
    else event.dismiss();
  });
  overlayApi.on('game-injected', () => createOverlayWindow().catch(console.error));
  overlayApi.on('game-exit', () => {
    if (overlayWindow?.window) overlayWindow.window.close();
    overlayWindow = null;
  });
}

function bindOverwolfPackages() {
  if (!app.overwolf?.packages) return;
  app.overwolf.packages.on('ready', (_event, name) => {
    if (name === 'gep') initializeGep();
    if (name === 'overlay') initializeOverlay();
  });
}

function addDemoApplicants() {
  const demo = [
    { name: 'Aeloria', realm: 'Tarren Mill', region: 'eu', role: 2, classId: 2, itemLevel: 317, rating: 3214, level: 90, id: 'demo-1', status: 1 },
    { name: 'Velmora', realm: 'Draenor', region: 'eu', role: 8, classId: 8, itemLevel: 314, rating: 2988, level: 90, id: 'demo-1', status: 1 },
    { name: 'Sythrael', realm: 'Silvermoon', region: 'eu', role: 8, classId: 12, itemLevel: 312, rating: 2871, level: 90, id: 'demo-1', status: 1 },
  ].map((entry) => normalizeApplicant(entry));
  applicants = demo;
  const dungeons = [
    ['Алтарь Клыков', 14, 2, 176], ['Спелящая долина', 13, 1, 164],
    ['Берлога Налоракка', 13, 3, 169], ['Закоулок душегубов', 12, 2, 151],
    ['Арена Шрама Бездны', 12, 1, 148], ['Рубиновые Омуты Жизни', 12, 2, 146],
    ['Храм Сетралисс', 11, 0, 130], ['Гробница королей', 11, 1, 128],
  ];
  const bosses = [
    ['Императрица Некслора', 96, 1642380, 7], ['Разрушитель Бездны', 91, 1517460, 9],
    ['Архонт Таэлис', 84, 1394810, 6], ['Совет Перерождённых', 79, 1286340, 8],
    ['Ночной страж', 73, 1179320, 5], ['Сердце полуночи', 68, 1098270, 4],
  ];
  demo.forEach((applicant, index) => {
    const score = applicant.rating;
    profiles.set(applicantKey(applicant), {
      loading: false,
      applicant,
      errors: [],
      rio: {
        name: applicant.name,
        realm: applicant.realm,
        region: applicant.region,
        className: index === 0 ? 'Paladin' : index === 1 ? 'Mage' : 'Demon Hunter',
        spec: index === 0 ? 'Protection' : index === 1 ? 'Frost' : 'Havoc',
        role: ROLE_FROM_CODE[applicant.role] || '',
        itemLevel: applicant.itemLevel,
        score,
        runs: dungeons.map(([dungeon, level, upgrades, runScore], runIndex) => ({
          dungeon,
          level: Math.max(2, level - index - (runIndex > 4 ? 1 : 0)),
          upgrades: runIndex === 6 ? 0 : upgrades,
          timed: runIndex !== 6,
          score: Math.max(0, runScore - index * 8),
        })),
        raidProgression: [
          { slug: 'citadel-of-midnight', summary: index === 0 ? '6/8 M' : '8/8 H', totalBosses: 8, normal: 8, heroic: 8, mythic: index === 0 ? 6 : index === 1 ? 3 : 1 },
          { slug: 'voidspire', summary: '8/8 H', totalBosses: 8, normal: 8, heroic: 8, mythic: 0 },
        ],
        profileUrl: `https://raider.io/characters/${applicant.region}/${encodeURIComponent(applicant.realm)}/${encodeURIComponent(applicant.name)}`,
        thumbnailUrl: '',
      },
      logs: {
        available: true,
        hidden: false,
        bestAverage: Math.max(63, 91 - index * 11),
        medianAverage: Math.max(52, 78 - index * 9),
        bosses: bosses.map(([boss, percent, amount, kills]) => ({
          boss,
          percent: Math.max(25, percent - index * 9),
          amount: Math.round(amount * (1 - index * 0.08)),
          kills,
        })),
      },
    });
  });
  broadcastState();
  showCandidateWindow();
}

function registerIpc() {
  ipcMain.handle('mb:get-state', () => state());
  ipcMain.handle('mb:save-settings', (_event, next) => {
    if (next.wclClientSecret === '********') next.wclClientSecret = settings.wclClientSecret;
    settings = saveSettings({ ...settings, ...next });
    for (const item of profiles.values()) item.loading = false;
    profiles.clear();
    for (const applicant of applicants) enrichApplicant(applicant);
    for (const win of allWindows()) win.setAlwaysOnTop(Boolean(settings.alwaysOnTop));
    broadcastState();
    return publicSettings(settings);
  });
  ipcMain.handle('mb:refresh', () => {
    if (MOCK_MODE) {
      addDemoApplicants();
      return true;
    }
    profiles.clear();
    for (const applicant of applicants) enrichApplicant(applicant, true);
    return true;
  });
  ipcMain.handle('mb:demo', () => { addDemoApplicants(); return true; });
  ipcMain.handle('mb:window', (event, action) => {
    const win = BrowserWindow.fromWebContents(event.sender);
    if (!win) return;
    if (action === 'close') win.hide();
    if (action === 'minimize') win.minimize();
  });
  ipcMain.handle('mb:open', (_event, url) => {
    if (/^https:\/\/(raider\.io|www\.warcraftlogs\.com)\//i.test(url)) return shell.openExternal(url);
    return false;
  });
}

bindOverwolfPackages();

app.whenReady().then(async () => {
  settings = loadSettings();
  registerIpc();
  await createDesktopWindow();
  if (MOCK_MODE) addDemoApplicants();
});

app.on('activate', () => {
  if (!desktopWindow) createDesktopWindow();
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
