export interface Track {
  id: string;
  title: string;
  artist: string;
  album: string | null;
  albumArtist: string | null;
  trackNumber: number | null;
  discNumber: number | null;
  year: number | null;
  genre: string | null;
  durationMs: number;
  format: string;
  bitrateKbps: number | null;
  sampleRate: number | null;
  bitDepth: number | null;
  fileName: string;
  fileSize: number;
  fileHash: string | null;
  coverName: string | null;
  motionName: string | null;
  motion3x4Name: string | null;
  isFavorite: boolean;
  playCount: number;
  lastPlayedAt: number | null;
  addedAt: number;
  siteId: string | null;
  bpm: number | null;
  palette: string | null;
  lyricsKind: string | null;
  lyricsSource: string | null;
  streamUrl: string | null;
}

export interface Playlist {
  id: string;
  name: string;
  coverName: string | null;
  siteId: string | null;
  createdAt: number;
  trackIds: string[];
}

export type ItemState =
  | { kind: 'waiting' }
  | { kind: 'working'; text: string }
  | { kind: 'done' }
  | { kind: 'duplicate'; existingId: string; dupKind: string; betterQuality: boolean }
  | { kind: 'skipped'; text: string }
  | { kind: 'failed'; text: string };

export interface ImportItem {
  id: string;
  name: string;
  state: ItemState;
  title: string | null;
  artist: string | null;
  coverName: string | null;
  trackId: string | null;
}

export interface ImportSummary {
  added: number;
  duplicates: number;
  failed: number;
  ignored: number;
}

export interface ImportSnapshot {
  items: ImportItem[];
  summary: ImportSummary;
  running: boolean;
  pendingDuplicates: number;
}

export type Decision = 'skip' | 'keepBoth' | 'replace';

export interface SiteUser {
  id: string;
  email: string | null;
  username: string | null;
  handle: string | null;
  avatarUrl: string | null;
}

export type SyncPhase =
  | { phase: 'idle' }
  | { phase: 'loading' }
  | { phase: 'downloading' }
  | { phase: 'done' }
  | { phase: 'failed'; text: string };

export interface ListState {
  id: string;
  name: string;
  total: number;
  done: number;
  phase: SyncPhase;
}

export interface SiteSnapshot {
  user: SiteUser | null;
  busy: boolean;
  lastError: string | null;
  favorites: ListState;
  playlists: ListState[];
  refreshing: boolean;
  needsLogin: boolean;
  lossless: boolean;
}

export interface LyricWord {
  text: string;
  start: number;
  end: number;
}

export interface LyricLine {
  time: number;
  text: string;
  words: LyricWord[] | null;
}

export type LyricsKind = 'word' | 'line' | 'plain' | 'none';

export type Lyrics =
  | { state: 'synced'; lines: LyricLine[]; source: string | null; kind: LyricsKind }
  | { state: 'plain'; text: string; source: string | null }
  | { state: 'none' };

export interface AppInfo {
  version: string;
  build: number;
  mediaBase: string;
  muted: boolean;
}

export interface UpdateManifest {
  platform: string;
  version: string;
  build: number;
  file: string;
  size: number;
  sha256: string;
  notes: string | null;
  builtAt: string | null;
  available: boolean | null;
}

export type RepeatMode = 'off' | 'all' | 'one';
