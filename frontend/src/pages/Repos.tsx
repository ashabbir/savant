import React, { useMemo, useState } from 'react';
import { useMutation, useQuery } from '@tanstack/react-query';
import { deleteRepo, indexRepo, repoStatus, resetAndIndexAll, RepoStatus } from '../api';
import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import LinearProgress from '@mui/material/LinearProgress';
import Alert from '@mui/material/Alert';
import Table from '@mui/material/Table';
import TableHead from '@mui/material/TableHead';
import TableRow from '@mui/material/TableRow';
import TableCell from '@mui/material/TableCell';
import TableBody from '@mui/material/TableBody';
import TableContainer from '@mui/material/TableContainer';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import TextField from '@mui/material/TextField';
import Snackbar from '@mui/material/Snackbar';
import Typography from '@mui/material/Typography';
import RefreshIcon from '@mui/icons-material/Refresh';
import CircularProgress from '@mui/material/CircularProgress';

export default function Repos() {
  const { data, isLoading, isError, refetch } = useQuery<RepoStatus[]>({
    queryKey: ['repos', 'status'],
    queryFn: repoStatus
  });

  const [filter, setFilter] = useState('');
  const rows = useMemo(() => (data || []).filter(r => r.name.includes(filter)), [data, filter]);

  const [toast, setToast] = useState<string | null>(null);
  const resetMut = useMutation({
    mutationFn: resetAndIndexAll,
    onSuccess: () => { setToast('Reset + Index All triggered'); refetch(); },
    onError: (e: any) => setToast(`Error: ${e?.message || 'failed'}`)
  });
  const indexMut = useMutation({
    mutationFn: (r: string) => indexRepo(r),
    onSuccess: () => { setToast('Index started'); refetch(); },
    onError: (e: any) => setToast(`Error: ${e?.message || 'failed'}`)
  });
  const deleteMut = useMutation({
    mutationFn: (r: string) => deleteRepo(r),
    onSuccess: () => { setToast('Delete requested'); refetch(); },
    onError: (e: any) => setToast(`Error: ${e?.message || 'failed'}`)
  });

  return (
    <>
      <Paper sx={{ p: 2, mb: 2 }}>
        <Stack direction={{ xs: 'column', sm: 'row' }} spacing={2} alignItems="center" justifyContent="space-between">
          <Typography variant="h6">Repositories</Typography>
          <Stack direction="row" spacing={2} alignItems="center">
            <TextField id="repo-filter" name="repoFilter"
              label="Filter"
              value={filter}
              onChange={(e) => setFilter(e.target.value)}
              size="small"
              sx={{ minWidth: 200 }}
            />
            <Button
              variant="contained"
              onClick={() => resetMut.mutate()}
              disabled={resetMut.isPending}
              startIcon={resetMut.isPending ? <CircularProgress size={16} color="inherit" /> : <RefreshIcon />}
              sx={{
                background: 'linear-gradient(45deg, #f57c00 30%, #ff9800 90%)',
                boxShadow: '0 2px 4px rgba(245,124,0,.3)',
                '&:hover': {
                  background: 'linear-gradient(45deg, #e65100 30%, #f57c00 90%)',
                }
              }}
            >
              {resetMut.isPending ? 'Reindexing...' : 'Reset + Reindex All'}
            </Button>
          </Stack>
        </Stack>
      </Paper>

      {isLoading && <LinearProgress sx={{ mb: 2 }} />}
      {isError && <Alert severity="error" sx={{ mb: 2 }}>Failed to load repo status</Alert>}

      <TableContainer component={Paper}>
        <Table size="small">
          <TableHead>
            <TableRow sx={{ bgcolor: 'grey.100' }}>
              <TableCell sx={{ fontWeight: 600 }}>Name</TableCell>
              <TableCell align="right" sx={{ fontWeight: 600 }}>Files</TableCell>
              <TableCell align="right" sx={{ fontWeight: 600 }}>Blobs</TableCell>
              <TableCell align="right" sx={{ fontWeight: 600 }}>Chunks</TableCell>
              <TableCell sx={{ fontWeight: 600 }}>Last Indexed</TableCell>
              <TableCell align="right" sx={{ fontWeight: 600 }}>Actions</TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {rows.map((r) => (
              <TableRow key={r.name} hover>
                <TableCell sx={{ fontFamily: 'monospace' }}>{r.name}</TableCell>
                <TableCell align="right">{r.files.toLocaleString()}</TableCell>
                <TableCell align="right">{r.blobs.toLocaleString()}</TableCell>
                <TableCell align="right">{r.chunks.toLocaleString()}</TableCell>
                <TableCell>{r.last_mtime || '-'}</TableCell>
                <TableCell align="right">
                  <Stack direction="row" spacing={1} justifyContent="flex-end">
                    <Button size="small" variant="outlined" onClick={() => indexMut.mutate(r.name)} disabled={indexMut.isPending}>Index</Button>
                    <Button size="small" variant="outlined" color="error" onClick={() => deleteMut.mutate(r.name)} disabled={deleteMut.isPending}>Delete</Button>
                  </Stack>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </TableContainer>

      <Snackbar open={!!toast} autoHideDuration={3000} onClose={() => setToast(null)} message={toast || ''} />
    </>
  );
}
