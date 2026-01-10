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
import FormControl from '@mui/material/FormControl';
import Select from '@mui/material/Select';
import MenuItem from '@mui/material/MenuItem';
import { agentRun, agentRunCancel, agentRunCancelId, agentsDelete, agentRunDelete, agentRunsClearAll, agentsUpdate, getErrorMessage, useAgent, useAgents, useAgentRuns, getUserId, loadConfig, callEngineTool } from '../../api';
import Snackbar from '@mui/material/Snackbar';
import { useNavigate } from 'react-router-dom';
import { useQueryClient, useQuery } from '@tanstack/react-query';
import ContentCopyIcon from '@mui/icons-material/ContentCopy';
import ArticleIcon from '@mui/icons-material/Article';
import Viewer from '../../components/Viewer';
import yaml from 'js-yaml';

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
  const [toast, setToast] = useState<string | null>(null);
  const [yamlOpen, setYamlOpen] = useState(false);
  const [yamlText, setYamlText] = useState('');
  const [yamlError, setYamlError] = useState<string | null>(null);
  const [yamlLoading, setYamlLoading] = useState(false);
  const [copyOpen, setCopyOpen] = useState(false);
  const [copyName, setCopyName] = useState('');
  const [copyInstructions, setCopyInstructions] = useState('');
  const [copyLoading, setCopyLoading] = useState(false);
  const { data, isLoading, isError, error, refetch } = useAgents();
  const details = useAgent(sel);
  const runs = useAgentRuns(sel);
  const hasRunning = useMemo(() => {
    const list = runs.data?.runs || [];
    return list.some((r: any) => String(r.status || '').toLowerCase() === 'running');
  }, [runs.data]);

  // Live diagnostics polling for compact per-run previews (only while there is a running row)
  const [liveEvents, setLiveEvents] = useState<any[]>([]);
  useEffect(() => {
    let cancelled = false;
    let timer: number | null = null;
    async function poll() {
      try {
        if (!hasRunning) { setLiveEvents([]); return; }
        const base = loadConfig().baseUrl || 'http://localhost:9999';
        const res = await fetch(`${base}/diagnostics/agent`, { headers: { 'x-savant-user-id': getUserId() } });
        const js = await res.json();
        const evts: any[] = (js && js.events) || [];
        if (!cancelled) setLiveEvents(evts);
      } catch { /* ignore */ }
      finally {
        if (!cancelled) timer = window.setTimeout(poll, 1500);
      }
    }
    poll();
    return () => { cancelled = true; if (timer) window.clearTimeout(timer); };
  }, [hasRunning, sel]);

  const liveByRun = useMemo(() => {
    const map: Record<number, { step: number; tool?: string; summary?: string }> = {};
    (liveEvents || []).forEach((e: any) => {
      const run = Number(e && (e.run ?? e['run']));
      if (!Number.isFinite(run)) return;
      const t = String(e.type || e['type'] || '').toLowerCase();
      if (t !== 'reasoning_step') return;
      const step = Number(e.step ?? e['step']) || 0;
      const tool = (e.tool_name || e['tool_name']) || undefined;
      const summary = (e.metadata && (e.metadata.decision_summary || e.metadata['decision_summary'])) || undefined;
      const prev = map[run];
      if (!prev || step >= prev.step) {
        map[run] = { step, tool, summary };
      }
    });
    return map;
  }, [liveEvents]);
  const llmModelsQuery = useQuery({
    queryKey: ['llm', 'models'],
    queryFn: async () => {
      const res = await callEngineTool('llm', 'llm_models_list', {});
      return (res.models || []) as any[];
    },
    staleTime: 1000 * 60,
  });
  const [favoriteLoading, setFavoriteLoading] = useState<Record<string, boolean>>({});
  const [modelFilter, setModelFilter] = useState<string>('all');
  const modelMap = useMemo(() => {
    const map = new Map<string, any>();
    (llmModelsQuery.data || []).forEach((model: any) => {
      if (model.id || model.provider_model_id) {
        map.set(String(model.id || model.provider_model_id), model);
      }
    });
    return map;
  }, [llmModelsQuery.data]);

  // Get unique models used by agents for the filter dropdown
  const usedModels = useMemo(() => {
    const list = data?.agents || [];
    const modelIds = new Set<string>();
    list.forEach((a: any) => {
      if (a.model_id) modelIds.add(String(a.model_id));
    });
    return Array.from(modelIds).map((id) => {
      const model = modelMap.get(id);
      return { id, label: model ? (model.display_name || model.provider_model_id) : `Model ${id}` };
    }).sort((a, b) => a.label.localeCompare(b.label));
  }, [data, modelMap]);

  const agents = useMemo(() => {
    let list = data?.agents || [];
    // Filter by model
    if (modelFilter !== 'all') {
      list = list.filter((a: any) => String(a.model_id) === modelFilter);
    }
    // Filter by name search
    const f = filter.toLowerCase();
    return f ? list.filter((a) => a.name.toLowerCase().includes(f)) : list;
  }, [data, filter, modelFilter]);

  // Auto-select first agent on initial load or when list updates
  useEffect(() => {
    if (!sel && agents.length > 0) {
      setSel(agents[0].name);
    }
  }, [agents, sel]);


  // Track running flag for the selected agent
  useEffect(() => {
    if (!sel) { setLiveRunning(false); return; }
    setLiveRunning(running || hasRunning);
  }, [sel, running, hasRunning]);


  const queryClient = useQueryClient();

  return (
    <>
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
              <Tooltip title={sel ? 'Copy Agent' : 'Select an agent'}>
                <span>
                  <IconButton
                    size="small"
                    color="primary"
                    disabled={!sel}
                    onClick={() => {
                      if (!sel) return;
                      setCopyName(`${sel}-copy`);
                      setCopyInstructions('');
                      setCopyOpen(true);
                      (async () => {
                        try {
                          setCopyLoading(true);
                          const res = await callEngineTool('agents', 'agents_read', { name: sel });
                          const txt = (res && (res as any).agent_yaml) || '';
                          const obj: any = (txt && yaml.load(txt)) || {};
                          const instr = (obj?.instructions || '').toString();
                          setCopyInstructions(instr);
                        } catch {}
                        finally { setCopyLoading(false); }
                      })();
                    }}
                  >
                    <ContentCopyIcon fontSize="small" />
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
          <Stack direction="row" spacing={1} sx={{ mb: 1 }}>
            <FormControl size="small" sx={{ minWidth: 120 }}>
              <Select
                value={modelFilter}
                onChange={(e) => setModelFilter(e.target.value)}
                displayEmpty
                sx={{ fontSize: 12 }}
              >
                <MenuItem value="all">All Models</MenuItem>
                {usedModels.map((m) => (
                  <MenuItem key={m.id} value={m.id}>{m.label}</MenuItem>
                ))}
              </Select>
            </FormControl>
            <TextField size="small" fullWidth placeholder="Search..." value={filter} onChange={(e) => setFilter(e.target.value)} />
          </Stack>
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
            <Stack direction="row" spacing={1} alignItems="center">
              <Tooltip title="Open Agent YAML">
                <span>
                  <Button
                    size="small"
                    startIcon={<ArticleIcon fontSize="small" />}
                    disabled={!sel}
                    onClick={async () => {
                      if (!sel) return;
                      setYamlLoading(true);
                      setYamlError(null);
                      try {
                        const res = await callEngineTool('agents', 'agents_read', { name: sel });
                        setYamlText(res.agent_yaml || '');
                        setYamlOpen(true);
                      } catch (e: any) {
                        setYamlError(getErrorMessage(e));
                        setYamlOpen(true);
                      } finally {
                        setYamlLoading(false);
                      }
                    }}
                  >
                    YAML
                  </Button>
                </span>
              </Tooltip>
            </Stack>
          </Stack>
          {details.isFetching && <LinearProgress />}
          {details.isError && <Alert severity="error">{getErrorMessage(details.error as any)}</Alert>}
          <Box sx={{ display: 'flex', gap: 2, alignItems: 'center' }}>
            <TextField size="small" fullWidth placeholder="Enter input for run..." value={input} onChange={(e) => setInput(e.target.value)} disabled={running || liveRunning} />
            <Button size="small" startIcon={running || liveRunning ? undefined : <PlayArrowIcon />} disabled={!sel || !input || running || liveRunning} onClick={async () => {
              if (!sel || !input) return;
              setRunning(true);
              try {
                const res = await agentRun(sel, input);
                const newRunId = (res && (res as any).run_id) ? Number((res as any).run_id) : Date.now();
                // Optimistically add to recent runs cache so it shows immediately
                const runsKey = ['agents', 'runs', sel] as const;
                queryClient.setQueryData(runsKey, (old: any) => {
                  const prev = old && Array.isArray(old.runs) ? old.runs : [];
                  const optimistic = {
                    id: newRunId,
                    input,
                    status: 'running',
                    duration_ms: 0,
                    created_at: new Date().toISOString(),
                  };
                  // Avoid duplicating if it already exists
                  const exists = prev.some((r: any) => Number(r.id) === Number(newRunId));
                  return { runs: exists ? prev : [optimistic, ...prev] };
                });
                setInput('');
                setToast('Job submitted');
                // Trigger a background refetch to replace optimistic row with server data
                setTimeout(() => { runs.refetch(); refetch(); }, 150);
                // Keep focus on Agents; no auto-open of Logs to avoid confusion
              } finally {
                setRunning(false);
              }
            }}>{(running || liveRunning) ? (
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                <CircularProgress size={16} /> Running…
              </Box>
            ) : 'Run'}</Button>
            {/* Per-run Stop controls are shown on each run entry below */}
            <Button size="small" href="/diagnostics/agent-runs" target="_blank">View Live</Button>
          </Box>
          {(running || liveRunning) && <LinearProgress sx={{ mt: 1 }} />}

          {/* Live Steps moved to per-run page */}
          <Typography variant="subtitle2" sx={{ mt: 1 }}>Recent Runs</Typography>
          {runs.isFetching && <LinearProgress />}
          {runs.isError && <Alert severity="error">{getErrorMessage(runs.error as any)}</Alert>}
          <Box sx={{ flex: 1, overflowY: 'auto' }}>
            {(() => { const hasRunningRow = ((runs.data?.runs || []).some((r:any) => (r.status || '').toLowerCase() === 'running')); return (running || liveRunning) && !hasRunningRow; })() && (
              <Paper variant="outlined" sx={{ p: 1, mb: 1, borderColor: 'success.main' }}>
                <Stack direction="row" justifyContent="space-between" alignItems="center">
                  <Stack direction="row" spacing={1} alignItems="center">
                    <Chip size="small" color="success" label="running" />
                    {/* Live chips removed; see per-run view */}
                  </Stack>
                  <Stack direction="row" spacing={1}>
                    <Button size="small" disabled>Live</Button>
                  </Stack>
                </Stack>
                {/* Live summary removed; see per-run view */}
              </Paper>
            )}
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
              <Paper key={r.id} variant="outlined" sx={{ px: 1, py: 0.5, mb: 1 }}>
                <Stack direction="row" spacing={1} alignItems="center" sx={{ minHeight: 32 }}>
                  <Chip size="small" label={`#${r.id}`} />
                  <Chip
                    size="small"
                    color={(() => {
                      const s = String(r.status || '').toLowerCase();
                      if (s === 'ok') return 'success';
                      if (s === 'running') return 'info';
                      if (s === 'error') return 'warning';
                      return 'default';
                    })() as any}
                    label={String(r.status ?? 'ok')}
                  />
                  <Chip size="small" label={`${r.duration_ms || 0} ms`} />
                  {typeof r.steps === 'number' && (
                    <Chip size="small" label={`steps ${r.steps}`} />
                  )}
                  <Box sx={{ flex: 1, minWidth: 0 }}>
                    <Typography
                      variant="caption"
                      sx={{ fontFamily: 'monospace', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', display: 'block' }}
                      title={r.input || ''}
                    >
                      {`params: ${r.input || ''}`}
                    </Typography>
                  </Box>
                  {String(r.status || '').toLowerCase() === 'running' && (
                    <>
                      <Button size="small" color="success" variant="contained" onClick={() => nav(`/agents/run/${sel}/${r.id}`)}>Live</Button>
                      <Button size="small" color="error" onClick={async () => {
                        if (!sel) return;
                        // Optimistically mark this row as stopping
                        const runsKey = ['agents', 'runs', sel] as const;
                        queryClient.setQueryData(runsKey, (old: any) => {
                          if (!old || !Array.isArray(old.runs)) return old;
                          return { runs: old.runs.map((it: any) => it.id === r.id ? { ...it, status: 'stopping' } : it) };
                        });
                        try {
                          await agentRunCancelId(sel, r.id);
                        } finally {
                          await runs.refetch();
                          await refetch();
                        }
                      }}>Stop</Button>
                    </>
                  )}
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
                {String(r.status || '').toLowerCase() === 'running' && liveByRun[r.id] && (
                  <Typography variant="caption" sx={{ ml: 1, mt: 0.5, mb: 0.5, display: 'block', opacity: 0.8 }}>
                    Live: step {liveByRun[r.id].step}
                    {liveByRun[r.id].tool ? ` • ${liveByRun[r.id].tool}` : ''}
                    {liveByRun[r.id].summary ? ` — ${liveByRun[r.id].summary}` : ''}
                  </Typography>
                )}
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
      <Dialog open={copyOpen} onClose={() => setCopyOpen(false)}>
        <DialogTitle sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          Copy Agent
          <IconButton size="small" onClick={() => setCopyOpen(false)}>
            <CloseIcon fontSize="small" />
          </IconButton>
        </DialogTitle>
        <DialogContent dividers>
          <Stack spacing={2} sx={{ mt: 1 }}>
            <TextField
              label="New Agent Name"
              value={copyName}
              onChange={(e) => setCopyName(e.target.value)}
              fullWidth
              size="small"
              autoFocus
              placeholder="my-agent-copy"
            />
            <TextField
              label="Instructions (Reason)"
              value={copyInstructions}
              onChange={(e) => setCopyInstructions(e.target.value)}
              fullWidth
              size="small"
              multiline
              minRows={3}
              placeholder="Optional instructions for the copied agent"
            />
            <Typography variant="caption" color="text.secondary">
              A duplicate will be created with the same persona, driver, rules, tools, and instructions.
            </Typography>
          </Stack>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setCopyOpen(false)}>Cancel</Button>
          <Button
            variant="contained"
            disabled={!sel || !copyName.trim() || copyLoading}
            onClick={async () => {
              if (!sel || !copyName.trim()) return;
              try {
                // Read YAML for the source agent
                const res = await callEngineTool('agents', 'agents_read', { name: sel });
                const txt = (res && (res as any).agent_yaml) || '';
                const obj: any = (txt && yaml.load(txt)) || {};
                // Also fetch agent record to get model_id
                let modelId: number | undefined = undefined;
                try {
                  const rec = await callEngineTool('agents', 'agents_get', { name: sel });
                  const mid = Number((rec && (rec as any).model_id) || NaN);
                  if (Number.isFinite(mid)) modelId = mid;
                } catch {}
                // Extract fields for creation
                const persona = (obj?.persona?.name || obj?.persona || 'savant-engineer').toString();
                let driver = '';
                if (obj?.driver) {
                  if (typeof obj.driver === 'string') driver = obj.driver;
                  else driver = (obj.driver.name || obj.driver.prompt_md || '').toString();
                }
                if (!driver) driver = 'developer';
                const rulesArr = Array.isArray(obj?.rules) ? obj.rules : [];
                const rules = rulesArr.map((r: any) => (r && (r.name || r)).toString()).filter((s: string) => !!s);
                const allowedTools = Array.isArray(obj?.tools?.allowlist) ? obj.tools.allowlist : [];
                const instructions = copyInstructions.trim() || (obj?.instructions || '').toString();

                await callEngineTool('agents', 'agents_create', {
                  name: copyName.trim(),
                  persona,
                  driver,
                  rules,
                  favorite: false,
                  instructions,
                  allowed_tools: allowedTools,
                  model_id: modelId,
                });
                setToast('Agent copied');
                setCopyOpen(false);
                setSel(copyName.trim());
                await refetch();
              } catch (e: any) {
                setToast(`Copy failed: ${getErrorMessage(e)}`);
              }
            }}
          >
            Create Copy
          </Button>
        </DialogActions>
      </Dialog>
      <Dialog open={yamlOpen} onClose={() => setYamlOpen(false)} maxWidth="md" fullWidth>
        <DialogTitle sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          Agent YAML
          <Stack direction="row" spacing={1} alignItems="center">
            <IconButton
              size="small"
              onClick={async () => {
                try {
                  await navigator.clipboard.writeText(yamlText || '');
                  setToast('YAML copied');
                } catch {
                  setToast('Copy failed');
                }
              }}
              disabled={!yamlText}
            >
              <ContentCopyIcon fontSize="small" />
            </IconButton>
            <IconButton size="small" onClick={() => setYamlOpen(false)}>
              <CloseIcon fontSize="small" />
            </IconButton>
          </Stack>
        </DialogTitle>
        <DialogContent dividers sx={{ p: 0 }}>
          {yamlLoading && <LinearProgress />}
          {yamlError && <Alert severity="error" sx={{ m: 2 }}>{yamlError}</Alert>}
          {!yamlError && (
            <Viewer content={yamlText || ''} language="yaml" height="70vh" yamlCollapsible />
          )}
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setYamlOpen(false)}>Close</Button>
        </DialogActions>
      </Dialog>
    </Grid>
    <Snackbar open={!!toast} autoHideDuration={2000} onClose={() => setToast(null)} message={toast || ''} anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }} />
    </>
  );
}
