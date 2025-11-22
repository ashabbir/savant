import React, { useMemo, useState } from 'react';
import { useThinkRuns, useThinkRun, thinkRunDelete } from '../../api';
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
import Stack from '@mui/material/Stack';
import Button from '@mui/material/Button';

export default function ThinkRuns() {
  const { data, isLoading, isError, error, refetch } = useThinkRuns();
  const rows = data?.runs || [];
  const [sel, setSel] = useState<{ workflow: string; run_id: string } | null>(null);
  const run = useThinkRun(sel?.workflow || null, sel?.run_id || null);

  const title = useMemo(() => sel ? `${sel.workflow} / ${sel.run_id}` : 'Select a run', [sel]);

  async function del() {
    if (!sel) return;
    await thinkRunDelete(sel.workflow, sel.run_id);
    setSel(null);
    refetch();
  }

  return (
    <Grid container spacing={2}>
      <Grid size={{ xs: 12, md: 4 }}>
        <Paper sx={{ p: 1 }}>
          <Typography variant="subtitle1" sx={{ px: 1, py: 1 }}>Runs</Typography>
          {isLoading && <LinearProgress />}
          {isError && <Alert severity="error">{(error as any)?.message || 'Failed to load runs'}</Alert>}
          <List dense>
            {rows.map(r => (
              <ListItem key={`${r.workflow}__${r.run_id}`} disablePadding>
                <ListItemButton selected={sel?.run_id === r.run_id && sel?.workflow === r.workflow} onClick={() => setSel({ workflow: r.workflow, run_id: r.run_id })}>
                  <ListItemText primary={`${r.workflow} / ${r.run_id}`} secondary={`completed=${r.completed} next=${r.next_step_id || '-'} updated=${r.updated_at}`} />
                </ListItemButton>
              </ListItem>
            ))}
          </List>
        </Paper>
      </Grid>
      <Grid size={{ xs: 12, md: 8 }}>
        <Paper sx={{ p: 2 }}>
          <Stack direction="row" justifyContent="space-between" alignItems="center"> 
            <Typography variant="subtitle1">Run state — {title}</Typography>
            <Button size="small" color="error" disabled={!sel} onClick={del}>Delete</Button>
          </Stack>
          {run.isFetching && <LinearProgress />}
          {run.isError && <Alert severity="error">{(run.error as any)?.message || 'Failed to load run'}</Alert>}
          <Box component="pre" sx={{ mt: 1, whiteSpace: 'pre-wrap', fontFamily: 'monospace', fontSize: 13 }}>
            {run.data ? JSON.stringify(run.data.state, null, 2) : 'Pick a run to view state'}
          </Box>
        </Paper>
      </Grid>
    </Grid>
  );
}
