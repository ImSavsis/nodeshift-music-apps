import { useEffect } from 'react';
import { AnimatePresence } from 'framer-motion';
import { Navigate, Route, Routes, useLocation } from 'react-router-dom';
import FlowField from './components/FlowField';
import CrystalMark from './components/CrystalMark';
import { Sidebar } from './components/Sidebar';
import { PlayerBar } from './components/PlayerBar';
import { NowPlaying } from './components/NowPlaying';
import { MediaEngine } from './components/MediaEngine';
import { PageTransition } from './components/PageTransition';
import { QueuePanel } from './components/QueuePanel';
import { Toasts } from './components/Toasts';
import { AddToPlaylistModal } from './components/AddToPlaylistModal';
import { EditTrackModal } from './components/EditTrackModal';
import { ShortcutsModal } from './components/ShortcutsModal';
import { DropOverlay } from './components/DropOverlay';
import { Library } from './pages/Library';
import { Playlists } from './pages/Playlists';
import { PlaylistDetail } from './pages/PlaylistDetail';
import { Favorites } from './pages/Favorites';
import { Import } from './pages/Import';
import { Site } from './pages/Site';
import { Settings } from './pages/Settings';
import { api, events } from './lib/api';
import { readFlag } from './lib/flags';
import { useHotkeys } from './hooks/useHotkeys';
import { useMediaSession } from './hooks/useMediaSession';
import { useAppStore } from './store/app';
import { useImportStore } from './store/importer';
import { scheduleReload, useLibraryStore } from './store/library';
import { usePlayerStore } from './store/player';
import { useCatalogStore } from './store/catalog';
import { useSiteStore } from './store/site';
import { toast } from './store/toast';

function AppRoutes() {
  const location = useLocation();

  useEffect(() => {
    window.scrollTo({ top: 0 });
  }, [location.pathname]);

  return (
    <AnimatePresence mode="wait">
      <Routes location={location} key={location.pathname}>
        <Route path="/" element={<PageTransition><Library /></PageTransition>} />
        <Route path="/playlists" element={<PageTransition><Playlists /></PageTransition>} />
        <Route path="/playlists/:id" element={<PageTransition><PlaylistDetail /></PageTransition>} />
        <Route path="/favorites" element={<PageTransition><Favorites /></PageTransition>} />
        <Route path="/import" element={<PageTransition><Import /></PageTransition>} />
        <Route path="/site" element={<PageTransition><Site /></PageTransition>} />
        <Route path="/settings" element={<PageTransition><Settings /></PageTransition>} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </AnimatePresence>
  );
}

function Shell() {
  useHotkeys();
  useMediaSession();
  const hasTrack = usePlayerStore((state) => state.currentTrack !== null);

  return (
    <div className="shell">
      <FlowField />
      <Sidebar />
      <div className="content">
        <main className={`main${hasTrack ? ' has-player' : ''}`}>
          <AppRoutes />
        </main>
      </div>
      <MediaEngine />
      <PlayerBar />
      <NowPlaying />
      <QueuePanel />
      <AddToPlaylistModal />
      <EditTrackModal />
      <ShortcutsModal />
      <DropOverlay />
      <Toasts />
    </div>
  );
}

export function App() {
  const info = useAppStore((state) => state.info);

  useEffect(() => {
    let disposed = false;
    const offs: Array<() => void> = [];

    async function boot() {
      await useAppStore.getState().init();
      await Promise.all([useLibraryStore.getState().load(), useImportStore.getState().refresh(), useSiteStore.getState().refresh()]);
      api.setLossless(readFlag('nsm_lossless', true)).catch(() => {});
      api.setMotionAuto(readFlag('nsm_motion_auto', true)).catch(() => {});
      useAppStore.getState().checkUpdate(true);
      useCatalogStore.getState().refreshLikes();
      const subscriptions = await Promise.all([
        events.library(() => scheduleReload()),
        events.importing(() => useImportStore.getState().refresh().catch(() => {})),
        events.site(() => useSiteStore.getState().refresh().catch(() => {})),
        events.toast((message) => toast(message))
      ]);
      const unwatchSession = useSiteStore.subscribe((state, previous) => {
        if (state.snapshot.user?.id !== previous.snapshot.user?.id) useCatalogStore.getState().refreshLikes();
      });
      const everything = [...subscriptions, unwatchSession];
      if (disposed) everything.forEach((off) => off());
      else offs.push(...everything);
    }

    boot().catch(() => toast('Не удалось запустить ядро приложения'));

    const blockMenu = (event: MouseEvent) => {
      const target = event.target;
      if (target instanceof HTMLElement && (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA')) return;
      if (import.meta.env.PROD) event.preventDefault();
    };
    window.addEventListener('contextmenu', blockMenu);

    return () => {
      disposed = true;
      offs.forEach((off) => off());
      window.removeEventListener('contextmenu', blockMenu);
    };
  }, []);

  if (!info) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-base">
        <div className="animate-pulse">
          <CrystalMark size={64} />
        </div>
      </div>
    );
  }

  return <Shell />;
}
