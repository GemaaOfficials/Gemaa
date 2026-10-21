'use strict';

const HOME_URL = 'https://www.google.com/';
const TRACKER_HOSTS = [
  'doubleclick.net', 'googlesyndication.com', 'googleadservices.com',
  'google-analytics.com', 'googletagmanager.com', 'adservice.google.com',
  'connect.facebook.net', 'pixel.facebook.com', 'ads-twitter.com',
  'analytics.twitter.com', 'scorecardresearch.com', 'taboola.com',
  'outbrain.com', 'adroll.com', 'adnxs.com', 'criteo.com', 'hotjar.com',
  'clarity.ms', 'bat.bing.com', 'amazon-adsystem.com', 'casalemedia.com',
  'rubiconproject.com', 'pubmatic.com', 'openx.net', 'moatads.com'
];

function normalizeAddress(input) {
  const raw = String(input ?? '').trim();
  if (!raw) return HOME_URL;
  if (/^(javascript|file|data|vbscript):/i.test(raw)) return null;
  if (/^https?:\/\//i.test(raw)) {
    try {
      const parsed = new URL(raw);
      return ['http:', 'https:'].includes(parsed.protocol) ? parsed.toString() : null;
    } catch { return null; }
  }
  if (/^(localhost|127(?:\.\d{1,3}){3})(:\d+)?(?:\/|$)/i.test(raw)) {
    return `http://${raw}`;
  }
  if (/^[\w-]+(?:\.[\w-]+)+(?:\:\d+)?(?:\/[^\s]*)?$/i.test(raw)) {
    return `https://${raw}`;
  }
  return `https://www.google.com/search?q=${encodeURIComponent(raw)}`;
}

function isTrackerURL(raw) {
  try {
    const url = new URL(raw);
    const host = url.hostname.toLowerCase();
    if (TRACKER_HOSTS.some((blocked) => host === blocked || host.endsWith(`.${blocked}`))) return true;
    if (host === 'facebook.com' && url.pathname === '/tr') return true;
    if (/(^|\/)collect(?:\?|\/|$)/i.test(url.pathname + url.search)) return true;
    if (/(^|\/)pixel(?:\.gif|\.png)?(?:\?|$)/i.test(url.pathname + url.search) && /analytics|track|ads/i.test(url.hostname)) return true;
  } catch { /* invalid or non-network URL */ }
  return false;
}

module.exports = { HOME_URL, TRACKER_HOSTS, normalizeAddress, isTrackerURL };
