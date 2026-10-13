import { useEffect, useRef } from 'react';
import { createPortal } from 'react-dom';
import { AnimatePresence, motion } from 'framer-motion';
import { Repeat, Repeat1, Shuffle, Trash2, X } from 'lucide-react';
import { CoverImage } from './CoverImage';
import { EqualizerBars } from './EqualizerBars';
import { usePlayerStore } from '../store/player';

export function QueuePanel() {
  const isOpen = usePlayerStore((state) => state.isQueueOpen);
  const queue = usePlayerStore((state) => state.queue);
  const queueIndex = usePlayerStore((state) => state.queueIndex);
  const isPlaying = usePlayerStore((state) => state.isPlaying);
  const shuffle = usePlayerStore((state) => state.shuffle);
  const repeat = usePlayerStore((state) => state.repeat);
  const close = usePlayerStore((state) => state.closeQueue);
  const playIndex = usePlayerStore((state) => state.playIndex);
  const removeFromQueue = usePlayerStore((state) => state.removeFromQueue);
  const clearUpcoming = usePlayerStore((state) => state.clearUpcoming);
  const toggleShuffle = usePlayerStore((state) => state.toggleShuffle);
  const cycleRepeat = usePlayerStore((state) => state.cycleRepeat);
  const currentRow = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (isOpen) currentRow.current?.scrollIntoView({ block: 'center' });
  }, [isOpen]);

  const upcoming = Math.max(0, queue.length - queueIndex - 1);

  return createPortal(
    <AnimatePresence>
      {isOpen ? (
        <div className="fixed inset-0 z-[75]">
          <motion.div className="absolute inset-0 bg-black/60" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} onClick={close} />
          <motion.aside
            initial={{ x: '100%' }}
            animate={{ x: 0 }}
            exit={{ x: '100%' }}
            transition={{ duration: 0.32, ease: [0.16, 1, 0.3, 1] }}
            className="absolute inset-y-0 right-0 flex w-[25rem] flex-col rounded-l-card border border-border2 bg-[#101010] shadow-float"
          >
            <div className="flex items-center gap-2 border-b border-border px-5 py-4">
              <div className="min-w-0 flex-1">
                <h2 className="font-display text-sm font-semibold tracking-tight text-primary">Очередь</h2>
                <p className="font-mono text-[0.6875rem] text-dim">
                  {queue.length} в списке · {upcoming} далее
                </p>
              </div>
              <button
                type="button"
                onClick={toggleShuffle}
                aria-pressed={shuffle}
                aria-label="Перемешать"
                className={`flex h-9 w-9 items-center justify-center rounded-full hover:bg-white/10 ${shuffle ? 'text-primary' : 'text-dim'}`}
              >
                <Shuffle size={17} />
              </button>
              <button
                type="button"
                onClick={cycleRepeat}
                aria-label="Повтор"
                className={`flex h-9 w-9 items-center justify-center rounded-full hover:bg-white/10 ${repeat === 'off' ? 'text-dim' : 'text-primary'}`}
              >
                {repeat === 'one' ? <Repeat1 size={17} /> : <Repeat size={17} />}
              </button>
              <button
                type="button"
                onClick={clearUpcoming}
                disabled={upcoming === 0}
                aria-label="Очистить очередь"
                className="flex h-9 w-9 items-center justify-center rounded-full text-dim hover:bg-white/10 hover:text-primary disabled:opacity-30"
              >
                <Trash2 size={17} />
              </button>
              <button type="button" onClick={close} aria-label="Закрыть" className="flex h-9 w-9 items-center justify-center rounded-full text-muted hover:bg-white/10 hover:text-primary">
                <X size={18} />
              </button>
            </div>

            <div className="flex-1 overflow-y-auto p-2">
              {queue.map((track, index) => {
                const isCurrent = index === queueIndex;
                return (
                  <div
                    key={`${track.id}-${index}`}
                    ref={isCurrent ? currentRow : undefined}
                    onClick={() => playIndex(index)}
                    className={`group flex cursor-pointer items-center gap-3 rounded-tile border px-2 py-2 transition-colors hover:bg-white/5 ${
                      isCurrent ? 'border-border2 bg-surface2' : 'border-transparent'
                    } ${index < queueIndex ? 'opacity-50' : ''}`}
                  >
                    <span className="w-5 shrink-0 text-center font-mono text-[0.6875rem] text-dim">{index + 1}</span>
                    <CoverImage coverName={track.coverName} alt={track.title} className="h-10 w-10 shrink-0" rounded="rounded-tile" live={false} playMotion={false} />
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm text-primary">{track.title}</p>
                      <p className="truncate font-mono text-[0.6875rem] text-dim">{track.artist}</p>
                    </div>
                    {isCurrent ? (
                      <EqualizerBars isPlaying={isPlaying} className="shrink-0" />
                    ) : (
                      <button
                        type="button"
                        aria-label="Убрать из очереди"
                        onClick={(event) => {
                          event.stopPropagation();
                          removeFromQueue(index);
                        }}
                        className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-dim opacity-0 hover:bg-white/10 hover:text-primary group-hover:opacity-100"
                      >
                        <X size={15} />
                      </button>
                    )}
                  </div>
                );
              })}
            </div>
          </motion.aside>
        </div>
      ) : null}
    </AnimatePresence>,
    document.body
  );
}
