import React from 'react';
import Grid from '@mui/material/Unstable_Grid2';
import Paper from '@mui/material/Paper';
import Box from '@mui/material/Box';
import Stack from '@mui/material/Stack';
import Typography from '@mui/material/Typography';
import TextField from '@mui/material/TextField';
import List from '@mui/material/List';
import ListItemButton from '@mui/material/ListItemButton';
import ListItemText from '@mui/material/ListItemText';
import Chip from '@mui/material/Chip';
import Divider from '@mui/material/Divider';
import IconButton from '@mui/material/IconButton';
import Tooltip from '@mui/material/Tooltip';
import LinearProgress from '@mui/material/LinearProgress';
import Accordion from '@mui/material/Accordion';
import AccordionSummary from '@mui/material/AccordionSummary';
import AccordionDetails from '@mui/material/AccordionDetails';
import RefreshIcon from '@mui/icons-material/Refresh';
import PersonIcon from '@mui/icons-material/Person';
import WorkIcon from '@mui/icons-material/Work';
import ErrorOutlineIcon from '@mui/icons-material/ErrorOutline';
import CheckCircleOutlineIcon from '@mui/icons-material/CheckCircleOutline';
import ExpandMoreIcon from '@mui/icons-material/ExpandMore';
import PlayCircleOutlineIcon from '@mui/icons-material/PlayCircleOutline';
import ScheduleIcon from '@mui/icons-material/Schedule';
import CloseIcon from '@mui/icons-material/Close';
import ContentCopyIcon from '@mui/icons-material/ContentCopy';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import Button from '@mui/material/Button';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { useReasoningDiagnostics, useReasoningJobs, getReasoningJob, clearReasoning, cancelReasoningJob, deleteReasoningJob, retryReasoningJob, deleteReasoningWorker } from '../../api';
import DeleteForeverIcon from '@mui/icons-material/DeleteForever';

const PANEL_HEIGHT = 'calc(100vh - 260px)';

export default function DiagnosticsWorkers() {
  const diag = useReasoningDiagnostics();
  const jobs = useReasoningJobs();
  const [filter, setFilter] = React.useState('');
  const [selectedWorker, setSelectedWorker] = React.useState<string | null>(null);
  const [jobFilter, setJobFilter] = React.useState('');
  const [openJobId, setOpenJobId] = React.useState<string | null>(null);
  const [jobDetail, setJobDetail] = React.useState<any | null>(null);
  const [clearing, setClearing] = React.useState(false);
  const [expanded, setExpanded] = React.useState<{ queued: boolean; running: boolean; completed: boolean; failed: boolean; canceled: boolean }>(() => ({ queued: false, running: true, completed: false, failed: false, canceled: false }));
  const [searchParams, setSearchParams] = useSearchParams();
  const navigate = useNavigate();

  // Hydrate job selection from ?job=
  React.useEffect(() => {
    const j = searchParams.get('job');
    if (j) setOpenJobId(j);
  }, []);

  // Load job details when openJobId changes
  React.useEffect(() => {
    let alive = true;
    async function load() {
      if (!openJobId) return setJobDetail(null);
      try {
        const data = await getReasoningJob(openJobId);
        if (alive) setJobDetail(data);
      } catch (e) {
        if (alive) setJobDetail({ error: 'Failed to load job', detail: (e as any)?.message });
      }
    }
    load();
    return () => { alive = false; };
  }, [openJobId]);

  const jobCopyText = React.useMemo(() => {
    try {
      if (!jobDetail) return '';
      return JSON.stringify(jobDetail, null, 2);
    } catch { return ''; }
  }, [jobDetail]);

  const workers = (diag.data?.workers || [])
    .filter(w => !filter || w.id.toLowerCase().includes(filter.toLowerCase()))
    .sort((a, b) => (a.id.localeCompare(b.id)));

  const running = jobs.data?.running_ids || [];
  const queued = jobs.data?.queued || [];
  const recentCompleted = jobs.data?.recent_completed || [];
  const recentFailed = jobs.data?.recent_failed || [];
  const recentCanceled = jobs.data?.recent_canceled || [];

  function getWorkerFromJob(j: any): string | null {
    try {
      const cand = (
        j?.worker_id || j?.worker || j?.workerId || j?.worker_name || j?.workerName ||
        j?.meta?.worker_id || j?.meta?.worker || j?.ctx?.worker_id ||
        j?.result?.worker_id || j?.result?.worker || null
      );
      return cand ? String(cand) : null;
    } catch {
      return null;
    }
  }

  const queuedFiltered = React.useMemo(() => {
    let arr = queued as any[];
    if (selectedWorker) arr = arr.filter(j => getWorkerFromJob(j) === selectedWorker); // queued items usually have no worker
    if (jobFilter) arr = arr.filter(j => jobMatchesText(j, jobFilter));
    return arr;
  }, [queued, selectedWorker, jobFilter]);

  function workerHasJobs(workerId: string): boolean {
    const hasInCompleted = (recentCompleted as any[]).some(j => getWorkerFromJob(j) === workerId);
    const hasInFailed = (recentFailed as any[]).some(j => getWorkerFromJob(j) === workerId);
    const hasInCanceled = (recentCanceled as any[]).some(j => getWorkerFromJob(j) === workerId);
    // Running mapping is not available client-side; server will enforce if any running jobs exist for worker
    return hasInCompleted || hasInFailed || hasInCanceled;
  }

  function jobMatchesText(j: any, q: string): boolean {
    if (!q) return true;
    const s = q.toLowerCase();
    const id = String(j?.job_id || j?.id || '').toLowerCase();
    const status = String(j?.status || '').toLowerCase();
    const err = String(j?.error || '').toLowerCase();
    const wid = (getWorkerFromJob(j) || '').toLowerCase();
    return id.includes(s) || status.includes(s) || err.includes(s) || wid.includes(s);
  }

  const completedFiltered = React.useMemo(() => {
    let arr = recentCompleted as any[];
    if (selectedWorker) arr = arr.filter(j => getWorkerFromJob(j) === selectedWorker);
    if (jobFilter) arr = arr.filter(j => jobMatchesText(j, jobFilter));
    return arr;
  }, [recentCompleted, selectedWorker, jobFilter]);

  const failedFiltered = React.useMemo(() => {
    let arr = recentFailed as any[];
    if (selectedWorker) arr = arr.filter(j => getWorkerFromJob(j) === selectedWorker);
    if (jobFilter) arr = arr.filter(j => jobMatchesText(j, jobFilter));
    return arr;
  }, [recentFailed, selectedWorker, jobFilter]);

  const canceledFiltered = React.useMemo(() => {
    let arr = recentCanceled as any[];
    if (selectedWorker) arr = arr.filter(j => getWorkerFromJob(j) === selectedWorker);
    if (jobFilter) arr = arr.filter(j => jobMatchesText(j, jobFilter));
    return arr;
  }, [recentCanceled, selectedWorker, jobFilter]);

  return (
    <Grid container spacing={2}>
      {/* Left: Workers list */}
      <Grid xs={12} md={4}>
        <Paper sx={{ p: 1, height: PANEL_HEIGHT, display: 'flex', flexDirection: 'column' }}>
          <Box display="flex" alignItems="center" justifyContent="space-between" sx={{ mb: 1 }}>
            <Stack direction="row" spacing={0.5} alignItems="center">
              <PersonIcon color="primary" fontSize="small" />
              <Typography variant="subtitle1" sx={{ fontSize: 12 }}>Workers</Typography>
              {diag.data?.workers && (
                <Chip size="small" label={diag.data.workers.length} />
              )}
            </Stack>
            <Stack direction="row" spacing={1} alignItems="center">
              {/* Legacy link removed per request */}
              <Tooltip title="Refresh">
                <IconButton size="small" onClick={() => { diag.refetch(); jobs.refetch(); }}>
                  <RefreshIcon fontSize="small" />
                </IconButton>
              </Tooltip>
            </Stack>
          </Box>
          {(diag.isLoading || jobs.isLoading) && <LinearProgress />}
          <TextField size="small" placeholder="Filter workers..." value={filter} onChange={(e) => setFilter(e.target.value)} sx={{ mb: 1 }} />
          <List dense sx={{ flex: 1, overflowY: 'auto' }}>
            {workers.map(w => {
              const dead = (w.status !== 'alive');
              const canDelete = dead && !workerHasJobs(w.id);
              return (
                <ListItemButton key={w.id} selected={selectedWorker === w.id} onClick={() => setSelectedWorker(w.id)}>
                  <ListItemText
                    primary={w.id}
                    secondary={`${w.status} • ${new Date(w.last_seen).toLocaleTimeString()}`}
                    primaryTypographyProps={{ fontSize: 12 }}
                    secondaryTypographyProps={{ fontSize: 11, sx: { opacity: 0.8 } }}
                  />
                  <Chip size="small" color={w.status === 'alive' ? 'success' : 'default'} label={w.status} sx={{ height: 18, mr: 0.5 }} />
                  {dead && (
                    <Tooltip title={canDelete ? 'Delete worker' : 'Worker has jobs; cannot delete'}>
                      <span>
                        <IconButton size="small" disabled={!canDelete} onClick={async (e) => { e.stopPropagation(); try { await deleteReasoningWorker(w.id); await diag.refetch(); } catch (err) { console.error(err); } }}>
                          <DeleteForeverIcon fontSize="small" />
                        </IconButton>
                      </span>
                    </Tooltip>
                  )}
                </ListItemButton>
              );
            })}
            {workers.length === 0 && (
              <Box sx={{ p: 2, textAlign: 'center' }}>
                <Typography variant="body2" color="text.secondary">No workers found</Typography>
              </Box>
            )}
          </List>
        </Paper>
      </Grid>

      {/* Right: Jobs summary */}
      <Grid xs={12} md={8}>
        <Paper sx={{ p: 1.5, height: PANEL_HEIGHT, display: 'flex', flexDirection: 'column' }}>
          <Stack direction="row" alignItems="center" justifyContent="space-between" sx={{ mb: 1 }}>
            <Stack direction="row" spacing={0.5} alignItems="center">
              <WorkIcon color="primary" fontSize="small" />
              <Typography variant="subtitle1" sx={{ fontSize: 12 }}>Jobs</Typography>
              {typeof jobs.data?.queue_length === 'number' && (
                <Chip size="small" color={expanded.queued ? 'primary' : 'default'} variant={expanded.queued ? 'filled' : 'outlined'} label={`Queued: ${jobs.data.queue_length}`} onClick={() => setExpanded(prev => ({ ...prev, queued: !prev.queued }))} />
              )}
              <Chip size="small" color={expanded.running ? 'info' : 'default'} variant={expanded.running ? 'filled' : 'outlined'} label={`Running: ${running.length}`} onClick={() => setExpanded(prev => ({ ...prev, running: !prev.running }))} />
              <Chip size="small" color={expanded.failed ? 'error' : 'default'} variant={expanded.failed ? 'filled' : 'outlined'} label={`Failed: ${failedFiltered.length}`} onClick={() => setExpanded(prev => ({ ...prev, failed: !prev.failed }))} />
              <Chip size="small" color={expanded.completed ? 'success' : 'default'} variant={expanded.completed ? 'filled' : 'outlined'} label={`Finished: ${completedFiltered.length}`} onClick={() => setExpanded(prev => ({ ...prev, completed: !prev.completed }))} />
              <Chip size="small" color={expanded.canceled ? 'warning' : 'default'} variant={expanded.canceled ? 'filled' : 'outlined'} label={`Canceled: ${canceledFiltered.length}`} onClick={() => setExpanded(prev => ({ ...prev, canceled: !prev.canceled }))} />
              {selectedWorker && (
                <Chip size="small" color="primary" variant="outlined" label={`Worker: ${selectedWorker}`} />
              )}
            </Stack>
            <Stack direction="row" spacing={1} alignItems="center">
              <Tooltip title="Refresh">
                <IconButton size="small" onClick={() => jobs.refetch()}>
                  <RefreshIcon fontSize="small" />
                </IconButton>
              </Tooltip>
              <Button
                size="small"
                variant="outlined"
                color="error"
                disabled={clearing}
                onClick={async () => {
                  try {
                    setClearing(true);
                    await clearReasoning();
                    await Promise.all([diag.refetch(), jobs.refetch()]);
                  } finally {
                    setClearing(false);
                  }
                }}
              >
                Clear All Activity
              </Button>
            </Stack>
          </Stack>

          {/* Jobs filter */}
          <Box sx={{ mb: 1, display: 'flex', gap: 1, alignItems: 'center' }}>
            <TextField
              size="small"
              placeholder="Filter jobs (id, status, error, worker)"
              value={jobFilter}
              onChange={(e) => setJobFilter(e.target.value)}
              fullWidth
            />
            {jobFilter && (
              <Button size="small" onClick={() => setJobFilter('')}>Clear</Button>
            )}
          </Box>

          <Box sx={{ flex: 1, minHeight: 0, overflow: 'auto' }}>
            {/* Unified Accordion for Queued / Running / Completed / Failed / Canceled */}
            <Accordion expanded={expanded.queued} onChange={() => setExpanded(prev => ({ ...prev, queued: !prev.queued }))} disableGutters>
              <AccordionSummary expandIcon={<ExpandMoreIcon />}>
                <Stack direction="row" spacing={1} alignItems="center">
                  <ScheduleIcon color="warning" fontSize="small" />
                  <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>Queued</Typography>
                  <Chip size="small" label={queuedFiltered.length} />
                </Stack>
              </AccordionSummary>
              <AccordionDetails>
                {queuedFiltered.length === 0 ? (
                  <Typography variant="body2" sx={{ opacity: 0.7, mb: 1 }}>No queued jobs</Typography>
                ) : (
                  <List dense>
                    {queuedFiltered.map((j: any, idx: number) => (
                      <ListItemButton key={idx} onClick={() => setOpenJobId(j.job_id)}>
                        <ListItemText primary={j.job_id || 'job'} secondary={`${j.ts ? new Date(j.ts).toLocaleTimeString() : ''}`} primaryTypographyProps={{ fontSize: 12 }} secondaryTypographyProps={{ fontSize: 11, sx: { opacity: 0.8 } }} />
                        <Stack direction="row" spacing={0.5}>
                          <Button size="small" color="warning" onClick={(e)=>{ e.stopPropagation(); cancelReasoningJob(j.job_id).then(()=>jobs.refetch()); }}>Cancel</Button>
                        </Stack>
                      </ListItemButton>
                    ))}
                  </List>
                )}
              </AccordionDetails>
            </Accordion>

            {/* Unified Accordion for Running / Completed / Failed / Canceled */}
            <Accordion expanded={expanded.running} onChange={() => setExpanded(prev => ({ ...prev, running: !prev.running }))} disableGutters>
              <AccordionSummary expandIcon={<ExpandMoreIcon />}> 
                <Stack direction="row" spacing={1} alignItems="center">
                  <PlayCircleOutlineIcon color="info" fontSize="small" />
                  <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>Running</Typography>
                  <Chip size="small" label={running.length} />
                </Stack>
              </AccordionSummary>
              <AccordionDetails>
                {running.length === 0 ? (
                  <Typography variant="body2" sx={{ opacity: 0.7, mb: 1 }}>No running jobs</Typography>
                ) : (
                  <List dense>
                    {running.map((id) => (
                      <ListItemButton key={id} onClick={() => setOpenJobId(id)}>
                        <ListItemText
                          primary={id}
                          secondary={`running`}
                          primaryTypographyProps={{ fontSize: 12 }}
                          secondaryTypographyProps={{ fontSize: 11, sx: { opacity: 0.8 } }}
                        />
                        <Button size="small" color="warning" onClick={(e)=>{ e.stopPropagation(); cancelReasoningJob(id).then(()=>jobs.refetch()); }}>Cancel</Button>
                      </ListItemButton>
                    ))}
                  </List>
                )}
              </AccordionDetails>
            </Accordion>

            <Accordion expanded={expanded.completed} onChange={() => setExpanded(prev => ({ ...prev, completed: !prev.completed }))} disableGutters>
              <AccordionSummary expandIcon={<ExpandMoreIcon />}>
                <Stack direction="row" spacing={1} alignItems="center">
                  <CheckCircleOutlineIcon color="success" fontSize="small" />
                  <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>Completed</Typography>
                  <Chip size="small" label={completedFiltered.length} />
                </Stack>
              </AccordionSummary>
              <AccordionDetails>
                {completedFiltered.length === 0 ? (
                  <Typography variant="body2" sx={{ opacity: 0.7, mb: 1 }}>{selectedWorker ? 'No completed jobs for this worker' : 'No recent completed jobs'}</Typography>
                ) : (
                  <List dense>
                    {completedFiltered.map((j: any, idx: number) => (
                      <ListItemButton key={idx} onClick={() => setOpenJobId(j.job_id || j.id)}>
                        <ListItemText primary={j.job_id || j.id || 'job'} secondary={`status: ${j.status || 'ok'} • ${j.ts ? new Date(j.ts * 1000).toLocaleTimeString() : ''}`} primaryTypographyProps={{ fontSize: 12 }} secondaryTypographyProps={{ fontSize: 11, sx: { opacity: 0.8 } }} />
                        {j.agent_name && (<Chip size="small" label={`Agent: ${j.agent_name}`} sx={{ ml: 0.5 }} />)}
                        {j.goal_text && (<Chip size="small" label={`Goal: ${String(j.goal_text).slice(0,40)}${String(j.goal_text).length>40?'…':''}`} sx={{ ml: 0.5 }} />)}
                        {getWorkerFromJob(j) && (<Chip size="small" color="success" variant="outlined" label={getWorkerFromJob(j) as string} sx={{ ml: 0.5 }} />)}
                        <Button size="small" color="error" onClick={(e)=>{ e.stopPropagation(); deleteReasoningJob(j.job_id || j.id).then(()=>jobs.refetch()); }}>Delete</Button>
                      </ListItemButton>
                    ))}
                  </List>
                )}
              </AccordionDetails>
            </Accordion>

            <Accordion expanded={expanded.failed} onChange={() => setExpanded(prev => ({ ...prev, failed: !prev.failed }))} disableGutters>
              <AccordionSummary expandIcon={<ExpandMoreIcon />}>
                <Stack direction="row" spacing={1} alignItems="center">
                  <ErrorOutlineIcon color="error" fontSize="small" />
                  <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>Failed</Typography>
                  <Chip size="small" label={failedFiltered.length} />
                </Stack>
              </AccordionSummary>
              <AccordionDetails>
                {failedFiltered.length === 0 ? (
                  <Typography variant="body2" sx={{ opacity: 0.7 }}>{selectedWorker ? 'No failed jobs for this worker' : 'No recent failed jobs'}</Typography>
                ) : (
                  <List dense>
                    {failedFiltered.map((j: any, idx: number) => (
                      <ListItemButton key={idx} onClick={() => setOpenJobId(j.job_id || j.id)}>
                        <ListItemText primary={j.job_id || j.id || 'job'} secondary={`${j.error || 'error'} • ${j.ts ? new Date(j.ts * 1000).toLocaleTimeString() : ''}`} primaryTypographyProps={{ fontSize: 12 }} secondaryTypographyProps={{ fontSize: 11, sx: { opacity: 0.8 } }} />
                        {getWorkerFromJob(j) && (<Chip size="small" color="error" variant="outlined" label={getWorkerFromJob(j) as string} sx={{ ml: 1 }} />)}
                        <Button size="small" onClick={async (e)=>{ e.stopPropagation(); const r = await retryReasoningJob(j.job_id || j.id); setOpenJobId(r.job_id); jobs.refetch(); }}>Retry</Button>
                        <Button size="small" color="error" onClick={(e)=>{ e.stopPropagation(); deleteReasoningJob(j.job_id || j.id).then(()=>jobs.refetch()); }}>Delete</Button>
                      </ListItemButton>
                    ))}
                  </List>
                )}
              </AccordionDetails>
            </Accordion>

            <Accordion expanded={expanded.canceled} onChange={() => setExpanded(prev => ({ ...prev, canceled: !prev.canceled }))} disableGutters>
              <AccordionSummary expandIcon={<ExpandMoreIcon />}>
                <Stack direction="row" spacing={1} alignItems="center">
                  <ErrorOutlineIcon color="warning" fontSize="small" />
                  <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>Canceled</Typography>
                  <Chip size="small" label={canceledFiltered.length} />
                </Stack>
              </AccordionSummary>
              <AccordionDetails>
                {canceledFiltered.length === 0 ? (
                  <Typography variant="body2" sx={{ opacity: 0.7 }}>{selectedWorker ? 'No canceled jobs for this worker' : 'No recent canceled jobs'}</Typography>
                ) : (
                  <List dense>
                    {canceledFiltered.map((j: any, idx: number) => (
                      <ListItemButton key={idx} onClick={() => setOpenJobId(j.job_id || j.id)}>
                        <ListItemText primary={j.job_id || j.id || 'job'} secondary={`canceled • ${j.ts ? new Date(j.ts * 1000).toLocaleTimeString() : ''}`} primaryTypographyProps={{ fontSize: 12 }} secondaryTypographyProps={{ fontSize: 11, sx: { opacity: 0.8 } }} />
                        {j.agent_name && (<Chip size="small" label={`Agent: ${j.agent_name}`} sx={{ ml: 0.5 }} />)}
                        {j.goal_text && (<Chip size="small" label={`Goal: ${String(j.goal_text).slice(0,40)}${String(j.goal_text).length>40?'…':''}`} sx={{ ml: 0.5 }} />)}
                        {getWorkerFromJob(j) && (<Chip size="small" color="warning" variant="outlined" label={getWorkerFromJob(j) as string} sx={{ ml: 0.5 }} />)}
                        <Button size="small" color="error" onClick={(e)=>{ e.stopPropagation(); deleteReasoningJob(j.job_id || j.id).then(()=>jobs.refetch()); }}>Delete</Button>
                      </ListItemButton>
                    ))}
                  </List>
                )}
              </AccordionDetails>
            </Accordion>
          </Box>
        </Paper>
      </Grid>

      {/* Job detail dialog */}
      <Dialog open={!!openJobId} onClose={() => { setOpenJobId(null); setSearchParams(prev => { prev.delete('job'); return prev; }, { replace: true }); }} fullWidth maxWidth="md">
        <DialogTitle sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <Typography variant="subtitle2">Job {openJobId}</Typography>
          <Stack direction="row" spacing={1} alignItems="center">
            <Tooltip title="Copy">
              <span>
                <IconButton size="small" disabled={!jobCopyText} onClick={async () => { try { await navigator.clipboard.writeText(jobCopyText); } catch {} }}>
                  <ContentCopyIcon fontSize="small" />
                </IconButton>
              </span>
            </Tooltip>
            <IconButton size="small" onClick={() => { setOpenJobId(null); setSearchParams(prev => { prev.delete('job'); return prev; }, { replace: true }); }}>
              <CloseIcon fontSize="small" />
            </IconButton>
          </Stack>
        </DialogTitle>
        <DialogContent dividers>
          {!jobDetail ? (
            <LinearProgress />
          ) : jobDetail.error ? (
            <Typography variant="body2" color="error">{jobDetail.detail || jobDetail.error}</Typography>
          ) : (
            <Box component="pre" sx={{ p: 1, bgcolor: '#0d1117', color: '#c9d1d9', borderRadius: 1, fontSize: 12, maxHeight: 500, overflow: 'auto' }}>
              {jobCopyText}
            </Box>
          )}
          {openJobId && (
            <Stack direction="row" spacing={1} sx={{ mt: 1 }}>
              <Button size="small" color="warning" onClick={async () => { await cancelReasoningJob(openJobId); await jobs.refetch(); }}>Cancel</Button>
              <Button size="small" onClick={async () => { const r = await retryReasoningJob(openJobId); setOpenJobId(r.job_id); await jobs.refetch(); }}>Retry</Button>
              <Button size="small" color="error" onClick={async () => { await deleteReasoningJob(openJobId); await jobs.refetch(); }}>Delete</Button>
            </Stack>
          )}
        </DialogContent>
      </Dialog>
    </Grid>
  );
}
