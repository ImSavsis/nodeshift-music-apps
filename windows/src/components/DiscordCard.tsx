import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { RefreshCw } from 'lucide-react';
import { discordApi } from '../lib/discord';
import type { DiscordInfo } from '../lib/discord';
import { isTauri } from '../lib/tauri';

const HINTS: Record<string, string> = {
  showing: 'В Discord видно «Слушает»: трек, исполнитель, обложка и время.',
  idle: 'Включи трек на этом компьютере или на телефоне с тем же аккаунтом, и он появится в Discord.',
  waiting_for_discord: 'Запусти приложение Discord на этом компьютере. Браузерная версия не подходит.',
  needs_login: 'Войди в аккаунт NodeShift на вкладке «Сайт», чтобы подхватывать и то, что играет на телефоне.',
  hub_unreachable: 'Нет связи с сервером. Приложение попробует снова само.',
  disabled: 'Показ в Discord выключен.'
};

function dotClass(status: string): string {
  if (status === 'showing') return 'bg-ok';
  if (status === 'idle') return 'bg-white/50';
  if (status === 'disabled') return 'bg-white/25';
  return 'bg-warn';
}

export function DiscordCard() {
  const [info, setInfo] = useState<DiscordInfo | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let alive = true;
    const load = () => {
      discordApi
        .info()
        .then((value) => {
          if (alive) setInfo(value);
        })
        .catch(() => {});
    };
    load();
    const timer = window.setInterval(load, 2000);
    return () => {
      alive = false;
      window.clearInterval(timer);
    };
  }, []);

  if (!isTauri || !info || !info.supported) return null;

  async function toggle(value: boolean) {
    setInfo((previous) => (previous ? { ...previous, enabled: value } : previous));
    await discordApi.setEnabled(value).catch(() => {});
    discordApi.info().then(setInfo).catch(() => {});
  }

  async function reconnect() {
    setBusy(true);
    await discordApi.reconnect().catch(() => {});
    window.setTimeout(() => setBusy(false), 1200);
  }

  return (
    <>
      <h2 className="eyebrow mt-8">Discord</h2>
      <div className="card static flex flex-col gap-4 !p-4">
        <div className="flex items-start gap-3">
          <span className={`mt-1.5 h-2.5 w-2.5 shrink-0 rounded-full ${dotClass(info.status)}`} />
          <div className="min-w-0">
            <p className="text-sm text-primary">{info.label.replace('Discord: ', '')}</p>
            <p className="mt-1 text-xs text-muted">{HINTS[info.status] ?? ''}</p>
          </div>
        </div>
        <label className="flex cursor-pointer items-center justify-between gap-4 rounded-tile border border-border2 bg-surface px-4 py-3">
          <span className="text-sm text-primary">
            Показывать в Discord
            <span className="block text-xs text-muted">статус «Слушает» с обложкой, пока играет музыка</span>
          </span>
          <input type="checkbox" checked={info.enabled} onChange={(event) => toggle(event.target.checked)} className="h-5 w-5 accent-white" />
        </label>
        <div className="flex flex-wrap items-center gap-2">
          <button type="button" onClick={reconnect} disabled={busy || !info.enabled} className="btn btn-ghost !px-4 !py-2 !text-xs">
            <RefreshCw size={14} className={busy ? 'animate-spin' : ''} />
            Переподключить
          </button>
          {info.status === 'needs_login' ? (
            <Link to="/site" className="btn btn-primary !px-4 !py-2 !text-xs">
              Войти на вкладке «Сайт»
            </Link>
          ) : null}
        </div>
        <p className="font-mono text-xs text-dim">
          приложение {info.appName} · {info.appId}
        </p>
      </div>
    </>
  );
}
