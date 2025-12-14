import React, { useState } from 'react';
import Grid from '@mui/material/Unstable_Grid2';
import Paper from '@mui/material/Paper';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import LinearProgress from '@mui/material/LinearProgress';
import Alert from '@mui/material/Alert';
import TextField from '@mui/material/TextField';
import List from '@mui/material/List';
import ListItem from '@mui/material/ListItem';
import ListItemButton from '@mui/material/ListItemButton';
import ListItemText from '@mui/material/ListItemText';
import Chip from '@mui/material/Chip';
import Stack from '@mui/material/Stack';
import Button from '@mui/material/Button';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import DialogActions from '@mui/material/DialogActions';
import Tooltip from '@mui/material/Tooltip';
import IconButton from '@mui/material/IconButton';
import Tabs from '@mui/material/Tabs';
import Tab from '@mui/material/Tab';
import CloseIcon from '@mui/icons-material/Close';
import CheckCircleIcon from '@mui/icons-material/CheckCircle';
import ErrorIcon from '@mui/icons-material/Error';
import RefreshIcon from '@mui/icons-material/Refresh';
import AddCircleIcon from '@mui/icons-material/AddCircle';
import DeleteOutlineIcon from '@mui/icons-material/DeleteOutline';
import { getErrorMessage, callEngineTool } from '../../api';

interface LLMBrowseProps {
  type: 'providers' | 'models';
}

export default function LLMBrowse({ type = 'providers' }: LLMBrowseProps) {

  // Providers state
  const [providers, setProviders] = useState<any[]>([]);
  const [selectedProvider, setSelectedProvider] = useState<string | null>(null);
  const [providersLoading, setProvidersLoading] = useState(true);

  // Models state
  const [models, setModels] = useState<any[]>([]);
  const [modelsLoading, setModelsLoading] = useState(false);
  const [selectedModel, setSelectedModel] = useState<number | null>(null);
  const [agents, setAgents] = useState<any[]>([]);

  // UI state
  const [error, setError] = useState<string | null>(null);
  const [openAddProviderDialog, setOpenAddProviderDialog] = useState(false);
  const [openDeleteProviderDialog, setOpenDeleteProviderDialog] = useState(false);
  const [formData, setFormData] = useState({
    name: '',
    type: 'google',
    apiKey: '',
    baseUrl: ''
  });
  const [deleting, setDeleting] = useState(false);

  React.useEffect(() => {
    loadAgents();
    if (type === 'providers') {
      loadProviders();
    } else {
      loadModels();
    }
  }, [type]);

  async function loadAgents() {
    try {
      const res = await callEngineTool('agents', 'agents_list', {});
      setAgents(res.agents || []);
    } catch (e: any) {
      // Silently fail, agents list is just for dependency checking
    }
  }

  async function loadProviders() {
    try {
      setProvidersLoading(true);
      setError(null);
      const res = await callEngineTool('llm', 'llm_providers_list', {});
      setProviders(res.providers || []);
      // Also load models to show count and check dependencies
      await loadModels();
      if (res.providers?.length > 0 && !selectedProvider) {
        setSelectedProvider(res.providers[0].name);
      }
    } catch (e: any) {
      setError(getErrorMessage(e));
    } finally {
      setProvidersLoading(false);
    }
  }

  async function loadModels() {
    try {
      setModelsLoading(true);
      setError(null);
      const res = await callEngineTool('llm', 'llm_models_list', {});
      setModels(res.models || []);
      if (res.models?.length > 0 && selectedModel === null) {
        setSelectedModel(res.models[0].id);
      }
    } catch (e: any) {
      setError(getErrorMessage(e));
    } finally {
      setModelsLoading(false);
    }
  }

  async function addProvider() {
    try {
      if (!formData.name.trim()) {
        setError('Provider name is required');
        return;
      }
      await callEngineTool('llm', 'llm_providers_create', {
        name: formData.name,
        provider_type: formData.type,
        base_url: formData.baseUrl || undefined,
        api_key: formData.apiKey || undefined,
      });
      setOpenAddProviderDialog(false);
      setFormData({ name: '', type: 'google', apiKey: '', baseUrl: '' });
      await loadProviders();
    } catch (e: any) {
      setError(getErrorMessage(e));
    }
  }

  async function deleteProvider() {
    try {
      if (!selectedProvider) return;
      setDeleting(true);
      const res = await callEngineTool('llm', 'llm_providers_delete', {
        name: selectedProvider,
      });
      if (!res.ok && res.error) {
        setError(res.error);
        return;
      }
      setOpenDeleteProviderDialog(false);
      setSelectedProvider(null);
      await loadProviders();
    } catch (e: any) {
      setError(getErrorMessage(e));
    } finally {
      setDeleting(false);
    }
  }

  async function testProvider() {
    try {
      if (!selectedProvider) return;
      const res = await callEngineTool('llm', 'llm_providers_test', {
        name: selectedProvider,
      });
      setError(res.status === 'valid' ? `✓ ${res.message}` : `✗ ${res.message}`);
      await loadProviders();
    } catch (e: any) {
      setError(getErrorMessage(e));
    }
  }

  const selected = providers.find(p => p.name === selectedProvider);
  const selectedModelData = models.find(m => m.id === selectedModel);

  // Helper functions
  const getProviderModelCount = (providerId: number) => {
    return models.filter(m => m.provider_id === providerId).length;
  };

  const getModelAgentCount = (modelId: number) => {
    return agents.filter((a: any) => a.model_id === modelId).length;
  };

  return (
    <>
      {error && <Alert severity={error.startsWith('✓') ? 'success' : 'error'} sx={{ mb: 2 }}>{error}</Alert>}

      {type === 'providers' && (
        /* PROVIDERS VIEW */
        <Grid container spacing={2}>
          <Grid xs={12} md={4}>
            <Paper sx={{ p: 1, height: 'calc(100vh - 320px)', display: 'flex', flexDirection: 'column' }}>
              <Stack direction="row" alignItems="center" justifyContent="space-between" sx={{ mb: 1 }}>
                <Typography variant="subtitle1" sx={{ fontSize: 12 }}>Providers</Typography>
                <Stack direction="row" spacing={1} alignItems="center">
                  <Tooltip title="New Provider">
                    <IconButton size="small" color="primary" onClick={() => setOpenAddProviderDialog(true)}>
                      <AddCircleIcon fontSize="small" />
                    </IconButton>
                  </Tooltip>
                  <Tooltip title={!selectedProvider ? 'Select a provider' : getProviderModelCount(selected?.id) > 0 ? `Cannot delete: ${getProviderModelCount(selected?.id)} model(s) registered` : 'Delete Provider'}>
                    <span>
                      <IconButton size="small" color="error" disabled={!selectedProvider || (selected && getProviderModelCount(selected.id) > 0)} onClick={() => setOpenDeleteProviderDialog(true)}>
                        <DeleteOutlineIcon fontSize="small" />
                      </IconButton>
                    </span>
                  </Tooltip>
                  <Tooltip title="Refresh">
                    <IconButton size="small" onClick={loadProviders} disabled={providersLoading}>
                      <RefreshIcon fontSize="small" />
                    </IconButton>
                  </Tooltip>
                </Stack>
              </Stack>
              {providersLoading && <LinearProgress />}
              <List dense sx={{ flex: 1, overflowY: 'auto' }}>
                {providers.map((p) => (
                  <ListItem key={p.name} disablePadding>
                    <ListItemButton selected={selectedProvider === p.name} onClick={() => setSelectedProvider(p.name)}>
                      <ListItemText
                        primary={
                          <Box display="flex" alignItems="center" gap={1}>
                            <Typography component="span" sx={{ fontWeight: 600 }}>{p.name}</Typography>
                            <Chip
                              size="small"
                              label={p.provider_type}
                              variant="outlined"
                            />
                          </Box>
                        }
                        secondary={
                          <Box display="flex" alignItems="center" gap={1}>
                            {p.status === 'valid' ? (
                              <><CheckCircleIcon fontSize="small" sx={{ color: 'green' }} /><span>Valid</span></>
                            ) : p.status === 'invalid' ? (
                              <><ErrorIcon fontSize="small" sx={{ color: 'red' }} /><span>Invalid</span></>
                            ) : (
                              <span>Unknown</span>
                            )}
                          </Box>
                        }
                      />
                    </ListItemButton>
                  </ListItem>
                ))}
              </List>
            </Paper>
          </Grid>
          <Grid xs={12} md={8}>
            <Paper sx={{ p: 2, height: 'calc(100vh - 320px)', display: 'flex', flexDirection: 'column' }}>
              {selected ? (
                <>
                  <Stack direction="row" alignItems="center" justifyContent="space-between" sx={{ mb: 2 }}>
                    <Box>
                      <Typography variant="subtitle1" sx={{ fontSize: 12 }}>Provider Details</Typography>
                      <Stack direction="row" spacing={1} sx={{ mt: 1 }}>
                        <Chip size="small" label={`Name: ${selected.name}`} />
                        <Chip size="small" label={`Type: ${selected.provider_type}`} variant="outlined" />
                        <Chip
                          size="small"
                          label={selected.status}
                          color={selected.status === 'valid' ? 'success' : 'error'}
                        />
                      </Stack>
                    </Box>
                    <Button variant="contained" size="small" onClick={testProvider}>
                      Test Connection
                    </Button>
                  </Stack>
                  <Box sx={{ flex: 1, overflow: 'auto' }}>
                    <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
                      {selected.provider_type === 'google' && 'Google Generative AI API provider'}
                      {selected.provider_type === 'ollama' && 'Local Ollama instance provider'}
                    </Typography>
                    {selected.base_url && (
                      <Typography variant="caption" display="block" sx={{ mb: 1 }}>
                        <strong>Base URL:</strong> {selected.base_url}
                      </Typography>
                    )}
                    {selected.last_validated_at && (
                      <Typography variant="caption" display="block">
                        <strong>Last Validated:</strong> {new Date(selected.last_validated_at).toLocaleString()}
                      </Typography>
                    )}
                  </Box>
                </>
              ) : (
                <Typography color="text.secondary" sx={{ textAlign: 'center', pt: 4 }}>
                  Select a provider to view details
                </Typography>
              )}
            </Paper>
          </Grid>
        </Grid>
      )}

      {type === 'models' && (
        /* MODELS VIEW */
        <Grid container spacing={2}>
          <Grid xs={12} md={4}>
            <Paper sx={{ p: 1, height: 'calc(100vh - 320px)', display: 'flex', flexDirection: 'column' }}>
              <Stack direction="row" alignItems="center" justifyContent="space-between" sx={{ mb: 1 }}>
                <Typography variant="subtitle1" sx={{ fontSize: 12 }}>Models</Typography>
                <Tooltip title="Refresh">
                  <IconButton size="small" onClick={loadModels} disabled={modelsLoading}>
                    <RefreshIcon fontSize="small" />
                  </IconButton>
                </Tooltip>
              </Stack>
              {modelsLoading && <LinearProgress />}
              <List dense sx={{ flex: 1, overflowY: 'auto' }}>
                {models.map((m) => (
                  <ListItem key={m.id} disablePadding>
                    <ListItemButton selected={selectedModel === m.id} onClick={() => setSelectedModel(m.id)}>
                      <ListItemText
                        primary={
                          <Box display="flex" alignItems="center" gap={1}>
                            <Typography component="span" sx={{ fontWeight: 600 }}>{m.display_name}</Typography>
                            <Chip
                              size="small"
                              label={m.provider_name}
                              variant="outlined"
                            />
                          </Box>
                        }
                        secondary={
                          <Typography variant="caption" color="text.secondary">
                            {Array.isArray(m.modality) ? m.modality.join(', ') : m.modality || 'text'}
                          </Typography>
                        }
                      />
                    </ListItemButton>
                  </ListItem>
                ))}
              </List>
            </Paper>
          </Grid>
          <Grid xs={12} md={8}>
            <Paper sx={{ p: 2, height: 'calc(100vh - 320px)', display: 'flex', flexDirection: 'column' }}>
              {selectedModelData ? (
                <>
                  <Typography variant="subtitle1" sx={{ fontSize: 12, mb: 2 }}>Model Details</Typography>
                  <Stack direction="row" spacing={1} sx={{ mb: 2, flexWrap: 'wrap' }}>
                    <Chip size="small" label={`Name: ${selectedModelData.display_name}`} />
                    <Chip size="small" label={`Provider: ${selectedModelData.provider_name}`} variant="outlined" />
                    <Chip size="small" label={`Model ID: ${selectedModelData.provider_model_id}`} variant="outlined" />
                  </Stack>
                  <Box sx={{ flex: 1, overflow: 'auto' }}>
                    {selectedModelData.context_window && (
                      <Typography variant="caption" display="block" sx={{ mb: 1 }}>
                        <strong>Context Window:</strong> {selectedModelData.context_window.toLocaleString()} tokens
                      </Typography>
                    )}
                    {selectedModelData.modality && (Array.isArray(selectedModelData.modality) ? selectedModelData.modality.length > 0 : selectedModelData.modality) && (
                      <Typography variant="caption" display="block" sx={{ mb: 1 }}>
                        <strong>Capabilities:</strong> {Array.isArray(selectedModelData.modality) ? selectedModelData.modality.join(', ') : selectedModelData.modality}
                      </Typography>
                    )}
                    {selectedModelData.input_cost_per_1k && (
                      <Typography variant="caption" display="block" sx={{ mb: 1 }}>
                        <strong>Input Cost (per 1K tokens):</strong> ${selectedModelData.input_cost_per_1k}
                      </Typography>
                    )}
                    {selectedModelData.output_cost_per_1k && (
                      <Typography variant="caption" display="block" sx={{ mb: 1 }}>
                        <strong>Output Cost (per 1K tokens):</strong> ${selectedModelData.output_cost_per_1k}
                      </Typography>
                    )}
                    <Box sx={{ mt: 2 }}>
                      <Chip
                        size="small"
                        label={selectedModelData.enabled ? 'Enabled' : 'Disabled'}
                        color={selectedModelData.enabled ? 'success' : 'default'}
                      />
                    </Box>
                  </Box>
                </>
              ) : (
                <Typography color="text.secondary" sx={{ textAlign: 'center', pt: 4 }}>
                  {models.length === 0 ? 'No models registered. Add providers and discover models first.' : 'Select a model to view details'}
                </Typography>
              )}
            </Paper>
          </Grid>
        </Grid>
      )}

      {/* Add Provider Dialog */}
      <Dialog open={openAddProviderDialog} onClose={() => setOpenAddProviderDialog(false)} maxWidth="sm" fullWidth>
        <DialogTitle sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          Add LLM Provider
          <IconButton size="small" onClick={() => setOpenAddProviderDialog(false)}>
            <CloseIcon fontSize="small" />
          </IconButton>
        </DialogTitle>
        <DialogContent sx={{ pt: 2 }}>
          <Stack spacing={2}>
            <TextField
              label="Provider Name"
              value={formData.name}
              onChange={(e) => setFormData({ ...formData, name: e.target.value })}
              fullWidth
              size="small"
            />
            <TextField
              label="Provider Type"
              select
              SelectProps={{ native: true }}
              value={formData.type}
              onChange={(e) => setFormData({ ...formData, type: e.target.value })}
              fullWidth
              size="small"
            >
              <option value="google">Google</option>
              <option value="ollama">Ollama</option>
            </TextField>
            {formData.type === 'google' && (
              <TextField
                label="API Key"
                type="password"
                value={formData.apiKey}
                onChange={(e) => setFormData({ ...formData, apiKey: e.target.value })}
                fullWidth
                size="small"
              />
            )}
            {formData.type === 'ollama' && (
              <TextField
                label="Base URL"
                placeholder="http://localhost:11434"
                value={formData.baseUrl}
                onChange={(e) => setFormData({ ...formData, baseUrl: e.target.value })}
                fullWidth
                size="small"
              />
            )}
          </Stack>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setOpenAddProviderDialog(false)}>Cancel</Button>
          <Button variant="contained" onClick={addProvider}>Add Provider</Button>
        </DialogActions>
      </Dialog>

      {/* Delete Dialog */}
      <Dialog open={openDeleteProviderDialog} onClose={() => setOpenDeleteProviderDialog(false)}>
        <DialogTitle sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          Delete provider
          <IconButton size="small" onClick={() => setOpenDeleteProviderDialog(false)}>
            <CloseIcon fontSize="small" />
          </IconButton>
        </DialogTitle>
        <DialogContent>
          Are you sure you want to delete "{selectedProvider}"?
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setOpenDeleteProviderDialog(false)}>Cancel</Button>
          <Button color="error" disabled={deleting} onClick={deleteProvider}>Delete</Button>
        </DialogActions>
      </Dialog>
    </>
  );
}
