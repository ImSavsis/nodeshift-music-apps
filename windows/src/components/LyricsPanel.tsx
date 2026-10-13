import { useEffect, useMemo, useRef, useState } from 'react';
import type { CSSProperties } from 'react';
import { MicOff, RefreshCw } from 'lucide-react';
import { api } from '../lib/api';
import { activeIndex as findActiveIndex, fills, splitWords } from '../lib/karaoke';
import { usePlayerStore } from '../store/player';
import type { LyricLine, Lyrics, Track } from '../lib/types';

interface LyricsPanelProps {
  track: Track;
  className?: string;
}

interface RenderWord {
  text: string;
  spaced: boolean;
}

function renderWords(line: LyricLine): RenderWord[] {
  if (line.words && line.words.length > 0) {
    return line.words.map((word) => ({ text: word.text, spaced: false }));
  }
  return splitWords(line.text).map((text) => ({ text, spaced: true }));
}

export function LyricsPanel({ track, className = '' }: LyricsPanelProps) {
  const trackId = track.id;
  const siteId = track.streamUrl ? track.siteId : null;
  const [lyrics, setLyrics] = useState<Lyrics | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isRetrying, setIsRetrying] = useState(false);
  const [activeIndex, setActiveIndex] = useState(-1);
  const containerRef = useRef<HTMLDivElement | null>(null);
  const lineRefs = useRef<Array<HTMLParagraphElement | null>>([]);
  const wordRefs = useRef<Array<Array<HTMLSpanElement | null>>>([]);
  const userScrollUntil = useRef(0);
  const requestSeek = usePlayerStore((state) => state.requestSeek);

  useEffect(() => {
    let cancelled = false;
    setIsLoading(true);
    setLyrics(null);
    setActiveIndex(-1);
    lineRefs.current = [];
    wordRefs.current = [];
    containerRef.current?.scrollTo({ top: 0 });

    (siteId ? api.siteLyrics(siteId) : api.lyrics(trackId, false))
      .then((result) => {
        if (!cancelled) setLyrics(result);
      })
      .catch(() => {
        if (!cancelled) setLyrics({ state: 'none' });
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [trackId, siteId]);

  const lines = lyrics && lyrics.state === 'synced' ? lyrics.lines : null;
  const rendered = useMemo(() => (lines ?? []).map(renderWords), [lines]);

  useEffect(() => {
    if (!lines || lines.length === 0) return;

    let frame = 0;
    let lastIndex = -2;

    function tick() {
      if (!lines) return;
      const { currentTime, timeStamp, isPlaying } = usePlayerStore.getState();
      const time = currentTime + (isPlaying ? (performance.now() - timeStamp) / 1000 : 0);
      const index = findActiveIndex(lines, time);

      if (index !== lastIndex) {
        lastIndex = index;
        setActiveIndex(index);
      }

      if (index >= 0) {
        const nextTime = index + 1 < lines.length ? lines[index + 1].time : null;
        const values = fills(lines[index], nextTime, time);
        const nodes = wordRefs.current[index];
        if (nodes) {
          for (let i = 0; i < values.length; i += 1) nodes[i]?.style.setProperty('--f', values[i].toFixed(3));
        }
      }

      frame = requestAnimationFrame(tick);
    }

    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [lines]);

  useEffect(() => {
    if (activeIndex < 0 || performance.now() < userScrollUntil.current) return;
    const container = containerRef.current;
    const line = lineRefs.current[activeIndex];
    if (!container || !line) return;
    const target = line.offsetTop - container.clientHeight * 0.34 + line.offsetHeight / 2;
    container.scrollTo({ top: Math.max(0, target), behavior: 'smooth' });
  }, [activeIndex]);

  function pauseAutoScroll() {
    userScrollUntil.current = performance.now() + 4000;
  }

  async function retry() {
    setIsRetrying(true);
    try {
      setLyrics(siteId ? await api.siteLyrics(siteId) : await api.lyrics(trackId, true));
    } catch {
      setLyrics({ state: 'none' });
    } finally {
      setIsRetrying(false);
    }
  }

  if (isLoading) {
    return (
      <div className={`flex flex-col gap-6 px-2 py-10 ${className}`}>
        {[70, 90, 55, 80, 65].map((width, index) => (
          <div key={index} className="h-6 animate-pulse rounded-pill bg-white/10" style={{ width: `${width}%`, animationDelay: `${index * 120}ms` }} />
        ))}
      </div>
    );
  }

  if (lines && lines.length > 0) {
    return (
      <div ref={containerRef} onWheel={pauseAutoScroll} onPointerDown={pauseAutoScroll} className={`lyrics-scroll relative overflow-y-auto ${className}`}>
        <div className="px-1 py-[34vh]">
          <div className={`lyric-dots ${activeIndex === -1 ? 'is-on' : ''}`} aria-hidden>
            <span />
            <span />
            <span />
          </div>
          {lines.map((line, index) => {
            const state = index === activeIndex ? 'active' : index < activeIndex ? 'past' : 'future';
            return (
              <p
                key={`${line.time}-${index}`}
                ref={(element) => {
                  lineRefs.current[index] = element;
                }}
                data-state={state}
                style={{ '--d': Math.abs(index - activeIndex) } as CSSProperties}
                onClick={() => requestSeek(line.time)}
                className="lyric-line"
              >
                {rendered[index].map((word, wordIndex) => (
                  <span key={wordIndex}>
                    <span
                      className="lyric-word"
                      ref={(element) => {
                        if (!wordRefs.current[index]) wordRefs.current[index] = [];
                        wordRefs.current[index][wordIndex] = element;
                      }}
                    >
                      {word.text}
                    </span>
                    {word.spaced ? ' ' : ''}
                  </span>
                ))}
              </p>
            );
          })}
        </div>
      </div>
    );
  }

  if (lyrics && lyrics.state === 'plain') {
    const blocks = lyrics.text.split(/\n{2,}/).filter((block) => block.trim());
    return (
      <div className={`lyrics-scroll overflow-y-auto ${className}`}>
        <div className="flex flex-col gap-7 px-1 py-16">
          {blocks.map((block, index) => (
            <p
              key={index}
              className="whitespace-pre-line font-display text-[clamp(1.0625rem,1.5vw,1.5rem)] font-medium leading-relaxed text-white/80"
              style={{ animation: `elIn 0.6s cubic-bezier(0.16,1,0.3,1) ${Math.min(index, 8) * 70}ms both` }}
            >
              {block}
            </p>
          ))}
          <p className="font-mono text-[0.6875rem] uppercase tracking-[0.18em] text-dim">Текст без синхронизации</p>
        </div>
      </div>
    );
  }

  return (
    <div className={`flex flex-col items-center justify-center gap-3 text-dim ${className}`}>
      <MicOff size={30} strokeWidth={1.4} />
      <p className="font-mono text-xs uppercase tracking-[0.16em]">Текст не найден</p>
      <button type="button" onClick={retry} disabled={isRetrying} className="btn btn-ghost mt-2 !px-4 !py-2 !text-xs">
        <RefreshCw size={14} className={isRetrying ? 'animate-spin' : ''} />
        {isRetrying ? 'Ищем…' : 'Найти ещё раз'}
      </button>
    </div>
  );
}
