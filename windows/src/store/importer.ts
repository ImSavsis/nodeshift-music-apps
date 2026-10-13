import { create } from 'zustand';
import { api } from '../lib/api';
import { toast } from './toast';
import type { Decision, ImportSnapshot } from '../lib/types';

interface ImportStore {
  snapshot: ImportSnapshot;
  refresh: () => Promise<void>;
  start: (paths: string[]) => Promise<void>;
  decide: (id: string, decision: Decision) => Promise<void>;
  skipAll: () => Promise<void>;
  clear: () => Promise<void>;
}

const EMPTY: ImportSnapshot = {
  items: [],
  summary: { added: 0, duplicates: 0, failed: 0, ignored: 0 },
  running: false,
  pendingDuplicates: 0
};

export const useImportStore = create<ImportStore>((set, get) => ({
  snapshot: EMPTY,

  refresh: async () => {
    set({ snapshot: await api.importSnapshot() });
  },

  start: async (paths) => {
    if (paths.length === 0) return;
    await api.importStart(paths);
    await get().refresh();
  },

  decide: async (id, decision) => {
    await api.importDecide(id, decision);
    await get().refresh();
  },

  skipAll: async () => {
    await api.importSkipAll();
    await get().refresh();
    toast('Дубликаты пропущены');
  },

  clear: async () => {
    await api.importClear();
    await get().refresh();
  }
}));
