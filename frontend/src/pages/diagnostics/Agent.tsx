import React, { useEffect, useState } from 'react';
import { Box, Paper, Stack, Typography, Divider, List, ListItemButton, ListItemText, Chip, IconButton, FormGroup, FormControlLabel, Checkbox, Tooltip, ListSubheader } from '@mui/material';
import RefreshIcon from '@mui/icons-material/Refresh';
import GetAppIcon from '@mui/icons-material/GetApp';
import InsertDriveFileIcon from '@mui/icons-material/InsertDriveFile';
import TimelineIcon from '@mui/icons-material/Timeline';
import ViewModuleIcon from '@mui/icons-material/ViewModule';
import PlayArrowIcon from '@mui/icons-material/PlayArrow';
import StopIcon from '@mui/icons-material/Stop';
import { getUserId, loadConfig } from '../../api';

type ReasoningEvent = {
  ts?: string;
  timestamp?: number;
  type: string;
  step: number;
  model?: string;
  prompt_tokens?: number;
  output_tokens?: number;
  duration_ms?: number;
  action?: string;
  tool_name?: string;
  metadata?: { decision_summary?: string };
};

export default function DiagnosticsAgent() {
  const [events, setEvents] = useState<ReasoningEvent[]>([]);
  const [memory, setMemory] = useState<any>(null);
  const [selected, setSelected] = useState<number>(0);
  const [tracePath, setTracePath] = useState<string>('');
  const [loading, setLoading] = useState<boolean>(false);
  const [view, setView] = useState<'grouped' | 'timeline'>(() => (localStorage.getItem('agent.view') as any) || 'timeline');
  const [follow, setFollow] = useState<boolean>(false);
  const [filters, setFilters] = useState<{ [k: string]: boolean }>({
    reasoning_step: true,
    llm_call: true,
    prompt_snapshot: false,
    tool_call_started: true,
    tool_call_completed: true,
    tool_call_error: true,
  });
  const esRef = React.useRef<EventSource | null>(null);

  async function load() {
    setLoading(true);
    const base = loadConfig().baseUrl || 'http://localhost:9999';
    const res = await fetch(`${base}/diagnostics/agent`, { headers: { 'x-savant-user-id': getUserId() } });
    const js = await res.json();
    setEvents((js && js.events) || []);
    setMemory(js && js.memory);
    setTracePath(js && js.trace_path);
    setSelected(0);
    setLoading(false);
  }

  useEffect(() => {
    load();
  }, []);

  useEffect(() => {
    if (!follow) return;
    const base = loadConfig().baseUrl || 'http://localhost:9999';
    const es = new EventSource(`${base}/logs/stream?mcp=agent`);
    es.onmessage = (ev) => {
      try {
        const data = JSON.parse(ev.data || '{}');
        if (!data || !data.type) return;
        setEvents((prev) => {
          const next = [...prev, data];
          return next.slice(-1000);
        });
      } catch { /* ignore */ }
    };
    esRef.current = es;
    return () => {
      esRef.current?.close();
      esRef.current = null;
    };
  }, [follow]);

  const hasSteps = events && events.length > 0;
  const groupList = React.useMemo(() => {
    const byStep: Record<string, ReasoningEvent[]> = {};
    events.forEach((e) => {
      const k = String((e.step as any) ?? '0');
      (byStep[k] = byStep[k] || []).push(e);
    });
    const steps = Object.keys(byStep).sort((a, b) => Number(a) - Number(b));
    return steps.map((s) => {
      const arr = byStep[s];
      const stepNum = Number(s);
      const rs = arr.find((e) => e.type === 'reasoning_step');
      const llm = arr.filter((e) => e.type === 'llm_call');
      const prompt = arr.find((e) => e.type === 'prompt_snapshot');
      const toolStart = arr.find((e) => e.type === 'tool_call_started');
      const toolDone = arr.find((e) => e.type === 'tool_call_completed');
      const toolErr = arr.find((e) => e.type === 'tool_call_error');
      return { step: stepNum, events: arr, rs, llm, prompt, toolStart, toolDone, toolErr };
    });
  }, [events]);

  const runs = React.useMemo(() => {
    // For now, group all events into a single run
    // Can be enhanced later to detect multiple runs based on event patterns
    return events.length > 0 ? [{ run: 1, events }] : [];
  }, [events]);

  const selEv = view === 'timeline' ? (events[selected] || null) : (groupList[selected]?.rs || groupList[selected]?.events?.[0] || null);

  function summarize(): string {
    try {
      const st = (memory && memory.steps) || [];
      if (st.length === 0) return 'No steps recorded.';
      const toolSteps = st.filter((s: any) => (s.action && s.action.action) === 'tool');
      const finishSteps = st.filter((s: any) => (s.action && s.action.action) === 'finish');
      const errSteps = (memory.errors || []);
      if (toolSteps.length === 0 && finishSteps.length === 1 && st.length === 1) {
        return 'Model finished immediately without calling any tools.';
      }
      const parts: string[] = [];
      if (toolSteps.length > 0) parts.push(`${toolSteps.length} tool call${toolSteps.length > 1 ? 's' : ''}`);
      if (finishSteps.length > 0) parts.push(`${finishSteps.length} finish action`);
      if (errSteps.length > 0) parts.push(`${errSteps.length} error${errSteps.length > 1 ? 's' : ''}`);
      return parts.length > 0 ? `Executed ${parts.join(', ')}.` : 'Steps recorded.';
    } catch {
      return 'Steps recorded.';
    }
  }

  return (
    <Box>
      <Paper sx={{ p: 1.5, mb: 1.5 }}>
        <Stack direction="row" spacing={2} alignItems="center">
          <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>Agent Diagnostics</Typography>
          <Chip label={`${events.length} steps`} size="small" />
          {tracePath && (
            <Typography variant="caption" sx={{ opacity: 0.7 }}>trace: {tracePath}</Typography>
          )}
          <Box sx={{ flexGrow: 1 }} />
          <Tooltip title={view === 'timeline' ? 'Timeline view' : 'Switch to timeline'}>
            <span>
              <IconButton size="small" color={view === 'timeline' ? 'primary' : 'default'} onClick={() => { setView('timeline'); localStorage.setItem('agent.view','timeline'); }}>
                <TimelineIcon fontSize="small" />
              </IconButton>
            </span>
          </Tooltip>
          <Tooltip title={view === 'grouped' ? 'Grouped view' : 'Switch to grouped'}>
            <span>
              <IconButton size="small" color={view === 'grouped' ? 'primary' : 'default'} onClick={() => { setView('grouped'); localStorage.setItem('agent.view','grouped'); }}>
                <ViewModuleIcon fontSize="small" />
              </IconButton>
            </span>
          </Tooltip>
          <Tooltip title={follow ? 'Live: on' : 'Live: off'}>
            <span>
              <IconButton size="small" color={follow ? 'success' : 'default'} onClick={() => setFollow(!follow)}>
                {follow ? <StopIcon fontSize="small" /> : <PlayArrowIcon fontSize="small" />}
              </IconButton>
            </span>
          </Tooltip>
          <Tooltip title={loading ? 'Refreshing…' : 'Refresh'}>
            <span>
              <IconButton size="small" onClick={load} disabled={loading}>
                <RefreshIcon fontSize="small" />
              </IconButton>
            </span>
          </Tooltip>
        </Stack>
        <Box sx={{ mt: 1 }}>
          <Typography variant="body2" sx={{ opacity: 0.8 }}>
            {summarize()}
          </Typography>
        </Box>
        <Stack direction={{ xs: 'column', sm: 'row' }} spacing={1} sx={{ mt: 1 }}>
          <FormGroup row>
            {Object.keys(filters).map((k) => (
              <FormControlLabel key={k} control={<Checkbox size="small" checked={filters[k]} onChange={(e) => setFilters({ ...filters, [k]: e.target.checked })} />} label={<Typography variant="caption">{k}</Typography>} />
            ))}
          </FormGroup>
          <Box sx={{ flexGrow: 1 }} />
          <Tooltip title="Download trace log">
            <IconButton size="small" href={`${(loadConfig().baseUrl || 'http://localhost:9999')}/diagnostics/agent/trace`} target="_blank">
              <GetAppIcon fontSize="small" />
            </IconButton>
          </Tooltip>
          <Tooltip title="Download session memory">
            <IconButton size="small" href={`${(loadConfig().baseUrl || 'http://localhost:9999')}/diagnostics/agent/session`} target="_blank">
              <InsertDriveFileIcon fontSize="small" />
            </IconButton>
          </Tooltip>
        </Stack>
      </Paper>

      <Stack direction={{ xs: 'column', md: 'row' }} spacing={2} alignItems="stretch">
        <Paper sx={{ p: 0, flex: 4, minHeight: 380, display: 'flex', flexDirection: 'column' }}>
          <Box sx={{ p: 1.5, borderBottom: '1px solid', borderColor: 'divider' }}>
            <Typography variant="subtitle2">Reasoning Timeline</Typography>
          </Box>
          <Box sx={{ flex: 1, minHeight: 0, overflow: 'hidden' }}>
            <List dense disablePadding sx={{ height: '100%', overflow: 'auto' }}>
              {view === 'timeline'
                ? runs.map((r, ri) => (
                    <Box key={ri} component="div">
                      <ListSubheader disableSticky>
                        <Typography variant="caption" sx={{ fontWeight: 600 }}>Run {r.run}</Typography>
                      </ListSubheader>
                      {r.events.filter((e) => !!filters[(e.type as any) || 'reasoning_step']).map((e, i) => (
                        <ListItemButton key={`${ri}-${i}`} sx={{ py: 0.5 }}>
                          <ListItemText
                            primary={`#${e.step || i + 1} ${e.type || ''} ${(e.action || '')} ${(e.tool_name || '')}`.trim()}
                            secondary={`ts=${(e as any).ts || ''} model=${e.model || ''} tokens=${e.prompt_tokens || 0}/${e.output_tokens || 0}`}
                            primaryTypographyProps={{ fontSize: 12 }}
                            secondaryTypographyProps={{ fontSize: 11 }}
                          />
                        </ListItemButton>
                      ))}
                    </Box>
                  ))
                : groupList.map((item: any, i: number) => (
                    <ListItemButton key={i} selected={i === selected} onClick={() => setSelected(i)} sx={{ py: 0.75 }}>
                      <ListItemText
                        primary={`Step #${item.step} ${item.rs?.action || ''} ${item.rs?.tool_name || ''}`.trim()}
                        secondary={`events=${item.events.length}`}
                        primaryTypographyProps={{ fontSize: 12 }}
                        secondaryTypographyProps={{ fontSize: 11 }}
                      />
                    </ListItemButton>
                  ))}
              {events.length === 0 && (
                <Box sx={{ p: 2 }}>
                  <Typography variant="body2" sx={{ opacity: 0.7 }}>No agent events yet. Run an agent session via CLI.</Typography>
                </Box>
              )}
            </List>
          </Box>
        </Paper>
        <Paper sx={{ p: 0, flex: 8, minHeight: 380, display: 'flex', flexDirection: 'column' }}>
          <Box sx={{ p: 1.5, borderBottom: '1px solid', borderColor: 'divider' }}>
            <Typography variant="subtitle2">Step Details</Typography>
          </Box>
          <Box sx={{ flex: 1, minHeight: 0, overflow: 'hidden', p: 2 }}>
            <Box sx={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 2 }}>
              {view === 'timeline' ? (
                selEv ? (
                  <>
                    <Box>
                      <Typography variant="caption" sx={{ opacity: 0.7 }}>Action</Typography>
                      <Typography variant="body2">{selEv.type || 'reasoning_step'} • {selEv.action || ''} {selEv.tool_name ? `→ ${selEv.tool_name}` : ''}</Typography>
                    </Box>
                    <Box>
                      <Typography variant="caption" sx={{ opacity: 0.7 }}>Model</Typography>
                      <Typography variant="body2">{selEv.model} ({selEv.prompt_tokens || 0}/{selEv.output_tokens || 0})</Typography>
                    </Box>
                    <Box sx={{ gridColumn: '1 / -1' }}>
                      <Typography variant="caption" sx={{ opacity: 0.7 }}>Reasoning</Typography>
                      <Typography variant="body2" sx={{ whiteSpace: 'pre-wrap' }}>{selEv.metadata?.decision_summary || ''}</Typography>
                    </Box>
                    <Box sx={{ gridColumn: '1 / -1' }}>
                      <Typography variant="caption" sx={{ opacity: 0.7 }}>Raw Event</Typography>
                      <Box component="pre" sx={{ m: 0, p: 1.5, bgcolor: '#0d1117', color: '#c9d1d9', borderRadius: 1, maxHeight: 300, overflow: 'auto', fontSize: 12 }}>
                        {JSON.stringify(selEv, null, 2)}
                      </Box>
                    </Box>
                  </>
                ) : (
                  <Typography variant="body2" sx={{ p: 1, opacity: 0.7 }}>Select a step to inspect details.</Typography>
                )
              ) : (
                groupList[selected] ? (
                  <>
                    <Box>
                      <Typography variant="caption" sx={{ opacity: 0.7 }}>Step</Typography>
                      <Typography variant="body2">#{groupList[selected].step} • {groupList[selected].rs?.action || ''} {groupList[selected].rs?.tool_name || ''}</Typography>
                    </Box>
                    <Box>
                      <Typography variant="caption" sx={{ opacity: 0.7 }}>LLM</Typography>
                      <Typography variant="body2">{(groupList[selected].llm[0]?.model) || ''} {groupList[selected].llm[0]?.duration_ms ? `(${groupList[selected].llm[0]?.duration_ms}ms)` : ''}</Typography>
                    </Box>
                    <Box>
                      <Typography variant="caption" sx={{ opacity: 0.7 }}>Tool</Typography>
                      <Typography variant="body2">{groupList[selected].toolDone ? `${groupList[selected].toolDone.tool} (${groupList[selected].toolDone.duration_ms || 0}ms)` : (groupList[selected].toolErr ? `error: ${groupList[selected].toolErr.error}` : '—')}</Typography>
                    </Box>
                    <Box sx={{ gridColumn: '1 / -1' }}>
                      <Typography variant="caption" sx={{ opacity: 0.7 }}>Reasoning</Typography>
                      <Typography variant="body2" sx={{ whiteSpace: 'pre-wrap' }}>{groupList[selected].rs?.metadata?.decision_summary || ''}</Typography>
                    </Box>
                    <Box sx={{ gridColumn: '1 / -1' }}>
                      <Typography variant="caption" sx={{ opacity: 0.7 }}>Events</Typography>
                      <Box component="pre" sx={{ m: 0, p: 1.5, bgcolor: '#0d1117', color: '#c9d1d9', borderRadius: 1, maxHeight: 300, overflow: 'auto', fontSize: 12 }}>
                        {JSON.stringify(groupList[selected].events, null, 2)}
                      </Box>
                    </Box>
                  </>
                ) : (
                  <Typography variant="body2" sx={{ p: 1, opacity: 0.7 }}>Select a step to inspect details.</Typography>
                )
              )}
              <Box sx={{ gridColumn: '1 / -1', my: 1 }}>
                <Divider />
              </Box>
              <Box sx={{ gridColumn: '1 / -1' }}>
                <Typography variant="subtitle2" sx={{ mb: 1 }}>Memory Snapshot</Typography>
                <Box component="pre" sx={{ m: 0, p: 1.5, bgcolor: '#0d1117', color: '#c9d1d9', borderRadius: 1, maxHeight: 300, overflow: 'auto', fontSize: 12 }}>
                  {memory ? JSON.stringify(memory, null, 2) : 'No memory snapshot found'}
                </Box>
              </Box>
            </Box>
          </Box>
        </Paper>
      </Stack>
    </Box>
  );
}
