import React, { useState } from 'react';
import Box from '@mui/material/Box';
import Tabs from '@mui/material/Tabs';
import Tab from '@mui/material/Tab';
import Paper from '@mui/material/Paper';
import DashboardIcon from '@mui/icons-material/Dashboard';
import TerminalIcon from '@mui/icons-material/Terminal';
import HttpIcon from '@mui/icons-material/Http';
import RouteIcon from '@mui/icons-material/Route';
import DiagnosticsOverview from './diagnostics/Overview';
import DiagnosticsLogs from './diagnostics/Logs';
import DiagnosticsRequests from './diagnostics/Requests';
import DiagnosticsRoutes from './diagnostics/Routes';

export default function Diagnostics() {
  const [tab, setTab] = useState<number>(() => {
    const saved = localStorage.getItem('diag.tab');
    return saved ? parseInt(saved, 10) : 0;
  });

  const handleTabChange = (_: React.SyntheticEvent, newValue: number) => {
    setTab(newValue);
    localStorage.setItem('diag.tab', String(newValue));
  };

  return (
    <Box>
      <Paper sx={{ mb: 2 }}>
        <Tabs
          value={tab}
          onChange={handleTabChange}
          centered
          sx={{
            '& .MuiTab-root': { fontSize: 12, minHeight: 36, py: 0.5, textTransform: 'none' },
            '& .MuiTabs-indicator': { height: 2 }
          }}
        >
          <Tab icon={<DashboardIcon />} iconPosition="start" label="Overview" />
          <Tab icon={<HttpIcon />} iconPosition="start" label="Requests" />
          <Tab icon={<TerminalIcon />} iconPosition="start" label="Logs" />
          <Tab icon={<RouteIcon />} iconPosition="start" label="Routes" />
        </Tabs>
      </Paper>

      {tab === 0 && <DiagnosticsOverview />}
      {tab === 1 && <DiagnosticsRequests />}
      {tab === 2 && <DiagnosticsLogs />}
      {tab === 3 && <DiagnosticsRoutes />}
    </Box>
  );
}
