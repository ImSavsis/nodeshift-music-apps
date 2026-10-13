import { useEffect, useRef, useState } from 'react';
import type { RefObject } from 'react';

type Listener = (visible: boolean) => void;

const listeners = new WeakMap<Element, Listener>();
let observer: IntersectionObserver | null = null;

function sharedObserver(): IntersectionObserver {
  if (!observer) {
    observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) listeners.get(entry.target)?.(entry.isIntersecting);
      },
      { rootMargin: '160px' }
    );
  }
  return observer;
}

export function useInView<T extends Element>(): [RefObject<T>, boolean] {
  const ref = useRef<T>(null);
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const element = ref.current;
    if (!element || typeof IntersectionObserver === 'undefined') {
      setVisible(true);
      return;
    }
    listeners.set(element, setVisible);
    sharedObserver().observe(element);
    return () => {
      sharedObserver().unobserve(element);
      listeners.delete(element);
    };
  }, []);

  return [ref, visible];
}
