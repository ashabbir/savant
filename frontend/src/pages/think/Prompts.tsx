import React, { useState } from 'react';
import { useThinkPrompts, useThinkPrompt } from '../../api';
import Box from '@mui/material/Box';
import Grid from '@mui/material/Grid2';
import Paper from '@mui/material/Paper';
import List from '@mui/material/List';
import ListItem from '@mui/material/ListItem';
import ListItemButton from '@mui/material/ListItemButton';
import ListItemText from '@mui/material/ListItemText';
import Typography from '@mui/material/Typography';
import LinearProgress from '@mui/material/LinearProgress';
import Alert from '@mui/material/Alert';

export default function ThinkPrompts() {
  const { data, isLoading, isError, error } = useThinkPrompts();
  const [sel, setSel] = useState<string | null>(null);
  const pr = useThinkPrompt(sel);

  return (
    <Grid container spacing={2}>
      <Grid size={{ xs: 12, md: 4 }}>
        <Paper sx={{ p: 1 }}>
          <Typography variant="subtitle1" sx={{ px: 1, py: 1 }}>Prompts</Typography>
          {isLoading && <LinearProgress />}
          {isError && <Alert severity="error">{(error as any)?.message || 'Failed to load prompts'}</Alert>}
          <List dense>
            {(data?.versions || []).map(v => (
              <ListItem key={v.version} disablePadding>
                <ListItemButton selected={sel === v.version} onClick={() => setSel(v.version)}>
                  <ListItemText primary={v.version} secondary={v.path} />
                </ListItemButton>
              </ListItem>
            ))}
          </List>
        </Paper>
      </Grid>
      <Grid size={{ xs: 12, md: 8 }}>
        <Paper sx={{ p: 2 }}>
          <Typography variant="subtitle1">Prompt Markdown {sel ? `(${sel})` : ''}</Typography>
          {pr.isFetching && <LinearProgress />}
          {pr.isError && <Alert severity="error">{(pr.error as any)?.message || 'Failed to load prompt'}</Alert>}
          <Box component="pre" sx={{ mt: 1, whiteSpace: 'pre-wrap', fontFamily: 'monospace', fontSize: 13 }}>
            {pr.data?.prompt_md || 'Select a prompt version to view markdown'}
          </Box>
        </Paper>
      </Grid>
    </Grid>
  );
}

