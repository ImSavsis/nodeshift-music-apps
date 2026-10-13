const LOSSLESS = new Set(['flac', 'wav', 'aiff', 'alac', 'ape']);

export function FormatBadge({ format, className = '' }: { format: string; className?: string }) {
  const lossless = LOSSLESS.has(format.toLowerCase());
  return (
    <span
      className={`inline-flex shrink-0 items-center rounded border px-1.5 py-px font-mono text-[0.5938rem] uppercase leading-4 tracking-wider ${
        lossless ? 'border-white/40 bg-white/10 text-primary' : 'border-border2 text-dim'
      } ${className}`}
    >
      {format}
    </span>
  );
}
