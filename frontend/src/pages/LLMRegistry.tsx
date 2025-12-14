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
} from '@mui/material';
import DeleteIcon from '@mui/icons-material/Delete';
import CheckCircleIcon from '@mui/icons-material/CheckCircle';
import ErrorIcon from '@mui/icons-material/Error';
import RefreshIcon from '@mui/icons-material/Refresh';
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

interface Agent {
  id: number;
  name: string;
  description?: string;
  model_id?: number;
  model_name?: string;
}

export default function LLMRegistry() {
  const [tabValue, setTabValue] = useState(0);
  const [openProviderDialog, setOpenProviderDialog] = useState(false);
  const [openModelDialog, setOpenModelDialog] = useState(false);
  const [openAgentDialog, setOpenAgentDialog] = useState(false);
  const [openDiscoverDialog, setOpenDiscoverDialog] = useState(false);

  const queryClient = useQueryClient();

  // Provider form state
  const [providerForm, setProviderForm] = useState({ name: '', type: 'google', apiKey: '', baseUrl: '' });
  const [modelForm, setModelForm] = useState({ provider: '', modelIds: [] as string[] });
  const [discoverProvider, setDiscoverProvider] = useState('');
  const [agentForm, setAgentForm] = useState({ name: '', description: '' });
  const [assignForm, setAssignForm] = useState({ agent: '', modelId: '' });

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

  // Fetch agents
  const agentsQuery = useQuery({
    queryKey: ['llm', 'agents'],
    queryFn: async () => {
      const res = await callEngineTool('llm', 'llm_agents_list', {});
      return res.agents || [];
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

  // Create agent
  const createAgentMutation = useMutation({
    mutationFn: async (data: typeof agentForm) => {
      await callEngineTool('llm', 'llm_agents_create', {
        name: data.name,
        description: data.description || undefined,
      });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['llm', 'agents'] });
      setOpenAgentDialog(false);
      setAgentForm({ name: '', description: '' });
    },
  });

  // Assign model to agent
  const assignModelMutation = useMutation({
    mutationFn: async (data: typeof assignForm) => {
      await callEngineTool('llm', 'llm_agents_assign_model', {
        agent_name: data.agent,
        model_id: parseInt(data.modelId),
      });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['llm', 'agents'] });
      setAssignForm({ agent: '', modelId: '' });
    },
  });

  // Delete agent
  const deleteAgentMutation = useMutation({
    mutationFn: async (name: string) => {
      await callEngineTool('llm', 'llm_agents_delete', { name });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['llm', 'agents'] });
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
          <Tab label="Agents" id="llm-tab-2" aria-controls="llm-tabpanel-2" />
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
                  <TableRow sx={{ backgroundColor: '#f5f5f5' }}>
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
                  <TableRow sx={{ backgroundColor: '#f5f5f5' }}>
                    <TableCell>Model</TableCell>
                    <TableCell>Provider</TableCell>
                    <TableCell>Modality</TableCell>
                    <TableCell>Context Window</TableCell>
                    <TableCell>Enabled</TableCell>
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
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </TableContainer>
          )}
        </Stack>
      </TabPanel>

      {/* Agents Tab */}
      <TabPanel value={tabValue} index={2}>
        <Stack spacing={2}>
          <Box display="flex" gap={1} justifyContent="space-between" alignItems="center">
            <Typography variant="h6">Agents</Typography>
            <Stack direction="row" spacing={1}>
              <Button
                variant="contained"
                color="primary"
                onClick={() => setOpenAgentDialog(true)}
              >
                Create Agent
              </Button>
              <IconButton
                onClick={() => agentsQuery.refetch()}
                disabled={agentsQuery.isLoading}
              >
                <RefreshIcon />
              </IconButton>
            </Stack>
          </Box>

          {agentsQuery.isLoading && <CircularProgress />}
          {agentsQuery.isError && (
            <Alert severity="error">Failed to load agents</Alert>
          )}

          {agentsQuery.data && agentsQuery.data.length === 0 && (
            <Alert severity="info">No agents configured. Create one to assign models.</Alert>
          )}

          {agentsQuery.data && agentsQuery.data.length > 0 && (
            <TableContainer>
              <Table>
                <TableHead>
                  <TableRow sx={{ backgroundColor: '#f5f5f5' }}>
                    <TableCell>Name</TableCell>
                    <TableCell>Description</TableCell>
                    <TableCell>Assigned Model</TableCell>
                    <TableCell align="right">Actions</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {(agentsQuery.data as Agent[]).map((agent) => (
                    <TableRow key={agent.id}>
                      <TableCell>{agent.name}</TableCell>
                      <TableCell>{agent.description || '-'}</TableCell>
                      <TableCell>{agent.model_name || 'Not assigned'}</TableCell>
                      <TableCell align="right">
                        {!agent.model_id && (
                          <Button
                            size="small"
                            onClick={() => setAssignForm({ agent: agent.name, modelId: '' })}
                          >
                            Assign Model
                          </Button>
                        )}
                        <Tooltip title="Delete">
                          <IconButton
                            size="small"
                            onClick={() => deleteAgentMutation.mutate(agent.name)}
                            disabled={deleteAgentMutation.isPending}
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

      {/* Create Agent Dialog */}
      <Dialog open={openAgentDialog} onClose={() => setOpenAgentDialog(false)} maxWidth="sm" fullWidth>
        <DialogTitle>Create Agent</DialogTitle>
        <DialogContent sx={{ pt: 2 }}>
          <Stack spacing={2}>
            <TextField
              label="Agent Name"
              value={agentForm.name}
              onChange={(e) => setAgentForm({ ...agentForm, name: e.target.value })}
              fullWidth
            />
            <TextField
              label="Description"
              value={agentForm.description}
              onChange={(e) => setAgentForm({ ...agentForm, description: e.target.value })}
              fullWidth
              multiline
              rows={3}
            />
          </Stack>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setOpenAgentDialog(false)}>Cancel</Button>
          <Button
            onClick={() => createAgentMutation.mutate(agentForm)}
            variant="contained"
            disabled={createAgentMutation.isPending || !agentForm.name}
          >
            Create Agent
          </Button>
        </DialogActions>
      </Dialog>

      {/* Assign Model Dialog */}
      {assignForm.agent && (
        <Dialog
          open={!!assignForm.agent}
          onClose={() => setAssignForm({ agent: '', modelId: '' })}
          maxWidth="sm"
          fullWidth
        >
          <DialogTitle>Assign Model to {assignForm.agent}</DialogTitle>
          <DialogContent sx={{ pt: 2 }}>
            <FormControl fullWidth>
              <InputLabel>Model</InputLabel>
              <Select
                value={assignForm.modelId}
                onChange={(e) => setAssignForm({ ...assignForm, modelId: e.target.value })}
                label="Model"
              >
                {(modelsQuery.data as Model[])?.map((m) => (
                  <MenuItem key={m.id} value={m.id.toString()}>
                    {m.display_name} ({m.provider_name})
                  </MenuItem>
                ))}
              </Select>
            </FormControl>
          </DialogContent>
          <DialogActions>
            <Button onClick={() => setAssignForm({ agent: '', modelId: '' })}>Cancel</Button>
            <Button
              onClick={() => {
                assignModelMutation.mutate(assignForm);
                setAssignForm({ agent: '', modelId: '' });
              }}
              variant="contained"
              disabled={assignModelMutation.isPending || !assignForm.modelId}
            >
              Assign
            </Button>
          </DialogActions>
        </Dialog>
      )}
    </Box>
  );
}
