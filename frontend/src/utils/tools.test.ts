import { describe, it, expect } from 'vitest';
import { isSimpleSchema, buildDefaultParams, parseEngineToolFromPath, buildCurlCommand, buildHttpieCommand } from './tools';

describe('tools utils', () => {
  it('detects simple schemas', () => {
    const simple = { properties: { q: { type: 'string' }, limit: { type: 'integer' }, tags: { type: 'array', items: { type: 'string' } } } };
    const complex = { properties: { obj: { type: 'object', properties: { a: { type: 'string' } } } } } as any;
    expect(isSimpleSchema(simple)).toBe(true);
    expect(isSimpleSchema(complex)).toBe(false);
    expect(isSimpleSchema(null as any)).toBe(false);
  });

  it('builds default params from schema', () => {
    const schema = { properties: { s: { type: 'string' }, n: { type: 'number' }, b: { type: 'boolean' }, arr: { type: 'array', items: { type: 'string' } } } };
    expect(buildDefaultParams(schema)).toEqual({ s: '', n: 0, b: false, arr: [] });
  });

  it('parses engine and tool from path', () => {
    expect(parseEngineToolFromPath('/context/tools/fts_search/call')).toEqual({ engine: 'context', tool: 'fts_search' });
    expect(parseEngineToolFromPath('think/tools/think_plan/call')).toEqual({ engine: 'think', tool: 'think_plan' });
    expect(parseEngineToolFromPath('/bad/path')).toEqual({ engine: null, tool: null });
  });

  it('builds cURL and HTTPie commands', () => {
    const base = 'http://localhost:9999/';
    const cmd = buildCurlCommand(base, 'context', 'fts_search', { q: 'foo' }, 'dev');
    expect(cmd).toContain("curl");
    expect(cmd).toContain("/context/tools/fts_search/call");
    expect(cmd).toContain("'x-savant-user-id: dev'");
    const httpie = buildHttpieCommand(base, 'context', 'fts_search', { q: 'foo' }, 'dev');
    expect(httpie).toContain('http');
    expect(httpie).toContain("POST");
  });
});

