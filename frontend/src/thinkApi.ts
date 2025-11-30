import { useQuery } from '@tanstack/react-query';
import axios from 'axios';
import { loadConfig } from './api';

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

export type ThinkWorkflowGraph = { nodes: any[]; edges?: any[] };

export function useThinkWorkflowGraph(id: string | null) {
  return useQuery<{ nodes: any[]; order: string[] }>({
    queryKey: ['think', 'workflow', 'graph', id],
    queryFn: async () => {
      const res = await client().post('/think/tools/think_workflows_graph/call', { params: { workflow: id } });
      return res.data as { nodes: any[]; order: string[] };
    },
    enabled: !!id
  });
}

export async function thinkWorkflowValidateGraph(graph: ThinkWorkflowGraph) {
  const res = await client().post('/think/tools/think_workflows_validate/call', { params: { graph } });
  return res.data as { ok: boolean; errors: string[] };
}

export async function thinkWorkflowCreateGraph(id: string, graph: ThinkWorkflowGraph) {
  const res = await client().post('/think/tools/think_workflows_create/call', { params: { workflow: id, graph } });
  return res.data as { ok: boolean; id: string };
}

export async function thinkWorkflowUpdateGraph(id: string, graph: ThinkWorkflowGraph) {
  const res = await client().post('/think/tools/think_workflows_update/call', { params: { workflow: id, graph } });
  return res.data as { ok: boolean; id: string };
}

export async function thinkWorkflowDelete(id: string) {
  const res = await client().post('/think/tools/think_workflows_delete/call', { params: { workflow: id } });
  return res.data as { ok: boolean; deleted: boolean };
}

