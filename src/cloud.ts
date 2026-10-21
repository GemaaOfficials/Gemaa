import { createClient, type SupabaseClient, type User } from '@supabase/supabase-js';

export interface BookmarkRecord {
  url: string;
  title: string;
  created_at?: string;
}

export interface TransferRecord {
  id: string;
  user_id: string;
  sender_device_id: string;
  target_device_id: string | null;
  url: string;
  title: string;
  created_at: string;
  expires_at: string;
}

const DEVICE_STORAGE_KEY = 'remim.device-id.v1';

function getDeviceId(): string {
  try {
    const existing = localStorage.getItem(DEVICE_STORAGE_KEY);
    if (existing) return existing;
    const id = globalThis.crypto?.randomUUID?.() ?? `remim-${Date.now()}-${Math.random().toString(36).slice(2)}`;
    localStorage.setItem(DEVICE_STORAGE_KEY, id);
    return id;
  } catch {
    return `remim-${Date.now()}-${Math.random().toString(36).slice(2)}`;
  }
}

function isUsableSupabaseConfig(url: string, key: string): boolean {
  return /^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(url.trim()) &&
    key.trim().length > 20 && !key.includes('YOUR_');
}

export class CloudSync {
  readonly deviceId = getDeviceId();
  readonly client: SupabaseClient | null;
  readonly configured: boolean;

  private activeUserId: string | null = null;
  private transferChannel: ReturnType<SupabaseClient['channel']> | null = null;
  private authSubscription: { unsubscribe: () => void } | null = null;
  private heartbeatTimer: number | null = null;
  private statusListener: (status: string, user: User | null) => void = () => {};
  private transferListener: (transfer: TransferRecord) => void = () => {};
  private bookmarksListener: (bookmarks: BookmarkRecord[]) => void = () => {};
  private currentUrl = '';
  private currentTitle = 'Remim';
  private currentUser: User | null = null;

  constructor() {
    const url = (import.meta.env.VITE_SUPABASE_URL || '').trim();
    const key = (import.meta.env.VITE_SUPABASE_ANON_KEY || '').trim();
    this.configured = isUsableSupabaseConfig(url, key);
    this.client = this.configured ? createClient(url, key, {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false },
      realtime: { params: { eventsPerSecond: 5 } }
    }) : null;
  }

  onStatus(listener: (status: string, user: User | null) => void): void { this.statusListener = listener; }
  onTransfer(listener: (transfer: TransferRecord) => void): void { this.transferListener = listener; }
  onBookmarks(listener: (bookmarks: BookmarkRecord[]) => void): void { this.bookmarksListener = listener; }

  async bootstrap(): Promise<void> {
    if (!this.client) {
      this.statusListener('Set Supabase values in .env to enable sync', null);
      return;
    }
    const { data, error } = await this.client.auth.getSession();
    if (error) {
      this.statusListener('Cloud unavailable', null);
      return;
    }
    this.authSubscription = this.client.auth.onAuthStateChange((_event: string, session: { user: User } | null) => {
      if (session?.user) void this.activateUser(session.user);
      else void this.deactivateUser();
    }).data.subscription;
    if (data.session?.user) await this.activateUser(data.session.user);
    else this.statusListener('Sign in to sync', null);
  }

  async signIn(email: string, password: string, createAccount = false): Promise<string | null> {
    if (!this.client) return 'Supabase is not configured. Copy .env.example to .env and add your project URL and publishable/anon key.';
    const result = createAccount
      ? await this.client.auth.signUp({ email, password })
      : await this.client.auth.signInWithPassword({ email, password });
    if (result.error) return result.error.message;
    if (createAccount && !result.data.session) return 'Account created. Check your email if confirmation is enabled, then sign in.';
    return null;
  }

  async signOut(): Promise<void> {
    if (!this.client) return;
    const { error } = await this.client.auth.signOut();
    if (error) this.statusListener(`Sign-out error: ${error.message}`, this.currentUser);
  }

  async sendTransfer(url: string, title: string): Promise<string | null> {
    if (!this.client || !this.currentUser) return 'Sign in on both devices to use Session Teleport.';
    if (!/^https?:\/\//i.test(url)) return 'Only HTTP or HTTPS pages can be transferred.';
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();
    const { error } = await this.client.from('session_transfers').insert({
      user_id: this.currentUser.id,
      sender_device_id: this.deviceId,
      target_device_id: null,
      url,
      title: title.slice(0, 300),
      status: 'pending',
      expires_at: expiresAt
    });
    return error ? error.message : null;
  }

  async saveBookmark(bookmark: BookmarkRecord): Promise<void> {
    if (!this.client || !this.currentUser) return;
    const { error } = await this.client.from('bookmarks').upsert({
      user_id: this.currentUser.id,
      url: bookmark.url,
      title: bookmark.title.slice(0, 300)
    }, { onConflict: 'user_id,url' });
    if (error) this.statusListener(`Bookmark sync paused: ${error.message}`, this.currentUser);
  }

  async removeBookmark(url: string): Promise<void> {
    if (!this.client || !this.currentUser) return;
    const { error } = await this.client.from('bookmarks').delete()
      .eq('user_id', this.currentUser.id).eq('url', url);
    if (error) this.statusListener(`Bookmark sync paused: ${error.message}`, this.currentUser);
  }

  async recordVisit(visit: { url: string; title: string; visitedAt: string }): Promise<void> {
    this.currentUrl = visit.url;
    this.currentTitle = visit.title;
    if (!this.client || !this.currentUser || !/^https?:\/\//i.test(visit.url)) return;
    const { error } = await this.client.from('browsing_history').insert({
      user_id: this.currentUser.id,
      url: visit.url,
      title: visit.title.slice(0, 300),
      visited_at: visit.visitedAt
    });
    if (error) this.statusListener(`History sync paused: ${error.message}`, this.currentUser);
    await this.updateDeviceSession();
  }

  async loadBookmarks(): Promise<BookmarkRecord[]> {
    if (!this.client || !this.currentUser) return [];
    const { data, error } = await this.client.from('bookmarks')
      .select('url,title,created_at').eq('user_id', this.currentUser.id)
      .order('created_at', { ascending: false }).limit(500);
    if (error) {
      this.statusListener(`Could not load cloud bookmarks: ${error.message}`, this.currentUser);
      return [];
    }
    const bookmarks = (data ?? []) as BookmarkRecord[];
    this.bookmarksListener(bookmarks);
    return bookmarks;
  }

  private async activateUser(user: User): Promise<void> {
    if (!this.client || this.activeUserId === user.id) {
      this.currentUser = user;
      this.statusListener('Synced', user);
      return;
    }
    await this.deactivateUser(false);
    this.activeUserId = user.id;
    this.currentUser = user;
    this.statusListener('Connecting…', user);
    await this.updateDeviceSession();
    this.transferChannel = this.client.channel(`remim-transfers:${user.id}:${this.deviceId}`)
      .on('postgres_changes', {
        event: 'INSERT', schema: 'public', table: 'session_transfers',
        filter: `user_id=eq.${user.id}`
      }, (payload: any) => {
        const row = payload.new as TransferRecord;
        const notExpired = row.expires_at ? new Date(row.expires_at).getTime() > Date.now() : true;
        const addressedHere = !row.target_device_id || row.target_device_id === this.deviceId;
        if (row.sender_device_id !== this.deviceId && addressedHere && notExpired && /^https?:\/\//i.test(row.url)) {
          this.transferListener(row);
        }
      }).subscribe((status: string) => {
        if (status === 'SUBSCRIBED') this.statusListener('Synced', this.currentUser);
        else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') this.statusListener('Realtime reconnecting…', this.currentUser);
      });
    this.heartbeatTimer = window.setInterval(() => { void this.updateDeviceSession(); }, 60_000);
    await this.loadBookmarks();
  }

  private async deactivateUser(updateStatus = true): Promise<void> {
    if (this.heartbeatTimer !== null) window.clearInterval(this.heartbeatTimer);
    this.heartbeatTimer = null;
    if (this.client && this.transferChannel) await this.client.removeChannel(this.transferChannel);
    this.transferChannel = null;
    this.activeUserId = null;
    this.currentUser = null;
    if (updateStatus) this.statusListener(this.configured ? 'Sign in to sync' : 'Set Supabase values in .env to enable sync', null);
  }

  private async updateDeviceSession(): Promise<void> {
    if (!this.client || !this.currentUser) return;
    const { error } = await this.client.from('device_sessions').upsert({
      user_id: this.currentUser.id,
      device_id: this.deviceId,
      device_name: `Remim Desktop (${navigator.platform || 'desktop'})`,
      platform: 'windows-desktop',
      current_url: this.currentUrl || null,
      current_title: this.currentTitle.slice(0, 300),
      last_seen: new Date().toISOString(),
      is_active: true
    }, { onConflict: 'user_id,device_id' });
    if (error) this.statusListener(`Sync unavailable: ${error.message}`, this.currentUser);
  }
}
