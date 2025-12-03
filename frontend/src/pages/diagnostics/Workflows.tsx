import React from 'react';
import Grid from '@mui/material/Grid2';
import Paper from '@mui/material/Paper';
import Typography from '@mui/material/Typography';
import LinearProgress from '@mui/material/LinearProgress';
import Alert from '@mui/material/Alert';
import Box from '@mui/material/Box';
import Stack from '@mui/material/Stack';
import IconButton from '@mui/material/IconButton';
import RefreshIcon from '@mui/icons-material/Refresh';
import Table from '@mui/material/Table';
import TableBody from '@mui/material/TableBody';
import TableCell from '@mui/material/TableCell';
import TableContainer from '@mui/material/TableContainer';
import TableHead from '@mui/material/TableHead';
import TableRow from '@mui/material/TableRow';
import Chip from '@mui/material/Chip';
import Tooltip from '@mui/material/Tooltip';
import Button from '@mui/material/Button';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import DialogActions from '@mui/material/DialogActions';
import List from '@mui/material/List';
import ListItem from '@mui/material/ListItem';
import { getUserId, loadConfig } from '../../api';

function useWorkflowEvents() {
  const [data, setData] = React.useState<{ events: any[] } | null>(null);
  const [error, setError] = React.useState<any>(null);
  const [loading, setLoading] = React.useState(false);
  const base = loadConfig().baseUrl || '';
  async function fetchNow() {
    try {
      setLoading(true);
      // Primary endpoint (Hub v0.1.0+)
      let ok = false;
      try {
        const res = await fetch(`${base}/diagnostics/workflows?n=200`, { headers: { 'x-savant-user-id': getUserId() } });
        if (res.ok) {
          const json = await res.json();
          setData(json);
          ok = true;
        }
      } catch { /* fallback below */ }

      // Fallback: aggregated events API filtered by type
      if (!ok) {
        const res2 = await fetch(`${base}/logs?n=200&type=workflow_step`, { headers: { 'x-savant-user-id': getUserId() } });
        if (!res2.ok) throw new Error(`HTTP ${res2.status}`);
        const js2 = await res2.json();
        const events = (js2 && js2.events) || [];
        setData({ events });
      }
      setError(null);
    } catch (e) {
      setError(e);
    } finally {
      setLoading(false);
    }
  }
  React.useEffect(() => { fetchNow(); }, []);
  return { data, error, isLoading: loading, refetch: fetchNow };
}

function useWorkflowRuns() {
  const [data, setData] = React.useState<{ runs: any[] } | null>(null);
  const [error, setError] = React.useState<any>(null);
  const [loading, setLoading] = React.useState(false);
  const base = loadConfig().baseUrl || '';
  async function fetchNow() {
    try {
      setLoading(true);
      // Prefer engine tool if mounted; otherwise fall back to Hub diagnostics route
      let ok = false;
      try {
        const res1 = await fetch(`${base}/workflow/tools/workflow_runs_list/call`, {
          method: 'POST',
          headers: { 'content-type': 'application/json', 'x-savant-user-id': getUserId() },
          body: JSON.stringify({ params: {} })
        });
        if (res1.ok) {
          const js1 = await res1.json();
          setData(js1);
          ok = true;
        }
      } catch {/* ignore and try fallback */}

      if (!ok) {
        const res2 = await fetch(`${base}/diagnostics/workflow_runs`, { headers: { 'x-savant-user-id': getUserId() } });
        const js2 = await res2.json();
        setData(js2);
      }
      setError(null);
    } catch (e) {
      setError(e);
    } finally {
      setLoading(false);
    }
  }
  React.useEffect(() => { fetchNow(); }, []);
  return { data, error, isLoading: loading, refetch: fetchNow };
}

export default function DiagnosticsWorkflows() {
  const base = loadConfig().baseUrl || '';
  const ev = useWorkflowEvents();
  const events = (ev.data?.events || []).slice().reverse();
  const runsHook = useWorkflowRuns();
  const runs = runsHook.data?.runs || [];
  const [detailOpen, setDetailOpen] = React.useState(false);
  const [detailRun, setDetailRun] = React.useState<any>(null);
  const [detailLoading, setDetailLoading] = React.useState(false);
  const [detailError, setDetailError] = React.useState<string | null>(null);

  const showRunDetails = async (run: any) => {
    setDetailRun(null);
    setDetailError(null);
    setDetailLoading(true);
    try {
      const resp = await fetch(`${base}/diagnostics/workflow_runs/${encodeURIComponent(run.workflow)}/${encodeURIComponent(run.run_id)}`);
      if (!resp.ok) {
        throw new Error(await resp.text());
      }
      const payload = await resp.json();
      setDetailRun(payload);
      setDetailOpen(true);
    } catch (err: any) {
      setDetailError(err?.message || 'Unable to load workflow run');
      setDetailOpen(true);
    } finally {
      setDetailLoading(false);
    }
  };
  return (
    <Grid container spacing={2}>
      <Grid size={{ xs: 12 }}>
        <Paper sx={{ p: 2 }}>
          <Stack direction="row" spacing={1} alignItems="center" justifyContent="space-between">
            <Typography variant="h6">Workflow Telemetry</Typography>
            <IconButton size="small" onClick={() => ev.refetch()} aria-label="Refresh"><RefreshIcon fontSize="small" /></IconButton>
          </Stack>
          {ev.isLoading && <LinearProgress sx={{ mt: 1 }} />}
          {ev.error && <Alert severity="error" sx={{ mt: 1 }}>{String(ev.error)}</Alert>}
          <Box sx={{ maxHeight: '60vh', overflow: 'auto', mt: 1 }}>
            {events.length === 0 && <Typography variant="body2" color="text.secondary">No workflow events yet.</Typography>}
            {events.map((e: any, i: number) => (
              <Box key={i} sx={{ py: 0.5, borderBottom: '1px solid #eee' }}>
                <Typography variant="caption" color="text.secondary">{e.timestamp}</Typography>
                <Typography variant="body2" sx={{ fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace' }}>
                  {e.event} step={e.step} type={e.type} duration={e.duration_ms || '-'}ms status={e.status || ''}
                </Typography>
              </Box>
            ))}
          </Box>
          <Typography variant="caption" sx={{ display: 'block', mt: 1 }}>
            Full trace: <a href={`${base}/diagnostics/workflows/trace?user=${encodeURIComponent(getUserId())}`} target="_blank" rel="noreferrer">download JSONL</a>
          </Typography>
        </Paper>
      </Grid>
      <Grid size={{ xs: 12 }}>
        <Paper sx={{ p: 2 }}>
          <Stack direction="row" spacing={1} alignItems="center" justifyContent="space-between">
            <Typography variant="h6">Saved Workflow Runs</Typography>
            <IconButton size="small" onClick={() => runsHook.refetch()} aria-label="Refresh"><RefreshIcon fontSize="small" /></IconButton>
          </Stack>
          {runsHook.isLoading && <LinearProgress sx={{ mt: 1 }} />}
          {runsHook.error && <Alert severity="error" sx={{ mt: 1 }}>{String(runsHook.error)}</Alert>}
          <TableContainer component={Paper} sx={{ mt: 2 }}>
            <Table size="small">
              <TableHead>
                <TableRow>
                  <TableCell>Workflow</TableCell>
                  <TableCell>Run ID</TableCell>
                  <TableCell>Status</TableCell>
                  <TableCell>Steps</TableCell>
                  <TableCell>Updated</TableCell>
                  <TableCell>Actions</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {runs.length === 0 && !runsHook.isLoading && (
                  <TableRow>
                    <TableCell colSpan={6}>
                      <Typography variant="body2" color="text.secondary">No saved workflow runs yet.</Typography>
                    </TableCell>
                  </TableRow>
                )}
                {runs.map((run: any) => (
                  <TableRow key={`${run.workflow}|${run.run_id}`} hover>
                    <TableCell>{run.workflow}</TableCell>
                    <TableCell>
                      <Button size="small" variant="text" onClick={() => showRunDetails(run)} sx={{ justifyContent: 'flex-start', textTransform: 'none' }}>
                        <Typography sx={{ fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace' }}>{run.run_id}</Typography>
                      </Button>
                    </TableCell>
                    <TableCell>
                      <Chip label={run.status || 'unknown'} size="small" color={run.status === 'ok' ? 'success' : 'default'} />
                    </TableCell>
                    <TableCell>{run.steps ?? '-'}</TableCell>
                    <TableCell>{run.updated_at || 'n/a'}</TableCell>
                    <TableCell>
                      <Button size="small" variant="outlined" onClick={() => showRunDetails(run)}>View trace</Button>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </TableContainer>
        </Paper>
      </Grid>
      <Dialog open={detailOpen} fullWidth maxWidth="md" onClose={() => setDetailOpen(false)}>
        <DialogTitle>
          Workflow Trace {detailRun?.workflow || ''} @{detailRun?.run_id || ''}
        </DialogTitle>
        <DialogContent dividers>
          {detailLoading && <LinearProgress />}
          {detailError && <Alert severity="error" sx={{ mb: 1 }}>{detailError}</Alert>}
          {detailRun && (
            <Stack spacing={1}>
              <Stack direction="row" spacing={2}>
                <Typography variant="body2">Status: {detailRun.status}</Typography>
                <Typography variant="body2">Started: {detailRun.started_at || 'n/a'}</Typography>
                <Typography variant="body2">Finished: {detailRun.finished_at || 'n/a'}</Typography>
              </Stack>
              {detailRun.error && <Alert severity="error">{detailRun.error}</Alert>}
              {detailRun.final && (
                <Typography variant="body2" sx={{ fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace' }}>
                  Final: {JSON.stringify(detailRun.final)}
                </Typography>
              )}
              <Typography variant="subtitle2">Steps</Typography>
              <List dense sx={{ maxHeight: 360, overflow: 'auto' }}>
                {Array.isArray(detailRun.steps) ? detailRun.steps.map((step: any, idx: number) => (
                  <ListItem key={`${idx}-${step.name}`} alignItems="flex-start" sx={{ flexDirection: 'column', alignItems: 'stretch' }}>
                    <Stack direction="row" spacing={1} alignItems="center" justifyContent="space-between">
                      <Typography variant="body2" sx={{ fontWeight: 600 }}>{step.name} ({step.type})</Typography>
                      <Chip label={`${step.duration_ms ?? '-'}ms`} size="small" />
                    </Stack>
                    {step.error && <Typography variant="caption" color="error">Error: {step.error}</Typography>}
                    {step.output && (
                      <Typography variant="body2" sx={{ fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace', mt: 0.5 }}>
                        {JSON.stringify(step.output)}
                      </Typography>
                    )}
                  </ListItem>
                )) : <Typography variant="body2" color="text.secondary">No steps recorded.</Typography>}
              </List>
            </Stack>
          )}
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setDetailOpen(false)}>Close</Button>
        </DialogActions>
      </Dialog>
    </Grid>
  );
}
