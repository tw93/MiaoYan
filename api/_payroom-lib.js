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
const HOUR = 3600 * 1000;
const SYNC_STALE_MS = 3 * HOUR;
// The cron runs hourly. `every` spaces out parts whose source changes slowly;
// `stale` is how old a part's last success may get before its failure reaches
// the page, so one slow answer that the next run repairs stays quiet.
const PARTS = {
  sales: { label: '销售报表', every: 0, stale: 3 * HOUR },
  finance: { label: '财务报表', every: 24 * HOUR, stale: 72 * HOUR },
  store: { label: '上架状态和评论', every: 0, stale: 6 * HOUR },
  fx: { label: '汇率', every: 6 * HOUR, stale: 48 * HOUR },
  traffic: { label: '官网流量', every: 0, stale: 6 * HOUR },
  analytics: { label: '渠道报告', every: 0, stale: 24 * HOUR },
  // Search Console never fails the page: a read that does not land keeps the
  // last panel (or none) and is kept in state.search.error, not in the warnings.
  search: { label: '搜索表现', every: 6 * HOUR, stale: 48 * HOUR },
};
// GA restates its last few days, so each run replaces those; the whole history
// is pulled once a day, since that query is the one that timed out.
const TRAFFIC_RECENT_DAYS = 4;
const TRAFFIC_FULL_EVERY = 20 * HOUR;

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

async function syncSales(state, vendor, today, errors, now = new Date(), { onlyYesterday = false } = {}) {
  const dates = state.sales.dates;
  const seenAt = (state.sales.seenAt ||= {});
  const yesterday = addDays(today, -1);
  const wanted = [];
  for (let i = 0; i < (onlyYesterday ? 1 : FIRST_SALES_LOOKBACK_DAYS); i += 1) {
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
        // When Apple's report for a day first answered, to learn its hour.
        seenAt[d] ||= now.toISOString();
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
  if (failed) errors.push(`有 ${failed} 天没取到${badShape ? `，${badShape}` : ''}`);
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
    else if (r.status !== 404 && r.status !== 410) errors.push(`${p} 返回 ${r.status}`);
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
    // One token serves GA and Search Console; the service account holds read
    // access on both, so asking for both scopes here is all the grant needs.
    scope: 'https://www.googleapis.com/auth/analytics.readonly https://www.googleapis.com/auth/webmasters.readonly',
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
// The GA property also receives other sites and local builds that copied this
// measurement ID, and the old /cats pages; only the product's own pages count.
const SITE_ONLY = {
  andGroup: {
    expressions: [
      { filter: { fieldName: 'hostName', stringFilter: { matchType: 'EXACT', value: 'miaoyan.app' } } },
      { notExpression: { filter: { fieldName: 'pagePath', stringFilter: { matchType: 'BEGINS_WITH', value: '/cats' } } } },
    ],
  },
};

// Each day is [sessions, activeUsers, screenPageViews, newUsers].
const DAILY_QUERY = {
  dimensions: [{ name: 'date' }],
  metrics: [{ name: 'sessions' }, { name: 'activeUsers' }, { name: 'screenPageViews' }, { name: 'newUsers' }],
};
// Breakdowns kept per day, read the way Mole's 访客来源 panel reads them:
// sessions by source, country and channel, and App Store link clicks
// (`store_click`, sent by the site since 2026-11-09) by source.
const TRAFFIC_VERSION = 2;
const STORE_CLICK_SINCE = '2026-11-09';
const BREAKDOWNS = {
  sources: { dim: 'sessionSource', metric: 'sessions' },
  countries: { dim: 'countryId', metric: 'sessions' },
  channels: { dim: 'sessionDefaultChannelGroup', metric: 'sessions' },
  clicks: { dim: 'sessionSource', metric: 'eventCount', event: 'store_click', since: STORE_CLICK_SINCE },
};
const breakdownQuery = (b, withDate = true) => ({
  dimensions: [...(withDate ? [{ name: 'date' }] : []), { name: b.dim }],
  metrics: [{ name: b.metric }],
  ...(b.event ? { dimensionFilter: { andGroup: { expressions: [SITE_ONLY, { filter: { fieldName: 'eventName', stringFilter: { matchType: 'EXACT', value: b.event } } }] } } } : {}),
});
const dayRows = (rows) => rows.map((r) => [gaDate(r.dimensionValues[0].value), r.metricValues.map((m) => Number(m.value) || 0)]);
const sourceRows = (rows) => rows.map((r) => [gaDate(r.dimensionValues[0].value), r.dimensionValues[1].value, Number(r.metricValues[0].value) || 0]);

// endDate 'today' is GA's own today in the property's time zone, which runs
// ahead of Pacific, so the newest visits are not cut off.
async function syncTraffic(state, today, problems, now = new Date()) {
  const property = process.env.MIAOYAN_GA_PROPERTY_ID;
  const token = await googleToken();
  // Pages through a report GA cut at its row limit, so a long daily
  // breakdown is never silently short.
  const run = async (startDate, endDate, body) => {
    const rows = [];
    for (;;) {
      const res = await fetch(`https://analyticsdata.googleapis.com/v1beta/properties/${property}:runReport`, {
        method: 'POST',
        headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
        body: JSON.stringify({ dateRanges: [{ startDate, endDate }], limit: 100000, offset: rows.length, dimensionFilter: SITE_ONLY, ...body }),
        signal: AbortSignal.timeout(60000),
      });
      if (!res.ok) throw new Error(`ga ${res.status}`);
      const json = await res.json();
      const got = json.rows || [];
      rows.push(...got);
      if (!got.length || rows.length >= (json.rowCount || 0)) return rows;
    }
  };
  const old = state.traffic || {};
  const fullAt = old.fullAt ? Date.parse(old.fullAt) : 0;
  // A snapshot written before a breakdown existed is pulled whole at once.
  if (now.getTime() - fullAt >= TRAFFIC_FULL_EVERY || old.v !== TRAFFIC_VERSION) {
    try {
      // Breakdowns stay daily for a year, which every preset and month needs;
      // older ones fold into one row dated at the start, so "all" counts them.
      const yearAgo = addDays(today, -365);
      const keys = Object.keys(BREAKDOWNS);
      const [daily, ...parts] = await Promise.all([
        run(TRAFFIC_START, 'today', DAILY_QUERY),
        ...keys.flatMap((k) => {
          const b = BREAKDOWNS[k];
          const start = b.since && b.since > yearAgo ? b.since : yearAgo;
          const older = b.since && b.since >= yearAgo ? Promise.resolve([]) : run(TRAFFIC_START, addDays(yearAgo, -1), breakdownQuery(b, false));
          return [run(start, 'today', breakdownQuery(b)), older];
        }),
      ]);
      state.traffic = { v: TRAFFIC_VERSION, fullAt: now.toISOString(), days: Object.fromEntries(dayRows(daily)) };
      keys.forEach((k, i) => {
        const [recent, older] = [parts[i * 2], parts[i * 2 + 1]];
        state.traffic[k] = [
          ...older.map((r) => [TRAFFIC_START, r.dimensionValues[0].value, Number(r.metricValues[0].value) || 0]),
          ...sourceRows(recent),
        ];
      });
      return;
    } catch (error) {
      // Without any history there is nothing to patch; otherwise the recent
      // days below keep the page current and the full pull retries next hour.
      if (!old.days || !Object.keys(old.days).length) throw error;
      if (now.getTime() - fullAt > 3 * 24 * HOUR) problems.push(`整段历史三天没刷新成功，${error.message}`);
    }
  }
  const from = addDays(today, -(TRAFFIC_RECENT_DAYS - 1));
  const keys = Object.keys(BREAKDOWNS);
  // Visits per day must land; a breakdown that fails keeps its old rows.
  const [daily, ...parts] = await Promise.all([
    run(from, 'today', DAILY_QUERY),
    ...keys.map((k) => run(from, 'today', breakdownQuery(BREAKDOWNS[k])).catch((error) => ({ error }))),
  ]);
  // A day inside the window that GA no longer lists had no visits.
  const days = Object.fromEntries(Object.entries(old.days || {}).filter(([d]) => d < from));
  for (const [d, v] of dayRows(daily)) days[d] = v;
  // The version is kept as found: a snapshot still missing the older
  // breakdowns stays marked so the next hour pulls it whole.
  state.traffic = { v: old.v, fullAt: old.fullAt || null, days };
  keys.forEach((k, i) => {
    if (parts[i].error) {
      state.traffic[k] = old[k] || [];
      if (now.getTime() - fullAt > 3 * 24 * HOUR) problems.push(`${k} 没刷新成功，${parts[i].error.message}`);
      return;
    }
    state.traffic[k] = [...(old[k] || []).filter(([d]) => d < from), ...sourceRows(parts[i])];
  });
}

// ---- search performance (Search Console) -----------------------------------
// Mirrors Mole's 搜索表现: two windows (近 7 天, 近 30 天) with totals against
// the window before, the top queries, and the top pages over 28 days. Search
// Console trails by about three days, so every window ends three days back.
// Failure is soft: a window that does not land keeps its last good copy marked
// stale, and with nothing to keep the panel is simply absent.
const SEARCH_SITE = process.env.MIAOYAN_SEARCH_CONSOLE_SITE || 'sc-domain:miaoyan.app';
const SEARCH_LAG_DAYS = 3;
const SEARCH_WINDOWS = [{ key: 'd7', days: 7 }, { key: 'd30', days: 30 }];
const SEARCH_PAGE_DAYS = 28;
const SEARCH_QUERY_LIMIT = 1000;
const SEARCH_KEEP_QUERIES = 25;
const SEARCH_KEEP_PAGES = 30;

function searchRange(today, days, back = 0) {
  const to = addDays(today, -SEARCH_LAG_DAYS - back * days);
  return { from: addDays(to, -(days - 1)), to };
}

function searchPath(raw) {
  try {
    const u = new URL(String(raw));
    if (u.protocol !== 'http:' && u.protocol !== 'https:') return String(raw);
    return `${u.pathname || '/'}${u.search || ''}`;
  } catch {
    return String(raw || '');
  }
}

const searchNumbers = (r) => ({
  clicks: Math.max(0, Number(r.clicks) || 0),
  impressions: Math.max(0, Number(r.impressions) || 0),
  ctr: Number.isFinite(Number(r.ctr)) ? Number(r.ctr) : null,
  position: Number.isFinite(Number(r.position)) ? Number(r.position) : null,
});

async function searchQuery(token, range, dimension, rowLimit) {
  const res = await fetch(`https://searchconsole.googleapis.com/webmasters/v3/sites/${encodeURIComponent(SEARCH_SITE)}/searchAnalytics/query`, {
    method: 'POST',
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: JSON.stringify({ startDate: range.from, endDate: range.to, dimensions: dimension ? [dimension] : [], rowLimit, dataState: 'final' }),
    signal: AbortSignal.timeout(30000),
  });
  if (!res.ok) throw new Error(`search ${res.status}`);
  const json = await res.json();
  return Array.isArray(json.rows) ? json.rows : [];
}

async function loadSearchWindow(token, today, spec) {
  const cur = searchRange(today, spec.days);
  const prev = searchRange(today, spec.days, 1);
  const [queryRows, curTotal, prevTotal] = await Promise.all([
    searchQuery(token, cur, 'query', SEARCH_QUERY_LIMIT),
    searchQuery(token, cur, null, 1),
    searchQuery(token, prev, null, 1),
  ]);
  const queries = queryRows
    .map((r) => ({ query: String(r.keys?.[0] ?? ''), ...searchNumbers(r) }))
    .filter((r) => r.query && r.impressions > 0);
  const totals = curTotal[0] ? searchNumbers(curTotal[0]) : null;
  return {
    known: totals !== null || queries.length > 0,
    days: spec.days,
    from: cur.from,
    to: cur.to,
    previousFrom: prev.from,
    previousTo: prev.to,
    totals,
    previousTotals: prevTotal[0] ? searchNumbers(prevTotal[0]) : null,
    keywordCount: queries.length,
    keywordCapped: queryRows.length >= SEARCH_QUERY_LIMIT,
    queries: queries.sort((a, b) => b.clicks - a.clicks || b.impressions - a.impressions).slice(0, SEARCH_KEEP_QUERIES),
    stale: false,
    syncedAt: new Date().toISOString(),
  };
}

async function syncSearch(state, today, now = new Date()) {
  const old = state.search && state.search.v === 1 ? state.search : null;
  const next = { v: 1, site: SEARCH_SITE, windows: {}, pages: old ? old.pages || null : null, error: null, syncedAt: old ? old.syncedAt || null : null };
  const keep = (key, error) => {
    const was = old && old.windows && old.windows[key];
    if (was && was.known) next.windows[key] = { ...was, stale: true };
    next.error = error;
  };
  try {
    if (!process.env.MIAOYAN_GA_SERVICE_ACCOUNT_JSON) throw new Error('no credentials');
    const token = await googleToken();
    for (const spec of SEARCH_WINDOWS) {
      try {
        const win = await loadSearchWindow(token, today, spec);
        if (win.known) next.windows[spec.key] = win;
        else keep(spec.key, 'empty');
      } catch (error) {
        keep(spec.key, error.message);
      }
    }
    try {
      const range = searchRange(today, SEARCH_PAGE_DAYS);
      const rows = await searchQuery(token, range, 'page', 500);
      const pages = rows
        .map((r) => ({ page: searchPath(r.keys?.[0]), ...searchNumbers(r) }))
        .filter((r) => r.impressions > 0)
        .sort((a, b) => b.clicks - a.clicks || b.impressions - a.impressions);
      if (pages.length) {
        next.pages = { from: range.from, to: range.to, count: pages.length, rows: pages.slice(0, SEARCH_KEEP_PAGES), stale: false };
      } else if (next.pages) {
        next.pages = { ...next.pages, stale: true };
      }
    } catch (error) {
      if (next.pages) next.pages = { ...next.pages, stale: true };
      next.error = next.error || error.message;
    }
    if (!next.error) next.syncedAt = now.toISOString();
  } catch (error) {
    for (const spec of SEARCH_WINDOWS) keep(spec.key, error.message);
    if (next.pages) next.pages = { ...next.pages, stale: true };
  }
  state.search = next;
}

function buildSearch(state) {
  const s = state.search;
  if (!s || s.v !== 1) return null;
  const labels = { d7: '近 7 天', d30: '近 30 天' };
  const windows = SEARCH_WINDOWS
    .map(({ key }) => ({ key, label: labels[key], win: s.windows && s.windows[key] }))
    .filter(({ win }) => win && win.known && (win.totals || (win.queries && win.queries.length)))
    .map(({ key, label, win }) => ({ key, label, ...win, queries: win.queries || [] }));
  const pages = s.pages && Array.isArray(s.pages.rows) && s.pages.rows.length ? s.pages : null;
  // Nothing readable means nothing to draw, never a card of zeros.
  if (!windows.length) return null;
  return { windows, pages, partial: Boolean(s.error) };
}

// Each part keeps its last good data when it fails; only the failed part's
// error reaches the page.
// The quick run fires every ten minutes around the hour Apple publishes the
// previous Pacific day (11:00 to 16:50 UTC, about 3 to 9 a.m. Pacific in either offset; reports measured landing 5 to 7 a.m.), asks for
// that one report only, and writes only when it arrived, so the day shows up
// within minutes instead of at the next hourly run. Everything else stays on
// the hourly run.
async function quickSales({ now = new Date() } = {}) {
  const vendor = process.env.ASC_VENDOR_NUMBER;
  if (!vendor) throw new Error('ASC_VENDOR_NUMBER missing');
  const stored = await readState();
  if (!stored) return { quick: 'no store yet' };
  const today = pacificToday(now);
  const yesterday = addDays(today, -1);
  if (stored.sales.dates[yesterday] === 'ok') return { quick: `${yesterday} already in` };
  const problems = [];
  await syncSales(stored, vendor, today, problems, now, { onlyYesterday: true });
  if (stored.sales.dates[yesterday] !== 'ok') return { quick: `${yesterday} not out yet`, problems };
  ((stored.health ||= {}).sales ||= {}).ok = now.toISOString();
  await writeState(stored);
  return { quick: `${yesterday} landed` };
}

async function runSync({ budgetMs = 200000, now = new Date() } = {}) {
  const deadline = Date.now() + budgetMs;
  const vendor = process.env.ASC_VENDOR_NUMBER;
  if (!vendor) throw new Error('ASC_VENDOR_NUMBER missing');
  const stored = await readState();
  const state = stored || emptyState();
  const today = pacificToday(now);
  const errors = [];
  const health = (state.health ||= {});
  // Each part keeps when it last succeeded. A part not due yet is skipped; a
  // failure reaches the page only once that success is older than `stale`.
  const part = async (key, work) => {
    const { label, every, stale } = PARTS[key];
    const h = (health[key] ||= {});
    const last = h.ok ? Date.parse(h.ok) : 0;
    if (every && now.getTime() - last < every) return;
    const problems = [];
    try {
      await work(problems);
    } catch (error) {
      problems.push(error.message);
    }
    if (!problems.length) {
      h.ok = now.toISOString();
      delete h.error;
      return;
    }
    h.error = problems.join('；');
    if (!last || now.getTime() - last > stale) errors.push(`${label}没同步成功：${h.error}`);
  };
  await part('sales', (p) => syncSales(state, vendor, today, p, now));
  await part('finance', (p) => syncFinance(state, vendor, today, p));
  await part('store', () => syncStore(state));
  await part('fx', () => syncFx(state));
  await part('traffic', (p) => syncTraffic(state, today, p, now));
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
  // Search Console runs after the first save, so a slow answer never costs the
  // sales; a run already past its budget leaves it for the next one.
  if (Date.now() < deadline) {
    await part('search', () => syncSearch(state, today, now));
    // A soft failure is not a success: drop the stamp so the next hourly run asks again.
    if (state.search && state.search.error && health.search) delete health.search.ok;
  }
  await part('analytics', () => syncAnalytics(state, deadline));
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
  // 当月 runs to yesterday, so on the 1st it is the month just ended.
  if (range === 'month') return { from: `${to.slice(0, 7)}-01`, to };
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
  // Standard reports carry no Source Info column (checked on the first real
  // instances, 2026-11-11), so its slot stays empty and only types are summed.
  // Per territory, for the country table's 产品页浏览 and 购买/浏览.
  const territories = new Map();
  for (const [type, , , territory, purchases, proceedsUsd, salesUsd] of analyticsIn(reports.purchases, from, to)) {
    sumByKey(sources, type || 'Unavailable', { purchases, proceeds: convertUsd(proceedsUsd) || 0, sales: convertUsd(salesUsd) || 0 });
    if (territory) sumByKey(territories, territory, { purchases });
  }
  let firstDownloads = 0;
  for (const [kind, type, , , , counts] of analyticsIn(reports.downloads, from, to)) {
    if (!/first/i.test(kind)) continue;
    firstDownloads += counts;
    sumByKey(sources, type || 'Unavailable', { downloads: counts });
  }
  let impressions = 0;
  let pageViews = 0;
  for (const [event, type, , territory, counts] of analyticsIn(reports.discovery, from, to)) {
    if (/impression/i.test(event)) {
      impressions += counts;
      sumByKey(sources, type || 'Unavailable', { impressions: counts });
    } else if (/page view/i.test(event)) {
      pageViews += counts;
      sumByKey(sources, type || 'Unavailable', { pageViews: counts });
      if (territory) sumByKey(territories, territory, { pageViews: counts });
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
    funnel: { impressions, pageViews, firstDownloads, purchases },
    territories: Object.fromEntries(territories),
    usage: { installs, deletions, sessions },
  };
}

// Visitors as Mole's 访客来源 reads them. App Store clicks exist only from
// STORE_CLICK_SINCE, so their rate divides by the sessions of those same days
// and an earlier window has no click figure at all, never a zero.
function trafficSum(t, from, to) {
  const out = { sessions: 0, views: 0, newUsers: 0, clicks: 0, clickSessions: 0, clickDays: 0 };
  for (const [date, [sessions, , views, newUsers]] of Object.entries(t.days || {})) {
    if (date < from || date > to) continue;
    out.sessions += sessions;
    out.views += views;
    out.newUsers += newUsers || 0;
    if (date >= STORE_CLICK_SINCE) { out.clickSessions += sessions; out.clickDays += 1; }
  }
  for (const [date, , n] of t.clicks || []) if (date >= from && date <= to) out.clicks += n;
  // A snapshot from before these were pulled knows neither: unknown, not zero.
  const days = Object.entries(t.days || {}).filter(([d]) => d >= from && d <= to);
  if (days.some(([, v]) => v.length < 4)) out.newUsers = null;
  out.clickRate = Array.isArray(t.clicks) && out.clickDays && out.clickSessions ? out.clicks / out.clickSessions : null;
  return out;
}

function breakdownIn(rows, from, to, top) {
  const map = new Map();
  for (const [date, key, n] of rows || []) if (date >= from && date <= to) map.set(key, (map.get(key) || 0) + n);
  return [...map.entries()].sort((a, b) => b[1] - a[1]).slice(0, top).map(([key, count]) => ({ key, count }));
}

function buildTraffic(state, from, to) {
  const t = state.traffic || { days: {} };
  const sum = trafficSum(t, from, to);
  const clicksBySource = new Map(breakdownIn(t.clicks, from, to, 1000).map((c) => [c.key, c.count]));
  // Daily bars, by month past three months, with clicks on the same buckets.
  const latest = Object.keys(t.days || {}).sort().pop() || null;
  const end = latest && latest < to ? latest : to;
  const byMonth = dayCount(from, end) > 92;
  const series = new Map();
  for (const [date, [sessions]] of Object.entries(t.days || {})) {
    if (date < from || date > end) continue;
    sumByKey(series, byMonth ? date.slice(0, 7) : date, { sessions });
  }
  for (const [date, , n] of t.clicks || []) {
    if (date < from || date > end) continue;
    sumByKey(series, byMonth ? date.slice(0, 7) : date, { clicks: n });
  }
  if (!byMonth) for (let d = from; d <= end; d = addDays(d, 1)) if (!series.has(d)) series.set(d, {});
  const hasBreakdown = (k) => Array.isArray(t[k]) && t[k].length > 0;
  return {
    available: Object.keys(t.days || {}).length > 0,
    latest,
    latestDay: latest ? { date: latest, sessions: t.days[latest][0], clicks: (t.clicks || []).reduce((n, [d, , c]) => (d === latest ? n + c : n), 0) } : null,
    ...sum,
    clicksKnown: hasBreakdown('clicks') && end >= STORE_CLICK_SINCE,
    byMonth,
    series: [...series.entries()].sort().map(([key, v]) => ({ key, sessions: v.sessions || 0, clicks: v.clicks || 0, clicksKnown: (byMonth ? `${key}-31` : key) >= STORE_CLICK_SINCE })),
    sources: breakdownIn(t.sources, from, to, 50).map((s) => ({ source: s.key, count: s.count, clicks: clicksBySource.get(s.key) || 0 })),
    countries: hasBreakdown('countries') ? breakdownIn(t.countries, from, to, 1000) : null,
    channels: hasBreakdown('channels') ? breakdownIn(t.channels, from, to, 1000) : null,
  };
}

// One row per day inside the chosen range: what sold, where and on which
// device. A day past Apple's newest sales report is unknown, not zero; when
// the channel report already has that day, its count stands in as an estimate.
// That report cuts days differently (on 25 of 58 days through 2026-11-10 its
// count sat a day off the sales report while the totals agreed), so it fills
// unknown days only and is never added to a known one.
function buildRecent(state, convert, { from, to, today, latestSalesDate }) {
  const byDay = new Map();
  const mix = new Map();
  for (const [date, type, units, proceeds, proceedsCur, price, , country, device] of state.sales.rows) {
    if (date < from || date > to || kindOf(type, price) !== 'sale') continue;
    const net = convert(proceeds, proceedsCur);
    const patch = { proceeds: (net || 0) * units };
    if (units > 0) {
      patch.sold = units;
      sumByKey(mix, `${date}\u0000${country}\u0000${deviceLabel(device)}`, { units });
    } else {
      patch.refunded = -units;
    }
    sumByKey(byDay, date, patch);
  }
  const mixOf = (date) => [...mix.entries()]
    .filter(([k]) => k.startsWith(`${date}\u0000`))
    .map(([k, v]) => { const [, country, device] = k.split('\u0000'); return { country, device, units: v.units }; })
    .sort((a, b) => b.units - a.units);
  const channel = (state.analytics && state.analytics.reports && state.analytics.reports.purchases) || {};
  const estimate = (date) => {
    if (!channel[date]) return null;
    let purchases = 0;
    let proceeds = 0;
    for (const [, , , , n, usd] of channel[date]) {
      purchases += n;
      proceeds += convert(usd, 'USD') || 0;
    }
    return purchases ? { purchases, proceeds } : null;
  };
  const days = (state.traffic && state.traffic.days) || {};
  const latestVisit = Object.keys(days).sort().pop() || '';
  const row = (date) => {
    const known = Boolean(latestSalesDate) && date <= latestSalesDate && Boolean(state.sales.dates[date]);
    const v = byDay.get(date) || {};
    return {
      date, known,
      sold: v.sold || 0, refunded: v.refunded || 0, proceeds: v.proceeds || 0,
      mix: mixOf(date),
      estimate: known ? null : estimate(date),
      sessions: date > latestVisit ? null : (days[date] ? days[date][0] : 0),
    };
  };
  // Days with income or a refund, plus recent days Apple has not reported: a
  // quiet day says nothing, and an unreported one must not read as quiet.
  const wanted = new Set([...byDay.keys()].filter((d) => d < today));
  for (let i = 0; i < RECENT_DAYS; i += 1) {
    const date = addDays(today, -1 - i);
    if (date >= from && date <= to && !row(date).known) wanted.add(date);
  }
  return [...wanted].sort().reverse().map(row);
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

function salesSum(rows, convert, from, to) {
  const out = { sold: 0, refunded: 0, proceeds: 0 };
  for (const [date, type, units, proceeds, proceedsCur, price] of rows) {
    if (date < from || date > to || kindOf(type, price) !== 'sale') continue;
    out.proceeds += (convert(proceeds, proceedsCur) || 0) * units;
    if (units > 0) out.sold += units;
    else out.refunded -= units;
  }
  return out;
}

const dayCount = (from, to) => Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / 864e5) + 1;

// The headline numbers people compare. Apple's sales report trails by a day or
// two, so a window's last days are unknown, not zero: the comparison takes only
// the days already reported and sets them against the same days one window
// earlier, and the daily average divides by reported days.
function buildPulse(state, convert, { range, from, to, latestSalesDate }) {
  const rows = state.sales.rows;
  const reportedTo = latestSalesDate && latestSalesDate < to ? latestSalesDate : to;
  // A calendar month compares with the month before it, day for day, as Mole's
  // 当月 does; a rolling window with the same number of days just before it.
  const monthly = range === 'month' || range.startsWith('m:');
  const out = { prev: null, trafficPrev: null, daily: null, prevLabel: range === 'month' ? '上月同期' : monthly ? '上月' : '上期' };
  const previous = (end) => {
    if (!monthly) {
      const span = dayCount(from, to);
      return [addDays(from, -span), addDays(end, -span)];
    }
    const pm = prevMonthOf(from.slice(0, 7));
    return [`${pm}-01`, `${pm}-${String(Math.min(Number(end.slice(8)), daysInMonth(pm))).padStart(2, '0')}`];
  };
  if (latestSalesDate && reportedTo >= from) {
    const days = dayCount(from, reportedTo);
    const cur = salesSum(rows, convert, from, reportedTo);
    out.daily = { days, proceeds: cur.proceeds / days, sold: cur.sold / days };
    if (range !== 'all') {
      const [pFrom, pTo] = previous(reportedTo);
      if (rows.length && rows[0][0] <= pFrom) {
        out.prev = salesSum(rows, convert, pFrom, pTo);
        out.prevWindow = { from: pFrom, to: pTo };
      }
    }
  }
  const tDays = (state.traffic && state.traffic.days) || {};
  const tLatest = Object.keys(tDays).sort().pop();
  if (range !== 'all' && tLatest && tLatest >= from) {
    const [pFrom, pTo] = previous(tLatest < to ? tLatest : to);
    if (Object.keys(tDays).sort()[0] <= pFrom) out.trafficPrev = trafficSum(state.traffic, pFrom, pTo);
  }
  return out;
}

const daysInMonth = (month) => {
  const [y, m] = month.split('-').map(Number);
  return new Date(Date.UTC(y, m, 0)).getUTCDate();
};
const prevMonthOf = (month) => {
  const [y, m] = month.split('-').map(Number);
  return new Date(Date.UTC(y, m - 2, 1)).toISOString().slice(0, 7);
};

// Month progress, as Mole reads it: how far through the month the reported
// days are, where the month lands at this pace, and the month so far drawn day
// by day against the whole previous month. A chosen closed month shows itself;
// any other window shows the month of Apple's newest report.
function buildMonthProgress(state, convert, { range, latestSalesDate, firstDate }) {
  if (!latestSalesDate || !firstDate) return null;
  const closed = /^m:(\d{4}-\d{2})$/.exec(range);
  const month = closed ? closed[1] : latestSalesDate.slice(0, 7);
  const total = daysInMonth(month);
  const reported = closed ? total : Number(latestSalesDate.slice(8));
  if (month < firstDate.slice(0, 7) || month > latestSalesDate.slice(0, 7)) return null;
  const daily = (m, lastDay) => {
    const out = Array.from({ length: lastDay }, () => ({ proceeds: 0, sold: 0, refunded: 0 }));
    for (const [date, type, units, proceeds, proceedsCur, price] of state.sales.rows) {
      if (date.slice(0, 7) !== m || kindOf(type, price) !== 'sale') continue;
      const i = Number(date.slice(8)) - 1;
      if (i >= lastDay) continue;
      out[i].proceeds += (convert(proceeds, proceedsCur) || 0) * units;
      if (units > 0) out[i].sold += units; else out[i].refunded -= units;
    }
    let run = 0;
    return out.map((d) => { run += d.proceeds; return { ...d, cumulative: run }; });
  };
  const cur = daily(month, reported);
  const sum = (days, k) => days.reduce((n, d) => n + d[k], 0);
  const proceeds = sum(cur, 'proceeds');
  const sold = sum(cur, 'sold');
  const refunded = sum(cur, 'refunded');
  const prevMonth = prevMonthOf(month);
  // A previous month sales did not fully cover draws nothing.
  const prev = firstDate <= `${prevMonth}-01` ? daily(prevMonth, daysInMonth(prevMonth)) : null;
  return {
    month, total, reported, closed: Boolean(closed),
    proceeds, sold, refunded,
    refundRate: sold ? refunded / sold : null,
    dailyAverage: reported ? proceeds / reported : 0,
    forecast: closed || !reported ? null : (proceeds / reported) * total,
    curve: cur.map((d) => d.cumulative),
    prev: prev ? { month: prevMonth, curve: prev.map((d) => d.cumulative), proceeds: sum(prev, 'proceeds') } : null,
  };
}

// The lifetime best day by money and by units, each with its own date.
function buildRecords(state, convert) {
  const byDay = new Map();
  for (const [date, type, units, proceeds, proceedsCur, price] of state.sales.rows) {
    if (kindOf(type, price) !== 'sale') continue;
    sumByKey(byDay, date, { proceeds: (convert(proceeds, proceedsCur) || 0) * units, sold: units > 0 ? units : 0 });
  }
  let money = null;
  let units = null;
  for (const [date, v] of byDay) {
    if (v.proceeds > 0 && (!money || v.proceeds > money.value)) money = { date, value: v.proceeds };
    if (v.sold > 0 && (!units || v.sold > units.value)) units = { date, value: v.sold };
  }
  return { money, units };
}

const STORE_REJECTED = new Set(['REJECTED', 'METADATA_REJECTED', 'INVALID_BINARY']);

// Rule alerts, one number each with its line printed in the sentence, set from
// the normal bands of this app's own history (2026-11-22 snapshot): Mole's
// "yesterday under 70% of the 7-day mean" would have been lit on 127 of 167
// days at a couple of sales a day, so silence is judged against chance instead.
// A rule whose inputs are missing is skipped, never read as zero.
function buildAlerts(state, { today, latestSalesDate, trafficStale, store }) {
  const out = [];
  const sold = new Map();
  const refunded = new Map();
  for (const [date, type, units, , , price] of state.sales.rows) {
    if (kindOf(type, price) !== 'sale') continue;
    if (units > 0) sold.set(date, (sold.get(date) || 0) + units);
    else refunded.set(date, (refunded.get(date) || 0) - units);
  }
  const reported = (d) => state.sales.dates[d] === 'ok' || state.sales.dates[d] === 'none';
  if (latestSalesDate) {
    // Silence: reported days in a row with no sale, lit once that run is less
    // than 5% likely at the previous 28 days' pace (mean x days >= 3).
    let streak = 0;
    for (let d = latestSalesDate; reported(d) && !sold.get(d); d = addDays(d, -1)) streak += 1;
    if (streak) {
      const end = addDays(latestSalesDate, -streak);
      let n = 0;
      for (let i = 0; i < 28; i += 1) n += sold.get(addDays(end, -i)) || 0;
      const mean = n / 28;
      if (mean * streak >= 3) out.push({ rule: '连续零销量', level: 'danger', text: `已连续 ${streak} 天没有售出，前 28 天日均 ${mean.toFixed(1)} 份` });
    }
    // Refunds: two or more in the last 7 reported days and over 20% of units;
    // p90 of the 7-day rate is 33% on a handful of units, so the count gates it.
    let s7 = 0;
    let r7 = 0;
    for (let i = 0; i < 7; i += 1) {
      const d = addDays(latestSalesDate, -i);
      s7 += sold.get(d) || 0;
      r7 += refunded.get(d) || 0;
    }
    if (r7 >= 2 && s7 && r7 / s7 > 0.2) {
      let sp = 0;
      let rp = 0;
      for (let i = 7; i < 14; i += 1) {
        const d = addDays(latestSalesDate, -i);
        sp += sold.get(d) || 0;
        rp += refunded.get(d) || 0;
      }
      const before = sp ? `，前 7 天 ${Math.round((rp / sp) * 100)}%` : '';
      out.push({ rule: '退款率', level: 'danger', text: `近 7 天退款率 ${Math.round((r7 / s7) * 100)}%（${r7} / ${s7}），超过 20%${before}` });
    }
    // Apple normally reports a Pacific day the next morning, so two days behind is late.
    if (latestSalesDate < addDays(today, -2)) out.push({ rule: '销售报表', level: 'warn', text: `Apple 销售报表停在 ${latestSalesDate.slice(5)}` });
  }
  if (trafficStale) out.push({ rule: '官网流量', level: 'warn', text: `官网流量停在 ${trafficStale.slice(5)}` });
  for (const v of store || []) {
    if (STORE_REJECTED.has(v.state)) out.push({ rule: '审核', level: 'danger', text: `${v.platform === 'IOS' ? 'iPhone 和 iPad' : 'Mac'} ${v.version} 没过审` });
  }
  return out;
}

function buildView(state, { range = 'all', currency = 'CNY', today = pacificToday() } = {}) {
  // A month remembered from before 当月 existed reads as 当月.
  if (range === `m:${addDays(today, -1).slice(0, 7)}`) range = 'month';
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
  // When each country first bought, over the whole history: a new market shows
  // up as a recent date whatever window is open.
  const firstSale = new Map();
  for (const [date, type, units, , , price, , country] of allRows) {
    if (units > 0 && kindOf(type, price) === 'sale' && !firstSale.has(country)) firstSale.set(country, date);
  }
  const convertUsd = (v) => convert(v, 'USD');
  const latestSalesDate = Object.keys(state.sales.dates).filter((d) => state.sales.dates[d] === 'ok').sort().pop() || null;
  const pulse = buildPulse(state, convert, { range, from, to, latestSalesDate });
  const analytics = buildAnalytics(state, from, to, convertUsd);
  // Units each country sold over the same reported days one window earlier.
  const prevByCountry = new Map();
  if (pulse.prevWindow) {
    for (const [date, type, units, , , price, , ctry] of allRows) {
      if (date < pulse.prevWindow.from || date > pulse.prevWindow.to || units <= 0 || kindOf(type, price) !== 'sale') continue;
      prevByCountry.set(ctry, (prevByCountry.get(ctry) || 0) + units);
    }
  }
  const countryList = toList(countries).map((c) => {
    const store = analytics.territories[c.key] || {};
    return {
      ...c,
      share: totals.sold ? c.sold / totals.sold : null,
      first: firstSale.get(c.key) || null,
      prevSold: pulse.prevWindow ? prevByCountry.get(c.key) || 0 : null,
      refundRate: c.sold ? c.refunded / c.sold : null,
      pageViews: store.pageViews || 0,
      storeRate: store.pageViews ? (store.purchases || 0) / store.pageViews : null,
    };
  });

  return {
    range, currency, from, to, today,
    totals: {
      ...totals,
      net: totals.gross - totals.refundAmount,
      netUnits: totals.sold - totals.refunded,
      refundRate: totals.sold ? totals.refunded / totals.sold : null,
    },
    byMonth,
    // A day (or month) Apple has not reported yet is pending, never a zero day:
    // the chart breaks its line there instead of drawing it down to the axis.
    series: [...points.entries()].sort().map(([key, v]) => ({ key, sold: v.sold || 0, refunded: v.refunded || 0, proceeds: v.proceeds || 0, pending: !latestSalesDate || (byMonth ? `${key}-01` : key) > latestSalesDate })),
    devices: toList(devices),
    countries: countryList,
    countriesEver: firstSale.size,
    refunds: refunds.sort((a, b) => (a.date < b.date ? 1 : -1)),
    analytics,
    traffic: buildTraffic(state, range === 'all' ? TRAFFIC_START : from, to),
    search: buildSearch(state),
    recent: buildRecent(state, convert, { from, to, today, latestSalesDate }),
    pulse,
    latest: latestIncome(state, convert),
    months: monthOptions(allRows, today),
    finance: buildFinance(state, convert),
    monthProgress: buildMonthProgress(state, convert, { range, latestSalesDate, firstDate }),
    records: buildRecords(state, convert),
    alerts: buildAlerts(state, { today, latestSalesDate, trafficStale: isTrafficStale(state, today), store: buildStore(state) }),
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

// Closed months only: the running month is the 当月 preset, so one question
// never has two entry points with two different numbers.
function monthOptions(rows, today) {
  const paid = rows.filter((r) => kindOf(r[1], r[5]) === 'sale');
  if (!paid.length) return [];
  const out = [];
  let m = paid[0][0].slice(0, 7);
  const current = addDays(today, -1).slice(0, 7);
  while (m < current) {
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
    // What buyers paid for the same days, refunds netted, so the payout reads
    // as a share of it the way Mole's payouts read against their payments.
    // Mole reads a payout against the payments behind it: the rate is the
    // payout over what buyers paid, and refunds and Apple's share (commission
    // and tax together, which these reports never split) are shares of it.
    let paid = 0;
    let refunds = 0;
    for (const [date, type, n, , , price, cur] of state.sales.rows) {
      if (date < rows[0].start || date > rows[0].end || kindOf(type, price) !== 'sale') continue;
      const c = convert(Math.abs(price), cur);
      if (c === null) unconverted = true;
      else if (n > 0) paid += c * n;
      else refunds -= c * n;
    }
    const known = paid > 0 && !unconverted;
    out.push({
      period, start: rows[0].start, end: rows[0].end, units, amount, paid, refunds,
      rate: known ? amount / paid : null,
      apple: known ? paid - refunds - amount : null,
      unconverted,
    });
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

// MiaoYan's paid units and buyer-paid USD cents per Apple (Pacific) day,
// before refunds, for the product cards at the top of Mole's Payroom
// (maintainer 2026-11-22). The same rows and conversion as buildView's totals,
// so both pages agree; `through` is the last day Apple's report is in. A day
// carries a third element, 1, when it is not whole: a currency with no rate
// yet, or a day before `through` whose report this store never got (a failed
// fetch), which this page also shows as not reported rather than as no sales.
function salesFeed(state) {
  const convert = converter(state.fx, 'USD');
  const days = {};
  for (const [date, type, units, , , price, cur] of state.sales.rows) {
    if (units <= 0 || kindOf(type, price) !== 'sale') continue;
    const usd = convert(price, cur);
    const cell = (days[date] ||= [0, 0]);
    cell[0] += units;
    cell[1] += Math.round((usd || 0) * units * 100);
    if (usd === null) cell[2] = 1;
  }
  const dates = state.sales.dates;
  const through = Object.keys(dates).filter((d) => dates[d] === 'ok').sort().pop() || null;
  const first = state.sales.rows[0] && state.sales.rows[0][0];
  if (through && first) {
    for (let d = first; d <= through; d = addDays(d, 1)) {
      if (!dates[d]) (days[d] ||= [0, 0])[2] = 1;
    }
  }
  return { product: 'miaoyan', timeZone: 'America/Los_Angeles', generatedAt: state.syncedAt || null, through, days };
}

module.exports = {
  APP_ID,
  ANALYTICS_REPORTS,
  addDays,
  buildSearch,
  buildView,
  compactAnalyticsRows,
  emptyState,
  financeRowsFromReport,
  fiscalPeriods,
  kindOf,
  pacificToday,
  parseTsv,
  rangeBounds,
  quickSales,
  salesFeed,
  readState,
  runSync,
  salesRowsFromReport,
  syncSearch,
};
