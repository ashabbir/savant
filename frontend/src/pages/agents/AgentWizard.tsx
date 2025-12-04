import React, { useMemo, useState } from 'react';
import Grid from '@mui/material/Grid2';
import Paper from '@mui/material/Paper';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import TextField from '@mui/material/TextField';
import Button from '@mui/material/Button';
import Alert from '@mui/material/Alert';
import LinearProgress from '@mui/material/LinearProgress';
import Autocomplete from '@mui/material/Autocomplete';
import Stack from '@mui/material/Stack';
import { agentsCreate, getErrorMessage, usePersonas, useRules } from '../../api';
import { useNavigate } from 'react-router-dom';

export default function AgentWizard() {
  const nav = useNavigate();
  const personas = usePersonas('');
  const rules = useRules('');
  const personaOptions = useMemo(() => (personas.data?.personas || []).map(p=>p.name), [personas.data]);
  const ruleOptions = useMemo(() => (rules.data?.rules || []).map(r=>r.name), [rules.data]);
  const [name, setName] = useState('');
  const [persona, setPersona] = useState<string | null>(null);
  const [driver, setDriver] = useState('');
  const [selRules, setSelRules] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function create() {
    setBusy(true); setError(null);
    try {
      await agentsCreate({ name, persona: persona || '', driver, rules: selRules });
      nav('/engines/agents');
    } catch (e:any) {
      setError(getErrorMessage(e));
    } finally { setBusy(false); }
  }

  return (
    <Grid container spacing={2}>
      <Grid size={{ xs: 12, md: 8 }}>
        <Paper sx={{ p:2 }}>
          <Typography variant="subtitle1" sx={{ mb: 2 }}>Create Agent</Typography>
          {personas.isFetching && <LinearProgress />}
          {rules.isFetching && <LinearProgress />}
          {error && <Alert severity="error" sx={{ mb: 2 }}>{error}</Alert>}
          <Stack spacing={2}>
            <TextField label="Name" value={name} onChange={(e)=>setName(e.target.value)} fullWidth />
            <Autocomplete
              options={personaOptions}
              value={persona}
              onChange={(_, v)=>setPersona(v)}
              renderInput={(params)=>(<TextField {...params} label="Persona" />)}
            />
            <TextField label="Driver (mission + endpoint)" value={driver} onChange={(e)=>setDriver(e.target.value)} fullWidth multiline minRows={4} />
            <Autocomplete
              multiple
              options={ruleOptions}
              value={selRules}
              onChange={(_, v)=>setSelRules(v)}
              renderInput={(params)=>(<TextField {...params} label="Rules" />)}
            />
            <Box>
              <Button variant="contained" disabled={!name || !persona || !driver || busy} onClick={create}>Save Agent</Button>
              <Button sx={{ ml: 1 }} onClick={() => nav('/engines/agents')}>Cancel</Button>
            </Box>
          </Stack>
        </Paper>
      </Grid>
    </Grid>
  );
}

