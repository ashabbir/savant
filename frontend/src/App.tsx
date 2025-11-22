import React, { useMemo, useState } from 'react';
import { Link, Route, Routes, useLocation, useNavigate } from 'react-router-dom';
import AppBar from '@mui/material/AppBar';
import Toolbar from '@mui/material/Toolbar';
import Typography from '@mui/material/Typography';
import Tabs from '@mui/material/Tabs';
import Tab from '@mui/material/Tab';
import IconButton from '@mui/material/IconButton';
import SettingsIcon from '@mui/icons-material/Settings';
import OpenInNewIcon from '@mui/icons-material/OpenInNew';
import Container from '@mui/material/Container';
import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import Alert from '@mui/material/Alert';
import { createTheme, ThemeProvider } from '@mui/material/styles';
import Search from './pages/Search';
import Repos from './pages/Repos';
import Diagnostics from './pages/Diagnostics';
import ThinkWorkflows from './pages/think/Workflows';
import ThinkPrompts from './pages/think/Prompts';
import ThinkRuns from './pages/think/Runs';
import ContextTools from './pages/context/Tools';
import ContextResources from './pages/context/Resources';
import ContextLogs from './pages/context/Logs';
import { getErrorMessage, useHubHealth } from './api';
import Tooltip from '@mui/material/Tooltip';
import SettingsDialog from './components/SettingsDialog';

function useTabIndex() {
  const location = useLocation();
  if (location.pathname.startsWith('/repos')) return 1;
  if (location.pathname.startsWith('/think')) return 2;
  if (location.pathname.startsWith('/ctx')) return 3;
  if (location.pathname.startsWith('/diagnostics')) return 4;
  return 0;
}

export default function App() {
  const [open, setOpen] = useState(false);
  const theme = useMemo(() => createTheme({}), []);
  const idx = useTabIndex();
  const navigate = useNavigate();
  const { data, isLoading, isError, error } = useHubHealth();
  const errMsg = getErrorMessage(error as any);

  return (
    <ThemeProvider theme={theme}>
      <AppBar position="static">
        <Toolbar>
          <Typography variant="h6" sx={{ flexGrow: 1 }}>Savant</Typography>
          {isLoading ? (
            <Alert severity="info" sx={{ mr: 2, p: 0, px: 1 }}>Checking hub…</Alert>
          ) : isError ? (
            <Tooltip title={errMsg}>
              <Alert severity="error" sx={{ mr: 2, p: 0, px: 1, cursor: 'help' }}>Hub unreachable</Alert>
            </Tooltip>
          ) : (
            <Alert severity="success" sx={{ mr: 2, p: 0, px: 1 }}>Hub OK</Alert>
          )}
          <IconButton color="inherit" component="a" href="/console" target="_blank" rel="noreferrer" aria-label="legacy-console" title="Open legacy console (/console)">
            <OpenInNewIcon />
          </IconButton>
          <IconButton color="inherit" onClick={() => setOpen(true)} aria-label="settings" title="Settings">
            <SettingsIcon />
          </IconButton>
        </Toolbar>
      </AppBar>
      <Tabs value={idx} onChange={(_, v) => navigate(v === 0 ? '/search' : v === 1 ? '/repos' : v === 2 ? '/think' : v === 3 ? '/ctx/tools' : '/diagnostics')} centered>
        <Tab label="Search" component={Link} to="/search" />
        <Tab label="Repos" component={Link} to="/repos" />
        <Tab label="Think" component={Link} to="/think" />
        <Tab label="Ctx Tools" component={Link} to="/ctx/tools" />
        <Tab label="Diagnostics" component={Link} to="/diagnostics" />
      </Tabs>
      <Container maxWidth="lg" sx={{ mt: 3, mb: 4 }}>
        <Routes>
          <Route path="/" element={<Search />} />
          <Route path="/search" element={<Search />} />
          <Route path="/repos" element={<Repos />} />
          <Route path="/think" element={<ThinkWorkflows />} />
          <Route path="/think/workflows" element={<ThinkWorkflows />} />
          <Route path="/think/prompts" element={<ThinkPrompts />} />
          <Route path="/think/runs" element={<ThinkRuns />} />
          <Route path="/ctx/tools" element={<ContextTools />} />
          <Route path="/ctx/resources" element={<ContextResources />} />
          <Route path="/ctx/logs" element={<ContextLogs />} />
          <Route path="/diagnostics" element={<Diagnostics />} />
      </Routes>
        <Box sx={{ mt: 4 }}>
          <Button variant="outlined" component={Link} to="/repos">Reset + Index All</Button>
        </Box>
      </Container>
      <SettingsDialog open={open} onClose={() => setOpen(false)} />
    </ThemeProvider>
  );
}
