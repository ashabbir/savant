import React, { useMemo } from 'react';
import Grid from '@mui/material/Unstable_Grid2';
import Paper from '@mui/material/Paper';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';

export type SmallSeries = { id: string; title?: string; data: number[] };

function Sparkline({ values, color = '#1976d2', height = 40 }: { values: number[]; color?: string; height?: number }) {
  const path = useMemo(() => {
    const w = 100; // viewBox width
    const h = height; // viewBox height
    const n = Math.max(values.length, 2);
    const max = Math.max(1, ...values);
    const points = values.map((v, i) => {
      const x = (i / (n - 1)) * w;
      const y = h - (v / max) * h;
      return `${x.toFixed(2)},${y.toFixed(2)}`;
    });
    return { d: `M ${points.join(' L ')}`, w, h };
  }, [values, height]);

  return (
    <svg viewBox={`0 0 100 ${height}`} width="100%" height={height} role="img" aria-label="sparkline">
      <polyline fill="none" stroke={color} strokeWidth={2} points={path.d.replace(/^M\s*/, '').replace(/\s*L\s*/g, ' ')} />
    </svg>
  );
}

export default function SmallMultiples({
  title,
  series,
  height = 60,
}: {
  title: string;
  series: SmallSeries[];
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
              <Sparkline values={s.data} height={height - 20} />
            </Box>
          </Grid>
        ))}
      </Grid>
    </Paper>
  );
}
