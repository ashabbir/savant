import React, { useMemo } from 'react';
import Grid from '@mui/material/Unstable_Grid2';
import Paper from '@mui/material/Paper';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';

export type MultiSeries = { id: string; title?: string; data: { ok: number[]; warn: number[]; err: number[] } };

function MultiSpark({ ok, warn, err, height = 40 }: { ok: number[]; warn: number[]; err: number[]; height?: number }) {
  const norm = useMemo(() => {
    const series = [ok, warn, err];
    const allVals = series.flat();
    const max = Math.max(1, ...allVals);
    const n = Math.max(ok.length, warn.length, err.length, 2);
    const w = 100;
    function points(vals: number[]) {
      const v = vals.length ? vals : new Array(n).fill(0);
      return v.map((val, idx) => {
        const x = (idx / (n - 1)) * w;
        const y = height - (val / max) * height;
        return `${x.toFixed(2)},${y.toFixed(2)}`;
      }).join(' ');
    }
    return { w, h: height, ok: points(ok), warn: points(warn), err: points(err) };
  }, [ok, warn, err, height]);

  return (
    <svg viewBox={`0 0 100 ${height}`} width="100%" height={height} role="img" aria-label="sparkline-multi">
      <polyline fill="none" stroke="#4caf50" strokeWidth={2} points={norm.ok} />
      <polyline fill="none" stroke="#ffb300" strokeWidth={2} points={norm.warn} />
      <polyline fill="none" stroke="#e53935" strokeWidth={2} points={norm.err} />
    </svg>
  );
}

export default function SmallMultiplesMulti({
  title,
  series,
  height = 60,
}: {
  title: string;
  series: MultiSeries[];
  height?: number;
}) {
  return (
    <Paper sx={{ p: 1.5 }}>
      <Typography variant="subtitle2" sx={{ fontWeight: 600, mb: 1 }}>{title}</Typography>
      <Grid container spacing={1}>
        {series.map((s) => (
          <Grid key={s.id} xs={12} sm={6} md={3}>
            <Box sx={{ p: 1, border: '1px solid', borderColor: 'divider', borderRadius: 1 }}>
              <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mb: 0.5 }}>
                {s.title || s.id}
              </Typography>
              <MultiSpark ok={s.data.ok} warn={s.data.warn} err={s.data.err} height={height - 20} />
              <Box sx={{ display: 'flex', gap: 1, mt: 0.5 }}>
                <Typography variant="caption" sx={{ color: '#4caf50' }}>2xx</Typography>
                <Typography variant="caption" sx={{ color: '#ffb300' }}>4xx</Typography>
                <Typography variant="caption" sx={{ color: '#e53935' }}>5xx</Typography>
              </Box>
            </Box>
          </Grid>
        ))}
      </Grid>
    </Paper>
  );
}

