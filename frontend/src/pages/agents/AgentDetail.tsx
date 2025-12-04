import React, { useEffect, useMemo, useState } from 'react';
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
import Chip from '@mui/material/Chip';
import Divider from '@mui/material/Divider';
import { agentsDelete, agentsUpdate, agentRunRead, getErrorMessage, useAgent, useAgentRuns, usePersonas, useRules } from '../../api';
import { useNavigate, useParams, useSearchParams } from 'react-router-dom';

function TranscriptView({ transcript }: { transcript: any }) {
  if (!transcript) return <Typography variant="body2" color="text.secondary">No transcript available.</Typography>;
  const steps = transcript.steps || [];
  return (
    <Stack spacing={1}>
      {steps.map((s: any, idx: number) => (
        <Paper key={idx} variant="outlined" sx={{ p: 1 }}>
          <Stack direction="row" spacing={1} alignItems="center">
            <Chip size="small" label={`#${s.index || idx+1}`} />
            <Chip size="small" label={s.action?.action || s.action || 'step'} />
            {s.action?.tool_name && <Chip size="small" color="primary" label={s.action.tool_name} />}
          </Stack>
          {s.action?.final && <Typography variant="body2" sx={{ mt: 1 }}>{s.action.final}</Typography>}
          {s.output && <pre style={{ margin: 0, marginTop: 8, whiteSpace: 'pre-wrap' }}>{JSON.stringify(s.output, null, 2)}</pre>}
          {s.note && <Typography variant="caption" color="text.secondary">{s.note}</Typography>}
        </Paper>
      ))}
    </Stack>
  );
}

export default function AgentDetail() {
  const params = useParams();
  const [search] = useSearchParams();
  const name = params.name || null;
  const nav = useNavigate();
  const agent = useAgent(name);
  const runs = useAgentRuns(name);
  const personas = usePersonas('');
  const rules = useRules('');
  const personaOptions = useMemo(() => (personas.data?.personas || []).map(p=>p.name), [personas.data]);
  const ruleOptions = useMemo(() => (rules.data?.rules || []).map(r=>r.name), [rules.data]);
  const [persona, setPersona] = useState<string | null>(null);
  const [driver, setDriver] = useState('');
  const [selRules, setSelRules] = useState<string[]>([]);
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [transcript, setTranscript] = useState<any>(null);

  useEffect(() => {
    const a = agent.data;
    if (!a) return;
    setDriver(a.driver || '');
  }, [agent.data]);

  useEffect(() => {
    const run = search.get('run');
    if (name && run) {
      agentRunRead(name, Number(run)).then((d)=> setTranscript(d.transcript)).catch(()=>setTranscript(null));
    } else {
      setTranscript(null);
    }
  }, [name, search]);

  async function save() {
    if (!name) return;
    setSaving(true); setErr(null);
    try {
      await agentsUpdate({ name, persona: persona || undefined, driver, rules: selRules.length ? selRules : undefined });
      await agent.refetch();
      nav('/engines/agents');
    } catch (e:any) { setErr(getErrorMessage(e)); } finally { setSaving(false); }
  }

  if (!name) return <div/>;
  return (
    <Grid container spacing={2}>
      <Grid size={{ xs: 12, md: 6 }}>
        <Paper sx={{ p:2 }}>
          <Typography variant="subtitle1" sx={{ mb: 2 }}>Edit Agent: {name}</Typography>
          {(agent.isFetching || personas.isFetching || rules.isFetching) && <LinearProgress />}
          {err && <Alert severity="error" sx={{ mb: 2 }}>{err}</Alert>}
          <Stack spacing={2}>
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
              <Button variant="contained" disabled={saving} onClick={save}>Save</Button>
              <Button sx={{ ml: 1 }} onClick={() => nav('/engines/agents')}>Cancel</Button>
            </Box>
          </Stack>
        </Paper>
      </Grid>

      <Grid size={{ xs: 12, md: 6 }}>
        <Paper sx={{ p:2, display: 'flex', flexDirection: 'column', gap: 1 }}>
          <Typography variant="subtitle1">Run Transcript</Typography>
          <Divider />
          {!transcript && <Alert severity="info">Select a run from Agents list and click View.</Alert>}
          {transcript && <TranscriptView transcript={transcript} />}
        </Paper>
      </Grid>
    </Grid>
  );
}

