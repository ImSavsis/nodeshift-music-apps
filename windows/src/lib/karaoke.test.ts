import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { activeIndex, driftSeed, fills, lineStyle, syntheticFills, timedFills } from './karaoke';
import type { LyricLine } from './types';

function vector<T>(name: string): T {
  return JSON.parse(readFileSync(new URL(`../../../shared/testdata/${name}`, import.meta.url), 'utf8')) as T;
}

interface KaraokeCase {
  text: string;
  lineTime: number;
  nextTime: number | null;
  samples: Array<{ t: number; fills: number[] }>;
}

interface SeedCase {
  seed: string;
  hash: number;
  duration: number;
  delay: number;
  shiftX: number;
  shiftY: number;
  originX: number;
  originY: number;
  sheenDelay: number;
}

describe('karaoke fills', () => {
  it('matches the shared synthetic fill vectors', () => {
    for (const item of vector<KaraokeCase[]>('karaoke.json')) {
      for (const sample of item.samples) {
        const got = syntheticFills(item.text, item.lineTime, item.nextTime, sample.t);
        expect(got.length).toBe(sample.fills.length);
        got.forEach((value, index) => expect(value).toBeCloseTo(sample.fills[index], 9));
      }
    }
  });

  it('uses word timing when a line has it', () => {
    const line: LyricLine = {
      time: 10,
      text: 'one two',
      words: [
        { text: 'one ', start: 10, end: 11 },
        { text: 'two', start: 11, end: 12 }
      ]
    };
    expect(fills(line, 20, 10.5)).toEqual([0.5, 0]);
    expect(timedFills(line.words ?? [], 12.5)).toEqual([1, 1]);
  });

  it('falls back to synthetic fills without word timing', () => {
    const line: LyricLine = { time: 10, text: 'Hello big world', words: null };
    expect(fills(line, 14, 11.2)).toEqual(syntheticFills('Hello big world', 10, 14, 11.2));
  });
});

describe('active line and style', () => {
  const lines: LyricLine[] = [0, 5, 10, 15].map((time) => ({ time, text: `line ${time}`, words: null }));

  it('finds the active index by binary search', () => {
    expect(activeIndex(lines, -1)).toBe(-1);
    expect(activeIndex(lines, 0)).toBe(0);
    expect(activeIndex(lines, 9.99)).toBe(1);
    expect(activeIndex(lines, 10)).toBe(2);
    expect(activeIndex(lines, 99)).toBe(3);
    expect(activeIndex([], 3)).toBe(-1);
  });

  it('styles lines by distance from the active one', () => {
    expect(lineStyle(2, 2)).toEqual({ opacity: 1, scale: 1, blur: 0 });
    expect(lineStyle(1, 2)).toEqual({ opacity: 0.38, scale: 0.93, blur: 0.55 });
    expect(lineStyle(4, 2)).toEqual({ opacity: 0.3, scale: 0.93, blur: 1.4 });
    expect(lineStyle(20, 2).blur).toBeCloseTo(3.5, 9);
    expect(lineStyle(0, 20).blur).toBeCloseTo(2.75, 9);
  });
});

describe('cover drift seeds', () => {
  it('matches the shared seed vectors', () => {
    for (const item of vector<SeedCase[]>('cover-seeds.json')) {
      const got = driftSeed(item.seed);
      expect(got.hash).toBe(item.hash);
      expect(got.duration).toBe(item.duration);
      expect(got.delay).toBe(item.delay);
      expect(got.shiftX).toBeCloseTo(item.shiftX, 9);
      expect(got.shiftY).toBeCloseTo(item.shiftY, 9);
      expect(got.originX).toBe(item.originX);
      expect(got.originY).toBe(item.originY);
      expect(got.sheenDelay).toBe(item.sheenDelay);
    }
  });
});
