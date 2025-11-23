import React, { useState, useRef, useEffect } from 'react';
import Card from '@mui/material/Card';
import CardContent from '@mui/material/CardContent';
import CardActions from '@mui/material/CardActions';
import Typography from '@mui/material/Typography';
import Chip from '@mui/material/Chip';
import Box from '@mui/material/Box';
import Stack from '@mui/material/Stack';
import Button from '@mui/material/Button';
import Collapse from '@mui/material/Collapse';
import Divider from '@mui/material/Divider';
import List from '@mui/material/List';
import ListItem from '@mui/material/ListItem';
import ListItemIcon from '@mui/material/ListItemIcon';
import ListItemText from '@mui/material/ListItemText';
import CircularProgress from '@mui/material/CircularProgress';
import LinearProgress from '@mui/material/LinearProgress';
import ExpandMoreIcon from '@mui/icons-material/ExpandMore';
import ExpandLessIcon from '@mui/icons-material/ExpandLess';
import CheckCircleIcon from '@mui/icons-material/CheckCircle';
import ErrorIcon from '@mui/icons-material/Error';
import HourglassEmptyIcon from '@mui/icons-material/HourglassEmpty';
import BuildIcon from '@mui/icons-material/Build';
import StorageIcon from '@mui/icons-material/Storage';
import PsychologyIcon from '@mui/icons-material/Psychology';
import IntegrationInstructionsIcon from '@mui/icons-material/IntegrationInstructions';
import GavelIcon from '@mui/icons-material/Gavel';
import PersonIcon from '@mui/icons-material/Person';
import { useEngineStatus, useEngineTools, ContextToolSpec } from '../api';

function formatUptime(seconds: number): string {
  if (seconds < 60) return `${Math.floor(seconds)}s`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ${Math.floor(seconds % 60)}s`;
  const hours = Math.floor(seconds / 3600);
  const mins = Math.floor((seconds % 3600) / 60);
  return `${hours}h ${mins}m`;
}

const ENGINE_ICONS: Record<string, React.ReactNode> = {
  context: <StorageIcon sx={{ fontSize: 32 }} />,
  think: <PsychologyIcon sx={{ fontSize: 32 }} />,
  jira: <IntegrationInstructionsIcon sx={{ fontSize: 32 }} />,
  personas: <PersonIcon sx={{ fontSize: 32 }} />,
  rules: <GavelIcon sx={{ fontSize: 32 }} />,
};

function formatEngineName(rawName: string): string {
  // Handle various formats:
  // "savant-jira" -> "Jira"
  // "service-jira" -> "Jira"
  // "Savant MCP service=jira" -> "Jira"
  let clean = rawName
    .replace(/^savant\s*mcp\s*/i, '')  // Remove "Savant MCP " prefix
    .replace(/^service[=\-]/i, '')      // Remove "service=" or "service-"
    .replace(/^savant[=\-]/i, '')       // Remove "savant=" or "savant-"
    .replace(/\s*\(unavailable\)/i, '') // Remove "(unavailable)" suffix
    .trim();

  if (!clean) clean = 'Unknown';
  return clean.charAt(0).toUpperCase() + clean.slice(1);
}

const ENGINE_COLORS: Record<string, string> = {
  context: '#4caf50',
  think: '#2196f3',
  jira: '#ff9800',
  personas: '#9c27b0',
  rules: '#6d4c41',
};

interface EngineCardProps {
  name: string;
  mount: string;
  toolCount: number;
}

export default function EngineCard({ name, mount, toolCount }: EngineCardProps) {
  const [expanded, setExpanded] = useState(false);
  const status = useEngineStatus(name);
  const tools = useEngineTools(name);
  const cardRef = useRef<HTMLDivElement>(null);
  const listRef = useRef<HTMLUListElement>(null);

  const handleToggle = () => {
    setExpanded(!expanded);
  };

  useEffect(() => {
    if (expanded && listRef.current) {
      listRef.current.scrollTop = 0;
    }
  }, [expanded]);

  const color = ENGINE_COLORS[name] || '#9e9e9e';
  const icon = ENGINE_ICONS[name] || <BuildIcon sx={{ fontSize: 40 }} />;

  return (
    <Card
      ref={cardRef}
      sx={{
        height: '100%',
        display: 'flex',
        flexDirection: 'column',
        borderTop: `4px solid ${color}`,
        transition: 'box-shadow 0.2s',
        '&:hover': { boxShadow: 6 },
        }}
    >
      {/* Card header - always visible */}
      <Box sx={{ px: 1.5, pt: 1.5, pb: 0.5 }}>
        <Stack direction="row" spacing={2} alignItems="flex-start">
          <Box sx={{ color }}>{icon}</Box>
          <Box sx={{ flexGrow: 1 }}>
            <Typography variant="subtitle1" component="div" sx={{ fontWeight: 600 }}>
              {formatEngineName(status.data?.info?.name || name)}
            </Typography>
            <Typography variant="caption" color="text.secondary" sx={{ fontFamily: 'monospace' }}>
              {mount}
            </Typography>
          </Box>
          <Chip
            icon={
              status.isLoading ? <HourglassEmptyIcon /> :
              status.isError ? <ErrorIcon /> :
              ['ok', 'running'].includes(status.data?.status || '') ? <CheckCircleIcon /> :
              <ErrorIcon />
            }
            label={
              status.isLoading ? 'loading' :
              status.isError ? 'error' :
              status.data?.status || 'unknown'
            }
            size="small"
            color={
              status.isLoading ? 'default' :
              status.isError ? 'error' :
              ['ok', 'running'].includes(status.data?.status || '') ? 'success' :
              'error'
            }
          />
        </Stack>
      </Box>

      {/* Card content - collapses when tools are shown */}
      <Collapse in={!expanded} timeout="auto">
        <CardContent sx={{ flexGrow: 1, pt: 1, minHeight: 120 }}>
          {status.isLoading && <LinearProgress sx={{ mb: 2 }} />}

          {status.data && (
            <>
              <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
                {status.data.info?.description || 'No description available'}
              </Typography>

              <Stack direction="row" spacing={1} flexWrap="wrap" useFlexGap>
                <Chip
                  label={`v${status.data.info?.version || '?'}`}
                  size="small"
                  variant="outlined"
                />
                <Chip
                  icon={<BuildIcon />}
                  label={`${toolCount} tools`}
                  size="small"
                  variant="outlined"
                />
                <Chip
                  label={`Uptime: ${formatUptime(status.data.uptime_seconds || (status.data as any).uptime || 0)}`}
                  size="small"
                  variant="outlined"
                />
              </Stack>
            </>
          )}
        </CardContent>
      </Collapse>

      {/* Tools list - shows when expanded */}
      <Collapse in={expanded} timeout="auto" unmountOnExit>
        <Divider />
        <Box sx={{ px: 1.5, py: 1.5, height: 120, overflow: 'auto' }}>
          {tools.isLoading && (
            <Box display="flex" justifyContent="center" py={2}>
              <CircularProgress size={24} />
            </Box>
          )}
          {tools.data && (
            <List ref={listRef} dense>
              {tools.data.tools.map((tool: ContextToolSpec) => (
                <ListItem key={tool.name} sx={{ py: 0.5 }}>
                  <ListItemIcon sx={{ minWidth: 32 }}>
                    <BuildIcon fontSize="small" sx={{ color }} />
                  </ListItemIcon>
                  <ListItemText
                    primary={
                      <Typography variant="body2" sx={{ fontFamily: 'monospace', fontWeight: 500 }}>
                        {tool.name}
                      </Typography>
                    }
                    secondary={
                      <Typography variant="caption" color="text.secondary" noWrap>
                        {tool.description || 'No description'}
                      </Typography>
                    }
                  />
                </ListItem>
              ))}
            </List>
          )}
        </Box>
      </Collapse>

      <Divider />

      <CardActions>
        <Button
          size="small"
          onClick={handleToggle}
          endIcon={expanded ? <ExpandLessIcon /> : <ExpandMoreIcon />}
        >
          {expanded ? 'Hide' : 'Show'} Tools
        </Button>
      </CardActions>
    </Card>
  );
}
