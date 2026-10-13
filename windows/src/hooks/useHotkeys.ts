import { useEffect } from 'react';
import { toggleFavorite } from '../store/catalog';
import { usePlayerStore } from '../store/player';
import { useUiStore } from '../store/ui';

function isTypingTarget(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false;
  const tag = target.tagName;
  return tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || target.isContentEditable;
}

export function useHotkeys() {
  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.ctrlKey || event.metaKey || event.altKey || isTypingTarget(event.target)) return;

      const player = usePlayerStore.getState();
      const hasTrack = player.currentTrack !== null;

      switch (event.key) {
        case ' ':
          if (!hasTrack) return;
          event.preventDefault();
          player.togglePlay();
          break;
        case 'ArrowRight':
          if (!hasTrack) return;
          event.preventDefault();
          player.requestSeek(Math.min(player.duration, player.currentTime + (event.shiftKey ? 15 : 5)));
          break;
        case 'ArrowLeft':
          if (!hasTrack) return;
          event.preventDefault();
          player.requestSeek(Math.max(0, player.currentTime - (event.shiftKey ? 15 : 5)));
          break;
        case 'ArrowUp':
          if (!player.isExpanded) return;
          event.preventDefault();
          player.setVolume(Math.min(1, player.volume + 0.05));
          break;
        case 'ArrowDown':
          if (!player.isExpanded) return;
          event.preventDefault();
          player.setVolume(Math.max(0, player.volume - 0.05));
          break;
        case 'm':
        case 'M':
          player.toggleMute();
          break;
        case 'n':
        case 'N':
          player.playNext();
          break;
        case 'p':
        case 'P':
          player.playPrevious();
          break;
        case 's':
        case 'S':
          player.toggleShuffle();
          break;
        case 'r':
        case 'R':
          player.cycleRepeat();
          break;
        case 'q':
        case 'Q':
          if (hasTrack) player.toggleQueue();
          break;
        case 'f':
        case 'F':
          if (!hasTrack) return;
          if (player.isExpanded) {
            player.collapse();
          } else {
            player.expand();
          }
          break;
        case 'l':
        case 'L':
          if (player.currentTrack) toggleFavorite(player.currentTrack);
          break;
        case '/': {
          const search = document.querySelector<HTMLInputElement>('[data-search]');
          if (search) {
            event.preventDefault();
            search.focus();
          }
          break;
        }
        case '?':
          useUiStore.getState().setHelpOpen(true);
          break;
        case 'Escape':
          if (player.isQueueOpen) {
            player.closeQueue();
          } else if (player.isExpanded) {
            player.collapse();
          }
          break;
        default:
          break;
      }
    }

    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, []);
}
