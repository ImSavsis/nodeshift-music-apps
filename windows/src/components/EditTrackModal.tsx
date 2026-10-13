import { useEffect, useState } from 'react';
import { Trash2 } from 'lucide-react';
import { Modal } from './Modal';
import { api } from '../lib/api';
import { scheduleReload } from '../store/library';
import { toast } from '../store/toast';
import { useUiStore } from '../store/ui';

export function EditTrackModal() {
  const track = useUiStore((state) => state.editTrack);
  const close = useUiStore((state) => state.closeEditTrack);

  const [title, setTitle] = useState('');
  const [artist, setArtist] = useState('');
  const [album, setAlbum] = useState('');
  const [number, setNumber] = useState('');
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [isBusy, setIsBusy] = useState(false);

  useEffect(() => {
    if (!track) return;
    setTitle(track.title);
    setArtist(track.artist);
    setAlbum(track.album ?? '');
    setNumber(track.trackNumber ? String(track.trackNumber) : '');
    setConfirmDelete(false);
  }, [track]);

  async function save() {
    if (!track || !title.trim() || !artist.trim()) return;
    const parsed = Number.parseInt(number, 10);
    setIsBusy(true);
    try {
      await api.updateTrack(track.id, title.trim(), artist.trim(), album.trim() || null, Number.isFinite(parsed) && parsed > 0 ? parsed : null);
      toast('Сохранено, теги записаны в файл');
      scheduleReload();
      close();
    } catch {
      toast('Не удалось сохранить');
    } finally {
      setIsBusy(false);
    }
  }

  async function remove() {
    if (!track) return;
    setIsBusy(true);
    try {
      await api.deleteTrack(track.id);
      toast('Трек удалён');
      scheduleReload();
      close();
    } catch {
      toast('Не удалось удалить');
    } finally {
      setIsBusy(false);
    }
  }

  return (
    <Modal isOpen={track !== null} onClose={close} title="Редактировать трек">
      <div className="flex flex-col gap-4">
        <div>
          <label className="eyebrow !mb-1.5 block">Название</label>
          <input value={title} onChange={(event) => setTitle(event.target.value)} className="field" />
        </div>
        <div>
          <label className="eyebrow !mb-1.5 block">Исполнитель</label>
          <input value={artist} onChange={(event) => setArtist(event.target.value)} className="field" />
        </div>
        <div className="grid grid-cols-[1fr_6rem] gap-3">
          <div>
            <label className="eyebrow !mb-1.5 block">Альбом</label>
            <input value={album} onChange={(event) => setAlbum(event.target.value)} className="field" />
          </div>
          <div>
            <label className="eyebrow !mb-1.5 block">№</label>
            <input value={number} onChange={(event) => setNumber(event.target.value.replace(/\D/g, '').slice(0, 3))} className="field" inputMode="numeric" />
          </div>
        </div>

        <button type="button" onClick={save} disabled={isBusy || !title.trim() || !artist.trim()} className="btn btn-primary w-full">
          Сохранить
        </button>

        {confirmDelete ? (
          <div className="flex gap-2">
            <button type="button" onClick={remove} disabled={isBusy} className="btn w-full border-danger/50 bg-danger/10 text-danger hover:bg-danger/20">
              Да, удалить вместе с файлом
            </button>
            <button type="button" onClick={() => setConfirmDelete(false)} className="btn btn-ghost shrink-0">
              Отмена
            </button>
          </div>
        ) : (
          <button type="button" onClick={() => setConfirmDelete(true)} className="btn btn-ghost w-full text-danger">
            <Trash2 size={16} />
            Удалить трек
          </button>
        )}
      </div>
    </Modal>
  );
}
