import React, { useMemo, useState } from 'react';
import { useThinkRuns, useThinkRun, thinkRunDelete } from '../../api';
import Grid from '@mui/material/Unstable_Grid2';
import Paper from '@mui/material/Paper';
import List from '@mui/material/List';
import ListItem from '@mui/material/ListItem';
import ListItemButton from '@mui/material/ListItemButton';
import ListItemText from '@mui/material/ListItemText';
import Typography from '@mui/material/Typography';
import LinearProgress from '@mui/material/LinearProgress';
import Alert from '@mui/material/Alert';
import { getErrorMessage } from '../../api';
import Box from '@mui/material/Box';
import Stack from '@mui/material/Stack';
import Tooltip from '@mui/material/Tooltip';
import IconButton from '@mui/material/IconButton';
import ContentCopyIcon from '@mui/icons-material/ContentCopy';
import DeleteOutlineIcon from '@mui/icons-material/DeleteOutline';
import SchemaIcon from '@mui/icons-material/Schema';
import DataObjectIcon from '@mui/icons-material/DataObject';
import Viewer from '../../components/Viewer';
import Tabs from '@mui/material/Tabs';
import Tab from '@mui/material/Tab';
import Snackbar from '@mui/material/Snackbar';
import Collapse from '@mui/material/Collapse';
import ExpandMoreIcon from '@mui/icons-material/ExpandMore';
import ExpandLessIcon from '@mui/icons-material/ExpandLess';

const PANEL_HEIGHT = 'calc(100vh - 260px)';

export default function ThinkRuns() {
  const { data, isLoading, isError, error, refetch } = useThinkRuns();
  const rows = data?.runs || [];
  const [sel, setSel] = useState<{ workflow: string; run_id: string } | null>(null);
  const run = useThinkRun(sel?.workflow || null, sel?.run_id || null);

  const title = useMemo(() => sel ? `${sel.workflow} / ${sel.run_id}` : 'Select a run', [sel]);
  const [viewTab, setViewTab] = useState(0); // 0 = Visual, 1 = JSON
  const [copiedOpen, setCopiedOpen] = useState(false);
  // Removed non-functional expand/collapse all controls to simplify UI

  function copyJson(txt: string) {
    try {
      navigator.clipboard.writeText(txt);
      setCopiedOpen(true);
    } catch {
      setCopiedOpen(true);
    }
  }

  function VisualNode({ name, value, depth = 0 }: { name?: string; value: any; depth?: number }) {
    const pad = depth * 12;
    const isArray = Array.isArray(value);
    const isObj = value && typeof value === 'object' && !isArray;
    if (!isObj && !isArray) {
      return (
        <Stack direction="row" spacing={1} sx={{ pl: pad/8, py: 0.5, alignItems: 'baseline' }}>
          {name && <Typography sx={{ minWidth: 180, fontWeight: 600 }}>{name}</Typography>}
          <Typography sx={{ fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace' }}>
            {typeof value === 'string' ? value : JSON.stringify(value)}
          </Typography>
        </Stack>
      );
    }
    const [open, setOpen] = useState(false);
    const header = (
      <Stack direction="row" spacing={1} alignItems="center" sx={{ pl: pad/8, py: 0.25 }}>
        <IconButton size="small" onClick={() => setOpen(o => !o)} aria-label={open ? 'Collapse' : 'Expand'}>
          {open ? <ExpandLessIcon fontSize="small" /> : <ExpandMoreIcon fontSize="small" />}
        </IconButton>
        {name && <Typography sx={{ fontWeight: 600 }}>{name}</Typography>}
        <Typography sx={{ color: 'text.secondary', fontSize: 12 }}>
          {isArray ? `[${(value as any[]).length}]` : '{ }'}
        </Typography>
      </Stack>
    );
    return (
      <Box sx={{ py: 0.25 }}>
        {header}
        <Collapse in={open} timeout="auto" unmountOnExit>
          <Box sx={{ borderLeft: '2px solid #eee', ml: 3 }}>
            {isArray
              ? (value as any[]).map((v: any, idx: number) => (
                  <VisualNode key={idx} name={`#${idx}`} value={v} depth={depth + 1} />
                ))
              : Object.entries(value || {}).map(([k, v]) => (
                  <VisualNode key={k} name={k} value={v} depth={depth + 1} />
                ))}
          </Box>
        </Collapse>
      </Box>
    );
  }

  async function del() {
    if (!sel) return;
    await thinkRunDelete(sel.workflow, sel.run_id);
    setSel(null);
    refetch();
  }

  return (
    <Grid container spacing={2}>
      <Grid xs={12} md={4}>
        <Paper sx={{ p: 1, height: PANEL_HEIGHT, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
          <Typography variant="subtitle1" sx={{ px: 1, py: 1 }}>Runs</Typography>
          {isLoading && <LinearProgress />}
          {isError && <Alert severity="error">{getErrorMessage(error as any)}</Alert>}
          <Box sx={{ flex: 1, overflowY: 'auto' }}>
            <List dense>
              {rows.map(r => (
                <ListItem key={`${r.workflow}__${r.run_id}`} disablePadding>
                  <ListItemButton selected={sel?.run_id === r.run_id && sel?.workflow === r.workflow} onClick={() => setSel({ workflow: r.workflow, run_id: r.run_id })}>
                    <ListItemText primary={`${r.workflow} / ${r.run_id}`} secondary={`completed=${r.completed} next=${r.next_step_id || '-'} updated=${r.updated_at}`} />
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
                <Tab icon={<SchemaIcon fontSize="small" />} aria-label="Visual" />
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
          {run.isError && <Alert severity="error">{getErrorMessage(run.error as any)}</Alert>}
          <Box sx={{ flex: 1, overflowY: 'auto', mt: 1 }}>
            {viewTab === 0 && (
              <Box>
                {run.data ? (
                  <VisualNode value={(run.data as any).state} />
                ) : (
                  <Typography>Select a run to view state</Typography>
                )}
              </Box>
            )}
            {viewTab === 1 && (
              <Box>
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
      <Snackbar open={copiedOpen} autoHideDuration={2000} onClose={() => setCopiedOpen(false)} message="Copied JSON to clipboard" anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }} />
    </Grid>
  );
}
