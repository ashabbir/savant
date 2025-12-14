import React from 'react';
import { SvgIcon, SvgIconProps } from '@mui/material';

export default function LLMIcon(props: SvgIconProps) {
  return (
    <SvgIcon viewBox="0 0 24 24" {...props}>
      {/* Brain shape with neural network connections */}
      <g fill="currentColor">
        {/* Main brain body */}
        <circle cx="12" cy="9" r="6" opacity="0.3" />

        {/* Left hemisphere bumps */}
        <circle cx="8" cy="6" r="1.5" />
        <circle cx="7" cy="9" r="1.5" />
        <circle cx="8" cy="12" r="1.5" />

        {/* Right hemisphere bumps */}
        <circle cx="16" cy="6" r="1.5" />
        <circle cx="17" cy="9" r="1.5" />
        <circle cx="16" cy="12" r="1.5" />

        {/* Top center bump */}
        <circle cx="12" cy="4" r="1.5" />

        {/* Center nodes */}
        <circle cx="12" cy="9" r="1.2" fill="currentColor" />
        <circle cx="10" cy="8" r="0.8" />
        <circle cx="14" cy="8" r="0.8" />
        <circle cx="10" cy="10" r="0.8" />
        <circle cx="14" cy="10" r="0.8" />
      </g>

      {/* Neural network connections (wires) */}
      <g stroke="currentColor" strokeWidth="0.8" fill="none" opacity="0.8">
        {/* Left side connections */}
        <line x1="8" y1="6" x2="10" y2="8" />
        <line x1="7" y1="9" x2="10" y2="9" />
        <line x1="8" y1="12" x2="10" y2="10" />

        {/* Right side connections */}
        <line x1="16" y1="6" x2="14" y2="8" />
        <line x1="17" y1="9" x2="14" y2="9" />
        <line x1="16" y1="12" x2="14" y2="10" />

        {/* Top connection */}
        <line x1="12" y1="4" x2="12" y2="8" />

        {/* Cross connections */}
        <line x1="10" y1="8" x2="14" y2="8" />
        <line x1="10" y1="10" x2="14" y2="10" />
        <line x1="10" y1="8" x2="10" y2="10" />
        <line x1="14" y1="8" x2="14" y2="10" />
      </g>

      {/* Bottom connectors (representing output) */}
      <g stroke="currentColor" strokeWidth="0.8" fill="none" opacity="0.6">
        <line x1="9" y1="14" x2="9" y2="18" />
        <line x1="12" y1="14" x2="12" y2="18" />
        <line x1="15" y1="14" x2="15" y2="18" />
        <circle cx="9" cy="19" r="0.6" fill="currentColor" />
        <circle cx="12" cy="19" r="0.6" fill="currentColor" />
        <circle cx="15" cy="19" r="0.6" fill="currentColor" />
      </g>
    </SvgIcon>
  );
}
