function hashOf(text: string): number {
  let hash = 0;
  for (let index = 0; index < text.length; index += 1) hash = (hash * 31 + text.charCodeAt(index)) >>> 0;
  return hash;
}

function hsl(hue: number, saturation: number, lightness: number): string {
  return `hsl(${Math.round(hue) % 360} ${saturation}% ${lightness}%)`;
}

function hslToRgb(hue: number, saturation: number, lightness: number): [number, number, number] {
  const s = saturation / 100;
  const l = lightness / 100;
  const k = (n: number) => (n + hue / 30) % 12;
  const a = s * Math.min(l, 1 - l);
  const f = (n: number) => l - a * Math.max(-1, Math.min(k(n) - 3, Math.min(9 - k(n), 1)));
  return [Math.round(f(0) * 255), Math.round(f(8) * 255), Math.round(f(4) * 255)];
}

export function mockPalette(name: string): Array<[number, number, number]> {
  const hash = hashOf(name);
  const hue = hash % 360;
  const other = (hue + 40 + ((hash >> 8) % 80)) % 360;
  return [hslToRgb(hue, 38, 46), hslToRgb(other, 30, 36), hslToRgb(hue, 22, 20)];
}

const covers = new Map<string, string>();

export function mockCoverUrl(name: string): string {
  const cached = covers.get(name);
  if (cached) return cached;
  const hash = hashOf(name);
  const hue = hash % 360;
  const other = (hue + 40 + ((hash >> 8) % 80)) % 360;
  const variant = (hash >> 4) % 4;
  const light = hsl(hue, 70, 62);
  const dark = hsl(other, 70, 24);
  let shapes = '';
  if (variant === 0) {
    shapes = [60, 120, 180, 240]
      .map((r, index) => `<circle cx="256" cy="256" r="${r}" fill="none" stroke="rgba(255,255,255,${0.32 - index * 0.06})" stroke-width="3"/>`)
      .join('');
    shapes += '<circle cx="256" cy="256" r="26" fill="rgba(255,255,255,0.85)"/>';
  } else if (variant === 1) {
    for (let index = -4; index < 12; index += 1) {
      shapes += `<rect x="${index * 70}" y="-40" width="26" height="620" fill="rgba(255,255,255,0.12)" transform="rotate(24 256 256)"/>`;
    }
  } else if (variant === 2) {
    shapes = `<circle cx="${150 + (hash % 200)}" cy="${170 + ((hash >> 6) % 150)}" r="170" fill="rgba(255,255,255,0.16)"/><circle cx="360" cy="360" r="90" fill="rgba(0,0,0,0.22)"/>`;
  } else {
    shapes = `<polygon points="256,60 440,380 72,380" fill="rgba(255,255,255,0.18)"/><polygon points="256,150 360,340 152,340" fill="rgba(0,0,0,0.2)"/>`;
  }
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${light}"/><stop offset="1" stop-color="${dark}"/></linearGradient></defs><rect width="512" height="512" fill="url(#g)"/>${shapes}</svg>`;
  const url = `data:image/svg+xml;utf8,${encodeURIComponent(svg)}`;
  covers.set(name, url);
  return url;
}

const sounds = new Map<string, string>();

export function mockTrackUrl(id: string, durationMs: number): string {
  const key = `${id}:${durationMs}`;
  const cached = sounds.get(key);
  if (cached) return cached;
  const rate = 8000;
  const frames = Math.max(1, Math.round((durationMs / 1000) * rate));
  const bytes = new Uint8Array(44 + frames);
  const view = new DataView(bytes.buffer);
  const write = (offset: number, text: string) => {
    for (let index = 0; index < text.length; index += 1) bytes[offset + index] = text.charCodeAt(index);
  };
  write(0, 'RIFF');
  view.setUint32(4, 36 + frames, true);
  write(8, 'WAVEfmt ');
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, 1, true);
  view.setUint32(24, rate, true);
  view.setUint32(28, rate, true);
  view.setUint16(32, 1, true);
  view.setUint16(34, 8, true);
  write(36, 'data');
  view.setUint32(40, frames, true);
  bytes.fill(128, 44);
  const url = URL.createObjectURL(new Blob([bytes], { type: 'audio/wav' }));
  sounds.set(key, url);
  return url;
}
