export type AppEvent =
  | { type: 'error'; message: string; detail?: unknown };

type Listener = (ev: AppEvent) => void;

const listeners = new Set<Listener>();

export function onAppEvent(listener: Listener): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function emitAppEvent(ev: AppEvent): void {
  listeners.forEach((fn) => {
    try { fn(ev); } catch { /* ignore */ }
  });
}

