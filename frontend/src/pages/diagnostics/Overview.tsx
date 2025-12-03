import React, { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import Box from '@mui/material/Box';
import Grid from '@mui/material/Grid2';
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
import CheckCircleIcon from '@mui/icons-material/CheckCircle';
import ErrorIcon from '@mui/icons-material/Error';
import StorageIcon from '@mui/icons-material/Storage';
import HubIcon from '@mui/icons-material/Hub';
// import PlayArrowIcon from '@mui/icons-material/PlayArrow';
// import TimerIcon from '@mui/icons-material/Timer';
import HttpIcon from '@mui/icons-material/Http';
import { useHubInfo, useDiagnostics, useHubStats, testDbQuery, DbQueryTest, usePersonas, useRules } from '../../api';
import SmallMultiples, { SmallSeries } from '../../components/SmallMultiples';

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
  if (val.includes('ok') || val.includes('online') || val.includes('running')) return 'success';
  if (val.includes('warn') || val.includes('partial') || val.includes('degraded')) return 'warning';
  if (val.includes('error') || val.includes('offline') || val.includes('fail')) return 'error';
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
  const personasList = usePersonas('');
  const rulesList = useRules('');
  const llmModels = diag.data?.llm_models;
  const runningModels = llmModels?.running ?? 0;
  const totalModels = llmModels?.total ?? (llmModels?.models?.length ?? 0);
  const llmStates = Object.entries(llmModels?.states || {}).filter(([state]) => state && state.toLowerCase() !== 'unknown');
  const llmModelList = llmModels?.models || [];
  const llmRuntime = diag.data?.llm_runtime;
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

      {/* Main Grid */}
      <Grid container spacing={1.5} sx={{ flex: 1, minHeight: 0 }}>
        {/* Left Column - Quick Cards + Requests (scrollable) */}
        <Grid size={{ xs: 12, md: 4 }}>
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
                {stats.data && (
                  <Table size="small" sx={{ '& td, & th': { py: 0.25, px: 0.5, fontSize: 10 } }}>
                    <TableHead>
                      <TableRow>
                        <TableCell>Engine</TableCell>
                        <TableCell>Tool</TableCell>
                        <TableCell align="right">Status</TableCell>
                        <TableCell align="right">ms</TableCell>
                      </TableRow>
                    </TableHead>
                    <TableBody>
                      {stats.data.recent
                        .filter((req) => (req.path || '').includes('/tools/') && (req.path || '').endsWith('/call'))
                        .slice(0, 10)
                        .map((req, i) => (
                          <TableRow key={i} sx={{ '&:hover': { bgcolor: 'action.hover' } }}>
                            <TableCell sx={{ fontFamily: 'monospace' }}>
                              {(() => {
                                const p = (req.path || '').split('/').filter(Boolean);
                                return p[0] || '';
                              })()}
                            </TableCell>
                            <TableCell sx={{ fontFamily: 'monospace', maxWidth: 180, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                              {(() => {
                                const p = req.path || '';
                                const i1 = p.indexOf('/tools/');
                                const i2 = p.lastIndexOf('/call');
                                if (i1 >= 0 && i2 > i1) return p.substring(i1 + 7, i2);
                                return '';
                              })()}
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
                              <Typography variant="caption" color={req.duration_ms < 100 ? 'success.main' : req.duration_ms < 500 ? 'warning.main' : 'error.main'}>
                                {req.duration_ms}
                              </Typography>
                            </TableCell>
                          </TableRow>
                        ))}
                    </TableBody>
                  </Table>
                )}
              </Box>
            </Paper>

            {/* Hub HTTP Requests */}
            <Paper sx={{ p: 1.5, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
              <Typography variant="subtitle2" sx={{ mb: 1, fontWeight: 600 }}>Hub HTTP Requests</Typography>
              <Box sx={{ flex: 1, overflow: 'auto' }}>
                {stats.data && (
                  <Table size="small" sx={{ '& td, & th': { py: 0.25, px: 0.5, fontSize: 10 } }}>
                    <TableHead>
                      <TableRow>
                        <TableCell>Method</TableCell>
                        <TableCell>Path</TableCell>
                        <TableCell align="right">Status</TableCell>
                        <TableCell align="right">ms</TableCell>
                      </TableRow>
                    </TableHead>
                    <TableBody>
                      {stats.data.recent.slice(0, 10).map((req, i) => (
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
                            <Typography variant="caption" color={req.duration_ms < 100 ? 'success.main' : req.duration_ms < 500 ? 'warning.main' : 'error.main'}>
                              {req.duration_ms}
                            </Typography>
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                )}
              </Box>
            </Paper>
          </Stack>
        </Grid>

        {/* Middle Column - Database & Config (scrollable) */}
        <Grid size={{ xs: 12, md: 4 }}>
          <Stack spacing={1.5} sx={{ height: '100%', overflow: 'auto', pr: 0.5 }}>
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
              <Stack spacing={0.5}>
                {hub.data?.engines?.map((engine) => (
                  <Stack
                    key={engine.name}
                    direction="row"
                    spacing={1}
                    alignItems="center"
                    justifyContent="space-between"
                    sx={{ p: 0.5, bgcolor: 'action.hover', borderRadius: 0.5 }}
                  >
                    <Stack direction="row" spacing={0.5} alignItems="center">
                      <CheckCircleIcon color="success" sx={{ fontSize: 16 }} />
                      <Typography variant="body2" sx={{ fontWeight: 500 }}>{formatEngineName(engine.name)}</Typography>
                    </Stack>
                    <Chip
                      label={`${engine.tools} tools`}
                      size="small"
                      variant="outlined"
                      sx={{ height: 20, '& .MuiChip-label': { px: 0.5, fontSize: 10 } }}
                    />
                  </Stack>
                ))}
              </Stack>
            </Paper>

            
            {/* Personas */}
            <Paper sx={{ p: 1.5 }}>
              <Typography variant="subtitle2" sx={{ mb: 1, fontWeight: 600 }}>Personas</Typography>
              <Stack direction="row" spacing={1} flexWrap="wrap" useFlexGap>
                <Chip size="small" label={`Catalog: ${(personasList.data?.personas?.length || 0)} entries`} variant="outlined" />
                <Chip size="small" label={`Requests: ${(stats.data?.requests?.by_engine?.['personas'] || 0)}`} variant="outlined" />
              </Stack>
              {stats.data && (
                <Box sx={{ mt: 1 }}>
                  <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mb: 0.5 }}>
                    Recent persona loads (last {stats.data.recent.length} reqs)
                  </Typography>
                  <Stack direction="row" spacing={0.5} flexWrap="wrap" useFlexGap>
                    {(() => {
                      try {
                        const counts: Record<string, number> = {};
                        for (const r of stats.data.recent) {
                          if (!r.path?.includes('/personas/tools/personas_get/call')) continue;
                          const body = r.request_body || '';
                          try {
                            const json = JSON.parse(body);
                            const nm = json?.params?.name || null;
                            if (nm) counts[nm] = (counts[nm] || 0) + 1;
                          } catch { /* ignore parse errors */ }
                        }
                        const rows = Object.entries(counts).sort((a, b) => b[1] - a[1]).slice(0, 6);
                        return rows.length > 0
                          ? rows.map(([name, cnt]) => (
                              <Chip key={name} size="small" label={`${name}: ${cnt}`} color="primary" variant="outlined" />
                            ))
                          : <Typography variant="caption" color="text.secondary">No recent persona loads</Typography>;
                      } catch {
                        return <Typography variant="caption" color="text.secondary">No recent persona loads</Typography>;
                      }
                    })()}
                  </Stack>
                </Box>
              )}
            </Paper>
            {/* Rules */}
            <Paper sx={{ p: 1.5 }}>
              <Typography variant="subtitle2" sx={{ mb: 1, fontWeight: 600 }}>Rules</Typography>
              <Stack direction="row" spacing={1} flexWrap="wrap" useFlexGap>
                <Chip size="small" label={`Catalog: ${(rulesList.data?.rules?.length || 0)} entries`} variant="outlined" />
                <Chip size="small" label={`Requests: ${(stats.data?.requests?.by_engine?.['rules'] || 0)}`} variant="outlined" />
              </Stack>
              {stats.data && (
                <Box sx={{ mt: 1 }}>
                  <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mb: 0.5 }}>
                    Recent rules loads (last {stats.data.recent.length} reqs)
                  </Typography>
                  <Stack direction="row" spacing={0.5} flexWrap="wrap" useFlexGap>
                    {(() => {
                      try {
                        const counts: Record<string, number> = {};
                        for (const r of stats.data.recent) {
                          if (!r.path?.includes('/rules/tools/rules_get/call')) continue;
                          const body = r.request_body || '';
                          try {
                            const json = JSON.parse(body);
                            const nm = json?.params?.name || null;
                            if (nm) counts[nm] = (counts[nm] || 0) + 1;
                          } catch { /* ignore parse errors */ }
                        }
                        const rows = Object.entries(counts).sort((a, b) => b[1] - a[1]).slice(0, 6);
                        return rows.length > 0
                          ? rows.map(([name, cnt]) => (
                              <Chip key={name} size="small" label={`${name}: ${cnt}`} color="primary" variant="outlined" />
                            ))
                          : <Typography variant="caption" color="text.secondary">No recent rules loads</Typography>;
                      } catch {
                        return <Typography variant="caption" color="text.secondary">No recent rules loads</Typography>;
                      }
                    })()}
                  </Stack>
                </Box>
              )}
            </Paper>

            {/* Per-Engine Stats (generic for all except Personas/Rules) */}
            {(hub.data?.engines || [])
              .filter((e) => e.name !== 'personas' && e.name !== 'rules')
              .map((e) => (
                <Paper key={e.name} sx={{ p: 1.5 }}>
                  <Typography variant="subtitle2" sx={{ mb: 1, fontWeight: 600 }}>{formatEngineName(e.name)}</Typography>
                  <Stack direction="row" spacing={1} flexWrap="wrap" useFlexGap>
                    <Chip size="small" label={`${e.tools} tools`} variant="outlined" />
                    <Chip size="small" label={`Requests: ${(stats.data?.requests?.by_engine?.[e.name] || 0)}`} variant="outlined" />
                  </Stack>
                  {stats.data && (
                    <Box sx={{ mt: 1 }}>
                      <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mb: 0.5 }}>
                        Recent tool calls
                      </Typography>
                      <Stack direction="row" spacing={0.5} flexWrap="wrap" useFlexGap>
                        {(() => {
                          try {
                            const counts: Record<string, number> = {};
                            for (const r of stats.data.recent) {
                              const p = r.path || '';
                              if (!p.startsWith(`/${e.name}/tools/`) || !p.endsWith('/call')) continue;
                              const middle = p.substring(p.indexOf('/tools/') + 7, p.length - '/call'.length);
                              const tool = middle; // keep full tool name (may include dots)
                              counts[tool] = (counts[tool] || 0) + 1;
                            }
                            const rows = Object.entries(counts).sort((a, b) => b[1] - a[1]).slice(0, 6);
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
                </Paper>
              ))}
            
          </Stack>
        </Grid>

        {/* Right Column - Database, Mounts & Config (scrollable) */}
        <Grid size={{ xs: 12, md: 4 }}>
          <Stack spacing={1.5} sx={{ height: '100%', overflow: 'auto' }}>
            {/* LLM Models */}
            <Paper sx={{ p: 1.5 }}>
              <Typography variant="subtitle2" sx={{ mb: 1, fontWeight: 600 }}>LLM Models</Typography>
              {diag.isLoading && <LinearProgress sx={{ mb: 1 }} />}
              {llmModels ? (
                <Stack spacing={1}>
                  <Stack direction="row" spacing={0.5} flexWrap="wrap" useFlexGap>
                    <Chip
                      size="small"
                      label={`Running: ${runningModels}`}
                      color={runningModels > 0 ? 'success' : 'default'}
                      variant="outlined"
                    />
                    <Chip
                      size="small"
                      label={`Total: ${totalModels}`}
                      variant="outlined"
                    />
                  </Stack>
                  {llmStates.length > 0 && (
                    <Stack direction="row" spacing={0.5} flexWrap="wrap" useFlexGap>
                      {llmStates.slice(0, 5).map(([state, count], idx) => (
                        <Chip
                          key={`${state}-${idx}`}
                          size="small"
                          label={`${state.charAt(0).toUpperCase() + state.slice(1)}: ${count}`}
                          variant="outlined"
                          color={statusColor(state)}
                        />
                      ))}
                    </Stack>
                  )}
                  {llmModelList.length > 0 ? (
                    <Stack spacing={1}>
                      {llmModelList.slice(0, 4).map((model, index) => {
                        const name = model.name || model.model || 'Unknown';
                        const stateLabel = (model.state || model.status || 'unknown').toString();
                        const progress = normalizeModelProgress(model);
                        return (
                          <Box key={`${name}-${index}`} sx={{ p: 1, borderRadius: 1, bgcolor: 'action.hover' }}>
                            <Stack direction="row" alignItems="center" justifyContent="space-between" spacing={1}>
                              <Typography variant="body2" sx={{ fontWeight: 600 }}>{name}</Typography>
                              <Chip
                                label={stateLabel}
                                size="small"
                                color={statusColor(stateLabel)}
                                variant="outlined"
                                sx={{ height: 20, '& .MuiChip-label': { px: 0.5, fontSize: 10 } }}
                              />
                            </Stack>
                            {progress !== null && (
                              <Stack direction="row" spacing={1} alignItems="center" sx={{ mt: 0.5 }}>
                                <Typography variant="caption" color="text.secondary">{`${Math.round(progress)}%`}</Typography>
                                <LinearProgress variant="determinate" value={progress} sx={{ flex: 1, height: 6, borderRadius: 1 }} />
                              </Stack>
                            )}
                          </Box>
                        );
                      })}
                      {llmModelList.length > 4 && (
                        <Typography variant="caption" color="text.secondary">
                          +{llmModelList.length - 4} more models
                        </Typography>
                      )}
                    </Stack>
                  ) : (
                    <Typography variant="caption" color="text.secondary">No models available</Typography>
                  )}
                  {llmRuntime && (
                    <Stack direction="row" spacing={1} flexWrap="wrap" useFlexGap sx={{ mt: 0.5 }}>
                      <Typography variant="caption" sx={{ fontFamily: 'monospace' }}>
                        SLM: {llmRuntime.slm_model || 'n/a'}
                      </Typography>
                      <Typography variant="caption" sx={{ fontFamily: 'monospace' }}>
                        LLM: {llmRuntime.llm_model || 'n/a'}
                      </Typography>
                      <Typography variant="caption" sx={{ fontFamily: 'monospace' }}>
                        Provider: {llmRuntime.provider || 'ollama'}
                      </Typography>
                    </Stack>
                  )}
                  {llmModels.error && (
                    <Alert severity="warning" sx={{ mt: 1 }}>{llmModels.error}</Alert>
                  )}
                </Stack>
              ) : !diag.isLoading ? (
                <Typography variant="caption" color="text.secondary">Model status not available</Typography>
              ) : null}
            </Paper>

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
                </Stack>
              )}
            </Paper>

            {/* Secrets */}
            <Paper sx={{ p: 1.5 }}>
              <Typography variant="subtitle2" sx={{ mb: 1, fontWeight: 600 }}>Secrets</Typography>
              {diag.data && (diag.data as any).secrets ? (
                <Stack spacing={1}>
                  <Stack direction="row" spacing={1} flexWrap="wrap" useFlexGap>
                    <Chip
                      size="small"
                      icon={(diag.data as any).secrets.exists ? <CheckCircleIcon /> : <ErrorIcon />}
                      label={`Path: ${(diag.data as any).secrets.path || 'unknown'}`}
                      variant="outlined"
                      color={(diag.data as any).secrets.exists ? 'success' : 'warning'}
                    />
                    {(diag.data as any).secrets.users && (
                      <Chip size="small" label={`Users: ${(diag.data as any).secrets.users}`} variant="outlined" />
                    )}
                    {(diag.data as any).secrets.services && (
                      <Chip size="small" label={`Services: ${((diag.data as any).secrets.services || []).join(', ') || 'n/a'}`} variant="outlined" />
                    )}
                  </Stack>
                  <Typography variant="caption" color="text.secondary">
                    {(diag.data as any).secrets.exists
                      ? 'Values are redacted server-side.'
                      : 'File not found. Create it at the path shown above.'}
                  </Typography>
                </Stack>
              ) : (
                <Typography variant="caption" color="text.secondary">Not available</Typography>
              )}
            </Paper>
            {/* Mounts */}
            <Paper sx={{ p: 1.5 }}>
              <Typography variant="subtitle2" sx={{ mb: 1, fontWeight: 600 }}>Mounts</Typography>
              {diag.data && (
                <Stack direction="row" spacing={0.5} flexWrap="wrap" useFlexGap>
                  {Object.entries(diag.data.mounts || {}).map(([k, v]) => (
                    <Chip
                      key={k}
                      size="small"
                      icon={v ? <CheckCircleIcon /> : <ErrorIcon />}
                      label={k}
                      color={v ? 'success' : 'warning'}
                      variant={v ? 'filled' : 'outlined'}
                    />
                  ))}
                </Stack>
              )}
            </Paper>

            {/* Config */}
            <Paper sx={{ p: 1.5 }}>
              <Typography variant="subtitle2" sx={{ mb: 1, fontWeight: 600 }}>Configuration</Typography>
              {diag.data && (
                <Stack spacing={0.5}>
                  <Typography variant="caption" sx={{ fontFamily: 'monospace' }}>
                    <strong>Base:</strong> {diag.data.base_path}
                  </Typography>
                  <Typography variant="caption" sx={{ fontFamily: 'monospace' }}>
                    <strong>Settings:</strong> {diag.data.settings_path}
                  </Typography>
                  {diag.data.config_error && (
                    <Alert severity="error" sx={{ py: 0, mt: 0.5 }}>{diag.data.config_error}</Alert>
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
