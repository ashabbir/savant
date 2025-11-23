import React, { useMemo, useState } from 'react';
import Grid from '@mui/material/Grid2';
import Paper from '@mui/material/Paper';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import LinearProgress from '@mui/material/LinearProgress';
import Alert from '@mui/material/Alert';
import TextField from '@mui/material/TextField';
import List from '@mui/material/List';
import ListItem from '@mui/material/ListItem';
import ListItemButton from '@mui/material/ListItemButton';
import ListItemText from '@mui/material/ListItemText';
import Chip from '@mui/material/Chip';
import Stack from '@mui/material/Stack';
import yaml from 'js-yaml';
import Button from '@mui/material/Button';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import DialogActions from '@mui/material/DialogActions';
import Viewer from '../../components/Viewer';
import { getErrorMessage, usePersona, usePersonas } from '../../api';

export default function Personas() {
  const [filter, setFilter] = useState('');
  const { data, isLoading, isError, error } = usePersonas(filter);
  const [sel, setSel] = useState<string | null>(null);
  const details = usePersona(sel);
  const [openPrompt, setOpenPrompt] = useState(false);

  const personas = data?.personas || [];
  const selected = details.data || null;
  const yamlText = useMemo(() => {
    if (!selected) return '# Select a persona to view details as YAML';
    const obj: any = { ...selected };
    return yaml.dump(obj, { lineWidth: 100 });
  }, [selected]);

  return (
    <Grid container spacing={2}>
      <Grid size={{ xs: 12, md: 4 }}>
        <Paper sx={{ p: 2 }}>
          <Typography variant="subtitle1" sx={{ mb: 1 }}>Personas</Typography>
          <TextField
            size="small"
            fullWidth
            placeholder="Filter by name, title, tags..."
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            sx={{ mb: 1.5 }}
          />
          {isLoading && <LinearProgress />}
          {isError && <Alert severity="error">{getErrorMessage(error as any)}</Alert>}
          <List dense>
            {personas.map((p) => (
              <ListItem key={p.name} disablePadding>
                <ListItemButton selected={sel === p.name} onClick={() => setSel(p.name)}>
                  <ListItemText
                    primary={<Box display="flex" alignItems="center" gap={1}><strong>{p.title}</strong><Chip size="small" label={p.version} /></Box>}
                    secondary={p.summary}
                  />
                </ListItemButton>
              </ListItem>
            ))}
          </List>
        </Paper>
      </Grid>
      <Grid size={{ xs: 12, md: 8 }}>
        <Stack spacing={2}>
          <Paper sx={{ p: 2 }}>
            <Stack direction="row" alignItems="center" justifyContent="space-between">
              <Typography variant="subtitle1">Persona (YAML)</Typography>
              <Button size="small" variant="outlined" disabled={!selected} onClick={() => setOpenPrompt(true)}>
                View Prompt
              </Button>
            </Stack>
            {details.isFetching && <LinearProgress />}
            {details.isError && <Alert severity="error">{getErrorMessage(details.error as any)}</Alert>}
            <Viewer content={yamlText} contentType="text/yaml" height={360} />
          </Paper>

          <Dialog open={openPrompt} onClose={() => setOpenPrompt(false)} fullWidth maxWidth="md">
            <DialogTitle>
              Prompt Markdown {selected ? `(${selected.title})` : ''}
            </DialogTitle>
            <DialogContent dividers>
              <Viewer content={selected?.prompt_md || 'Select a persona to view prompt markdown'} contentType="text/markdown" height={'60vh'} />
            </DialogContent>
            <DialogActions>
              <Button onClick={() => setOpenPrompt(false)}>Close</Button>
            </DialogActions>
          </Dialog>
        </Stack>
      </Grid>
    </Grid>
  );
}
