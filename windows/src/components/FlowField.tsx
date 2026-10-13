import { useEffect, useRef } from 'react';

type Dot = {
  homeX: number;
  homeY: number;
  x: number;
  y: number;
  phase: number;
  ease: number;
  depth: number;
};

function randomFrom(n: number) {
  const s = Math.sin(12.9898 * n + 4.1414) * 43758.5453;
  return s - Math.floor(s);
}

export default function FlowField() {
  const ref = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = ref.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    let width = 0;
    let height = 0;
    let dots: Dot[] = [];
    let centers: number[] = [];

    function build() {
      if (!canvas || !ctx) return;
      const ratio = Math.min(window.devicePixelRatio || 1, 2);
      width = window.innerWidth;
      height = window.innerHeight;
      canvas.width = Math.round(width * ratio);
      canvas.height = Math.round(height * ratio);
      canvas.style.width = `${width}px`;
      canvas.style.height = `${height}px`;
      ctx.setTransform(ratio, 0, 0, ratio, 0, 0);

      const scale = parseFloat(getComputedStyle(document.documentElement).fontSize) / 16 || 1;
      const step = (width < 640 ? 40 : 48) * scale;
      const margin = (width < 640 ? 16 : 40) * scale;
      const cols = Math.max(2, Math.floor(Math.min(width - 2 * margin, 1152 * scale) / step) + 1);
      const rows = Math.ceil(height / step) + 1;
      const startX = (width - (cols - 1) * step) / 2;
      const startY = (height - (rows - 1) * step) / 2;

      dots = [];
      let n = 0;
      for (let r = 0; r < rows; r++) {
        for (let c = 0; c < cols; c++) {
          const rnd = randomFrom(n);
          const x = startX + c * step;
          const y = startY + r * step;
          dots.push({ homeX: x, homeY: y, x, y, phase: rnd * Math.PI * 2, ease: 0.06 + 0.05 * rnd, depth: rnd });
          n++;
        }
      }
    }

    function measure() {
      const list = Array.from(document.querySelectorAll('.main .fade-in > *'));
      const top = window.scrollY;
      centers = list.map((el) => {
        const box = el.getBoundingClientRect();
        return box.top + top + box.height / 2;
      });
    }

    function sectionProgress(y: number) {
      if (centers.length < 2 || y <= centers[0] || y >= centers[centers.length - 1]) return 0;
      let i = 0;
      while (i < centers.length - 1 && centers[i + 1] <= y) i++;
      const a = centers[i];
      const b = centers[i + 1];
      if (b <= a) return 0;
      return Math.min(1, Math.max(0, (y - a) / (b - a)));
    }

    function draw(time: number, progress: number) {
      if (!ctx) return;
      ctx.clearRect(0, 0, width, height);
      const midX = width / 2;
      const wave = 1 - progress;
      const strength = Math.min(1, 2 * Math.sin(progress * Math.PI));

      for (let i = 0; i < dots.length; i++) {
        const d = dots[i];
        const offset = (d.homeY / height - wave) / 0.15;
        const m = strength * Math.exp(-offset * offset);
        const pull = 1 - 0.26 * m;
        const calm = 1 - 0.5 * m;

        const wobbleX = d.homeX + 6 * Math.sin(0.6 * time + d.phase) * calm;
        const wobbleY = d.homeY + 6 * Math.cos(0.5 * time + 1.3 * d.phase) * calm;
        const targetX = midX + (wobbleX - midX) * pull;

        d.x += (targetX - d.x) * d.ease;
        d.y += (wobbleY - d.y) * d.ease;

        const alpha = 0.06 * (0.55 + 0.9 * d.depth) * (1 + 1.6 * m);
        if (alpha <= 0.002) continue;

        const tint = 229 + ((26 * 0.4 * m) | 0);
        const radius = 2.4 * (0.7 + 0.6 * d.depth) * (1 + 0.3 * m) * 0.5;
        ctx.fillStyle = `rgba(${tint},${tint},${tint},${alpha})`;
        ctx.beginPath();
        ctx.arc(d.x, d.y, radius, 0, Math.PI * 2);
        ctx.fill();
      }
    }

    build();
    measure();

    if (reduced) {
      draw(0, 0);
      const onResize = () => {
        build();
        measure();
        draw(0, 0);
      };
      window.addEventListener('resize', onResize);
      return () => window.removeEventListener('resize', onResize);
    }

    let time = 0;
    let last = performance.now();
    let raf = 0;

    function frame(now: number) {
      const dt = Math.min(0.05, (now - last) / 1000);
      last = now;
      time += dt;
      draw(time, sectionProgress(window.scrollY + height / 2));
      raf = requestAnimationFrame(frame);
    }
    raf = requestAnimationFrame(frame);

    let resizeTimer = 0;
    const onResize = () => {
      window.clearTimeout(resizeTimer);
      resizeTimer = window.setTimeout(() => {
        build();
        measure();
      }, 150);
    };
    window.addEventListener('resize', onResize);

    const observer = new ResizeObserver(measure);
    observer.observe(document.body);

    return () => {
      cancelAnimationFrame(raf);
      window.clearTimeout(resizeTimer);
      window.removeEventListener('resize', onResize);
      observer.disconnect();
    };
  }, []);

  return <canvas ref={ref} aria-hidden className="flow-field" />;
}
