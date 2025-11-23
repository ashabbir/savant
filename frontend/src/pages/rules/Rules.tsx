import React, { useMemo, useState } from 'react';
import Grid from '@mui/material/Grid2';
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
import Snackbar from '@mui/material/Snackbar';
import yaml from 'js-yaml';
import Viewer from '../../components/Viewer';
import { getErrorMessage, useRule, useRules } from '../../api';

export default function Rules() {
  const [filter, setFilter] = useState('');
  const { data, isLoading, isError, error } = useRules(filter);
  const [sel, setSel] = useState<string | null>(null);
  const details = useRule(sel);
  const [openDialog, setOpenDialog] = useState(false);
  const [copied, setCopied] = useState(false);

  const rows = data?.rules || [];
  const selected = details.data || null;
  const yamlText = useMemo(() => {
    if (!selected) return '# Select a ruleset to view details as YAML';
    const obj: any = { ...selected };
    return yaml.dump(obj, { lineWidth: 100 });
  }, [selected]);

  return (
    <Grid container spacing={2}>
      <Grid size={{ xs: 12, md: 4 }}>
        <Paper sx={{ p: 2 }}>
          <Typography variant="subtitle1" sx={{ mb: 1, fontSize: 12 }}>Rules</Typography>
          <TextField
            fullWidth
            placeholder="Filter by name, title, tags..."
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            sx={{ mb: 1.5 }}
          />
          {isLoading && <LinearProgress />}
          {isError && <Alert severity="error">{getErrorMessage(error as any)}</Alert>}
          <List dense>
            {rows.map((r) => (
              <ListItem key={r.name} disablePadding>
                <ListItemButton selected={sel === r.name} onClick={() => setSel(r.name)}>
                  <ListItemText
                    primary={<Box display="flex" alignItems="center" gap={1}><strong>{r.title}</strong><Chip size="small" label={r.version} /></Box>}
                    secondary={r.summary}
                  />
                </ListItemButton>
              </ListItem>
            ))}
          </List>
        </Paper>
      </Grid>
      <Grid size={{ xs: 12, md: 8 }}>
        <Stack spacing={2}>
          <Paper sx={{ p: 2 }}>
            <Stack direction="row" alignItems="center" justifyContent="space-between">
              <Typography variant="subtitle1" sx={{ fontSize: 12 }}>Ruleset {selected ? `(${selected.title})` : ''}</Typography>
              <Stack direction="row" spacing={1} alignItems="center">
                <Tooltip title={selected ? 'View Rules Markdown' : 'Select a ruleset'}>
                  <span>
                    <Button size="small" variant="outlined" disabled={!selected} onClick={() => setOpenDialog(true)}>
                      View Rules
                    </Button>
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
            <Viewer content={yamlText} contentType="text/yaml" height={360} />
          </Paper>

          <Dialog open={openDialog} onClose={() => setOpenDialog(false)} fullWidth maxWidth="md">
            <DialogTitle>
              Rules (Markdown) {selected ? `(${selected.title})` : ''}
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
              <Button onClick={() => setOpenDialog(false)}>Close</Button>
            </DialogActions>
          </Dialog>
          <Snackbar open={copied} autoHideDuration={2000} onClose={() => setCopied(false)} message="Copied" anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }} />
        </Stack>
      </Grid>
    </Grid>
  );
}

