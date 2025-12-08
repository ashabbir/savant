import axios from 'axios';
import { emitAppEvent } from './utils/bus';
import { useMutation, useQuery } from '@tanstack/react-query';

export type SearchResult = { rel_path: string; chunk: string; lang: string; score: number };
export type RepoStatus = { name: string; files: number; blobs: number; chunks: number; last_mtime: string | null };

export type HubConfig = { baseUrl: string; userId: string; themeMode?: 'light' | 'dark' };

const LS_KEY = 'savantHub';

export function loadConfig(): HubConfig {
  try {
    const raw = localStorage.getItem(LS_KEY);
    if (!raw) throw new Error('no config');
    const parsed = JSON.parse(raw);
    return {
      baseUrl: parsed.baseUrl || import.meta.env.VITE_HUB_BASE || 'http://localhost:9999',
      userId: parsed.userId || 'dev',
      themeMode: parsed.themeMode === 'dark' ? 'dark' : 'light'
    };
  } catch {
    return { baseUrl: import.meta.env.VITE_HUB_BASE || 'http://localhost:9999', userId: 'dev', themeMode: 'light' };
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
  const res = await client().post(`/context/tools/fts_search/call`, { params: { q, repo: repo ?? null, limit } });
  return res.data as SearchResult[];
}

export async function searchMemory(q: string, repo?: string | null, limit: number = 20): Promise<SearchResult[]> {
  const res = await client().post(`/context/tools/memory_search/call`, { params: { q, repo: repo ?? null, limit } });
  return res.data as SearchResult[];
}

export async function repoStatus(): Promise<RepoStatus[]> {
  const res = await client().post(`/context/tools/fs_repo_status/call`, { params: {} });
  return res.data as RepoStatus[];
}

export function useRepoStatus() {
  return useQuery<RepoStatus[]>({
    queryKey: ['repos', 'status'],
    queryFn: repoStatus
  });
}

export async function indexRepo(repo?: string | null): Promise<any> {
  const res = await client().post(`/context/tools/fs_repo_index/call`, { params: { repo: repo ?? null } });
  return res.data;
}

export async function deleteRepo(repo?: string | null): Promise<any> {
  const res = await client().post(`/context/tools/fs_repo_delete/call`, { params: { repo: repo ?? null } });
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

export type LLMModelInfo = {
  name?: string;
  model?: string;
  state?: string;
  status?: string;
  running?: boolean;
  progress?: number;
  progress_percent?: number;
  [key: string]: any;
};

export type LLMDiagnostics = {
  total?: number;
  running?: number;
  states?: Record<string, number>;
  models?: LLMModelInfo[];
  error?: string;
};

export type LLMDiagnosticRuntime = {
  slm_model?: string;
  llm_model?: string;
  provider?: string;
  error?: string;
};

export type Diagnostics = {
  base_path: string;
  settings_path: string;
  config_error?: string;
  repos: { name: string; path: string; exists: boolean; directory: boolean; readable: boolean; has_files?: boolean; sampled_count?: number; sample_files?: string[]; error?: string }[];
  db: { connected: boolean; counts?: { repos: number; files: number; chunks: number }; error?: string; counts_error?: string };
  mounts: { [k: string]: boolean };
  secrets?: { path: string; exists: boolean; users?: number; services?: string[]; error?: string };
  llm_models?: LLMDiagnostics;
  llm_runtime?: LLMDiagnosticRuntime;
};

export function useDiagnostics() {
  return useQuery<Diagnostics>({
    queryKey: ['hub', 'diagnostics'],
    queryFn: async () => {
      const res = await client().post('/context/tools/fs_repo_diagnostics/call', { params: {} });
      return res.data as Diagnostics;
    },
    retry: 0
  });
}

// THINK engine API
export type ThinkWorkflowRow = { id: string; version: string; desc: string; name?: string; driver_version?: string; rules?: string[] };
export type ThinkWorkflows = { workflows: ThinkWorkflowRow[] };
export function useThinkWorkflows() {
  return useQuery<ThinkWorkflows>({
    queryKey: ['think', 'workflows'],
    queryFn: async () => {
    const res = await client().post('/think/tools/think_workflows_list/call', { params: {} });
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
      const res = await client().post('/context/tools/memory_resources_list/call', { params: { repo: repo || null } });
      return res.data as MemoryResource[];
    }
  });
}

export function useMemoryResource(uri: string | null) {
  return useQuery<string>({
    queryKey: ['context', 'memory', 'read', uri],
    queryFn: async () => {
      const res = await client().post('/context/tools/memory_resources_read/call', { params: { uri } });
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
      const res = await client().post('/think/tools/think_workflows_read/call', { params: { workflow: id } });
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
      const res = await client().post('/think/tools/think_prompts_list/call', { params: {} });
      return res.data as ThinkPrompts;
    }
  });
}

export function useThinkPrompt(version: string | null) {
  return useQuery<{ version: string; hash: string; prompt_md: string }>({
    queryKey: ['think', 'prompt', version],
    queryFn: async () => {
  const res = await client().post('/think/tools/think_prompts_read/call', { params: { version } });
      return res.data as { version: string; hash: string; prompt_md: string };
    },
    enabled: !!version
  });
}

// THINK prompts mutations and catalog ops
export async function thinkPromptsCreate(payload: { version: string; prompt_md: string; path?: string }) {
  const res = await client().post('/think/tools/think_prompts_create/call', { params: payload });
  return res.data as { ok: boolean; version: string; path: string };
}

export async function thinkPromptsUpdate(payload: { version: string; prompt_md?: string; new_version?: string }) {
  const res = await client().post('/think/tools/think_prompts_update/call', { params: payload });
  return res.data as { ok: boolean; version: string; path: string };
}

export async function thinkPromptsDelete(version: string) {
  const res = await client().post('/think/tools/think_prompts_delete/call', { params: { version } });
  return res.data as { ok: boolean; deleted: boolean };
}

export async function thinkPromptsCatalogRead() {
  const res = await client().post('/think/tools/think_prompts_catalog_read/call', { params: {} });
  return res.data as { catalog_yaml: string };
}

export async function thinkPromptsCatalogWrite(yaml: string) {
  const res = await client().post('/think/tools/think_prompts_catalog_write/call', { params: { yaml } });
  return res.data as { ok: boolean; count: number };
}

export function useThinkRuns() {
  return useQuery<{ runs: { workflow: string; run_id: string; completed: number; next_step_id?: string; path: string; updated_at: string }[] }>({
    queryKey: ['think', 'runs'],
    queryFn: async () => {
      const res = await client().post('/think/tools/think_runs_list/call', { params: {} });
      return res.data;
    }
  });
}

export function useThinkRun(workflow: string | null, runId: string | null) {
  return useQuery<{ state: any }>({
    queryKey: ['think', 'run', workflow, runId],
    queryFn: async () => {
      const res = await client().post('/think/tools/think_runs_read/call', { params: { workflow, run_id: runId } });
      return res.data;
    },
    enabled: !!workflow && !!runId
  });
}

export async function thinkRunDelete(workflow: string, runId: string) {
  const res = await client().post('/think/tools/think_runs_delete/call', { params: { workflow, run_id: runId } });
  return res.data;
}

export async function thinkPlan(workflow: string, params: any, runId?: string | null, startFresh: boolean = true) {
  const res = await client().post('/think/tools/think_plan/call', { params: { workflow, params, run_id: runId || undefined, start_fresh: startFresh } });
  return res.data as { instruction: any; state: any; run_id: string; done: boolean };
}

export async function thinkNext(workflow: string, runId: string, stepId: string, resultSnapshot: any) {
  const res = await client().post('/think/tools/think_next/call', { params: { workflow, run_id: runId, step_id: stepId, result_snapshot: resultSnapshot } });
  return res.data as { instruction?: any; done: boolean; summary?: string };
}

export function useThinkLimits() {
  return useQuery<{ max_snapshot_bytes: number; max_string_bytes: number; truncation_strategy: string; log_payload_sizes: boolean; warn_threshold_bytes: number }>({
    queryKey: ['think', 'limits'],
    queryFn: async () => {
      const res = await client().post('/think/tools/think_limits_read/call', { params: {} });
      return res.data;
    }
  });
}

// WORKFLOW engine API
export function useWorkflowRuns() {
  return useQuery<{ runs: { workflow: string; run_id: string; steps: number; status: string; path: string; updated_at: string }[] }>({
    queryKey: ['workflow', 'runs'],
    queryFn: async () => {
      const res = await client().post('/workflow/tools/workflow_runs_list/call', { params: {} });
      return res.data;
    }
  });
}

export function useWorkflowRun(workflow: string | null, runId: string | null) {
  return useQuery<{ state: any }>({
    queryKey: ['workflow', 'run', workflow, runId],
    queryFn: async () => {
      const res = await client().post('/workflow/tools/workflow.runs.read/call', { params: { workflow, run_id: runId } });
      return res.data;
    },
    enabled: !!workflow && !!runId
  });
}

export async function workflowRunDelete(workflow: string, runId: string) {
  const res = await client().post('/workflow/tools/workflow.runs.delete/call', { params: { workflow, run_id: runId } });
  return res.data as { ok: boolean; deleted: boolean };
}

export async function workflowRunStart(workflow: string, params: any) {
  const res = await client().post('/workflow/tools/workflow.run/call', { params: { workflow, params } });
  return res.data as { run_id: string; final: any; steps: number; status: string; error?: string };
}

export function useWorkflowList(filter: string = '') {
  return useQuery<{ workflows: { id: string; path: string }[] }>({
    queryKey: ['workflow', 'list', filter],
    queryFn: async () => {
      const res = await client().post('/workflow/tools/workflow.list/call', { params: { filter: filter || undefined } });
      return res.data as { workflows: { id: string; path: string }[] };
    }
  });
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
    const res = await client().post('/context/tools/fts_search/call', { params: { q: query, limit: 5 } });
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

export type MultiplexerInfo = {
  status?: string;
  engines?: number;
  online?: number;
  offline?: number;
  tools?: number;
  routes?: number;
  uptime_seconds?: number;
  log_path?: string;
  version?: string;
  notes?: string;
};

export type HubInfo = {
  service: string;
  version: string;
  transport: string;
  hub: { pid: number; uptime_seconds: number };
  engines: { name: string; mount: string; tools: number }[];
  multiplexer?: MultiplexerInfo;
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

// Generic tool caller for any engine (used by diagnostics/health).
export async function callEngineTool(engine: string, name: string, params: any): Promise<any> {
  const res = await client().post(`/${engine}/tools/${name}/call`, { params });
  return res.data;
}

// PERSONAS engine API
export type PersonaSummary = { name: string; version: number; summary: string; tags?: string[] };
export type PersonasList = { personas: PersonaSummary[] };
export function usePersonas(filter: string = '') {
  return useQuery<PersonasList>({
    queryKey: ['personas', 'list', filter],
    queryFn: async () => {
      const res = await client().post('/personas/tools/personas_list/call', { params: { filter: filter || undefined } });
      return res.data as PersonasList;
    }
  });
}

export type Persona = { name: string; version: number; summary: string; tags?: string[]; prompt_md: string; notes?: string };
export function usePersona(name: string | null) {
  return useQuery<Persona>({
    queryKey: ['personas', 'get', name],
    queryFn: async () => {
      const res = await client().post('/personas/tools/personas_get/call', { params: { name } });
      return res.data as Persona;
    },
    enabled: !!name
  });
}

// PERSONAS engine mutations and catalog ops
export async function personasCreate(payload: { name: string; summary: string; prompt_md: string; tags?: string[]; notes?: string | null }) {
  const res = await client().post('/personas/tools/personas_create/call', { params: payload });
  return res.data as { ok: boolean; name: string };
}

export async function personasUpdate(payload: { name: string; summary?: string; prompt_md?: string; tags?: string[]; notes?: string | null }) {
  const res = await client().post('/personas/tools/personas_update/call', { params: payload });
  return res.data as { ok: boolean; name: string };
}

export async function personasDelete(name: string) {
  const res = await client().post('/personas/tools/personas_delete/call', { params: { name } });
  return res.data as { ok: boolean; deleted: boolean };
}

export function usePersonasCreate() { return useMutation({ mutationFn: personasCreate }); }
export function usePersonasUpdate() { return useMutation({ mutationFn: personasUpdate }); }
export function usePersonasDelete() { return useMutation({ mutationFn: personasDelete }); }

export async function personasCatalogRead() {
  const res = await client().post('/personas/tools/personas_catalog_read/call', { params: {} });
  return res.data as { catalog_yaml: string };
}

export async function personasCatalogWrite(yaml: string) {
  const res = await client().post('/personas/tools/personas_catalog_write/call', { params: { yaml } });
  return res.data as { ok: boolean; count: number };
}

// RULES engine API
export type RuleSummary = { id?: string; name: string; version: number; summary: string; tags?: string[] };
export type RulesList = { rules: RuleSummary[] };
export function useRules(filter: string = '') {
  return useQuery<RulesList>({
    queryKey: ['rules', 'list', filter],
    queryFn: async () => {
      const res = await client().post('/rules/tools/rules_list/call', { params: { filter: filter || undefined } });
      return res.data as RulesList;
    }
  });
}

export type Rule = { id?: string; name: string; version: number; summary: string; tags?: string[]; rules_md: string; notes?: string };
export function useRule(name: string | null) {
  return useQuery<Rule>({
    queryKey: ['rules', 'get', name],
    queryFn: async () => {
      const res = await client().post('/rules/tools/rules_get/call', { params: { name } });
      return res.data as Rule;
    },
    enabled: !!name
  });
}

// RULES engine mutations (create/update/delete + catalog rw)
export async function rulesCreate(payload: { name: string; summary: string; rules_md: string; tags?: string[]; notes?: string | null }) {
  const res = await client().post('/rules/tools/rules_create/call', { params: payload });
  return res.data as { ok: boolean; name: string };
}

export async function rulesUpdate(payload: { name: string; summary?: string; rules_md?: string; tags?: string[]; notes?: string | null }) {
  const res = await client().post('/rules/tools/rules_update/call', { params: payload });
  return res.data as { ok: boolean; name: string };
}

export async function rulesDelete(name: string) {
  const res = await client().post('/rules/tools/rules_delete/call', { params: { name } });
  return res.data as { ok: boolean; deleted: boolean };
}

export function useRulesCreate() {
  return useMutation({ mutationFn: rulesCreate });
}

export function useRulesUpdate() {
  return useMutation({ mutationFn: rulesUpdate });
}

export function useRulesDelete() {
  return useMutation({ mutationFn: rulesDelete });
}

export async function rulesCatalogRead() {
  const res = await client().post('/rules/tools/rules_catalog_read/call', { params: {} });
  return res.data as { catalog_yaml: string };
}

export async function rulesCatalogWrite(yaml: string) {
  const res = await client().post('/rules/tools/rules_catalog_write/call', { params: { yaml } });
  return res.data as { ok: boolean; count: number };
}

// AGENTS engine API
export type AgentSummary = { id: number; name: string; favorite: boolean; run_count?: number; last_run_at?: string | null };
export type AgentsList = { agents: AgentSummary[] };
export type Agent = { id: number; name: string; persona_id?: number | null; persona_name?: string | null; driver: string; rule_set_ids: number[]; rules_names?: string[]; favorite: boolean; run_count?: number; last_run_at?: string | null };

export function useAgents() {
  return useQuery<AgentsList>({
    queryKey: ['agents', 'list'],
    queryFn: async () => {
      const res = await client().post('/agents/tools/agents_list/call', { params: {} });
      return res.data as AgentsList;
    }
  });
}

export function useAgent(name: string | null) {
  return useQuery<Agent>({
    queryKey: ['agents', 'get', name],
    queryFn: async () => {
      const res = await client().post('/agents/tools/agents_get/call', { params: { name } });
      return res.data as Agent;
    },
    enabled: !!name
  });
}

export async function agentsCreate(payload: { name: string; persona: string; driver: string; rules?: string[]; favorite?: boolean }) {
  const res = await client().post('/agents/tools/agents_create/call', { params: payload });
  return res.data as Agent;
}

export async function agentsUpdate(payload: { name: string; persona?: string; driver?: string; rules?: string[]; favorite?: boolean }) {
  const res = await client().post('/agents/tools/agents_update/call', { params: payload });
  return res.data as Agent;
}

// DRIVERS engine API (similar to personas)
export type DriverSummary = { name: string; version: number; summary: string; tags?: string[] };
export type DriversList = { drivers: DriverSummary[] };
export function useDrivers(filter: string = '') {
  return useQuery<DriversList>({
    queryKey: ['drivers', 'list', filter],
    queryFn: async () => {
      const res = await client().post('/drivers/tools/drivers_list/call', { params: { filter: filter || undefined } });
      return res.data as DriversList;
    }
  });
}

export type Driver = { name: string; version: number; summary: string; tags?: string[]; prompt_md: string; notes?: string };
export function useDriver(name: string | null) {
  return useQuery<Driver>({
    queryKey: ['drivers', 'get', name],
    queryFn: async () => {
      const res = await client().post('/drivers/tools/drivers_get/call', { params: { name } });
      return res.data as Driver;
    },
    enabled: !!name
  });
}

export async function driversCreate(payload: { name: string; summary: string; prompt_md: string; tags?: string[]; notes?: string | null }) {
  const res = await client().post('/drivers/tools/drivers_create/call', { params: payload });
  return res.data as { ok: boolean; name: string };
}

export async function driversUpdate(payload: { name: string; summary?: string; prompt_md?: string; tags?: string[]; notes?: string | null }) {
  const res = await client().post('/drivers/tools/drivers_update/call', { params: payload });
  return res.data as { ok: boolean; name: string };
}

export async function driversDelete(name: string) {
  const res = await client().post('/drivers/tools/drivers_delete/call', { params: { name } });
  return res.data as { ok: boolean; deleted: boolean };
}

export function useDriversCreate() { return useMutation({ mutationFn: driversCreate }); }
export function useDriversUpdate() { return useMutation({ mutationFn: driversUpdate }); }
export function useDriversDelete() { return useMutation({ mutationFn: driversDelete }); }

export async function driversCatalogRead() {
  const res = await client().post('/drivers/tools/drivers_catalog_read/call', { params: {} });
  return res.data as { catalog_yaml: string };
}

export async function driversCatalogWrite(yaml: string) {
  const res = await client().post('/drivers/tools/drivers_catalog_write/call', { params: { yaml } });
  return res.data as { ok: boolean; count: number };
}

export async function agentsDelete(name: string) {
  const res = await client().post('/agents/tools/agents_delete/call', { params: { name } });
  return res.data as { ok: boolean };
}

export type AgentRun = { id: number; input: string; output_summary?: string; status?: string; duration_ms?: number; created_at: string; steps?: number | null; final?: string | null };
export function useAgentRuns(name: string | null) {
  return useQuery<{ runs: AgentRun[] }>({
    queryKey: ['agents', 'runs', name],
    queryFn: async () => {
      const res = await client().post('/agents/tools/agents_runs_list/call', { params: { name } });
      return res.data as { runs: AgentRun[] };
    },
    enabled: !!name
  });
}

export async function agentRun(name: string, input: string, maxSteps?: number) {
  const res = await client().post('/agents/tools/agents_run/call', { params: { name, input, max_steps: maxSteps } });
  return res.data as { status: string; duration_ms?: number; result?: any };
}

export async function agentRunRead(name: string, runId: number) {
  const res = await client().post('/agents/tools/agents_run_read/call', { params: { name, run_id: runId } });
  return res.data as { id: number; transcript: any };
}

export async function agentRunCancel(name: string) {
  const res = await client().post('/agents/tools/agents_run_cancel/call', { params: { name } });
  return res.data as { ok: boolean };
}

export async function agentRunDelete(name: string, runId: number) {
  const res = await client().post('/agents/tools/agents_run_delete/call', { params: { name, run_id: runId } });
  return res.data as { ok: boolean };
}

export async function agentRunsClearAll(name: string) {
  const res = await client().post('/agents/tools/agents_runs_clear_all/call', { params: { name } });
  return res.data as { deleted_count: number };
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

// Routes API for diagnostics
export type RouteInfo = {
  module: string;
  method: string;
  path: string;
  description: string;
};

export type RoutesResponse = {
  routes: RouteInfo[];
};

export function useRoutes() {
  return useQuery<RoutesResponse>({
    queryKey: ['hub', 'routes'],
    queryFn: async () => {
      const res = await client().get('/routes?expand=1');
      return res.data as RoutesResponse;
    }
  });
}

// Jira credentials diagnostics (no secret values; booleans + source)
export type JiraCredsCheck = {
  user: string | null;
  resolved_user: string | null;
  source: 'secret_store' | 'env' | 'none' | string;
  fields: { base_url: boolean; email: boolean; api_token: boolean; username: boolean; password: boolean };
  auth_mode: 'email+token' | 'username+password' | 'missing' | string;
  allow_writes: boolean | null;
  problems: string[];
  suggestions: string[];
};

export function useJiraCreds() {
  return useQuery<JiraCredsCheck>({
    queryKey: ['diagnostics', 'jira'],
    queryFn: async () => {
      const res = await client().get('/diagnostics/jira');
      return res.data as JiraCredsCheck;
    },
    retry: 0
  });
}
