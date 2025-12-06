import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react-swc';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const r = (p: string) => path.resolve(__dirname, 'node_modules', p);

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  optimizeDeps: {
    include: [
      '@mui/material', '@mui/icons-material', '@emotion/react', '@emotion/styled',
      'react-router-dom', 'react-router'
    ],
    exclude: ['internmap']
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
