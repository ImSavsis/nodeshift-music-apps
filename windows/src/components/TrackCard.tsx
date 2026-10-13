import { motion } from 'framer-motion';
import { ArrowDownToLine, Pause, Play } from 'lucide-react';
import { CoverImage } from './CoverImage';
import { EqualizerBars } from './EqualizerBars';
import { FormatBadge } from './FormatBadge';
import { TrackActions } from './TrackActions';
import { usePlayerStore } from '../store/player';
import type { Track } from '../lib/types';

interface TrackCardProps {
  track: Track;
  queue?: Track[];
  showsDownloaded?: boolean;
}

const cardMotion = {
  hidden: { opacity: 0, y: 16 },
  visible: { opacity: 1, y: 0 }
};

export function TrackCard({ track, queue, showsDownloaded = false }: TrackCardProps) {
  const isCurrent = usePlayerStore((state) => state.currentTrack?.id === track.id);
  const isPlaying = usePlayerStore((state) => state.isPlaying);
  const playTrack = usePlayerStore((state) => state.playTrack);
  const togglePlay = usePlayerStore((state) => state.togglePlay);

  const isActivePlaying = isCurrent && isPlaying;

  function handleActivate() {
    if (isCurrent) {
      togglePlay();
    } else {
      playTrack(track, queue);
    }
  }

  return (
    <motion.div variants={cardMotion} className="group flex min-w-0 flex-col gap-3">
      <div className="relative">
        <button
          type="button"
          onClick={handleActivate}
          aria-label={isActivePlaying ? 'Пауза' : 'Играть'}
          className="relative block w-full overflow-hidden rounded-tile"
        >
          <CoverImage coverName={track.coverName} motionName={track.motionName} alt={track.title} className="aspect-square w-full" />
          <span
            className={`absolute inset-0 flex items-center justify-center bg-black/0 transition-all duration-200 group-hover:bg-black/40 ${
              isCurrent ? 'bg-black/30' : ''
            }`}
          >
            <span
              className={`flex h-12 w-12 items-center justify-center rounded-full bg-gradient-to-b from-[#f4f4f6] to-[#cfcfd6] text-[#111] shadow-float transition-all duration-200 ${
                isCurrent ? 'scale-100 opacity-100' : 'scale-90 opacity-0 group-hover:scale-100 group-hover:opacity-100'
              }`}
            >
              {isActivePlaying ? <Pause size={20} fill="currentColor" /> : <Play size={20} fill="currentColor" className="ml-0.5" />}
            </span>
          </span>
        </button>

        <TrackActions
          track={track}
          className="absolute right-1.5 top-1.5 rounded-pill border border-border2 bg-black/55 opacity-0 backdrop-blur transition-opacity group-hover:opacity-100"
        />

        {isCurrent ? (
          <div className="pointer-events-none absolute bottom-2 left-2 rounded-full border border-border2 bg-base/80 px-2 py-1 backdrop-blur">
            <EqualizerBars isPlaying={isPlaying} />
          </div>
        ) : null}
      </div>
      <div className="min-w-0">
        <p className="truncate text-sm font-medium text-primary">{track.title}</p>
        <div className="mt-0.5 flex items-center gap-1.5">
          <p className="truncate font-mono text-[0.6875rem] text-dim">{track.artist}</p>
          <FormatBadge format={track.format} />
          {showsDownloaded && !track.streamUrl && track.siteId ? <ArrowDownToLine size={12} className="shrink-0 text-dim" aria-label="Скачан" /> : null}
        </div>
      </div>
    </motion.div>
  );
}
