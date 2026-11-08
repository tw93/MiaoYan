'use strict';

// /payroom: the password gate and the dashboard. It only reads the snapshot
// payroom-sync.js writes; it never calls App Store Connect on a page view.

const crypto = require('node:crypto');
const { buildView, pacificToday, readState } = require('./_payroom-lib');
const { renderDashboard, renderLogin, renderMessage } = require('./_payroom-page');

const COOKIE = 'miaoyan_payroom';
const SESSION_SECONDS = 30 * 24 * 3600;
const CSP = "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src 'self' data:; form-action 'self'; base-uri 'none'; frame-ancestors 'none'";

function hmac(payload) {
  return crypto.createHmac('sha256', process.env.MIAOYAN_PAYROOM_SESSION_SECRET).update(payload).digest('base64url');
}

function safeEqual(a, b) {
  const x = crypto.createHash('sha256').update(String(a)).digest();
  const y = crypto.createHash('sha256').update(String(b)).digest();
  return crypto.timingSafeEqual(x, y);
}

function sessionCookie() {
  const payload = Buffer.from(JSON.stringify({ exp: Math.floor(Date.now() / 1000) + SESSION_SECONDS })).toString('base64url');
  return `${COOKIE}=${payload}.${hmac(payload)}; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=${SESSION_SECONDS}`;
}

function sessionValid(req) {
  const match = String(req.headers.cookie || '').split(';').map((c) => c.trim()).find((c) => c.startsWith(`${COOKIE}=`));
  if (!match) return false;
  const [payload, signature] = match.slice(COOKIE.length + 1).split('.');
  if (!payload || !signature || !safeEqual(signature, hmac(payload))) return false;
  try {
    return JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')).exp > Date.now() / 1000;
  } catch {
    return false;
  }
}

function send(res, status, html) {
  res.statusCode = status;
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('Cache-Control', 'private, no-store, max-age=0');
  res.setHeader('X-Robots-Tag', 'noindex, nofollow, noarchive');
  // Not no-referrer: under it a browser posts this page's form with `Origin: null`,
  // which sameOrigin() refuses, so no one could log in from a browser.
  res.setHeader('Referrer-Policy', 'same-origin');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Content-Security-Policy', CSP);
  res.end(html);
}

async function formPassword(req) {
  if (req.body && typeof req.body === 'object') return String(req.body.password || '');
  if (typeof req.body === 'string') return new URLSearchParams(req.body).get('password') || '';
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > 4096) return '';
    chunks.push(chunk);
  }
  return new URLSearchParams(Buffer.concat(chunks).toString('utf8')).get('password') || '';
}

function sameOrigin(req) {
  const origin = req.headers.origin;
  if (!origin) return true;
  try {
    return new URL(origin).host === req.headers.host;
  } catch {
    return false;
  }
}

function query(req) {
  const url = new URL(req.url, 'https://miaoyan.app');
  const r = url.searchParams.get('r') || '';
  const c = url.searchParams.get('c') || '';
  return {
    range: /^(7d|30d|90d|all|m:\d{4}-\d{2})$/.test(r) ? r : 'all',
    currency: c === 'USD' ? 'USD' : 'CNY',
  };
}

module.exports = async function handler(req, res) {
  const password = process.env.MIAOYAN_PAYROOM_PASSWORD;
  const configured = Boolean(password && process.env.MIAOYAN_PAYROOM_SESSION_SECRET);

  if (req.method === 'POST') {
    if (!configured) return send(res, 503, renderLogin({ unconfigured: true }));
    if (!sameOrigin(req)) return send(res, 403, renderLogin({ blocked: true }));
    if (!safeEqual(await formPassword(req), password)) return send(res, 401, renderLogin({ failed: true }));
    res.setHeader('Set-Cookie', sessionCookie());
    res.statusCode = 303;
    res.setHeader('Location', '/payroom');
    res.setHeader('Cache-Control', 'private, no-store, max-age=0');
    return res.end();
  }
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.statusCode = 405;
    res.setHeader('Allow', 'GET, HEAD, POST');
    return res.end();
  }
  if (!configured) return send(res, 503, renderLogin({ unconfigured: true }));
  if (!sessionValid(req)) return send(res, 200, renderLogin());

  let state;
  try {
    state = await readState();
  } catch (error) {
    console.error('payroom read failed', error.message);
    return send(res, 503, renderMessage('数据暂时读不到，稍后刷新。'));
  }
  if (!state) return send(res, 200, renderMessage('还没有同步过数据。'));
  return send(res, 200, renderDashboard(buildView(state, { ...query(req), today: pacificToday() })));
};
