'use strict';

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('remim', {
  getState: () => ipcRenderer.invoke('browser:get-state'),
  navigate: (address) => ipcRenderer.invoke('browser:navigate', address),
  newTab: (address) => ipcRenderer.invoke('browser:new-tab', address),
  selectTab: (id) => ipcRenderer.invoke('browser:select-tab', id),
  closeTab: (id) => ipcRenderer.invoke('browser:close-tab', id),
  back: () => ipcRenderer.invoke('browser:back'),
  forward: () => ipcRenderer.invoke('browser:forward'),
  reload: () => ipcRenderer.invoke('browser:reload'),
  toggleLowMemory: (enabled) => ipcRenderer.invoke('browser:toggle-low-memory', enabled),
  setChromeHeight: (height) => ipcRenderer.invoke('browser:set-chrome-height', height),
  onState: (callback) => {
    const listener = (_event, state) => callback(state);
    ipcRenderer.on('browser:state', listener);
    return () => ipcRenderer.removeListener('browser:state', listener);
  },
  onVisit: (callback) => {
    const listener = (_event, visit) => callback(visit);
    ipcRenderer.on('browser:visit', listener);
    return () => ipcRenderer.removeListener('browser:visit', listener);
  },
  onNotice: (callback) => {
    const listener = (_event, message) => callback(message);
    ipcRenderer.on('browser:notice', listener);
    return () => ipcRenderer.removeListener('browser:notice', listener);
  }
});
