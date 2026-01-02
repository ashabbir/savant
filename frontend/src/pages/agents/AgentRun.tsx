import React, { useEffect, useMemo, useState } from 'react';
import Grid from '@mui/material/Unstable_Grid2';
import Paper from '@mui/material/Paper';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import Stack from '@mui/material/Stack';
import Chip from '@mui/material/Chip';
import Alert from '@mui/material/Alert';
import Button from '@mui/material/Button';
import LinearProgress from '@mui/material/LinearProgress';
import Accordion from '@mui/material/Accordion';
import AccordionSummary from '@mui/material/AccordionSummary';
import AccordionDetails from '@mui/material/AccordionDetails';
import ExpandMoreIcon from '@mui/icons-material/ExpandMore';
import { agentRunRead, getErrorMessage, getUserId, loadConfig, agentRunContinue, callEngineTool } from '../../api';
import TextField from '@mui/material/TextField';
import Snackbar from '@mui/material/Snackbar';
import { Link, useNavigate, useParams } from 'react-router-dom';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import DialogActions from '@mui/material/DialogActions';
import IconButton from '@mui/material/IconButton';
import Tooltip from '@mui/material/Tooltip';
import ArticleIcon from '@mui/icons-material/Article';
import ContentCopyIcon from '@mui/icons-material/ContentCopy';
import CloseIcon from '@mui/icons-material/Close';
import Viewer from '../../components/Viewer';
import yaml from 'js-yaml';

// Ensure non-primitive values render safely in JSX
function toText(v: any): string {
  if (v === null || v === undefined) return '';
  return typeof v === 'string' ? v : JSON.stringify(v);
}

type AgentConfig = {
  name?: string;
  persona_name?: string | null;
  driver?: string | null;
  rules_names?: string[];
  model_id?: number | null;
  model_name?: string | null;
  model_provider?: string | null;
  instructions?: string | null;
};

function ParamsAndSettingsView({ agent, input }: { agent: AgentConfig | null | undefined; input?: string | null }) {
  if (!agent && !input) return null;

  const hasLeftColumn = agent && (agent.model_name || agent.persona_name || agent.driver || (agent.rules_names && agent.rules_names.length > 0));
  const hasRightColumn = input || (agent && agent.instructions);

  if (!hasLeftColumn && !hasRightColumn) return null;

  return (
    <Accordion defaultExpanded={false} sx={{ mb: 1, '&:before': { display: 'none' } }} disableGutters>
      <AccordionSummary expandIcon={<ExpandMoreIcon />} sx={{ minHeight: 36, '& .MuiAccordionSummary-content': { my: 0.5 } }}>
        <Typography variant="body2" fontWeight={500}>Params & Settings</Typography>
      </AccordionSummary>
      <AccordionDetails sx={{ pt: 0, pb: 1.5 }}>
        <Grid container spacing={2}>
          {/* Left Column: Params, Model, Persona, Driver, Rules */}
          <Grid xs={12} md={6}>
            <Stack spacing={0.5}>
              {input && (
                <Typography variant="body2" sx={{ fontSize: 12 }}><b>Params:</b> {input}</Typography>
              )}
              <Stack direction="row" spacing={0.5} flexWrap="wrap" useFlexGap alignItems="center">
                {agent?.model_name && (
                  <Chip size="small" label={`Model: ${agent.model_name}${agent.model_provider ? ` (${agent.model_provider})` : ''}`} color="primary" variant="outlined" />
                )}
                {agent?.persona_name && (
                  <Chip size="small" label={`Persona: ${agent.persona_name}`} variant="outlined" />
                )}
                {agent?.driver && (
                  <Chip size="small" label={`Driver: ${agent.driver}`} variant="outlined" />
                )}
                {agent?.rules_names && agent.rules_names.length > 0 && agent.rules_names.map((rule, idx) => (
                  <Chip key={idx} size="small" label={`Rule: ${rule}`} variant="outlined" />
                ))}
              </Stack>
            </Stack>
          </Grid>
          {/* Right Column: Instructions */}
          <Grid xs={12} md={6}>
            {agent?.instructions && (
              <Typography variant="body2" sx={{ fontSize: 12, whiteSpace: 'pre-wrap' }}><b>Instructions:</b> {agent.instructions}</Typography>
            )}
          </Grid>
        </Grid>
      </AccordionDetails>
    </Accordion>
  );
}

function TranscriptView({ transcript }: { transcript: any }) {
  if (!transcript) return <Typography variant="body2" color="text.secondary">No transcript available.</Typography>;

  // Handle case where transcript might be a string
  let transcriptObj = transcript;
  if (typeof transcript === 'string') {
    try {
      transcriptObj = JSON.parse(transcript);
    } catch {
      return <Typography variant="body2" color="text.secondary">Invalid transcript format.</Typography>;
    }
  }

  const steps = Array.isArray(transcriptObj?.steps) ? transcriptObj.steps : [];
  const errors = Array.isArray(transcriptObj?.errors) ? transcriptObj.errors : [];
  const summaries = Array.isArray(transcriptObj?.summaries) ? transcriptObj.summaries : [];
  const wasSummarized = Array.isArray(steps) && steps.length > 0 && steps[0] && steps[0].index === 'summary';

  return (
    <Stack spacing={2}>
      {/* Steps */}
      {steps.length > 0 && (
        <Box>
          <Typography variant="subtitle2" sx={{ mb: 1 }}>Steps ({steps.length})</Typography>
          {wasSummarized && (
            <Alert severity="info" sx={{ mb: 1 }}>
              This transcript was summarized during execution to keep prompts small. Older steps may be omitted.
            </Alert>
          )}
          <Stack spacing={1}>
            {steps.map((s: any, idx: number) => (
              <Accordion key={idx} defaultExpanded={false} sx={{ '&:before': { display: 'none' } }}>
                <AccordionSummary expandIcon={<ExpandMoreIcon />} sx={{ minHeight: 36, '& .MuiAccordionSummary-content': { my: 0.5 } }}>
                  <Stack direction="row" spacing={1} alignItems="center" sx={{ flexWrap: 'wrap', gap: 0.5 }}>
                    <Chip size="small" label={`Step ${s.index || idx + 1}`} color="primary" />
                    <Typography variant="body2" sx={{ fontWeight: 600 }}>{s.action?.action || s.note || 'step'}</Typography>
                    {s.action?.tool_name && <Chip size="small" variant="outlined" label={s.action.tool_name} />}
                    {s.action?.final && <Chip size="small" color="success" variant="outlined" label="final" />}
                  </Stack>
                </AccordionSummary>
                <AccordionDetails>
                  <Stack direction="row" spacing={1} alignItems="center" sx={{ mb: 1 }}>
                    <Chip size="small" label={`Step ${s.index || idx + 1}`} color="primary" />
                    <Typography variant="body2" sx={{ fontWeight: 600 }}>
                      {toText(s.action?.action ?? (s.note ?? 'step'))} {s.action?.tool_name ? `→ ${s.action.tool_name}` : ''}
                    </Typography>
                  </Stack>

                  {s.action?.reasoning && (
                    <Box sx={{ mb: 1 }}>
                      <Typography variant="caption" color="text.secondary">Reasoning:</Typography>
                      <Typography variant="body2" sx={{ fontStyle: 'italic' }}>{toText(s.action.reasoning)}</Typography>
                    </Box>
                  )}

                  {s.action?.args && Object.keys(s.action.args).length > 0 && (
                    <Box sx={{ mb: 1 }}>
                      <Typography variant="caption" color="text.secondary">Arguments:</Typography>
                      <Box
                        component="pre"
                        sx={{
                          m: 0,
                          mt: 0.5,
                          p: 1,
                          bgcolor: 'background.paper',
                          color: 'text.primary',
                          border: '1px solid',
                          borderColor: 'divider',
                          borderRadius: 1,
                          fontSize: 12,
                          whiteSpace: 'pre-wrap',
                          overflow: 'auto',
                        }}
                      >
                        {JSON.stringify(s.action.args, null, 2)}
                      </Box>
                    </Box>
                  )}

                  {s.action?.final && (
                    <Box sx={{ mb: 1 }}>
                      <Typography variant="caption" color="text.secondary">Final:</Typography>
                      <Typography variant="body2">{toText(s.action.final)}</Typography>
                    </Box>
                  )}

                  {s.output && (
                    <Box>
                      <Typography variant="caption" color="text.secondary">Output:</Typography>
                      {s.output.error ? (
                        <Alert severity="error" sx={{ mt: 0.5 }}>{s.output.message || s.output.error}</Alert>
                      ) : (
                        <Box
                          component="pre"
                          sx={{
                            m: 0,
                            mt: 0.5,
                            p: 1,
                            bgcolor: 'background.paper',
                            color: 'text.primary',
                            border: '1px solid',
                            borderColor: 'divider',
                            borderRadius: 1,
                            fontSize: 12,
                            whiteSpace: 'pre-wrap',
                            maxHeight: 200,
                            overflow: 'auto',
                          }}
                        >
                          {typeof s.output === 'string' ? s.output : JSON.stringify(s.output, null, 2)}
                        </Box>
                      )}
                    </Box>
                  )}
                  {!s.action && s.note && (
                    <Alert severity="info">{toText(s.note)}</Alert>
                  )}
                </AccordionDetails>
              </Accordion>
            ))}
          </Stack>
        </Box>
      )}

      {/* Errors */}
      {errors.length > 0 && (
        <Box>
          <Typography variant="subtitle2" sx={{ mb: 1 }}>Errors</Typography>
          <Stack spacing={1}>
            {errors.map((e: any, idx: number) => (
              <Alert key={idx} severity="error">
                {toText(e.final ?? e.error ?? e.message ?? 'Unknown error')}
              </Alert>
            ))}
          </Stack>
        </Box>
      )}

      {/* Summaries */}
      {summaries.length > 0 && (
        <Box>
          <Typography variant="subtitle2" sx={{ mb: 1 }}>Summaries</Typography>
          <Stack spacing={1}>
            {summaries.map((summary: any, idx: number) => (
              <Paper key={idx} variant="outlined" sx={{ p: 1 }}>
                <Typography variant="body2">{typeof summary === 'string' ? summary : JSON.stringify(summary)}</Typography>
              </Paper>
            ))}
          </Stack>
        </Box>
      )}
    </Stack>
  );
}

export default function AgentRun() {
  const params = useParams();
  const name = params.name || '';
  const runId = Number(params.id || '0');
  const nav = useNavigate();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [data, setData] = useState<any>(null);
  const [events, setEvents] = useState<any[]>([]);
  const [polling, setPolling] = useState<boolean>(true);
  const [followup, setFollowup] = useState<string>('');
  const [submitting, setSubmitting] = useState<boolean>(false);
  const [toast, setToast] = useState<string | null>(null);
  const [yamlOpen, setYamlOpen] = useState(false);
  const [yamlText, setYamlText] = useState('');
  const [yamlLoading, setYamlLoading] = useState(false);
  const [yamlError, setYamlError] = useState<string | null>(null);
  const [chain, setChain] = useState<number[]>([]);
  const [mergedTranscript, setMergedTranscript] = useState<{ steps: any[]; errors: any[]; summaries: any[] }>({ steps: [], errors: [], summaries: [] });
  const [latestSummary, setLatestSummary] = useState<string | null>(null);
  const [responses, setResponses] = useState<Array<{ id: number; text: string }>>([]);

  const activeRunId = chain.length > 0 ? chain[chain.length - 1] : runId;

  // Poll run status for the latest run (base on first load)
  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    let timer: number | null = null;
    async function pollRun() {
      try {
        const d = await agentRunRead(name, activeRunId);
        if (!cancelled) {
          setData(d);
          setLoading(false);
          // Initialize chain and merged transcript on first load
          setChain((prev) => (prev.length === 0 ? [runId] : prev));
          const t = (d && d.transcript) || null;
          const obj = typeof t === 'string' ? (JSON.parse(t)) : t;
          const steps = Array.isArray(obj?.steps) ? obj.steps : [];
          const errors = Array.isArray(obj?.errors) ? obj.errors : [];
          const summaries = Array.isArray(obj?.summaries) ? obj.summaries : [];
          if (activeRunId === runId && mergedTranscript.steps.length === 0) {
            setMergedTranscript({ steps, errors, summaries });
          }
          if (d?.output_summary) {
            setLatestSummary(d.output_summary);
            // Seed initial response list on first load
            setResponses((prev) => (prev.length === 0 ? [{ id: d.id, text: d.output_summary as string }] : prev));
          }
        }
        if (d && d.status && String(d.status).toLowerCase() !== 'running') {
          setPolling(false);
          return;
        }
      } catch (e: any) {
        if (!cancelled) {
          setError(getErrorMessage(e));
          setLoading(false);
        }
      } finally {
        if (!cancelled) timer = window.setTimeout(pollRun, 1500);
      }
    }
    pollRun();
    return () => { cancelled = true; if (timer) window.clearTimeout(timer); };
  }, [name, runId, activeRunId, mergedTranscript.steps.length]);

  // Poll diagnostics events; filter to latest run id
  useEffect(() => {
    let cancelled = false;
    let timer: number | null = null;
    async function pollEv() {
      try {
        const base = loadConfig().baseUrl || 'http://localhost:9999';
        const res = await fetch(`${base}/diagnostics/agent`, { headers: { 'x-savant-user-id': getUserId() } });
        const js = await res.json();
        const all: any[] = (js && js.events) || [];
        const filtered = all.filter((e) => Number(e && (e.run ?? e['run'])) === activeRunId);
        if (!cancelled) setEvents(filtered);
      } catch { /* ignore */ }
      finally {
        if (!cancelled && polling) timer = window.setTimeout(pollEv, 1500);
      }
    }
    pollEv();
    return () => { cancelled = true; if (timer) window.clearTimeout(timer); };
  }, [activeRunId, polling]);

  // When a follow-up run completes, append its steps to the merged transcript
  useEffect(() => {
    let cancelled = false;
    async function maybeAppend() {
      if (chain.length <= 1) return;
      const lastId = chain[chain.length - 1];
      const d = await agentRunRead(name, lastId);
      if (String(d?.status || '').toLowerCase() === 'running') return;
      const t = d?.transcript;
      const obj = typeof t === 'string' ? (JSON.parse(t)) : t;
      const steps = Array.isArray(obj?.steps) ? obj.steps : [];
      const errors = Array.isArray(obj?.errors) ? obj.errors : [];
      const summaries = Array.isArray(obj?.summaries) ? obj.summaries : [];
      if (cancelled) return;
      setMergedTranscript((prev) => ({
        steps: [...prev.steps, ...steps.map((s, i) => ({ ...s, index: (prev.steps.length + 1 + i) }))],
        errors: [...prev.errors, ...errors],
        summaries: [...prev.summaries, ...summaries]
      }));
      if (d?.output_summary) {
        setLatestSummary(d.output_summary);
        setResponses((prev) => {
          const idx = prev.findIndex((r) => r.id === d.id);
          if (idx >= 0) {
            const copy = [...prev];
            copy[idx] = { ...copy[idx], text: d.output_summary as string };
            return copy;
          }
          return [...prev, { id: d.id, text: d.output_summary as string }];
        });
      }
    }
    maybeAppend().catch(() => {});
    return () => { cancelled = true; };
  }, [chain, name]);

  const stepGroups = useMemo(() => {
    const by: Record<string, any[]> = {};
    (events || []).forEach((e) => {
      const s = String(Number(e.step ?? e['step']));
      if (!s || s === 'NaN') return;
      const t = String(e.type || e['type'] || '').toLowerCase();
      if (!['reasoning_step', 'tool_call_started', 'tool_call_completed', 'tool_call_error', 'llm_call'].includes(t)) return;
      (by[s] = by[s] || []).push(e);
    });
    const keys = Object.keys(by).map((k) => Number(k)).sort((a, b) => a - b);
    return keys.map((k) => {
      const arr = by[String(k)] || [];
      const rs = arr.find((e) => e.type === 'reasoning_step');
      const llm = arr.filter((e) => e.type === 'llm_call');
      const toolDone = arr.filter((e) => e.type === 'tool_call_completed').slice(-1)[0];
      const toolErr = arr.filter((e) => e.type === 'tool_call_error').slice(-1)[0];
      return { step: k, rs, llm, toolDone, toolErr };
    });
  }, [events]);

  async function openYaml() {
    setYamlLoading(true);
    setYamlError(null);
    try {
      const agentRes = await callEngineTool('agents', 'agents_read', { name });
      const agentYaml = agentRes?.agent_yaml || '';
      let agentObj: any = agentYaml;
      try {
        agentObj = yaml.load(agentYaml) || {};
      } catch {
        agentObj = { raw_yaml: agentYaml };
      }
      const runInfo = {
        id: data?.id,
        status: data?.status,
        duration_ms: data?.duration_ms,
        output_summary: data?.output_summary
      };
      const payload = {
        agent: agentObj,
        run_params: data?.input || '',
        run_info: runInfo,
        run_steps: {
          steps: mergedTranscript.steps || [],
          errors: mergedTranscript.errors || [],
          summaries: mergedTranscript.summaries || []
        }
      };
      setYamlText(yaml.dump(payload, { lineWidth: 100 }));
      setYamlOpen(true);
    } catch (e: any) {
      setYamlError(getErrorMessage(e));
      setYamlOpen(true);
    } finally {
      setYamlLoading(false);
    }
  }

  return (
    <Grid container spacing={2}>
      <Grid xs={12}>
        <Paper sx={{ p:2, display: 'flex', flexDirection: 'column', gap: 1 }}>
          <Stack direction="row" alignItems="center" justifyContent="space-between">
            <Typography variant="subtitle1">Agent Run: {name}</Typography>
            <Stack direction="row" spacing={1} alignItems="center">
              {data?.id && <Chip size="small" label={`#${data.id}`} />}
              {data?.status && <Chip size="small" color={String(data.status) === 'ok' ? 'success' : 'warning'} label={String(data.status)} />}
              {typeof data?.duration_ms === 'number' && <Chip size="small" label={`${data.duration_ms} ms`} />}
              <Tooltip title="Open Run YAML">
                <span>
                  <Button
                    size="small"
                    startIcon={<ArticleIcon fontSize="small" />}
                    disabled={loading || !data}
                    onClick={openYaml}
                  >
                    YAML
                  </Button>
                </span>
              </Tooltip>
            </Stack>
          </Stack>
          {loading && <LinearProgress />}
          {error && <Alert severity="error">{error}</Alert>}
          {!loading && !error && (
            <>
              <ParamsAndSettingsView agent={data?.agent} input={data?.input} />

              {/* Steps (group collapsible) */}
              <Accordion defaultExpanded sx={{ '&:before': { display: 'none' } }}>
                <AccordionSummary expandIcon={<ExpandMoreIcon />} sx={{ minHeight: 36, '& .MuiAccordionSummary-content': { my: 0.5 } }}>
                  <Typography variant="body2" fontWeight={500}>Steps</Typography>
                </AccordionSummary>
                <AccordionDetails>
                  {/* Completed steps */}
                  <TranscriptView transcript={mergedTranscript} />
                  {/* Live steps for active run, appended with offset numbering */}
                  {(data?.status === 'running') && (
                    <Box sx={{ mt: 1 }}>
                      <Typography variant="subtitle2" sx={{ mb: 0.5 }}>Live Steps</Typography>
                      {stepGroups.length === 0 ? (
                        <Typography variant="body2" sx={{ opacity: 0.7 }}>Waiting for step events…</Typography>
                      ) : (
                        <Stack spacing={0.5}>
                          {stepGroups.slice(-15).map((g) => {
                            const action = (g.rs && (g.rs.action || g.rs['action'])) || 'reason';
                            const toolName = (g.rs && (g.rs.tool_name || g.rs['tool_name'])) || '';
                            const summary = (g.rs && g.rs.metadata && (g.rs.metadata.decision_summary || g.rs.metadata['decision_summary'])) || '';
                            const llmModel = (g.llm && g.llm[0] && (g.llm[0].model || g.llm[0]['model'])) || '';
                            const llmDur = (g.llm && g.llm[0] && (g.llm[0].duration_ms || g.llm[0]['duration_ms'])) || null;
                            const toolDur = g.toolDone ? (g.toolDone.duration_ms || g.toolDone['duration_ms']) : null;
                            const toolErr = g.toolErr ? (g.toolErr.error || g.toolErr['error'] || 'error') : null;
                            const globalStep = (mergedTranscript.steps?.length || 0) + g.step;
                            return (
                              <Stack key={`live-${g.step}`} direction="row" spacing={1} alignItems="center" sx={{ flexWrap: 'wrap', gap: 0.5 }}>
                                <Chip size="small" label={`#${globalStep}`} />
                                <Typography variant="body2" sx={{ fontWeight: 600 }}> {action}{toolName ? ` → ${toolName}` : ''}</Typography>
                                {llmModel && <Chip size="small" variant="outlined" label={llmModel + (llmDur ? ` (${llmDur}ms)` : '')} />}
                                {toolDur !== null && <Chip size="small" color="success" variant="outlined" label={`done ${toolDur}ms`} />}
                                {toolErr && <Chip size="small" color="error" variant="outlined" label={String(toolErr)} />}
                                {summary && <Typography variant="caption" sx={{ opacity: 0.8 }}>{summary}</Typography>}
                              </Stack>
                            );
                          })}
                        </Stack>
                      )}
                    </Box>
                  )}
                </AccordionDetails>
              </Accordion>

              {/* Response */}
              <Accordion defaultExpanded sx={{ '&:before': { display: 'none' }, mt: 1 }}>
                <AccordionSummary expandIcon={<ExpandMoreIcon />} sx={{ minHeight: 36, '& .MuiAccordionSummary-content': { my: 0.5 } }}>
                  <Typography variant="body2" fontWeight={500}>Response</Typography>
                </AccordionSummary>
                <AccordionDetails>
                  {responses.length === 0 && (
                    <Typography variant="body2" color="text.secondary">No response yet.</Typography>
                  )}
                  {responses.length > 0 && (
                    <Stack spacing={1}>
                      {responses.map((r) => (
                        <Alert key={r.id} severity="info">{toText(r.text)}</Alert>
                      ))}
                    </Stack>
                  )}
                </AccordionDetails>
              </Accordion>

              {/* Follow-up (open new run page on submit) */}
              <Box sx={{ display: 'flex', flexDirection: 'row', gap: 1, alignItems: 'center', mt: 1 }}>
                <TextField
                  size="small"
                  fullWidth
                  placeholder="Ask a follow-up question…"
                  value={followup}
                  onChange={(e) => setFollowup(e.target.value)}
                  onKeyDown={async (e) => {
                    if (e.key === 'Enter' && !e.shiftKey) {
                      e.preventDefault();
                      if (!followup.trim()) return;
                      try {
                        setSubmitting(true);
                        const res = await agentRunContinue(name, activeRunId, followup);
                        setFollowup('');
                        if (res?.run_id) {
                          nav(`/agents/run/${name}/${res.run_id}`);
                        } else {
                          setToast(res?.message || 'Submitted follow-up');
                        }
                      } catch (err: any) {
                        setToast(err?.message || 'Failed to submit');
                      } finally {
                        setSubmitting(false);
                      }
                    }
                  }}
                  disabled={submitting}
                />
                <Button size="small" variant="contained" disabled={submitting || !followup.trim()} onClick={async () => {
                  try {
                    setSubmitting(true);
                    const res = await agentRunContinue(name, activeRunId, followup);
                    setFollowup('');
                    if (res?.run_id) {
                      nav(`/agents/run/${name}/${res.run_id}`);
                    } else {
                      setToast(res?.message || 'Submitted follow-up');
                    }
                  } catch (err: any) {
                    setToast(err?.message || 'Failed to submit');
                  } finally {
                    setSubmitting(false);
                  }
                }}>Send</Button>
              </Box>
              <Stack direction="row" spacing={1} sx={{ mt: 1 }}>
                <Button size="small" component={Link} to="/diagnostics/logs">View Logs</Button>
                <Button size="small" component={Link} to="/diagnostics/agent-runs">Agent Diagnostics</Button>
                <Button size="small" onClick={() => nav('/agents')}>Back</Button>
              </Stack>
              <Snackbar open={!!toast} autoHideDuration={2000} onClose={() => setToast(null)} message={toast || ''} />
            </>
          )}
        </Paper>
      </Grid>
      <Dialog open={yamlOpen} onClose={() => setYamlOpen(false)} maxWidth="md" fullWidth>
        <DialogTitle sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          Agent Run YAML
          <Stack direction="row" spacing={1} alignItems="center">
            <IconButton
              size="small"
              onClick={async () => {
                try {
                  await navigator.clipboard.writeText(yamlText || '');
                  setToast('YAML copied');
                } catch {
                  setToast('Copy failed');
                }
              }}
              disabled={!yamlText}
            >
              <ContentCopyIcon fontSize="small" />
            </IconButton>
            <IconButton size="small" onClick={() => setYamlOpen(false)}>
              <CloseIcon fontSize="small" />
            </IconButton>
          </Stack>
        </DialogTitle>
        <DialogContent dividers sx={{ p: 0 }}>
          {yamlLoading && <LinearProgress />}
          {yamlError && <Alert severity="error" sx={{ m: 2 }}>{yamlError}</Alert>}
          {!yamlError && <Viewer content={yamlText || ''} language="yaml" height="70vh" />}
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setYamlOpen(false)}>Close</Button>
        </DialogActions>
      </Dialog>
    </Grid>
  );
}
