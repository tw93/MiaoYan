// node scripts/test-payroom.mjs
// Fixture rows copy the shape of real App Store Connect reports. The one that
// matters: a refund row has negative Units and Customer Price but a POSITIVE
// Developer Proceeds, so a naive sum of proceeds would add refunds.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import zlib from 'node:zlib';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const lib = require('../api/_payroom-lib.js');
const page = require('../api/_payroom-page.js');

const HEAD = 'Provider\tProvider Country\tSKU\tDeveloper\tTitle\tVersion\tProduct Type Identifier\tUnits\tDeveloper Proceeds\tBegin Date\tEnd Date\tCustomer Currency\tCountry Code\tCurrency of Proceeds\tApple Identifier\tCustomer Price\tPromo Code\tParent Identifier\tSubscription\tPeriod\tCategory\tCMB\tDevice\tSupported Platforms\tProceeds Reason\tPreserved Pricing\tClient\tOrder Type';
const row = ({ type, units, proceeds, date, cur, country, price, device = 'iPhone', promo = ' ', version = '4.6.1' }) =>
  `APPLE\tUS\tcom.tw93.miaoyan\tx\tMiaoYan\t${version}\t${type}\t${units}\t${proceeds}\t${date}\t${date}\t${cur}\t${country}\t${cur}\t6759252269\t${price}\t${promo}\t \t \t \tProductivity\t \t${device}\tiOS and macOS\t \t \t \t `;

const report = [
  HEAD,
  row({ type: '1F', units: 3, proceeds: '76.89', date: '11/05/2026', cur: 'CNY', country: 'CN', price: '88.00' }),
  row({ type: '1F', units: -1, proceeds: '76.89', date: '11/06/2026', cur: 'CNY', country: 'CN', price: '-88.00' }),
  row({ type: 'F1', units: 1, proceeds: '11.04', date: '10/28/2026', cur: 'USD', country: 'US', price: '12.99', device: 'Desktop' }),
  row({ type: 'F1', units: 1, proceeds: '0', date: '10/28/2026', cur: 'USD', country: 'US', price: '0.00', device: 'Desktop', promo: 'CR-RW' }),
  row({ type: 'F7', units: 40, proceeds: '0', date: '10/28/2026', cur: 'USD', country: 'US', price: '0', device: 'Desktop' }),
  row({ type: '3F', units: 2, proceeds: '0', date: '10/28/2026', cur: 'USD', country: 'US', price: '0' }),
].join('\n');

const state = lib.emptyState();
state.sales.rows = lib.salesRowsFromReport(report).sort((a, b) => (a[0] < b[0] ? -1 : 1));
state.fx = { rates: { USD: 1, CNY: 7 } };

let checks = 0;
const eq = (a, b, what) => { assert.deepEqual(a, b, what); checks += 1; };
const near = (a, b, what) => { assert.ok(Math.abs(a - b) < 1e-6, `${what}: ${a} vs ${b}`); checks += 1; };

const today = '2026-11-08';
const all = lib.buildView(state, { range: 'all', currency: 'CNY', today }).totals;
eq(all.sold, 4, 'three units in one row count as three, plus the Mac sale');
eq(all.refunded, 1, 'the refund row counts once');
eq(all.netUnits, 3, 'net units');
near(all.gross, 3 * 88 + 12.99 * 7, 'gross is units times price');
near(all.refundAmount, 88, 'refund amount');
near(all.net, 3 * 88 + 12.99 * 7 - 88, 'net subtracts the refund');
near(all.proceeds, 2 * 76.89 + 11.04 * 7, 'a refund takes its proceeds back even though the column is positive');
near(all.refundRate, 1 / 4, 'refund rate');
eq(all.free, 1, 'a promo code is not a sale');
eq(all.update, 40, 'updates stay out of sales');
eq(all.redownload, 2, 'redownloads stay out of sales');

const usd = lib.buildView(state, { range: 'all', currency: 'USD', today }).totals;
near(usd.gross, (3 * 88) / 7 + 12.99, 'USD view converts CNY and keeps USD');

const view = lib.buildView(state, { range: '7d', currency: 'CNY', today });
eq([view.from, view.to], ['2026-11-01', '2026-11-07'], '7d is seven complete days ending yesterday');
eq(view.totals.sold, 3, 'the window drops the October sale');
eq(view.countries[0].refunded, 1, 'the refund reaches the country split');
eq(view.devices[0].refunded, 1, 'the refund reaches the device split');
near(view.devices[0].proceeds, 2 * 76.89, 'device proceeds net of the refund');
eq(view.refunds.length, 1, 'the refund is listed');

const noFx = lib.emptyState();
noFx.sales.rows = state.sales.rows;
noFx.fx = { rates: { USD: 1 } };
eq(lib.buildView(noFx, { range: 'all', currency: 'USD', today }).totals.unconverted, 4, 'a currency without a rate is flagged, not silently zero');

eq(lib.financeRowsFromReport('Start Date\tEnd Date\tQuantity\tExtended Partner Share\tPartner Share Currency\tCountry Of Sale\tProduct Type Identifier\n05/31/2026\t06/27/2026\t2\t121.02\tCNY\tCN\tF1\nTotal_Rows\t5\n\nCountry Of Sale\tCN').length, 1, 'finance summary lines are not rows');
eq(lib.fiscalPeriods('2026-11-08').slice(-3), ['2026-12', '2027-01', '2027-02'], 'November 2026 is FY27 period 2');

const spec = lib.ANALYTICS_REPORTS.downloads;
const parsed = lib.parseTsv('Date\tDownload Type\tSource Type\tSource Info\tDevice\tTerritory\tCounts\n2026-11-01\tFirst-time download\tWeb Referrer\tmiaoyan.app\tiPhone\tCN\t5\n2026-11-01\tRedownload\tApp Store Search\t\tiPhone\tCN\t9');
state.analytics.reports.downloads = lib.compactAnalyticsRows(spec, parsed);
state.analytics.reports.purchases = lib.compactAnalyticsRows(lib.ANALYTICS_REPORTS.purchases, lib.parseTsv('Date\tSource Type\tSource Info\tDevice\tTerritory\tPurchases\tProceeds in USD\tSales in USD\n2026-11-01\tWeb Referrer\tmiaoyan.app\tiPhone\tCN\t2\t20\t26'));
const a = lib.buildView(state, { range: '7d', currency: 'CNY', today }).analytics;
eq(a.funnel.firstDownloads, 5, 'redownloads are not first downloads');
eq(a.sources[0].type, 'Web Referrer', 'the source that sold ranks first');
eq(a.sources[0].purchases, 2, 'purchases by source');
near(a.sources[0].proceeds, 140, 'source proceeds convert from USD');
eq(a.details[0].info, 'miaoyan.app', 'referrer detail');

state.sales.dates = { '2026-11-05': 'ok', '2026-11-06': 'ok', '2026-11-07': 'none' };
state.traffic = {
  days: { '2026-11-05': [10, 8, 20], '2026-11-06': [5, 4, 6], '2023-01-01': [99, 99, 99] },
  sources: [['2026-11-05', 'github.com', 7], ['2026-11-05', '(direct)', 3], ['2026-11-06', 'github.com', 5]],
};
const week = lib.buildView(state, { range: '7d', currency: 'CNY', today });
eq([week.traffic.sessions, week.traffic.views], [15, 26], 'traffic sums inside the window only');
eq(week.traffic.sources[0], { source: 'github.com', count: 12 }, 'sources sum across days');
const recent = Object.fromEntries(week.recent.map((d) => [d.date, d]));
eq(week.recent.length, 14, 'the daily table always shows fourteen days');
eq(recent['2026-11-05'].sold, 3, 'a day with sales');
near(recent['2026-11-06'].proceeds, -76.89, 'a day with only a refund goes negative');
eq(recent['2026-11-06'].refunded, 1, 'the refund reaches the daily table');
eq(recent['2026-11-07'].known, false, 'a day past the newest report is unknown, not zero');
eq(recent['2026-11-05'].sessions, 10, 'site visits sit beside the income');
eq(recent['2026-11-07'].sessions, null, 'a day past the newest GA day is unknown, not zero');
eq(lib.buildView(state, { today }).trafficStale, null, 'GA one or two days behind is normal');
eq(lib.buildView(state, { today: '2026-11-20' }).trafficStale, '2026-11-06', 'a long silence is called out');
eq(week.latest.date, '2026-11-05', 'the newest income ignores a later refund-only day');
near(week.latest.proceeds, 3 * 76.89, 'the newest income counts every unit that day');
eq(lib.buildView(state, { today }).range, 'all', 'the default view is everything');
eq(lib.buildView(state, { today }).traffic.sessions, 114, 'all counts traffic from before the first sale');

state.reviews = [{ rating: 5, title: '<img src=x onerror=alert(1)>', body: '<script>alert(1)</script>', nickname: 'a"b', territory: 'CHN', created: '2026-11-01T00:00:00Z' }];
const html = page.renderDashboard(lib.buildView(state, { range: 'all', currency: 'CNY', today }));
assert.ok(!html.includes('<script>alert(1)'), 'a review body is escaped');
assert.ok(!html.includes('<img src=x'), 'a review title is escaped');
assert.ok(html.includes('&lt;script&gt;alert(1)'), 'the escaped text still shows');
checks += 3;
const fresh = lib.emptyState();
assert.ok(page.renderDashboard(lib.buildView(fresh, { today })).includes('已向 Apple 申请渠道报告'), 'an empty store still renders');
checks += 1;

// ---- runSync against a stubbed network ----------------------------------
const { privateKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'P-256' });
Object.assign(process.env, {
  ASC_PRIVATE_KEY: privateKey.export({ type: 'pkcs8', format: 'pem' }),
  ASC_KEY_ID: 'k', ASC_ISSUER_ID: 'i', ASC_VENDOR_NUMBER: '1',
  BLOB_READ_WRITE_TOKEN: 'vercel_blob_rw_store_x',
  MIAOYAN_GA_PROPERTY_ID: '1', MIAOYAN_GA_SERVICE_ACCOUNT_JSON: '{bad',
});
const SYNC_NOW = new Date('2026-11-08T12:00:00Z');
const answer = (status, body = '') => new Response(body, { status });
function stub({ blob, sales, json = () => answer(500) }) {
  const writes = [];
  globalThis.fetch = async (url, init = {}) => {
    const u = String(url);
    if (u.includes('.blob.vercel-storage.com')) return blob();
    if (u.includes('/api/blob/')) { writes.push(JSON.parse(zlib.gunzipSync(init.body).toString())); return answer(200, '{}'); }
    if (u.includes('/v1/salesReports')) return sales(u);
    return json(u);
  };
  return writes;
}
const absent = () => answer(404);
const stored = (value) => () => answer(200, zlib.gzipSync(JSON.stringify(value)));
const salesFor = (date, body) => (u) => (u.includes(`reportDate]=${date}`) ? answer(200, body) : answer(404));

let writes = stub({ blob: () => answer(503), sales: () => answer(404) });
await assert.rejects(lib.runSync({ now: SYNC_NOW }), /blob read 503/, 'an unreadable store stops the sync');
eq(writes.length, 0, 'an unreadable store is never overwritten');

writes = stub({ blob: absent, sales: () => answer(404) });
await assert.rejects(lib.runSync({ now: SYNC_NOW }), /第一次同步/, 'a first run with nothing does not create the store');
eq(writes.length, 0, 'a first run with nothing writes nothing');

const renamed = 'Date\tCount\n2026-11-05\t1';
const seeded = lib.emptyState();
seeded.sales.rows = [['2026-01-01', 'F1', 1, 60, 'CNY', 88, 'CNY', 'CN', 'Desktop', '', '4.0.0']];
writes = stub({ blob: stored(seeded), sales: salesFor('2026-11-05', renamed) });
await lib.runSync({ now: SYNC_NOW, budgetMs: 1000 });
const afterRename = writes[writes.length - 1];
eq(afterRename.sales.dates['2026-11-05'], undefined, 'a report with renamed columns is not marked done');
assert.ok(afterRename.errors.some((e) => e.includes('缺字段')), 'a renamed column is reported on the page');
eq(afterRename.sales.rows.length, 1, 'a failed part keeps the rows it had');
checks += 1;
assert.ok(writes.length >= 2, 'sales are saved before the channel reports run');
checks += 1;

writes = stub({ blob: stored(seeded), sales: (u) => { if (u.includes('reportDate]=2026-11-05')) throw new TypeError('fetch failed'); return salesFor('2026-11-06', report)(u); } });
await lib.runSync({ now: SYNC_NOW, budgetMs: 1000 });
const afterDrop = writes[writes.length - 1];
eq(afterDrop.sales.dates['2026-11-05'], undefined, 'a dropped connection leaves that day to retry');
eq(afterDrop.sales.dates['2026-11-06'], 'ok', 'the other days still land');
assert.ok(afterDrop.sales.rows.length > 1, 'and keep their rows');
checks += 1;
const dropView = lib.buildView(afterDrop, { today });
eq(Object.fromEntries(dropView.recent.map((d) => [d.date, d.known]))['2026-11-05'], false, 'a day that failed reads as unknown, not zero');

// ---- the page ------------------------------------------------------------
const bad = lib.emptyState();
bad.sales.rows = [['2026-11-01', '1F', -1, 5, 'USD', 5, '', 'US', 'iPhone', '', '4.0.0']];
assert.ok(page.renderDashboard(lib.buildView(bad, { today })).includes('退款明细'), 'a blank currency does not take the page down');
checks += 1;
const lateRefund = lib.emptyState();
lateRefund.fx = { rates: { USD: 1, CNY: 7 } };
lateRefund.sales.rows = [['2026-11-05', '1F', 3, 10, 'CNY', 20, 'CNY', 'CN', 'iPhone', '', ''], ['2026-11-05', '1F', -1, 10, 'CNY', 20, 'CNY', 'CN', 'iPhone', '', '']];
near(lib.buildView(lateRefund, { today }).latest.proceeds, 20, 'the newest income nets a same-day refund');

// ---- the login form, as a browser posts it ------------------------------
process.env.MIAOYAN_PAYROOM_PASSWORD = 'yes@!';
process.env.MIAOYAN_PAYROOM_SESSION_SECRET = 'session';
const handler = (await import('../api/payroom.js')).default;
function call(method, headers = {}, body = undefined) {
  return new Promise((resolve) => {
    const seen = {};
    const res = { statusCode: 200, setHeader(k, v) { seen[k.toLowerCase()] = v; }, end(html) { resolve({ status: this.statusCode, headers: seen, html: String(html || '') }); } };
    handler({ method, headers, url: '/payroom', body }, res);
  });
}
// A browser under no-referrer posts `Origin: null`, and curl sends none: the login
// has to work for both, because an Origin check locked the maintainer out while
// every curl test passed.
eq((await call('POST', { host: 'miaoyan.app', origin: 'null' }, { password: 'yes@!' })).status, 303, 'the right password logs in with Origin: null');
eq((await call('POST', { host: 'miaoyan.app', origin: 'https://miaoyan.app' }, { password: 'yes@!' })).status, 303, 'the right password logs in with the real Origin');
eq((await call('POST', { host: 'miaoyan.app', origin: 'null' }, { password: 'no' })).status, 401, 'a wrong password is refused');

console.log(`payroom: ${checks} checks passed`);
