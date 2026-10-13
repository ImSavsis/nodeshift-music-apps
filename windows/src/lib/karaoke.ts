import type { LyricLine, LyricWord } from './types';

export const MAX_LINE_SECONDS = 7;
export const MIN_SPAN = 0.6;
export const SPAN_FACTOR = 0.92;

export interface SyntheticWord {
  text: string;
  start: number;
  end: number;
}

export interface LineStyle {
  opacity: number;
  scale: number;
  blur: number;
}

export function clamp01(value: number): number {
  return Math.min(1, Math.max(0, value));
}

export function splitWords(text: string): string[] {
  return text.split(/\s+/).filter((part) => part.length > 0);
}

export function syntheticWords(text: string): SyntheticWord[] {
  const parts = splitWords(text);
  const weights = parts.map((part) => [...part].length + 1.5);
  const sum = weights.reduce((total, weight) => total + weight, 0);
  const total = sum === 0 ? 1 : sum;
  let cursor = 0;
  return parts.map((part, index) => {
    const start = cursor / total;
    cursor += weights[index];
    return { text: part, start, end: cursor / total };
  });
}

export function span(lineTime: number, nextTime: number | null): number {
  const next = nextTime ?? lineTime + MAX_LINE_SECONDS;
  return Math.max(MIN_SPAN, Math.min(next - lineTime, MAX_LINE_SECONDS) * SPAN_FACTOR);
}

export function syntheticFills(text: string, lineTime: number, nextTime: number | null, at: number): number[] {
  const progress = clamp01((at - lineTime) / span(lineTime, nextTime));
  return syntheticWords(text).map((word) => {
    const width = word.end - word.start;
    return width <= 0 ? 1 : clamp01((progress - word.start) / width);
  });
}

export function timedFills(words: LyricWord[], at: number): number[] {
  return words.map((word) => clamp01((at - word.start) / Math.max(word.end - word.start, 0.001)));
}

export function fills(line: LyricLine, nextTime: number | null, at: number): number[] {
  if (line.words && line.words.length > 0) return timedFills(line.words, at);
  return syntheticFills(line.text, line.time, nextTime, at);
}

export function activeIndex(lines: LyricLine[], at: number): number {
  let low = 0;
  let high = lines.length - 1;
  let found = -1;
  while (low <= high) {
    const mid = (low + high) >> 1;
    if (lines[mid].time <= at) {
      found = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return found;
}

export function lineStyle(index: number, active: number): LineStyle {
  if (index === active) return { opacity: 1, scale: 1, blur: 0 };
  const distance = Math.abs(index - active);
  if (index < active) return { opacity: 0.38, scale: 0.93, blur: Math.min(distance, 5) * 0.55 };
  return { opacity: 0.3, scale: 0.93, blur: Math.min(distance, 5) * 0.7 };
}

export interface DriftSeed {
  hash: number;
  duration: number;
  delay: number;
  shiftX: number;
  shiftY: number;
  originX: number;
  originY: number;
  sheenDelay: number;
}

export function hashOf(text: string): number {
  let hash = 0;
  for (let index = 0; index < text.length; index += 1) hash = (hash * 31 + text.charCodeAt(index)) >>> 0;
  return hash;
}

function round1(value: number): number {
  return Math.round(value * 10) / 10;
}

export function driftSeed(seed: string): DriftSeed {
  const hash = hashOf(seed);
  const signX = hash & 1 ? 1 : -1;
  const signY = hash & 2 ? 1 : -1;
  return {
    hash,
    duration: 18 + (hash % 13),
    delay: -((hash >> 4) % 20) + 0,
    shiftX: round1(signX * (1.5 + (hash % 3) * 0.6)),
    shiftY: round1(signY * (1 + ((hash >> 2) % 3) * 0.5)),
    originX: 30 + ((hash >> 8) % 40),
    originY: 30 + ((hash >> 12) % 40),
    sheenDelay: -((hash >> 6) % 9) + 0
  };
}
