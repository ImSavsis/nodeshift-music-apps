import { usePlayerStore } from '../store/player';
import { invoke, isTauri } from './tauri';

const COVERS = 'https://burmalda.savsis.xyz/covers/';

function deviceId(): string {
  try {
    const saved = localStorage.getItem('nsm_device_id');
    if (saved) return saved;
    const fresh = crypto.randomUUID();
    localStorage.setItem('nsm_device_id', fresh);
    return fresh;
  } catch {
    return 'windows';
  }
}

function coverFile(name: string | null): string | null {
  if (!name) return null;
  if (name.startsWith('remote:')) return name.slice(7);
  if (name.startsWith('site-')) return name.slice(5);
  return null;
}

function publish(body: Record<string, unknown>) {
  invoke('presence_publish', { body }).catch(() => undefined);
}

function send() {
  const state = usePlayerStore.getState();
  const track = state.currentTrack;
  if (!track) {
    publish({ stop: true });
    return;
  }
  const file = coverFile(track.coverName);
  publish({
    device: deviceId(),
    platform: 'win',
    playing: state.isPlaying,
    title: track.title,
    artist: track.artist,
    album: track.album ?? '',
    position_ms: Math.round(state.currentTime * 1000),
    duration_ms: Math.round((state.duration > 0 ? state.duration : track.durationMs / 1000) * 1000),
    cover: file ? `${COVERS}${encodeURIComponent(file)}` : undefined,
    site_id: track.siteId ?? undefined
  });
}

export function startPresence() {
  if (!isTauri) return;
  let heartbeat: number | undefined;
  const sync = () => {
    send();
    window.clearInterval(heartbeat);
    heartbeat = undefined;
    if (usePlayerStore.getState().isPlaying) heartbeat = window.setInterval(send, 15000);
  };
  usePlayerStore.subscribe((state, previous) => {
    if (state.currentTrack?.id !== previous.currentTrack?.id || state.isPlaying !== previous.isPlaying || state.seekToken !== previous.seekToken) {
      sync();
    }
  });
}
