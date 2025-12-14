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
import { agentsUpdate, getErrorMessage, useAgent, useDrivers, usePersonas, useRules, callEngineTool } from '../../api';
import { useNavigate, useParams } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';

export default function AgentDetail() {
  const params = useParams();
  const name = params.name || null;
  const nav = useNavigate();
  const agent = useAgent(name);
  const personas = usePersonas('');
  const rules = useRules('');
  const personaOptions = useMemo(() => (personas.data?.personas || []).map(p=>p.name), [personas.data]);
  const ruleOptions = useMemo(() => (rules.data?.rules || []).map(r=>r.name), [rules.data]);
  const drivers = useDrivers('');
  const driverOptions = useMemo(() => (drivers.data?.drivers || []).map(d => d.name), [drivers.data]);
  const models = useQuery({
    queryKey: ['llm', 'models'],
    queryFn: async () => {
      const res = await callEngineTool('llm', 'llm_models_list', {});
      return res.models || [];
    },
  });
  const modelOptions = useMemo(() => (models.data || []).map(m => ({ id: m.id, label: `${m.display_name} (${m.provider_name})` })), [models.data]);
  const [persona, setPersona] = useState<string | null>(null);
  const [driver, setDriver] = useState('');
  const [instructions, setInstructions] = useState('');
  const [selRules, setSelRules] = useState<string[]>([]);
  const [selectedModelId, setSelectedModelId] = useState<number | null>(null);
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    const a = agent.data as any;
    if (!a) return;
    setDriver(a.driver || '');
    setInstructions((a.instructions as string) || '');
    if (typeof a.persona_name === 'string' && a.persona_name.length > 0) setPersona(a.persona_name);
    if (Array.isArray(a.rules_names) && a.rules_names.length > 0) setSelRules(a.rules_names);
  }, [agent.data]);

  // Ensure values are set after options load as well
  useEffect(() => {
    const a = agent.data as any;
    if (!a) return;
    if (a.persona_name && personaOptions.includes(a.persona_name)) setPersona((prev)=> prev || a.persona_name);
    if (Array.isArray(a.rules_names) && a.rules_names.length > 0) {
      const ready = a.rules_names.every((n: string) => ruleOptions.includes(n));
      if (ready && selRules.length === 0) setSelRules(a.rules_names);
    }
  }, [personaOptions, ruleOptions]);

  // Load existing model assignment
  useEffect(() => {
    const a = agent.data as any;
    if (!a || !a.model_id) return;
    setSelectedModelId(a.model_id);
  }, [agent.data, models.data]);

  async function save() {
    if (!name) return;
    setSaving(true); setErr(null);
    try {
      await agentsUpdate({ name, persona: persona || undefined, driver, rules: selRules.length ? selRules : undefined, instructions: instructions || undefined, model_id: selectedModelId || undefined });
      await agent.refetch();
      nav('/agents');
    } catch (e:any) { setErr(getErrorMessage(e)); } finally { setSaving(false); }
  }

  if (!name) return <div/>;
  return (
    <Grid container spacing={2}>
      <Grid xs={12}>
        <Paper sx={{ p:2 }}>
          <Typography variant="subtitle1" sx={{ mb: 2 }}>Edit Agent: {name}</Typography>
          {(agent.isFetching || personas.isFetching || rules.isFetching || models.isFetching) && <LinearProgress />}
          {err && <Alert severity="error" sx={{ mb: 2 }}>{err}</Alert>}
          <Stack spacing={2}>
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
            <TextField
              label="Instructions"
              value={instructions}
              onChange={(e)=>setInstructions(e.target.value)}
              fullWidth
              multiline
              minRows={4}
              placeholder="Describe what the agent should do, steps, guardrails, and success criteria."
            />
            <Autocomplete
              multiple
              options={ruleOptions}
              freeSolo
              value={selRules}
              onChange={(_, v)=>setSelRules(v)}
              renderInput={(params)=>(<TextField {...params} label="Rules" />)}
            />
            <Autocomplete
              options={modelOptions}
              getOptionLabel={(option) => option.label}
              value={modelOptions.find(m => m.id === selectedModelId) || null}
              onChange={(_, v) => setSelectedModelId(v?.id || null)}
              renderInput={(params) => (<TextField {...params} label="LLM Model" />)}
            />

            <Box>
              <Button variant="contained" disabled={saving} onClick={save}>Save</Button>
              <Button sx={{ ml: 1 }} onClick={() => nav('/agents')}>Cancel</Button>
            </Box>
          </Stack>
        </Paper>
      </Grid>

      {/* No run info in edit page per requirements */}
    </Grid>
  );
}
