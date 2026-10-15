import { mockPalette } from './mockMedia';
import { MOCK_BASE } from './media';
import type {
  Decision,
  ImportItem,
  ImportSnapshot,
  LyricLine,
  Lyrics,
  Playlist,
  SiteSnapshot,
  Track,
  UpdateManifest
} from './types';

type Handler = (payload: never) => void;

const listeners = new Map<string, Set<Handler>>();

export function subscribe<T>(event: string, handler: (payload: T) => void): () => void {
  const set = listeners.get(event) ?? new Set<Handler>();
  set.add(handler as Handler);
  listeners.set(event, set);
  return () => {
    set.delete(handler as Handler);
  };
}

function emit(event: string, payload: unknown = null) {
  listeners.get(event)?.forEach((handler) => (handler as (value: unknown) => void)(payload));
}

interface AlbumSpec {
  artist: string;
  album: string;
  year: number;
  format: string;
  tracks: Array<[string, number]>;
}

const CATALOG: AlbumSpec[] = [
  {
    artist: 'Night Drive',
    album: 'Неоновый город',
    year: 2023,
    format: 'flac',
    tracks: [
      ['Первый свет', 214],
      ['Дорога домой', 187],
      ['Стекло', 243],
      ['Полночь в метро', 201],
      ['Эхо', 176]
    ]
  },
  {
    artist: 'Lumen',
    album: 'Glass Hours',
    year: 2022,
    format: 'flac',
    tracks: [
      ['Afterglow', 232],
      ['Paper Moons', 198],
      ['Static Bloom', 255],
      ['Low Tide', 207]
    ]
  },
  {
    artist: 'Кристалл',
    album: 'Грани',
    year: 2024,
    format: 'mp3',
    tracks: [
      ['Грань', 189],
      ['Холодный огонь', 224],
      ['Север', 171],
      ['Отражение', 236],
      ['Снег на проводах', 203]
    ]
  },
  {
    artist: 'Voxel',
    album: 'Pixel Rain',
    year: 2021,
    format: 'mp3',
    tracks: [
      ['Boot Sequence', 162],
      ['Pixel Rain', 219],
      ['Overclock', 196],
      ['Dial-up Dreams', 244]
    ]
  },
  {
    artist: 'Мария Ветер',
    album: 'Тихие дворы',
    year: 2020,
    format: 'flac',
    tracks: [
      ['Тихие дворы', 258],
      ['Июльский дождь', 213],
      ['Чай на подоконнике', 186],
      ['Последний трамвай', 231]
    ]
  },
  {
    artist: 'Afterhours',
    album: 'Sundown Club',
    year: 2019,
    format: 'wav',
    tracks: [
      ['Sundown', 247],
      ['Velvet', 205],
      ['Room 404', 183]
    ]
  }
];

function slug(text: string): string {
  return text.toLowerCase().replace(/[^a-zа-я0-9]+/giu, '-');
}

function buildTracks(): Track[] {
  const now = Date.now();
  const list: Track[] = [];
  let counter = 0;
  for (const spec of CATALOG) {
    spec.tracks.forEach(([title, seconds], index) => {
      counter += 1;
      list.push({
        id: `t${counter}`,
        title,
        artist: spec.artist,
        album: spec.album,
        albumArtist: spec.artist,
        trackNumber: index + 1,
        discNumber: 1,
        year: spec.year,
        genre: null,
        durationMs: seconds * 1000,
        format: spec.format,
        bitrateKbps: spec.format === 'mp3' ? 320 : null,
        sampleRate: 44100,
        bitDepth: spec.format === 'mp3' ? null : 16,
        fileName: `${slug(`${spec.artist}-${title}`)}.${spec.format}`,
        fileSize: seconds * (spec.format === 'mp3' ? 40000 : 160000),
        fileHash: `h${counter}`,
        coverName: `${slug(spec.album)}.jpg`,
        motionName: null,
        motion3x4Name: null,
        isFavorite: counter % 4 === 0,
        playCount: (counter * 7) % 23,
        lastPlayedAt: counter % 3 === 0 ? now - counter * 3_600_000 : null,
        addedAt: now - counter * 86_400_000,
        siteId: null,
        bpm: null,
        palette: null,
        lyricsKind: null,
        lyricsSource: null,
        streamUrl: null
      });
    });
  }
  return list;
}

let tracks: Track[] = buildTracks();

const SITE_TITLES = [
  'Ночной автобус', 'Letters From Mars', 'Тёплый дождь', 'Glass Animals Run', 'Последний вагон', 'Neon Prayer', 'Север', 'Paper Planes',
  'Эхо в метро', 'Slow Burn', 'Белый шум', 'Midnight Radio', 'Город спит', 'Afterglow Club', 'Свет в окне', 'Static Hearts',
  'Дальний свет', 'Cold Brew', 'Пустые улицы', 'Satellite'
];
const SITE_ARTISTS = ['Night Drive', 'Lumen', 'Кристалл', 'Voxel', 'Мария Ветер', 'Afterhours', 'Скриптонит Jr.', 'Hollow Sun'];
const SITE_FORMATS = ['flac', 'mp3', 'mp3', 'flac', 'mp3'];

function buildCatalog(): Track[] {
  const now = Date.now();
  return Array.from({ length: 96 }, (_, index) => {
    const number = index + 1;
    const title = `${SITE_TITLES[index % SITE_TITLES.length]}${index >= SITE_TITLES.length ? ` ${Math.floor(index / SITE_TITLES.length) + 1}` : ''}`;
    const artist = SITE_ARTISTS[(index * 3) % SITE_ARTISTS.length];
    const seconds = 150 + ((index * 37) % 140);
    return {
      id: `site:${number}`,
      title,
      artist,
      album: null,
      albumArtist: null,
      trackNumber: null,
      discNumber: null,
      year: null,
      genre: null,
      durationMs: seconds * 1000,
      format: SITE_FORMATS[index % SITE_FORMATS.length],
      bitrateKbps: null,
      sampleRate: null,
      bitDepth: null,
      fileName: '',
      fileSize: 0,
      fileHash: null,
      coverName: `remote:${slug(`${artist}-${index % 7}`)}.jpg`,
      motionName: null,
      motion3x4Name: null,
      isFavorite: false,
      playCount: (number * 13) % 97,
      lastPlayedAt: null,
      addedAt: now - number * 3_600_000,
      siteId: String(number),
      bpm: null,
      palette: null,
      lyricsKind: null,
      lyricsSource: null,
      streamUrl: `mock:${number}`
    };
  });
}

const siteCatalog: Track[] = buildCatalog();
let siteLikes = new Set<string>(['3', '8', '21']);

function catalogSlice(args: Record<string, unknown>): { tracks: Track[]; count: number } {
  const search = String(args.search ?? '').toLowerCase();
  const format = args.format ? String(args.format) : null;
  const sort = String(args.sort ?? 'new');
  const limit = Number(args.limit ?? 30);
  const offset = Number(args.offset ?? 0);
  let list = siteCatalog.filter((track) => (!format || track.format === format) && (!search || `${track.title} ${track.artist}`.toLowerCase().includes(search)));
  if (sort === 'popular') list = [...list].sort((a, b) => b.playCount - a.playCount);
  else if (sort === 'title') list = [...list].sort((a, b) => a.title.localeCompare(b.title, 'ru'));
  const page = list.slice(offset, offset + limit);
  return { tracks: page, count: page.length };
}

let playlists: Playlist[] = [
  { id: 'p1', name: 'Для дороги', coverName: null, siteId: null, createdAt: Date.now() - 9e8, trackIds: ['t1', 't6', 't10', 't14', 't19'] },
  { id: 'p2', name: 'Вечер', coverName: null, siteId: null, createdAt: Date.now() - 5e8, trackIds: ['t3', 't11', 't17'] },
  { id: 'p3', name: 'Пустой плейлист', coverName: null, siteId: null, createdAt: Date.now() - 1e8, trackIds: [] }
];

const VERSES = [
  'Город засыпает в огнях',
  'Ты идёшь по мокрым улицам',
  'Свет фонарей ложится на стекло',
  'Я слышу эхо твоих шагов',
  'Мы так долго искали дорогу домой',
  'Ночь не спрашивает, кто мы такие',
  'Время течёт между пальцев',
  'И каждый звук становится светом',
  'Пусть этот вечер не заканчивается',
  'Мы остаёмся там, где музыка',
  'Тише, только слушай',
  'Всё, что было, остаётся с нами',
  'Новый день начинается с тишины',
  'Мы снова встретимся у края неба'
];

function buildLyrics(track: Track): Lyrics {
  const variant = Number(track.id.slice(1)) % 5;
  if (variant === 4 || variant === 0) return { state: 'none' };
  if (variant === 3) return { state: 'plain', text: VERSES.slice(0, 8).join('\n') + '\n\n' + VERSES.slice(8).join('\n'), source: 'lrclib-verified' };
  const total = track.durationMs / 1000;
  const start = 9;
  const step = Math.max(3.4, (total - start - 12) / VERSES.length);
  const lines: LyricLine[] = VERSES.map((text, index) => {
    const time = start + index * step;
    const parts = text.split(' ');
    const words =
      variant === 1
        ? parts.map((part, wordIndex) => {
            const from = time + (wordIndex / parts.length) * (step * 0.86);
            const to = time + ((wordIndex + 1) / parts.length) * (step * 0.86);
            return { text: wordIndex < parts.length - 1 ? `${part} ` : part, start: from, end: to };
          })
        : null;
    return { time, text, words };
  });
  return { state: 'synced', lines, source: variant === 1 ? 'lrclib-verified' : 'embedded', kind: variant === 1 ? 'word' : 'line' };
}

let importSnapshot: ImportSnapshot = { items: [], summary: { added: 0, duplicates: 0, failed: 0, ignored: 0 }, running: false, pendingDuplicates: 0 };
let importTimers: number[] = [];

function recount() {
  const summary = { added: 0, duplicates: 0, failed: 0, ignored: importSnapshot.summary.ignored };
  let pending = 0;
  for (const item of importSnapshot.items) {
    if (item.state.kind === 'done') summary.added += 1;
    else if (item.state.kind === 'failed') summary.failed += 1;
    else if (item.state.kind === 'skipped') summary.duplicates += 1;
    else if (item.state.kind === 'duplicate') {
      summary.duplicates += 1;
      pending += 1;
    }
  }
  importSnapshot = { ...importSnapshot, summary, pendingDuplicates: pending };
}

function setItem(id: string, patch: Partial<ImportItem>) {
  importSnapshot = { ...importSnapshot, items: importSnapshot.items.map((item) => (item.id === id ? { ...item, ...patch } : item)) };
  recount();
  emit('nsm:import');
}

function parseName(name: string): { title: string; artist: string | null } {
  const stripped = name.replace(/\.[a-z0-9]+$/i, '');
  const match = /^\s*\d+\s*[-.]\s*(.+?)\s+-\s+(.+)$/.exec(stripped);
  if (match) return { artist: match[1], title: match[2] };
  const two = /^(.+?)\s+-\s+(.+)$/.exec(stripped);
  if (two) return { artist: two[1], title: two[2] };
  return { artist: null, title: stripped.replace(/^\d+\s*[-.]\s*/, '') };
}

function runImport(paths: string[]) {
  const expanded = paths.flatMap((path) => (/\.[a-z0-9]{2,4}$/i.test(path) ? [path] : [`${path}\\01 - Lumen - Afterglow.flac`, `${path}\\02 - Lumen - Paper Moons.flac`, `${path}\\03 - Lumen - Static Bloom.flac`]));
  const baseId = Date.now();
  const fresh: ImportItem[] = expanded.map((path, index) => ({
    id: `i${baseId}-${index}`,
    name: path.split(/[\\/]/).pop() ?? path,
    state: { kind: 'waiting' },
    title: null,
    artist: null,
    coverName: null,
    trackId: null
  }));
  importSnapshot = { ...importSnapshot, items: [...importSnapshot.items, ...fresh], running: true };
  recount();
  emit('nsm:import');
  fresh.forEach((item, index) => {
    const delay = 500 + index * 900;
    const parsed = parseName(item.name);
    importTimers.push(window.setTimeout(() => setItem(item.id, { state: { kind: 'working', text: 'Читаем теги' }, title: parsed.title, artist: parsed.artist }), delay));
    importTimers.push(window.setTimeout(() => setItem(item.id, { state: { kind: 'working', text: 'Ищем обложку и альбом' } }), delay + 450));
    importTimers.push(
      window.setTimeout(() => {
        if (item.name.toLowerCase().includes('broken')) {
          setItem(item.id, { state: { kind: 'failed', text: 'Не удалось прочитать файл' } });
        } else if (index === 1 && fresh.length > 2) {
          setItem(item.id, { state: { kind: 'duplicate', existingId: 't2', dupKind: 'sameTrack', betterQuality: false }, coverName: 'glass-hours.jpg' });
        } else {
          setItem(item.id, { state: { kind: 'done' }, coverName: 'glass-hours.jpg' });
          emit('nsm:library');
        }
      }, delay + 1000)
    );
  });
  const last = 500 + (fresh.length - 1) * 900 + 1100;
  importTimers.push(
    window.setTimeout(() => {
      importSnapshot = { ...importSnapshot, running: false };
      emit('nsm:import');
    }, last)
  );
}

let site: SiteSnapshot = {
  user: null,
  busy: false,
  lastError: null,
  favorites: { id: 'favorites', name: 'Понравившиеся', total: 0, done: 0, phase: { phase: 'idle' } },
  playlists: [],
  refreshing: false,
  needsLogin: false,
  lossless: true
};

function patchSite(patch: Partial<SiteSnapshot>) {
  site = { ...site, ...patch };
  emit('nsm:site');
}

function runDownload(listId: string) {
  const isFavorites = listId === 'favorites';
  const total = isFavorites ? site.favorites.total : site.playlists.find((list) => list.id === listId)?.total ?? 0;
  let done = 0;
  const apply = (phase: 'downloading' | 'done') => {
    if (isFavorites) {
      patchSite({ busy: phase === 'downloading', favorites: { ...site.favorites, done, phase: { phase } } });
    } else {
      patchSite({ busy: phase === 'downloading', playlists: site.playlists.map((list) => (list.id === listId ? { ...list, done, phase: { phase } } : list)) });
    }
  };
  apply('downloading');
  const timer = window.setInterval(() => {
    done = Math.min(total, done + 2);
    if (done >= total) {
      window.clearInterval(timer);
      apply('done');
    } else {
      apply('downloading');
    }
  }, 350);
}

function login() {
  patchSite({ busy: true });
  window.setTimeout(() => {
    patchSite({
      busy: false,
      user: { id: '1', email: 'dev@savsis.xyz', username: 'savsis', handle: 'savsis', avatarUrl: null },
      favorites: { id: 'favorites', name: 'Понравившиеся', total: 14, done: 0, phase: { phase: 'idle' } },
      playlists: [
        { id: 's1', name: 'Ночная трасса', total: 9, done: 0, phase: { phase: 'idle' } },
        { id: 's2', name: 'Спокойное', total: 21, done: 0, phase: { phase: 'idle' } }
      ]
    });
    emit('nsm:toast', 'Вы вошли как savsis');
  }, 1200);
}

export async function pick(kind: 'files' | 'folder'): Promise<string[]> {
  if (kind === 'folder') return ['C:\\Music\\Lumen - Glass Hours'];
  return [
    'C:\\Music\\09 - 2pac - Ratha Be Ya Nigga.flac',
    'C:\\Music\\02 - Lumen - Paper Moons.flac',
    'C:\\Music\\Мария Ветер - Июльский дождь.mp3',
    'C:\\Music\\broken-file.mp3'
  ];
}

function nextId(prefix: string): string {
  return `${prefix}${Date.now().toString(36)}${Math.floor(Math.random() * 1000).toString(36)}`;
}

function clone<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

export async function handle<T>(command: string, args: Record<string, unknown>): Promise<T> {
  const result = await dispatch(command, args);
  return result as T;
}

async function dispatch(command: string, args: Record<string, unknown>): Promise<unknown> {
  switch (command) {
    case 'app_info':
      return { version: '0.1.0', build: 1, mediaBase: MOCK_BASE, muted: true };
    case 'library_all':
      return clone(tracks);
    case 'playlists_all':
      return clone(playlists);
    case 'track_favorite': {
      const id = String(args.id);
      tracks = tracks.map((track) => (track.id === id ? { ...track, isFavorite: Boolean(args.value) } : track));
      emit('nsm:library');
      return null;
    }
    case 'track_played': {
      const id = String(args.id);
      tracks = tracks.map((track) => (track.id === id ? { ...track, playCount: track.playCount + 1, lastPlayedAt: Date.now() } : track));
      return null;
    }
    case 'track_delete': {
      const id = String(args.id);
      tracks = tracks.filter((track) => track.id !== id);
      playlists = playlists.map((list) => ({ ...list, trackIds: list.trackIds.filter((item) => item !== id) }));
      emit('nsm:library');
      return null;
    }
    case 'track_update': {
      const id = String(args.id);
      let updated: Track | null = null;
      tracks = tracks.map((track) => {
        if (track.id !== id) return track;
        updated = {
          ...track,
          title: String(args.title),
          artist: String(args.artist),
          album: (args.album as string | null) ?? null,
          trackNumber: (args.trackNumber as number | null) ?? null
        };
        return updated;
      });
      emit('nsm:library');
      return clone(updated);
    }
    case 'playlist_create': {
      const created: Playlist = { id: nextId('p'), name: String(args.name), coverName: null, siteId: null, createdAt: Date.now(), trackIds: [] };
      playlists = [...playlists, created];
      emit('nsm:library');
      return clone(created);
    }
    case 'playlist_add': {
      const listId = String(args.playlistId);
      const trackId = String(args.trackId);
      playlists = playlists.map((list) => (list.id === listId && !list.trackIds.includes(trackId) ? { ...list, trackIds: [...list.trackIds, trackId] } : list));
      emit('nsm:library');
      return null;
    }
    case 'playlist_remove': {
      const listId = String(args.playlistId);
      const trackId = String(args.trackId);
      playlists = playlists.map((list) => (list.id === listId ? { ...list, trackIds: list.trackIds.filter((item) => item !== trackId) } : list));
      emit('nsm:library');
      return null;
    }
    case 'playlist_rename': {
      const listId = String(args.playlistId);
      playlists = playlists.map((list) => (list.id === listId ? { ...list, name: String(args.name) } : list));
      emit('nsm:library');
      return null;
    }
    case 'playlist_delete': {
      const listId = String(args.playlistId);
      playlists = playlists.filter((list) => list.id !== listId);
      emit('nsm:library');
      return null;
    }
    case 'import_start':
      runImport(args.paths as string[]);
      return null;
    case 'import_snapshot':
      return clone(importSnapshot);
    case 'import_decide': {
      const id = String(args.id);
      const decision = args.decision as Decision;
      setItem(id, decision === 'skip' ? { state: { kind: 'skipped', text: 'Пропущено, трек уже есть' } } : { state: { kind: 'done' } });
      if (decision !== 'skip') emit('nsm:library');
      return null;
    }
    case 'import_skip_all': {
      importSnapshot = {
        ...importSnapshot,
        items: importSnapshot.items.map((item) => (item.state.kind === 'duplicate' ? { ...item, state: { kind: 'skipped', text: 'Пропущено, трек уже есть' } } : item))
      };
      recount();
      emit('nsm:import');
      return null;
    }
    case 'import_clear':
      importTimers.forEach((timer) => window.clearTimeout(timer));
      importTimers = [];
      importSnapshot = { items: [], summary: { added: 0, duplicates: 0, failed: 0, ignored: 0 }, running: false, pendingDuplicates: 0 };
      emit('nsm:import');
      return null;
    case 'lyrics_get': {
      const track = tracks.find((item) => item.id === String(args.trackId));
      await new Promise((resolve) => window.setTimeout(resolve, 380));
      return track ? buildLyrics(track) : { state: 'none' };
    }
    case 'cover_palette':
      return mockPalette(String(args.name));
    case 'catalog_page': {
      await new Promise((resolve) => window.setTimeout(resolve, 260));
      return clone(catalogSlice(args));
    }
    case 'catalog_wave':
      return clone([...siteCatalog].sort(() => Math.random() - 0.5).slice(0, Number(args.limit ?? 40)));
    case 'catalog_likes':
      return [...siteLikes];
    case 'catalog_like': {
      const siteId = String(args.siteId);
      siteLikes = new Set(siteLikes);
      if (args.value) siteLikes.add(siteId);
      else siteLikes.delete(siteId);
      return null;
    }
    case 'catalog_played':
      return null;
    case 'site_lyrics_get': {
      await new Promise((resolve) => window.setTimeout(resolve, 320));
      const found = siteCatalog.find((track) => track.siteId === String(args.siteId));
      return found ? buildLyrics({ ...found, id: `t${found.siteId}` }) : { state: 'none' };
    }
    case 'site_snapshot':
      return clone(site);
    case 'site_login':
      login();
      return null;
    case 'site_cancel_login':
      patchSite({ busy: false });
      return null;
    case 'site_logout':
      patchSite({ user: null, favorites: { ...site.favorites, total: 0, done: 0, phase: { phase: 'idle' } }, playlists: [] });
      return null;
    case 'site_refresh':
      return null;
    case 'site_download_favorites':
      runDownload('favorites');
      return null;
    case 'site_download_playlist':
      runDownload(String(args.id));
      return null;
    case 'set_lossless':
      patchSite({ lossless: Boolean(args.value) });
      return null;
    case 'set_motion_auto':
      return null;
    case 'discord_info':
      return { supported: true, status: 'waiting_for_discord', label: 'Discord: не найден, жду', enabled: true, appId: '1498024819675889704', appName: 'Burmalda' };
    case 'discord_set_enabled':
    case 'discord_reconnect':
      return null;
    case 'update_check': {
      const manifest: UpdateManifest | null = window.location.search.includes('update')
        ? { platform: 'win', version: '0.2.0', build: 9, file: 'NodeShiftMusic-Setup.exe', size: 28_400_000, sha256: '', notes: 'Новая версия с анимированными обложками', builtAt: null, available: true }
        : null;
      return manifest;
    }
    case 'update_install':
      emit('nsm:toast', 'Обновление скачивается');
      return null;
    default:
      throw new Error(`mock: unknown command ${command}`);
  }
}
