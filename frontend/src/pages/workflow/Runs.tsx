import React, { useMemo, useState, useEffect } from 'react';
import { useWorkflowRuns, useWorkflowRun, workflowRunDelete, workflowRunStart } from '../../api';
import Grid from '@mui/material/Unstable_Grid2';
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
import Tooltip from '@mui/material/Tooltip';
import IconButton from '@mui/material/IconButton';
import ContentCopyIcon from '@mui/icons-material/ContentCopy';
import DeleteOutlineIcon from '@mui/icons-material/DeleteOutline';
import PlayArrowIcon from '@mui/icons-material/PlayArrow';
import DataObjectIcon from '@mui/icons-material/DataObject';
import Viewer from '../../components/Viewer';
import Tabs from '@mui/material/Tabs';
import Tab from '@mui/material/Tab';
import Snackbar from '@mui/material/Snackbar';
import TextField from '@mui/material/TextField';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import DialogActions from '@mui/material/DialogActions';
import Button from '@mui/material/Button';
import Autocomplete from '@mui/material/Autocomplete';
import { useWorkflowList } from '../../api';
import Divider from '@mui/material/Divider';
import { useLocation, useSearchParams } from 'react-router-dom';

const PANEL_HEIGHT = 'calc(100vh - 260px)';

export default function WorkflowRuns() {
  const { data, isLoading, isError, error, refetch } = useWorkflowRuns();
  const rows = (data?.runs || []).slice().reverse();
  const [sel, setSel] = useState<{ workflow: string; run_id: string } | null>(null);
  const run = useWorkflowRun(sel?.workflow || null, sel?.run_id || null);

  const title = useMemo(() => sel ? `${sel.workflow} / ${sel.run_id}` : 'Select a run', [sel]);
  const [viewTab, setViewTab] = useState(0); // 0 = JSON
  const [copiedOpen, setCopiedOpen] = useState(false);
  const [startOpen, setStartOpen] = useState(false);
  const [startWf, setStartWf] = useState('hello');
  const [startParams, setStartParams] = useState('{}');
  const [search, setSearch] = useSearchParams();
  useEffect(() => {
    if (search.get('start') === '1') {
      const wf = search.get('wf');
      const p = search.get('params');
      if (wf) setStartWf(wf);
      if (p) setStartParams(p);
      setStartOpen(true);
    }
  }, [search]);

  function copyJson(txt: string) {
    try { navigator.clipboard.writeText(txt); setCopiedOpen(true); } catch { setCopiedOpen(true); }
  }

  async function del() {
    if (!sel) return;
    await workflowRunDelete(sel.workflow, sel.run_id);
    setSel(null);
    refetch();
  }

  async function start() {
    try {
      const params = JSON.parse(startParams || '{}');
      await workflowRunStart(startWf, params);
      setStartOpen(false);
      refetch();
    } catch (e) {
      alert('Invalid JSON for params');
    }
  }

  const wfList = useWorkflowList('');
  const options = (wfList.data?.workflows || []).map((w) => w.id);

  return (
    <Grid container spacing={2}>
      <Grid xs={12} md={4}>
        <Paper sx={{ p: 1, height: PANEL_HEIGHT, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
          <Stack direction="row" justifyContent="space-between" alignItems="center" sx={{ px: 1, py: 1 }}>
            <Typography variant="subtitle1">Workflow Runs</Typography>
            <Tooltip title="Start workflow">
              <IconButton size="small" onClick={() => setStartOpen(true)}><PlayArrowIcon fontSize="small" /></IconButton>
            </Tooltip>
          </Stack>
          {isLoading && <LinearProgress />}
          {isError && <Alert severity="error">{String(error)}</Alert>}
          <Box sx={{ flex: 1, overflowY: 'auto' }}>
            <List dense>
              {rows.map(r => (
                <ListItem key={`${r.workflow}__${r.run_id}`} disablePadding>
                  <ListItemButton selected={sel?.run_id === r.run_id && sel?.workflow === r.workflow} onClick={() => setSel({ workflow: r.workflow, run_id: r.run_id })}>
                    <ListItemText primary={`${r.workflow} / ${r.run_id}`} secondary={`steps=${r.steps} status=${r.status} updated=${r.updated_at}`} />
                  </ListItemButton>
                </ListItem>
              ))}
            </List>
          </Box>
        </Paper>
      </Grid>
      <Grid xs={12} md={8}>
        <Paper sx={{ p: 2, height: PANEL_HEIGHT, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
          <Stack direction="row" justifyContent="space-between" alignItems="center">
            <Typography variant="subtitle1">Run state — {title}</Typography>
            <Stack direction="row" spacing={1} alignItems="center">
              <Tooltip title={run.data ? 'Copy JSON' : 'Select a run to copy'}>
                <span>
                  <IconButton size="small" onClick={() => run.data && copyJson(typeof (run.data as any).state === 'string' ? (run.data as any).state : JSON.stringify((run.data as any).state, null, 2))} disabled={!run.data}>
                    <ContentCopyIcon fontSize="small" />
                  </IconButton>
                </span>
              </Tooltip>
              <Tabs value={viewTab} onChange={(_, v)=>setViewTab(v)}>
                <Tab icon={<DataObjectIcon fontSize="small" />} aria-label="JSON" />
              </Tabs>
              <Tooltip title="Delete run">
                <span>
                  <IconButton size="small" color="error" disabled={!sel} onClick={del}>
                    <DeleteOutlineIcon fontSize="small" />
                  </IconButton>
                </span>
              </Tooltip>
            </Stack>
          </Stack>
          {run.isFetching && <LinearProgress />}
          {run.isError && <Alert severity="error">{String(run.error)}</Alert>}
          <Box sx={{ flex: 1, overflowY: 'auto', mt: 1 }}>
            {viewTab === 0 && (
              <Box>
                {/* Specialized MR Review rendering */}
                {(() => {
                  const state = (run.data as any)?.state;
                  const steps = Array.isArray(state?.steps) ? state.steps : [];
                  const last = steps.length ? steps[steps.length - 1] : null;
                  const out = last?.output || null;
                  const agentName = (out && (out.agent || out['agent'])) || null;
                  if (agentName === 'mr_review') {
                    const finalText = out.final || out['final'] || '';
                    // Extract structured sections from output if present
                    const toList = (v: any): string[] => {
                      if (!v) return [];
                      if (Array.isArray(v)) {
                        return v.map((x) => {
                          if (typeof x === 'string') return x;
                          if (x && typeof x === 'object') return x.text || x.msg || x.title || JSON.stringify(x);
                          return String(x);
                        });
                      }
                      if (typeof v === 'string') return [v];
                      if (typeof v === 'object') return Object.values(v).map((x:any)=> (typeof x === 'string' ? x : JSON.stringify(x)));
                      return [String(v)];
                    };
                    const findings = toList(out.findings || out.issues || out.observations);
                    const risks = toList(out.risks || out.red_flags || out.concerns);
                    const checklist = toList(out.checklist || out.todo || out.actions || out.action_items);
                    const tests = toList(out.tests || out.test_impact || (out.testing && out.testing.affected));
                    return (
                      <Box sx={{ mb: 2, p: 1, border: '1px solid #eee', borderRadius: 1 }}>
                        <Typography variant="subtitle2" sx={{ mb: 1 }}>MR Review Summary</Typography>
                        <Viewer content={finalText || '*No final text provided.*'} contentType="markdown" height={'auto'} />
                        {(findings.length || risks.length || checklist.length || tests.length) > 0 && (
                          <Box sx={{ mt: 1 }}>
                            {findings.length > 0 && (
                              <Box sx={{ mb: 1 }}>
                                <Typography variant="subtitle2">Findings</Typography>
                                <List dense>
                                  {findings.map((t, i) => (
                                    <ListItem key={`f-${i}`} sx={{ py: 0 }}>
                                      <ListItemText primary={t} />
                                    </ListItem>
                                  ))}
                                </List>
                              </Box>
                            )}
                            {risks.length > 0 && (
                              <Box sx={{ mb: 1 }}>
                                <Typography variant="subtitle2">Risks</Typography>
                                <List dense>
                                  {risks.map((t, i) => (
                                    <ListItem key={`r-${i}`} sx={{ py: 0 }}>
                                      <ListItemText primary={t} />
                                    </ListItem>
                                  ))}
                                </List>
                              </Box>
                            )}
                            {tests.length > 0 && (
                              <Box sx={{ mb: 1 }}>
                                <Typography variant="subtitle2">Tests Affected</Typography>
                                <List dense>
                                  {tests.map((t, i) => (
                                    <ListItem key={`t-${i}`} sx={{ py: 0 }}>
                                      <ListItemText primary={t} />
                                    </ListItem>
                                  ))}
                                </List>
                              </Box>
                            )}
                            {checklist.length > 0 && (
                              <Box sx={{ mb: 1 }}>
                                <Typography variant="subtitle2">Checklist</Typography>
                                <List dense>
                                  {checklist.map((t, i) => (
                                    <ListItem key={`c-${i}`} sx={{ py: 0 }}>
                                      <ListItemText primary={t} />
                                    </ListItem>
                                  ))}
                                </List>
                              </Box>
                            )}
                          </Box>
                        )}
                      </Box>
                    );
                  }
                  return null;
                })()}

                <Viewer
                  content={run.data ? (typeof (run.data as any).state === 'string' ? (run.data as any).state : JSON.stringify((run.data as any).state, null, 2)) : 'Pick a run to view state'}
                  contentType="application/json"
                  height={'100%'}
                />
              </Box>
            )}
          </Box>
        </Paper>
      </Grid>

      <Dialog open={startOpen} onClose={()=>setStartOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle>Start Workflow</DialogTitle>
        <DialogContent>
          <Stack spacing={1} sx={{ mt: 1 }}>
            <Autocomplete
              options={options}
              freeSolo
              value={startWf}
              onChange={(_, v) => setStartWf(v || '')}
              renderInput={(params) => (
                <TextField {...params} label="Workflow name" size="small" value={startWf} onChange={(e)=>setStartWf(e.target.value)} />
              )}
            />
            <TextField label="Params (JSON)" value={startParams} onChange={e=>setStartParams(e.target.value)} size="small" multiline minRows={4} />
          </Stack>
        </DialogContent>
        <DialogActions>
          <Button onClick={()=>setStartOpen(false)}>Cancel</Button>
          <Button variant="contained" onClick={start}>Run</Button>
        </DialogActions>
      </Dialog>

      <Snackbar open={copiedOpen} autoHideDuration={2000} onClose={() => setCopiedOpen(false)} message="Copied JSON to clipboard" anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }} />
    </Grid>
  );
}
