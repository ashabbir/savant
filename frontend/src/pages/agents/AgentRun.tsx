import React, { useEffect, useState } from 'react';
import Grid from '@mui/material/Unstable_Grid2';
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
  const errors = transcript.errors || [];
  const summaries = transcript.summaries || [];
  const wasSummarized = Array.isArray(steps) && steps.length > 0 && steps[0] && steps[0].index === 'summary';

  return (
    <Stack spacing={2}>
      {/* Steps */}
      {steps.length > 0 && (
        <Box>
          <Typography variant="subtitle2" sx={{ mb: 1 }}>Steps ({steps.length})</Typography>
          {wasSummarized && (
            <Alert severity="info" sx={{ mb: 1 }}>
              This transcript was summarized during execution to keep prompts small. Older steps may be omitted.
            </Alert>
          )}
          <Stack spacing={1}>
            {steps.map((s: any, idx: number) => (
              <Paper key={idx} variant="outlined" sx={{ p: 2 }}>
                <Stack direction="row" spacing={1} alignItems="center" sx={{ mb: 1 }}>
                  <Chip size="small" label={`Step ${s.index || idx + 1}`} color="primary" />
                  <Chip size="small" label={s.action?.action || 'unknown'} />
                  {s.action?.tool_name && <Chip size="small" color="info" label={s.action.tool_name} />}
                </Stack>

                {s.action?.reasoning && (
                  <Box sx={{ mb: 1 }}>
                    <Typography variant="caption" color="text.secondary">Reasoning:</Typography>
                    <Typography variant="body2" sx={{ fontStyle: 'italic' }}>{s.action.reasoning}</Typography>
                  </Box>
                )}

                {s.action?.args && Object.keys(s.action.args).length > 0 && (
                  <Box sx={{ mb: 1 }}>
                    <Typography variant="caption" color="text.secondary">Arguments:</Typography>
                    <Box
                      component="pre"
                      sx={{
                        m: 0,
                        mt: 0.5,
                        p: 1,
                        bgcolor: 'background.paper',
                        color: 'text.primary',
                        border: '1px solid',
                        borderColor: 'divider',
                        borderRadius: 1,
                        fontSize: 12,
                        whiteSpace: 'pre-wrap',
                        overflow: 'auto',
                      }}
                    >
                      {JSON.stringify(s.action.args, null, 2)}
                    </Box>
                  </Box>
                )}

                {s.action?.final && (
                  <Box sx={{ mb: 1 }}>
                    <Typography variant="caption" color="text.secondary">Final:</Typography>
                    <Typography variant="body2">{s.action.final}</Typography>
                  </Box>
                )}

                {s.output && (
                  <Box>
                    <Typography variant="caption" color="text.secondary">Output:</Typography>
                    {s.output.error ? (
                      <Alert severity="error" sx={{ mt: 0.5 }}>{s.output.message || s.output.error}</Alert>
                    ) : (
                      <Box
                        component="pre"
                        sx={{
                          m: 0,
                          mt: 0.5,
                          p: 1,
                          bgcolor: 'background.paper',
                          color: 'text.primary',
                          border: '1px solid',
                          borderColor: 'divider',
                          borderRadius: 1,
                          fontSize: 12,
                          whiteSpace: 'pre-wrap',
                          maxHeight: 200,
                          overflow: 'auto',
                        }}
                      >
                        {typeof s.output === 'string' ? s.output : JSON.stringify(s.output, null, 2)}
                      </Box>
                    )}
                  </Box>
                )}
                {!s.action && s.note && (
                  <Alert severity="info">{s.note}</Alert>
                )}
              </Paper>
            ))}
          </Stack>
        </Box>
      )}

      {/* Errors */}
      {errors.length > 0 && (
        <Box>
          <Typography variant="subtitle2" sx={{ mb: 1 }}>Errors</Typography>
          <Stack spacing={1}>
            {errors.map((e: any, idx: number) => (
              <Alert key={idx} severity="error">
                {e.final || e.error || e.message || 'Unknown error'}
              </Alert>
            ))}
          </Stack>
        </Box>
      )}

      {/* Summaries */}
      {summaries.length > 0 && (
        <Box>
          <Typography variant="subtitle2" sx={{ mb: 1 }}>Summaries</Typography>
          <Stack spacing={1}>
            {summaries.map((summary: any, idx: number) => (
              <Paper key={idx} variant="outlined" sx={{ p: 1 }}>
                <Typography variant="body2">{typeof summary === 'string' ? summary : JSON.stringify(summary)}</Typography>
              </Paper>
            ))}
          </Stack>
        </Box>
      )}
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
      <Grid xs={12}>
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
                <Button size="small" onClick={() => nav('/agents')}>Back</Button>
              </Stack>
            </>
          )}
        </Paper>
      </Grid>
    </Grid>
  );
}
