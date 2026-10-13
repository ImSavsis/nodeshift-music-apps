import { useEffect, useRef } from 'react';
import { motion } from 'framer-motion';
import { LayoutGrid, LayoutList, LoaderCircle, RefreshCw, Shuffle, Sparkles } from 'lucide-react';
import { SearchBar } from './SearchBar';
import { TrackCard } from './TrackCard';
import { TrackListItem } from './TrackListItem';
import { PAGE_SIZE, useCatalogStore } from '../store/catalog';
import type { CatalogSort } from '../store/catalog';
import { usePlayerStore } from '../store/player';
import { toast } from '../store/toast';

const SORTS: Array<{ value: CatalogSort; label: string }> = [
  { value: 'new', label: 'Новые' },
  { value: 'popular', label: 'Популярные' },
  { value: 'title', label: 'По названию' }
];

const FORMATS = [
  { value: '', label: 'Все' },
  { value: 'flac', label: 'FLAC' },
  { value: 'mp3', label: 'MP3' }
];

const gridMotion = {
  hidden: {},
  visible: { transition: { staggerChildren: 0.04 } }
};

interface CatalogSectionProps {
  view: 'grid' | 'list';
  onView: (value: 'grid' | 'list') => void;
}

export function CatalogSection({ view, onView }: CatalogSectionProps) {
  const tracks = useCatalogStore((state) => state.tracks);
  const query = useCatalogStore((state) => state.query);
  const sort = useCatalogStore((state) => state.sort);
  const format = useCatalogStore((state) => state.format);
  const isLoading = useCatalogStore((state) => state.isLoading);
  const hasMore = useCatalogStore((state) => state.hasMore);
  const failed = useCatalogStore((state) => state.failed);
  const startIfNeeded = useCatalogStore((state) => state.startIfNeeded);
  const setQuery = useCatalogStore((state) => state.setQuery);
  const setSort = useCatalogStore((state) => state.setSort);
  const setFormat = useCatalogStore((state) => state.setFormat);
  const reload = useCatalogStore((state) => state.reload);
  const loadMore = useCatalogStore((state) => state.loadMore);
  const wave = useCatalogStore((state) => state.wave);
  const playMany = usePlayerStore((state) => state.playMany);
  const sentinel = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    startIfNeeded();
  }, [startIfNeeded]);

  useEffect(() => {
    const element = sentinel.current;
    if (!element || !hasMore) return;
    const observer = new IntersectionObserver((entries) => {
      if (entries.some((entry) => entry.isIntersecting)) loadMore();
    }, { rootMargin: '400px' });
    observer.observe(element);
    return () => observer.disconnect();
  }, [hasMore, loadMore, tracks.length]);

  async function startWave() {
    const picked = await wave();
    if (picked.length === 0) return;
    playMany(picked);
    toast('Играет случайная волна');
  }

  const isSearching = query.trim().length > 0;

  return (
    <div>
      <div className="mb-6 flex flex-wrap items-center gap-3">
        <SearchBar value={query} onChange={setQuery} placeholder="Поиск по всем трекам сайта" className="w-full max-w-md" />
        <button type="button" onClick={startWave} className="btn btn-primary">
          <Sparkles size={16} />
          Случайная волна
        </button>
        <button type="button" onClick={() => playMany(tracks, { shuffled: true })} disabled={tracks.length === 0} className="btn btn-ghost">
          <Shuffle size={16} />
          Перемешать
        </button>
      </div>

      <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
        <h2 className="eyebrow !mb-0">{isSearching ? 'Результаты поиска' : 'Каталог сайта'}</h2>
        <div className="flex flex-wrap items-center gap-2">
          {SORTS.map((item) => (
            <button key={item.value} type="button" onClick={() => setSort(item.value)} className={`chip ${sort === item.value ? 'on' : ''}`}>
              {item.label}
            </button>
          ))}
          <span className="mx-1 h-5 w-px bg-border2" />
          {FORMATS.map((item) => (
            <button key={item.label} type="button" onClick={() => setFormat(item.value)} className={`chip ${format === item.value ? 'on' : ''}`}>
              {item.label}
            </button>
          ))}
          <span className="mx-1 h-5 w-px bg-border2" />
          <button type="button" onClick={() => onView('grid')} aria-label="Сеткой" className={`chip !px-2.5 ${view === 'grid' ? 'on' : ''}`}>
            <LayoutGrid size={15} />
          </button>
          <button type="button" onClick={() => onView('list')} aria-label="Списком" className={`chip !px-2.5 ${view === 'list' ? 'on' : ''}`}>
            <LayoutList size={15} />
          </button>
        </div>
      </div>

      {tracks.length === 0 ? (
        <div className="flex flex-col items-center gap-4 py-16 text-center">
          {isLoading ? (
            <LoaderCircle size={26} className="animate-spin text-muted" />
          ) : failed ? (
            <>
              <p className="text-sm text-muted">Не получилось загрузить каталог. Проверьте интернет.</p>
              <button type="button" onClick={reload} className="btn btn-ghost">
                <RefreshCw size={15} />
                Повторить
              </button>
            </>
          ) : (
            <p className="text-sm text-muted">Ничего не найдено.</p>
          )}
        </div>
      ) : view === 'grid' ? (
        <motion.div key={`grid-${sort}-${format}-${query}`} variants={gridMotion} initial="hidden" animate="visible" className="track-grid">
          {tracks.map((track) => (
            <TrackCard key={track.id} track={track} queue={tracks} showsDownloaded />
          ))}
        </motion.div>
      ) : (
        <motion.div key={`list-${sort}-${format}-${query}`} variants={gridMotion} initial="hidden" animate="visible" className="flex flex-col gap-1">
          {tracks.map((track) => (
            <TrackListItem key={track.id} track={track} queue={tracks} showsDownloaded />
          ))}
        </motion.div>
      )}

      {hasMore && tracks.length > 0 ? (
        <div ref={sentinel} className="mt-10 flex justify-center">
          <button type="button" onClick={loadMore} disabled={isLoading} className="btn btn-ghost">
            {isLoading ? <LoaderCircle size={15} className="animate-spin" /> : null}
            {isLoading ? 'Загрузка…' : `Показать ещё ${PAGE_SIZE}`}
          </button>
        </div>
      ) : null}
    </div>
  );
}
