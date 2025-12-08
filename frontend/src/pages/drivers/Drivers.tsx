import React, { useEffect, useState } from 'react';
import Grid from '@mui/material/Unstable_Grid2';
import Paper from '@mui/material/Paper';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import TextField from '@mui/material/TextField';
import Alert from '@mui/material/Alert';
import LinearProgress from '@mui/material/LinearProgress';
import List from '@mui/material/List';
import ListItemButton from '@mui/material/ListItemButton';
import ListItemText from '@mui/material/ListItemText';
import Chip from '@mui/material/Chip';
import Stack from '@mui/material/Stack';
import IconButton from '@mui/material/IconButton';
import Tooltip from '@mui/material/Tooltip';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import DialogActions from '@mui/material/DialogActions';
import Snackbar from '@mui/material/Snackbar';
import EditIcon from '@mui/icons-material/Edit';
import DeleteIcon from '@mui/icons-material/DeleteOutline';
import AddIcon from '@mui/icons-material/Add';
import DescriptionIcon from '@mui/icons-material/Description';
import ContentCopyIcon from '@mui/icons-material/ContentCopy';
import CloseIcon from '@mui/icons-material/Close';
import Viewer from '../../components/Viewer';
import { getErrorMessage, useDriver, useDrivers, driversDelete } from '../../api';
import { useNavigate } from 'react-router-dom';

const PANEL_HEIGHT = 'calc(100vh - 260px)';

export default function Drivers() {
  const nav = useNavigate();
  const [filter, setFilter] = useState('');
  const [sel, setSel] = useState<string | null>(null);
  const [openPrompt, setOpenPrompt] = useState(false);
  const [copied, setCopied] = useState(false);
  const { data, isLoading, isError, error, refetch } = useDrivers(filter);
  const drivers = data?.drivers || [];
  const selDriver = useDriver(sel);
  const selected = selDriver.data || null;

  useEffect(() => {
    if (!sel && drivers.length > 0) setSel(drivers[0].name);
  }, [drivers, sel]);

  async function onDelete() {
    if (!sel) return;
    if (!confirm(`Delete driver ${sel}?`)) return;
    await driversDelete(sel);
    setSel(null);
    await refetch();
  }

  return (
    <Grid container spacing={2}>
      <Grid xs={3}>
        <Paper sx={{ p: 2, height: PANEL_HEIGHT, display: 'flex', flexDirection: 'column' }}>
          <Typography variant="subtitle1" sx={{ fontSize: 12 }}>Drivers</Typography>
          <Stack direction="row" spacing={1} sx={{ mt: 1, mb: 1 }}>
            <TextField size="small" placeholder="Search drivers..." value={filter} onChange={(e)=>setFilter(e.target.value)} fullWidth />
            <Tooltip title="Create new driver">
              <IconButton size="small" color="primary" onClick={() => nav('/engines/drivers/new')}><AddIcon /></IconButton>
            </Tooltip>
          </Stack>
          {isLoading && <LinearProgress />}
          {isError && <Alert severity="error">{getErrorMessage(error as any)}</Alert>}
          <List dense sx={{ overflow: 'auto', flex: 1 }}>
            {drivers.map((p) => (
              <ListItemButton key={p.name} selected={sel === p.name} onClick={() => setSel(p.name)}>
                <ListItemText primary={p.name} secondary={<span>v{p.version} — {p.summary}</span>} />
              </ListItemButton>
            ))}
          </List>
        </Paper>
      </Grid>
      <Grid xs={9}>
        <Paper sx={{ p: 2, height: PANEL_HEIGHT, display: 'flex', flexDirection: 'column' }}>
          {!sel && <Typography variant="body2">Select a driver to view details.</Typography>}
          {sel && (
            <>
              {(selDriver.isFetching) && <LinearProgress />}
              {selDriver.isError && <Alert severity="error">{getErrorMessage(selDriver.error as any)}</Alert>}
              {selected && (
                <>
                  <Stack direction="row" justifyContent="space-between" alignItems="center">
                    <Stack direction="row" spacing={1} alignItems="center">
                      <Typography variant="h6" sx={{ fontWeight: 600 }}>{selected.name}</Typography>
                      <Chip size="small" label={`v${selected.version}`} />
                    </Stack>
                    <Stack direction="row" spacing={1}>
                      <Tooltip title="View Prompt (Markdown)">
                        <span><IconButton size="small" color="primary" onClick={() => setOpenPrompt(true)}><DescriptionIcon /></IconButton></span>
                      </Tooltip>
                      <Tooltip title="Edit">
                        <span><IconButton size="small" color="primary" onClick={() => nav(`/engines/drivers/edit/${selected.name}`)}><EditIcon /></IconButton></span>
                      </Tooltip>
                      <Tooltip title="Delete">
                        <span><IconButton size="small" color="error" onClick={onDelete}><DeleteIcon /></IconButton></span>
                      </Tooltip>
                    </Stack>
                  </Stack>
                  <Typography variant="body2" sx={{ mt: 1, mb: 1, color: 'text.secondary' }}>{selected.summary}</Typography>
                  {selected.tags && selected.tags.length > 0 && (
                    <Stack direction="row" spacing={0.5} sx={{ mb: 1 }}>
                      {selected.tags.map((tag: string) => <Chip key={tag} size="small" label={tag} variant="outlined" />)}
                    </Stack>
                  )}
                  <Box sx={{ flex: 1, minHeight: 0, mt: 1 }}>
                    <Viewer content={selected.prompt_md || ''} contentType="text/markdown" height={'100%'} />
                  </Box>
                </>
              )}
            </>
          )}
        </Paper>
      </Grid>

      {/* Markdown Prompt Dialog */}
      <Dialog open={openPrompt} onClose={() => setOpenPrompt(false)} fullWidth maxWidth="md">
        <DialogTitle sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
            <span>Prompt Markdown</span>
            {selected && (
              <Stack direction="row" spacing={1} alignItems="center">
                <Chip size="small" label={selected.name} />
                <Chip size="small" color="primary" label={`v${selected.version}`} />
              </Stack>
            )}
          </Box>
          <IconButton size="small" onClick={() => setOpenPrompt(false)}>
            <CloseIcon fontSize="small" />
          </IconButton>
        </DialogTitle>
        <DialogContent dividers>
          <Viewer content={selected?.prompt_md || ''} contentType="text/markdown" height={'60vh'} />
        </DialogContent>
        <DialogActions>
          <Tooltip title="Copy Prompt">
            <span>
              <IconButton size="small" disabled={!selected} onClick={() => {
                try { navigator.clipboard.writeText(selected?.prompt_md || ''); setCopied(true); } catch { setCopied(true); }
              }}>
                <ContentCopyIcon fontSize="small" />
              </IconButton>
            </span>
          </Tooltip>
          <Tooltip title="Close">
            <IconButton size="small" onClick={() => setOpenPrompt(false)}>
              <CloseIcon fontSize="small" />
            </IconButton>
          </Tooltip>
        </DialogActions>
      </Dialog>

      <Snackbar open={copied} autoHideDuration={2000} onClose={() => setCopied(false)} message="Copied prompt" anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }} />
    </Grid>
  );
}

