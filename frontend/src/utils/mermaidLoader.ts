const MERMAID_CDN = 'https://cdn.jsdelivr.net/npm/mermaid@11.4.0/dist/mermaid.esm.min.mjs';

const MERMAID_CONFIG = {
  startOnLoad: false,
  theme: 'default',
  flowchart: { useMaxWidth: true, htmlLabels: true, curve: 'basis' },
  securityLevel: 'loose'
};

declare global {
  interface Window {
    __savantMermaid?: any;
  }
}

let localInstance: any = null;
let cdnInstance: any = null;

async function importMermaid(forceCdn: boolean) {
  if (forceCdn) {
    // Vite cannot statically analyze a fully dynamic import path; suppress with @vite-ignore.
    // eslint-disable-next-line @typescript-eslint/ban-ts-comment
    // @ts-ignore
    return import(/* @vite-ignore */ MERMAID_CDN);
  }
  return import('mermaid');
}

function configureMermaid(instance: any) {
  instance.initialize(MERMAID_CONFIG);
  if (typeof window !== 'undefined') {
    window.__savantMermaid = instance;
  }
}

export async function getMermaidInstance(forceCdn = false) {
  if (forceCdn && cdnInstance) return cdnInstance;
  if (!forceCdn && localInstance) return localInstance;
  let module: any;
  try {
    module = await importMermaid(forceCdn);
  } catch (error) {
    if (!forceCdn) {
      return getMermaidInstance(true);
    }
    throw error;
  }

  const instance = (module && (module.default || module)) as any;
  configureMermaid(instance);
  if (forceCdn) {
    cdnInstance = instance;
  } else {
    localInstance = instance;
  }
  return instance;
}

export function isMermaidDynamicImportError(error: unknown) {
  const message = typeof error === 'string' ? error : (error as any)?.message;
  return typeof message === 'string' && message.includes('Failed to fetch dynamically imported module');
}
