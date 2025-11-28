import React, { useState, useMemo, useEffect } from 'react';
import { useThinkWorkflows, useThinkWorkflowRead } from '../../api';
import { useNavigate } from 'react-router-dom';
import Box from '@mui/material/Box';
import Grid from '@mui/material/Grid2';
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
import IconButton from '@mui/material/IconButton';
import Tooltip from '@mui/material/Tooltip';
import Snackbar from '@mui/material/Snackbar';
import Button from '@mui/material/Button';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import DialogActions from '@mui/material/DialogActions';
import CircularProgress from '@mui/material/CircularProgress';
import ContentCopyIcon from '@mui/icons-material/ContentCopy';
import AccountTreeIcon from '@mui/icons-material/AccountTree';
import EditIcon from '@mui/icons-material/Edit';
import DeleteOutlineIcon from '@mui/icons-material/DeleteOutline';
import AddCircleIcon from '@mui/icons-material/AddCircle';
import WorkflowDiagram from '../../components/WorkflowDiagram';
import { workflowToMermaid } from '../../utils/workflowToMermaid';
import { getErrorMessage } from '../../api';
import Viewer from '../../components/Viewer';
import { thinkWorkflowDelete } from '../../thinkApi';

// Lazy load mermaid and cache it
let mermaidInstance: any = null;
async function getMermaid() {
  if (mermaidInstance) return mermaidInstance;
  const m = await import('mermaid');
  mermaidInstance = m.default;
  mermaidInstance.initialize({
    startOnLoad: false,
    theme: 'default',
    flowchart: { useMaxWidth: true, htmlLabels: true, curve: 'basis' },
    securityLevel: 'loose',
  });
  return mermaidInstance;
}

export default function ThinkWorkflows() {
  const navigate = useNavigate();
  const { data, isLoading, isError, error, refetch } = useThinkWorkflows();
  const [sel, setSel] = useState<string | null>(null);
  const wfRead = useThinkWorkflowRead(sel);
  const [subTab, setSubTab] = useState(0);
  const [diagramOpen, setDiagramOpen] = useState(false);
  const [copied, setCopied] = useState(false);
  const [deleteOpen, setDeleteOpen] = useState(false);
  const [deleteBusy, setDeleteBusy] = useState(false);
  const [deleteErr, setDeleteErr] = useState<string | null>(null);

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

    const renderInBackground = async () => {
      try {
        const mermaid = await getMermaid();
        const id = `pre-render-${Date.now()}`;
        const { svg } = await mermaid.render(id, mermaidCode);
        if (!cancelled) {
          setPreRenderedSvg(svg);
          setIsRendering(false);
        }
      } catch (e: any) {
        if (!cancelled) {
          setMermaidError(`Diagram render failed: ${e?.message || e}`);
          setIsRendering(false);
        }
      }
    };

    renderInBackground();
    return () => { cancelled = true; };
  }, [mermaidCode]);

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
      <Grid size={4}>
        <Paper sx={{ p: 1 }}>
          <Stack direction="row" alignItems="center" justifyContent="space-between">
            <Typography variant="subtitle1" sx={{ px: 1, py: 1 }}>Workflows</Typography>
            <Stack direction="row" spacing={1} alignItems="center">
              <Tooltip title="Edit workflow">
                <span>
                  <IconButton size="small" disabled={!sel} onClick={() => sel && navigate(`/engines/think/workflows/edit/${sel}`)}>
                    <EditIcon fontSize="small" />
                  </IconButton>
                </span>
              </Tooltip>
              <Tooltip title="Delete workflow">
                <span>
                  <IconButton size="small" color="error" disabled={!sel} onClick={()=>setDeleteOpen(true)}>
                    <DeleteOutlineIcon fontSize="small" />
                  </IconButton>
                </span>
              </Tooltip>
              <Tooltip title="Create workflow">
                <IconButton size="small" color="primary" onClick={() => navigate('/engines/think/workflows/new')}>
                  <AddCircleIcon fontSize="small" />
                </IconButton>
              </Tooltip>
            </Stack>
          </Stack>
          {isLoading && <LinearProgress />}
          {isError && <Alert severity="error">{getErrorMessage(error as any)}</Alert>}
          <List dense>
            {(data?.workflows || []).map(w => (
              <ListItem key={w.id} disablePadding>
                <ListItemButton selected={sel === w.id} onClick={() => setSel(w.id)} onDoubleClick={()=>navigate(`/engines/think/workflows/edit/${w.id}`)}>
                  <ListItemText primary={w.id} secondary={`${w.version} — ${w.desc || ''}`} />
                </ListItemButton>
              </ListItem>
            ))}
          </List>
        </Paper>
      </Grid>
      <Grid size={8}>
        <Paper sx={{ p: 2 }}>
          <Stack direction="row" spacing={2} alignItems="center" justifyContent="space-between">
            <Typography variant="subtitle1" sx={{ fontSize: 12 }}>Workflow {sel ? `(${sel})` : ''}</Typography>
            <Stack direction="row" alignItems="center" spacing={1}>
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
                <Tab label="YAML" />
              </Tabs>
            </Stack>
          </Stack>
          {wfRead.isFetching && <LinearProgress />}
          {wfRead.isError && <Alert severity="error">{getErrorMessage(wfRead.error as any)}</Alert>}
          {mermaidError && <Alert severity="warning" sx={{ mt: 1 }}>{mermaidError}</Alert>}
          {subTab === 0 && (
            <Viewer
              content={wfRead.data?.workflow_yaml || 'Select a workflow to view YAML'}
              language="yaml"
              height={460}
            />
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
          <Button onClick={() => { setDeleteOpen(false); setDeleteErr(null); }} disabled={deleteBusy}>Cancel</Button>
          <Button onClick={handleDelete} color="error" variant="contained" disabled={!sel || deleteBusy} startIcon={deleteBusy ? <CircularProgress size={16} /> : undefined}>
            {deleteBusy ? 'Deleting…' : 'Delete'}
          </Button>
        </DialogActions>
      </Dialog>
      <Snackbar open={copied} autoHideDuration={2000} onClose={() => setCopied(false)} message="Copied YAML" anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }} />
    </Grid>
  );
}
