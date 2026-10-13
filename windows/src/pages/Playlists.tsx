import { useState } from 'react';
import { motion } from 'framer-motion';
import { useNavigate } from 'react-router-dom';
import { Plus } from 'lucide-react';
import { Modal } from '../components/Modal';
import { PlaylistCard } from '../components/PlaylistCard';
import { api } from '../lib/api';
import { scheduleReload, useLibraryStore } from '../store/library';
import { toast } from '../store/toast';

const gridMotion = {
  hidden: {},
  visible: { transition: { staggerChildren: 0.05 } }
};

export function Playlists() {
  const navigate = useNavigate();
  const playlists = useLibraryStore((state) => state.playlists);
  const loaded = useLibraryStore((state) => state.loaded);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [newName, setNewName] = useState('');
  const [isCreating, setIsCreating] = useState(false);

  async function handleCreate() {
    const name = newName.trim();
    if (!name) return;
    setIsCreating(true);
    try {
      const playlist = await api.createPlaylist(name);
      scheduleReload();
      setIsModalOpen(false);
      setNewName('');
      navigate(`/playlists/${playlist.id}`);
    } catch {
      toast('Не получилось создать плейлист');
    } finally {
      setIsCreating(false);
    }
  }

  return (
    <div className="fade-in">
      <div className="ph">
        <div>
          <h1>Плейлисты</h1>
          <p>Ваши подборки на этом компьютере</p>
        </div>
      </div>

      {loaded ? (
        <motion.div variants={gridMotion} initial="hidden" animate="visible" className="track-grid">
          <motion.button
            type="button"
            variants={{ hidden: { opacity: 0, y: 16 }, visible: { opacity: 1, y: 0 } }}
            onClick={() => setIsModalOpen(true)}
            className="flex aspect-square w-full flex-col items-center justify-center gap-2 rounded-card border border-dashed border-border2 text-muted transition-colors hover:border-white/40 hover:bg-surface hover:text-primary"
          >
            <Plus size={22} />
            <span className="text-sm">Новый плейлист</span>
          </motion.button>

          {playlists.map((playlist) => (
            <PlaylistCard key={playlist.id} playlist={playlist} />
          ))}
        </motion.div>
      ) : null}

      <Modal isOpen={isModalOpen} onClose={() => setIsModalOpen(false)} title="Новый плейлист">
        <input
          value={newName}
          onChange={(event) => setNewName(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === 'Enter') handleCreate();
          }}
          placeholder="Название плейлиста"
          autoFocus
          className="field"
        />
        <button type="button" onClick={handleCreate} disabled={!newName.trim() || isCreating} className="btn btn-primary mt-5 w-full">
          Создать
        </button>
      </Modal>
    </div>
  );
}
