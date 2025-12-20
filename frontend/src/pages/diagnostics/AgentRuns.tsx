import React, { useState } from 'react';
import {
  Box,
  Paper,
  Stack,
  Typography,
  List,
  ListItemButton,
  ListItemText,
  Chip,
  IconButton,
  Tooltip,
  Divider,
  CircularProgress,
  Button,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
} from '@mui/material';
import RefreshIcon from '@mui/icons-material/Refresh';
import DeleteIcon from '@mui/icons-material/Delete';
import DeleteSweepIcon from '@mui/icons-material/DeleteSweep';
import PlayArrowIcon from '@mui/icons-material/PlayArrow';
import { useAgents, useAgentRuns, agentRunDelete, agentsDelete } from '../../api';
import { getUserId, agentRunRead } from '../../api';
import { useQuery } from '@tanstack/react-query';

function statusColor(status?: string): 'success' | 'warning' | 'error' | 'info' | 'default' {
  switch (status) {
    case 'ok':
    case 'completed':
      return 'success';
    case 'running':
      return 'info';
    case 'error':
    case 'failed':
      return 'error';
    default:
      return 'default';
  }
}

function formatDuration(ms?: number): string {
  if (!ms) return '—';
  if (ms < 1000) return `${ms}ms`;
  return `${(ms / 1000).toFixed(1)}s`;
}

function formatDate(dateStr?: string): string {
  if (!dateStr) return '—';
  try {
    const d = new Date(dateStr);
    return d.toLocaleTimeString();
  } catch {
    return dateStr;
  }
}

type SelectedRun = { agentName: string; runId: number } | null;

export default function DiagnosticsAgentRuns() {
  const { data: agentsData, isLoading: agentsLoading, refetch: refetchAgents } = useAgents();
  const [selectedAgent, setSelectedAgent] = useState<string | null>(null);
  const [selectedRun, setSelectedRun] = useState<SelectedRun>(null);
  const [deleteDialog, setDeleteDialog] = useState<{ type: 'run' | 'agent'; agent?: string; run?: number } | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  const { data: runsData, isLoading: runsLoading, refetch: refetchRuns } = useAgentRuns(selectedAgent);
  const { data: runDetails, isLoading: runDetailsLoading } = useQuery({
    queryKey: ['agents', 'run', selectedRun?.agentName, selectedRun?.runId],
    queryFn: async () => {
      if (!selectedRun) return null;
      return agentRunRead(selectedRun.agentName, selectedRun.runId);
    },
    enabled: !!selectedRun
  });

  const agents = agentsData?.agents || [];
  const runs = runsData?.runs || [];
  const steps = runDetails?.transcript?.steps || [];

  async function handleDeleteRun(agentName: string, runId: number) {
    try {
      await agentRunDelete(agentName, runId);
      await refetchRuns();
      if (selectedRun?.runId === runId) {
        setSelectedRun(null);
      }
    } catch (err) {
      console.error('Failed to delete run:', err);
    }
    setDeleteDialog(null);
  }

  async function handleDeleteAgent(agentName: string) {
    try {
      await agentsDelete(agentName);
      await refetchAgents();
      setSelectedAgent(null);
      setSelectedRun(null);
    } catch (err) {
      console.error('Failed to delete agent:', err);
    }
    setDeleteDialog(null);
  }

  async function handleRefresh() {
    setRefreshing(true);
    await Promise.all([refetchAgents(), refetchRuns()]);
    setRefreshing(false);
  }

  return (
    <Box>
      {/* Header */}
      <Paper sx={{ p: 2, mb: 2 }}>
        <Stack direction="row" spacing={2} alignItems="center" justifyContent="space-between">
          <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>Agent Runs</Typography>
          <Stack direction="row" spacing={1}>
            <Tooltip title={refreshing ? 'Refreshing…' : 'Refresh'}>
              <span>
                <IconButton size="small" onClick={handleRefresh} disabled={refreshing || agentsLoading}>
                  <RefreshIcon fontSize="small" />
                </IconButton>
              </span>
            </Tooltip>
          </Stack>
        </Stack>
        <Stack direction="row" spacing={1} sx={{ mt: 1 }}>
          <Chip label={`${agents.length} agents`} size="small" />
          <Chip label={`${runs.length} runs`} size="small" />
        </Stack>
      </Paper>

      <Stack direction={{ xs: 'column', lg: 'row' }} spacing={2} alignItems="stretch">
        {/* Left: Agents List */}
        <Paper sx={{ p: 0, flex: 2, minHeight: 400, display: 'flex', flexDirection: 'column' }}>
          <Box sx={{ p: 1.5, borderBottom: '1px solid', borderColor: 'divider' }}>
            <Typography variant="subtitle2">Agents</Typography>
          </Box>
          {agentsLoading ? (
            <Box sx={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <CircularProgress size={32} />
            </Box>
          ) : agents.length === 0 ? (
            <Box sx={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', p: 2 }}>
              <Typography variant="body2" sx={{ opacity: 0.7 }}>No agents found</Typography>
            </Box>
          ) : (
            <List dense disablePadding sx={{ flex: 1, overflow: 'auto' }}>
              {agents.map((agent) => (
                <ListItemButton
                  key={agent.id}
                  selected={selectedAgent === agent.name}
                  onClick={() => {
                    setSelectedAgent(agent.name);
                    setSelectedRun(null);
                  }}
                  sx={{ py: 0.75 }}
                >
                  <ListItemText
                    primary={agent.name}
                    secondary={`${agent.run_count || 0} runs`}
                    primaryTypographyProps={{ fontSize: 13, fontWeight: 500 }}
                    secondaryTypographyProps={{ fontSize: 11 }}
                  />
                </ListItemButton>
              ))}
            </List>
          )}
        </Paper>

        {/* Middle: Runs List */}
        <Paper sx={{ p: 0, flex: 2, minHeight: 400, display: 'flex', flexDirection: 'column' }}>
          <Box sx={{ p: 1.5, borderBottom: '1px solid', borderColor: 'divider' }}>
            <Typography variant="subtitle2">
              {selectedAgent ? `Runs: ${selectedAgent}` : 'Select an agent'}
            </Typography>
          </Box>
          {!selectedAgent ? (
            <Box sx={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', p: 2 }}>
              <Typography variant="body2" sx={{ opacity: 0.7 }}>Select an agent to view its runs</Typography>
            </Box>
          ) : runsLoading ? (
            <Box sx={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <CircularProgress size={32} />
            </Box>
          ) : runs.length === 0 ? (
            <Box sx={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', p: 2 }}>
              <Typography variant="body2" sx={{ opacity: 0.7 }}>No runs for this agent</Typography>
            </Box>
          ) : (
            <List dense disablePadding sx={{ flex: 1, overflow: 'auto' }}>
              {runs
                .slice()
                .reverse()
                .map((run) => (
                  <Box key={run.id}>
                    <ListItemButton
                      selected={selectedRun?.runId === run.id}
                      onClick={() => setSelectedRun({ agentName: selectedAgent, runId: run.id })}
                      sx={{ py: 0.75 }}
                    >
                      <ListItemText
                        primary={`Run #${run.id} — ${run.input?.substring(0, 40)}${run.input && run.input.length > 40 ? '…' : ''}`}
                        secondary={
                          <Stack direction="row" spacing={0.5} sx={{ mt: 0.5 }}>
                            <Chip size="small" label={String(run.status ?? 'unknown')} color={statusColor(run.status)} />
                            <Chip size="small" label={formatDuration(run.duration_ms)} variant="outlined" />
                            <Typography variant="caption" sx={{ opacity: 0.6 }}>
                              {formatDate(run.created_at)}
                            </Typography>
                          </Stack>
                        }
                        primaryTypographyProps={{ fontSize: 12 }}
                      />
                      <Tooltip title="Delete run">
                        <IconButton
                          edge="end"
                          size="small"
                          onClick={(e) => {
                            e.stopPropagation();
                            setDeleteDialog({ type: 'run', agent: selectedAgent, run: run.id });
                          }}
                        >
                          <DeleteIcon fontSize="small" />
                        </IconButton>
                      </Tooltip>
                    </ListItemButton>
                    <Divider />
                  </Box>
                ))}
            </List>
          )}
        </Paper>

        {/* Right: Run Details */}
        <Paper sx={{ p: 0, flex: 3, minHeight: 400, display: 'flex', flexDirection: 'column' }}>
          <Box sx={{ p: 1.5, borderBottom: '1px solid', borderColor: 'divider' }}>
            <Typography variant="subtitle2">
              {selectedRun ? `Run #${selectedRun.runId} Details` : 'Select a run'}
            </Typography>
          </Box>
          {!selectedRun ? (
            <Box sx={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', p: 2 }}>
              <Typography variant="body2" sx={{ opacity: 0.7 }}>Select a run to view its details</Typography>
            </Box>
          ) : runDetailsLoading ? (
            <Box sx={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <CircularProgress size={32} />
            </Box>
          ) : (
            <Box sx={{ flex: 1, overflow: 'auto', p: 2 }}>
              {/* Run Metadata */}
              <Stack spacing={2}>
                <Box>
                  <Typography variant="caption" sx={{ opacity: 0.7, display: 'block', mb: 0.5 }}>
                    Status
                  </Typography>
                  <Chip label={String(runDetails?.status ?? 'unknown')} color={statusColor(runDetails?.status)} />
                </Box>

                {runDetails?.output_summary !== undefined && runDetails?.output_summary !== null && (
                  <Box>
                    <Typography variant="caption" sx={{ opacity: 0.7, display: 'block', mb: 0.5 }}>
                      Output
                    </Typography>
                    <Typography variant="body2">{typeof runDetails.output_summary === 'string' ? runDetails.output_summary : JSON.stringify(runDetails.output_summary)}</Typography>
                  </Box>
                )}

                {runDetails?.duration_ms && (
                  <Box>
                    <Typography variant="caption" sx={{ opacity: 0.7, display: 'block', mb: 0.5 }}>
                      Duration
                    </Typography>
                    <Typography variant="body2">{formatDuration(runDetails.duration_ms)}</Typography>
                  </Box>
                )}

                <Divider />

                {/* Steps */}
                <Box>
                  <Typography variant="subtitle2" sx={{ mb: 1 }}>
                    Steps ({steps.length})
                  </Typography>
                  {steps.length === 0 ? (
                    <Typography variant="body2" sx={{ opacity: 0.7 }}>No steps recorded</Typography>
                  ) : (
                    <Stack spacing={1.5}>
                      {steps.map((step: any, idx: number) => (
                        <Paper key={idx} sx={{ p: 1.5, bgcolor: 'background.default' }}>
                          <Stack spacing={1}>
                            <Box>
                              <Typography variant="caption" sx={{ opacity: 0.7, fontWeight: 600 }}>
                                Step #{step.index}
                              </Typography>
                              {step.action && (
                                <Box sx={{ mt: 0.5 }}>
                                  <Chip
                                    size="small"
                                    label={step.action.action}
                                    variant="outlined"
                                    sx={{ mr: 0.5 }}
                                  />
                                  {step.action.tool_name && (
                                    <Chip
                                      size="small"
                                      label={step.action.tool_name}
                                      color="info"
                                    />
                                  )}
                                </Box>
                              )}
                            </Box>

                            {step.action?.reasoning && (
                              <Box>
                                <Typography variant="caption" sx={{ opacity: 0.7 }}>
                                  Reasoning
                                </Typography>
                                <Typography variant="body2" sx={{ whiteSpace: 'pre-wrap', mt: 0.5 }}>
                                  {typeof step.action.reasoning === 'string' ? step.action.reasoning : JSON.stringify(step.action.reasoning)}
                                </Typography>
                              </Box>
                            )}

                            {step.action?.final && (
                              <Box>
                                <Typography variant="caption" sx={{ opacity: 0.7 }}>
                                  Final
                                </Typography>
                                <Typography variant="body2" sx={{ whiteSpace: 'pre-wrap', mt: 0.5 }}>
                                  {typeof step.action.final === 'string' ? step.action.final : JSON.stringify(step.action.final)}
                                </Typography>
                              </Box>
                            )}

                            {step.output && (
                              <Box>
                                <Typography variant="caption" sx={{ opacity: 0.7 }}>
                                  Output
                                </Typography>
                                <Box
                                  component="pre"
                                  sx={{
                                    mt: 0.5,
                                    p: 1,
                                    bgcolor: '#0d1117',
                                    color: '#c9d1d9',
                                    borderRadius: 1,
                                    fontSize: 11,
                                    maxHeight: 200,
                                    overflow: 'auto',
                                  }}
                                >
                                  {JSON.stringify(step.output, null, 2)}
                                </Box>
                              </Box>
                            )}
                          </Stack>
                        </Paper>
                      ))}
                    </Stack>
                  )}
                </Box>
              </Stack>
            </Box>
          )}
        </Paper>
      </Stack>

      {/* Delete Confirmation Dialog */}
      <Dialog open={!!deleteDialog} onClose={() => setDeleteDialog(null)}>
        <DialogTitle>
          {deleteDialog?.type === 'run' ? 'Delete Run?' : 'Delete Agent?'}
        </DialogTitle>
        <DialogContent>
          <Typography>
            {deleteDialog?.type === 'run'
              ? `Delete run #${deleteDialog.run}? This cannot be undone.`
              : `Delete agent ${deleteDialog?.agent} and all its runs? This cannot be undone.`}
          </Typography>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setDeleteDialog(null)}>Cancel</Button>
          <Button
            color="error"
            variant="contained"
            onClick={() => {
              if (deleteDialog?.type === 'run' && deleteDialog.agent && deleteDialog.run) {
                handleDeleteRun(deleteDialog.agent, deleteDialog.run);
              } else if (deleteDialog?.type === 'agent' && deleteDialog.agent) {
                handleDeleteAgent(deleteDialog.agent);
              }
            }}
          >
            Delete
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}
