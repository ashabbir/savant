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
import Stack from '@mui/material/Stack';
import TextField from '@mui/material/TextField';

export default function Repos() {
  const { data, isLoading, isError, refetch } = useQuery<RepoStatus[]>({
    queryKey: ['repos', 'status'],
    queryFn: repoStatus
  });

  const [filter, setFilter] = useState('');
  const rows = useMemo(() => (data || []).filter(r => r.name.includes(filter)), [data, filter]);

  const resetMut = useMutation({ mutationFn: resetAndIndexAll, onSuccess: () => refetch() });
  const indexMut = useMutation({ mutationFn: (repo: string) => indexRepo(repo), onSuccess: () => refetch() });
  const deleteMut = useMutation({ mutationFn: (repo: string) => deleteRepo(repo), onSuccess: () => refetch() });

  return (
    <Box>
      <Stack direction={{ xs: 'column', sm: 'row' }} spacing={2} sx={{ mb: 2 }}>
        <TextField label="Filter" value={filter} onChange={(e) => setFilter(e.target.value)} />
        <Button variant="contained" color="warning" onClick={() => resetMut.mutate()} disabled={resetMut.isPending}>Reset + Index All</Button>
      </Stack>
      {isLoading && <LinearProgress />}
      {isError && <Alert severity="error">Failed to load repo status</Alert>}
      <Table size="small">
        <TableHead>
          <TableRow>
            <TableCell>Name</TableCell>
            <TableCell align="right">Files</TableCell>
            <TableCell align="right">Blobs</TableCell>
            <TableCell align="right">Chunks</TableCell>
            <TableCell>Last Indexed</TableCell>
            <TableCell align="right">Actions</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          {rows.map((r) => (
            <TableRow key={r.name}>
              <TableCell>{r.name}</TableCell>
              <TableCell align="right">{r.files}</TableCell>
              <TableCell align="right">{r.blobs}</TableCell>
              <TableCell align="right">{r.chunks}</TableCell>
              <TableCell>{r.last_mtime || '-'}</TableCell>
              <TableCell align="right">
                <Stack direction="row" spacing={1} justifyContent="flex-end">
                  <Button size="small" onClick={() => indexMut.mutate(r.name)} disabled={indexMut.isPending}>Index</Button>
                  <Button size="small" color="error" onClick={() => deleteMut.mutate(r.name)} disabled={deleteMut.isPending}>Delete</Button>
                </Stack>
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </Box>
  );
}

