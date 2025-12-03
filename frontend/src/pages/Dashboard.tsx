import React from 'react';
// Box imported below; remove duplicate
import Grid from '@mui/material/Grid2';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import Chip from '@mui/material/Chip';
import Divider from '@mui/material/Divider';
import Alert from '@mui/material/Alert';
import LinearProgress from '@mui/material/LinearProgress';
import { useHubInfo } from '../api';
import EngineCard from '../components/EngineCard';
// import MultiplexerCard from '../components/MultiplexerCard';

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

      {/* Compact one-line stats row (MCPs + Multiplexer) */}
      {hub.data?.engines && hub.data.engines.length > 0 && (
        <Paper sx={{ p: 1.25, mb: 2 }}>
          <Stack direction={{ xs: 'column', md: 'row' }} spacing={1.25} alignItems={{ xs: 'flex-start', md: 'center' }} justifyContent="space-between">
            {/* Left: MCP stats */}
            <Stack direction="row" spacing={2} alignItems="center" flexWrap="wrap" useFlexGap>
              <Stack direction="row" spacing={0.75} alignItems="baseline">
                <Typography variant="h5" color="primary" sx={{ fontWeight: 700, lineHeight: 1 }}>
                  {hub.data.engines.length}
                </Typography>
                <Typography variant="body2" color="text.secondary">MCPs</Typography>
              </Stack>
              <Stack direction="row" spacing={0.75} alignItems="baseline">
                <Typography variant="h5" color="secondary" sx={{ fontWeight: 700, lineHeight: 1 }}>
                  {hub.data.engines.reduce((acc, e) => acc + e.tools, 0)}
                </Typography>
                <Typography variant="body2" color="text.secondary">Total Tools</Typography>
              </Stack>
              <Stack direction="row" spacing={0.75} alignItems="baseline">
                <Typography variant="h5" sx={{ fontWeight: 700, lineHeight: 1, color: '#4caf50' }}>
                  {hub.data.engines.length}
                </Typography>
                <Typography variant="body2" color="text.secondary">Active</Typography>
              </Stack>
            </Stack>

            {/* Right: Multiplexer summary (only if mounted) */}
            {hub.data?.multiplexer && (
              <Stack direction="row" spacing={0.75} alignItems="center" flexWrap="wrap" useFlexGap>
                <Chip size="small" label={`Mux: ${hub.data.multiplexer.status || 'unknown'}`} color={
                  (hub.data.multiplexer.status || '').toLowerCase().includes('ok') ? 'success'
                    : (hub.data.multiplexer.status || '').toLowerCase().includes('warn') ? 'warning'
                    : (hub.data.multiplexer.status || '').toLowerCase().includes('error') ? 'error'
                    : 'default'
                } />
                {typeof hub.data.multiplexer.engines === 'number' && (
                  <Chip size="small" variant="outlined" label={`Engines ${hub.data.multiplexer.engines}`} />
                )}
                {typeof hub.data.multiplexer.online === 'number' && (
                  <Chip size="small" variant="outlined" color="success" label={`Online ${hub.data.multiplexer.online}`} />
                )}
                {typeof hub.data.multiplexer.offline === 'number' && (
                  <Chip size="small" variant="outlined" color="warning" label={`Offline ${hub.data.multiplexer.offline}`} />
                )}
                {typeof hub.data.multiplexer.tools === 'number' && (
                  <Chip size="small" variant="outlined" label={`Tools ${hub.data.multiplexer.tools}`} />
                )}
                {typeof hub.data.multiplexer.routes === 'number' && (
                  <Chip size="small" variant="outlined" label={`Routes ${hub.data.multiplexer.routes}`} />
                )}
                {typeof hub.data.multiplexer.uptime_seconds === 'number' && (
                  <Chip size="small" variant="outlined" label={`Uptime ${Math.floor((hub.data.multiplexer.uptime_seconds || 0)/60)}m`} />
                )}
              </Stack>
            )}
          </Stack>
        </Paper>
      )}

      {/* Multiplexer detailed card intentionally omitted to keep header compact */}

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
          <Box key={engine.name} sx={{ mb: 2 }}>
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
