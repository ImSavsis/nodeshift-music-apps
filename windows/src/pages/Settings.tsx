import { useMemo, useState } from 'react';
import { Download, Keyboard, RefreshCw } from 'lucide-react';
import { DiscordCard } from '../components/DiscordCard';
import { api } from '../lib/api';
import { readFlag, writeFlag } from '../lib/flags';
import { formatBytes, formatTotalDuration, pluralTracks } from '../lib/format';
import { useAppStore } from '../store/app';
import { useLibraryStore } from '../store/library';
import { useUiStore } from '../store/ui';

export function Settings() {
  const info = useAppStore((state) => state.info);
  const update = useAppStore((state) => state.update);
  const checking = useAppStore((state) => state.checking);
  const installing = useAppStore((state) => state.installing);
  const checkUpdate = useAppStore((state) => state.checkUpdate);
  const installUpdate = useAppStore((state) => state.installUpdate);
  const tracks = useLibraryStore((state) => state.tracks);
  const setHelpOpen = useUiStore((state) => state.setHelpOpen);
  const [motionAuto, setMotionAuto] = useState(() => readFlag('nsm_motion_auto', true));

  const stats = useMemo(
    () => ({
      count: tracks.length,
      bytes: tracks.reduce((sum, track) => sum + track.fileSize, 0),
      seconds: tracks.reduce((sum, track) => sum + track.durationMs / 1000, 0)
    }),
    [tracks]
  );

  function changeMotion(value: boolean) {
    setMotionAuto(value);
    writeFlag('nsm_motion_auto', value);
    api.setMotionAuto(value);
  }

  return (
    <div className="fade-in max-w-2xl">
      <div className="ph">
        <div>
          <h1>Настройки</h1>
          <p>Всё хранится на этом компьютере</p>
        </div>
      </div>

      <h2 className="eyebrow">Библиотека</h2>
      <div className="card static !p-4">
        <p className="text-sm text-primary">{pluralTracks(stats.count)}</p>
        <p className="mt-1 font-mono text-xs text-dim">
          {formatBytes(stats.bytes)} · {formatTotalDuration(stats.seconds)}
        </p>
      </div>

      <h2 className="eyebrow mt-8">Импорт</h2>
      <label className="flex cursor-pointer items-center justify-between gap-4 rounded-tile border border-border2 bg-surface px-4 py-3">
        <span className="text-sm text-primary">
          Искать анимированные обложки
          <span className="block text-xs text-muted">при импорте подтягивать живую обложку альбома, если она есть</span>
        </span>
        <input type="checkbox" checked={motionAuto} onChange={(event) => changeMotion(event.target.checked)} className="h-5 w-5 accent-white" />
      </label>

      <DiscordCard />

      <h2 className="eyebrow mt-8">Приложение</h2>
      <div className="card static flex flex-col gap-4 !p-4">
        <div>
          <p className="text-sm text-primary">NS Music для Windows</p>
          <p className="mt-1 font-mono text-xs text-dim">
            версия {info?.version ?? '…'} · сборка {info?.build ?? '…'}
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          {update ? (
            <button type="button" onClick={installUpdate} disabled={installing} className="btn btn-primary !px-4 !py-2 !text-xs">
              <Download size={14} />
              {installing ? 'Скачиваем…' : `Обновить до ${update.version}`}
            </button>
          ) : (
            <button type="button" onClick={() => checkUpdate(false)} disabled={checking} className="btn btn-ghost !px-4 !py-2 !text-xs">
              <RefreshCw size={14} className={checking ? 'animate-spin' : ''} />
              Проверить обновления
            </button>
          )}
          <button type="button" onClick={() => setHelpOpen(true)} className="btn btn-ghost !px-4 !py-2 !text-xs">
            <Keyboard size={14} />
            Горячие клавиши
          </button>
        </div>
        {update?.notes ? <p className="text-xs text-muted">{update.notes}</p> : null}
      </div>
    </div>
  );
}
