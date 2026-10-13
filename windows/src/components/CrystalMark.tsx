export default function CrystalMark({ size = 96, dim = false }: { size?: number; dim?: boolean }) {
  const o = dim ? 0.55 : 1;
  return (
    <svg className="crystal-mark" width={size} height={size} viewBox="0 0 96 96" fill="none" aria-hidden="true" style={{ opacity: o }}>
      <defs>
        <linearGradient id="cmA" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#ffffff" stopOpacity="0.95" />
          <stop offset="1" stopColor="#bfc4d0" stopOpacity="0.55" />
        </linearGradient>
        <linearGradient id="cmB" x1="1" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#e8ebf2" stopOpacity="0.8" />
          <stop offset="1" stopColor="#8a90a0" stopOpacity="0.4" />
        </linearGradient>
      </defs>
      <polygon points="48,6 76,34 48,52" fill="url(#cmA)" />
      <polygon points="48,6 20,34 48,52" fill="url(#cmB)" />
      <polygon points="20,34 48,52 48,90" fill="url(#cmA)" opacity="0.7" />
      <polygon points="76,34 48,52 48,90" fill="url(#cmB)" opacity="0.8" />
      <polygon points="48,6 76,34 48,52 20,34" stroke="rgba(255,255,255,0.45)" strokeWidth="0.8" fill="none" />
      <polyline points="20,34 48,90 76,34" stroke="rgba(255,255,255,0.25)" strokeWidth="0.8" fill="none" />
    </svg>
  );
}
