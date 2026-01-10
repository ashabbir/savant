import React, { useEffect, useMemo, useState, useRef, useCallback } from 'react';
import { agentRun, agentRunContinue, agentRunRead, useAgents, useCouncilSessions, councilSessionCreate, councilSessionGet, councilAppendUser, councilAppendAgent, councilSessionDelete, councilSessionClear, councilSessionUpdate, councilEscalate, councilRun as runCouncilApi, councilReturnToChat, councilRunGet, councilRunsList, CouncilRun, callEngineTool, useBlackboardReplay, BlackboardEvent } from '../../api';
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
import CloseIcon from '@mui/icons-material/Close';
import IosShareIcon from '@mui/icons-material/IosShare';
import ArticleIcon from '@mui/icons-material/Article';
import yaml from 'js-yaml';
import Viewer from '../../components/Viewer';
import DeleteSweepIcon from '@mui/icons-material/DeleteSweep';

type AgentSession = { lastRunId: number | null; running?: boolean };
type AgentReply = {
  agent: string;
  runId: number;
  runKey?: string;
  text: string;
  status: 'running' | 'ok' | 'error';
  startedAt?: number;
  finishedAt?: number;
  durationMs?: number;
  at?: number;
  eventId?: string;
};
type ChatTurn = { id: number; user: string; replies: AgentReply[]; at?: number; userEventId?: string };

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
  const [clearOpen, setClearOpen] = useState(false);
  // Search filter for sessions
  const [filter, setFilter] = useState('');
  // Last-open timestamps for unread indicators
  const [lastOpen, setLastOpen] = useState<Record<number, number>>(() => {
    try { return JSON.parse(localStorage.getItem(LS_LAST_OPEN) || '{}'); } catch { return {}; }
  });
  // Council protocol state
  const [sessionMode, setSessionMode] = useState<'chat' | 'council'>('chat');
  const [councilRun, setCouncilRun] = useState<CouncilRun | null>(null);
  const [lastCouncilRun, setLastCouncilRun] = useState<CouncilRun | null>(null);
  const [lastCouncilOpen, setLastCouncilOpen] = useState(false);
  const [councilLoading, setCouncilLoading] = useState(false);
  const [escalateOpen, setEscalateOpen] = useState(false);
  const [escalateQuery, setEscalateQuery] = useState('');
  const [exportOpen, setExportOpen] = useState(false);
  const [exportYaml, setExportYaml] = useState('');
  const [expandedPosition, setExpandedPosition] = useState<string | false>(false);
  const [expandedRunSection, setExpandedRunSection] = useState<'positions' | 'debate' | 'result' | false>('positions');
  const [expandedDebateRound, setExpandedDebateRound] = useState<number | false>(false);
  // Blackboard refresh: watch council events for this session
  const bbSessionId = useMemo(() => (sessionId ? `council-${sessionId}` : null), [sessionId]);
  const bbReplay = useBlackboardReplay(bbSessionId, { pollMs: 1500 });
  useEffect(() => {
    if (!sessionId) return;
    const events = bbReplay.data || [];
    const turnsFromBB = buildTurnsFromEvents(events);
    setTurns(turnsFromBB);
  }, [bbReplay.data, sessionId]);

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
      // Newest turn first
      const turnsDesc = [...history].reverse();
      turnsDesc.forEach((t) => {
        const userLine = (t.user || '').toString().trim();
        if (userLine) lines.push(`User: ${userLine}`);
        (t.replies || []).forEach((r) => {
          const who = (r.agent || '').toString();
          if (who.toLowerCase() === 'system') return; // drop system messages
          const bodyStr = toDisplayText(r.text).trim();
          if (r.status !== 'running' && (bodyStr || r.status === 'error')) {
            const body = bodyStr;
            if (body) lines.push(`${who}: ${body}`);
          }
        });
      });
      return lines.join('\n');
    } catch {
      return '';
    }
  }

  async function deleteChatEvent(eventId?: string, scope: 'single' | 'turn' = 'single') {
    try {
      if (!eventId || !sessionId) return;
      await callEngineTool('council', 'council_message_delete', { session_id: sessionId, event_id: eventId, scope });
      try { await bbReplay.refetch(); } catch {}
      try { await sessions.refetch(); } catch {}
    } catch (e: any) {
      try { console.error('delete message failed', e?.message || e); } catch {}
    }
  }

  // Safely convert arbitrary values to displayable text
  function toDisplayText(value: any): string {
    try {
      if (value == null) return '';
      if (typeof value === 'string') return value;
      if (typeof value === 'object') {
        try { return JSON.stringify(value, null, 2); } catch { /* fallthrough */ }
      }
      return String(value);
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

  // Build chat turns from Blackboard replay events
  function buildTurnsFromEvents(events: BlackboardEvent[]): ChatTurn[] {
    try {
      const sorted = [...(events || [])].sort((a: any, b: any) => {
        const ta = a.created_at ? Date.parse(a.created_at as any) : 0;
        const tb = b.created_at ? Date.parse(b.created_at as any) : 0;
        return ta - tb;
      });
      const out: ChatTurn[] = [];
      let cur: ChatTurn | null = null;
      let replyIndexByAgent: Record<string, number> = {};
      for (const ev of sorted) {
        const t = (ev.type || '').toString();
        const p: any = (ev as any).payload || {};
        if (t === 'session_created') continue;
        if (t === 'message_posted') {
          if (cur) out.push(cur);
          cur = {
            id: Date.parse((ev.created_at as any) || String(Date.now())),
            user: toDisplayText((p && p.text) || ''),
            replies: [],
            at: ev.created_at ? Date.parse(ev.created_at as any) : undefined,
            userEventId: (ev as any).event_id || undefined,
          };
          replyIndexByAgent = {};
        } else if (t === 'agent_reply') {
          if (!cur) { cur = { id: Date.now(), user: '', replies: [] }; replyIndexByAgent = {}; }
          const agent = (((ev as any).actor_id as any) || 'agent').toString();
          if (agent.toLowerCase() === 'system') continue; // drop system replies from chat turns
          const idx = replyIndexByAgent[agent] ?? -1;
          const text = toDisplayText((p && p.text) || '');
          const status = ((p && p.status || '').toString().toLowerCase() === 'error') ? 'error' as const : 'ok' as const;
          const base = { agent, runId: (p && p.run_id) || 0, text, status, at: ev.created_at ? Date.parse(ev.created_at as any) : undefined, eventId: (ev as any).event_id || undefined };
          if (idx >= 0) {
            cur.replies[idx] = { ...cur.replies[idx], ...base };
          } else {
            cur.replies.push(base);
            replyIndexByAgent[agent] = cur.replies.length - 1;
          }
        } else if (t === 'result_emitted') {
          if (!cur) { cur = { id: Date.now(), user: '', replies: [] }; replyIndexByAgent = {}; }
          const agent = (((ev as any).actor_id as any) || 'agent').toString();
          if (agent.toLowerCase() === 'system') continue; // drop system 
          const idx = replyIndexByAgent[agent] ?? -1;
          const text = toDisplayText((p && p.text) || '');
          if (text) {
            const base = { agent, runId: (p && p.run_id) || 0, text, status: 'ok' as const, at: ev.created_at ? Date.parse(ev.created_at as any) : undefined, eventId: (ev as any).event_id || undefined };
            if (idx >= 0) {
              cur.replies[idx] = { ...cur.replies[idx], ...base };
            } else {
              cur.replies.push(base);
              replyIndexByAgent[agent] = cur.replies.length - 1;
            }
          }
        } else if (t === 'reasoning_job_error') {
          if (!cur) { cur = { id: Date.now(), user: '', replies: [] }; replyIndexByAgent = {}; }
          const agent = ((ev as any).actor_id as any) || 'agent';
          const idx = replyIndexByAgent[agent] ?? -1;
          const text = toDisplayText((p && p.error) || 'error');
          const base = { agent, runId: (p && p.run_id) || 0, text, status: 'error' as const, at: ev.created_at ? Date.parse(ev.created_at as any) : undefined, eventId: (ev as any).event_id || undefined };
          if (idx >= 0) {
            cur.replies[idx] = { ...cur.replies[idx], ...base };
          } else {
            cur.replies.push(base);
            replyIndexByAgent[agent] = cur.replies.length - 1;
          }
        }
      }
      if (cur) out.push(cur);
      return out;
    } catch {
      return [];
    }
  }

  // Build a YAML export for debugging with keys: council, chat, agents
  function buildYamlExport(runs?: any[], runsByAgent?: Record<string, { run_id: number; steps: any[] }[]>, agentDefs?: Record<string, any>): string {
    try {
      const members = (sessionMembers && sessionMembers.length ? sessionMembers : selected) || [];

      // Latest interaction summarized like AgentRun chat export
      const lastTurn = turns.length ? turns[turns.length - 1] : null;
      const latestInteraction = lastTurn ? {
        user_message: lastTurn.user || '',
        at: lastTurn.at ? new Date(lastTurn.at).toISOString() : undefined,
        responses: lastTurn.replies.filter((r) => (r.agent || '').toLowerCase() !== 'system').map((r) => ({
          agent: r.agent,
          status: r.status,
          text: (r.text ?? '').toString(),
          at: r.at ? new Date(r.at).toISOString() : undefined,
          duration_ms: r.durationMs ?? undefined,
          run_id: r.runId ?? undefined,
          run_key: r.runKey ?? undefined,
        }))
      } : null;

      // Full transcript structure
      const transcript = turns.map((t, idx) => ({
        index: idx + 1,
        user: { text: t.user || '', at: t.at ? new Date(t.at).toISOString() : undefined },
        responses: t.replies.filter((r) => (r.agent || '').toLowerCase() !== 'system').map((r) => ({
          agent: r.agent,
          status: r.status,
          text: (r.text ?? '').toString(),
          at: r.at ? new Date(r.at).toISOString() : undefined,
          duration_ms: r.durationMs ?? undefined,
          run_id: r.runId ?? undefined,
          run_key: r.runKey ?? undefined,
        }))
      }));

      // Map council protocol into AgentRun-like fields
      const councilLike = councilRun ? (() => {
        const run: any = councilRun as any;
        const run_info: any = {
          run_id: run.run_id,
          status: run.status,
          phase: run.phase,
          query: run.query,
          veto: run.veto,
          veto_reason: run.veto_reason,
          started_at: run.started_at,
          completed_at: run.completed_at,
        };
        const steps: any[] = [];
        const positionsArr = Array.isArray(run.positions)
          ? run.positions
          : Object.entries(run.positions || {}).map(([role, position]) => ({ agent: role, position }));
        positionsArr.forEach((p: any, i: number) => {
          steps.push({ index: i + 1, phase: 'positions', role: p.agent || p.role || p.name || 'agent', position: p.position || p.text || p.summary || p });
        });
        if (Array.isArray(run.debate_rounds)) {
          run.debate_rounds.forEach((round: any, ri: number) => {
            const items = Array.isArray(round) ? round : (round?.items || []);
            items.forEach((d: any) => {
              steps.push({ index: steps.length + 1, phase: `debate:${ri + 1}`, role: d.agent || d.role || d.name || 'agent', argument: d.text || d.argument || d });
            });
          });
        }
        if (run.synthesis) {
          steps.push({ index: steps.length + 1, phase: 'synthesis', moderator: (run.synthesis.role || 'moderator'), summary: run.synthesis.summary || run.synthesis });
        }
        return { run_info, run_steps: { steps }, raw: { positions: run.positions, debate_rounds: run.debate_rounds, synthesis: run.synthesis } };
      })() : null;

      // Build agents list with their messages and per-agent steps (from council)
      const byAgentMessages: Record<string, any[]> = {};
      transcript.forEach((turn) => {
        (turn.responses || []).filter((r: any) => (r.agent || '').toString().toLowerCase() !== 'system').forEach((r: any) => {
          const key = r.agent || 'unknown';
          (byAgentMessages[key] = byAgentMessages[key] || []).push({
            text: r.text,
            at: r.at,
            status: r.status,
            run_id: r.run_id,
            run_key: r.run_key,
            duration_ms: r.duration_ms,
          });
        });
      });
      // Build per-agent steps across each council run
      // Start with optional caller-provided runsByAgent (from agentRunRead)
      const perAgentRuns: Record<string, { run_id: string | number | undefined; steps: any[] }[]> = runsByAgent ? { ...runsByAgent } : {};
      const runList: any[] = Array.isArray(runs) && runs.length ? runs : (councilRun ? [councilRun as any] : []);
      runList.forEach((runAny: any) => {
        const runId = runAny.run_id || runAny.id;
        const steps: any[] = [];
        const positions = Array.isArray(runAny.positions)
          ? runAny.positions
          : Object.entries(runAny.positions || {}).map(([role, position]) => ({ agent: role, position }));
        const debate = runAny.debate_rounds || [];
        const synthesis = runAny.synthesis || null;
        positions.forEach((p: any) => {
          steps.push({ index: steps.length + 1, phase: 'positions', role: p.agent || p.role || p.name || 'agent', position: p.position || p.text || p.summary || p });
        });
        if (Array.isArray(debate)) {
          debate.forEach((round: any, ri: number) => {
            const items = Array.isArray(round) ? round : (round?.items || []);
            items.forEach((d: any) => {
              steps.push({ index: steps.length + 1, phase: `debate:${ri + 1}`, role: d.agent || d.role || d.name || 'agent', argument: d.text || d.argument || d });
            });
          });
        }
        if (synthesis) {
          steps.push({ index: steps.length + 1, phase: 'synthesis', moderator: (synthesis.role || 'moderator'), summary: synthesis.summary || synthesis });
        }
        // Distribute steps to each role as agent bucket
        steps.forEach((s) => {
          const key = s.role || s.moderator || 'unknown';
          (perAgentRuns[key] = perAgentRuns[key] || []).push({ run_id: runId, steps: [s] });
        });
      });

      // Merge steps per run for each agent (so each run_id groups its steps)
      Object.keys(perAgentRuns).forEach((agent) => {
        const byRun: Record<string, any[]> = {};
        (perAgentRuns[agent] || []).forEach((entry) => {
          const k = String(entry.run_id ?? '');
          (byRun[k] = byRun[k] || []).push(...entry.steps);
        });
        perAgentRuns[agent] = Object.keys(byRun).map((k) => {
          const numeric = Number(k);
          const rid = Number.isFinite(numeric) ? numeric : (k === '' ? undefined : k);
          return { run_id: rid, steps: byRun[k] };
        });
      });

      const agentsArr = members.map((name) => ({
        name,
        definition: agentDefs && agentDefs[name] ? agentDefs[name] : null,
        messages: byAgentMessages[name] || [],
        runs: perAgentRuns[name] || [],
      }));

      // Final payload with the requested top-level keys
      const payload: any = {
        council: {
          group_name: sessionTitle || (sessionId ? `Session #${sessionId}` : 'council'),
          description: sessionDescription || undefined,
          mode: sessionMode,
          run_info: councilLike?.run_info || { mode: sessionMode },
          run_steps: councilLike?.run_steps || { steps: [] },
        },
        chat: transcript,
        agents: agentsArr,
      };

      return yaml.dump(payload, { lineWidth: 120, noRefs: true, skipInvalid: true });
    } catch (e) {
      try { return String(e); } catch { return 'export error'; }
    }
  }

  async function triggerYamlExport() {
    try {
      let runs: any[] | undefined = undefined;
      let runsByAgent: Record<string, { run_id: number; steps: any[] }[]> | undefined = undefined;
      let agentDefs: Record<string, any> | undefined = undefined;
      const members = (sessionMembers && sessionMembers.length ? sessionMembers : selected) || [];
      if (sessionId) {
        try {
          const res = await councilRunsList(sessionId, 50);
          runs = ((res as any).runs || []) as any[];
        } catch { /* ignore */ }
      }
      // Collect agent definitions
      try {
        const defs = await Promise.all(members.map(async (agent) => {
          try {
            const res = await callEngineTool('agents', 'agents_read', { name: agent });
            const text = res?.agent_yaml || '';
            const obj = yaml.load(text) || {};
            return { agent, def: obj };
          } catch {
            return { agent, def: null };
          }
        }));
        agentDefs = {};
        defs.forEach(({ agent, def }) => {
          agentDefs![agent] = def;
        });
      } catch { /* ignore */ }

      // Collect agent run transcripts for each reply to fill per-agent runs
      try {
        const pairs: { agent: string; runId: number }[] = [];
        const seen = new Set<string>();
        (turns || []).forEach((t) => {
          (t.replies || []).forEach((r) => {
            const a = r.agent || '';
            const rid = r.runId;
            if (!a || !rid) return;
            const key = `${a}::${rid}`;
            if (seen.has(key)) return;
            seen.add(key);
            pairs.push({ agent: a, runId: rid });
          });
        });
        const fetched = await Promise.all(pairs.map(async ({ agent, runId }) => {
          try {
            const d = await agentRunRead(agent, runId);
            const t = (d && d.transcript) || null;
            const obj = typeof t === 'string' ? (JSON.parse(t)) : t;
            const steps = Array.isArray(obj?.steps) ? obj.steps : [];
            const errors = Array.isArray(obj?.errors) ? obj.errors : [];
            const summaries = Array.isArray(obj?.summaries) ? obj.summaries : [];
            return { agent, runId, steps, status: d?.status, duration_ms: d?.duration_ms, errors, summaries };
          } catch {
            return { agent, runId, steps: [], errors: [], summaries: [] };
          }
        }));
        runsByAgent = {};
        fetched.forEach(({ agent, runId, steps, status, duration_ms, errors, summaries }) => {
          (runsByAgent![agent] = runsByAgent![agent] || []).push({ run_id: runId, status, duration_ms, steps, errors, summaries });
        });
      } catch { /* ignore */ }
      const y = buildYamlExport(runs, runsByAgent, agentDefs);
      setExportYaml(y);
      setExportOpen(true);
    } catch {
      const y = buildYamlExport();
      setExportYaml(y);
      setExportOpen(true);
    }
  }

  function downloadYaml() {
    try {
      const blob = new Blob([exportYaml], { type: 'text/yaml;charset=utf-8' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      const base = (sessionTitle?.trim() || (sessionId ? `council-${sessionId}` : 'council')) as string;
      a.href = url;
      a.download = `${base.replace(/\s+/g, '-').toLowerCase()}-debug.yaml`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
    } catch { /* ignore */ }
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
        const run = (data as any).council_run || null;
        setCouncilRun(run);
        setLastCouncilRun(run);
      } catch {
        setSessionMode('chat');
        setCouncilRun(null);
        setLastCouncilRun(null);
      }
      // Chat now renders from Blackboard replay; no need to set turns from DB messages
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
    // Send only the latest user message; server will append filtered conversation history
    const messageWithHistory = text;
    // Resolve a session id reliably (avoid state race)
    let localSid = sessionId;
    try {
      if (!localSid) { const created = await councilSessionCreate(undefined, selected); localSid = created.id; setSessionId(localSid); }
      if (localSid) await councilAppendUser(localSid, text);
    } catch {}

    // Use the resolved localSid (fallback to state if needed)
    const sess = localSid || sessionId;
    await Promise.all(selected.map(async (agentRaw) => {
      const agent = normalizeAgentName(agentRaw);
      try {
        if (sess) {
          await callEngineTool('council', 'council_agent_step', { session_id: sess, goal_text: messageWithHistory, agent_name: agent });
        }
      } catch (e: any) {
        try { console.error('council_agent_step failed', { agent, session_id: sess, error: e?.message || String(e) }); } catch {}
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
        const text = extractAgentReplyText(d);
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

  // Extract a useful reply string from run_read payload
  function extractAgentReplyText(d: any): string {
    try {
      const sum = toDisplayText(d?.output_summary).trim();
      // We'll attempt to compose an explanation + final if available
      let finalOut = '';
      if (sum) finalOut = sum;
      const t = d?.transcript;
      if (!t) return finalOut;
      if (typeof t === 'string') return t;
      // steps: find last action.final
      const steps = (t?.steps ?? []) as any[];
      let explanation = '';
      if (Array.isArray(steps) && steps.length) {
        // Walk forward to capture early explanations, and backward for final
        for (let i = 0; i < steps.length; i++) {
          const s = steps[i] || {};
          const a = s.action || s['action'] || {};
          const actionType = (a.action || a['action'] || '').toString().toLowerCase();
          const rsn = toDisplayText(a.reasoning ?? a['reasoning'] ?? s.reasoning ?? s['reasoning']).trim();
          if (actionType === 'reason' && rsn) explanation = rsn; // keep latest explanation
        }
        for (let i = steps.length - 1; i >= 0; i--) {
          const s = steps[i] || {};
          const a = s.action || s['action'] || {};
          const f = a.final ?? a['final'] ?? s.final ?? s['final'];
          const out = toDisplayText(f).trim();
          if (out) { finalOut = out; break; }
          const txt = a.text ?? a['text'] ?? s.text ?? s['text'];
          const out2 = toDisplayText(txt).trim();
          if (out2) { finalOut = out2; break; }
        }
      }
      if (explanation && finalOut && explanation !== finalOut) return `${explanation}\n\n${finalOut}`;
      if (finalOut) return finalOut;
      if (explanation) return explanation;
      // messages array: last assistant-like content
      const msgs = (t?.messages ?? t?.chat ?? []) as any[];
      if (Array.isArray(msgs) && msgs.length) {
        for (let i = msgs.length - 1; i >= 0; i--) {
          const m = msgs[i] || {};
          const role = (m.role || '').toString().toLowerCase();
          if (!role || role === 'assistant' || role === 'agent' || role === 'system') {
            const content = m.content ?? m.text ?? m.message ?? '';
            const out = toDisplayText(content).trim();
            if (out) return out;
          }
        }
      }
      return '';
    } catch { return ''; }
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
            setLastCouncilRun(run);
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
      const startRun = { ...escalateResult, status: 'running', phase: 'init', veto: false } as any;
      setCouncilRun(startRun);
      setLastCouncilRun(startRun);
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
      const finalRun = (sess as any).council_run || {
        ...result,
        status: result.status as any,
        synthesis: result.synthesis,
        positions: result.positions,
        debate_rounds: result.debate_rounds,
      } as any;
      setCouncilRun(finalRun);
      setLastCouncilRun(finalRun);
      if (finalRun && (finalRun.status === 'error' || finalRun.status === 'completed')) {
        setLastCouncilOpen(true);
      }
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
        const run = (sess as any).council_run || null;
        setCouncilRun(run);
        setLastCouncilRun(run);
        if (run && (run.status === 'error' || run.status === 'completed')) {
          setLastCouncilOpen(true);
        }
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
      const run = (sess as any).council_run || null;
      setLastCouncilRun(run);
      sessions.refetch();
      // Scroll to bottom
      setTimeout(() => chatRef.current?.scrollTo({ top: chatRef.current.scrollHeight, behavior: 'smooth' }), 100);
    } catch (e: any) {
      console.error('Return to chat failed:', e);
    } finally {
      setCouncilLoading(false);
    }
  }, [sessionId, sessions]);

  const reloadMessages = (_messages: any[]) => {
    // No-op: chat now renders from Blackboard replay events
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
    const sat = isDark ? 35 : 70;
    const light = 92;
    return `hsl(${hue} ${sat}% ${light}%)`;
  }

  const lightBubbleBg = '#f5f5f5';
  const lightBubbleFg = '#111111';
  const meBubbleBg = isDark ? lightBubbleBg : alpha(theme.palette.primary.main, 0.12);
  const meBubbleFg = isDark ? lightBubbleFg : theme.palette.text.primary;

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

  function sadTimeoutText(seed: string): string {
    const emojis = ['😞', '😔', '😢', '🥺', '🙁', '☹️', '😿'];
    const idx = hashString(seed) % emojis.length;
    return emojis[idx];
  }

  function replyDisplayText(reply: AgentReply): string {
    const raw = toDisplayText(reply.text || '').trim();
    if (reply.status === 'error' && raw && /timeout/i.test(raw)) {
      const seed = `${reply.agent}-${reply.runId}-${reply.at || reply.finishedAt || 0}`;
      return sadTimeoutText(seed);
    }
    if (raw && raw.startsWith('{') && raw.includes('"type"')) {
      try {
        const parsed = JSON.parse(raw);
        if (parsed && parsed.type === 'synthesis' && parsed.synthesis) {
          const synth = parsed.synthesis || {};
          const summary = synth.summary || synth.final_recommendation || synth.response || '';
          const text = summary ? String(summary).trim() : '';
          if (text) {
            const short = text.length > 220 ? `${text.slice(0, 220)}...` : text;
            return `Council completed - ${short}`;
          }
        }
      } catch {}
    }
    return raw || '(no summary)';
  }

  function isSynthesisMessage(reply: AgentReply): boolean {
    const raw = toDisplayText(reply.text || '').trim();
    if (!raw || !raw.startsWith('{') || !raw.includes('"type"')) return false;
    try {
      const parsed = JSON.parse(raw);
      return parsed && parsed.type === 'synthesis';
    } catch {
      return false;
    }
  }

  function renderCouncilRunResults(run: CouncilRun) {
    return (
      <>
        {run.positions && (Array.isArray(run.positions) ? run.positions.length : Object.keys(run.positions).length) > 0 && (
          <Accordion
            expanded={expandedRunSection === 'positions'}
            onChange={(_, isExpanded) => setExpandedRunSection(isExpanded ? 'positions' : false)}
          >
            <AccordionSummary expandIcon={<ExpandMoreIcon />}>
              <Typography variant="subtitle2">
                Positions ({Array.isArray(run.positions) ? run.positions.length : Object.keys(run.positions).length})
              </Typography>
            </AccordionSummary>
            <AccordionDetails sx={{ p: 1, maxHeight: 240, overflowY: 'auto' }}>
              <Stack spacing={0.5}>
                {(Array.isArray(run.positions)
                  ? run.positions
                  : Object.entries(run.positions).map(([agent, position]) => ({ agent, position }))
                ).map((entry: any) => {
                  const agentName = entry.agent || entry.role || entry.name || 'agent';
                  const pos = entry.position || entry;
                  const icon = '👤';
                  let summary = '';
                  if (pos.skipped) summary = `skipped (${pos.status || 'error'})`;
                  else if (pos.summary) summary = pos.summary;
                  else if (pos.response) summary = pos.response;
                  else if (pos.position) summary = pos.position;
                  else if (pos.reasoning) summary = pos.reasoning.substring(0, 80) + (pos.reasoning.length > 80 ? '...' : '');
                  else if (typeof pos === 'string') summary = pos.substring(0, 80);

                  const positionText = (() => {
                    if (pos && typeof pos === 'object') {
                      if (pos.skipped && typeof pos.error === 'string') return pos.error;
                      const v = pos.response ?? pos.summary ?? pos.position ?? pos.reasoning;
                      return typeof v === 'string' ? v : JSON.stringify(v ?? pos, null, 2);
                    }
                    return typeof pos === 'string' ? pos : JSON.stringify(pos, null, 2);
                  })();

                  return (
                    <Accordion
                      key={agentName}
                      expanded={expandedPosition === agentName}
                      onChange={(_, isExpanded) => setExpandedPosition(isExpanded ? agentName : false)}
                      disableGutters
                      sx={{ '&:before': { display: 'none' }, boxShadow: 'none', bgcolor: alpha(theme.palette.background.default, 0.3) }}
                    >
                      <AccordionSummary expandIcon={<ExpandMoreIcon sx={{ fontSize: 16 }} />} sx={{ minHeight: 32, '& .MuiAccordionSummary-content': { my: 0.5 } }}>
                        <Stack direction="row" spacing={1} alignItems="center" sx={{ width: '100%' }}>
                          <Typography sx={{ fontSize: 14 }}>{icon}</Typography>
                          <Typography variant="caption" sx={{ fontWeight: 600, flex: 1, whiteSpace: 'normal', wordBreak: 'break-word' }}>
                            Agent {agentName} — {summary || 'no position'}
                          </Typography>
                        </Stack>
                      </AccordionSummary>
                      <AccordionDetails sx={{ pt: 0, pb: 1, px: 1 }}>
                        <Box sx={{ maxHeight: 150, overflow: 'auto', fontSize: 10 }}>
                          <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mt: 0.5, whiteSpace: 'pre-wrap' }}>
                            {positionText}
                          </Typography>
                        </Box>
                      </AccordionDetails>
                    </Accordion>
                  );
                })}
              </Stack>
            </AccordionDetails>
          </Accordion>
        )}
        {Array.isArray(run.debate_rounds) && run.debate_rounds.length > 0 && (
          <Accordion
            expanded={expandedRunSection === 'debate'}
            onChange={(_, isExpanded) => setExpandedRunSection(isExpanded ? 'debate' : false)}
          >
            <AccordionSummary expandIcon={<ExpandMoreIcon />}>
              <Typography variant="subtitle2">Debate ({run.debate_rounds.length} rounds)</Typography>
            </AccordionSummary>
            <AccordionDetails sx={{ p: 1 }}>
              <Stack spacing={1}>
                {run.debate_rounds.map((round: any, idx: number) => {
                  const items = Array.isArray(round) ? round : (round?.items || []);
                  const roundLabel = round?.round || idx + 1;
                  const isOpen = expandedDebateRound === roundLabel;
                  return (
                    <Accordion
                      key={idx}
                      expanded={isOpen}
                      onChange={(_, isExpanded) => setExpandedDebateRound(isExpanded ? roundLabel : false)}
                      disableGutters
                      sx={{ '&:before': { display: 'none' }, boxShadow: 'none', bgcolor: alpha(theme.palette.background.default, 0.35) }}
                    >
                      <AccordionSummary expandIcon={<ExpandMoreIcon sx={{ fontSize: 16 }} />} sx={{ minHeight: 32 }}>
                        <Typography variant="caption" sx={{ fontWeight: 600 }}>
                          Round {roundLabel}
                        </Typography>
                      </AccordionSummary>
                      <AccordionDetails sx={{ pt: 0, pb: 1, px: 1 }}>
                        <Stack spacing={0.5}>
                          {items.map((item: any, i: number) => {
                            const who = item.agent || item.role || item.name || 'agent';
                            const val = item.text ?? item.argument;
                            const text = typeof val === 'string' ? val : JSON.stringify(val ?? item);
                            return (
                              <Box key={`${idx}-${i}`} sx={{ px: 0.5 }}>
                                <Typography variant="caption" sx={{ fontWeight: 600 }}>{who}:</Typography>{' '}
                                <Typography variant="caption" color="text.secondary" sx={{ whiteSpace: 'pre-wrap' }}>
                                  {text}
                                </Typography>
                              </Box>
                            );
                          })}
                          {!items.length && (
                            <Typography variant="caption" color="text.secondary">No debate items.</Typography>
                          )}
                        </Stack>
                      </AccordionDetails>
                    </Accordion>
                  );
                })}
              </Stack>
            </AccordionDetails>
          </Accordion>
        )}
        {run.synthesis && (
          <Accordion
            expanded={expandedRunSection === 'result'}
            onChange={(_, isExpanded) => setExpandedRunSection(isExpanded ? 'result' : false)}
          >
            <AccordionSummary expandIcon={<ExpandMoreIcon />}>
              <Typography variant="subtitle2">Result</Typography>
            </AccordionSummary>
            <AccordionDetails>
              <Typography variant="body2" sx={{ whiteSpace: 'pre-wrap' }}>
                {typeof run.synthesis === 'string'
                  ? run.synthesis
                  : run.synthesis.summary || run.synthesis.final_recommendation || JSON.stringify(run.synthesis, null, 2)}
              </Typography>
              {typeof run.synthesis !== 'string' && run.synthesis.note && (
                <Alert severity="warning" sx={{ mt: 1 }}>
                  {run.synthesis.note}
                </Alert>
              )}
              {typeof run.synthesis !== 'string' && Array.isArray((run.synthesis as any).skipped_roles) && (run.synthesis as any).skipped_roles.length > 0 && (
                <Alert severity="info" sx={{ mt: 1 }}>
                  Skipped roles: {(run.synthesis as any).skipped_roles.join(', ')}
                </Alert>
              )}
              {typeof run.synthesis !== 'string' && Array.isArray((run.synthesis as any).skipped_agents) && (run.synthesis as any).skipped_agents.length > 0 && (
                <Alert severity="info" sx={{ mt: 1 }}>
                  Skipped agents: {(run.synthesis as any).skipped_agents.join(', ')}
                </Alert>
              )}
              {run.synthesis.next_steps && (
                <Box sx={{ mt: 1 }}>
                  <Typography variant="caption" sx={{ fontWeight: 600 }}>Next Steps:</Typography>
                  <ul style={{ margin: 0, paddingLeft: 20 }}>
                    {(run.synthesis.next_steps as string[]).map((step, i) => (
                      <li key={i}><Typography variant="caption">{step}</Typography></li>
                    ))}
                  </ul>
                </Box>
              )}
            </AccordionDetails>
          </Accordion>
        )}
      </>
    );
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

  async function openCouncilRun(runKey?: string | null, at?: number) {
    if (runKey) {
      try {
        const run = await councilRunGet(String(runKey));
        if (run) {
          setLastCouncilRun(run);
          setLastCouncilOpen(true);
          return;
        }
      } catch {}
    }
    if (!sessionId) return;
    try {
      const res = await councilRunsList(sessionId, 50);
      const runs = (res as any).runs || [];
      if (!runs.length) return;
      if (!at) {
        setLastCouncilRun(runs[0]);
        setLastCouncilOpen(true);
        return;
      }
      const target = typeof at === 'number' ? at : Date.now();
      const sorted = runs
        .map((r: any) => ({ r, ts: Date.parse(r.started_at || r.completed_at || '') }))
        .filter((x: any) => Number.isFinite(x.ts))
        .sort((a: any, b: any) => Math.abs(a.ts - target) - Math.abs(b.ts - target));
      const best = sorted.length ? sorted[0].r : runs[0];
      setLastCouncilRun(best);
      setLastCouncilOpen(true);
    } catch {}
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
                          (() => {
                            const members = Array.isArray(s.agents) ? s.agents.length : 0;
                            const parts: string[] = [];
                            if (members > 0) parts.push(`${members} ${members === 1 ? 'member' : 'members'}`);
                            if (s.created_at) parts.push(`created ${formatRelative(s.created_at)}`);
                            if (s.last_at) parts.push(`last message ${formatRelative(s.last_at)}`);
                            if (!s.last_at && !s.updated_at) parts.push('no messages yet');
                            const metaLine = parts.join(' • ');

                            const rawDesc = ((s.description || '') as string).toString();
                            const descLine = rawDesc ? (rawDesc.length > 80 ? rawDesc.slice(0, 80) + ' ..' : rawDesc) : '';

                            return (
                              <>
                                {descLine && (
                                  <Typography variant="caption" color="text.secondary" sx={{ display: 'block', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                                    {descLine}
                                  </Typography>
                                )}
                                <Typography variant="caption" color="text.secondary" sx={{ display: 'block', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                                  {metaLine}
                                </Typography>
                              </>
                            );
                          })()
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

      {/* YAML Dialog matching Agent Run */}
      <Dialog open={exportOpen} onClose={() => setExportOpen(false)} maxWidth="md" fullWidth>
        <DialogTitle sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          YAML
          <Stack direction="row" spacing={1} alignItems="center">
            <IconButton
              size="small"
              onClick={async () => { try { await navigator.clipboard.writeText(exportYaml || ''); } catch {} }}
              disabled={!exportYaml}
            >
              <IosShareIcon fontSize="small" />
            </IconButton>
            <IconButton size="small" onClick={() => setExportOpen(false)}>
              <CloseIcon fontSize="small" />
            </IconButton>
          </Stack>
        </DialogTitle>
        <DialogContent dividers sx={{ p: 0 }}>
          <Viewer content={exportYaml || ''} language="yaml" height="70vh" yamlCollapsible />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setExportOpen(false)}>Close</Button>
        </DialogActions>
      </Dialog>

      {/* Right Panel: Transcript and controls */}
      <Grid xs={12} md={8}>
      <Paper variant="outlined" sx={{ p: 1.25, height: PANEL_HEIGHT, display: 'flex', flexDirection: 'column', gap: 0.75, overflow: 'hidden' }}>
        <Stack direction="row" alignItems="center" justifyContent="space-between" sx={{ mb: 0.25 }}>
          <Box>
            <Stack direction="row" alignItems="center" spacing={1}>
              <Tooltip title={sessionDescription || ''} disableHoverListener={!sessionDescription}>
                <Typography variant="subtitle1" sx={{ fontWeight: 600, lineHeight: 1 }}>
                  {sessionTitle || (sessionId ? `Session #${sessionId}` : 'Transcript')}
                </Typography>
              </Tooltip>
              {sessionId && (
                <Chip
                  size="small"
                  icon={sessionMode === 'council' ? <GavelIcon fontSize="small" /> : <ChatIcon fontSize="small" />}
                  label={sessionMode === 'council' ? 'Council' : 'Chat'}
                  color={sessionMode === 'council' ? 'warning' : 'default'}
                  variant={sessionMode === 'council' ? 'filled' : 'outlined'}
                />
              )}
              {!!sessionMembers.length && (
                <Tooltip title={sessionMembers.join(', ')}>
                  <Chip size="small" icon={<GroupIcon fontSize="small" />} label={`${sessionMembers.length} members`} variant="outlined" />
                </Tooltip>
              )}
            </Stack>
          </Box>
          {sessionId && (
            <Stack direction="row" spacing={0.5}>
              <Tooltip title="YAML">
                <span>
                  <Button size="small" startIcon={<ArticleIcon fontSize="small" />} onClick={triggerYamlExport}>YAML</Button>
                </span>
              </Tooltip>
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
              <Tooltip title={sessionMode === 'council' ? 'Return to chat mode to clear' : 'Clear chat history'}>
                <span><IconButton size="small" disabled={sessionMode === 'council'} onClick={() => setClearOpen(true)}><DeleteSweepIcon fontSize="small" /></IconButton></span>
              </Tooltip>
              <Tooltip title={sessionMode === 'council' ? 'Return to chat mode to delete' : 'Delete'}>
                <span><IconButton size="small" color="error" disabled={sessionMode === 'council'} onClick={async () => { if (!sessionId) return; try { await councilSessionDelete(sessionId); await sessions.refetch(); setSessionId(null); setSessionTitle(''); setSessionMembers([]); setSelected([]); setTurns([]); } catch {} }}><DeleteOutlineIcon fontSize="small" /></IconButton></span>
              </Tooltip>
            </Stack>
          )}
        </Stack>

        {/* Council Run Status Panel */}
        {sessionMode === 'council' && councilRun && (
          <Paper variant="outlined" sx={{ p: 1, mb: 1, bgcolor: alpha(theme.palette.warning.main, 0.06) }}>
            <Stack direction="row" alignItems="center" spacing={1} sx={{ mb: 0.5 }}>
              <GavelIcon color="warning" fontSize="small" />
              <Typography variant="subtitle2" sx={{ fontWeight: 600, fontSize: 13 }}>Council Deliberation</Typography>
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
            <Box sx={{ maxHeight: 320, overflowY: 'auto', pr: 1 }}>
              {councilRun.status === 'running' && (
                <Stack direction="row" spacing={0.5} alignItems="center" sx={{ flexWrap: 'wrap', gap: 0.5, mb: 0.5 }}>
                  {['Initialize', 'Positions', 'Debate', 'Synthesize'].map((label, idx) => {
                    const phaseIdx = councilRun.phase === 'init' ? 0 : councilRun.phase === 'positions' ? 1 : councilRun.phase === 'debate' ? 2 : councilRun.phase === 'synthesis' ? 3 : 0;
                    const selected = idx === phaseIdx;
                    return (
                      <Chip key={label} size="small" label={label} color={selected ? 'primary' : undefined} variant={selected ? 'filled' : 'outlined'} sx={{ height: 22 }} />
                    );
                  })}
                  <Typography variant="caption" color="text.secondary" sx={{ ml: 0.5 }}>
                    {councilRun.phase === 'init' && 'Initializing'}
                    {councilRun.phase === 'positions' && 'Gathering positions'}
                    {councilRun.phase === 'debate' && 'Debating'}
                    {councilRun.phase === 'synthesis' && 'Synthesizing'}
                  </Typography>
                </Stack>
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
                  <strong>Error:</strong>{' '}
                  {(() => {
                    const em: any = (councilRun as any).error_message;
                    const eobj: any = (councilRun as any).error;
                    const msg = em || eobj || 'An error occurred during council deliberation. One or more agents may have failed to respond.';
                    return typeof msg === 'string' ? msg : JSON.stringify(msg);
                  })()}
                </Alert>
              )}
              {renderCouncilRunResults(councilRun)}
              {(councilRun.status === 'pending' || councilRun.status === 'running') && (
                <Stack direction="row" spacing={1} sx={{ mt: 1 }}>
                  <Button
                    size="small"
                    variant="outlined"
                    startIcon={<ChatIcon />}
                    onClick={handleReturnToChat}
                    disabled={councilLoading}
                  >
                    Stop & Return to Chat
                  </Button>
                </Stack>
              )}
            </Box>
          </Paper>
        )}

        <Box ref={chatRef} sx={{ flex: 1, minHeight: 0, overflowY: 'auto' }}>
        {turns.map((t, idx) => {
          // include all non-running replies so status-only responses still show metadata
          const replies = t.replies.filter((r) => r.status !== 'running');
          // Day separator logic
          const thisTs = t.at || (replies[0]?.finishedAt || replies[0]?.at);
          const prevTurn = idx > 0 ? turns[idx - 1] : undefined;
          const prevReplies = prevTurn ? prevTurn.replies.filter((r) => r.status !== 'running') : [];
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
                  <Stack direction="row" spacing={0.5} alignItems="flex-start">
                    <Paper elevation={0} sx={{ px: 1.25, py: 1, mt: 0.25, bgcolor: meBubbleBg, color: meBubbleFg, borderRadius: 2, borderTopLeftRadius: 4 }}>
                      <Typography sx={{ whiteSpace: 'pre-wrap' }}>{t.user}</Typography>
                    </Paper>
                    {t.userEventId && (
                      <Tooltip title="Delete message">
                        <span>
                          <IconButton size="small" onClick={async () => {
                            const ok = window.confirm('Delete this message?');
                            if (!ok) return;
                            await deleteChatEvent(t.userEventId!, 'single');
                          }}>
                            <DeleteOutlineIcon fontSize="small" />
                          </IconButton>
                        </span>
                      </Tooltip>
                    )}
                  </Stack>
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
                  if (sys) { i += 1; continue; } // hide join/leave system messages
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
                  const last = g.items[g.items.length - 1];
                  const bg = agentBubbleBg(g.agent, last.status);
                  const bubbleFg = isDark ? lightBubbleFg : theme.palette.getContrastText(bg);
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
                          {g.items.map((r, ri) => {
                            const isSynthesis = isSynthesisMessage(r);
                            return (
                              <Stack key={`${t.id}-${g.agent}-msg-${gi}-${ri}`} direction="row" spacing={0.5} alignItems="flex-start">
                                <Paper
                                  elevation={0}
                                  onClick={isSynthesis ? () => openCouncilRun(r.runKey, r.at) : undefined}
                                  sx={{
                                    px: 1.25,
                                    py: 1,
                                    mt: 0.25,
                                    bgcolor: bg,
                                    color: bubbleFg,
                                    borderRadius: 2,
                                    borderTopRightRadius: 4,
                                    cursor: isSynthesis ? 'pointer' : 'default',
                                    boxShadow: isSynthesis ? '0 0 0 1px rgba(0,0,0,0.08) inset' : 'none',
                                    '&:hover': isSynthesis ? { filter: 'brightness(0.98)' } : undefined
                                  }}
                                >
                                  <Typography sx={{ whiteSpace: 'pre-wrap' }}>{replyDisplayText(r)}</Typography>
                                </Paper>
                                {r.eventId && (
                                  <Tooltip title="Delete message">
                                    <span>
                                      <IconButton size="small" onClick={async () => {
                                        const ok = window.confirm('Delete this message?');
                                        if (!ok) return;
                                        await deleteChatEvent(r.eventId!, 'single');
                                      }}>
                                        <DeleteOutlineIcon fontSize="small" />
                                      </IconButton>
                                    </span>
                                  </Tooltip>
                                )}
                              </Stack>
                            );
                          })}
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
            <Typography variant="caption" color="text.secondary">Enter to send • Shift+Enter for newline</Typography>
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

      <Dialog open={clearOpen} onClose={() => setClearOpen(false)} maxWidth="xs" fullWidth>
        <DialogTitle sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <Typography variant="subtitle1" sx={{ fontWeight: 600 }}>Clear Chat History</Typography>
          <IconButton size="small" onClick={() => setClearOpen(false)} aria-label="Close clear chat dialog">
            <CloseIcon fontSize="small" />
          </IconButton>
        </DialogTitle>
        <DialogContent>
          <Typography variant="body2" color="text.secondary">
            This removes all messages and council runs from this session. The council members and title stay the same.
          </Typography>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setClearOpen(false)}>Cancel</Button>
          <Button
            variant="contained"
            color="warning"
            onClick={async () => {
              if (!sessionId) return;
              try {
                await councilSessionClear(sessionId);
                setTurns([]);
                setCouncilRun(null);
                setLastCouncilRun(null);
                setSessionMode('chat');
                setLastCouncilOpen(false);
                setInput('');
                const now = Date.now();
                setLastOpen((prev) => {
                  const next = { ...prev, [sessionId]: now };
                  try { localStorage.setItem(LS_LAST_OPEN, JSON.stringify(next)); } catch {}
                  return next;
                });
                await sessions.refetch();
              } catch {}
              setClearOpen(false);
            }}
          >
            Clear
          </Button>
        </DialogActions>
      </Dialog>

      {lastCouncilRun && (
        <Dialog open={lastCouncilOpen} onClose={() => setLastCouncilOpen(false)} maxWidth="lg" fullWidth>
          <DialogTitle sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
            <Stack direction="row" spacing={1} alignItems="center">
              <GavelIcon color="warning" />
              <Typography variant="subtitle1" sx={{ fontWeight: 600 }}>Council Run Details</Typography>
            </Stack>
            <IconButton size="small" onClick={() => setLastCouncilOpen(false)} aria-label="Close council run dialog">
              <CloseIcon fontSize="small" />
            </IconButton>
          </DialogTitle>
          <DialogContent dividers>
            <Grid container spacing={2}>
              <Grid xs={12} md={4}>
                <Stack spacing={1.5}>
                  <Chip
                    size="small"
                    label={lastCouncilRun.status}
                    color={
                      lastCouncilRun.status === 'completed' ? 'success' :
                      lastCouncilRun.status === 'vetoed' ? 'error' :
                      lastCouncilRun.status === 'running' ? 'primary' :
                      lastCouncilRun.status === 'error' ? 'error' : 'default'
                    }
                  />
                  <Typography variant="caption" color="text.secondary">Run ID</Typography>
                  <Typography variant="body2" sx={{ fontFamily: 'monospace' }}>{lastCouncilRun.run_id}</Typography>
                  {lastCouncilRun.phase && (
                    <>
                      <Typography variant="caption" color="text.secondary">Phase</Typography>
                      <Typography variant="body2">{lastCouncilRun.phase}</Typography>
                    </>
                  )}
                  {lastCouncilRun.query && (
                    <>
                      <Typography variant="caption" color="text.secondary">Query</Typography>
                      <Typography variant="body2" sx={{ whiteSpace: 'pre-wrap' }}>{lastCouncilRun.query}</Typography>
                    </>
                  )}
                  {lastCouncilRun.error && (
                    <Alert severity="error">
                      <strong>Error:</strong>{' '}
                      {typeof (lastCouncilRun as any).error === 'string' ? (lastCouncilRun as any).error : JSON.stringify((lastCouncilRun as any).error)}
                    </Alert>
                  )}
                </Stack>
              </Grid>
              <Grid xs={12} md={8}>
                {renderCouncilRunResults(lastCouncilRun)}
              </Grid>
            </Grid>
          </DialogContent>
          <DialogActions>
            <Button onClick={() => setLastCouncilOpen(false)}>Close</Button>
          </DialogActions>
        </Dialog>
      )}

      {/* Start Council Dialog */}
      <Dialog open={escalateOpen} onClose={() => setEscalateOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle>
          <Stack direction="row" alignItems="center" spacing={1}>
            <GavelIcon color="warning" />
            <Typography variant="h6" component="span">Start Council Deliberation</Typography>
          </Stack>
        </DialogTitle>
        <DialogContent>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
            Starting a council deliberation will freeze the current conversation context and begin a formal deliberation
            with multiple agents.
          </Typography>
          <Alert severity="info" sx={{ mb: 2 }}>
            The council will analyze the conversation, gather positions from each agent, conduct a structured debate,
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
