import { create } from 'zustand';
import { api } from '../lib/api';
import { setMediaBase } from '../lib/media';
import { toast } from './toast';
import type { AppInfo, UpdateManifest } from '../lib/types';

interface AppStore {
  info: AppInfo | null;
  update: UpdateManifest | null;
  checking: boolean;
  installing: boolean;
  init: () => Promise<void>;
  checkUpdate: (quiet?: boolean) => Promise<void>;
  installUpdate: () => Promise<void>;
}

export const useAppStore = create<AppStore>((set, get) => ({
  info: null,
  update: null,
  checking: false,
  installing: false,

  init: async () => {
    const info = await api.appInfo();
    setMediaBase(info.mediaBase);
    set({ info });
  },

  checkUpdate: async (quiet = false) => {
    if (get().checking) return;
    set({ checking: true });
    try {
      const update = await api.updateCheck();
      set({ update });
      if (!quiet) toast(update ? `Есть новая версия ${update.version}` : 'У вас последняя версия');
    } catch {
      if (!quiet) toast('Не удалось проверить обновления');
    } finally {
      set({ checking: false });
    }
  },

  installUpdate: async () => {
    if (get().installing) return;
    set({ installing: true });
    try {
      await api.updateInstall();
    } catch {
      toast('Не удалось установить обновление');
      set({ installing: false });
    }
  }
}));
