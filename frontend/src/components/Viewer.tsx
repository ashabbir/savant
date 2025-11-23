import React, { useMemo } from 'react';
import Box from '@mui/material/Box';
import DOMPurify from 'dompurify';
import { marked } from 'marked';

type ViewerProps = {
  content: string;
  contentType?: string; // e.g., 'markdown', 'text/plain', 'ruby', 'java', 'scala'
  filename?: string;    // used to infer type by extension
  language?: string;    // override language (e.g., 'rb', 'java', 'scala', 'md')
  height?: number | string;
  className?: string;
};

function escapeHtml(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function wrapToken(text: string, cls: string): string {
  return `<span class="${cls}">${escapeHtml(text)}</span>`;
}

function buildKeywordRegex(words: string[]): RegExp {
  const body = words.map(w => w.replace(/[-/\\^$*+?.()|[\]{}]/g, '\\$&')).join('|');
  return new RegExp(`\\b(?:${body})\\b`, 'g');
}

// Very small, focused syntax highlighter for Ruby/Java/Scala.
// It is not exhaustive; tuned for readability of code snippets.
function simpleHighlight(code: string, lang: 'ruby' | 'java' | 'scala'): string {
  // Extract strings and comments first into placeholders.
  type Slot = { key: string; html: string };
  const slots: Slot[] = [];
  let idx = 0;

  function put(html: string): string {
    const key = `\u0000SLOT_${idx++}\u0000`;
    slots.push({ key, html });
    return key;
  }

  let s = code;

  // Block comments (Java/Scala)
  if (lang !== 'ruby') {
    s = s.replace(/\/\*[\s\S]*?\*\//g, (m) => put(`<span class="tok-com">${escapeHtml(m)}</span>`));
  }
  // Line comments
  if (lang === 'ruby') {
    s = s.replace(/#.*/g, (m) => put(`<span class="tok-com">${escapeHtml(m)}</span>`));
  } else {
    s = s.replace(/\/\/.*$/gm, (m) => put(`<span class="tok-com">${escapeHtml(m)}</span>`));
  }

  // Strings (single, double, and Scala triple)
  s = s.replace(/'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*"|"""[\s\S]*?"""/g, (m) => put(`<span class="tok-str">${escapeHtml(m)}</span>`));

  // Numbers
  s = s.replace(/\b\d+(?:_\d+)*(?:\.\d+)?\b/g, (m) => wrapToken(m, 'tok-num'));

  // Symbols (Ruby)
  if (lang === 'ruby') {
    s = s.replace(/(?::)[a-zA-Z_]\w*/g, (m) => wrapToken(m, 'tok-sym'));
    // Instance / class / global vars
    s = s.replace(/[@$]{1,2}[a-zA-Z_]\w*/g, (m) => wrapToken(m, 'tok-var'));
  }

  // Types (Java/Scala): highlight Capitalized identifiers and common types
  if (lang !== 'ruby') {
    s = s.replace(/\b(?:String|Integer|Long|Short|Double|Float|Boolean|Character|Byte|List|Map|Set|Optional|Future|Either|Option|Unit|Any|Nothing|BigInt|BigDecimal)\b/g, (m) => wrapToken(m, 'tok-type'));
    s = s.replace(/\b[A-Z][A-Za-z0-9_]*\b/g, (m) => wrapToken(m, 'tok-type'));
  }

  // Keywords
  const KEYWORDS: Record<typeof lang, string[]> = {
    ruby: [
      'def','end','class','module','if','else','elsif','case','when','then','do','while','until','for','in','break','next','redo','retry','rescue','ensure','yield','return','self','nil','true','false','and','or','not','alias','undef','super','unless','BEGIN','END','require','include','extend'
    ],
    java: [
      'public','private','protected','class','interface','enum','static','final','void','int','long','short','double','float','boolean','char','byte','if','else','switch','case','default','for','while','do','return','try','catch','finally','throw','throws','new','this','super','extends','implements','import','package','synchronized','volatile','transient','abstract','native','strictfp','assert','instanceof'
    ],
    scala: [
      'def','val','var','lazy','type','class','object','trait','extends','with','new','if','else','match','case','for','while','do','yield','return','try','catch','finally','throw','import','package','implicit','given','using','end','enum','then','override','private','protected','final','abstract','sealed'
    ]
  } as const;

  const kwRe = buildKeywordRegex(KEYWORDS[lang]);
  s = s.replace(kwRe, (m) => wrapToken(m, 'tok-kw'));

  // Restore slots
  for (const slot of slots) {
    s = s.replaceAll(slot.key, slot.html);
  }
  return s;
}

// Pretty-print JSON into HTML with token classes
function renderJsonHtml(text: string): string {
  try {
    const val = typeof text === 'string' ? JSON.parse(text) : text;
    function esc(s: string) { return escapeHtml(String(s)); }
    function q(s: string) { return `"${esc(s)}"`; }
    function walk(v: any, depth: number): string {
      const pad = '  '.repeat(depth);
      const pad1 = '  '.repeat(depth + 1);
      if (v === null) return '<span class="tok-kw">null</span>';
      if (typeof v === 'string') return `<span class="tok-str">${q(v)}</span>`;
      if (typeof v === 'number') return `<span class="tok-num">${String(v)}</span>`;
      if (typeof v === 'boolean') return `<span class="tok-kw">${String(v)}</span>`;
      if (Array.isArray(v)) {
        if (v.length === 0) return '[]';
        const items = v.map((it, i) => `${pad1}${walk(it, depth + 1)}${i < v.length - 1 ? ',' : ''}`).join('\n');
        return `[\n${items}\n${pad}]`;
      }
      // object
      const entries = Object.entries(v || {});
      if (entries.length === 0) return '{}';
      const lines = entries.map(([k, vv], i) => `${pad1}<span class="tok-key">${q(k)}</span>: ${walk(vv, depth + 1)}${i < entries.length - 1 ? ',' : ''}`).join('\n');
      return `{\n${lines}\n${pad}}`;
    }
    return walk(val, 0);
  } catch {
    return escapeHtml(text);
  }
}

// Lightweight YAML highlighter
function renderYamlHtml(text: string): string {
  let s = text;
  s = s.replace(/#.*/g, (m) => `<span class="tok-com">${escapeHtml(m)}</span>`);
  s = s.replace(/'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*"/g, (m) => `<span class=\"tok-str\">${escapeHtml(m)}</span>`);
  s = s.replace(/([&*][a-zA-Z0-9_-]+)/g, (m) => `<span class=\"tok-var\">${escapeHtml(m)}</span>`);
  s = s.replace(/^(\s*)([^\s:#][^:#\n]*?)(\s*):/gm, (_m, p1: string, p2: string, p3: string) => `${p1}<span class="tok-key">${escapeHtml(p2)}</span>${p3}:`);
  s = s.replace(/\b(?:true|false|null|~)\b/g, (m) => `<span class=\"tok-kw\">${m}</span>`);
  s = s.replace(/\b-?\d+(?:\.\d+)?\b/g, (m) => `<span class=\"tok-num\">${m}</span>`);
  return s.split('\n').map(ln => `<div>${ln}</div>`).join('');
}

function detectType({ contentType, filename, language }: { contentType?: string; filename?: string; language?: string }): 'markdown' | 'ruby' | 'java' | 'scala' | 'json' | 'yaml' | 'text' {
  const ct = (contentType || '').toLowerCase();
  const lang = (language || '').toLowerCase();
  const ext = (filename || '').split('.').pop()?.toLowerCase();
  if (ct.includes('markdown') || lang === 'md' || lang === 'markdown' || ext === 'md' || ext === 'mdx') return 'markdown';
  if (ct.includes('ruby') || lang === 'rb' || lang === 'ruby' || ext === 'rb') return 'ruby';
  if (ct.includes('java') || lang === 'java' || ext === 'java') return 'java';
  if (ct.includes('scala') || lang === 'scala' || ext === 'scala') return 'scala';
  if (ct.includes('json') || lang === 'json' || ext === 'json') return 'json';
  if (ct.includes('yaml') || ct.includes('yml') || lang === 'yaml' || lang === 'yml' || ext === 'yaml' || ext === 'yml') return 'yaml';
  return 'text';
}

export default function Viewer({ content, contentType, filename, language, height = 420, className }: ViewerProps) {
  const kind = useMemo(() => detectType({ contentType, filename, language }), [contentType, filename, language]);

  const markdownHtml = useMemo(() => {
    if (kind !== 'markdown') return '';
    // Lightweight renderer with code hook for ruby/java/scala
    const renderer = new marked.Renderer();
    const origCode = renderer.code?.bind(renderer);
    renderer.code = (code: string, info: string | undefined) => {
      const lang = (info || '').split(/\s+/)[0]?.toLowerCase();
      if (lang === 'ruby' || lang === 'rb') {
        return `<pre class="code"><code>${simpleHighlight(code, 'ruby')}</code></pre>`;
      }
      if (lang === 'java') {
        return `<pre class="code"><code>${simpleHighlight(code, 'java')}</code></pre>`;
      }
      if (lang === 'scala') {
        return `<pre class="code"><code>${simpleHighlight(code, 'scala')}</code></pre>`;
      }
      if (lang === 'json') {
        return `<pre class="code"><code>${renderJsonHtml(code)}</code></pre>`;
      }
      if (lang === 'yaml' || lang === 'yml') {
        return `<pre class="code"><code>${renderYamlHtml(code)}</code></pre>`;
      }
      // default (no highlighting)
      const html = `<pre class="code"><code>${escapeHtml(code)}</code></pre>`;
      return html;
    };
    const origLink = renderer.link?.bind(renderer);
    renderer.link = (href: string | null, title: string | null, text: string) => {
      const h = href || '#';
      const t = title ? ` title="${escapeHtml(title)}"` : '';
      return `<a href="${escapeHtml(h)}"${t} target="_blank" rel="noreferrer noopener">${text}</a>`;
    };
    const raw = marked.parse(content, { renderer, breaks: true }) as string;
    return DOMPurify.sanitize(raw);
  }, [content, kind]);

  const codeHtml = useMemo(() => {
    if (kind === 'ruby') return simpleHighlight(content, 'ruby');
    if (kind === 'java') return simpleHighlight(content, 'java');
    if (kind === 'scala') return simpleHighlight(content, 'scala');
    return '';
  }, [content, kind]);

  // Render JSON with structured HTML, preserving indentation and coloring keys/values.
  const jsonHtml = useMemo(() => (kind === 'json' ? renderJsonHtml(content) : ''), [content, kind]);

  // YAML highlighter (regex-based, lightweight)
  const yamlHtml = useMemo(() => (kind === 'yaml' ? renderYamlHtml(content) : ''), [content, kind]);

  // Base styles and token palette (inspired by One Dark)
  const baseSx = {
    borderRadius: 1,
    border: '1px solid rgba(0,0,0,0.12)',
    overflow: 'auto',
    fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace',
    '& pre': { m: 0, p: 1.5 },
    '& code': { fontFamily: 'inherit' },
    '& .tok-kw': { color: '#c678dd' },
    '& .tok-str': { color: '#98c379' },
    '& .tok-com': { color: '#5c6370', fontStyle: 'italic' as const },
    '& .tok-num': { color: '#d19a66' },
    '& .tok-sym': { color: '#56b6c2' },
    '& .tok-var': { color: '#e06c75' },
    '& .tok-type': { color: '#61afef' },
    '& .tok-key': { color: '#61afef', fontWeight: 600 },
  } as const;

  if (kind === 'markdown') {
    return (
      <Box className={className} sx={{
        ...baseSx,
        fontFamily: 'system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, sans-serif',
        p: 2,
        height,
        '& h1, & h2, & h3': { mt: 1.2, mb: 0.6 },
        '& p': { my: 1 },
        '& pre': { backgroundColor: '#0f1320', color: '#e6e6e6', p: 1.25, borderRadius: 1 },
        '& a': { color: '#2d6cdf' },
        '& ul': { pl: 3 }
      }}>
        <div dangerouslySetInnerHTML={{ __html: markdownHtml }} />
      </Box>
    );
  }

  if (kind === 'ruby' || kind === 'java' || kind === 'scala') {
    return (
      <Box className={className} sx={{ ...baseSx, backgroundColor: '#0f1320', color: '#e6e6e6', height }}>
        <pre><code dangerouslySetInnerHTML={{ __html: codeHtml }} /></pre>
      </Box>
    );
  }

  if (kind === 'json') {
    return (
      <Box className={className} sx={{ ...baseSx, backgroundColor: '#0f1320', color: '#e6e6e6', height }}>
        <pre><code dangerouslySetInnerHTML={{ __html: jsonHtml }} /></pre>
      </Box>
    );
  }

  if (kind === 'yaml') {
    return (
      <Box className={className} sx={{ ...baseSx, backgroundColor: '#0f1320', color: '#e6e6e6', height }}>
        <pre><code dangerouslySetInnerHTML={{ __html: yamlHtml }} /></pre>
      </Box>
    );
  }

  // Text/plain default: black background, white text
  return (
    <Box className={className} sx={{ ...baseSx, backgroundColor: '#0b0c10', color: '#eaeef2', height }}>
      <pre><code>{content}</code></pre>
    </Box>
  );
}
