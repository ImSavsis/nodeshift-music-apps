import { invoke as tauriInvoke } from '@tauri-apps/api/core';
import { listen as tauriListen } from '@tauri-apps/api/event';
import { getCurrentWebview } from '@tauri-apps/api/webview';

export const isTauri = typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;

export type Unlisten = () => void;

export type DropEvent =
  | { type: 'enter'; paths: string[] }
  | { type: 'over' }
  | { type: 'drop'; paths: string[] }
  | { type: 'leave' };

let mockModule: Promise<typeof import('./mock')> | null = null;

function loadMock() {
  if (!mockModule) mockModule = import('./mock');
  return mockModule;
}

export async function invoke<T>(command: string, args?: Record<string, unknown>): Promise<T> {
  if (isTauri) return tauriInvoke<T>(command, args);
  const mock = await loadMock();
  return mock.handle<T>(command, args ?? {});
}

export async function listen<T>(event: string, handler: (payload: T) => void): Promise<Unlisten> {
  if (isTauri) return tauriListen<T>(event, (message) => handler(message.payload));
  const mock = await loadMock();
  return mock.subscribe<T>(event, handler);
}

export async function onFileDrop(handler: (event: DropEvent) => void): Promise<Unlisten> {
  if (!isTauri) return () => {};
  return getCurrentWebview().onDragDropEvent((message) => {
    const payload = message.payload;
    if (payload.type === 'enter') handler({ type: 'enter', paths: payload.paths });
    else if (payload.type === 'drop') handler({ type: 'drop', paths: payload.paths });
    else if (payload.type === 'over') handler({ type: 'over' });
    else handler({ type: 'leave' });
  });
}

const AUDIO_EXTENSIONS = ['mp3', 'flac', 'wav', 'ogg', 'oga', 'opus', 'm4a', 'aac', 'aiff', 'aif', 'wma', 'ape', 'wv', 'alac'];
const ARCHIVE_EXTENSIONS = ['zip', '7z', 'tar', 'tgz', 'gz'];

export async function pickPaths(kind: 'files' | 'folder'): Promise<string[]> {
  if (!isTauri) {
    const mock = await loadMock();
    return mock.pick(kind);
  }
  const { open } = await import('@tauri-apps/plugin-dialog');
  const picked =
    kind === 'folder'
      ? await open({ directory: true, multiple: true })
      : await open({
          multiple: true,
          directory: false,
          filters: [
            { name: 'Музыка и архивы', extensions: [...AUDIO_EXTENSIONS, ...ARCHIVE_EXTENSIONS] },
            { name: 'Все файлы', extensions: ['*'] }
          ]
        });
  if (!picked) return [];
  return Array.isArray(picked) ? picked : [picked];
}

export async function openExternal(url: string): Promise<void> {
  if (!isTauri) {
    window.open(url, '_blank', 'noopener');
    return;
  }
  const { openUrl } = await import('@tauri-apps/plugin-opener');
  await openUrl(url);
}
