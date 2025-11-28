import React from 'react';
import Grid from '@mui/material/Grid2';
import { Alert, Box, Button, Chip, IconButton, LinearProgress, Paper, Snackbar, Stack, TextField, Tooltip, Typography, Autocomplete, Dialog, DialogTitle, DialogContent, DialogActions } from '@mui/material';
import VisibilityIcon from '@mui/icons-material/Visibility';
import SaveIcon from '@mui/icons-material/Save';
import ArrowBackIcon from '@mui/icons-material/ArrowBack';
import DeleteOutlineIcon from '@mui/icons-material/DeleteOutline';
import ContentCopyIcon from '@mui/icons-material/ContentCopy';
import CloseIcon from '@mui/icons-material/Close';
import { useNavigate, useParams } from 'react-router-dom';
import { Rule, useRule, useRules, useRulesCreate, useRulesDelete, useRulesUpdate } from '../../api';
import Viewer from '../../components/Viewer';

const PANEL_HEIGHT = 'calc(100vh - 260px)';

function generateIdFromName(name: string): string {
  let s = (name || '').toLowerCase();
  s = s.normalize('NFKD').replace(/[\u0300-\u036f]/g, '');
  s = s.replace(/[^a-z0-9]+/g, '_');
  s = s.replace(/_+/g, '_');
  s = s.replace(/^_+|_+$/g, '');
  return s;
}

export default function RuleEditor() {
  const { name: routeName } = useParams();
  const isNew = !routeName;
  const nav = useNavigate();
  const list = useRules('');
  const details = useRule(isNew ? null : routeName || null);
  const create = useRulesCreate();
  const update = useRulesUpdate();
  const del = useRulesDelete();

  const [name, setName] = React.useState(routeName || '');
  // version is managed by backend (starts at 1, bumps on save)
  const [summary, setSummary] = React.useState('');
  const [tags, setTags] = React.useState<string[]>([]);
  const [notes, setNotes] = React.useState('');
  const [rulesMd, setRulesMd] = React.useState('');
  const [snack, setSnack] = React.useState<string | null>(null);
  const [confirmOpen, setConfirmOpen] = React.useState(false);
  const [previewOpen, setPreviewOpen] = React.useState(false);

  React.useEffect(() => {
    if (isNew) return;
    const d = details.data as Rule | undefined;
    if (!d) return;
    // version is read-only; shown in header via details.data
    setSummary(d.summary || '');
    setTags(d.tags || []);
    setNotes(d.notes || '');
    setRulesMd(d.rules_md || '');
  }, [isNew, details.data?.name]);

  React.useEffect(() => {
    // keep name as user-entered label; id is generated on backend
  }, [name]);

  const existingIds = React.useMemo(() => new Set((list.data?.rules || []).map(r => (r as any).id || generateIdFromName(r.name))), [list.data?.rules]);

  const canSave = React.useMemo(() => {
    const nm = (name || '').trim();
    const gid = generateIdFromName(nm);
    if (!nm || !gid || !summary.trim() || !rulesMd.trim()) return false;
    if (isNew && existingIds.has(gid)) return false;
    return true;
  }, [name, summary, rulesMd, isNew, existingIds]);

  const onSave = async () => {
    const nm = (name || '').trim();
    if (!canSave) return;
    const payload = { name: nm, summary: summary.trim(), rules_md: rulesMd, tags, notes } as any;
    if (isNew) await create.mutateAsync(payload);
    else await update.mutateAsync({ ...payload, name: routeName! });
    setSnack('Saved');
    // small delay to surface the green toaster before navigation
    setTimeout(() => nav('/engines/rules'), 700);
  };

  const onDelete = async () => {
    if (!routeName) return;
    await del.mutateAsync(routeName);
    setSnack('Deleted');
    setConfirmOpen(false);
    nav('/engines/rules');
  };

  return (
    <Grid container spacing={2}>
      <Grid size={{ xs: 12, md: 4 }}>
        <Paper sx={{ p: 1, height: PANEL_HEIGHT, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
          <Stack direction="row" alignItems="center" justifyContent="space-between">
            <Typography variant="subtitle1" sx={{ fontSize: 12 }}>{isNew ? 'Create Rule' : `Edit Rule (${routeName})`}{!isNew && details.data?.version ? ` • v${details.data.version}` : ''}</Typography>
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
              <Tooltip title="Back to rules">
                <IconButton onClick={() => nav('/engines/rules')}>
                  <ArrowBackIcon fontSize="small" />
                </IconButton>
              </Tooltip>
            </Stack>
          </Stack>
          {(details.isFetching || list.isFetching) && <LinearProgress />}
          {details.isError && <Alert severity="error">{(details.error as any)?.message || 'Failed to load'}</Alert>}
          <Box sx={{ flex: 1, overflowY: 'auto', pr: 1, mt: 1 }}>
            <Stack spacing={1.2}>
              <TextField label="name" value={name} onChange={(e)=>setName(e.target.value)} disabled={!isNew} helperText={isNew && existingIds.has(generateIdFromName(name)) ? 'A rule with this id already exists' : ' '} />
              {/* Version is auto-managed; show read-only in header */}
              <TextField label="summary" value={summary} onChange={(e)=>setSummary(e.target.value)} multiline minRows={2} />
              <Autocomplete
                multiple
                freeSolo
                options={(list.data?.rules || []).map(r=>r.name)}
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
      <Grid size={{ xs: 12, md: 8 }}>
        <Paper sx={{ p: 1, height: PANEL_HEIGHT, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
          <Stack direction="row" alignItems="center" justifyContent="space-between" sx={{ mb: 1 }}>
            <Typography variant="subtitle1" sx={{ fontSize: 12 }}>Rules Markdown</Typography>
            <Stack direction="row" spacing={1}>
              <Tooltip title="Copy">
                <IconButton onClick={() => { try { navigator.clipboard.writeText(rulesMd); setSnack('Copied'); } catch { setSnack('Copied'); } }}>
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
            <TextField label="rules_md" value={rulesMd} onChange={(e)=>setRulesMd(e.target.value)} multiline minRows={16} fullWidth />
          </Box>
        </Paper>
      </Grid>
      <Dialog open={confirmOpen} onClose={() => setConfirmOpen(false)}>
        <DialogTitle sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          Delete rule
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
          Rules Markdown Preview
          <IconButton size="small" onClick={() => setPreviewOpen(false)}>
            <CloseIcon fontSize="small" />
          </IconButton>
        </DialogTitle>
        <DialogContent dividers>
          <Viewer content={rulesMd || ''} contentType="text/markdown" height={420} />
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
