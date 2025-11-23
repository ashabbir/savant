import React, { useMemo, useState } from 'react';
import { Link, Navigate, Route, Routes, useLocation, useNavigate } from 'react-router-dom';
import AppBar from '@mui/material/AppBar';
import Toolbar from '@mui/material/Toolbar';
import Typography from '@mui/material/Typography';
import Tabs from '@mui/material/Tabs';
import Tab from '@mui/material/Tab';
import IconButton from '@mui/material/IconButton';
import SettingsIcon from '@mui/icons-material/Settings';
import OpenInNewIcon from '@mui/icons-material/OpenInNew';
import Container from '@mui/material/Container';
import Alert from '@mui/material/Alert';
import Snackbar from '@mui/material/Snackbar';
import { createTheme, ThemeProvider } from '@mui/material/styles';
import Search from './pages/Search';
import Repos from './pages/Repos';
import Diagnostics from './pages/Diagnostics';
import Dashboard from './pages/Dashboard';
import ThinkWorkflows from './pages/think/Workflows';
import ThinkPrompts from './pages/think/Prompts';
import ThinkRuns from './pages/think/Runs';
import Personas from './pages/personas/Personas';
import ContextTools from './pages/context/Tools';
import ContextResources from './pages/context/Resources';
import MemorySearch from './pages/context/MemorySearch';
import { getErrorMessage, useHubHealth, useHubInfo } from './api';
import Chip from '@mui/material/Chip';
import Box from '@mui/material/Box';
import DashboardIcon from '@mui/icons-material/Dashboard';
import HubIcon from '@mui/icons-material/Hub';
import Tooltip from '@mui/material/Tooltip';
import Stack from '@mui/material/Stack';
import SettingsDialog from './components/SettingsDialog';
import { onAppEvent } from './utils/bus';

function useMainTabIndex() {
  const { pathname } = useLocation();
  if (pathname === '/dashboard' || pathname === '/') return 0;
  if (pathname.startsWith('/ctx')) return 1;
  if (pathname.startsWith('/think')) return 2;
  if (pathname.startsWith('/personas')) return 3;
  if (pathname.startsWith('/diagnostics')) return 4;
  return 0;
}

function useContextSubIndex() {
  const { pathname } = useLocation();
  if (pathname.startsWith('/ctx/resources')) return 0;
  if (pathname.startsWith('/ctx/search') || pathname.startsWith('/ctx/fts')) return 1;
  if (pathname.startsWith('/ctx/memory')) return 2;
  if (pathname.startsWith('/ctx/repos') || pathname === '/repos') return 3;
  return 0;
}

function useThinkSubIndex() {
  const { pathname } = useLocation();
  if (pathname.startsWith('/think/prompts')) return 1;
  if (pathname.startsWith('/think/runs')) return 2;
  return 0;
}

function formatUptime(seconds: number): string {
  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const mins = Math.floor((seconds % 3600) / 60);
  if (days > 0) return `${days}d ${hours}h`;
  if (hours > 0) return `${hours}h ${mins}m`;
  return `${mins}m`;
}

export default function App() {
  const [open, setOpen] = useState(false);
  const theme = useMemo(() => createTheme({}), []);
  const mainIdx = useMainTabIndex();
  const ctxIdx = useContextSubIndex();
  const thinkIdx = useThinkSubIndex();
  const isDev = import.meta.env.DEV;
  const navigate = useNavigate();
  const { data, isLoading, isError, error } = useHubHealth();
  const hub = useHubInfo();
  const errMsg = getErrorMessage(error as any);
  const [snackOpen, setSnackOpen] = useState(false);
  const [snackMsg, setSnackMsg] = useState('');

  React.useEffect(() => {
    return onAppEvent((ev) => {
      if (ev.type === 'error') {
        setSnackMsg(ev.message);
        setSnackOpen(true);
      }
    });
  }, []);

  return (
    <ThemeProvider theme={theme}>
      <Box sx={{ minHeight: '100vh', display: 'flex', flexDirection: 'column' }}>
      <AppBar position="static" sx={{ background: 'linear-gradient(135deg, #1a237e 0%, #283593 100%)' }}>
        <Toolbar variant="dense">
          <Stack direction="row" spacing={1.5} alignItems="center" sx={{ flexGrow: 1 }}>
            <HubIcon sx={{ fontSize: 28 }} />
            <Box>
              <Typography variant="subtitle1" sx={{ fontWeight: 600, lineHeight: 1.2 }}>
                {hub.data?.service || 'Savant MCP Hub'}
              </Typography>
              <Typography variant="caption" sx={{ opacity: 0.7 }}>
                {hub.data?.transport || 'http'} - Unified access to all engines
              </Typography>
            </Box>
          </Stack>
          <Stack direction="row" spacing={1} alignItems="center">
            {hub.data && (
              <>
                <Chip size="small" label={`v${hub.data.version}`} sx={{ bgcolor: 'rgba(255,255,255,0.15)', color: 'white', height: 22 }} />
                <Chip size="small" label={`Uptime: ${formatUptime(hub.data.hub?.uptime_seconds || 0)}`} sx={{ bgcolor: 'rgba(255,255,255,0.15)', color: 'white', height: 22 }} />
                <Chip size="small" label={`PID: ${hub.data.hub?.pid}`} sx={{ bgcolor: 'rgba(255,255,255,0.15)', color: 'white', height: 22 }} />
              </>
            )}
            {isLoading ? (
              <Chip size="small" label="Connecting..." sx={{ bgcolor: 'info.main', color: 'white', height: 22 }} />
            ) : isError ? (
              <Tooltip title={errMsg}>
                <Chip size="small" label="Unreachable" sx={{ bgcolor: 'error.main', color: 'white', height: 22, cursor: 'help' }} />
              </Tooltip>
            ) : (
              <Chip size="small" label="Connected" sx={{ bgcolor: 'success.main', color: 'white', height: 22 }} />
            )}
            <Tooltip title="Open legacy console">
              <IconButton size="small" color="inherit" component="a" href="/console" target="_blank" rel="noreferrer">
                <OpenInNewIcon fontSize="small" />
              </IconButton>
            </Tooltip>
            <IconButton size="small" color="inherit" onClick={() => setOpen(true)} title="Settings">
              <SettingsIcon fontSize="small" />
            </IconButton>
          </Stack>
        </Toolbar>
      </AppBar>
      <Tabs value={mainIdx} onChange={(_, v) => {
        if (v === 0) navigate('/dashboard');
        else if (v === 1) navigate('/ctx/resources');
        else if (v === 2) navigate('/think/workflows');
        else if (v === 3) navigate('/personas');
        else if (v === 4) navigate('/diagnostics');
      }} centered>
        <Tab icon={<DashboardIcon />} iconPosition="start" label="Dashboard" component={Link} to="/dashboard" />
        <Tab label="Context" component={Link} to="/ctx/resources" />
        <Tab label="Think" component={Link} to="/think" />
        <Tab label="Personas" component={Link} to="/personas" />
        <Tab label="Diagnostics" component={Link} to="/diagnostics" />
      </Tabs>
      {mainIdx === 1 && (
        <Tabs value={ctxIdx} onChange={(_, v) => {
          if (v === 0) navigate('/ctx/resources');
          else if (v === 1) navigate('/ctx/search');
          else if (v === 2) navigate('/ctx/memory-search');
          else if (v === 3) navigate('/ctx/repos');
        }} centered>
          <Tab label="Resources" component={Link} to="/ctx/resources" />
          <Tab label="FTS Search" component={Link} to="/ctx/search" />
          <Tab label="Memory Search" component={Link} to="/ctx/memory-search" />
          <Tab label="Repos" component={Link} to="/ctx/repos" />
        </Tabs>
      )}
      {mainIdx === 2 && (
        <Tabs value={thinkIdx} onChange={(_, v) => {
          if (v === 0) navigate('/think/workflows');
          else if (v === 1) navigate('/think/prompts');
          else if (v === 2) navigate('/think/runs');
        }} centered>
          <Tab label="Workflows" component={Link} to="/think/workflows" />
          <Tab label="Prompts" component={Link} to="/think/prompts" />
          <Tab label="Runs" component={Link} to="/think/runs" />
        </Tabs>
      )}
      <Container maxWidth="lg" sx={{ mt: 3, mb: 4, flex: 1 }}>
        <Routes>
          <Route path="/" element={<Navigate to="/dashboard" replace />} />
          <Route path="/dashboard" element={<Dashboard />} />
          <Route path="/search" element={<Navigate to="/ctx/search" replace />} />
          <Route path="/repos" element={<Navigate to="/ctx/repos" replace />} />
          <Route path="/ctx/search" element={<Search />} />
          <Route path="/ctx/fts" element={<Search />} />
          <Route path="/ctx/repos" element={<Repos />} />
          <Route path="/think" element={<ThinkWorkflows />} />
          <Route path="/think/workflows" element={<ThinkWorkflows />} />
          <Route path="/think/prompts" element={<ThinkPrompts />} />
          <Route path="/think/runs" element={<ThinkRuns />} />
          <Route path="/personas" element={<Personas />} />
          <Route path="/ctx/tools" element={<ContextTools />} />
          <Route path="/ctx/resources" element={<ContextResources />} />
          <Route path="/ctx/memory-search" element={<MemorySearch />} />
          <Route path="/ctx/memory" element={<MemorySearch />} />
          <Route path="/diagnostics" element={<Diagnostics />} />
        </Routes>
      </Container>
      {/* Footer banner (DEV green / BUILD blue) */}
      <Box sx={{
        bgcolor: isDev ? 'success.main' : 'primary.main',
        color: 'rgba(255,255,255,0.8)',
        px: 2,
        py: 0.5,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        mt: 'auto'
      }}>
        <Typography variant="caption" sx={{ opacity: 0.9 }}>amdSh@2025</Typography>
        <Typography variant="caption" sx={{ opacity: 0.9 }}>{isDev ? 'DEV' : 'BUILD'}</Typography>
        <Typography variant="caption" sx={{ opacity: 0.9 }}>github.com/ashabbir</Typography>
      </Box>
      </Box>
      <SettingsDialog open={open} onClose={() => setOpen(false)} />
      <Snackbar
        open={snackOpen}
        autoHideDuration={6000}
        onClose={() => setSnackOpen(false)}
        anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }}
      >
        <Alert onClose={() => setSnackOpen(false)} severity="error" sx={{ width: '100%' }}>
          {snackMsg}
        </Alert>
      </Snackbar>
    </ThemeProvider>
  );
}
