import { useEffect, useState } from 'react';
import { api } from '../lib/api';

const cache = new Map<string, string[]>();

export const FALLBACK_PALETTE = ['72, 76, 94', '46, 50, 64', '28, 30, 40'];

export function usePalette(coverName: string | null): string[] {
  const [palette, setPalette] = useState<string[]>(coverName ? (cache.get(coverName) ?? FALLBACK_PALETTE) : FALLBACK_PALETTE);

  useEffect(() => {
    if (!coverName) {
      setPalette(FALLBACK_PALETTE);
      return;
    }

    const cached = cache.get(coverName);
    if (cached) {
      setPalette(cached);
      return;
    }

    let cancelled = false;
    api
      .palette(coverName)
      .then((colors) => {
        if (cancelled) return;
        const result = colors.length >= 3 ? colors.slice(0, 3).map(([red, green, blue]) => `${red}, ${green}, ${blue}`) : FALLBACK_PALETTE;
        cache.set(coverName, result);
        setPalette(result);
      })
      .catch(() => {
        if (!cancelled) setPalette(FALLBACK_PALETTE);
      });

    return () => {
      cancelled = true;
    };
  }, [coverName]);

  return palette;
}
