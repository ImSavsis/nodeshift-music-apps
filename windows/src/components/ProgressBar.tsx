import type { CSSProperties } from 'react';
import { formatDuration } from '../lib/format';

interface ProgressBarProps {
  currentTime: number;
  duration: number;
  onSeek: (time: number) => void;
  showTime?: boolean;
  className?: string;
}

export function ProgressBar({ currentTime, duration, onSeek, showTime = true, className = '' }: ProgressBarProps) {
  const safeDuration = duration > 0 ? duration : 0;
  const percent = safeDuration > 0 ? Math.min(100, (currentTime / safeDuration) * 100) : 0;

  return (
    <div className={`flex items-center gap-3 ${className}`}>
      {showTime ? <span className="w-10 shrink-0 text-right font-mono text-[0.6875rem] text-dim">{formatDuration(currentTime)}</span> : null}
      <input
        type="range"
        min={0}
        max={safeDuration || 1}
        step={0.1}
        value={Math.min(currentTime, safeDuration || 1)}
        onChange={(event) => onSeek(Number(event.target.value))}
        aria-label="Позиция в треке"
        style={{ '--p': `${percent}%` } as CSSProperties}
        className="seek flex-1"
      />
      {showTime ? <span className="w-10 shrink-0 font-mono text-[0.6875rem] text-dim">{formatDuration(safeDuration)}</span> : null}
    </div>
  );
}
