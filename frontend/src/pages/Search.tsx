import React, { useEffect, useMemo, useState } from 'react';
import { useMutation } from '@tanstack/react-query';
import TextField from '@mui/material/TextField';
import Button from '@mui/material/Button';
import Box from '@mui/material/Box';
import Paper from '@mui/material/Paper';
import Typography from '@mui/material/Typography';
import Chip from '@mui/material/Chip';
import Stack from '@mui/material/Stack';
import LinearProgress from '@mui/material/LinearProgress';
import Alert from '@mui/material/Alert';
import { search, SearchResult } from '../api';
import Pagination from '@mui/material/Pagination';
import MenuItem from '@mui/material/MenuItem';

function Highlight({ text, query }: { text: string; query: string }) {
  if (!query) return <>{text}</>;
  const parts = text.split(new RegExp(`(${query.replace(/[.*+?^${}()|[\\]\\]/g, "\\$&")})`, 'gi'));
  return (
    <>
      {parts.map((part, i) => (
        part.toLowerCase() === query.toLowerCase() ? <mark key={i}>{part}</mark> : <span key={i}>{part}</span>
      ))}
    </>
  );
}

export default function Search() {
  const [q, setQ] = useState('');
  const [repo, setRepo] = useState('');
  const [results, setResults] = useState<SearchResult[]>([]);
  const [langFilter, setLangFilter] = useState('');
  const [perPage, setPerPage] = useState(10);
  const [page, setPage] = useState(1);

  const { mutateAsync, isPending, isError, error } = useMutation({
    mutationFn: async () => await search(q, repo || null, 100),
    onSuccess: (data) => setResults(data)
  });

  useEffect(() => setPage(1), [results.length, langFilter]);

  const filtered = useMemo(() => {
    return results.filter(r => !langFilter || r.lang.toLowerCase().includes(langFilter.toLowerCase()));
  }, [results, langFilter]);

  const totalPages = Math.max(1, Math.ceil(filtered.length / perPage));
  const pageData = useMemo(() => filtered.slice((page - 1) * perPage, (page - 1) * perPage + perPage), [filtered, page, perPage]);

  return (
    <Box>
      <Stack direction={{ xs: 'column', sm: 'row' }} spacing={2} sx={{ mb: 2 }}>
        <TextField label="Query" variant="outlined" fullWidth value={q} onChange={(e) => setQ(e.target.value)} />
        <TextField label="Repo (optional)" variant="outlined" value={repo} onChange={(e) => setRepo(e.target.value)} />
        <TextField label="Lang filter" variant="outlined" value={langFilter} onChange={(e) => setLangFilter(e.target.value)} />
        <TextField label="Per page" select value={perPage} onChange={(e) => setPerPage(Number(e.target.value))} sx={{ minWidth: 120 }}>
          {[10, 20, 50].map(n => <MenuItem key={n} value={n}>{n}</MenuItem>)}
        </TextField>
        <Button variant="contained" disabled={!q} onClick={() => mutateAsync()}>Search</Button>
      </Stack>
      {isPending && <LinearProgress />}
      {isError && <Alert severity="error">{(error as any)?.message || 'Search failed'}</Alert>}
      <Stack spacing={2}>
        {pageData.map((r, idx) => (
          <Paper key={idx} sx={{ p: 2 }}>
            <Stack direction="row" justifyContent="space-between" alignItems="center">
              <Typography variant="subtitle1" sx={{ fontFamily: 'monospace' }}>{r.rel_path}</Typography>
              <Stack direction="row" spacing={1}>
                <Chip size="small" label={r.lang} />
                <Chip size="small" label={r.score.toFixed(2)} />
              </Stack>
            </Stack>
            <Box component="pre" sx={{ whiteSpace: 'pre-wrap', mt: 1, fontFamily: 'monospace' }}>
              <Highlight text={r.chunk} query={q} />
            </Box>
          </Paper>
        ))}
      </Stack>
      <Stack direction="row" justifyContent="center" sx={{ mt: 2 }}>
        <Pagination count={totalPages} page={page} onChange={(_, p) => setPage(p)} shape="rounded" />
      </Stack>
    </Box>
  );
}
