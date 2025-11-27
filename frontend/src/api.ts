import axios from 'axios';
import { emitAppEvent } from './utils/bus';
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
  c.interceptors.response.use(
    (resp) => resp,
    (error) => {
      try {
        const err: any = error || {};
        const cfg: any = err.config || {};
        const method = (cfg.method || 'GET').toString().toUpperCase();
        const url = (cfg.url || '').toString();
        const resp = err.response;
        let statusStr = '';
        if (resp) {
          const s = resp.status;
          const st = resp.statusText || '';
          statusStr = `${s}${st ? ' ' + st : ''}`;
        }
        let serverMsg = '';
        const data = resp?.data;
        if (typeof data === 'string') serverMsg = data;
        else if (data && typeof data === 'object') serverMsg = data.error || data.message || '';
        else if (err.message) serverMsg = err.message;
        if (serverMsg.length > 240) serverMsg = serverMsg.slice(0, 240) + '…';
        const endpoint = [method, url].filter(Boolean).join(' ');
        const friendly = resp
          ? `Oops! ${endpoint} failed (${statusStr})${serverMsg ? ' — ' + serverMsg : ''}`
          : `Oops! ${endpoint || 'Request'} failed — ${err.message || 'Network error'}`;
        err.message = friendly;
        emitAppEvent({ type: 'error', message: friendly, detail: error });
      } catch { /* ignore */ }
      return Promise.reject(error);
    }
  );
  return c;
}

export function useHubHealth() {
  return useQuery({
    queryKey: ['hub', 'root'],
    queryFn: async () => {
      const res = await client().get('/');
      return res.data;
    },
    retry: 1
  });
}

export async function search(q: string, repo?: string | null, limit: number = 20): Promise<SearchResult[]> {
  const res = await client().post(`/context/tools/fts/search/call`, { params: { q, repo: repo ?? null, limit } });
  return res.data as SearchResult[];
}

export async function searchMemory(q: string, repo?: string | null, limit: number = 20): Promise<SearchResult[]> {
  const res = await client().post(`/context/tools/memory/search/call`, { params: { q, repo: repo ?? null, limit } });
  return res.data as SearchResult[];
}

export async function repoStatus(): Promise<RepoStatus[]> {
  const res = await client().post(`/context/tools/fs/repo/status/call`, { params: {} });
  return res.data as RepoStatus[];
}

export function useRepoStatus() {
  return useQuery<RepoStatus[]>({
    queryKey: ['repos', 'status'],
    queryFn: repoStatus
  });
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

export function getErrorMessage(err: any): string {
  try {
    if (!err) return 'Unknown error';
    const e: any = err;
    const resp = e.response;
    const cfg = e.config || {};
    const method = (cfg.method || 'GET').toString().toUpperCase();
    const url = (cfg.url || '').toString();
    const endpoint = [method, url].filter(Boolean).join(' ');
    if (resp) {
      const statusStr = `${resp.status || ''}${resp.statusText ? ' ' + resp.statusText : ''}`.trim();
      let serverMsg = '';
      if (typeof resp.data === 'string') serverMsg = resp.data;
      else if (resp.data && typeof resp.data === 'object') serverMsg = resp.data.error || resp.data.message || '';
      if (!serverMsg && e.message) serverMsg = e.message;
      if (serverMsg && serverMsg.length > 240) serverMsg = serverMsg.slice(0, 240) + '…';
      return `Oops! ${endpoint || 'Request'} failed (${statusStr})${serverMsg ? ' — ' + serverMsg : ''}`;
    }
    if (e.request) {
      const base = endpoint || 'Request';
      const m = e.message || 'Network error';
      return `Oops! ${base} failed — ${m}`;
    }
    return e.message || String(e);
  } catch {
    return 'Request failed';
  }
}

export type Diagnostics = {
  base_path: string;
  settings_path: string;
  config_error?: string;
  repos: { name: string; path: string; exists: boolean; directory: boolean; readable: boolean; has_files?: boolean; sampled_count?: number; sample_files?: string[]; error?: string }[];
  db: { connected: boolean; counts?: { repos: number; files: number; chunks: number }; error?: string; counts_error?: string };
  mounts: { [k: string]: boolean };
};

export function useDiagnostics() {
  return useQuery<Diagnostics>({
    queryKey: ['hub', 'diagnostics'],
    queryFn: async () => {
      const res = await client().post('/context/tools/fs/repo/diagnostics/call', { params: {} });
      return res.data as Diagnostics;
    },
    retry: 0
  });
}

// THINK engine API
export type ThinkWorkflowRow = { id: string; version: string; desc: string };
export type ThinkWorkflows = { workflows: ThinkWorkflowRow[] };
export function useThinkWorkflows() {
  return useQuery<ThinkWorkflows>({
    queryKey: ['think', 'workflows'],
    queryFn: async () => {
      const res = await client().post('/think/tools/think.workflows.list/call', { params: {} });
      return res.data as ThinkWorkflows;
    }
  });
}

// CONTEXT engine API: tools + memory resources + logs helper
export type ContextToolSpec = { name: string; description?: string; inputSchema?: any; schema?: any };
export function useContextTools() {
  return useQuery<{ engine: string; tools: ContextToolSpec[] }>({
    queryKey: ['context', 'tools'],
    queryFn: async () => {
      const res = await client().get('/context/tools');
      return res.data as { engine: string; tools: ContextToolSpec[] };
    }
  });
}

export async function callContextTool(name: string, params: any) {
  const res = await client().post(`/context/tools/${name}/call`, { params });
  return res.data;
}

export type MemoryResource = { uri: string; mimeType: string; metadata: { path: string; title: string; modified_at?: string | null; source?: string } };
export function useMemoryResources(repo: string | null) {
  return useQuery<MemoryResource[]>({
    queryKey: ['context', 'memory', 'list', repo || null],
    queryFn: async () => {
      const res = await client().post('/context/tools/memory/resources/list/call', { params: { repo: repo || null } });
      return res.data as MemoryResource[];
    }
  });
}

export function useMemoryResource(uri: string | null) {
  return useQuery<string>({
    queryKey: ['context', 'memory', 'read', uri],
    queryFn: async () => {
      const res = await client().post('/context/tools/memory/resources/read/call', { params: { uri } });
      return res.data as string;
    },
    enabled: !!uri
  });
}

export function getUserId(): string {
  return loadConfig().userId || 'dev';
}

export function useThinkWorkflowRead(id: string | null) {
  return useQuery<{ workflow_yaml: string }>({
    queryKey: ['think', 'workflow', id],
    queryFn: async () => {
      const res = await client().post('/think/tools/think.workflows.read/call', { params: { workflow: id } });
      return res.data as { workflow_yaml: string };
    },
    enabled: !!id
  });
}

export type ThinkPromptRow = { version: string; path: string };
export type ThinkPrompts = { versions: ThinkPromptRow[] };
export function useThinkPrompts() {
  return useQuery<ThinkPrompts>({
    queryKey: ['think', 'prompts'],
    queryFn: async () => {
      const res = await client().post('/think/tools/think.prompts.list/call', { params: {} });
      return res.data as ThinkPrompts;
    }
  });
}

export function useThinkPrompt(version: string | null) {
  return useQuery<{ version: string; hash: string; prompt_md: string }>({
    queryKey: ['think', 'prompt', version],
    queryFn: async () => {
      const res = await client().post('/think/tools/think.prompts.read/call', { params: { version } });
      return res.data as { version: string; hash: string; prompt_md: string };
    },
    enabled: !!version
  });
}

export function useThinkRuns() {
  return useQuery<{ runs: { workflow: string; run_id: string; completed: number; next_step_id?: string; path: string; updated_at: string }[] }>({
    queryKey: ['think', 'runs'],
    queryFn: async () => {
      const res = await client().post('/think/tools/think.runs.list/call', { params: {} });
      return res.data;
    }
  });
}

export function useThinkRun(workflow: string | null, runId: string | null) {
  return useQuery<{ state: any }>({
    queryKey: ['think', 'run', workflow, runId],
    queryFn: async () => {
      const res = await client().post('/think/tools/think.runs.read/call', { params: { workflow, run_id: runId } });
      return res.data;
    },
    enabled: !!workflow && !!runId
  });
}

export async function thinkRunDelete(workflow: string, runId: string) {
  const res = await client().post('/think/tools/think.runs.delete/call', { params: { workflow, run_id: runId } });
  return res.data;
}

export async function thinkPlan(workflow: string, params: any, runId?: string | null, startFresh: boolean = true) {
  const res = await client().post('/think/tools/think.plan/call', { params: { workflow, params, run_id: runId || undefined, start_fresh: startFresh } });
  return res.data as { instruction: any; state: any; run_id: string; done: boolean };
}

export async function thinkNext(workflow: string, runId: string, stepId: string, resultSnapshot: any) {
  const res = await client().post('/think/tools/think.next/call', { params: { workflow, run_id: runId, step_id: stepId, result_snapshot: resultSnapshot } });
  return res.data as { instruction?: any; done: boolean; summary?: string };
}

export function useThinkLimits() {
  return useQuery<{ max_snapshot_bytes: number; max_string_bytes: number; truncation_strategy: string; log_payload_sizes: boolean; warn_threshold_bytes: number }>({
    queryKey: ['think', 'limits'],
    queryFn: async () => {
      const res = await client().post('/think/tools/think.limits.read/call', { params: {} });
      return res.data;
    }
  });
}

// WORKFLOWS engine API (Dashboard Workflow Builder)
export type WorkflowMeta = { id: string; title: string; mtime: string };
export type WorkflowsList = { workflows: WorkflowMeta[] };
export function useWorkflows() {
  return useQuery<WorkflowsList>({
    queryKey: ['workflows', 'list'],
    queryFn: async () => {
      const res = await client().post('/workflows/tools/workflows.list/call', { params: {} });
      return res.data as WorkflowsList;
    }
  });
}

export type WorkflowGraph = { nodes: any[]; edges: any[] };
export function useWorkflow(id: string | null) {
  return useQuery<{ yaml: string; graph: WorkflowGraph }>({
    queryKey: ['workflows', 'read', id],
    queryFn: async () => {
      const res = await client().post('/workflows/tools/workflows.read/call', { params: { id } });
      return res.data as { yaml: string; graph: WorkflowGraph };
    },
    enabled: !!id
  });
}

export async function workflowValidate(graph: WorkflowGraph) {
  const res = await client().post('/workflows/tools/workflows.validate/call', { params: { graph } });
  return res.data as { ok: boolean; errors: string[] };
}

export async function workflowCreate(id: string, graph: WorkflowGraph) {
  const res = await client().post('/workflows/tools/workflows.create/call', { params: { id, graph } });
  return res.data as { ok: boolean; id: string };
}

export async function workflowUpdate(id: string, graph: WorkflowGraph) {
  const res = await client().post('/workflows/tools/workflows.update/call', { params: { id, graph } });
  return res.data as { ok: boolean; id: string };
}

export async function workflowDelete(id: string) {
  const res = await client().post('/workflows/tools/workflows.delete/call', { params: { id } });
  return res.data as { ok: boolean; deleted: boolean };
}

// Database query test
export type DbQueryTest = {
  query: string;
  results: number;
  duration_ms: number;
  success: boolean;
  error?: string;
};

export async function testDbQuery(query: string = 'test'): Promise<DbQueryTest> {
  const start = performance.now();
  try {
    const res = await client().post('/context/tools/fts/search/call', { params: { q: query, limit: 5 } });
    const duration = Math.round(performance.now() - start);
    const results = Array.isArray(res.data) ? res.data.length : 0;
    return { query, results, duration_ms: duration, success: true };
  } catch (err: any) {
    const duration = Math.round(performance.now() - start);
    return { query, results: 0, duration_ms: duration, success: false, error: err?.message || 'Query failed' };
  }
}

// Hub & Engine info
export type EngineInfo = {
  name: string;
  version: string;
  description: string;
};

export type EngineStatus = {
  engine: string;
  status: string;
  uptime_seconds: number;
  info: EngineInfo;
};

export type HubInfo = {
  service: string;
  version: string;
  transport: string;
  hub: { pid: number; uptime_seconds: number };
  engines: { name: string; mount: string; tools: number }[];
};

export function useHubInfo() {
  return useQuery<HubInfo>({
    queryKey: ['hub', 'info'],
    queryFn: async () => {
      const res = await client().get('/');
      return res.data as HubInfo;
    }
  });
}

export function useEngineStatus(engine: string) {
  return useQuery<EngineStatus>({
    queryKey: ['engine', engine, 'status'],
    queryFn: async () => {
      const res = await client().get(`/${engine}/status`);
      return res.data as EngineStatus;
    },
    enabled: !!engine,
    refetchInterval: 10000 // Refresh every 10 seconds
  });
}

export function useEngineTools(engine: string) {
  return useQuery<{ engine: string; tools: ContextToolSpec[] }>({
    queryKey: ['engine', engine, 'tools'],
    queryFn: async () => {
      const res = await client().get(`/${engine}/tools`);
      return res.data as { engine: string; tools: ContextToolSpec[] };
    },
    enabled: !!engine
  });
}

// PERSONAS engine API
export type PersonaSummary = { name: string; title: string; version: string; summary: string; tags?: string[] };
export type PersonasList = { personas: PersonaSummary[] };
export function usePersonas(filter: string = '') {
  return useQuery<PersonasList>({
    queryKey: ['personas', 'list', filter],
    queryFn: async () => {
      const res = await client().post('/personas/tools/personas.list/call', { params: { filter: filter || undefined } });
      return res.data as PersonasList;
    }
  });
}

export type Persona = { name: string; title: string; version: string; summary: string; tags?: string[]; prompt_md: string; notes?: string };
export function usePersona(name: string | null) {
  return useQuery<Persona>({
    queryKey: ['personas', 'get', name],
    queryFn: async () => {
      const res = await client().post('/personas/tools/personas.get/call', { params: { name } });
      return res.data as Persona;
    },
    enabled: !!name
  });
}

// RULES engine API
export type RuleSummary = { name: string; title: string; version: string; summary: string; tags?: string[] };
export type RulesList = { rules: RuleSummary[] };
export function useRules(filter: string = '') {
  return useQuery<RulesList>({
    queryKey: ['rules', 'list', filter],
    queryFn: async () => {
      const res = await client().post('/rules/tools/rules.list/call', { params: { filter: filter || undefined } });
      return res.data as RulesList;
    }
  });
}

export type Rule = { name: string; title: string; version: string; summary: string; tags?: string[]; rules_md: string; notes?: string };
export function useRule(name: string | null) {
  return useQuery<Rule>({
    queryKey: ['rules', 'get', name],
    queryFn: async () => {
      const res = await client().post('/rules/tools/rules.get/call', { params: { name } });
      return res.data as Rule;
    },
    enabled: !!name
  });
}

// Hub stats for diagnostics
export type RequestRecord = {
  id: number;
  time: string;
  method: string;
  path: string;
  query: string | null;
  status: number;
  duration_ms: number;
  engine: string;
  user: string | null;
  request_body: string | null;
  response_body: string | null;
};

export type HubStats = {
  uptime_seconds: number;
  requests: {
    total: number;
    by_engine: Record<string, number>;
    by_status: Record<string, number>;
    by_method: Record<string, number>;
  };
  recent: RequestRecord[];
};

export function useHubStats() {
  return useQuery<HubStats>({
    queryKey: ['hub', 'stats'],
    queryFn: async () => {
      const res = await client().get('/hub/stats');
      return res.data as HubStats;
    },
    refetchInterval: 5000 // Auto-refresh every 5 seconds
  });
}
