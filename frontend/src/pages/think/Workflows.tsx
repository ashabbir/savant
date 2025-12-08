import React, { useState, useMemo, useEffect } from 'react';
import { useThinkWorkflows, useThinkWorkflowRead } from '../../api';
import { useNavigate } from 'react-router-dom';
import Box from '@mui/material/Box';
import Grid from '@mui/material/Unstable_Grid2';
import Tabs from '@mui/material/Tabs';
import Tab from '@mui/material/Tab';
import Stack from '@mui/material/Stack';
import Paper from '@mui/material/Paper';
import List from '@mui/material/List';
import ListItem from '@mui/material/ListItem';
import ListItemButton from '@mui/material/ListItemButton';
import ListItemText from '@mui/material/ListItemText';
import Typography from '@mui/material/Typography';
import LinearProgress from '@mui/material/LinearProgress';
import Alert from '@mui/material/Alert';
import Chip from '@mui/material/Chip';
import IconButton from '@mui/material/IconButton';
import Tooltip from '@mui/material/Tooltip';
import Snackbar from '@mui/material/Snackbar';
import Button from '@mui/material/Button';
import TextField from '@mui/material/TextField';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import DialogActions from '@mui/material/DialogActions';
import CircularProgress from '@mui/material/CircularProgress';
import CloseIcon from '@mui/icons-material/Close';
import ContentCopyIcon from '@mui/icons-material/ContentCopy';
import AccountTreeIcon from '@mui/icons-material/AccountTree';
import ArticleIcon from '@mui/icons-material/Article';
import EditIcon from '@mui/icons-material/Edit';
import DeleteOutlineIcon from '@mui/icons-material/DeleteOutline';
import AddCircleIcon from '@mui/icons-material/AddCircle';
import WorkflowDiagram from '../../components/WorkflowDiagram';
import { workflowToMermaid } from '../../utils/workflowToMermaid';
import { getErrorMessage, thinkPlan } from '../../api';
import Viewer from '../../components/Viewer';
import YAML from 'js-yaml';
import { thinkWorkflowDelete } from '../../thinkApi';
import { getMermaidInstance, isMermaidDynamicImportError } from '../../utils/mermaidLoader';

export default function ThinkWorkflows() {
  const navigate = useNavigate();
  const { data, isLoading, isError, error, refetch } = useThinkWorkflows();
  const workflows = useMemo(() => (data?.workflows || []).filter(w => w.id !== '_template'), [data?.workflows]);
  const [sel, setSel] = useState<string | null>(null);
  const wfRead = useThinkWorkflowRead(sel);
  const [subTab, setSubTab] = useState(0);
  const [diagramOpen, setDiagramOpen] = useState(false);
  const [copied, setCopied] = useState(false);
  const [deleteOpen, setDeleteOpen] = useState(false);
  const [deleteBusy, setDeleteBusy] = useState(false);
  const [deleteErr, setDeleteErr] = useState<string | null>(null);
  const [filter, setFilter] = useState('');
  // Start dialog state
  const [startOpen, setStartOpen] = useState(false);
  const [startBusy, setStartBusy] = useState(false);
  const [startErr, setStartErr] = useState<string | null>(null);
  const [startUseForm, setStartUseForm] = useState(false);
  const [startFormValues, setStartFormValues] = useState<any>({});
  const [startJson, setStartJson] = useState<string>('{}');

  function deriveParamSchemaFromYaml(yaml: string | undefined): any | null {
    if (!yaml) return null;
    try {
      const parsed = YAML.load(yaml) as any;
      // Look for params_schema or params.properties
      const schema = parsed?.params_schema || (parsed?.params && parsed.params.properties ? { properties: parsed.params.properties } : null);
      if (schema && typeof schema === 'object') return schema;
    } catch { /* ignore */ }
    return null;
  }

  const startSchema = useMemo(() => deriveParamSchemaFromYaml(wfRead.data?.workflow_yaml), [wfRead.data?.workflow_yaml]);

  const [mermaidError, setMermaidError] = useState<string | null>(null);
  const [preRenderedSvg, setPreRenderedSvg] = useState<string | null>(null);
  const [isRendering, setIsRendering] = useState(false);

  const mermaidCode = useMemo(() => {
    setMermaidError(null);
    setPreRenderedSvg(null);
    if (!wfRead.data?.workflow_yaml) {
      return '';
    }
    try {
      return workflowToMermaid(wfRead.data.workflow_yaml);
    } catch (e: any) {
      setMermaidError(`Failed to parse workflow: ${e?.message || e}`);
      return '';
    }
  }, [wfRead.data?.workflow_yaml]);

  // Pre-render diagram in background as soon as mermaid code is available
  useEffect(() => {
    if (!mermaidCode) return;

    let cancelled = false;
    setIsRendering(true);

    const renderInBackground = async (useCdn = false) => {
      try {
        const mermaid = await getMermaidInstance(useCdn);
        const id = `pre-render-${Date.now()}`;
        const { svg } = await mermaid.render(id, mermaidCode);
        if (!cancelled) {
          setPreRenderedSvg(svg);
          setIsRendering(false);
        }
      } catch (e: any) {
        if (cancelled) return;
        if (!useCdn && isMermaidDynamicImportError(e)) {
          await renderInBackground(true);
          return;
        }
        if (!cancelled) {
          setMermaidError(`Diagram render failed: ${e?.message || e}`);
          setIsRendering(false);
        }
      }
    };

    renderInBackground();
    return () => {
      cancelled = true;
    };
  }, [mermaidCode]);

  useEffect(() => {
    if (sel === '_template') {
      setSel(null);
      return;
    }
    if (!sel && workflows.length) {
      setSel(workflows[0].id);
    }
  }, [sel, workflows]);

  const filteredWorkflows = useMemo(() => {
    if (!filter) return workflows;
    const q = filter.toLowerCase();
    return workflows.filter(w => (w.id || '').toLowerCase().includes(q) || (w.name || '').toLowerCase().includes(q));
  }, [workflows, filter]);

  const handleDelete = async () => {
    if (!sel) return;
    setDeleteBusy(true);
    setDeleteErr(null);
    try {
      const res = await thinkWorkflowDelete(sel);
      if (!res.ok) {
        setDeleteErr('Failed to delete workflow');
      } else {
        setDeleteOpen(false);
        setSel(null);
        await refetch();
      }
    } catch (e: any) {
      setDeleteErr(getErrorMessage(e));
    } finally {
      setDeleteBusy(false);
    }
  };

  return (
    <Grid container spacing={2}>
      <Grid xs={4}>
        <Paper sx={{ p: 1, height: 'calc(100vh - 260px)', display: 'flex', flexDirection: 'column' }}>
          <Stack direction="row" alignItems="center" justifyContent="space-between" sx={{ mb: 1 }}>
            <Typography variant="subtitle1" sx={{ fontSize: 12 }}>Workflows</Typography>
            <Stack direction="row" spacing={1} alignItems="center">
              <Tooltip title="New Workflow">
                <IconButton size="small" color="primary" onClick={() => navigate('/workflows/new')}>
                  <AddCircleIcon fontSize="small" />
                </IconButton>
              </Tooltip>
              <Tooltip title={sel ? 'Edit Workflow' : 'Select a workflow'}>
                <span>
                  <IconButton size="small" color="primary" disabled={!sel} onClick={() => sel && navigate(`/workflows/edit/${sel}`)}>
                    <EditIcon fontSize="small" />
                  </IconButton>
                </span>
              </Tooltip>
              <Tooltip title={sel ? 'Delete Workflow' : 'Select a workflow'}>
                <span>
                  <IconButton size="small" color="error" disabled={!sel} onClick={()=>setDeleteOpen(true)}>
                    <DeleteOutlineIcon fontSize="small" />
                  </IconButton>
                </span>
              </Tooltip>
            </Stack>
          </Stack>
          {isLoading && <LinearProgress />}
          {isError && <Alert severity="error">{getErrorMessage(error as any)}</Alert>}
          <TextField
            fullWidth
            size="small"
            placeholder="Search workflows..."
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            sx={{ mb: 1 }}
          />
          <List dense sx={{ flex: 1, overflowY: 'auto' }}>
            {filteredWorkflows.map(w => (
              <ListItem key={w.id} disablePadding>
                <ListItemButton selected={sel === w.id} onClick={() => setSel(w.id)} onDoubleClick={()=>navigate(`/workflows/edit/${w.id}`)}>
                  <ListItemText
                    primary={
                      <Box display="flex" alignItems="center" gap={1}>
                        <Typography component="span" sx={{ fontWeight: 600 }}>{w.name || w.id}</Typography>
                        <Chip size="small" label={`v${w.version}`} />
                      </Box>
                    }
                    secondary={w.desc || ''}
                  />
                </ListItemButton>
              </ListItem>
            ))}
          </List>
        </Paper>
      </Grid>
      <Grid xs={8}>
        <Paper sx={{ p: 2, height: 'calc(100vh - 260px)', display: 'flex', flexDirection: 'column' }}>
          <Stack direction="row" spacing={2} alignItems="center" justifyContent="space-between">
            <Stack spacing={0.5}>
              <Typography variant="subtitle1" sx={{ fontSize: 12 }}>Workflow Details</Typography>
              {sel && (
                <Stack direction="row" spacing={1} alignItems="center">
                  <Chip size="small" label={`ID: ${sel}`} sx={{ textTransform: 'none' }} />
                  {wfRead.data?.workflow_yaml && (() => {
                    try {
                      const parsed = YAML.load(wfRead.data.workflow_yaml) as any;
                      const version = parsed?.version ?? '1';
                      return <Chip size="small" color="primary" label={`v${version}`} />;
                    } catch {
                      return null;
                    }
                  })()}
                </Stack>
              )}
            </Stack>
          <Stack direction="row" alignItems="center" spacing={1}>
              <Tooltip title={sel ? 'Start Workflow' : 'Select a workflow to start'}>
                <span>
                  <Button size="small" variant="contained" disabled={!sel} onClick={() => {
                    setStartErr(null);
                    const sch = startSchema;
                    if (sch && sch.properties && Object.keys(sch.properties).length) {
                      setStartUseForm(true);
                      try {
                        const def: any = {};
                        Object.keys(sch.properties).forEach((k) => {
                          const t = sch.properties[k]?.type;
                          if (t === 'string') def[k] = '';
                          else if (t === 'integer' || t === 'number') def[k] = 0;
                          else if (t === 'boolean') def[k] = false;
                          else if (t === 'array' && sch.properties[k]?.items?.type === 'string') def[k] = [];
                        });
                        setStartFormValues(def);
                        setStartJson(JSON.stringify(def, null, 2));
                      } catch { setStartJson('{}'); }
                    } else {
                      setStartUseForm(false);
                      setStartJson('{}');
                    }
                    setStartOpen(true);
                  }}>Start</Button>
                </span>
              </Tooltip>
              {sel && mermaidCode && (
                <Tooltip title={isRendering ? 'Rendering diagram...' : preRenderedSvg ? 'View diagram' : 'Diagram not ready'}>
                  <span>
                    <IconButton
                      size="small"
                      onClick={() => setDiagramOpen(true)}
                      color="primary"
                      disabled={!preRenderedSvg}
                    >
                      {isRendering ? <CircularProgress size={20} /> : <AccountTreeIcon />}
                    </IconButton>
                  </span>
                </Tooltip>
              )}
              <Tooltip title={wfRead.data?.workflow_yaml ? 'Copy YAML' : 'Select a workflow to copy'}>
                <span>
                  <IconButton
                    size="small"
                    disabled={!wfRead.data?.workflow_yaml}
                    onClick={() => { try { navigator.clipboard.writeText(wfRead.data?.workflow_yaml || ''); setCopied(true); } catch { setCopied(true); } }}
                  >
                    <ContentCopyIcon fontSize="small" />
                  </IconButton>
                </span>
              </Tooltip>
              <Tabs value={subTab} onChange={(_, v)=>setSubTab(v)}>
                <Tab icon={<ArticleIcon fontSize="small" />} iconPosition="start" label="YAML" />
              </Tabs>
            </Stack>
          </Stack>
          {wfRead.isFetching && <LinearProgress />}
          {wfRead.isError && <Alert severity="error">{getErrorMessage(wfRead.error as any)}</Alert>}
          {mermaidError && <Alert severity="warning" sx={{ mt: 1 }}>{mermaidError}</Alert>}
          {subTab === 0 && (
            <Box sx={{ flex: 1, minHeight: 0 }}>
              <Viewer
                content={wfRead.data?.workflow_yaml || 'Select a workflow to view YAML'}
                language="yaml"
                height={'100%'}
              />
            </Box>
          )}
        </Paper>
      </Grid>

      <WorkflowDiagram
        open={diagramOpen}
        onClose={() => setDiagramOpen(false)}
        svgContent={preRenderedSvg || ''}
        workflowName={sel || undefined}
      />
      <Dialog open={deleteOpen} onClose={() => { if (!deleteBusy) { setDeleteOpen(false); setDeleteErr(null); } }}>
        <DialogTitle>Delete Workflow</DialogTitle>
        <DialogContent dividers>
          <Typography variant="body2">Are you sure you want to delete workflow <strong>{sel}</strong>? This action cannot be undone.</Typography>
          {deleteErr && <Alert severity="error" sx={{ mt: 2 }}>{deleteErr}</Alert>}
        </DialogContent>
        <DialogActions>
          <Tooltip title="Cancel">
            <span>
              <IconButton onClick={() => { setDeleteOpen(false); setDeleteErr(null); }} disabled={deleteBusy}>
                <CloseIcon />
              </IconButton>
            </span>
          </Tooltip>
          <Tooltip title="Delete">
            <span>
              <IconButton onClick={handleDelete} color="error" disabled={!sel || deleteBusy}>
                {deleteBusy ? <CircularProgress size={20} /> : <DeleteOutlineIcon />}
              </IconButton>
            </span>
          </Tooltip>
        </DialogActions>
      </Dialog>
      <Snackbar open={copied} autoHideDuration={2000} onClose={() => setCopied(false)} message="Copied YAML" anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }} />

      {/* Start Dialog */}
      <Dialog open={startOpen} onClose={() => !startBusy && setStartOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle>Start Workflow {sel}</DialogTitle>
        <DialogContent dividers>
          {startErr && <Alert severity="error" sx={{ mb: 1 }}>{startErr}</Alert>}
          <Stack direction="row" spacing={1} sx={{ mb: 1 }}>
            <Button size="small" variant={startUseForm ? 'contained' : 'outlined'} disabled={!startSchema} onClick={()=>setStartUseForm(true)}>Form</Button>
            <Button size="small" variant={!startUseForm ? 'contained' : 'outlined'} onClick={()=>setStartUseForm(false)}>JSON</Button>
          </Stack>
          {startUseForm && startSchema ? (
            <Stack spacing={1}>
              {Object.entries((startSchema as any).properties || {}).map(([k, v]: any) => {
                const t = v?.type;
                if (t === 'string') return <TextField key={k} label={k} value={startFormValues[k]||''} onChange={(e)=>setStartFormValues({...startFormValues,[k]:e.target.value})} />;
                if (t === 'integer' || t === 'number') return <TextField key={k} type="number" label={k} value={startFormValues[k]??0} onChange={(e)=>setStartFormValues({...startFormValues,[k]:Number(e.target.value)})} />;
                if (t === 'boolean') return (
                  <Stack key={k} direction="row" spacing={1} alignItems="center">
                    <Typography>{k}</Typography>
                    <Button size="small" variant={startFormValues[k]? 'contained':'outlined'} onClick={()=>setStartFormValues({...startFormValues,[k]:!startFormValues[k]})}>{String(startFormValues[k]||false)}</Button>
                  </Stack>
                );
                if (t === 'array' && v?.items?.type === 'string') return <TextField key={k} label={`${k} (comma-separated)`} value={(startFormValues[k]||[]).join(',')} onChange={(e)=>setStartFormValues({...startFormValues,[k]:e.target.value.split(',').map((s:string)=>s.trim()).filter(Boolean)})} />;
                return null;
              })}
            </Stack>
          ) : (
            <TextField label="Params (JSON)" value={startJson} onChange={(e)=>setStartJson(e.target.value)} multiline minRows={4} />
          )}
        </DialogContent>
        <DialogActions>
          <Button onClick={()=>!startBusy && setStartOpen(false)} disabled={startBusy}>Close</Button>
          <Button variant="contained" onClick={async ()=>{
            setStartErr(null);
            if (!sel) return;
            try {
              setStartBusy(true);
              const params = startUseForm ? startFormValues : JSON.parse(startJson || '{}');
              const res = await thinkPlan(sel, params, null, true);
              if (res && res.run_id) {
                setStartOpen(false);
                navigate('/engines/think/runs');
              }
            } catch (e: any) {
              setStartErr(getErrorMessage(e));
            } finally {
              setStartBusy(false);
            }
          }} disabled={startBusy}>
            {startBusy ? 'Starting…' : 'Start'}
          </Button>
        </DialogActions>
      </Dialog>
    </Grid>
  );
}
