import { useMemo } from 'react';
import { motion } from 'framer-motion';
import { Play, Shuffle } from 'lucide-react';
import { TrackListItem } from '../components/TrackListItem';
import { pluralTracks } from '../lib/format';
import { useLibraryStore } from '../store/library';
import { usePlayerStore } from '../store/player';

const listMotion = {
  hidden: {},
  visible: { transition: { staggerChildren: 0.04 } }
};

export function Favorites() {
  const tracks = useLibraryStore((state) => state.tracks);
  const loaded = useLibraryStore((state) => state.loaded);
  const playMany = usePlayerStore((state) => state.playMany);

  const visible = useMemo(() => tracks.filter((track) => track.isFavorite).sort((a, b) => b.addedAt - a.addedAt), [tracks]);

  return (
    <div className="fade-in">
      <div className="ph">
        <div>
          <h1>Избранное</h1>
          <p>{visible.length > 0 ? `${pluralTracks(visible.length)}, которые вы отметили` : 'Треки, которые вы отметили'}</p>
        </div>
      </div>

      {visible.length > 0 ? (
        <div className="mb-6 flex flex-wrap gap-3">
          <button type="button" onClick={() => playMany(visible)} className="btn btn-primary">
            <Play size={16} fill="currentColor" />
            Слушать
          </button>
          <button type="button" onClick={() => playMany(visible, { shuffled: true })} className="btn btn-ghost">
            <Shuffle size={16} />
            Перемешать
          </button>
        </div>
      ) : null}

      {!loaded ? null : visible.length === 0 ? (
        <p className="py-16 text-center text-sm text-muted">В избранном пока пусто. Нажмите на сердце у любого трека.</p>
      ) : (
        <motion.div variants={listMotion} initial="hidden" animate="visible" className="flex flex-col gap-1">
          {visible.map((track) => (
            <TrackListItem key={track.id} track={track} queue={visible} />
          ))}
        </motion.div>
      )}
    </div>
  );
}
