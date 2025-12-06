import React, { useMemo, useState } from 'react';
import Grid from '@mui/material/Grid2';
import Paper from '@mui/material/Paper';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import LinearProgress from '@mui/material/LinearProgress';
import Alert from '@mui/material/Alert';
import List from '@mui/material/List';
import ListItem from '@mui/material/ListItem';
import ListItemButton from '@mui/material/ListItemButton';
import ListItemText from '@mui/material/ListItemText';
import Stack from '@mui/material/Stack';
import Chip from '@mui/material/Chip';
import IconButton from '@mui/material/IconButton';
import Tooltip from '@mui/material/Tooltip';
import AddCircleIcon from '@mui/icons-material/AddCircle';
import PlayArrowIcon from '@mui/icons-material/PlayArrow';
import EditIcon from '@mui/icons-material/Edit';
import DeleteOutlineIcon from '@mui/icons-material/DeleteOutline';
import FavoriteIcon from '@mui/icons-material/Favorite';
import FavoriteBorderIcon from '@mui/icons-material/FavoriteBorder';
import TextField from '@mui/material/TextField';
import Button from '@mui/material/Button';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import DialogActions from '@mui/material/DialogActions';
import CloseIcon from '@mui/icons-material/Close';
import { agentRun, agentsDelete, getErrorMessage, useAgent, useAgents, useAgentRuns } from '../../api';
import { useNavigate } from 'react-router-dom';

const PANEL_HEIGHT = 'calc(100vh - 260px)';

export default function Agents() {
  const nav = useNavigate();
  const [filter, setFilter] = useState('');
  const [sel, setSel] = useState<string | null>(null);
  const [input, setInput] = useState('');
  const [running, setRunning] = useState(false);
  const [confirmOpen, setConfirmOpen] = useState(false);
  const { data, isLoading, isError, error, refetch } = useAgents();
  const details = useAgent(sel);
  const runs = useAgentRuns(sel);
  const agents = useMemo(() => {
    const list = data?.agents || [];
    const f = filter.toLowerCase();
    return f ? list.filter((a) => a.name.toLowerCase().includes(f)) : list;
  }, [data, filter]);

  return (
    <Grid container spacing={2}>
      <Grid size={{ xs: 12, md: 4 }}>
        <Paper sx={{ p: 1, height: PANEL_HEIGHT, display: 'flex', flexDirection: 'column' }}>
          <Box display="flex" alignItems="center" justifyContent="space-between" sx={{ mb: 1 }}>
            <Typography variant="subtitle1" sx={{ fontSize: 12 }}>Agents</Typography>
            <Tooltip title="New Agent">
              <IconButton size="small" color="primary" onClick={() => nav('/engines/agents/new')}>
                <AddCircleIcon fontSize="small" />
              </IconButton>
            </Tooltip>
          </Box>
          {isLoading && <LinearProgress />}
          {isError && <Alert severity="error">{getErrorMessage(error as any)}</Alert>}
          <TextField size="small" fullWidth placeholder="Search agents..." value={filter} onChange={(e) => setFilter(e.target.value)} sx={{ mb: 1 }} />
          <List dense sx={{ flex: 1, overflowY: 'auto' }}>
            {agents.map((a) => (
              <ListItem key={a.name} disablePadding secondaryAction={
                <Stack direction="row" spacing={1} alignItems="center">
                  <Chip size="small" label={`runs ${a.run_count || 0}`} />
                  <IconButton size="small" color={a.favorite ? 'error' : 'default'}>
                    {a.favorite ? <FavoriteIcon fontSize="small" /> : <FavoriteBorderIcon fontSize="small" />}
                  </IconButton>
                </Stack>
              }>
                <ListItemButton selected={sel === a.name} onClick={() => setSel(a.name)}>
                  <ListItemText primary={a.name} secondary={a.last_run_at ? `last ${new Date(a.last_run_at).toLocaleString()}` : 'never run'} />
                </ListItemButton>
              </ListItem>
            ))}
          </List>
        </Paper>
      </Grid>

      <Grid size={{ xs: 12, md: 8 }}>
        <Paper sx={{ p: 2, height: PANEL_HEIGHT, display: 'flex', flexDirection: 'column', gap: 1 }}>
          <Stack direction="row" alignItems="center" justifyContent="space-between">
            <Typography variant="subtitle2">Agent Details</Typography>
            <Stack direction="row" spacing={1}>
              <Tooltip title={sel ? 'Edit Agent' : 'Select an agent'}>
                <span>
                  <IconButton size="small" color="primary" disabled={!sel} onClick={() => sel && nav(`/engines/agents/edit/${sel}`)}>
                    <EditIcon fontSize="small" />
                  </IconButton>
                </span>
              </Tooltip>
              <Tooltip title={sel ? 'Delete Agent' : 'Select an agent'}>
                <span>
                  <IconButton size="small" color="error" disabled={!sel} onClick={() => setConfirmOpen(true)}>
                    <DeleteOutlineIcon fontSize="small" />
                  </IconButton>
                </span>
              </Tooltip>
            </Stack>
          </Stack>
          {details.isFetching && <LinearProgress />}
          {details.isError && <Alert severity="error">{getErrorMessage(details.error as any)}</Alert>}
          <Box sx={{ display: 'flex', gap: 2 }}>
            <TextField size="small" fullWidth placeholder="Enter input for run..." value={input} onChange={(e) => setInput(e.target.value)} />
            <Button size="small" startIcon={<PlayArrowIcon />} disabled={!sel || !input || running} onClick={async () => {
              if (!sel || !input) return;
              setRunning(true);
              try { await agentRun(sel, input); setInput(''); await runs.refetch(); await refetch(); } finally { setRunning(false); }
            }}>Run</Button>
          </Box>
          <Typography variant="subtitle2" sx={{ mt: 1 }}>Recent Runs</Typography>
          {runs.isFetching && <LinearProgress />}
          {runs.isError && <Alert severity="error">{getErrorMessage(runs.error as any)}</Alert>}
          <Box sx={{ flex: 1, overflowY: 'auto' }}>
            {(runs.data?.runs || []).map((r) => (
              <Paper key={r.id} variant="outlined" sx={{ p: 1, mb: 1 }}>
                <Stack direction="row" justifyContent="space-between" alignItems="center">
                  <Stack direction="row" spacing={1} alignItems="center">
                    <Chip size="small" label={`#${r.id}`} />
                    <Chip size="small" color={r.status === 'ok' ? 'success' : 'warning'} label={r.status || 'ok'} />
                    <Chip size="small" label={`${r.duration_ms || 0} ms`} />
                  </Stack>
                  <Button size="small" onClick={() => nav(`/engines/agents/run/${sel}/${r.id}`)}>View</Button>
                </Stack>
                <Typography variant="body2" sx={{ mt: 1 }}>{r.output_summary || '(no summary)'}</Typography>
              </Paper>
            ))}
          </Box>
        </Paper>
      </Grid>

      <Dialog open={confirmOpen} onClose={() => setConfirmOpen(false)}>
        <DialogTitle sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          Delete Agent
          <IconButton size="small" onClick={() => setConfirmOpen(false)}>
            <CloseIcon fontSize="small" />
          </IconButton>
        </DialogTitle>
        <DialogContent dividers>
          Are you sure you want to delete "{sel}"?
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setConfirmOpen(false)}>Cancel</Button>
          <Button color="error" disabled={!sel} onClick={async () => {
            if (!sel) return;
            await agentsDelete(sel);
            setConfirmOpen(false);
            setSel(null);
            await refetch();
          }}>Delete</Button>
        </DialogActions>
      </Dialog>
    </Grid>
  );
}
