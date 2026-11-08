'use strict';

// Payroom's data layer: App Store Connect reads, the private Blob that holds
// them, and the aggregation the page renders. No dependency: this deploys from
// a public branch as plain functions, and every secret is environment-only.

const crypto = require('node:crypto');
const zlib = require('node:zlib');

const APP_ID = '6759252269';
const STATE_PATH = 'payroom/state.json.gz';
const ASC = 'https://api.appstoreconnect.apple.com';
const FIRST_SALES_LOOKBACK_DAYS = 365;
const RECHECK_EMPTY_DAYS = 7;
const TRAFFIC_START = '2022-06-01';
const RECENT_DAYS = 14;
const SYNC_STALE_MS = 12 * 3600 * 1000;

// Standard rather than Detailed: Apple applies fewer privacy cuts to it.
const ANALYTICS_REPORTS = {
  purchases: {
    name: 'App Store Purchases Standard',
    dims: ['Source Type', 'Source Info', 'Device', 'Territory'],
    measures: ['Purchases', 'Proceeds in USD', 'Sales in USD'],
  },
  downloads: {
    name: 'App Downloads Standard',
    dims: ['Download Type', 'Source Type', 'Source Info', 'Device', 'Territory'],
    measures: ['Counts'],
  },
  discovery: {
    name: 'App Store Discovery and Engagement Standard',
    dims: ['Event', 'Source Type', 'Device', 'Territory'],
    measures: ['Counts'],
  },
  sessions: {
    name: 'App Sessions Standard',
    dims: ['Device', 'Territory'],
    measures: ['Sessions'],
  },
  installs: {
    name: 'App Store Installation and Deletion Standard',
    dims: ['Event', 'Device', 'Territory'],
    measures: ['Counts'],
  },
};

function emptyState() {
  return {
    v: 1,
    syncedAt: null,
    errors: [],
    sales: { rows: [], dates: {} },
    finance: { months: {} },
    analytics: { processed: {}, reports: {}, headers: {}, requests: 0 },
    store: { versions: [], submissions: [] },
    reviews: [],
    fx: null,
    traffic: { days: {}, sources: [] },
  };
}

// ---- dates ---------------------------------------------------------------

// Apple's report days run on Pacific time, so "yesterday" is Pacific too.
function pacificToday(now = new Date()) {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Los_Angeles', year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(now);
}

function addDays(iso, delta) {
  const d = new Date(`${iso}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + delta);
  return d.toISOString().slice(0, 10);
}

function usDate(text) {
  const m = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(String(text || '').trim());
  return m ? `${m[3]}-${m[1]}-${m[2]}` : null;
}

// ---- transport -----------------------------------------------------------

function ascToken() {
  const pem = String(process.env.ASC_PRIVATE_KEY || '').replace(/\\n/g, '\n');
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  const head = b64({ alg: 'ES256', kid: process.env.ASC_KEY_ID, typ: 'JWT' });
  const body = b64({ iss: process.env.ASC_ISSUER_ID, iat: now, exp: now + 1100, aud: 'appstoreconnect-v1' });
  const sig = crypto.sign('sha256', Buffer.from(`${head}.${body}`), { key: pem, dsaEncoding: 'ieee-p1363' });
  return `${head}.${body}.${sig.toString('base64url')}`;
}

function maybeGunzip(buf) {
  return buf[0] === 0x1f && buf[1] === 0x8b ? zlib.gunzipSync(buf) : buf;
}

async function asc(path, options = {}) {
  const url = path.startsWith('http') ? path : ASC + path;
  const res = await fetch(url, {
    ...options,
    headers: { authorization: `Bearer ${ascToken()}`, ...(options.headers || {}) },
    signal: AbortSignal.timeout(45000),
  });
  const buf = Buffer.from(await res.arrayBuffer());
  return { status: res.status, text: maybeGunzip(buf).toString('utf8') };
}

async function ascJson(path, options) {
  const r = await asc(path, options);
  if (r.status < 200 || r.status >= 300) {
    throw new Error(`${path.split('?')[0].replace(ASC, '')} ${r.status}`);
  }
  return JSON.parse(r.text);
}

async function ascAll(path) {
  const out = [];
  let next = path;
  while (next) {
    const page = await ascJson(next);
    out.push(...page.data);
    next = page.links && page.links.next;
  }
  return out;
}

function blobStoreId(token) {
  return String(token || '').split('_')[3] || '';
}

// Throws on any answer but found or truly absent: a failed read must never
// look like an empty store, or the next write would erase the history.
async function readState() {
  const token = process.env.BLOB_READ_WRITE_TOKEN;
  if (!token) throw new Error('BLOB_READ_WRITE_TOKEN missing');
  const url = `https://${blobStoreId(token)}.private.blob.vercel-storage.com/${STATE_PATH}?cache=0`;
  const res = await fetch(url, { headers: { authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(20000) });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`blob read ${res.status}`);
  return JSON.parse(maybeGunzip(Buffer.from(await res.arrayBuffer())).toString('utf8'));
}

async function writeState(state) {
  const token = process.env.BLOB_READ_WRITE_TOKEN;
  const res = await fetch(`https://vercel.com/api/blob/?pathname=${encodeURIComponent(STATE_PATH)}`, {
    method: 'PUT',
    headers: {
      authorization: `Bearer ${token}`,
      'x-api-version': '13',
      'x-vercel-blob-access': 'private',
      'x-add-random-suffix': '0',
      'x-allow-overwrite': '1',
      'x-content-type': 'application/gzip',
      'x-cache-control-max-age': '60',
    },
    body: zlib.gzipSync(JSON.stringify(state)),
    signal: AbortSignal.timeout(30000),
  });
  if (!res.ok) throw new Error(`blob write ${res.status}`);
}

async function pool(items, size, work) {
  let index = 0;
  await Promise.all(Array.from({ length: size }, async () => {
    while (index < items.length) {
      const item = items[index];
      index += 1;
      await work(item);
    }
  }));
}

// ---- parsing -------------------------------------------------------------

function parseTsv(text) {
  const lines = String(text || '').split(/\r?\n/).filter((l) => l.trim());
  if (!lines.length) return { header: [], rows: [] };
  const header = lines[0].split('\t').map((h) => h.trim());
  const rows = lines.slice(1).map((line) => {
    const cells = line.split('\t');
    const row = {};
    header.forEach((h, i) => { row[h] = (cells[i] || '').trim(); });
    return row;
  });
  return { header, rows };
}

// [date, type, units, proceeds, proceedsCurrency, price, currency, country, device, promo, version]
function requireColumns(parsed, columns, what) {
  const missing = columns.filter((c) => !parsed.header.includes(c));
  if (missing.length) throw new Error(`${what}缺字段 ${missing.join('、')}`);
}

const SALES_COLUMNS = ['Begin Date', 'Product Type Identifier', 'Units', 'Developer Proceeds', 'Currency of Proceeds', 'Customer Price', 'Customer Currency', 'Country Code', 'Device'];
const FINANCE_COLUMNS = ['Start Date', 'End Date', 'Quantity', 'Extended Partner Share', 'Partner Share Currency'];

function salesRowsFromReport(text) {
  const parsed = parseTsv(text);
  requireColumns(parsed, SALES_COLUMNS, '销售报表');
  return parsed.rows.map((r) => {
    const date = usDate(r['Begin Date']);
    if (!date) return null;
    return [
      date, r['Product Type Identifier'], Number(r.Units) || 0,
      Math.abs(Number(r['Developer Proceeds']) || 0), r['Currency of Proceeds'],
      Math.abs(Number(r['Customer Price']) || 0), r['Customer Currency'],
      r['Country Code'], r.Device, r['Promo Code'] || '', r.Version || '',
    ];
  }).filter(Boolean);
}

// A finance report ends in summary lines with no dates; only dated rows count.
function financeRowsFromReport(text) {
  const out = [];
  const parsed = parseTsv(text);
  requireColumns(parsed, FINANCE_COLUMNS, '财务报表');
  for (const r of parsed.rows) {
    const start = usDate(r['Start Date']);
    const end = usDate(r['End Date']);
    if (!start || !end) continue;
    out.push({
      start, end,
      quantity: Number(r.Quantity) || 0,
      amount: Number(r['Extended Partner Share']) || 0,
      currency: r['Partner Share Currency'],
      country: r['Country Of Sale'],
      type: r['Product Type Identifier'],
    });
  }
  return out;
}

function compactAnalyticsRows(spec, parsed) {
  const byDate = {};
  for (const row of parsed.rows) {
    const date = row.Date;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date || '')) continue;
    const entry = [
      ...spec.dims.map((d) => row[d] || ''),
      ...spec.measures.map((m) => Number(row[m]) || 0),
    ];
    (byDate[date] ||= []).push(entry);
  }
  return byDate;
}

// ---- sync ----------------------------------------------------------------

async function syncSales(state, vendor, today, errors) {
  const dates = state.sales.dates;
  const yesterday = addDays(today, -1);
  const wanted = [];
  for (let i = 0; i < FIRST_SALES_LOOKBACK_DAYS; i += 1) {
    const d = addDays(yesterday, -i);
    const seen = dates[d];
    if (seen === 'ok') continue;
    if (seen === 'none' && i >= RECHECK_EMPTY_DAYS) continue;
    wanted.push(d);
  }
  const fresh = {};
  let failed = 0;
  let badShape = null;
  await pool(wanted, 8, async (d) => {
    const q = `filter[frequency]=DAILY&filter[reportType]=SALES&filter[reportSubType]=SUMMARY&filter[version]=1_0&filter[vendorNumber]=${vendor}&filter[reportDate]=${d}`;
    let r;
    try {
      r = await asc(`/v1/salesReports?${q}`, { headers: { accept: 'application/a-gzip' } });
    } catch {
      failed += 1;
      return;
    }
    if (r.status === 200) {
      try {
        fresh[d] = salesRowsFromReport(r.text);
        dates[d] = 'ok';
      } catch (error) {
        failed += 1;
        badShape = error.message;
      }
    } else if (r.status === 404 || r.status === 410) {
      dates[d] = 'none';
    } else {
      failed += 1;
    }
  });
  const keep = state.sales.rows.filter((row) => !fresh[row[0]]);
  state.sales.rows = keep.concat(...Object.values(fresh)).sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));
  if (failed) errors.push(`销售报表有 ${failed} 天没取到，下次同步重试${badShape ? `：${badShape}` : ''}`);
}

// Apple's finance periods are fiscal: FY27 starts in October 2026, and
// reportDate 2026-09 means FY26 period 9, about June 2026.
function fiscalPeriods(today, firstFiscalYear = 2026) {
  const [y, m] = today.split('-').map(Number);
  const fy = m >= 10 ? y + 1 : y;
  const period = m >= 10 ? m - 9 : m + 3;
  const out = [];
  for (let year = firstFiscalYear; year <= fy; year += 1) {
    for (let p = 1; p <= (year === fy ? period : 12); p += 1) out.push(`${year}-${String(p).padStart(2, '0')}`);
  }
  return out;
}

async function syncFinance(state, vendor, today, errors) {
  const months = state.finance.months;
  const wanted = fiscalPeriods(today).filter((p) => !months[p]);
  await pool(wanted, 4, async (p) => {
    const q = `filter[reportType]=FINANCIAL&filter[regionCode]=ZZ&filter[reportDate]=${p}&filter[vendorNumber]=${vendor}`;
    const r = await asc(`/v1/financeReports?${q}`, { headers: { accept: 'application/a-gzip' } });
    if (r.status === 200) {
      const rows = financeRowsFromReport(r.text);
      if (rows.length) months[p] = rows;
    }
    else if (r.status !== 404 && r.status !== 410) errors.push(`财务报表 ${p} 返回 ${r.status}`);
  });
}

async function syncStore(state) {
  const fields = 'fields[appStoreVersions]=platform,versionString,appVersionState,createdDate';
  const versions = await ascJson(`/v1/apps/${APP_ID}/appStoreVersions?limit=20&${fields}`);
  state.store.versions = versions.data.map((v) => ({
    platform: v.attributes.platform,
    version: v.attributes.versionString,
    state: v.attributes.appVersionState,
    created: v.attributes.createdDate,
  }));
  const subs = await ascJson(`/v1/reviewSubmissions?filter[app]=${APP_ID}&limit=20&fields[reviewSubmissions]=platform,state,submittedDate`);
  state.store.submissions = subs.data.map((s) => ({
    platform: s.attributes.platform,
    state: s.attributes.state,
    submitted: s.attributes.submittedDate,
  }));
  const reviews = await ascJson(`/v1/apps/${APP_ID}/customerReviews?limit=50&sort=-createdDate`);
  state.reviews = reviews.data.map((r) => ({
    rating: r.attributes.rating,
    title: r.attributes.title,
    body: r.attributes.body,
    nickname: r.attributes.reviewerNickname,
    territory: r.attributes.territory,
    created: r.attributes.createdDate,
  }));
}

async function syncFx(state) {
  const res = await fetch('https://open.er-api.com/v6/latest/USD', { signal: AbortSignal.timeout(15000) });
  if (!res.ok) throw new Error(`fx ${res.status}`);
  const j = await res.json();
  if (j.result !== 'success' || !j.rates || !j.rates.CNY) throw new Error('fx bad body');
  state.fx = { base: 'USD', rates: j.rates, at: j.time_last_update_utc };
}

async function ensureOngoingRequest(requests) {
  const live = requests.some((r) => r.attributes.accessType === 'ONGOING' && !r.attributes.stoppedDueToInactivity);
  if (live) return requests;
  await ascJson('/v1/analyticsReportRequests', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ data: {
      type: 'analyticsReportRequests',
      attributes: { accessType: 'ONGOING' },
      relationships: { app: { data: { type: 'apps', id: APP_ID } } },
    } }),
  });
  return ascAll(`/v1/apps/${APP_ID}/analyticsReportRequests?limit=20`);
}

async function syncAnalytics(state, deadline) {
  const a = state.analytics;
  a.headers ||= {};
  let requests = await ascAll(`/v1/apps/${APP_ID}/analyticsReportRequests?limit=20`);
  requests = await ensureOngoingRequest(requests);
  a.requests = requests.length;

  const todo = [];
  await pool(requests, 2, async (request) => {
    for (const [key, spec] of Object.entries(ANALYTICS_REPORTS)) {
      const reports = await ascAll(`/v1/analyticsReportRequests/${request.id}/reports?filter[name]=${encodeURIComponent(spec.name)}&limit=5`);
      for (const report of reports) {
        const instances = await ascAll(`/v1/analyticsReports/${report.id}/instances?filter[granularity]=DAILY&limit=200`);
        for (const inst of instances) {
          if (!a.processed[inst.id]) todo.push({ key, spec, id: inst.id, date: inst.attributes.processingDate });
        }
      }
    }
  });

  // Oldest first, so where the snapshot and the ongoing request overlap the
  // newest processing of a day wins.
  todo.sort((x, y) => (x.date < y.date ? -1 : x.date > y.date ? 1 : 0));
  a.pending = 0;
  for (const item of todo) {
    if (Date.now() > deadline) {
      a.pending += 1;
      continue;
    }
    const segments = await ascAll(`/v1/analyticsReportInstances/${item.id}/segments?limit=50`);
    const merged = { header: [], rows: [] };
    for (const seg of segments) {
      const res = await fetch(seg.attributes.url, { signal: AbortSignal.timeout(45000) });
      if (!res.ok) throw new Error(`analytics segment ${res.status}`);
      const parsed = parseTsv(maybeGunzip(Buffer.from(await res.arrayBuffer())).toString('utf8'));
      merged.header = parsed.header;
      merged.rows.push(...parsed.rows);
    }
    // No segments yet can mean Apple is still writing this instance; only an
    // old one is really empty.
    if (!segments.length && item.date >= addDays(pacificToday(), -7)) continue;
    if (merged.header.length) {
      a.headers[item.key] = merged.header;
      requireColumns(merged, ['Date', ...item.spec.measures], item.spec.name);
    }
    const byDate = compactAnalyticsRows(item.spec, merged);
    a.reports[item.key] ||= {};
    Object.assign(a.reports[item.key], byDate);
    a.processed[item.id] = 1;
  }
}

async function googleToken() {
  const c = JSON.parse(process.env.MIAOYAN_GA_SERVICE_ACCOUNT_JSON);
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${b64({ alg: 'RS256', typ: 'JWT' })}.${b64({
    iss: c.client_email,
    scope: 'https://www.googleapis.com/auth/analytics.readonly',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3000,
  })}`;
  const assertion = `${unsigned}.${crypto.sign('RSA-SHA256', Buffer.from(unsigned), c.private_key).toString('base64url')}`;
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }),
    signal: AbortSignal.timeout(20000),
  });
  const j = await res.json();
  if (!j.access_token) throw new Error(`token ${res.status}`);
  return j.access_token;
}

function gaDate(raw) {
  return `${raw.slice(0, 4)}-${raw.slice(4, 6)}-${raw.slice(6, 8)}`;
}

// The whole history each time: GA restates recent days, and a day this site
// had no visits is simply absent, which the page reads as zero.
async function syncTraffic(state, today) {
  const property = process.env.MIAOYAN_GA_PROPERTY_ID;
  const token = await googleToken();
  const run = async (startDate, endDate, body) => {
    const res = await fetch(`https://analyticsdata.googleapis.com/v1beta/properties/${property}:runReport`, {
      method: 'POST',
      headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: JSON.stringify({ dateRanges: [{ startDate, endDate }], limit: 100000, ...body }),
      signal: AbortSignal.timeout(60000),
    });
    if (!res.ok) throw new Error(`ga ${res.status}`);
    return (await res.json()).rows || [];
  };
  // Sources stay daily for a year, which every preset and month needs; older
  // ones fold into one row dated at the start, so "all" still counts them.
  const yearAgo = addDays(today, -365);
  const [daily, recentSources, olderSources] = await Promise.all([
    run(TRAFFIC_START, today, {
      dimensions: [{ name: 'date' }],
      metrics: [{ name: 'sessions' }, { name: 'activeUsers' }, { name: 'screenPageViews' }],
    }),
    run(yearAgo, today, {
      dimensions: [{ name: 'date' }, { name: 'sessionSource' }],
      metrics: [{ name: 'sessions' }],
    }),
    run(TRAFFIC_START, addDays(yearAgo, -1), {
      dimensions: [{ name: 'sessionSource' }],
      metrics: [{ name: 'sessions' }],
    }),
  ]);
  state.traffic = {
    days: Object.fromEntries(daily.map((r) => [gaDate(r.dimensionValues[0].value), r.metricValues.map((m) => Number(m.value) || 0)])),
    sources: [
      ...olderSources.map((r) => [TRAFFIC_START, r.dimensionValues[0].value, Number(r.metricValues[0].value) || 0]),
      ...recentSources.map((r) => [gaDate(r.dimensionValues[0].value), r.dimensionValues[1].value, Number(r.metricValues[0].value) || 0]),
    ],
  };
}

// Each part keeps its last good data when it fails; only the failed part's
// error reaches the page.
async function runSync({ budgetMs = 200000, now = new Date() } = {}) {
  const deadline = Date.now() + budgetMs;
  const vendor = process.env.ASC_VENDOR_NUMBER;
  if (!vendor) throw new Error('ASC_VENDOR_NUMBER missing');
  const stored = await readState();
  const state = stored || emptyState();
  const today = pacificToday(now);
  const errors = [];
  const part = async (label, work) => {
    try {
      await work();
    } catch (error) {
      errors.push(`${label}没同步成功：${error.message}`);
    }
  };
  await part('销售报表', () => syncSales(state, vendor, today, errors));
  await part('财务报表', () => syncFinance(state, vendor, today, errors));
  await part('上架状态和评论', () => syncStore(state));
  await part('汇率', () => syncFx(state));
  await part('官网流量', () => syncTraffic(state, today));
  // A first run that got nothing must not create the store: a read that wrongly
  // answered "absent" would otherwise replace the history with an empty one.
  if (!stored && !state.sales.rows.length) {
    throw new Error(`第一次同步没有拿到销售数据：${errors.join('；') || '报表为空'}`);
  }
  state.errors = errors;
  state.syncedAt = now.toISOString();
  // Saved before the channel reports, whose downloads are the slow part: a run
  // killed there keeps the sales it already has.
  await writeState(state);
  await part('渠道报告', () => syncAnalytics(state, deadline));
  state.errors = errors;
  await writeState(state);
  return {
    syncedAt: state.syncedAt,
    errors,
    salesRows: state.sales.rows.length,
    analyticsDays: Object.fromEntries(Object.entries(state.analytics.reports).map(([k, v]) => [k, Object.keys(v).length])),
    analyticsPending: state.analytics.pending || 0,
  };
}

// ---- aggregation ---------------------------------------------------------

function kindOf(type, price) {
  const t = String(type || '');
  if (t === 'F3' || t.startsWith('3')) return 'redownload';
  if (t === 'F7' || t.startsWith('7')) return 'update';
  if (t === 'F1' || t === '1' || t === '1F' || t === '1T') return price > 0 ? 'sale' : 'free';
  return 'other';
}

function deviceLabel(device) {
  return device === 'Desktop' ? 'Mac' : device;
}

function converter(fx, currency) {
  return (amount, from) => {
    if (from === currency) return amount;
    const a = fx && fx.rates && fx.rates[from];
    const b = fx && fx.rates && fx.rates[currency];
    return a && b ? (amount / a) * b : null;
  };
}

function rangeBounds(range, today, firstDate) {
  const to = addDays(today, -1);
  const preset = /^(\d+)d$/.exec(range);
  if (preset) return { from: addDays(to, -(Number(preset[1]) - 1)), to };
  const month = /^m:(\d{4}-\d{2})$/.exec(range);
  if (month) {
    const [y, m] = month[1].split('-').map(Number);
    const last = new Date(Date.UTC(y, m, 0)).toISOString().slice(0, 10);
    return { from: `${month[1]}-01`, to: last < to ? last : to };
  }
  return { from: firstDate || to, to };
}

function sumByKey(map, key, patch) {
  const entry = map.get(key) || {};
  for (const [k, v] of Object.entries(patch)) entry[k] = (entry[k] || 0) + v;
  map.set(key, entry);
}

function analyticsIn(report, from, to) {
  const out = [];
  for (const [date, rows] of Object.entries(report || {})) {
    if (date >= from && date <= to) out.push(...rows);
  }
  return out;
}

function analyticsCoverage(report) {
  const days = Object.keys(report || {}).sort();
  return days.length ? { from: days[0], to: days[days.length - 1], days: days.length } : null;
}

function buildAnalytics(state, from, to, convertUsd) {
  const reports = (state.analytics && state.analytics.reports) || {};
  const sources = new Map();
  const details = new Map();
  for (const [type, info, , , purchases, proceedsUsd, salesUsd] of analyticsIn(reports.purchases, from, to)) {
    sumByKey(sources, type || 'Unavailable', { purchases, proceeds: convertUsd(proceedsUsd) || 0, sales: convertUsd(salesUsd) || 0 });
    if (info) sumByKey(details, `${type}\u0000${info}`, { purchases });
  }
  let firstDownloads = 0;
  for (const [kind, type, info, , , counts] of analyticsIn(reports.downloads, from, to)) {
    if (!/first/i.test(kind)) continue;
    firstDownloads += counts;
    sumByKey(sources, type || 'Unavailable', { downloads: counts });
    if (info) sumByKey(details, `${type}\u0000${info}`, { downloads: counts });
  }
  let impressions = 0;
  let pageViews = 0;
  for (const [event, type, , , counts] of analyticsIn(reports.discovery, from, to)) {
    if (/impression/i.test(event)) {
      impressions += counts;
      sumByKey(sources, type || 'Unavailable', { impressions: counts });
    } else if (/page view/i.test(event)) {
      pageViews += counts;
      sumByKey(sources, type || 'Unavailable', { pageViews: counts });
    }
  }
  let installs = 0;
  let deletions = 0;
  for (const [event, , , counts] of analyticsIn(reports.installs, from, to)) {
    if (/install/i.test(event)) installs += counts;
    else if (/delet/i.test(event)) deletions += counts;
  }
  let sessions = 0;
  for (const [, , count] of analyticsIn(reports.sessions, from, to)) sessions += count;

  const purchases = [...sources.values()].reduce((n, s) => n + (s.purchases || 0), 0);
  return {
    available: Object.keys(reports).some((k) => Object.keys(reports[k]).length),
    coverage: analyticsCoverage(reports.downloads || reports.purchases || reports.discovery),
    pending: (state.analytics && state.analytics.pending) || 0,
    sources: [...sources.entries()]
      .map(([type, v]) => ({ type, purchases: 0, downloads: 0, impressions: 0, pageViews: 0, proceeds: 0, ...v }))
      .sort((a, b) => b.purchases - a.purchases || b.downloads - a.downloads || b.pageViews - a.pageViews),
    details: [...details.entries()]
      .map(([key, v]) => {
        const [type, info] = key.split('\u0000');
        return { type, info, purchases: 0, downloads: 0, ...v };
      })
      .sort((a, b) => b.purchases - a.purchases || b.downloads - a.downloads)
      .slice(0, 12),
    funnel: { impressions, pageViews, firstDownloads, purchases },
    usage: { installs, deletions, sessions },
  };
}

function buildTraffic(state, from, to) {
  const t = state.traffic || { days: {}, sources: [] };
  let sessions = 0;
  let views = 0;
  for (const [date, [s, , v]] of Object.entries(t.days)) {
    if (date >= from && date <= to) {
      sessions += s;
      views += v;
    }
  }
  const sources = new Map();
  for (const [date, source, count] of t.sources) {
    if (date >= from && date <= to) sources.set(source, (sources.get(source) || 0) + count);
  }
  return {
    available: Object.keys(t.days).length > 0,
    latest: Object.keys(t.days).sort().pop() || null,
    sessions,
    views,
    sources: [...sources.entries()].sort((a, b) => b[1] - a[1]).slice(0, 10).map(([source, count]) => ({ source, count })),
  };
}

// The newest days regardless of the chosen range: "did money come in today".
// A day past Apple's newest report is unknown, not zero.
function buildRecent(state, convert, today, latestSalesDate) {
  const byDay = new Map();
  for (const [date, type, units, proceeds, proceedsCur, price] of state.sales.rows) {
    if (kindOf(type, price) !== 'sale') continue;
    const net = convert(proceeds, proceedsCur);
    const patch = { proceeds: (net || 0) * units };
    if (units > 0) patch.sold = units; else patch.refunded = -units;
    sumByKey(byDay, date, patch);
  }
  const days = (state.traffic && state.traffic.days) || {};
  const latestVisit = Object.keys(days).sort().pop() || '';
  const out = [];
  for (let i = 0; i < RECENT_DAYS; i += 1) {
    const date = addDays(today, -1 - i);
    const known = Boolean(latestSalesDate) && date <= latestSalesDate && Boolean(state.sales.dates[date]);
    const v = byDay.get(date) || {};
    out.push({
      date, known,
      sold: v.sold || 0, refunded: v.refunded || 0, proceeds: v.proceeds || 0,
      sessions: date > latestVisit ? null : (days[date] ? days[date][0] : 0),
    });
  }
  return out;
}

// GA reports a day late at most, so a longer silence means counting stopped.
function isTrafficStale(state, today) {
  const latest = Object.keys((state.traffic && state.traffic.days) || {}).sort().pop();
  return Boolean(latest) && latest < addDays(today, -3) ? latest : null;
}

function latestIncome(state, convert) {
  const rows = state.sales.rows.filter((r) => kindOf(r[1], r[5]) === 'sale');
  const sales = rows.filter((r) => r[2] > 0);
  if (!sales.length) return null;
  const date = sales[sales.length - 1][0];
  let units = 0;
  let proceeds = 0;
  for (const r of rows) {
    if (r[0] !== date) continue;
    if (r[2] > 0) units += r[2];
    proceeds += (convert(r[3], r[4]) || 0) * r[2];
  }
  return { date, units, proceeds };
}

function buildView(state, { range = 'all', currency = 'CNY', today = pacificToday() } = {}) {
  const allRows = state.sales.rows;
  const firstDate = allRows[0] && allRows[0][0];
  const { from, to } = rangeBounds(range, today, firstDate);
  const convert = converter(state.fx, currency);

  const totals = { sold: 0, refunded: 0, gross: 0, refundAmount: 0, proceeds: 0, free: 0, redownload: 0, update: 0, unconverted: 0 };
  const devices = new Map();
  const countries = new Map();
  const series = new Map();
  const refunds = [];

  for (const [date, type, units, proceeds, proceedsCur, price, cur, country, device, , version] of allRows) {
    if (date < from || date > to) continue;
    const kind = kindOf(type, price);
    if (kind === 'free') { totals.free += units; continue; }
    if (kind === 'redownload') { totals.redownload += units; continue; }
    if (kind === 'update') { totals.update += units; continue; }
    if (kind !== 'sale') continue;

    const price1 = convert(price, cur);
    const proceeds1 = convert(proceeds, proceedsCur);
    if (price1 === null || proceeds1 === null) { totals.unconverted += Math.abs(units); }
    const amount = (price1 || 0) * Math.abs(units);
    const net = (proceeds1 || 0) * units;
    const label = deviceLabel(device);
    const bucket = date;
    totals.proceeds += net;
    if (units > 0) {
      totals.sold += units;
      totals.gross += amount;
      sumByKey(devices, label, { sold: units, gross: amount, proceeds: net });
      sumByKey(countries, country, { sold: units, gross: amount, proceeds: net });
      sumByKey(series, bucket, { sold: units, proceeds: net });
    } else if (units < 0) {
      const n = -units;
      totals.refunded += n;
      totals.refundAmount += amount;
      sumByKey(devices, label, { refunded: n, gross: -amount, proceeds: net });
      sumByKey(countries, country, { refunded: n, gross: -amount, proceeds: net });
      sumByKey(series, bucket, { refunded: n, proceeds: net });
      refunds.push({ date, country, device: label, version, units: n, amount, currency: cur, price });
    }
  }

  const span = (Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / 864e5;
  const byMonth = span > 92;
  const points = new Map();
  if (byMonth) {
    for (const [d, v] of series) sumByKey(points, d.slice(0, 7), v);
    for (let m = from.slice(0, 7); m <= to.slice(0, 7);) {
      if (!points.has(m)) points.set(m, {});
      const [y, mm] = m.split('-').map(Number);
      m = new Date(Date.UTC(y, mm, 1)).toISOString().slice(0, 7);
    }
  } else {
    for (let d = from; d <= to; d = addDays(d, 1)) points.set(d, series.get(d) || {});
  }

  const toList = (map) => [...map.entries()]
    .map(([key, v]) => ({ key, sold: 0, refunded: 0, gross: 0, proceeds: 0, ...v }))
    .sort((a, b) => b.sold - a.sold || b.proceeds - a.proceeds);

  const convertUsd = (v) => convert(v, 'USD');
  const latestSalesDate = Object.keys(state.sales.dates).filter((d) => state.sales.dates[d] === 'ok').sort().pop() || null;
  return {
    range, currency, from, to,
    totals: {
      ...totals,
      net: totals.gross - totals.refundAmount,
      netUnits: totals.sold - totals.refunded,
      refundRate: totals.sold ? totals.refunded / totals.sold : null,
    },
    byMonth,
    series: [...points.entries()].sort().map(([key, v]) => ({ key, sold: v.sold || 0, refunded: v.refunded || 0, proceeds: v.proceeds || 0 })),
    devices: toList(devices),
    countries: toList(countries),
    refunds: refunds.sort((a, b) => (a.date < b.date ? 1 : -1)),
    analytics: buildAnalytics(state, from, to, convertUsd),
    traffic: buildTraffic(state, range === 'all' ? TRAFFIC_START : from, to),
    recent: buildRecent(state, convert, today, latestSalesDate),
    latest: latestIncome(state, convert),
    months: monthOptions(allRows, today),
    finance: buildFinance(state, convert),
    store: buildStore(state),
    reviews: state.reviews || [],
    syncedAt: state.syncedAt,
    errors: state.errors || [],
    trafficStale: isTrafficStale(state, today),
    fxAt: state.fx && state.fx.at,
    usdCny: state.fx && state.fx.rates ? state.fx.rates.CNY : null,
    syncStale: Boolean(state.syncedAt) && Date.now() - Date.parse(state.syncedAt) > SYNC_STALE_MS,
    latestSalesDate,
  };
}

function monthOptions(rows, today) {
  const paid = rows.filter((r) => kindOf(r[1], r[5]) === 'sale');
  if (!paid.length) return [];
  const out = [];
  let m = paid[0][0].slice(0, 7);
  const last = today.slice(0, 7);
  while (m <= last) {
    out.unshift(m);
    const [y, mm] = m.split('-').map(Number);
    m = new Date(Date.UTC(y, mm, 1)).toISOString().slice(0, 7);
  }
  return out;
}

function buildFinance(state, convert) {
  const out = [];
  for (const [period, rows] of Object.entries(state.finance.months || {})) {
    if (!rows.length) continue;
    let units = 0;
    let amount = 0;
    let unconverted = false;
    for (const r of rows) {
      units += r.quantity;
      const c = convert(r.amount, r.currency);
      if (c === null) unconverted = true;
      else amount += c;
    }
    out.push({ period, start: rows[0].start, end: rows[0].end, units, amount, unconverted });
  }
  return out.sort((a, b) => (a.start < b.start ? 1 : -1));
}

function buildStore(state) {
  const out = [];
  for (const platform of ['MAC_OS', 'IOS']) {
    const v = (state.store.versions || []).find((x) => x.platform === platform);
    if (!v) continue;
    const sub = (state.store.submissions || []).find((s) => s.platform === platform && s.state !== 'COMPLETE');
    out.push({ ...v, submitted: sub ? sub.submitted : null });
  }
  return out;
}

module.exports = {
  APP_ID,
  ANALYTICS_REPORTS,
  addDays,
  buildView,
  compactAnalyticsRows,
  emptyState,
  financeRowsFromReport,
  fiscalPeriods,
  kindOf,
  pacificToday,
  parseTsv,
  rangeBounds,
  readState,
  runSync,
  salesRowsFromReport,
};
