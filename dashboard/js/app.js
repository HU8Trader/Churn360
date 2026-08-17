/* ============================================================
   Customer 360 - Churn Intelligence Dashboard
   App logic: theme engine, slicers, KPIs, Chart.js rendering, Q&A

   THEME CONTRAST PHILOSOPHY
   -------------------------
   * Dark theme  -> light / neon colors for charts, grids & text
                    (bright on dark glass) - holographic look.
   * Light theme -> deep / saturated colors for charts & text
                    (dark on white) - Apple-like clarity.
   Charts are rebuilt on every theme change & page switch.
   Only the ACTIVE page's charts are mounted (hidden canvases
   cannot be measured by Chart.js -> 0x0 donut bug is gone).
   ============================================================ */

/* ---------- Constants & state ---------- */
const DATA = window.CHURN_DATA || [];
const $ = (id) => document.getElementById(id);

const state = {
  theme: 'dark',
  page: 'overview',
  filters: { gender: 'All', contract: 'All', internet: 'All', pay: 'All', tenure: 'All', churn: 'All' },
};

let charts = {}; // active Chart instances (one page at a time)

let geoMap = null;   // Leaflet instance (Geography page)
let geoLayer = null; // marker layer group
let geoTiles = null; // basemap tile layer (theme-aware)

/* ---------- Theme-aware color systems ---------- */
/* BRIGHT / LIGHT palette - used on DARK holographic theme */
const DARK_PALETTE = ['#2bff9e', '#22d3ee', '#86efac', '#fde047', '#fb7185', '#a78bfa', '#38bdf8', '#fb923c', '#a3e635', '#f472b6'];
/* DEEP / SATURATED palette - used on LIGHT Apple theme */
const LIGHT_PALETTE = ['#047857', '#0e7490', '#15803d', '#b45309', '#be123c', '#6d28d9', '#1d4ed8', '#c2410c', '#4d7c0f', '#db2777'];

function palette() { return state.theme === 'dark' ? DARK_PALETTE : LIGHT_PALETTE; }
function paletteAt(i) { const p = palette(); return p[i % p.length]; }

/* Churn status colors - always the strongest contrast for the theme */
function churnColors() {
  return state.theme === 'dark'
    ? { churned: '#fb7185', active: '#2bff9e' }
    : { churned: '#be123c', active: '#047857' };
}

const TENURE_BANDS = [
  { label: '0-6', test: (t) => t >= 0 && t <= 6 },
  { label: '7-12', test: (t) => t >= 7 && t <= 12 },
  { label: '13-24', test: (t) => t >= 13 && t <= 24 },
  { label: '25-48', test: (t) => t >= 25 && t <= 48 },
  { label: '49-72', test: (t) => t >= 49 },
];

const SCORE_BANDS = [
  { label: '0-19', test: (s) => s >= 0 && s < 20 },
  { label: '20-39', test: (s) => s >= 20 && s < 40 },
  { label: '40-59', test: (s) => s >= 40 && s < 60 },
  { label: '60-79', test: (s) => s >= 60 && s < 80 },
  { label: '80-100', test: (s) => s >= 80 },
];

const SERVICES = [
  { key: 'phone', name: 'Phone Service' },
  { key: 'mlines', name: 'Multiple Lines' },
  { key: 'internet', name: 'Internet Service' },
  { key: 'osec', name: 'Online Security' },
  { key: 'oback', name: 'Online Backup' },
  { key: 'dprot', name: 'Device Protection' },
  { key: 'tech', name: 'Tech Support' },
  { key: 'stv', name: 'Streaming TV' },
  { key: 'smov', name: 'Streaming Movies' },
];

const CATEGORY_OF = { phone: 'Phone', mlines: 'Phone', internet: 'Internet', osec: 'Add-on', oback: 'Add-on', dprot: 'Add-on', tech: 'Add-on', stv: 'Streaming', smov: 'Streaming' };
const CONTRACTS = ['Month-to-month', 'One year', 'Two year'];
const PAYS = ['Electronic check', 'Mailed check', 'Credit card (automatic)', 'Bank transfer (automatic)'];

/* ---------- Small utils ---------- */
const nf0 = new Intl.NumberFormat('en-US');
const nf2 = new Intl.NumberFormat('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const fmtMoney = (v) => '$' + nf0.format(Math.round(v));
const fmtPct = (v) => nf2.format(v) + '%';
const intOf = (r) => (r.internet === 'DSL' || r.internet === 'Fiber optic') ? r.internet : 'No';

function isSubscribed(row, key) {
  if (key === 'phone') return row.phone === 1;
  if (key === 'internet') return intOf(row) !== 'No';
  if (key === 'mlines') return row.mlines === 'Yes';
  return row[key] === 'Yes';
}
function tenureBand(t) { return (TENURE_BANDS.find((b) => b.test(t)) || { label: '49-72' }).label; }
function scoreBand(s) { return (SCORE_BANDS.find((b) => b.test(s)) || { label: '80-100' }).label; }

function matchesWith(row, f) {
  if (f.gender !== 'All' && row.gender !== f.gender) return false;
  if (f.contract !== 'All' && row.contract !== f.contract) return false;
  if (f.internet !== 'All' && intOf(row) !== f.internet) return false;
  if (f.pay !== 'All' && row.pay !== f.pay) return false;
  if (f.tenure !== 'All' && tenureBand(row.tenure) !== f.tenure) return false;
  if (f.churn !== 'All') {
    const isChurned = row.churn === 'Yes';
    if (f.churn === 'Churned' && !isChurned) return false;
    if (f.churn === 'Active' && isChurned) return false;
  }
  return true;
}
function filtered(excludeKey) {
  const f = Object.assign({}, state.filters);
  if (excludeKey) f[excludeKey] = 'All';
  return DATA.filter((r) => matchesWith(r, f));
}
function churned(r) { return r.churn === 'Yes'; }
function churnRateOf(rows) { return rows.length ? 100 * rows.filter(churned).length / rows.length : 0; }

/* ---------- Theme ---------- */
function applyTheme(theme, persist) {
  state.theme = theme;
  document.documentElement.setAttribute('data-theme', theme);
  $('iconSun').style.display = theme === 'light' ? '' : 'none';
  $('iconMoon').style.display = theme === 'dark' ? '' : 'none';
  if (persist) localStorage.setItem('churn-theme', theme);
  /* Force Chart.js defaults to theme contrast - legend text, axis text,
     gridlines & any default labels ALWAYS match the theme (light-on-dark
     in dark theme, dark-on-light in light theme). */
  if (window.Chart) {
    Chart.defaults.color = cssVar('--text');
    Chart.defaults.borderColor = cssVar('--grid');
    Chart.defaults.font.family = cssVar('--font');
  }
}
function cssVar(name) { return getComputedStyle(document.documentElement).getPropertyValue(name).trim(); }
function themeMode() { return state.theme; }

/* ---------- Slicers ---------- */
function buildSlicers() {
  const defs = [
    { key: 'gender', values: ['All', 'Male', 'Female'], labelOf: (v) => v },
    { key: 'contract', values: ['All'].concat(CONTRACTS), labelOf: (v) => v },
    { key: 'internet', values: ['All', 'DSL', 'Fiber optic', 'No'], labelOf: (v) => v },
    { key: 'pay', values: ['All'].concat(PAYS), labelOf: (v) => v.replace(' (automatic)', ' · Auto') },
    { key: 'tenure', values: ['All'].concat(TENURE_BANDS.map((b) => b.label)), labelOf: (v) => v === 'All' ? 'All' : v + ' mo' },
    { key: 'churn', values: ['All', 'Churned', 'Active'], labelOf: (v) => v },
  ];
  defs.forEach((def) => {
    const box = $(`slicer-${def.key}`);
    if (!box) return;
    box.innerHTML = '';
    const base = filtered(def.key);
    def.values.forEach((v) => {
      let count = base.length;
      if (def.key === 'gender') count = base.filter((r) => r.gender === v).length;
      else if (def.key === 'contract') count = base.filter((r) => r.contract === v).length;
      else if (def.key === 'internet') count = base.filter((r) => intOf(r) === v).length;
      else if (def.key === 'pay') count = base.filter((r) => r.pay === v).length;
      else if (def.key === 'tenure') count = base.filter((r) => tenureBand(r.tenure) === v).length;
      else if (def.key === 'churn') count = v === 'All' ? base.length : base.filter((r) => (v === 'Churned' ? churned(r) : !churned(r))).length;
      const b = document.createElement('button');
      b.className = 'chip' + (state.filters[def.key] === v ? ' active' : '');
      b.innerHTML = def.labelOf(v) + (v === 'All' ? '' : ` <span class="count">${nf0.format(count)}</span>`);
      b.onclick = () => {
        state.filters[def.key] = state.filters[def.key] === v ? 'All' : v;
        renderAll();
      };
      box.appendChild(b);
    });
  });
}

/* ---------- KPI cards (page-specific business KPIs) ---------- */
const ICONS = {
  users: '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
  trend: '<path d="M3 17l6-6 4 4 8-8"/><path d="M15 7h6v6"/>',
  coin: '<path d="M12 2v20M17 6.5c0-1.5-2-2.5-5-2.5s-5 1-5 2.5S8 9 12 9s5 1 5 2.5S14 14 12 14s-5-1-5-2.5"/>',
  diamond: '<path d="M12 2a7 7 0 0 0-4 12.7V16h8v-1.3A7 7 0 0 0 12 2Z"/><path d="M9 19h6M10 22h4"/>',
  bill: '<path d="M6 2h12v20l-3-2-3 2-3-2-3 2Z"/><path d="M9 8h6M9 12h6"/>',
  piggy: '<path d="M21 12V7H5a2 2 0 0 1 0-4h14v4"/><path d="M3 5v14a2 2 0 0 0 2 2h16v-5"/><path d="M18 12a2 2 0 0 0 0 4h4v-4Z"/>',
  userX: '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M17 8l5 5M22 8l-5 5"/>',
  gauge: '<path d="M12 14l4-5"/><path d="M3.3 15a9 9 0 1 1 17.4 0"/>',
  alert: '<path d="M12 9v4M12 17h.01"/><path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0Z"/>',
  chat: '<path d="M4 5h16v11H9l-5 4Z"/><circle cx="9.5" cy="10.5" r="0.6" fill="currentColor"/><circle cx="12.5" cy="10.5" r="0.6" fill="currentColor"/><circle cx="15.5" cy="10.5" r="0.6" fill="currentColor"/>',
  grid: '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
  stack: '<path d="M12 2 3 7l9 5 9-5Z"/><path d="M3 12l9 5 9-5"/><path d="M3 17l9 5 9-5"/>',
  shield: '<path d="M12 2 20 6v6c0 5-3.5 8.5-8 10-4.5-1.5-8-5-8-10V6Z"/><path d="M9 12l2 2 4-4"/>',
  play: '<circle cx="12" cy="12" r="9"/><path d="M10 8l6 4-6 4Z"/>',
  lock: '<rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
  scale: '<path d="M12 3v18M7 21h10"/><path d="M5 7l14 4"/><path d="M5 7 2.5 13a3 3 0 0 0 5 0Z"/><path d="M19 11l2.5 6a3 3 0 0 1-5 0Z"/>',
  contract: '<path d="M4 4h16v16H4Z"/><path d="M8 8h8M8 12h5"/>',
  mapPin: '<path d="M12 2a7 7 0 0 0-4 12.7V16h8v-1.3A7 7 0 0 0 12 2Z"/><circle cx="12" cy="9" r="2.2"/>',
  city: '<path d="M3 21V9l6-3v15M9 12h4M13 9V3l5 3v15M3 21h18"/>',
  hash: '<path d="M4 9h16M4 15h16M10 3 8 21M16 3l-2 18"/>',
  building: '<rect x="4" y="3" width="12" height="18"/><path d="M16 9h4v12"/><path d="M8 7h1M11 7h1M8 11h1M11 11h1M8 15h1M11 15h1"/>',
};

function kpiCard({ label, value, sub, icon, small }) {
  return `<div class="kpi"><div class="kpi-glow"></div><div class="kpi-top"><span class="kpi-label">${label}</span><span class="kpi-icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${icon}</svg></span></div><div class="kpi-value${small ? ' small' : ''}">${value}</div><div class="kpi-sub">${sub}</div></div>`;
}

/* OVERVIEW - market snapshot */
function kpiOverview(rows) {
  const total = rows.length;
  const churners = rows.filter(churned).length;
  const monthly = rows.reduce((s, r) => s + (r.monthly || 0), 0);
  const lifetime = rows.reduce((s, r) => s + (r.total || 0), 0);
  const avgMonthly = total ? monthly / total : 0;
  const avgCltv = total ? rows.reduce((s, r) => s + (r.cltv || 0), 0) / total : 0;
  return [
    { label: 'Total Customers', value: nf0.format(total), sub: 'segmented base', icon: ICONS.users },
    { label: 'Churn Rate', value: fmtPct(100 * churners / (total || 1)), sub: nf0.format(churners) + ' churned', icon: ICONS.trend },
    { label: 'Monthly Revenue', value: fmtMoney(monthly), sub: 'recurring / mo', icon: ICONS.coin },
    { label: 'Avg Monthly Charge', value: fmtMoney(avgMonthly), sub: 'per customer / mo', icon: ICONS.bill },
    { label: 'Avg CLTV', value: fmtMoney(avgCltv), sub: 'lifetime value', icon: ICONS.diamond },
    { label: 'Lifetime Revenue', value: fmtMoney(lifetime), sub: 'total billed', icon: ICONS.piggy },
  ].map(kpiCard).join('');
}

/* CHURN - churn drivers & risk */
function kpiChurn(rows) {
  const total = rows.length;
  const churners = rows.filter(churned).length;
  const actives = total - churners;
  const rate = total ? 100 * churners / total : 0;
  const avgScore = total ? rows.reduce((s, r) => s + (r.score || 0), 0) / total : 0;
  const hiRiskActive = rows.filter((r) => !churned(r) && (r.score || 0) >= 70).length;
  const atRisk = rows.filter(churned).reduce((s, r) => s + (r.monthly || 0), 0);
  const reasonMap = groupSum(rows.filter(churned), (r) => r.reason || 'Unknown', () => 1);
  const top = [...reasonMap.entries()].sort((a, b) => b[1] - a[1])[0];
  return [
    { label: 'Churned Customers', value: nf0.format(churners), sub: fmtPct(rate) + ' of base', icon: ICONS.userX },
    { label: 'Active Customers', value: nf0.format(actives), sub: 'still subscribed', icon: ICONS.users },
    { label: 'Avg Churn Score', value: nf0.format(Math.round(avgScore)), sub: 'model risk · 0-100', icon: ICONS.gauge },
    { label: 'High-Risk · Active', value: nf0.format(hiRiskActive), sub: 'score ≥ 70, not churned', icon: ICONS.alert },
    { label: 'Revenue at Risk', value: fmtMoney(atRisk), sub: 'monthly, churned base', icon: ICONS.coin },
    { label: 'Top Churn Reason', value: top ? top[0] : '—', sub: top ? nf0.format(top[1]) + ' customers' : '', icon: ICONS.chat, small: true },
  ].map(kpiCard).join('');
}

/* SERVICES - adoption & retention */
function kpiServices(rows) {
  const total = rows.length;
  const subs = (k) => rows.filter((r) => isSubscribed(r, k)).length;
  const allSubs = SERVICES.reduce((s, svc) => s + subs(svc.key), 0);
  const avgAddons = total ? rows.reduce((s, r) => s + ['osec', 'oback', 'dprot', 'tech'].filter((k) => isSubscribed(r, k)).length, 0) / total : 0;
  const svcRates = SERVICES.map((s) => { const g = rows.filter((r) => isSubscribed(r, s.key)); return { name: s.name, rate: g.length ? 100 * g.filter(churned).length / g.length : 0, n: g.length }; }).sort((a, b) => b.rate - a.rate);
  const best = svcRates[svcRates.length - 1];
  const worst = svcRates[0];
  const stream = rows.filter((r) => isSubscribed(r, 'stv') || isSubscribed(r, 'smov')).length;
  const suite = rows.filter((r) => ['osec', 'oback', 'dprot', 'tech'].some((k) => isSubscribed(r, k))).length;
  return [
    { label: 'Active Subscriptions', value: nf0.format(allSubs), sub: 'across 9 services', icon: ICONS.grid },
    { label: 'Avg Add-ons / Customer', value: nf2.format(avgAddons), sub: 'security · support', icon: ICONS.stack },
    { label: 'Best Retaining Service', value: best.name, sub: fmtPct(best.rate) + ' churn · ' + nf0.format(best.n) + ' users', icon: ICONS.shield, small: true },
    { label: 'At-Risk Service', value: worst.name, sub: fmtPct(worst.rate) + ' churn · ' + nf0.format(worst.n) + ' users', icon: ICONS.alert, small: true },
    { label: 'Streaming Adoption', value: fmtPct(100 * stream / (total || 1)), sub: nf0.format(stream) + ' customers', icon: ICONS.play },
    { label: 'Security Suite', value: fmtPct(100 * suite / (total || 1)), sub: nf0.format(suite) + ' customers', icon: ICONS.lock },
  ].map(kpiCard).join('');
}

/* REVENUE - value & monetization */
function kpiRevenue(rows) {
  const total = rows.length;
  const monthly = rows.reduce((s, r) => s + (r.monthly || 0), 0);
  const lifetime = rows.reduce((s, r) => s + (r.total || 0), 0);
  const avgMonthly = total ? monthly / total : 0;
  const avgCltv = total ? rows.reduce((s, r) => s + (r.cltv || 0), 0) / total : 0;
  const topContract = CONTRACTS.map((c) => { const g = rows.filter((r) => r.contract === c); return { c, rev: g.reduce((s, r) => s + (r.monthly || 0), 0), n: g.length }; }).sort((a, b) => b.rev - a.rev)[0];
  const mult = avgMonthly > 0 ? avgCltv / avgMonthly : 0;
  return [
    { label: 'Monthly Revenue', value: fmtMoney(monthly), sub: 'recurring charges', icon: ICONS.coin },
    { label: 'Lifetime Revenue', value: fmtMoney(lifetime), sub: 'total billed', icon: ICONS.piggy },
    { label: 'Avg Monthly Charge', value: fmtMoney(avgMonthly), sub: 'per customer / mo', icon: ICONS.bill },
    { label: 'Avg CLTV', value: fmtMoney(avgCltv), sub: 'lifetime value', icon: ICONS.diamond },
    { label: 'Top Revenue Contract', value: topContract.c, sub: fmtMoney(topContract.rev) + ' · ' + nf0.format(topContract.n) + ' customers', icon: ICONS.contract, small: true },
    { label: 'CLTV × Monthly', value: nf2.format(mult) + '×', sub: 'customer value multiple', icon: ICONS.scale },
  ].map(kpiCard).join('');
}

/* GEOGRAPHY - market footprint */
function kpiGeography(rows) {
  const states = new Set(), cities = new Set(), cityMap = new Map(), zipMap = new Map();
  rows.forEach((r) => {
    if (r.state) states.add(r.state);
    if (r.city) cities.add(r.city);
    const c = r.city || 'Unknown'; let a = cityMap.get(c); if (!a) { a = { n: 0, ch: 0 }; cityMap.set(c, a); } a.n += 1; a.ch += churned(r) ? 1 : 0;
    const lat = Number(r.lat), lng = Number(r.lng);
    if (isFinite(lat) && isFinite(lng)) { const k = String(r.zip == null ? '0' : r.zip); let z = zipMap.get(k); if (!z) { z = { zip: k, n: 0, ch: 0 }; zipMap.set(k, z); } z.n += 1; z.ch += churned(r) ? 1 : 0; }
  });
  const citiesArr = [...cityMap.entries()].map(([name, a]) => ({ name, n: a.n, rate: 100 * a.ch / a.n })).sort((x, y) => y.n - x.n);
  const zipsArr = [...zipMap.values()].map((z) => { z.rate = 100 * z.ch / z.n; return z; }).sort((x, y) => y.n - x.n);
  const topCity = citiesArr[0];
  const topZip = zipsArr[0];
  const hotCity = citiesArr.filter((c) => c.n >= 10).sort((a, b) => b.rate - a.rate)[0];
  return [
    { label: 'States Covered', value: nf0.format(states.size), sub: 'regional footprint', icon: ICONS.mapPin },
    { label: 'Cities', value: nf0.format(cities.size), sub: 'urban spread', icon: ICONS.city },
    { label: 'Zip Codes', value: nf0.format(zipsArr.length), sub: 'field locations', icon: ICONS.hash },
    { label: 'Top City', value: topCity ? topCity.name : '—', sub: topCity ? nf0.format(topCity.n) + ' customers' : '', icon: ICONS.building, small: true },
    { label: 'Top Zip', value: topZip ? topZip.zip : '—', sub: topZip ? nf0.format(topZip.n) + ' customers · ' + fmtPct(topZip.rate) + ' churn' : '', icon: ICONS.hash, small: true },
    { label: 'High-Churn City', value: hotCity ? hotCity.name : '—', sub: hotCity ? fmtPct(hotCity.rate) + ' churn · ' + nf0.format(hotCity.n) + ' customers' : '', icon: ICONS.alert, small: true },
  ].map(kpiCard).join('');
}

function buildKPI(rows) {
  const fns = { overview: kpiOverview, churn: kpiChurn, services: kpiServices, revenue: kpiRevenue, geography: kpiGeography };
  $('kpiGrid').innerHTML = (fns[state.page] || kpiOverview)(rows);
}

/* ---------- Chart.js infrastructure ---------- */
function baseOptions(type, opts = {}) {
  const accent = cssVar('--accent');
  const text = cssVar('--text');
  const muted = cssVar('--muted');
  const grid = cssVar('--grid');
  const font = cssVar('--font');
  const isDark = themeMode() === 'dark';
  const tooltipBg = isDark ? 'rgba(3, 18, 11, 0.97)' : 'rgba(255, 255, 255, 0.98)';
  const tooltipBorder = isDark ? 'rgba(43,255,158,0.5)' : 'rgba(0,0,0,0.08)';

  return {
    responsive: true,
    maintainAspectRatio: false,
    interaction: { mode: 'index', intersect: false },
    animation: { duration: 650, easing: 'easeOutQuart' },
    plugins: {
      legend: { display: !!opts.legend, position: 'bottom', labels: { color: text, font: { family: font, size: 12, weight: 600 }, boxWidth: 11, boxHeight: 11, usePointStyle: true, pointStyle: 'circle', padding: 16 } },
      tooltip: {
        enabled: true,
        backgroundColor: tooltipBg,
        borderColor: tooltipBorder,
        borderWidth: 1,
        titleColor: text,
        bodyColor: text,
        padding: 12,
        cornerRadius: 10,
        displayColors: true,
        boxPadding: 4,
        titleFont: { family: font, weight: 700, size: 13 },
        bodyFont: { family: font, weight: 600, size: 13 },
        callbacks: opts.tooltip || {},
      },
    },
    scales: (type === 'pie' || type === 'doughnut') ? undefined : {
      x: { grid: { color: 'transparent' }, border: { color: grid }, ticks: { color: muted, font: { family: font, size: 11 }, maxRotation: 0, autoSkip: true }, title: opts.xTitle ? { display: true, text: opts.xTitle, color: muted, font: { family: font, size: 11, weight: 700 } } : undefined },
      y: { beginAtZero: true, grid: { color: grid }, border: { display: false }, ticks: { color: muted, font: { family: font, size: 11 }, callback: opts.yTick || undefined }, title: opts.yTitle ? { display: true, text: opts.yTitle, color: muted, font: { family: font, size: 11, weight: 700 } } : undefined },
    },
  };
}

/* Center-text plugin for doughnut charts */
const centerTotal = {
  id: 'centerTotal',
  afterDraw(chart) {
    if (!chart.config.options.centerText) return;
    const { ctx, chartArea } = chart;
    const c = chart.config.options.centerText;
    const cx = (chartArea.left + chartArea.right) / 2;
    const cy = (chartArea.top + chartArea.bottom) / 2;
    ctx.save();
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.font = '800 20px ' + cssVar('--font');
    ctx.fillStyle = cssVar('--text');
    ctx.fillText(c.value, cx, cy - 9);
    ctx.font = '600 11px ' + cssVar('--font');
    ctx.fillStyle = cssVar('--muted');
    ctx.fillText(c.label, cx, cy + 15);
    ctx.restore();
  },
};

function makeChart(id, config) {
  if (charts[id]) { charts[id].destroy(); delete charts[id]; }
  const canvas = $(id);
  if (!canvas) return;
  charts[id] = new Chart(canvas, config);
  window.__charts = charts;
  canvas.dataset.legendColor = (config.options && config.options.plugins && config.options.plugins.legend && config.options.plugins.legend.labels) ? config.options.plugins.legend.labels.color : '';
  canvas.dataset.chartType = config.type;
}

/* Theme-consistent doughnut options: ring colors, borders, legend w/ % */
function donutConfig({ data, labels, center, legendLabels }) {
  const border = cssVar('--panel');
  const text = cssVar('--text');
  const font = cssVar('--font');
  const opts = baseOptions('doughnut', { legend: true });
  opts.cutout = '64%';
  opts.centerText = center;
  opts.plugins.legend = {
    display: true, position: 'bottom',
    labels: {
      color: text, usePointStyle: true, pointStyle: 'circle', padding: 16,
      font: { family: font, size: 12, weight: 600 },
      labelTextColor: () => text,
      generateLabels: (chart) => chart.data.labels.map((l, i) => ({
        text: legendLabels ? legendLabels[i] : l,
        fillStyle: chart.data.datasets[0].backgroundColor[i],
        strokeStyle: 'transparent', pointStyle: 'circle', hidden: false,
      })),
    },
  };
  return {
    type: 'doughnut',
    data: { labels, datasets: [{ data, backgroundColor: labels.map((_, i) => paletteAt(i)), borderColor: border, borderWidth: 3, hoverOffset: 12 }] },
    options: opts,
    plugins: [centerTotal],
  };
}

/* ---------- Aggregation helpers ---------- */
function groupSum(rows, keyFn, valFn) { const m = new Map(); rows.forEach((r) => { const k = keyFn(r); m.set(k, (m.get(k) || 0) + valFn(r)); }); return m; }

/* ---------- RENDER: OVERVIEW page ---------- */
function renderOverview(rows) {
  /* 1) Churn by contract - doughnut (churned share) */
  const cData = CONTRACTS.map((c) => {
    const grp = rows.filter((r) => r.contract === c);
    return { total: grp.length, churners: grp.filter(churned).length, rate: churnRateOf(grp) };
  });
  const cDonut = donutConfig({
    labels: CONTRACTS,
    data: cData.map((d) => d.churners),
    center: { value: nf0.format(rows.length), label: 'customers' },
    legendLabels: CONTRACTS.map((c, i) => `${c}  ·  ${fmtPct(100 * cData[i].churners / (cData[i].total || 1))}`),
  });
  cDonut.options.plugins.tooltip.callbacks.label = (ctx) => {
    const d = cData[ctx.dataIndex];
    return ` ${nf0.format(d.churners)} churned · ${nf0.format(d.total)} total · ${fmtPct(d.rate)}`;
  };
  makeChart('chartContractDonut', cDonut);

  /* 2) Churn rate by tenure - bar */
  const tenureRates = TENURE_BANDS.map((b) => {
    const grp = rows.filter((r) => b.test(r.tenure));
    return { rate: churnRateOf(grp), ch: grp.filter(churned).length, total: grp.length };
  });
  makeChart('chartTenureBar', {
    type: 'bar',
    data: { labels: TENURE_BANDS.map((b) => b.label), datasets: [{ data: tenureRates.map((d) => d.rate), backgroundColor: TENURE_BANDS.map((_, i) => paletteAt(i)), borderRadius: 10, maxBarThickness: 46 }] },
    options: { ...baseOptions('bar', { yTitle: 'Churn rate (%)' }), plugins: { ...baseOptions('bar').plugins, tooltip: { ...baseOptions('bar').plugins.tooltip, callbacks: { label: (ctx) => ` Churn rate ${fmtPct(ctx.parsed.y)} · ${nf0.format(tenureRates[ctx.dataIndex].ch)} of ${nf0.format(tenureRates[ctx.dataIndex].total)} churned` } } } },
  });

  /* 3) Churn rate by payment method - horizontal bar */
  const payRates = PAYS.map((p) => {
    const grp = rows.filter((r) => r.pay === p);
    return { rate: churnRateOf(grp), ch: grp.filter(churned).length, total: grp.length };
  });
  makeChart('chartPayBar', {
    type: 'bar',
    data: { labels: PAYS.map((p) => p.replace(' (automatic)', ' · Auto')), datasets: [{ data: payRates.map((d) => d.rate), backgroundColor: PAYS.map((_, i) => paletteAt(i)), borderRadius: 10, maxBarThickness: 40 }] },
    options: {
      indexAxis: 'y',
      ...baseOptions('bar', { xTitle: 'Churn rate (%)' }),
      scales: { ...baseOptions('bar').scales, x: { ...baseOptions('bar').scales.x, beginAtZero: true }, y: { ...baseOptions('bar').scales.y, grid: { color: 'transparent' } } },
      plugins: { ...baseOptions('bar').plugins, tooltip: { ...baseOptions('bar').plugins.tooltip, callbacks: { label: (ctx) => ` ${fmtPct(ctx.parsed.x)} · ${nf0.format(payRates[ctx.dataIndex].ch)} of ${nf0.format(payRates[ctx.dataIndex].total)}` } } },
    },
  });

  /* 4) Avg monthly by tenure - line with gradient area */
  const monthlySeries = TENURE_BANDS.map((b) => {
    const grp = rows.filter((r) => b.test(r.tenure));
    return grp.length ? grp.reduce((s, r) => s + (r.monthly || 0), 0) / grp.length : 0;
  });
  const accent = cssVar('--accent');
  const accent2 = cssVar('--accent-2');
  makeChart('chartMonthlyLine', {
    type: 'line',
    data: { labels: TENURE_BANDS.map((b) => b.label), datasets: [{ data: monthlySeries, borderColor: accent, backgroundColor: (context) => { const c = context.chart.ctx; const a = context.chart.chartArea; if (!a) return 'transparent'; const g = c.createLinearGradient(0, a.top, 0, a.bottom); g.addColorStop(0, accent + (themeMode() === 'dark' ? '55' : '22')); g.addColorStop(1, accent + '00'); return g; }, tension: 0.45, fill: true, pointBackgroundColor: accent, pointBorderColor: cssVar('--panel'), pointRadius: 4, pointHoverRadius: 7, borderWidth: 3 }] },
    options: { ...baseOptions('line', { yTitle: 'USD' }), plugins: { ...baseOptions('line').plugins, tooltip: { ...baseOptions('line').plugins.tooltip, callbacks: { label: (ctx) => ` Avg monthly ${fmtMoney(ctx.parsed.y)}` } } } },
  });
}

/* ---------- RENDER: CHURN page ---------- */
function renderChurn(rows) {
  const cc = churnColors();
  const churners = rows.filter(churned).length;
  const actives = rows.length - churners;
  const rate = rows.length ? 100 * churners / rows.length : 0;

  /* 1) Churn status doughnut */
  makeChart('chartStatusDonut', donutConfig({
    labels: ['Active', 'Churned'],
    data: [actives, churners],
    center: { value: fmtPct(rate), label: 'churn rate' },
    legendLabels: [`Active  (${fmtPct(100 * actives / (rows.length || 1))})`, `Churned  (${fmtPct(rate)})`],
  }));
  /* override status ring colors to success/danger for clarity */
  const sd = charts.chartStatusDonut;
  if (sd) { sd.data.datasets[0].backgroundColor = [cc.active, cc.churned]; sd.update(); }

  /* 2) Internet service mix doughnut */
  const intVals = ['Fiber optic', 'DSL', 'No'];
  const intCounts = intVals.map((v) => rows.filter((r) => intOf(r) === v).length);
  const intTotal = intCounts.reduce((a, b) => a + b, 0) || 1;
  makeChart('chartInternetDonut', donutConfig({
    labels: intVals,
    data: intCounts,
    center: { value: nf0.format(intTotal), label: 'customers' },
    legendLabels: intVals.map((v, i) => `${v}  ·  ${fmtPct(100 * intCounts[i] / intTotal)}`),
  }));

  /* 3) Top churn reasons - horizontal bar */
  const reasonMap = groupSum(rows.filter(churned), (r) => r.reason || 'Unknown', () => 1);
  const reasons = [...reasonMap.entries()].sort((a, b) => b[1] - a[1]).slice(0, 10);
  makeChart('chartReasonBar', {
    type: 'bar',
    data: { labels: reasons.map((r) => r[0]), datasets: [{ data: reasons.map((r) => r[1]), backgroundColor: reasons.map((_, i) => paletteAt(i)), borderRadius: 8, maxBarThickness: 24 }] },
    options: {
      indexAxis: 'y',
      ...baseOptions('bar', { xTitle: 'Customers' }),
      scales: { ...baseOptions('bar').scales, x: { ...baseOptions('bar').scales.x, beginAtZero: true }, y: { ...baseOptions('bar').scales.y, grid: { color: 'transparent' } } },
      plugins: { ...baseOptions('bar').plugins, tooltip: { ...baseOptions('bar').plugins.tooltip, callbacks: { label: (ctx) => ` ${nf0.format(ctx.parsed.x)} customers` } } },
    },
  });

  /* 4) Churn score distribution - histogram */
  const scoreCounts = SCORE_BANDS.map((b) => rows.filter((r) => b.test(r.score)).length);
  makeChart('chartScoreHist', {
    type: 'bar',
    data: { labels: SCORE_BANDS.map((b) => b.label), datasets: [{ data: scoreCounts, backgroundColor: SCORE_BANDS.map((_, i) => paletteAt(i)), borderRadius: 10, maxBarThickness: 46 }] },
    options: { ...baseOptions('bar', { yTitle: 'Customers' }), plugins: { ...baseOptions('bar').plugins, tooltip: { ...baseOptions('bar').plugins.tooltip, callbacks: { label: (ctx) => ` ${nf0.format(ctx.parsed.y)} customers` } } } },
  });
}

/* ---------- RENDER: SERVICES page ---------- */
function renderServices(rows) {
  /* 1) Service adoption - horizontal bar */
  const adopt = SERVICES.map((s) => rows.filter((r) => isSubscribed(r, s.key)).length);
  makeChart('chartServiceAdopt', {
    type: 'bar',
    data: { labels: SERVICES.map((s) => s.name), datasets: [{ data: adopt, backgroundColor: SERVICES.map((_, i) => paletteAt(i)), borderRadius: 10, maxBarThickness: 26 }] },
    options: {
      indexAxis: 'y',
      ...baseOptions('bar', { xTitle: 'Subscribers' }),
      scales: { ...baseOptions('bar').scales, x: { ...baseOptions('bar').scales.x, beginAtZero: true }, y: { ...baseOptions('bar').scales.y, grid: { color: 'transparent' } } },
      plugins: { ...baseOptions('bar').plugins, tooltip: { ...baseOptions('bar').plugins.tooltip, callbacks: { label: (ctx) => ` ${nf0.format(ctx.parsed.x)} subscribers` } } },
    },
  });

  /* 2) Churn rate by service - horizontal bar */
  const svcChurn = SERVICES.map((s) => {
    const grp = rows.filter((r) => isSubscribed(r, s.key));
    return { rate: churnRateOf(grp), ch: grp.filter(churned).length, total: grp.length };
  });
  makeChart('chartServiceChurn', {
    type: 'bar',
    data: { labels: SERVICES.map((s) => s.name), datasets: [{ data: svcChurn.map((d) => d.rate), backgroundColor: SERVICES.map((_, i) => paletteAt(i)), borderRadius: 10, maxBarThickness: 26 }] },
    options: {
      indexAxis: 'y',
      ...baseOptions('bar', { xTitle: 'Churn rate (%)' }),
      scales: { ...baseOptions('bar').scales, x: { ...baseOptions('bar').scales.x, beginAtZero: true }, y: { ...baseOptions('bar').scales.y, grid: { color: 'transparent' } } },
      plugins: { ...baseOptions('bar').plugins, tooltip: { ...baseOptions('bar').plugins.tooltip, callbacks: { label: (ctx) => ` ${fmtPct(ctx.parsed.x)} · ${nf0.format(svcChurn[ctx.dataIndex].ch)} of ${nf0.format(svcChurn[ctx.dataIndex].total)}` } } },
    },
  });

  /* 3) Service categories doughnut - REAL donut now (visible page render) */
  const cats = ['Phone', 'Internet', 'Add-on', 'Streaming'];
  const catCounts = cats.map((c) => SERVICES.reduce((s, svc) => s + (CATEGORY_OF[svc.key] === c ? rows.filter((r) => isSubscribed(r, svc.key)).length : 0), 0));
  const catTotal = catCounts.reduce((a, b) => a + b, 0) || 1;
  makeChart('chartServiceCat', donutConfig({
    labels: cats,
    data: catCounts,
    center: { value: nf0.format(catTotal), label: 'subscriptions' },
    legendLabels: cats.map((c, i) => `${c}  ·  ${fmtPct(100 * catCounts[i] / catTotal)}`),
  }));

  /* 4) Avg add-on count by contract - bar */
  const addonAvg = CONTRACTS.map((c) => {
    const grp = rows.filter((r) => r.contract === c);
    return grp.length ? grp.reduce((s, r) => s + ['osec', 'oback', 'dprot', 'tech'].filter((k) => isSubscribed(r, k)).length, 0) / grp.length : 0;
  });
  makeChart('chartAddonByContract', {
    type: 'bar',
    data: { labels: CONTRACTS, datasets: [{ data: addonAvg, backgroundColor: CONTRACTS.map((_, i) => paletteAt(i)), borderRadius: 10, maxBarThickness: 64 }] },
    options: { ...baseOptions('bar', { yTitle: 'Avg add-ons' }), plugins: { ...baseOptions('bar').plugins, tooltip: { ...baseOptions('bar').plugins.tooltip, callbacks: { label: (ctx) => ` ${nf2.format(ctx.parsed.y)} add-ons avg` } } } },
  });
}

/* ---------- RENDER: REVENUE page ---------- */
function renderRevenue(rows) {
  /* 1) Monthly revenue by contract - bar */
  const rev = CONTRACTS.map((c) => rows.filter((r) => r.contract === c).reduce((s, r) => s + (r.monthly || 0), 0));
  makeChart('chartRevenueContract', {
    type: 'bar',
    data: { labels: CONTRACTS, datasets: [{ data: rev, backgroundColor: CONTRACTS.map((_, i) => paletteAt(i)), borderRadius: 10, maxBarThickness: 70 }] },
    options: { ...baseOptions('bar', { yTitle: 'USD', yTick: (v) => '$' + nf0.format(v / 1000) + 'k' }), plugins: { ...baseOptions('bar').plugins, tooltip: { ...baseOptions('bar').plugins.tooltip, callbacks: { label: (ctx) => ` Monthly revenue ${fmtMoney(ctx.parsed.y)}` } } } },
  });

  /* 2) Avg CLTV by tenure - bar */
  const cltvAvg = TENURE_BANDS.map((b) => {
    const grp = rows.filter((r) => b.test(r.tenure));
    return grp.length ? grp.reduce((s, r) => s + (r.cltv || 0), 0) / grp.length : 0;
  });
  makeChart('chartCltvBar', {
    type: 'bar',
    data: { labels: TENURE_BANDS.map((b) => b.label), datasets: [{ data: cltvAvg, backgroundColor: TENURE_BANDS.map((_, i) => paletteAt(i)), borderRadius: 10, maxBarThickness: 46 }] },
    options: { ...baseOptions('bar', { yTitle: 'USD', yTick: (v) => '$' + nf0.format(v / 1000) + 'k' }), plugins: { ...baseOptions('bar').plugins, tooltip: { ...baseOptions('bar').plugins.tooltip, callbacks: { label: (ctx) => ` Avg CLTV ${fmtMoney(ctx.parsed.y)}` } } } },
  });

  /* 3) Monthly trajectory active vs churned - dual line */
  const actLine = TENURE_BANDS.map((b) => { const g = rows.filter((r) => b.test(r.tenure) && !churned(r)); return g.length ? g.reduce((s, r) => s + (r.monthly || 0), 0) / g.length : 0; });
  const chLine = TENURE_BANDS.map((b) => { const g = rows.filter((r) => b.test(r.tenure) && churned(r)); return g.length ? g.reduce((s, r) => s + (r.monthly || 0), 0) / g.length : 0; });
  const cc = churnColors();
  makeChart('chartTrajectory', {
    type: 'line',
    data: {
      labels: TENURE_BANDS.map((b) => b.label),
      datasets: [
        { label: 'Active', data: actLine, borderColor: cc.active, backgroundColor: 'transparent', tension: 0.45, borderWidth: 3, pointRadius: 4, pointHoverRadius: 7, pointBackgroundColor: cc.active },
        { label: 'Churned', data: chLine, borderColor: cc.churned, backgroundColor: 'transparent', tension: 0.45, borderWidth: 3, pointRadius: 4, pointHoverRadius: 7, pointBackgroundColor: cc.churned },
      ],
    },
    options: baseOptions('line', { yTitle: 'USD', legend: true }),
  });

  /* 4) Payment method mix doughnut */
  const payMix = PAYS.map((p) => rows.filter((r) => r.pay === p).length);
  const payTotal = payMix.reduce((a, b) => a + b, 0) || 1;
  makeChart('chartPayMix', donutConfig({
    labels: PAYS.map((p) => p.replace(' (automatic)', ' · Auto')),
    data: payMix,
    center: { value: nf0.format(payTotal), label: 'customers' },
    legendLabels: PAYS.map((p, i) => `${p.replace(' (automatic)', ' · Auto')}  ·  ${fmtPct(100 * payMix[i] / payTotal)}`),
  }));
}

/* ---------- RENDER: GEOGRAPHY page (interactive field map) ---------- */
function hexToRgb(h) { const n = parseInt(h.slice(1), 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; }
function lerp(a, b, t) { return Math.round(a + (b - a) * t); }
/* Green INTENSITY scale: low intensity = dull dark green, high = full neon glow */
function intensityGreen(rate) {
  const isDark = themeMode() === 'dark';
  const low = hexToRgb(isDark ? '#0d3b22' : '#bfe8d2');
  const high = hexToRgb(isDark ? '#2bff9e' : '#047857');
  const t = Math.max(0, Math.min(1, rate / 100));
  return 'rgb(' + lerp(low[0], high[0], t) + ',' + lerp(low[1], high[1], t) + ',' + lerp(low[2], high[2], t) + ')';
}
function mapDotLevel(rate) { return rate >= 80 ? 4 : rate >= 60 ? 3 : rate >= 40 ? 2 : rate >= 20 ? 1 : 0; }
function tileUrl() {
  return themeMode() === 'dark'
    ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
    : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';
}

function renderGeography(rows) {
  const mapEl = $('geoMap');
  if (!mapEl) return;
  const isDark = themeMode() === 'dark';
  mapEl.classList.toggle('dark', isDark);
  mapEl.classList.toggle('light', !isDark);

  /* Aggregate by zip code (lat/lng per zip = mean) */
  const zipMap = new Map();
  rows.forEach((r) => {
    const lat = Number(r.lat), lng = Number(r.lng);
    if (!isFinite(lat) || !isFinite(lng)) return;
    const key = String(r.zip == null ? '0' : r.zip);
    let a = zipMap.get(key);
    if (!a) { a = { zip: key, city: r.city || '?', state: r.state || 'CA', lat: 0, lng: 0, n: 0, ch: 0, cltv: 0, rev: 0 }; zipMap.set(key, a); }
    a.lat += lat; a.lng += lng; a.n += 1; a.ch += churned(r) ? 1 : 0; a.cltv += (r.cltv || 0); a.rev += (r.monthly || 0);
  });
  const zips = [...zipMap.values()].map((a) => { a.lat /= a.n; a.lng /= a.n; a.rate = 100 * a.ch / a.n; return a; });
  zips.sort((x, y) => y.n - x.n);

  $('geoLegend').innerHTML = `<span>Low churn</span><div class="grad"></div><span>High churn</span>`;

  /* Map init / update - theme boundary tiles: dark surface (dark theme) / light (light theme) */
  if (!geoMap) {
    geoMap = L.map('geoMap', { zoomControl: true, scrollWheelZoom: true });
    geoTiles = L.tileLayer(tileUrl(), { maxZoom: 18, attribution: '&copy; <a href="https://carto.com/attributions">CARTO</a> &copy; <a href="https://www.openstreetmap.org/copyright">OSM</a>' }).addTo(geoMap);
    geoLayer = L.layerGroup().addTo(geoMap);
  } else {
    if (geoTiles) geoTiles.setUrl(tileUrl());
    geoLayer.clearLayers();
  }
  if (!zips.length) { geoMap.setView([36.7783, -119.4179], 6); return; }

  const maxN = Math.max(...zips.map((z) => z.n), 1);
  zips.forEach((z) => {
    const r = 6 + 16 * Math.sqrt(z.n / maxN);
    const col = intensityGreen(z.rate);
    L.circleMarker([z.lat, z.lng], { radius: r, color: col, weight: 1.2, fillColor: col, fillOpacity: 0.9, opacity: 1, className: 'map-dot-' + mapDotLevel(z.rate) })
      .bindPopup(`<b>${z.city}</b> · ${z.zip}<br>State: ${z.state}<br>Customers: <b>${nf0.format(z.n)}</b><br>Churn rate: <b>${fmtPct(z.rate)}</b> (${nf0.format(z.ch)} churned)<br>Avg CLTV: ${fmtMoney(z.cltv / z.n)}<br>Monthly revenue: ${fmtMoney(z.rev)}`)
      .addTo(geoLayer);
  });
  try { geoMap.fitBounds(L.latLngBounds(zips.map((z) => [z.lat, z.lng])), { padding: [18, 18], maxZoom: 11 }); } catch (e) { geoMap.setView([36.7783, -119.4179], 6); }

  /* City churn-rate bar (top cities by customer count) */
  const cityMap = new Map();
  rows.forEach((r) => { const c = r.city || 'Unknown'; let a = cityMap.get(c); if (!a) { a = { n: 0, ch: 0 }; cityMap.set(c, a); } a.n += 1; a.ch += churned(r) ? 1 : 0; });
  const citiesArr = [...cityMap.entries()].map(([name, a]) => ({ name, n: a.n, rate: 100 * a.ch / a.n })).sort((x, y) => y.n - x.n);
  const cityTop10 = citiesArr.slice(0, 10);
  makeChart('chartCityBar', {
    type: 'bar',
    data: { labels: cityTop10.map((c) => c.name), datasets: [{ data: cityTop10.map((c) => c.rate), backgroundColor: cityTop10.map((_, i) => paletteAt(i)), borderRadius: 8, maxBarThickness: 22 }] },
    options: {
      indexAxis: 'y',
      ...baseOptions('bar', { xTitle: 'Churn rate (%)' }),
      scales: { ...baseOptions('bar').scales, x: { ...baseOptions('bar').scales.x, beginAtZero: true }, y: { ...baseOptions('bar').scales.y, grid: { color: 'transparent' } } },
      plugins: { ...baseOptions('bar').plugins, tooltip: { ...baseOptions('bar').plugins.tooltip, callbacks: { label: (ctx) => ` ${fmtPct(ctx.parsed.x)} · ${nf0.format(cityTop10[ctx.dataIndex].n)} customers` } } },
    },
  });

  /* Zip density bar (top zips by customer count) */
  const topZips = zips.slice(0, 10);
  makeChart('chartZipBar', {
    type: 'bar',
    data: { labels: topZips.map((z) => `${z.zip} · ${z.city}`), datasets: [{ data: topZips.map((z) => z.n), backgroundColor: topZips.map((_, i) => paletteAt(i)), borderRadius: 8, maxBarThickness: 22 }] },
    options: {
      indexAxis: 'y',
      ...baseOptions('bar', { xTitle: 'Customers' }),
      scales: { ...baseOptions('bar').scales, x: { ...baseOptions('bar').scales.x, beginAtZero: true }, y: { ...baseOptions('bar').scales.y, grid: { color: 'transparent' } } },
      plugins: { ...baseOptions('bar').plugins, tooltip: { ...baseOptions('bar').plugins.tooltip, callbacks: { label: (ctx) => ` ${nf0.format(ctx.parsed.x)} customers · churn ${fmtPct(topZips[ctx.dataIndex].rate)}` } } },
    },
  });
}

/* ---------- Page dispatcher ---------- */
function renderCharts() {
  const rows = filtered();
  buildKPI(rows);
  switch (state.page) {
    case 'overview': renderOverview(rows); break;
    case 'churn': renderChurn(rows); break;
    case 'services': renderServices(rows); break;
    case 'revenue': renderRevenue(rows); break;
    case 'geography': renderGeography(rows); break;
  }
}

function renderAll() {
  buildSlicers();
  renderCharts();
}

/* ---------- Pages ---------- */
function showPage(page) {
  state.page = page;
  document.querySelectorAll('.page').forEach((s) => s.classList.remove('active'));
  const sec = $('page-' + page);
  if (sec) sec.classList.add('active');
  document.querySelectorAll('.page-btn').forEach((b) => b.classList.toggle('active', b.dataset.page === page));
  renderCharts(); // rebuild charts for the now-visible page (correct canvas size)
  /* Leaflet container was hidden -> force a size recalc after it is visible */
  if (page === 'geography' && geoMap) setTimeout(() => geoMap.invalidateSize(), 150);
  window.scrollTo({ top: 0, behavior: 'smooth' });
}

/* ---------- Q&A engine ---------- */
const QA_SUGGESTIONS = [
  'What is the overall churn rate?',
  'Top churn reasons',
  'Which contract churns the most?',
  'Which service has the highest churn?',
  'What is the average monthly charge?',
  'How much revenue is at risk?',
];

function answerQuestion(q) {
  const rows = filtered();
  const total = rows.length;
  const churners = rows.filter(churned).length;
  const rate = total ? 100 * churners / total : 0;
  const qq = q.toLowerCase();
  const lines = [];
  const scope = `${nf0.format(total)} customers`;

  const reasonMap = groupSum(rows.filter(churned), (r) => r.reason || 'Unknown', () => 1);
  const topReason = [...reasonMap.entries()].sort((a, b) => b[1] - a[1])[0];

  if (/(churn rate|churn%|churn percentage|how many.*churn|overall churn)/.test(qq)) {
    lines.push(`Overall churn rate in the current view is **${fmtPct(rate)}** (${nf0.format(churners)} of ${nf0.format(total)} customers churned).`);
  }
  if (/(reason|why.*leave|why.*churn|top churn)/.test(qq)) {
    lines.push(`Top churn reason: **${topReason ? topReason[0] : 'n/a'}** (${topReason ? nf0.format(topReason[1]) : 0} churners).`);
    if (reasonMap.size > 1) {
      const top3 = [...reasonMap.entries()].sort((a, b) => b[1] - a[1]).slice(0, 3);
      lines.push(`Top 3 reasons: ${top3.map(([r, c]) => `${r} (${nf0.format(c)})`).join(' · ')}.`);
    }
  }
  if (/(contract|plan|month.to.month|two.year|one.year)/.test(qq)) {
    const rates = CONTRACTS.map((c) => { const g = rows.filter((r) => r.contract === c); return { c, rate: churnRateOf(g) }; }).sort((a, b) => b.rate - a.rate);
    lines.push(`Highest-churn contract: **${rates[0].c}** at **${fmtPct(rates[0].rate)}**; lowest: **${rates[2].c}** at **${fmtPct(rates[2].rate)}**.`);
  }
  if (/(service|fiber|dsl|internet|tech support|add.on|retention)/.test(qq)) {
    const svcRates = SERVICES.map((s) => { const g = rows.filter((r) => isSubscribed(r, s.key)); return { s: s.name, rate: churnRateOf(g) }; }).sort((a, b) => b.rate - a.rate);
    lines.push(`Highest-churn service: **${svcRates[0].s}** at **${fmtPct(svcRates[0].rate)}**; best retention: **${svcRates[svcRates.length - 1].s}** at **${fmtPct(svcRates[svcRates.length - 1].rate)}**.`);
  }
  if (/(average|avg|monthly charge|spend|bill)/.test(qq)) {
    const avg = total ? rows.reduce((s, r) => s + (r.monthly || 0), 0) / total : 0;
    const avgCltv = total ? rows.reduce((s, r) => s + (r.cltv || 0), 0) / total : 0;
    lines.push(`Average monthly charge is **${fmtMoney(avg)}** and average CLTV is **${fmtMoney(avgCltv)}**.`);
  }
  if (/(revenue.*risk|at risk|money.*lose|lose.*money|exposure)/.test(qq)) {
    const atRisk = rows.filter(churned).reduce((s, r) => s + (r.monthly || 0), 0);
    lines.push(`Revenue at risk is **${fmtMoney(atRisk)}** per month (churned customers' recurring charges).`);
  }
  if (/(how many|total|customers|count)/.test(qq)) {
    lines.push(`Current view contains **${nf0.format(total)}** customers — **${nf0.format(churners)}** churned, **${nf0.format(total - churners)}** active.`);
  }
  if (/(high.risk|risk|score|cltv.*risk|at.risk.*customer)/.test(qq)) {
    const highRisk = rows.filter((r) => r.score >= 70 && !churned(r)).length;
    lines.push(`**${nf0.format(highRisk)}** currently-active customers are high-risk (churn score ≥ 70) and should be prioritized for retention.`);
  }
  if (!lines.length) {
    lines.push(`Analysis of ${scope}: churn rate **${fmtPct(rate)}**, ${topReason ? `top reason **${topReason[0]}**` : 'no churners in view'}.`);
    lines.push('Try: "overall churn rate", "top churn reasons", "which contract churns the most", "revenue at risk".');
  }
  return lines.join('\n');
}

function openQA(q) {
  const input = $('qaInput');
  if (q) input.value = q;
  const ans = $('qaAnswer');
  ans.className = 'qa-answer show';
  ans.innerHTML = answerQuestion(input.value || q).replace(/\*\*(.+?)\*\*/g, '<b>$1</b>');
  $('qaModal').classList.add('open');
}

/* ---------- Toast ---------- */
function toast(msg) {
  const el = document.createElement('div');
  el.className = 'toast';
  el.innerHTML = `<span class="dot"></span>${msg}`;
  $('toastWrap').appendChild(el);
  setTimeout(() => { el.style.opacity = '0'; el.style.transition = 'opacity 0.4s'; setTimeout(() => el.remove(), 450); }, 2600);
}

/* ---------- Bookmark ---------- */
function bookmarkView() {
  const saved = { theme: state.theme, page: state.page, filters: Object.assign({}, state.filters) };
  localStorage.setItem('churn-bookmark', JSON.stringify(saved));
  toast('Bookmark saved — theme, page & filters preserved');
}

/* ---------- Wire up ---------- */
function init() {
  const savedTheme = localStorage.getItem('churn-theme');
  applyTheme(savedTheme || 'dark', false);

  const bm = localStorage.getItem('churn-bookmark');
  if (bm) {
    try {
      const s = JSON.parse(bm);
      if (s.filters) state.filters = Object.assign(state.filters, s.filters);
    } catch (e) { /* ignore */ }
  }

  buildSlicers();
  renderCharts();

  document.querySelectorAll('.page-btn').forEach((b) => b.addEventListener('click', () => showPage(b.dataset.page)));

  $('btnTheme').addEventListener('click', () => {
    applyTheme(state.theme === 'dark' ? 'light' : 'dark', true);
    renderAll();
    toast(state.theme === 'dark' ? 'Holographic theme activated' : 'Apple-style theme activated');
  });

  $('btnHome').addEventListener('click', () => showPage('overview'));
  $('btnReset').addEventListener('click', () => {
    Object.keys(state.filters).forEach((k) => { state.filters[k] = 'All'; });
    renderAll();
    toast('Filters reset');
  });
  $('btnBookmark').addEventListener('click', bookmarkView);

  $('btnQA').addEventListener('click', () => {
    const sg = $('qaSuggest');
    sg.innerHTML = '';
    QA_SUGGESTIONS.forEach((s) => {
      const b = document.createElement('button');
      b.className = 'chip';
      b.textContent = s;
      b.onclick = () => openQA(s);
      sg.appendChild(b);
    });
    $('qaAnswer').className = 'qa-answer';
    $('qaModal').classList.add('open');
    setTimeout(() => $('qaInput').focus(), 80);
  });

  $('qaAsk').addEventListener('click', () => openQA());
  $('qaInput').addEventListener('keydown', (e) => { if (e.key === 'Enter') openQA(); });
  $('qaModal').addEventListener('click', (e) => { if (e.target === $('qaModal')) $('qaModal').classList.remove('open'); });
}

document.addEventListener('DOMContentLoaded', init);