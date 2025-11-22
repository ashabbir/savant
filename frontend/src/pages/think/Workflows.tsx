import React, { useState } from 'react';
import { useThinkWorkflows, useThinkWorkflowRead } from '../../api';
import Box from '@mui/material/Box';
import Grid from '@mui/material/Grid2';
import Tabs from '@mui/material/Tabs';
import Tab from '@mui/material/Tab';
import Button from '@mui/material/Button';
import Stack from '@mui/material/Stack';
import Paper from '@mui/material/Paper';
import List from '@mui/material/List';
import ListItem from '@mui/material/ListItem';
import ListItemButton from '@mui/material/ListItemButton';
import ListItemText from '@mui/material/ListItemText';
import Typography from '@mui/material/Typography';
import LinearProgress from '@mui/material/LinearProgress';
import Alert from '@mui/material/Alert';

export default function ThinkWorkflows() {
  const { data, isLoading, isError, error } = useThinkWorkflows();
  const [sel, setSel] = useState<string | null>(null);
  const wfRead = useThinkWorkflowRead(sel);
  const [subTab, setSubTab] = useState(0);

  return (
    <Grid container spacing={2}>
      <Grid size={{ xs: 12, md: 4 }}>
        <Paper sx={{ p: 1 }}>
          <Typography variant="subtitle1" sx={{ px: 1, py: 1 }}>Workflows</Typography>
          {isLoading && <LinearProgress />}
          {isError && <Alert severity="error">{(error as any)?.message || 'Failed to load workflows'}</Alert>}
          <List dense>
            {(data?.workflows || []).map(w => (
              <ListItem key={w.id} disablePadding>
                <ListItemButton selected={sel === w.id} onClick={() => setSel(w.id)}>
                  <ListItemText primary={w.id} secondary={`${w.version} — ${w.desc || ''}`} />
                </ListItemButton>
              </ListItem>
            ))}
          </List>
        </Paper>
      </Grid>
      <Grid size={{ xs: 12, md: 8 }}>
        <Paper sx={{ p: 2 }}>
          <Stack direction="row" spacing={2} alignItems="center" justifyContent="space-between">
            <Typography variant="subtitle1">Workflow {sel ? `(${sel})` : ''}</Typography>
            <Tabs value={subTab} onChange={(_, v)=>setSubTab(v)}>
              <Tab label="YAML" />
            </Tabs>
          </Stack>
          {wfRead.isFetching && <LinearProgress />}
          {wfRead.isError && <Alert severity="error">{(wfRead.error as any)?.message || 'Failed to load workflow'}</Alert>}
          {subTab === 0 && (
            <Box component="pre" sx={{ mt: 1, whiteSpace: 'pre-wrap', fontFamily: 'monospace', fontSize: 13 }}>
              {wfRead.data?.workflow_yaml || 'Select a workflow to view YAML'}
            </Box>
          )}
        </Paper>
      </Grid>
    </Grid>
  );
}
