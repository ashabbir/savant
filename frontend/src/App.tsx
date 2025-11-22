import React, { useMemo, useState } from 'react';
import { Link, Route, Routes, useLocation, useNavigate } from 'react-router-dom';
import AppBar from '@mui/material/AppBar';
import Toolbar from '@mui/material/Toolbar';
import Typography from '@mui/material/Typography';
import Tabs from '@mui/material/Tabs';
import Tab from '@mui/material/Tab';
import IconButton from '@mui/material/IconButton';
import SettingsIcon from '@mui/icons-material/Settings';
import Container from '@mui/material/Container';
import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import Alert from '@mui/material/Alert';
import { createTheme, ThemeProvider } from '@mui/material/styles';
import Search from './pages/Search';
import Repos from './pages/Repos';
import { getErrorMessage, useHubHealth } from './api';
import Tooltip from '@mui/material/Tooltip';
import SettingsDialog from './components/SettingsDialog';

function useTabIndex() {
  const location = useLocation();
  if (location.pathname.startsWith('/repos')) return 1;
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
          <IconButton color="inherit" onClick={() => setOpen(true)} aria-label="settings">
            <SettingsIcon />
          </IconButton>
        </Toolbar>
      </AppBar>
      <Tabs value={idx} onChange={(_, v) => navigate(v === 0 ? '/search' : '/repos')} centered>
        <Tab label="Search" component={Link} to="/search" />
        <Tab label="Repos" component={Link} to="/repos" />
      </Tabs>
      <Container maxWidth="lg" sx={{ mt: 3, mb: 4 }}>
        <Routes>
          <Route path="/" element={<Search />} />
          <Route path="/search" element={<Search />} />
          <Route path="/repos" element={<Repos />} />
        </Routes>
        <Box sx={{ mt: 4 }}>
          <Button variant="outlined" component={Link} to="/repos">Reset + Index All</Button>
        </Box>
      </Container>
      <SettingsDialog open={open} onClose={() => setOpen(false)} />
    </ThemeProvider>
  );
}
