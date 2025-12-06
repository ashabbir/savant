import React, { useEffect, useState } from 'react';
import Grid from '@mui/material/Grid2';
import Paper from '@mui/material/Paper';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import Stack from '@mui/material/Stack';
import Chip from '@mui/material/Chip';
import Alert from '@mui/material/Alert';
import Button from '@mui/material/Button';
import LinearProgress from '@mui/material/LinearProgress';
import { agentRunRead, getErrorMessage } from '../../api';
import { Link, useNavigate, useParams } from 'react-router-dom';

function TranscriptView({ transcript }: { transcript: any }) {
  if (!transcript) return <Typography variant="body2" color="text.secondary">No transcript available.</Typography>;
  const steps = transcript.steps || [];
  return (
    <Stack spacing={1}>
      {steps.map((s: any, idx: number) => (
        <Paper key={idx} variant="outlined" sx={{ p: 1 }}>
          <Stack direction="row" spacing={1} alignItems="center">
            <Chip size="small" label={`#${s.index || idx+1}`} />
            <Chip size="small" label={s.action?.action || s.action || 'step'} />
            {s.action?.tool_name && <Chip size="small" color="primary" label={s.action.tool_name} />}
          </Stack>
          {s.action?.final && <Typography variant="body2" sx={{ mt: 1 }}>{s.action.final}</Typography>}
          {s.output && <pre style={{ margin: 0, marginTop: 8, whiteSpace: 'pre-wrap' }}>{JSON.stringify(s.output, null, 2)}</pre>}
          {s.note && <Typography variant="caption" color="text.secondary">{s.note}</Typography>}
        </Paper>
      ))}
    </Stack>
  );
}

export default function AgentRun() {
  const params = useParams();
  const name = params.name || '';
  const runId = Number(params.id || '0');
  const nav = useNavigate();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [data, setData] = useState<any>(null);

  useEffect(() => {
    setLoading(true); setError(null);
    agentRunRead(name, runId).then((d)=> { setData(d); }).catch((e)=> setError(getErrorMessage(e as any))).finally(()=> setLoading(false));
  }, [name, runId]);

  return (
    <Grid container spacing={2}>
      <Grid size={{ xs: 12, md: 10 }}>
        <Paper sx={{ p:2, display: 'flex', flexDirection: 'column', gap: 1 }}>
          <Stack direction="row" alignItems="center" justifyContent="space-between">
            <Typography variant="subtitle1">Agent Run: {name}</Typography>
            <Stack direction="row" spacing={1}>
              {data?.id && <Chip size="small" label={`#${data.id}`} />}
              {data?.status && <Chip size="small" color={data.status === 'ok' ? 'success' : 'warning'} label={data.status} />}
              {typeof data?.duration_ms === 'number' && <Chip size="small" label={`${data.duration_ms} ms`} />}
            </Stack>
          </Stack>
          {loading && <LinearProgress />}
          {error && <Alert severity="error">{error}</Alert>}
          {!loading && !error && (
            <>
              {data?.output_summary && <Alert severity={data.status === 'ok' ? 'success' : 'error'}>{data.output_summary}</Alert>}
              <TranscriptView transcript={data?.transcript} />
              <Stack direction="row" spacing={1} sx={{ mt: 1 }}>
                <Button size="small" component={Link} to="/diagnostics/logs">View Logs</Button>
                <Button size="small" component={Link} to="/diagnostics/agent">Agent Diagnostics</Button>
                <Button size="small" onClick={() => nav('/engines/agents')}>Back</Button>
              </Stack>
            </>
          )}
        </Paper>
      </Grid>
    </Grid>
  );
}

