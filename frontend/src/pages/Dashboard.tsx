import React from 'react';
// Box imported below; remove duplicate
import Grid from '@mui/material/Grid2';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import Divider from '@mui/material/Divider';
import Alert from '@mui/material/Alert';
import LinearProgress from '@mui/material/LinearProgress';
import { useHubInfo } from '../api';
import EngineCard from '../components/EngineCard';

export default function Dashboard() {
  const hub = useHubInfo();

  return (
    <Box>
      {hub.isLoading && <LinearProgress sx={{ mb: 2 }} />}

      {hub.isError && (
        <Alert severity="error" sx={{ mb: 3 }}>
          Failed to connect to hub: {(hub.error as any)?.message || 'Unknown error'}
        </Alert>
      )}

      {/* Quick Stats */}
      {hub.data?.engines && hub.data.engines.length > 0 && (
        <Paper sx={{ p: 2, mb: 3 }}>
          <Stack direction="row" spacing={6} justifyContent="center" flexWrap="wrap" useFlexGap>
            <Box textAlign="center">
              <Typography variant="h3" color="primary" sx={{ fontWeight: 600 }}>
                {hub.data.engines.length}
              </Typography>
              <Typography variant="body2" color="text.secondary">
                Engines
              </Typography>
            </Box>
            <Box textAlign="center">
              <Typography variant="h3" color="secondary" sx={{ fontWeight: 600 }}>
                {hub.data.engines.reduce((acc, e) => acc + e.tools, 0)}
              </Typography>
              <Typography variant="body2" color="text.secondary">
                Total Tools
              </Typography>
            </Box>
            <Box textAlign="center">
              <Typography variant="h3" sx={{ fontWeight: 600, color: '#4caf50' }}>
                {hub.data.engines.length}
              </Typography>
              <Typography variant="body2" color="text.secondary">
                Active
              </Typography>
            </Box>
          </Stack>
        </Paper>
      )}

      {/* Engines Section */}
      <Typography variant="h6" sx={{ mb: 2, fontWeight: 500 }}>
        Mounted Engines
      </Typography>
      <Divider sx={{ mb: 3 }} />

      {/* Fluid grid: 1..N per row depending on window size */}
      <Box
        sx={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))',
          gap: 2,
        }}
      >
        {hub.data?.engines?.map((engine) => (
          <Box key={engine.name}>
            <EngineCard name={engine.name} mount={engine.mount} toolCount={engine.tools} />
          </Box>
        ))}
      </Box>

      {!hub.isLoading && (!hub.data?.engines || hub.data.engines.length === 0) && (
        <Alert severity="info" sx={{ mt: 1 }}>No engines mounted</Alert>
      )}
    </Box>
  );
}
