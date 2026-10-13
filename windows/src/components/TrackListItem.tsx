import type { ReactNode } from 'react';
import { motion } from 'framer-motion';
import { ArrowDownToLine, Pause, Play, X } from 'lucide-react';
import { CoverImage } from './CoverImage';
import { EqualizerBars } from './EqualizerBars';
import { FormatBadge } from './FormatBadge';
import { TrackActions } from './TrackActions';
import { usePlayerStore } from '../store/player';
import { formatDuration, formatPlayCount } from '../lib/format';
import type { Track } from '../lib/types';

interface TrackListItemProps {
  track: Track;
  queue?: Track[];
  rank?: number;
  onRemove?: () => void;
  trailing?: ReactNode;
  showsDownloaded?: boolean;
}

const rowMotion = {
  hidden: { opacity: 0, y: 10 },
  visible: { opacity: 1, y: 0 }
};

export function TrackListItem({ track, queue, rank, onRemove, trailing, showsDownloaded = false }: TrackListItemProps) {
  const isCurrent = usePlayerStore((state) => state.currentTrack?.id === track.id);
  const isPlaying = usePlayerStore((state) => state.isPlaying);
  const playTrack = usePlayerStore((state) => state.playTrack);
  const togglePlay = usePlayerStore((state) => state.togglePlay);

  function handleActivate() {
    if (isCurrent) {
      togglePlay();
    } else {
      playTrack(track, queue);
    }
  }

  return (
    <motion.div
      variants={rowMotion}
      onClick={handleActivate}
      className={`group flex cursor-pointer items-center gap-4 rounded-tile border px-3 py-2 transition-colors hover:bg-surface ${
        isCurrent ? 'border-border2 bg-surface2 shadow-edge' : 'border-transparent'
      }`}
    >
      {rank !== undefined ? <span className="w-6 shrink-0 text-center font-mono text-xs text-dim">{rank}</span> : null}

      <div className="relative h-11 w-11 shrink-0 overflow-hidden rounded-tile">
        <CoverImage coverName={track.coverName} alt={track.title} className="h-11 w-11" rounded="rounded-tile" live={false} playMotion={false} />
        <span
          className={`absolute inset-0 flex items-center justify-center bg-black/0 transition-all group-hover:bg-black/50 group-hover:opacity-100 ${
            isCurrent ? 'bg-black/40 opacity-100' : 'opacity-0'
          }`}
        >
          {isCurrent && isPlaying ? <Pause size={16} fill="currentColor" /> : <Play size={16} fill="currentColor" className="ml-0.5" />}
        </span>
      </div>

      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-medium text-primary">{track.title}</p>
        <p className="truncate font-mono text-[0.6875rem] text-dim">
          {track.artist}
          {track.album ? ` · ${track.album}` : ''}
        </p>
      </div>

      {isCurrent ? <EqualizerBars isPlaying={isPlaying} className="shrink-0" /> : null}

      <FormatBadge format={track.format} />
      {showsDownloaded && !track.streamUrl && track.siteId ? <ArrowDownToLine size={13} className="shrink-0 text-dim" aria-label="Скачан" /> : null}
      {track.playCount > 0 ? <span className="hidden shrink-0 font-mono text-[0.6875rem] text-dim md:block">{formatPlayCount(track.playCount)} прослуш.</span> : null}
      <span className="shrink-0 font-mono text-[0.6875rem] text-dim">{formatDuration(track.durationMs / 1000)}</span>

      {trailing}

      <TrackActions track={track} className="shrink-0" />

      {onRemove ? (
        <button
          type="button"
          onClick={(event) => {
            event.stopPropagation();
            onRemove();
          }}
          aria-label="Убрать"
          className="shrink-0 rounded-full p-1.5 text-dim opacity-0 transition-opacity hover:text-primary group-hover:opacity-100"
        >
          <X size={16} />
        </button>
      ) : null}
    </motion.div>
  );
}
