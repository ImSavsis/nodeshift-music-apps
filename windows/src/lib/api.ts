import { invoke, listen } from './tauri';
import type {
  AppInfo,
  Decision,
  ImportSnapshot,
  Lyrics,
  Playlist,
  SiteSnapshot,
  Track,
  UpdateManifest
} from './types';

export const api = {
  appInfo: () => invoke<AppInfo>('app_info'),
  library: () => invoke<Track[]>('library_all'),
  playlists: () => invoke<Playlist[]>('playlists_all'),
  setFavorite: (id: string, value: boolean) => invoke<void>('track_favorite', { id, value }),
  markPlayed: (id: string) => invoke<void>('track_played', { id }),
  deleteTrack: (id: string) => invoke<void>('track_delete', { id }),
  updateTrack: (id: string, title: string, artist: string, album: string | null, trackNumber: number | null) =>
    invoke<Track>('track_update', { id, title, artist, album, trackNumber }),
  createPlaylist: (name: string) => invoke<Playlist>('playlist_create', { name }),
  playlistAdd: (playlistId: string, trackId: string) => invoke<void>('playlist_add', { playlistId, trackId }),
  playlistRemove: (playlistId: string, trackId: string) => invoke<void>('playlist_remove', { playlistId, trackId }),
  playlistRename: (playlistId: string, name: string) => invoke<void>('playlist_rename', { playlistId, name }),
  playlistDelete: (playlistId: string) => invoke<void>('playlist_delete', { playlistId }),
  importStart: (paths: string[]) => invoke<void>('import_start', { paths }),
  importSnapshot: () => invoke<ImportSnapshot>('import_snapshot'),
  importDecide: (id: string, decision: Decision) => invoke<void>('import_decide', { id, decision }),
  importSkipAll: () => invoke<void>('import_skip_all'),
  importClear: () => invoke<void>('import_clear'),
  lyrics: (trackId: string, force: boolean) => invoke<Lyrics>('lyrics_get', { trackId, force }),
  palette: (name: string) => invoke<Array<[number, number, number]>>('cover_palette', { name }),
  catalogPage: (search: string, sort: string, format: string | null, limit: number, offset: number) =>
    invoke<{ tracks: Track[]; count: number }>('catalog_page', { search, sort, format, limit, offset }),
  catalogWave: (limit: number) => invoke<Track[]>('catalog_wave', { limit }),
  catalogLikes: () => invoke<string[]>('catalog_likes'),
  catalogLike: (siteId: string, value: boolean) => invoke<void>('catalog_like', { siteId, value }),
  catalogPlayed: (siteId: string) => invoke<void>('catalog_played', { siteId }),
  siteLyrics: (siteId: string) => invoke<Lyrics>('site_lyrics_get', { siteId }),
  siteSnapshot: () => invoke<SiteSnapshot>('site_snapshot'),
  siteLogin: () => invoke<void>('site_login'),
  siteCancelLogin: () => invoke<void>('site_cancel_login'),
  siteLogout: () => invoke<void>('site_logout'),
  siteRefresh: () => invoke<void>('site_refresh'),
  siteDownloadFavorites: () => invoke<void>('site_download_favorites'),
  siteDownloadPlaylist: (id: string) => invoke<void>('site_download_playlist', { id }),
  setLossless: (value: boolean) => invoke<void>('set_lossless', { value }),
  setMotionAuto: (value: boolean) => invoke<void>('set_motion_auto', { value }),
  updateCheck: () => invoke<UpdateManifest | null>('update_check'),
  updateInstall: () => invoke<void>('update_install')
};

export const events = {
  library: (handler: () => void) => listen<null>('nsm:library', () => handler()),
  importing: (handler: () => void) => listen<null>('nsm:import', () => handler()),
  site: (handler: () => void) => listen<null>('nsm:site', () => handler()),
  toast: (handler: (message: string) => void) => listen<string>('nsm:toast', handler)
};
