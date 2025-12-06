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
      'react-router-dom', 'react-router', 'internmap', 'd3-array'
    ]
  },
  resolve: {
    alias: {
      'react-router-dom': r('react-router-dom/dist/index.js')
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
