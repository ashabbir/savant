import axios from 'axios';
import { useMutation, useQuery } from '@tanstack/react-query';

export type SearchResult = { rel_path: string; chunk: string; lang: string; score: number };
export type RepoStatus = { name: string; files: number; blobs: number; chunks: number; last_mtime: string | null };

type HubConfig = { baseUrl: string; userId: string };

const LS_KEY = 'savantHub';

export function loadConfig(): HubConfig {
  try {
    const raw = localStorage.getItem(LS_KEY);
    if (!raw) throw new Error('no config');
    const parsed = JSON.parse(raw);
    return {
      baseUrl: parsed.baseUrl || import.meta.env.VITE_HUB_BASE || 'http://localhost:9999',
      userId: parsed.userId || 'dev'
    };
  } catch {
    return { baseUrl: import.meta.env.VITE_HUB_BASE || 'http://localhost:9999', userId: 'dev' };
  }
}

export function saveConfig(cfg: HubConfig) {
  localStorage.setItem(LS_KEY, JSON.stringify(cfg));
}

function client() {
  const { baseUrl, userId } = loadConfig();
  const c = axios.create({ baseURL: baseUrl });
  c.interceptors.request.use((config) => {
    config.headers = config.headers || {};
    (config.headers as any)['x-savant-user-id'] = userId || 'dev';
    return config;
  });
  return c;
}

export function useHubHealth() {
  return useQuery({
    queryKey: ['hub', 'root'],
    queryFn: async () => {
      const res = await client().get('/');
      return res.data;
    }
  });
}

export async function search(q: string, repo?: string | null, limit: number = 10): Promise<SearchResult[]> {
  const res = await client().post(`/context/tools/fts/search/call`, { params: { q, repo: repo ?? null, limit } });
  return res.data as SearchResult[];
}

export async function repoStatus(): Promise<RepoStatus[]> {
  const res = await client().post(`/context/tools/fs/repo/status/call`, { params: {} });
  return res.data as RepoStatus[];
}

export async function indexRepo(repo?: string | null): Promise<any> {
  const res = await client().post(`/context/tools/fs/repo/index/call`, { params: { repo: repo ?? null } });
  return res.data;
}

export async function deleteRepo(repo?: string | null): Promise<any> {
  const res = await client().post(`/context/tools/fs/repo/delete/call`, { params: { repo: repo ?? null } });
  return res.data;
}

export async function resetAndIndexAll(): Promise<any> {
  await deleteRepo(null);
  return indexRepo(null);
}

export function useResetAndIndex() {
  return useMutation({ mutationFn: resetAndIndexAll });
}

