import { useEffect } from 'react';
import { media } from '../lib/media';
import { usePlayerStore } from '../store/player';

export function useMediaSession() {
  const track = usePlayerStore((state) => state.currentTrack);
  const isPlaying = usePlayerStore((state) => state.isPlaying);

  useEffect(() => {
    if (!('mediaSession' in navigator)) return;

    if (!track) {
      navigator.mediaSession.metadata = null;
      return;
    }

    navigator.mediaSession.metadata = new MediaMetadata({
      title: track.title,
      artist: track.artist,
      album: track.album ?? 'NS Music',
      artwork: track.coverName ? [{ src: media.cover(track.coverName), sizes: '512x512' }] : []
    });
  }, [track?.id, track?.title, track?.artist, track?.album, track?.coverName]);

  useEffect(() => {
    if (!('mediaSession' in navigator)) return;
    navigator.mediaSession.playbackState = isPlaying ? 'playing' : 'paused';
  }, [isPlaying]);

  useEffect(() => {
    if (!('mediaSession' in navigator)) return;

    const player = usePlayerStore.getState;
    const handlers: Array<[MediaSessionAction, MediaSessionActionHandler]> = [
      ['play', () => player().play()],
      ['pause', () => player().pause()],
      ['previoustrack', () => player().playPrevious()],
      ['nexttrack', () => player().playNext()],
      ['seekbackward', () => player().requestSeek(Math.max(0, player().currentTime - 10))],
      ['seekforward', () => player().requestSeek(Math.min(player().duration, player().currentTime + 10))],
      [
        'seekto',
        (details) => {
          if (typeof details.seekTime === 'number') player().requestSeek(details.seekTime);
        }
      ]
    ];

    for (const [action, handler] of handlers) {
      try {
        navigator.mediaSession.setActionHandler(action, handler);
      } catch {
        continue;
      }
    }

    return () => {
      for (const [action] of handlers) {
        try {
          navigator.mediaSession.setActionHandler(action, null);
        } catch {
          continue;
        }
      }
    };
  }, []);

  useEffect(() => {
    if (!('mediaSession' in navigator) || !('setPositionState' in navigator.mediaSession)) return;

    let lastSecond = -1;
    return usePlayerStore.subscribe((state) => {
      const second = Math.floor(state.currentTime);
      if (second === lastSecond || !state.currentTrack || !(state.duration > 0)) return;
      lastSecond = second;
      try {
        navigator.mediaSession.setPositionState({
          duration: state.duration,
          position: Math.min(state.currentTime, state.duration),
          playbackRate: 1
        });
      } catch {
        return;
      }
    });
  }, []);
}
