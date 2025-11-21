(() => {
  const $ = (sel) => document.querySelector(sel);
  const $$ = (sel) => Array.from(document.querySelectorAll(sel));

  const state = {
    baseUrl: localStorage.getItem('savant.baseUrl') || `${location.protocol}//${location.host}`,
    userId: localStorage.getItem('savant.userId') || '',
    engines: [],
    currentEngine: null,
    currentTool: null,
    currentSchema: null,
    sse: null,
    routes: [],
  };

  function saveSettings() {
    // Only used from Settings tab; header no longer contains inputs
    renderStatus();
  }

  function saveSettingsView() {
    const baseUrl = $('#settingsBaseUrl').value;
    const userId = $('#settingsUserId').value;
    state.baseUrl = baseUrl; state.userId = userId;
    localStorage.setItem('savant.baseUrl', baseUrl);
    localStorage.setItem('savant.userId', userId);
    renderStatus();
  }

  function renderStatus() {
    $('#status').textContent = `URL: ${state.baseUrl} · user: ${state.userId || '—'}`;
  }

  async function api(path, opts = {}) {
    if (!state.userId) throw new Error('Set user ID in settings');
    const url = path.startsWith('http') ? path : state.baseUrl + path;
    const headers = Object.assign({ 'x-savant-user-id': state.userId }, opts.headers || {});
    const res = await fetch(url, Object.assign({}, opts, { headers }));
    if (!res.ok) {
      const text = await res.text();
      throw new Error(`HTTP ${res.status}: ${text}`);
    }
    const ct = res.headers.get('content-type') || '';
    return ct.includes('application/json') ? res.json() : res.text();
  }

  async function loadDashboard() {
    try {
      const data = await api('/');
      state.engines = data.engines || [];
      renderDashboardSummary(data);
      renderDashboardEngines();
    } catch (e) {
      console.error('Dashboard load error', e);
      const errEl = document.getElementById('dashboardSummary');
      if (errEl) errEl.textContent = String(e);
    }
  }

  function renderDashboardSummary(data) {
    const el = $('#dashboardSummary');
    if (!el) return;
    const hub = data.hub || {};
    const trans = data.transport || 'sse';
    const version = data.version || '';
    const service = data.service || 'Savant MCP Hub';
    const pid = hub.pid || '';
    const up = formatUptime(hub.uptime_seconds || 0);
    el.innerHTML = `
      <div style="display:flex; align-items:center; justify-content:space-between; margin-bottom: 8px;">
        <div><strong>${service}</strong> <span class="chip">${version}</span> <span class="chip">${trans.toUpperCase()}</span></div>
        <div class="chip">PID ${pid}</div>
      </div>
      <div class="grid">
        <div class="kv"><span class="k">Uptime</span><span class="v">${up}</span></div>
        <div class="kv"><span class="k">Mounted Engines</span><span class="v">${(data.engines||[]).length}</span></div>
      </div>
    `;
  }

  function renderDashboardEngines() {
    const container = $('#dashEngineCards');
    if (!container) return;
    container.innerHTML = '';
    state.engines.forEach((e) => {
      const card = document.createElement('div');
      card.className = 'card';
      card.dataset.engine = e.name;
      const up = formatUptime(e.uptime_seconds || 0);
      card.innerHTML = `
        <div class="title">${e.name}</div>
        <div class="meta">path: ${e.path}</div>
        <div class="meta">tools: ${e.tools} · status: ${e.status || 'running'} · up: ${up}</div>
        <div class="actions"><button data-engine="${e.name}" class="openEngine">Open</button></div>
      `;
      container.appendChild(card);
    });
    $$('.openEngine').forEach((btn) => btn.onclick = (ev) => {
      const name = ev.currentTarget.dataset.engine;
      // Stay on dashboard; open right drawer (narrow) with tools
      openRightDrawerForEngine(name);
    });
  }

  function formatUptime(sec) {
    const s = Math.max(0, parseInt(sec, 10) || 0);
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const ss = s % 60;
    return `${h}h ${m}m ${ss}s`;
  }

  function renderEnginesList() {
    const container = $('#engineCards');
    if (!container) return;
    container.innerHTML = '';
    state.engines.forEach((e) => {
      const card = document.createElement('div');
      card.className = 'card';
      card.dataset.engine = e.name;
      const status = e.status || 'running';
      card.innerHTML = `
        <div class="title">${e.name}</div>
        <div class="meta">tools: ${e.tools} · status: ${status}</div>
      `;
      card.onclick = () => openDrawerForEngine(e.name);
      container.appendChild(card);
    });
  }

  async function openRightDrawerForEngine(name) {
    state.currentEngine = name;
    // highlight selected card
    $$('#engineCards .card, #dashEngineCards .card').forEach((c) => c.classList.toggle('selected', c.dataset.engine === name));
    const ul = $('#drawerToolList');
    ul.innerHTML = '';
    const drawer = $('#drawer');
    drawer.classList.add('open');
    drawer.classList.remove('wide');
    drawer.classList.remove('mode-tool');
    drawer.classList.add('mode-list');
    // ensure panel is hidden when showing list
    $('#drawerToolPanel').classList.add('hidden');
    $('#drawerBack').classList.add('hidden');
    try {
      const data = await api(`/${name}/tools`);
      const tools = data.tools || [];
      tools.forEach((t) => {
        const nm = t.name || t['name'];
        const desc = t.description || t['description'] || '';
        const li = document.createElement('li');
        li.className = 'tool-item';
        const icon = document.createElement('span');
        icon.className = 'tool-icon';
        icon.textContent = iconForTool(nm);
        const nameEl = document.createElement('span');
        nameEl.className = 'tool-name';
        nameEl.textContent = nm;
        const descEl = document.createElement('span');
        descEl.className = 'tool-desc';
        descEl.textContent = ` — ${desc}`;
        li.appendChild(icon);
        li.appendChild(nameEl);
        li.appendChild(descEl);
        li.onclick = () => openToolInDrawer(nm, desc, t.schema || t['schema']);
        ul.appendChild(li);
      });
    } catch (e) { ul.innerHTML = `<li>${e}</li>`; }
  }

  // removed left drawer flow

  function iconForTool(name) {
    if (!name) return '🛠️';
    if (name.startsWith('fts/')) return '🔎';
    if (name.startsWith('memory/')) return '🧠';
    if (name.startsWith('fs/')) return '📁';
    if (name.startsWith('repos/')) return '📚';
    if (name.startsWith('jira')) return '🧩';
    return '🛠️';
  }

  function openToolInDrawer(name, desc, schema) {
    state.currentTool = name;
    state.currentSchema = schema || {};
    const drawer = $('#drawer');
    drawer.classList.add('open', 'wide');
    drawer.classList.remove('mode-list');
    drawer.classList.add('mode-tool');
    // show the tool panel
    $('#drawerToolPanel').classList.remove('hidden');
    $('#drawerBack').classList.remove('hidden');
    const d = $('#drawerToolDetail');
    d.innerHTML = `<div><b>${name}</b></div><div>${desc || ''}</div><details><summary>Schema</summary><pre>${JSON.stringify(schema || {}, null, 2)}</pre></details>`;
    const simple = isSimpleObjectSchema(state.currentSchema);
    setInputMode(simple ? 'form' : 'json');
    if (simple) buildForm(state.currentSchema);
    $('#drawerToolInput').value = '{}';
  }

  async function runTool() {
    if (!state.currentEngine || !state.currentTool) return;
    const mode = currentMode();
    let payload = {};
    if (mode === 'json') {
      try { payload = JSON.parse($('#drawerToolInput').value || '{}'); } catch { payload = {}; }
    } else {
      payload = collectForm();
    }
    const body = JSON.stringify({ params: payload });
    const t0 = performance.now();
    try {
      const res = await api(`/${state.currentEngine}/tools/${state.currentTool}/call`, { method: 'POST', headers: { 'content-type': 'application/json' }, body });
      const ms = Math.round(performance.now() - t0);
      $('#drawerToolResult').textContent = JSON.stringify({ elapsed_ms: ms, result: res }, null, 2);
    } catch (e) {
      $('#drawerToolResult').textContent = String(e);
    }
  }

  function streamTool() {
    if (!state.currentEngine || !state.currentTool) return;
    const mode = currentMode();
    let payload = {};
    if (mode === 'json') {
      try { payload = JSON.parse($('#drawerToolInput').value || '{}'); } catch { payload = {}; }
    } else {
      payload = collectForm();
    }
    const qp = encodeURIComponent(JSON.stringify(payload));
    const url = `${state.baseUrl}/${state.currentEngine}/tools/${state.currentTool}/stream?params=${qp}&user=${encodeURIComponent(state.userId)}`;
    try { state.sse && state.sse.close(); } catch {}
    $('#drawerToolResult').textContent = '';
    state.sse = new EventSource(url);
    state.sse.onmessage = (ev) => {
      try {
        const data = JSON.parse(ev.data);
        $('#drawerToolResult').textContent += `${ev.type || 'event'}: ${JSON.stringify(data)}\n`;
      } catch {
        $('#drawerToolResult').textContent += `${ev.type || 'event'}: ${ev.data}\n`;
      }
    };
    state.sse.addEventListener('result', (ev) => {
      try { const d = JSON.parse(ev.data); $('#drawerToolResult').textContent += `result: ${JSON.stringify(d, null, 2)}\n`; } catch {}
    });
    state.sse.addEventListener('error', (ev) => { $('#drawerToolResult').textContent += `error: ${ev.data}\n`; try { state.sse.close(); } catch {} });
    state.sse.addEventListener('done', () => { $('#drawerToolResult').textContent += `done\n`; try { state.sse.close(); } catch {} });
  }

  function currentMode() {
    const selected = document.querySelector('input[name="drawer-mode"]:checked');
    return selected ? selected.value : 'json';
  }

  function setInputMode(mode) {
    const formEl = $('#drawerToolForm');
    const jsonEl = $('#drawerToolInput');
    if (mode === 'form') {
      formEl.classList.remove('hidden');
      jsonEl.classList.add('hidden');
    } else {
      formEl.classList.add('hidden');
      jsonEl.classList.remove('hidden');
    }
  }

  function isSimpleObjectSchema(schema) {
    if (!schema || typeof schema !== 'object') return false;
    if ((schema.type || schema['type']) !== 'object') return false;
    const props = schema.properties || schema['properties'] || {};
    return Object.values(props).every((p) => {
      const t = (p.type || p['type']);
      if (t === 'string' || t === 'integer' || t === 'number' || t === 'boolean') return true;
      if (t === 'array') {
        const it = p.items || p['items'] || {};
        const itType = it.type || it['type'];
        return itType === 'string';
      }
      return false;
    });
  }

  function buildForm(schema) {
    const form = $('#drawerToolForm');
    form.innerHTML = '';
    const props = schema.properties || schema['properties'] || {};
    const required = new Set(schema.required || schema['required'] || []);
    Object.entries(props).forEach(([key, prop]) => {
      const t = prop.type || prop['type'];
      const label = document.createElement('label');
      label.textContent = `${key}${required.has(key) ? ' *' : ''}`;
      label.title = prop.description || prop['description'] || '';
      const fieldWrap = document.createElement('div');
      fieldWrap.className = 'field';
      fieldWrap.appendChild(label);
      let input;
      if (t === 'boolean') {
        input = document.createElement('input');
        input.type = 'checkbox';
        input.dataset.key = key;
      } else if (t === 'integer' || t === 'number') {
        input = document.createElement('input');
        input.type = 'number';
        input.step = t === 'integer' ? '1' : 'any';
        input.dataset.key = key;
      } else if (t === 'array') {
        input = document.createElement('textarea');
        input.rows = 3;
        input.placeholder = 'one per line';
        input.dataset.key = key;
        input.dataset.kind = 'array-string';
      } else {
        input = document.createElement('input');
        input.type = 'text';
        input.placeholder = key;
        input.dataset.key = key;
      }
      fieldWrap.appendChild(input);
      form.appendChild(fieldWrap);
    });
  }

  function collectForm() {
    const out = {};
    $$('#drawerToolForm [data-key]').forEach((el) => {
      const key = el.dataset.key;
      if (el.type === 'checkbox') {
        out[key] = !!el.checked;
      } else if (el.dataset.kind === 'array-string') {
        const lines = (el.value || '').split(/\r?\n/).map((s) => s.trim()).filter(Boolean);
        out[key] = lines;
      } else if (el.type === 'number') {
        const v = el.value;
        if (v === '' || v == null) { out[key] = null; }
        else {
          out[key] = el.step === '1' ? parseInt(v, 10) : parseFloat(v);
        }
      } else {
        out[key] = el.value;
      }
    });
    return out;
  }

  async function loadRoutes() {
    try {
      const expanded = $('#routesExpand').checked;
      const data = await api(`/routes${expanded ? '?expand=1' : ''}`);
      state.routes = Array.isArray(data.routes) ? data.routes : (Array.isArray(data) ? data : []);
      renderRoutesTable(filterRoutes(state.routes, ($('#routesSearch')?.value || '')));
    } catch (e) {
      const tbody = document.querySelector('#routesTable tbody');
      if (tbody) {
        tbody.innerHTML = '';
        const tr = document.createElement('tr');
        const td = document.createElement('td');
        td.colSpan = 3; td.textContent = String(e);
        tr.appendChild(td); tbody.appendChild(tr);
      }
    }
  }

  function renderRoutesTable(routes) {
    const tbody = document.querySelector('#routesTable tbody');
    if (!tbody) return;
    tbody.innerHTML = '';
    if (!Array.isArray(routes) || routes.length === 0) {
      const tr = document.createElement('tr');
      const td = document.createElement('td');
      td.colSpan = 3;
      td.textContent = 'No routes';
      tr.appendChild(td);
      tbody.appendChild(tr);
      return;
    }
    routes.forEach((r) => {
      const tr = document.createElement('tr');
      const tdM = document.createElement('td'); tdM.textContent = r.method || r.METHOD || '';
      const tdP = document.createElement('td'); tdP.textContent = r.path || r.PATH || '';
      const tdD = document.createElement('td'); tdD.textContent = r.description || '';
      tr.appendChild(tdM); tr.appendChild(tdP); tr.appendChild(tdD);
      tbody.appendChild(tr);
    });
  }

  function filterRoutes(routes, q) {
    const query = (q || '').toLowerCase().trim();
    if (!query) return routes;
    return routes.filter((r) => {
      const m = (r.method || '').toString().toLowerCase();
      const p = (r.path || '').toString().toLowerCase();
      const d = (r.description || '').toString().toLowerCase();
      return m.includes(query) || p.includes(query) || d.includes(query);
    });
  }

  async function logsTail() {
    const engine = $('#logsEngine').value || 'context';
    const n = parseInt($('#logsN').value || '100', 10);
    try {
      const data = await api(`/${engine}/logs?n=${n}`);
      const lines = data.lines || [];
      $('#logsOut').textContent = lines.join('\n');
    } catch (e) { $('#logsOut').textContent = String(e); }
  }

  function logsFollow() {
    const engine = $('#logsEngine').value || 'context';
    const n = parseInt($('#logsN').value || '100', 10);
    const url = `${state.baseUrl}/${engine}/logs?stream=1&n=${n}&user=${encodeURIComponent(state.userId)}`;
    try { state.sse.close(); } catch {}
    state.sse = new EventSource(url);
    $('#logsStop').disabled = false;
    state.sse.onmessage = (ev) => {
      // Expect SSE lines encoded as event: log / data: {line:"..."}
      try {
        const data = JSON.parse(ev.data);
        $('#logsOut').textContent += (data.line || '') + '\n';
      } catch { /* ignore */ }
    };
    state.sse.onerror = () => { try { state.sse.close(); } catch {}; $('#logsStop').disabled = true; };
  }

  function logsStop() {
    try { state.sse.close(); } catch {}
    $('#logsStop').disabled = true;
  }

  function logsClear() { $('#logsOut').textContent = ''; }

  function switchView(id) {
    $$('.view').forEach((v) => v.classList.add('hidden'));
    $(`#view-${id}`)?.classList.remove('hidden');
    if (id === 'dashboard') loadDashboard();
    if (id === 'routes') loadRoutes();
  }

  function init() {
    // Header settings panel
    // Header inputs removed; settings managed in Settings tab only
    const saveBtn = document.getElementById('saveSettings');
    if (saveBtn) saveBtn.onclick = saveSettings;
    renderStatus();

    // Views
    $$('#settingsSave').forEach((b) => b.onclick = saveSettingsView);
    $('#routesExpand').onchange = loadRoutes;
    const rs = document.getElementById('routesSearch');
    if (rs) rs.addEventListener('input', (ev) => {
      renderRoutesTable(filterRoutes(state.routes, ev.target.value));
    });
    $('#drawerRunTool').onclick = runTool;
    $('#drawerStreamTool').onclick = streamTool;
    $('#drawerClose').onclick = () => { const d = $('#drawer'); d.classList.remove('open', 'wide', 'mode-tool'); d.classList.add('mode-list'); $('#drawerToolPanel').classList.add('hidden'); };
    $('#drawerBack').onclick = () => { const d = $('#drawer'); d.classList.remove('wide', 'mode-tool'); d.classList.add('mode-list'); $('#drawerBack').classList.add('hidden'); $('#drawerToolPanel').classList.add('hidden'); };
    $$('input[name="drawer-mode"]').forEach((el) => el.addEventListener('change', (ev) => {
      const mode = ev.target.value;
      setInputMode(mode);
      if (mode === 'form' && isSimpleObjectSchema(state.currentSchema)) {
        buildForm(state.currentSchema);
      }
    }));
    $('#logsTail').onclick = logsTail;
    $('#logsFollow').onclick = logsFollow;
    $('#logsStop').onclick = logsStop;
    $('#logsClear').onclick = logsClear;
    $$('#view-settings #settingsBaseUrl').forEach((i) => i.value = state.baseUrl);
    $$('#view-settings #settingsUserId').forEach((i) => i.value = state.userId);

    // Nav
    $$('nav button[data-view]').forEach((btn) => btn.onclick = () => switchView(btn.dataset.view));
    const cog = document.getElementById('settingsCog');
    if (cog) cog.onclick = () => switchView('settings');

    // Default to dashboard
    switchView('dashboard');
  }

  document.addEventListener('DOMContentLoaded', init);
})();
