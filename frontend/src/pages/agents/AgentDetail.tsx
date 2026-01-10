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
import Chip from '@mui/material/Chip';
import Stack from '@mui/material/Stack';
import FormControlLabel from '@mui/material/FormControlLabel';
import Switch from '@mui/material/Switch';
import { agentsCreate, agentsUpdate, agentsRename, getErrorMessage, useAgent, useDrivers, usePersonas, useRules, callEngineTool, useRoutes } from '../../api';
import { useNavigate, useParams } from 'react-router-dom';
import { useQuery, useQueryClient } from '@tanstack/react-query';

export default function AgentDetail() {
  const params = useParams();
  const name = params.name || null;
  const isCreate = !name;
  const nav = useNavigate();
  const queryClient = useQueryClient();
  const agent = useAgent(name);
  const personas = usePersonas('');
  const rules = useRules('');
  const personaOptions = useMemo(() => (personas.data?.personas || []).map(p=>p.name), [personas.data]);
  const ruleOptions = useMemo(() => (rules.data?.rules || []).map(r=>r.name), [rules.data]);
  const drivers = useDrivers('');
  const routes = useRoutes();
  const driverOptions = useMemo(() => (drivers.data?.drivers || []).map(d => d.name), [drivers.data]);
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
  const models = useQuery({
    queryKey: ['llm', 'models'],
    queryFn: async () => {
      const res = await callEngineTool('llm', 'llm_models_list', {});
      return res.models || [];
    },
  });
  const modelOptions = useMemo(
    () =>
      (models.data || []).map((m) => ({
        id: Number(m.id),
        label: `${m.display_name || m.provider_model_id} (${m.provider_name || 'unknown'})`,
      })),
    [models.data]
  );
  const [nameValue, setNameValue] = useState('');
  const [idValue, setIdValue] = useState<number | null>(null);
  const [persona, setPersona] = useState<string | null>(null);
  const [driver, setDriver] = useState('');
  const [instructions, setInstructions] = useState('');
  const [selRules, setSelRules] = useState<string[]>([]);
  const [noTools, setNoTools] = useState(true);
  const [allowedTools, setAllowedTools] = useState<string[]>([]);
  const [selectedModelId, setSelectedModelId] = useState<number | null>(null);
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    const a = agent.data as any;
    if (!a) return;
    setNameValue(a.name || '');
    if (typeof a.id === 'number') setIdValue(a.id);
    setDriver(a.driver || '');
    setInstructions((a.instructions as string) || '');
    if (typeof a.persona_name === 'string' && a.persona_name.length > 0) setPersona(a.persona_name);
    if (Array.isArray(a.rules_names) && a.rules_names.length > 0) setSelRules(a.rules_names);
    if (Array.isArray(a.allowed_tools)) {
      setNoTools(a.allowed_tools.length === 0);
      setAllowedTools(a.allowed_tools);
    } else {
      setNoTools(true);
      setAllowedTools([]);
    }
  }, [agent.data, isCreate]);

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

  // Load existing model assignment - set when agent data or model options are ready
  useEffect(() => {
    const a = agent.data as any;
    if (!a || !a.model_id) return;
    const numericId = Number(a.model_id);
    if (!Number.isFinite(numericId)) return;
    if (modelOptions.length > 0) {
      setSelectedModelId(numericId);
    }
  }, [agent.data, modelOptions]);

  async function save() {
    setSaving(true); setErr(null);
    try {
      if (isCreate) {
        await agentsCreate({
          name: nameValue,
          persona: persona || '',
          driver: driver || '',
          rules: selRules.length ? selRules : undefined,
          instructions: instructions || undefined,
          model_id: selectedModelId || undefined,
          allowed_tools: noTools ? [] : (allowedTools.length ? allowedTools : undefined)
        });
        queryClient.invalidateQueries({ queryKey: ['agents', 'list'] });
      } else {
        // If renamed, perform rename first
        if (name && nameValue && nameValue !== name) {
          await agentsRename({ name, new_name: nameValue });
        }
        await agentsUpdate({
          name: nameValue || name || '',
          persona: persona || undefined,
          driver,
          rules: selRules.length ? selRules : undefined,
          instructions: instructions || undefined,
          model_id: selectedModelId || undefined,
          allowed_tools: noTools ? [] : (allowedTools.length ? allowedTools : undefined)
        });
        await agent.refetch();
        queryClient.invalidateQueries({ queryKey: ['agents', 'list'] });
        if (nameValue) queryClient.invalidateQueries({ queryKey: ['agents', 'get', nameValue] });
      }
      nav(`/agents/edit/${nameValue || name}`);
    } catch (e:any) { setErr(getErrorMessage(e)); } finally { setSaving(false); }
  }

  const canSave = isCreate
    ? !!nameValue && !!persona && Number.isFinite(Number(selectedModelId)) && !saving
    : !!nameValue && Number.isFinite(Number(selectedModelId)) && !saving;
  return (
    <Grid container spacing={2}>
      <Grid xs={12}>
        <Paper sx={{ p:2 }}>
          <Typography variant="subtitle1" sx={{ mb: 2 }}>{isCreate ? 'Create Agent' : `Edit Agent: ${name}`}</Typography>
          {(!isCreate && agent.isFetching) || personas.isFetching || rules.isFetching || models.isFetching || routes.isFetching ? <LinearProgress /> : null}
          {err && <Alert severity="error" sx={{ mb: 2 }}>{err}</Alert>}
          <Stack spacing={2}>
            <Grid container spacing={2}>
              <Grid xs={12} md={1}>
                <TextField
                  size="small"
                  label="ID"
                  value={idValue ?? ''}
                  fullWidth
                  disabled
                />
              </Grid>
              <Grid xs={12} md={2}>
                <TextField
                  size="small"
                  label="Name"
                  value={nameValue}
                  onChange={(e) => setNameValue(e.target.value)}
                  fullWidth
                />
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
                  maxRows={3}
                  placeholder="Describe what the agent should do, steps, guardrails, and success criteria."
                  sx={{ '& .MuiInputBase-root': { minHeight: 88 } }}
                />
              </Grid>
              <Grid xs={12} md={4}>
                <Autocomplete
                  multiple
                  options={ruleOptions}
                  freeSolo
                  value={selRules}
                  onChange={(_, v)=>setSelRules(v)}
                  renderTags={(value, getTagProps) => (
                    <Box sx={{ maxHeight: 64, overflowY: 'auto', display: 'flex', flexWrap: 'wrap', gap: 0.5 }}>
                      {value.map((option, index) => (
                        <Chip {...getTagProps({ index })} key={`${option}-${index}`} size="small" label={option} />
                      ))}
                    </Box>
                  )}
                  renderInput={(params)=>(<TextField {...params} label="Rules" size="small" />)}
                  sx={{ '& .MuiInputBase-root': { minHeight: 88, alignItems: 'flex-start' } }}
                />
              </Grid>
            </Grid>
            <Grid container spacing={2} alignItems="center">
              <Grid xs={12} md={3}>
                <FormControlLabel
                  control={<Switch checked={!noTools} onChange={(e) => setNoTools(!e.target.checked)} />}
                  label="Enable Tools"
                />
              </Grid>
              {!noTools && (
                <Grid xs={12} md={9}>
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
                </Grid>
              )}
            </Grid>
            <Box>
              <Button variant="contained" disabled={!canSave} onClick={save}>Save</Button>
              <Button sx={{ ml: 1 }} onClick={() => nav('/agents')}>Cancel</Button>
            </Box>
          </Stack>
        </Paper>
      </Grid>

      {/* No run info in edit page per requirements */}
    </Grid>
  );
}
