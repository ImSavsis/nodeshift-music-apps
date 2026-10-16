import { useEffect, useRef, useState } from 'react';
import { Check, Sparkles } from 'lucide-react';
import { ANIMATIONS, ANIMATION_LABELS } from '../lib/karaoke';
import type { LyricAnimationMode } from '../lib/karaoke';
import { useUiStore } from '../store/ui';

const MODES: LyricAnimationMode[] = ['auto', ...ANIMATIONS];

export function LyricAnimationPicker() {
  const mode = useUiStore((state) => state.lyricAnimation);
  const setMode = useUiStore((state) => state.setLyricAnimation);
  const [open, setOpen] = useState(false);
  const rootRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (!open) return;
    function close(event: PointerEvent) {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false);
    }
    window.addEventListener('pointerdown', close);
    return () => window.removeEventListener('pointerdown', close);
  }, [open]);

  return (
    <div ref={rootRef} className="lyric-picker">
      <button type="button" onClick={() => setOpen((value) => !value)} aria-label="Анимация текста" aria-expanded={open} className="lyric-picker-btn">
        <Sparkles size={13} />
        <span>{ANIMATION_LABELS[mode]}</span>
      </button>
      {open ? (
        <ul className="lyric-picker-menu" role="menu">
          {MODES.map((item) => (
            <li key={item}>
              <button
                type="button"
                role="menuitemradio"
                aria-checked={item === mode}
                onClick={() => {
                  setMode(item);
                  setOpen(false);
                }}
                className={item === mode ? 'is-on' : ''}
              >
                <span>{ANIMATION_LABELS[item]}</span>
                {item === mode ? <Check size={13} /> : null}
              </button>
            </li>
          ))}
        </ul>
      ) : null}
    </div>
  );
}
