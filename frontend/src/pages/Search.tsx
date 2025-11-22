import React, { useState } from 'react';
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

export default function Search() {
  const [q, setQ] = useState('');
  const [repo, setRepo] = useState('');
  const [results, setResults] = useState<SearchResult[]>([]);
  const { mutateAsync, isPending, isError, error } = useMutation({
    mutationFn: async () => await search(q, repo || null, 20),
    onSuccess: (data) => setResults(data)
  });

  return (
    <Box>
      <Stack direction={{ xs: 'column', sm: 'row' }} spacing={2} sx={{ mb: 2 }}>
        <TextField label="Query" variant="outlined" fullWidth value={q} onChange={(e) => setQ(e.target.value)} />
        <TextField label="Repo (optional)" variant="outlined" value={repo} onChange={(e) => setRepo(e.target.value)} />
        <Button variant="contained" disabled={!q} onClick={() => mutateAsync()}>Search</Button>
      </Stack>
      {isPending && <LinearProgress />}
      {isError && <Alert severity="error">{(error as any)?.message || 'Search failed'}</Alert>}
      <Stack spacing={2}>
        {results.map((r, idx) => (
          <Paper key={idx} sx={{ p: 2 }}>
            <Stack direction="row" justifyContent="space-between" alignItems="center">
              <Typography variant="subtitle1" sx={{ fontFamily: 'monospace' }}>{r.rel_path}</Typography>
              <Stack direction="row" spacing={1}>
                <Chip size="small" label={r.lang} />
                <Chip size="small" label={r.score.toFixed(2)} />
              </Stack>
            </Stack>
            <Box component="pre" sx={{ whiteSpace: 'pre-wrap', mt: 1, fontFamily: 'monospace' }}>{r.chunk}</Box>
          </Paper>
        ))}
      </Stack>
    </Box>
  );
}

