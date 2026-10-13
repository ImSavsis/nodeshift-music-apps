import { motion } from 'framer-motion';
import { Link } from 'react-router-dom';
import { CoverImage } from './CoverImage';
import { pluralTracks } from '../lib/format';
import { useLibraryStore } from '../store/library';
import type { Playlist } from '../lib/types';

const cardMotion = {
  hidden: { opacity: 0, y: 16 },
  visible: { opacity: 1, y: 0 }
};

export function PlaylistCard({ playlist }: { playlist: Playlist }) {
  const tracks = useLibraryStore((state) => state.byId);
  const first = playlist.trackIds.map((id) => tracks.get(id)).find((track) => track?.coverName);
  const motionTrack = playlist.coverName ? null : playlist.trackIds.map((id) => tracks.get(id)).find((track) => track?.motionName);

  return (
    <motion.div variants={cardMotion}>
      <Link to={`/playlists/${playlist.id}`} className="group flex flex-col gap-3">
        <CoverImage
          coverName={playlist.coverName ?? first?.coverName ?? null}
          motionName={motionTrack?.motionName ?? null}
          alt={playlist.name}
          className="aspect-square w-full"
        />
        <div className="min-w-0">
          <p className="truncate text-sm font-medium text-primary">{playlist.name}</p>
          <p className="truncate font-mono text-[0.6875rem] text-dim">{pluralTracks(playlist.trackIds.length)}</p>
        </div>
      </Link>
    </motion.div>
  );
}
