import { motion } from 'framer-motion';
import { ChevronUp, ListMusic, Pause, Play, Repeat, Repeat1, Shuffle, SkipBack, SkipForward } from 'lucide-react';
import { CoverImage } from './CoverImage';
import { IconToggle, TrackActions } from './TrackActions';
import { ProgressBar } from './ProgressBar';
import { VolumeControl } from './VolumeControl';
import { usePlayerStore } from '../store/player';

export function PlayerBar() {
  const currentTrack = usePlayerStore((state) => state.currentTrack);
  const isPlaying = usePlayerStore((state) => state.isPlaying);
  const currentTime = usePlayerStore((state) => state.currentTime);
  const duration = usePlayerStore((state) => state.duration);
  const shuffle = usePlayerStore((state) => state.shuffle);
  const repeat = usePlayerStore((state) => state.repeat);
  const isQueueOpen = usePlayerStore((state) => state.isQueueOpen);
  const togglePlay = usePlayerStore((state) => state.togglePlay);
  const requestSeek = usePlayerStore((state) => state.requestSeek);
  const expand = usePlayerStore((state) => state.expand);
  const playNext = usePlayerStore((state) => state.playNext);
  const playPrevious = usePlayerStore((state) => state.playPrevious);
  const toggleShuffle = usePlayerStore((state) => state.toggleShuffle);
  const cycleRepeat = usePlayerStore((state) => state.cycleRepeat);
  const toggleQueue = usePlayerStore((state) => state.toggleQueue);

  if (!currentTrack) return null;

  return (
    <motion.div
      initial={{ y: 96, opacity: 0 }}
      animate={{ y: 0, opacity: 1 }}
      transition={{ duration: 0.35, ease: [0.16, 1, 0.3, 1] }}
      className="player"
    >
      <div className="flex items-center gap-4 px-4 py-3">
        <button type="button" onClick={expand} className="flex min-w-0 flex-1 items-center gap-3 text-left" aria-label="Открыть плеер">
          <motion.div layoutId="player-art" className="h-12 w-12 shrink-0 overflow-hidden rounded-tile">
            <CoverImage coverName={currentTrack.coverName} alt={currentTrack.title} className="h-full w-full" rounded="rounded-tile" live={false} playMotion={false} />
          </motion.div>
          <div className="min-w-0">
            <p className="truncate text-sm font-medium text-primary">{currentTrack.title}</p>
            <p className="truncate font-mono text-[0.6875rem] text-dim">{currentTrack.artist}</p>
          </div>
        </button>

        <TrackActions track={currentTrack} className="hidden lg:flex" />

        <div className="flex flex-[1.4] flex-col items-center gap-1">
          <div className="flex items-center gap-2">
            <IconToggle active={shuffle} label="Перемешать" onClick={toggleShuffle}>
              <Shuffle size={16} />
            </IconToggle>
            <button
              type="button"
              onClick={playPrevious}
              className="flex h-9 w-9 items-center justify-center text-muted transition-colors hover:text-primary"
              aria-label="Предыдущий трек"
            >
              <SkipBack size={18} fill="currentColor" />
            </button>
            <button
              type="button"
              onClick={togglePlay}
              aria-label={isPlaying ? 'Пауза' : 'Играть'}
              className="flex h-10 w-10 items-center justify-center rounded-full bg-gradient-to-b from-[#f4f4f6] to-[#cfcfd6] text-[#111] shadow-[inset_0_1px_rgba(255,255,255,0.9),0_6px_20px_rgba(0,0,0,0.45)] transition-transform active:scale-95"
            >
              {isPlaying ? <Pause size={16} fill="currentColor" /> : <Play size={16} fill="currentColor" className="ml-0.5" />}
            </button>
            <button
              type="button"
              onClick={playNext}
              className="flex h-9 w-9 items-center justify-center text-muted transition-colors hover:text-primary"
              aria-label="Следующий трек"
            >
              <SkipForward size={18} fill="currentColor" />
            </button>
            <IconToggle active={repeat !== 'off'} label="Повтор" onClick={cycleRepeat}>
              {repeat === 'one' ? <Repeat1 size={16} /> : <Repeat size={16} />}
            </IconToggle>
          </div>
          <ProgressBar currentTime={currentTime} duration={duration} onSeek={requestSeek} className="w-full max-w-lg" />
        </div>

        <div className="flex flex-1 items-center justify-end gap-1">
          <IconToggle active={isQueueOpen} label="Очередь" onClick={toggleQueue}>
            <ListMusic size={18} />
          </IconToggle>
          <VolumeControl className="hidden xl:flex" />
          <button
            type="button"
            onClick={expand}
            aria-label="Развернуть плеер"
            className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-muted transition-colors hover:bg-white/10 hover:text-primary"
          >
            <ChevronUp size={20} />
          </button>
        </div>
      </div>
    </motion.div>
  );
}
