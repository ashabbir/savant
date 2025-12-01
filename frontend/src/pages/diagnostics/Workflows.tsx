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

function useWorkflowEvents() {
  const [data, setData] = React.useState<{ events: any[] } | null>(null);
  const [error, setError] = React.useState<any>(null);
  const [loading, setLoading] = React.useState(false);
  const base = (window as any).SAVANT_BASE_URL || '';
  async function fetchNow() {
    try {
      setLoading(true);
      const res = await fetch(`${base}/diagnostics/workflows?n=200`);
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
  const ev = useWorkflowEvents();
  const events = (ev.data?.events || []).slice().reverse();
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
            Full trace: <a href="/diagnostics/workflows/trace" target="_blank" rel="noreferrer">download JSONL</a>
          </Typography>
        </Paper>
      </Grid>
    </Grid>
  );
}

