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
import { getUserId, loadConfig } from '../../api';

function useWorkflowEvents() {
  const [data, setData] = React.useState<{ events: any[] } | null>(null);
  const [error, setError] = React.useState<any>(null);
  const [loading, setLoading] = React.useState(false);
  const base = loadConfig().baseUrl || '';
  async function fetchNow() {
    try {
      setLoading(true);
      const res = await fetch(`${base}/diagnostics/workflows?n=200`, { headers: { 'x-savant-user-id': getUserId() } });
      const json = await res.json();
      setData(json);
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
      // Call workflow engine tool directly to avoid 404s on hubs without the diagnostics route
      const res = await fetch(`${base}/workflow/tools/workflow_runs_list/call`, {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'x-savant-user-id': getUserId() },
        body: JSON.stringify({ params: {} })
      });
      const json = await res.json();
      setData(json);
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
                </TableRow>
              </TableHead>
              <TableBody>
                {runs.length === 0 && !runsHook.isLoading && (
                  <TableRow>
                    <TableCell colSpan={5}>
                      <Typography variant="body2" color="text.secondary">No saved workflow runs yet.</Typography>
                    </TableCell>
                  </TableRow>
                )}
                {runs.map((run: any) => (
                  <TableRow key={`${run.workflow}|${run.run_id}`} hover>
                    <TableCell>{run.workflow}</TableCell>
                    <TableCell>
                      <Tooltip title="Download workflow trace" enterDelay={300}>
                        <a
                          href={`${base}/diagnostics/workflows/trace?user=${encodeURIComponent(getUserId())}`}
                          target="_blank"
                          rel="noreferrer"
                          style={{ fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace' }}
                        >
                          {run.run_id}
                        </a>
                      </Tooltip>
                    </TableCell>
                    <TableCell>
                      <Chip label={run.status || 'unknown'} size="small" color={run.status === 'ok' ? 'success' : 'default'} />
                    </TableCell>
                    <TableCell>{run.steps ?? '-'}</TableCell>
                    <TableCell>{run.updated_at || 'n/a'}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </TableContainer>
        </Paper>
      </Grid>
    </Grid>
  );
}
