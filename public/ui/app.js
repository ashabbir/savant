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
  };

  function saveSettings() {
    const baseUrl = $('#baseUrl')?.value || state.baseUrl;
    const userId = $('#userId')?.value || state.userId;
    state.baseUrl = baseUrl; state.userId = userId;
    localStorage.setItem('savant.baseUrl', baseUrl);
    localStorage.setItem('savant.userId', userId);
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
      $('#dashboard').textContent = JSON.stringify(data, null, 2);
      renderEnginesList();
    } catch (e) { $('#dashboard').textContent = String(e); }
  }

  function renderEnginesList() {
    const ul = $('#engineList');
    if (!ul) return;
    ul.innerHTML = '';
    state.engines.forEach((e) => {
      const li = document.createElement('li');
      li.textContent = `${e.name} (${e.tools})`;
      li.onclick = () => selectEngine(e.name);
      ul.appendChild(li);
    });
  }

  async function selectEngine(name) {
    state.currentEngine = name;
    $('#toolList').innerHTML = '';
    $('#toolDetail').textContent = '';
    $('#toolResult').textContent = '';
    try {
      const data = await api(`/${name}/tools`);
      const tools = data.tools || [];
      const ul = $('#toolList');
      tools.forEach((t) => {
        const nm = t.name || t['name'];
        const desc = t.description || t['description'] || '';
        const li = document.createElement('li');
        li.textContent = `${nm} — ${desc}`;
        li.onclick = () => selectTool(nm, desc, t.schema || t['schema']);
        ul.appendChild(li);
      });
    } catch (e) { $('#toolList').innerHTML = `<li>${e}</li>`; }
  }

  function selectTool(name, desc, schema) {
    state.currentTool = name;
    state.currentSchema = schema || {};
    const d = $('#toolDetail');
    d.innerHTML = `<div><b>${name}</b></div><div>${desc || ''}</div><details><summary>Schema</summary><pre>${JSON.stringify(schema || {}, null, 2)}</pre></details>`;
    // Default to form mode if schema is simple object, otherwise JSON
    const simple = isSimpleObjectSchema(state.currentSchema);
    setInputMode(simple ? 'form' : 'json');
    if (simple) buildForm(state.currentSchema);
    $('#toolInput').value = '{}';
  }

  async function runTool() {
    if (!state.currentEngine || !state.currentTool) return;
    const mode = currentMode();
    let payload = {};
    if (mode === 'json') {
      try { payload = JSON.parse($('#toolInput').value || '{}'); } catch { payload = {}; }
    } else {
      payload = collectForm();
    }
    const body = JSON.stringify({ params: payload });
    const t0 = performance.now();
    try {
      const res = await api(`/${state.currentEngine}/tools/${state.currentTool}/call`, { method: 'POST', headers: { 'content-type': 'application/json' }, body });
      const ms = Math.round(performance.now() - t0);
      $('#toolResult').textContent = JSON.stringify({ elapsed_ms: ms, result: res }, null, 2);
    } catch (e) {
      $('#toolResult').textContent = String(e);
    }
  }

  function streamTool() {
    if (!state.currentEngine || !state.currentTool) return;
    const mode = currentMode();
    let payload = {};
    if (mode === 'json') {
      try { payload = JSON.parse($('#toolInput').value || '{}'); } catch { payload = {}; }
    } else {
      payload = collectForm();
    }
    const qp = encodeURIComponent(JSON.stringify(payload));
    const url = `${state.baseUrl}/${state.currentEngine}/tools/${state.currentTool}/stream?params=${qp}&user=${encodeURIComponent(state.userId)}`;
    try { state.sse && state.sse.close(); } catch {}
    $('#toolResult').textContent = '';
    state.sse = new EventSource(url);
    state.sse.onmessage = (ev) => {
      try {
        const data = JSON.parse(ev.data);
        $('#toolResult').textContent += `${ev.type || 'event'}: ${JSON.stringify(data)}\n`;
      } catch {
        $('#toolResult').textContent += `${ev.type || 'event'}: ${ev.data}\n`;
      }
    };
    state.sse.addEventListener('result', (ev) => {
      try { const d = JSON.parse(ev.data); $('#toolResult').textContent += `result: ${JSON.stringify(d, null, 2)}\n`; } catch {}
    });
    state.sse.addEventListener('error', (ev) => { $('#toolResult').textContent += `error: ${ev.data}\n`; try { state.sse.close(); } catch {} });
    state.sse.addEventListener('done', () => { $('#toolResult').textContent += `done\n`; try { state.sse.close(); } catch {} });
  }

  function currentMode() {
    const selected = document.querySelector('input[name="mode"]:checked');
    return selected ? selected.value : 'json';
  }

  function setInputMode(mode) {
    const formEl = $('#toolForm');
    const jsonEl = $('#toolInput');
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
    const form = $('#toolForm');
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
    $$('#toolForm [data-key]').forEach((el) => {
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
      $('#routes').textContent = JSON.stringify(data, null, 2);
    } catch (e) { $('#routes').textContent = String(e); }
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
    $('#baseUrl').value = state.baseUrl; $('#userId').value = state.userId;
    $('#saveSettings').onclick = saveSettings;
    renderStatus();

    // Views
    $$('#settingsSave').forEach((b) => b.onclick = saveSettingsView);
    $('#routesExpand').onchange = loadRoutes;
    $('#runTool').onclick = runTool;
    $('#streamTool').onclick = streamTool;
    $$('input[name="mode"]').forEach((el) => el.addEventListener('change', (ev) => {
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
    $$('nav button').forEach((btn) => btn.onclick = () => switchView(btn.dataset.view));

    // Default to dashboard
    switchView('dashboard');
  }

  document.addEventListener('DOMContentLoaded', init);
})();
