import React, { useMemo, useState } from 'react';
import { callContextTool, ContextToolSpec, useContextTools } from '../../api';
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
import TextField from '@mui/material/TextField';

export default function ContextTools() {
  const { data, isLoading, isError, error } = useContextTools();
  const tools = data?.tools || [];
  const [sel, setSel] = useState<ContextToolSpec | null>(null);
  const [input, setInput] = useState<string>('{}');
  const [out, setOut] = useState<string>('');
  const schema = useMemo(() => sel?.inputSchema || sel?.schema, [sel]);
  const name = sel?.name || '';

  async function run() {
    try {
      const params = input ? JSON.parse(input) : {};
      const res = await callContextTool(name, params);
      setOut(JSON.stringify(res, null, 2));
    } catch (e: any) {
      setOut(String(e?.message || e));
    }
  }

  return (
    <Grid container spacing={2}>
      <Grid size={{ xs: 12, md: 4 }}>
        <Paper sx={{ p: 1 }}>
          <Typography variant="subtitle1" sx={{ px: 1, py: 1 }}>Context Tools</Typography>
          {isLoading && <LinearProgress />}
          {isError && <Alert severity="error">{(error as any)?.message || 'Failed to load tools'}</Alert>}
          <List dense>
            {tools.map(t => (
              <ListItem key={t.name} disablePadding>
                <ListItemButton selected={sel?.name === t.name} onClick={() => { setSel(t); setInput('{}'); setOut(''); }}>
                  <ListItemText primary={t.name} secondary={t.description} />
                </ListItemButton>
              </ListItem>
            ))}
          </List>
        </Paper>
      </Grid>
      <Grid size={{ xs: 12, md: 8 }}>
        <Paper sx={{ p: 2 }}>
          <Typography variant="subtitle1">{name || 'Select a tool'}</Typography>
          {schema && (
            <Box component="pre" sx={{ mt: 1, whiteSpace: 'pre-wrap', fontFamily: 'monospace', fontSize: 12, bgcolor: '#fafafa', p: 1 }}>
              {JSON.stringify(schema, null, 2)}
            </Box>
          )}
          <Stack spacing={1} sx={{ mt: 1 }}>
            <TextField label="Params (JSON)" value={input} onChange={(e)=>setInput(e.target.value)} multiline minRows={4} />
            <Stack direction="row" spacing={1}>
              <Button variant="contained" onClick={run} disabled={!sel}>Call</Button>
              <Button onClick={() => setOut('')}>Clear</Button>
            </Stack>
            <Box component="pre" sx={{ mt: 1, whiteSpace: 'pre-wrap', fontFamily: 'monospace', fontSize: 12 }}>
              {out}
            </Box>
          </Stack>
        </Paper>
      </Grid>
    </Grid>
  );
}

