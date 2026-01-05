import React, { useMemo, useState } from 'react';
import Box from '@mui/material/Box';
import Paper from '@mui/material/Paper';
import Typography from '@mui/material/Typography';
import Stack from '@mui/material/Stack';
import Chip from '@mui/material/Chip';
import IconButton from '@mui/material/IconButton';
import RefreshIcon from '@mui/icons-material/Refresh';
import FormControl from '@mui/material/FormControl';
import InputLabel from '@mui/material/InputLabel';
import Select from '@mui/material/Select';
import MenuItem from '@mui/material/MenuItem';
import LinearProgress from '@mui/material/LinearProgress';
import Divider from '@mui/material/Divider';
import { clearReasoning, useReasoningDiagnostics, useReasoningEvents, loadConfig } from '../../api';
import Button from '@mui/material/Button';
import List from '@mui/material/List';
import ListItemButton from '@mui/material/ListItemButton';
import ListItemText from '@mui/material/ListItemText';
import CircularProgress from '@mui/material/CircularProgress';

const EVENT_TYPES = [
  { value: 'all', label: 'All events' },
  { value: 'agent_intent_received', label: 'Agent intent received' },
  { value: 'agent_intent_decision', label: 'Agent decision' },
  { value: 'workflow_intent_received', label: 'Workflow intent received' },
  { value: 'workflow_intent_decision', label: 'Workflow decision' },
  { value: 'reasoning_timeout', label: 'Timeouts' },
  { value: 'reasoning_post_error', label: 'HTTP errors' },
];

function ts(val: any): string {
  try {
    const d = new Date(val);
    if (!isNaN(d.getTime())) return d.toLocaleTimeString();
  } catch {}
  return String(val || '');
}

function labelForType(t: string): string {
  const m = EVENT_TYPES.find((e) => e.value === t);
  return m ? m.label : t;
}

type SelectedSession = { sessionId: string; events: any[] } | null;

export default function DiagnosticsReasoning() {
  const [n, setN] = useState<number>(() => Number(localStorage.getItem('diag.reasoning.n') || '200') || 200);
  const [type, setType] = useState<string>(() => localStorage.getItem('diag.reasoning.type') || 'all');
  const { data, isLoading, refetch } = useReasoningEvents(n, type);
  const diag = useReasoningDiagnostics();
  const [clearing, setClearing] = useState<boolean>(false);
  const [selectedSession, setSelectedSession] = useState<SelectedSession>(null);
  const [selectedEventIdx, setSelectedEventIdx] = useState<number | null>(null);
  const events = data?.events || [];

  React.useEffect(() => { localStorage.setItem('diag.reasoning.n', String(n)); }, [n]);
  React.useEffect(() => { localStorage.setItem('diag.reasoning.type', type); }, [type]);

  const counts = useMemo(() => {
    const acc: Record<string, number> = {};
    for (const ev of events) {
      const t = (ev.event || ev.type || 'unknown').toString();
      acc[t] = (acc[t] || 0) + 1;
    }
    return acc;
  }, [events]);

  function groupKey(e: any): string {
    const run = e.run_id || e.session_id || e.correlation_id || e.job_id || e.intent_id;
    return (run ? String(run) : 'unknown');
  }

  function eventTs(e: any): number {
    const raw = e.timestamp || e.ts || e.time || e.created_at || '';
    const d = new Date(raw);
    return isNaN(d.getTime()) ? 0 : d.getTime();
  }

  const grouped = useMemo(() => {
    const map = new Map<string, any[]>();
    for (const ev of events) {
      const k = groupKey(ev);
      if (!map.has(k)) map.set(k, []);
      map.get(k)!.push(ev);
    }
    for (const [k, arr] of map.entries()) {
      arr.sort((a, b) => eventTs(b) - eventTs(a));
    }
    const out = Array.from(map.entries()).map(([k, arr]) => ({
      id: k,
      latestTs: arr.length ? eventTs(arr[0]) : 0,
      events: arr
    }));
    out.sort((a, b) => b.latestTs - a.latestTs);
    return out;
  }, [events]);

  const selectedEvent = selectedSession && selectedEventIdx !== null ? selectedSession.events[selectedEventIdx] : null;

  return (
    <Box>
      <Paper sx={{ p: 2, mb: 2 }}>
        <Stack direction={{ xs: 'column', sm: 'row' }} spacing={2} alignItems={{ xs: 'stretch', sm: 'center' }} justifyContent="space-between">
          <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>Reasoning Worker Diagnostics</Typography>
          <Stack direction="row" spacing={1} alignItems="center" flexWrap="wrap" useFlexGap>
            {diag.data?.redis === 'connected' ? (
              <Chip size="small" color="success" label="Redis connected" />
            ) : (
              <Chip size="small" color="error" label={`Redis: ${diag.data?.redis || 'disconnected'}`} />
            )}
            {diag.data?.dashboard_url && (
              <Button size="small" variant="outlined" component="a" href={diag.data.dashboard_url.startsWith('/') ? `${loadConfig().baseUrl}${diag.data.dashboard_url}` : diag.data.dashboard_url} target="_blank">Job Dashboard</Button>
            )}
            {diag.data?.workers_url && (
              <Button size="small" variant="outlined" component="a" href={diag.data.workers_url.startsWith('/') ? `${loadConfig().baseUrl}${diag.data.workers_url}` : diag.data.workers_url} target="_blank">Workers</Button>
            )}
            {typeof diag.data?.calls?.total === 'number' && <Chip size="small" label={`Total ${diag.data.calls.total}`} />}
            {typeof diag.data?.calls?.last_24h === 'number' && <Chip size="small" label={`24h ${diag.data.calls.last_24h}`} />}
            <Button size="small" variant="outlined" color="error" disabled={clearing} onClick={async () => {
              try {
                setClearing(true);
                await clearReasoning();
                await Promise.all([refetch(), diag.refetch()]);
              } finally {
                setClearing(false);
              }
            }}>Clear All Activity</Button>
          </Stack>
        </Stack>
        {(diag.data?.recent_completed?.length ?? 0) > 0 && (
          <Box sx={{ mt: 2 }}>
            <Typography variant="caption" sx={{ fontWeight: 600, display: 'block', mb: 0.5 }}>Recent Redis Processing (Completed):</Typography>
            <Stack direction="row" spacing={1} flexWrap="wrap" useFlexGap>
              {diag.data?.recent_completed?.map((j: any, i: number) => (
                <Chip key={i} size="small" variant="outlined" color="success" label={j.job_id || 'job'} sx={{ fontSize: 11 }} />
              ))}
            </Stack>
          </Box>
        )}
        {(diag.data?.recent_failed?.length ?? 0) > 0 && (
          <Box sx={{ mt: 1.5 }}>
            <Typography variant="caption" sx={{ fontWeight: 600, display: 'block', mb: 0.5 }}>Recent Redis Processing (Failed):</Typography>
            <Stack direction="row" spacing={1} flexWrap="wrap" useFlexGap>
              {diag.data?.recent_failed?.map((j: any, i: number) => (
                <Chip key={i} size="small" variant="outlined" color="error" label={j.job_id || 'job'} sx={{ fontSize: 11 }} />
              ))}
            </Stack>
          </Box>
        )}
      </Paper>

      <Paper sx={{ p: 2, mb: 2 }}>
        <Stack direction={{ xs: 'column', sm: 'row' }} spacing={2} alignItems={{ xs: 'stretch', sm: 'center' }} justifyContent="space-between">
          <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>Reasoning Activity</Typography>
          <Stack direction="row" spacing={2} alignItems="center">
            <FormControl size="small" sx={{ minWidth: 200 }}>
              <InputLabel>Event Type</InputLabel>
              <Select value={type} label="Event Type" onChange={(e) => setType(e.target.value)}>
                {EVENT_TYPES.map((t) => (<MenuItem key={t.value} value={t.value}>{t.label}</MenuItem>))}
              </Select>
            </FormControl>
            <FormControl size="small" sx={{ width: 120 }}>
              <InputLabel>Max</InputLabel>
              <Select value={String(n)} label="Max" onChange={(e) => setN(Number(e.target.value))}>
                {[50, 100, 200, 500].map((m) => (<MenuItem key={m} value={String(m)}>{m}</MenuItem>))}
              </Select>
            </FormControl>
            <IconButton onClick={() => refetch()} aria-label="Refresh" title="Refresh">
              <RefreshIcon />
            </IconButton>
          </Stack>
        </Stack>
        {isLoading && <LinearProgress sx={{ mt: 1 }} />}
        <Stack direction="row" spacing={1} sx={{ mt: 1, flexWrap: 'wrap', gap: 1 }}>
          {Object.entries(counts).map(([k, v]) => (
            <Chip key={k} size="small" label={`${labelForType(k)}: ${v}`} />
          ))}
        </Stack>
      </Paper>

      <Stack direction={{ xs: 'column', lg: 'row' }} spacing={2} alignItems="stretch">
        {/* Left: Sessions List */}
        <Paper sx={{ p: 0, flex: 2, minHeight: 400, display: 'flex', flexDirection: 'column' }}>
          <Box sx={{ p: 1.5, borderBottom: '1px solid', borderColor: 'divider' }}>
            <Typography variant="subtitle2">Sessions ({grouped.length})</Typography>
          </Box>
          {isLoading ? (
            <Box sx={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <CircularProgress size={32} />
            </Box>
          ) : grouped.length === 0 ? (
            <Box sx={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', p: 2 }}>
              <Typography variant="body2" sx={{ opacity: 0.7 }}>No reasoning activity found</Typography>
            </Box>
          ) : (
            <List dense disablePadding sx={{ flex: 1, overflow: 'auto' }}>
              {grouped.map((g) => (
                <ListItemButton
                  key={g.id}
                  selected={selectedSession?.sessionId === g.id}
                  onClick={() => {
                    setSelectedSession({ sessionId: g.id, events: g.events });
                    setSelectedEventIdx(null);
                  }}
                  sx={{ py: 0.75 }}
                >
                  <ListItemText
                    primary={`Session ${g.id}`}
                    secondary={`${g.events.length} events • ${ts(g.latestTs)}`}
                    primaryTypographyProps={{ fontSize: 13, fontWeight: 500 }}
                    secondaryTypographyProps={{ fontSize: 11 }}
                  />
                </ListItemButton>
              ))}
            </List>
          )}
        </Paper>

        {/* Middle: Events List */}
        <Paper sx={{ p: 0, flex: 2, minHeight: 400, display: 'flex', flexDirection: 'column' }}>
          <Box sx={{ p: 1.5, borderBottom: '1px solid', borderColor: 'divider' }}>
            <Typography variant="subtitle2">
              {selectedSession ? `Events: ${selectedSession.sessionId}` : 'Select a session'}
            </Typography>
          </Box>
          {!selectedSession ? (
            <Box sx={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', p: 2 }}>
              <Typography variant="body2" sx={{ opacity: 0.7 }}>Select a session to view its events</Typography>
            </Box>
          ) : (
            <List dense disablePadding sx={{ flex: 1, overflow: 'auto' }}>
              {selectedSession.events.map((e: any, idx: number) => (
                <Box key={idx}>
                  <ListItemButton
                    selected={selectedEventIdx === idx}
                    onClick={() => setSelectedEventIdx(idx)}
                    sx={{ py: 0.75 }}
                  >
                    <ListItemText
                      primary={`${e.event || e.type || 'event'} • ${ts(e.timestamp)}`}
                      secondary={e.goal_text ? String(e.goal_text).substring(0, 50) : e.tool_name || 'no goal'}
                      primaryTypographyProps={{ fontSize: 12 }}
                      secondaryTypographyProps={{ fontSize: 11 }}
                    />
                  </ListItemButton>
                  <Divider />
                </Box>
              ))}
            </List>
          )}
        </Paper>

        {/* Right: Event Details */}
        <Paper sx={{ p: 0, flex: 3, minHeight: 400, display: 'flex', flexDirection: 'column' }}>
          <Box sx={{ p: 1.5, borderBottom: '1px solid', borderColor: 'divider' }}>
            <Typography variant="subtitle2">
              {selectedEvent ? `Event Details` : 'Select an event'}
            </Typography>
          </Box>
          {!selectedEvent ? (
            <Box sx={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', p: 2 }}>
              <Typography variant="body2" sx={{ opacity: 0.7 }}>Select an event to view its details</Typography>
            </Box>
          ) : (
            <Box sx={{ flex: 1, overflow: 'auto', p: 2 }}>
              <Stack spacing={2}>
                <Box>
                  <Typography variant="caption" sx={{ opacity: 0.7, display: 'block', mb: 0.5 }}>
                    Event Type
                  </Typography>
                  <Chip label={selectedEvent.event || selectedEvent.type || 'event'} size="small" />
                </Box>

                <Box>
                  <Typography variant="caption" sx={{ opacity: 0.7, display: 'block', mb: 0.5 }}>
                    Timestamp
                  </Typography>
                  <Typography variant="body2">{ts(selectedEvent.timestamp)}</Typography>
                </Box>

                {selectedEvent.goal_text && (
                  <Box>
                    <Typography variant="caption" sx={{ opacity: 0.7, display: 'block', mb: 0.5 }}>
                      Goal
                    </Typography>
                    <Typography variant="body2">{selectedEvent.goal_text}</Typography>
                  </Box>
                )}

                {selectedEvent.reasoning && (
                  <Box>
                    <Typography variant="caption" sx={{ opacity: 0.7, display: 'block', mb: 0.5 }}>
                      Reasoning
                    </Typography>
                    <Typography variant="body2" sx={{ fontStyle: 'italic' }}>{selectedEvent.reasoning}</Typography>
                  </Box>
                )}

                {selectedEvent.tool_name && (
                  <Box>
                    <Typography variant="caption" sx={{ opacity: 0.7, display: 'block', mb: 0.5 }}>
                      Tool Requested
                    </Typography>
                    <Chip label={selectedEvent.tool_name} size="small" color="info" />
                  </Box>
                )}

                {selectedEvent.tool_args && (
                  <Box>
                    <Typography variant="caption" sx={{ opacity: 0.7, display: 'block', mb: 0.5 }}>
                      Tool Args
                    </Typography>
                    <Box
                      component="pre"
                      sx={{
                        p: 1,
                        bgcolor: '#0d1117',
                        color: '#c9d1d9',
                        borderRadius: 1,
                        fontSize: 11,
                        maxHeight: 200,
                        overflow: 'auto',
                      }}
                    >
                      {JSON.stringify(selectedEvent.tool_args, null, 2)}
                    </Box>
                  </Box>
                )}

                {selectedEvent.final_text && (
                  <Box>
                    <Typography variant="caption" sx={{ opacity: 0.7, display: 'block', mb: 0.5 }}>
                      Final Result
                    </Typography>
                    <Typography variant="body2">{selectedEvent.final_text}</Typography>
                  </Box>
                )}

                {typeof selectedEvent.finish === 'boolean' && (
                  <Box>
                    <Typography variant="caption" sx={{ opacity: 0.7, display: 'block', mb: 0.5 }}>
                      Status
                    </Typography>
                    <Chip label={selectedEvent.finish ? 'Finished' : 'Continue'} size="small" />
                  </Box>
                )}

                {(selectedEvent.session_id || selectedEvent.run_id || selectedEvent.llm_provider || selectedEvent.llm_model) && (
                  <>
                    <Divider />
                    <Box>
                      <Typography variant="caption" sx={{ opacity: 0.7, display: 'block', mb: 0.5 }}>
                        Metadata
                      </Typography>
                      <Stack direction="row" spacing={0.5} sx={{ flexWrap: 'wrap', gap: 0.5 }}>
                        {selectedEvent.session_id && <Chip size="small" variant="outlined" label={`session ${selectedEvent.session_id}`} />}
                        {selectedEvent.run_id && <Chip size="small" variant="outlined" label={`run ${selectedEvent.run_id}`} />}
                        {selectedEvent.llm_provider && <Chip size="small" variant="outlined" label={selectedEvent.llm_provider} />}
                        {selectedEvent.llm_model && <Chip size="small" variant="outlined" label={selectedEvent.llm_model} />}
                      </Stack>
                    </Box>
                  </>
                )}

                <Divider />
                <Box>
                  <Typography variant="caption" sx={{ opacity: 0.7, display: 'block', mb: 0.5 }}>
                    Raw Event
                  </Typography>
                  <Box
                    component="pre"
                    sx={{
                      p: 1,
                      bgcolor: '#0d1117',
                      color: '#c9d1d9',
                      borderRadius: 1,
                      fontSize: 10,
                      maxHeight: 300,
                      overflow: 'auto',
                    }}
                  >
                    {JSON.stringify(selectedEvent, null, 2)}
                  </Box>
                </Box>
              </Stack>
            </Box>
          )}
        </Paper>
      </Stack>
    </Box>
  );
}
