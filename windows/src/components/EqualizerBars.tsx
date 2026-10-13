import { motion } from 'framer-motion';

interface EqualizerBarsProps {
  isPlaying: boolean;
  className?: string;
  barClassName?: string;
}

const BAR_DELAYS = [0, 0.15, 0.3, 0.1];

export function EqualizerBars({ isPlaying, className = '', barClassName = 'bg-accent' }: EqualizerBarsProps) {
  return (
    <div className={`flex h-3.5 items-end gap-0.5 ${className}`}>
      {BAR_DELAYS.map((delay, index) => (
        <motion.span
          key={index}
          className={`w-0.5 rounded-full ${barClassName}`}
          style={{ height: '100%', originY: 1 }}
          animate={isPlaying ? { scaleY: [0.25, 1, 0.4, 0.9, 0.25] } : { scaleY: 0.25 }}
          transition={isPlaying ? { duration: 1 + delay, repeat: Infinity, ease: 'easeInOut', delay } : { duration: 0.2 }}
        />
      ))}
    </div>
  );
}
