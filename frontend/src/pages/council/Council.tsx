import React, { useEffect, useMemo, useState, useRef, useCallback } from 'react';
import { agentRun, agentRunContinue, agentRunRead, useAgents, useCouncilSessions, councilSessionCreate, councilSessionGet, councilAppendUser, councilAppendAgent, councilSessionDelete, councilSessionUpdate, councilEscalate, councilRun as runCouncilApi, councilReturnToChat, CouncilRun } from '../../api';
import { useTheme, alpha } from '@mui/material/styles';
import Grid from '@mui/material/Unstable_Grid2';
import Paper from '@mui/material/Paper';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import Stack from '@mui/material/Stack';
import Chip from '@mui/material/Chip';
import Avatar from '@mui/material/Avatar';
import Button from '@mui/material/Button';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import DialogActions from '@mui/material/DialogActions';
import Stepper from '@mui/material/Stepper';
import Step from '@mui/material/Step';
import StepLabel from '@mui/material/StepLabel';
import TextField from '@mui/material/TextField';
import IconButton from '@mui/material/IconButton';
import Tooltip from '@mui/material/Tooltip';
import List from '@mui/material/List';
import ListItem from '@mui/material/ListItem';
import ListItemButton from '@mui/material/ListItemButton';
import ListItemText from '@mui/material/ListItemText';
import LinearProgress from '@mui/material/LinearProgress';
import Accordion from '@mui/material/Accordion';
import AccordionSummary from '@mui/material/AccordionSummary';
import AccordionDetails from '@mui/material/AccordionDetails';
import Alert from '@mui/material/Alert';
import AddCircleIcon from '@mui/icons-material/AddCircle';
import EditIcon from '@mui/icons-material/Edit';
import DeleteOutlineIcon from '@mui/icons-material/DeleteOutline';
import GavelIcon from '@mui/icons-material/Gavel';
import ChatIcon from '@mui/icons-material/Chat';
import ExpandMoreIcon from '@mui/icons-material/ExpandMore';
import BlockIcon from '@mui/icons-material/Block';
import CheckCircleIcon from '@mui/icons-material/CheckCircle';
import ErrorIcon from '@mui/icons-material/Error';
import GroupIcon from '@mui/icons-material/Group';

type AgentSession = { lastRunId: number | null; running?: boolean };
type AgentReply = {
  agent: string;
  runId: number;
  text: string;
  status: 'running' | 'ok' | 'error';
  startedAt?: number;
  finishedAt?: number;
  durationMs?: number;
  at?: number;
};
type ChatTurn = { id: number; user: string; replies: AgentReply[]; at?: number };

const PANEL_HEIGHT = 'calc(100vh - 260px)';
const LS_LAST_OPEN = 'councilLastOpen';

export default function Council() {
  const theme = useTheme();
  const allAgents = useAgents();
  const sessions = useCouncilSessions();
  const [sessionId, setSessionId] = useState<number | null>(null);
  const [sessionTitle, setSessionTitle] = useState<string>('');
  const [sessionMembers, setSessionMembers] = useState<string[]>([]);
  const [sessionDescription, setSessionDescription] = useState<string>('');
  const [selected, setSelected] = useState<string[]>([]);
  const [agentSessions, setAgentSessions] = useState<Record<string, AgentSession>>({});
  const [input, setInput] = useState('');
  const [sending, setSending] = useState(false);
  const [turns, setTurns] = useState<ChatTurn[]>([]);
  const [showHistory, setShowHistory] = useState(false); // no longer used; left panel always lists councils
  const chatRef = useRef<HTMLDivElement | null>(null);
  // New group dialog state
  const [newOpen, setNewOpen] = useState(false);
  const [newStep, setNewStep] = useState(0);
  const [newName, setNewName] = useState('');
  const [newMembers, setNewMembers] = useState<string[]>([]);
  const [newDesc, setNewDesc] = useState('');
  // Edit members dialog state
  const [editOpen, setEditOpen] = useState(false);
  const [editMembers, setEditMembers] = useState<string[]>([]);
  // Rename dialog
  const [renameOpen, setRenameOpen] = useState(false);
  const [renameTitle, setRenameTitle] = useState('');
  const [renameDesc, setRenameDesc] = useState('');
  // Search filter for sessions
  const [filter, setFilter] = useState('');
  // Last-open timestamps for unread indicators
  const [lastOpen, setLastOpen] = useState<Record<number, number>>(() => {
    try { return JSON.parse(localStorage.getItem(LS_LAST_OPEN) || '{}'); } catch { return {}; }
  });
  // Council protocol state
  const [sessionMode, setSessionMode] = useState<'chat' | 'council'>('chat');
  const [councilRun, setCouncilRun] = useState<CouncilRun | null>(null);
  const [councilLoading, setCouncilLoading] = useState(false);
  const [escalateOpen, setEscalateOpen] = useState(false);
  const [escalateQuery, setEscalateQuery] = useState('');

  useEffect(() => {
    const map: Record<string, AgentSession> = {};
    const list = (allAgents.data && (allAgents.data as any).agents) || [];
    (list as any[]).forEach((a: any) => { map[a.name] = { lastRunId: null }; });
    setAgentSessions((prev) => ({ ...map, ...prev }));
  }, [allAgents.data]);

  const available = useMemo(() => {
    const list = (allAgents.data && (allAgents.data as any).agents) || [];
    return (list as any[]).map((a: any) => (a.name as string));
  }, [allAgents.data]);

  const toggleAgent = (name: string) => {
    setSelected((prev) => (prev.includes(name) ? prev.filter((n) => n !== name) : [...prev, name]));
  };

  function buildHistoryString(history: ChatTurn[]): string {
    try {
      const lines: string[] = [];
      history.forEach((t) => {
        if (t.user?.trim()) lines.push(`User: ${t.user.trim()}`);
        (t.replies || []).forEach((r) => {
          if (r.status !== 'running' && (r.text?.trim() || r.status === 'error')) {
            const body = (r.text || '').trim();
            if (body) lines.push(`${r.agent}: ${body}`);
          }
        });
      });
      return lines.join('\n');
    } catch {
      return '';
    }
  }

  function normalizeAgentName(name: string): string {
    try {
      let n = (name || '').toString().trim();
      if ((n.startsWith('"') && n.endsWith('"')) || (n.startsWith("'") && n.endsWith("'"))) {
        n = n.slice(1, -1).trim();
      }
      return n;
    } catch { return name; }
  }

  const loadSession = async (id: number) => {
    setSessionId(id);
    try {
      const data = await councilSessionGet(id);
      const msgs = data.messages || [];
      try { setSessionTitle((data as any).title || `Session #${id}`); } catch { setSessionTitle(`Session #${id}`); }
      try { setSessionDescription((data as any).description || ''); } catch { setSessionDescription(''); }
      try {
        const agents = (data as any).agents as string[] | undefined;
        if (agents && Array.isArray(agents)) {
          const norm = agents.map((n) => normalizeAgentName(n));
          setSessionMembers(norm);
          setSelected(norm);
        }
      } catch {}
      // Set session mode and council run
      try {
        const mode = (data as any).mode || 'chat';
        setSessionMode(mode as 'chat' | 'council');
        setCouncilRun((data as any).council_run || null);
      } catch {
        setSessionMode('chat');
        setCouncilRun(null);
      }
      const grouped: ChatTurn[] = [];
      let cur: ChatTurn | null = null;
      msgs.forEach((m) => {
        if (m.role === 'user') {
          if (cur) grouped.push(cur);
          cur = { id: m.id, user: m.text || '', replies: [], at: m.created_at ? Date.parse(m.created_at) : undefined };
        } else {
          if (!cur) cur = { id: m.id, user: '', replies: [] };
          cur.replies.push({ agent: m.agent_name || '', runId: m.run_id || 0, text: m.text || '', status: (m.status as any) || 'ok', at: m.created_at ? Date.parse(m.created_at) : undefined });
        }
      });
      if (cur) grouped.push(cur);
      setTurns(grouped);
      // Mark as read now (update last-open timestamp)
      const now = Date.now();
      setLastOpen((prev) => {
        const next = { ...prev, [id]: now };
        try { localStorage.setItem(LS_LAST_OPEN, JSON.stringify(next)); } catch {}
        return next;
      });
    } catch {}
  };

  const handleSend = async () => {
    const text = input.trim();
    if (!text || selected.length === 0) return;
    setSending(true);
    setInput('');
    const historyStr = buildHistoryString(turns);
    const messageWithHistory = historyStr ? `Conversation so far:\n${historyStr}\n\nUser: ${text}` : text;
    const turnId = Date.now();
    // Create placeholders for replies (hidden while running)
    setTurns((prev) => [
      ...prev,
      {
        id: turnId,
        user: text,
        at: Date.now(),
        replies: selected.map((n) => ({ agent: normalizeAgentName(n), runId: 0, text: '', status: 'running' as const })),
      },
    ]);
    try {
      let sid = sessionId;
      if (!sid) { const created = await councilSessionCreate(undefined, selected); sid = created.id; setSessionId(sid); }
      if (sid) await councilAppendUser(sid, text);
    } catch {}

    await Promise.all(selected.map(async (agentRaw) => {
      const agent = normalizeAgentName(agentRaw);
      const sess = agentSessions[agent] || { lastRunId: null };
      try {
        const submitStartedAt = Date.now();
        let runId: number | null = null;
        if (sess.lastRunId) { const res = await agentRunContinue(agent, sess.lastRunId, messageWithHistory, 12); runId = res?.run_id || null; }
        else { const res = await agentRun(agent, messageWithHistory, 12); runId = res?.run_id || null; }
        if (runId) {
          setAgentSessions((prev) => ({ ...prev, [agent]: { lastRunId: runId, running: true } }));
          // Mark startedAt on the reply immediately
          setTurns((prev) => prev.map((t) => (t.id === turnId ? { ...t, replies: t.replies.map((r) => (r.agent === agent ? { ...r, runId, startedAt: submitStartedAt } : r)) } : t)));
          await pollRun(agent, runId, submitStartedAt, (reply) => {
            setTurns((prev) => prev.map((t) => (
              t.id === turnId
                ? { ...t, replies: t.replies.map((r) => (r.agent === agent ? { ...r, ...reply } : r)) }
                : t
            )));
          });
          setAgentSessions((prev) => ({ ...prev, [agent]: { lastRunId: runId, running: false } }));
          if (sessionId) { try { const d = await agentRunRead(agent, runId); await councilAppendAgent(sessionId, agent, runId, d?.output_summary || '', 'ok'); } catch {} }
        } else {
          const now = Date.now();
          const reply: AgentReply = { agent, runId: 0, text: 'submit failed', status: 'error', startedAt: submitStartedAt, finishedAt: now, durationMs: now - submitStartedAt };
          setTurns((prev) => prev.map((t) => (t.id === turnId ? { ...t, replies: t.replies.map((r) => (r.agent === agent ? reply : r)) } : t)));
          if (sessionId) { try { await councilAppendAgent(sessionId, agent, null, 'submit failed', 'error'); } catch {} }
        }
      } catch (e: any) {
        const now = Date.now();
        const reply: AgentReply = { agent, runId: 0, text: e?.message || 'error', status: 'error', finishedAt: now };
        setTurns((prev) => prev.map((t) => (t.id === turnId ? { ...t, replies: t.replies.map((r) => (r.agent === agent ? reply : r)) } : t)));
        if (sessionId) { try { await councilAppendAgent(sessionId, agent, null, e?.message || 'error', 'error'); } catch {} }
      }
    }));
    setSending(false);
  };

  async function pollRun(agent: string, runId: number, startedAt: number, onUpdate: (r: AgentReply) => void) {
    let finished = false;
    while (!finished) {
      try {
        const d = await agentRunRead(agent, runId);
        const status = String(d?.status || '').toLowerCase();
        const text = d?.output_summary || '';
        const now = Date.now();
        const normStatus: AgentReply['status'] = (status === 'running' ? 'running' : status === 'error' ? 'error' : 'ok');
        const payload: AgentReply = { agent, runId, text, status: normStatus };
        if (normStatus !== 'running') {
          payload.startedAt = startedAt;
          payload.finishedAt = now;
          payload.durationMs = now - (startedAt || now);
          finished = true;
        }
        onUpdate(payload);
      } catch {
        const now = Date.now();
        onUpdate({ agent, runId, text: 'read failed', status: 'error', startedAt, finishedAt: now, durationMs: now - (startedAt || now) });
        finished = true;
      }
      if (!finished) await new Promise((r) => setTimeout(r, 1200));
    }
  }

  // Council Protocol Functions - Single action: escalate and run with live polling
  const handleStartCouncil = useCallback(async () => {
    if (!sessionId) return;
    setCouncilLoading(true);
    setEscalateOpen(false);

    // Polling function to update UI during deliberation
    let pollInterval: ReturnType<typeof setInterval> | null = null;
    const startPolling = () => {
      pollInterval = setInterval(async () => {
        try {
          const sess = await councilSessionGet(sessionId);
          reloadMessages(sess.messages || []);
          const run = (sess as any).council_run;
          if (run) {
            setCouncilRun(run);
            // Auto-scroll as new messages come in
            setTimeout(() => chatRef.current?.scrollTo({ top: chatRef.current.scrollHeight, behavior: 'smooth' }), 50);
          }
          // Refresh sessions list to update mode icon
          sessions.refetch();
        } catch {}
      }, 1500); // Poll every 1.5 seconds
    };

    const stopPolling = () => {
      if (pollInterval) {
        clearInterval(pollInterval);
        pollInterval = null;
      }
    };

    try {
      // Step 1: Escalate to council mode
      const escalateResult = await councilEscalate(sessionId, escalateQuery || undefined);
      setSessionMode('council');
      setCouncilRun({ ...escalateResult, status: 'running', phase: 'init', veto: false } as any);
      setEscalateQuery('');

      // Refresh sessions list immediately to show mode change
      sessions.refetch();

      // Start polling for live updates
      startPolling();

      // Step 2: Run the council protocol (this is the long-running operation)
      const result = await runCouncilApi(sessionId);

      // Stop polling once complete
      stopPolling();

      // Final reload to ensure we have the complete data
      const sess = await councilSessionGet(sessionId);
      setSessionMode((sess.mode as any) || 'chat');
      reloadMessages(sess.messages || []);
      setCouncilRun((sess as any).council_run || {
        ...result,
        status: result.status as any,
        synthesis: result.synthesis,
        positions: result.positions,
        debate_rounds: result.debate_rounds,
      } as any);
      sessions.refetch();
      // Scroll to bottom
      setTimeout(() => chatRef.current?.scrollTo({ top: chatRef.current.scrollHeight, behavior: 'smooth' }), 100);
    } catch (e: any) {
      console.error('Council failed:', e);
      stopPolling();
      // Still reload session to show any error messages
      try {
        const sess = await councilSessionGet(sessionId);
        reloadMessages(sess.messages || []);
        setCouncilRun((sess as any).council_run || null);
      } catch {}
    } finally {
      stopPolling();
      setCouncilLoading(false);
    }
  }, [sessionId, escalateQuery, sessions]);

  const handleReturnToChat = useCallback(async () => {
    if (!sessionId) return;
    setCouncilLoading(true);
    try {
      await councilReturnToChat(sessionId, 'User requested return to chat');
      setSessionMode('chat');
      setCouncilRun(null);
      // Reload session to show return message
      const sess = await councilSessionGet(sessionId);
      reloadMessages(sess.messages || []);
      sessions.refetch();
      // Scroll to bottom
      setTimeout(() => chatRef.current?.scrollTo({ top: chatRef.current.scrollHeight, behavior: 'smooth' }), 100);
    } catch (e: any) {
      console.error('Return to chat failed:', e);
    } finally {
      setCouncilLoading(false);
    }
  }, [sessionId, sessions]);

  const reloadMessages = (messages: any[]) => {
    const newTurns: ChatTurn[] = [];
    let currentTurn: ChatTurn | null = null;
    messages.forEach((m) => {
      if (m.role === 'user') {
        if (currentTurn) newTurns.push(currentTurn);
        currentTurn = {
          id: m.id,
          user: m.text || '',
          replies: [],
          at: m.created_at ? new Date(m.created_at).getTime() : undefined
        };
      } else if (m.role === 'agent' && currentTurn) {
        currentTurn.replies.push({
          agent: m.agent_name || 'Agent',
          runId: m.run_id || 0,
          text: m.text || '',
          status: m.status === 'error' ? 'error' : 'ok',
          at: m.created_at ? new Date(m.created_at).getTime() : undefined
        });
      }
    });
    if (currentTurn) newTurns.push(currentTurn);
    setTurns(newTurns);
  };

  const isDark = theme.palette.mode === 'dark';
  const selectedBg = theme.palette.action.selected;

  function hashString(str: string): number {
    let h = 0;
    for (let i = 0; i < str.length; i++) h = (h << 5) - h + str.charCodeAt(i);
    return Math.abs(h);
  }

  function agentBubbleBg(name: string, status: AgentReply['status']): string {
    if (status === 'error') return alpha(theme.palette.error.main, isDark ? 0.25 : 0.15);
    const hue = hashString(name) % 360;
    const sat = isDark ? 55 : 70;
    const light = isDark ? 22 : 92;
    return `hsl(${hue} ${sat}% ${light}%)`;
  }

  const meBubbleBg = isDark ? alpha(theme.palette.primary.light, 0.15) : alpha(theme.palette.primary.main, 0.12);
  const meBubbleFg = theme.palette.text.primary;

  const fmtClock = (ts?: number) => {
    if (!ts) return '';
    try { return new Date(ts).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' }); } catch { return ''; }
  };
  const avatarColor = (name: string) => {
    const hue = hashString(name) % 360;
    const sat = 65;
    const light = isDark ? 35 : 70;
    return `hsl(${hue} ${sat}% ${light}%)`;
  };

  function initialsFor(name: string, maxLen: number = 2): string {
    try {
      const n = (name || '').trim();
      if (!n) return '?';
      // Split on spaces, hyphens and underscores
      let parts = n.split(/[\s_-]+/).filter(Boolean);
      if (parts.length >= 2) {
        const first = parts[0][0] || '';
        const last = parts[parts.length - 1][0] || '';
        return (first + last).toUpperCase().slice(0, maxLen);
      }
      // Single token: take first letters of camelCase or first two chars
      const single = parts[0];
      const camel = single.replace(/([a-z])([A-Z])/g, '$1 $2').split(/[\s]+/);
      if (camel.length >= 2) {
        const first = camel[0][0] || '';
        const second = camel[1][0] || '';
        return (first + second).toUpperCase().slice(0, maxLen);
      }
      return single.substring(0, maxLen).toUpperCase();
    } catch { return '?'; }
  }

  function formatRelative(ts?: string | number | null): string {
    try {
      if (ts === undefined || ts === null) return '';
      const t = typeof ts === 'number' ? ts : Date.parse(ts);
      if (!Number.isFinite(t)) return '';
      const diff = Date.now() - t;
      const s = Math.floor(diff / 1000);
      if (s < 5) return 'just now';
      if (s < 60) return `${s}s ago`;
      const m = Math.floor(s / 60);
      if (m < 60) return `${m}m ago`;
      const h = Math.floor(m / 60);
      if (h < 24) return `${h}h ago`;
      const d = Math.floor(h / 24);
      if (d < 7) return `${d}d ago`;
      // Fallback to date string
      const dt = new Date(t);
      return dt.toLocaleDateString();
    } catch { return ''; }
  }

  function isUnread(session: any): boolean {
    try {
      const key = Number(session.id);
      const last = lastOpen[key] || 0;
      const ts = session.last_at || session.updated_at || session.created_at;
      const when = ts ? Date.parse(ts) : 0;
      return when > last;
    } catch { return false; }
  }

  // Auto-scroll to bottom when new messages arrive or update
  useEffect(() => {
    const el = chatRef.current;
    if (!el) return;
    requestAnimationFrame(() => {
      try { el.scrollTop = el.scrollHeight; } catch {}
    });
  }, [turns]);

  function dayLabel(ts?: number): string | null {
    try {
      if (!ts) return null;
      const d = new Date(ts);
      return d.toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });
    } catch { return null; }
  }

  const filteredSessions = useMemo(() => {
    const list = sessions.data?.sessions || [];
    const f = filter.trim().toLowerCase();
    if (!f) return list;
    return list.filter((s: any) => {
      const title = (s.title || '').toString().toLowerCase();
      const id = String(s.id || '');
      return title.includes(f) || id.includes(f);
    });
  }, [sessions.data, filter]);

  return (
    <Grid container spacing={2}>
      {/* Left Panel: Councils list and actions */}
      <Grid xs={12} md={4}>
        <Paper sx={{ p: 1, height: PANEL_HEIGHT, display: 'flex', flexDirection: 'column' }}>
          <Stack direction="row" alignItems="center" justifyContent="space-between" sx={{ mb: 1 }}>
            <Typography variant="subtitle1" sx={{ fontSize: 12 }}>Councils</Typography>
            <Stack direction="row" spacing={1} alignItems="center">
              <Tooltip title="New Council">
                <IconButton size="small" color="primary" onClick={() => { setNewOpen(true); setNewStep(0); setNewName(''); setNewMembers([]); }}>
                  <AddCircleIcon fontSize="small" />
                </IconButton>
              </Tooltip>
              <Tooltip title={sessionId ? 'Rename Council' : 'Select a council'}>
                <span>
                  <IconButton size="small" color="primary" disabled={!sessionId} onClick={() => {
                    if (!sessionId) return;
                    setRenameTitle(sessionTitle || '');
                    setRenameDesc(sessionDescription || '');
                    setRenameOpen(true);
                  }}>
                    <EditIcon fontSize="small" />
                  </IconButton>
                </span>
              </Tooltip>
              <Tooltip title={sessionId ? 'Edit Members' : 'Select a council'}>
                <span>
                  <IconButton size="small" color="primary" disabled={!sessionId} onClick={() => {
                    if (!sessionId) return;
                    setEditMembers(sessionMembers.length ? sessionMembers : selected);
                    setEditOpen(true);
                  }}>
                    <GroupIcon fontSize="small" />
                  </IconButton>
                </span>
              </Tooltip>
              <Tooltip title={sessionId ? 'Delete Council' : 'Select a council'}>
                <span>
                  <IconButton size="small" color="error" disabled={!sessionId} onClick={async () => {
                    if (!sessionId) return;
                    try {
                      await councilSessionDelete(sessionId);
                      await sessions.refetch();
                      setSessionId(null);
                      setSessionTitle('');
                      setSessionMembers([]);
                      setSelected([]);
                      setTurns([]);
                    } catch {}
                  }}>
                    <DeleteOutlineIcon fontSize="small" />
                  </IconButton>
                </span>
              </Tooltip>
            </Stack>
          </Stack>
          <TextField size="small" placeholder="Search..." value={filter} onChange={(e) => setFilter(e.target.value)} sx={{ mb: 1 }} />
          <Paper variant="outlined" sx={{ p: 1, flex: 1, overflowY: 'auto' }}>
            {filteredSessions.length === 0 ? (
              <Typography variant="body2" color="text.secondary">No councils{filter ? ' match your search' : ''}. Create one to get started.</Typography>
            ) : (
              <List dense>
                {filteredSessions.map((s: any) => (
                  <ListItem key={s.id} disablePadding>
                    <ListItemButton selected={sessionId === s.id} onClick={() => loadSession(s.id)}>
                      <Tooltip title={s.mode === 'council' ? 'In Council Mode' : 'In Chat Mode'}>
                        <Box sx={{ mr: 1, display: 'flex', alignItems: 'center' }}>
                          {s.mode === 'council' ? (
                            <GavelIcon fontSize="small" color="warning" sx={{ fontSize: 16 }} />
                          ) : (
                            <ChatIcon fontSize="small" color="action" sx={{ fontSize: 16 }} />
                          )}
                        </Box>
                      </Tooltip>
                      <ListItemText
                        primary={
                          <Stack direction="row" spacing={1} alignItems="center">
                            {isUnread(s) && <Box sx={{ width: 8, height: 8, borderRadius: '50%', bgcolor: 'primary.main' }} />}
                            <Typography variant="body2" sx={{ fontWeight: sessionId === s.id ? 700 : 500, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                              {s.title || `Session #${s.id}`}
                            </Typography>
                          </Stack>
                        }
                        secondary={
                          <>
                            <Typography variant="caption" color="text.secondary" sx={{ display: 'block', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                              {s.last_preview || 'No messages yet'}
                            </Typography>
                            <Typography variant="caption" color="text.secondary">{formatRelative(s.last_at || s.updated_at || s.created_at)}</Typography>
                          </>
                        }
                      />
                    </ListItemButton>
                  </ListItem>
                ))}
              </List>
            )}
          </Paper>
        </Paper>
      </Grid>

      {/* New Council (Group) Dialog */}
      <Dialog open={newOpen} onClose={() => setNewOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle>New Council</DialogTitle>
        <DialogContent>
          <Stepper activeStep={newStep} alternativeLabel sx={{ mb: 2 }}>
            <Step><StepLabel>Group Name</StepLabel></Step>
            <Step><StepLabel>Participants</StepLabel></Step>
          </Stepper>
          {newStep === 0 && (
            <Box sx={{ mt: 1 }}>
              <TextField
                autoFocus
                fullWidth
                label="Group name"
                placeholder="e.g., Product Planning Council"
                value={newName}
                onChange={(e) => setNewName(e.target.value)}
              />
              <TextField fullWidth multiline minRows={3} label="Description" value={newDesc} onChange={(e) => setNewDesc(e.target.value)} sx={{ mt: 1 }} />
            </Box>
          )}
          {newStep === 1 && (
            <Box>
              <Typography variant="body2" color="text.secondary" sx={{ mb: 1 }}>Select agents to include in this group.</Typography>
              <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 1 }}>
                {available.map((name) => {
                  const active = newMembers.includes(name);
                  return (
                    <Chip
                      key={name}
                      size="small"
                      label={name}
                      color={active ? 'primary' : 'default'}
                      variant={active ? 'filled' : 'outlined'}
                      onClick={() => setNewMembers((prev) => prev.includes(name) ? prev.filter((n) => n !== name) : [...prev, name])}
                      sx={{ cursor: 'pointer' }}
                    />
                  );
                })}
              </Box>
            </Box>
          )}
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setNewOpen(false)}>Cancel</Button>
          {newStep > 0 && <Button onClick={() => setNewStep((s) => Math.max(0, s - 1))}>Back</Button>}
          {newStep === 0 && (
            <Button variant="contained" onClick={() => setNewStep(1)} disabled={!newName.trim()}>Next</Button>
          )}
          {newStep === 1 && (
            <Button
              variant="contained"
              disabled={newMembers.length === 0}
              onClick={async () => {
                try {
                  const created = await councilSessionCreate(newName.trim() || undefined, newMembers.map((n) => normalizeAgentName(n)), newDesc || undefined);
                  await sessions.refetch();
                  setSelected(newMembers.map((n) => normalizeAgentName(n)));
                  await loadSession(created.id);
                  setSessionId(created.id);
                  setSessionTitle(newName.trim() || `Session #${created.id}`);
                  const normMembers = newMembers.map((n) => normalizeAgentName(n));
                  setSessionMembers(normMembers);
                  setSessionDescription(newDesc || '');
                  // Emit join events so it reads like a chat
                  for (const a of normMembers) {
                    try { await councilAppendAgent(created.id, a, null, 'joined the council', 'ok'); } catch {}
                  }
                  setNewOpen(false);
                } catch { /* ignore */ }
              }}
            >Create</Button>
          )}
        </DialogActions>
      </Dialog>

      {/* Right Panel: Transcript and controls */}
      <Grid xs={12} md={8}>
      <Paper variant="outlined" sx={{ p: 2, height: PANEL_HEIGHT, display: 'flex', flexDirection: 'column', gap: 1 }}>
        <Stack direction="row" alignItems="center" justifyContent="space-between" sx={{ mb: 0.5 }}>
          <Box>
            <Stack direction="row" alignItems="center" spacing={1}>
              <Typography variant="subtitle1" sx={{ fontWeight: 600 }}>{sessionTitle || (sessionId ? `Session #${sessionId}` : 'Transcript')}</Typography>
              {sessionId && (
                <Chip
                  size="small"
                  icon={sessionMode === 'council' ? <GavelIcon fontSize="small" /> : <ChatIcon fontSize="small" />}
                  label={sessionMode === 'council' ? 'Council Mode' : 'Chat Mode'}
                  color={sessionMode === 'council' ? 'warning' : 'default'}
                  variant={sessionMode === 'council' ? 'filled' : 'outlined'}
                />
              )}
            </Stack>
            {!!sessionMembers.length && (
              <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 0.5, mt: 0.5 }}>
                {sessionMembers.map((m) => (
                  <Chip key={m} size="small" label={m} />
                ))}
              </Box>
            )}
            {!!sessionDescription && (
              <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mt: 0.5 }}>{sessionDescription}</Typography>
            )}
          </Box>
          {sessionId && (
            <Stack direction="row" spacing={0.5}>
              {sessionMode === 'chat' && (
                <Tooltip title={sessionMembers.length < 2 ? 'Add at least 2 agents to start deliberation' : 'Start Council Deliberation'}>
                  <span>
                    <IconButton size="small" color="warning" onClick={() => setEscalateOpen(true)} disabled={sessionMembers.length < 2}>
                      <GavelIcon fontSize="small" />
                    </IconButton>
                  </span>
                </Tooltip>
              )}
              {sessionMode === 'council' && (
                <Tooltip title="Return to Chat">
                  <IconButton size="small" color="primary" onClick={handleReturnToChat} disabled={councilLoading}>
                    <ChatIcon fontSize="small" />
                  </IconButton>
                </Tooltip>
              )}
              <Tooltip title={sessionMode === 'council' ? 'Return to chat mode to rename' : 'Rename Council'}>
                <span><IconButton size="small" disabled={sessionMode === 'council'} onClick={() => { setRenameTitle(sessionTitle || ''); setRenameDesc(sessionDescription || ''); setRenameOpen(true); }}><EditIcon fontSize="small" /></IconButton></span>
              </Tooltip>
              <Tooltip title={sessionMode === 'council' ? 'Return to chat mode to edit members' : 'Edit Members'}>
                <span><IconButton size="small" disabled={sessionMode === 'council'} onClick={() => { setEditMembers(sessionMembers.length ? sessionMembers : selected); setEditOpen(true); }}><GroupIcon fontSize="small" /></IconButton></span>
              </Tooltip>
              <Tooltip title={sessionMode === 'council' ? 'Return to chat mode to delete' : 'Delete'}>
                <span><IconButton size="small" color="error" disabled={sessionMode === 'council'} onClick={async () => { if (!sessionId) return; try { await councilSessionDelete(sessionId); await sessions.refetch(); setSessionId(null); setSessionTitle(''); setSessionMembers([]); setSelected([]); setTurns([]); } catch {} }}><DeleteOutlineIcon fontSize="small" /></IconButton></span>
              </Tooltip>
            </Stack>
          )}
        </Stack>

        {/* Council Run Status Panel */}
        {sessionMode === 'council' && councilRun && (
          <Paper variant="outlined" sx={{ p: 2, mb: 1, bgcolor: alpha(theme.palette.warning.main, 0.08) }}>
            <Stack direction="row" alignItems="center" spacing={1} sx={{ mb: 1 }}>
              <GavelIcon color="warning" />
              <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>Council Deliberation</Typography>
              <Chip
                size="small"
                label={councilRun.status}
                color={
                  councilRun.status === 'completed' ? 'success' :
                  councilRun.status === 'vetoed' ? 'error' :
                  councilRun.status === 'running' ? 'primary' :
                  councilRun.status === 'error' ? 'error' : 'default'
                }
                icon={
                  councilRun.status === 'completed' ? <CheckCircleIcon fontSize="small" /> :
                  councilRun.status === 'vetoed' ? <BlockIcon fontSize="small" /> :
                  councilRun.status === 'error' ? <ErrorIcon fontSize="small" /> : undefined
                }
              />
            </Stack>
            {/* Progress Stepper showing phases */}
            {councilRun.status === 'running' && (
              <Box sx={{ mb: 2 }}>
                <Stepper
                  activeStep={
                    councilRun.phase === 'init' ? 0 :
                    councilRun.phase === 'positions' ? 1 :
                    councilRun.phase === 'debate' ? 2 :
                    councilRun.phase === 'synthesis' ? 3 : 0
                  }
                  alternativeLabel
                  sx={{ '& .MuiStepLabel-label': { fontSize: 11 } }}
                >
                  <Step><StepLabel>Initialize</StepLabel></Step>
                  <Step><StepLabel>Gather Positions</StepLabel></Step>
                  <Step><StepLabel>Debate</StepLabel></Step>
                  <Step><StepLabel>Synthesize</StepLabel></Step>
                </Stepper>
                <Typography variant="caption" color="text.secondary" sx={{ display: 'block', textAlign: 'center', mt: 1 }}>
                  {councilRun.phase === 'init' && 'Initializing council session...'}
                  {councilRun.phase === 'positions' && 'Each role is analyzing and forming their position...'}
                  {councilRun.phase === 'debate' && 'Roles are debating and challenging each other...'}
                  {councilRun.phase === 'synthesis' && 'Moderator is synthesizing final recommendation...'}
                </Typography>
              </Box>
            )}
            {councilLoading && <LinearProgress sx={{ mb: 1 }} />}
            {councilRun.query && (
              <Typography variant="body2" sx={{ mb: 1 }}>
                <strong>Query:</strong> {councilRun.query}
              </Typography>
            )}
            {councilRun.veto && (
              <Alert severity="error" sx={{ mb: 1 }}>
                <strong>VETOED:</strong> {councilRun.veto_reason || 'Safety/Ethics veto exercised'}
              </Alert>
            )}
            {councilRun.status === 'error' && (
              <Alert severity="error" sx={{ mb: 1 }}>
                <strong>Error:</strong> {(councilRun as any).error_message || (councilRun as any).error || 'An error occurred during council deliberation. One or more agents may have failed to respond.'}
              </Alert>
            )}
            {councilRun.synthesis && (
              <Accordion>
                <AccordionSummary expandIcon={<ExpandMoreIcon />}>
                  <Typography variant="subtitle2">Final Synthesis</Typography>
                </AccordionSummary>
                <AccordionDetails>
                  <Typography variant="body2" sx={{ whiteSpace: 'pre-wrap' }}>
                    {typeof councilRun.synthesis === 'string'
                      ? councilRun.synthesis
                      : councilRun.synthesis.summary || councilRun.synthesis.final_recommendation || JSON.stringify(councilRun.synthesis, null, 2)}
                  </Typography>
                  {councilRun.synthesis.next_steps && (
                    <Box sx={{ mt: 1 }}>
                      <Typography variant="caption" sx={{ fontWeight: 600 }}>Next Steps:</Typography>
                      <ul style={{ margin: 0, paddingLeft: 20 }}>
                        {(councilRun.synthesis.next_steps as string[]).map((step, i) => (
                          <li key={i}><Typography variant="caption">{step}</Typography></li>
                        ))}
                      </ul>
                    </Box>
                  )}
                </AccordionDetails>
              </Accordion>
            )}
            {councilRun.positions && Object.keys(councilRun.positions).length > 0 && (
              <Accordion>
                <AccordionSummary expandIcon={<ExpandMoreIcon />}>
                  <Typography variant="subtitle2">Role Positions ({Object.keys(councilRun.positions).length})</Typography>
                </AccordionSummary>
                <AccordionDetails sx={{ p: 1 }}>
                  <Stack spacing={0.5}>
                    {Object.entries(councilRun.positions).map(([role, position]) => {
                      const pos = position as any;
                      const roleIcons: Record<string, string> = { analyst: '📊', skeptic: '🔍', pragmatist: '⚙️', safety: '🛡️', moderator: '⚖️' };
                      const icon = roleIcons[role] || '👤';
                      // Extract key info based on role
                      let summary = '';
                      if (pos.recommendation) summary = pos.recommendation;
                      else if (pos.overall_concern_level) summary = `Concern: ${pos.overall_concern_level}`;
                      else if (pos.recommended_path) summary = pos.recommended_path;
                      else if (pos.veto === true) summary = '⛔ VETO';
                      else if (pos.veto === false) summary = '✓ No concerns';
                      else if (pos.reasoning) summary = pos.reasoning.substring(0, 80) + (pos.reasoning.length > 80 ? '...' : '');
                      else if (typeof position === 'string') summary = (position as string).substring(0, 80);

                      return (
                        <Accordion key={role} disableGutters sx={{ '&:before': { display: 'none' }, boxShadow: 'none', bgcolor: alpha(theme.palette.background.default, 0.3) }}>
                          <AccordionSummary expandIcon={<ExpandMoreIcon sx={{ fontSize: 16 }} />} sx={{ minHeight: 32, '& .MuiAccordionSummary-content': { my: 0.5 } }}>
                            <Stack direction="row" spacing={1} alignItems="center" sx={{ width: '100%' }}>
                              <Typography sx={{ fontSize: 14 }}>{icon}</Typography>
                              <Typography variant="caption" sx={{ fontWeight: 600, textTransform: 'capitalize', minWidth: 70 }}>{role}</Typography>
                              <Typography variant="caption" color="text.secondary" sx={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                                {summary}
                              </Typography>
                            </Stack>
                          </AccordionSummary>
                          <AccordionDetails sx={{ pt: 0, pb: 1, px: 1 }}>
                            <Box sx={{ maxHeight: 150, overflow: 'auto', fontSize: 10 }}>
                              {pos.options && (
                                <Box sx={{ mb: 0.5 }}>
                                  <Typography variant="caption" sx={{ fontWeight: 600 }}>Options:</Typography>
                                  {pos.options.map((opt: any, i: number) => (
                                    <Typography key={i} variant="caption" sx={{ display: 'block', pl: 1 }}>• {opt.name || opt}</Typography>
                                  ))}
                                </Box>
                              )}
                              {pos.risks && (
                                <Box sx={{ mb: 0.5 }}>
                                  <Typography variant="caption" sx={{ fontWeight: 600 }}>Risks:</Typography>
                                  {pos.risks.slice(0, 3).map((r: any, i: number) => (
                                    <Typography key={i} variant="caption" sx={{ display: 'block', pl: 1 }}>• {r.risk || r} ({r.severity || 'unknown'})</Typography>
                                  ))}
                                </Box>
                              )}
                              {pos.quick_wins && (
                                <Box sx={{ mb: 0.5 }}>
                                  <Typography variant="caption" sx={{ fontWeight: 600 }}>Quick wins:</Typography>
                                  {pos.quick_wins.slice(0, 3).map((w: string, i: number) => (
                                    <Typography key={i} variant="caption" sx={{ display: 'block', pl: 1 }}>• {w}</Typography>
                                  ))}
                                </Box>
                              )}
                              {pos.safety_concerns && pos.safety_concerns.length > 0 && (
                                <Box sx={{ mb: 0.5 }}>
                                  <Typography variant="caption" sx={{ fontWeight: 600 }}>Safety:</Typography>
                                  {pos.safety_concerns.map((c: any, i: number) => (
                                    <Typography key={i} variant="caption" sx={{ display: 'block', pl: 1 }}>• {c.concern || c}</Typography>
                                  ))}
                                </Box>
                              )}
                              {pos.reasoning && (
                                <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mt: 0.5, fontStyle: 'italic' }}>
                                  {pos.reasoning}
                                </Typography>
                              )}
                            </Box>
                          </AccordionDetails>
                        </Accordion>
                      );
                    })}
                  </Stack>
                </AccordionDetails>
              </Accordion>
            )}
            {councilRun.status === 'pending' && (
              <Stack direction="row" spacing={1} sx={{ mt: 1 }}>
                <Button
                  size="small"
                  variant="outlined"
                  startIcon={<ChatIcon />}
                  onClick={handleReturnToChat}
                  disabled={councilLoading}
                >
                  Cancel & Return to Chat
                </Button>
              </Stack>
            )}
          </Paper>
        )}

        <Box ref={chatRef} sx={{ flex: 1, minHeight: 200, overflowY: 'auto' }}>
        {turns.map((t, idx) => {
          const replies = t.replies.filter((r) => r.status !== 'running' && (r.text?.trim() || r.status === 'error'));
          // Day separator logic
          const thisTs = t.at || (replies[0]?.finishedAt || replies[0]?.at);
          const prevTurn = idx > 0 ? turns[idx - 1] : undefined;
          const prevReplies = prevTurn ? prevTurn.replies.filter((r) => r.status !== 'running' && (r.text?.trim() || r.status === 'error')) : [];
          const prevTs = prevTurn ? (prevTurn.at || (prevReplies[prevReplies.length - 1]?.finishedAt || prevReplies[prevReplies.length - 1]?.at)) : undefined;
          const showDate = (() => {
            if (!thisTs) return idx === 0;
            if (!prevTs) return idx === 0;
            const d1 = new Date(thisTs); const d0 = new Date(prevTs);
            return d1.getFullYear() !== d0.getFullYear() || d1.getMonth() !== d0.getMonth() || d1.getDate() !== d0.getDate();
          })();
          return (
            <Box key={t.id} sx={{ mb: 2 }}>
              {showDate && (
                <Box sx={{ display: 'flex', justifyContent: 'center', my: 1 }}>
                  <Chip size="small" label={dayLabel(thisTs) || 'Today'} />
                </Box>
              )}
              {/* Me (left) */}
              <Box sx={{ display: 'flex', justifyContent: 'flex-start', alignItems: 'flex-end', gap: 1, mb: 0.5 }}>
                <Chip size="small" label="You" sx={{
                  height: 24,
                  fontSize: 12,
                  bgcolor: theme.palette.primary.main,
                  color: theme.palette.getContrastText(theme.palette.primary.main)
                }} />
                <Box sx={{ maxWidth: '80%' }}>
                  <Paper elevation={0} sx={{ px: 1.25, py: 1, mt: 0.25, bgcolor: meBubbleBg, color: meBubbleFg, borderRadius: 2, borderTopLeftRadius: 4 }}>
                    <Typography sx={{ whiteSpace: 'pre-wrap' }}>{t.user}</Typography>
                  </Paper>
                  <Typography variant="caption" color="text.secondary" sx={{ ml: 0.5 }} title={t.at ? new Date(t.at).toLocaleString() : ''}>{formatRelative(t.at)}</Typography>
                </Box>
              </Box>
              {/* Others (right) grouped by consecutive agent */}
              {(() => {
                const groups: { agent: string; items: AgentReply[]; system?: boolean }[] = [];
                let i = 0;
                while (i < replies.length) {
                  const curr = replies[i];
                  const sys = /(joined|left) the (group|council)/i.test(curr.text || '');
                  if (sys) {
                    groups.push({ agent: curr.agent, items: [curr], system: true });
                    i += 1;
                    continue;
                  }
                  let j = i + 1;
                  while (j < replies.length) {
                    const nxt = replies[j];
                    const nxtSys = /(joined|left) the (group|council)/i.test(nxt.text || '');
                    if (nxtSys || nxt.agent !== curr.agent) break;
                    j += 1;
                  }
                  groups.push({ agent: curr.agent, items: replies.slice(i, j) });
                  i = j;
                }
                return groups.map((g, gi) => {
                  if (g.system) {
                    return g.items.map((r, si) => (
                      <Box key={`${t.id}-${g.agent}-sys-${gi}-${si}`} sx={{ display: 'flex', justifyContent: 'center', my: 0.5 }}>
                        <Chip size="small" label={`${g.agent} ${r.text}`} variant="outlined" />
                      </Box>
                    ));
                  }
                  const last = g.items[g.items.length - 1];
                  const bg = agentBubbleBg(g.agent, last.status);
                  const duration = last.durationMs ?? (last.finishedAt && last.startedAt ? last.finishedAt - last.startedAt : undefined);
                  const fmt = (ms?: number) => {
                    if (ms == null) return undefined;
                    if (ms < 1000) return `${ms}ms`;
                    if (ms < 60_000) return `${(ms / 1000).toFixed(1)}s`;
                    const m = Math.floor(ms / 60000);
                    const s = Math.floor((ms % 60000) / 1000);
                    return `${m}m ${s}s`;
                  };
                  return (
                    <Box key={`${t.id}-${g.agent}-grp-${gi}`} sx={{ display: 'flex', justifyContent: 'flex-end', alignItems: 'flex-end', gap: 1, mb: 0.75 }}>
                      <Box sx={{ maxWidth: '80%' }}>
                        <Stack spacing={0.5}>
                          {g.items.map((r, ri) => (
                            <Paper key={`${t.id}-${g.agent}-msg-${gi}-${ri}`} elevation={0} sx={{ px: 1.25, py: 1, mt: 0.25, bgcolor: bg, color: theme.palette.getContrastText(bg), borderRadius: 2, borderTopRightRadius: 4 }}>
                              <Typography sx={{ whiteSpace: 'pre-wrap' }}>{r.text}</Typography>
                            </Paper>
                          ))}
                        </Stack>
                        <Typography variant="caption" color="text.secondary" sx={{ mr: 0.5, display: 'block', textAlign: 'right' }} title={(last.finishedAt || last.at) ? new Date((last.finishedAt || last.at) as number).toLocaleString() : ''}>
                          {g.agent}{duration !== undefined ? ` • ${last.status} • ${fmt(duration)}` : ` • ${last.status}`} • {formatRelative(last.finishedAt || last.at)}
                        </Typography>
                      </Box>
                      <Chip size="small" label={g.agent} sx={{
                        height: 24,
                        fontSize: 12,
                        bgcolor: avatarColor(g.agent),
                        color: theme.palette.getContrastText(avatarColor(g.agent))
                      }} />
                    </Box>
                  );
                });
              })()}
              {idx === turns.length - 1 && t.replies.some((r) => r.status === 'running') && (
                <Typography variant="caption" color="text.secondary" sx={{ display: 'block', textAlign: 'center', mt: 0.5 }}>
                  Waiting for {t.replies.filter((r) => r.status === 'running').map((r) => r.agent).join(', ')}…
                </Typography>
              )}
            </Box>
          );
        })}
        {!turns.length && (
          <Typography variant="body2" color="text.secondary">No messages yet.</Typography>
        )}
        </Box>
        {/* Chat input under the transcript */}
        <Box>
          <TextField
            fullWidth
            multiline
            minRows={3}
            size="small"
            placeholder={selected.length ? `Message ${sessionTitle || 'council'}…` : 'Select one or more agents…'}
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault();
                if (!sending && input.trim() && selected.length > 0) handleSend();
              } else if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
                if (!sending && input.trim() && selected.length > 0) handleSend();
              }
            }}
          />
          <Stack direction="row" spacing={1} sx={{ mt: 1, justifyContent: 'flex-end' }}>
            {sending && <Typography variant="caption" color="text.secondary" sx={{ mr: 'auto' }}>Sending…</Typography>}
            <Button
              size="small"
              variant="contained"
              onClick={handleSend}
              disabled={sending || !input.trim() || selected.length === 0}
            >Send</Button>
          </Stack>
        </Box>
      </Paper>
      </Grid>

      {/* Edit Members Dialog */}
      <Dialog open={editOpen} onClose={() => setEditOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle>Edit Members</DialogTitle>
        <DialogContent>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 1 }}>Select agents to include in this council.</Typography>
          <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 1 }}>
            {available.map((name) => {
              const active = editMembers.includes(name);
              return (
                <Chip
                  key={name}
                  size="small"
                  label={name}
                  color={active ? 'primary' : 'default'}
                  variant={active ? 'filled' : 'outlined'}
                  onClick={() => setEditMembers((prev) => prev.includes(name) ? prev.filter((n) => n !== name) : [...prev, name])}
                  sx={{ cursor: 'pointer' }}
                />
              );
            })}
          </Box>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setEditOpen(false)}>Cancel</Button>
          <Button
            variant="contained"
            disabled={!sessionId}
            onClick={async () => {
              try {
                if (!sessionId) return;
                const before = new Set(sessionMembers.map((n) => normalizeAgentName(n)));
                const afterList = editMembers.map((n) => normalizeAgentName(n));
                const after = new Set(afterList);
                const added = afterList.filter((n) => !before.has(n));
                const removed = sessionMembers.filter((n) => !after.has(normalizeAgentName(n)));
                // Persist members to backend first
                try {
                  await councilSessionUpdate(sessionId, undefined, afterList);
                } catch {}
                // Emit join/leave chat events
                for (const a of added) {
                  try { await councilAppendAgent(sessionId, a, null, 'joined the council', 'ok'); } catch {}
                }
                for (const r of removed) {
                  try { await councilAppendAgent(sessionId, r, null, 'left the council', 'ok'); } catch {}
                }
                setSessionMembers(afterList);
                setSelected(afterList);
                // Refresh list + transcript so system messages appear immediately
                try { await sessions.refetch(); } catch {}
                try { await loadSession(sessionId); } catch {}
                setEditOpen(false);
              } catch { setEditOpen(false); }
            }}
          >Save</Button>
        </DialogActions>
      </Dialog>

      {/* Rename Dialog */}
      <Dialog open={renameOpen} onClose={() => setRenameOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle>Rename Council</DialogTitle>
        <DialogContent>
          <TextField autoFocus fullWidth label="Title" value={renameTitle} onChange={(e) => setRenameTitle(e.target.value)} sx={{ mt: 1, mb: 1 }} />
          <TextField fullWidth multiline minRows={3} label="Description" value={renameDesc} onChange={(e) => setRenameDesc(e.target.value)} />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setRenameOpen(false)}>Cancel</Button>
          <Button variant="contained" disabled={!sessionId} onClick={async () => {
            try {
              if (!sessionId) return;
              const prevTitle = sessionTitle || '';
              const prevDesc = sessionDescription || '';
              const updated = await councilSessionUpdate(sessionId, renameTitle || undefined, undefined, renameDesc || undefined);
              setSessionTitle(updated.title || renameTitle);
              setSessionDescription(renameDesc);
              // Announcements
              if ((renameTitle || '') !== prevTitle) {
                try { await councilAppendAgent(sessionId, 'System', null, `council renamed to "${renameTitle || updated.title || ''}"`, 'ok'); } catch {}
              }
              if ((renameDesc || '') !== prevDesc) {
                try { await councilAppendAgent(sessionId, 'System', null, 'council description updated', 'ok'); } catch {}
              }
              setRenameOpen(false);
            } catch { setRenameOpen(false); }
          }}>Save</Button>
        </DialogActions>
      </Dialog>

      {/* Start Council Dialog */}
      <Dialog open={escalateOpen} onClose={() => setEscalateOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle>
          <Stack direction="row" alignItems="center" spacing={1}>
            <GavelIcon color="warning" />
            <Typography variant="h6">Start Council Deliberation</Typography>
          </Stack>
        </DialogTitle>
        <DialogContent>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
            Starting a council deliberation will freeze the current conversation context and begin a formal deliberation
            with multiple AI roles (Analyst, Skeptic, Pragmatist, Safety/Ethics, Moderator).
          </Typography>
          <Alert severity="info" sx={{ mb: 2 }}>
            The council will analyze the conversation, gather positions from each role, conduct a structured debate,
            and provide a synthesized recommendation.
          </Alert>
          <TextField
            autoFocus
            fullWidth
            multiline
            minRows={3}
            label="Decision Query (optional)"
            placeholder="What specific question should the council deliberate on? If left empty, the council will infer from conversation."
            value={escalateQuery}
            onChange={(e) => setEscalateQuery(e.target.value)}
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setEscalateOpen(false)}>Cancel</Button>
          <Button
            variant="contained"
            color="warning"
            disabled={!sessionId || councilLoading}
            startIcon={councilLoading ? undefined : <GavelIcon />}
            onClick={handleStartCouncil}
          >
            {councilLoading ? 'Starting...' : 'Start Council'}
          </Button>
        </DialogActions>
      </Dialog>
    </Grid>
  );
}
