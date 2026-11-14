'use strict';

// Payroom's HTML. Server-rendered with no client framework: range and currency
// are plain links, and every value from Apple or a reviewer goes through esc().

const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

const CSS = `
:root{color-scheme:light;--bg:#f5f4ed;--panel:#fffefa;--panel-3:#f9f6ee;--ink:#141413;--muted:#504e49;--subtle:#6b6a64;--line:#eae6da;--accent:#1B365D;--accent-soft:#EEF2F7;--danger:#9f3f2f;--serif:Charter,Georgia,"Times New Roman",serif;--sans:-apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC",sans-serif;font-family:var(--sans)}
*{box-sizing:border-box}
html{-webkit-text-size-adjust:100%}
body{margin:0;background:var(--bg);color:var(--ink);min-height:100vh;-webkit-font-smoothing:antialiased;-moz-osx-font-smoothing:grayscale;font-variant-numeric:tabular-nums}
a{color:inherit}
h1,h2,p{margin:0}
h1,h2{font-family:var(--serif)}
h1{font-size:36px;line-height:1.05;margin-top:6px;letter-spacing:0}
h2{font-size:20px;line-height:28px;letter-spacing:0}
.topbar{display:flex;flex-wrap:wrap;align-items:center;gap:12px 24px;padding:28px clamp(18px,4vw,54px) 8px}
.brand{display:flex;flex-wrap:wrap;align-items:baseline;gap:4px 24px;min-width:0}
.window-note{color:var(--subtle);font-size:11px;font-style:normal}
.filters{display:flex;flex-wrap:wrap;justify-content:flex-end;align-items:center;gap:10px 12px;margin-left:auto}
.switch{display:flex;min-height:30px;overflow:hidden;border:1px solid var(--line);border-radius:8px;background:var(--panel)}
.switch a{display:flex;align-items:center;min-height:28px;padding:0 10px;color:var(--muted);font-size:11px;font-weight:650;letter-spacing:.02em;text-decoration:none;white-space:nowrap;transition:background-color .12s ease-out,color .12s ease-out}
.switch a+a{border-left:1px solid var(--line)}
.switch a:hover{color:var(--accent)}
.switch a[aria-current=true]{background:var(--accent-soft);color:var(--accent);font-weight:750}
.month{margin:0}
.month select:focus,.month select:focus-visible{outline:none}
.month select{width:62px;appearance:none;-webkit-appearance:none;min-height:30px;border:1px solid var(--line);border-radius:8px;padding:0 26px 0 10px;background-color:var(--panel);background-image:url("data:image/svg+xml;charset=utf-8,%3Csvg xmlns='http://www.w3.org/2000/svg' width='10' height='6' viewBox='0 0 10 6'%3E%3Cpath d='M1 1l4 4 4-4' fill='none' stroke='%236b6a64' stroke-width='1.5' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E");background-repeat:no-repeat;background-position:right 8px center;color:var(--muted);font:inherit;font-size:11px;font-weight:650;cursor:pointer}
.month select[data-active=true]{width:70px;background-color:var(--accent-soft);border-color:var(--accent-soft);color:var(--accent);font-weight:750}
main{padding:12px clamp(18px,4vw,54px) 42px;display:grid;gap:12px}
.metrics{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px}
.metric,.panel{background:var(--panel);border:1px solid var(--line);border-radius:8px}
.metric{min-height:126px;padding:16px;display:grid;align-content:space-between;gap:10px}
.metric>span,.metric>em,.head p{color:var(--muted);font-style:normal;font-size:13px;line-height:1.45}
.metric strong{font-family:var(--serif);font-size:28px;line-height:1.12;white-space:nowrap}
.panel{padding:18px;display:grid;gap:8px;min-width:0;align-content:start}
.board{display:grid;grid-template-columns:repeat(12,minmax(0,1fr));gap:12px}
.board>.panel{grid-column:span 12}
.s4{--span:4}.s5{--span:5}.s6{--span:6}.s7{--span:7}.s8{--span:8}
.panel:not(.open) .more{display:none}
.more-btn{justify-self:start;min-height:30px;padding:0;border:0;background:none;color:var(--accent);font:inherit;font-size:13px;cursor:pointer}
.panel.open .more-btn{display:none}
.scroll{max-width:100%;overflow-x:auto;overscroll-behavior-x:contain;-webkit-overflow-scrolling:touch}
table{width:100%;border-collapse:collapse;font-size:13px;line-height:18px}
th,td{min-width:64px;padding:7px 0 7px 20px;text-align:right;vertical-align:middle;white-space:nowrap}
th{color:var(--muted);font-size:11px;font-weight:650}
th:first-child,td:first-child{width:100%;min-width:0;text-align:left;padding-left:0;white-space:normal}
td.refund{color:var(--danger)}
td small{color:var(--subtle);font-size:12px}
.note{color:var(--muted);font-size:13px;line-height:1.45;padding:12px;border:1px solid var(--line);border-radius:7px;background:var(--panel-3)}
.note div+div{margin-top:2px}
.line,.empty{color:var(--muted);font-size:13px;line-height:1.45}
.chart-frame{display:flex;height:240px;padding:36px 8px 0;gap:0;background:var(--panel-3);border:1px solid color-mix(in srgb,var(--line) 76%,transparent);border-radius:6px;overflow:hidden}
.chart-col{position:relative;flex:1 1 0;min-width:0;display:grid;grid-template-rows:var(--up) var(--down) 24px;justify-items:center}
.chart-up,.chart-down{position:relative;width:100%;display:flex;justify-content:center}
.chart-up{align-items:flex-end}
.chart-down{align-items:flex-start;border-top:1px solid color-mix(in srgb,var(--ink) 18%,transparent)}
.chart-bar{display:block;width:min(52%,26px);min-width:1px;background:color-mix(in srgb,var(--accent) 18%,transparent)}
.chart-bar.refund{background:color-mix(in srgb,var(--danger) 50%,transparent)}
.chart-value{position:absolute;left:50%;transform:translateX(-50%);padding-bottom:3px;color:var(--subtle);font-size:11px;line-height:1.2;text-align:center;white-space:nowrap}
.chart-tick{align-self:center;color:var(--subtle);font-size:12px;white-space:nowrap}
.review{padding:10px 0}
.review+.review{border-top:1px solid var(--line)}
.review .top{display:flex;flex-wrap:wrap;gap:2px 10px;font-size:13px}
.review .stars{color:var(--accent)}
.review .meta{color:var(--subtle);font-size:12px}
.review p{margin-top:4px;font-size:13px;line-height:1.5;color:var(--muted);white-space:pre-wrap;overflow-wrap:anywhere}
.range-select{display:none}
.login-shell{min-height:100vh;display:grid;place-items:center;padding:24px}
.login-card{width:min(440px,100%);background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:40px 36px;display:grid;gap:18px}
.login-card p{color:var(--muted);font-size:15px;line-height:1.5}
.login-card .login-error{color:var(--danger);background:#fff1ed;border:1px solid #f0c3b5;border-radius:7px;padding:10px}
.login-card input,.login-card button{width:100%;min-height:48px;font:inherit;font-size:16px;border:1px solid var(--line);border-radius:6px;padding:0 12px}
.login-card input{background:var(--panel);color:var(--ink)}
.login-card input::placeholder{color:var(--subtle)}
.login-card input:focus,.login-card input:focus-visible{outline:none}
.login-card button{background:var(--ink);border-color:var(--ink);color:#fffdf7;font-weight:650;cursor:pointer}
@media (min-width:1081px){.board>.panel[class*=" s"]{grid-column:span var(--span)}}
@media (max-width:900px){.metrics{grid-template-columns:repeat(2,minmax(0,1fr))}}
@media (max-width:760px){.chart-value.dense{display:none}}
@media (max-width:640px){h1{font-size:22px;margin-top:3px}.topbar{padding:14px 12px 2px}main{padding:8px 12px 28px;gap:10px}.metrics{gap:8px}.metric{min-height:74px;padding:10px 12px;gap:4px}.metric strong{font-size:22px}.metric>span,.metric>em{font-size:12px}.panel{padding:14px;gap:14px}table{font-size:12px}th,td{min-width:48px;padding:6px 0 6px 12px}.filters{margin-left:0;justify-content:flex-start}.month select{width:76px;font-size:16px;font-weight:400}.month select[data-active=true]{width:108px}.chart-value,.chart-tick.alt,.wide-only{display:none}.login-card{padding:28px 22px}.topbar{flex-wrap:wrap;gap:8px}.switch a{padding:0 8px}.brand{display:contents}.sync{display:none}.filters{order:1;margin-left:auto;justify-content:flex-end;gap:8px}.switch.range,.month{display:none}.range-select{display:block;appearance:none;-webkit-appearance:none;min-height:30px;border:1px solid var(--line);border-radius:8px;padding:0 22px 0 10px;background:var(--panel) url("data:image/svg+xml;charset=utf-8,%3Csvg xmlns='http://www.w3.org/2000/svg' width='10' height='6' viewBox='0 0 10 6'%3E%3Cpath d='M1 1l4 4 4-4' fill='none' stroke='%236b6a64' stroke-width='1.5' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E") no-repeat right 8px center;color:var(--accent);font:inherit;font-size:16px}.range-select:focus,.range-select:focus-visible{outline:none}.board{gap:10px}.day td:first-child{max-width:0}.day td small{display:block;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}}
`;

function shell(title, body) {
  return `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="theme-color" content="#f5f4ed"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow,noarchive"><title>${esc(title)}</title><link rel="icon" href="/favicon.ico" sizes="32x32"><link rel="icon" href="/assets/icon-64.png" type="image/png" sizes="64x64"><link rel="apple-touch-icon" href="/assets/icon-180.png"><style>${CSS}</style></head><body>${body}</body></html>`;
}

function renderLogin({ failed = false, unconfigured = false } = {}) {
  const note = unconfigured ? '<p class="login-error">还没有配置密码。</p>' : failed ? '<p class="login-error">密码不正确。</p>' : '';
  return shell('妙言 Payroom', `<main class="login-shell"><form class="login-card" method="post" action="/payroom"><h1>Payroom</h1><p>输入私有密码，查看妙言的售卖数据。</p>${note}<input name="password" type="password" placeholder="密码" aria-label="密码" autocomplete="current-password" autofocus required><button type="submit">打开面板</button></form></main>`);
}

function renderMessage(line) {
  return shell('妙言 Payroom', `<main class="login-shell"><section class="login-card"><h1>Payroom</h1><p>${esc(line)}</p></section></main>`);
}

const countryNames = new Intl.DisplayNames(['zh-CN'], { type: 'region' });
const SHORT_REGIONS = { HK: '香港', MO: '澳门', TW: '台湾' };
function country(code) {
  if (SHORT_REGIONS[code]) return SHORT_REGIONS[code];
  try { return countryNames.of(code) || code; } catch { return code; }
}

// Keyed in lower case: the real reports say `App Store search`, the docs
// `App Store Search`, and both must read the same.
const SOURCE_LABELS = {
  'app store search': 'App Store 搜索',
  'app store browse': 'App Store 浏览',
  'app referrer': '其他 App 跳转',
  'web referrer': '网页跳转',
  'app clip': 'App Clip',
  'institutional purchase': '机构购买',
  unavailable: '未知',
  other: '其他',
};
const sourceLabel = (t) => SOURCE_LABELS[String(t).toLowerCase()] || t;

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
  return new Intl.NumberFormat('zh-CN', { style: 'currency', currency, currencyDisplay: 'narrowSymbol', minimumFractionDigits: digits, maximumFractionDigits: digits }).format(value);
}
const compactMoney = (v, c) => money(v, c).replace(/\.\d+$/, '');
const percent = (v) => (v === null || v === undefined ? '' : `${(v * 100).toFixed(1).replace(/\.0$/, '')}%`);
const int = (v) => new Intl.NumberFormat('en-US').format(Math.round(v));
const shanghai = (iso) => new Intl.DateTimeFormat('zh-CN', { timeZone: 'Asia/Shanghai', month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit', hour12: false }).format(new Date(iso));

const updatedAt = (iso) => new Intl.DateTimeFormat('sv-SE', { timeZone: 'Asia/Shanghai', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' }).format(new Date(iso));

// A long list shows its first rows and opens the rest in place, so no panel
// scrolls inside the page.
const FOLD = { day: 14, review: 3, refund: 5, finance: 6, traffic: 10, country: 12 };
const fold = (kind, i) => (i >= FOLD[kind] ? ' class="more"' : '');
const moreButton = (kind, n, unit) => (n > FOLD[kind] ? `<button type="button" class="more-btn" onclick="this.closest('.panel').classList.add('open')">展开全部 ${int(n)} ${unit}</button>` : '');

const cell = (n, cls = '') => (n ? `<td${cls ? ` class="${cls}"` : ''}>${int(n)}</td>` : '<td></td>');

// Where a day's units went, as one phrase per country and device.
const dayMix = (mix) => mix.map((m) => `${country(m.country)} ${m.device} ${int(m.units)}`).join('、');

function recentSection(view) {
  if (!view.recent.length) return '';
  const rows = view.recent.map((d, i) => {
    const date = view.from.slice(0, 4) !== view.to.slice(0, 4) ? d.date.slice(2) : d.date.slice(5);
    if (d.known) {
      const mix = d.mix.length ? ` <small>${esc(dayMix(d.mix))}</small>` : '';
      return `<tr${fold('day', i)}><td>${esc(date)}${mix}</td>${cell(d.sold)}${cell(d.refunded, 'refund')}<td>${money(d.proceeds, view.currency)}</td></tr>`;
    }
    if (d.estimate) {
      return `<tr${fold('day', i)}><td>${esc(date)} <small>按渠道报告估算</small></td><td>约 ${int(d.estimate.purchases)}</td><td></td><td>约 ${money(d.estimate.proceeds, view.currency)}</td></tr>`;
    }
    return `<tr${fold('day', i)}><td>${esc(date)} <small>等 Apple 报表</small></td><td></td><td></td><td></td></tr>`;
  }).join('');
  return `<section class="panel day s7"><h2>每天销量</h2><div class="scroll"><table><thead><tr><th scope="col">日期</th><th scope="col">售出</th><th scope="col">退款</th><th scope="col">到手</th></tr></thead><tbody>${rows}</tbody></table></div>${moreButton('day', view.recent.length, '天')}</section>`;
}

const sourceName = (s) => (s === '(direct)' ? '直接打开' : s === '(not set)' ? '未知' : s);

function trafficSection(view) {
  const t = view.traffic;
  if (!t.available || !t.sources.length) return '';
  const rows = t.sources.map((s, i) => `<tr${fold('traffic', i)}><td>${esc(sourceName(s.source))}</td><td>${int(s.count)}</td></tr>`).join('');
  return `<section class="panel s4"><h2>官网流量来源</h2><div class="scroll"><table><thead><tr><th scope="col">来源</th><th scope="col">访问</th></tr></thead><tbody>${rows}</tbody></table></div>${moreButton('traffic', t.sources.length, '个')}</section>`;
}

function chart(view) {
  const pts = view.series;
  if (!pts.some((p) => p.sold || p.refunded)) return '';
  const maxUp = Math.max(1, ...pts.map((p) => p.sold));
  const maxDown = Math.max(0, ...pts.map((p) => p.refunded));
  const total = maxUp + maxDown;
  const every = Math.max(1, Math.ceil(pts.length / 12));
  const showValues = pts.length <= 31;
  const dense = pts.length > 12;
  const columns = pts.map((p, i) => {
    const value = showValues && p.sold ? `<span class="chart-value${dense ? ' dense' : ''}" style="bottom:${(p.sold / maxUp * 100).toFixed(1)}%">${dense ? '' : `${esc(compactMoney(p.proceeds, view.currency))}<br>`}${int(p.sold)} 份</span>` : '';
    const up = p.sold ? `<i class="chart-bar" style="height:${(p.sold / maxUp * 100).toFixed(1)}%"></i>` : '';
    const down = p.refunded ? `<i class="chart-bar refund" style="height:${(p.refunded / Math.max(1, maxDown) * 100).toFixed(1)}%"></i>` : '';
    const tick = i % every === 0 ? esc(view.byMonth ? p.key.slice(2) : p.key.slice(5)) : '';
    const title = `${p.key} 售出 ${p.sold}${p.refunded ? `，退款 ${p.refunded}` : ''}，到手 ${money(p.proceeds, view.currency)}`;
    return `<div class="chart-col" title="${esc(title)}"><div class="chart-up">${up}${value}</div><div class="chart-down">${down}</div><span class="chart-tick${i % (every * 2) ? ' alt' : ''}">${tick}</span></div>`;
  }).join('');
  const best = pts.reduce((a, b) => (b.proceeds > a.proceeds ? b : a), pts[0]);
  const unit = view.byMonth ? '单月' : '单日';
  const caption = best.proceeds > 0 ? `<p>${unit}最高 ${esc(money(best.proceeds, view.currency))}（${esc(best.key)}）</p>` : '';
  return `<section class="panel"><div class="head"><h2>收入走势</h2>${caption}</div><div class="chart-frame" role="img" aria-label="售出和退款份数" style="--up:calc((100% - 24px) * ${(maxUp / total).toFixed(4)});--down:calc((100% - 24px) * ${(maxDown / total).toFixed(4)})">${columns}</div></section>`;
}

function splitTable(view, title, rows, nameOf, head, order, kind) {
  if (!rows.length) return '';
  const body = rows.map((r, i) => `<tr${kind ? fold(kind, i) : ''}><td>${esc(nameOf(r.key))}</td>${cell(r.sold)}${cell(r.refunded, 'refund')}<td>${money(r.gross, view.currency)}</td><td>${money(r.proceeds, view.currency)}</td></tr>`).join('');
  return `<section class="panel ${order}"><h2>${esc(title)}</h2><div class="scroll"><table><thead><tr><th scope="col">${esc(head)}</th><th scope="col">售出</th><th scope="col">退款</th><th scope="col">销售额</th><th scope="col">到手</th></tr></thead><tbody>${body}</tbody></table></div>${kind ? moreButton(kind, rows.length, '个') : ''}</section>`;
}

function channels(view) {
  const a = view.analytics;
  if (!a.available) {
    return '';
  }
  const hasPurchases = a.funnel.purchases > 0;
  const rows = a.sources.filter((s) => s.purchases || s.downloads || s.pageViews).map((s) => `<tr><td>${esc(sourceLabel(s.type))}</td><td>${int(s.purchases)}</td><td>${int(s.downloads)}</td><td>${int(s.pageViews)}</td>${hasPurchases ? `<td>${money(s.proceeds, view.currency)}</td>` : ''}</tr>`).join('');
  const table = rows
    ? `<div class="scroll"><table><thead><tr><th scope="col">渠道</th><th scope="col">购买</th><th scope="col">首次下载</th><th scope="col">产品页浏览</th>${hasPurchases ? '<th scope="col">到手</th>' : ''}</tr></thead><tbody>${rows}</tbody></table></div>`
    : '<p class="empty">这段时间 Apple 的渠道报告里没有记录</p>';
  const f = a.funnel;
  const u = a.usage;
  const funnel = (f.impressions || f.pageViews) ? `<p class="line">曝光 ${int(f.impressions)}，产品页浏览 ${int(f.pageViews)}，首次下载 ${int(f.firstDownloads)}，购买 ${int(f.purchases)}</p>` : '';
  const usage = (u.installs || u.deletions || u.sessions) ? `<p class="line">安装 ${int(u.installs)}，卸载 ${int(u.deletions)}，打开 ${int(u.sessions)} 次</p>` : '';
  const coverage = a.coverage ? `<p class="line">渠道报告覆盖 ${esc(a.coverage.from)} 到 ${esc(a.coverage.to)}${a.pending ? `，还有 ${int(a.pending)} 份待下次同步` : ''}</p>` : '';
  return `<section class="panel s7"><h2>购买渠道</h2>${table}${funnel}${usage}${coverage}</section>`;
}

function refundsSection(view) {
  if (!view.refunds.length) return '';
  const body = view.refunds.map((r, i) => `<tr${fold('refund', i)}><td>${esc(r.date)}</td><td>${esc(country(r.country))}</td><td>${esc(r.device)}</td><td class="wide-only">${esc(r.version)}</td><td class="wide-only">${r.units}</td><td class="refund">${money(r.price * r.units, r.currency)}</td></tr>`).join('');
  return `<section class="panel s6"><h2>退款明细</h2><div class="scroll"><table><thead><tr><th scope="col">日期</th><th scope="col">国家和地区</th><th scope="col">设备</th><th scope="col" class="wide-only">版本</th><th scope="col" class="wide-only">份数</th><th scope="col">金额</th></tr></thead><tbody>${body}</tbody></table></div>${moreButton('refund', view.refunds.length, '笔')}</section>`;
}

function financeSection(view) {
  if (!view.finance.length) return '';
  const body = view.finance.map((f, i) => `<tr${fold('finance', i)}><td>${esc(f.start)} 到 ${esc(f.end)}</td><td>${int(f.units)}</td><td>${money(f.amount, view.currency)}${f.unconverted ? ' <small>部分货币未折算</small>' : ''}</td></tr>`).join('');
  return `<section class="panel s6"><h2>Apple 结算月</h2><div class="scroll"><table><thead><tr><th scope="col">结算周期</th><th scope="col">净份数</th><th scope="col">到手</th></tr></thead><tbody>${body}</tbody></table></div>${moreButton('finance', view.finance.length, '个月')}</section>`;
}

function storeSection(view) {
  const body = view.store.map((s) => {
    const label = STATE_LABELS[s.state] || s.state;
    const since = s.submitted ? shanghai(s.submitted) : '';
    return `<tr><td>${esc(PLATFORM_LABELS[s.platform] || s.platform)}</td><td>${esc(s.version)}</td><td>${esc(label)}</td><td class="wide-only">${esc(since)}</td></tr>`;
  }).join('');
  const status = body ? `<div class="scroll"><table><thead><tr><th scope="col">平台</th><th scope="col">版本</th><th scope="col">状态</th><th scope="col" class="wide-only">提交时间</th></tr></thead><tbody>${body}</tbody></table></div>` : '';
  return status ? `<section class="panel s6"><h2>App Store</h2>${status}</section>` : '';
}

function otherDownloadsSection(view) {
  const t = view.totals;
  const others = [['兑换码和免费', t.free], ['重新下载', t.redownload], ['更新', t.update]].filter(([, n]) => n);
  if (!others.length) return '';
  return `<section class="panel s6"><h2>其他下载</h2><div class="scroll"><table><thead><tr><th scope="col">类型</th><th scope="col">次数</th></tr></thead><tbody>${others.map(([k, n]) => `<tr><td>${esc(k)}</td><td>${int(n)}</td></tr>`).join('')}</tbody></table></div></section>`;
}

function reviewsSection(view) {
  if (!view.reviews.length) return '';
  const items = view.reviews.map((r, i) => `<div class="review${i >= FOLD.review ? ' more' : ''}"><div class="top"><span class="stars" aria-label="${esc(r.rating)} 星">${'★'.repeat(Math.max(0, Math.min(5, Number(r.rating) || 0)))}</span><span>${esc(r.title)}</span><span class="meta">${esc(r.nickname)}，${esc(country(iso3to2(r.territory)))}，${esc(String(r.created || '').slice(0, 10))}</span></div><p>${esc(r.body)}</p></div>`).join('');
  return `<section class="panel s8"><h2>评论</h2><div class="scroll">${items}</div>${moreButton('review', view.reviews.length, '条')}</section>`;
}

// customerReviews reports territories as alpha-3; the region names want alpha-2.
const ALPHA3 = { CHN: 'CN', USA: 'US', TWN: 'TW', HKG: 'HK', JPN: 'JP', KOR: 'KR', GBR: 'GB', DEU: 'DE', FRA: 'FR', CAN: 'CA', AUS: 'AU', SGP: 'SG', RUS: 'RU', ESP: 'ES', ITA: 'IT', NLD: 'NL', VNM: 'VN', COL: 'CO' };
function iso3to2(code) {
  return ALPHA3[code] || code;
}

function controls(view) {
  const link = (r, c, text, on) => `<a href="/payroom?r=${encodeURIComponent(r)}&amp;c=${c}"${on ? ' aria-current="true"' : ''}>${esc(text)}</a>`;
  const presets = [['all', '全部'], ['90d', '近90天'], ['30d', '近30天'], ['7d', '近7天']];
  const ranges = presets.map(([r, t]) => link(r, view.currency, t, view.range === r)).join('');
  const inMonth = view.range.startsWith('m:');
  // A month reads 2611: 2026-11 did not fit the desktop select and cost the
  // phone header its one row.
  const options = view.months.map((m) => `<option value="m:${esc(m)}"${view.range === `m:${m}` ? ' selected' : ''}>${esc(m.slice(2).replace('-', ''))}</option>`).join('');
  const month = options ? `<form class="month" method="get" action="/payroom"><input type="hidden" name="c" value="${esc(view.currency)}"><select name="r" aria-label="按月"${inMonth ? ' data-active="true"' : ''} onchange="this.form.submit()"><option value="">按月</option>${options}</select></form>` : '';
  const pick = presets.map(([r, t]) => `<option value="${r}"${view.range === r ? ' selected' : ''}>${esc(t)}</option>`).join('');
  const phone = `<form method="get" action="/payroom"><input type="hidden" name="c" value="${esc(view.currency)}"><select class="range-select" name="r" aria-label="日期" onchange="this.form.submit()">${pick}${options ? `<optgroup label="按月">${options}</optgroup>` : ''}</select></form>`;
  const currencies = ['CNY', 'USD'].map((c) => link(view.range, c, c, view.currency === c)).join('');
  return `<nav class="filters">${phone}<div class="switch range" role="group" aria-label="日期">${ranges}</div>${month}<div class="switch" role="group" aria-label="金额显示币种">${currencies}</div></nav>`;
}

function renderDashboard(view) {
  const t = view.totals;
  const stamp = view.syncedAt ? `更新于 ${updatedAt(view.syncedAt)}` : '';
  const sync = [stamp, view.latestSalesDate ? `销售数据到 ${view.latestSalesDate.slice(5)}` : '', view.usdCny ? `汇率 ${view.usdCny.toFixed(2)}` : ''].filter(Boolean).map((t) => `<em class="window-note">${esc(t)}</em>`).join(' ');
  const warnings = [...view.errors];
  if (view.syncStale) warnings.push('超过 3 小时没有同步成功，下面的数字可能不是最新的');
  if (t.unconverted) warnings.push(`有 ${t.unconverted} 份的货币没有汇率，金额里没算`);
  const warn = warnings.length ? `<div class="note">${warnings.map((w) => `<div>${esc(w)}</div>`).join('')}</div>` : '';
  const metric = (label, value, note = '') => `<article class="metric"><span>${esc(label)}</span><strong>${value}</strong><em>${note}</em></article>`;
  const isAll = view.range === 'all';
  const latest = view.latest;
  const p = view.pulse;
  // The previous window's own figure: early windows sold a handful, so a
  // percentage reads +1643% and says nothing.
  const delta = (prev, what = '上期') => `${what} ${prev}`;
  // The first half of a note gives way on phones, its dot with it.
  const lead = (text, rest) => (rest ? `<span class="wide-only">${text} · </span>${rest}` : text);
  const f = view.analytics.funnel;
  const m = p.month;
  const monthName = m ? (m.month === view.today.slice(0, 7) ? '本月' : `${Number(m.month.slice(5))} 月`) : '';
  // Apple's sales report reaches the previous Pacific day at best, so the newest
  // day leads (maintainer 2026-11-14 asked for today's sales on top).
  const metrics = [
    metric('最新入账', latest ? money(latest.proceeds, view.currency) : '没有', latest ? `${esc(latest.date.slice(5))} 售出 ${int(latest.units)} 份` : ''),
    metric(isAll ? '累计到手' : '到手', money(t.proceeds, view.currency), p.prev ? lead(`销售额 ${money(t.net, view.currency)}`, delta(money(p.prev.proceeds, view.currency))) : `销售额 ${money(t.net, view.currency)}${isAll ? `<span class="wide-only"> · 自 ${esc(view.from.slice(2))}</span>` : ''}`),
    metric(isAll ? '累计售出' : '售出', `${int(t.sold)} 份`, p.prev ? lead(`退款 ${int(t.refunded)}`, delta(`${int(p.prev.sold)} 份`)) : (t.refunded ? `退款 ${int(t.refunded)} 份 · ${percent(t.refundRate)}` : '没有退款')),
    metric(`${monthName}到手`, m ? money(m.cur.proceeds, view.currency) : '没有', m ? lead(`${int(m.cur.sold)} 份`, m.prev ? delta(money(m.prev.proceeds, view.currency), '上月同期') : '') : ''),
    metric('日均到手', p.daily ? money(p.daily.proceeds, view.currency) : '没有', p.daily ? `日均 ${p.daily.sold.toFixed(1).replace(/\.0$/, '')} 份` : ''),
    metric('产品页转化', f.pageViews ? percent(f.purchases / f.pageViews) : '没有', f.pageViews ? `浏览 ${int(f.pageViews)} · 购买 ${int(f.purchases)}` : ''),
    metric('App Store 曝光', f.impressions ? int(f.impressions) : '没有', f.impressions ? `点进产品页 ${percent(f.pageViews / f.impressions)}` : ''),
    metric(isAll ? '官网累计访问' : '官网访问', view.traffic.available ? int(view.traffic.sessions) : '没有', view.traffic.available ? (p.trafficPrev ? lead(`页面浏览 ${int(view.traffic.views)}`, delta(int(p.trafficPrev))) : `页面浏览 ${int(view.traffic.views)}`) : ''),
  ].join('');
  // Pairs share a row on wide screens; a pair missing one half lets the other
  // take the row.
  const pair = (a, b) => (a && b ? a + b : (a || b).replace(/class="panel([^"]*) s\d/, 'class="panel$1'));
  const panels = [
    chart(view),
    pair(recentSection(view), splitTable(view, '国家和地区', view.countries, country, '国家和地区', 's5', 'country')),
    pair(channels(view), splitTable(view, '设备', view.devices, (k) => k, '设备', 's5')),
    pair(trafficSection(view), reviewsSection(view)),
    pair(refundsSection(view), financeSection(view)),
    pair(storeSection(view), otherDownloadsSection(view)),
  ].join('');
  // A select is as wide as its longest option; size it to the chosen one.
  const fit = `<script>document.querySelectorAll('.range-select').forEach((s)=>{const st=getComputedStyle(s);const m=document.createElement('span');m.textContent=s.options[s.selectedIndex].text;m.style.cssText='position:absolute;visibility:hidden;white-space:pre';['fontFamily','fontSize','fontWeight','fontVariantNumeric','letterSpacing'].forEach((k)=>{m.style[k]=st[k];});document.body.appendChild(m);s.style.width=Math.ceil(m.getBoundingClientRect().width+parseFloat(st.paddingLeft)+parseFloat(st.paddingRight)+parseFloat(st.borderLeftWidth)+parseFloat(st.borderRightWidth)+1)+'px';m.remove();});</script>`;
  const body = `<header class="topbar"><div class="brand"><h1>Payroom</h1><div class="sync">${sync}</div></div>${controls(view)}</header><main>${warn}<div class="metrics">${metrics}</div><div class="board">${panels}</div></main>${fit}`;
  return shell('妙言 Payroom', body);
}

module.exports = { esc, renderDashboard, renderLogin, renderMessage };
