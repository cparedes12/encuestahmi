/* ============================================================================
   Encuestas de Salida · Dashboard de producción
   Diseño fiel al demo aprobado, alimentado con datos reales de Supabase.
   ========================================================================== */
"use strict";

let sb = null;
const state = { range: "30", depto: "", tab: "dashboard", admTab: "preguntas" };

const $  = (s, el=document) => el.querySelector(s);
const $$ = (s, el=document) => [...el.querySelectorAll(s)];
const nf = new Intl.NumberFormat("es-MX");
const cap = s => (s||"").charAt(0).toUpperCase() + (s||"").slice(1);
const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));

/* ---------------------------------------------------------------- init */
function initClient(){
  if (!window.CONFIG || !window.CONFIG.SUPABASE_URL ||
      !window.CONFIG.SUPABASE_ANON_KEY || window.CONFIG.SUPABASE_ANON_KEY === "PEGA_AQUI_TU_ANON_KEY"){
    document.body.innerHTML =
      `<div style="max-width:560px;margin:80px auto;padding:28px;background:#fff;border-radius:18px;
        box-shadow:0 10px 34px rgba(60,40,50,.12);border:1px solid #f0e6e9;font-family:Nunito,sans-serif">
        <h1 style="font-family:Quicksand">Falta configurar el dashboard</h1>
        <p style="color:#6a6a78">Edita <b>config.js</b> y pega tu <b>SUPABASE_URL</b> y <b>SUPABASE_ANON_KEY</b>
        (los encuentras en GitHub → Settings → Secrets and variables → Actions).</p>
      </div>`;
    return false;
  }
  sb = supabase.createClient(window.CONFIG.SUPABASE_URL, window.CONFIG.SUPABASE_ANON_KEY);
  return true;
}

/* ---------------------------------------------------------------- fechas */
const startOfDay = d => { const x = new Date(d); x.setHours(0,0,0,0); return x; };
const firstOfMonth = d => new Date(d.getFullYear(), d.getMonth(), 1);
const addMonths = (d,n) => new Date(d.getFullYear(), d.getMonth()+n, 1);

function rangeFor(key){
  const now = new Date();
  let desde, hasta = new Date(now.getTime()+1000);
  if (key === "hoy")          desde = startOfDay(now);
  else if (key === "semana")  desde = new Date(now.getTime() - 7*864e5);
  else if (key === "anterior"){ hasta = firstOfMonth(now); desde = addMonths(hasta,-1); }
  else                        desde = new Date(now.getTime() - 30*864e5);
  const len = hasta - desde;
  return { desde, hasta, prevDesde: new Date(desde.getTime()-len), prevHasta: desde };
}
const iso = d => d.toISOString();

/* ---------------------------------------------------------------- auth */
async function checkSession(){
  const { data } = await sb.auth.getSession();
  if (data.session) enterApp(data.session);
  else showLogin();
}
function showLogin(){ $("#login").classList.remove("hidden"); $("#app").classList.add("hidden"); }
function enterApp(session){
  $("#login").classList.add("hidden");
  $("#app").classList.remove("hidden");
  $("#userChip").textContent = session.user.email || "";
  switchTab("dashboard");
}

/* ---------------------------------------------------------------- tabs */
function switchTab(tab){
  state.tab = tab;
  $$("#tabs button").forEach(b => b.classList.toggle("active", b.dataset.tab === tab));
  $("#view-dashboard").classList.toggle("active", tab === "dashboard");
  $("#view-admin").classList.toggle("active", tab === "admin");
  if (tab === "dashboard") loadDashboard();
  else loadAdmin();
}

/* ================================================================ DASHBOARD */
async function loadDashboard(){
  const host = $("#dash");
  host.innerHTML = `<div class="loading">Cargando datos…</div>`;
  const r = rangeFor(state.range);
  const depto = state.depto || null;
  try{
    const [met, prev, dep, desg, tend, heat, hora, ult] = await Promise.all([
      sb.rpc("dashboard_metrics",              { p_desde: iso(r.desde),     p_hasta: iso(r.hasta),     p_depto: depto }),
      sb.rpc("dashboard_metrics",              { p_desde: iso(r.prevDesde), p_hasta: iso(r.prevHasta), p_depto: depto }),
      sb.rpc("dashboard_resumen_departamento", { p_desde: iso(r.desde),     p_hasta: iso(r.hasta) }),
      sb.rpc("dashboard_desglose_pregunta",    { p_desde: iso(r.desde),     p_hasta: iso(r.hasta),     p_depto: depto }),
      sb.rpc("dashboard_tendencia_dept",       { p_desde: iso(r.desde),     p_hasta: iso(r.hasta) }),
      sb.rpc("dashboard_heatmap",              { p_desde: iso(r.desde),     p_hasta: iso(r.hasta),     p_depto: depto }),
      sb.rpc("dashboard_por_hora",             { p_desde: iso(r.desde),     p_hasta: iso(r.hasta),     p_depto: depto }),
      sb.rpc("dashboard_ultimas",              { p_limit: 8 }),
    ]);
    const bad = [met,prev,dep,desg,tend,heat,hora,ult].find(x => x.error);
    if (bad) throw bad.error;

    const D = {
      met:  (met.data && met.data[0])  || {},
      prev: (prev.data && prev.data[0]) || {},
      dep:  dep.data  || [],
      desg: desg.data || [],
      tend: tend.data || [],
      heat: heat.data || [],
      hora: hora.data || [],
      ult:  ult.data  || [],
    };
    renderDashboard(D);
    updateLive(D.ult);
  }catch(e){
    host.innerHTML = `<div class="banner">No se pudieron cargar los datos: ${esc(e.message||e)}.
      Verifica que aplicaste <b>dashboard_rpc.sql</b> en tu instancia y que tu sesión está activa.</div>`;
    $("#liveTxt").textContent = "Sin conexión";
  }
}

function updateLive(ult){
  const txt = $("#liveTxt");
  if (!ult.length){ txt.textContent = "Sin respuestas aún"; return; }
  txt.textContent = "En vivo · última respuesta " + rel(ult[0].completada_en);
}

function renderDashboard(D){
  const depLabel = state.depto ? cap(state.depto) : "Ambos departamentos";
  $("#dash").innerHTML = `
    ${kpiRow(D)}
    ${execRow(D)}
    ${heatmapPanel(D.heat)}
    <div class="analytics-two-col">
      ${donutsPanel(D.dep)}
      ${byHourPanel(D.hora)}
    </div>
    ${insightsRow(D)}
    <div class="dash-main">
      ${desglosePanel(D.desg, depLabel)}
      <div style="display:flex;flex-direction:column;gap:22px;">
        ${deptPanel(D.dep)}
        ${trendPanel(D.tend)}
        ${recentPanel(D.ult)}
      </div>
    </div>`;
  requestAnimationFrame(applyAnims);
}

/* ---- KPIs ---- */
function deltaSub(cur, prev, unit){
  if (cur == null || prev == null || prev === 0) return `<span class="muted">— sin comparativo</span>`;
  const d = unit === "%pts" ? (cur - prev) : Math.round((cur - prev) / prev * 100);
  const up = d >= 0;
  const val = unit === "%pts" ? `${up?"↑":"↓"} ${Math.abs(d)} pts` : `${up?"↑":"↓"} ${Math.abs(d)}%`;
  return `<span class="${up?"up":"down"}">${val}</span> vs. periodo anterior`;
}
function spark(color){
  return `<svg class="kpi-spark" viewBox="0 0 70 28" preserveAspectRatio="none">
    <path d="M0,20 L10,18 L20,19 L30,14 L40,16 L50,11 L60,13 L70,7" fill="none" stroke="${color}" stroke-width="2" stroke-linecap="round"/></svg>`;
}
function kpiRow(D){
  const m = D.met, p = D.prev;
  const ped = D.dep.find(x => x.departamento === "pediatria")   || {};
  const gin = D.dep.find(x => x.departamento === "ginecologia") || {};
  return `<div class="kpi-row">
    <div class="kpi total"><div class="kpi-accent"></div>
      <div class="kpi-label">Total respuestas</div>
      <div class="kpi-value">${nf.format(m.total_respuestas||0)}</div>
      <div class="kpi-sub">${deltaSub(m.total_respuestas, p.total_respuestas, "%")}</div>
      ${spark("#3a3a4a")}
    </div>
    <div class="kpi good"><div class="kpi-accent"></div>
      <div class="kpi-label">Satisfacción general</div>
      <div class="kpi-value">${m.satisfaccion_general==null?"—":m.satisfaccion_general}<small>%</small></div>
      <div class="kpi-sub">${deltaSub(m.satisfaccion_general, p.satisfaccion_general, "%pts")}</div>
      ${spark("#2f8f5f")}
    </div>
    <div class="kpi ped"><div class="kpi-accent"></div>
      <div class="kpi-label">Pediatría</div>
      <div class="kpi-value">${ped.pct_satisfecho==null?"—":ped.pct_satisfecho}<small>%</small></div>
      <div class="kpi-sub">${nf.format(ped.total_respuestas||0)} respuestas</div>
      ${spark("#3bb4c8")}
    </div>
    <div class="kpi gin"><div class="kpi-accent"></div>
      <div class="kpi-label">Ginecología</div>
      <div class="kpi-value">${gin.pct_satisfecho==null?"—":gin.pct_satisfecho}<small>%</small></div>
      <div class="kpi-sub">${nf.format(gin.total_respuestas||0)} respuestas</div>
      ${spark("#d97a96")}
    </div>
  </div>`;
}

/* ---- Exec row (NPS + finalización + tiempo + mejora) ---- */
function npsCopy(nps){
  if (nps == null) return ["—","Sin datos suficientes"];
  if (nps >= 50) return ["Excelente desempeño","En salud, un NPS > +50 se considera <strong>excelente</strong>."];
  if (nps >= 0)  return ["Desempeño positivo","Más promotores que detractores. Hay margen de mejora."];
  return ["Requiere atención","Predominan los detractores; conviene revisar la experiencia."];
}
function execRow(D){
  const m = D.met, p = D.prev;
  const nps = m.nps;
  const len = 175, frac = nps==null ? 0 : Math.max(0, Math.min(1, (nps+100)/200));
  const [h4, desc] = npsCopy(nps);
  const npsDelta = (nps!=null && p.nps!=null) ? (nps - p.nps) : null;
  const finDelta = (m.tasa_finalizacion!=null && p.tasa_finalizacion!=null) ? (m.tasa_finalizacion - p.tasa_finalizacion) : null;
  const abandona = m.tasa_finalizacion==null ? "—" : (100 - m.tasa_finalizacion);
  const t = m.tiempo_promedio_seg;
  const satDelta = (m.satisfaccion_general!=null && p.satisfaccion_general!=null) ? (m.satisfaccion_general - p.satisfaccion_general) : null;
  return `
  <div class="section-divider">
    <div class="section-divider-line"></div>
    <div class="section-divider-title"><span class="badge-pro">📈 Pro</span> Analíticos profesionales</div>
    <div class="section-divider-line"></div>
  </div>
  <div class="exec-row">
    <div class="nps-card">
      <div class="nps-gauge">
        <svg viewBox="0 0 140 90">
          <defs><linearGradient id="nps-gradient" x1="0%" y1="0%" x2="100%" y2="0%">
            <stop offset="0%" stop-color="#c44a3f"/><stop offset="50%" stop-color="#d8a23a"/><stop offset="100%" stop-color="#2f8f5f"/>
          </linearGradient></defs>
          <path class="nps-arc-bg" d="M 15 80 A 55 55 0 0 1 125 80"/>
          <path class="nps-arc-fg" d="M 15 80 A 55 55 0 0 1 125 80"
            style="animation:none;stroke-dasharray:${(len*frac).toFixed(1)} ${len};stroke-dashoffset:0;transition:stroke-dasharray 1.2s ease"/>
        </svg>
        <div class="nps-value">${nps==null?"—":(nps>0?"+":"")+nps}<small>NPS</small></div>
      </div>
      <div class="nps-info">
        <div class="label">Net Promoter Score</div>
        <h4>${h4}</h4>
        <div class="desc">${m.pct_promotores??"—"}% promotores menos ${m.pct_detractores??"—"}% detractores. ${desc}</div>
        ${npsDelta!=null?`<span class="tag">${npsDelta>=0?"↑ +":"↓ "}${npsDelta} vs. periodo anterior</span>`:""}
      </div>
    </div>
    <div class="exec-card good">
      <div><div class="ec-icon">✓</div><div class="ec-label">Tasa de finalización</div></div>
      <div><div class="ec-value">${m.tasa_finalizacion==null?"—":m.tasa_finalizacion}<small>%</small></div>
        <div class="ec-sub">${finDelta!=null?`<span class="${finDelta>=0?"up":"down"}">${finDelta>=0?"↑":"↓"} ${Math.abs(finDelta)} pts</span> · `:""}${abandona}% no termina</div></div>
    </div>
    <div class="exec-card">
      <div><div class="ec-icon">⏱</div><div class="ec-label">Tiempo promedio</div></div>
      <div><div class="ec-value">${t==null?"—":Math.round(t)}<small>s</small></div>
        <div class="ec-sub">Objetivo: <strong>≤60s</strong>${t!=null?(t<=60?" · Cumplido ✓":" · Por encima"):""}</div></div>
    </div>
    <div class="exec-card rose">
      <div><div class="ec-icon">📈</div><div class="ec-label">Cambio de satisfacción</div></div>
      <div><div class="ec-value">${satDelta==null?"—":(satDelta>=0?"+":"")+satDelta}<small>pts</small></div>
        <div class="ec-sub">${satDelta==null?"sin comparativo":(satDelta>=0?'<span class="up">al alza</span>':'<span class="down">a la baja</span>')+" vs. periodo anterior"}</div></div>
    </div>
  </div>`;
}

/* ---- Heatmap día × hora ---- */
const HM_ROWS = [{l:"8 a",h:8},{l:"10 a",h:10},{l:"12 p",h:12},{l:"2 p",h:14},{l:"4 p",h:16},{l:"6 p",h:18},{l:"8 p",h:20}];
const HM_DAYS = [1,2,3,4,5,6,0]; // Lun..Dom (Postgres dow)
function heatmapPanel(rows){
  const grid = {}; let max = 0, peakKey = null;
  for (const r of rows){
    let b = r.hora - (r.hora % 2); b = Math.max(8, Math.min(20, b));
    const key = b + "_" + r.dow;
    grid[key] = (grid[key]||0) + Number(r.n);
    if (grid[key] > max){ max = grid[key]; peakKey = key; }
  }
  let cells = `<div></div>` + ["Lun","Mar","Mié","Jue","Vie","Sáb","Dom"].map(d=>`<div class="hm-col-label">${d}</div>`).join("");
  for (const row of HM_ROWS){
    cells += `<div class="hm-row-label">${row.l}</div>`;
    for (const dow of HM_DAYS){
      const key = row.h + "_" + dow, v = grid[key]||0;
      const a = max ? (.08 + .92*(v/max)) : .08;
      const light = a > .5;
      cells += `<div class="hm-cell ${key===peakKey&&max>0?"peak":""}"
        style="background:rgba(220,128,155,${a.toFixed(2)});color:${light?"#fff":"#5a4a52"}">${v||""}</div>`;
    }
  }
  const empty = max === 0;
  return `<div class="panel"><div class="panel-head"><div>
      <h3>📅 Patrón de respuestas por día y hora</h3>
      <p>Distribución acumulada — útil para planear staffing de Trabajo Social</p>
    </div></div>
    ${empty ? `<div class="chart-empty" style="padding:30px;text-align:center;color:#9a9aa6;font-weight:700">Sin respuestas en el periodo</div>`
      : `<div class="heatmap-grid">${cells}</div>
      <div class="hm-legend">Menos<div class="hm-legend-scale">
        <span style="background:rgba(220,128,155,.10)"></span><span style="background:rgba(220,128,155,.30)"></span>
        <span style="background:rgba(220,128,155,.55)"></span><span style="background:rgba(220,128,155,.80)"></span>
        <span style="background:rgba(220,128,155,1)"></span></div>Más respuestas</div>`}
  </div>`;
}

/* ---- Donuts por departamento ---- */
function donut(dep){
  const C = 263.89, g = dep.pct_satisfecho||0, m = dep.pct_neutral||0, b = dep.pct_insatisfecho||0;
  const seg = (pct, off, color) => `<circle class="seg" cx="50" cy="50" r="42" fill="none" stroke="${color}" stroke-width="14"
    stroke-dasharray="${(C*pct/100).toFixed(2)} ${C}" stroke-dashoffset="${(-C*off/100).toFixed(2)}"/>`;
  const isPed = dep.departamento === "pediatria";
  return `<div class="donut-item">
    <div class="donut-title"><span style="color:var(--${isPed?"teal":"rose"}-deep)">●</span> ${isPed?"👶 Pediatría":"🤱 Ginecología"}</div>
    <div class="donut-svg">
      <svg viewBox="0 0 100 100"><circle cx="50" cy="50" r="42" fill="none" stroke="#f4ecef" stroke-width="14"/>
        ${seg(g,0,"#2f8f5f")}${seg(m,g,"#d8a23a")}${seg(b,g+m,"#c44a3f")}</svg>
      <div class="donut-center"><div class="num">${nf.format(dep.total_respuestas||0)}</div><small>respuestas</small></div>
    </div>
    <div class="donut-legend"><span class="l-good">${g}%</span><span class="l-mid">${m}%</span><span class="l-bad">${b}%</span></div>
  </div>`;
}
function donutsPanel(dep){
  const order = ["pediatria","ginecologia"];
  const items = order.map(k => dep.find(d=>d.departamento===k)).filter(Boolean);
  return `<div class="panel"><div class="panel-head"><div>
      <h3>🍩 Distribución por departamento</h3><p>Proporción por nivel de satisfacción</p>
    </div></div>
    ${items.length? `<div class="donuts-grid">${items.map(donut).join("")}</div>`
      : `<div class="chart-empty" style="padding:30px;text-align:center;color:#9a9aa6;font-weight:700">Sin datos</div>`}
  </div>`;
}

/* ---- Satisfacción por hora ---- */
function byHourPanel(rows){
  const buckets = HM_ROWS.map(r => ({l:r.l, h:r.h, sum:0, n:0}));
  for (const r of rows){
    let b = r.h ?? r.hora; b = Math.max(8, Math.min(20, b - (b%2)));
    const t = buckets.find(x => x.h === b); if (!t) continue;
    t.sum += Number(r.pct_satisfecho||0) * Number(r.total||0); t.n += Number(r.total||0);
  }
  const vals = buckets.map(b => ({l:b.l, pct: b.n ? Math.round(b.sum/b.n) : 0, n:b.n}));
  const withData = vals.filter(v => v.n>0);
  const maxV = Math.max(...withData.map(v=>v.pct), 0);
  const minV = withData.length ? Math.min(...withData.map(v=>v.pct)) : 0;
  const bars = vals.map(v => `<div class="tod-bar ${v.n&&v.pct===maxV?"peak":""} ${v.n&&v.pct===minV&&maxV!==minV?"dip":""}">
      <div class="tod-bar-wrap"><div class="tod-bar-fill" data-h="${v.pct}"></div></div>
      <div class="tod-bar-label">${v.l}</div></div>`).join("");
  const best = withData.length ? withData.reduce((a,b)=>b.pct>a.pct?b:a) : null;
  const worst = withData.length ? withData.reduce((a,b)=>b.pct<a.pct?b:a) : null;
  return `<div class="panel"><div class="panel-head"><div>
      <h3>🕐 Satisfacción por hora del día</h3><p>Promedio de satisfacción según hora de respuesta</p>
    </div></div>
    ${withData.length? `<div class="tod-chart">${bars}</div>
      <div class="tod-annotation"><span class="star">⭐</span>
        Mejor horario: <strong>${best.l} (${best.pct}%)</strong>. Más bajo: <strong>${worst.l} (${worst.pct}%)</strong>.</div>`
      : `<div class="chart-empty" style="padding:30px;text-align:center;color:#9a9aa6;font-weight:700">Sin datos</div>`}
  </div>`;
}

/* ---- Insights automáticos ---- */
function insightsRow(D){
  const cards = [];
  // pico de actividad (heatmap)
  let peak = null, max = 0;
  for (const r of D.heat){ if (Number(r.n) > max){ max = Number(r.n); peak = r; } }
  if (peak){
    const dias = ["Domingo","Lunes","Martes","Miércoles","Jueves","Viernes","Sábado"];
    cards.push(`<div class="insight-card peak"><div class="ic-icon">⭐</div>
      <div class="ic-headline">Pico de actividad</div>
      <div class="ic-detail"><strong>${dias[peak.dow]} ~${peak.hora}:00</strong> concentra el mayor volumen de respuestas.</div>
      <span class="ic-tag">Auto-detectado</span></div>`);
  }
  // tendencia
  const sat = D.met.satisfaccion_general, prevSat = D.prev.satisfaccion_general;
  if (sat!=null && prevSat!=null){
    const d = sat - prevSat, up = d>=0;
    cards.push(`<div class="insight-card ${up?"trend":"alert"}"><div class="ic-icon">${up?"📈":"📉"}</div>
      <div class="ic-headline">${up?"Tendencia positiva":"Tendencia a la baja"}</div>
      <div class="ic-detail">Satisfacción general ${up?"subió":"bajó"} <strong>${Math.abs(d)} pts</strong> vs. el periodo anterior.</div>
      <span class="ic-tag">Vs. periodo anterior</span></div>`);
  }
  // pregunta crítica
  const conDatos = D.desg.filter(q => q.total>0 && q.pct_satisfecho!=null);
  if (conDatos.length){
    const peor = conDatos.reduce((a,b)=> b.pct_satisfecho < a.pct_satisfecho ? b : a);
    cards.push(`<div class="insight-card target"><div class="ic-icon">🎯</div>
      <div class="ic-headline">Pregunta crítica</div>
      <div class="ic-detail"><strong>${esc(peor.texto)}</strong> (${cap(peor.departamento)}) es la peor evaluada: ${peor.pct_satisfecho}% satisfecho.</div>
      <span class="ic-tag">Acción sugerida</span></div>`);
  }
  // dip vespertino
  const hb = {}; for (const r of D.hora){ const h=r.hora; hb[h]={pct:r.pct_satisfecho,n:r.total}; }
  const avg = hs => { let s=0,n=0; hs.forEach(h=>{ if(hb[h]){ s+=hb[h].pct*hb[h].n; n+=hb[h].n; }}); return n? s/n : null; };
  const am = avg([8,9,10]), pm = avg([16,17,18]);
  if (am!=null && pm!=null && am-pm >= 8){
    cards.push(`<div class="insight-card alert"><div class="ic-icon">⚠️</div>
      <div class="ic-headline">Patrón a revisar</div>
      <div class="ic-detail">Las respuestas vespertinas (4-6 p) tienen <strong>${Math.round(am-pm)} pts menos</strong> de satisfacción que las matutinas.</div>
      <span class="ic-tag">Requiere atención</span></div>`);
  }
  if (!cards.length) return "";
  return `<div class="insights-grid">${cards.join("")}</div>`;
}

/* ---- Desglose por pregunta ---- */
function qbar(q){
  const t = q.total||0, pct = n => t? Math.round(100*n/t):0;
  const g = pct(q.n_satisfecho), m = pct(q.n_neutral), b = pct(q.n_insatisfecho);
  const score = q.pct_satisfecho==null?0:q.pct_satisfecho;
  const cls = score>=75?"good":score>=60?"mid":"bad";
  return `<div class="qbar">
    <div class="qbar-head"><div class="qbar-text">${esc(q.texto)}</div>
      <div class="qbar-score ${cls}">${q.pct_satisfecho==null?"—":q.pct_satisfecho+"%"}</div></div>
    <div class="qbar-track">
      <div class="qbar-seg good" data-w="${g}"></div><div class="qbar-seg mid" data-w="${m}"></div><div class="qbar-seg bad" data-w="${b}"></div>
    </div>
    <div class="qbar-legend"><span class="lg-good">${nf.format(q.n_satisfecho||0)} satisfecho</span>
      <span class="lg-mid">${nf.format(q.n_neutral||0)} neutral</span>
      <span class="lg-bad">${nf.format(q.n_insatisfecho||0)} insatisfecho</span></div>
  </div>`;
}
function desglosePanel(desg, depLabel){
  const groups = ["pediatria","ginecologia"]
    .map(k => ({ k, items: desg.filter(q => q.departamento === k) }))
    .filter(g => g.items.length);
  const body = groups.map(g => `
    <div style="margin-bottom:24px">
      <div class="qsection-label ${g.k==="pediatria"?"ped":"gin"}">
        <span class="icon">${g.k==="pediatria"?"👶":"🤱"}</span> ${cap(g.k)}</div>
      ${g.items.map(qbar).join("")}
    </div>`).join("");
  return `<div class="panel"><div class="panel-head"><div>
      <h3>Desglose por pregunta</h3><p>${esc(depLabel)} · % satisfecho (😃) por pregunta</p>
    </div></div>
    ${body || `<div class="chart-empty" style="padding:30px;text-align:center;color:#9a9aa6;font-weight:700">Sin preguntas activas o sin respuestas</div>`}
  </div>`;
}

/* ---- Resumen por departamento ---- */
function deptPanel(dep){
  if (!dep.length) return `<div class="panel"><div class="panel-head"><div><h3>Por departamento</h3></div></div>
    <div class="chart-empty" style="padding:24px;text-align:center;color:#9a9aa6;font-weight:700">Sin datos</div></div>`;
  const block = d => `<div class="dept-block ${d.departamento==="pediatria"?"ped":"gin"}">
    <div class="dept-head"><div class="dept-name"><span class="icon">${d.departamento==="pediatria"?"👶":"🤱"}</span> ${cap(d.departamento)}</div>
      <div class="dept-count">${nf.format(d.total_respuestas||0)} respuestas</div></div>
    <div class="dept-score">${d.pct_satisfecho??"—"}<small>%</small></div>
    <div class="dept-meta"><span>😃 ${d.pct_satisfecho??0}%</span><span>😕 ${d.pct_neutral??0}%</span><span>☹️ ${d.pct_insatisfecho??0}%</span></div>
  </div>`;
  return `<div class="panel"><div class="panel-head"><div><h3>Por departamento</h3><p>Resumen del periodo</p></div></div>
    ${["pediatria","ginecologia"].map(k=>dep.find(d=>d.departamento===k)).filter(Boolean).map(block).join("")}</div>`;
}

/* ---- Tendencia por departamento ---- */
function trendPanel(tend){
  // serie diaria por depto (encuestas completadas), últimos N días del rango
  const days = [...new Set(tend.map(r => r.dia))].sort();
  const last = days.slice(-14);
  const serie = depto => last.map(d => {
    const row = tend.find(r => r.dia === d && r.departamento === depto);
    return row ? Number(row.total_encuestas) : 0;
  });
  const ped = serie("pediatria"), gin = serie("ginecologia");
  const maxV = Math.max(1, ...ped, ...gin);
  const W = 400, H = 180, n = last.length;
  const X = i => n<=1 ? 0 : (W * i/(n-1));
  const Y = v => H - 10 - (H-30) * (v/maxV);
  const path = arr => arr.map((v,i)=>`${i?"L":"M"} ${X(i).toFixed(1)},${Y(v).toFixed(1)}`).join(" ");
  const area = arr => arr.length ? `${path(arr)} L ${W},${H} L 0,${H} Z` : "";
  const empty = !last.length;
  return `<div class="panel"><div class="panel-head"><div><h3>Tendencia · ${last.length} días</h3><p>Encuestas completadas por día</p></div></div>
    ${empty? `<div class="chart-empty" style="padding:24px;text-align:center;color:#9a9aa6;font-weight:700">Sin datos</div>` :
    `<div class="trend-chart"><svg class="trend-svg" viewBox="0 0 400 180" preserveAspectRatio="none">
      <line x1="0" y1="45" x2="400" y2="45" stroke="#f0e6e9" stroke-dasharray="3,3"/>
      <line x1="0" y1="90" x2="400" y2="90" stroke="#f0e6e9" stroke-dasharray="3,3"/>
      <line x1="0" y1="135" x2="400" y2="135" stroke="#f0e6e9" stroke-dasharray="3,3"/>
      <path class="area-path" d="${area(ped)}" fill="rgba(94,197,214,.15)"/>
      <path class="line-path" d="${path(ped)}" fill="none" stroke="#3bb4c8" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>
      <path class="area-path" d="${area(gin)}" fill="rgba(232,155,176,.13)"/>
      <path class="line-path" d="${path(gin)}" fill="none" stroke="#d97a96" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>
    </svg></div>
    <div class="trend-legend"><span class="lg-ped">Pediatría</span><span class="lg-gin">Ginecología</span></div>`}
  </div>`;
}

/* ---- Últimas respuestas ---- */
function rel(ts){
  if (!ts) return "";
  const s = Math.max(0, (Date.now() - new Date(ts).getTime())/1000);
  if (s < 60) return "hace " + Math.floor(s) + " s";
  if (s < 3600) return "hace " + Math.floor(s/60) + " min";
  if (s < 86400) return "hace " + Math.floor(s/3600) + " h";
  return "hace " + Math.floor(s/86400) + " d";
}
function recentPanel(ult){
  const item = r => {
    const g=Number(r.n_satisfecho), m=Number(r.n_neutral), b=Number(r.n_insatisfecho), tot=g+m+b;
    const emoji = b>0 ? "☹️" : m>0 ? "😕" : "😃";
    const cls = b>0 ? "bad" : m>0 ? "mid" : "good";
    const score = (b===0&&m===0) ? `${g}/${tot} 😃` : [g?`${g} 😃`:"", m?`${m} 😕`:"", b?`${b} ☹️`:""].filter(Boolean).join(" · ");
    const isPed = r.departamento === "pediatria";
    return `<div class="recent-item"><span class="emoji">${emoji}</span>
      <span class="dept ${isPed?"ped":"gin"}">${cap(r.departamento)}</span>
      <span class="score ${cls}">${score}</span><span class="time">${rel(r.completada_en)}</span></div>`;
  };
  return `<div class="panel"><div class="panel-head"><div><h3>Últimas respuestas</h3><p>Stream anonimizado</p></div></div>
    ${ult.length? `<div class="recent-list">${ult.map(item).join("")}</div>`
      : `<div class="chart-empty" style="padding:24px;text-align:center;color:#9a9aa6;font-weight:700">Aún no hay respuestas</div>`}
  </div>`;
}

/* ---- animaciones (anchos/alturas tras render) ---- */
function applyAnims(){
  $$("#dash .qbar-seg[data-w]").forEach(el => el.style.width  = el.dataset.w + "%");
  $$("#dash .tod-bar-fill[data-h]").forEach(el => el.style.height = el.dataset.h + "%");
}

/* ================================================================ ADMIN */
async function loadAdmin(){
  $("#admNew").textContent = state.admTab === "preguntas" ? "+ Nueva pregunta" : "+ Nueva tablet";
  const host = $("#admin");
  host.innerHTML = `<div class="loading">Cargando…</div>`;
  try{
    if (state.admTab === "preguntas"){
      const { data, error } = await sb.from("preguntas").select("*").order("departamento").order("orden");
      if (error) throw error;
      renderPreguntas(data || []);
    } else {
      const { data, error } = await sb.from("dispositivos").select("*").order("departamento").order("nombre");
      if (error) throw error;
      renderDispositivos(data || []);
    }
  }catch(e){
    host.innerHTML = `<div class="banner">No se pudo cargar: ${esc(e.message||e)}.
      ¿Aplicaste <b>dashboard_admin.sql</b>?</div>`;
  }
}

function renderPreguntas(rows){
  const tag = d => `<span class="depto-tag depto-${d==="pediatria"?"ped":"gin"}">${cap(d)}</span>`;
  const tr = p => `<tr>
    <td>${tag(p.departamento)}</td><td>${p.orden}</td>
    <td>${esc(p.texto)}</td>
    <td><span class="pill-state ${p.activa?"pill-on":"pill-off"}">${p.activa?"Activa":"Inactiva"}</span></td>
    <td><div class="row-actions">
      <button class="btn btn-ghost btn-sm" data-edit="${p.id}">Editar</button>
      <button class="btn btn-ghost btn-sm" data-toggle="${p.id}">${p.activa?"Desactivar":"Activar"}</button>
      <button class="btn btn-danger btn-sm" data-del="${p.id}">Borrar</button>
    </div></td></tr>`;
  $("#admin").innerHTML = `<div class="panel"><div class="panel-head"><div>
      <h3>Preguntas</h3><p>Edítalas sin recompilar la app · la tablet descarga solo las activas</p></div></div>
    <table class="adm-table"><thead><tr><th>Depto.</th><th>Orden</th><th>Texto</th><th>Estado</th><th></th></tr></thead>
    <tbody>${rows.length?rows.map(tr).join(""):`<tr><td colspan="5" style="text-align:center;color:#9a9aa6;padding:24px">Sin preguntas</td></tr>`}</tbody></table></div>`;
  window.__preguntas = rows;
  $$("#admin [data-edit]").forEach(b => b.onclick = () => editPregunta(rows.find(p=>p.id===b.dataset.edit)));
  $$("#admin [data-toggle]").forEach(b => b.onclick = () => togglePregunta(rows.find(p=>p.id===b.dataset.toggle)));
  $$("#admin [data-del]").forEach(b => b.onclick = () => delPregunta(rows.find(p=>p.id===b.dataset.del)));
}

function renderDispositivos(rows){
  const tag = d => `<span class="depto-tag depto-${d==="pediatria"?"ped":"gin"}">${cap(d)}</span>`;
  const tr = d => `<tr>
    <td>${esc(d.nombre)}</td><td>${tag(d.departamento)}</td><td>${esc(d.ubicacion||"—")}</td>
    <td><span class="pill-state ${d.activo?"pill-on":"pill-off"}">${d.activo?"Activo":"Inactivo"}</span></td>
    <td>${d.ultima_conexion?rel(d.ultima_conexion):"—"}</td>
    <td><div class="row-actions">
      <button class="btn btn-ghost btn-sm" data-edit="${d.id}">Editar</button>
      <button class="btn btn-ghost btn-sm" data-toggle="${d.id}">${d.activo?"Desactivar":"Activar"}</button>
      <button class="btn btn-danger btn-sm" data-del="${d.id}">Borrar</button>
    </div></td></tr>`;
  $("#admin").innerHTML = `<div class="panel"><div class="panel-head"><div>
      <h3>Tablets registradas</h3><p>Dispositivos que envían encuestas</p></div></div>
    <table class="adm-table"><thead><tr><th>Nombre</th><th>Depto.</th><th>Ubicación</th><th>Estado</th><th>Últ. conexión</th><th></th></tr></thead>
    <tbody>${rows.length?rows.map(tr).join(""):`<tr><td colspan="6" style="text-align:center;color:#9a9aa6;padding:24px">Sin tablets</td></tr>`}</tbody></table></div>`;
  $$("#admin [data-edit]").forEach(b => b.onclick = () => editDispositivo(rows.find(d=>d.id===b.dataset.edit)));
  $$("#admin [data-toggle]").forEach(b => b.onclick = () => toggleDispositivo(rows.find(d=>d.id===b.dataset.toggle)));
  $$("#admin [data-del]").forEach(b => b.onclick = () => delDispositivo(rows.find(d=>d.id===b.dataset.del)));
}

/* ---- modal helper ---- */
function modal(title, bodyHtml, onSave){
  const root = $("#modalRoot");
  root.innerHTML = `<div class="modal-bg"><div class="modal"><h3>${esc(title)}</h3>${bodyHtml}
    <div class="modal-actions"><button class="btn btn-ghost" id="mCancel">Cancelar</button>
    <button class="btn btn-primary" id="mSave">Guardar</button></div></div></div>`;
  const close = () => root.innerHTML = "";
  $("#mCancel").onclick = close;
  $(".modal-bg").onclick = e => { if (e.target.classList.contains("modal-bg")) close(); };
  $("#mSave").onclick = async () => { const ok = await onSave(); if (ok !== false) close(); };
  return close;
}
function toast(msg, isErr){
  const t = $("#toast"); t.textContent = msg; t.className = "toast show" + (isErr?" err":"");
  setTimeout(() => t.className = "toast", 2600);
}

/* ---- preguntas CRUD ---- */
function preguntaForm(p){
  return `<div class="fld"><label>Departamento</label>
      <select id="fDepto" ${p?"disabled":""}>
        <option value="pediatria" ${p&&p.departamento==="pediatria"?"selected":""}>Pediatría</option>
        <option value="ginecologia" ${p&&p.departamento==="ginecologia"?"selected":""}>Ginecología</option></select></div>
    <div class="fld"><label>Orden</label><input type="number" id="fOrden" min="1" value="${p?p.orden:""}" /></div>
    <div class="fld"><label>Texto de la pregunta</label><input type="text" id="fTexto" value="${p?esc(p.texto):""}" placeholder="¿…?" /></div>
    <div class="fld"><label><input type="checkbox" id="fActiva" ${(!p||p.activa)?"checked":""} style="width:auto;margin-right:8px;vertical-align:-2px">Activa</label></div>`;
}
function editPregunta(p){
  modal(p?"Editar pregunta":"Nueva pregunta", preguntaForm(p), async () => {
    const depto = $("#fDepto").value, orden = parseInt($("#fOrden").value,10);
    const texto = $("#fTexto").value.trim(), activa = $("#fActiva").checked;
    if (!texto || !orden){ toast("Completa orden y texto", true); return false; }
    try{
      if (p){
        const { error } = await sb.from("preguntas").update({ orden, texto, activa }).eq("id", p.id);
        if (error) throw error;
      } else {
        const { error } = await sb.from("preguntas").insert({ departamento: depto, orden, texto, activa });
        if (error) throw error;
      }
      toast("Pregunta guardada"); loadAdmin();
    }catch(e){ toast(e.message||"Error", true); return false; }
  });
}
async function togglePregunta(p){
  try{ const { error } = await sb.from("preguntas").update({ activa: !p.activa }).eq("id", p.id);
    if (error) throw error; toast(p.activa?"Desactivada":"Activada"); loadAdmin();
  }catch(e){ toast(e.message||"Error", true); }
}
function delPregunta(p){
  modal("Borrar pregunta", `<p style="color:#6a6a78">¿Borrar <b>"${esc(p.texto)}"</b>? Las respuestas históricas no se eliminan.</p>`,
    async () => { try{ const { error } = await sb.from("preguntas").delete().eq("id", p.id);
      if (error) throw error; toast("Pregunta borrada"); loadAdmin();
    }catch(e){ toast(e.message||"Error", true); return false; } });
}

/* ---- dispositivos CRUD ---- */
function dispForm(d){
  return `<div class="fld"><label>Nombre</label><input type="text" id="fNombre" value="${d?esc(d.nombre):""}" placeholder="Tablet Pediatría P5" /></div>
    <div class="fld"><label>Departamento</label>
      <select id="fDepto"><option value="pediatria" ${d&&d.departamento==="pediatria"?"selected":""}>Pediatría</option>
        <option value="ginecologia" ${d&&d.departamento==="ginecologia"?"selected":""}>Ginecología</option></select></div>
    <div class="fld"><label>Ubicación</label><input type="text" id="fUbic" value="${d?esc(d.ubicacion||""):""}" placeholder="Trabajo Social, Piso 5" /></div>
    <div class="fld"><label><input type="checkbox" id="fActivo" ${(!d||d.activo)?"checked":""} style="width:auto;margin-right:8px;vertical-align:-2px">Activo</label></div>`;
}
function editDispositivo(d){
  modal(d?"Editar tablet":"Nueva tablet", dispForm(d), async () => {
    const nombre = $("#fNombre").value.trim(), departamento = $("#fDepto").value;
    const ubicacion = $("#fUbic").value.trim() || null, activo = $("#fActivo").checked;
    if (!nombre){ toast("El nombre es obligatorio", true); return false; }
    try{
      if (d){ const { error } = await sb.from("dispositivos").update({ nombre, departamento, ubicacion, activo }).eq("id", d.id);
        if (error) throw error;
      } else { const { error } = await sb.from("dispositivos").insert({ nombre, departamento, ubicacion, activo });
        if (error) throw error; }
      toast("Tablet guardada"); loadAdmin();
    }catch(e){ toast(e.message||"Error", true); return false; }
  });
}
async function toggleDispositivo(d){
  try{ const { error } = await sb.from("dispositivos").update({ activo: !d.activo }).eq("id", d.id);
    if (error) throw error; toast(d.activo?"Desactivada":"Activada"); loadAdmin();
  }catch(e){ toast(e.message||"Error", true); }
}
function delDispositivo(d){
  modal("Borrar tablet", `<p style="color:#6a6a78">¿Borrar <b>"${esc(d.nombre)}"</b>?</p>`,
    async () => { try{ const { error } = await sb.from("dispositivos").delete().eq("id", d.id);
      if (error) throw error; toast("Tablet borrada"); loadAdmin();
    }catch(e){ toast(e.message||"Error", true); return false; } });
}

/* ================================================================ eventos */
function wire(){
  $("#loginForm").addEventListener("submit", async e => {
    e.preventDefault();
    const btn = $("#loginBtn"), err = $("#loginErr");
    err.textContent = ""; btn.textContent = "Entrando…"; btn.disabled = true;
    const { error } = await sb.auth.signInWithPassword({ email: $("#email").value.trim(), password: $("#password").value });
    btn.textContent = "Entrar"; btn.disabled = false;
    if (error){ err.textContent = error.message === "Invalid login credentials" ? "Correo o contraseña incorrectos." : error.message; return; }
    const { data } = await sb.auth.getSession();
    enterApp(data.session);
  });
  $("#logoutBtn").addEventListener("click", async () => { await sb.auth.signOut(); $("#password").value=""; showLogin(); });
  $("#tabs").addEventListener("click", e => { const b = e.target.closest("button"); if (b) switchTab(b.dataset.tab); });

  $(".dash-filters").addEventListener("click", e => {
    const b = e.target.closest(".filter-pill"); if (!b) return;
    if (b.dataset.range !== undefined){
      $$('.filter-pill[data-range]').forEach(x => x.classList.remove("active")); b.classList.add("active");
      state.range = b.dataset.range;
    } else if (b.dataset.depto !== undefined){
      $$('.filter-pill[data-depto]').forEach(x => x.classList.remove("active")); b.classList.add("active");
      state.depto = b.dataset.depto;
    }
    loadDashboard();
  });

  $("#admSeg").addEventListener("click", e => { const b = e.target.closest("button"); if (!b) return;
    $$("#admSeg button").forEach(x => x.classList.remove("active")); b.classList.add("active");
    state.admTab = b.dataset.adm; loadAdmin();
  });
  $("#admNew").addEventListener("click", () => state.admTab === "preguntas" ? editPregunta(null) : editDispositivo(null));
}

/* ---------------------------------------------------------------- boot */
(function(){
  if (!initClient()) return;
  wire();
  sb.auth.onAuthStateChange((_e, session) => { if (!session) showLogin(); });
  checkSession();
})();
