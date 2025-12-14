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
  FormControlLabel,
  Switch,
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
  const [tabValue, setTabValue] = useState(0);
  const [openProviderDialog, setOpenProviderDialog] = useState(false);
  const [openModelDialog, setOpenModelDialog] = useState(false);
  const [openDiscoverDialog, setOpenDiscoverDialog] = useState(false);
  const [openEditModelDialog, setOpenEditModelDialog] = useState(false);

  const queryClient = useQueryClient();

  // Provider form state
  const [providerForm, setProviderForm] = useState({ name: '', type: 'google', apiKey: '', baseUrl: '' });
  const [modelForm, setModelForm] = useState({ provider: '', modelIds: [] as string[] });
  const [discoverProvider, setDiscoverProvider] = useState('');
  const [editModelForm, setEditModelForm] = useState({ displayName: '', contextWindow: '', enabled: true });
  const [selectedModel, setSelectedModel] = useState<Model | null>(null);
  const closeEditModelDialog = () => {
    setOpenEditModelDialog(false);
    setSelectedModel(null);
    setEditModelForm({ displayName: '', contextWindow: '', enabled: true });
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
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['llm', 'models'] });
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

  // Register models
  const registerModelsMutation = useMutation({
    mutationFn: async (data: typeof modelForm) => {
      await callEngineTool('llm', 'llm_models_register', {
        provider_name: data.provider,
        model_ids: data.modelIds,
      });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['llm', 'models'] });
      setOpenModelDialog(false);
      setModelForm({ provider: '', modelIds: [] });
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

  const updateModelMutation = useMutation({
    mutationFn: async ({ modelId, data }: { modelId: number; data: typeof editModelForm }) => {
      await callEngineTool('llm', 'llm_models_update', {
        model_id: modelId,
        display_name: data.displayName,
        context_window: data.contextWindow ? parseInt(data.contextWindow, 10) : undefined,
        enabled: data.enabled,
      });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['llm', 'models'] });
      setOpenEditModelDialog(false);
      setSelectedModel(null);
      setEditModelForm({ displayName: '', contextWindow: '', enabled: true });
    },
  });

  const openEditModelDialogWith = (model: Model) => {
    setSelectedModel(model);
    setEditModelForm({
      displayName: model.display_name,
      contextWindow: model.context_window ? String(model.context_window) : '',
      enabled: model.enabled,
    });
    setOpenEditModelDialog(true);
  };

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
              <Button
                variant="outlined"
                color="primary"
                onClick={() => setOpenModelDialog(true)}
              >
                Register Models
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
                          {(Array.isArray(model.modality) ? model.modality : []).map((m) => (
                            <Chip key={m} label={m} size="small" variant="outlined" />
                          ))}
                        </Stack>
                      </TableCell>
                      <TableCell>
                        {model.context_window
                          ? `${(model.context_window / 1000).toFixed(1)}k`
                          : '-'}
                      </TableCell>
                      <TableCell>
                        <Chip
                          label={model.enabled ? 'Enabled' : 'Disabled'}
                          color={model.enabled ? 'success' : 'default'}
                          size="small"
                        />
                      </TableCell>
                      <TableCell align="right">
                        <Tooltip title="Edit model">
                          <IconButton
                            size="small"
                            onClick={() => openEditModelDialogWith(model)}
                          >
                            <EditIcon fontSize="small" />
                          </IconButton>
                        </Tooltip>
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

      {/* Discover Models Dialog */}
      <Dialog open={openDiscoverDialog} onClose={() => setOpenDiscoverDialog(false)} maxWidth="sm" fullWidth>
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
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setOpenDiscoverDialog(false)}>Cancel</Button>
          <Button
            onClick={() => {
              discoverMutation.mutate(discoverProvider);
              setOpenDiscoverDialog(false);
            }}
            variant="contained"
            disabled={discoverMutation.isPending || !discoverProvider}
          >
            Discover
          </Button>
        </DialogActions>
      </Dialog>

      {/* Register Models Dialog */}
      <Dialog open={openModelDialog} onClose={() => setOpenModelDialog(false)} maxWidth="sm" fullWidth>
        <DialogTitle>Register Models</DialogTitle>
        <DialogContent sx={{ pt: 2 }}>
          <Stack spacing={2}>
            <FormControl fullWidth>
              <InputLabel>Provider</InputLabel>
              <Select
                value={modelForm.provider}
                onChange={(e) => setModelForm({ ...modelForm, provider: e.target.value })}
                label="Provider"
              >
                {(providersQuery.data as Provider[])?.map((p) => (
                  <MenuItem key={p.id} value={p.name}>{p.name}</MenuItem>
                ))}
              </Select>
            </FormControl>
            <Typography variant="body2" color="text.secondary">
              Model IDs will be fetched from the provider. Register by entering model identifiers.
            </Typography>
          </Stack>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setOpenModelDialog(false)}>Cancel</Button>
          <Button
            onClick={() => registerModelsMutation.mutate(modelForm)}
            variant="contained"
            disabled={registerModelsMutation.isPending || !modelForm.provider}
          >
            Register
          </Button>
        </DialogActions>
      </Dialog>

      {/* Edit Model Dialog */}
      <Dialog
        open={openEditModelDialog}
        onClose={closeEditModelDialog}
        maxWidth="sm"
        fullWidth
      >
        <DialogTitle>Edit Model</DialogTitle>
        <DialogContent sx={{ pt: 2 }}>
          <Stack spacing={2}>
            <TextField
              label="Display Name"
              value={editModelForm.displayName}
              onChange={(e) => setEditModelForm({ ...editModelForm, displayName: e.target.value })}
              fullWidth
            />
            <TextField
              label="Context Window"
              type="number"
              value={editModelForm.contextWindow}
              onChange={(e) => setEditModelForm({ ...editModelForm, contextWindow: e.target.value })}
              fullWidth
              helperText="Enter context window in tokens (optional)"
            />
            <FormControlLabel
              control={
                <Switch
                  checked={editModelForm.enabled}
                  onChange={(_, checked) => setEditModelForm({ ...editModelForm, enabled: checked })}
                />
              }
              label={editModelForm.enabled ? 'Enabled' : 'Disabled'}
            />
          </Stack>
        </DialogContent>
        <DialogActions>
          <Button onClick={closeEditModelDialog}>Cancel</Button>
          <Button
            onClick={() => selectedModel && updateModelMutation.mutate({ modelId: selectedModel.id, data: editModelForm })}
            variant="contained"
            disabled={!selectedModel || updateModelMutation.isPending}
          >
            Save Changes
          </Button>
        </DialogActions>
      </Dialog>

    </Box>
  );
}
