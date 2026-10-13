import type { Config } from 'tailwindcss';

const config: Config = {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        base: '#0a0a0a',
        surface: 'rgba(255,255,255,0.05)',
        surface2: 'rgba(255,255,255,0.09)',
        border: 'rgba(255,255,255,0.08)',
        border2: 'rgba(255,255,255,0.14)',
        primary: '#ffffff',
        text: '#e5e5e5',
        muted: 'rgba(255,255,255,0.6)',
        dim: 'rgba(255,255,255,0.45)',
        accent: '#ffffff',
        ok: '#3fb950',
        warn: '#e3b341',
        danger: '#ff5555'
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
        display: ['Unbounded', 'Inter', 'system-ui', 'sans-serif'],
        mono: ['JetBrains Mono', 'ui-monospace', 'SFMono-Regular', 'Menlo', 'monospace']
      },
      borderRadius: {
        card: '1.25rem',
        tile: '0.75rem',
        pill: '999px'
      },
      boxShadow: {
        edge: 'inset 0 1px 0 rgba(255,255,255,0.16), inset 0 -1px 0 rgba(255,255,255,0.05)',
        float: '0 2px 4px rgba(0,0,0,0.5), 0 18px 48px rgba(0,0,0,0.35)'
      }
    }
  },
  plugins: []
};

export default config;
