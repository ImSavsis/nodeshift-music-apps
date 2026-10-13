import { create } from 'zustand';
import { api } from '../lib/api';
import { toast } from './toast';
import { usePlayerStore } from './player';
import type { Playlist, Track } from '../lib/types';

interface LibraryStore {
  tracks: Track[];
  playlists: Playlist[];
  byId: Map<string, Track>;
  loaded: boolean;
  load: () => Promise<void>;
  toggleFavorite: (id: string) => void;
  deleteTrack: (id: string) => Promise<void>;
  tracksOf: (playlist: Playlist) => Track[];
}

let pending: ReturnType<typeof setTimeout> | null = null;

export const useLibraryStore = create<LibraryStore>((set, get) => ({
  tracks: [],
  playlists: [],
  byId: new Map(),
  loaded: false,

  load: async () => {
    const [tracks, playlists] = await Promise.all([api.library(), api.playlists()]);
    const byId = new Map(tracks.map((track) => [track.id, track]));
    set({ tracks, playlists, byId, loaded: true });
    usePlayerStore.getState().reconcile(byId);
  },

  toggleFavorite: (id) => {
    const track = get().byId.get(id);
    if (!track) return;
    const value = !track.isFavorite;
    const patched = { ...track, isFavorite: value };
    const byId = new Map(get().byId);
    byId.set(id, patched);
    set({ byId, tracks: get().tracks.map((item) => (item.id === id ? patched : item)) });
    api.setFavorite(id, value).catch(() => {
      toast('Не удалось сохранить');
      scheduleReload();
    });
  },

  deleteTrack: async (id) => {
    await api.deleteTrack(id);
    await get().load();
  },

  tracksOf: (playlist) => {
    const { byId } = get();
    return playlist.trackIds.map((id) => byId.get(id)).filter((track): track is Track => Boolean(track));
  }
}));

export function scheduleReload() {
  if (pending) clearTimeout(pending);
  pending = setTimeout(() => {
    pending = null;
    useLibraryStore.getState().load().catch(() => {});
  }, 120);
}
