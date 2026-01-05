import React from 'react';
import Card from '@mui/material/Card';
import CardContent from '@mui/material/CardContent';
import CardActions from '@mui/material/CardActions';
import Typography from '@mui/material/Typography';
import Chip from '@mui/material/Chip';
import Box from '@mui/material/Box';
import Stack from '@mui/material/Stack';
import Button from '@mui/material/Button';
import Divider from '@mui/material/Divider';
import CircularProgress from '@mui/material/CircularProgress';
import HistoryIcon from '@mui/icons-material/History';
import AssignmentIcon from '@mui/icons-material/Assignment';
import StorageIcon from '@mui/icons-material/Storage';
import TimelineIcon from '@mui/icons-material/Timeline';
import { useBlackboardStats } from '../api';

export default function BlackboardCard() {
  const { data, isLoading, isError } = useBlackboardStats();

  return (
    <Card
      sx={{
        height: '100%',
        display: 'flex',
        flexDirection: 'column',
        borderTop: '4px solid #f44336',
        transition: 'box-shadow 0.2s',
        '&:hover': { boxShadow: 6 },
      }}
    >
      <Box sx={{ px: 1.5, pt: 1.5, pb: 0.5 }}>
        <Stack direction="row" spacing={2} alignItems="flex-start">
          <Box sx={{ color: '#f44336' }}>
            <AssignmentIcon sx={{ fontSize: 32 }} />
          </Box>
          <Box sx={{ flexGrow: 1 }}>
            <Typography variant="subtitle1" component="div" sx={{ fontWeight: 600 }}>
              Blackboard
            </Typography>
            <Typography variant="caption" color="text.secondary">
              Universal truth & coordination substrate
            </Typography>
          </Box>
          <Chip
            icon={isError ? <HistoryIcon /> : <TimelineIcon />}
            label={isError ? "Offline" : "Live"}
            size="small"
            color={isError ? "error" : "success"}
          />
        </Stack>
      </Box>

      <CardContent sx={{ flexGrow: 1, pt: 1 }}>
        {isLoading ? (
          <Box display="flex" justifyContent="center" py={2}>
            <CircularProgress size={24} />
          </Box>
        ) : data ? (
          <Stack spacing={1.5}>
            <Typography variant="body2" color="text.secondary">
              Append-only event stream and immutable artifact storage for cross-agent coordination.
            </Typography>
            <Stack direction="row" spacing={1} flexWrap="wrap" useFlexGap>
              <Chip
                icon={<AssignmentIcon sx={{ fontSize: '14px !important' }} />}
                label={`${data.sessions} Sessions`}
                size="small"
                variant="outlined"
              />
              <Chip
                icon={<TimelineIcon sx={{ fontSize: '14px !important' }} />}
                label={`${data.events} Events`}
                size="small"
                variant="outlined"
              />
              <Chip
                icon={<StorageIcon sx={{ fontSize: '14px !important' }} />}
                label={`${data.artifacts} Artifacts`}
                size="small"
                variant="outlined"
              />
            </Stack>
          </Stack>
        ) : (
          <Typography variant="body2" color="error">
            Failed to load blackboard stats.
          </Typography>
        )}
      </CardContent>

      <Divider />

      <CardActions>
        <Button
          size="small"
          onClick={() => {
            window.open('/engine/blackboard', '_blank');
          }}
          startIcon={<HistoryIcon />}
        >
          Open Explorer
        </Button>
      </CardActions>
    </Card>
  );
}
