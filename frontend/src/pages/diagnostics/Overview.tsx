import React, { useState } from 'react';
import Box from '@mui/material/Box';
import Grid from '@mui/material/Grid2';
import Paper from '@mui/material/Paper';
import Typography from '@mui/material/Typography';
import Stack from '@mui/material/Stack';
import Chip from '@mui/material/Chip';
import LinearProgress from '@mui/material/LinearProgress';
import Alert from '@mui/material/Alert';
import Button from '@mui/material/Button';
import TextField from '@mui/material/TextField';
import Table from '@mui/material/Table';
import TableBody from '@mui/material/TableBody';
import TableCell from '@mui/material/TableCell';
import TableHead from '@mui/material/TableHead';
import TableRow from '@mui/material/TableRow';
import CheckCircleIcon from '@mui/icons-material/CheckCircle';
import ErrorIcon from '@mui/icons-material/Error';
import StorageIcon from '@mui/icons-material/Storage';
import PlayArrowIcon from '@mui/icons-material/PlayArrow';
import TimerIcon from '@mui/icons-material/Timer';
import HttpIcon from '@mui/icons-material/Http';
import { useHubInfo, useDiagnostics, useHubStats, testDbQuery, DbQueryTest, usePersonas, useRules } from '../../api';

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

export default function DiagnosticsOverview() {
  const hub = useHubInfo();
  const diag = useDiagnostics();
  const stats = useHubStats();
  const personasList = usePersonas('');
  const rulesList = useRules('');
  const [queryText, setQueryText] = useState('function');
  const [queryResult, setQueryResult] = useState<DbQueryTest | null>(null);
  const [queryLoading, setQueryLoading] = useState(false);

  async function runQuery() {
    setQueryLoading(true);
    const result = await testDbQuery(queryText);
    setQueryResult(result);
    setQueryLoading(false);
  }

  return (
    <Box sx={{ height: 'calc(100vh - 200px)', overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
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

      {/* Main Grid */}
      <Grid container spacing={1.5} sx={{ flex: 1, minHeight: 0 }}>
        {/* Left Column - Engines & Recent Requests */}
        <Grid size={{ xs: 12, md: 4 }}>
          <Stack spacing={1.5} sx={{ height: '100%' }}>
            <Paper sx={{ p: 1.5 }}>
              <Typography variant="subtitle2" sx={{ mb: 1, fontWeight: 600 }}>Engines</Typography>
              <Stack spacing={0.5}>
                {hub.data?.engines?.map((engine) => (
                  <Stack key={engine.name} direction="row" spacing={1} alignItems="center" justifyContent="space-between" sx={{ p: 0.5, bgcolor: 'grey.50', borderRadius: 0.5 }}>
                    <Stack direction="row" spacing={0.5} alignItems="center">
                      <CheckCircleIcon color="success" sx={{ fontSize: 16 }} />
                      <Typography variant="body2" sx={{ fontWeight: 500 }}>{formatEngineName(engine.name)}</Typography>
                    </Stack>
                    <Chip label={`${engine.tools} tools`} size="small" variant="outlined" sx={{ height: 20, '& .MuiChip-label': { px: 0.5, fontSize: 10 } }} />
                  </Stack>
                ))}
              </Stack>
            </Paper>

            {/* Recent Requests */}
            <Paper sx={{ p: 1.5, flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
              <Typography variant="subtitle2" sx={{ mb: 1, fontWeight: 600 }}>Recent Requests</Typography>
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
                      {stats.data.recent.slice(0, 15).map((req, i) => (
                        <TableRow key={i} sx={{ '&:hover': { bgcolor: 'grey.50' } }}>
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
                          if (!r.path?.includes('/personas/tools/personas.get/call')) continue;
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
                          if (!r.path?.includes('/rules/tools/rules.get/call')) continue;
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

                  {/* Query Test */}
                  <Box sx={{ pt: 1, borderTop: '1px solid', borderColor: 'divider' }}>
                    <Typography variant="caption" color="text.secondary" sx={{ mb: 0.5, display: 'block' }}>
                      FTS Query Test
                    </Typography>
                    <Stack direction="row" spacing={1} alignItems="center">
                      <TextField
                        size="small"
                        value={queryText}
                        onChange={(e) => setQueryText(e.target.value)}
                        placeholder="search term"
                        sx={{ flex: 1, '& input': { py: 0.5, fontSize: 12 } }}
                      />
                      <Button
                        size="small"
                        variant="contained"
                        onClick={runQuery}
                        disabled={queryLoading}
                        startIcon={<PlayArrowIcon />}
                        sx={{ minWidth: 70 }}
                      >
                        Run
                      </Button>
                    </Stack>
                    {queryResult && (
                      <Stack direction="row" spacing={1} sx={{ mt: 1 }} flexWrap="wrap" useFlexGap>
                        <Chip
                          size="small"
                          icon={queryResult.success ? <CheckCircleIcon /> : <ErrorIcon />}
                          label={queryResult.success ? 'OK' : 'Failed'}
                          color={queryResult.success ? 'success' : 'error'}
                        />
                        <Chip
                          size="small"
                          icon={<TimerIcon />}
                          label={`${queryResult.duration_ms}ms`}
                          variant="outlined"
                          color={queryResult.duration_ms < 100 ? 'success' : queryResult.duration_ms < 500 ? 'warning' : 'error'}
                        />
                        <Chip size="small" label={`${queryResult.results} results`} variant="outlined" />
                      </Stack>
                    )}
                  </Box>
                </Stack>
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
            <Paper sx={{ p: 1.5, flex: 1 }}>
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

        {/* Right Column - Repos */}
        <Grid size={{ xs: 12, md: 4 }}>
          <Paper sx={{ p: 1.5, height: '100%', display: 'flex', flexDirection: 'column' }}>
            <Typography variant="subtitle2" sx={{ mb: 1, fontWeight: 600 }}>Repository Visibility</Typography>
            <Box sx={{ flex: 1, overflow: 'auto' }}>
              <Stack spacing={1}>
                {(diag.data?.repos || []).map((r) => (
                  <Box key={r.name} sx={{ p: 1, bgcolor: 'grey.50', borderRadius: 1 }}>
                    <Stack direction="row" spacing={0.5} alignItems="center" mb={0.5}>
                      <StorageIcon color="action" sx={{ fontSize: 16 }} />
                      <Typography variant="body2" sx={{ fontFamily: 'monospace', fontWeight: 500 }}>{r.name}</Typography>
                    </Stack>
                    <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mb: 0.5, fontFamily: 'monospace' }}>
                      {r.path}
                    </Typography>
                    <Stack direction="row" spacing={0.5} flexWrap="wrap" useFlexGap>
                      <Chip size="small" label={r.exists ? 'exists' : 'missing'} color={r.exists ? 'success' : 'error'} sx={{ height: 20, '& .MuiChip-label': { px: 1, fontSize: 10 } }} />
                      <Chip size="small" label={r.readable ? 'readable' : 'no read'} color={r.readable ? 'success' : 'warning'} sx={{ height: 20, '& .MuiChip-label': { px: 1, fontSize: 10 } }} />
                      {typeof r.sampled_count === 'number' && (
                        <Chip size="small" label={`~${r.sampled_count} files`} variant="outlined" sx={{ height: 20, '& .MuiChip-label': { px: 1, fontSize: 10 } }} />
                      )}
                    </Stack>
                  </Box>
                ))}
              </Stack>
            </Box>
          </Paper>
        </Grid>
      </Grid>

      {diag.isError && <Alert severity="error" sx={{ mt: 1 }}>Failed to load diagnostics</Alert>}
    </Box>
  );
}
