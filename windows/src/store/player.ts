import { create } from 'zustand';
import { api } from '../lib/api';
import type { RepeatMode, Track } from '../lib/types';

const VOLUME_KEY = 'nsm_volume';
const SHUFFLE_KEY = 'nsm_shuffle';
const REPEAT_KEY = 'nsm_repeat';

function readStorage(key: string): string | null {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

function writeStorage(key: string, value: string) {
  try {
    localStorage.setItem(key, value);
  } catch {
    return;
  }
}

function loadVolume(): number {
  const raw = readStorage(VOLUME_KEY);
  const value = raw === null ? 1 : Number(raw);
  return Number.isFinite(value) ? Math.min(1, Math.max(0, value)) : 1;
}

function loadRepeat(): RepeatMode {
  const raw = readStorage(REPEAT_KEY);
  return raw === 'all' || raw === 'one' ? raw : 'off';
}

function registerPlay(track: Track) {
  if (track.streamUrl && track.siteId) api.catalogPlayed(track.siteId).catch(() => {});
  else api.markPlayed(track.id).catch(() => {});
}

function shuffled<T>(items: T[]): T[] {
  const copy = [...items];
  for (let i = copy.length - 1; i > 0; i -= 1) {
    const j = Math.floor(Math.random() * (i + 1));
    [copy[i], copy[j]] = [copy[j], copy[i]];
  }
  return copy;
}

interface PlayerStore {
  currentTrack: Track | null;
  queue: Track[];
  queueIndex: number;
  isPlaying: boolean;
  isExpanded: boolean;
  isQueueOpen: boolean;
  currentTime: number;
  duration: number;
  timeStamp: number;
  volume: number;
  isMuted: boolean;
  shuffle: boolean;
  repeat: RepeatMode;
  shuffleHistory: number[];
  hasRegisteredPlay: boolean;
  pendingSeekTime: number | null;
  seekToken: number;
  playTrack: (track: Track, queue?: Track[]) => void;
  playMany: (tracks: Track[], options?: { shuffled?: boolean }) => void;
  playIndex: (index: number) => void;
  togglePlay: () => void;
  play: () => void;
  pause: () => void;
  requestSeek: (time: number) => void;
  setVolume: (volume: number) => void;
  toggleMute: () => void;
  expand: () => void;
  collapse: () => void;
  closeQueue: () => void;
  toggleQueue: () => void;
  playNext: () => void;
  playPrevious: () => void;
  toggleShuffle: () => void;
  cycleRepeat: () => void;
  playNextInQueue: (track: Track) => void;
  addToQueue: (track: Track) => void;
  removeFromQueue: (index: number) => void;
  clearUpcoming: () => void;
  reconcile: (byId: Map<string, Track>) => void;
  handleTimeUpdate: (currentTime: number, duration: number) => void;
  handleEnded: () => void;
}

export const usePlayerStore = create<PlayerStore>((set, get) => {
  function begin(queue: Track[], index: number, resetHistory: boolean) {
    const track = queue[index];
    if (!track) return;
    set({
      currentTrack: track,
      queue,
      queueIndex: index,
      isPlaying: true,
      currentTime: 0,
      duration: track.durationMs / 1000,
      timeStamp: performance.now(),
      hasRegisteredPlay: false,
      shuffleHistory: resetHistory ? [] : get().shuffleHistory
    });
  }

  return {
    currentTrack: null,
    queue: [],
    queueIndex: -1,
    isPlaying: false,
    isExpanded: false,
    isQueueOpen: false,
    currentTime: 0,
    duration: 0,
    timeStamp: 0,
    volume: loadVolume(),
    isMuted: false,
    shuffle: readStorage(SHUFFLE_KEY) === '1',
    repeat: loadRepeat(),
    shuffleHistory: [],
    hasRegisteredPlay: false,
    pendingSeekTime: null,
    seekToken: 0,

    playTrack: (track, queue) => {
      const base = queue ?? [track];
      const found = base.findIndex((item) => item.id === track.id);
      if (found === -1) {
        begin([track, ...base], 0, true);
      } else {
        begin(base, found, true);
      }
    },

    playMany: (tracks, options) => {
      if (tracks.length === 0) return;
      begin(options?.shuffled ? shuffled(tracks) : tracks, 0, true);
    },

    playIndex: (index) => begin(get().queue, index, false),

    togglePlay: () => set((state) => ({ isPlaying: !state.isPlaying })),
    play: () => set({ isPlaying: true }),
    pause: () => set({ isPlaying: false }),

    requestSeek: (time) =>
      set((state) => ({ currentTime: time, timeStamp: performance.now(), pendingSeekTime: time, seekToken: state.seekToken + 1 })),

    setVolume: (volume) => {
      writeStorage(VOLUME_KEY, String(volume));
      set({ volume, isMuted: volume === 0 });
    },

    toggleMute: () => set((state) => ({ isMuted: !state.isMuted })),

    expand: () => set({ isExpanded: true }),
    collapse: () => set({ isExpanded: false, isQueueOpen: false }),
    closeQueue: () => set({ isQueueOpen: false }),
    toggleQueue: () => set((state) => ({ isQueueOpen: !state.isQueueOpen })),

    playNext: () => {
      const { queue, queueIndex, shuffle, repeat, shuffleHistory } = get();
      if (queue.length === 0) return;

      if (shuffle && queue.length > 1) {
        const choices = queue.map((_, index) => index).filter((index) => index !== queueIndex);
        const pick = choices[Math.floor(Math.random() * choices.length)];
        begin(queue, pick, false);
        set({ shuffleHistory: [...shuffleHistory, queueIndex].slice(-50) });
        return;
      }

      const nextIndex = queueIndex + 1;
      if (nextIndex < queue.length) {
        begin(queue, nextIndex, false);
      } else if (repeat === 'all') {
        begin(queue, 0, false);
      }
    },

    playPrevious: () => {
      const { queue, queueIndex, shuffle, repeat, currentTime, shuffleHistory } = get();
      if (queue.length === 0) return;

      if (currentTime > 3) {
        get().requestSeek(0);
        return;
      }

      if (shuffle && shuffleHistory.length > 0) {
        const previous = shuffleHistory[shuffleHistory.length - 1];
        begin(queue, previous, false);
        set({ shuffleHistory: shuffleHistory.slice(0, -1) });
        return;
      }

      if (queueIndex > 0) {
        begin(queue, queueIndex - 1, false);
      } else if (repeat === 'all') {
        begin(queue, queue.length - 1, false);
      } else {
        get().requestSeek(0);
      }
    },

    toggleShuffle: () => {
      const next = !get().shuffle;
      writeStorage(SHUFFLE_KEY, next ? '1' : '0');
      set({ shuffle: next, shuffleHistory: [] });
    },

    cycleRepeat: () => {
      const order: RepeatMode[] = ['off', 'all', 'one'];
      const next = order[(order.indexOf(get().repeat) + 1) % order.length];
      writeStorage(REPEAT_KEY, next);
      set({ repeat: next });
    },

    playNextInQueue: (track) => {
      const { queue, queueIndex } = get();
      if (queue.length === 0) {
        begin([track], 0, true);
        return;
      }
      set({ queue: [...queue.slice(0, queueIndex + 1), track, ...queue.slice(queueIndex + 1)] });
    },

    addToQueue: (track) => {
      const { queue } = get();
      if (queue.length === 0) {
        begin([track], 0, true);
        return;
      }
      set({ queue: [...queue, track] });
    },

    removeFromQueue: (index) => {
      const { queue, queueIndex } = get();
      if (index === queueIndex || index < 0 || index >= queue.length) return;
      set({ queue: queue.filter((_, position) => position !== index), queueIndex: index < queueIndex ? queueIndex - 1 : queueIndex });
    },

    clearUpcoming: () => {
      const { queue, queueIndex } = get();
      set({ queue: queue.slice(0, queueIndex + 1) });
    },

    reconcile: (byId) => {
      const { queue, queueIndex, currentTrack } = get();
      if (!currentTrack) return;
      const keep = (item: Track) => Boolean(item.streamUrl) || byId.has(item.id);
      const fresh = (item: Track) => (item.streamUrl ? item : (byId.get(item.id) as Track));
      if (!keep(currentTrack)) {
        set({ currentTrack: null, queue: [], queueIndex: -1, isPlaying: false, isExpanded: false, isQueueOpen: false });
        return;
      }
      const removedBefore = queue.slice(0, queueIndex).filter((item) => !keep(item)).length;
      set({
        queue: queue.filter(keep).map(fresh),
        queueIndex: queueIndex - removedBefore,
        currentTrack: fresh(currentTrack)
      });
    },

    handleTimeUpdate: (currentTime, duration) => {
      const { currentTrack, hasRegisteredPlay } = get();
      set({ currentTime, duration: duration > 0 ? duration : get().duration, timeStamp: performance.now() });
      if (currentTrack && !hasRegisteredPlay && currentTime >= 5) {
        set({ hasRegisteredPlay: true });
        registerPlay(currentTrack);
      }
    },

    handleEnded: () => {
      const { currentTrack, hasRegisteredPlay, repeat, queue, queueIndex, shuffle } = get();
      if (currentTrack && !hasRegisteredPlay) {
        registerPlay(currentTrack);
      }

      if (repeat === 'one') {
        set({ hasRegisteredPlay: false, isPlaying: true });
        get().requestSeek(0);
        return;
      }

      const hasNext = shuffle ? queue.length > 1 : queueIndex + 1 < queue.length || (repeat === 'all' && queue.length > 0);
      if (hasNext) {
        get().playNext();
        return;
      }

      set({ hasRegisteredPlay: true, isPlaying: false, currentTime: 0 });
    }
  };
});
