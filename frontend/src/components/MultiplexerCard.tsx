import React from 'react';
import Card from '@mui/material/Card';
import CardContent from '@mui/material/CardContent';
import Typography from '@mui/material/Typography';
import Chip from '@mui/material/Chip';
import Stack from '@mui/material/Stack';
import Box from '@mui/material/Box';
import Divider from '@mui/material/Divider';
import Tooltip from '@mui/material/Tooltip';
import HubIcon from '@mui/icons-material/Hub';
import TroubleshootIcon from '@mui/icons-material/Troubleshoot';
import StorageIcon from '@mui/icons-material/Storage';
import AccessTimeIcon from '@mui/icons-material/AccessTime';
import ErrorOutlineIcon from '@mui/icons-material/ErrorOutline';
import AssignmentIcon from '@mui/icons-material/Assignment';
import { MultiplexerInfo } from '../api';

function formatUptime(seconds?: number): string {
  if (!seconds || seconds <= 0) return 'n/a';
  if (seconds < 60) return `${Math.floor(seconds)}s`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ${Math.floor(seconds % 60)}s`;
  const hours = Math.floor(seconds / 3600);
  const mins = Math.floor((seconds % 3600) / 60);
  return `${hours}h ${mins}m`;
}

interface MultiplexerCardProps {
  info: MultiplexerInfo;
}

export default function MultiplexerCard({ info }: MultiplexerCardProps) {
  const status = (info.status || 'unknown').toLowerCase();
  let statusColor: 'success' | 'warning' | 'error' | 'default' = 'default';
  if (status.includes('ok') || status.includes('online') || status === 'running') statusColor = 'success';
  else if (status.includes('degraded') || status.includes('partial')) statusColor = 'warning';
  else if (status.includes('error') || status.includes('offline') || status.includes('fail')) statusColor = 'error';

  const metrics: { label: string; value?: number; icon: React.ReactNode }[] = [
    { label: 'Engines', value: info.engines ?? info.online, icon: <HubIcon fontSize="small" /> },
    { label: 'Online', value: info.online, icon: <HubIcon fontSize="small" /> },
    { label: 'Offline', value: info.offline, icon: <ErrorOutlineIcon fontSize="small" /> },
    { label: 'Tools', value: info.tools, icon: <StorageIcon fontSize="small" /> },
    { label: 'Routes', value: info.routes, icon: <TroubleshootIcon fontSize="small" /> },
  ];

  const chips = metrics.filter((m) => m.value !== undefined && m.value !== null);

  return (
    <Card
      sx={{
        borderTop: '4px solid',
        borderColor: statusColor === 'success' ? 'success.main' : statusColor === 'warning' ? 'warning.main' : statusColor === 'error' ? 'error.main' : 'divider',
        minHeight: 160,
        display: 'flex',
        flexDirection: 'column',
      }}
    >
      <CardContent sx={{ flexGrow: 1 }}>
        <Stack direction="row" spacing={1.5} alignItems="center" justifyContent="space-between" sx={{ mb: 1 }}>
          <Stack direction="row" spacing={1} alignItems="center">
            <HubIcon color="primary" />
            <Box>
              <Typography variant="subtitle1" sx={{ fontWeight: 600 }}>Multiplexer</Typography>
              {info.version && (
                <Typography variant="caption" color="text.secondary">v{info.version}</Typography>
              )}
            </Box>
          </Stack>
          <Chip label={info.status || 'unknown'} color={statusColor} size="small" />
        </Stack>

        <Stack direction="row" spacing={1} flexWrap="wrap" useFlexGap sx={{ mb: 1 }}>
          <Chip
            icon={<AccessTimeIcon fontSize="small" />}
            label={`Uptime: ${formatUptime(info.uptime_seconds)}`}
            size="small"
            variant="outlined"
          />
          {chips.map((chip) => (
            <Chip
              key={chip.label}
              icon={chip.icon}
              label={`${chip.label}: ${chip.value}`}
              size="small"
              variant="outlined"
            />
          ))}
        </Stack>

        {info.notes && (
          <Typography variant="body2" color="text.secondary" sx={{ mb: 1 }}>
            {info.notes}
          </Typography>
        )}

        {info.log_path && (
          <Box>
            <Divider sx={{ my: 1 }} />
            <Tooltip title="Log path">
              <Stack direction="row" spacing={0.5} alignItems="center">
                <AssignmentIcon fontSize="small" color="action" />
                <Typography variant="caption" sx={{ fontFamily: 'monospace' }}>{info.log_path}</Typography>
              </Stack>
            </Tooltip>
          </Box>
        )}
      </CardContent>
    </Card>
  );
}
