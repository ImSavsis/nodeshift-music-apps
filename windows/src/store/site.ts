import { create } from 'zustand';
import { api } from '../lib/api';
import type { SiteSnapshot } from '../lib/types';

interface SiteStore {
  snapshot: SiteSnapshot;
  refresh: () => Promise<void>;
}

const EMPTY: SiteSnapshot = {
  user: null,
  busy: false,
  lastError: null,
  favorites: { id: 'favorites', name: 'Понравившиеся', total: 0, done: 0, phase: { phase: 'idle' } },
  playlists: [],
  refreshing: false,
  needsLogin: false,
  lossless: true
};

export const useSiteStore = create<SiteStore>((set) => ({
  snapshot: EMPTY,
  refresh: async () => {
    set({ snapshot: await api.siteSnapshot() });
  }
}));
