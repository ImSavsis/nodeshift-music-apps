import { Check, CloudDownload, LoaderCircle, LogIn, LogOut, RefreshCw, UserRound } from 'lucide-react';
import { api } from '../lib/api';
import { writeFlag } from '../lib/flags';
import { pluralTracks } from '../lib/format';
import { useSiteStore } from '../store/site';
import { toast } from '../store/toast';
import type { ListState } from '../lib/types';

function ListCard({ list, onDownload, busy }: { list: ListState; onDownload: () => void; busy: boolean }) {
  const phase = list.phase;
  const percent = list.total > 0 ? Math.round((list.done / list.total) * 100) : 0;
  const downloading = phase.phase === 'downloading' || phase.phase === 'loading';

  return (
    <div className="card static !p-4">
      <div className="flex items-center gap-4">
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-medium text-primary">{list.name}</p>
          <p className="mt-0.5 font-mono text-[0.6875rem] text-dim">
            {phase.phase === 'loading' ? 'Загружаем список…' : null}
            {phase.phase === 'downloading' ? `Скачано ${list.done} из ${list.total}` : null}
            {phase.phase === 'done' ? `Готово, ${pluralTracks(list.total)} на этом компьютере` : null}
            {phase.phase === 'failed' ? phase.text : null}
            {phase.phase === 'idle' ? (list.total > 0 ? pluralTracks(list.total) : 'Пока пусто') : null}
          </p>
        </div>
        {phase.phase === 'done' ? <Check size={18} className="shrink-0 text-ok" /> : null}
        {downloading ? (
          <LoaderCircle size={18} className="shrink-0 animate-spin text-muted" />
        ) : (
          <button type="button" onClick={onDownload} disabled={busy || list.total === 0} className="btn btn-ghost shrink-0 !px-4 !py-2 !text-xs">
            <CloudDownload size={14} />
            {phase.phase === 'done' ? 'Проверить ещё раз' : phase.phase === 'failed' ? 'Повторить' : 'Скачать'}
          </button>
        )}
      </div>
      {downloading && list.total > 0 ? (
        <div className="progress-track mt-3">
          <div className="progress-fill" style={{ width: `${percent}%` }} />
        </div>
      ) : null}
    </div>
  );
}

export function Site() {
  const snapshot = useSiteStore((state) => state.snapshot);
  const { user, busy, lastError, favorites, playlists, refreshing, lossless } = snapshot;

  async function login() {
    try {
      await api.siteLogin();
    } catch {
      toast('Не удалось открыть браузер для входа');
    }
  }

  async function toggleLossless(value: boolean) {
    writeFlag('nsm_lossless', value);
    await api.setLossless(value);
  }

  return (
    <div className="fade-in max-w-3xl">
      <div className="ph">
        <div>
          <h1>NodeShift Music</h1>
          <p>Вход через сайт нужен только чтобы скачать на этот компьютер свои плейлисты и понравившиеся треки, дальше всё работает без интернета.</p>
        </div>
      </div>

      {!user ? (
        <div className="card static flex flex-col items-start gap-4">
          <UserRound size={26} className="text-muted" />
          <div>
            <p className="font-display text-base font-semibold text-primary">Вы не вошли</p>
            <p className="mt-2 text-sm text-muted">
              Откроется браузер на music.nodeshift.space, после входа вы вернётесь прямо в это приложение. Пароли сюда не попадают.
            </p>
          </div>
          {busy ? (
            <div className="flex items-center gap-3">
              <span className="flex items-center gap-2 text-sm text-muted">
                <LoaderCircle size={16} className="animate-spin" />
                Ждём вход в браузере…
              </span>
              <button type="button" onClick={() => api.siteCancelLogin()} className="btn btn-ghost !px-4 !py-2 !text-xs">
                Отмена
              </button>
            </div>
          ) : (
            <button type="button" onClick={login} className="btn btn-primary">
              <LogIn size={16} />
              Войти через сайт
            </button>
          )}
          {lastError ? <p className="font-mono text-xs text-danger">{lastError}</p> : null}
        </div>
      ) : (
        <>
          <div className="card static flex items-center gap-4">
            <div className="flex h-12 w-12 shrink-0 items-center justify-center overflow-hidden rounded-full border border-border2 bg-surface2">
              <UserRound size={22} className="text-muted" />
            </div>
            <div className="min-w-0 flex-1">
              <p className="truncate font-display text-base font-semibold text-primary">{user.username ?? user.handle ?? 'Аккаунт'}</p>
              <p className="truncate font-mono text-xs text-dim">{user.email ?? (user.handle ? `@${user.handle}` : '')}</p>
            </div>
            <button type="button" onClick={() => api.siteRefresh()} disabled={refreshing || busy} className="btn btn-ghost !px-4 !py-2 !text-xs">
              <RefreshCw size={14} className={refreshing ? 'animate-spin' : ''} />
              Обновить списки
            </button>
            <button type="button" onClick={() => api.siteLogout()} className="btn btn-ghost !px-4 !py-2 !text-xs text-danger">
              <LogOut size={14} />
              Выйти
            </button>
          </div>

          {lastError ? <p className="mt-3 font-mono text-xs text-danger">{lastError}</p> : null}

          <h2 className="eyebrow mt-8">Понравившиеся</h2>
          <ListCard list={favorites} busy={busy} onDownload={() => api.siteDownloadFavorites()} />

          <h2 className="eyebrow mt-8">Мои плейлисты</h2>
          {playlists.length === 0 ? (
            <p className="py-6 text-sm text-muted">{refreshing ? 'Загружаем плейлисты…' : 'На сайте пока нет плейлистов.'}</p>
          ) : (
            <div className="flex flex-col gap-2">
              {playlists.map((list) => (
                <ListCard key={list.id} list={list} busy={busy} onDownload={() => api.siteDownloadPlaylist(list.id)} />
              ))}
            </div>
          )}

          <h2 className="eyebrow mt-8">Качество</h2>
          <label className="flex cursor-pointer items-center justify-between gap-4 rounded-tile border border-border2 bg-surface px-4 py-3">
            <span className="text-sm text-primary">
              Оригинальные файлы без потерь
              <span className="block text-xs text-muted">{lossless ? 'FLAC и WAV качаются как есть: тяжелее, зато точнее' : 'Скачивается сжатая версия: быстрее и занимает меньше места'}</span>
            </span>
            <input type="checkbox" checked={lossless} onChange={(event) => toggleLossless(event.target.checked)} className="h-5 w-5 accent-white" />
          </label>
        </>
      )}
    </div>
  );
}
