import React, { useState } from 'react';
import { useThinkPrompts, useThinkPrompt } from '../../api';
import Box from '@mui/material/Box';
import Stack from '@mui/material/Stack';
import Grid from '@mui/material/Grid2';
import Paper from '@mui/material/Paper';
import List from '@mui/material/List';
import ListItem from '@mui/material/ListItem';
import ListItemButton from '@mui/material/ListItemButton';
import ListItemText from '@mui/material/ListItemText';
import Typography from '@mui/material/Typography';
import LinearProgress from '@mui/material/LinearProgress';
import Alert from '@mui/material/Alert';
import IconButton from '@mui/material/IconButton';
import Tooltip from '@mui/material/Tooltip';
import Snackbar from '@mui/material/Snackbar';
import ContentCopyIcon from '@mui/icons-material/ContentCopy';
import { getErrorMessage } from '../../api';
import Viewer from '../../components/Viewer';

export default function ThinkPrompts() {
  const { data, isLoading, isError, error } = useThinkPrompts();
  const [sel, setSel] = useState<string | null>(null);
  const pr = useThinkPrompt(sel);
  const [copied, setCopied] = useState(false);

  return (
    <Grid container spacing={2}>
      <Grid size={{ xs: 12, md: 4 }}>
        <Paper sx={{ p: 1 }}>
          <Typography variant="subtitle1" sx={{ px: 1, py: 1 }}>Prompts</Typography>
          {isLoading && <LinearProgress />}
          {isError && <Alert severity="error">{getErrorMessage(error as any)}</Alert>}
          <List dense>
            {(data?.versions || []).map(v => (
              <ListItem key={v.version} disablePadding>
                <ListItemButton selected={sel === v.version} onClick={() => setSel(v.version)}>
                  <ListItemText primary={v.version} secondary={v.path} />
                </ListItemButton>
              </ListItem>
            ))}
          </List>
        </Paper>
      </Grid>
      <Grid size={{ xs: 12, md: 8 }}>
        <Paper sx={{ p: 2 }}>
          <Stack direction="row" spacing={2} alignItems="center" justifyContent="space-between">
            <Typography variant="subtitle1" sx={{ fontSize: 12 }}>Prompt Markdown {sel ? `(${sel})` : ''}</Typography>
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
          <Viewer content={pr.data?.prompt_md || 'Select a prompt version to view markdown'} contentType="text/markdown" height={420} />
        </Paper>
        <Snackbar open={copied} autoHideDuration={2000} onClose={() => setCopied(false)} message="Copied prompt" anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }} />
      </Grid>
    </Grid>
  );
}
