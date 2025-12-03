import React from 'react';
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import SmallMultiplesMulti from './SmallMultiplesMulti';

describe('SmallMultiplesMulti', () => {
  it('renders multi-series tiles with legend', () => {
    const series = [
      { id: 'ctx', title: 'Context', data: { ok: [1,2,3], warn: [0,1,0], err: [0,0,1] } },
    ];
    render(<SmallMultiplesMulti title="Status" series={series} />);
    expect(screen.getByText('Status')).toBeInTheDocument();
    expect(screen.getByText('Context')).toBeInTheDocument();
    expect(screen.getByText('2xx')).toBeInTheDocument();
    expect(screen.getByText('4xx')).toBeInTheDocument();
    expect(screen.getByText('5xx')).toBeInTheDocument();
  });
});

