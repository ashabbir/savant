import React, { useEffect, useMemo, useState } from 'react';
import { useEngineTools, ContextToolSpec } from '../../api';
import Grid from '@mui/material/Grid2';
import Paper from '@mui/material/Paper';
import List from '@mui/material/List';
import ListItem from '@mui/material/ListItem';
import ListItemButton from '@mui/material/ListItemButton';
import ListItemText from '@mui/material/ListItemText';
import Typography from '@mui/material/Typography';
import LinearProgress from '@mui/material/LinearProgress';
import Alert from '@mui/material/Alert';
import TextField from '@mui/material/TextField';
import Box from '@mui/material/Box';
import Viewer from '../../components/Viewer';

const PANEL_HEIGHT = 'calc(100vh - 260px)';

export default function JiraTools() {
  const { data, isLoading, isError, error } = useEngineTools('jira');
  const tools = data?.tools || [];
  const [sel, setSel] = useState<ContextToolSpec | null>(null);
  const [filter, setFilter] = useState<string>('');
  const schema = useMemo(() => sel?.inputSchema || sel?.schema, [sel]);

  // Load first tool by default
  useEffect(() => {
    if (!sel && tools.length) setSel(tools[0]);
  }, [tools]);

  return (
    <Grid container spacing={2}>
      <Grid size={{ xs: 12, md: 4 }}>
        <Paper sx={{ p: 1, height: PANEL_HEIGHT, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
          <Typography variant="subtitle1" sx={{ px: 1, py: 1 }}>Jira Tools</Typography>
          <TextField id="jira-filter" name="jiraFilter" size="small" label="Filter" value={filter} onChange={(e)=>setFilter(e.target.value)} sx={{ m: 1 }} />
          {isLoading && <LinearProgress />}
          {isError && <Alert severity="error">{(error as any)?.message || 'Failed to load tools'}</Alert>}
          <Box sx={{ flex: 1, overflowY: 'auto' }}>
            <List dense>
              {tools.filter(t => !filter || t.name.includes(filter) || (t.description||'').includes(filter)).map(t => (
                <ListItem key={t.name} disablePadding>
                  <ListItemButton selected={sel?.name === t.name} onClick={() => setSel(t)}>
                    <ListItemText primary={t.name} secondary={t.description} />
                  </ListItemButton>
                </ListItem>
              ))}
            </List>
          </Box>
        </Paper>
      </Grid>
      <Grid size={{ xs: 12, md: 8 }}>
        <Paper sx={{ p: 2, height: PANEL_HEIGHT, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
          <Typography variant="subtitle1" sx={{ fontSize: 12 }}>{sel?.name || 'Select a tool'}</Typography>
          {schema ? (
            <Viewer content={JSON.stringify(schema, null, 2)} contentType="application/json" height={undefined} style={{ flex: 1 }} />
          ) : (
            <Box sx={{ p: 2, color: 'text.secondary', flex: 1, overflowY: 'auto' }}>No input schema available</Box>
          )}
        </Paper>
      </Grid>
    </Grid>
  );
}
