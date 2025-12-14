import React, { useEffect, useMemo, useRef } from 'react';
import Box from '@mui/material/Box';
import DOMPurify from 'dompurify';
import { marked } from 'marked';
import mermaid from 'mermaid';

let mermaidConfigured = false;

function ensureMermaidConfigured() {
  if (!mermaidConfigured) {
    mermaid.initialize({
      startOnLoad: false,
      securityLevel: 'loose',
      suppressErrorRendering: true,
      // @ts-ignore - errorHandler exists in v11
      errorHandler: () => { /* no-op: prevent overlay */ },
    } as any);
    mermaidConfigured = true;
  }
}

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

// Heuristic to detect likely-valid Mermaid diagrams to avoid noisy error overlays
function isLikelyMermaid(src: string): boolean {
  const s = (src || '').trim();
  if (!s) return false;
  const starters = [
    /^graph(\s+|$)/i,
    /^flowchart(\s+|$)/i,
    /^sequenceDiagram(\s+|$)/i,
    /^classDiagram(\s+|$)/i,
    /^stateDiagram(\-v2)?(\s+|$)/i,
    /^erDiagram(\s+|$)/i,
    /^journey(\s+|$)/i,
    /^gantt(\s+|$)/i,
    /^pie(\s+|$)/i,
    /^timeline(\s+|$)/i,
    /^gitGraph(\s+|$)/i,
    /^mindmap(\s+|$)/i,
    /^quadrantChart(\s+|$)/i,
    /^xychart\-beta(\s+|$)/i,
  ];
  return starters.some((re) => re.test(s));
}

function wrapToken(text: string, cls: string): string {
  return `<span class="${cls}">${escapeHtml(text)}</span>`;
}

function buildKeywordRegex(words: string[]): RegExp {
  const body = words.map(w => w.replace(/[-/\\^$*+?.()|[\]{}]/g, '\\$&')).join('|');
  return new RegExp(`\\b(?:${body})\\b`, 'g');
}

type HighlightLang = 'ruby' | 'java' | 'scala' | 'typescript' | 'python' | 'go';

// Very small, focused syntax highlighter for common languages.
// It is not exhaustive; tuned for readability of code snippets.
function simpleHighlight(code: string, lang: HighlightLang): string {
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

  // Block comments
  if (lang !== 'ruby' && lang !== 'python') {
    s = s.replace(/\/\*[\s\S]*?\*\//g, (m) => put(`<span class="tok-com">${escapeHtml(m)}</span>`));
  }
  // Line comments
  if (lang === 'ruby' || lang === 'python') {
    s = s.replace(/#.*/g, (m) => put(`<span class="tok-com">${escapeHtml(m)}</span>`));
  } else {
    s = s.replace(/\/\/.*$/gm, (m) => put(`<span class="tok-com">${escapeHtml(m)}</span>`));
  }

  // Template literals (JS/TS)
  if (lang === 'typescript') {
    s = s.replace(/`(?:\\.|[^`\\])*`/g, (m) => put(`<span class="tok-str">${escapeHtml(m)}</span>`));
  }

  // Triple-quoted strings (Python, Scala)
  if (lang === 'python' || lang === 'scala') {
    s = s.replace(/'''[\s\S]*?'''|"""[\s\S]*?"""/g, (m) => put(`<span class="tok-str">${escapeHtml(m)}</span>`));
  }

  // Strings (single, double)
  s = s.replace(/'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*"/g, (m) => put(`<span class="tok-str">${escapeHtml(m)}</span>`));

  // Numbers
  s = s.replace(/\b\d+(?:_\d+)*(?:\.\d+)?\b/g, (m) => wrapToken(m, 'tok-num'));

  // Symbols (Ruby)
  if (lang === 'ruby') {
    s = s.replace(/(?::)[a-zA-Z_]\w*/g, (m) => wrapToken(m, 'tok-sym'));
    s = s.replace(/[@$]{1,2}[a-zA-Z_]\w*/g, (m) => wrapToken(m, 'tok-var'));
  }

  // Decorators (Python)
  if (lang === 'python') {
    s = s.replace(/@[a-zA-Z_]\w*/g, (m) => wrapToken(m, 'tok-var'));
  }

  // Types: highlight Capitalized identifiers
  if (lang !== 'ruby' && lang !== 'python') {
    s = s.replace(/\b[A-Z][A-Za-z0-9_]*\b/g, (m) => wrapToken(m, 'tok-type'));
  }

  // Keywords
  const KEYWORDS: Record<HighlightLang, string[]> = {
    ruby: [
      'def','end','class','module','if','else','elsif','case','when','then','do','while','until','for','in','break','next','redo','retry','rescue','ensure','yield','return','self','nil','true','false','and','or','not','alias','undef','super','unless','BEGIN','END','require','include','extend'
    ],
    java: [
      'public','private','protected','class','interface','enum','static','final','void','int','long','short','double','float','boolean','char','byte','if','else','switch','case','default','for','while','do','return','try','catch','finally','throw','throws','new','this','super','extends','implements','import','package','synchronized','volatile','transient','abstract','native','strictfp','assert','instanceof'
    ],
    scala: [
      'def','val','var','lazy','type','class','object','trait','extends','with','new','if','else','match','case','for','while','do','yield','return','try','catch','finally','throw','import','package','implicit','given','using','end','enum','then','override','private','protected','final','abstract','sealed'
    ],
    typescript: [
      'const','let','var','function','class','interface','type','enum','if','else','switch','case','default','for','while','do','return','try','catch','finally','throw','new','this','super','extends','implements','import','export','from','as','async','await','yield','break','continue','typeof','instanceof','in','of','true','false','null','undefined','void','never','any','unknown','public','private','protected','static','readonly','abstract','declare','module','namespace','require'
    ],
    python: [
      'def','class','if','elif','else','for','while','try','except','finally','with','as','import','from','return','yield','raise','pass','break','continue','lambda','and','or','not','in','is','True','False','None','global','nonlocal','assert','async','await','self','cls'
    ],
    go: [
      'func','type','struct','interface','map','chan','if','else','switch','case','default','for','range','return','defer','go','select','break','continue','fallthrough','goto','package','import','const','var','true','false','nil','iota','make','new','len','cap','append','copy','delete','close','panic','recover'
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

type ViewerKind = 'markdown' | 'ruby' | 'java' | 'scala' | 'typescript' | 'python' | 'go' | 'json' | 'yaml' | 'text';

function detectType({ contentType, filename, language }: { contentType?: string; filename?: string; language?: string }): ViewerKind {
  const ct = (contentType || '').toLowerCase();
  const lang = (language || '').toLowerCase();
  const ext = (filename || '').split('.').pop()?.toLowerCase();
  if (ct.includes('markdown') || lang === 'md' || lang === 'markdown' || ext === 'md' || ext === 'mdx') return 'markdown';
  if (ct.includes('ruby') || lang === 'rb' || lang === 'ruby' || ext === 'rb') return 'ruby';
  if (ct.includes('java') || lang === 'java' || ext === 'java') return 'java';
  if (ct.includes('scala') || lang === 'scala' || ext === 'scala') return 'scala';
  if (ct.includes('typescript') || ct.includes('javascript') || lang === 'ts' || lang === 'tsx' || lang === 'js' || lang === 'jsx' || lang === 'typescript' || lang === 'javascript' || ext === 'ts' || ext === 'tsx' || ext === 'js' || ext === 'jsx' || ext === 'mjs' || ext === 'cjs') return 'typescript';
  if (ct.includes('python') || lang === 'py' || lang === 'python' || ext === 'py' || ext === 'pyw') return 'python';
  if (ct.includes('go') || lang === 'go' || lang === 'golang' || ext === 'go') return 'go';
  if (ct.includes('json') || lang === 'json' || ext === 'json') return 'json';
  if (ct.includes('yaml') || ct.includes('yml') || lang === 'yaml' || lang === 'yml' || ext === 'yaml' || ext === 'yml') return 'yaml';
  return 'text';
}

export default function Viewer({ content, contentType, filename, language, height = 420, className }: ViewerProps) {
  const kind = useMemo(() => detectType({ contentType, filename, language }), [contentType, filename, language]);
  const markdownRef = useRef<HTMLDivElement>(null);

  const markdownHtml = useMemo(() => {
    if (kind !== 'markdown') return '';
    // Preprocess: wrap loose Mermaid definitions (no code fences) into ```mermaid blocks
    function wrapLooseMermaid(src: string): string {
      const starters = [
        /^\s*graph(\s+|$)/i,
        /^\s*flowchart(\s+|$)/i,
        /^\s*sequenceDiagram(\s+|$)/i,
        /^\s*classDiagram(\s+|$)/i,
        /^\s*stateDiagram(\-v2)?(\s+|$)/i,
        /^\s*erDiagram(\s+|$)/i,
        /^\s*journey(\s+|$)/i,
        /^\s*gantt(\s+|$)/i,
        /^\s*pie(\s+|$)/i,
        /^\s*timeline(\s+|$)/i,
        /^\s*gitGraph(\s+|$)/i,
        /^\s*mindmap(\s+|$)/i,
        /^\s*quadrantChart(\s+|$)/i,
        /^\s*xychart\-beta(\s+|$)/i,
      ];
      const lines = src.split(/\r?\n/);
      const out: string[] = [];
      let i = 0;
      while (i < lines.length) {
        const line = lines[i];
        // If this line starts a fenced code block, just copy until it closes
        if (/^\s*```/.test(line)) {
          out.push(line);
          i++;
          while (i < lines.length && !/^\s*```\s*$/.test(lines[i])) {
            out.push(lines[i]);
            i++;
          }
          if (i < lines.length) out.push(lines[i]);
          i++;
          continue;
        }
        // Detect loose Mermaid start
        if (starters.some((re) => re.test(line))) {
          out.push('```mermaid');
          out.push(line);
          i++;
          // Collect lines until a clear section boundary:
          // - Markdown heading
          // - Fenced code start
          // - List item start
          // - A single-line section title ending with ':' (e.g., "Key ideas:")
          // Allow single blank lines inside diagrams.
          let blankStreak = 0;
          while (i < lines.length) {
            const l = lines[i];
            const trimmed = l.trim();
            const isFence = /^\s*```/.test(l);
            const isHeading = /^\s*#{1,6}\s/.test(l);
            const isList = /^\s*(?:[-*+]\s|\d+\.)/.test(l);
            const isSectionLabel = /^\s*[A-Za-z].*:\s*$/.test(l);
            if (isFence || isHeading || isList || isSectionLabel) break;
            out.push(l);
            if (trimmed === '') blankStreak++; else blankStreak = 0;
            // If we see two consecutive blank lines, assume the diagram ended
            if (blankStreak >= 2) { i++; break; }
            i++;
          }
          out.push('```');
          // Preserve a single blank line gap if present
          if (i < lines.length && lines[i].trim() === '') { out.push(''); i++; }
          continue;
        }
        out.push(line);
        i++;
      }
      return out.join('\n');
    }
    // Lightweight renderer with code hook for syntax highlighting
    const renderer = new marked.Renderer();
    // marked v12+ passes token object; v11 and below pass (code, info, escaped)
    renderer.code = function(this: marked.Renderer, codeOrToken: string | { text: string; lang?: string }, info?: string) {
      let code: string;
      let lang: string;
      if (typeof codeOrToken === 'object' && codeOrToken !== null) {
        // marked v12+ token object
        code = codeOrToken.text || '';
        lang = (codeOrToken.lang || '').split(/\s+/)[0]?.toLowerCase() || '';
      } else {
        // marked v11 and below
        code = codeOrToken as string;
        lang = (info || '').split(/\s+/)[0]?.toLowerCase() || '';
      }
      if (lang === 'mermaid') {
        if (isLikelyMermaid(code)) {
          // Use a data attribute to preserve the raw code for mermaid rendering
          return `<div class="mermaid" data-mermaid-src="${encodeURIComponent(code)}">${escapeHtml(code)}</div>`;
        }
        return `<pre class="code"><code>${escapeHtml(code)}</code></pre>`;
      }
      if (lang === 'ruby' || lang === 'rb') {
        return `<pre class="code"><code>${simpleHighlight(code, 'ruby')}</code></pre>`;
      }
      if (lang === 'java') {
        return `<pre class="code"><code>${simpleHighlight(code, 'java')}</code></pre>`;
      }
      if (lang === 'scala') {
        return `<pre class="code"><code>${simpleHighlight(code, 'scala')}</code></pre>`;
      }
      if (lang === 'typescript' || lang === 'ts' || lang === 'javascript' || lang === 'js' || lang === 'tsx' || lang === 'jsx') {
        return `<pre class="code"><code>${simpleHighlight(code, 'typescript')}</code></pre>`;
      }
      if (lang === 'python' || lang === 'py') {
        return `<pre class="code"><code>${simpleHighlight(code, 'python')}</code></pre>`;
      }
      if (lang === 'go' || lang === 'golang') {
        return `<pre class="code"><code>${simpleHighlight(code, 'go')}</code></pre>`;
      }
      if (lang === 'json') {
        return `<pre class="code"><code>${renderJsonHtml(code)}</code></pre>`;
      }
      if (lang === 'yaml' || lang === 'yml') {
        return `<pre class="code"><code>${renderYamlHtml(code)}</code></pre>`;
      }
      return `<pre class="code"><code>${escapeHtml(code)}</code></pre>`;
    };
    // marked v12+ passes token object for link as well
    renderer.link = function(this: marked.Renderer, hrefOrToken: string | { href: string; title?: string | null; text: string } | null, title?: string | null, text?: string) {
      let h: string;
      let t: string | null;
      let linkText: string;
      if (typeof hrefOrToken === 'object' && hrefOrToken !== null) {
        h = hrefOrToken.href || '#';
        t = hrefOrToken.title || null;
        linkText = hrefOrToken.text || '';
      } else {
        h = hrefOrToken || '#';
        t = title || null;
        linkText = text || '';
      }
      const titleAttr = t ? ` title="${escapeHtml(t)}"` : '';
      return `<a href="${escapeHtml(h)}"${titleAttr} target="_blank" rel="noreferrer noopener">${linkText}</a>`;
    };
    const preprocessed = wrapLooseMermaid(content);
    const raw = marked.parse(preprocessed, { renderer, breaks: true }) as string;
    // Configure DOMPurify to allow data attributes needed for mermaid
    return DOMPurify.sanitize(raw, { ADD_ATTR: ['data-mermaid-src'] });
  }, [content, kind]);

  useEffect(() => {
    if (kind !== 'markdown') return;
    const root = markdownRef.current;
    if (!root) return;
    const nodes = root.querySelectorAll<HTMLElement>('.mermaid');
    if (!nodes.length) return;
    ensureMermaidConfigured();
    // Render each diagram individually to prevent Mermaid's overlay injection
    const promises: Promise<void>[] = [];
    nodes.forEach((el, i) => {
      // Get source from data attribute (URL-encoded) or fall back to textContent
      const encodedSrc = el.getAttribute('data-mermaid-src');
      const src = encodedSrc ? decodeURIComponent(encodedSrc) : (el.textContent || '');
      const fallbackToCode = () => {
        const pre = document.createElement('pre');
        pre.className = 'code';
        const codeEl = document.createElement('code');
        codeEl.textContent = src;
        pre.appendChild(codeEl);
        el.replaceWith(pre);
      };
      if (!isLikelyMermaid(src)) {
        fallbackToCode();
        return;
      }
      // Try render off-DOM; on success, replace innerHTML with SVG
      const id = `mmd-${Date.now()}-${i}`;
      const p = (async () => {
        try {
          // @ts-ignore - types for render may vary by version
          const { svg } = await mermaid.render(id, src);
          el.innerHTML = svg;
        } catch (err) {
          console.warn('Mermaid render failed:', err);
          fallbackToCode();
        }
      })();
      promises.push(p);
    });
    // Swallow any unhandled errors
    void Promise.all(promises).catch(() => {});
  }, [kind, markdownHtml]);

  const codeHtml = useMemo(() => {
    if (kind === 'ruby') return simpleHighlight(content, 'ruby');
    if (kind === 'java') return simpleHighlight(content, 'java');
    if (kind === 'scala') return simpleHighlight(content, 'scala');
    if (kind === 'typescript') return simpleHighlight(content, 'typescript');
    if (kind === 'python') return simpleHighlight(content, 'python');
    if (kind === 'go') return simpleHighlight(content, 'go');
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
    fontSize: 11,
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
        '& ul': { pl: 3 },
        '& .mermaid': { my: 2, '& svg': { maxWidth: '100%' } }
      }}>
        <div ref={markdownRef} dangerouslySetInnerHTML={{ __html: markdownHtml }} />
      </Box>
    );
  }

  if (kind === 'ruby' || kind === 'java' || kind === 'scala' || kind === 'typescript' || kind === 'python' || kind === 'go') {
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
