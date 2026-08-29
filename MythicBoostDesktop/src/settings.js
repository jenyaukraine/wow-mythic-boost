const fs = require('node:fs');
const path = require('node:path');
const { app, safeStorage } = require('electron');

const DEFAULTS = {
  region: 'eu',
  autoOpen: true,
  alwaysOnTop: true,
  wclClientId: '',
  wclClientSecret: '',
};

function settingsPath() {
  return path.join(app.getPath('userData'), 'settings.json');
}

function decrypt(value) {
  if (!value) return '';
  try {
    if (safeStorage.isEncryptionAvailable()) {
      return safeStorage.decryptString(Buffer.from(value, 'base64'));
    }
  } catch (_) {}
  return '';
}

function encrypt(value) {
  if (!value) return '';
  if (!safeStorage.isEncryptionAvailable()) return '';
  return safeStorage.encryptString(String(value)).toString('base64');
}

function loadSettings() {
  let stored = {};
  try {
    stored = JSON.parse(fs.readFileSync(settingsPath(), 'utf8'));
  } catch (_) {}
  return {
    ...DEFAULTS,
    ...stored,
    wclClientId: decrypt(stored.wclClientId),
    wclClientSecret: decrypt(stored.wclClientSecret),
  };
}

function saveSettings(next) {
  const value = { ...DEFAULTS, ...next };
  const diskValue = {
    ...value,
    wclClientId: encrypt(value.wclClientId),
    wclClientSecret: encrypt(value.wclClientSecret),
  };
  fs.mkdirSync(path.dirname(settingsPath()), { recursive: true });
  fs.writeFileSync(settingsPath(), JSON.stringify(diskValue, null, 2), 'utf8');
  return value;
}

function publicSettings(settings) {
  return {
    ...settings,
    wclClientSecret: settings.wclClientSecret ? '********' : '',
    wclConfigured: Boolean(settings.wclClientId && settings.wclClientSecret),
  };
}

module.exports = { loadSettings, saveSettings, publicSettings };
