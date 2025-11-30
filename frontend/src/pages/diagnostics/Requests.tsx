import React, { useState, useMemo } from 'react';
import Box from '@mui/material/Box';
import Paper from '@mui/material/Paper';
import Table from '@mui/material/Table';
import TableBody from '@mui/material/TableBody';
import TableCell from '@mui/material/TableCell';
import TableContainer from '@mui/material/TableContainer';
import TableHead from '@mui/material/TableHead';
import TableRow from '@mui/material/TableRow';
import Chip from '@mui/material/Chip';
import Typography from '@mui/material/Typography';
import IconButton from '@mui/material/IconButton';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import Stack from '@mui/material/Stack';
import Divider from '@mui/material/Divider';
import Select from '@mui/material/Select';
import MenuItem from '@mui/material/MenuItem';
import FormControl from '@mui/material/FormControl';
import InputLabel from '@mui/material/InputLabel';
import CloseIcon from '@mui/icons-material/Close';
import RefreshIcon from '@mui/icons-material/Refresh';
import LinearProgress from '@mui/material/LinearProgress';
import { useHubStats, RequestRecord } from '../../api';

function formatTime(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleTimeString();
}

function getStatusColor(status: number): 'success' | 'warning' | 'error' | 'default' {
  if (status < 300) return 'success';
  if (status < 400) return 'warning';
  if (status < 500) return 'warning';
  return 'error';
}

function getMethodColor(method: string): 'info' | 'secondary' | 'success' | 'warning' | 'error' {
  switch (method) {
    case 'GET': return 'info';
    case 'POST': return 'secondary';
    case 'PUT': return 'warning';
    case 'DELETE': return 'error';
    default: return 'info';
  }
}

function formatJson(str: string | null): string {
  if (!str) return '';
  try {
    return JSON.stringify(JSON.parse(str), null, 2);
  } catch {
    return str;
  }
}

export default function DiagnosticsRequests() {
  const { data, isLoading, refetch } = useHubStats();
  const [selected, setSelected] = useState<RequestRecord | null>(null);
  const [methodFilter, setMethodFilter] = useState<string>('');
  const [engineFilter, setEngineFilter] = useState<string>('');
  const [statusFilter, setStatusFilter] = useState<string>('');

  // Get unique values for filters
  const methods = useMemo(() => {
    if (!data?.recent) return [];
    return [...new Set(data.recent.map(r => r.method))].sort();
  }, [data?.recent]);

  const engines = useMemo(() => {
    if (!data?.recent) return [];
    return [...new Set(data.recent.map(r => r.engine))].sort();
  }, [data?.recent]);

  const statuses = useMemo(() => {
    if (!data?.recent) return [];
    return [...new Set(data.recent.map(r => String(r.status)))].sort();
  }, [data?.recent]);

  // Filter requests
  const filteredRequests = useMemo(() => {
    if (!data?.recent) return [];
    return data.recent.filter(r => {
      if (methodFilter && r.method !== methodFilter) return false;
      if (engineFilter && r.engine !== engineFilter) return false;
      if (statusFilter && String(r.status) !== statusFilter) return false;
      return true;
    });
  }, [data?.recent, methodFilter, engineFilter, statusFilter]);

  return (
    <Box sx={{ height: 'calc(100vh - 220px)', display: 'flex', flexDirection: 'column' }}>
      <Paper sx={{ p: 1.5, mb: 1, display: 'flex', alignItems: 'center', gap: 2, flexWrap: 'wrap' }}>
        <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>
          Requests ({filteredRequests.length}{filteredRequests.length !== data?.recent.length ? ` / ${data?.recent.length}` : ''})
        </Typography>

        <FormControl size="small" sx={{ minWidth: 100 }}>
          <InputLabel>Method</InputLabel>
          <Select
            value={methodFilter}
            label="Method"
            onChange={(e) => setMethodFilter(e.target.value)}
          >
            <MenuItem value="">All</MenuItem>
            {methods.map(m => <MenuItem key={m} value={m}>{m}</MenuItem>)}
          </Select>
        </FormControl>

        <FormControl size="small" sx={{ minWidth: 120 }}>
          <InputLabel>Engine</InputLabel>
          <Select
            value={engineFilter}
            label="Engine"
            onChange={(e) => setEngineFilter(e.target.value)}
          >
            <MenuItem value="">All</MenuItem>
            {engines.map(e => <MenuItem key={e} value={e}>{e}</MenuItem>)}
          </Select>
        </FormControl>

        <FormControl size="small" sx={{ minWidth: 100 }}>
          <InputLabel>Status</InputLabel>
          <Select
            value={statusFilter}
            label="Status"
            onChange={(e) => setStatusFilter(e.target.value)}
          >
            <MenuItem value="">All</MenuItem>
            {statuses.map(s => <MenuItem key={s} value={s}>{s}</MenuItem>)}
          </Select>
        </FormControl>

        <Box sx={{ flex: 1 }} />

        <IconButton size="small" onClick={() => refetch()} title="Refresh">
          <RefreshIcon fontSize="small" />
        </IconButton>
      </Paper>

      {isLoading && <LinearProgress />}

      <TableContainer component={Paper} sx={{ flex: 1, overflow: 'auto' }}>
        <Table size="small" stickyHeader>
          <TableHead>
            <TableRow>
              <TableCell sx={{ fontWeight: 600, width: 80 }}>Time</TableCell>
              <TableCell sx={{ fontWeight: 600, width: 70 }}>Method</TableCell>
              <TableCell sx={{ fontWeight: 600 }}>Path</TableCell>
              <TableCell sx={{ fontWeight: 600, width: 80 }}>Engine</TableCell>
              <TableCell sx={{ fontWeight: 600, width: 70 }} align="center">Status</TableCell>
              <TableCell sx={{ fontWeight: 600, width: 60 }} align="right">ms</TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {filteredRequests.map((req) => (
              <TableRow
                key={req.id}
                hover
                onClick={() => setSelected(req)}
                sx={{ cursor: 'pointer', '&:hover': { bgcolor: 'action.hover' } }}
              >
                <TableCell sx={{ fontFamily: 'monospace', fontSize: 12 }}>
                  {formatTime(req.time)}
                </TableCell>
                <TableCell>
                  <Chip
                    label={req.method}
                    size="small"
                    color={getMethodColor(req.method)}
                    sx={{ height: 20, '& .MuiChip-label': { px: 1, fontSize: 11 } }}
                  />
                </TableCell>
                <TableCell sx={{ fontFamily: 'monospace', fontSize: 12, maxWidth: 300, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                  {req.path}{req.query ? `?${req.query}` : ''}
                </TableCell>
                <TableCell>
                  <Chip
                    label={req.engine}
                    size="small"
                    variant="outlined"
                    sx={{ height: 20, '& .MuiChip-label': { px: 1, fontSize: 11 } }}
                  />
                </TableCell>
                <TableCell align="center">
                  <Chip
                    label={req.status}
                    size="small"
                    color={getStatusColor(req.status)}
                    sx={{ height: 20, minWidth: 40, '& .MuiChip-label': { px: 0.5, fontSize: 11, fontWeight: 600 } }}
                  />
                </TableCell>
                <TableCell align="right" sx={{ fontFamily: 'monospace', fontSize: 12, color: req.duration_ms > 500 ? 'error.main' : req.duration_ms > 100 ? 'warning.main' : 'success.main' }}>
                  {req.duration_ms}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </TableContainer>

      {/* Request Detail Dialog */}
      <Dialog open={!!selected} onClose={() => setSelected(null)} maxWidth="md" fullWidth>
        <DialogTitle sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', pb: 1 }}>
          <Stack direction="row" spacing={1} alignItems="center">
            <Chip label={selected?.method} size="small" color={getMethodColor(selected?.method || 'GET')} />
            <Typography variant="subtitle1" sx={{ fontFamily: 'monospace' }}>
              {selected?.path}
            </Typography>
            <Chip label={selected?.status} size="small" color={getStatusColor(selected?.status || 200)} />
          </Stack>
          <IconButton size="small" onClick={() => setSelected(null)}>
            <CloseIcon fontSize="small" />
          </IconButton>
        </DialogTitle>
        <DialogContent dividers>
          {selected && (
            <Stack spacing={2}>
              {/* Meta info */}
              <Stack direction="row" spacing={2} flexWrap="wrap" useFlexGap>
                <Box>
                  <Typography variant="caption" color="text.secondary">Time</Typography>
                  <Typography variant="body2" sx={{ fontFamily: 'monospace' }}>{selected.time}</Typography>
                </Box>
                <Box>
                  <Typography variant="caption" color="text.secondary">Engine</Typography>
                  <Typography variant="body2">{selected.engine}</Typography>
                </Box>
                <Box>
                  <Typography variant="caption" color="text.secondary">Duration</Typography>
                  <Typography variant="body2">{selected.duration_ms}ms</Typography>
                </Box>
                <Box>
                  <Typography variant="caption" color="text.secondary">User</Typography>
                  <Typography variant="body2">{selected.user || '-'}</Typography>
                </Box>
              </Stack>

              {selected.query && (
                <Box>
                  <Typography variant="caption" color="text.secondary">Query String</Typography>
                  <Typography
                    variant="body2"
                    sx={{
                      fontFamily: 'monospace',
                      bgcolor: 'action.hover',
                      color: 'text.primary',
                      p: 1,
                      borderRadius: 1,
                      border: '1px solid',
                      borderColor: 'divider'
                    }}
                  >
                    {selected.query}
                  </Typography>
                </Box>
              )}

              <Divider />

              {/* Request Body */}
              {selected.request_body && (
                <Box>
                  <Typography variant="subtitle2" sx={{ mb: 0.5 }}>Request Body</Typography>
                  <Box
                    component="pre"
                    sx={{
                      bgcolor: 'grey.900',
                      color: 'grey.100',
                      p: 1.5,
                      borderRadius: 1,
                      overflow: 'auto',
                      maxHeight: 250,
                      fontSize: 12,
                      fontFamily: '"Roboto Mono", monospace',
                      lineHeight: 1.5,
                      whiteSpace: 'pre-wrap',
                      wordBreak: 'break-word',
                      m: 0
                    }}
                  >
                    {formatJson(selected.request_body)}
                  </Box>
                </Box>
              )}

              {/* Response Body */}
              <Box>
                <Typography variant="subtitle2" sx={{ mb: 0.5 }}>Response Body</Typography>
                <Box
                  component="pre"
                  sx={{
                    bgcolor: selected.status >= 400 ? 'error.dark' : 'grey.900',
                    color: 'grey.100',
                    p: 1.5,
                    borderRadius: 1,
                    overflow: 'auto',
                    maxHeight: 400,
                    fontSize: 12,
                    fontFamily: '"Roboto Mono", monospace',
                    lineHeight: 1.5,
                    whiteSpace: 'pre-wrap',
                    wordBreak: 'break-word',
                    m: 0
                  }}
                >
                  {formatJson(selected.response_body) || '(empty)'}
                </Box>
              </Box>
            </Stack>
          )}
        </DialogContent>
      </Dialog>
    </Box>
  );
}
