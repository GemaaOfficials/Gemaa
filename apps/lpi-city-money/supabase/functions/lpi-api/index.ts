import { createClient } from "npm:@supabase/supabase-js@2.118.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const db = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false }
});
const CARD_STYLES = ["LPI NEON", "LPI AURA", "LPI ROYAL"];
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-lpi-api-key",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json"
};

function reply(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status, headers: cors });
}
function randHex(bytes = 32): string {
  const b = new Uint8Array(bytes);
  crypto.getRandomValues(b);
  return Array.from(b).map((x) => x.toString(16).padStart(2, "0")).join("");
}
function randDigits(count: number): string {
  const b = new Uint8Array(count);
  crypto.getRandomValues(b);
  return Array.from(b).map((x) => String(x % 10)).join("");
}
function bytesFromHex(hex: string): Uint8Array {
  const out = new Uint8Array(Math.floor(hex.length / 2));
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  return out;
}
function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes).map((x) => x.toString(16).padStart(2, "0")).join("");
}
async function shaHex(value: string): Promise<string> {
  return bytesToHex(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value))));
}
async function derivePassword(password: string, saltHex: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(password), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits({
    name: "PBKDF2", salt: bytesFromHex(saltHex), iterations: 180000, hash: "SHA-256"
  }, key, 256);
  return bytesToHex(new Uint8Array(bits));
}
function cleanName(name: unknown): { display: string; key: string } {
  const display = String(name || "").trim().replace(/\s+/g, " ");
  if (display.length < 3 || display.length > 24 || !/^[a-zA-Z0-9 _.-]+$/.test(display)) {
    throw new Error("Name must be 3–24 characters using letters, numbers, spaces, dots, _ or -.");
  }
  return { display, key: display.toLowerCase() };
}
function amountValue(value: unknown): number {
  const n = Number(value);
  if (!Number.isSafeInteger(n) || n < 1 || n > 100000000) throw new Error("Enter a whole-number amount in LPI game coins.");
  return n;
}
function publicUser(u: any) {
  const vipActive = Boolean(u.is_vip) && (Boolean(u.vip_lifetime) || !u.vip_expires_at || new Date(u.vip_expires_at).getTime() > Date.now());
  return {
    id: u.id, name: u.display_name, nameKey: u.name_key, balance: Number(u.balance),
    isVip: vipActive, vipLifetime: Boolean(u.vip_lifetime), vipExpiresAt: u.vip_expires_at || null,
    nextPaymentCashbackPercent: Number(u.next_payment_cashback_percent || 0),
    cardBrand: u.card_brand, createdAt: u.created_at
  };
}
async function makeSession(userId: string, isAdmin = false): Promise<string> {
  const token = randHex(32);
  const { error } = await db.from("lpi_sessions").insert({
    user_id: userId, token_hash: await shaHex(token), is_admin: isAdmin,
    expires_at: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString()
  });
  if (error) throw error;
  return token;
}
async function findSession(token: string, admin = false): Promise<any> {
  if (!token || token.length < 32) throw new Error("Please sign in again.");
  const { data, error } = await db.from("lpi_sessions").select("id,user_id,is_admin,expires_at")
    .eq("token_hash", await shaHex(token)).eq("is_admin", admin)
    .gt("expires_at", new Date().toISOString()).maybeSingle();
  if (error) throw error;
  if (!data || !data.user_id) throw new Error("Session expired. Please sign in again.");
  return data;
}
async function requireUser(token: string): Promise<any> {
  const session = await findSession(token, false);
  const { data, error } = await db.from("lpi_users")
    .select("id,display_name,name_key,balance,is_vip,vip_expires_at,vip_lifetime,next_payment_cashback_percent,card_brand,created_at")
    .eq("id", session.user_id).single();
  if (error || !data) throw new Error("Account could not be loaded. Please sign in again.");
  return data;
}
async function requireAdmin(token: string, userId: string): Promise<void> {
  const session = await findSession(token, true);
  if (session.user_id !== userId) throw new Error("Admin session does not match this account.");
}
async function callRpc(name: string, args: Record<string, unknown>): Promise<any> {
  const { data, error } = await db.rpc(name, args);
  if (error) throw new Error(error.message || "The game operation failed.");
  return data;
}
async function refreshGold(): Promise<any> {
  const { data, error } = await db.from("lpi_gold_market").select("price,updated_at").eq("id", 1).single();
  if (error) throw error;
  if (Date.now() - new Date(data.updated_at).getTime() > 60000) {
    const move = (Math.random() * 0.06) - 0.03;
    const price = Math.max(10, Math.round(Number(data.price) * (1 + move) * 100) / 100);
    const { data: updated, error: updateError } = await db.from("lpi_gold_market")
      .update({ price: price, updated_at: new Date().toISOString() }).eq("id", 1).select("price,updated_at").single();
    if (!updateError && updated) return updated;
  }
  return data;
}
async function dashboard(user: any): Promise<Record<string, unknown>> {
  await db.rpc("lpi_process_sips", { p_user_id: user.id });
  const market = await refreshGold();
  const results = await Promise.all([
    db.from("lpi_cards").select("card_brand,card_number,cvv,exp_month,exp_year").eq("user_id", user.id).maybeSingle(),
    db.from("lpi_transfers").select("id,amount,payer_debit,discount,cashback,cashback_percent,payment_method,note,created_at,from_user:lpi_users!lpi_transfers_from_user_id_fkey(display_name),to_user:lpi_users!lpi_transfers_to_user_id_fkey(display_name)")
      .or("from_user_id.eq." + user.id + ",to_user_id.eq." + user.id).order("created_at", { ascending: false }).limit(18),
    db.from("lpi_bills").select("id,amount,memo,status,due_at,postponed_once,created_at")
      .eq("user_id", user.id).neq("status", "paid").order("due_at", { ascending: true }),
    db.from("lpi_sips").select("id,amount,active,total_contributed,missed_payments,next_due_date,created_at")
      .eq("user_id", user.id).order("created_at", { ascending: false }),
    db.from("lpi_announcements").select("id,message,kind,created_at").order("created_at", { ascending: false }).limit(12),
    db.from("lpi_payment_requests").select("id,amount,status,expires_at,created_at")
      .eq("receiver_user_id", user.id).eq("status", "pending").gt("expires_at", new Date().toISOString()).order("created_at", { ascending: false }).limit(6),
    db.from("lpi_gold_holdings").select("units").eq("user_id", user.id).maybeSingle(),
    db.from("lpi_media_cards").select("id,title,media_url,content_type,created_at").eq("user_id", user.id).order("created_at", { ascending: false }).limit(12),
    db.from("lpi_spin_history").select("id").eq("user_id", user.id).eq("spin_date", new Date().toISOString().slice(0, 10)).maybeSingle(),
    db.from("lpi_spin_config").select("enabled").eq("id", 1).maybeSingle(),
    db.from("lpi_gift_cards").select("id,card_brand,amount,created_at,expires_at,redeemed_at,code_display").eq("issuer_user_id", user.id).order("created_at", { ascending: false }).limit(25)
  ]);
  for (const result of results) if (result.error) throw new Error("Could not load all city data. Please refresh.");
  const refreshed = await db.from("lpi_users").select("id,display_name,name_key,balance,is_vip,vip_expires_at,vip_lifetime,next_payment_cashback_percent,card_brand,created_at").eq("id", user.id).single();
  if (refreshed.error) throw refreshed.error;
  return {
    user: publicUser(refreshed.data),
    card: results[0].data,
    transfers: results[1].data || [],
    bills: results[2].data || [],
    sips: results[3].data || [],
    announcements: results[4].data || [],
    pendingRequests: results[5].data || [],
    gold: { price: Number(market.price), updatedAt: market.updated_at, units: Number((results[6].data || {}).units || 0) },
    mediaCards: results[7].data || [],
    spinUsedToday: Boolean(results[8].data),
    spinEnabled: Boolean(results[9].data && results[9].data.enabled),
    giftCards: results[10].data || []
  };
}
async function createAccount(body: any) {
  const n = cleanName(body.name);
  const password = String(body.password || "");
  if (password.length < 6 || password.length > 128) throw new Error("Password must be 6–128 characters.");
  const salt = randHex(16);
  const password_hash = await derivePassword(password, salt);
  const style = CARD_STYLES[Math.floor(Math.random() * CARD_STYLES.length)];
  const { data: user, error } = await db.from("lpi_users").insert({
    display_name: n.display, name_key: n.key, password_salt: salt,
    password_hash: password_hash, card_brand: style, balance: 5000
  }).select("id,display_name,name_key,balance,is_vip,vip_expires_at,vip_lifetime,next_payment_cashback_percent,card_brand,created_at").single();
  if (error) {
    if (error.code === "23505") throw new Error("That name is already taken. Try another name.");
    throw error;
  }
  const now = new Date();
  const expires = new Date(now.getFullYear(), now.getMonth() + 24, 1);
  const { error: cardError } = await db.from("lpi_cards").insert({
    user_id: user.id, card_brand: style, card_number: randDigits(16), cvv: randDigits(3),
    exp_month: expires.getMonth() + 1, exp_year: expires.getFullYear()
  });
  if (cardError) {
    await db.from("lpi_users").delete().eq("id", user.id);
    throw cardError;
  }
  await db.from("lpi_announcements").insert({ message: n.display + " joined LPI City", kind: "news" });
  return { token: await makeSession(user.id), user: publicUser(user) };
}
async function login(body: any) {
  const n = cleanName(body.name);
  const password = String(body.password || "");
  const { data, error } = await db.from("lpi_users")
    .select("id,display_name,name_key,password_salt,password_hash,balance,is_vip,card_brand,created_at")
    .eq("name_key", n.key).maybeSingle();
  if (error) throw error;
  if (!data) throw new Error("Name or password is incorrect.");
  const check = await derivePassword(password, data.password_salt);
  if (check !== data.password_hash) throw new Error("Name or password is incorrect.");
  return { token: await makeSession(data.id), user: publicUser(data) };
}
const MINIMUM_CLIENT_VERSION = "0.2.1";
const UPDATE_REQUIRED_ACTIONS = new Set([
  "transfer", "request_create", "request_approve", "vip_buy", "spin_play",
  "gift_create", "gift_redeem", "bill_pay", "bill_postpone", "sip_create",
  "sip_cancel", "gold_trade", "admin_grant", "admin_bill_create",
  "admin_announce", "admin_spin_update", "admin_media_upload",
  "admin_api_create", "admin_api_revoke"
]);
function isClientVersionAtLeast(version: string, minimum: string): boolean {
  const parse = (value: string) => String(value || "0").replace(/^v/i, "").split(/[.+-]/).slice(0, 3)
    .map((part) => { const n = Number.parseInt(part, 10); return Number.isFinite(n) ? n : 0; });
  const a = parse(version), b = parse(minimum);
  for (let i = 0; i < 3; i++) { if (a[i] > b[i]) return true; if (a[i] < b[i]) return false; }
  return true;
}

async function apiRequest(body: any): Promise<Response> {
  const key = String(body.apiKey || body.key || "");
  if (!key.startsWith("lpi_test_")) return reply(401, { error: "Invalid sandbox API key." });
  const keyHash = await shaHex(key);
  const { data: apiKey, error } = await db.from("lpi_api_keys")
    .select("id,label,scopes,is_active").eq("key_hash", keyHash).maybeSingle();
  if (error || !apiKey || !apiKey.is_active) return reply(401, { error: "Invalid or revoked sandbox API key." });
  const operation = String(body.operation || "");
  const scope = operation === "balance" ? "balance" : operation;
  if (!["balance", "deposit", "withdraw"].includes(scope) || !(apiKey.scopes || []).includes(scope)) {
    return reply(403, { error: "This sandbox key does not have the requested scope." });
  }
  const n = cleanName(body.userName);
  const { data: target, error: targetError } = await db.from("lpi_users")
    .select("id,display_name,name_key,balance").eq("name_key", n.key).maybeSingle();
  if (targetError || !target) return reply(404, { error: "LPI game account not found." });
  if (operation === "balance") {
    await db.from("lpi_api_audit").insert({ api_key_id: apiKey.id, user_id: target.id, action: "balance", amount: null });
    return reply(200, { sandbox: true, userName: target.display_name, balance: Number(target.balance), currency: "LPI game coins" });
  }
  const amount = amountValue(body.amount);
  const result = await callRpc("lpi_api_adjust", {
    p_target_user_id: target.id, p_amount: amount, p_mode: operation, p_api_key_id: apiKey.id
  });
  return reply(200, { sandbox: true, userName: target.display_name, currency: "LPI game coins", result: result });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply(405, { error: "Use POST for LPI API requests." });
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) return reply(500, { error: "LPI server configuration is incomplete." });
  let body: any = {};
  try {
    body = await req.json();
    if (body.apiKey || body.key) return await apiRequest(body);
    const action = String(body.action || "");
    if (action === "signup") return reply(200, await createAccount(body));
    if (action === "login") return reply(200, await login(body));
    if (action === "admin_login") {
      const user = await requireUser(String(body.token || ""));
      const { data, error } = await db.rpc("lpi_check_admin_password", { p_password: String(body.password || "") });
      if (error) throw error;
      if (data !== true) return reply(401, { error: "Admin password is incorrect." });
      return reply(200, { adminToken: await makeSession(user.id, true) });
    }
    const user = await requireUser(String(body.token || ""));
    if (UPDATE_REQUIRED_ACTIONS.has(action) && !isClientVersionAtLeast(String(body.appVersion || "0.0.0"), MINIMUM_CLIENT_VERSION)) {
      return reply(426, {
        error: "Update required: install LPI City Money v" + MINIMUM_CLIENT_VERSION +
          " to use payments and the latest features. Open https://github.com/GemaaOfficials/Gemaa/releases/latest and install the Windows EXE or Android APK. Your city account and LPI game coins are unchanged."
      });
    }
    if (action === "dashboard") return reply(200, await dashboard(user));
    if (action === "logout") {
      await db.from("lpi_sessions").delete().eq("token_hash", await shaHex(String(body.token || "")));
      if (body.adminToken) await db.from("lpi_sessions").delete().eq("token_hash", await shaHex(String(body.adminToken)));
      return reply(200, { success: true });
    }
    if (action === "directory_search") {
      const q = String(body.query || "").trim().toLowerCase().replace(/[%_]/g, "").slice(0, 24);
      if (q.length < 1) return reply(200, { users: [] });
      const { data, error } = await db.from("lpi_users")
        .select("id,display_name,name_key,card_brand,is_vip,vip_expires_at,vip_lifetime")
        .neq("id", user.id).ilike("name_key", "%" + q + "%").limit(10);
      if (error) throw error;
      return reply(200, { users: (data || []).map((x: any) => ({
        id: x.id, name: x.display_name, nameKey: x.name_key, cardBrand: x.card_brand,
        isVip: Boolean(x.is_vip) && (Boolean(x.vip_lifetime) || !x.vip_expires_at || new Date(x.vip_expires_at).getTime() > Date.now())
      })) });
    }
    if (action === "transfer") {
      const n = cleanName(body.toName);
      const amount = amountValue(body.amount);
      const { data: target, error } = await db.from("lpi_users").select("id,display_name").eq("name_key", n.key).maybeSingle();
      if (error || !target) throw new Error("Receiver account not found. Check the name.");
      const result = await callRpc("lpi_transfer", { p_from: user.id, p_to: target.id, p_amount: amount, p_method: body.method === "card" ? "card" : "direct" });
      return reply(200, { success: true, receiver: target.display_name, result: result });
    }
    if (action === "request_create") {
      const amount = amountValue(body.amount);
      const code = randDigits(6);
      const { data, error } = await db.from("lpi_payment_requests").insert({
        receiver_user_id: user.id, amount: amount, code_hash: await shaHex(code),
        expires_at: new Date(Date.now() + 10 * 60 * 1000).toISOString()
      }).select("id,amount,expires_at").single();
      if (error) throw error;
      return reply(200, { request: data, code: code, qrPayload: "lpi://pay/" + code });
    }
    if (action === "request_lookup") {
      const code = String(body.code || "").replace(/\D/g, "");
      if (code.length !== 6) throw new Error("Enter the 6-digit city payment code.");
      const { data: reqRow, error } = await db.from("lpi_payment_requests").select("id,receiver_user_id,amount,expires_at,status")
        .eq("code_hash", await shaHex(code)).eq("status", "pending").gt("expires_at", new Date().toISOString()).maybeSingle();
      if (error || !reqRow) throw new Error("Payment code is invalid or expired.");
      if (reqRow.receiver_user_id === user.id) throw new Error("This is your own request.");
      const { data: receiver } = await db.from("lpi_users").select("display_name,card_brand").eq("id", reqRow.receiver_user_id).single();
      return reply(200, { request: { id: reqRow.id, amount: Number(reqRow.amount), expiresAt: reqRow.expires_at, receiverName: receiver.display_name, receiverBrand: receiver.card_brand } });
    }
    if (action === "request_approve") {
      const result = await callRpc("lpi_complete_payment_request", { p_request_id: String(body.requestId || ""), p_payer_id: user.id });
      return reply(200, { success: true, result: result });
    }
    if (action === "vip_buy") {
      const duration = String(body.duration || "30m");
      if (!["30m", "lifetime"].includes(duration)) throw new Error("Choose 30-minute or lifetime VIP.");
      const result = await callRpc("lpi_buy_vip", { p_user_id: user.id, p_duration: duration });
      return reply(200, { success: true, result: result });
    }
    if (action === "spin_play") {
      const { data: spinConfig, error: spinConfigError } = await db.from("lpi_spin_config").select("enabled").eq("id", 1).single();
      if (spinConfigError) throw spinConfigError;
      if (!spinConfig.enabled) throw new Error("The city admin has paused the daily spin. Check back later.");
      const result = await callRpc("lpi_play_spin", { p_user_id: user.id });
      return reply(200, { success: true, result: result });
    }
    if (action === "gift_create") {
      const amount = amountValue(body.amount);
      const { data: owner } = await db.from("lpi_users").select("card_brand").eq("id", user.id).single();
      const requestedBrand = body.giftBrand == null ? owner.card_brand : String(body.giftBrand).trim().toUpperCase();
      if (!["LPI NEON", "LPI AURA", "LPI ROYAL"].includes(requestedBrand)) throw new Error("Choose a valid LPI gift-card style.");
      const code = randDigits(16);
      const result = await callRpc("lpi_create_gift_card", { p_issuer: user.id, p_amount: amount, p_code_hash: await shaHex(code), p_brand: requestedBrand });
      const { error: displayCodeError } = await db.from("lpi_gift_cards").update({ code_display: code }).eq("id", result.gift_card_id).eq("issuer_user_id", user.id);
      return reply(200, { success: true, code: code, brand: requestedBrand, codeSaved: !displayCodeError, result: result });
    }
    if (action === "gift_redeem") {
      const code = String(body.code || "").replace(/\D/g, "");
      if (code.length !== 16) throw new Error("Enter the 16-digit LPI gift code.");
      const result = await callRpc("lpi_redeem_gift_card", { p_user_id: user.id, p_code_hash: await shaHex(code) });
      return reply(200, { success: true, result: result });
    }
    if (action === "bill_pay") {
      const result = await callRpc("lpi_pay_bill", { p_bill_id: String(body.billId || ""), p_user_id: user.id });
      return reply(200, { success: true, result: result });
    }
    if (action === "bill_postpone") {
      const { data, error } = await db.from("lpi_bills").update({
        status: "postponed", due_at: new Date(Date.now() + 10 * 60 * 1000).toISOString(), postponed_once: true
      }).eq("id", String(body.billId || "")).eq("user_id", user.id).eq("postponed_once", false)
        .neq("status", "paid").select("id").maybeSingle();
      if (error) throw error;
      if (!data) throw new Error("This bill has already been postponed or paid.");
      return reply(200, { success: true, message: "Bill postponed for 10 minutes. The app will show it as overdue after the deadline; your phone will not be locked." });
    }
    if (action === "sip_create") {
      const amount = Number(body.amount);
      if (![10, 20, 30].includes(amount)) throw new Error("Choose a 10, 20 or 30 game-coin daily SIP.");
      const { data, error } = await db.from("lpi_sips").insert({
        user_id: user.id, amount: amount, next_due_date: new Date(Date.now() + 86400000).toISOString().slice(0, 10)
      }).select("id,amount,active,next_due_date").single();
      if (error) throw error;
      return reply(200, { success: true, sip: data });
    }
    if (action === "sip_cancel") {
      const { data, error } = await db.from("lpi_sips").update({ active: false })
        .eq("id", String(body.sipId || "")).eq("user_id", user.id).eq("active", true).select("id").maybeSingle();
      if (error) throw error;
      if (!data) throw new Error("That SIP is already paused or not found.");
      return reply(200, { success: true });
    }
    if (action === "gold_quote") {
      const market = await refreshGold();
      const { data: holdings } = await db.from("lpi_gold_holdings").select("units").eq("user_id", user.id).maybeSingle();
      return reply(200, { price: Number(market.price), updatedAt: market.updated_at, units: Number((holdings || {}).units || 0) });
    }
    if (action === "gold_trade") {
      const units = Number(body.units);
      if (!Number.isFinite(units) || units <= 0 || Math.round(units * 1000) !== units * 1000) throw new Error("Enter gold units with up to 3 decimal places.");
      const market = await refreshGold();
      const result = await callRpc("lpi_trade_gold", { p_user_id: user.id, p_units: units, p_side: body.side });
      return reply(200, { success: true, marketPrice: Number(market.price), result: result });
    }
    if (action === "admin_users") {
      await requireAdmin(String(body.adminToken || ""), user.id);
      const { data, error } = await db.from("lpi_users")
        .select("id,display_name,name_key,balance,is_vip,vip_expires_at,vip_lifetime,next_payment_cashback_percent,card_brand,created_at")
        .order("created_at", { ascending: false }).limit(250);
      if (error) throw error;
      return reply(200, { users: (data || []).map(publicUser) });
    }
    if (action === "admin_grant") {
      await requireAdmin(String(body.adminToken || ""), user.id);
      const amount = amountValue(body.amount);
      const result = await callRpc("lpi_admin_grant", {
        p_target_user_id: String(body.userId || ""), p_amount: amount,
        p_note: String(body.note || "Admin coin grant").slice(0, 120)
      });
      return reply(200, { success: true, result: result });
    }
    if (action === "admin_bill_create") {
      await requireAdmin(String(body.adminToken || ""), user.id);
      const amount = amountValue(body.amount);
      const memo = String(body.memo || "City bill").trim().slice(0, 120) || "City bill";
      const { data: target, error: targetError } = await db.from("lpi_users").select("id,display_name").eq("id", String(body.userId || "")).maybeSingle();
      if (targetError || !target) throw new Error("Select a valid city player.");
      const { data, error } = await db.from("lpi_bills").insert({
        user_id: target.id, issued_by_user_id: user.id, amount: amount, memo: memo,
        due_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString()
      }).select("id").single();
      if (error) throw error;
      await db.from("lpi_announcements").insert({ message: "A new city bill was issued to " + target.display_name, kind: "admin" });
      return reply(200, { success: true, billId: data.id, userName: target.display_name });
    }
    if (action === "admin_announce") {
      await requireAdmin(String(body.adminToken || ""), user.id);
      const message = String(body.message || "").trim().slice(0, 250);
      if (message.length < 3) throw new Error("Announcement must be at least 3 characters.");
      const { error } = await db.from("lpi_announcements").insert({ message: message, kind: "admin" });
      if (error) throw error;
      return reply(200, { success: true });
    }
    if (action === "admin_spin_get") {
      await requireAdmin(String(body.adminToken || ""), user.id);
      const { data, error } = await db.from("lpi_spin_config").select("reward_config,updated_at,enabled").eq("id", 1).single();
      if (error) throw error;
      return reply(200, { rewardConfig: data.reward_config, updatedAt: data.updated_at, enabled: Boolean(data.enabled) });
    }
    if (action === "admin_spin_update") {
      await requireAdmin(String(body.adminToken || ""), user.id);
      const enabled = body.enabled !== false;
      const rawCoins = String(body.coins || "10,20,30").split(",").map((x) => Number(x.trim())).filter((x) => Number.isInteger(x) && x >= 1 && x <= 100000);
      const coins = Array.from(new Set(rawCoins)).slice(0, 6);
      if (coins.length < 1) throw new Error("Enter at least one valid LPI coin reward.");
      const cashbackPct = Number(body.cashbackPct || 0);
      const vipMinutes = Number(body.vipMinutes || 0);
      if (!Number.isInteger(cashbackPct) || cashbackPct < 0 || cashbackPct > 50) throw new Error("Cashback must be 0–50 percent.");
      if (!Number.isInteger(vipMinutes) || vipMinutes < 0 || vipMinutes > 1440) throw new Error("VIP minutes must be 0–1,440.");
      const rewards: Array<{type:string;amount:number;label:string;weight:number}> = coins.map((amount) => ({ type: "coins", amount, label: amount + " LPI bonus coins", weight: 3 }));
      if (cashbackPct > 0) rewards.push({ type: "cashback", amount: cashbackPct, label: cashbackPct + "% cashback coupon", weight: 1 });
      if (vipMinutes > 0) rewards.push({ type: "vip", amount: vipMinutes, label: vipMinutes + "-minute VIP pass", weight: 1 });
      const { error } = await db.from("lpi_spin_config").upsert({ id: 1, reward_config: rewards, enabled: enabled, updated_at: new Date().toISOString(), updated_by: user.id }, { onConflict: "id" });
      if (error) throw error;
      return reply(200, { success: true, rewardConfig: rewards, enabled: enabled });
    }
    if (action === "admin_media_upload") {
      await requireAdmin(String(body.adminToken || ""), user.id);
      const targetId = String(body.userId || "");
      const title = String(body.title || "A city card").trim().slice(0, 80) || "A city card";
      const contentType = String(body.contentType || "");
      if (!["image/jpeg", "image/png", "image/webp", "video/mp4"].includes(contentType)) throw new Error("Choose a JPG, PNG, WebP image or MP4 video.");
      const mediaBase64 = String(body.mediaBase64 || "");
      if (!mediaBase64 || mediaBase64.length > 5600000) throw new Error("Media is empty or larger than 4 MB. Choose a smaller file.");
      const { data: target, error: targetError } = await db.from("lpi_users").select("id,display_name").eq("id", targetId).maybeSingle();
      if (targetError || !target) throw new Error("Select a valid city player.");
      const binary = atob(mediaBase64);
      const bytes = new Uint8Array(binary.length);
      for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
      if (bytes.byteLength > 4 * 1024 * 1024) throw new Error("Media must be 4 MB or smaller.");
      const ext = contentType === "image/jpeg" ? "jpg" : contentType.split("/")[1];
      const path = user.id + "/" + crypto.randomUUID() + "." + ext;
      const { error: uploadError } = await db.storage.from("lpi-admin-media").upload(path, bytes, { contentType, upsert: false, cacheControl: "3600" });
      if (uploadError) throw uploadError;
      const mediaUrl = db.storage.from("lpi-admin-media").getPublicUrl(path).data.publicUrl;
      const { data, error } = await db.from("lpi_media_cards").insert({
        user_id: target.id, admin_user_id: user.id, title, media_url: mediaUrl, content_type: contentType
      }).select("id,title,media_url,content_type,created_at").single();
      if (error) throw error;
      await db.from("lpi_announcements").insert({ message: "A new city media card was sent to " + target.display_name, kind: "admin" });
      return reply(200, { success: true, card: data, userName: target.display_name });
    }
    if (action === "admin_api_create") {
      await requireAdmin(String(body.adminToken || ""), user.id);
      const label = String(body.label || "Fry Trading").trim().slice(0, 60) || "Game integration";
      const allowed = ["balance", "deposit", "withdraw"];
      const scopes = Array.isArray(body.scopes) ? body.scopes.filter((s: unknown) => allowed.includes(String(s))) : ["balance"];
      if (scopes.length === 0) throw new Error("Choose at least one API scope.");
      const key = "lpi_test_" + randHex(24);
      const { data, error } = await db.from("lpi_api_keys").insert({
        label: label, key_hash: await shaHex(key), key_last4: key.slice(-4), scopes: Array.from(new Set(scopes)), created_by_user_id: user.id
      }).select("id,label,key_last4,scopes,created_at").single();
      if (error) throw error;
      return reply(200, { success: true, key: key, apiKey: data });
    }
    if (action === "admin_api_list") {
      await requireAdmin(String(body.adminToken || ""), user.id);
      const { data, error } = await db.from("lpi_api_keys").select("id,label,key_last4,scopes,is_active,created_at,revoked_at")
        .order("created_at", { ascending: false }).limit(100);
      if (error) throw error;
      return reply(200, { keys: data || [] });
    }
    if (action === "admin_api_revoke") {
      await requireAdmin(String(body.adminToken || ""), user.id);
      const { data, error } = await db.from("lpi_api_keys").update({ is_active: false, revoked_at: new Date().toISOString() })
        .eq("id", String(body.keyId || "")).eq("is_active", true).select("id").maybeSingle();
      if (error) throw error;
      if (!data) throw new Error("API key is already revoked or unavailable.");
      return reply(200, { success: true });
    }
    return reply(400, { error: "Unknown LPI action." });
  } catch (err) {
    const message = err instanceof Error ? err.message : "LPI server error.";
    const status = /Session expired|sign in again/.test(message) ? 401 : 400;
    return reply(status, { error: message });
  }
});
