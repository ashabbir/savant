import React from 'react';
import Grid from '@mui/material/Unstable_Grid2';
import { Alert, Autocomplete, Box, Button, Chip, IconButton, LinearProgress, Paper, Snackbar, Stack, TextField, Tooltip, Typography, Dialog, DialogTitle, DialogContent, DialogActions } from '@mui/material';
import SaveIcon from '@mui/icons-material/Save';
import ArrowBackIcon from '@mui/icons-material/ArrowBack';
import DeleteOutlineIcon from '@mui/icons-material/DeleteOutline';
import ContentCopyIcon from '@mui/icons-material/ContentCopy';
import VisibilityIcon from '@mui/icons-material/Visibility';
import CloseIcon from '@mui/icons-material/Close';
import { useNavigate, useParams } from 'react-router-dom';
import { Persona, usePersona, usePersonas, usePersonasCreate, usePersonasDelete, usePersonasUpdate } from '../../api';
import Viewer from '../../components/Viewer';

function generateIdFromName(name: string): string {
  let s = (name || '').toLowerCase();
  try { s = s.normalize('NFKD').replace(/[\u0300-\u036f]/g, ''); } catch {}
  s = s.replace(/[^a-z0-9]+/g, '_');
  s = s.replace(/_+/g, '_');
  s = s.replace(/^_+|_+$/g, '');
  return s;
}

const PANEL_HEIGHT = 'calc(100vh - 260px)';

export default function PersonaEditor() {
  const { name: routeName } = useParams();
  const isNew = !routeName;
  const nav = useNavigate();
  const list = usePersonas('');
  const details = usePersona(isNew ? null : routeName || null);
  const create = usePersonasCreate();
  const update = usePersonasUpdate();
  const del = usePersonasDelete();

  const [name, setName] = React.useState(routeName || '');
  const [summary, setSummary] = React.useState('');
  const [tags, setTags] = React.useState<string[]>([]);
  const [notes, setNotes] = React.useState('');
  const [promptMd, setPromptMd] = React.useState('');
  const [snack, setSnack] = React.useState<string | null>(null);
  const [confirmOpen, setConfirmOpen] = React.useState(false);
  const [previewOpen, setPreviewOpen] = React.useState(false);

  React.useEffect(() => {
    if (isNew) return;
    const d = details.data as Persona | undefined;
    if (!d) return;
    setSummary(d.summary || '');
    setTags(d.tags || []);
    setNotes(d.notes || '');
    setPromptMd(d.prompt_md || '');
  }, [isNew, details.data?.name]);

  // Personas use `name` as the backend key; on create, derive id from typed name like Rules
  const existingSlugs = React.useMemo(() => new Set((list.data?.personas || []).map(p => p.name)), [list.data?.personas]);

  const targetId = React.useMemo(() => (isNew ? generateIdFromName(name) : (routeName || name || '')), [isNew, name, routeName]);

  const canSave = React.useMemo(() => {
    const slug = targetId;
    if (!slug || !summary.trim() || !promptMd.trim()) return false;
    if (isNew && existingSlugs.has(slug)) return false;
    return true;
  }, [targetId, summary, promptMd, isNew, existingSlugs]);

  const onSave = async () => {
    if (!canSave) return;
    const slug = targetId;
    const payload = { name: slug, summary: summary.trim(), prompt_md: promptMd, tags, notes } as any;
    if (isNew) await create.mutateAsync(payload);
    else await update.mutateAsync(payload);
    setSnack('Saved');
    // small delay to surface the green toaster before navigation
    setTimeout(() => nav('/engines/personas'), 700);
  };

  const onDelete = async () => {
    if (!routeName) return;
    await del.mutateAsync(routeName);
    setSnack('Deleted');
    setConfirmOpen(false);
    nav('/engines/personas');
  };

  return (
    <Grid container spacing={2}>
      <Grid xs={12} md={4}>
        <Paper sx={{ p: 1, height: PANEL_HEIGHT, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
          <Stack direction="row" alignItems="center" justifyContent="space-between">
            <Typography variant="subtitle1" sx={{ fontSize: 12 }}>{isNew ? 'Create Persona' : `Edit Persona (${routeName})`}{!isNew && (details.data as any)?.version ? ` • v${(details.data as any).version}` : ''}</Typography>
            <Stack direction="row" spacing={1}>
              {!isNew && (
                <Tooltip title="Delete">
                  <span>
                    <IconButton onClick={() => setConfirmOpen(true)} color="error">
                      <DeleteOutlineIcon fontSize="small" />
                    </IconButton>
                  </span>
                </Tooltip>
              )}
              <Tooltip title="Back to personas">
                <IconButton onClick={() => nav('/engines/personas')}>
                  <ArrowBackIcon fontSize="small" />
                </IconButton>
              </Tooltip>
            </Stack>
          </Stack>
          {(details.isFetching || list.isFetching) && <LinearProgress />}
          {details.isError && <Alert severity="error">{(details.error as any)?.message || 'Failed to load'}</Alert>}
          <Box sx={{ flex: 1, overflowY: 'auto', pr: 1, mt: 1 }}>
            <Stack spacing={1.2}>
              <TextField
                label="name"
                value={name}
                onChange={(e)=>setName(e.target.value)}
                disabled={!isNew}
                helperText={(() => {
                  const slug = generateIdFromName(name);
                  if (!isNew) return ' ';
                  if (!slug) return 'Enter a name to generate id';
                  if (existingSlugs.has(slug)) return 'A persona with this id already exists';
                  return `id will be: ${slug}`;
                })()}
              />
              <TextField label="summary" value={summary} onChange={(e)=>setSummary(e.target.value)} multiline minRows={2} />
              <Autocomplete
                multiple
                freeSolo
                options={(list.data?.personas || []).map(p=>p.name)}
                isOptionEqualToValue={(option, value) => option === value}
                value={tags}
                onChange={(_e, v)=> setTags(v as string[])}
                renderTags={(value: readonly string[], getTagProps) =>
                  value.map((option: string, index: number) => (
                    <Chip variant="outlined" label={option} {...getTagProps({ index })} />
                  ))
                }
                renderInput={(params) => (
                  <TextField {...params} label="tags" placeholder="Add tag" />
                )}
              />
              <TextField label="notes" value={notes} onChange={(e)=>setNotes(e.target.value)} multiline minRows={2} />
            </Stack>
          </Box>
        </Paper>
      </Grid>
      <Grid xs={12} md={8}>
        <Paper sx={{ p: 1, height: PANEL_HEIGHT, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
          <Stack direction="row" alignItems="center" justifyContent="space-between" sx={{ mb: 1 }}>
            <Typography variant="subtitle1" sx={{ fontSize: 12 }}>Prompt Markdown</Typography>
            <Stack direction="row" spacing={1}>
              <Tooltip title="Copy">
                <IconButton onClick={() => { try { navigator.clipboard.writeText(promptMd); setSnack('Copied'); } catch { setSnack('Copied'); } }}>
                  <ContentCopyIcon fontSize="small" />
                </IconButton>
              </Tooltip>
              <Tooltip title="Preview">
                <IconButton onClick={() => setPreviewOpen(true)}>
                  <VisibilityIcon fontSize="small" />
                </IconButton>
              </Tooltip>
              <Tooltip title={canSave ? 'Save' : 'Fill required fields'}>
                <span>
                  <IconButton onClick={onSave} disabled={!canSave} color="primary">
                    <SaveIcon fontSize="small" />
                  </IconButton>
                </span>
              </Tooltip>
            </Stack>
          </Stack>
          <Box sx={{ flex: 1, minHeight: 0, width: '100%', overflow: 'auto', pt: 1 }}>
            <TextField label="prompt_md" value={promptMd} onChange={(e)=>setPromptMd(e.target.value)} multiline minRows={16} fullWidth />
          </Box>
        </Paper>
      </Grid>
      <Dialog open={confirmOpen} onClose={() => setConfirmOpen(false)}>
        <DialogTitle sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          Delete persona
          <IconButton size="small" onClick={() => setConfirmOpen(false)}>
            <CloseIcon fontSize="small" />
          </IconButton>
        </DialogTitle>
        <DialogContent>Are you sure you want to delete "{routeName}"?</DialogContent>
        <DialogActions>
          <Button onClick={() => setConfirmOpen(false)}>Cancel</Button>
          <Button color="error" onClick={onDelete}>Delete</Button>
        </DialogActions>
      </Dialog>
      <Dialog open={previewOpen} onClose={() => setPreviewOpen(false)} fullWidth maxWidth="md">
        <DialogTitle sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          Prompt Markdown Preview
          <IconButton size="small" onClick={() => setPreviewOpen(false)}>
            <CloseIcon fontSize="small" />
          </IconButton>
        </DialogTitle>
        <DialogContent dividers>
          <Viewer content={promptMd || ''} contentType="text/markdown" height={420} />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setPreviewOpen(false)}>Close</Button>
        </DialogActions>
      </Dialog>
      <Snackbar open={!!snack} autoHideDuration={2000} onClose={() => setSnack(null)} anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }}>
        <Alert onClose={() => setSnack(null)} severity={snack === 'Saved' ? 'success' : 'info'} sx={{ width: '100%' }}>
          {snack}
        </Alert>
      </Snackbar>
    </Grid>
  );
}
