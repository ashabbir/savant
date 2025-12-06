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
import Button from '@mui/material/Button';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import DialogActions from '@mui/material/DialogActions';
import Tooltip from '@mui/material/Tooltip';
import IconButton from '@mui/material/IconButton';
import ContentCopyIcon from '@mui/icons-material/ContentCopy';
import CloseIcon from '@mui/icons-material/Close';
import DescriptionIcon from '@mui/icons-material/Description';
import Snackbar from '@mui/material/Snackbar';
import yaml from 'js-yaml';
import Viewer from '../../components/Viewer';
import { getErrorMessage, useRule, useRules, rulesDelete, useThinkWorkflows } from '../../api';
import AddCircleIcon from '@mui/icons-material/AddCircle';
import EditIcon from '@mui/icons-material/Edit';
import DeleteOutlineIcon from '@mui/icons-material/DeleteOutline';
import { useNavigate } from 'react-router-dom';

export default function Rules() {
  const nav = useNavigate();
  const [filter, setFilter] = useState('');
  const { data, isLoading, isError, error, refetch } = useRules(filter) as any;
  const [sel, setSel] = useState<string | null>(null);
  const details = useRule(sel);
  const thinkWorkflows = useThinkWorkflows();
  const [openDialog, setOpenDialog] = useState(false);
  const [copied, setCopied] = useState(false);
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [busy, setBusy] = useState(false);

  const rows = data?.rules || [];
  const selected = details.data || null;
  const workflows = thinkWorkflows.data?.workflows || [];
  const ruleUsageMap = useMemo(() => {
    const map = new Map<string, { id: string; label: string }[]>();
    workflows.forEach((wf) => {
      const rules = Array.isArray(wf.rules) ? wf.rules : [];
      rules.forEach((rule) => {
        if (!map.has(rule)) map.set(rule, []);
        map.get(rule)!.push({ id: wf.id, label: wf.name || wf.id });
      });
    });
    return map;
  }, [workflows]);
  const selectedUsage = selected ? ruleUsageMap.get(selected.name) || [] : [];
  const deleteDisabled = !selected || selectedUsage.length > 0;
  const yamlText = useMemo(() => {
    if (!selected) return '# Select a ruleset to view details as YAML';
    const obj: any = { ...selected };
    return yaml.dump(obj, { lineWidth: 100 });
  }, [selected]);

  // Auto-select first ruleset when list loads or filter changes
  useEffect(() => {
    if (!sel && rows.length > 0) {
      setSel(rows[0].name);
    }
  }, [rows, sel]);

  return (
    <Grid container spacing={2}>
      <Grid xs={12} md={4}>
        <Paper sx={{ p: 1, height: 'calc(100vh - 260px)', display: 'flex', flexDirection: 'column' }}>
          <Stack direction="row" alignItems="center" justifyContent="space-between" sx={{ mb: 1 }}>
            <Typography variant="subtitle1" sx={{ fontSize: 12 }}>Rules</Typography>
            <Stack direction="row" spacing={1} alignItems="center">
              <Tooltip title="New Rule">
                <IconButton size="small" color="primary" onClick={() => nav('/engines/rules/new')}>
                  <AddCircleIcon fontSize="small" />
                </IconButton>
              </Tooltip>
              <Tooltip title={sel ? 'Edit Rule' : 'Select a ruleset'}>
                <span>
                  <IconButton size="small" color="primary" disabled={!sel} onClick={() => sel && nav(`/engines/rules/edit/${sel}`)}>
                    <EditIcon fontSize="small" />
                  </IconButton>
                </span>
              </Tooltip>
              <Tooltip title={!sel ? 'Select a ruleset' : selectedUsage.length ? `Used by ${selectedUsage.length} workflow${selectedUsage.length === 1 ? '' : 's'}` : 'Delete Rule'}>
                <span>
                  <IconButton size="small" color="error" disabled={deleteDisabled} onClick={() => setConfirmOpen(true)}>
                    <DeleteOutlineIcon fontSize="small" />
                  </IconButton>
                </span>
              </Tooltip>
            </Stack>
          </Stack>
          {isLoading && <LinearProgress />}
          {isError && <Alert severity="error">{getErrorMessage(error as any)}</Alert>}
          <TextField id="rules-filter" name="rulesFilter"
            fullWidth
            size="small"
            placeholder="Search rules..."
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            sx={{ mb: 1 }}
          />
          <List dense sx={{ flex: 1, overflowY: 'auto' }}>
            {rows.map((r) => (
              <ListItem key={r.name} disablePadding>
                <ListItemButton selected={sel === r.name} onClick={() => setSel(r.name)} onDoubleClick={() => nav(`/engines/rules/edit/${r.name}`)}>
                  <ListItemText
                    primary={
                      <Box display="flex" alignItems="center" gap={1}>
                        <Typography component="span" sx={{ fontWeight: 600 }}>{r.name}</Typography>
                        <Chip size="small" label={`v${String(r.version)}`} />
                      </Box>
                    }
                    secondary={r.summary}
                  />
                </ListItemButton>
              </ListItem>
            ))}
          </List>
        </Paper>
      </Grid>
      <Grid xs={12} md={8}>
        <Paper sx={{ p: 2, height: 'calc(100vh - 260px)', display: 'flex', flexDirection: 'column' }}>
            <Stack direction="row" alignItems="center" justifyContent="space-between">
              <Stack spacing={0.5}>
                <Typography variant="subtitle1" sx={{ fontSize: 12 }}>Ruleset Details</Typography>
                {selected && (
                  <Stack direction="row" spacing={1} alignItems="center">
                    <Chip size="small" label={`ID: ${selected.name}`}/>
                    <Chip size="small" color="primary" label={`v${selected.version}`}/>
                  </Stack>
                )}
                {selected && (
                  <Box>
                    <Typography variant="caption" sx={{ fontWeight: 600 }}>Used by</Typography>
                    {thinkWorkflows.isLoading && <Typography variant="caption" sx={{ ml: 1 }}>Loading…</Typography>}
                    {!thinkWorkflows.isLoading && (
                      selectedUsage.length > 0 ? (
                        <Stack direction="row" spacing={1} sx={{ mt: 0.5, flexWrap: 'wrap' }}>
                          {selectedUsage.map((wf) => (
                            <Chip
                              key={wf.id}
                              size="small"
                              label={wf.label}
                              onClick={() => nav(`/engines/think/workflows/edit/${wf.id}`)}
                              clickable
                              sx={{ mb: 0.5 }}
                            />
                          ))}
                        </Stack>
                      ) : (
                        <Typography variant="caption" sx={{ display: 'block', mt: 0.5 }}>No workflows reference this rule.</Typography>
                      )
                    )}
                  </Box>
                )}
              </Stack>
              <Stack direction="row" spacing={1} alignItems="center">
                <Tooltip title={selected ? 'View Rules Markdown' : 'Select a ruleset'}>
                  <span>
                    <IconButton size="small" color="primary" disabled={!selected} onClick={() => setOpenDialog(true)}>
                      <DescriptionIcon fontSize="small" />
                    </IconButton>
                  </span>
                </Tooltip>
                <Tooltip title={selected ? 'Copy YAML' : 'Select a ruleset'}>
                  <span>
                    <IconButton size="small" disabled={!selected} onClick={() => { try { navigator.clipboard.writeText(yamlText); setCopied(true); } catch { setCopied(true); } }}>
                      <ContentCopyIcon fontSize="small" />
                    </IconButton>
                  </span>
                </Tooltip>
              </Stack>
            </Stack>
            {details.isFetching && <LinearProgress />}
            {details.isError && <Alert severity="error">{getErrorMessage(details.error as any)}</Alert>}
            <Box sx={{ flex: 1, minHeight: 0 }}>
              <Viewer content={yamlText} contentType="text/yaml" height={'100%'} />
            </Box>
          </Paper>

          <Dialog open={openDialog} onClose={() => setOpenDialog(false)} fullWidth maxWidth="md">
            <DialogTitle sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
              Rules (Markdown) {selected ? `(${selected.name})` : ''}
              <IconButton size="small" onClick={() => setOpenDialog(false)}>
                <CloseIcon fontSize="small" />
              </IconButton>
            </DialogTitle>
            <DialogContent dividers>
              <Viewer content={selected?.rules_md || 'Select a ruleset to view markdown'} contentType="text/markdown" height={'60vh'} />
            </DialogContent>
            <DialogActions>
              <Tooltip title={selected ? 'Copy Rules' : ''}>
                <span>
                  <IconButton size="small" disabled={!selected} onClick={() => { try { navigator.clipboard.writeText(selected?.rules_md || ''); setCopied(true); } catch { setCopied(true); } }}>
                    <ContentCopyIcon fontSize="small" />
                  </IconButton>
                </span>
              </Tooltip>
              <Tooltip title="Close">
                <IconButton size="small" onClick={() => setOpenDialog(false)}>
                  <CloseIcon fontSize="small" />
                </IconButton>
              </Tooltip>
            </DialogActions>
          </Dialog>
          <Snackbar open={copied} autoHideDuration={2000} onClose={() => setCopied(false)} message="Copied" anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }} />
          <Dialog open={confirmOpen} onClose={() => setConfirmOpen(false)}>
            <DialogTitle sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
              Delete rule
              <IconButton size="small" onClick={() => setConfirmOpen(false)}>
                <CloseIcon fontSize="small" />
              </IconButton>
            </DialogTitle>
            <DialogContent>
              {selectedUsage.length > 0 ? (
                `Cannot delete "${selected?.name}" because it is used by ${selectedUsage.length} workflow${selectedUsage.length === 1 ? '' : 's'}.`
              ) : (
                <>Are you sure you want to delete "{selected?.name}"?</>
              )}
            </DialogContent>
            <DialogActions>
              <Button onClick={() => setConfirmOpen(false)}>Cancel</Button>
              <Button color="error" disabled={!selected || busy || selectedUsage.length > 0} onClick={async () => {
                if (!selected) return;
                try {
                  setBusy(true);
                  await rulesDelete(selected.name);
                  setConfirmOpen(false);
                  setSel(null);
                  await refetch?.();
                } finally {
                  setBusy(false);
                }
              }}>Delete</Button>
            </DialogActions>
          </Dialog>
      </Grid>
    </Grid>
  );
}
