import React from 'react';
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import SmallMultiples from './SmallMultiples';

describe('SmallMultiples', () => {
  it('renders a small chart per series', () => {
    const series = [
      { id: 'ctx', title: 'Context', data: [1, 2, 3, 2, 1] },
      { id: 'think', title: 'Think', data: [0, 1, 0, 2, 1] },
    ];
    render(<SmallMultiples title="Recent Requests" series={series} />);
    expect(screen.getByText('Recent Requests')).toBeInTheDocument();
    expect(screen.getByText('Context')).toBeInTheDocument();
    expect(screen.getByText('Think')).toBeInTheDocument();
    // Two sparklines (svg role="img")
    const svgs = screen.getAllByRole('img', { name: 'sparkline' });
    expect(svgs.length).toBe(2);
  });
});

