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
    routesSort: { key: 'path', dir: 'asc' },
    routesFilters: { module: 'hub', method: 'GET' },
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
    loadHeaderInfo();
  }

  function renderStatus() {
    $('#status').textContent = `URL: ${state.baseUrl} · user: ${state.userId || '—'}`;
  }

  async function loadHeaderInfo() {
    const infoEl = document.getElementById('headerInfo');
    if (!infoEl) return;
    try {
      const data = await api('/');
      const service = data.service || 'Savant MCP Hub';
      const version = data.version || '';
      const transport = (data.transport || '').toUpperCase();
      const pid = (data.hub && data.hub.pid) ? data.hub.pid : '';
      const engines = (data.engines || []).map((e) => e.name).join(', ');
      const parts = [];
      if (service) parts.push(service);
      if (version) parts.push(version);
      if (transport) parts.push(transport);
      if (pid) parts.push(`PID ${pid}`);
      if (engines) parts.push(`Engines: ${engines}`);
      infoEl.textContent = parts.join(' · ');
    } catch (e) {
      // Leave header info blank if user not set yet
      infoEl.textContent = '';
    }
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
    const engines = (data.engines || []);
    const chips = engines.map((e) => `<span class="chip">${e.name} · ${formatUptime(e.uptime_seconds || 0)}</span>`).join(' ');
    el.innerHTML = `
      <div style="display:flex; align-items:center; justify-content:space-between; margin-bottom: 8px;">
        <div><strong>${service}</strong> <span class="chip">${version}</span> <span class="chip">${trans.toUpperCase()}</span></div>
        <div class="chip">PID ${pid}</div>
      </div>
      <div class="grid">
        <div class="kv"><span class="k">Uptime</span><span class="v">${up}</span></div>
        <div class="kv"><span class="k">Mounted Engines</span><span class="v">${engines.length}</span></div>
      </div>
      <div class="badge-row">${chips}</div>
    `;
  }

  function renderDashboardEngines() {
    const container = $('#dashEngineCards');
    if (!container) return;
    container.innerHTML = '';
    state.engines.forEach((e) => {
      const card = document.createElement('div');
      card.className = 'card ripple';
      card.dataset.engine = e.name;
      const up = formatUptime(e.uptime_seconds || 0);
      const running = (e.status || 'running').toLowerCase() === 'running';
      const statusDot = `<span class=\"status-dot ${running ? 'status-ok' : 'status-bad'}\"></span>`;
      card.innerHTML = `
        <div class="title">${e.name}</div>
        <div class="subtitle">${e.path}</div>
        <div class="meta-line">tools: ${e.tools}</div>
        <div class="meta-line">uptime: ${up}</div>
        <div class="meta-line">${statusDot}<span>status: ${e.status || 'unknown'}</span></div>
      `;
      // Make the whole card clickable
      card.addEventListener('click', () => openRightDrawerForEngine(e.name));
      container.appendChild(card);
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
      card.className = 'card ripple';
      card.dataset.engine = e.name;
      const status = e.status || 'running';
      const running = (status || 'running').toLowerCase() === 'running';
      const statusDot = `<span class=\"status-dot ${running ? 'status-ok' : 'status-bad'}\"></span>`;
      card.innerHTML = `
        <div class="title">${e.name}</div>
        <div class="subtitle">${e.path || ''}</div>
        <div class="meta-line">tools: ${e.tools}</div>
        <div class="meta-line">${statusDot}<span>status: ${status}</span></div>
      `;
      card.onclick = () => openRightDrawerForEngine(e.name);
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
        const schema = getToolSchema(t);
        const li = document.createElement('li');
        li.className = 'tool-item ripple';
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
        li.onclick = () => openToolInDrawer(nm, desc, schema);
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

  function getToolSchema(toolSpec) {
    if (!toolSpec || typeof toolSpec !== 'object') return {};
    // Prefer inputSchema from backend Tool.spec
    return toolSpec.inputSchema || toolSpec['inputSchema'] || toolSpec.schema || toolSpec['schema'] || {};
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
    // schema considered simple if all props resolve to a known simple kind
    return Object.values(props).every((p) => getSimpleKind(p) !== 'unknown');
  }

  // Map a JSON Schema property to a simple kind we can render
  // Returns: 'string' | 'number' | 'integer' | 'boolean' | 'array-string' | 'array-number' | 'select' | 'unknown'
  function getSimpleKind(prop) {
    if (!prop || typeof prop !== 'object') return 'unknown';
    if (Array.isArray(prop.enum) && (prop.type === 'string' || !prop.type)) return 'select';
    const t = prop.type || prop['type'];
    if (t === 'string' || t === 'number' || t === 'integer' || t === 'boolean') return t;
    if (t === 'array') {
      const it = prop.items || prop['items'] || {};
      const itType = it.type || it['type'];
      if (itType === 'string') return 'array-string';
      if (itType === 'number' || itType === 'integer') return 'array-number';
    }
    // anyOf with simple types
    if (Array.isArray(prop.anyOf)) {
      const kinds = prop.anyOf.map(getSimpleKind);
      if (kinds.includes('array-string')) return 'array-string';
      if (kinds.includes('string')) return 'string';
      if (kinds.includes('array-number')) return 'array-number';
      if (kinds.includes('number')) return 'number';
      if (kinds.includes('integer')) return 'integer';
      if (kinds.includes('boolean')) return 'boolean';
    }
    return 'unknown';
  }

  function buildForm(schema) {
    const form = $('#drawerToolForm');
    form.innerHTML = '';
    const props = schema.properties || schema['properties'] || {};
    const required = new Set(schema.required || schema['required'] || []);
    Object.entries(props).forEach(([key, prop]) => {
      const kind = getSimpleKind(prop);
      if (kind === 'unknown') return; // skip unsupported fields
      const label = document.createElement('label');
      label.textContent = `${key}${required.has(key) ? ' *' : ''}`;
      label.title = prop.description || prop['description'] || '';
      const fieldWrap = document.createElement('div');
      fieldWrap.className = 'field';
      fieldWrap.appendChild(label);
      let input;
      if (kind === 'boolean') {
        input = document.createElement('input');
        input.type = 'checkbox';
        input.dataset.key = key;
      } else if (kind === 'integer' || kind === 'number') {
        input = document.createElement('input');
        input.type = 'number';
        input.step = kind === 'integer' ? '1' : 'any';
        input.dataset.key = key;
      } else if (kind === 'array-string' || kind === 'array-number') {
        input = document.createElement('textarea');
        input.rows = 3;
        input.placeholder = 'one per line';
        input.dataset.key = key;
        input.dataset.kind = kind;
      } else if (kind === 'select') {
        input = document.createElement('select');
        input.dataset.key = key;
        (prop.enum || []).forEach((optVal) => {
          const opt = document.createElement('option');
          opt.value = String(optVal);
          opt.textContent = String(optVal);
          input.appendChild(opt);
        });
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
      } else if (el.dataset.kind === 'array-number') {
        const lines = (el.value || '').split(/\r?\n/).map((s) => s.trim()).filter(Boolean);
        out[key] = lines.map((v) => (v.includes('.') ? parseFloat(v) : parseInt(v, 10)));
      } else if (el.type === 'number') {
        const v = el.value;
        if (v === '' || v == null) { out[key] = null; }
        else {
          out[key] = el.step === '1' ? parseInt(v, 10) : parseFloat(v);
        }
      } else if (el.tagName === 'SELECT') {
        out[key] = el.value;
      } else {
        out[key] = el.value;
      }
    });
    return out;
  }

  async function loadRoutes() {
    try {
      // Always expanded; no UI toggle
      const data = await api(`/routes?expand=1`);
      state.routes = Array.isArray(data.routes) ? data.routes : (Array.isArray(data) ? data : []);
      ensureRoutesFilters(state.routes);
      renderRoutesTable(applyRoutesView(state.routes));
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
    updateRoutesSortHeaders();
    if (!Array.isArray(routes) || routes.length === 0) {
      const tr = document.createElement('tr');
      const td = document.createElement('td');
      td.colSpan = 4;
      td.textContent = 'No routes';
      tr.appendChild(td);
      tbody.appendChild(tr);
      return;
    }
    routes.forEach((r) => {
      const tr = document.createElement('tr');
      const tdMod = document.createElement('td'); tdMod.textContent = routeModule(r);
      const tdM = document.createElement('td'); tdM.textContent = (r.method || r.METHOD || '').toUpperCase();
      const tdP = document.createElement('td'); tdP.textContent = r.path || r.PATH || '';
      const tdD = document.createElement('td'); tdD.textContent = r.description || '';
      tr.appendChild(tdMod); tr.appendChild(tdM); tr.appendChild(tdP); tr.appendChild(tdD);
      tbody.appendChild(tr);
    });
  }

  function filterRoutes(routes, q) {
    const query = (q || '').toLowerCase().trim();
    if (!query) return routes;
    return routes.filter((r) => {
      const mod = routeModule(r).toLowerCase();
      const m = (r.method || '').toString().toLowerCase();
      const p = (r.path || '').toString().toLowerCase();
      const d = (r.description || '').toString().toLowerCase();
      return mod.includes(query) || m.includes(query) || p.includes(query) || d.includes(query);
    });
  }

  function applyRoutesView(routes) {
    // Apply module/method filters and search, then sort
    const moduleSel = ($('#routesModule')?.value || state.routesFilters.module || '').toLowerCase();
    const methodSel = ($('#routesMethod')?.value || state.routesFilters.method || '').toUpperCase();
    const searchQ = ($('#routesSearch')?.value || '');
    let list = routes.slice();
    if (moduleSel && moduleSel !== 'all') list = list.filter((r) => routeModule(r).toLowerCase() === moduleSel);
    if (methodSel && methodSel !== 'ALL') list = list.filter((r) => (r.method || '').toUpperCase() === methodSel);
    list = filterRoutes(list, searchQ);
    const { key, dir } = state.routesSort || { key: 'path', dir: 'asc' };
    const mul = dir === 'desc' ? -1 : 1;
    const getVal = (r) => {
      if (key === 'module') return routeModule(r).toLowerCase();
      if (key === 'method') return (r.method || '').toUpperCase();
      if (key === 'path') return (r.path || '').toLowerCase();
      if (key === 'description') return (r.description || '').toLowerCase();
      return '';
    };
    list.sort((a, b) => (getVal(a) > getVal(b) ? 1 * mul : (getVal(a) < getVal(b) ? -1 * mul : 0)));
    return list;
  }

  function updateRoutesSortHeaders() {
    const { key, dir } = state.routesSort || {};
    $$('#routesTable thead th[data-key]').forEach((th) => {
      th.classList.remove('sort-asc', 'sort-desc');
      if (th.dataset.key === key) th.classList.add(dir === 'desc' ? 'sort-desc' : 'sort-asc');
    });
  }

  function ensureRoutesFilters(routes) {
    // Populate dropdowns for module and method with defaults
    const mods = new Set(['all']);
    const methods = new Set(['ALL']);
    routes.forEach((r) => { mods.add(routeModule(r).toLowerCase()); methods.add((r.method || '').toUpperCase()); });
    const modSel = document.getElementById('routesModule');
    const methSel = document.getElementById('routesMethod');
    if (modSel) {
      const current = modSel.value || state.routesFilters.module || 'hub';
      modSel.innerHTML = '';
      Array.from(mods).sort().forEach((m) => {
        const opt = document.createElement('option');
        opt.value = m; opt.textContent = m === 'all' ? 'All Modules' : m;
        modSel.appendChild(opt);
      });
      modSel.value = (Array.from(mods).includes(current.toLowerCase()) ? current.toLowerCase() : 'hub');
      state.routesFilters.module = modSel.value;
    }
    if (methSel) {
      const current = methSel.value || state.routesFilters.method || 'GET';
      methSel.innerHTML = '';
      Array.from(methods).sort().forEach((m) => {
        const opt = document.createElement('option');
        opt.value = m; opt.textContent = m === 'ALL' ? 'All Methods' : m;
        methSel.appendChild(opt);
      });
      methSel.value = (Array.from(methods).includes(current.toUpperCase()) ? current.toUpperCase() : 'GET');
      state.routesFilters.method = methSel.value;
    }
  }

  // Derive module (engine name) if not provided by backend
  function routeModule(r) {
    if (r && r.module) return String(r.module);
    const path = (r && r.path) ? String(r.path) : '';
    const seg = path.split('/').filter(Boolean)[0];
    return seg || 'hub';
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
    if (id === 'logs') ensureLogsEngines();
  }

  function init() {
    // Header settings panel
    // Header inputs removed; settings managed in Settings tab only
    const saveBtn = document.getElementById('saveSettings');
    if (saveBtn) saveBtn.onclick = saveSettings;
    renderStatus();
    loadHeaderInfo();

    // Views
    $$('#settingsSave').forEach((b) => b.onclick = saveSettingsView);
    // Always expanded; no checkbox handler
    const rs = document.getElementById('routesSearch');
    if (rs) rs.addEventListener('input', (ev) => {
      renderRoutesTable(applyRoutesView(state.routes));
    });
    const modSel = document.getElementById('routesModule');
    if (modSel) modSel.addEventListener('change', (ev) => { state.routesFilters.module = ev.target.value; renderRoutesTable(applyRoutesView(state.routes)); });
    const methSel = document.getElementById('routesMethod');
    if (methSel) methSel.addEventListener('change', (ev) => { state.routesFilters.method = ev.target.value; renderRoutesTable(applyRoutesView(state.routes)); });
    // Sortable table headers
    $$('#routesTable thead th[data-key]').forEach((th) => {
      th.classList.add('sortable');
      th.addEventListener('click', () => {
        const key = th.dataset.key;
        if (state.routesSort.key === key) {
          state.routesSort.dir = (state.routesSort.dir === 'asc') ? 'desc' : 'asc';
        } else {
          state.routesSort = { key, dir: 'asc' };
        }
        renderRoutesTable(applyRoutesView(state.routes));
      });
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
    // Dashboard logs controls
    const dlt = document.getElementById('dashLogsTail'); if (dlt) dlt.onclick = dashLogsTail;
    const dlf = document.getElementById('dashLogsFollow'); if (dlf) dlf.onclick = dashLogsFollow;
    const dls = document.getElementById('dashLogsStop'); if (dls) dls.onclick = dashLogsStop;
    const dlc = document.getElementById('dashLogsClear'); if (dlc) dlc.onclick = dashLogsClear;
    $$('#view-settings #settingsBaseUrl').forEach((i) => i.value = state.baseUrl);
    $$('#view-settings #settingsUserId').forEach((i) => i.value = state.userId);

    // Nav
    $$('nav button[data-view]').forEach((btn) => btn.onclick = () => switchView(btn.dataset.view));
    const cog = document.getElementById('settingsCog');
    if (cog) cog.onclick = () => switchView('settings');

    // Default to dashboard
    switchView('dashboard');
  }

  async function ensureLogsEngines() {
    try {
      if (!state.engines || state.engines.length === 0) {
        const data = await api('/');
        state.engines = data.engines || [];
      }
    } catch (e) {
      // ignore; api() will error if user not set
    }
    const sel = document.getElementById('logsEngine');
    if (!sel) return;
    const current = sel.value;
    sel.innerHTML = '';
    (state.engines || []).forEach((e) => {
      const opt = document.createElement('option');
      opt.value = e.name; opt.textContent = e.name;
      sel.appendChild(opt);
    });
    // Restore selection or default to first
    if (current && Array.from(sel.options).some((o) => o.value === current)) sel.value = current;
  }

  // Dashboard logs preview handlers
  async function dashPopulateLogsEngines() {
    try {
      if (!state.engines || state.engines.length === 0) {
        const data = await api('/');
        state.engines = data.engines || [];
      }
    } catch (e) { /* ignore */ }
    const sel = document.getElementById('dashLogsEngine');
    if (!sel) return;
    const current = sel.value;
    sel.innerHTML = '';
    (state.engines || []).forEach((e) => {
      const opt = document.createElement('option');
      opt.value = e.name; opt.textContent = e.name;
      sel.appendChild(opt);
    });
    if (current && Array.from(sel.options).some((o) => o.value === current)) sel.value = current;
  }

  async function dashLogsTail() {
    await dashPopulateLogsEngines();
    const engine = document.getElementById('dashLogsEngine').value || 'context';
    const n = parseInt(document.getElementById('dashLogsN').value || '100', 10);
    try {
      const data = await api(`/${engine}/logs?n=${n}`);
      const lines = data.lines || [];
      document.getElementById('dashLogsOut').textContent = (lines.length ? lines.join('\n') : (data.note || 'No logs'));
    } catch (e) {
      document.getElementById('dashLogsOut').textContent = String(e);
    }
  }

  async function dashLogsFollow() {
    await dashPopulateLogsEngines();
    const engine = document.getElementById('dashLogsEngine').value || 'context';
    const n = parseInt(document.getElementById('dashLogsN').value || '100', 10);
    const url = `${state.baseUrl}/${engine}/logs?stream=1&n=${n}&user=${encodeURIComponent(state.userId)}`;
    try { state.sse && state.sse.close(); } catch {}
    document.getElementById('dashLogsOut').textContent = '';
    state.sse = new EventSource(url);
    document.getElementById('dashLogsStop').disabled = false;
    state.sse.onmessage = (ev) => {
      try {
        const data = JSON.parse(ev.data);
        document.getElementById('dashLogsOut').textContent += (data.line || '') + '\n';
      } catch {
        document.getElementById('dashLogsOut').textContent += (ev.data || '') + '\n';
      }
    };
    state.sse.onerror = () => { try { state.sse.close(); } catch {}; document.getElementById('dashLogsStop').disabled = true; };
  }

  function dashLogsStop() {
    try { state.sse && state.sse.close(); } catch {}
    document.getElementById('dashLogsStop').disabled = true;
  }

  function dashLogsClear() { document.getElementById('dashLogsOut').textContent = ''; }

  document.addEventListener('DOMContentLoaded', init);
})();
