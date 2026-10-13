import { create } from 'zustand';
import { api } from '../lib/api';
import { useLibraryStore } from './library';
import { useSiteStore } from './site';
import { toast } from './toast';
import type { Track } from '../lib/types';

export type CatalogSort = 'new' | 'popular' | 'title';

export const PAGE_SIZE = 30;

interface CatalogStore {
  tracks: Track[];
  query: string;
  sort: CatalogSort;
  format: string;
  isLoading: boolean;
  hasMore: boolean;
  failed: boolean;
  likedIds: Set<string>;
  startIfNeeded: () => void;
  setQuery: (value: string) => void;
  setSort: (value: CatalogSort) => void;
  setFormat: (value: string) => void;
  reload: () => void;
  loadMore: () => void;
  wave: () => Promise<Track[]>;
  refreshLikes: () => Promise<void>;
  toggleLike: (track: Track) => void;
}

let generation = 0;
let offset = 0;
let searchTimer: ReturnType<typeof setTimeout> | null = null;

export const useCatalogStore = create<CatalogStore>((set, get) => {
  async function load(reset: boolean) {
    const token = generation;
    const { query, sort, format } = get();
    const start = offset;
    set({ isLoading: true, failed: false });
    try {
      const page = await api.catalogPage(query.trim(), sort, format || null, PAGE_SIZE, start);
      if (token !== generation) return;
      const current = get().tracks;
      const known = new Set(current.map((track) => track.id));
      set({
        tracks: reset ? page.tracks : [...current, ...page.tracks.filter((track) => !known.has(track.id))],
        hasMore: page.count === PAGE_SIZE,
        isLoading: false
      });
      offset = start + page.count;
    } catch {
      if (token !== generation) return;
      set({ failed: true, hasMore: false, isLoading: false });
    }
  }

  return {
    tracks: [],
    query: '',
    sort: 'new',
    format: '',
    isLoading: false,
    hasMore: true,
    failed: false,
    likedIds: new Set(),

    startIfNeeded: () => {
      if (get().tracks.length === 0 && !get().isLoading) get().reload();
    },

    setQuery: (value) => {
      set({ query: value });
      if (searchTimer) clearTimeout(searchTimer);
      searchTimer = setTimeout(() => get().reload(), 350);
    },

    setSort: (value) => {
      set({ sort: value });
      get().reload();
    },

    setFormat: (value) => {
      set({ format: value });
      get().reload();
    },

    reload: () => {
      generation += 1;
      offset = 0;
      set({ hasMore: true });
      void load(true);
    },

    loadMore: () => {
      const { hasMore, isLoading } = get();
      if (!hasMore || isLoading) return;
      void load(false);
    },

    wave: async () => {
      try {
        return await api.catalogWave(40);
      } catch {
        toast('Не получилось запустить волну');
        return [];
      }
    },

    refreshLikes: async () => {
      if (!useSiteStore.getState().snapshot.user) {
        set({ likedIds: new Set() });
        return;
      }
      try {
        set({ likedIds: new Set(await api.catalogLikes()) });
      } catch {
        return;
      }
    },

    toggleLike: (track) => {
      const siteId = track.siteId;
      if (!siteId) return;
      if (!useSiteStore.getState().snapshot.user) {
        toast('Войдите через сайт, чтобы ставить лайки');
        return;
      }
      const value = !get().likedIds.has(siteId);
      const next = new Set(get().likedIds);
      if (value) next.add(siteId);
      else next.delete(siteId);
      set({ likedIds: next });
      api.catalogLike(siteId, value).catch(() => {
        const reverted = new Set(get().likedIds);
        if (value) reverted.delete(siteId);
        else reverted.add(siteId);
        set({ likedIds: reverted });
        toast('Не получилось сохранить лайк');
      });
    }
  };
});

export function useIsFavorite(track: Track): boolean {
  const local = useLibraryStore((state) => state.byId.get(track.id)?.isFavorite ?? track.isFavorite);
  const remote = useCatalogStore((state) => (track.siteId ? state.likedIds.has(track.siteId) : false));
  return track.streamUrl ? remote : local;
}

export function toggleFavorite(track: Track) {
  if (track.streamUrl) useCatalogStore.getState().toggleLike(track);
  else useLibraryStore.getState().toggleFavorite(track.id);
}
