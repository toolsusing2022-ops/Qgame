export function hexToRgb(hex: string): [number, number, number] {
  const h = hex.replace("#", "");
  return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)];
}

export function rgbToHex(r: number, g: number, b: number): string {
  const clamp = (v: number) => Math.max(0, Math.min(255, Math.round(v)));
  return `#${[r, g, b].map((v) => clamp(v).toString(16).padStart(2, "0")).join("")}`;
}

export function shade(hex: string, amount: number): string {
  const [r, g, b] = hexToRgb(hex);
  if (amount >= 0) {
    return rgbToHex(r + (255 - r) * amount, g + (255 - g) * amount, b + (255 - b) * amount);
  }
  return rgbToHex(r * (1 + amount), g * (1 + amount), b * (1 + amount));
}

export function relativeLuminance(hex: string): number {
  const [r, g, b] = hexToRgb(hex);
  return (0.299 * r + 0.587 * g + 0.114 * b) / 255;
}
