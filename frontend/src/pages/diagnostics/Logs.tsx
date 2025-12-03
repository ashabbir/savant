import React, { useEffect, useRef, useState } from 'react';
import Box from '@mui/material/Box';
import Paper from '@mui/material/Paper';
import Typography from '@mui/material/Typography';
import Stack from '@mui/material/Stack';
import TextField from '@mui/material/TextField';
import Button from '@mui/material/Button';
import IconButton from '@mui/material/IconButton';
import Tooltip from '@mui/material/Tooltip';
import FormControl from '@mui/material/FormControl';
import InputLabel from '@mui/material/InputLabel';
import Select from '@mui/material/Select';
import MenuItem from '@mui/material/MenuItem';
import Chip from '@mui/material/Chip';
import PlayArrowIcon from '@mui/icons-material/PlayArrow';
import StopIcon from '@mui/icons-material/Stop';
import RefreshIcon from '@mui/icons-material/Refresh';
import DeleteIcon from '@mui/icons-material/Delete';
import ContentCopyIcon from '@mui/icons-material/ContentCopy';
import Snackbar from '@mui/material/Snackbar';
import { useHubInfo, getUserId, loadConfig } from '../../api';

const LOG_LEVELS = [
  { value: 'all', label: 'All levels' },
  { value: 'debug', label: 'Debug' },
  { value: 'info', label: 'Info' },
  { value: 'warn', label: 'Warn' },
  { value: 'error', label: 'Error' },
];

export default function DiagnosticsLogs() {
  const hub = useHubInfo();
  // Include 'hub' as first option for HTTP request logs, and 'events' for aggregated hub events
  const engines = [
    { name: 'events' },
    { name: 'hub' },
    ...(hub.data?.multiplexer ? [{ name: 'multiplexer' }] : []),
    ...(hub.data?.engines || []),
  ];

  const [engine, setEngine] = useState<string>(() => localStorage.getItem('diag.logs.engine') || 'context');
  const [lines, setLines] = useState<string[]>([]);
  const [n, setN] = useState<number>(() => Number(localStorage.getItem('diag.logs.n') || '100') || 100);
  const [levelFilter, setLevelFilter] = useState<string>(
    () => localStorage.getItem('diag.logs.level') || 'all',
  );
  // Aggregated events filter (when engine === 'events')
  const [eventType, setEventType] = useState<string>(() => localStorage.getItem('diag.events.type') || 'all');
  const [following, setFollowing] = useState<boolean>(false);
  const [toast, setToast] = useState<string | null>(null);
  const esRef = useRef<EventSource | null>(null);
  const logBoxRef = useRef<HTMLPreElement>(null);

  function copyLogs() {
    navigator.clipboard.writeText(lines.join('\n')).then(() => {
      setToast('Logs copied to clipboard');
    }).catch(() => {
      setToast('Failed to copy');
    });
  }

  function levelQuery(level: string) {
    return level === 'all' ? '' : `&level=${encodeURIComponent(level)}`;
  }

  function eventTypeQuery(type: string) {
    return type === 'all' ? '' : `&type=${encodeURIComponent(type)}`;
  }

  function baseUrl() {
    return loadConfig().baseUrl || 'http://localhost:9999';
  }

  function start(level = levelFilter) {
    stop();
    setLines([]);
    let url = '';
    if (engine === 'events') {
      const typePart = eventTypeQuery(eventType);
      url = `${baseUrl()}/logs/stream?${typePart}${typePart ? '&' : ''}user=${encodeURIComponent(getUserId())}`;
    } else {
      const levelPart = levelQuery(level);
      url = `${baseUrl()}/${engine}/logs?stream=1&n=${n}${levelPart}&user=${encodeURIComponent(getUserId())}`;
    }
    const es = new EventSource(url);
    // Default message handler
    es.onmessage = (ev) => {
      try {
        const data = JSON.parse(ev.data || '{}');
        if (data && data.line) setLines((prev) => [...prev, data.line]);
        else if (engine === 'events' && data && data.ts) setLines((prev) => [...prev, formatEventLine(data)]);
      } catch { /* ignore */ }
    };
    // Named events for hub logs and aggregated events
    es.addEventListener('log', (ev: MessageEvent) => {
      try {
        const data = JSON.parse((ev as any).data || '{}');
        if (data && data.line) setLines((prev) => [...prev, data.line]);
      } catch { /* ignore */ }
    });
    es.addEventListener('event', (ev: MessageEvent) => {
      try {
        const data = JSON.parse((ev as any).data || '{}');
        if (data && data.ts) setLines((prev) => [...prev, formatEventLine(data)]);
      } catch { /* ignore */ }
    });
    es.onerror = () => {
      stop();
    };
    esRef.current = es;
    setFollowing(true);
  }

  function stop() {
    esRef.current?.close();
    esRef.current = null;
    setFollowing(false);
  }

  async function tailOnce(level = levelFilter) {
    stop();
    try {
      if (engine === 'events') {
        const typePart = eventTypeQuery(eventType);
        const url = `${baseUrl()}/logs?n=${n}${typePart}`;
        const res = await fetch(url, { headers: { 'x-savant-user-id': getUserId() } });
        const js = await res.json();
        const arr: any[] = (js && js.events) || [];
        setLines(arr.map((e) => formatEventLine(e)));
      } else {
        const levelPart = levelQuery(level);
        const url = `${baseUrl()}/${engine}/logs?n=${n}${levelPart}`;
        const res = await fetch(url, { headers: { 'x-savant-user-id': getUserId() } });
        const js = await res.json();
        const arr: string[] = (js && js.lines) || [];
        setLines(arr);
      }
    } catch (err) {
      setLines([`Error fetching logs: ${err}`]);
    }
  }

  // Auto-scroll to bottom when new lines arrive
  useEffect(() => {
    if (logBoxRef.current) {
      logBoxRef.current.scrollTop = logBoxRef.current.scrollHeight;
    }
  }, [lines]);

  // Persist settings
  useEffect(() => {
    localStorage.setItem('diag.logs.engine', engine);
  }, [engine]);
  useEffect(() => {
    localStorage.setItem('diag.logs.n', String(n));
  }, [n]);
  useEffect(() => {
    localStorage.setItem('diag.logs.level', levelFilter);
  }, [levelFilter]);
  useEffect(() => {
    localStorage.setItem('diag.events.type', eventType);
  }, [eventType]);

  // Fetch logs when engine changes
  useEffect(() => {
    tailOnce();
  }, [engine]);

  function formatEventLine(e: any): string {
    try {
      const ts = e.ts || '';
      const t = e.type || 'event';
      const m = e.mcp || e.engine || '';
      const status = e.status !== undefined ? ` status=${e.status}` : '';
      const dur = e.duration_ms !== undefined ? ` ${e.duration_ms}ms` : '';
      if (t === 'http_request') {
        return `[${ts}] ${t} ${m} ${e.method || ''} ${e.path || ''}${status}${dur}`.trim();
      }
      if (t.startsWith('tool_call')) {
        return `[${ts}] ${t} ${m} ${e.tool || ''}${status}${dur}`.trim();
      }
      if (t.startsWith('client_')) {
        return `[${ts}] ${t} ${m} ${e.conn_type || ''} ${e.client_id || ''} ${e.path || ''}`.trim();
      }
      if (t === 'stdio_message') {
        return `[${ts}] ${t} ${m} ${e.dir} id=${e.id || ''} method=${e.method || ''}${dur}`.trim();
      }
      return `[${ts}] ${t} ${m}`.trim();
    } catch {
      return typeof e === 'string' ? e : JSON.stringify(e);
    }
  }

  return (
    <Box>
      <Paper sx={{ p: 2, mb: 2 }}>
        <Stack direction={{ xs: 'column', sm: 'row' }} spacing={2} alignItems="center">
          <FormControl size="small" sx={{ minWidth: 180 }}>
            <InputLabel>Engine</InputLabel>
            <Select
              value={engine}
              label="Engine"
              onChange={(e) => {
                stop();
                setEngine(e.target.value);
              }}
            >
              {engines.map((eng) => {
                const label = eng.name === 'events' ? 'All (Events)' : eng.name.charAt(0).toUpperCase() + eng.name.slice(1);
                return (
                  <MenuItem key={eng.name} value={eng.name}>
                    {label}
                  </MenuItem>
                );
              })}
            </Select>
          </FormControl>

          {engine !== 'events' ? (
            <FormControl size="small" sx={{ minWidth: 150 }}>
              <InputLabel>Level</InputLabel>
              <Select
                value={levelFilter}
                label="Level"
                onChange={(e) => {
                  const nextLevel = e.target.value;
                  setLevelFilter(nextLevel);
                  if (following) start(nextLevel); else tailOnce(nextLevel);
                }}
              >
                {LOG_LEVELS.map((level) => (
                  <MenuItem key={level.value} value={level.value}>
                    {level.label}
                  </MenuItem>
                ))}
              </Select>
            </FormControl>
          ) : (
            <FormControl size="small" sx={{ minWidth: 180 }}>
              <InputLabel>Event Type</InputLabel>
              <Select
                value={eventType}
                label="Event Type"
                onChange={(e) => {
                  const nextType = e.target.value;
                  setEventType(nextType);
                  if (following) start(); else tailOnce();
                }}
              >
                {[
                  { value: 'all', label: 'All events' },
                  { value: 'http_request', label: 'HTTP requests' },
                  { value: 'reasoning_step', label: 'Agent reasoning steps' },
                  { value: 'tool_call_started', label: 'Tool call started' },
                  { value: 'tool_call_completed', label: 'Tool call completed' },
                  { value: 'tool_call_error', label: 'Tool call errors' },
                  { value: 'client_connected', label: 'Client connected' },
                  { value: 'client_disconnected', label: 'Client disconnected' },
                  { value: 'stdio_message', label: 'STDIO messages' },
                ].map((t) => (
                  <MenuItem key={t.value} value={t.value}>{t.label}</MenuItem>
                ))}
              </Select>
            </FormControl>
          )}

          <TextField
            label="Lines"
            type="number"
            value={n}
            onChange={(e) => setN(parseInt(e.target.value || '100', 10))}
            size="small"
            sx={{ width: 100 }}
          />

          <Box sx={{ flex: 1 }} />

          <Tooltip title="Tail once">
            <span>
              <IconButton color="default" onClick={tailOnce} aria-label="Tail once">
                <RefreshIcon />
              </IconButton>
            </span>
          </Tooltip>

          {!following ? (
            <Tooltip title="Start following">
              <span>
                <IconButton color="success" onClick={start} aria-label="Follow">
                  <PlayArrowIcon />
                </IconButton>
              </span>
            </Tooltip>
          ) : (
            <Tooltip title="Stop">
              <span>
                <IconButton color="warning" onClick={stop} aria-label="Stop">
                  <StopIcon />
                </IconButton>
              </span>
            </Tooltip>
          )}

          <Tooltip title="Clear">
            <span>
              <IconButton color="default" onClick={() => setLines([])} aria-label="Clear logs">
                <DeleteIcon />
              </IconButton>
            </span>
          </Tooltip>

          <Tooltip title={lines.length === 0 ? 'No logs to copy' : 'Copy logs'}>
            <span>
              <IconButton color="inherit" onClick={copyLogs} disabled={lines.length === 0}>
                <ContentCopyIcon />
              </IconButton>
            </span>
          </Tooltip>

          {following && (
            <Chip label="LIVE" color="success" size="small" sx={{ animation: 'pulse 1s infinite' }} />
          )}
        </Stack>
      </Paper>

      <Paper sx={{ p: 0, overflow: 'hidden', display: 'flex', flexDirection: 'column', height: 'calc(100vh - 320px)', minHeight: 300 }}>
        <Box
          sx={{
            px: 2,
            py: 1,
            bgcolor: 'grey.900',
            borderBottom: '1px solid',
            borderColor: 'grey.700',
            flexShrink: 0,
          }}
        >
          <Typography variant="caption" sx={{ color: 'grey.400', fontFamily: 'monospace' }}>
            {engine === 'events'
              ? `logs/stream • ${lines.length} lines • Type: ${eventType}`
              : `${engine}/logs • ${lines.length} lines • Level: ${LOG_LEVELS.find((lvl) => lvl.value === levelFilter)?.label || 'All'}`}
          </Typography>
        </Box>
        <Box
          component="pre"
          ref={logBoxRef}
          sx={{
            m: 0,
            p: 2,
            whiteSpace: 'pre-wrap',
            wordBreak: 'break-all',
            fontFamily: 'monospace',
            fontSize: 12,
            bgcolor: '#0d1117',
            color: '#c9d1d9',
            flex: 1,
            overflow: 'auto',
            '&::-webkit-scrollbar': { width: 8 },
            '&::-webkit-scrollbar-track': { bgcolor: '#161b22' },
            '&::-webkit-scrollbar-thumb': { bgcolor: '#30363d', borderRadius: 4 },
          }}
        >
          {lines.length === 0 ? (
            <Typography sx={{ color: 'grey.600', fontStyle: 'italic' }}>
              {levelFilter === 'all' ? 'No logs available' : 'No logs match this level'}
            </Typography>
          ) : (
            lines.map((line, i) => (
              <Box
                key={i}
                component="span"
                sx={{
                  display: 'block',
                  py: 0.25,
                  '&:hover': { bgcolor: 'rgba(255,255,255,0.05)' },
                  color: line.includes('ERROR') || line.includes('error')
                    ? '#f85149'
                    : line.includes('WARN') || line.includes('warn')
                    ? '#d29922'
                    : line.includes('INFO') || line.includes('info')
                    ? '#58a6ff'
                    : 'inherit',
                }}
              >
                {line}
              </Box>
            ))
          )}
        </Box>
      </Paper>

      <Snackbar open={!!toast} autoHideDuration={2000} onClose={() => setToast(null)} message={toast || ''} />
    </Box>
  );
}
