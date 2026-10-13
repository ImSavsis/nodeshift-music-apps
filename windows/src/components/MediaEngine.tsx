import { useEffect, useRef } from 'react';
import { setActiveMediaElement } from '../lib/audioElements';
import { media } from '../lib/media';
import { useAppStore } from '../store/app';
import { usePlayerStore } from '../store/player';
import { toast } from '../store/toast';

export function MediaEngine() {
  const audioRef = useRef<HTMLAudioElement | null>(null);

  const currentTrack = usePlayerStore((state) => state.currentTrack);
  const isPlaying = usePlayerStore((state) => state.isPlaying);
  const volume = usePlayerStore((state) => state.volume);
  const isMuted = usePlayerStore((state) => state.isMuted);
  const pendingSeekTime = usePlayerStore((state) => state.pendingSeekTime);
  const seekToken = usePlayerStore((state) => state.seekToken);
  const handleTimeUpdate = usePlayerStore((state) => state.handleTimeUpdate);
  const handleEnded = usePlayerStore((state) => state.handleEnded);
  const pause = usePlayerStore((state) => state.pause);
  const forcedMute = useAppStore((state) => state.info?.muted ?? false);

  const trackId = currentTrack?.id;
  const durationMs = currentTrack?.durationMs ?? 0;
  const streamUrl = currentTrack?.streamUrl ?? null;

  useEffect(() => {
    const element = audioRef.current;
    if (!element) return;
    setActiveMediaElement(element);
    if (!trackId) {
      element.pause();
      element.removeAttribute('src');
      element.load();
      return;
    }
    element.pause();
    const active = usePlayerStore.getState().currentTrack;
    if (!active) return;
    element.crossOrigin = streamUrl ? null : 'anonymous';
    element.dataset.trackId = trackId;
    element.src = media.track(active);
    element.currentTime = 0;
    element.load();
    if (usePlayerStore.getState().isPlaying) {
      element.play().catch(() => pause());
    }
  }, [trackId, durationMs, streamUrl, pause]);

  useEffect(() => {
    const element = audioRef.current;
    if (!element || !element.getAttribute('src')) return;
    if (isPlaying) {
      element.play().catch(() => pause());
    } else {
      element.pause();
    }
  }, [isPlaying, trackId, pause]);

  useEffect(() => {
    const element = audioRef.current;
    if (!element) return;
    element.volume = volume;
    element.muted = isMuted || forcedMute;
  }, [volume, isMuted, forcedMute]);

  useEffect(() => {
    const element = audioRef.current;
    if (pendingSeekTime === null || !element || !element.getAttribute('src')) return;
    element.currentTime = pendingSeekTime;
    if (usePlayerStore.getState().isPlaying) {
      element.play().catch(() => {});
    }
  }, [seekToken, pendingSeekTime]);

  useEffect(() => {
    const element = audioRef.current;
    if (!element) return;

    function onTimeUpdate() {
      if (!element) return;
      handleTimeUpdate(element.currentTime, element.duration || 0);
    }

    function onError() {
      if (!usePlayerStore.getState().currentTrack) return;
      toast('Не удалось воспроизвести трек');
      pause();
    }

    element.addEventListener('timeupdate', onTimeUpdate);
    element.addEventListener('ended', handleEnded);
    element.addEventListener('error', onError);

    return () => {
      element.removeEventListener('timeupdate', onTimeUpdate);
      element.removeEventListener('ended', handleEnded);
      element.removeEventListener('error', onError);
    };
  }, [handleTimeUpdate, handleEnded, pause]);

  return (
    <div className="pointer-events-none fixed -left-[9999px] -top-[9999px] h-px w-px overflow-hidden opacity-0">
      <audio ref={audioRef} preload="auto" />
    </div>
  );
}
