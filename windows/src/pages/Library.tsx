import { useMemo, useState } from 'react';
import { motion } from 'framer-motion';
import { useNavigate } from 'react-router-dom';
import { Cloud, LayoutGrid, LayoutList, Play, Shuffle, Upload } from 'lucide-react';
import { CatalogSection } from '../components/CatalogSection';
import { SearchBar } from '../components/SearchBar';
import { TrackCard } from '../components/TrackCard';
import { TrackListItem } from '../components/TrackListItem';
import { useDebounce } from '../hooks/useDebounce';
import { formatTotalDuration, pluralTracks } from '../lib/format';
import { useLibraryStore } from '../store/library';
import { usePlayerStore } from '../store/player';
import type { Track } from '../lib/types';

const PAGE_SIZE = 60;
const VIEW_KEY = 'nsm_view';
const MODE_KEY = 'nsm_library_mode';

type Mode = 'mine' | 'catalog';

function readMode(): Mode | null {
  try {
    const raw = localStorage.getItem(MODE_KEY);
    return raw === 'mine' || raw === 'catalog' ? raw : null;
  } catch {
    return null;
  }
}

type SortKey = 'new' | 'popular' | 'title' | 'artist';

const SORTS: Array<{ value: SortKey; label: string }> = [
  { value: 'new', label: 'Новые' },
  { value: 'popular', label: 'Популярные' },
  { value: 'title', label: 'По названию' },
  { value: 'artist', label: 'По артисту' }
];

const gridMotion = {
  hidden: {},
  visible: { transition: { staggerChildren: 0.04 } }
};

function readView(): 'grid' | 'list' {
  try {
    return localStorage.getItem(VIEW_KEY) === 'list' ? 'list' : 'grid';
  } catch {
    return 'grid';
  }
}

function normalize(text: string): string {
  return text.toLowerCase().replace(/ё/g, 'е');
}

function sortTracks(tracks: Track[], sort: SortKey): Track[] {
  const copy = [...tracks];
  if (sort === 'new') copy.sort((a, b) => b.addedAt - a.addedAt);
  else if (sort === 'popular') copy.sort((a, b) => b.playCount - a.playCount || b.addedAt - a.addedAt);
  else if (sort === 'title') copy.sort((a, b) => a.title.localeCompare(b.title, 'ru'));
  else copy.sort((a, b) => a.artist.localeCompare(b.artist, 'ru') || (a.album ?? '').localeCompare(b.album ?? '', 'ru') || (a.trackNumber ?? 0) - (b.trackNumber ?? 0));
  return copy;
}

export function Library() {
  const navigate = useNavigate();
  const tracks = useLibraryStore((state) => state.tracks);
  const loaded = useLibraryStore((state) => state.loaded);
  const playMany = usePlayerStore((state) => state.playMany);

  const [chosen, setChosen] = useState<Mode | null>(readMode);
  const mode: Mode = chosen ?? (loaded && tracks.length === 0 ? 'catalog' : 'mine');
  const [search, setSearch] = useState('');
  const debounced = useDebounce(search, 200);
  const [sort, setSort] = useState<SortKey>('new');
  const [format, setFormat] = useState('');
  const [view, setView] = useState<'grid' | 'list'>(readView);
  const [limit, setLimit] = useState(PAGE_SIZE);

  const formats = useMemo(() => {
    const counts = new Map<string, number>();
    for (const track of tracks) counts.set(track.format.toLowerCase(), (counts.get(track.format.toLowerCase()) ?? 0) + 1);
    return [...counts.entries()].sort((a, b) => b[1] - a[1]).slice(0, 5).map(([name]) => name);
  }, [tracks]);

  const recent = useMemo(
    () =>
      tracks
        .filter((track) => track.lastPlayedAt)
        .sort((a, b) => (b.lastPlayedAt ?? 0) - (a.lastPlayedAt ?? 0))
        .slice(0, 12),
    [tracks]
  );

  const visible = useMemo(() => {
    const needle = normalize(debounced.trim());
    const filtered = tracks.filter((track) => {
      if (format && track.format.toLowerCase() !== format) return false;
      if (!needle) return true;
      return normalize(`${track.title} ${track.artist} ${track.album ?? ''}`).includes(needle);
    });
    return sortTracks(filtered, sort);
  }, [tracks, debounced, sort, format]);

  const totalSeconds = useMemo(() => tracks.reduce((sum, track) => sum + track.durationMs / 1000, 0), [tracks]);
  const isSearching = debounced.trim().length > 0;
  const shown = visible.slice(0, limit);

  function chooseView(next: 'grid' | 'list') {
    setView(next);
    try {
      localStorage.setItem(VIEW_KEY, next);
    } catch {
      return;
    }
  }

  function pickMode(value: Mode) {
    try {
      localStorage.setItem(MODE_KEY, value);
    } catch {
      return;
    } finally {
      setChosen(value);
    }
  }

  const modeSwitch = (
    <div className="mb-6 flex items-center gap-2">
      <button type="button" onClick={() => pickMode('mine')} className={`chip ${mode === 'mine' ? 'on' : ''}`}>
        Моя музыка
      </button>
      <button type="button" onClick={() => pickMode('catalog')} className={`chip ${mode === 'catalog' ? 'on' : ''}`}>
        <Cloud size={14} />
        Весь каталог
      </button>
    </div>
  );

  if (mode === 'catalog') {
    return (
      <div className="fade-in">
        <div className="ph">
          <div>
            <h1>Треки</h1>
            <p>Все треки NodeShift, играют онлайн</p>
          </div>
        </div>
        {modeSwitch}
        <CatalogSection view={view} onView={chooseView} />
      </div>
    );
  }

  if (loaded && tracks.length === 0) {
    return (
      <div className="fade-in">
        <div className="ph">
          <div>
            <h1>Треки</h1>
            <p>Вся ваша музыка лежит локально, на этом компьютере</p>
          </div>
        </div>
        {modeSwitch}
        <div className="card static flex max-w-xl flex-col items-start gap-4">
          <Upload size={26} className="text-muted" />
          <div>
            <p className="font-display text-base font-semibold text-primary">Библиотека пока пустая</p>
            <p className="mt-2 text-sm text-muted">
              Перетащите в окно файлы, папку или архив. Название и артист возьмутся из тегов или из имени файла, альбом, обложка и текст подтянутся сами.
            </p>
          </div>
          <button type="button" onClick={() => navigate('/import')} className="btn btn-primary">
            <Upload size={16} />
            Добавить музыку
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="fade-in">
      <div className="ph">
        <div>
          <h1>Треки</h1>
          <p>
            {tracks.length > 0 ? `${pluralTracks(tracks.length)} · ${formatTotalDuration(totalSeconds)}` : 'Загружаем библиотеку…'}
          </p>
        </div>
        <SearchBar value={search} onChange={setSearch} className="w-full max-w-xs" />
      </div>

      {modeSwitch}

      <div className="mb-8 flex flex-wrap items-center gap-3">
        <button type="button" onClick={() => playMany(visible, { shuffled: true })} disabled={visible.length === 0} className="btn btn-primary">
          <Shuffle size={16} />
          Перемешать
        </button>
        <button type="button" onClick={() => playMany(visible)} disabled={visible.length === 0} className="btn btn-ghost">
          <Play size={16} fill="currentColor" />
          Слушать по порядку
        </button>
      </div>

      {!isSearching && recent.length > 0 ? (
        <section className="mb-10">
          <h2 className="eyebrow">Недавно слушали</h2>
          <div className="flex gap-5 overflow-x-auto pb-2">
            {recent.map((track) => (
              <div key={track.id} className="w-40 shrink-0">
                <TrackCard track={track} queue={recent} />
              </div>
            ))}
          </div>
        </section>
      ) : null}

      <section>
        <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
          <h2 className="eyebrow !mb-0">{isSearching ? 'Результаты поиска' : 'Библиотека'}</h2>
          <div className="flex flex-wrap items-center gap-2">
            {SORTS.map((item) => (
              <button key={item.value} type="button" onClick={() => setSort(item.value)} className={`chip ${sort === item.value ? 'on' : ''}`}>
                {item.label}
              </button>
            ))}
            {formats.length > 1 ? (
              <>
                <span className="mx-1 h-5 w-px bg-border2" />
                <button type="button" onClick={() => setFormat('')} className={`chip ${format === '' ? 'on' : ''}`}>
                  Все
                </button>
                {formats.map((name) => (
                  <button key={name} type="button" onClick={() => setFormat(name)} className={`chip uppercase ${format === name ? 'on' : ''}`}>
                    {name}
                  </button>
                ))}
              </>
            ) : null}
            <span className="mx-1 h-5 w-px bg-border2" />
            <button type="button" onClick={() => chooseView('grid')} aria-label="Сеткой" className={`chip !px-2.5 ${view === 'grid' ? 'on' : ''}`}>
              <LayoutGrid size={15} />
            </button>
            <button type="button" onClick={() => chooseView('list')} aria-label="Списком" className={`chip !px-2.5 ${view === 'list' ? 'on' : ''}`}>
              <LayoutList size={15} />
            </button>
          </div>
        </div>

        {visible.length === 0 ? (
          <p className="py-16 text-center text-sm text-muted">Ничего не найдено.</p>
        ) : view === 'grid' ? (
          <motion.div key={`grid-${sort}-${format}-${debounced}`} variants={gridMotion} initial="hidden" animate="visible" className="track-grid">
            {shown.map((track) => (
              <TrackCard key={track.id} track={track} queue={visible} />
            ))}
          </motion.div>
        ) : (
          <motion.div key={`list-${sort}-${format}-${debounced}`} variants={gridMotion} initial="hidden" animate="visible" className="flex flex-col gap-1">
            {shown.map((track) => (
              <TrackListItem key={track.id} track={track} queue={visible} />
            ))}
          </motion.div>
        )}

        {visible.length > shown.length ? (
          <div className="mt-10 flex justify-center">
            <button type="button" onClick={() => setLimit((value) => value + PAGE_SIZE)} className="btn btn-ghost">
              Показать ещё
            </button>
          </div>
        ) : null}
      </section>
    </div>
  );
}
