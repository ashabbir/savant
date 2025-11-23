import React, { useEffect, useMemo, useState } from 'react';
import { useMutation } from '@tanstack/react-query';
import Box from '@mui/material/Box';
import Stack from '@mui/material/Stack';
import TextField from '@mui/material/TextField';
import Button from '@mui/material/Button';
import Paper from '@mui/material/Paper';
import Typography from '@mui/material/Typography';
import Chip from '@mui/material/Chip';
import LinearProgress from '@mui/material/LinearProgress';
import Alert from '@mui/material/Alert';
import Pagination from '@mui/material/Pagination';
import MenuItem from '@mui/material/MenuItem';
import Viewer from '../../components/Viewer';
import { searchMemory, useRepoStatus, SearchResult, getErrorMessage } from '../../api';

export default function MemorySearch() {
  const [q, setQ] = useState('');
  const [repo, setRepo] = useState('');
  const [results, setResults] = useState<SearchResult[]>([]);
  const { data: statusData } = useRepoStatus();
  const [perPage, setPerPage] = useState(20);
  const [page, setPage] = useState(1);

  const { mutateAsync, isPending, isError, error } = useMutation({
    mutationFn: async () => await searchMemory(q, repo || null, 20),
    onSuccess: (data) => setResults(data)
  });

  useEffect(() => setPage(1), [results.length]);

  const totalPages = Math.max(1, Math.ceil(results.length / perPage));
  const pageData = useMemo(() => results.slice((page - 1) * perPage, (page - 1) * perPage + perPage), [results, page, perPage]);

  return (
    <Box>
      <Paper sx={{ p: 2, mb: 2 }}>
        <Typography variant="subtitle2" sx={{ mb: 2, fontWeight: 600 }}>Memory Search</Typography>
        <Stack spacing={2}>
          <TextField
            label="Memory Query"
            variant="outlined"
            fullWidth
            value={q}
            onChange={(e) => setQ(e.target.value)}
          />
          <TextField
            label="Repository"
            select
            fullWidth
            value={repo}
            onChange={(e) => setRepo(e.target.value)}
          >
            <MenuItem value="">All Repositories</MenuItem>
            {(statusData || []).map((r) => (
              <MenuItem key={r.name} value={r.name}>{r.name}</MenuItem>
            ))}
          </TextField>
          <TextField
            label="Results per page"
            select
            fullWidth
            value={perPage}
            onChange={(e) => setPerPage(Number(e.target.value))}
          >
            {[10, 20, 50].map(n => <MenuItem key={n} value={n}>{n}</MenuItem>)}
          </TextField>
          <Box sx={{ display: 'flex', gap: 1 }}>
            <Button
              variant="contained"
              disabled={!q}
              onClick={() => mutateAsync()}
              sx={{ minWidth: 120 }}
            >
              Search
            </Button>
            <Button
              variant="outlined"
              onClick={() => { setResults([]); setQ(''); setRepo(''); }}
            >
              Clear
            </Button>
          </Box>
        </Stack>
      </Paper>
      {isPending && <LinearProgress />}
      {isError && <Alert severity="error">{getErrorMessage(error as any) || 'Memory search failed'}</Alert>}
      <Stack spacing={2}>
        {pageData.map((r, idx) => (
          <Paper key={idx} sx={{ p: 2 }}>
            <Stack direction="row" justifyContent="space-between" alignItems="center">
              <Typography variant="subtitle1" sx={{ fontFamily: 'monospace' }}>{r.rel_path}</Typography>
              <Chip size="small" label={r.score.toFixed(2)} />
            </Stack>
            <Viewer content={r.chunk} filename={r.rel_path} language={(r as any).lang} height={260} />
          </Paper>
        ))}
      </Stack>
      <Stack direction="row" justifyContent="center" sx={{ mt: 2 }}>
        <Pagination count={totalPages} page={page} onChange={(_, p) => setPage(p)} shape="rounded" />
      </Stack>
    </Box>
  );
}
