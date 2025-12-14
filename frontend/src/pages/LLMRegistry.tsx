import React, { useState } from 'react';
import {
  Box,
  Paper,
  Typography,
  Tabs,
  Tab,
  Alert,
  CircularProgress,
  Stack,
  Button,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  TextField,
  Select,
  MenuItem,
  FormControl,
  InputLabel,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Chip,
  IconButton,
  Tooltip,
  Switch,
  Checkbox,
  useTheme,
} from '@mui/material';
import DeleteIcon from '@mui/icons-material/Delete';
import CheckCircleIcon from '@mui/icons-material/CheckCircle';
import ErrorIcon from '@mui/icons-material/Error';
import RefreshIcon from '@mui/icons-material/Refresh';
import EditIcon from '@mui/icons-material/Edit';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { callEngineTool } from '../api';

interface TabPanelProps {
  children?: React.ReactNode;
  index: number;
  value: number;
}

function TabPanel(props: TabPanelProps) {
  const { children, value, index, ...other } = props;
  return (
    <div
      role="tabpanel"
      hidden={value !== index}
      id={`llm-tabpanel-${index}`}
      aria-labelledby={`llm-tab-${index}`}
      {...other}
    >
      {value === index && <Box sx={{ p: 3 }}>{children}</Box>}
    </div>
  );
}

interface Provider {
  id: number;
  name: string;
  provider_type: string;
  status: string;
  base_url?: string;
  last_validated_at?: string;
}

interface Model {
  id: number;
  provider_id: number;
  provider_name: string;
  provider_model_id: string;
  display_name: string;
  modality: string[];
  context_window?: number;
  enabled: boolean;
}

export default function LLMRegistry() {
  const theme = useTheme();
  const formatModality = (modality: string[] | string | undefined) => {
    const raw = Array.isArray(modality) ? modality : modality ? [modality] : [];
    return raw
      .flatMap((entry) =>
        entry
          .replace(/[{}]/g, '')
          .split(',')
          .map((token) => token.trim())
      )
      .filter(Boolean);
  };
  const [tabValue, setTabValue] = useState(0);
  const [openProviderDialog, setOpenProviderDialog] = useState(false);
  const [openDiscoverDialog, setOpenDiscoverDialog] = useState(false);
  const [openEditProviderDialog, setOpenEditProviderDialog] = useState(false);

  const queryClient = useQueryClient();

  // Provider form state
  const [providerForm, setProviderForm] = useState({ name: '', type: 'google', apiKey: '', baseUrl: '' });
  const [discoverProvider, setDiscoverProvider] = useState('');
  const [providerEditForm, setProviderEditForm] = useState({ baseUrl: '', apiKey: '' });
  const [selectedProvider, setSelectedProvider] = useState<Provider | null>(null);
  const [discoveredModels, setDiscoveredModels] = useState<any[]>([]);
  const [selectedDiscoverIds, setSelectedDiscoverIds] = useState<string[]>([]);
  const [discoverError, setDiscoverError] = useState<string | null>(null);
  const [discoveryAttempted, setDiscoveryAttempted] = useState(false);
  const closeEditProviderDialog = () => {
    setOpenEditProviderDialog(false);
    setSelectedProvider(null);
    setProviderEditForm({ baseUrl: '', apiKey: '' });
  };

  const closeDiscoverDialog = () => {
    setOpenDiscoverDialog(false);
    setDiscoveryAttempted(false);
    setDiscoveredModels([]);
    setSelectedDiscoverIds([]);
    setDiscoverError(null);
  };

  const handleDiscover = () => {
    setDiscoverError(null);
    setDiscoveredModels([]);
    setSelectedDiscoverIds([]);
    setDiscoveryAttempted(true);
    discoverMutation.mutate(discoverProvider);
  };

  const toggleDiscoveredSelection = (modelId: string) => {
    setSelectedDiscoverIds((prev) =>
      prev.includes(modelId) ? prev.filter((id) => id !== modelId) : [...prev, modelId]
    );
  };

  // Fetch providers
  const providersQuery = useQuery({
    queryKey: ['llm', 'providers'],
    queryFn: async () => {
      const res = await callEngineTool('llm', 'llm_providers_list', {});
      return res.providers || [];
    },
  });

  // Fetch models
  const modelsQuery = useQuery({
    queryKey: ['llm', 'models'],
    queryFn: async () => {
      const res = await callEngineTool('llm', 'llm_models_list', {});
      return res.models || [];
    },
  });

  // Discover models
  const discoverMutation = useMutation({
    mutationFn: async (providerName: string) => {
      const res = await callEngineTool('llm', 'llm_models_discover', { provider_name: providerName });
      return res.models || [];
    },
    onSuccess: (models) => {
      setDiscoveredModels(models);
      setSelectedDiscoverIds([]);
      setDiscoverError(null);
    },
    onError: (error: any) => {
      const message = error?.message || 'Failed to discover models';
      setDiscoverError(message);
      setDiscoveredModels([]);
    },
  });

  // Create provider
  const createProviderMutation = useMutation({
    mutationFn: async (data: typeof providerForm) => {
      await callEngineTool('llm', 'llm_providers_create', {
        name: data.name,
        provider_type: data.type,
        base_url: data.baseUrl || undefined,
        api_key: data.apiKey || undefined,
      });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['llm', 'providers'] });
      setOpenProviderDialog(false);
      setProviderForm({ name: '', type: 'google', apiKey: '', baseUrl: '' });
    },
  });

  // Test provider
const testProviderMutation = useMutation({
  mutationFn: async (name: string) => {
    const res = await callEngineTool('llm', 'llm_providers_test', { name });
    return res;
  },
  onSuccess: () => {
    queryClient.invalidateQueries({ queryKey: ['llm', 'providers'] });
  },
});

// Delete provider
const deleteProviderMutation = useMutation({
  mutationFn: async (name: string) => {
    await callEngineTool('llm', 'llm_providers_delete', { name });
  },
  onSuccess: () => {
    queryClient.invalidateQueries({ queryKey: ['llm', 'providers'] });
    queryClient.invalidateQueries({ queryKey: ['llm', 'models'] });
  },
});

const updateProviderMutation = useMutation({
  mutationFn: async ({ name, data }: { name: string; data: typeof providerEditForm }) => {
    await callEngineTool('llm', 'llm_providers_update', {
      name,
      base_url: data.baseUrl || undefined,
      api_key: data.apiKey || undefined,
    });
  },
  onSuccess: () => {
    queryClient.invalidateQueries({ queryKey: ['llm', 'providers'] });
    setOpenEditProviderDialog(false);
    setSelectedProvider(null);
    setProviderEditForm({ baseUrl: '', apiKey: '' });
  },
});

const openEditProviderDialogWith = (provider: Provider) => {
  setSelectedProvider(provider);
  setProviderEditForm({ baseUrl: provider.base_url || '', apiKey: '' });
  setOpenEditProviderDialog(true);
};

  const registerDiscoveredMutation = useMutation({
    mutationFn: async ({ providerName, modelIds }: { providerName: string; modelIds: string[] }) => {
      if (!modelIds.length) {
        throw new Error('Select at least one model to register');
      }
      await callEngineTool('llm', 'llm_models_register', {
        provider_name: providerName,
        model_ids: modelIds,
      });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['llm', 'models'] });
      setSelectedDiscoverIds([]);
      setDiscoveredModels([]);
      setOpenDiscoverDialog(false);
      setDiscoverError(null);
      setDiscoveryAttempted(false);
    },
    onError: (error: any) => {
      const message = error?.message || 'Failed to register selected models';
      setDiscoverError(message);
    },
  });

  // Delete model
  const deleteModelMutation = useMutation({
    mutationFn: async (modelId: number) => {
      await callEngineTool('llm', 'llm_models_delete', { model_id: modelId });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['llm', 'models'] });
    },
  });

  const toggleModelMutation = useMutation({
    mutationFn: async ({ modelId, enabled }: { modelId: number; enabled: boolean }) => {
      await callEngineTool('llm', 'llm_models_set_enabled', { model_id: modelId, enabled });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['llm', 'models'] });
    },
  });

  
  const getStatusColor = (status: string) => {
    if (status === 'valid') return 'success';
    if (status === 'invalid') return 'error';
    return 'default';
  };

  return (
    <Box>
      <Paper sx={{ mb: 3 }}>
        <Box sx={{ p: 2 }}>
          <Typography variant="h4" sx={{ fontWeight: 600 }}>
            LLM Registry
          </Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
            Manage LLM providers, models, and agents
          </Typography>
        </Box>

        <Tabs
          value={tabValue}
          onChange={(_, newValue) => setTabValue(newValue)}
          sx={{ borderBottom: 1, borderColor: 'divider' }}
          aria-label="llm registry tabs"
        >
          <Tab label="Providers" id="llm-tab-0" aria-controls="llm-tabpanel-0" />
          <Tab label="Models" id="llm-tab-1" aria-controls="llm-tabpanel-1" />
        </Tabs>
      </Paper>

      {/* Providers Tab */}
      <TabPanel value={tabValue} index={0}>
        <Stack spacing={2}>
          <Box display="flex" gap={1} justifyContent="space-between" alignItems="center">
            <Typography variant="h6">Providers</Typography>
            <Stack direction="row" spacing={1}>
              <Button
                variant="contained"
                color="primary"
                onClick={() => setOpenProviderDialog(true)}
              >
                Add Provider
              </Button>
              <IconButton
                onClick={() => providersQuery.refetch()}
                disabled={providersQuery.isLoading}
              >
                <RefreshIcon />
              </IconButton>
            </Stack>
          </Box>

          {providersQuery.isLoading && <CircularProgress />}
          {providersQuery.isError && (
            <Alert severity="error">Failed to load providers</Alert>
          )}

          {providersQuery.data && providersQuery.data.length === 0 && (
            <Alert severity="info">No providers configured. Add one to get started.</Alert>
          )}

          {providersQuery.data && providersQuery.data.length > 0 && (
            <TableContainer>
              <Table>
                <TableHead>
                  <TableRow sx={{ bgcolor: theme.palette.mode === 'dark' ? theme.palette.grey[900] : 'grey.100' }}>
                    <TableCell>Name</TableCell>
                    <TableCell>Type</TableCell>
                    <TableCell>Status</TableCell>
                    <TableCell>Last Validated</TableCell>
                    <TableCell align="right">Actions</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {(providersQuery.data as Provider[]).map((provider) => (
                    <TableRow key={provider.id}>
                      <TableCell>{provider.name}</TableCell>
                      <TableCell>
                        <Chip
                          label={provider.provider_type}
                          size="small"
                          variant="outlined"
                        />
                      </TableCell>
                      <TableCell>
                        <Chip
                          icon={
                            provider.status === 'valid' ? (
                              <CheckCircleIcon />
                            ) : (
                              <ErrorIcon />
                            )
                          }
                          label={provider.status}
                          color={getStatusColor(provider.status) as any}
                          size="small"
                        />
                      </TableCell>
                      <TableCell>
                        {provider.last_validated_at
                          ? new Date(provider.last_validated_at).toLocaleDateString()
                          : 'Never'}
                      </TableCell>
                      <TableCell align="right">
                        <Tooltip title="Edit provider">
                          <IconButton
                            size="small"
                            onClick={() => openEditProviderDialogWith(provider)}
                          >
                            <EditIcon fontSize="small" />
                          </IconButton>
                        </Tooltip>
                        <Tooltip title="Test Connection">
                          <IconButton
                            size="small"
                            onClick={() =>
                              testProviderMutation.mutate(provider.name)
                            }
                            disabled={testProviderMutation.isPending}
                          >
                            <CheckCircleIcon fontSize="small" />
                          </IconButton>
                        </Tooltip>
                        <Tooltip title="Delete">
                          <IconButton
                            size="small"
                            onClick={() =>
                              deleteProviderMutation.mutate(provider.name)
                            }
                            disabled={deleteProviderMutation.isPending}
                          >
                            <DeleteIcon fontSize="small" />
                          </IconButton>
                        </Tooltip>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </TableContainer>
          )}
        </Stack>
      </TabPanel>

      {/* Models Tab */}
      <TabPanel value={tabValue} index={1}>
        <Stack spacing={2}>
          <Box display="flex" gap={1} justifyContent="space-between" alignItems="center">
            <Typography variant="h6">Models</Typography>
            <Stack direction="row" spacing={1}>
              <Button
                variant="contained"
                color="primary"
                onClick={() => setOpenDiscoverDialog(true)}
              >
                Discover Models
              </Button>
              <IconButton
                onClick={() => modelsQuery.refetch()}
                disabled={modelsQuery.isLoading}
              >
                <RefreshIcon />
              </IconButton>
            </Stack>
          </Box>

          {modelsQuery.isLoading && <CircularProgress />}
          {modelsQuery.isError && (
            <Alert severity="error">Failed to load models</Alert>
          )}

          {modelsQuery.data && modelsQuery.data.length === 0 && (
            <Alert severity="info">No models registered. Discover and register models from providers.</Alert>
          )}

          {modelsQuery.data && modelsQuery.data.length > 0 && (
            <TableContainer>
              <Table>
                <TableHead>
                  <TableRow sx={{ bgcolor: theme.palette.mode === 'dark' ? theme.palette.grey[900] : 'grey.100' }}>
                    <TableCell>Model</TableCell>
                    <TableCell>Provider</TableCell>
                    <TableCell>Modality</TableCell>
                    <TableCell>Context Window</TableCell>
                    <TableCell>Enabled</TableCell>
                    <TableCell align="right">Actions</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {(modelsQuery.data as Model[]).map((model) => (
                    <TableRow key={model.id}>
                      <TableCell>{model.display_name}</TableCell>
                      <TableCell>{model.provider_name}</TableCell>
                      <TableCell>
                        <Stack direction="row" spacing={0.5} flexWrap="wrap">
                          {formatModality(model.modality).length === 0 ? (
                            <Chip label="Unknown" size="small" variant="outlined" />
                          ) : (
                            formatModality(model.modality).map((m) => (
                              <Chip key={m} label={m} size="small" variant="outlined" />
                            ))
                          )}
                        </Stack>
                      </TableCell>
                      <TableCell>
                        {model.context_window
                          ? `${(model.context_window / 1000).toFixed(1)}k`
                          : '-'}
                      </TableCell>
                      <TableCell>
                        <Switch
                          checked={model.enabled}
                          onChange={() =>
                            toggleModelMutation.mutate({ modelId: model.id, enabled: !model.enabled })
                          }
                          disabled={toggleModelMutation.isPending}
                          color="primary"
                          inputProps={{ 'aria-label': 'toggle model enabled' }}
                        />
                      </TableCell>
                      <TableCell align="right">
                        <Tooltip title="Delete model">
                          <IconButton
                            size="small"
                            onClick={() => deleteModelMutation.mutate(model.id)}
                            disabled={deleteModelMutation.isPending}
                          >
                            <DeleteIcon fontSize="small" />
                          </IconButton>
                        </Tooltip>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </TableContainer>
          )}
        </Stack>
      </TabPanel>

      {/* Add Provider Dialog */}
      <Dialog open={openProviderDialog} onClose={() => setOpenProviderDialog(false)} maxWidth="sm" fullWidth>
        <DialogTitle>Add LLM Provider</DialogTitle>
        <DialogContent sx={{ pt: 2 }}>
          <Stack spacing={2}>
            <TextField
              label="Provider Name"
              value={providerForm.name}
              onChange={(e) => setProviderForm({ ...providerForm, name: e.target.value })}
              fullWidth
            />
            <FormControl fullWidth>
              <InputLabel>Provider Type</InputLabel>
              <Select
                value={providerForm.type}
                onChange={(e) => setProviderForm({ ...providerForm, type: e.target.value })}
                label="Provider Type"
              >
                <MenuItem value="google">Google</MenuItem>
                <MenuItem value="ollama">Ollama</MenuItem>
              </Select>
            </FormControl>

            {providerForm.type === 'google' && (
              <TextField
                label="API Key"
                type="password"
                value={providerForm.apiKey}
                onChange={(e) => setProviderForm({ ...providerForm, apiKey: e.target.value })}
                fullWidth
              />
            )}

            {providerForm.type === 'ollama' && (
              <TextField
                label="Base URL"
                placeholder="http://localhost:11434"
                value={providerForm.baseUrl}
                onChange={(e) => setProviderForm({ ...providerForm, baseUrl: e.target.value })}
                fullWidth
              />
            )}
          </Stack>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setOpenProviderDialog(false)}>Cancel</Button>
          <Button
            onClick={() => createProviderMutation.mutate(providerForm)}
            variant="contained"
            disabled={createProviderMutation.isPending || !providerForm.name}
          >
            Add Provider
          </Button>
        </DialogActions>
      </Dialog>

      {/* Edit Provider Dialog */}
      <Dialog
        open={openEditProviderDialog}
        onClose={closeEditProviderDialog}
        maxWidth="sm"
        fullWidth
      >
        <DialogTitle>Edit Provider</DialogTitle>
        <DialogContent sx={{ pt: 2 }}>
          <Stack spacing={2}>
            <TextField
              label="Base URL"
              value={providerEditForm.baseUrl}
              onChange={(e) => setProviderEditForm({ ...providerEditForm, baseUrl: e.target.value })}
              fullWidth
            />
            <TextField
              label="API Key"
              type="password"
              value={providerEditForm.apiKey}
              onChange={(e) => setProviderEditForm({ ...providerEditForm, apiKey: e.target.value })}
              helperText="Leave blank to keep existing key"
              fullWidth
            />
          </Stack>
        </DialogContent>
        <DialogActions>
          <Button onClick={closeEditProviderDialog}>Cancel</Button>
          <Button
            onClick={() =>
              selectedProvider &&
              updateProviderMutation.mutate({ name: selectedProvider.name, data: providerEditForm })
            }
            variant="contained"
            disabled={!selectedProvider || updateProviderMutation.isPending}
          >
            Save Changes
          </Button>
        </DialogActions>
      </Dialog>

      {/* Discover Models Dialog */}
      <Dialog open={openDiscoverDialog} onClose={closeDiscoverDialog} maxWidth="sm" fullWidth>
        <DialogTitle>Discover Available Models</DialogTitle>
        <DialogContent sx={{ pt: 2 }}>
          <FormControl fullWidth>
            <InputLabel>Provider</InputLabel>
            <Select
              value={discoverProvider}
              onChange={(e) => setDiscoverProvider(e.target.value)}
              label="Provider"
            >
              {(providersQuery.data as Provider[])?.map((p) => (
                <MenuItem key={p.id} value={p.name}>{p.name}</MenuItem>
              ))}
            </Select>
          </FormControl>
          <Box sx={{ mt: 2 }}>
            {discoverMutation.isLoading && <CircularProgress size={24} />}
            {discoverError && <Alert severity="error" sx={{ mt: 1 }}>{discoverError}</Alert>}
            {!discoverMutation.isLoading && !discoverError && discoverProvider && discoveredModels.length === 0 && discoveryAttempted && (
              <Alert severity="info" sx={{ mt: 1 }}>
                No models were found for {discoverProvider}. Try a different provider.
              </Alert>
            )}
            {discoveredModels.length > 0 && (
              <TableContainer sx={{ maxHeight: 240, mt: 1 }}>
                <Table size="small">
                  <TableHead>
                    <TableRow>
                      <TableCell padding="checkbox"></TableCell>
                      <TableCell>Model Name</TableCell>
                      <TableCell>Model ID</TableCell>
                      <TableCell>Modality</TableCell>
                    </TableRow>
                  </TableHead>
                  <TableBody>
                    {discoveredModels.map((model: any) => (
                      <TableRow key={model.provider_model_id} hover>
                        <TableCell padding="checkbox">
                          <Checkbox
                            size="small"
                            checked={selectedDiscoverIds.includes(model.provider_model_id)}
                            onChange={() => toggleDiscoveredSelection(model.provider_model_id)}
                          />
                        </TableCell>
                        <TableCell>{model.display_name || model.provider_model_id}</TableCell>
                        <TableCell>{model.provider_model_id}</TableCell>
                        <TableCell>
                        <Stack direction="row" spacing={0.5} flexWrap="wrap">
                          {formatModality(model.modality).length === 0 ? (
                            <Chip label="Unknown" size="small" variant="outlined" />
                          ) : (
                            formatModality(model.modality).map((m: string) => (
                              <Chip key={m} label={m} size="small" variant="outlined" />
                            ))
                          )}
                        </Stack>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </TableContainer>
            )}
          </Box>
        </DialogContent>
        <DialogActions>
          <Button onClick={closeDiscoverDialog}>Cancel</Button>
          <Button
            onClick={handleDiscover}
            variant="contained"
            disabled={discoverMutation.isPending || !discoverProvider}
          >
            Discover
          </Button>
          <Button
            onClick={() =>
              discoverProvider &&
              registerDiscoveredMutation.mutate({ providerName: discoverProvider, modelIds: selectedDiscoverIds })
            }
            variant="contained"
            color="success"
            disabled={
              selectedDiscoverIds.length === 0 ||
              registerDiscoveredMutation.isPending ||
              !discoverProvider
            }
          >
            Register Selected
          </Button>
        </DialogActions>
      </Dialog>

    </Box>
  );
}
