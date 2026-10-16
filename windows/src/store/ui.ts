import { create } from 'zustand';
import { ANIMATIONS } from '../lib/karaoke';
import type { LyricAnimationMode } from '../lib/karaoke';
import type { Track } from '../lib/types';

const ANIMATION_KEY = 'nsm.lyricAnimation';

function loadAnimation(): LyricAnimationMode {
  try {
    const value = localStorage.getItem(ANIMATION_KEY) ?? '';
    if (value === 'auto' || (ANIMATIONS as readonly string[]).includes(value)) return value as LyricAnimationMode;
  } catch {
    return 'auto';
  }
  return 'auto';
}

function saveAnimation(mode: LyricAnimationMode) {
  try {
    localStorage.setItem(ANIMATION_KEY, mode);
  } catch {
    return;
  }
}

interface UiStore {
  helpOpen: boolean;
  playlistPickerTrack: Track | null;
  editTrack: Track | null;
  dropActive: boolean;
  lyricAnimation: LyricAnimationMode;
  setLyricAnimation: (mode: LyricAnimationMode) => void;
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
  lyricAnimation: loadAnimation(),
  setLyricAnimation: (mode) => {
    saveAnimation(mode);
    set({ lyricAnimation: mode });
  },
  setHelpOpen: (open) => set({ helpOpen: open }),
  openPlaylistPicker: (track) => set({ playlistPickerTrack: track }),
  closePlaylistPicker: () => set({ playlistPickerTrack: null }),
  openEditTrack: (track) => set({ editTrack: track }),
  closeEditTrack: () => set({ editTrack: null }),
  setDropActive: (active) => set({ dropActive: active })
}));
