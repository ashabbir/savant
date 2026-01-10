import React, { useMemo, useState } from 'react';
import { Box, Card, CardContent, CardHeader, Chip, IconButton, Stack, Table, TableBody, TableCell, TableHead, TableRow, Tooltip, Typography, Button, Dialog, DialogTitle, DialogContent, DialogActions, Snackbar, Alert, Divider, CircularProgress } from '@mui/material';
import DeleteForeverIcon from '@mui/icons-material/DeleteForever';
import OpenInNewIcon from '@mui/icons-material/OpenInNew';
import StopCircleIcon from '@mui/icons-material/StopCircle';
import CleaningServicesIcon from '@mui/icons-material/CleaningServices';
import TimelineIcon from '@mui/icons-material/Timeline';
import { useBlackboardSessions, useBlackboardStats, useKillBlackboardSession, useClearBlackboardSession, useDeleteBlackboardSession, useBlackboardReplay, useBlackboardRecentEvents, BlackboardEvent, killAllBlackboardSessions, deleteAllBlackboardSessions } from '../../api';

export default function DiagnosticsBlackboard() {
  const stats = useBlackboardStats();
  const sessions = useBlackboardSessions();
  const killMut = useKillBlackboardSession();
  const clearMut = useClearBlackboardSession();
  const deleteMut = useDeleteBlackboardSession();
  const [confirm, setConfirm] = useState<{ open: boolean; id?: string; action?: 'kill' | 'clear' | 'delete' | 'kill_all' | 'delete_all' }>(() => ({ open: false }));
  const [toast, setToast] = useState<string | null>(null);
  const [timeline, setTimeline] = useState<{ open: boolean; id?: string }>({ open: false });
  const [streamOpen, setStreamOpen] = useState(false);
  const [streamEvents, setStreamEvents] = useState<BlackboardEvent[]>([]);

  const rows = sessions.data || [];
  const counts = useMemo(() => ({
    total: rows.length,
    active: rows.filter(r => r.state === 'active').length,
    paused: rows.filter(r => r.state === 'paused').length,
    completed: rows.filter(r => r.state === 'completed').length,
  }), [rows]);

  function stateChip(state: string) {
    const color = state === 'active' ? 'success' : state === 'paused' ? 'warning' : 'default';
    return <Chip label={state} size="small" color={color as any} variant="outlined" />;
  }

  function doAction() {
    const { id, action } = confirm;
    if (!action) return;
    setConfirm({ open: false });
    if (action === 'kill_all') {
      killAllBlackboardSessions().then(() => { sessions.refetch(); setToast('All sessions killed'); });
      return;
    }
    if (action === 'delete_all') {
      deleteAllBlackboardSessions().then(() => { sessions.refetch(); setToast('All sessions deleted'); });
      return;
    }
    if (!id) return;
    if (action === 'kill') {
      killMut.mutate(id, { onSuccess: () => { sessions.refetch(); setToast('Session killed'); } });
    } else if (action === 'clear') {
      clearMut.mutate(id, { onSuccess: () => { sessions.refetch(); setToast('Session events cleared'); } });
    } else if (action === 'delete') {
      deleteMut.mutate(id, { onSuccess: () => { sessions.refetch(); setToast('Session deleted'); } });
    }
  }

  const replay = useBlackboardReplay(timeline.open ? (timeline.id || null) : null, { pollMs: 2000 });
  const [timelineEvents, setTimelineEvents] = useState<BlackboardEvent[]>([]);

  // Load baseline replay when dialog opens
  React.useEffect(() => {
    if (!timeline.open) return;
    if (replay.data) setTimelineEvents(replay.data);
  }, [timeline.open, replay.data]);

  // Poll per-session timeline (replay) while dialog open
  React.useEffect(() => {
    if (!timeline.open) return;
    setTimelineEvents(replay.data || []);
  }, [timeline.open, replay.data]);

  // Poll global recent events while dialog open
  const recent = useBlackboardRecentEvents(200, streamOpen, { pollMs: 2000 });
  React.useEffect(() => {
    if (!streamOpen) return;
    setStreamEvents(recent.data || []);
  }, [streamOpen, recent.data]);

  function EventRow({ ev }: { ev: BlackboardEvent }) {
    return (
      <Box sx={{ fontFamily: 'monospace', py: 0.5, borderBottom: '1px solid', borderColor: 'divider' }}>
        <Typography variant="caption" color="text.secondary">{ev.created_at ? new Date(ev.created_at).toLocaleTimeString() : ''}</Typography>
        <Typography variant="body2" component="span" sx={{ ml: 1, color: 'warning.main' }}>{ev.type}</Typography>
        <Typography variant="caption" component="span" sx={{ ml: 1, color: 'success.main' }}>session:{(ev.session_id || '').slice(0, 8)}…</Typography>
        {ev.actor_id && <Typography variant="caption" component="span" sx={{ ml: 1, color: 'info.main' }}>actor:{ev.actor_id}</Typography>}
        {ev.payload && <Typography variant="caption" sx={{ display: 'block', color: 'text.secondary' }}>{JSON.stringify(ev.payload)}</Typography>}
      </Box>
    );
  }

  return (
    <Stack spacing={2}>
      <Card>
        <CardHeader title="Blackboard" subheader="Sessions and global event substrate" />
        <CardContent>
          <Stack direction="row" spacing={1} alignItems="center" flexWrap="wrap" useFlexGap>
            <Chip label={`Sessions ${stats.data?.sessions ?? '—'}`} size="small" />
            <Chip label={`Events ${stats.data?.events ?? '—'}`} size="small" />
            <Chip label={`Artifacts ${stats.data?.artifacts ?? '—'}`} size="small" />
            <Box sx={{ flexGrow: 1 }} />
            <Chip label={`Active ${counts.active}`} size="small" variant="outlined" />
            <Chip label={`Paused ${counts.paused}`} size="small" variant="outlined" />
            <Chip label={`Completed ${counts.completed}`} size="small" variant="outlined" />
          </Stack>
        </CardContent>
      </Card>

      <Card>
        <CardHeader title={`Sessions (${rows.length})`} action={
          <Stack direction="row" spacing={1}>
            <Button size="small" startIcon={<TimelineIcon />} onClick={() => { setStreamEvents([]); setStreamOpen(true); }}>Live Events</Button>
            <Button size="small" color="warning" startIcon={<StopCircleIcon />} onClick={() => setConfirm({ open: true, action: 'kill_all' })}>Kill All</Button>
            <Button size="small" color="error" startIcon={<DeleteForeverIcon />} onClick={() => setConfirm({ open: true, action: 'delete_all' })}>Delete All</Button>
          </Stack>
        } />
        <CardContent>
          <Table size="small">
            <TableHead>
              <TableRow>
                <TableCell>Session ID</TableCell>
                <TableCell>Type</TableCell>
                <TableCell>State</TableCell>
                <TableCell>Created</TableCell>
                <TableCell align="right">Actions</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {rows.map((r) => (
                <TableRow key={r.session_id} hover>
                  <TableCell sx={{ fontFamily: 'monospace' }}>{r.session_id}</TableCell>
                  <TableCell>{r.type}</TableCell>
                  <TableCell>{stateChip(r.state)}</TableCell>
                  <TableCell>{r.created_at ? new Date(r.created_at).toLocaleString() : ''}</TableCell>
                  <TableCell align="right">
                    <Stack direction="row" spacing={1} justifyContent="flex-end">
                      <Tooltip title="Open Timeline">
                        <span>
                          <IconButton size="small" onClick={() => setTimeline({ open: true, id: r.session_id })}>
                            <OpenInNewIcon fontSize="small" />
                          </IconButton>
                        </span>
                      </Tooltip>
                      {r.state !== 'completed' && (
                        <Tooltip title="Kill Session">
                          <span>
                            <IconButton size="small" color="error" onClick={() => setConfirm({ open: true, id: r.session_id, action: 'kill' })} disabled={killMut.isPending}>
                              <StopCircleIcon fontSize="small" />
                            </IconButton>
                          </span>
                        </Tooltip>
                      )}
                      <Tooltip title="Clear Events">
                        <span>
                          <IconButton size="small" color="warning" onClick={() => setConfirm({ open: true, id: r.session_id, action: 'clear' })} disabled={clearMut.isPending}>
                            <CleaningServicesIcon fontSize="small" />
                          </IconButton>
                        </span>
                      </Tooltip>
                      <Tooltip title="Delete Session">
                        <span>
                          <IconButton size="small" onClick={() => setConfirm({ open: true, id: r.session_id, action: 'delete' })} disabled={deleteMut.isPending}>
                            <DeleteForeverIcon fontSize="small" />
                          </IconButton>
                        </span>
                      </Tooltip>
                    </Stack>
                  </TableCell>
                </TableRow>
              ))}
              {rows.length === 0 && (
                <TableRow>
                  <TableCell colSpan={5}>
                    <Typography variant="body2" color="text.secondary">No sessions found.</Typography>
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      {/* Confirm action dialog */}
      <Dialog open={confirm.open} onClose={() => setConfirm({ open: false })}>
        <DialogTitle>
          {confirm.action === 'kill' ? 'Kill session?' : confirm.action === 'clear' ? 'Clear session events?' : confirm.action === 'delete' ? 'Delete session?' : confirm.action === 'kill_all' ? 'Kill ALL sessions?' : 'Delete ALL sessions?'}
        </DialogTitle>
        <DialogContent>
          {confirm.action === 'kill' && (
            <Typography variant="body2">This will mark the session as completed and emit a terminal event.</Typography>
          )}
          {confirm.action === 'clear' && (
            <Typography variant="body2">This will delete all events for the session. The session document remains.</Typography>
          )}
          {confirm.action === 'delete' && (
            <Typography variant="body2">This will delete the session and all its events. This action cannot be undone.</Typography>
          )}
          {confirm.action === 'kill_all' && (
            <Typography variant="body2">This will mark ALL sessions as completed and emit terminal events. Proceed?</Typography>
          )}
          {confirm.action === 'delete_all' && (
            <Typography variant="body2">This will delete ALL sessions and their events. This action cannot be undone.</Typography>
          )}
          {confirm.id && (
            <Typography variant="caption" sx={{ mt: 1, display: 'block', fontFamily: 'monospace' }}>{confirm.id}</Typography>
          )}
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setConfirm({ open: false })}>Cancel</Button>
          <Button color={confirm.action === 'clear' || confirm.action === 'kill_all' ? 'warning' : 'error'} variant="contained" startIcon={<DeleteForeverIcon />} onClick={doAction} disabled={killMut.isPending || clearMut.isPending || deleteMut.isPending}>
            {confirm.action === 'kill' ? 'Kill' : confirm.action === 'clear' ? 'Clear' : confirm.action === 'delete' ? 'Delete' : confirm.action === 'kill_all' ? 'Kill All' : 'Delete All'}
          </Button>
        </DialogActions>
      </Dialog>

      {/* Session timeline popup */}
      <Dialog open={timeline.open} onClose={() => setTimeline({ open: false })} maxWidth="md" fullWidth>
        <DialogTitle>Session Timeline</DialogTitle>
        <DialogContent dividers>
          {replay.isLoading ? (
            <Box display="flex" justifyContent="center" py={2}><CircularProgress size={20} /></Box>
          ) : (
            <Box sx={{ maxHeight: 500, overflow: 'auto' }}>
              {(timelineEvents || []).map((ev) => (
                <EventRow key={ev.event_id} ev={ev} />
              ))}
              {(!timelineEvents || timelineEvents.length === 0) && (
                <Typography variant="body2" color="text.secondary">No events yet.</Typography>
              )}
            </Box>
          )}
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setTimeline({ open: false })}>Close</Button>
        </DialogActions>
      </Dialog>

      {/* Global non-session events popup (global SSE stream) */}
      <Dialog open={streamOpen} onClose={() => setStreamOpen(false)} maxWidth="md" fullWidth>
        <DialogTitle>Global Events (All Sessions)</DialogTitle>
        <DialogContent dividers>
          <Box sx={{ maxHeight: 500, overflow: 'auto' }}>
            {streamEvents.map((ev, idx) => (
              <EventRow key={`${ev.event_id}:${idx}`} ev={ev} />
            ))}
            {streamEvents.length === 0 && (
              <Typography variant="body2" color="text.secondary">Listening for events…</Typography>
            )}
          </Box>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setStreamOpen(false)}>Close</Button>
        </DialogActions>
      </Dialog>

      <Snackbar open={!!toast} autoHideDuration={3000} onClose={() => setToast(null)} message={toast || ''}>
        <Alert onClose={() => setToast(null)} severity="success" sx={{ width: '100%' }}>
          {toast}
        </Alert>
      </Snackbar>
    </Stack>
  );
}
