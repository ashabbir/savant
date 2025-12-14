import React, { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import Box from '@mui/material/Box';
import Grid from '@mui/material/Unstable_Grid2';
import Paper from '@mui/material/Paper';
import Typography from '@mui/material/Typography';
import IconButton from '@mui/material/IconButton';
import Tooltip from '@mui/material/Tooltip';
import OpenInNewIcon from '@mui/icons-material/OpenInNew';
import Stack from '@mui/material/Stack';
import Chip from '@mui/material/Chip';
import LinearProgress from '@mui/material/LinearProgress';
import Alert from '@mui/material/Alert';
// import Button from '@mui/material/Button';
// import TextField from '@mui/material/TextField';
import Table from '@mui/material/Table';
import TableBody from '@mui/material/TableBody';
import TableCell from '@mui/material/TableCell';
import TableHead from '@mui/material/TableHead';
import TableRow from '@mui/material/TableRow';
import TableSortLabel from '@mui/material/TableSortLabel';
import CheckCircleIcon from '@mui/icons-material/CheckCircle';
import ErrorIcon from '@mui/icons-material/Error';
import StorageIcon from '@mui/icons-material/Storage';
import HubIcon from '@mui/icons-material/Hub';
// import PlayArrowIcon from '@mui/icons-material/PlayArrow';
// import TimerIcon from '@mui/icons-material/Timer';
import HttpIcon from '@mui/icons-material/Http';
import ChevronLeftIcon from '@mui/icons-material/ChevronLeft';
import ChevronRightIcon from '@mui/icons-material/ChevronRight';
import { useHubInfo, useDiagnostics, useHubStats, testDbQuery, DbQueryTest } from '../../api';
import SmallMultiples, { SmallSeries } from '../../components/SmallMultiples';
import SmallMultiplesMulti, { MultiSeries } from '../../components/SmallMultiplesMulti';

function formatEngineName(rawName: string): string {
  let clean = rawName
    .replace(/^savant\s*mcp\s*/i, '')
    .replace(/^service[=\-]/i, '')
    .replace(/^savant[=\-]/i, '')
    .replace(/\s*\(unavailable\)/i, '')
    .trim();
  if (!clean) clean = 'Unknown';
  return clean.charAt(0).toUpperCase() + clean.slice(1);
}

function statusColor(status?: string): 'default' | 'success' | 'warning' | 'error' {
  const val = (status || '').toLowerCase();
  if (!val) return 'default';
  if (
    val.includes('ok') ||
    val.includes('online') ||
    val.includes('running') ||
    val.includes('enabled') ||
    val.includes('active') ||
    val.includes('valid')
  ) {
    return 'success';
  }
  if (val.includes('warn') || val.includes('partial') || val.includes('degraded')) return 'warning';
  if (val.includes('error') || val.includes('offline') || val.includes('fail') || val.includes('invalid') || val.includes('bad')) return 'error';
  return 'default';
}

function normalizeModelProgress(model: any): number | null {
  const keys = ['progress', 'progress_percent', 'progress_pct', 'loading_progress', 'download_progress'];
  for (const key of keys) {
    const raw = model?.[key];
    if (raw == null) continue;
    const value = typeof raw === 'string' ? Number(raw) : raw;
    if (Number.isNaN(value)) continue;
    if (value <= 1) {
      return Math.min(Math.max(value * 100, 0), 100);
    }
    if (value <= 100) {
      return Math.min(Math.max(value, 0), 100);
    }
  }
  return null;
}


export default function DiagnosticsOverview() {
  const navigate = useNavigate();
  const hub = useHubInfo();
  const diag = useDiagnostics();
  const stats = useHubStats();
  const llmModels = diag.data?.llm_models;
  const llmModelList = llmModels?.models || [];
  const runningModels = llmModelList.filter((m: any) => m?.enabled === true).length;
  const totalModels = llmModelList.length || (llmModels?.total ?? 0);
  const llmStates = Object.entries(llmModels?.states || {}).filter(([state]) => {
    const normalized = state.toLowerCase();
    return state && normalized !== 'unknown' && normalized !== 'enabled';
  });
  const llmProviders = llmModels?.providers || [];
  const [dbPage, setDbPage] = useState(0);
  const [mongoPage, setMongoPage] = useState(0);
  const [toolsPage, setToolsPage] = useState(0);
  const [httpPage, setHttpPage] = useState(0);
  const [llmPage, setLlmPage] = useState(0);
  const [expanded, setExpanded] = useState<Record<string, boolean>>({});
  const [modelExpanded, setModelExpanded] = useState<Record<string, boolean>>({});
  // Default: collapse all engine entries; clicking toggles to show
  React.useEffect(() => {
    const engines = hub.data?.engines || [];
    if (!engines.length) return;
    setExpanded((prev) => {
      const next = { ...prev } as Record<string, boolean>;
      for (const e of engines) {
        if (next[e.name] === undefined) next[e.name] = false; // default collapsed
      }
      return next;
    });
  }, [hub.data?.engines]);

  // Default-collapse all LLM models
  React.useEffect(() => {
    const list = llmModelList || [];
    if (!list.length) return;
    setModelExpanded((prev) => {
      const next = { ...prev } as Record<string, boolean>;
      for (const m of list as any[]) {
        const key = `${m.provider_name || 'prov'}:${m.provider_model_id || m.name || ''}`;
        if (next[key] === undefined) next[key] = false;
      }
      return next;
    });
  }, [llmModelList]);
  // Sorting state per-table
  const [dbSortBy, setDbSortBy] = useState<'name'|'rows'|'status'>('name');
  const [dbSortDir, setDbSortDir] = useState<'asc'|'desc'>('asc');
  const [mongoSortBy, setMongoSortBy] = useState<'name'|'rows'|'status'>('name');
  const [mongoSortDir, setMongoSortDir] = useState<'asc'|'desc'>('asc');
  const [toolsSortBy, setToolsSortBy] = useState<'engine'|'tool'|'status'|'ms'>('ms');
  const [toolsSortDir, setToolsSortDir] = useState<'asc'|'desc'>('desc');
  const [httpSortBy, setHttpSortBy] = useState<'method'|'path'|'status'|'ms'>('ms');
  const [httpSortDir, setHttpSortDir] = useState<'asc'|'desc'>('desc');
  const PAGE_SIZE = 5;
  // Removed FTS Query Test state


  // Build small multiples per engine using recent requests time-series
  const engineSeries: SmallSeries[] = React.useMemo(() => {
    const out: SmallSeries[] = [];
    // Exclude hub, diagnostics, and logs traffic from charts
    const rec = (stats.data?.recent || []).filter(r => {
      const p = (r.path || '');
      if (r.engine === 'hub') return false;
      if (p.startsWith('/diagnostics')) return false;
      if (p.startsWith('/logs')) return false;
      if (/^\/[\w-]+\/logs/.test(p)) return false; // /:engine/logs
      return true;
    });
    if (!rec.length) return out;
    const engines = Array.from(new Set(rec.map(r => r.engine))).sort();
    // Determine time span and split into 12 buckets
    const times = rec.map(r => new Date(r.time).getTime()).filter(n => !Number.isNaN(n));
    const minT = Math.min(...times);
    const maxT = Math.max(...times);
    const buckets = 12;
    const span = Math.max(1, maxT - minT);
    for (const eng of engines) {
      const vals = new Array(buckets).fill(0);
      for (const r of rec) {
        if (r.engine !== eng) continue;
        const t = new Date(r.time).getTime();
        const idx = span === 0 ? buckets - 1 : Math.min(buckets - 1, Math.max(0, Math.floor(((t - minT) / span) * buckets)));
        vals[idx] += 1;
      }
      out.push({ id: eng, title: eng.charAt(0).toUpperCase() + eng.slice(1), data: vals });
    }
    return out;
  }, [stats.data?.recent]);

  const statusSeries: MultiSeries[] = React.useMemo(() => {
    const out: MultiSeries[] = [];
    const rec = (stats.data?.recent || []).filter(r => {
      const p = (r.path || '');
      if (r.engine === 'hub') return false;
      if (p.startsWith('/diagnostics')) return false;
      if (p.startsWith('/logs')) return false;
      if (/^\/[\w-]+\/logs/.test(p)) return false;
      return true;
    });
    if (!rec.length) return out;
    const engines = Array.from(new Set(rec.map(r => r.engine))).sort();
    // 12 buckets over time
    const times = rec.map(r => new Date(r.time).getTime()).filter(n => !Number.isNaN(n));
    const minT = Math.min(...times);
    const maxT = Math.max(...times);
    const buckets = 12;
    const span = Math.max(1, maxT - minT);
    for (const eng of engines) {
      const ok = new Array(buckets).fill(0);
      const warn = new Array(buckets).fill(0);
      const err = new Array(buckets).fill(0);
      for (const r of rec) {
        if (r.engine !== eng) continue;
        const t = new Date(r.time).getTime();
        const idx = span === 0 ? buckets - 1 : Math.min(buckets - 1, Math.max(0, Math.floor(((t - minT) / span) * buckets)));
        if (r.status < 300) ok[idx] += 1;
        else if (r.status < 500) warn[idx] += 1;
        else err[idx] += 1;
      }
      out.push({ id: eng, title: eng.charAt(0).toUpperCase() + eng.slice(1), data: { ok, warn, err } });
    }
    return out;
  }, [stats.data?.recent]);

  return (
    <Box sx={{ flex: 1, minHeight: 0, overflow: 'auto', display: 'flex', flexDirection: 'column' }}>
      {/* Top Row - Hub Stats */}
      <Paper sx={{ p: 1.5, mb: 1.5 }}>
        <Stack direction="row" spacing={3} alignItems="center" justifyContent="space-between" flexWrap="wrap" useFlexGap>
          <Stack direction="row" spacing={1} alignItems="center">
            <HttpIcon color="primary" />
            <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>Hub Traffic</Typography>
          </Stack>
          {stats.data && (
            <>
              <Box textAlign="center">
                <Typography variant="h5" color="primary" sx={{ fontWeight: 600, lineHeight: 1 }}>
                  {stats.data.requests.total.toLocaleString()}
                </Typography>
                <Typography variant="caption" color="text.secondary">Total Requests</Typography>
              </Box>
              <Stack direction="row" spacing={1} flexWrap="wrap" useFlexGap>
                {Object.entries(stats.data.requests.by_engine).map(([engine, count]) => (
                  <Chip
                    key={engine}
                    size="small"
                    label={`${engine.charAt(0).toUpperCase() + engine.slice(1)}: ${count}`}
                    variant="outlined"
                    color="primary"
                  />
                ))}
              </Stack>
              <Stack direction="row" spacing={0.5} flexWrap="wrap" useFlexGap>
                {Object.entries(stats.data.requests.by_status).map(([status, count]) => (
                  <Chip
                    key={status}
                    size="small"
                    label={`${status}: ${count}`}
                    color={status.startsWith('2') ? 'success' : status.startsWith('4') ? 'warning' : status.startsWith('5') ? 'error' : 'default'}
                    sx={{ height: 22 }}
                  />
                ))}
              </Stack>
              <Stack direction="row" spacing={0.5}>
                {Object.entries(stats.data.requests.by_method).map(([method, count]) => (
                  <Chip key={method} size="small" label={`${method}: ${count}`} variant="outlined" sx={{ height: 22 }} />
                ))}
              </Stack>
            </>
          )}
          {stats.isLoading && <LinearProgress sx={{ width: 100 }} />}
        </Stack>
      </Paper>

      {/* Small Multiples: Requests per Engine (recent) */}
      {engineSeries.length > 0 && (
        <Box sx={{ mb: 1.5 }}>
          <SmallMultiples title="Requests (recent) — per engine" series={engineSeries} height={60} />
        </Box>
      )}

      {/* Small Multiples: Status codes per Engine (recent) */}
      {statusSeries.length > 0 && (
        <Box sx={{ mb: 1.5 }}>
          <SmallMultiplesMulti title="HTTP status (recent) — per engine" series={statusSeries} height={68} />
        </Box>
      )}

      {/* Main Grid */}
      <Grid container spacing={1.5} sx={{ flex: 1, minHeight: 0 }}>
        {/* Left Column - Quick Cards + Requests (scrollable) */}
        <Grid xs={12} md={4}>
          <Stack spacing={1.5} sx={{ height: '100%', overflow: 'auto' }}>
            {/* Quick Cards: Workflows + API Health */}
            <Paper sx={{ p: 1.5, cursor: 'pointer' }} onClick={() => navigate('/diagnostics/workflows')}>
              <Typography variant="subtitle2" sx={{ mb: 0.5, fontWeight: 600 }}>Workflows</Typography>
              <Typography variant="body2" color="text.secondary">
                View recent workflow execution events and download the full trace.
              </Typography>
              <Box sx={{ mt: 1 }}>
                <Tooltip title="Open Workflows Telemetry">
                  <IconButton size="small" onClick={(e)=>{ e.stopPropagation(); navigate('/diagnostics/workflows'); }}>
                    <OpenInNewIcon fontSize="small" />
                  </IconButton>
                </Tooltip>
              </Box>
            </Paper>

            <Paper sx={{ p: 1.5, cursor: 'pointer' }} onClick={() => navigate('/diagnostics/api')}>
              <Typography variant="subtitle2" sx={{ mb: 0.5, fontWeight: 600 }}>API Health</Typography>
              <Typography variant="body2" color="text.secondary">
                Scan engine tool routes and detect mismatches or non‑JSON responses.
              </Typography>
              <Box sx={{ mt: 1 }}>
                <Tooltip title="Open API Health">
                  <IconButton size="small" onClick={(e)=>{ e.stopPropagation(); navigate('/diagnostics/api'); }}>
                    <OpenInNewIcon fontSize="small" />
                  </IconButton>
                </Tooltip>
              </Box>
            </Paper>

            {/* Recent Tool Calls */}
            <Paper sx={{ p: 1.5, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
              <Typography variant="subtitle2" sx={{ mb: 1, fontWeight: 600 }}>Recent Tool Calls</Typography>
              <Box sx={{ flex: 1, overflow: 'auto' }}>
                {stats.data && (() => {
                  const rows = stats.data.recent
                    .filter((req) => (req.path || '').includes('/tools/') && (req.path || '').endsWith('/call'))
                    .map((req) => {
                      const p = (req.path || '');
                      const segs = p.split('/').filter(Boolean);
                      const engine = segs[0] || '';
                      let tool = '';
                      const i1 = p.indexOf('/tools/');
                      const i2 = p.lastIndexOf('/call');
                      if (i1 >= 0 && i2 > i1) tool = p.substring(i1 + 7, i2);
                      return { engine, tool, status: Number(req.status) || 0, ms: Number(req.duration_ms) || 0, _raw: req };
                    });
                  const cmp = (a: any, b: any) => {
                    const dir = toolsSortDir === 'asc' ? 1 : -1;
                    const by = toolsSortBy;
                    if (by === 'status' || by === 'ms') return (a[by] - b[by]) * dir;
                    const av = (a[by] || '').toString().toLowerCase();
                    const bv = (b[by] || '').toString().toLowerCase();
                    return av < bv ? -1 * dir : av > bv ? 1 * dir : 0;
                  };
                  rows.sort(cmp);
                  const total = rows.length;
                  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));
                  const page = Math.min(toolsPage, totalPages - 1);
                  const start = page * PAGE_SIZE;
                  const pageRows = rows.slice(start, start + PAGE_SIZE);
                  const from = total === 0 ? 0 : start + 1;
                  const to = Math.min(start + PAGE_SIZE, total);
                  return (
                    <>
                      <Table size="small" sx={{ '& td, & th': { py: 0.25, px: 0.5, fontSize: 10 } }}>
                        <TableHead>
                          <TableRow>
                            <TableCell sortDirection={toolsSortBy === 'engine' ? toolsSortDir : false as any}>
                              <TableSortLabel active={toolsSortBy === 'engine'} direction={toolsSortDir} onClick={() => {
                                setToolsSortBy('engine');
                                setToolsSortDir(toolsSortBy === 'engine' && toolsSortDir === 'asc' ? 'desc' : 'asc');
                              }}>Engine</TableSortLabel>
                            </TableCell>
                            <TableCell sortDirection={toolsSortBy === 'tool' ? toolsSortDir : false as any}>
                              <TableSortLabel active={toolsSortBy === 'tool'} direction={toolsSortDir} onClick={() => {
                                setToolsSortBy('tool');
                                setToolsSortDir(toolsSortBy === 'tool' && toolsSortDir === 'asc' ? 'desc' : 'asc');
                              }}>Tool</TableSortLabel>
                            </TableCell>
                            <TableCell align="right" sortDirection={toolsSortBy === 'status' ? toolsSortDir : false as any}>
                              <TableSortLabel active={toolsSortBy === 'status'} direction={toolsSortDir} onClick={() => {
                                setToolsSortBy('status');
                                setToolsSortDir(toolsSortBy === 'status' && toolsSortDir === 'asc' ? 'desc' : 'asc');
                              }}>Status</TableSortLabel>
                            </TableCell>
                            <TableCell align="right" sortDirection={toolsSortBy === 'ms' ? toolsSortDir : false as any}>
                              <TableSortLabel active={toolsSortBy === 'ms'} direction={toolsSortDir} onClick={() => {
                                setToolsSortBy('ms');
                                setToolsSortDir(toolsSortBy === 'ms' && toolsSortDir === 'asc' ? 'desc' : 'asc');
                              }}>ms</TableSortLabel>
                            </TableCell>
                          </TableRow>
                        </TableHead>
                        <TableBody>
                          {pageRows.map((row, i) => (
                            <TableRow key={i} sx={{ '&:hover': { bgcolor: 'action.hover' } }}>
                              <TableCell sx={{ fontFamily: 'monospace' }}>{row.engine}</TableCell>
                              <TableCell sx={{ fontFamily: 'monospace', maxWidth: 180, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{row.tool}</TableCell>
                              <TableCell align="right">
                                <Typography
                                  variant="caption"
                                  sx={{
                                    color: row.status < 300 ? 'success.main' : row.status < 400 ? 'warning.main' : 'error.main',
                                    fontWeight: 600
                                  }}
                                >
                                  {row.status}
                                </Typography>
                              </TableCell>
                              <TableCell align="right">
                                <Typography variant="caption" color={row.ms < 100 ? 'success.main' : row.ms < 500 ? 'warning.main' : 'error.main'}>
                                  {row.ms}
                                </Typography>
                              </TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                      <Stack direction="row" spacing={1} alignItems="center" justifyContent="flex-end" sx={{ mt: 0.5 }}>
                        <Typography variant="caption" color="text.secondary">{from}-{to} of {total}</Typography>
                        <IconButton size="small" onClick={() => setToolsPage(Math.max(0, page - 1))} disabled={page <= 0}>
                          <ChevronLeftIcon fontSize="small" />
                        </IconButton>
                        <IconButton size="small" onClick={() => setToolsPage(Math.min(totalPages - 1, page + 1))} disabled={page >= totalPages - 1}>
                          <ChevronRightIcon fontSize="small" />
                        </IconButton>
                      </Stack>
                    </>
                  );
                })()}
              </Box>
            </Paper>

            {/* Hub HTTP Requests */}
            <Paper sx={{ p: 1.5, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
              <Typography variant="subtitle2" sx={{ mb: 1, fontWeight: 600 }}>Hub HTTP Requests</Typography>
              <Box sx={{ flex: 1, overflow: 'auto' }}>
                {stats.data && (() => {
                  const rows = stats.data.recent.map((r) => ({
                    method: r.method || '',
                    path: r.path || '',
                    status: Number(r.status) || 0,
                    ms: Number(r.duration_ms) || 0,
                    _raw: r
                  }));
                  const cmp = (a: any, b: any) => {
                    const dir = httpSortDir === 'asc' ? 1 : -1;
                    const by = httpSortBy;
                    if (by === 'status' || by === 'ms') return (a[by] - b[by]) * dir;
                    const av = (a[by] || '').toString().toLowerCase();
                    const bv = (b[by] || '').toString().toLowerCase();
                    return av < bv ? -1 * dir : av > bv ? 1 * dir : 0;
                  };
                  rows.sort(cmp);
                  const total = rows.length;
                  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));
                  const page = Math.min(httpPage, totalPages - 1);
                  const start = page * PAGE_SIZE;
                  const pageRows = rows.slice(start, start + PAGE_SIZE);
                  const from = total === 0 ? 0 : start + 1;
                  const to = Math.min(start + PAGE_SIZE, total);
                  return (
                    <>
                      <Table size="small" sx={{ '& td, & th': { py: 0.25, px: 0.5, fontSize: 10 } }}>
                        <TableHead>
                          <TableRow>
                            <TableCell sortDirection={httpSortBy === 'method' ? httpSortDir : false as any}>
                              <TableSortLabel active={httpSortBy === 'method'} direction={httpSortDir} onClick={() => {
                                setHttpSortBy('method');
                                setHttpSortDir(httpSortBy === 'method' && httpSortDir === 'asc' ? 'desc' : 'asc');
                              }}>Method</TableSortLabel>
                            </TableCell>
                            <TableCell sortDirection={httpSortBy === 'path' ? httpSortDir : false as any}>
                              <TableSortLabel active={httpSortBy === 'path'} direction={httpSortDir} onClick={() => {
                                setHttpSortBy('path');
                                setHttpSortDir(httpSortBy === 'path' && httpSortDir === 'asc' ? 'desc' : 'asc');
                              }}>Path</TableSortLabel>
                            </TableCell>
                            <TableCell align="right" sortDirection={httpSortBy === 'status' ? httpSortDir : false as any}>
                              <TableSortLabel active={httpSortBy === 'status'} direction={httpSortDir} onClick={() => {
                                setHttpSortBy('status');
                                setHttpSortDir(httpSortBy === 'status' && httpSortDir === 'asc' ? 'desc' : 'asc');
                              }}>Status</TableSortLabel>
                            </TableCell>
                            <TableCell align="right" sortDirection={httpSortBy === 'ms' ? httpSortDir : false as any}>
                              <TableSortLabel active={httpSortBy === 'ms'} direction={httpSortDir} onClick={() => {
                                setHttpSortBy('ms');
                                setHttpSortDir(httpSortBy === 'ms' && httpSortDir === 'asc' ? 'desc' : 'asc');
                              }}>ms</TableSortLabel>
                            </TableCell>
                          </TableRow>
                        </TableHead>
                        <TableBody>
                          {pageRows.map((req, i) => (
                            <TableRow key={i} sx={{ '&:hover': { bgcolor: 'action.hover' } }}>
                              <TableCell>
                                <Chip
                                  label={req.method}
                                  size="small"
                                  color={req.method === 'GET' ? 'info' : 'secondary'}
                                  sx={{ height: 16, '& .MuiChip-label': { px: 0.5, fontSize: 9 } }}
                                />
                              </TableCell>
                              <TableCell sx={{ fontFamily: 'monospace', maxWidth: 150, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                                {req.path}
                              </TableCell>
                              <TableCell align="right">
                                <Typography
                                  variant="caption"
                                  sx={{
                                    color: req.status < 300 ? 'success.main' : req.status < 400 ? 'warning.main' : 'error.main',
                                    fontWeight: 600
                                  }}
                                >
                                  {req.status}
                                </Typography>
                              </TableCell>
                              <TableCell align="right">
                                <Typography variant="caption" color={req.ms < 100 ? 'success.main' : req.ms < 500 ? 'warning.main' : 'error.main'}>
                                  {req.ms}
                                </Typography>
                              </TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                      <Stack direction="row" spacing={1} alignItems="center" justifyContent="flex-end" sx={{ mt: 0.5 }}>
                        <Typography variant="caption" color="text.secondary">{from}-{to} of {total}</Typography>
                        <IconButton size="small" onClick={() => setHttpPage(Math.max(0, page - 1))} disabled={page <= 0}>
                          <ChevronLeftIcon fontSize="small" />
                        </IconButton>
                        <IconButton size="small" onClick={() => setHttpPage(Math.min(totalPages - 1, page + 1))} disabled={page >= totalPages - 1}>
                          <ChevronRightIcon fontSize="small" />
                        </IconButton>
                      </Stack>
                    </>
                  );
                })()}
              </Box>
            </Paper>
          </Stack>
        </Grid>

        {/* Middle Column - LLM + Engines (scrollable) */}
        <Grid xs={12} md={4}>
          <Stack spacing={1.5} sx={{ height: '100%', overflow: 'auto', pr: 0.5 }}>
            {/* LLM Models (moved here; expandable items like Engines) */}
            <Paper sx={{ p: 1.5 }}>
              <Typography variant="subtitle2" sx={{ mb: 1, fontWeight: 600 }}>LLM Models</Typography>
              {diag.isLoading && <LinearProgress sx={{ mb: 1 }} />}
              {llmModels ? (
                <Stack spacing={1}>
                  {llmProviders.length > 0 && llmModelList.length > 0 && (
                    <Stack direction="row" spacing={0.5} flexWrap="wrap" useFlexGap>
                      <Chip size="small" label={`Providers: ${llmProviders.filter((p) => p.status === 'valid').length}/${llmProviders.length}`} variant="outlined" />
                      <Chip size="small" label={`Models: ${llmModelList.filter((m: any) => m.enabled).length}/${llmModelList.length}`} variant="outlined" />
                    </Stack>
                  )}
                  {llmStates.length > 0 && (
                    <Stack direction="row" spacing={0.5} flexWrap="wrap" useFlexGap>
                      {llmStates.slice(0, 5).map(([state, count], idx) => (
                        <Chip key={`${state}-${idx}`} size="small" label={`${state.charAt(0).toUpperCase() + state.slice(1)}: ${count}`} variant="outlined" color={statusColor(state)} />
                      ))}
                    </Stack>
                  )}
                  {llmModelList.length > 0 ? (
                    (() => {
                      const models = llmModelList;
                      return (
                        <Stack spacing={1}>
                          {models.map((model: any, index: number) => {
                            const name = model.name || model.model || 'Unknown';
                            const key = `${model.provider_name || 'prov'}:${model.provider_model_id || name}`;
                            const stateLabel = (model.state || (model.enabled ? 'enabled' : 'disabled') || 'unknown').toString();
                            const isOpen = (modelExpanded[key] ?? false);
                            const modality = Array.isArray(model.modality) ? model.modality : [];
                            return (
                              <Box key={`${key}-${index}`} sx={{ borderRadius: 1, border: '1px solid', borderColor: 'divider' }}>
                                <Stack
                                  direction="row"
                                  spacing={1}
                                  alignItems="center"
                                  justifyContent="space-between"
                                  sx={{ p: 0.75, cursor: 'pointer', bgcolor: 'action.hover' }}
                                  onClick={() => setModelExpanded((prev) => ({ ...prev, [key]: !isOpen }))}
                                >
                                  <Stack direction="row" spacing={0.75} alignItems="center" sx={{ minWidth: 0, flex: 1 }}>
                                    <Typography variant="body2" sx={{ fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{name}</Typography>
                                    <Typography variant="caption" color="text.secondary" sx={{ fontFamily: 'monospace', whiteSpace: 'nowrap' }}>
                                      Provider: {model.provider_name || 'unknown'}
                                    </Typography>
                                  </Stack>
                                  <Chip label={stateLabel} size="small" color={statusColor(stateLabel)} variant="outlined" sx={{ height: 20, '& .MuiChip-label': { px: 0.5, fontSize: 10 } }} />
                                  <Chip size="small" label={(isOpen ? 'Hide' : 'Show') + ' details'} />
                                </Stack>
                                {isOpen && (
                                  <Box sx={{ p: 1 }}>
                                    <Stack direction="row" spacing={0.5} flexWrap="wrap" useFlexGap>
                                      {modality.length > 0 ? (
                                        modality.map((m: string) => <Chip key={m} label={m} size="small" variant="outlined" />)
                                      ) : (
                                        <Chip label="Unknown modality" size="small" variant="outlined" />
                                      )}
                                      <Chip size="small" label={`Context: ${model.context_window ? `${(model.context_window / 1000).toFixed(1)}k` : '-'}`} variant="outlined" />
                                      <Chip size="small" label={`Model ID: ${model.provider_model_id || '-'}`} variant="outlined" />
                                    </Stack>
                                  </Box>
                                )}
                              </Box>
                            );
                          })}
                          
                        </Stack>
                      );
                    })()
                  ) : (
                    <Typography variant="caption" color="text.secondary">No models available</Typography>
                  )}
                  {(llmModels as any)?.error && (
                    <Alert severity="warning" sx={{ mt: 1 }}>{(llmModels as any).error}</Alert>
                  )}
                </Stack>
              ) : !diag.isLoading ? (
                <Typography variant="caption" color="text.secondary">Model status not available</Typography>
              ) : null}
            </Paper>
            {/* Engines */}
            <Paper sx={{ p: 1.5 }}>
              <Typography variant="subtitle2" sx={{ mb: 1, fontWeight: 600 }}>Engines</Typography>
              {hub.data?.multiplexer && (
                <Box sx={{ mb: 1, p: 0.75, borderRadius: 1, bgcolor: 'action.hover' }}>
                  <Stack direction="row" spacing={1} alignItems="center" justifyContent="space-between">
                    <Stack direction="row" spacing={0.5} alignItems="center">
                      <HubIcon color="primary" sx={{ fontSize: 18 }} />
                      <Typography variant="body2" sx={{ fontWeight: 600 }}>Multiplexer</Typography>
                    </Stack>
                    <Chip
                      label={hub.data.multiplexer.status || 'unknown'}
                      size="small"
                      color={statusColor(hub.data.multiplexer.status)}
                    />
                  </Stack>
                  <Stack direction="row" spacing={0.5} flexWrap="wrap" useFlexGap sx={{ mt: 0.5 }}>
                    {[
                      hub.data.multiplexer.engines !== undefined && `Engines: ${hub.data.multiplexer.engines}`,
                      hub.data.multiplexer.online !== undefined && `Online: ${hub.data.multiplexer.online}`,
                      hub.data.multiplexer.offline !== undefined && `Offline: ${hub.data.multiplexer.offline}`,
                      hub.data.multiplexer.tools !== undefined && `Tools: ${hub.data.multiplexer.tools}`,
                      hub.data.multiplexer.routes !== undefined && `Routes: ${hub.data.multiplexer.routes}`,
                    ].filter(Boolean).map((label) => (
                      <Chip
                        key={label as string}
                        size="small"
                        label={label as string}
                        variant="outlined"
                        sx={{ height: 20, '& .MuiChip-label': { px: 0.5, fontSize: 10 } }}
                      />
                    ))}
                  </Stack>
                </Box>
              )}
              <Stack spacing={0.75}>
                {hub.data?.engines?.map((engine) => (
                  <Box key={engine.name} sx={{ borderRadius: 1, border: '1px solid', borderColor: 'divider' }}>
                    <Stack
                      direction="row"
                      spacing={1}
                      alignItems="center"
                      justifyContent="space-between"
                      sx={{ p: 0.75, cursor: 'pointer', bgcolor: 'action.hover' }}
                      onClick={() => {
                        // Toggle expand (default expanded)
                        setExpanded((prev) => {
                          const cur = prev[engine.name];
                          const isExpanded = (cur === undefined ? true : cur);
                          return { ...prev, [engine.name]: !isExpanded };
                        });
                      }}
                    >
                      <Stack direction="row" spacing={0.75} alignItems="center">
                        <CheckCircleIcon color="success" sx={{ fontSize: 16 }} />
                        <Typography variant="body2" sx={{ fontWeight: 600 }}>{formatEngineName(engine.name)}</Typography>
                        <Chip size="small" label={`${engine.tools} tools`} variant="outlined" sx={{ height: 20, '& .MuiChip-label': { px: 0.5, fontSize: 10 } }} />
                        <Chip size="small" label={`Requests: ${(stats.data?.requests?.by_engine?.[engine.name] || 0)}`} variant="outlined" sx={{ height: 20, '& .MuiChip-label': { px: 0.5, fontSize: 10 } }} />
                      </Stack>
                      <Chip size="small" label={((expanded[engine.name] ?? false) ? 'Hide' : 'Show') + ' details'} />
                    </Stack>
                    {(expanded[engine.name] ?? false) && (
                      <Box sx={{ p: 1 }}>
                        <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mb: 0.5 }}>
                          Recent tool calls
                        </Typography>
                        <Stack direction="row" spacing={0.5} flexWrap="wrap" useFlexGap>
                          {(() => {
                            try {
                              const counts: Record<string, number> = {};
                              for (const r of (stats.data?.recent || [])) {
                                const p = r.path || '';
                                if (!p.startsWith(`/${engine.name}/tools/`) || !p.endsWith('/call')) continue;
                                const middle = p.substring(p.indexOf('/tools/') + 7, p.length - '/call'.length);
                                const tool = middle; // keep full tool name (may include dots)
                                counts[tool] = (counts[tool] || 0) + 1;
                              }
                              const rows = Object.entries(counts).sort((a, b) => b[1] - a[1]).slice(0, 8);
                              return rows.length > 0
                                ? rows.map(([name, cnt]) => (
                                    <Chip key={name} size="small" label={`${name}: ${cnt}`} color="primary" variant="outlined" />
                                  ))
                                : <Typography variant="caption" color="text.secondary">No recent calls</Typography>;
                            } catch {
                              return <Typography variant="caption" color="text.secondary">No recent calls</Typography>;
                            }
                          })()}
                        </Stack>
                      </Box>
                    )}
                  </Box>
                ))}
              </Stack>
            </Paper>

            

            {/* Removed per-engine cards; details now expand inside Engines card */}
          </Stack>
        </Grid>

        {/* Right Column - Database, Mounts & Config (scrollable) */}
        <Grid xs={12} md={4}>
          <Stack spacing={1.5} sx={{ height: '100%', overflow: 'auto' }}>
            {/* LLM Models moved to middle column above */}

            {/* Database */}
            <Paper sx={{ p: 1.5 }}>
              <Typography variant="subtitle2" sx={{ mb: 1, fontWeight: 600 }}>Database</Typography>
              {diag.isLoading && <LinearProgress />}
              {diag.data && (
                <Stack spacing={1.5}>
                  <Stack direction="row" spacing={1} flexWrap="wrap" useFlexGap>
                    <Chip
                      size="small"
                      icon={diag.data.db.connected ? <CheckCircleIcon /> : <ErrorIcon />}
                      label={diag.data.db.connected ? 'Connected' : 'Disconnected'}
                      color={diag.data.db.connected ? 'success' : 'error'}
                    />
                    {diag.data.db.counts && (
                      <>
                        <Chip size="small" label={`${diag.data.db.counts.repos} repos`} variant="outlined" />
                        <Chip size="small" label={`${diag.data.db.counts.files.toLocaleString()} files`} variant="outlined" />
                        <Chip size="small" label={`${diag.data.db.counts.chunks.toLocaleString()} chunks`} variant="outlined" />
                      </>
                    )}
                  </Stack>
                  {Array.isArray((diag.data as any).db?.tables) && (diag.data as any).db.tables.length > 0 && (
                    (() => {
                      const tables = ((diag.data as any).db.tables as any[]);
                      const cmp = (a: any, b: any) => {
                        const dir = dbSortDir === 'asc' ? 1 : -1;
                        if (dbSortBy === 'rows') return ((a.rows || 0) - (b.rows || 0)) * dir;
                        if (dbSortBy === 'status') {
                          const av = a.error ? 1 : 0; const bv = b.error ? 1 : 0; return (av - bv) * dir;
                        }
                        const av = (a.name || '').toString().toLowerCase();
                        const bv = (b.name || '').toString().toLowerCase();
                        return av < bv ? -1 * dir : av > bv ? 1 * dir : 0;
                      };
                      tables.sort(cmp);
                      const total = tables.length;
                      const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));
                      const page = Math.min(dbPage, totalPages - 1);
                      const start = page * PAGE_SIZE;
                      const pageRows = tables.slice(start, start + PAGE_SIZE);
                      const from = start + 1;
                      const to = Math.min(start + PAGE_SIZE, total);
                      return (
                        <>
                          <Table size="small" sx={{ tableLayout: 'fixed' }}>
                            <TableHead>
                              <TableRow>
                                <TableCell sx={{ fontWeight: 600, width: '55%' }} sortDirection={dbSortBy==='name'?dbSortDir:false as any}>
                                  <TableSortLabel active={dbSortBy==='name'} direction={dbSortDir} onClick={() => { setDbSortBy('name'); setDbSortDir(dbSortBy==='name' && dbSortDir==='asc' ? 'desc' : 'asc'); }}>Table</TableSortLabel>
                                </TableCell>
                                <TableCell sx={{ fontWeight: 600 }} align="right" sortDirection={dbSortBy==='rows'?dbSortDir:false as any}>
                                  <TableSortLabel active={dbSortBy==='rows'} direction={dbSortDir} onClick={() => { setDbSortBy('rows'); setDbSortDir(dbSortBy==='rows' && dbSortDir==='asc' ? 'desc' : 'asc'); }}>Rows</TableSortLabel>
                                </TableCell>
                                <TableCell sx={{ fontWeight: 600 }} align="left" sortDirection={dbSortBy==='status'?dbSortDir:false as any}>
                                  <TableSortLabel active={dbSortBy==='status'} direction={dbSortDir} onClick={() => { setDbSortBy('status'); setDbSortDir(dbSortBy==='status' && dbSortDir==='asc' ? 'desc' : 'asc'); }}>Status</TableSortLabel>
                                </TableCell>
                              </TableRow>
                            </TableHead>
                            <TableBody>
                              {pageRows.map((t: any) => (
                                <TableRow key={t.name} hover>
                                  <TableCell sx={{ fontFamily: 'monospace', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{t.name}</TableCell>
                                  <TableCell align="right">{t.rows?.toLocaleString?.() || '-'}</TableCell>
                                  <TableCell align="left">{t.error ? <Chip size="small" label="error" color="warning" /> : <Chip size="small" label="ok" color="success" variant="outlined" />}</TableCell>
                                </TableRow>
                              ))}
                            </TableBody>
                          </Table>
                          <Stack direction="row" spacing={1} alignItems="center" justifyContent="flex-end" sx={{ mt: 0.5 }}>
                            <Typography variant="caption" color="text.secondary">{from}-{to} of {total}</Typography>
                            <IconButton size="small" onClick={() => setDbPage(Math.max(0, page - 1))} disabled={page <= 0}>
                              <ChevronLeftIcon fontSize="small" />
                            </IconButton>
                            <IconButton size="small" onClick={() => setDbPage(Math.min(totalPages - 1, page + 1))} disabled={page >= totalPages - 1}>
                              <ChevronRightIcon fontSize="small" />
                            </IconButton>
                          </Stack>
                        </>
                      );
                    })()
                  )}
                </Stack>
              )}
            </Paper>

            {/* MongoDB */}
            <Paper sx={{ p: 1.5 }}>
              <Typography variant="subtitle2" sx={{ mb: 1, fontWeight: 600 }}>MongoDB</Typography>
              {diag.isLoading && <LinearProgress />}
              {diag.data && (diag.data as any).mongo && (
                <Stack spacing={1.5}>
                  <Stack direction="row" spacing={1} flexWrap="wrap" useFlexGap>
                    <Chip
                      size="small"
                      icon={(diag.data as any).mongo.connected ? <CheckCircleIcon /> : <ErrorIcon />}
                      label={(diag.data as any).mongo.connected ? 'Connected' : 'Disconnected'}
                      color={(diag.data as any).mongo.connected ? 'success' : 'error'}
                    />
                    {(diag.data as any).mongo.db && (
                      <Chip size="small" label={`DB: ${(diag.data as any).mongo.db}`} variant="outlined" />
                    )}
                    {(diag.data as any).mongo.counts && (
                      <>
                        <Chip size="small" label={`${(diag.data as any).mongo.counts.collections} collections`} variant="outlined" />
                        <Chip size="small" label={`${((diag.data as any).mongo.counts.documents || 0).toLocaleString()} docs`} variant="outlined" />
                      </>
                    )}
                  </Stack>
                  {Array.isArray((diag.data as any).mongo?.collections) && (diag.data as any).mongo.collections.length > 0 && (
                    (() => {
                      const cols = (((diag.data as any).mongo.collections) as any[]);
                      const cmp = (a: any, b: any) => {
                        const dir = mongoSortDir === 'asc' ? 1 : -1;
                        if (mongoSortBy === 'rows') return ((a.rows || 0) - (b.rows || 0)) * dir;
                        if (mongoSortBy === 'status') {
                          const av = a.error ? 1 : 0; const bv = b.error ? 1 : 0; return (av - bv) * dir;
                        }
                        const av = (a.name || '').toString().toLowerCase();
                        const bv = (b.name || '').toString().toLowerCase();
                        return av < bv ? -1 * dir : av > bv ? 1 * dir : 0;
                      };
                      cols.sort(cmp);
                      const total = cols.length;
                      const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));
                      const page = Math.min(mongoPage, totalPages - 1);
                      const start = page * PAGE_SIZE;
                      const pageRows = cols.slice(start, start + PAGE_SIZE);
                      const from = start + 1;
                      const to = Math.min(start + PAGE_SIZE, total);
                      return (
                        <>
                          <Table size="small" sx={{ tableLayout: 'fixed' }}>
                            <TableHead>
                              <TableRow>
                                <TableCell sx={{ fontWeight: 600, width: '55%' }} sortDirection={mongoSortBy==='name'?mongoSortDir:false as any}>
                                  <TableSortLabel active={mongoSortBy==='name'} direction={mongoSortDir} onClick={() => { setMongoSortBy('name'); setMongoSortDir(mongoSortBy==='name' && mongoSortDir==='asc' ? 'desc' : 'asc'); }}>Collection</TableSortLabel>
                                </TableCell>
                                <TableCell sx={{ fontWeight: 600 }} align="right" sortDirection={mongoSortBy==='rows'?mongoSortDir:false as any}>
                                  <TableSortLabel active={mongoSortBy==='rows'} direction={mongoSortDir} onClick={() => { setMongoSortBy('rows'); setMongoSortDir(mongoSortBy==='rows' && mongoSortDir==='asc' ? 'desc' : 'asc'); }}>Docs</TableSortLabel>
                                </TableCell>
                                <TableCell sx={{ fontWeight: 600 }} align="left" sortDirection={mongoSortBy==='status'?mongoSortDir:false as any}>
                                  <TableSortLabel active={mongoSortBy==='status'} direction={mongoSortDir} onClick={() => { setMongoSortBy('status'); setMongoSortDir(mongoSortBy==='status' && mongoSortDir==='asc' ? 'desc' : 'asc'); }}>Status</TableSortLabel>
                                </TableCell>
                              </TableRow>
                            </TableHead>
                            <TableBody>
                              {pageRows.map((t: any) => (
                                <TableRow key={t.name} hover>
                                  <TableCell sx={{ fontFamily: 'monospace', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{t.name}</TableCell>
                                  <TableCell align="right">{t.rows?.toLocaleString?.() || '-'}</TableCell>
                                  <TableCell align="left">{t.error ? <Chip size="small" label="error" color="warning" /> : <Chip size="small" label="ok" color="success" variant="outlined" />}</TableCell>
                                </TableRow>
                              ))}
                            </TableBody>
                          </Table>
                          <Stack direction="row" spacing={1} alignItems="center" justifyContent="flex-end" sx={{ mt: 0.5 }}>
                            <Typography variant="caption" color="text.secondary">{from}-{to} of {total}</Typography>
                            <IconButton size="small" onClick={() => setMongoPage(Math.max(0, page - 1))} disabled={page <= 0}>
                              <ChevronLeftIcon fontSize="small" />
                            </IconButton>
                            <IconButton size="small" onClick={() => setMongoPage(Math.min(totalPages - 1, page + 1))} disabled={page >= totalPages - 1}>
                              <ChevronRightIcon fontSize="small" />
                            </IconButton>
                          </Stack>
                        </>
                      );
                    })()
                  )}
                  {(diag.data as any).mongo?.error && (
                    <Alert severity="warning">{(diag.data as any).mongo.error}</Alert>
                  )}
                </Stack>
              )}
            </Paper>

          </Stack>
        </Grid>
      </Grid>

      {diag.isError && <Alert severity="error" sx={{ mt: 1 }}>Failed to load diagnostics</Alert>}
    </Box>
  );
}
