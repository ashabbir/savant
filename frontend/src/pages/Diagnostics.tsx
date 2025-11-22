import React from 'react';
import { useDiagnostics } from '../api';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import LinearProgress from '@mui/material/LinearProgress';
import Alert from '@mui/material/Alert';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import Chip from '@mui/material/Chip';

export default function Diagnostics() {
  const { data, isLoading, isError, error } = useDiagnostics();

  if (isLoading) return <LinearProgress />;
  if (isError) return <Alert severity="error">{(error as any)?.message || 'Failed to load diagnostics'}</Alert>;

  return (
    <Box>
      <Typography variant="h6" gutterBottom>Diagnostics</Typography>
      <Paper sx={{ p: 2, mb: 2 }}>
        <Stack direction="row" spacing={2}>
          <Chip label={`Base: ${data?.base_path}`} variant="outlined" />
          <Chip label={`Settings: ${data?.settings_path}`} variant="outlined" />
          {data?.config_error && <Chip color="error" label={`Config: ${data?.config_error}`} />}
        </Stack>
      </Paper>

      <Paper sx={{ p: 2, mb: 2 }}>
        <Typography variant="subtitle1" gutterBottom>Mounts</Typography>
        <Stack direction="row" spacing={1}>
          {Object.entries(data?.mounts || {}).map(([k, v]) => (
            <Chip key={k} label={`${k}: ${v ? 'ok' : 'missing'}`} color={v ? 'success' as any : 'warning' as any} variant={v ? 'filled' : 'outlined'} />
          ))}
        </Stack>
      </Paper>

      <Paper sx={{ p: 2, mb: 2 }}>
        <Typography variant="subtitle1" gutterBottom>Database</Typography>
        <Stack direction="row" spacing={2}>
          <Chip label={`Connected: ${data?.db.connected ? 'yes' : 'no'}`} color={data?.db.connected ? 'success' as any : 'error' as any} />
          {data?.db.counts && <Chip label={`repos=${data.db.counts.repos} files=${data.db.counts.files} chunks=${data.db.counts.chunks}`} variant="outlined" />}
          {data?.db.error && <Chip color="error" label={`error: ${data.db.error}`} />}
          {data?.db.counts_error && <Chip color="error" label={`counts: ${data.db.counts_error}`} />}
        </Stack>
      </Paper>

      <Paper sx={{ p: 2 }}>
        <Typography variant="subtitle1" gutterBottom>Repos Visibility</Typography>
        <Stack spacing={1}>
          {(data?.repos || []).map(r => (
            <Box key={r.name} sx={{ borderBottom: '1px solid #eee', pb: 1 }}>
              <Typography sx={{ fontFamily: 'monospace' }}>{r.name} → {r.path}</Typography>
              <Stack direction="row" spacing={1} sx={{ mt: 0.5 }}>
                <Chip label={`exists: ${r.exists ? 'yes' : 'no'}`} color={r.exists ? 'success' as any : 'error' as any} />
                <Chip label={`dir: ${r.directory ? 'yes' : 'no'}`} color={r.directory ? 'success' as any : 'warning' as any} />
                <Chip label={`readable: ${r.readable ? 'yes' : 'no'}`} color={r.readable ? 'success' as any : 'warning' as any} />
                {typeof r.sampled_count === 'number' && <Chip label={`files(~200 max): ${r.sampled_count}`} variant="outlined" />}
                {(r.sample_files || []).length > 0 && <Chip label={`sample: ${(r.sample_files || []).join(', ')}`} variant="outlined" />}
                {r.error && <Chip color="error" label={`error: ${r.error}`} />}
              </Stack>
            </Box>
          ))}
        </Stack>
      </Paper>
    </Box>
  );
}

