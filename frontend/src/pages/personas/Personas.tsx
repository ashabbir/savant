import React, { useEffect, useMemo, useState } from 'react';
import Grid from '@mui/material/Unstable_Grid2';
import Paper from '@mui/material/Paper';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import LinearProgress from '@mui/material/LinearProgress';
import Alert from '@mui/material/Alert';
import TextField from '@mui/material/TextField';
import List from '@mui/material/List';
import ListItem from '@mui/material/ListItem';
import ListItemButton from '@mui/material/ListItemButton';
import ListItemText from '@mui/material/ListItemText';
import Chip from '@mui/material/Chip';
import Stack from '@mui/material/Stack';
import Tabs from '@mui/material/Tabs';
import Tab from '@mui/material/Tab';
import IconButton from '@mui/material/IconButton';
import Tooltip from '@mui/material/Tooltip';
import DescriptionIcon from '@mui/icons-material/Description';
import AddCircleIcon from '@mui/icons-material/AddCircle';
import EditIcon from '@mui/icons-material/Edit';
import DeleteOutlineIcon from '@mui/icons-material/DeleteOutline';
import ContentCopyIcon from '@mui/icons-material/ContentCopy';
import ArticleIcon from '@mui/icons-material/Article';
import CloseIcon from '@mui/icons-material/Close';
import yaml from 'js-yaml';
import Button from '@mui/material/Button';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import DialogActions from '@mui/material/DialogActions';
import Snackbar from '@mui/material/Snackbar';
import Viewer from '../../components/Viewer';
import { getErrorMessage, usePersona, usePersonas, personasDelete } from '../../api';
import { useNavigate } from 'react-router-dom';

const PANEL_HEIGHT = 'calc(100vh - 260px)';

export default function Personas() {
  const displayVersion = (v: any): string => {
    if (typeof v === 'number') return String(v);
    const s = String(v || '').trim();
    const m = s.match(/(\d+)/);
    return m ? m[1] : s;
  };
  const nav = useNavigate();
  const [filter, setFilter] = useState('');
  const { data, isLoading, isError, error } = usePersonas(filter);
  const [sel, setSel] = useState<string | null>(null);
  const details = usePersona(sel);
  const [openPrompt, setOpenPrompt] = useState(false);
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [subTab, setSubTab] = useState(0);
  const [copied, setCopied] = useState(false);

  const personas = data?.personas || [];
  const selected = details.data || null;
  const yamlText = useMemo(() => {
    if (!selected) return '# Select a persona to view details as YAML';
    const obj: any = { ...selected };
    return yaml.dump(obj, { lineWidth: 100 });
  }, [selected]);

  // Auto-select first persona when list loads or filter changes
  useEffect(() => {
    if (!sel && personas.length > 0) {
      setSel(personas[0].name);
    }
  }, [personas, sel]);

  return (
    <Grid container spacing={2}>
      <Grid xs={12} md={4}>
        <Paper sx={{ p: 1, height: PANEL_HEIGHT, display: 'flex', flexDirection: 'column' }}>
          <Box display="flex" alignItems="center" justifyContent="space-between" sx={{ mb: 1 }}>
            <Typography variant="subtitle1" sx={{ fontSize: 12 }}>Personas</Typography>
            <Stack direction="row" spacing={1} alignItems="center">
              <Tooltip title="New Persona">
                <IconButton size="small" color="primary" onClick={() => nav('/engines/personas/new')}>
                  <AddCircleIcon fontSize="small" />
                </IconButton>
              </Tooltip>
              <Tooltip title={sel ? 'Edit Persona' : 'Select a persona'}>
                <span>
                  <IconButton size="small" color="primary" disabled={!sel} onClick={() => sel && nav(`/engines/personas/edit/${sel}`)}>
                    <EditIcon fontSize="small" />
                  </IconButton>
                </span>
              </Tooltip>
              <Tooltip title={sel ? 'Delete Persona' : 'Select a persona'}>
                <span>
                  <IconButton size="small" color="error" disabled={!sel} onClick={() => setConfirmOpen(true)}>
                    <DeleteOutlineIcon fontSize="small" />
                  </IconButton>
                </span>
              </Tooltip>
            </Stack>
          </Box>
          {isLoading && <LinearProgress />}
          {isError && <Alert severity="error">{getErrorMessage(error as any)}</Alert>}
          <TextField
            size="small"
            fullWidth
            placeholder="Search personas..."
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            sx={{ mb: 1 }}
          />
          <List dense sx={{ flex: 1, overflowY: 'auto' }}>
            {personas.map((p) => (
              <ListItem key={p.name} disablePadding>
                <ListItemButton selected={sel === p.name} onClick={() => setSel(p.name)}>
                  <ListItemText
                    primary={
                      <Box display="flex" alignItems="center" gap={1}>
                        <Typography component="span" sx={{ fontWeight: 600 }}>{p.name}</Typography>
                        <Chip size="small" label={`v${displayVersion(p.version)}`} />
                      </Box>
                    }
                    secondary={p.summary}
                  />
                </ListItemButton>
              </ListItem>
            ))}
          </List>
        </Paper>
      </Grid>
      <Grid xs={12} md={8}>
        <Stack spacing={2}>
          <Paper sx={{ p: 2, height: PANEL_HEIGHT, display: 'flex', flexDirection: 'column' }}>
            <Stack direction="row" spacing={2} alignItems="center" justifyContent="space-between">
              <Stack spacing={0.5}>
                <Typography variant="subtitle1" sx={{ fontSize: 12 }}>Persona Details</Typography>
                {selected && (
                  <Stack direction="row" spacing={1} alignItems="center">
                    <Chip size="small" label={`ID: ${selected.name}`}/>
                    <Chip size="small" color="primary" label={`v${displayVersion(selected.version)}`}/>
                  </Stack>
                )}
              </Stack>
              <Stack direction="row" alignItems="center" spacing={1}>
                <Tooltip title={selected ? 'View Prompt (Markdown)' : 'Select a persona'}>
                  <span>
                    <IconButton size="small" color="primary" disabled={!selected} onClick={() => setOpenPrompt(true)}>
                      <DescriptionIcon fontSize="small" />
                    </IconButton>
                  </span>
                </Tooltip>
                <Tooltip title={selected ? 'Copy YAML' : 'Select a persona'}>
                  <span>
                    <IconButton
                      size="small"
                      disabled={!selected}
                      onClick={() => { try { navigator.clipboard.writeText(yamlText); } catch {} }}
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
            {details.isFetching && <LinearProgress />}
            {details.isError && <Alert severity="error">{getErrorMessage(details.error as any)}</Alert>}
            {subTab === 0 && (
              <Box sx={{ flex: 1, minHeight: 0 }}>
                <Viewer content={yamlText} contentType="text/yaml" height={'100%'} />
              </Box>
            )}
          </Paper>

          <Dialog open={openPrompt} onClose={() => setOpenPrompt(false)} fullWidth maxWidth="md">
            <DialogTitle sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                <span>Prompt Markdown</span>
                {selected && (
                  <Stack direction="row" spacing={1} alignItems="center">
                    <Chip size="small" label={`ID: ${selected.name}`}/>
                    <Chip size="small" color="primary" label={`v${displayVersion(selected.version)}`}/>
                  </Stack>
                )}
              </Box>
              <IconButton size="small" onClick={() => setOpenPrompt(false)}>
                <CloseIcon fontSize="small" />
              </IconButton>
            </DialogTitle>
            <DialogContent dividers>
              <Viewer content={selected?.prompt_md || 'Select a persona to view prompt markdown'} contentType="text/markdown" height={'60vh'} />
            </DialogContent>
            <DialogActions>
              <Tooltip title={selected ? 'Copy Prompt' : ''}>
                <span>
                  <IconButton size="small" disabled={!selected} onClick={() => { try { navigator.clipboard.writeText(selected?.prompt_md || ''); setCopied(true); } catch { setCopied(true); } }}>
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
          <Dialog open={confirmOpen} onClose={() => setConfirmOpen(false)}>
            <DialogTitle sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
              Delete Persona
              <IconButton size="small" onClick={() => setConfirmOpen(false)}>
                <CloseIcon fontSize="small" />
              </IconButton>
            </DialogTitle>
            <DialogContent dividers>
              Are you sure you want to delete "{sel}"?
            </DialogContent>
            <DialogActions>
              <Button onClick={() => setConfirmOpen(false)}>Cancel</Button>
              <Button color="error" disabled={!sel || busy} onClick={async () => {
                if (!sel) return;
                try {
                  setBusy(true);
                  await personasDelete(sel);
                  setConfirmOpen(false);
                  setSel(null);
                } finally {
                  setBusy(false);
                }
              }}>Delete</Button>
            </DialogActions>
          </Dialog>
          <Snackbar open={copied} autoHideDuration={2000} onClose={() => setCopied(false)} message="Copied prompt" anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }} />
        </Stack>
      </Grid>
    </Grid>
  );
}
