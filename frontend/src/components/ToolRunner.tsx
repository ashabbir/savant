import React, { useEffect, useMemo, useState } from 'react';
import Paper from '@mui/material/Paper';
import Typography from '@mui/material/Typography';
import Stack from '@mui/material/Stack';
import Button from '@mui/material/Button';
import TextField from '@mui/material/TextField';
import Box from '@mui/material/Box';
import Snackbar from '@mui/material/Snackbar';
import IconButton from '@mui/material/IconButton';
import Menu from '@mui/material/Menu';
import MenuItem from '@mui/material/MenuItem';
import Divider from '@mui/material/Divider';
import LinearProgress from '@mui/material/LinearProgress';
import BookmarkAddIcon from '@mui/icons-material/BookmarkAdd';
import HistoryIcon from '@mui/icons-material/History';
import ContentCopyIcon from '@mui/icons-material/ContentCopy';
import DataObjectIcon from '@mui/icons-material/DataObject';
import List from '@mui/material/List';
import ListItem from '@mui/material/ListItem';
import ListItemText from '@mui/material/ListItemText';
import Viewer from './Viewer';
import { callEngineTool, loadConfig, getUserId } from '../api';
import { buildDefaultParams, buildCurlCommand, buildHttpieCommand, isSimpleSchema } from '../utils/tools';

export type ToolSpec = { name: string; description?: string; inputSchema?: any; schema?: any };

type Preset = { name: string; params: any };
type HistoryItem = { ts: number; params: any };

export default function ToolRunner({ engine, tool }: { engine: string; tool: ToolSpec | null }) {
  const schema = useMemo(() => (tool?.inputSchema || tool?.schema), [tool]);
  const toolName = tool?.name || '';
  const [useForm, setUseForm] = useState(false);
  const [formValues, setFormValues] = useState<any>({});
  const [inputJson, setInputJson] = useState<string>('{}');
  const [output, setOutput] = useState<string>('');
  const [loading, setLoading] = useState(false);
  const [toast, setToast] = useState<string | null>(null);
  const [historyAnchor, setHistoryAnchor] = useState<null | HTMLElement>(null);
  const [presetsAnchor, setPresetsAnchor] = useState<null | HTMLElement>(null);
  const [curlAnchor, setCurlAnchor] = useState<null | HTMLElement>(null);

  const simple = useMemo(() => isSimpleSchema(schema), [schema]);
  const outContentType = useMemo(() => {
    if (!output) return undefined as string | undefined;
    try { JSON.parse(output); return 'application/json'; } catch { return 'text/plain'; }
  }, [output]);

  const lsPrefix = `tool.${engine}.${toolName}`;
  function historyKey() { return `${lsPrefix}.history`; }
  function presetsKey() { return `${lsPrefix}.presets`; }
  function prefillKey() { return `${lsPrefix}.prefill`; }

  useEffect(() => {
    // Initialize on tool change
    setOutput('');
    if (!toolName) return;
    const pfRaw = localStorage.getItem(prefillKey());
    if (pfRaw) {
      try {
        const pf = JSON.parse(pfRaw);
        setUseForm(simple);
        if (simple) setFormValues(pf);
        setInputJson(JSON.stringify(pf, null, 2));
      } catch { /* ignore */ }
      localStorage.removeItem(prefillKey());
      return;
    }
    if (simple) {
      const def = buildDefaultParams(schema);
      setUseForm(true);
      setFormValues(def);
      setInputJson(JSON.stringify(def, null, 2));
    } else {
      setUseForm(false);
      setInputJson('{}');
    }
  }, [toolName, simple]);

  function readHistory(): HistoryItem[] {
    try { return JSON.parse(localStorage.getItem(historyKey()) || '[]'); } catch { return []; }
  }
  function writeHistory(items: HistoryItem[]) {
    localStorage.setItem(historyKey(), JSON.stringify(items.slice(-10)));
  }
  function readPresets(): Preset[] {
    try { return JSON.parse(localStorage.getItem(presetsKey()) || '[]'); } catch { return []; }
  }
  function writePresets(items: Preset[]) { localStorage.setItem(presetsKey(), JSON.stringify(items.slice(-20))); }

  async function run() {
    if (!engine || !toolName) return;
    try {
      setLoading(true);
      const params = useForm ? formValues : (inputJson ? JSON.parse(inputJson) : {});
      const res = await callEngineTool(engine, toolName, params);
      setOutput(JSON.stringify(res, null, 2));
      const hist = readHistory();
      hist.push({ ts: Date.now(), params });
      writeHistory(hist);
    } catch (e: any) {
      setOutput(String(e?.message || e));
    } finally {
      setLoading(false);
    }
  }

  function copy(cmd: string) {
    navigator.clipboard.writeText(cmd).then(() => setToast('Copied')).catch(() => setToast('Copy failed'));
  }

  const baseUrl = loadConfig().baseUrl;
  const userId = getUserId();
  const curl = toolName ? buildCurlCommand(baseUrl, engine, toolName, (() => { try {return useForm ? formValues : JSON.parse(inputJson);} catch {return {};}})(), userId) : '';
  const httpie = toolName ? buildHttpieCommand(baseUrl, engine, toolName, (() => { try {return useForm ? formValues : JSON.parse(inputJson);} catch {return {};}})(), userId) : '';

  return (
    <Paper sx={{ p: 2, height: 'calc(100vh - 260px)', display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
      <Typography variant="subtitle1" sx={{ fontSize: 12 }}>{toolName || 'Select a tool'}</Typography>
      {schema && (
        <Box sx={{ mt: 1 }}>
          <Viewer content={JSON.stringify(schema, null, 2)} contentType="application/json" height={180} />
        </Box>
      )}
      <Box sx={{ flex: 1, overflowY: 'auto', mt: 1, pr: 1 }}>
        <Stack spacing={1}>
          <Stack direction="row" spacing={1} sx={{ mb: 1 }}>
            <Button size="small" variant={useForm ? 'contained' : 'outlined'} onClick={() => setUseForm(true)} disabled={!simple}>Form</Button>
            <Button size="small" variant={!useForm ? 'contained' : 'outlined'} onClick={() => setUseForm(false)} startIcon={<DataObjectIcon fontSize="small" />}>JSON</Button>

            <Button size="small" variant="outlined" startIcon={<BookmarkAddIcon fontSize="small" />} onClick={(e)=>setPresetsAnchor(e.currentTarget)}>Presets</Button>
            <Menu anchorEl={presetsAnchor} open={!!presetsAnchor} onClose={()=>setPresetsAnchor(null)}>
              <MenuItem onClick={() => {
                const name = prompt('Preset name?');
                if (!name) return;
                try {
                  const params = useForm ? formValues : JSON.parse(inputJson || '{}');
                  const list = readPresets();
                  list.push({ name, params });
                  writePresets(list);
                  setToast('Preset saved');
                } catch { setToast('Invalid JSON'); }
                setPresetsAnchor(null);
              }}>Save current as preset…</MenuItem>
              <Divider />
              {readPresets().length === 0 && <MenuItem disabled>No presets</MenuItem>}
              {readPresets().map((p, i) => (
                <MenuItem key={`${p.name}-${i}`} onClick={()=>{
                  setFormValues(p.params);
                  setInputJson(JSON.stringify(p.params, null, 2));
                  setPresetsAnchor(null);
                }}>{p.name}</MenuItem>
              ))}
            </Menu>

            <Button size="small" variant="outlined" startIcon={<HistoryIcon fontSize="small" />} onClick={(e)=>setHistoryAnchor(e.currentTarget)}>History</Button>
            <Menu anchorEl={historyAnchor} open={!!historyAnchor} onClose={()=>setHistoryAnchor(null)}>
              {readHistory().length === 0 && <MenuItem disabled>No history</MenuItem>}
              {readHistory().slice().reverse().map((h, i) => (
                <MenuItem key={i} onClick={()=>{
                  setFormValues(h.params);
                  setInputJson(JSON.stringify(h.params, null, 2));
                  setHistoryAnchor(null);
                }}>{new Date(h.ts).toLocaleString()}</MenuItem>
              ))}
            </Menu>

            <Button size="small" variant="outlined" startIcon={<ContentCopyIcon fontSize="small" />} onClick={(e)=>setCurlAnchor(e.currentTarget)}>Copy cURL/CLI</Button>
            <Menu anchorEl={curlAnchor} open={!!curlAnchor} onClose={()=>setCurlAnchor(null)}>
              <MenuItem onClick={()=>{ copy(curl); setCurlAnchor(null); }}>Copy cURL</MenuItem>
              <MenuItem onClick={()=>{ copy(httpie); setCurlAnchor(null); }}>Copy HTTPie</MenuItem>
            </Menu>
          </Stack>

          {!useForm ? (
            <TextField label="Params (JSON)" value={inputJson} onChange={(e)=>setInputJson(e.target.value)} multiline minRows={4} />
          ) : (
            <Stack spacing={1}>
              {Object.entries(((schema as any)?.properties)||{}).map(([k, v]: any) => {
                const t = v?.type;
                if (t === 'string') return <TextField key={k} label={k} value={formValues[k]||''} onChange={(e)=>setFormValues({...formValues,[k]:e.target.value})} />;
                if (t === 'integer' || t === 'number') return <TextField key={k} type="number" label={k} value={formValues[k]??0} onChange={(e)=>setFormValues({...formValues,[k]:Number(e.target.value)})} />;
                if (t === 'boolean') return (
                  <Stack key={k} direction="row" spacing={1} alignItems="center">
                    <Typography>{k}</Typography>
                    <Button size="small" variant={formValues[k]? 'contained':'outlined'} onClick={()=>setFormValues({...formValues,[k]:!formValues[k]})}>{String(formValues[k]||false)}</Button>
                  </Stack>
                );
                if (t === 'array' && v?.items?.type === 'string') return <TextField key={k} label={`${k} (comma-separated)`} value={(formValues[k]||[]).join(',')} onChange={(e)=>setFormValues({...formValues,[k]:e.target.value.split(',').map(s=>s.trim()).filter(Boolean)})} />;
                return null;
              })}
            </Stack>
          )}

          <Stack direction="row" spacing={1} sx={{ mt: 2 }}>
            <Button variant="contained" onClick={run} disabled={!toolName || loading} sx={{ minWidth: 100 }}>
              {loading ? 'Running…' : 'Run'}
            </Button>
            <Button variant="outlined" onClick={() => setOutput('')}>Clear Output</Button>
          </Stack>

          {loading && <LinearProgress />}
          {output && <Viewer content={output} contentType={outContentType} height={320} />}
        </Stack>
      </Box>
      <Snackbar open={!!toast} autoHideDuration={2000} onClose={() => setToast(null)} message={toast || ''} />
    </Paper>
  );
}

