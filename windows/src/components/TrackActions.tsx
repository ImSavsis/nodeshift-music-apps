import { useEffect, useState } from 'react';
import type { MouseEvent, ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { Ellipsis, Heart, ListEnd, ListMusic, ListStart, Pencil } from 'lucide-react';
import { toggleFavorite, useIsFavorite } from '../store/catalog';
import { usePlayerStore } from '../store/player';
import { toast } from '../store/toast';
import { useUiStore } from '../store/ui';
import type { Track } from '../lib/types';

interface IconToggleProps {
  active?: boolean;
  label: string;
  onClick: (event: MouseEvent<HTMLButtonElement>) => void;
  children: ReactNode;
}

export function IconToggle({ active = false, label, onClick, children }: IconToggleProps) {
  return (
    <button
      type="button"
      aria-label={label}
      aria-pressed={active}
      title={label}
      onClick={onClick}
      className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-full transition-colors hover:bg-white/10 hover:text-primary ${
        active ? 'text-primary' : 'text-dim'
      }`}
    >
      {children}
    </button>
  );
}

interface MenuPosition {
  x: number;
  y: number;
  flip: boolean;
}

function MenuItem({ icon, label, onClick }: { icon: ReactNode; label: string; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="flex w-full items-center gap-3 rounded-tile px-3 py-2.5 text-left text-sm text-primary transition-colors hover:bg-white/10"
    >
      <span className="shrink-0 text-muted">{icon}</span>
      {label}
    </button>
  );
}

function TrackMenu({ track }: { track: Track }) {
  const [position, setPosition] = useState<MenuPosition | null>(null);
  const playNextInQueue = usePlayerStore((state) => state.playNextInQueue);
  const addToQueue = usePlayerStore((state) => state.addToQueue);
  const openPlaylistPicker = useUiStore((state) => state.openPlaylistPicker);
  const openEditTrack = useUiStore((state) => state.openEditTrack);

  useEffect(() => {
    if (!position) return;
    const close = () => setPosition(null);
    function onKey(event: KeyboardEvent) {
      if (event.key === 'Escape') close();
    }
    window.addEventListener('keydown', onKey);
    window.addEventListener('resize', close);
    window.addEventListener('scroll', close, true);
    return () => {
      window.removeEventListener('keydown', onKey);
      window.removeEventListener('resize', close);
      window.removeEventListener('scroll', close, true);
    };
  }, [position]);

  function open(event: MouseEvent<HTMLButtonElement>) {
    const rect = event.currentTarget.getBoundingClientRect();
    const flip = window.innerHeight - rect.bottom < 280;
    setPosition({ x: rect.right, y: flip ? rect.top : rect.bottom, flip });
  }

  function run(action: () => void) {
    setPosition(null);
    action();
  }

  const menu = position ? (
    <div className="fixed inset-0 z-[70]" onClick={() => setPosition(null)}>
      <div
        onClick={(event) => event.stopPropagation()}
        style={
          position.flip
            ? { right: window.innerWidth - position.x, bottom: window.innerHeight - position.y + 6 }
            : { right: window.innerWidth - position.x, top: position.y + 6 }
        }
        className="absolute w-60 rounded-card border border-border2 bg-[#121212] p-1.5 shadow-float"
      >
        <MenuItem
          icon={<ListStart size={16} />}
          label="Играть следом"
          onClick={() =>
            run(() => {
              playNextInQueue(track);
              toast('Сыграет следующим');
            })
          }
        />
        <MenuItem
          icon={<ListEnd size={16} />}
          label="Добавить в очередь"
          onClick={() =>
            run(() => {
              addToQueue(track);
              toast('Добавлено в очередь');
            })
          }
        />
        {track.streamUrl ? null : (
          <>
            <MenuItem icon={<ListMusic size={16} />} label="В плейлист…" onClick={() => run(() => openPlaylistPicker(track))} />
            <MenuItem icon={<Pencil size={16} />} label="Редактировать" onClick={() => run(() => openEditTrack(track))} />
          </>
        )}
      </div>
    </div>
  ) : null;

  return (
    <>
      <IconToggle label="Ещё" onClick={open}>
        <Ellipsis size={18} />
      </IconToggle>
      {menu ? createPortal(menu, document.body) : null}
    </>
  );
}

interface TrackActionsProps {
  track: Track;
  className?: string;
}

export function TrackActions({ track, className = '' }: TrackActionsProps) {
  const isLiked = useIsFavorite(track);

  return (
    <div className={`flex items-center ${className}`} onClick={(event) => event.stopPropagation()}>
      <IconToggle active={isLiked} label={isLiked ? 'Убрать из избранного' : 'В избранное'} onClick={() => toggleFavorite(track)}>
        <Heart size={18} fill={isLiked ? 'currentColor' : 'none'} />
      </IconToggle>
      <TrackMenu track={track} />
    </div>
  );
}
