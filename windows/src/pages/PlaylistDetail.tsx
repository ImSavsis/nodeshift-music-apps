import { useMemo, useState } from 'react';
import { motion } from 'framer-motion';
import { useNavigate, useParams } from 'react-router-dom';
import { Check, Pencil, Play, Plus, Shuffle, Trash2 } from 'lucide-react';
import { CoverImage } from '../components/CoverImage';
import { SearchBar } from '../components/SearchBar';
import { TrackListItem } from '../components/TrackListItem';
import { useDebounce } from '../hooks/useDebounce';
import { api } from '../lib/api';
import { formatTotalDuration, pluralTracks } from '../lib/format';
import { scheduleReload, useLibraryStore } from '../store/library';
import { usePlayerStore } from '../store/player';
import { toast } from '../store/toast';

const listMotion = {
  hidden: {},
  visible: { transition: { staggerChildren: 0.04 } }
};

function normalize(text: string): string {
  return text.toLowerCase().replace(/ё/g, 'е');
}

export function PlaylistDetail() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const playlist = useLibraryStore((state) => state.playlists.find((item) => item.id === id) ?? null);
  const allTracks = useLibraryStore((state) => state.tracks);
  const byId = useLibraryStore((state) => state.byId);
  const loaded = useLibraryStore((state) => state.loaded);
  const playMany = usePlayerStore((state) => state.playMany);

  const [isEditingName, setIsEditingName] = useState(false);
  const [nameDraft, setNameDraft] = useState('');
  const [isAdding, setIsAdding] = useState(false);
  const [addSearch, setAddSearch] = useState('');
  const debouncedSearch = useDebounce(addSearch, 200);
  const [confirmDelete, setConfirmDelete] = useState(false);

  const tracks = useMemo(() => (playlist ? playlist.trackIds.map((trackId) => byId.get(trackId)).filter((track) => track !== undefined) : []), [playlist, byId]);
  const totalSeconds = useMemo(() => tracks.reduce((sum, track) => sum + track.durationMs / 1000, 0), [tracks]);

  const searchResults = useMemo(() => {
    const needle = normalize(debouncedSearch.trim());
    if (!isAdding || !needle || !playlist) return [];
    const inList = new Set(playlist.trackIds);
    return allTracks.filter((track) => !inList.has(track.id) && normalize(`${track.title} ${track.artist}`).includes(needle)).slice(0, 10);
  }, [allTracks, debouncedSearch, isAdding, playlist]);

  if (!playlist) {
    return loaded ? <p className="px-6 py-24 text-center text-sm text-muted">Плейлист не найден.</p> : null;
  }

  const coverTrack = tracks.find((track) => track.coverName);
  const motionTrack = playlist.coverName ? null : tracks.find((track) => track.motionName);

  async function saveName() {
    if (!playlist) return;
    const name = nameDraft.trim();
    setIsEditingName(false);
    if (!name || name === playlist.name) return;
    await api.playlistRename(playlist.id, name);
    scheduleReload();
  }

  async function addTrack(trackId: string) {
    if (!playlist) return;
    await api.playlistAdd(playlist.id, trackId);
    scheduleReload();
  }

  async function removeTrack(trackId: string) {
    if (!playlist) return;
    await api.playlistRemove(playlist.id, trackId);
    scheduleReload();
  }

  async function removePlaylist() {
    if (!playlist) return;
    try {
      await api.playlistDelete(playlist.id);
      scheduleReload();
      toast('Плейлист удалён');
      navigate('/playlists');
    } catch {
      toast('Не удалось удалить плейлист');
    }
  }

  return (
    <div className="fade-in">
      <div className="mb-10 flex flex-row items-end gap-6">
        <div className="relative h-44 w-44 shrink-0">
          <CoverImage
            coverName={playlist.coverName ?? coverTrack?.coverName ?? null}
            motionName={motionTrack?.motionName ?? null}
            alt={playlist.name}
            className="h-44 w-44"
            rounded="rounded-card"
          />
        </div>

        <div className="min-w-0 flex-1">
          <p className="eyebrow !mb-2">Плейлист</p>
          {isEditingName ? (
            <div className="flex items-center gap-2">
              <input
                value={nameDraft}
                onChange={(event) => setNameDraft(event.target.value)}
                onKeyDown={(event) => {
                  if (event.key === 'Enter') saveName();
                  if (event.key === 'Escape') setIsEditingName(false);
                }}
                autoFocus
                className="field max-w-md !text-xl"
              />
              <button type="button" onClick={saveName} className="text-accent" aria-label="Сохранить название">
                <Check size={20} />
              </button>
            </div>
          ) : (
            <div className="flex items-center gap-2">
              <h1 className="truncate font-display text-2xl font-semibold tracking-tight text-primary">{playlist.name}</h1>
              <button
                type="button"
                onClick={() => {
                  setNameDraft(playlist.name);
                  setIsEditingName(true);
                }}
                className="text-muted hover:text-primary"
                aria-label="Переименовать"
              >
                <Pencil size={16} />
              </button>
            </div>
          )}
          <p className="mt-2 font-mono text-xs text-dim">
            {pluralTracks(tracks.length)}
            {tracks.length > 0 ? ` · ${formatTotalDuration(totalSeconds)}` : ''}
          </p>
          <div className="mt-4 flex flex-wrap gap-2">
            {tracks.length > 0 ? (
              <>
                <button type="button" onClick={() => playMany(tracks)} className="btn btn-primary !px-5">
                  <Play size={15} fill="currentColor" />
                  Слушать
                </button>
                <button type="button" onClick={() => playMany(tracks, { shuffled: true })} className="btn btn-ghost !px-4" aria-label="Перемешать">
                  <Shuffle size={15} />
                </button>
              </>
            ) : null}
            {confirmDelete ? (
              <>
                <button type="button" onClick={removePlaylist} className="btn border-danger/50 bg-danger/10 text-danger hover:bg-danger/20">
                  Да, удалить плейлист
                </button>
                <button type="button" onClick={() => setConfirmDelete(false)} className="btn btn-ghost">
                  Отмена
                </button>
              </>
            ) : (
              <button type="button" onClick={() => setConfirmDelete(true)} className="btn btn-ghost !px-4 text-danger" aria-label="Удалить плейлист">
                <Trash2 size={15} />
              </button>
            )}
          </div>
        </div>
      </div>

      <div className="mb-8">
        <button type="button" onClick={() => setIsAdding((value) => !value)} className="btn btn-ghost mb-3">
          <Plus size={16} />
          Добавить треки
        </button>
        {isAdding ? (
          <div className="card static">
            <SearchBar value={addSearch} onChange={setAddSearch} placeholder="Найти трек, чтобы добавить" />
            {searchResults.length > 0 ? (
              <div className="mt-3 flex flex-col gap-1">
                {searchResults.map((track) => (
                  <button
                    key={track.id}
                    type="button"
                    onClick={() => addTrack(track.id)}
                    className="flex items-center justify-between rounded-tile px-3 py-2 text-left hover:bg-surface2"
                  >
                    <span className="min-w-0 truncate text-sm text-primary">
                      {track.title} <span className="text-muted">— {track.artist}</span>
                    </span>
                    <Plus size={16} className="shrink-0 text-primary" />
                  </button>
                ))}
              </div>
            ) : null}
          </div>
        ) : null}
      </div>

      {tracks.length === 0 ? (
        <p className="py-16 text-center text-sm text-muted">В плейлисте пока нет треков.</p>
      ) : (
        <motion.div variants={listMotion} initial="hidden" animate="visible" className="flex flex-col gap-1">
          {tracks.map((track) => (
            <TrackListItem key={track.id} track={track} queue={tracks} onRemove={() => removeTrack(track.id)} />
          ))}
        </motion.div>
      )}
    </div>
  );
}
