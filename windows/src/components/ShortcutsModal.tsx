import { Modal } from './Modal';
import { useUiStore } from '../store/ui';

const SHORTCUTS: Array<[string, string]> = [
  ['Пробел', 'Играть / пауза'],
  ['← →', 'Перемотка на 5 секунд (с Shift на 15)'],
  ['↑ ↓', 'Громкость (в полном плеере)'],
  ['N / P', 'Следующий / предыдущий трек'],
  ['S', 'Перемешать'],
  ['R', 'Повтор: выкл / все / один'],
  ['L', 'Лайк текущему треку'],
  ['Q', 'Очередь'],
  ['F', 'Полный плеер'],
  ['M', 'Выключить звук'],
  ['/', 'Поиск'],
  ['?', 'Это окно']
];

export function ShortcutsModal() {
  const isOpen = useUiStore((state) => state.helpOpen);
  const setOpen = useUiStore((state) => state.setHelpOpen);

  return (
    <Modal isOpen={isOpen} onClose={() => setOpen(false)} title="Горячие клавиши">
      <div className="flex flex-col">
        {SHORTCUTS.map(([keys, label]) => (
          <div key={keys} className="flex items-center justify-between gap-4 border-b border-border py-2.5 last:border-0">
            <span className="text-sm text-muted">{label}</span>
            <kbd className="shrink-0 rounded-md border border-border2 bg-surface px-2 py-0.5 font-mono text-xs text-primary">{keys}</kbd>
          </div>
        ))}
      </div>
    </Modal>
  );
}
