'use strict';

const { app, BaseWindow, WebContentsView, ipcMain, session, shell, Menu } = require('electron');
const fs = require('node:fs');
const path = require('node:path');
const { HOME_URL, normalizeAddress, isTrackerURL } = require('../src/browser-utils.cjs');

const CHROME_HEIGHT = 132;
const MAX_TABS = 24;
const SNAPSHOT_LIMIT = 180_000;

let mainWindow = null;
let chromeView = null;
let browserSession = null;
let tabs = [];
let activeTabId = null;
let nextTabNumber = 1;
let lowMemory = true;
let currentChromeHeight = CHROME_HEIGHT;
let isQuitting = false;
const filterEnabled = true;

function dataPath() {
  return path.join(app.getPath('userData'), 'remim-tabs.json');
}

function persistTabs() {
  try {
    const state = {
      lowMemory,
      activeTabId,
      tabs: tabs.slice(-MAX_TABS).map((tab) => ({
        id: tab.id,
        url: tab.url,
        title: tab.title,
        frozen: Boolean(tab.frozen),
        snapshot: typeof tab.snapshot === 'string' ? tab.snapshot.slice(0, SNAPSHOT_LIMIT) : null
      }))
    };
    fs.writeFileSync(dataPath(), JSON.stringify(state), { encoding: 'utf8', mode: 0o600 });
  } catch (error) {
    console.warn('Could not save Remim tab state:', error?.message || error);
  }
}

function readPersistedTabs() {
  try {
    const parsed = JSON.parse(fs.readFileSync(dataPath(), 'utf8'));
    if (!parsed || !Array.isArray(parsed.tabs)) return null;
    return parsed;
  } catch {
    return null;
  }
}

function trackerBlocker() {
  browserSession.webRequest.onBeforeRequest({ urls: ['<all_urls>'] }, (details, callback) => {
    callback({ cancel: filterEnabled && isTrackerURL(details.url) });
  });
}

function getTab(id = activeTabId) {
  return tabs.find((tab) => tab.id === id) || null;
}

function getActiveTab() {
  return getTab(activeTabId);
}

function getState() {
  const active = getActiveTab();
  const contents = active?.view?.webContents;
  return {
    tabs: tabs.map((tab) => ({
      id: tab.id,
      title: tab.title || 'New tab',
      url: tab.url || HOME_URL,
      active: tab.id === activeTabId,
      frozen: Boolean(tab.frozen),
      hasSnapshot: Boolean(tab.snapshot)
    })),
    activeTabId,
    activeUrl: active?.url || HOME_URL,
    activeTitle: active?.title || 'Remim',
    activeFrozen: Boolean(active?.frozen),
    canGoBack: Boolean(contents && !active.frozen && contents.navigationHistory?.canGoBack?.()),
    canGoForward: Boolean(contents && !active.frozen && contents.navigationHistory?.canGoForward?.()),
    lowMemory,
    filterEnabled
  };
}

function sendState() {
  if (!chromeView?.webContents || chromeView.webContents.isDestroyed()) return;
  chromeView.webContents.send('browser:state', getState());
}

function layoutViews() {
  if (!mainWindow || mainWindow.isDestroyed()) return;
  const [width, height] = mainWindow.getContentSize();
  chromeView?.setBounds({ x: 0, y: 0, width, height: Math.min(currentChromeHeight, height) });
  const active = getActiveTab();
  if (active?.view) {
    active.view.setBounds({ x: 0, y: currentChromeHeight, width, height: Math.max(0, height - currentChromeHeight) });
  }
}

function removeFromWindow(view) {
  if (!view || !mainWindow || mainWindow.isDestroyed()) return;
  try { mainWindow.contentView.removeChildView(view); } catch { /* already detached */ }
}

function snapshotScript() {
  return `(() => {
    const originalTitle = document.title || location.hostname || 'Saved page';
    const body = document.body ? document.body.cloneNode(true) : document.documentElement.cloneNode(true);
    body.querySelectorAll('script, style, link, iframe, frame, frameset, object, embed, form, input, textarea, select, button, video, audio, canvas, source, track, portal').forEach(node => node.remove());
    body.querySelectorAll('*').forEach(node => {
      [...node.attributes].forEach(attribute => {
        const name = attribute.name.toLowerCase();
        if (name.startsWith('on') || name.endsWith(':href') || ['src', 'srcset', 'href', 'action', 'formaction', 'poster', 'background'].includes(name)) node.removeAttribute(attribute.name);
        if (name === 'style' && /url\\s*\\(|@import/i.test(attribute.value)) node.removeAttribute(attribute.name);
      });
    });
    const html = (body.innerHTML || '').slice(0, ${SNAPSHOT_LIMIT});
    return { title: originalTitle, html };
  })()`;
}

function snapshotDocument(tab) {
  const safeTitle = escapeHtml(tab.title || 'Saved page');
  const body = typeof tab.snapshot === 'string' ? tab.snapshot : '';
  return `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${safeTitle}</title>
  <style>body{margin:0;background:#f4f6f8;color:#1d2633;font:16px/1.55 system-ui,sans-serif}.banner{position:sticky;top:0;background:#17241e;color:#ecf7ef;padding:12px 18px;font-size:13px}.banner a{color:#bdf3cc;font-weight:700;margin-left:8px}.content{max-width:900px;margin:24px auto;padding:24px;background:white;border-radius:12px;overflow-wrap:anywhere;box-shadow:0 4px 24px #0001}img{max-width:100%}</style></head><body>
  <div class="banner">This tab was frozen to save memory. The preview is static. <a href="remim-restore://restore">Restore live page</a></div><main class="content">${body || '<p>This page has no saved preview.</p>'}</main></body></html>`;
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);
}

function emitVisit(tab) {
  if (!tab?.url || !/^https?:\/\//i.test(tab.url)) return;
  const visit = { url: tab.url, title: tab.title || tab.url, visitedAt: new Date().toISOString() };
  if (chromeView?.webContents && !chromeView.webContents.isDestroyed()) {
    chromeView.webContents.send('browser:visit', visit);
  }
}

function injectLightweightCleanup(tab) {
  if (!lowMemory || !tab?.view || tab.frozen) return;
  const script = `(() => {
    const css = document.createElement('style');
    css.id = '__remim_lightweight_style__';
    css.textContent = '*,*::before,*::after{scroll-behavior:auto!important;animation-duration:.001ms!important;animation-iteration-count:1!important;transition-duration:.001ms!important} iframe[src*="doubleclick" i],iframe[src*="googlesyndication" i],iframe[id*="ad" i], [aria-label*="advertisement" i], [data-ad-slot], [data-ad-unit], .adsbygoogle, .advertisement, .ad-banner, #google_ads_iframe {display:none!important;content-visibility:hidden!important}';
    if (!document.getElementById(css.id)) (document.head || document.documentElement).appendChild(css);
  })()`;
  tab.view.webContents.executeJavaScript(script, true).catch(() => {});
}

function attachView(tab, { load = true } = {}) {
  const view = new WebContentsView({
    webPreferences: {
      partition: 'persist:remim-browser',
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      spellcheck: true,
      webSecurity: true
    }
  });
  tab.view = view;
  view.webContents.setWindowOpenHandler(({ url }) => {
    const safe = normalizeAddress(url);
    if (safe && /^https?:\/\//i.test(safe)) createTab(safe);
    return { action: 'deny' };
  });
  view.webContents.on('will-navigate', (event, url) => {
    if (url.startsWith('remim-restore://')) {
      event.preventDefault();
      restoreLive(tab);
      return;
    }
    if (tab.frozen && url.startsWith('data:text/html')) return;
    if (!/^https?:\/\//i.test(url)) event.preventDefault();
  });
  view.webContents.on('did-navigate', (_event, url) => {
    if (tab.frozen) return; // Static previews must not replace the saved target URL.
    if (/^https?:\/\//i.test(url)) {
      tab.url = url;
      tab.snapshot = null;
      tab.title = tab.title || new URL(url).hostname;
      persistTabs();
      sendState();
    }
  });
  view.webContents.on('page-title-updated', (_event, title) => {
    if (tab.frozen) return;
    tab.title = String(title || tab.url || 'Remim').slice(0, 300);
    persistTabs();
    sendState();
  });
  view.webContents.on('dom-ready', () => injectLightweightCleanup(tab));
  view.webContents.on('did-finish-load', () => {
    if (tab.frozen) return;
    injectLightweightCleanup(tab);
    emitVisit(tab);
    sendState();
  });
  view.webContents.on('render-process-gone', (_event, details) => {
    console.warn('Remim page renderer exited:', details?.reason || 'unknown');
    tab.frozen = true;
    tab.title = `${tab.title || 'Tab'} (reopen to continue)`;
    if (tab.id === activeTabId) sendState();
  });
  view.webContents.on('destroyed', () => {
    if (tab.view === view) tab.view = null;
  });

  if (tab.id === activeTabId && mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.contentView.addChildView(view);
    layoutViews();
  }
  if (load) {
    if (tab.frozen && tab.snapshot) {
      view.webContents.loadURL(`data:text/html;charset=utf-8,${encodeURIComponent(snapshotDocument(tab))}`).catch(() => {});
    } else {
      const target = normalizeAddress(tab.url) || HOME_URL;
      tab.url = target;
      tab.frozen = false;
      view.webContents.loadURL(target).catch((error) => {
        console.warn('Navigation failed:', error?.message || error);
      });
    }
  }
  return view;
}

function scheduleFreeze(tab) {
  clearTimeout(tab.freezeTimer);
  if (!tab || tab.frozen || !tab.view || !lowMemory) return;
  tab.freezeTimer = setTimeout(async () => {
    if (tab.id === activeTabId || !tab.view || tab.view.webContents.isDestroyed()) return;
    try {
      const snapshot = await tab.view.webContents.executeJavaScript(snapshotScript(), true);
      if (snapshot && typeof snapshot.html === 'string') {
        tab.title = String(snapshot.title || tab.title || 'Saved page').slice(0, 300);
        tab.snapshot = snapshot.html.slice(0, SNAPSHOT_LIMIT);
      }
    } catch (error) {
      console.warn('Page snapshot failed; URL will still be retained:', error?.message || error);
    }
    if (tab.id === activeTabId || !tab.view) return;
    removeFromWindow(tab.view);
    try { tab.view.webContents.close(); } catch { /* view may already be gone */ }
    tab.view = null;
    tab.frozen = true;
    tab.freezeTimer = null;
    persistTabs();
    sendState();
  }, 60_000);
}

function activateTab(id) {
  const target = getTab(id);
  if (!target) return;
  const outgoing = getActiveTab();
  if (outgoing && outgoing.id !== target.id) {
    removeFromWindow(outgoing.view);
    scheduleFreeze(outgoing);
  }
  clearTimeout(target.freezeTimer);
  target.freezeTimer = null;
  activeTabId = target.id;
  if (!target.view || target.view.webContents.isDestroyed()) attachView(target);
  else {
    mainWindow.contentView.addChildView(target.view);
    layoutViews();
  }
  persistTabs();
  sendState();
}

function createTab(address = HOME_URL, activate = true) {
  if (tabs.length >= MAX_TABS) {
    if (chromeView?.webContents && !chromeView.webContents.isDestroyed()) {
      chromeView.webContents.send('browser:notice', 'Tab limit reached (24). Close a tab first.');
    }
    return null;
  }
  const safeUrl = normalizeAddress(address) || HOME_URL;
  const tab = {
    id: `tab-${nextTabNumber++}-${Date.now().toString(36)}`,
    title: safeUrl === HOME_URL ? 'New tab' : safeUrl,
    url: safeUrl,
    frozen: false,
    snapshot: null,
    view: null,
    freezeTimer: null
  };
  const current = getActiveTab();
  if (activate && current) {
    removeFromWindow(current.view);
    scheduleFreeze(current);
  }
  tabs.push(tab);
  if (activate || !activeTabId) {
    activeTabId = tab.id;
    attachView(tab);
  }
  persistTabs();
  sendState();
  return tab;
}

function restoreLive(tab) {
  if (!tab) return;
  tab.frozen = false;
  tab.snapshot = null;
  if (!tab.view || tab.view.webContents.isDestroyed()) attachView(tab, { load: false });
  if (tab.id === activeTabId && tab.view) {
    mainWindow.contentView.addChildView(tab.view);
    layoutViews();
    tab.view.webContents.loadURL(normalizeAddress(tab.url) || HOME_URL).catch(() => {});
  }
  persistTabs();
  sendState();
}

function removeTab(id) {
  const index = tabs.findIndex((tab) => tab.id === id);
  if (index < 0) return;
  const [tab] = tabs.splice(index, 1);
  clearTimeout(tab.freezeTimer);
  removeFromWindow(tab.view);
  try { if (tab.view && !tab.view.webContents.isDestroyed()) tab.view.webContents.close(); } catch { /* ignore */ }
  if (activeTabId === id) {
    activeTabId = null;
    const replacement = tabs[Math.max(0, index - 1)] || tabs[0];
    if (replacement) activateTab(replacement.id);
    else createTab(HOME_URL, true);
  }
  persistTabs();
  sendState();
}

function getActiveContents() {
  const active = getActiveTab();
  if (!active || active.frozen || !active.view || active.view.webContents.isDestroyed()) return null;
  return active.view.webContents;
}

async function navigateActive(address) {
  const active = getActiveTab();
  if (!active) return createTab(address || HOME_URL, true);
  const target = normalizeAddress(address);
  if (!target) {
    chromeView?.webContents.send('browser:notice', 'Only normal HTTP/HTTPS web addresses are allowed.');
    return;
  }
  active.url = target;
  active.frozen = false;
  active.snapshot = null;
  if (!active.view || active.view.webContents.isDestroyed()) attachView(active, { load: false });
  active.view.webContents.loadURL(target).catch((error) => {
    chromeView?.webContents.send('browser:notice', `Could not open page: ${error?.message || 'navigation failed'}`);
  });
  persistTabs();
  sendState();
}

function hydrateTabs() {
  const saved = readPersistedTabs();
  if (!saved) return false;
  lowMemory = saved.lowMemory !== false;
  const persisted = saved.tabs.slice(0, MAX_TABS);
  tabs = persisted.map((item) => ({
    id: typeof item.id === 'string' ? item.id : `tab-${nextTabNumber++}`,
    url: normalizeAddress(item.url) || HOME_URL,
    title: String(item.title || 'New tab').slice(0, 300),
    frozen: true,
    snapshot: typeof item.snapshot === 'string' ? item.snapshot.slice(0, SNAPSHOT_LIMIT) : null,
    view: null,
    freezeTimer: null
  }));
  activeTabId = tabs.some((tab) => tab.id === saved.activeTabId) ? saved.activeTabId : tabs[0]?.id || null;
  return tabs.length > 0;
}

function setupIpc() {
  ipcMain.handle('browser:get-state', () => getState());
  ipcMain.handle('browser:navigate', (_event, address) => navigateActive(address));
  ipcMain.handle('browser:new-tab', (_event, address) => createTab(address || HOME_URL, true));
  ipcMain.handle('browser:select-tab', (_event, id) => activateTab(String(id)));
  ipcMain.handle('browser:close-tab', (_event, id) => removeTab(String(id)));
  ipcMain.handle('browser:back', async () => {
    const tab = getActiveTab();
    const contents = getActiveContents();
    if (tab?.frozen) return restoreLive(tab);
    if (contents && contents.navigationHistory.canGoBack()) await contents.navigationHistory.goBack();
  });
  ipcMain.handle('browser:forward', async () => {
    const tab = getActiveTab();
    const contents = getActiveContents();
    if (tab?.frozen) return restoreLive(tab);
    if (contents && contents.navigationHistory.canGoForward()) await contents.navigationHistory.goForward();
  });
  ipcMain.handle('browser:reload', async () => {
    const tab = getActiveTab();
    const contents = getActiveContents();
    if (tab?.frozen) return restoreLive(tab);
    if (contents) await contents.reload();
  });
  ipcMain.handle('browser:set-chrome-height', (_event, height) => {
    currentChromeHeight = Math.max(CHROME_HEIGHT, Math.min(320, Number(height) || CHROME_HEIGHT));
    layoutViews();
  });
  ipcMain.handle('browser:toggle-low-memory', (_event, enabled) => {
    lowMemory = Boolean(enabled);
    if (lowMemory) {
      tabs.filter((tab) => tab.id !== activeTabId).forEach(scheduleFreeze);
    } else {
      tabs.forEach((tab) => clearTimeout(tab.freezeTimer));
    }
    persistTabs();
    sendState();
  });
}

function createWindow() {
  mainWindow = new BaseWindow({
    width: 1280,
    height: 820,
    minWidth: 760,
    minHeight: 540,
    title: 'Remim Browser',
    backgroundColor: '#101514',
    show: false
  });

  chromeView = new WebContentsView({
    webPreferences: {
      preload: path.join(__dirname, 'preload.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      spellcheck: true
    }
  });
  mainWindow.contentView.addChildView(chromeView);
  chromeView.setBounds({ x: 0, y: 0, width: 1280, height: CHROME_HEIGHT });
  chromeView.webContents.setWindowOpenHandler(({ url }) => {
    const target = normalizeAddress(url);
    if (target && /^https?:\/\//i.test(target)) shell.openExternal(target).catch(() => {});
    return { action: 'deny' };
  });

  mainWindow.on('resize', layoutViews);
  mainWindow.on('closed', () => {
    for (const tab of tabs) {
      clearTimeout(tab.freezeTimer);
      try { if (tab.view && !tab.view.webContents.isDestroyed()) tab.view.webContents.close(); } catch { /* ignore */ }
    }
    mainWindow = null;
    chromeView = null;
  });

  const isDev = process.argv.includes('--dev');
  if (isDev) chromeView.webContents.loadURL('http://127.0.0.1:5173');
  else chromeView.webContents.loadFile(path.join(__dirname, '..', 'dist', 'index.html'));

  if (!hydrateTabs()) {
    const tab = {
      id: `tab-${nextTabNumber++}-${Date.now().toString(36)}`,
      title: 'New tab', url: HOME_URL, frozen: false, snapshot: null, view: null, freezeTimer: null
    };
    tabs = [tab];
    activeTabId = tab.id;
    attachView(tab);
  } else {
    const active = getActiveTab();
    if (active) attachView(active);
  }

  setTimeout(() => {
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.show();
      layoutViews();
      sendState();
    }
  }, 120);
}

app.whenReady().then(() => {
  app.setAppUserModelId('app.remim.browser');
  Menu.setApplicationMenu(null);
  browserSession = session.fromPartition('persist:remim-browser');
  trackerBlocker();
  browserSession.setPermissionRequestHandler((_webContents, _permission, callback) => callback(false));
  setupIpc();
  createWindow();
  app.on('activate', () => {
    if (!mainWindow) createWindow();
  });
});

app.on('before-quit', () => {
  isQuitting = true;
  persistTabs();
  for (const tab of tabs) clearTimeout(tab.freezeTimer);
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin' || isQuitting) app.quit();
});
