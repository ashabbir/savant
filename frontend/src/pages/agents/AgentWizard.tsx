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
import Stack from '@mui/material/Stack';
import FormControlLabel from '@mui/material/FormControlLabel';
import Switch from '@mui/material/Switch';
import { agentsCreate, getErrorMessage, usePersonas, useRules, useDrivers, useRoutes, callEngineTool } from '../../api';
import { useNavigate } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';

export default function AgentWizard() {
  const nav = useNavigate();
  const personas = usePersonas('');
  const rules = useRules('');
  const drivers = useDrivers('');
  const routes = useRoutes();
  const models = useQuery({
    queryKey: ['llm', 'models'],
    queryFn: async () => {
      const res = await callEngineTool('llm', 'llm_models_list', {});
      return res.models || [];
    },
  });
  const personaOptions = useMemo(() => (personas.data?.personas || []).map(p=>p.name), [personas.data]);
  const driverOptions = useMemo(() => (drivers.data?.drivers || []).map(d=>d.name), [drivers.data]);
  const ruleOptions = useMemo(() => (rules.data?.rules || []).map(r=>r.name), [rules.data]);
  const modelOptions = useMemo(
    () =>
      (models.data || []).map((m: any) => ({
        id: Number(m.id),
        label: `${m.display_name || m.provider_model_id} (${m.provider_name || 'unknown'})`,
      })),
    [models.data]
  );
  const toolOptions = useMemo(() => {
    const list = routes.data?.routes || [];
    return list
      .map((r) => {
        const m = r.path.match(/^\/([^/]+)\/tools\/([^/]+)\/call$/);
        if (!m) return null;
        return { name: `${m[1]}.${m[2]}`, description: r.description || '' };
      })
      .filter((v): v is { name: string; description: string } => !!v)
      .sort((a, b) => a.name.localeCompare(b.name));
  }, [routes.data]);
  const toolDescriptions = useMemo(() => new Map(toolOptions.map((t) => [t.name, t.description])), [toolOptions]);
  const [name, setName] = useState('');
  const [persona, setPersona] = useState<string | null>(null);
  const [driver, setDriver] = useState<string | null>(null);
  const [selectedModelId, setSelectedModelId] = useState<number | null>(null);
  const [instructions, setInstructions] = useState<string>('');
  const [selRules, setSelRules] = useState<string[]>([]);
  const [noTools, setNoTools] = useState(false);
  const [allowedTools, setAllowedTools] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function create() {
    setBusy(true); setError(null);
    try {
      await agentsCreate({
        name,
        persona: persona || '',
        driver: driver || '',
        rules: selRules,
        instructions: instructions || undefined,
        model_id: selectedModelId || undefined,
        allowed_tools: noTools ? [] : (allowedTools.length ? allowedTools : undefined)
      });
      nav('/agents');
    } catch (e:any) {
      setError(getErrorMessage(e));
    } finally { setBusy(false); }
  }

  return (
    <Grid container spacing={2}>
      <Grid xs={12}>
        <Paper sx={{ p:2 }}>
          <Typography variant="subtitle1" sx={{ mb: 2 }}>Create Agent</Typography>
          {personas.isFetching && <LinearProgress />}
          {rules.isFetching && <LinearProgress />}
          {routes.isFetching && <LinearProgress />}
          {models.isFetching && <LinearProgress />}
          {error && <Alert severity="error" sx={{ mb: 2 }}>{error}</Alert>}
          <Stack spacing={2}>
            <Grid container spacing={2}>
              <Grid xs={12} md={3}>
                <TextField size="small" label="Name" value={name} onChange={(e)=>setName(e.target.value)} fullWidth />
              </Grid>
              <Grid xs={12} md={3}>
                <Autocomplete
                  options={personaOptions}
                  freeSolo
                  value={persona}
                  onChange={(_, v)=>setPersona(v)}
                  renderInput={(params)=>(<TextField {...params} size="small" label="Persona" />)}
                />
              </Grid>
              <Grid xs={12} md={3}>
                <Autocomplete
                  options={driverOptions}
                  value={driver}
                  onChange={(_, v)=>setDriver(v)}
                  renderInput={(params)=>(<TextField {...params} size="small" label="Driver" />)}
                />
              </Grid>
              <Grid xs={12} md={3}>
                <Autocomplete
                  options={modelOptions}
                  getOptionLabel={(option) => option.label}
                  value={modelOptions.find((m) => m.id === selectedModelId) || null}
                  isOptionEqualToValue={(option, value) => option.id === value?.id}
                  onChange={(_, v) => setSelectedModelId(v?.id || null)}
                  renderInput={(params) => (<TextField {...params} size="small" label="LLM Model" />)}
                />
              </Grid>
            </Grid>
            <Grid container spacing={2}>
              <Grid xs={12} md={8}>
                <TextField
                  label="Instructions"
                  value={instructions}
                  onChange={(e)=>setInstructions(e.target.value)}
                  fullWidth
                  multiline
                  minRows={3}
                  maxRows={6}
                  placeholder="Describe what the agent should do, steps, guardrails, and success criteria."
                />
              </Grid>
              <Grid xs={12} md={4}>
                <Stack spacing={2}>
                  <Autocomplete
                    multiple
                    options={ruleOptions}
                    freeSolo
                    value={selRules}
                    onChange={(_, v)=>setSelRules(v)}
                    renderInput={(params)=>(<TextField {...params} label="Rules" />)}
                  />
                  <FormControlLabel
                    control={<Switch checked={noTools} onChange={(e) => setNoTools(e.target.checked)} />}
                    label="No Tools"
                  />
                  {!noTools && (
                    <Autocomplete
                      multiple
                      options={toolOptions.map((t) => t.name)}
                      value={allowedTools}
                      onChange={(_, v)=>setAllowedTools(v)}
                      renderOption={(props, option) => (
                        <li {...props}>
                          <Box sx={{ display: 'flex', flexDirection: 'column' }}>
                            <Typography variant="body2">{option}</Typography>
                            {toolDescriptions.get(option) && (
                              <Typography variant="caption" color="text.secondary">
                                {toolDescriptions.get(option)}
                              </Typography>
                            )}
                          </Box>
                        </li>
                      )}
                      renderInput={(params)=>(<TextField {...params} label="Allowed Tools (empty = all tools)" />)}
                    />
                  )}
                </Stack>
              </Grid>
            </Grid>
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
