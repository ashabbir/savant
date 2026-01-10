import React, { useEffect, useRef, useState } from 'react';
import Paper from '@mui/material/Paper';
import Typography from '@mui/material/Typography';
import Stack from '@mui/material/Stack';
import TextField from '@mui/material/TextField';
import Button from '@mui/material/Button';
import Box from '@mui/material/Box';
import { getUserId, loadConfig } from '../../api';

export default function ContextLogs() {
  const [lines, setLines] = useState<string[]>([]);
  const [n, setN] = useState<number>(() => Number(localStorage.getItem('ctx.logs.n')||'100')||100);
  const [following, setFollowing] = useState<boolean>(false);
  const pollRef = useRef<number | null>(null);

  function baseUrl() { return loadConfig().baseUrl || 'http://localhost:9999'; }
  function start() {
    stop();
    // Initial fetch and then poll every 2s
    tailOnce();
    pollRef.current = window.setInterval(() => { tailOnce(); }, 2000);
    setFollowing(true);
  }
  function stop() {
    if (pollRef.current) {
      clearInterval(pollRef.current);
      pollRef.current = null;
    }
    setFollowing(false);
  }
  async function tailOnce() {
    const url = `${baseUrl()}/context/logs?n=${n}`;
    const res = await fetch(url, { headers: { 'x-savant-user-id': getUserId() } });
    const js = await res.json();
    const arr: string[] = (js && js.lines) || [];
    setLines(arr);
  }

  useEffect(()=>{ tailOnce(); return () => { if (pollRef.current) clearInterval(pollRef.current); }; }, []);
  useEffect(()=>{ localStorage.setItem('ctx.logs.n', String(n)); }, [n]);

  return (
    <Paper sx={{ p: 2 }}>
      <Typography variant="subtitle1">Context Logs</Typography>
      <Stack direction="row" spacing={1} alignItems="center" sx={{ my: 1 }}>
        <TextField label="Tail N" type="number" value={n} onChange={(e)=>setN(parseInt(e.target.value||'100',10))} sx={{ width: 120 }} />
        <Button variant="outlined" onClick={tailOnce}>Tail</Button>
        {!following ? (
          <Button variant="contained" onClick={start}>Follow</Button>
        ) : (
          <Button color="warning" onClick={stop}>Stop</Button>
        )}
        <Button onClick={()=>setLines([])}>Clear</Button>
      </Stack>
      <Box component="pre" sx={{ whiteSpace: 'pre-wrap', fontFamily: 'monospace', bgcolor: '#111', color: '#ddd', p: 2, minHeight: 240, borderRadius: 1 }}>
        {lines.join('\n')}
      </Box>
    </Paper>
  );
}
