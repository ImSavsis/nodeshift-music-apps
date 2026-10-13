const ENVELOPE_RATE = 50;
const WINDOW_SECONDS = 10;
const MIN_BPM = 60;
const MAX_BPM = 180;

interface Sample {
  time: number;
  energy: number;
}

type CaptureElement = HTMLMediaElement & { captureStream?: () => MediaStream };

class BeatEngine {
  private context: AudioContext | null = null;
  private analyser: AnalyserNode | null = null;
  private source: MediaStreamAudioSourceNode | null = null;
  private sink: GainNode | null = null;
  private bins: Uint8Array<ArrayBuffer> | null = null;
  private samples: Sample[] = [];
  private lastAnalysis = 0;
  private peakLevel = 0.05;
  private bound: HTMLMediaElement | null = null;
  private pendingBpm = 0;
  private pendingCount = 0;

  bpm = 0;
  energy = 0;

  bind(element: HTMLMediaElement): boolean {
    if (this.bound === element && this.source) return true;
    this.unbind();

    const capture = (element as CaptureElement).captureStream;
    if (typeof capture !== 'function') return false;

    try {
      const stream = capture.call(element);
      if (stream.getAudioTracks().length === 0) return false;

      const AudioContextClass = window.AudioContext ?? (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
      if (!AudioContextClass) return false;

      if (!this.context) this.context = new AudioContextClass();
      if (this.context.state === 'suspended') this.context.resume().catch(() => {});

      this.analyser = this.context.createAnalyser();
      this.analyser.fftSize = 2048;
      this.analyser.smoothingTimeConstant = 0.4;
      this.bins = new Uint8Array(new ArrayBuffer(this.analyser.frequencyBinCount));

      this.sink = this.context.createGain();
      this.sink.gain.value = 0;

      this.source = this.context.createMediaStreamSource(stream);
      this.source.connect(this.analyser);
      this.analyser.connect(this.sink);
      this.sink.connect(this.context.destination);

      this.bound = element;
      this.samples = [];
      this.bpm = 0;
      this.pendingBpm = 0;
      this.pendingCount = 0;
      return true;
    } catch {
      this.unbind();
      return false;
    }
  }

  unbind() {
    try {
      this.source?.disconnect();
      this.analyser?.disconnect();
      this.sink?.disconnect();
    } catch {
      this.source = null;
    }
    this.source = null;
    this.analyser = null;
    this.sink = null;
    this.bound = null;
    this.samples = [];
    this.energy = 0;
  }

  isBound(): boolean {
    return this.source !== null;
  }

  tick(now: number) {
    if (!this.analyser || !this.bins) return;

    this.analyser.getByteFrequencyData(this.bins);
    let sum = 0;
    const count = 8;
    for (let i = 1; i <= count; i += 1) sum += this.bins[i];
    const raw = sum / count / 255;

    this.peakLevel = Math.max(raw, this.peakLevel * 0.9995);
    const level = Math.min(1, raw / Math.max(this.peakLevel, 0.05));

    const attack = level > this.energy ? 0.35 : 0.06;
    this.energy += (level - this.energy) * attack;

    this.samples.push({ time: now / 1000, energy: raw });
    const cutoff = now / 1000 - WINDOW_SECONDS - 1;
    while (this.samples.length > 0 && this.samples[0].time < cutoff) this.samples.shift();

    if (now - this.lastAnalysis > 1000) {
      this.lastAnalysis = now;
      this.estimateTempo(now / 1000);
    }
  }

  private estimateTempo(nowSeconds: number) {
    if (this.samples.length < ENVELOPE_RATE * 5) return;

    const start = nowSeconds - WINDOW_SECONDS;
    const frames = WINDOW_SECONDS * ENVELOPE_RATE;
    const envelope = new Float32Array(frames);
    let cursor = 0;
    for (let n = 0; n < frames; n += 1) {
      const time = start + n / ENVELOPE_RATE;
      while (cursor + 1 < this.samples.length && this.samples[cursor + 1].time <= time) cursor += 1;
      envelope[n] = this.samples[cursor].time <= time ? this.samples[cursor].energy : 0;
    }

    const onset = new Float32Array(frames);
    for (let n = 6; n < frames; n += 1) {
      let mean = 0;
      for (let k = 1; k <= 6; k += 1) mean += envelope[n - k];
      onset[n] = Math.max(0, envelope[n] - mean / 6);
    }

    const minLag = Math.floor((60 / MAX_BPM) * ENVELOPE_RATE);
    const maxLag = Math.ceil((60 / MIN_BPM) * ENVELOPE_RATE);

    let zero = 0;
    for (let n = 0; n < frames; n += 1) zero += onset[n] * onset[n];
    if (zero < 1e-4) return;

    let bestLag = 0;
    let bestScore = 0;
    const scores = new Float32Array(maxLag + 2);
    for (let lag = minLag; lag <= maxLag; lag += 1) {
      let sum = 0;
      for (let n = lag; n < frames; n += 1) sum += onset[n] * onset[n - lag];
      const bpm = (60 * ENVELOPE_RATE) / lag;
      const preference = bpm >= 80 && bpm <= 150 ? 1.08 : 1;
      scores[lag] = sum * preference;
      if (scores[lag] > bestScore) {
        bestScore = scores[lag];
        bestLag = lag;
      }
    }

    if (bestLag === 0 || bestScore / zero < 0.12) return;

    let refined = bestLag;
    if (bestLag > minLag && bestLag < maxLag) {
      const left = scores[bestLag - 1];
      const right = scores[bestLag + 1];
      const denominator = left - 2 * bestScore + right;
      if (denominator !== 0) refined = bestLag + (0.5 * (left - right)) / denominator;
    }

    let bpm = (60 * ENVELOPE_RATE) / refined;
    while (bpm < 70) bpm *= 2;
    while (bpm > 165) bpm /= 2;

    if (this.bpm === 0) {
      this.bpm = bpm;
      return;
    }

    if (Math.abs(bpm - this.bpm) / this.bpm < 0.08) {
      this.bpm = this.bpm * 0.7 + bpm * 0.3;
      this.pendingCount = 0;
      return;
    }

    if (Math.abs(bpm - this.pendingBpm) / Math.max(this.pendingBpm, 1) < 0.08) {
      this.pendingCount += 1;
    } else {
      this.pendingBpm = bpm;
      this.pendingCount = 1;
    }
    if (this.pendingCount >= 4) {
      this.bpm = this.pendingBpm;
      this.pendingCount = 0;
    }
  }
}

export const beatEngine = new BeatEngine();
