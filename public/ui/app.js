(() => {
  const $ = (sel) => document.querySelector(sel);
  const $$ = (sel) => Array.from(document.querySelectorAll(sel));

  const state = {
    baseUrl: localStorage.getItem('savant.baseUrl') || `${location.protocol}//${location.host}`,
    userId: localStorage.getItem('savant.userId') || '',
    engines: [],
    currentEngine: null,
    currentTool: null,
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
    const d = $('#toolDetail');
    d.innerHTML = `<div><b>${name}</b></div><div>${desc || ''}</div><details><summary>Schema</summary><pre>${JSON.stringify(schema || {}, null, 2)}</pre></details>`;
    $('#toolInput').value = '{}';
  }

  async function runTool() {
    if (!state.currentEngine || !state.currentTool) return;
    let payload = {};
    try { payload = JSON.parse($('#toolInput').value || '{}'); } catch { payload = {}; }
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

