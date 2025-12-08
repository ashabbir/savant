import React from 'react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import Agents from './Agents';

vi.mock('../../api', async () => {
  return {
    useAgents: () => ({ data: { agents: [{ name: 'alpha', favorite: true, run_count: 2, last_run_at: new Date().toISOString() }] }, isLoading: false, isError: false, error: null, refetch: vi.fn() }),
    useAgent: () => ({ data: { id: 1, name: 'alpha', driver: 'drive' }, isFetching: false, isError: false, error: null, refetch: vi.fn() }),
    useAgentRuns: () => ({ data: { runs: [{ id: 1, input: 'hi', output_summary: 'ok', status: 'ok', duration_ms: 10, created_at: new Date().toISOString() }] }, isFetching: false, isError: false, error: null, refetch: vi.fn() }),
    agentsDelete: vi.fn(async () => ({ ok: true })),
    agentRun: vi.fn(async () => ({ status: 'ok' })),
    getErrorMessage: (e: any) => String(e || 'error'),
  };
});

describe('Agents page', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('renders list and allows selecting and running', async () => {
    render(<MemoryRouter><Agents /></MemoryRouter>);
    expect(await screen.findByText('Agents')).toBeInTheDocument();
    const row = await screen.findByText('alpha');
    fireEvent.click(row);
    const runBtn = await screen.findByRole('button', { name: /run/i });
    expect(runBtn).toBeDisabled();
    const input = screen.getByPlaceholderText('Enter input for run...');
    fireEvent.change(input, { target: { value: 'do it' } });
    await waitFor(() => expect(runBtn).not.toBeDisabled());
  });
});

