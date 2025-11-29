import React, { useState, useMemo } from 'react';
import Box from '@mui/material/Box';
import Paper from '@mui/material/Paper';
import Typography from '@mui/material/Typography';
import Stack from '@mui/material/Stack';
import TextField from '@mui/material/TextField';
import Select from '@mui/material/Select';
import MenuItem from '@mui/material/MenuItem';
import FormControl from '@mui/material/FormControl';
import InputLabel from '@mui/material/InputLabel';
import LinearProgress from '@mui/material/LinearProgress';
import Alert from '@mui/material/Alert';
import Table from '@mui/material/Table';
import TableBody from '@mui/material/TableBody';
import TableCell from '@mui/material/TableCell';
import TableContainer from '@mui/material/TableContainer';
import TableHead from '@mui/material/TableHead';
import TableRow from '@mui/material/TableRow';
import TableSortLabel from '@mui/material/TableSortLabel';
import Chip from '@mui/material/Chip';
import RouteIcon from '@mui/icons-material/Route';
import { useRoutes, RouteInfo } from '../../api';

type SortKey = 'module' | 'method' | 'path' | 'description';
type SortDir = 'asc' | 'desc';

export default function DiagnosticsRoutes() {
  const { data, isLoading, isError, error } = useRoutes();
  const [moduleFilter, setModuleFilter] = useState<string>('');
  const [methodFilter, setMethodFilter] = useState<string>('');
  const [searchFilter, setSearchFilter] = useState<string>('');
  const [sortKey, setSortKey] = useState<SortKey>('path');
  const [sortDir, setSortDir] = useState<SortDir>('asc');

  const routes = data?.routes || [];

  // Get unique modules and methods for filters
  const modules = useMemo(() => {
    const unique = [...new Set(routes.map(r => r.module))].filter(Boolean).sort();
    return unique;
  }, [routes]);

  const methods = useMemo(() => {
    const unique = [...new Set(routes.map(r => r.method))].filter(Boolean).sort();
    return unique;
  }, [routes]);

  // Filter and sort routes
  const filteredRoutes = useMemo(() => {
    let filtered = routes;

    if (moduleFilter) {
      filtered = filtered.filter(r => r.module === moduleFilter);
    }

    if (methodFilter) {
      filtered = filtered.filter(r => r.method === methodFilter);
    }

    if (searchFilter) {
      const search = searchFilter.toLowerCase();
      filtered = filtered.filter(r =>
        r.path.toLowerCase().includes(search) ||
        (r.description || '').toLowerCase().includes(search)
      );
    }

    // Sort
    filtered = [...filtered].sort((a, b) => {
      const aVal = a[sortKey] || '';
      const bVal = b[sortKey] || '';
      const cmp = aVal.localeCompare(bVal);
      return sortDir === 'asc' ? cmp : -cmp;
    });

    return filtered;
  }, [routes, moduleFilter, methodFilter, searchFilter, sortKey, sortDir]);

  const handleSort = (key: SortKey) => {
    if (sortKey === key) {
      setSortDir(sortDir === 'asc' ? 'desc' : 'asc');
    } else {
      setSortKey(key);
      setSortDir('asc');
    }
  };

  const getMethodColor = (method: string): 'success' | 'primary' | 'warning' | 'error' | 'default' => {
    switch (method.toUpperCase()) {
      case 'GET': return 'primary';
      case 'POST': return 'success';
      case 'PUT': return 'warning';
      case 'DELETE': return 'error';
      default: return 'default';
    }
  };

  if (isLoading) {
    return (
      <Box sx={{ flex: 1, minHeight: 0, overflow: 'auto' }}>
        <LinearProgress />
      </Box>
    );
  }

  if (isError) {
    return (
      <Box sx={{ flex: 1, minHeight: 0, overflow: 'auto', p: 2 }}>
        <Alert severity="error">
          Failed to load routes: {error?.message || 'Unknown error'}
        </Alert>
      </Box>
    );
  }

  return (
    <Box sx={{ flex: 1, minHeight: 0, overflow: 'auto', display: 'flex', flexDirection: 'column' }}>
      {/* Header */}
      <Paper sx={{ p: 1.5, mb: 1.5 }}>
        <Stack direction="row" spacing={1} alignItems="center">
          <RouteIcon color="primary" />
          <Typography variant="h6" sx={{ fontSize: 14, fontWeight: 600 }}>
            API Routes
          </Typography>
          <Chip size="small" label={`${filteredRoutes.length} of ${routes.length}`} sx={{ ml: 1 }} />
        </Stack>
      </Paper>

      {/* Filters */}
      <Paper sx={{ p: 2, mb: 1.5 }}>
        <Stack direction="row" spacing={2} flexWrap="wrap" useFlexGap>
          <FormControl size="small" sx={{ minWidth: 150 }}>
            <InputLabel>Module</InputLabel>
            <Select
              value={moduleFilter}
              label="Module"
              onChange={(e) => setModuleFilter(e.target.value)}
            >
              <MenuItem value="">All Modules</MenuItem>
              {modules.map(m => (
                <MenuItem key={m} value={m}>{m}</MenuItem>
              ))}
            </Select>
          </FormControl>

          <FormControl size="small" sx={{ minWidth: 120 }}>
            <InputLabel>Method</InputLabel>
            <Select
              value={methodFilter}
              label="Method"
              onChange={(e) => setMethodFilter(e.target.value)}
            >
              <MenuItem value="">All Methods</MenuItem>
              {methods.map(m => (
                <MenuItem key={m} value={m}>{m}</MenuItem>
              ))}
            </Select>
          </FormControl>

          <TextField
            size="small"
            label="Search path or description"
            value={searchFilter}
            onChange={(e) => setSearchFilter(e.target.value)}
            sx={{ flexGrow: 1, minWidth: 200 }}
          />
        </Stack>
      </Paper>

      {/* Routes Table */}
      <Paper sx={{ flex: 1, minHeight: 0, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
        <TableContainer sx={{ flex: 1, minHeight: 0, overflow: 'auto' }}>
          <Table stickyHeader size="small">
            <TableHead>
              <TableRow>
                <TableCell sx={{ fontWeight: 600, bgcolor: 'background.default' }}>
                  <TableSortLabel
                    active={sortKey === 'module'}
                    direction={sortKey === 'module' ? sortDir : 'asc'}
                    onClick={() => handleSort('module')}
                  >
                    Module
                  </TableSortLabel>
                </TableCell>
                <TableCell sx={{ fontWeight: 600, bgcolor: 'background.default' }}>
                  <TableSortLabel
                    active={sortKey === 'method'}
                    direction={sortKey === 'method' ? sortDir : 'asc'}
                    onClick={() => handleSort('method')}
                  >
                    Method
                  </TableSortLabel>
                </TableCell>
                <TableCell sx={{ fontWeight: 600, bgcolor: 'background.default' }}>
                  <TableSortLabel
                    active={sortKey === 'path'}
                    direction={sortKey === 'path' ? sortDir : 'asc'}
                    onClick={() => handleSort('path')}
                  >
                    Path
                  </TableSortLabel>
                </TableCell>
                <TableCell sx={{ fontWeight: 600, bgcolor: 'background.default' }}>
                  <TableSortLabel
                    active={sortKey === 'description'}
                    direction={sortKey === 'description' ? sortDir : 'asc'}
                    onClick={() => handleSort('description')}
                  >
                    Description
                  </TableSortLabel>
                </TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {filteredRoutes.map((route, idx) => (
                <TableRow key={idx} hover>
                  <TableCell>
                    <Chip size="small" label={route.module} variant="outlined" />
                  </TableCell>
                  <TableCell>
                    <Chip
                      size="small"
                      label={route.method}
                      color={getMethodColor(route.method)}
                      sx={{ minWidth: 60, fontFamily: 'monospace', fontWeight: 600 }}
                    />
                  </TableCell>
                  <TableCell sx={{ fontFamily: 'monospace', fontSize: 12 }}>
                    {route.path}
                  </TableCell>
                  <TableCell sx={{ fontSize: 12, color: 'text.secondary' }}>
                    {route.description || '—'}
                  </TableCell>
                </TableRow>
              ))}
              {filteredRoutes.length === 0 && (
                <TableRow>
                  <TableCell colSpan={4} align="center" sx={{ py: 4, color: 'text.secondary' }}>
                    No routes found matching your filters
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </TableContainer>
      </Paper>
    </Box>
  );
}
