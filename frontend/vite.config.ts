import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const r = (p: string) => path.resolve(__dirname, 'node_modules', p);

// https://vitejs.dev/config/
export default defineConfig(({ command }) => ({
  // Ensure built assets resolve under Hub's /ui mount; keep dev at root
  base: command === 'build' ? '/ui/' : '/',
  plugins: [
    // Use Babel-based React plugin only; avoid Emotion babel plugin to prevent styled() conflicts
    react(),
  ],
  // Pre-bundle MUI + Emotion to avoid duplicate instances and default export interop issues
  optimizeDeps: {
    include: [
      'react-router-dom',
      'react-router',
      // MUI + Emotion
      '@mui/material',
      '@mui/material/styles',
      '@mui/system',
      '@mui/icons-material',
      '@mui/styled-engine',
      '@emotion/react',
      '@emotion/styled'
    ],
    // Only exclude local shims
    exclude: ['internmap'],
    // Force pre-bundling to refresh when config changes
    force: true,
  },
  resolve: {
    dedupe: ['react', 'react-dom', '@emotion/react', '@emotion/styled'],
    alias: [
      // Avoid forcing a specific RRD entry; let Vite resolve appropriately to prevent mixed builds
      // Shim internmap used by d3-array in reactflow; avoids npm packaging issues in container
      { find: 'internmap', replacement: path.resolve(__dirname, 'src/shims/internmap.ts') },
      // Force Emotion/MUI to ESM builds to ensure "styled" is a function and prevent CJS interop issues
      { find: '@emotion/styled', replacement: r('@emotion/styled/dist/emotion-styled.esm.js') },
      { find: '@mui/styled-engine', replacement: r('@mui/styled-engine/modern/index.js') },
      // Material styles shim to source styled() from system/engine (exact match only)
      // Ensure Material's styled import resolves to system/engine implementation without touching other named exports
      { find: '@mui/material/styles/styled', replacement: r('@mui/system/styled') },
      // Route Material's Unstable_Grid2 to System's Grid implementation to avoid styled() interop issues
      { find: '@mui/material/Unstable_Grid2', replacement: r('@mui/system/Unstable_Grid') },
      { find: '@mui/material/Unstable_Grid2/Grid2', replacement: r('@mui/system/Unstable_Grid/Grid') },
    ]
  },
  server: {
    host: '0.0.0.0',
    port: 5173
  },
  preview: {
    host: '0.0.0.0',
    port: 5173
  }
}));
