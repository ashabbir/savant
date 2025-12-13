import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import emotionPlugin from '@emotion/babel-plugin';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const r = (p: string) => path.resolve(__dirname, 'node_modules', p);

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [
    // Use Babel-based React plugin and enable Emotion via direct import
    react({
      babel: {
        plugins: [
          [emotionPlugin as any, { sourceMap: true, autoLabel: 'dev-only', labelFormat: '[local]' }],
        ],
      },
    }),
  ],
  // Let Vite auto-optimize MUI/Emotion implicitly to avoid ESM/CJS interop issues
  optimizeDeps: {
    include: ['react-router-dom', 'react-router'],
    exclude: ['internmap'],
  },
  resolve: {
    alias: {
      'react-router-dom': r('react-router-dom/dist/index.js')
      ,
      // Shim internmap used by d3-array in reactflow; avoids npm packaging issues in container
      'internmap': path.resolve(__dirname, 'src/shims/internmap.ts')
    }
  },
  server: {
    host: '0.0.0.0',
    port: 5173
  },
  preview: {
    host: '0.0.0.0',
    port: 5173
  }
});
