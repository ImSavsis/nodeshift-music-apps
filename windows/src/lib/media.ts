import { mockCoverUrl, mockTrackUrl } from './mockMedia';
import type { Track } from './types';

const MOCK_BASE = 'mock://media';

let base = '';

export function setMediaBase(value: string) {
  base = value;
}

function isMock(): boolean {
  return base === MOCK_BASE;
}

const SITE_MEDIA = 'https://burmalda.savsis.xyz';
const REMOTE_PREFIX = 'remote:';

export function isRemoteCover(name: string): boolean {
  return name.startsWith(REMOTE_PREFIX);
}

function remoteCover(name: string, full: boolean): string {
  const file = name.slice(REMOTE_PREFIX.length);
  if (full) return `${SITE_MEDIA}/covers/${encodeURIComponent(file)}`;
  const dot = file.lastIndexOf('.');
  const stem = dot > 0 ? file.slice(0, dot) : file;
  return `${SITE_MEDIA}/thumbs/${encodeURIComponent(stem)}.webp`;
}

export const media = {
  track(track: Track): string {
    if (track.streamUrl) {
      if (track.streamUrl.startsWith('mock:')) return mockTrackUrl(track.id, track.durationMs);
      if (track.siteId && base && !isMock()) return `${base}/site/${encodeURIComponent(track.siteId)}`;
      return track.streamUrl;
    }
    if (isMock()) return mockTrackUrl(track.id, track.durationMs);
    return `${base}/track/${encodeURIComponent(track.id)}`;
  },
  cover(name: string, full = false): string {
    if (isMock()) return mockCoverUrl(name);
    if (isRemoteCover(name)) return remoteCover(name, full);
    return `${base}/cover/${encodeURIComponent(name)}`;
  },
  motion(name: string): string {
    return `${base}/motion/${encodeURIComponent(name)}`;
  }
};

export { MOCK_BASE };
