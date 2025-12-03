import { describe, it, expect } from 'vitest';
import { createCompactTheme } from './compact';

describe('compact theme', () => {
  it('uses small typography and row heights', () => {
    const t = createCompactTheme('light');
    expect(t.typography.fontSize).toBeLessThanOrEqual(11);
    // Headings and body should be compact
    expect(Number.parseFloat(String((t.typography as any).body2.fontSize))).toBeTruthy();
    // Table rows compact
    const tr = (t.components?.MuiTableRow?.styleOverrides as any)?.root || {};
    expect(tr.height).toBe(28);
    const li = (t.components?.MuiListItem?.styleOverrides as any)?.root || {};
    expect(li.minHeight).toBe(28);
  });

  it('standardizes button/icon defaults', () => {
    const t = createCompactTheme('light');
    const btn = t.components?.MuiButton as any;
    expect(btn?.defaultProps?.size).toBe('small');
    const iconBtn = t.components?.MuiIconButton as any;
    expect(iconBtn?.defaultProps?.size).toBe('small');
    const svg = t.components?.MuiSvgIcon as any;
    expect(svg?.defaultProps?.fontSize).toBe('small');
  });
});
