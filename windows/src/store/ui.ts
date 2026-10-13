import { create } from 'zustand';
import type { Track } from '../lib/types';

interface UiStore {
  helpOpen: boolean;
  playlistPickerTrack: Track | null;
  editTrack: Track | null;
  dropActive: boolean;
  setHelpOpen: (open: boolean) => void;
  openPlaylistPicker: (track: Track) => void;
  closePlaylistPicker: () => void;
  openEditTrack: (track: Track) => void;
  closeEditTrack: () => void;
  setDropActive: (active: boolean) => void;
}

export const useUiStore = create<UiStore>((set) => ({
  helpOpen: false,
  playlistPickerTrack: null,
  editTrack: null,
  dropActive: false,
  setHelpOpen: (open) => set({ helpOpen: open }),
  openPlaylistPicker: (track) => set({ playlistPickerTrack: track }),
  closePlaylistPicker: () => set({ playlistPickerTrack: null }),
  openEditTrack: (track) => set({ editTrack: track }),
  closeEditTrack: () => set({ editTrack: null }),
  setDropActive: (active) => set({ dropActive: active })
}));
