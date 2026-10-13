import { createPortal } from 'react-dom';
import { AnimatePresence, motion } from 'framer-motion';
import { useToastStore } from '../store/toast';

export function Toasts() {
  const toasts = useToastStore((state) => state.toasts);
  const dismiss = useToastStore((state) => state.dismiss);

  return createPortal(
    <div className="toast-stack pointer-events-none fixed left-1/2 z-[90] flex w-[min(92vw,26.25rem)] -translate-x-1/2 flex-col items-center gap-2">
      <AnimatePresence>
        {toasts.map((item) => (
          <motion.div
            key={item.id}
            layout
            initial={{ opacity: 0, y: 16, scale: 0.96 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 8, scale: 0.96 }}
            transition={{ duration: 0.22, ease: [0.16, 1, 0.3, 1] }}
            className="pointer-events-auto flex max-w-full items-center gap-3 rounded-pill border border-border2 bg-[#161616]/95 px-4 py-2.5 text-sm text-primary shadow-float backdrop-blur"
          >
            <span className="min-w-0 truncate">{item.message}</span>
            {item.actionLabel ? (
              <button
                type="button"
                onClick={() => {
                  item.onAction?.();
                  dismiss(item.id);
                }}
                className="shrink-0 rounded-pill bg-white/10 px-3 py-1 text-xs font-semibold text-primary hover:bg-white/20"
              >
                {item.actionLabel}
              </button>
            ) : null}
          </motion.div>
        ))}
      </AnimatePresence>
    </div>,
    document.body
  );
}
