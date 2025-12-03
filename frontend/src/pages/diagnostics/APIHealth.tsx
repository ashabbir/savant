import React from 'react';
import Grid from '@mui/material/Grid2';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import Typography from '@mui/material/Typography';
import IconButton from '@mui/material/IconButton';
import Tooltip from '@mui/material/Tooltip';
import LinearProgress from '@mui/material/LinearProgress';
import Alert from '@mui/material/Alert';
import TextField from '@mui/material/TextField';
import Box from '@mui/material/Box';
import { Checkbox, FormControlLabel } from '@mui/material';
import ContentCopyIcon from '@mui/icons-material/ContentCopy';
import RefreshIcon from '@mui/icons-material/Refresh';
import { useHubInfo, callEngineTool, getUserId, loadConfig, useJiraCreds } from '../../api';
import Chip from '@mui/material/Chip';
import CheckCircleIcon from '@mui/icons-material/CheckCircle';
import ErrorIcon from '@mui/icons-material/Error';

type ToolHealth = {
  engine: string;
  name: string;
  status: 'ok' | 'reachable' | 'html' | 'network' | 'error';
  message?: string;
};

async function retry<T>(fn: () => Promise<T>, tries = 3, baseDelayMs = 200): Promise<T> {
  let attempt = 0;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    try { return await fn(); } catch (e) {
      attempt += 1;
      if (attempt >= tries) throw e;
      const delay = baseDelayMs * Math.pow(2, attempt - 1);
      await new Promise((r) => setTimeout(r, delay));
    }
  }
}

export default function APIHealth() {
  const hub = useHubInfo();
  const jira = useJiraCreds();
  const engines = (hub.data?.engines || []).map((e) => e.name);
  const [filter, setFilter] = React.useState('');
  const [onlyFailures, setOnlyFailures] = React.useState(false);
  const [checking, setChecking] = React.useState(false);
  const [results, setResults] = React.useState<ToolHealth[]>([]);
  const [probeBusy, setProbeBusy] = React.useState(false);
  const [probeOk, setProbeOk] = React.useState<null | boolean>(null);

  async function checkAll() {
    setChecking(true);
    const out: ToolHealth[] = [];
    try {
      const base = loadConfig().baseUrl || '';
      const user = getUserId();
      for (const engine of engines) {
        const res = await fetch(`${base}/${engine}/tools`, { headers: { 'x-savant-user-id': user } });
        const json = await res.json();
        const tools = (json?.tools || []) as any[];
        for (const spec of tools) {
          const name = spec.name || spec['name'];
          if (!name) continue;
          if (filter && !name.toLowerCase().includes(filter.toLowerCase())) continue;
          try {
            await retry(() => callEngineTool(engine, name, {}), 3, 200);
            out.push({ engine, name, status: 'reachable' });
          } catch (err: any) {
            const resp = err?.response;
            if (resp && typeof resp.data === 'object') {
              out.push({ engine, name, status: 'reachable', message: resp.data?.error || 'validation' });
            } else if (resp && typeof resp.data === 'string' && resp.data.trim().startsWith('<')) {
              out.push({ engine, name, status: 'html', message: 'non-JSON (route mismatch or proxy HTML)' });
            } else if (err?.message) {
              out.push({ engine, name, status: 'error', message: err.message });
            } else {
              out.push({ engine, name, status: 'network', message: 'network error' });
            }
          }
        }
      }
    } catch (e: any) {
      out.push({ engine: 'hub', name: 'scan', status: 'network', message: e?.message || 'scan failed' });
    }
    setResults(out);
    setChecking(false);
  }

  function failing(r: ToolHealth) { return r.status === 'html' || r.status === 'network' || r.status === 'error'; }
  const visible = results.filter((r) => !onlyFailures || failing(r));
  const failingOnly = results.filter(failing);

  function copyFailures() {
    const lines = failingOnly.map((r) => `${r.engine} ${r.name} — ${r.status}${r.message ? ' : ' + r.message : ''}`);
    try { navigator.clipboard.writeText(lines.join('\n')); } catch { /* ignore */ }
  }

  return (
    <Grid container spacing={2}>
      {/* Jira Credentials Panel */}
      <Grid size={{ xs: 12 }}>
        <Paper sx={{ p: 1.5 }}>
          <Stack direction="row" spacing={1} alignItems="center" justifyContent="space-between">
            <Stack direction="row" spacing={1} alignItems="center" flexWrap="wrap" useFlexGap>
              <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>Jira Credentials</Typography>
              {jira.isLoading && <LinearProgress sx={{ width: 120 }} />}
              {jira.data && (
                <>
                  <Chip size="small" label={`user: ${jira.data.user || '-'}`} />
                  {jira.data.resolved_user && jira.data.resolved_user !== jira.data.user && (
                    <Chip size="small" label={`resolved: ${jira.data.resolved_user}`} color="warning" />
                  )}
                  <Chip size="small" label={`src: ${jira.data.source}`} variant="outlined" />
                  <Chip size="small" label={`mode: ${jira.data.auth_mode}`} variant="outlined" />
                  <Chip size="small" label={`base_url`} color={jira.data.fields.base_url ? 'success' : 'default'} variant={jira.data.fields.base_url ? 'filled' : 'outlined'} />
                  <Chip size="small" label={`email`} color={jira.data.fields.email ? 'success' : 'default'} variant={jira.data.fields.email ? 'filled' : 'outlined'} />
                  <Chip size="small" label={`api_token`} color={jira.data.fields.api_token ? 'success' : 'default'} variant={jira.data.fields.api_token ? 'filled' : 'outlined'} />
                  <Chip size="small" label={`username`} color={jira.data.fields.username ? 'success' : 'default'} variant={jira.data.fields.username ? 'filled' : 'outlined'} />
                  <Chip size="small" label={`password`} color={jira.data.fields.password ? 'success' : 'default'} variant={jira.data.fields.password ? 'filled' : 'outlined'} />
                  {jira.data.allow_writes != null && (
                    <Chip size="small" label={jira.data.allow_writes ? 'writes on' : 'writes off'} color={jira.data.allow_writes ? 'success' : 'default'} />
                  )}
                  {jira.data.problems?.length > 0 && (
                    <Chip size="small" color="warning" label={`${jira.data.problems.length} issue(s)`} />
                  )}
                </>
              )}
            </Stack>
            <Stack direction="row" spacing={1} alignItems="center">
              <Tooltip title="Refresh">
                <span>
                  <IconButton size="small" onClick={() => jira.refetch()} aria-label="Refresh" disabled={jira.isLoading}>
                    <RefreshIcon fontSize="small" />
                  </IconButton>
                </span>
              </Tooltip>
              <Tooltip title="Probe (jira_self)">
                <span>
                  <IconButton size="small" onClick={async ()=>{
                    setProbeBusy(true);
                    setProbeOk(null);
                    try { await callEngineTool('jira','jira_self',{}); setProbeOk(true); } catch { setProbeOk(false); }
                    setProbeBusy(false);
                  }} aria-label="Probe" disabled={probeBusy}>
                    {probeOk == null ? <RefreshIcon fontSize="small" /> : probeOk ? <CheckCircleIcon color="success" fontSize="small" /> : <ErrorIcon color="error" fontSize="small" />}
                  </IconButton>
                </span>
              </Tooltip>
            </Stack>
          </Stack>
          {jira.data && jira.data.suggestions?.length > 0 && (
            <Box sx={{ mt: 1 }}>
              {jira.data.suggestions.map((s, i) => (
                <Typography key={i} variant="caption" sx={{ display: 'block', color: 'text.secondary' }}>• {s}</Typography>
              ))}
            </Box>
          )}
        </Paper>
      </Grid>
      <Grid size={{ xs: 12 }}>
        <Paper sx={{ p: 2 }}>
          <Stack direction="row" spacing={1} alignItems="center" justifyContent="space-between">
            <Typography variant="h6">API Health</Typography>
            <Stack direction="row" spacing={1}>
              <TextField size="small" label="Filter tools" value={filter} onChange={(e)=>setFilter(e.target.value)} />
              <FormControlLabel control={<Checkbox checked={onlyFailures} onChange={(e)=>setOnlyFailures(e.target.checked)} />} label="Only failures" />
              <Tooltip title="Scan all tools">
                <span>
                  <IconButton color="primary" onClick={checkAll} disabled={checking} aria-label="Scan all">
                    <RefreshIcon />
                  </IconButton>
                </span>
              </Tooltip>
              <Tooltip title="Copy failing">
                <span>
                  <IconButton color="default" onClick={copyFailures} disabled={!failingOnly.length} aria-label="Copy failing">
                    <ContentCopyIcon />
                  </IconButton>
                </span>
              </Tooltip>
            </Stack>
          </Stack>
          {checking && <LinearProgress sx={{ mt: 1 }} />}
          {!engines.length && <Alert sx={{ mt: 1 }} severity="warning">No engines discovered</Alert>}
          <Box sx={{ maxHeight: '70vh', overflow: 'auto', mt: 1 }}>
            {visible.map((r, idx) => (
              <Stack key={`${r.engine}:${r.name}:${idx}`} direction="row" spacing={2} sx={{ py: 0.5, borderBottom: '1px solid #eee' }}>
                <Typography sx={{ minWidth: 90, fontWeight: 600 }}>{r.engine}</Typography>
                <Typography sx={{ fontFamily: 'monospace', flex: 1 }}>{r.name}</Typography>
                <Typography color={r.status === 'ok' || r.status === 'reachable' ? 'success.main' : r.status === 'html' ? 'warning.main' : 'error.main'}>
                  {r.status}
                </Typography>
                {r.message && <Typography sx={{ color: 'text.secondary' }}>{r.message}</Typography>}
              </Stack>
            ))}
            {!visible.length && results.length > 0 && (
              <Typography variant="body2" sx={{ color: 'text.secondary', mt: 1 }}>No results match the current filter.</Typography>
            )}
          </Box>
        </Paper>
      </Grid>
    </Grid>
  );
}
