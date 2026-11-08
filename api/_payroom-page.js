'use strict';

// Payroom's HTML. Server-rendered with no client framework: range and currency
// are plain links, and every value from Apple or a reviewer goes through esc().

const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

const CSS = `
:root{color-scheme:light dark;--paper:#FDFCF9;--ink:#363433;--secondary:#5F5C57;--meta:#74716B;--line:rgba(60,50,30,.1);--sand:#EFEDE4;--green:#1C5D33;--refund:#9F3F2F;--bar:#1C5D33}
@media (prefers-color-scheme:dark){:root{--paper:#1E1D1B;--ink:#E7E3DA;--secondary:#BDB8AD;--meta:#A09B90;--line:rgba(255,255,255,.1);--sand:rgba(255,255,255,.08);--green:#54C59F;--refund:#E08E7C;--bar:#54C59F}}
*{box-sizing:border-box}
html{-webkit-text-size-adjust:100%}
body{margin:0;background:var(--paper);color:var(--ink);font:15px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC",sans-serif;font-variant-numeric:tabular-nums}
main{max-width:1000px;margin:0 auto;padding:28px 24px 64px}
h1,h2{font-family:Charter,Georgia,"Songti SC",serif;font-weight:500;margin:0}
h1{font-size:24px;line-height:1.3}
h2{font-size:18px;line-height:1.4}
a{color:inherit}
.top{display:flex;flex-wrap:wrap;align-items:baseline;gap:4px 14px}
.top .sync{color:var(--meta);font-size:13px}
.controls{display:flex;flex-wrap:wrap;align-items:center;gap:6px;margin:18px 0 8px}
.controls a,.controls select{height:32px;line-height:32px;padding:0 12px;border-radius:8px;font-size:13px;text-decoration:none;color:var(--secondary);border:0;background:transparent;font-family:inherit}
.controls select{background:transparent;appearance:auto;padding:0 6px;color:var(--secondary)}
.controls a[aria-current=true]{background:var(--sand);color:var(--ink);font-weight:500}
.controls .gap{flex:1}
.range{color:var(--meta);font-size:13px;margin:0 0 18px}
.warn{margin:0 0 20px;padding:10px 14px;border-radius:10px;background:var(--sand);font-size:13px}
.warn div+div{margin-top:2px}
.metrics{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:20px;padding:4px 0 22px}
.metric .label{color:var(--meta);font-size:13px}
.metric .value{font-size:28px;line-height:1.25;font-family:Charter,Georgia,serif;margin-top:2px;overflow-wrap:anywhere}
.metric .note{color:var(--secondary);font-size:13px}
section{border-top:.5px solid var(--line);padding:22px 0}
@media (max-resolution:1dppx){section{border-top-width:1px}}
section>h2{margin-bottom:12px}
.chart svg{display:block;width:100%;height:auto}
.chart text{fill:var(--meta);font-size:11px}
.legend{color:var(--meta);font-size:13px;margin-top:6px}
.scroll{overflow-x:auto}
table{width:100%;border-collapse:collapse;font-size:14px}
th{font-weight:400;color:var(--meta);font-size:13px;text-align:right;padding:4px 0 6px 16px;white-space:nowrap}
td{padding:5px 0 5px 16px;text-align:right;white-space:nowrap}
th:first-child,td:first-child{text-align:left;padding-left:0;white-space:normal}
td.refund{color:var(--refund)}
td small{color:var(--meta);font-size:13px}
.line{color:var(--secondary);font-size:14px;margin:12px 0 0}
.empty{color:var(--secondary);font-size:14px;margin:0}
.review{padding:10px 0}
.review+.review{border-top:.5px solid var(--line)}
.review .head{display:flex;flex-wrap:wrap;gap:2px 10px;font-size:14px}
.review .stars{color:var(--green)}
.review .meta{color:var(--meta);font-size:13px}
.review p{margin:4px 0 0;font-size:14px;color:var(--secondary);white-space:pre-wrap;overflow-wrap:anywhere}
.login{max-width:320px;margin:18vh auto 0;padding:0 24px}
.login h1{margin-bottom:18px}
.login input{width:100%;height:40px;border-radius:10px;border:.5px solid var(--line);background:transparent;color:var(--ink);padding:0 12px;font-size:16px;font-family:inherit}
.login button{margin-top:10px;width:100%;height:40px;border:0;border-radius:10px;background:var(--green);color:var(--paper);font-size:15px;font-family:inherit;font-weight:500;cursor:pointer}
.login .err{color:var(--refund);font-size:13px;margin:10px 0 0}
@media (max-width:760px){.metrics{grid-template-columns:repeat(2,minmax(0,1fr))}}
@media (max-width:560px){main{padding:20px 16px 48px}.metric .value{font-size:24px}.controls select{font-size:16px}th,td{padding-left:12px}}
`;

function shell(title, body) {
  return `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow,noarchive"><title>${esc(title)}</title><link rel="icon" href="/favicon.ico"><style>${CSS}</style></head><body>${body}</body></html>`;
}

function renderLogin({ failed = false, unconfigured = false } = {}) {
  const note = unconfigured ? '<p class="err">还没有配置密码</p>' : failed ? '<p class="err">密码不对</p>' : '';
  return shell('妙言 Payroom', `<div class="login"><h1>妙言 Payroom</h1><form method="post" action="/payroom"><input type="password" name="password" autocomplete="current-password" autofocus aria-label="密码" placeholder="密码"><button type="submit">进入</button></form>${note}</div>`);
}

const countryNames = new Intl.DisplayNames(['zh-CN'], { type: 'region' });
const SHORT_REGIONS = { HK: '香港', MO: '澳门', TW: '台湾' };
function country(code) {
  if (SHORT_REGIONS[code]) return SHORT_REGIONS[code];
  try { return countryNames.of(code) || code; } catch { return code; }
}

const SOURCE_LABELS = {
  'App Store Search': 'App Store 搜索',
  'App Store Browse': 'App Store 浏览',
  'App Referrer': '其他 App 跳转',
  'Web Referrer': '网页跳转',
  'App Clip': 'App Clip',
  'Institutional Purchase': '机构购买',
  Unavailable: '未知',
  'Other': '其他',
};
const sourceLabel = (t) => SOURCE_LABELS[t] || t;

const STATE_LABELS = {
  READY_FOR_DISTRIBUTION: '已上架',
  READY_FOR_SALE: '已上架',
  WAITING_FOR_REVIEW: '等待审核',
  IN_REVIEW: '审核中',
  PENDING_DEVELOPER_RELEASE: '等你发布',
  PENDING_APPLE_RELEASE: '等 Apple 发布',
  PROCESSING_FOR_DISTRIBUTION: '处理中',
  PREPARE_FOR_SUBMISSION: '准备提交',
  REJECTED: '被拒',
  METADATA_REJECTED: '元数据被拒',
  DEVELOPER_REJECTED: '已撤回',
  INVALID_BINARY: '构建无效',
};
const PLATFORM_LABELS = { MAC_OS: 'Mac', IOS: 'iPhone 和 iPad' };

function money(value, currency) {
  const digits = Math.abs(value) >= 1000 ? 0 : 2;
  if (!/^[A-Z]{3}$/.test(String(currency))) return value.toFixed(2);
  return new Intl.NumberFormat('zh-CN', { style: 'currency', currency, minimumFractionDigits: digits, maximumFractionDigits: digits }).format(value);
}
const percent = (v) => (v === null || v === undefined ? '' : `${(v * 100).toFixed(1).replace(/\.0$/, '')}%`);
const int = (v) => new Intl.NumberFormat('en-US').format(Math.round(v));
const shanghai = (iso) => new Intl.DateTimeFormat('zh-CN', { timeZone: 'Asia/Shanghai', month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit', hour12: false }).format(new Date(iso));

const fxDate = (at) => new Intl.DateTimeFormat('zh-CN', { timeZone: 'Asia/Shanghai', month: 'numeric', day: 'numeric' }).format(new Date(at));

function recentSection(view) {
  const rows = view.recent.map((d) => {
    const income = d.known
      ? `<td>${int(d.sold)}</td><td${d.refunded ? ' class="refund"' : ''}>${int(d.refunded)}</td><td>${d.sold || d.refunded ? money(d.proceeds, view.currency) : '0'}</td>`
      : '<td colspan="3"><small>等 Apple 报表</small></td>';
    return `<tr><td>${esc(d.date.slice(5))}</td>${income}<td>${d.sessions === null ? '' : int(d.sessions)}</td></tr>`;
  }).join('');
  return `<section><h2>每天入账</h2><div class="scroll"><table><thead><tr><th scope="col"></th><th scope="col">售出</th><th scope="col">退款</th><th scope="col">到手</th><th scope="col">官网访问</th></tr></thead><tbody>${rows}</tbody></table></div></section>`;
}

function trafficSection(view) {
  const t = view.traffic;
  if (!t.available || !t.sources.length) return '';
  const rows = t.sources.map((s) => `<tr><td>${esc(s.source === '(direct)' ? '直接打开' : s.source)}</td><td>${int(s.count)}</td></tr>`).join('');
  return `<section><h2>官网流量来源</h2><div class="scroll"><table><thead><tr><th scope="col"></th><th scope="col">访问</th></tr></thead><tbody>${rows}</tbody></table></div></section>`;
}

function chart(view) {
  const pts = view.series;
  if (!pts.some((p) => p.sold || p.refunded)) return '';
  const W = 960; const H = 190; const top = 12; const axis = 22;
  const maxUp = Math.max(1, ...pts.map((p) => p.sold));
  const maxDown = Math.max(0, ...pts.map((p) => p.refunded));
  const plot = H - top - axis;
  const unit = plot / (maxUp + maxDown);
  const zero = top + maxUp * unit;
  const step = W / pts.length;
  const barW = Math.max(1.5, Math.min(step * 0.62, 26));
  const labelEvery = Math.max(1, Math.ceil(pts.length / 8));
  const bars = pts.map((p, i) => {
    const x = (i + 0.5) * step - barW / 2;
    const title = `<title>${esc(p.key)} 售出 ${p.sold}${p.refunded ? `，退款 ${p.refunded}` : ''}</title>`;
    let out = '';
    if (p.sold) out += `<rect x="${x.toFixed(1)}" y="${(zero - p.sold * unit).toFixed(1)}" width="${barW.toFixed(1)}" height="${(p.sold * unit).toFixed(1)}" rx="1.5" fill="var(--bar)">${title}</rect>`;
    if (p.refunded) out += `<rect x="${x.toFixed(1)}" y="${zero.toFixed(1)}" width="${barW.toFixed(1)}" height="${(p.refunded * unit).toFixed(1)}" rx="1.5" fill="var(--refund)">${title}</rect>`;
    if (i % labelEvery === 0) {
      const text = view.byMonth ? p.key : p.key.slice(5);
      out += `<text x="${((i + 0.5) * step).toFixed(1)}" y="${H - 6}" text-anchor="middle">${esc(text)}</text>`;
    }
    return out;
  }).join('');
  return `<section class="chart"><h2>${view.byMonth ? '每月售出' : '每天售出'}</h2><svg viewBox="0 0 ${W} ${H}" role="img" aria-label="售出和退款份数"><line x1="0" x2="${W}" y1="${zero.toFixed(1)}" y2="${zero.toFixed(1)}" stroke="var(--line)"/>${bars}</svg><div class="legend">峰值 ${maxUp} 份，退款画在线下</div></section>`;
}

function splitTable(view, title, rows, nameOf) {
  if (!rows.length) return '';
  const body = rows.map((r) => `<tr><td>${esc(nameOf(r.key))}</td><td>${int(r.sold)}</td><td${r.refunded ? ' class="refund"' : ''}>${int(r.refunded)}</td><td>${money(r.gross, view.currency)}</td><td>${money(r.proceeds, view.currency)}</td></tr>`).join('');
  return `<section><h2>${esc(title)}</h2><div class="scroll"><table><thead><tr><th scope="col"></th><th scope="col">售出</th><th scope="col">退款</th><th scope="col">销售额</th><th scope="col">到手</th></tr></thead><tbody>${body}</tbody></table></div></section>`;
}

function channels(view) {
  const a = view.analytics;
  if (!a.available) {
    return '<section><h2>购买渠道</h2><p class="empty">已向 Apple 申请渠道报告，首批生成后这里会显示搜索、浏览、网页跳转各带来多少购买</p></section>';
  }
  const hasPurchases = a.funnel.purchases > 0;
  const rows = a.sources.filter((s) => s.purchases || s.downloads || s.pageViews).map((s) => `<tr><td>${esc(sourceLabel(s.type))}</td><td>${int(s.purchases)}</td><td>${int(s.downloads)}</td><td>${int(s.pageViews)}</td>${hasPurchases ? `<td>${money(s.proceeds, view.currency)}</td>` : ''}</tr>`).join('');
  const table = rows
    ? `<div class="scroll"><table><thead><tr><th scope="col"></th><th scope="col">购买</th><th scope="col">首次下载</th><th scope="col">产品页浏览</th>${hasPurchases ? '<th scope="col">到手</th>' : ''}</tr></thead><tbody>${rows}</tbody></table></div>`
    : '<p class="empty">这段时间 Apple 的渠道报告里没有记录</p>';
  const details = a.details.filter((d) => d.purchases || d.downloads).map((d) => `<tr><td>${esc(d.info)} <small>${esc(sourceLabel(d.type))}</small></td><td>${int(d.purchases)}</td><td>${int(d.downloads)}</td></tr>`).join('');
  const detailTable = details ? `<h2 style="margin:22px 0 12px">来源明细</h2><div class="scroll"><table><thead><tr><th scope="col"></th><th scope="col">购买</th><th scope="col">首次下载</th></tr></thead><tbody>${details}</tbody></table></div>` : '';
  const f = a.funnel;
  const u = a.usage;
  const funnel = (f.impressions || f.pageViews) ? `<p class="line">曝光 ${int(f.impressions)}，产品页浏览 ${int(f.pageViews)}，首次下载 ${int(f.firstDownloads)}，购买 ${int(f.purchases)}</p>` : '';
  const usage = (u.installs || u.deletions || u.sessions) ? `<p class="line">安装 ${int(u.installs)}，卸载 ${int(u.deletions)}，打开 ${int(u.sessions)} 次</p>` : '';
  const coverage = a.coverage ? `<p class="line">渠道报告覆盖 ${esc(a.coverage.from)} 到 ${esc(a.coverage.to)}${a.pending ? `，还有 ${int(a.pending)} 份待下次同步` : ''}</p>` : '';
  return `<section><h2>购买渠道</h2>${table}${funnel}${usage}${coverage}${detailTable}</section>`;
}

function refundsSection(view) {
  if (!view.refunds.length) return '';
  const body = view.refunds.map((r) => `<tr><td>${esc(r.date)}</td><td>${esc(country(r.country))}</td><td>${esc(r.device)}</td><td>${esc(r.version)}</td><td>${r.units}</td><td class="refund">${money(r.price * r.units, r.currency)}</td></tr>`).join('');
  return `<section><h2>退款明细</h2><div class="scroll"><table><thead><tr><th scope="col"></th><th scope="col">国家和地区</th><th scope="col">设备</th><th scope="col">版本</th><th scope="col">份数</th><th scope="col">金额</th></tr></thead><tbody>${body}</tbody></table></div></section>`;
}

function financeSection(view) {
  if (!view.finance.length) return '';
  const body = view.finance.map((f) => `<tr><td>${esc(f.start)} 到 ${esc(f.end)}</td><td>${int(f.units)}</td><td>${money(f.amount, view.currency)}${f.unconverted ? ' <small>部分货币未折算</small>' : ''}</td></tr>`).join('');
  return `<section><h2>Apple 结算月</h2><div class="scroll"><table><thead><tr><th scope="col"></th><th scope="col">净份数</th><th scope="col">到手</th></tr></thead><tbody>${body}</tbody></table></div></section>`;
}

function storeSection(view) {
  if (!view.store.length) return '';
  const body = view.store.map((s) => {
    const label = STATE_LABELS[s.state] || s.state;
    const since = s.submitted ? `${shanghai(s.submitted)} 提交` : '';
    return `<tr><td>${esc(PLATFORM_LABELS[s.platform] || s.platform)}</td><td>${esc(s.version)}</td><td>${esc(label)}</td><td>${esc(since)}</td></tr>`;
  }).join('');
  return `<section><h2>App Store 状态</h2><div class="scroll"><table><tbody>${body}</tbody></table></div></section>`;
}

function reviewsSection(view) {
  if (!view.reviews.length) return '';
  const items = view.reviews.map((r) => `<div class="review"><div class="head"><span class="stars" aria-label="${esc(r.rating)} 星">${'★'.repeat(Math.max(0, Math.min(5, Number(r.rating) || 0)))}</span><span>${esc(r.title)}</span><span class="meta">${esc(r.nickname)}，${esc(country(iso3to2(r.territory)))}，${esc(String(r.created || '').slice(0, 10))}</span></div><p>${esc(r.body)}</p></div>`).join('');
  return `<section><h2>评论</h2>${items}</section>`;
}

// customerReviews reports territories as alpha-3; the region names want alpha-2.
const ALPHA3 = { CHN: 'CN', USA: 'US', TWN: 'TW', HKG: 'HK', JPN: 'JP', KOR: 'KR', GBR: 'GB', DEU: 'DE', FRA: 'FR', CAN: 'CA', AUS: 'AU', SGP: 'SG', RUS: 'RU', ESP: 'ES', ITA: 'IT', NLD: 'NL', VNM: 'VN', COL: 'CO' };
function iso3to2(code) {
  return ALPHA3[code] || code;
}

function controls(view) {
  const link = (r, c, text, on) => `<a href="/payroom?r=${encodeURIComponent(r)}&amp;c=${c}"${on ? ' aria-current="true"' : ''}>${esc(text)}</a>`;
  const presets = [['all', '全部'], ['90d', '90 天'], ['30d', '30 天'], ['7d', '7 天']];
  const ranges = presets.map(([r, t]) => link(r, view.currency, t, view.range === r)).join('');
  const options = view.months.map((m) => `<option value="m:${esc(m)}"${view.range === `m:${m}` ? ' selected' : ''}>${esc(m)}</option>`).join('');
  const month = options ? `<form method="get" action="/payroom" style="margin:0"><input type="hidden" name="c" value="${esc(view.currency)}"><select name="r" aria-label="按月" onchange="this.form.submit()"><option value="">按月</option>${options}</select></form>` : '';
  const currencies = ['CNY', 'USD'].map((c) => link(view.range, c, c, view.currency === c)).join('');
  return `<nav class="controls">${ranges}${month}<span class="gap"></span>${currencies}</nav>`;
}

function renderDashboard(view) {
  const t = view.totals;
  const sync = [view.latestSalesDate ? `销售数据到 ${esc(view.latestSalesDate)}` : '', view.syncedAt ? `${esc(shanghai(view.syncedAt))} 同步` : '', view.fxAt ? `金额按 ${esc(fxDate(view.fxAt))} 汇率折算` : ''].filter(Boolean).join('，');
  const warnings = [...view.errors];
  if (view.syncStale) warnings.push('超过 12 小时没有同步成功，下面的数字可能不是最新的');
  if (view.trafficStale) warnings.push(`官网统计 ${view.trafficStale} 之后没有新数据，流量数字只算到这一天`);
  if (t.unconverted) warnings.push(`有 ${t.unconverted} 份的货币没有汇率，金额里没算`);
  const warn = warnings.length ? `<div class="warn">${warnings.map((w) => `<div>${esc(w)}</div>`).join('')}</div>` : '';
  const extras = [t.free ? `兑换码和免费 ${int(t.free)}` : '', t.redownload ? `重新下载 ${int(t.redownload)}` : '', t.update ? `更新 ${int(t.update)}` : ''].filter(Boolean).join('，');
  const metric = (label, value, note = '') => `<div class="metric"><div class="label">${esc(label)}</div><div class="value">${value}</div>${note ? `<div class="note">${note}</div>` : ''}</div>`;
  const isAll = view.range === 'all';
  const latest = view.latest;
  const metrics = [
    metric(isAll ? '累计到手' : '到手', money(t.proceeds, view.currency), `销售额 ${money(t.net, view.currency)}`),
    metric(isAll ? '累计售出' : '售出', `${int(t.sold)} 份`, t.refunded ? `退款 ${int(t.refunded)} 份，退款率 ${percent(t.refundRate)}` : '没有退款'),
    metric('最新入账', latest ? money(latest.proceeds, view.currency) : '没有', latest ? `${esc(latest.date)} 售出 ${int(latest.units)} 份` : ''),
    metric(isAll ? '官网累计访问' : '官网访问', view.traffic.available ? int(view.traffic.sessions) : '没有', view.traffic.available ? `页面浏览 ${int(view.traffic.views)}` : ''),
  ].join('');
  const body = `<main><header class="top"><h1>妙言 Payroom</h1><span class="sync">${sync}</span></header>${controls(view)}<p class="range">${esc(view.from)} 到 ${esc(view.to)}</p>${warn}<div class="metrics">${metrics}</div>${recentSection(view)}${chart(view)}${trafficSection(view)}${channels(view)}${splitTable(view, '设备', view.devices, (k) => k)}${splitTable(view, '国家和地区', view.countries, country)}${refundsSection(view)}${financeSection(view)}${storeSection(view)}${reviewsSection(view)}${extras ? `<p class="line">${extras}</p>` : ''}</main>`;
  return shell('妙言 Payroom', body);
}

module.exports = { esc, renderDashboard, renderLogin };
