import React from 'react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import ToolRunner from './ToolRunner';

vi.mock('../api', async () => {
  return {
    callEngineTool: vi.fn(async () => ({ ok: true })),
    loadConfig: () => ({ baseUrl: 'http://localhost:9999' }),
    getUserId: () => 'dev',
  };
});

const { callEngineTool } = await import('../api');

describe('ToolRunner', () => {
  beforeEach(() => {
    localStorage.clear();
    vi.clearAllMocks();
  });

  it('renders form for simple schema and runs tool', async () => {
    const tool = { name: 'fts_search', inputSchema: { properties: { q: { type: 'string' }, limit: { type: 'integer' } } } } as any;
    render(<ToolRunner engine="context" tool={tool} />);
    // Form fields should be present
    const qField = await screen.findByLabelText('q');
    fireEvent.change(qField, { target: { value: 'test' } });
    const limitField = await screen.findByLabelText('limit');
    fireEvent.change(limitField, { target: { value: '5' } });
    const runBtn = screen.getByRole('button', { name: /run/i });
    fireEvent.click(runBtn);
    await waitFor(() => expect(callEngineTool).toHaveBeenCalled());
    const args = (callEngineTool as any).mock.calls[0];
    expect(args[0]).toBe('context');
    expect(args[1]).toBe('fts_search');
    expect(args[2]).toMatchObject({ q: 'test', limit: 5 });
  });

  it('falls back to JSON editor for complex schema', async () => {
    const tool = { name: 'complex', inputSchema: { properties: { obj: { type: 'object', properties: { a: { type: 'string' } } } } } } as any;
    render(<ToolRunner engine="rules" tool={tool} />);
    // Should render JSON field
    const jsonField = await screen.findByLabelText(/params \(json\)/i);
    fireEvent.change(jsonField, { target: { value: '{"hello":"world"}' } });
    fireEvent.click(screen.getByRole('button', { name: /run/i }));
    await waitFor(() => expect(callEngineTool).toHaveBeenCalled());
  });

  it('readOnly hides run controls', async () => {
    const tool = { name: 'noop', inputSchema: { properties: { q: { type: 'string' } } } } as any;
    render(<ToolRunner engine="workflow" tool={tool} readOnly />);
    // Schema viewer still present (by heading text)
    expect(await screen.findByText(/noop/i)).toBeInTheDocument();
    // No Run button in readOnly mode
    const run = screen.queryByRole('button', { name: /run/i });
    expect(run).toBeNull();
  });
});
