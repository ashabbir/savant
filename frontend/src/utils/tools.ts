export type JsonSchema = { properties?: Record<string, any> } | any;

export function isSimpleSchema(schema: JsonSchema): boolean {
  try {
    if (!schema || typeof schema !== 'object') return false;
    const props = (schema as any).properties || {};
    const keys = Object.keys(props);
    if (keys.length === 0) return false;
    return keys.every((k) => {
      const t = props[k]?.type;
      if (t === 'string' || t === 'integer' || t === 'number' || t === 'boolean') return true;
      if (t === 'array' && props[k]?.items?.type === 'string') return true;
      return false;
    });
  } catch {
    return false;
  }
}

export function buildDefaultParams(schema: JsonSchema): any {
  const props = (schema && (schema as any).properties) || {};
  const out: any = {};
  Object.keys(props).forEach((k) => {
    const t = props[k]?.type;
    if (t === 'string') out[k] = '';
    else if (t === 'integer' || t === 'number') out[k] = 0;
    else if (t === 'boolean') out[k] = false;
    else if (t === 'array' && props[k]?.items?.type === 'string') out[k] = [];
  });
  return out;
}

export function parseEngineToolFromPath(path: string): { engine: string | null; tool: string | null } {
  try {
    const m = path.match(/^\/?([^/]+)\/tools\/([^/]+)\/call/);
    if (m) return { engine: m[1], tool: m[2] };
  } catch { /* ignore */ }
  return { engine: null, tool: null };
}

export function buildCurlCommand(baseUrl: string, engine: string, tool: string, params: any, userId: string): string {
  const url = `${baseUrl.replace(/\/+$/,'')}/${engine}/tools/${tool}/call`;
  const body = JSON.stringify({ params });
  return [
    'curl',
    '-sS',
    "-H", `'Content-Type: application/json'`,
    "-H", `'x-savant-user-id: ${userId}'`,
    '-X', 'POST',
    '--data', `'${body.replace(/'/g, "'\\''")}'`,
    `'${url}'`
  ].join(' ');
}

export function buildHttpieCommand(baseUrl: string, engine: string, tool: string, params: any, userId: string): string {
  const url = `${baseUrl.replace(/\/+$/,'')}/${engine}/tools/${tool}/call`;
  const body = JSON.stringify({ params });
  return [
    'http',
    '-pb',
    'POST',
    `'${url}'`,
    "Content-Type:'application/json'",
    `x-savant-user-id:'${userId}'`,
    `<<<'${body.replace(/'/g, "'\\''")}'`
  ].join(' ');
}

