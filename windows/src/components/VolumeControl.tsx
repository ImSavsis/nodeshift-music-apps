import type { CSSProperties } from 'react';
import { Volume1, Volume2, VolumeX } from 'lucide-react';
import { usePlayerStore } from '../store/player';

export function VolumeControl({ className = '' }: { className?: string }) {
  const volume = usePlayerStore((state) => state.volume);
  const isMuted = usePlayerStore((state) => state.isMuted);
  const setVolume = usePlayerStore((state) => state.setVolume);
  const toggleMute = usePlayerStore((state) => state.toggleMute);

  const effectiveVolume = isMuted ? 0 : volume;
  const Icon = effectiveVolume === 0 ? VolumeX : effectiveVolume < 0.5 ? Volume1 : Volume2;
  const percent = Math.round(effectiveVolume * 100);

  return (
    <div className={`flex items-center gap-2 ${className}`}>
      <button type="button" onClick={toggleMute} aria-label="Выключить звук" className="text-muted hover:text-primary">
        <Icon size={18} />
      </button>
      <input
        type="range"
        min={0}
        max={100}
        value={percent}
        onChange={(event) => setVolume(Number(event.target.value) / 100)}
        aria-label="Громкость"
        style={{ '--p': `${percent}%` } as CSSProperties}
        className="seek w-24"
      />
    </div>
  );
}
