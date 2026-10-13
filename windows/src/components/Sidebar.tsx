import { NavLink, useNavigate } from 'react-router-dom';
import { Cloud, Heart, Keyboard, ListMusic, LogIn, Music2, Settings, Upload, UserRound } from 'lucide-react';
import CrystalMark from './CrystalMark';
import { api } from '../lib/api';
import { openExternal } from '../lib/tauri';
import { useAppStore } from '../store/app';
import { useImportStore } from '../store/importer';
import { useSiteStore } from '../store/site';
import { useUiStore } from '../store/ui';
import { toast } from '../store/toast';

const NAV_ITEMS = [
  { to: '/', label: 'Треки', icon: Music2 },
  { to: '/playlists', label: 'Плейлисты', icon: ListMusic },
  { to: '/favorites', label: 'Избранное', icon: Heart },
  { to: '/import', label: 'Импорт', icon: Upload },
  { to: '/site', label: 'Сайт', icon: Cloud }
];

export function Sidebar() {
  const navigate = useNavigate();
  const setHelpOpen = useUiStore((state) => state.setHelpOpen);
  const user = useSiteStore((state) => state.snapshot.user);
  const pending = useImportStore((state) => state.snapshot.pendingDuplicates);
  const importing = useImportStore((state) => state.snapshot.running);
  const update = useAppStore((state) => state.update);
  const installing = useAppStore((state) => state.installing);
  const installUpdate = useAppStore((state) => state.installUpdate);

  async function login() {
    navigate('/site');
    try {
      await api.siteLogin();
    } catch {
      toast('Не удалось открыть браузер для входа');
    }
  }

  return (
    <nav className="sidebar">
      <div className="sidebar-brand">
        <div className="brand-mark">
          <CrystalMark size={20} />
        </div>
        <span>
          Node<b>Shift</b>
          <small>music</small>
        </span>
      </div>

      <div className="nav-items">
        {NAV_ITEMS.map((item) => (
          <NavLink key={item.to} to={item.to} end={item.to === '/'} className={({ isActive }) => `nav-btn${isActive ? ' on' : ''}`}>
            <item.icon size={18} strokeWidth={1.6} />
            <span>{item.label}</span>
            {item.to === '/import' && pending > 0 ? <span className="nav-badge">{pending}</span> : null}
            {item.to === '/import' && pending === 0 && importing ? <span className="nav-badge animate-pulse">…</span> : null}
          </NavLink>
        ))}
      </div>

      {update ? (
        <div className="card static mb-3 !p-3">
          <p className="font-mono text-[0.6875rem] uppercase tracking-[0.14em] text-dim">Обновление</p>
          <p className="mt-1 text-sm text-primary">Версия {update.version}</p>
          <button type="button" onClick={installUpdate} disabled={installing} className="btn btn-primary mt-2 w-full !px-3 !py-2 !text-xs">
            {installing ? 'Скачиваем…' : 'Обновить'}
          </button>
        </div>
      ) : null}

      <div className="sidebar-foot">
        <button type="button" className="nav-btn" onClick={() => setHelpOpen(true)}>
          <Keyboard size={18} strokeWidth={1.6} />
          <span>Горячие клавиши</span>
        </button>

        <NavLink to="/settings" className={({ isActive }) => `nav-btn${isActive ? ' on' : ''}`}>
          <Settings size={18} strokeWidth={1.6} />
          <span>Настройки</span>
        </NavLink>

        {user ? (
          <NavLink to="/site" className="nav-btn">
            <UserRound size={18} strokeWidth={1.6} />
            <span className="truncate">@{user.handle ?? user.username ?? 'user'}</span>
          </NavLink>
        ) : (
          <button type="button" className="btn btn-primary mt-2" onClick={login}>
            <LogIn size={16} />
            Войти через сайт
          </button>
        )}

        <button type="button" onClick={() => openExternal('https://im.savsis.xyz')} className="nav-btn small">
          <span>made by savsis with &lt;3</span>
        </button>
      </div>
    </nav>
  );
}
