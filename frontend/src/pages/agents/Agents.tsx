import React, { useEffect, useMemo, useRef, useState } from 'react';
import Grid from '@mui/material/Unstable_Grid2';
import Paper from '@mui/material/Paper';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import CircularProgress from '@mui/material/CircularProgress';
import LinearProgress from '@mui/material/LinearProgress';
import Alert from '@mui/material/Alert';
import List from '@mui/material/List';
import ListItem from '@mui/material/ListItem';
import ListItemButton from '@mui/material/ListItemButton';
import ListItemText from '@mui/material/ListItemText';
import Stack from '@mui/material/Stack';
import Chip from '@mui/material/Chip';
import IconButton from '@mui/material/IconButton';
import Tooltip from '@mui/material/Tooltip';
import AddCircleIcon from '@mui/icons-material/AddCircle';
import PlayArrowIcon from '@mui/icons-material/PlayArrow';
import EditIcon from '@mui/icons-material/Edit';
import DeleteOutlineIcon from '@mui/icons-material/DeleteOutline';
import FavoriteIcon from '@mui/icons-material/Favorite';
import FavoriteBorderIcon from '@mui/icons-material/FavoriteBorder';
import TextField from '@mui/material/TextField';
import Button from '@mui/material/Button';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import DialogActions from '@mui/material/DialogActions';
import CloseIcon from '@mui/icons-material/Close';
import { agentRun, agentRunCancel, agentsDelete, agentRunDelete, agentRunsClearAll, agentsUpdate, getErrorMessage, useAgent, useAgents, useAgentRuns, getUserId, loadConfig, callEngineTool } from '../../api';
import { useNavigate } from 'react-router-dom';
import { useQueryClient, useQuery } from '@tanstack/react-query';

const PANEL_HEIGHT = 'calc(100vh - 260px)';

export default function Agents() {
  const nav = useNavigate();
  const [filter, setFilter] = useState('');
  const [sel, setSel] = useState<string | null>(null);
  const [input, setInput] = useState('');
  const [running, setRunning] = useState(false);
  const [liveRunning, setLiveRunning] = useState(false);
  const [runningMap, setRunningMap] = useState<Record<string, boolean>>({});
  const [runningCounts, setRunningCounts] = useState<Record<string, number>>({});
  const esRef = useRef<EventSource | null>(null);
  const activityRef = useRef<Record<string, { start?: number; done?: number }>>({});
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [confirmName, setConfirmName] = useState<string | null>(null);
  const { data, isLoading, isError, error, refetch } = useAgents();
  const details = useAgent(sel);
  const runs = useAgentRuns(sel);
  const llmModelsQuery = useQuery({
    queryKey: ['llm', 'models'],
    queryFn: async () => {
      const res = await callEngineTool('llm', 'llm_models_list', {});
      return (res.models || []) as any[];
    },
    staleTime: 1000 * 60,
  });
  const [favoriteLoading, setFavoriteLoading] = useState<Record<string, boolean>>({});
  const modelMap = useMemo(() => {
    const map = new Map<string, any>();
    (llmModelsQuery.data || []).forEach((model: any) => {
      if (model.id || model.provider_model_id) {
        map.set(String(model.id || model.provider_model_id), model);
      }
    });
    return map;
  }, [llmModelsQuery.data]);

  const agents = useMemo(() => {
    const list = data?.agents || [];
    const f = filter.toLowerCase();
    return f ? list.filter((a) => a.name.toLowerCase().includes(f)) : list;
  }, [data, filter]);

  // Auto-select first agent on initial load or when list updates
  useEffect(() => {
    if (!sel && agents.length > 0) {
      setSel(agents[0].name);
    }
  }, [agents, sel]);

  // Live running status via SSE events (agent_run_started / agent_run_completed)
  useEffect(() => {
    // Open a single SSE to aggregated events for agent
    if (esRef.current) return;
    const base = loadConfig().baseUrl || 'http://localhost:9999';
    const es = new EventSource(`${base}/logs/stream?mcp=agent&user=${encodeURIComponent(getUserId())}`);
    const onEvent = (payload: any) => {
      try {
        const e = typeof payload === 'string' ? JSON.parse(payload) : payload;
        if (!e || e.mcp !== 'agent' || !e.type) return;
        const a = (e.agent || '').toString();
        if (!a) return;
        const t = Number(e.timestamp || Date.now()/1000);
        const acc = activityRef.current[a] || {};
        if (e.type === 'agent_run_started') acc.start = t;
        if (e.type === 'agent_run_completed') acc.done = t;
        activityRef.current[a] = acc;
        // If current selected matches, recompute liveRunning
        if (a === sel) {
          const runningNow = acc.start !== undefined && (acc.done === undefined || (acc.done || 0) < (acc.start || 0));
          setLiveRunning(runningNow);
        }
        // Update counters and maps for list badges
        setRunningCounts((prev) => {
          const cur = prev[a] || 0;
          let next = cur;
          if (e.type === 'agent_run_started') next = cur + 1;
          if (e.type === 'agent_run_completed') next = Math.max(0, cur - 1);
          const out = { ...prev, [a]: next };
          setRunningMap((pm) => ({ ...pm, [a]: next > 0 }));
          if (a === sel) setLiveRunning(next > 0);
          return out;
        });
      } catch { /* ignore */ }
    };
    es.onmessage = (ev) => onEvent(ev.data);
    es.addEventListener('event', (ev: any) => onEvent(ev?.data));
    es.onerror = () => { /* keep connection; server may drop */ };
    esRef.current = es;
    return () => { esRef.current?.close(); esRef.current = null; };
  }, [sel]);

  // When selected agent changes, recompute status from buffered activity
  useEffect(() => {
    if (!sel) { setLiveRunning(false); return; }
    const cnt = runningCounts[sel] || 0;
    setLiveRunning(cnt > 0);
  }, [sel, runningCounts]);

  const queryClient = useQueryClient();

  return (
    <Grid container spacing={2}>
      <Grid xs={12} md={4}>
        <Paper sx={{ p: 1, height: PANEL_HEIGHT, display: 'flex', flexDirection: 'column' }}>
          <Stack direction="row" alignItems="center" justifyContent="space-between" sx={{ mb: 1 }}>
            <Typography variant="subtitle1" sx={{ fontSize: 12 }}>Agents</Typography>
            <Stack direction="row" spacing={1} alignItems="center">
              <Tooltip title="New Agent">
                <IconButton size="small" color="primary" onClick={() => nav('/agents/new')}>
                  <AddCircleIcon fontSize="small" />
                </IconButton>
              </Tooltip>
              <Tooltip title={sel ? 'Edit Agent' : 'Select an agent'}>
                <span>
                  <IconButton size="small" color="primary" disabled={!sel} onClick={() => sel && nav(`/agents/edit/${sel}`)}>
                    <EditIcon fontSize="small" />
                  </IconButton>
                </span>
              </Tooltip>
              <Tooltip title={sel ? 'Delete Agent' : 'Select an agent'}>
                <span>
                  <IconButton size="small" color="error" disabled={!sel} onClick={() => {
                    if (sel) {
                      setConfirmName(sel);
                      setConfirmOpen(true);
                    }
                  }}>
                    <DeleteOutlineIcon fontSize="small" />
                  </IconButton>
                </span>
              </Tooltip>
            </Stack>
          </Stack>
          {isLoading && <LinearProgress />}
          {isError && <Alert severity="error">{getErrorMessage(error as any)}</Alert>}
          <TextField size="small" fullWidth placeholder="Search agents..." value={filter} onChange={(e) => setFilter(e.target.value)} sx={{ mb: 1 }} />
          <List dense sx={{ flex: 1, overflowY: 'auto' }}>
            {agents.map((a) => {
              const modelKey = a.model_id ? String(a.model_id) : null;
              const model = modelKey ? modelMap.get(modelKey) : null;
              const modelLabel = model
                ? `${model.display_name || model.provider_model_id} @ ${model.provider_name || 'unknown'}`
                : 'Not assigned';
              const personaLabel = a.persona_name || a.driver || 'Default persona';
              const rulesLabel = (Array.isArray(a.rules_names) && a.rules_names.length > 0)
                ? a.rules_names.join(', ')
                : 'No rules';
              return (
                <ListItem key={a.name} disablePadding secondaryAction={
                  <Stack direction="row" spacing={1} alignItems="center">
                    {runningMap[a.name] && (
                      <Chip size="small" color="success" label={`running ${runningCounts[a.name] || 1}`} />
                    )}
                    <Chip size="small" label={`runs ${a.run_count || 0}`} />
                    <IconButton
                      size="small"
                      color={a.favorite ? 'error' : 'default'}
                      disabled={!!favoriteLoading[a.name]}
                      onClick={async (ev) => {
                        ev.stopPropagation();
                        const nextValue = !a.favorite;
                        setFavoriteLoading((prev) => ({ ...prev, [a.name]: true }));
                        const listKey = ['agents', 'list'] as const;
                        const getKey = ['agents', 'get', a.name] as const;
                        const prevList = queryClient.getQueryData(listKey);
                        const prevGet = queryClient.getQueryData(getKey);
                        try {
                          queryClient.setQueryData(listKey, (old: any) => {
                            if (!old || !old.agents) return old;
                            return {
                              ...old,
                              agents: old.agents.map((it: any) => it.name === a.name ? { ...it, favorite: nextValue } : it)
                            };
                          });
                          queryClient.setQueryData(getKey, (old: any) => old ? { ...old, favorite: nextValue } : old);
                          await agentsUpdate({ name: a.name, favorite: nextValue });
                          await refetch();
                          queryClient.invalidateQueries(listKey);
                          queryClient.invalidateQueries(getKey);
                        } catch (e) {
                          if (prevList) queryClient.setQueryData(listKey, prevList as any);
                          if (prevGet) queryClient.setQueryData(getKey, prevGet as any);
                        } finally {
                          setFavoriteLoading((prev) => {
                            const next = { ...prev };
                            delete next[a.name];
                            return next;
                          });
                        }
                      }}
                    >
                      {favoriteLoading[a.name] ? <CircularProgress size={16} /> : (a.favorite ? <FavoriteIcon fontSize="small" /> : <FavoriteBorderIcon fontSize="small" />)}
                    </IconButton>
                  </Stack>
                }>
                  <ListItemButton selected={sel === a.name} onClick={() => setSel(a.name)}>
                    <Stack sx={{ flex: 1, minWidth: 0 }} spacing={0.5}>
                      <Stack direction="row" spacing={1} alignItems="center">
                        <Typography variant="caption" color="text.secondary" sx={{ minWidth: 32 }}>#{a.id}</Typography>
                        <Typography variant="body2" sx={{ fontWeight: 700, flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                          {a.name}
                        </Typography>
                      </Stack>
                      <Stack direction="row" spacing={1} alignItems="center" sx={{ flexWrap: 'wrap', gap: 0.5 }}>
                        <Chip size="small" label={personaLabel} variant="outlined" sx={{ height: 20 }} />
                        <Chip size="small" label={`Rules: ${Array.isArray(a.rules_names) && a.rules_names.length > 0 ? a.rules_names.length : '0'}`} variant="outlined" sx={{ height: 20 }} />
                        <Chip size="small" label={`Runs: ${a.run_count || 0}`} variant="outlined" sx={{ height: 20 }} />
                      </Stack>
                      <Typography variant="caption" color="text.secondary" sx={{ display: 'block', fontSize: '0.75rem' }}>
                        {model?.provider_name && <span style={{ fontStyle: 'italic', marginRight: '4px' }}>{model.provider_name}</span>}
                        {model ? model.display_name || model.provider_model_id : 'Not assigned'}
                      </Typography>
                    </Stack>
                  </ListItemButton>
                </ListItem>
              );
            })}
          </List>
        </Paper>
      </Grid>

      <Grid xs={12} md={8}>
        <Paper sx={{ p: 2, height: PANEL_HEIGHT, display: 'flex', flexDirection: 'column', gap: 1 }}>
          <Stack direction="row" alignItems="center" justifyContent="space-between">
            <Typography variant="subtitle2">Agent Details</Typography>
            <span />
          </Stack>
          {details.isFetching && <LinearProgress />}
          {details.isError && <Alert severity="error">{getErrorMessage(details.error as any)}</Alert>}
          <Box sx={{ display: 'flex', gap: 2, alignItems: 'center' }}>
            <TextField size="small" fullWidth placeholder="Enter input for run..." value={input} onChange={(e) => setInput(e.target.value)} disabled={running || liveRunning} />
            <Button size="small" startIcon={running || liveRunning ? undefined : <PlayArrowIcon />} disabled={!sel || !input || running || liveRunning} onClick={async () => {
              if (!sel || !input) return;
              setRunning(true);
              try { await agentRun(sel, input); setInput(''); await runs.refetch(); await refetch(); } finally { setRunning(false); }
            }}>{(running || liveRunning) ? (
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                <CircularProgress size={16} /> Running…
              </Box>
            ) : 'Run'}</Button>
            <Button size="small" color="error" disabled={!sel || !(running || liveRunning)} onClick={async () => {
              if (!sel) return;
              try { await agentRunCancel(sel); } catch { /* ignore */ }
            }}>Stop</Button>
            <Button size="small" href="/diagnostics/agent" target="_blank">View Live</Button>
          </Box>
          {(running || liveRunning) && <LinearProgress sx={{ mt: 1 }} />}
          <Typography variant="subtitle2" sx={{ mt: 1 }}>Recent Runs</Typography>
          {runs.isFetching && <LinearProgress />}
          {runs.isError && <Alert severity="error">{getErrorMessage(runs.error as any)}</Alert>}
          <Box sx={{ flex: 1, overflowY: 'auto' }}>
            {(runs.data?.runs || []).length > 0 && (
              <Button size="small" variant="outlined" color="error" fullWidth sx={{ mb: 1 }} onClick={async () => {
                if (!sel || !confirm(`Delete all ${runs.data?.runs.length} runs for ${sel}?`)) return;
                await agentRunsClearAll(sel);
                await runs.refetch();
                await refetch();
              }}>
                Clear All Runs
              </Button>
            )}
            {(runs.data?.runs || []).map((r) => (
              <Paper key={r.id} variant="outlined" sx={{ p: 1, mb: 1 }}>
                <Stack direction="row" justifyContent="space-between" alignItems="center">
                  <Stack direction="row" spacing={1} alignItems="center">
                    <Chip size="small" label={`#${r.id}`} />
                    <Chip size="small" color={r.status === 'ok' ? 'success' : 'warning'} label={r.status || 'ok'} />
                    <Chip size="small" label={`${r.duration_ms || 0} ms`} />
                    {typeof r.steps === 'number' && (
                      <Chip size="small" label={`steps ${r.steps}`} />
                    )}
                  </Stack>
                  <Stack direction="row" spacing={1}>
                    <Button size="small" onClick={() => nav(`/agents/run/${sel}/${r.id}`)}>View</Button>
                    <IconButton size="small" color="error" onClick={async () => {
                      if (!sel) return;
                      await agentRunDelete(sel, r.id);
                      await runs.refetch();
                      await refetch();
                    }}>
                      <DeleteOutlineIcon fontSize="small" />
                    </IconButton>
                  </Stack>
                </Stack>
                <Typography variant="body2" sx={{ mt: 1 }}>{r.output_summary || r.final || '(no summary)'}</Typography>
              </Paper>
            ))}
          </Box>
        </Paper>
      </Grid>

      <Dialog open={confirmOpen} onClose={() => setConfirmOpen(false)}>
        <DialogTitle sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          Delete Agent
          <IconButton size="small" onClick={() => setConfirmOpen(false)}>
            <CloseIcon fontSize="small" />
          </IconButton>
        </DialogTitle>
        <DialogContent dividers>
          Are you sure you want to delete "{confirmName}"?
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setConfirmOpen(false)}>Cancel</Button>
          <Button color="error" disabled={!confirmName} onClick={async () => {
            if (!confirmName) return;
            await agentsDelete(confirmName);
            setConfirmOpen(false);
            if (sel === confirmName) setSel(null);
            setConfirmName(null);
            await refetch();
          }}>Delete</Button>
        </DialogActions>
      </Dialog>
    </Grid>
  );
}
