import React, { useMemo, useState } from 'react';
import { Link, Navigate, Route, Routes, useLocation, useNavigate } from 'react-router-dom';
import { AppBar, Toolbar, Typography, Tabs, Tab, IconButton, Container, Alert, Snackbar, Chip, Box, Tooltip, Stack } from '@mui/material';
import SettingsIcon from '@mui/icons-material/Settings';
import { ThemeProvider } from '@mui/material/styles';
import { createCompactTheme } from './theme/compact';
import Search from './pages/Search';
import Repos from './pages/Repos';
import DiagnosticsAgent from './pages/diagnostics/Agent';
import DiagnosticsOverview from './pages/diagnostics/Overview';
import DiagnosticsRequests from './pages/diagnostics/Requests';
import DiagnosticsLogs from './pages/diagnostics/Logs';
import DiagnosticsRoutes from './pages/diagnostics/Routes';
import DiagnosticsWorkflows from './pages/diagnostics/Workflows';
import APIHealth from './pages/diagnostics/APIHealth';
import Dashboard from './pages/Dashboard';
import ThinkWorkflows from './pages/think/Workflows';
import ThinkTools from './pages/think/Tools';
import ThinkWorkflowEditor from './pages/think/WorkflowEditor';
import ThinkPrompts from './pages/think/Prompts';
import PromptEditor from './pages/think/PromptEditor';
import ThinkRuns from './pages/think/Runs';
import WorkflowRuns from './pages/workflow/Runs';
import Personas from './pages/personas/Personas';
import PersonasTools from './pages/personas/Tools';
import PersonaEditor from './pages/personas/PersonaEditor';
import RulesPage from './pages/rules/Rules';
import RulesTools from './pages/rules/Tools';
import RuleEditor from './pages/rules/RuleEditor';
import JiraTools from './pages/jira/Tools';
import GitTools from './pages/git/Tools';
import ContextTools from './pages/context/Tools';
import ContextResources from './pages/context/Resources';
import MemorySearch from './pages/context/MemorySearch';
import WorkflowTools from './pages/workflow/Tools';
import { getErrorMessage, loadConfig, useHubHealth, useHubInfo } from './api';
import DashboardIcon from '@mui/icons-material/Dashboard';
import HubIcon from '@mui/icons-material/Hub';
import StorageIcon from '@mui/icons-material/Storage';
import ManageSearchIcon from '@mui/icons-material/ManageSearch';
import CodeIcon from '@mui/icons-material/Code';
import SettingsDialog from './components/SettingsDialog';
import { onAppEvent } from './utils/bus';

function useMainTabIndex() {
  const { pathname } = useLocation();
  if (pathname === '/dashboard' || pathname === '/') return 0;
  if (pathname.startsWith('/engines')) return 1;
  if (pathname.startsWith('/diagnostics')) return 2;
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

function sortEngines(engines: string[]): string[] {
  const order = ['context', 'think', 'personas', 'rules', 'jira', 'git'];
  return engines.sort((a, b) => {
    const aIdx = order.indexOf(a);
    const bIdx = order.indexOf(b);
    if (aIdx === -1 && bIdx === -1) return a.localeCompare(b);
    if (aIdx === -1) return 1;
    if (bIdx === -1) return -1;
    return aIdx - bIdx;
  });
}

function useSelectedEngine(hub: ReturnType<typeof useHubInfo>['data']) {
  const { pathname } = useLocation();
  const seg = pathname.split('/').filter(Boolean);
  const rawEngines = (hub?.engines || []).map((e) => e.name);
  const engines = sortEngines(rawEngines);
  const idx = seg[0] === 'engines' && seg[1] ? engines.indexOf(seg[1]) : -1;
  return {
    engines,
    name: idx >= 0 ? engines[idx] : engines[0],
    index: idx >= 0 ? idx : 0,
  };
}

function useEngineSubIndex(engineName: string | undefined) {
  const { pathname } = useLocation();
  if (!engineName) return 0;
  if (engineName === 'context') {
    if (pathname.includes('/resources')) return 0;
    if (pathname.includes('/search') || pathname.includes('/fts')) return 1;
    if (pathname.includes('/memory')) return 2;
    if (pathname.includes('/repos')) return 3;
    if (pathname.includes('/tools')) return 4;
    return 0;
  }
  if (engineName === 'think') {
    if (pathname.includes('/workflows')) return 0;
    if (pathname.includes('/prompts')) return 1;
    if (pathname.includes('/runs')) return 2;
    if (pathname.includes('/think/tools')) return 3;
    return 0;
  }
  if (engineName === 'personas') {
    if (pathname.includes('/tools')) return 1;
    return 0;
  }
  if (engineName === 'rules') {
    if (pathname.includes('/tools')) return 1;
    return 0;
  }
  if (engineName === 'workflow') {
    if (pathname.includes('/tools')) return 1;
    if (pathname.includes('/runs')) return 0;
    return 0;
  }
  // personas/jira/git default single or first tab
  return 0;
}

function defaultEngineRoute(name: string): string {
  if (name === 'context') return '/engines/context/resources';
  if (name === 'think') return '/engines/think/workflows';
  if (name === 'jira') return '/engines/jira/tools';
  if (name === 'personas') return '/engines/personas';
  if (name === 'rules') return '/engines/rules';
  if (name === 'git') return '/engines/git/tools';
  return `/engines/${name}`;
}

function multiplexerChipColor(status?: string): 'default' | 'success' | 'warning' | 'error' {
  const val = (status || '').toLowerCase();
  if (!val) return 'default';
  if (val.includes('ok') || val.includes('online') || val.includes('running')) return 'success';
  if (val.includes('warn') || val.includes('degraded') || val.includes('partial')) return 'warning';
  if (val.includes('error') || val.includes('offline') || val.includes('fail')) return 'error';
  return 'default';
}

function useDiagnosticsSubIndex() {
  const { pathname } = useLocation();
  if (pathname.includes('/diagnostics/overview') || pathname === '/diagnostics') return 0;
  if (pathname.includes('/diagnostics/requests')) return 1;
  if (pathname.includes('/diagnostics/logs')) return 2;
  if (pathname.includes('/diagnostics/workflows')) return 3;
  if (pathname.includes('/diagnostics/routes')) return 4;
  if (pathname.includes('/diagnostics/api')) return 5;
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
  const [themeMode, setThemeMode] = useState<'light' | 'dark'>(() => loadConfig().themeMode || 'light');
  const theme = useMemo(() => createCompactTheme(themeMode), [themeMode]);
  const mainIdx = useMainTabIndex();
  const ctxIdx = useContextSubIndex();
  const thinkIdx = useThinkSubIndex();
  const isDev = import.meta.env.DEV;
  const navigate = useNavigate();
  const { data, isLoading, isError, error } = useHubHealth();
  const hub = useHubInfo();
  const { engines, name: selEngine, index: engIdx } = useSelectedEngine(hub.data);
  const engSubIdx = useEngineSubIndex(selEngine);
  const diagSubIdx = useDiagnosticsSubIndex();

  const loc = useLocation();
  React.useEffect(() => {
    if (mainIdx === 1 && (loc.pathname === '/engines' || loc.pathname === '/engines/')) {
      const tgt = engines[0];
      if (tgt) navigate(defaultEngineRoute(tgt), { replace: true });
    }
  }, [mainIdx, loc.pathname, engines]);
  // Normalize Diagnostics root to a concrete sub-route so tabs highlight consistently
  React.useEffect(() => {
    if (mainIdx === 2 && (loc.pathname === '/diagnostics' || loc.pathname === '/diagnostics/')) {
      navigate('/diagnostics/overview', { replace: true });
    }
  }, [mainIdx, loc.pathname]);
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

  const chromeGradient = themeMode === 'dark'
    ? 'linear-gradient(135deg, #0f172a 0%, #1f2937 100%)'
    : 'linear-gradient(135deg, #1a237e 0%, #283593 100%)';

  return (
    <ThemeProvider theme={theme}>
      <Box sx={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', backgroundColor: 'background.default', color: 'text.primary' }}>
      <AppBar position="static" sx={{ background: chromeGradient }}>
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
                {hub.data.multiplexer && (
                  <Chip
                    size="small"
                    label={`Mux: ${hub.data.multiplexer.status || 'unknown'}`}
                    color={multiplexerChipColor(hub.data.multiplexer.status)}
                    sx={{ height: 22 }}
                  />
                )}
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
            <IconButton size="small" color="inherit" onClick={() => setOpen(true)} title="Settings">
              <SettingsIcon fontSize="small" />
            </IconButton>
          </Stack>
        </Toolbar>
      </AppBar>
      <Tabs value={mainIdx} onChange={(_, v) => {
        if (v === 0) navigate('/dashboard');
        else if (v === 1) navigate('/engines');
        else if (v === 2) navigate('/diagnostics');
      }} centered>
        <Tab icon={<DashboardIcon />} iconPosition="start" label="Dashboard" component={Link} to="/dashboard" />
        <Tab icon={<StorageIcon />} iconPosition="start" label="Engines" component={Link} to="/engines" />
        <Tab icon={<ManageSearchIcon />} iconPosition="start" label="Diagnostics" component={Link} to="/diagnostics" />
      </Tabs>
      {mainIdx === 1 && (
        <Tabs value={engIdx} onChange={(_, v) => {
          const tgt = engines[v];
          if (tgt) {
            // Navigate to engine default route
          if (tgt === 'context') navigate('/engines/context/resources');
          else if (tgt === 'think') navigate('/engines/think/workflows');
          else if (tgt === 'personas') navigate('/engines/personas');
          else if (tgt === 'rules') navigate('/engines/rules');
          else if (tgt === 'jira') navigate('/engines/jira/tools');
          else if (tgt === 'git') navigate('/engines/git/tools');
          else navigate(`/engines/${tgt}`);
          }
        }} centered sx={{
          '& .MuiTab-root': { fontSize: 12, minHeight: 36, py: 0.5, textTransform: 'none' },
          '& .MuiTabs-indicator': { height: 2 }
        }}>
          {engines.map((e) => (
            <Tab key={e} label={e.charAt(0).toUpperCase() + e.slice(1)} component={Link} to={defaultEngineRoute(e)} />
          ))}
        </Tabs>
      )}
      
      {mainIdx === 1 && selEngine === 'context' && (
        <Tabs value={engSubIdx} onChange={(_, v) => {
          if (v === 0) navigate('/engines/context/resources');
          else if (v === 1) navigate('/engines/context/search');
          else if (v === 2) navigate('/engines/context/memory-search');
          else if (v === 3) navigate('/engines/context/repos');
          else if (v === 4) navigate('/engines/context/tools');
        }} centered sx={{
          '& .MuiTab-root': { fontSize: 12, minHeight: 36, py: 0.5, textTransform: 'none', color: 'text.secondary' },
          '& .Mui-selected': { color: 'primary.main !important' },
          '& .MuiTabs-indicator': { height: 2, backgroundColor: 'primary.light' }
        }}>
          <Tab label="Resources" component={Link} to="/engines/context/resources" />
          <Tab label="FTS" component={Link} to="/engines/context/search" />
          <Tab label="Memory Search" component={Link} to="/engines/context/memory-search" />
          <Tab label="Repos" component={Link} to="/engines/context/repos" />
          <Tab label="Tools" component={Link} to="/engines/context/tools" />
        </Tabs>
      )}
      {mainIdx === 1 && selEngine === 'think' && (
        <Tabs value={engSubIdx} onChange={(_, v) => {
          if (v === 0) navigate('/engines/think/workflows');
          else if (v === 1) navigate('/engines/think/prompts');
          else if (v === 2) navigate('/engines/think/runs');
          else if (v === 3) navigate('/engines/think/tools');
        }} centered sx={{
          '& .MuiTab-root': { fontSize: 12, minHeight: 36, py: 0.5, textTransform: 'none', color: 'text.secondary' },
          '& .Mui-selected': { color: 'primary.main !important' },
          '& .MuiTabs-indicator': { height: 2, backgroundColor: 'primary.light' }
        }}>
          <Tab label="Workflows" component={Link} to="/engines/think/workflows" />
          <Tab label="Prompts" component={Link} to="/engines/think/prompts" />
          <Tab label="Runs" component={Link} to="/engines/think/runs" />
          <Tab label="Tools" component={Link} to="/engines/think/tools" />
        </Tabs>
      )}
      {mainIdx === 1 && selEngine === 'personas' && (
        <Tabs value={engSubIdx} onChange={(_, v) => {
          if (v === 0) navigate('/engines/personas');
          else if (v === 1) navigate('/engines/personas/tools');
        }} centered sx={{
          '& .MuiTab-root': { fontSize: 12, minHeight: 36, py: 0.5, textTransform: 'none', color: 'text.secondary' },
          '& .Mui-selected': { color: 'primary.main !important' },
          '& .MuiTabs-indicator': { height: 2, backgroundColor: 'primary.light' }
        }}>
          <Tab label="Browse" component={Link} to="/engines/personas" />
          <Tab label="Tools" component={Link} to="/engines/personas/tools" />
        </Tabs>
      )}
      {mainIdx === 1 && selEngine === 'rules' && (
        <Tabs value={engSubIdx} onChange={(_, v) => {
          if (v === 0) navigate('/engines/rules');
          else if (v === 1) navigate('/engines/rules/tools');
        }} centered sx={{
          '& .MuiTab-root': { fontSize: 12, minHeight: 36, py: 0.5, textTransform: 'none', color: 'text.secondary' },
          '& .Mui-selected': { color: 'primary.main !important' },
          '& .MuiTabs-indicator': { height: 2, backgroundColor: 'primary.light' }
        }}>
          <Tab label="Browse" component={Link} to="/engines/rules" />
          <Tab label="Tools" component={Link} to="/engines/rules/tools" />
        </Tabs>
      )}
      {mainIdx === 1 && selEngine === 'workflow' && (
        <Tabs value={engSubIdx} onChange={(_, v) => {
          if (v === 0) navigate('/engines/workflow/runs');
          else if (v === 1) navigate('/engines/workflow/tools');
        }} centered sx={{
          '& .MuiTab-root': { fontSize: 12, minHeight: 36, py: 0.5, textTransform: 'none', color: 'text.secondary' },
          '& .Mui-selected': { color: 'primary.main !important' },
          '& .MuiTabs-indicator': { height: 2, backgroundColor: 'primary.light' }
        }}>
          <Tab label="Runs" component={Link} to="/engines/workflow/runs" />
          <Tab label="Tools" component={Link} to="/engines/workflow/tools" />
        </Tabs>
      )}
      {mainIdx === 1 && selEngine === 'jira' && (
        <Tabs value={0} centered sx={{
          '& .MuiTab-root': { fontSize: 12, minHeight: 36, py: 0.5, textTransform: 'none', color: 'text.secondary' },
          '& .Mui-selected': { color: 'primary.main !important' },
          '& .MuiTabs-indicator': { height: 2, backgroundColor: 'primary.light' }
        }}>
          <Tab label="Tools" component={Link} to="/engines/jira/tools" />
        </Tabs>
      )}
      {mainIdx === 1 && selEngine === 'git' && (
        <Tabs value={0} centered sx={{
          '& .MuiTab-root': { fontSize: 12, minHeight: 36, py: 0.5, textTransform: 'none', color: 'text.secondary' },
          '& .Mui-selected': { color: 'primary.main !important' },
          '& .MuiTabs-indicator': { height: 2, backgroundColor: 'primary.light' }
        }}>
          <Tab label="Tools" component={Link} to="/engines/git/tools" />
        </Tabs>
      )}
      {/* Diagnostics subtabs */}
      {mainIdx === 2 && (
        <Tabs value={diagSubIdx} centered sx={{
          '& .MuiTab-root': { fontSize: 12, minHeight: 32, py: 0.5, textTransform: 'none', color: 'text.secondary' },
          '& .Mui-selected': { color: 'primary.main !important' },
          '& .MuiTabs-indicator': { height: 2, backgroundColor: 'primary.light' }
        }}>
          <Tab label="Overview" component={Link} to="/diagnostics/overview" />
          <Tab label="Requests" component={Link} to="/diagnostics/requests" />
          <Tab label="Logs" component={Link} to="/diagnostics/logs" />
          <Tab label="Workflows" component={Link} to="/diagnostics/workflows" />
          <Tab label="Routes" component={Link} to="/diagnostics/routes" />
          <Tab label="API Health" component={Link} to="/diagnostics/api" />
        </Tabs>
      )}

      <Container maxWidth="lg" sx={{ mt: 2, mb: 4, flex: 1, color: 'text.primary' }}>
        <Routes>
          <Route path="/" element={<Navigate to="/dashboard" replace />} />
          <Route path="/dashboard" element={<Dashboard />} />
          <Route path="/search" element={<Navigate to="/ctx/search" replace />} />
          <Route path="/repos" element={<Navigate to="/ctx/repos" replace />} />
          {/* Legacy routes (back-compat) */}
          <Route path="/ctx/search" element={<Search />} />
          <Route path="/ctx/fts" element={<Search />} />
          <Route path="/ctx/repos" element={<Repos />} />
          <Route path="/think" element={<ThinkWorkflows />} />
          <Route path="/think/workflows" element={<ThinkWorkflows />} />
          <Route path="/think/prompts" element={<ThinkPrompts />} />
          <Route path="/think/runs" element={<ThinkRuns />} />
          <Route path="/personas" element={<Personas />} />

          {/* New Engines routes */}
          <Route path="/engines/context/resources" element={<ContextResources />} />
          <Route path="/engines/context/search" element={<Search />} />
          <Route path="/engines/context/memory-search" element={<MemorySearch />} />
          <Route path="/engines/context/repos" element={<Repos />} />
          <Route path="/engines/context/tools" element={<ContextTools />} />

          <Route path="/engines/think/workflows" element={<ThinkWorkflows />} />
          <Route path="/engines/think/workflows/new" element={<ThinkWorkflowEditor />} />
          <Route path="/engines/think/workflows/edit/:id" element={<ThinkWorkflowEditor />} />
          <Route path="/engines/think/prompts" element={<ThinkPrompts />} />
          <Route path="/engines/think/prompts/new" element={<PromptEditor />} />
          <Route path="/engines/think/prompts/edit/:version" element={<PromptEditor />} />
          <Route path="/engines/think/runs" element={<ThinkRuns />} />
          <Route path="/engines/think/tools" element={<ThinkTools />} />
          <Route path="/engines/workflow/runs" element={<WorkflowRuns />} />
          <Route path="/engines/workflow/tools" element={<WorkflowTools />} />

          <Route path="/engines/personas" element={<Personas />} />
          <Route path="/engines/personas/tools" element={<PersonasTools />} />
          <Route path="/engines/personas/new" element={<PersonaEditor />} />
          <Route path="/engines/personas/edit/:name" element={<PersonaEditor />} />
          <Route path="/engines/rules" element={<RulesPage />} />
          <Route path="/engines/rules/tools" element={<RulesTools />} />
          <Route path="/engines/rules/new" element={<RuleEditor />} />
          <Route path="/engines/rules/edit/:name" element={<RuleEditor />} />
          {/* Workflows editor moved under Think engine */}
          {/* Legacy shortcuts */}
          <Route path="/rules" element={<RulesPage />} />
          <Route path="/engines/jira/tools" element={<JiraTools />} />
          <Route path="/engines/git/tools" element={<GitTools />} />
          <Route path="/ctx/tools" element={<ContextTools />} />
          <Route path="/ctx/resources" element={<ContextResources />} />
          <Route path="/ctx/memory-search" element={<MemorySearch />} />
          <Route path="/ctx/memory" element={<MemorySearch />} />
          {/* Diagnostics routes at second-layer */}
          <Route path="/diagnostics" element={<DiagnosticsOverview />} />
          <Route path="/diagnostics/overview" element={<DiagnosticsOverview />} />
          <Route path="/diagnostics/requests" element={<DiagnosticsRequests />} />
          <Route path="/diagnostics/logs" element={<DiagnosticsLogs />} />
          <Route path="/diagnostics/agent" element={<DiagnosticsAgent />} />
          <Route path="/diagnostics/workflows" element={<DiagnosticsWorkflows />} />
          <Route path="/diagnostics/api" element={<APIHealth />} />
          <Route path="/diagnostics/routes" element={<DiagnosticsRoutes />} />
        </Routes>
      </Container>
      {/* Footer banner (always blue like header; DEV shows icon + text) */}
      <Box sx={{
        background: chromeGradient,
        color: 'rgba(255,255,255,0.8)',
        px: 2,
        py: 0.5,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        mt: 'auto'
      }}>
        <Typography variant="caption" sx={{ opacity: 0.9 }}>amdSh@2025</Typography>
        {isDev ? (
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
            <CodeIcon sx={{ fontSize: 14, opacity: 0.9 }} />
            <Typography variant="caption" sx={{ opacity: 0.9 }}>Dev-Mode</Typography>
          </Box>
        ) : (
          <Typography variant="caption" sx={{ opacity: 0.9 }}>Build-Mode</Typography>
        )}
        <Typography variant="caption" sx={{ opacity: 0.9 }}>github.com/ashabbir</Typography>
      </Box>
      </Box>
      <SettingsDialog
        open={open}
        onClose={() => setOpen(false)}
        onConfigChange={(cfg) => {
          setThemeMode(cfg.themeMode || 'light');
        }}
      />
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
