import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createPresenceSender, type PresenceBody } from './presenceSender';

function gate() {
  let open: () => void = () => undefined;
  const promise = new Promise<void>((resolve) => {
    open = resolve;
  });
  return { promise, open };
}

describe('presence sender', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('builds the body at send time from the live state', async () => {
    let title = 'first';
    const sent: PresenceBody[] = [];
    const sender = createPresenceSender({
      build: () => ({ title }),
      deliver: async (body) => {
        sent.push(body);
      }
    });
    sender.request();
    title = 'second';
    await vi.advanceTimersByTimeAsync(0);
    expect(sent).toEqual([{ title: 'first' }]);
    sender.request();
    await vi.advanceTimersByTimeAsync(0);
    expect(sent.at(-1)).toEqual({ title: 'second' });
  });

  it('keeps one request in flight and coalesces bursts into the latest state', async () => {
    let title = 'a';
    const gates: ReturnType<typeof gate>[] = [];
    const sent: PresenceBody[] = [];
    let active = 0;
    let peak = 0;
    const sender = createPresenceSender({
      build: () => ({ title }),
      deliver: async (body) => {
        sent.push(body);
        active += 1;
        peak = Math.max(peak, active);
        const next = gate();
        gates.push(next);
        try {
          await next.promise;
        } finally {
          active -= 1;
        }
      }
    });
    sender.request();
    await vi.advanceTimersByTimeAsync(0);
    for (const next of ['b', 'c', 'd', 'e']) {
      title = next;
      sender.request();
    }
    await vi.advanceTimersByTimeAsync(0);
    expect(sent).toEqual([{ title: 'a' }]);
    gates[0].open();
    await vi.advanceTimersByTimeAsync(0);
    expect(sent).toEqual([{ title: 'a' }, { title: 'e' }]);
    gates[1].open();
    await vi.advanceTimersByTimeAsync(0);
    expect(sent).toHaveLength(2);
    expect(peak).toBe(1);
  });

  it('retries failures with the 2, 4, 8, 16, 30 second backoff and rebuilds the body each time', async () => {
    let counter = 0;
    const attempts: number[] = [];
    const sender = createPresenceSender({
      build: () => ({ counter: (counter += 1) }),
      deliver: async () => {
        attempts.push(Date.now());
        throw new Error('offline');
      }
    });
    const start = Date.now();
    sender.request();
    await vi.advanceTimersByTimeAsync(0);
    for (const wait of [2000, 4000, 8000, 16000, 30000, 30000]) {
      await vi.advanceTimersByTimeAsync(wait - 1);
      const before = attempts.length;
      await vi.advanceTimersByTimeAsync(1);
      expect(attempts.length).toBe(before + 1);
    }
    expect(attempts.map((at) => at - start)).toEqual([0, 2000, 6000, 14000, 30000, 60000, 90000]);
    expect(counter).toBe(7);
    sender.cancel();
  });

  it('stops retrying once a send succeeds and resets the backoff', async () => {
    let offline = true;
    const attempts: number[] = [];
    const sender = createPresenceSender({
      build: () => ({}),
      deliver: async () => {
        attempts.push(Date.now());
        if (offline) throw new Error('offline');
      }
    });
    sender.request();
    await vi.advanceTimersByTimeAsync(0);
    offline = false;
    await vi.advanceTimersByTimeAsync(2000);
    expect(attempts).toHaveLength(2);
    await vi.advanceTimersByTimeAsync(120000);
    expect(attempts).toHaveLength(2);
    offline = true;
    sender.request();
    await vi.advanceTimersByTimeAsync(0);
    const failedAt = Date.now();
    await vi.advanceTimersByTimeAsync(2000);
    expect(attempts.at(-1)).toBe(failedAt + 2000);
    sender.cancel();
  });

  it('sends a newer state right away instead of waiting for the backoff', async () => {
    let offline = true;
    let title = 'old';
    const sent: PresenceBody[] = [];
    const sender = createPresenceSender({
      build: () => ({ title }),
      deliver: async (body) => {
        sent.push(body);
        if (offline) throw new Error('offline');
      }
    });
    sender.request();
    await vi.advanceTimersByTimeAsync(0);
    expect(sent).toHaveLength(1);
    offline = false;
    title = 'new';
    sender.request();
    await vi.advanceTimersByTimeAsync(0);
    expect(sent.at(-1)).toEqual({ title: 'new' });
    expect(sent).toHaveLength(2);
    await vi.advanceTimersByTimeAsync(60000);
    expect(sent).toHaveLength(2);
  });

  it('survives a build that throws', async () => {
    let broken = true;
    const sent: PresenceBody[] = [];
    const sender = createPresenceSender({
      build: () => {
        if (broken) throw new Error('no state');
        return { ok: true };
      },
      deliver: async (body) => {
        sent.push(body);
      }
    });
    sender.request();
    await vi.advanceTimersByTimeAsync(0);
    expect(sent).toHaveLength(0);
    broken = false;
    await vi.advanceTimersByTimeAsync(2000);
    expect(sent).toEqual([{ ok: true }]);
  });
});
