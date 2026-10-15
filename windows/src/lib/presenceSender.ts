export type PresenceBody = Record<string, unknown>;

export const RETRY_DELAYS_MS: readonly number[] = [2000, 4000, 8000, 16000, 30000];

export interface PresenceSenderOptions {
  build: () => PresenceBody;
  deliver: (body: PresenceBody) => Promise<unknown>;
  delays?: readonly number[];
}

export interface PresenceSender {
  request: () => void;
  cancel: () => void;
}

export function createPresenceSender({ build, deliver, delays = RETRY_DELAYS_MS }: PresenceSenderOptions): PresenceSender {
  let inFlight = false;
  let pending = false;
  let failures = 0;
  let timer: ReturnType<typeof setTimeout> | undefined;

  function clearTimer() {
    if (timer === undefined) return;
    clearTimeout(timer);
    timer = undefined;
  }

  function retryDelay() {
    return delays[Math.min(failures - 1, delays.length - 1)];
  }

  async function drain() {
    inFlight = true;
    while (pending) {
      pending = false;
      let delivered = true;
      try {
        await deliver(build());
      } catch {
        delivered = false;
      }
      if (delivered) {
        failures = 0;
        continue;
      }
      failures += 1;
      if (!pending) {
        timer = setTimeout(() => {
          timer = undefined;
          request();
        }, retryDelay());
      }
    }
    inFlight = false;
  }

  function request() {
    pending = true;
    clearTimer();
    if (!inFlight) void drain();
  }

  return { request, cancel: clearTimer };
}
