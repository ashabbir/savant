import React from 'react';
import SvgIcon, { SvgIconProps } from '@mui/material/SvgIcon';

// Simple Jira-like glyph using Atlassian blue shades
export default function JiraIcon(props: SvgIconProps) {
  return (
    <SvgIcon {...props} viewBox="0 0 24 24">
      {/* Main diamond */}
      <path fill="#2684FF" d="M12 2l6 6-6 6-6-6 6-6z" />
      {/* Lower chevron */}
      <path fill="#4C9AFF" d="M7.5 12.5l4.5 4.5 4.5-4.5-1.9-1.9-2.6 2.6-2.6-2.6-1.9 1.9z" />
      {/* Center small diamond */}
      <path fill="#B3D4FF" d="M12 13l2 2-2 2-2-2 2-2z" />
    </SvgIcon>
  );
}

