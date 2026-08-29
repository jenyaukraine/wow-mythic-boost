const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('mythicBoost', {
  getState: () => ipcRenderer.invoke('mb:get-state'),
  saveSettings: (settings) => ipcRenderer.invoke('mb:save-settings', settings),
  refresh: () => ipcRenderer.invoke('mb:refresh'),
  demo: () => ipcRenderer.invoke('mb:demo'),
  windowAction: (action) => ipcRenderer.invoke('mb:window', action),
  openExternal: (url) => ipcRenderer.invoke('mb:open', url),
  onState: (callback) => {
    const listener = (_event, value) => callback(value);
    ipcRenderer.on('mb:state', listener);
    return () => ipcRenderer.removeListener('mb:state', listener);
  },
  onStatus: (callback) => {
    const listener = (_event, value) => callback(value);
    ipcRenderer.on('mb:status', listener);
    return () => ipcRenderer.removeListener('mb:status', listener);
  },
});
