import React, { useMemo, useState } from 'react';
import { useThinkPrompts, useThinkPrompt, thinkPromptsDelete, useThinkWorkflows } from '../../api';
import Box from '@mui/material/Box';
import Stack from '@mui/material/Stack';
import Grid from '@mui/material/Unstable_Grid2';
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
import ContentCopyIcon from '@mui/icons-material/ContentCopy';
import AddCircleIcon from '@mui/icons-material/AddCircle';
import EditIcon from '@mui/icons-material/Edit';
import DeleteOutlineIcon from '@mui/icons-material/DeleteOutline';
import TextField from '@mui/material/TextField';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import DialogActions from '@mui/material/DialogActions';
import Button from '@mui/material/Button';
import { getErrorMessage } from '../../api';
import Viewer from '../../components/Viewer';
import { useNavigate } from 'react-router-dom';
import { THINK_PROMPTS_NEW_PATH, thinkPromptsEditPath } from './routes';

const PANEL_HEIGHT = 'calc(100vh - 260px)';

export default function ThinkPrompts() {
  const { data, isLoading, isError, error } = useThinkPrompts();
  const [sel, setSel] = useState<string | null>(null);
  const pr = useThinkPrompt(sel);
  const workflows = useThinkWorkflows();
  const [copied, setCopied] = useState(false);
  const [filter, setFilter] = useState('');
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const nav = useNavigate();

  const rows = data?.versions || [];
  const workflowRows = workflows.data?.workflows || [];
  const usedBy = React.useMemo(() => {
    if (!sel) return [] as { id: string; label: string }[];
    return workflowRows
      .filter((w) => (w.driver_version || 'stable') === sel)
      .map((w) => ({ id: w.id, label: w.name || w.id }));
  }, [workflowRows, sel]);
  const filtered = useMemo(() => {
    const q = filter.trim().toLowerCase();
    if (!q) return rows;
    return rows.filter(r => r.version.toLowerCase().includes(q) || (r.path || '').toLowerCase().includes(q));
  }, [rows, filter]);

  return (
    <Grid container spacing={2}>
      <Grid xs={12} md={4}>
        <Paper sx={{ p: 1, height: PANEL_HEIGHT, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
          <Stack direction="row" alignItems="center" justifyContent="space-between" sx={{ mb: 1 }}>
            <Typography variant="subtitle1" sx={{ fontSize: 12 }}>Prompts</Typography>
            <Stack direction="row" spacing={1}>
              <Tooltip title="New Prompt">
                <IconButton size="small" color="primary" onClick={() => nav(THINK_PROMPTS_NEW_PATH)}>
                  <AddCircleIcon fontSize="small" />
                </IconButton>
              </Tooltip>
              <Tooltip title={sel ? 'Edit Prompt' : 'Select a prompt'}>
                <span>
                  <IconButton size="small" color="primary" disabled={!sel} onClick={() => sel && nav(thinkPromptsEditPath(sel))}>
                    <EditIcon fontSize="small" />
                  </IconButton>
                </span>
              </Tooltip>
              <Tooltip title={sel ? (usedBy.length > 0 ? 'Cannot delete: prompt in use by workflows' : 'Delete Prompt') : 'Select a prompt'}>
                <span>
                  <IconButton size="small" color="error" disabled={!sel || usedBy.length > 0} onClick={() => setConfirmOpen(true)}>
                    <DeleteOutlineIcon fontSize="small" />
                  </IconButton>
                </span>
              </Tooltip>
            </Stack>
          </Stack>
          {isLoading && <LinearProgress />}
          {isError && <Alert severity="error">{getErrorMessage(error as any)}</Alert>}
          <TextField size="small" fullWidth placeholder="Search prompts..." value={filter} onChange={(e)=>setFilter(e.target.value)} sx={{ mb: 1 }} />
          <Box sx={{ flex: 1, overflowY: 'auto' }}>
            <List dense>
              {filtered.map(v => (
                <ListItem key={v.version} disablePadding>
                  <ListItemButton selected={sel === v.version} onClick={() => setSel(v.version)} onDoubleClick={() => nav(thinkPromptsEditPath(v.version))}>
                    <ListItemText
                      primary={
                        <Box display="flex" alignItems="center" gap={1}>
                          <Typography component="span" sx={{ fontWeight: 600 }}>{v.version}</Typography>
                          {v.path && <Chip size="small" label={(v.path.split('/').pop() || '').replace(/\.md$/,'')} />}
                        </Box>
                      }
                      secondary={v.path}
                    />
                  </ListItemButton>
                </ListItem>
              ))}
            </List>
          </Box>
        </Paper>
      </Grid>
      <Grid xs={12} md={8}>
        <Paper sx={{ p: 2, height: PANEL_HEIGHT, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
          <Stack direction="row" spacing={2} alignItems="center" justifyContent="space-between">
            <Stack spacing={0.5}>
              <Typography variant="subtitle1" sx={{ fontSize: 12 }}>Prompt Details</Typography>
              {sel && (
                <Stack direction="row" spacing={1} alignItems="center" flexWrap="wrap">
                  <Chip size="small" label={`ID: ${sel}`} />
                  {(() => { const row = rows.find(r => r.version === sel); return row?.path ? <Chip size="small" color="primary" label={(row.path.split('/').pop() || '')} /> : null; })()}
                </Stack>
              )}
              {sel && (
                <Box sx={{ mt: 1 }}>
                  <Typography variant="caption" sx={{ fontWeight: 600 }}>Used by</Typography>
                  {workflows.isLoading && <Typography variant="caption" sx={{ ml: 1 }}>Loading…</Typography>}
                  {!workflows.isLoading && (
                    usedBy.length > 0 ? (
                      <Stack direction="row" spacing={1} sx={{ mt: 0.5, flexWrap: 'wrap' }}>
                        {usedBy.map((wf) => (
                          <Chip
                            key={wf.id}
                            size="small"
                            label={wf.label}
                            clickable
                            onClick={() => nav(`/workflows/edit/${wf.id}`)}
                            sx={{ mb: 0.5 }}
                          />
                        ))}
                      </Stack>
                    ) : (
                      <Typography variant="caption" sx={{ display: 'block', mt: 0.5 }}>No workflows reference this prompt.</Typography>
                    )
                  )}
                </Box>
              )}
            </Stack>
            <Tooltip title={pr.data?.prompt_md ? 'Copy Prompt' : 'Select a prompt to copy'}>
              <span>
                <IconButton
                  size="small"
                  disabled={!pr.data?.prompt_md}
                  onClick={() => { try { navigator.clipboard.writeText(pr.data?.prompt_md || ''); setCopied(true); } catch { setCopied(true); } }}
                >
                  <ContentCopyIcon fontSize="small" />
                </IconButton>
              </span>
            </Tooltip>
          </Stack>
          {pr.isFetching && <LinearProgress />}
          {pr.isError && <Alert severity="error">{getErrorMessage(pr.error as any)}</Alert>}
          <Box sx={{ flex: 1, overflowY: 'auto', mt: 1 }}>
            <Viewer content={pr.data?.prompt_md || 'Select a prompt version to view markdown'} contentType="text/markdown" height={'100%'} />
          </Box>
        </Paper>
        <Snackbar open={copied} autoHideDuration={2000} onClose={() => setCopied(false)} message="Copied prompt" anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }} />
        <Dialog open={confirmOpen} onClose={() => setConfirmOpen(false)}>
          <DialogTitle>Delete Prompt</DialogTitle>
          <DialogContent>
            {usedBy.length > 0 && (
              <Alert severity="warning" sx={{ mb: 1 }}>
                Cannot delete: this prompt is used by {usedBy.length} workflow{usedBy.length === 1 ? '' : 's'}.
              </Alert>
            )}
            Are you sure you want to delete "{sel}"?
          </DialogContent>
          <DialogActions>
            <Button onClick={()=>setConfirmOpen(false)}>Cancel</Button>
            <Button color="error" disabled={!sel || busy || usedBy.length > 0} onClick={async ()=>{ if (!sel) return; try { setBusy(true); await thinkPromptsDelete(sel); setConfirmOpen(false); setSel(null); } finally { setBusy(false); } }}>Delete</Button>
          </DialogActions>
        </Dialog>
      </Grid>
    </Grid>
  );
}
