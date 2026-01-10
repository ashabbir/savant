import React from 'react';
import Box from '@mui/material/Box';
import Paper from '@mui/material/Paper';
import Typography from '@mui/material/Typography';
import Stack from '@mui/material/Stack';
import Chip from '@mui/material/Chip';
import { useReasoningDiagnostics, useReasoningJobs } from '../../api';
import DiagnosticsWorkers from './Workers';

export default function DiagnosticsReasoning() {
  const diag = useReasoningDiagnostics();
  const jobs = useReasoningJobs();
  

  return (
    <Box>
      <Paper sx={{ p: 2, mb: 2 }}>
        <Stack direction={{ xs: 'column', sm: 'row' }} spacing={2} alignItems={{ xs: 'stretch', sm: 'center' }} justifyContent="space-between">
          <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>Reasoning Worker Diagnostics</Typography>
          <Stack direction="row" spacing={1} alignItems="center" flexWrap="wrap" useFlexGap>
            {diag.data?.redis === 'connected' ? (
              <Chip size="small" color="success" label="Redis connected" />
            ) : (
              <Chip size="small" color="error" label={`Redis: ${diag.data?.redis || 'disconnected'}`} />
            )}
            {(() => {
              const queued = jobs.data?.queue_length ?? diag.data?.queue_length;
              const running = (jobs.data?.running_ids ? jobs.data.running_ids.length : undefined) ?? diag.data?.running_jobs;
              const failed = (jobs.data?.recent_failed ? jobs.data.recent_failed.length : undefined) ?? (diag.data?.recent_failed ? diag.data.recent_failed.length : undefined);
              const finished = (jobs.data?.recent_completed ? jobs.data.recent_completed.length : undefined) ?? (diag.data?.recent_completed ? diag.data.recent_completed.length : undefined);
              return (
                <>
                  {typeof queued === 'number' && <Chip size="small" label={`Queued ${queued}`} />}
                  {typeof running === 'number' && <Chip size="small" label={`Running ${running}`} />}
                  {typeof failed === 'number' && <Chip size="small" label={`Failed ${failed}`} />}
                  {typeof finished === 'number' && <Chip size="small" label={`Finished ${finished}`} />}
                </>
              );
            })()}
            {typeof diag.data?.calls?.total === 'number' && <Chip size="small" label={`Total ${diag.data.calls.total}`} />}
            {typeof diag.data?.calls?.last_24h === 'number' && <Chip size="small" label={`24h ${diag.data.calls.last_24h}`} />}
          </Stack>
        </Stack>
      </Paper>

      {/* Workers UI (embedded) */}
      <Box id="workers" sx={{ mt: 2 }}>
        <Paper sx={{ p: 2, mb: 2 }}>
          <Typography variant="subtitle2" sx={{ fontWeight: 600, mb: 1 }}>Workers</Typography>
          <DiagnosticsWorkers />
        </Paper>
      </Box>
    </Box>
  );
}
