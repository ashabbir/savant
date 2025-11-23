import React, { useEffect, useMemo, useState } from 'react';
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
import Viewer from '../../components/Viewer';

function isSimpleSchema(schema: any): boolean {
  try {
    if (!schema || typeof schema !== 'object') return false;
    const props = schema.properties || {};
    const keys = Object.keys(props);
    if (keys.length === 0) return false;
    return keys.every((k) => {
      const t = props[k]?.type;
      if (t === 'string' || t === 'integer' || t === 'number' || t === 'boolean') return true;
      if (t === 'array' && props[k]?.items?.type === 'string') return true;
      return false;
    });
  } catch { return false; }
}

function buildDefaultParams(schema: any): any {
  const props = (schema && schema.properties) || {};
  const out: any = {};
  Object.keys(props).forEach((k) => {
    const t = props[k]?.type;
    if (t === 'string') out[k] = '';
    else if (t === 'integer' || t === 'number') out[k] = 0;
    else if (t === 'boolean') out[k] = false;
    else if (t === 'array' && props[k]?.items?.type === 'string') out[k] = [];
  });
  return out;
}

export default function ContextTools() {
  const { data, isLoading, isError, error } = useContextTools();
  const tools = data?.tools || [];
  const [sel, setSel] = useState<ContextToolSpec | null>(null);
  const [input, setInput] = useState<string>('{}');
  const [out, setOut] = useState<string>('');
  const outContentType = useMemo(() => {
    if (!out) return undefined as string | undefined;
    try { JSON.parse(out); return 'application/json'; } catch { /* not JSON */ }
    return 'text/plain';
  }, [out]);
  const schema = useMemo(() => sel?.inputSchema || sel?.schema, [sel]);
  const name = sel?.name || '';
  const [useForm, setUseForm] = useState<boolean>(false);
  const [formValues, setFormValues] = useState<any>({});
  const [filter, setFilter] = useState<string>('');

  // Load last selected tool
  useEffect(() => {
    if (!sel && tools.length) {
      const last = localStorage.getItem('ctx.tools.selected');
      const found = tools.find((t) => t.name === last) || tools[0];
      if (found) { setSel(found); }
    }
  }, [tools]);

  useEffect(() => {
    if (name) localStorage.setItem('ctx.tools.selected', name);
  }, [name]);

  useEffect(() => {
    const simple = isSimpleSchema(schema);
    setUseForm(simple);
    if (simple) {
      setFormValues(buildDefaultParams(schema));
      setInput(JSON.stringify(buildDefaultParams(schema)));
    }
  }, [schema]);

  async function run() {
    try {
      const params = useForm ? formValues : (input ? JSON.parse(input) : {});
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
          <TextField size="small" label="Filter" value={filter} onChange={(e)=>setFilter(e.target.value)} sx={{ m: 1 }} />
          {isLoading && <LinearProgress />}
          {isError && <Alert severity="error">{(error as any)?.message || 'Failed to load tools'}</Alert>}
          <List dense>
            {tools.filter(t => !filter || t.name.includes(filter) || (t.description||'').includes(filter)).map(t => (
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
            <Viewer content={JSON.stringify(schema, null, 2)} contentType="application/json" height={200} />
          )}
          <Stack spacing={1} sx={{ mt: 1 }}>
            <Stack direction="row" spacing={1} sx={{ mb: 1 }}>
              <Button
                size="small"
                variant={useForm ? 'contained' : 'outlined'}
                onClick={() => setUseForm(true)}
                disabled={!isSimpleSchema(schema)}
              >
                Form
              </Button>
              <Button
                size="small"
                variant={!useForm ? 'contained' : 'outlined'}
                onClick={() => setUseForm(false)}
              >
                JSON
              </Button>
            </Stack>
            {!useForm ? (
              <TextField label="Params (JSON)" value={input} onChange={(e)=>setInput(e.target.value)} multiline minRows={4} />
            ) : (
              <Stack spacing={1}>
                {Object.entries(((schema as any)?.properties)||{}).map(([k, v]: any) => {
                  const t = v?.type;
                  if (t === 'string') return <TextField key={k} label={k} value={formValues[k]||''} onChange={(e)=>setFormValues({...formValues,[k]:e.target.value})} />;
                  if (t === 'integer' || t === 'number') return <TextField key={k} type="number" label={k} value={formValues[k]??0} onChange={(e)=>setFormValues({...formValues,[k]:Number(e.target.value)})} />;
                  if (t === 'boolean') return <Stack key={k} direction="row" spacing={1} alignItems="center"><Typography>{k}</Typography><Button size="small" variant={formValues[k]? 'contained':'outlined'} onClick={()=>setFormValues({...formValues,[k]:!formValues[k]})}>{String(formValues[k]||false)}</Button></Stack>;
                  if (t === 'array' && v?.items?.type === 'string') return <TextField key={k} label={`${k} (comma-separated)`} value={(formValues[k]||[]).join(',')} onChange={(e)=>setFormValues({...formValues,[k]:e.target.value.split(',').map(s=>s.trim()).filter(Boolean)})} />;
                  return null;
                })}
              </Stack>
            )}
            <Stack direction="row" spacing={1} sx={{ mt: 2 }}>
              <Button
                variant="contained"
                onClick={run}
                disabled={!sel}
                sx={{ minWidth: 100 }}
              >
                Call
              </Button>
              <Button
                variant="outlined"
                onClick={() => setOut('')}
              >
                Clear
              </Button>
            </Stack>
            {out && (
              <Viewer content={out} contentType={outContentType} height={400} />
            )}
          </Stack>
        </Paper>
      </Grid>
    </Grid>
  );
}
