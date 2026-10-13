import { AnimatePresence, motion } from 'framer-motion';
import { ChevronDown, Heart, ListMusic, ListPlus, Pause, Pencil, Play, Repeat, Repeat1, Shuffle, SkipBack, SkipForward } from 'lucide-react';
import { AmbientBackdrop } from './AmbientBackdrop';
import { CoverImage } from './CoverImage';
import { EqualizerBars } from './EqualizerBars';
import { FormatBadge } from './FormatBadge';
import { IconToggle } from './TrackActions';
import { LyricsPanel } from './LyricsPanel';
import { ProgressBar } from './ProgressBar';
import { VolumeControl } from './VolumeControl';
import { toggleFavorite, useIsFavorite } from '../store/catalog';
import { usePlayerStore } from '../store/player';
import { useUiStore } from '../store/ui';
import type { Track } from '../lib/types';

const EMPTY_TRACK = {
  id: '',
  siteId: null,
  streamUrl: null,
  isFavorite: false
} as unknown as Track;

export function NowPlaying() {
  const currentTrack = usePlayerStore((state) => state.currentTrack);
  const isExpanded = usePlayerStore((state) => state.isExpanded);
  const isPlaying = usePlayerStore((state) => state.isPlaying);
  const currentTime = usePlayerStore((state) => state.currentTime);
  const duration = usePlayerStore((state) => state.duration);
  const queue = usePlayerStore((state) => state.queue);
  const queueIndex = usePlayerStore((state) => state.queueIndex);
  const shuffle = usePlayerStore((state) => state.shuffle);
  const repeat = usePlayerStore((state) => state.repeat);
  const collapse = usePlayerStore((state) => state.collapse);
  const togglePlay = usePlayerStore((state) => state.togglePlay);
  const requestSeek = usePlayerStore((state) => state.requestSeek);
  const playNext = usePlayerStore((state) => state.playNext);
  const playPrevious = usePlayerStore((state) => state.playPrevious);
  const toggleShuffle = usePlayerStore((state) => state.toggleShuffle);
  const cycleRepeat = usePlayerStore((state) => state.cycleRepeat);
  const toggleQueue = usePlayerStore((state) => state.toggleQueue);

  const isLiked = useIsFavorite(currentTrack ?? EMPTY_TRACK);
  const openPlaylistPicker = useUiStore((state) => state.openPlaylistPicker);
  const openEditTrack = useUiStore((state) => state.openEditTrack);

  const upcoming = Math.max(0, queue.length - queueIndex - 1);

  return (
    <AnimatePresence>
      {isExpanded && currentTrack ? (
        <motion.div
          key="now-playing"
          role="dialog"
          aria-label="Сейчас играет"
          initial={{ opacity: 0, y: 40 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: 40 }}
          transition={{ duration: 0.38, ease: [0.16, 1, 0.3, 1] }}
          className="np"
        >
          <AmbientBackdrop coverName={currentTrack.coverName} />

          <header className="np-head">
            <button
              type="button"
              onClick={collapse}
              aria-label="Свернуть плеер"
              className="flex h-10 w-10 items-center justify-center rounded-full text-muted transition-colors hover:bg-white/10 hover:text-primary"
            >
              <ChevronDown size={24} />
            </button>
            <p className="font-mono text-[0.6875rem] uppercase tracking-[0.2em] text-dim">Сейчас играет</p>
            <button
              type="button"
              onClick={toggleQueue}
              aria-label="Очередь"
              className="relative flex h-10 w-10 items-center justify-center rounded-full text-muted transition-colors hover:bg-white/10 hover:text-primary"
            >
              <ListMusic size={20} />
              {upcoming > 0 ? (
                <span className="absolute -right-0.5 -top-0.5 flex h-4 min-w-4 items-center justify-center rounded-full bg-white px-1 font-mono text-[0.5625rem] font-semibold text-[#111]">
                  {upcoming > 99 ? '99+' : upcoming}
                </span>
              ) : null}
            </button>
          </header>

          <div className="np-body">
            <section className="np-main">
              <motion.div layoutId="player-art" className="np-cover">
                <motion.div animate={{ scale: isPlaying ? 1 : 0.92 }} transition={{ type: 'spring', stiffness: 220, damping: 22 }} className="h-full w-full">
                  <CoverImage
                    coverName={currentTrack.coverName}
                    motionName={currentTrack.motionName}
                    playMotion
                    priority
                    alt={currentTrack.title}
                    className="h-full w-full"
                    rounded="rounded-card"
                  />
                </motion.div>
              </motion.div>

              <div className="flex w-full items-center gap-3">
                <div className="min-w-0 flex-1">
                  <p className="truncate font-display text-[clamp(1.25rem,2.2vw,2rem)] font-semibold leading-tight tracking-tight text-primary">{currentTrack.title}</p>
                  <div className="mt-1.5 flex items-center gap-2">
                    <p className="truncate font-mono text-xs text-dim">{currentTrack.artist}</p>
                    <FormatBadge format={currentTrack.format} />
                  </div>
                </div>
                <EqualizerBars isPlaying={isPlaying} />
              </div>

              <ProgressBar currentTime={currentTime} duration={duration} onSeek={requestSeek} className="w-full" />

              <div className="flex w-full items-center justify-between gap-2">
                <IconToggle active={shuffle} label="Перемешать" onClick={toggleShuffle}>
                  <Shuffle size={19} />
                </IconToggle>
                <button
                  type="button"
                  onClick={playPrevious}
                  aria-label="Предыдущий трек"
                  className="flex h-12 w-12 items-center justify-center rounded-full text-muted transition-colors hover:text-primary"
                >
                  <SkipBack size={24} fill="currentColor" />
                </button>
                <button
                  type="button"
                  onClick={togglePlay}
                  aria-label={isPlaying ? 'Пауза' : 'Играть'}
                  className="flex h-16 w-16 items-center justify-center rounded-full bg-gradient-to-b from-[#f4f4f6] to-[#cfcfd6] text-[#111] shadow-float transition-transform active:scale-95"
                >
                  {isPlaying ? <Pause size={26} fill="currentColor" /> : <Play size={26} fill="currentColor" className="ml-1" />}
                </button>
                <button
                  type="button"
                  onClick={playNext}
                  aria-label="Следующий трек"
                  className="flex h-12 w-12 items-center justify-center rounded-full text-muted transition-colors hover:text-primary"
                >
                  <SkipForward size={24} fill="currentColor" />
                </button>
                <IconToggle active={repeat !== 'off'} label="Повтор" onClick={cycleRepeat}>
                  {repeat === 'one' ? <Repeat1 size={19} /> : <Repeat size={19} />}
                </IconToggle>
              </div>

              <div className="flex w-full items-center justify-between gap-2">
                <div className="flex items-center">
                  <IconToggle active={isLiked} label="В избранное" onClick={() => toggleFavorite(currentTrack)}>
                    <Heart size={19} fill={isLiked ? 'currentColor' : 'none'} />
                  </IconToggle>
                  {currentTrack.streamUrl ? null : (
                    <>
                      <IconToggle label="В плейлист" onClick={() => openPlaylistPicker(currentTrack)}>
                        <ListPlus size={19} />
                      </IconToggle>
                      <IconToggle label="Редактировать" onClick={() => openEditTrack(currentTrack)}>
                        <Pencil size={17} />
                      </IconToggle>
                    </>
                  )}
                </div>
                <VolumeControl />
              </div>
            </section>

            <section className="np-lyrics">
              <LyricsPanel track={currentTrack} className="h-full w-full" />
            </section>
          </div>
        </motion.div>
      ) : null}
    </AnimatePresence>
  );
}
