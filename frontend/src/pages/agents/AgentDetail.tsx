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
import Divider from '@mui/material/Divider';
import Tooltip from '@mui/material/Tooltip';
import Stack from '@mui/material/Stack';
import { agentsUpdate, getErrorMessage, useAgent, usePersonas, useRules } from '../../api';
import { useNavigate, useParams } from 'react-router-dom';

export default function AgentDetail() {
  const params = useParams();
  const name = params.name || null;
  const nav = useNavigate();
  const agent = useAgent(name);
  const personas = usePersonas('');
  const rules = useRules('');
  const personaOptions = useMemo(() => (personas.data?.personas || []).map(p=>p.name), [personas.data]);
  const ruleOptions = useMemo(() => (rules.data?.rules || []).map(r=>r.name), [rules.data]);
  const [persona, setPersona] = useState<string | null>(null);
  const [driver, setDriver] = useState('');
  const [selRules, setSelRules] = useState<string[]>([]);
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    const a = agent.data as any;
    if (!a) return;
    setDriver(a.driver || '');
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

  async function save() {
    if (!name) return;
    setSaving(true); setErr(null);
    try {
      await agentsUpdate({ name, persona: persona || undefined, driver, rules: selRules.length ? selRules : undefined });
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
          {(agent.isFetching || personas.isFetching || rules.isFetching) && <LinearProgress />}
          {err && <Alert severity="error" sx={{ mb: 2 }}>{err}</Alert>}
          <Stack spacing={2}>
            <Autocomplete
              options={personaOptions}
              freeSolo
              value={persona}
              onChange={(_, v)=>setPersona(v)}
              renderInput={(params)=>(<TextField {...params} label="Persona" />)}
            />
            <TextField label="Driver (mission + endpoint)" value={driver} onChange={(e)=>setDriver(e.target.value)} fullWidth multiline minRows={4} />
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
                  <Button size="small" variant="outlined" onClick={() => {
                    const tmpl = `Objective: Given the Goal (run input), search local indexed repos and memory bank, then produce a concise, accurate summary.\n\nRequired steps:\n1) action=tool, tool_name=context.fts_search, args={"q": Goal, "repo": null, "limit": 10}\n2) action=tool, tool_name=context.memory_search, args={"q": Goal, "repo": null, "limit": 10}\n3) action=reason (optional): synthesize findings if needed\n4) action=finish: deliver a concise summary\n\nConstraints:\n- Do not output action="finish" before at least one tool call.\n- Use fully qualified tool names exactly as listed.\n- ONE JSON object per step with keys: action, tool_name, args, final, reasoning.\n- Map Goal verbatim to args.q. Keep reasoning short.`;
                    setDriver((prev) => (prev && prev.trim().length > 0) ? prev + "\n\n" + tmpl : tmpl);
                  }}>Insert Search Driver</Button>
                </span>
              </Tooltip>
              
            </Stack>
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
