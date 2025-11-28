import React from 'react';
import Grid from '@mui/material/Grid2';
import { Alert, Box, Chip, Dialog, DialogActions, DialogContent, DialogTitle, IconButton, LinearProgress, Paper, Snackbar, Stack, TextField, Tooltip, Typography, Button } from '@mui/material';
import SaveIcon from '@mui/icons-material/Save';
import ArrowBackIcon from '@mui/icons-material/ArrowBack';
import DeleteOutlineIcon from '@mui/icons-material/DeleteOutline';
import ContentCopyIcon from '@mui/icons-material/ContentCopy';
import VisibilityIcon from '@mui/icons-material/Visibility';
import CloseIcon from '@mui/icons-material/Close';
import SaveAltIcon from '@mui/icons-material/SaveAlt';
import { useNavigate, useParams } from 'react-router-dom';
import Viewer from '../../components/Viewer';
import { ThinkPrompts, useThinkPrompt, useThinkPrompts, thinkPromptsCreate, thinkPromptsDelete, thinkPromptsUpdate, useThinkWorkflows } from '../../api';

const PANEL_HEIGHT = 'calc(100vh - 260px)';

export default function PromptEditor() {
  const { version: routeVersion } = useParams();
  const isNew = !routeVersion;
  const nav = useNavigate();
  const list = useThinkPrompts();
  const details = useThinkPrompt(isNew ? null : routeVersion || null);
  const workflows = useThinkWorkflows();

  const [version, setVersion] = React.useState(routeVersion || '');
  const [name, setName] = React.useState('');
  const [promptMd, setPromptMd] = React.useState('');
  const [snack, setSnack] = React.useState<string | null>(null);
  const [confirmOpen, setConfirmOpen] = React.useState(false);
  const [previewOpen, setPreviewOpen] = React.useState(false);

  React.useEffect(() => {
    if (isNew) return;
    const d = details.data;
    if (!d) return;
    setPromptMd(d.prompt_md || '');
  }, [isNew, details.data?.version]);

  const existing = React.useMemo(() => new Set((list.data?.versions || []).map(v => v.version)), [list.data?.versions]);
  // No default version on create; user must enter a valid key
  const nameSlug = React.useMemo(() => (name || '').toLowerCase().trim().replace(/[^a-z0-9_.-]+/g, '_').replace(/^_+|_+$/g, ''), [name]);
  const canSave = React.useMemo(() => {
    if (isNew) {
      const validVersion = /^[a-z]+$/.test(version || '');
      return !!nameSlug && !!promptMd.trim() && validVersion && !existing.has(version || '');
    }
    return !!promptMd.trim();
  }, [nameSlug, promptMd, isNew, version, existing]);

  const onSave = async () => {
    if (!canSave) return;
    if (isNew) {
      const relPath = `prompts/${nameSlug}.md`;
      await thinkPromptsCreate({ version: version, prompt_md: promptMd, path: relPath });
    } else {
      await thinkPromptsUpdate({ version: routeVersion as string, prompt_md: promptMd });
    }
    setSnack('Saved');
    setTimeout(() => nav('/engines/think/prompts'), 700);
  };

  const onDelete = async () => {
    if (!routeVersion) return;
    await thinkPromptsDelete(routeVersion);
    setSnack('Deleted');
    setConfirmOpen(false);
    nav('/engines/think/prompts');
  };

  const resolvedPath = React.useMemo(() => {
    if (isNew) {
      if (!nameSlug) return '';
      return `prompts/${nameSlug}.md`;
    }
    const row = (list.data?.versions || []).find(v => v.version === (routeVersion || ''));
    return row?.path || '';
  }, [nameSlug, isNew, list.data?.versions, routeVersion]);

  // Workflows using this prompt version (edit mode only)
  const usingWorkflows = React.useMemo(() => {
    if (isNew || !routeVersion) return [] as { id: string }[];
    const rows = workflows.data?.workflows || [];
    return rows.filter((w: any) => (w.driver_version || 'stable') === routeVersion) as any[];
  }, [workflows.data?.workflows, isNew, routeVersion]);

  return (
    <Grid container spacing={2}>
      <Grid size={{ xs: 12, md: 4 }}>
        <Paper sx={{ p: 1, height: PANEL_HEIGHT, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
            <Stack direction="row" alignItems="center" justifyContent="space-between">
              <Typography variant="subtitle1" sx={{ fontSize: 12 }}>{isNew ? 'Create Prompt' : `Edit Prompt (${routeVersion})`}</Typography>
            <Stack direction="row" spacing={1}>
              {!isNew && (
                <Tooltip title={usingWorkflows.length > 0 ? 'Cannot delete: prompt in use by workflows' : 'Delete'}>
                  <span>
                    <IconButton onClick={() => setConfirmOpen(true)} color="error" disabled={usingWorkflows.length > 0}>
                      <DeleteOutlineIcon fontSize="small" />
                    </IconButton>
                  </span>
                </Tooltip>
              )}
              <Tooltip title="Back to prompts">
                <IconButton onClick={() => nav('/engines/think/prompts')}>
                  <ArrowBackIcon fontSize="small" />
                </IconButton>
              </Tooltip>
            </Stack>
          </Stack>
          {(details.isFetching || list.isFetching) && <LinearProgress />}
          {details.isError && <Alert severity="error">{(details.error as any)?.message || 'Failed to load'}</Alert>}
          <Box sx={{ flex: 1, overflowY: 'auto', pr: 1, mt: 1 }}>
            <Stack spacing={1.2}>
              {isNew ? (
                <>
                  <TextField
                    label="version"
                    value={version}
                    onChange={(e)=>{ const raw = e.target.value || ''; const cleaned = raw.toLowerCase().replace(/[^a-z]/g, ''); setVersion(cleaned); }}
                    error={!!version && (!/^[a-z]+$/.test(version) || existing.has(version))}
                    helperText={(function(){
                      if (!version) return 'Enter a version (lowercase a-z; e.g., stable)';
                      if (!/^[a-z]+$/.test(version)) return 'Use only lowercase letters a-z (no spaces or symbols)';
                      if (existing.has(version)) return 'A prompt with this version already exists';
                      return ' ';
                    })()}
                  />
                  <TextField
                    label="name"
                    value={name}
                    onChange={(e)=>setName(e.target.value)}
                    helperText={(() => {
                      if (!nameSlug) return 'Enter a name to derive the file path';
                      return `file will be: prompts/${nameSlug}.md`;
                    })()}
                  />
                </>
              ) : (
                <>
                  <Stack direction="row" spacing={1} alignItems="center">
                    <Typography variant="caption" sx={{ fontWeight: 600 }}>version</Typography>
                    <Chip size="small" color="primary" label={routeVersion || '(unknown)'} />
                  </Stack>
                  <Stack direction="row" spacing={1} alignItems="center">
                    <Typography variant="caption" sx={{ fontWeight: 600 }}>file</Typography>
                    <Chip size="small" label={resolvedPath || '(unknown)'} />
                  </Stack>
                </>
              )}
              {!isNew && (
                <Stack spacing={0.5}>
                  <Typography variant="caption" sx={{ fontWeight: 600 }}>Used by</Typography>
                  {usingWorkflows.length === 0 ? (
                    <Typography variant="caption" color="text.secondary">No workflows reference this prompt</Typography>
                  ) : (
                    <Stack direction="row" spacing={1} flexWrap="wrap">
                      {usingWorkflows.map((w: any) => (
                        <Chip key={w.id} label={w.name || w.id} onClick={() => nav(`/engines/think/workflows/edit/${w.id}`)} clickable size="small" />
                      ))}
                    </Stack>
                  )}
                </Stack>
              )}
              <Stack direction="row" spacing={1} alignItems="center">
                {!isNew && <></>}
              </Stack>
            </Stack>
          </Box>
        </Paper>
      </Grid>
      <Grid size={{ xs: 12, md: 8 }}>
        <Paper sx={{ p: 1, height: PANEL_HEIGHT, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
          <Stack direction="row" alignItems="center" justifyContent="space-between" sx={{ mb: 1 }}>
            <Typography variant="subtitle1" sx={{ fontSize: 12 }}>Prompt Markdown</Typography>
            <Stack direction="row" spacing={1}>
              <Tooltip title={routeVersion ? 'Export to file' : 'Save first to enable export'}>
                <span>
                  <IconButton onClick={async ()=>{ if (!routeVersion) return; await thinkPromptsUpdate({ version: routeVersion, prompt_md: promptMd }); setSnack(`Exported to ${resolvedPath}`); }} disabled={!routeVersion} color="primary">
                    <SaveAltIcon fontSize="small" />
                  </IconButton>
                </span>
              </Tooltip>
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
          Delete prompt
          <IconButton size="small" onClick={() => setConfirmOpen(false)}>
            <CloseIcon fontSize="small" />
          </IconButton>
        </DialogTitle>
        <DialogContent>
          {usingWorkflows.length > 0 && (
            <Alert severity="warning" sx={{ mb: 1 }}>
              Cannot delete: this prompt is used by {usingWorkflows.length} workflow{usingWorkflows.length === 1 ? '' : 's'}.
            </Alert>
          )}
          Are you sure you want to delete "{routeVersion}"?
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setConfirmOpen(false)}>Cancel</Button>
          <Button color="error" onClick={onDelete} disabled={!routeVersion || usingWorkflows.length > 0}>Delete</Button>
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
