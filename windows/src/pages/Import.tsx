import { useState } from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import { Check, CircleAlert, FolderUp, LoaderCircle, Music2, SkipForward, Trash2, UploadCloud } from 'lucide-react';
import { CoverImage } from '../components/CoverImage';
import { pickPaths } from '../lib/tauri';
import { useImportStore } from '../store/importer';
import { useLibraryStore } from '../store/library';
import { toast } from '../store/toast';
import type { Decision, ImportItem } from '../lib/types';

function duplicateNote(kind: string, better: boolean): string {
  const base = kind === 'sameFile' ? 'Точно такой же файл уже есть' : kind === 'sameTrack' ? 'Такой трек уже есть в библиотеке' : 'Похожий трек уже есть';
  return better ? `${base}, новый файл качественнее` : base;
}

function ItemRow({ item }: { item: ImportItem }) {
  const decide = useImportStore((state) => state.decide);
  const existing = useLibraryStore((state) => (item.state.kind === 'duplicate' ? state.byId.get(item.state.existingId) : undefined));
  const state = item.state;

  const heading = item.title ?? item.name;
  const sub = item.title ? [item.artist, item.name].filter(Boolean).join(' · ') : '';

  function choose(decision: Decision) {
    decide(item.id, decision).catch(() => toast('Не удалось применить выбор'));
  }

  return (
    <motion.div layout initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }} transition={{ duration: 0.24, ease: [0.16, 1, 0.3, 1] }} className="card static !p-3">
      <div className="flex items-center gap-3">
        <div className="h-11 w-11 shrink-0 overflow-hidden rounded-tile">
          <CoverImage coverName={item.coverName} alt={heading} className="h-11 w-11" rounded="rounded-tile" live={false} playMotion={false} />
        </div>
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm text-primary">{heading}</p>
          {sub ? <p className="truncate text-[0.6875rem] text-muted">{sub}</p> : null}
          <p
            className={`truncate font-mono text-[0.6875rem] ${
              state.kind === 'failed' ? 'text-danger' : state.kind === 'duplicate' ? 'text-warn' : 'text-dim'
            }`}
          >
            {state.kind === 'waiting' ? 'В очереди' : null}
            {state.kind === 'working' ? state.text : null}
            {state.kind === 'done' ? 'Добавлено в библиотеку' : null}
            {state.kind === 'skipped' ? state.text : null}
            {state.kind === 'failed' ? state.text : null}
            {state.kind === 'duplicate' ? duplicateNote(state.dupKind, state.betterQuality) : null}
          </p>
        </div>
        {state.kind === 'working' ? <LoaderCircle size={18} className="shrink-0 animate-spin text-muted" /> : null}
        {state.kind === 'done' ? <Check size={18} className="shrink-0 text-ok" /> : null}
        {state.kind === 'failed' ? <CircleAlert size={18} className="shrink-0 text-danger" /> : null}
      </div>

      {state.kind === 'duplicate' ? (
        <div className="mt-3 flex flex-wrap items-center justify-between gap-3 border-t border-border pt-3">
          <p className="min-w-0 truncate font-mono text-[0.6875rem] text-dim">
            {existing ? `Уже есть: ${existing.artist} — ${existing.title} · ${existing.format.toUpperCase()}` : 'Уже есть в библиотеке'}
          </p>
          <div className="flex shrink-0 gap-2">
            <button type="button" onClick={() => choose('skip')} className="btn btn-ghost !px-4 !py-1.5 !text-xs">
              Пропустить
            </button>
            <button type="button" onClick={() => choose('keepBoth')} className="btn btn-ghost !px-4 !py-1.5 !text-xs">
              Оставить оба
            </button>
            <button type="button" onClick={() => choose('replace')} className="btn btn-primary !px-4 !py-1.5 !text-xs">
              Заменить
            </button>
          </div>
        </div>
      ) : null}
    </motion.div>
  );
}

export function Import() {
  const snapshot = useImportStore((state) => state.snapshot);
  const start = useImportStore((state) => state.start);
  const skipAll = useImportStore((state) => state.skipAll);
  const clear = useImportStore((state) => state.clear);
  const [picking, setPicking] = useState(false);

  async function pick(kind: 'files' | 'folder') {
    setPicking(true);
    try {
      const paths = await pickPaths(kind);
      if (paths.length > 0) await start(paths);
    } catch {
      toast('Не удалось открыть выбор файлов');
    } finally {
      setPicking(false);
    }
  }

  const { summary, items, running, pendingDuplicates } = snapshot;
  const finished = !running && items.length > 0;

  return (
    <div className="fade-in max-w-3xl">
      <div className="ph">
        <div>
          <h1>Импорт музыки</h1>
          <p>
            Файлы, целые папки и архивы zip, 7z, tar. Название и артист берутся из тегов или из имени файла вроде «09 - 2pac - Ratha Be Ya Nigga.flac», теги, альбом, обложка и текст пишутся автоматически.
          </p>
        </div>
      </div>

      <div className="flex flex-col items-center gap-4 rounded-card border border-dashed border-border2 bg-surface px-6 py-10 text-center">
        <UploadCloud size={28} className="text-muted" />
        <p className="text-sm text-primary">Перетащите файлы, папку или архив в это окно</p>
        <div className="flex flex-wrap justify-center gap-2">
          <button type="button" disabled={picking} onClick={() => pick('files')} className="btn btn-ghost !px-4 !py-2 !text-xs">
            <Music2 size={14} />
            Выбрать файлы
          </button>
          <button type="button" disabled={picking} onClick={() => pick('folder')} className="btn btn-ghost !px-4 !py-2 !text-xs">
            <FolderUp size={14} />
            Выбрать папку
          </button>
        </div>
        <p className="font-mono text-[0.6875rem] uppercase tracking-[0.16em] text-dim">mp3 · flac · wav · ogg · m4a · aiff · opus · zip · 7z · tar</p>
      </div>

      {items.length > 0 ? (
        <>
          <div className="mt-6 flex flex-wrap items-center justify-between gap-3">
            <p className="font-mono text-xs text-muted">
              добавлено {summary.added}
              {summary.duplicates > 0 ? ` · дубликатов ${summary.duplicates}` : ''}
              {summary.failed > 0 ? ` · ошибок ${summary.failed}` : ''}
              {summary.ignored > 0 ? ` · лишних файлов пропущено ${summary.ignored}` : ''}
              {running ? ' · идёт импорт…' : ''}
            </p>
            <div className="flex gap-2">
              {pendingDuplicates > 1 ? (
                <button type="button" onClick={() => skipAll()} className="btn btn-ghost !px-4 !py-2 !text-xs">
                  <SkipForward size={14} />
                  Пропустить все дубликаты
                </button>
              ) : null}
              {finished && pendingDuplicates === 0 ? (
                <button type="button" onClick={() => clear()} className="btn btn-ghost !px-4 !py-2 !text-xs">
                  <Trash2 size={14} />
                  Очистить список
                </button>
              ) : null}
            </div>
          </div>

          <div className="mt-3 flex flex-col gap-2">
            <AnimatePresence initial={false}>
              {items.map((item) => (
                <ItemRow key={item.id} item={item} />
              ))}
            </AnimatePresence>
          </div>
        </>
      ) : null}
    </div>
  );
}
