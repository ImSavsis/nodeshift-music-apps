import { useEffect, useRef } from 'react';
import type { CSSProperties } from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import { getActiveMediaElement } from '../lib/audioElements';
import { beatEngine } from '../lib/beatEngine';
import { usePalette } from '../hooks/usePalette';
import { usePlayerStore } from '../store/player';

const DEFAULT_BPM = 92;
const MIN_RATE = 0.6;
const MAX_RATE = 1.6;
const IDLE_RATE = 0.12;

function Blobs({ palette }: { palette: string[] }) {
  const rootRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    const root = rootRef.current;
    if (!root) return;

    const blobs = Array.from(root.querySelectorAll<HTMLElement>('.ambient-blob'));
    let frame = 0;
    let rate = 0.5;
    let pulse = 0;
    let lastBind = 0;

    function loop(now: number) {
      const { isPlaying } = usePlayerStore.getState();

      if (isPlaying && now - lastBind > 700) {
        lastBind = now;
        const element = getActiveMediaElement();
        if (element && !beatEngine.isBound()) beatEngine.bind(element);
      }
      if (beatEngine.isBound() && isPlaying) beatEngine.tick(now);

      const bpm = beatEngine.bpm > 0 ? beatEngine.bpm : DEFAULT_BPM;
      const tempoRate = Math.min(MAX_RATE, Math.max(MIN_RATE, bpm / 100));
      const target = isPlaying ? tempoRate : IDLE_RATE;
      rate += (target - rate) * 0.02;

      const energy = isPlaying && beatEngine.isBound() ? beatEngine.energy : 0;
      pulse += (energy - pulse) * 0.12;

      for (const blob of blobs) {
        const speed = Number(blob.dataset.speed ?? '1');
        for (const animation of blob.getAnimations()) animation.playbackRate = rate * speed;
      }
      root!.style.setProperty('--pulse', pulse.toFixed(3));

      frame = requestAnimationFrame(loop);
    }

    frame = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(frame);
  }, []);

  return (
    <div ref={rootRef} className="ambient">
      {palette.slice(0, 3).map((color, index) => (
        <div key={index} data-speed={[1, 0.82, 1.15, 0.7][index]} className={`ambient-blob blob-${index}`} style={{ '--c': color } as CSSProperties} />
      ))}
      <div className="ambient-grain" />
    </div>
  );
}

export function AmbientBackdrop({ coverName }: { coverName: string | null }) {
  const palette = usePalette(coverName);
  const trackId = usePlayerStore((state) => state.currentTrack?.id);

  useEffect(() => {
    beatEngine.unbind();
    return () => beatEngine.unbind();
  }, [trackId]);

  const key = palette.join('|');

  return (
    <div className="np-ambient" aria-hidden>
      <AnimatePresence initial={false}>
        <motion.div
          key={key}
          className="absolute inset-0"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          transition={{ duration: 1.6, ease: 'easeInOut' }}
        >
          <Blobs palette={palette} />
        </motion.div>
      </AnimatePresence>
    </div>
  );
}
