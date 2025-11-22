import React, { useEffect, useMemo, useState } from 'react';
import { MemoryResource, useMemoryResource, useMemoryResources, useRepoStatus } from '../../api';
import Grid from '@mui/material/Grid2';
import Paper from '@mui/material/Paper';
import List from '@mui/material/List';
import ListItem from '@mui/material/ListItem';
import ListItemButton from '@mui/material/ListItemButton';
import ListItemText from '@mui/material/ListItemText';
import Typography from '@mui/material/Typography';
import LinearProgress from '@mui/material/LinearProgress';
import Alert from '@mui/material/Alert';
import Box from '@mui/material/Box';
import TextField from '@mui/material/TextField';
import MenuItem from '@mui/material/MenuItem';

import { marked } from 'marked';
import DOMPurify from 'dompurify';

export default function ContextResources() {
  const { data: status } = useRepoStatus();
  const [repo, setRepo] = useState<string>(() => localStorage.getItem('ctx.resources.repo') || '');
  const { data, isLoading, isError, error } = useMemoryResources(repo || null);
  const [sel, setSel] = useState<MemoryResource | null>(null);
  const content = useMemoryResource(sel?.uri || null);

  const rows = data || [];
  const repos = useMemo(()=> (status || []).map(r=>r.name), [status]);

  useEffect(() => {
    if (!sel && rows.length) {
      const last = localStorage.getItem('ctx.resources.selected');
      const found = rows.find(r => r.uri === last) || rows[0];
      if (found) setSel(found);
    }
  }, [rows]);

  useEffect(() => {
    localStorage.setItem('ctx.resources.repo', repo);
  }, [repo]);

  useEffect(() => {
    if (sel?.uri) localStorage.setItem('ctx.resources.selected', sel.uri);
  }, [sel?.uri]);

  return (
    <Grid container spacing={2}>
      <Grid size={{ xs: 12, md: 4 }}>
        <Paper sx={{ p: 1 }}>
          <Typography variant="subtitle1" sx={{ px: 1, py: 1 }}>Memory Resources</Typography>
          <TextField label="Repo" select value={repo} onChange={(e)=>setRepo(e.target.value)} sx={{ m:1, minWidth: 220 }}>
            <MenuItem value="">All</MenuItem>
            {repos.map(r => <MenuItem key={r} value={r}>{r}</MenuItem>)}
          </TextField>
          {isLoading && <LinearProgress />}
          {isError && <Alert severity="error">{(error as any)?.message || 'Failed to load resources'}</Alert>}
          <List dense>
            {rows.map(r => (
              <ListItem key={r.uri} disablePadding>
                <ListItemButton selected={sel?.uri === r.uri} onClick={()=>setSel(r)}>
                  <ListItemText primary={r.metadata.title} secondary={`${r.metadata.path}`} />
                </ListItemButton>
              </ListItem>
            ))}
          </List>
        </Paper>
      </Grid>
      <Grid size={{ xs: 12, md: 8 }}>
        <Paper sx={{ p: 2 }}>
          <Typography variant="subtitle1">{sel ? sel.metadata.title : 'Select a resource'}</Typography>
          {content.isFetching && <LinearProgress />}
          {content.isError && <Alert severity="error">{(content.error as any)?.message || 'Failed to load resource'}</Alert>}
          {content.data && (
            <Box sx={{ mt: 1 }}>
              <div dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(marked.parse(content.data)) }} />
            </Box>
          )}
        </Paper>
      </Grid>
    </Grid>
  );
}
