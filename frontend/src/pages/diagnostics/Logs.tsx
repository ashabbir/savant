import React, { useEffect, useRef, useState } from 'react';
import Box from '@mui/material/Box';
import Paper from '@mui/material/Paper';
import Typography from '@mui/material/Typography';
import Stack from '@mui/material/Stack';
import TextField from '@mui/material/TextField';
import Button from '@mui/material/Button';
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

export default function DiagnosticsLogs() {
  const hub = useHubInfo();
  // Include 'hub' as first option for HTTP request logs
  const engines = [{ name: 'hub' }, ...(hub.data?.engines || [])];

  const [engine, setEngine] = useState<string>(() => localStorage.getItem('diag.logs.engine') || 'context');
  const [lines, setLines] = useState<string[]>([]);
  const [n, setN] = useState<number>(() => Number(localStorage.getItem('diag.logs.n') || '100') || 100);
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

  function baseUrl() {
    return loadConfig().baseUrl || 'http://localhost:9999';
  }

  function start() {
    stop();
    setLines([]);
    const url = `${baseUrl()}/${engine}/logs?stream=1&n=${n}&user=${encodeURIComponent(getUserId())}`;
    const es = new EventSource(url);
    es.onmessage = (ev) => {
      try {
        const data = JSON.parse(ev.data);
        if (data && data.line) {
          setLines((prev) => [...prev, data.line]);
        }
      } catch {
        /* ignore */
      }
    };
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

  async function tailOnce() {
    stop();
    const url = `${baseUrl()}/${engine}/logs?n=${n}`;
    try {
      const res = await fetch(url, { headers: { 'x-savant-user-id': getUserId() } });
      const js = await res.json();
      const arr: string[] = (js && js.lines) || [];
      setLines(arr);
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

  // Fetch logs when engine changes
  useEffect(() => {
    tailOnce();
  }, [engine]);

  return (
    <Box>
      <Paper sx={{ p: 2, mb: 2 }}>
        <Stack direction={{ xs: 'column', sm: 'row' }} spacing={2} alignItems="center">
          <FormControl size="small" sx={{ minWidth: 150 }}>
            <InputLabel>Engine</InputLabel>
            <Select
              value={engine}
              label="Engine"
              onChange={(e) => {
                stop();
                setEngine(e.target.value);
              }}
            >
              {engines.map((eng) => (
                <MenuItem key={eng.name} value={eng.name}>
                  {eng.name.charAt(0).toUpperCase() + eng.name.slice(1)}
                </MenuItem>
              ))}
            </Select>
          </FormControl>

          <TextField
            label="Lines"
            type="number"
            value={n}
            onChange={(e) => setN(parseInt(e.target.value || '100', 10))}
            size="small"
            sx={{ width: 100 }}
          />

          <Button variant="outlined" startIcon={<RefreshIcon />} onClick={tailOnce}>
            Tail
          </Button>

          {!following ? (
            <Button variant="contained" color="success" startIcon={<PlayArrowIcon />} onClick={start}>
              Follow
            </Button>
          ) : (
            <Button variant="contained" color="warning" startIcon={<StopIcon />} onClick={stop}>
              Stop
            </Button>
          )}

          <Button variant="outlined" color="inherit" startIcon={<DeleteIcon />} onClick={() => setLines([])}>
            Clear
          </Button>

          <Button variant="outlined" color="inherit" startIcon={<ContentCopyIcon />} onClick={copyLogs} disabled={lines.length === 0}>
            Copy
          </Button>

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
            {engine}/logs • {lines.length} lines
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
            <Typography sx={{ color: 'grey.600', fontStyle: 'italic' }}>No logs available</Typography>
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
