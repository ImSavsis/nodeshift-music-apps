import { create } from 'zustand';

export interface ToastItem {
  id: number;
  message: string;
  actionLabel?: string;
  onAction?: () => void;
}

interface ToastStore {
  toasts: ToastItem[];
  push: (message: string, options?: { actionLabel?: string; onAction?: () => void }) => void;
  dismiss: (id: number) => void;
}

let nextId = 1;

export const useToastStore = create<ToastStore>((set, get) => ({
  toasts: [],

  push: (message, options) => {
    const id = nextId;
    nextId += 1;
    set((state) => ({ toasts: [...state.toasts.slice(-2), { id, message, ...options }] }));
    setTimeout(() => get().dismiss(id), options?.actionLabel ? 6000 : 3000);
  },

  dismiss: (id) => set((state) => ({ toasts: state.toasts.filter((item) => item.id !== id) }))
}));

export function toast(message: string, options?: { actionLabel?: string; onAction?: () => void }) {
  useToastStore.getState().push(message, options);
}
