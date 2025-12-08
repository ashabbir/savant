import React, { useEffect, useMemo, useState } from 'react';
import Grid from '@mui/material/Unstable_Grid2';
import Paper from '@mui/material/Paper';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import TextField from '@mui/material/TextField';
import Button from '@mui/material/Button';
import Alert from '@mui/material/Alert';
import LinearProgress from '@mui/material/LinearProgress';
import Autocomplete from '@mui/material/Autocomplete';
import Stack from '@mui/material/Stack';
import { Driver, driversCreate, driversUpdate, getErrorMessage, useDriver, useDrivers } from '../../api';
import { useNavigate, useParams } from 'react-router-dom';

export default function DriverEditor() {
  const params = useParams();
  const nav = useNavigate();
  const editingName = params.name || null;
  const list = useDrivers('');
  const driver = useDriver(editingName);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [name, setName] = useState('');
  const [summary, setSummary] = useState('');
  const [prompt, setPrompt] = useState('');
  const [tags, setTags] = useState<string>('');

  useEffect(() => {
    if (driver.data && editingName) {
      setName(driver.data.name);
      setSummary(driver.data.summary);
      setPrompt(driver.data.prompt_md);
      setTags((driver.data.tags || []).join(', '));
    }
  }, [driver.data, editingName]);

  async function save() {
    setBusy(true); setErr(null);
    try {
      const payload = { name, summary, prompt_md: prompt, tags: tags.split(',').map(s=>s.trim()).filter(Boolean) } as any;
      if (editingName) await driversUpdate(payload);
      else await driversCreate(payload);
      nav('/engines/drivers');
    } catch (e:any) { setErr(getErrorMessage(e)); } finally { setBusy(false); }
  }

  return (
    <Grid container spacing={2}>
      <Grid xs={12}>
        <Paper sx={{ p:2 }}>
          <Typography variant="subtitle1" sx={{ mb: 2 }}>{editingName ? `Edit Driver: ${editingName}` : 'Create Driver'}</Typography>
          {(list.isFetching || driver.isFetching) && <LinearProgress />}
          {err && <Alert severity="error" sx={{ mb: 2 }}>{err}</Alert>}
          <Stack spacing={2}>
            <TextField label="Name" value={name} onChange={(e)=>setName(e.target.value)} fullWidth disabled={!!editingName} />
            <TextField label="Summary" value={summary} onChange={(e)=>setSummary(e.target.value)} fullWidth />
            <TextField label="Tags (comma-separated)" value={tags} onChange={(e)=>setTags(e.target.value)} fullWidth />
            <TextField label="Prompt (Markdown)" value={prompt} onChange={(e)=>setPrompt(e.target.value)} fullWidth multiline minRows={8} />
            <Box>
              <Button variant="contained" disabled={!name || !summary || !prompt || busy} onClick={save}>Save</Button>
              <Button sx={{ ml: 1 }} onClick={() => nav('/engines/drivers')}>Cancel</Button>
            </Box>
          </Stack>
        </Paper>
      </Grid>
    </Grid>
  );
}

