export interface PaletteEntry {
  id: number;
  hex: string;
  count: number;
}

export interface LevelData {
  cols: number;
  rows: number;
  palette: PaletteEntry[];
  cells: number[][];
}

export interface ToolCounts {
  wand: number;
  brush: number;
  magnet: number;
}

export interface GameState {
  level: LevelData;
  filled: boolean[][];
  noiseColor: number[][];
  colorOrder: number[];
  activeIndex: number;
  remainingInColor: Record<number, number>;
  tools: ToolCounts;
  placedCount: number;
  totalCount: number;
  lastPlaced: { row: number; col: number } | null;
  isComplete: boolean;
}

export type ToolName = "wand" | "brush" | "magnet";
