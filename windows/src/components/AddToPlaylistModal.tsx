import { useEffect, useState } from 'react';
import { ListMusic, Plus } from 'lucide-react';
import { Modal } from './Modal';
import { CoverImage } from './CoverImage';
import { api } from '../lib/api';
import { pluralTracks } from '../lib/format';
import { scheduleReload, useLibraryStore } from '../store/library';
import { toast } from '../store/toast';
import { useUiStore } from '../store/ui';
import type { Playlist } from '../lib/types';

export function AddToPlaylistModal() {
  const track = useUiStore((state) => state.playlistPickerTrack);
  const close = useUiStore((state) => state.closePlaylistPicker);
  const playlists = useLibraryStore((state) => state.playlists);
  const byId = useLibraryStore((state) => state.byId);
  const [newName, setNewName] = useState('');
  const [isBusy, setIsBusy] = useState(false);

  useEffect(() => {
    if (track) setNewName('');
  }, [track]);

  async function addTo(playlist: Playlist) {
    if (!track) return;
    if (playlist.trackIds.includes(track.id)) {
      toast('Этот трек уже в плейлисте');
      return;
    }
    setIsBusy(true);
    try {
      await api.playlistAdd(playlist.id, track.id);
      toast(`Добавлено в «${playlist.name}»`);
      scheduleReload();
      close();
    } catch {
      toast('Не получилось добавить');
    } finally {
      setIsBusy(false);
    }
  }

  async function createAndAdd() {
    const name = newName.trim();
    if (!name || !track) return;
    setIsBusy(true);
    try {
      const playlist = await api.createPlaylist(name);
      await api.playlistAdd(playlist.id, track.id);
      toast(`Создан плейлист «${name}»`);
      scheduleReload();
      close();
    } catch {
      toast('Не получилось создать плейлист');
    } finally {
      setIsBusy(false);
    }
  }

  return (
    <Modal isOpen={track !== null} onClose={close} title="Добавить в плейлист">
      {track ? (
        <p className="mb-4 truncate font-mono text-xs text-dim">
          {track.title} — {track.artist}
        </p>
      ) : null}

      <div className="mb-4 flex gap-2">
        <input
          value={newName}
          onChange={(event) => setNewName(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === 'Enter') createAndAdd();
          }}
          placeholder="Новый плейлист"
          className="field"
        />
        <button type="button" onClick={createAndAdd} disabled={!newName.trim() || isBusy} className="btn btn-primary shrink-0 !px-4" aria-label="Создать">
          <Plus size={16} />
        </button>
      </div>

      <div className="flex max-h-[40vh] flex-col gap-1 overflow-y-auto">
        {playlists.length === 0 ? <p className="py-6 text-center text-sm text-muted">Плейлистов пока нет, создайте первый выше.</p> : null}
        {playlists.map((playlist) => {
          const first = playlist.trackIds.map((id) => byId.get(id)).find((item) => item?.coverName);
          return (
            <button
              key={playlist.id}
              type="button"
              disabled={isBusy}
              onClick={() => addTo(playlist)}
              className="flex items-center gap-3 rounded-tile px-2 py-2 text-left transition-colors hover:bg-white/10 disabled:opacity-50"
            >
              <CoverImage coverName={playlist.coverName ?? first?.coverName ?? null} alt={playlist.name} className="h-10 w-10 shrink-0" rounded="rounded-tile" live={false} playMotion={false} />
              <span className="min-w-0 flex-1">
                <span className="block truncate text-sm text-primary">{playlist.name}</span>
                <span className="block font-mono text-[0.6875rem] text-dim">{pluralTracks(playlist.trackIds.length)}</span>
              </span>
              <ListMusic size={16} className="shrink-0 text-muted" />
            </button>
          );
        })}
      </div>
    </Modal>
  );
}
