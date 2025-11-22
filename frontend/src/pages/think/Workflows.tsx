import React, { useState, useMemo, useEffect } from 'react';
import { useThinkWorkflows, useThinkWorkflowRead } from '../../api';
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
import CircularProgress from '@mui/material/CircularProgress';
import AccountTreeIcon from '@mui/icons-material/AccountTree';
import WorkflowDiagram from '../../components/WorkflowDiagram';
import { workflowToMermaid } from '../../utils/workflowToMermaid';

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
  const { data, isLoading, isError, error } = useThinkWorkflows();
  const [sel, setSel] = useState<string | null>(null);
  const wfRead = useThinkWorkflowRead(sel);
  const [subTab, setSubTab] = useState(0);
  const [diagramOpen, setDiagramOpen] = useState(false);

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

  return (
    <Grid container spacing={2}>
      <Grid size={{ xs: 12, md: 4 }}>
        <Paper sx={{ p: 1 }}>
          <Typography variant="subtitle1" sx={{ px: 1, py: 1 }}>Workflows</Typography>
          {isLoading && <LinearProgress />}
          {isError && <Alert severity="error">{(error as any)?.message || 'Failed to load workflows'}</Alert>}
          <List dense>
            {(data?.workflows || []).map(w => (
              <ListItem key={w.id} disablePadding>
                <ListItemButton selected={sel === w.id} onClick={() => setSel(w.id)}>
                  <ListItemText primary={w.id} secondary={`${w.version} — ${w.desc || ''}`} />
                </ListItemButton>
              </ListItem>
            ))}
          </List>
        </Paper>
      </Grid>
      <Grid size={{ xs: 12, md: 8 }}>
        <Paper sx={{ p: 2 }}>
          <Stack direction="row" spacing={2} alignItems="center" justifyContent="space-between">
            <Typography variant="subtitle1">Workflow {sel ? `(${sel})` : ''}</Typography>
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
              <Tabs value={subTab} onChange={(_, v)=>setSubTab(v)}>
                <Tab label="YAML" />
              </Tabs>
            </Stack>
          </Stack>
          {wfRead.isFetching && <LinearProgress />}
          {wfRead.isError && <Alert severity="error">{(wfRead.error as any)?.message || 'Failed to load workflow'}</Alert>}
          {mermaidError && <Alert severity="warning" sx={{ mt: 1 }}>{mermaidError}</Alert>}
          {subTab === 0 && (
            <Box component="pre" sx={{ mt: 1, whiteSpace: 'pre-wrap', fontFamily: 'monospace', fontSize: 13 }}>
              {wfRead.data?.workflow_yaml || 'Select a workflow to view YAML'}
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
    </Grid>
  );
}
