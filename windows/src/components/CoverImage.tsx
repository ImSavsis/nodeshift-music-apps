import { useEffect, useState } from 'react';
import type { CSSProperties } from 'react';
import { driftSeed } from '../lib/karaoke';
import { media } from '../lib/media';
import { useInView } from '../hooks/useInView';
import CrystalMark from './CrystalMark';

const MAX_MOTION = 6;
let activeMotion = 0;

function useMotionSlot(wanted: boolean, priority: boolean): boolean {
  const [granted, setGranted] = useState(false);

  useEffect(() => {
    if (!wanted) {
      setGranted(false);
      return;
    }
    if (priority) {
      setGranted(true);
      return;
    }
    if (activeMotion >= MAX_MOTION) {
      setGranted(false);
      return;
    }
    activeMotion += 1;
    setGranted(true);
    return () => {
      activeMotion -= 1;
    };
  }, [wanted, priority]);

  return granted;
}

function motionAllowed(): boolean {
  if (typeof window === 'undefined') return false;
  return !window.matchMedia('(prefers-reduced-motion: reduce)').matches;
}

function driftStyle(seed: string): CSSProperties {
  const value = driftSeed(seed);
  return {
    '--kb-dur': `${value.duration}s`,
    '--kb-delay': `${value.delay}s`,
    '--kb-x': `${value.shiftX}%`,
    '--kb-y': `${value.shiftY}%`,
    '--kb-ox': `${value.originX}%`,
    '--kb-oy': `${value.originY}%`,
    '--sheen-delay': `${value.sheenDelay}s`
  } as CSSProperties;
}

function MotionLayer({ url }: { url: string }) {
  const [ready, setReady] = useState(false);
  const [failed, setFailed] = useState(false);
  if (failed) return null;
  return (
    <video
      src={url}
      muted
      loop
      autoPlay
      playsInline
      preload="auto"
      onCanPlay={() => setReady(true)}
      onError={() => setFailed(true)}
      className={`absolute inset-0 h-full w-full object-cover transition-opacity duration-700 ${ready ? 'opacity-100' : 'opacity-0'}`}
    />
  );
}

interface CoverImageProps {
  coverName: string | null;
  alt: string;
  className?: string;
  rounded?: string;
  motionName?: string | null;
  playMotion?: boolean;
  live?: boolean;
  priority?: boolean;
}

export function CoverImage({
  coverName,
  alt,
  className = '',
  rounded = 'rounded-tile',
  motionName = null,
  playMotion = true,
  live = true,
  priority = false
}: CoverImageProps) {
  const [ref, inView] = useInView<HTMLDivElement>();
  const allowed = motionAllowed();
  const wantsMotion = playMotion && Boolean(motionName) && allowed && (inView || priority);
  const showMotion = useMotionSlot(wantsMotion, priority);

  if (!coverName && !motionName) {
    return (
      <div className={`cover-fallback ${rounded} ${className}`}>
        <CrystalMark size={28} dim />
      </div>
    );
  }

  const drift = live && allowed && inView && !showMotion && Boolean(coverName);

  return (
    <div ref={ref} className={`cover-frame relative overflow-hidden bg-surface ${rounded} ${className}`} style={drift ? driftStyle(coverName ?? '') : undefined}>
      {coverName ? (
        <img src={media.cover(coverName, priority)} alt={alt} loading="lazy" decoding="async" className={`h-full w-full object-cover ${drift ? 'cover-live' : ''}`} />
      ) : (
        <div className="cover-fallback h-full w-full">
          <CrystalMark size={28} dim />
        </div>
      )}
      {showMotion && motionName ? <MotionLayer url={media.motion(motionName)} /> : null}
      {drift ? <span className="cover-sheen" aria-hidden /> : null}
    </div>
  );
}
