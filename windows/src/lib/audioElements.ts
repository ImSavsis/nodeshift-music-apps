let activeElement: HTMLMediaElement | null = null;

export function setActiveMediaElement(element: HTMLMediaElement | null) {
  activeElement = element;
}

export function getActiveMediaElement(): HTMLMediaElement | null {
  return activeElement;
}
