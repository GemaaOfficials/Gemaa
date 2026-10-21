import './style.css';
import { CloudSync, type BookmarkRecord, type TransferRecord } from './cloud';

const root = document.querySelector<HTMLDivElement>('#app');
if (!root) throw new Error('Remim root element is missing');

root.innerHTML = `
  <main class="remim-shell">
    <header class="topbar">
      <div class="brand-mark" aria-hidden="true">R</div>
      <div class="brand-copy"><strong>Remim</strong><span>light browser</span></div>
      <div class="topbar-spacer"></div>
      <span id="sync-dot" class="sync-dot" aria-hidden="true"></span>
      <span id="sync-status" class="sync-status">Checking sync…</span>
      <button id="teleport-btn" class="button button-teleport" type="button" title="Send this tab to another signed-in device">↗ Teleport</button>
    </header>

    <nav id="tab-strip" class="tab-strip" aria-label="Open tabs"></nav>

    <form id="address-form" class="address-row">
      <button id="back-btn" class="icon-button" type="button" title="Back" aria-label="Back">‹</button>
      <button id="forward-btn" class="icon-button" type="button" title="Forward" aria-label="Forward">›</button>
      <button id="reload-btn" class="icon-button" type="button" title="Reload or restore frozen page" aria-label="Reload">↻</button>
      <div class="address-wrap"><span class="address-lock" aria-hidden="true">◈</span><input id="address-input" name="address" autocomplete="off" spellcheck="false" aria-label="Search or enter website" placeholder="Search or enter a website" /></div>
      <button class="go-button" type="submit">Go</button>
    </form>

    <div class="tools-row">
      <button id="bookmark-current-btn" class="tool-button" type="button" title="Bookmark current page">☆ <span>Save</span></button>
      <button id="bookmarks-btn" class="tool-button" type="button">Bookmarks</button>
      <button id="history-btn" class="tool-button" type="button">History</button>
      <label class="memory-toggle" title="Freeze inactive tabs after 60 seconds"><input id="low-memory-toggle" type="checkbox" checked /><span class="toggle-track"><i></i></span><span>Low memory</span></label>
      <div class="tools-spacer"></div>
      <button id="account-btn" class="tool-button account-button" type="button">Sign in</button>
      <button id="new-tab-btn" class="new-tab-button" type="button" title="New tab" aria-label="New tab">＋</button>
    </div>

    <section id="popup-layer" class="popup-layer" hidden aria-live="polite"></section>
    <div id="toast" class="toast" hidden role="status"></div>
  </main>
`;

const $ = <T extends HTMLElement>(selector: string): T => {
  const element = root!.querySelector<T>(selector);
  if (!element) throw new Error(`Missing UI element: ${selector}`);
  return element;
};

const cloud = new CloudSync();
let state: BrowserState | null = null;
let currentUser: { id: string; email?: string } | null = null;
let cloudStatus = 'Starting…';
let toastTimer = 0;
let toastAction: (() => void) | null = null;
let incomingTransfer: TransferRecord | null = null;

const localStorageKeys = {
  bookmarks: 'remim.bookmarks.v1',
  history: 'remim.history.v1'
};

function escapeHtml(value: unknown): string {
  return String(value ?? '').replace(/[&<>"']/g, (char) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  })[char]!);
}

function safeReadArray<T>(key: string): T[] {
  try {
    const data: unknown = JSON.parse(localStorage.getItem(key) || '[]');
    return Array.isArray(data) ? data as T[] : [];
  } catch { return []; }
}

function persistArray<T>(key: string, values: T[]): void {
  try { localStorage.setItem(key, JSON.stringify(values)); }
  catch { showToast('Local storage is full. Remove old history or bookmarks.'); }
}

function getBookmarks(): BookmarkRecord[] {
  return safeReadArray<BookmarkRecord>(localStorageKeys.bookmarks);
}

function getHistory(): BrowserVisit[] {
  return safeReadArray<BrowserVisit>(localStorageKeys.history);
}

function showToast(message: string, actionLabel?: string, action?: () => void): void {
  const toast = $('#toast');
  window.clearTimeout(toastTimer);
  toastAction = action ?? null;
  toast.innerHTML = `<span>${escapeHtml(message)}</span>${actionLabel ? `<button id="toast-action" type="button">${escapeHtml(actionLabel)}</button>` : ''}<button id="toast-dismiss" class="toast-dismiss" type="button" aria-label="Dismiss">×</button>`;
  toast.hidden = false;
  $('#toast-dismiss').addEventListener('click', () => { toast.hidden = true; toastAction = null; });
  const actionButton = toast.querySelector<HTMLButtonElement>('#toast-action');
  actionButton?.addEventListener('click', () => { const callback = toastAction; toast.hidden = true; toastAction = null; callback?.(); });
  toastTimer = window.setTimeout(() => { toast.hidden = true; toastAction = null; }, 7500);
}

function setPopup(open: boolean, content = ''): void {
  const layer = $('#popup-layer');
  layer.innerHTML = content;
  layer.hidden = !open;
  void window.remim.setChromeHeight(open ? 320 : 132);
}

function closePopup(): void { setPopup(false); }

function renderTabs(): void {
  if (!state) return;
  const strip = $('#tab-strip');
  strip.innerHTML = state.tabs.map((tab) => `
    <div class="tab-pill ${tab.active ? 'active' : ''}" data-tab="${escapeHtml(tab.id)}">
      <button class="tab-select" type="button" title="${escapeHtml(tab.title)}">
        <span class="tab-state-dot ${tab.frozen ? 'frozen' : ''}"></span>
        <span class="tab-title">${escapeHtml(tab.title || 'New tab')}</span>
        ${tab.frozen ? '<span class="frozen-tag">SAVED</span>' : ''}
      </button>
      <button class="tab-close" type="button" title="Close tab" aria-label="Close tab">×</button>
    </div>
  `).join('');
  strip.querySelectorAll<HTMLElement>('.tab-pill').forEach((pill) => {
    const id = pill.dataset.tab;
    if (!id) return;
    pill.querySelector('.tab-select')?.addEventListener('click', () => { void window.remim.selectTab(id); closePopup(); });
    pill.querySelector('.tab-close')?.addEventListener('click', (event) => {
      event.stopPropagation();
      void window.remim.closeTab(id);
    });
  });
}

function renderState(next: BrowserState): void {
  state = next;
  renderTabs();
  const address = $('#address-input') as HTMLInputElement;
  if (document.activeElement !== address) address.value = next.activeUrl || '';
  $('#back-btn').toggleAttribute('disabled', !next.canGoBack && !next.activeFrozen);
  $('#forward-btn').toggleAttribute('disabled', !next.canGoForward && !next.activeFrozen);
  $('#reload-btn').textContent = next.activeFrozen ? '⟳' : '↻';
  $('#reload-btn').title = next.activeFrozen ? 'Restore live page' : 'Reload';
  ($('#low-memory-toggle') as HTMLInputElement).checked = next.lowMemory;
  $('#bookmark-current-btn').innerHTML = `${getBookmarks().some((item) => item.url === next.activeUrl) ? '★' : '☆'} <span>${getBookmarks().some((item) => item.url === next.activeUrl) ? 'Saved' : 'Save'}</span>`;
  $('#bookmark-current-btn').classList.toggle('is-saved', getBookmarks().some((item) => item.url === next.activeUrl));
}

function renderCloudStatus(status: string, user: { id: string; email?: string } | null): void {
  cloudStatus = status;
  currentUser = user;
  const isConnected = Boolean(user) && /synced|connecting/i.test(status);
  $('#sync-dot').classList.toggle('connected', isConnected && /synced/i.test(status));
  $('#sync-dot').classList.toggle('warning', !isConnected);
  $('#sync-status').textContent = user?.email ? status === 'Synced' ? 'Synced' : status : status;
  $('#sync-status').title = status;
  $('#account-btn').textContent = user ? 'Account' : 'Sign in';
  $('#account-btn').classList.toggle('account-connected', Boolean(user));
}

function renderListPanel(kind: 'bookmarks' | 'history'): void {
  const rows = kind === 'bookmarks' ? getBookmarks() : getHistory();
  const title = kind === 'bookmarks' ? 'Saved pages' : 'Recent history';
  const body = rows.length ? rows.slice(0, 40).map((row, index) => {
    const url = escapeHtml(row.url);
    const label = escapeHtml(row.title || row.url);
    const date = 'visitedAt' in row && row.visitedAt ? new Date(row.visitedAt).toLocaleString() : '';
    return `<div class="list-row" data-index="${index}"><button class="list-open" type="button"><strong>${label}</strong><small>${url}${date ? ` · ${escapeHtml(date)}` : ''}</small></button>${kind === 'bookmarks' ? '<button class="list-remove" type="button" title="Remove bookmark">×</button>' : ''}</div>`;
  }).join('') : `<div class="empty-state">${kind === 'bookmarks' ? 'Your saved pages will appear here.' : 'Pages you visit will appear here.'}</div>`;
  setPopup(true, `<div class="popup-heading"><strong>${title}</strong><button id="popup-close" type="button" aria-label="Close">×</button></div><div class="popup-list">${body}</div>`);
  $('#popup-close').addEventListener('click', closePopup);
  $('#popup-layer').querySelectorAll<HTMLElement>('.list-row').forEach((line) => {
    const index = Number(line.dataset.index);
    line.querySelector('.list-open')?.addEventListener('click', () => {
      const target = kind === 'bookmarks' ? getBookmarks()[index] : getHistory()[index];
      if (target?.url) void window.remim.navigate(target.url);
      closePopup();
    });
    line.querySelector('.list-remove')?.addEventListener('click', () => {
      const target = getBookmarks()[index];
      if (!target) return;
      const updated = getBookmarks().filter((item) => item.url !== target.url);
      persistArray(localStorageKeys.bookmarks, updated);
      void cloud.removeBookmark(target.url);
      renderListPanel('bookmarks');
      if (state) renderState(state);
    });
  });
}

function renderAuthPanel(): void {
  if (currentUser) {
    setPopup(true, `<div class="popup-heading"><strong>Remim account</strong><button id="popup-close" type="button" aria-label="Close">×</button></div><div class="auth-panel"><p>Signed in as <strong>${escapeHtml(currentUser.email || 'Remim user')}</strong></p><p class="muted">Bookmarks and browsing history sync when this device is online. Teleport transfers expire after 10 minutes.</p><button id="sign-out-btn" class="primary-action" type="button">Sign out</button></div>`);
    $('#popup-close').addEventListener('click', closePopup);
    $('#sign-out-btn').addEventListener('click', async () => {
      await cloud.signOut();
      closePopup();
      showToast('Signed out of Remim sync.');
    });
    return;
  }
  setPopup(true, `<div class="popup-heading"><strong>Sign in to sync</strong><button id="popup-close" type="button" aria-label="Close">×</button></div>
    <form id="auth-form" class="auth-form">
      <label>Email<input id="auth-email" type="email" required autocomplete="email" placeholder="you@example.com" /></label>
      <label>Password<input id="auth-password" type="password" minlength="6" required autocomplete="current-password" placeholder="At least 6 characters" /></label>
      <div class="auth-actions"><button id="auth-submit" class="primary-action" type="submit">Sign in</button><button id="auth-create" class="secondary-action" type="button">Create account</button></div>
      <p class="muted">Your Supabase project URL and public anon/publishable key must be set in <code>.env</code>.</p>
      <p id="auth-error" class="form-error" hidden></p>
    </form>`);
  $('#popup-close').addEventListener('click', closePopup);
  const authForm = $('#auth-form') as HTMLFormElement;
  const error = $('#auth-error');
  let createAccount = false;
  $('#auth-create').addEventListener('click', () => {
    createAccount = !createAccount;
    $('#auth-submit').textContent = createAccount ? 'Create account' : 'Sign in';
    $('#auth-create').textContent = createAccount ? 'Use existing account' : 'Create account';
    ($('#auth-password') as HTMLInputElement).autocomplete = createAccount ? 'new-password' : 'current-password';
  });
  authForm.addEventListener('submit', async (event) => {
    event.preventDefault();
    const submit = $('#auth-submit') as HTMLButtonElement;
    submit.disabled = true;
    submit.textContent = 'Connecting…';
    error.hidden = true;
    const email = ($('#auth-email') as HTMLInputElement).value.trim();
    const password = ($('#auth-password') as HTMLInputElement).value;
    const message = await cloud.signIn(email, password, createAccount);
    submit.disabled = false;
    submit.textContent = createAccount ? 'Create account' : 'Sign in';
    if (message) {
      error.textContent = message;
      error.hidden = false;
    } else {
      closePopup();
      showToast(createAccount ? 'Account request submitted.' : 'Remim sync is connecting…');
    }
  });
}

function handleTransfer(transfer: TransferRecord): void {
  incomingTransfer = transfer;
  showToast(`Tab received: ${transfer.title || transfer.url}`, 'Open', () => {
    const current = incomingTransfer;
    incomingTransfer = null;
    if (current) void window.remim.newTab(current.url);
  });
}

$('#address-form').addEventListener('submit', (event) => {
  event.preventDefault();
  const value = ($('#address-input') as HTMLInputElement).value.trim();
  if (value) void window.remim.navigate(value);
});
$('#back-btn').addEventListener('click', () => { void window.remim.back(); });
$('#forward-btn').addEventListener('click', () => { void window.remim.forward(); });
$('#reload-btn').addEventListener('click', () => { void window.remim.reload(); });
$('#new-tab-btn').addEventListener('click', () => { void window.remim.newTab(); closePopup(); });
$('#low-memory-toggle').addEventListener('change', (event) => {
  void window.remim.toggleLowMemory((event.currentTarget as HTMLInputElement).checked);
});
$('#bookmark-current-btn').addEventListener('click', () => {
  if (!state || !/^https?:\/\//i.test(state.activeUrl)) return showToast('Open a web page before saving a bookmark.');
  const current = getBookmarks();
  const exists = current.some((item) => item.url === state!.activeUrl);
  if (exists) {
    persistArray(localStorageKeys.bookmarks, current.filter((item) => item.url !== state!.activeUrl));
    void cloud.removeBookmark(state.activeUrl);
    showToast('Bookmark removed.');
  } else {
    const item = { url: state.activeUrl, title: state.activeTitle || state.activeUrl, created_at: new Date().toISOString() };
    persistArray(localStorageKeys.bookmarks, [item, ...current].slice(0, 500));
    void cloud.saveBookmark(item);
    showToast('Bookmark saved.');
  }
  if (state) renderState(state);
});
$('#bookmarks-btn').addEventListener('click', () => renderListPanel('bookmarks'));
$('#history-btn').addEventListener('click', () => renderListPanel('history'));
$('#account-btn').addEventListener('click', renderAuthPanel);
$('#teleport-btn').addEventListener('click', async () => {
  if (!state || !/^https?:\/\//i.test(state.activeUrl)) return showToast('Open a web page to teleport it.');
  const error = await cloud.sendTransfer(state.activeUrl, state.activeTitle || state.activeUrl);
  if (error) showToast(error);
  else showToast('Tab sent. Other signed-in Remim devices should receive it shortly.');
});

cloud.onStatus(renderCloudStatus);
cloud.onTransfer(handleTransfer);
cloud.onBookmarks((remote) => {
  const merged = new Map<string, BookmarkRecord>();
  const localBookmarks = getBookmarks();
  for (const bookmark of [...remote, ...localBookmarks]) if (bookmark.url) merged.set(bookmark.url, bookmark);
  const combined = [...merged.values()].slice(0, 500);
  persistArray(localStorageKeys.bookmarks, combined);
  // Push device-only bookmarks to the signed-in account as well as pulling cloud ones.
  for (const bookmark of localBookmarks) void cloud.saveBookmark(bookmark);
  if (state) renderState(state);
});

window.remim.onState(renderState);
window.remim.onVisit((visit) => {
  if (!/^https?:\/\//i.test(visit.url)) return;
  const history = getHistory().filter((item) => item.url !== visit.url);
  history.unshift(visit);
  persistArray(localStorageKeys.history, history.slice(0, 300));
  void cloud.recordVisit(visit);
});
window.remim.onNotice((message) => showToast(message));
void window.remim.getState().then(renderState).catch(() => showToast('Browser engine did not initialize correctly. Restart Remim.'));

// A small local-only default state remains available when Supabase is not configured.
renderCloudStatus('Sign in to sync', null);
void cloud.bootstrap();
