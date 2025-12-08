import React, { useMemo, useState } from 'react';
import Grid from '@mui/material/Unstable_Grid2';
import Paper from '@mui/material/Paper';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import TextField from '@mui/material/TextField';
import Button from '@mui/material/Button';
import Alert from '@mui/material/Alert';
import LinearProgress from '@mui/material/LinearProgress';
import Autocomplete from '@mui/material/Autocomplete';
import Divider from '@mui/material/Divider';
import Tooltip from '@mui/material/Tooltip';
import Stack from '@mui/material/Stack';
import { agentsCreate, getErrorMessage, usePersonas, useRules, useDrivers } from '../../api';
import { useNavigate } from 'react-router-dom';

export default function AgentWizard() {
  const nav = useNavigate();
  const personas = usePersonas('');
  const rules = useRules('');
  const drivers = useDrivers('');
  const personaOptions = useMemo(() => (personas.data?.personas || []).map(p=>p.name), [personas.data]);
  const driverOptions = useMemo(() => (drivers.data?.drivers || []).map(d=>d.name), [drivers.data]);
  const ruleOptions = useMemo(() => (rules.data?.rules || []).map(r=>r.name), [rules.data]);
  const [name, setName] = useState('');
  const [persona, setPersona] = useState<string | null>(null);
  const [driver, setDriver] = useState<string | null>(null);
  const [selRules, setSelRules] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function create() {
    setBusy(true); setError(null);
    try {
      await agentsCreate({ name, persona: persona || '', driver: driver || '', rules: selRules });
      nav('/agents');
    } catch (e:any) {
      setError(getErrorMessage(e));
    } finally { setBusy(false); }
  }

  function insertSearchDriver() {}

  return (
    <Grid container spacing={2}>
      <Grid xs={12}>
        <Paper sx={{ p:2 }}>
          <Typography variant="subtitle1" sx={{ mb: 2 }}>Create Agent</Typography>
          {personas.isFetching && <LinearProgress />}
          {rules.isFetching && <LinearProgress />}
          {error && <Alert severity="error" sx={{ mb: 2 }}>{error}</Alert>}
          <Stack spacing={2}>
            <TextField label="Name" value={name} onChange={(e)=>setName(e.target.value)} fullWidth />
            <Autocomplete
              options={personaOptions}
              freeSolo
              value={persona}
              onChange={(_, v)=>setPersona(v)}
              renderInput={(params)=>(<TextField {...params} label="Persona" />)}
            />
            <Autocomplete
              options={driverOptions}
              value={driver}
              onChange={(_, v)=>setDriver(v)}
              renderInput={(params)=>(<TextField {...params} label="Driver" />)}
            />
            <Autocomplete
              multiple
              options={ruleOptions}
              freeSolo
              value={selRules}
              onChange={(_, v)=>setSelRules(v)}
              renderInput={(params)=>(<TextField {...params} label="Rules" />)}
            />
            <Divider />
            <Typography variant="subtitle2">Action Helpers</Typography>
            <Stack direction="row" spacing={1} flexWrap="wrap" useFlexGap>
              <Tooltip title="Insert a sensible search + memory + summary driver template">
                <span>
                  <Button size="small" variant="outlined" onClick={insertSearchDriver}>Insert Search Driver</Button>
                </span>
              </Tooltip>
            </Stack>
            <Box>
              <Button variant="contained" disabled={!name || !persona || !driver || busy} onClick={create}>Save Agent</Button>
              <Button sx={{ ml: 1 }} onClick={() => nav('/agents')}>Cancel</Button>
            </Box>
          </Stack>
        </Paper>
      </Grid>
    </Grid>
  );
}
