import React, { useEffect, useMemo, useState } from 'react';
import { useEngineTools, ContextToolSpec } from '../api';
import Grid from '@mui/material/Unstable_Grid2';
import Paper from '@mui/material/Paper';
import List from '@mui/material/List';
import ListItem from '@mui/material/ListItem';
import ListItemButton from '@mui/material/ListItemButton';
import ListItemText from '@mui/material/ListItemText';
import Typography from '@mui/material/Typography';
import Stack from '@mui/material/Stack';
import LinearProgress from '@mui/material/LinearProgress';
import Alert from '@mui/material/Alert';
import TextField from '@mui/material/TextField';
import Box from '@mui/material/Box';
import ToolRunner from './ToolRunner';

const PANEL_HEIGHT = 'calc(100vh - 260px)';

export default function EngineToolsList({ engine, title, readOnly = false }: { engine: string; title?: string; readOnly?: boolean }) {
  const { data, isLoading, isError, error } = useEngineTools(engine);
  const tools = data?.tools || [];
  const [sel, setSel] = useState<ContextToolSpec | null>(null);
  const [filter, setFilter] = useState<string>('');
  const schema = useMemo(() => sel?.inputSchema || sel?.schema, [sel]);

  useEffect(() => { if (!sel && tools.length) setSel(tools[0]); }, [tools]);

  return (
    <Grid container spacing={2}>
      <Grid xs={12} md={4}>
        <Paper sx={{ p: 1, height: PANEL_HEIGHT, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
          <Stack direction="row" alignItems="center" justifyContent="space-between" sx={{ mb: 1 }}>
            <Typography variant="subtitle1" sx={{ fontSize: 12 }}>{title || `${engine} Tools`}</Typography>
          </Stack>
          {isLoading && <LinearProgress />}
          {isError && <Alert severity="error">{(error as any)?.message || 'Failed to load tools'}</Alert>}
          <TextField fullWidth size="small" placeholder="Search tools..." value={filter} onChange={(e)=>setFilter(e.target.value)} sx={{ mb: 1 }} />
          <Box sx={{ flex: 1, overflowY: 'auto' }}>
            <List dense>
              {tools.filter(t => !filter || t.name.toLowerCase().includes(filter.toLowerCase()) || (t.description||'').toLowerCase().includes(filter.toLowerCase())).map(t => (
                <ListItem key={t.name} disablePadding>
                  <ListItemButton selected={sel?.name === t.name} onClick={() => setSel(t)}>
                    <ListItemText
                      primary={<Typography component="span" sx={{ fontWeight: 600 }}>{t.name}</Typography>}
                      secondary={t.description}
                    />
                  </ListItemButton>
                </ListItem>
              ))}
            </List>
          </Box>
        </Paper>
      </Grid>
      <Grid xs={12} md={8}>
        <ToolRunner engine={engine} tool={sel} readOnly={readOnly} />
      </Grid>
    </Grid>
  );
}
