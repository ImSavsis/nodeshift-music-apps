import { useEffect } from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import { useNavigate } from 'react-router-dom';
import { UploadCloud } from 'lucide-react';
import { onFileDrop } from '../lib/tauri';
import { useImportStore } from '../store/importer';
import { toast } from '../store/toast';
import { useUiStore } from '../store/ui';

export function DropOverlay() {
  const navigate = useNavigate();
  const active = useUiStore((state) => state.dropActive);
  const setActive = useUiStore((state) => state.setDropActive);
  const start = useImportStore((state) => state.start);

  useEffect(() => {
    let off: (() => void) | null = null;
    let disposed = false;
    onFileDrop((event) => {
      if (event.type === 'enter') {
        setActive(true);
      } else if (event.type === 'leave') {
        setActive(false);
      } else if (event.type === 'drop') {
        setActive(false);
        if (event.paths.length === 0) return;
        navigate('/import');
        start(event.paths).catch(() => toast('Не удалось начать импорт'));
      }
    }).then((unlisten) => {
      if (disposed) unlisten();
      else off = unlisten;
    });
    return () => {
      disposed = true;
      off?.();
    };
  }, [navigate, setActive, start]);

  return (
    <AnimatePresence>
      {active ? (
        <motion.div className="drop-veil" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={{ duration: 0.18 }}>
          <motion.div className="drop-frame" initial={{ scale: 0.96 }} animate={{ scale: 1 }} exit={{ scale: 0.96 }}>
            <UploadCloud size={36} className="text-primary" />
            <p className="font-display text-lg font-semibold text-primary">Отпустите, чтобы добавить</p>
            <p className="font-mono text-xs uppercase tracking-[0.16em] text-dim">файлы · папки · архивы</p>
          </motion.div>
        </motion.div>
      ) : null}
    </AnimatePresence>
  );
}
