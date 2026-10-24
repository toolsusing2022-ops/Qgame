import type { GameState, LevelData, ToolName } from "./types";

function mulberry32(seed: number) {
  return function () {
    seed |= 0;
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function createInitialState(level: LevelData): GameState {
  const rng = mulberry32(1337);
  const paletteIds = level.palette.map((p) => p.id);

  const filled: boolean[][] = [];
  const noiseColor: number[][] = [];
  for (let r = 0; r < level.rows; r++) {
    const filledRow: boolean[] = [];
    const noiseRow: number[] = [];
    for (let c = 0; c < level.cols; c++) {
      filledRow.push(false);
      noiseRow.push(paletteIds[Math.floor(rng() * paletteIds.length)]);
    }
    filled.push(filledRow);
    noiseColor.push(noiseRow);
  }

  const colorOrder = [...level.palette].sort((a, b) => b.count - a.count).map((p) => p.id);

  const remainingInColor: Record<number, number> = {};
  for (const p of level.palette) remainingInColor[p.id] = p.count;

  const totalCount = level.palette.reduce((sum, p) => sum + p.count, 0);

  return {
    level,
    filled,
    noiseColor,
    colorOrder,
    activeIndex: 0,
    remainingInColor,
    tools: { wand: 3, brush: 3, magnet: 3 },
    placedCount: 0,
    totalCount,
    lastPlaced: null,
    isComplete: false,
  };
}

function advanceColorIfDepleted(state: GameState): GameState {
  let activeIndex = state.activeIndex;
  while (
    activeIndex < state.colorOrder.length &&
    state.remainingInColor[state.colorOrder[activeIndex]] <= 0
  ) {
    activeIndex++;
  }
  const isComplete = activeIndex >= state.colorOrder.length;
  return { ...state, activeIndex, isComplete };
}

export function activeColorId(state: GameState): number | null {
  if (state.activeIndex >= state.colorOrder.length) return null;
  return state.colorOrder[state.activeIndex];
}

export function placeBead(state: GameState, row: number, col: number): GameState {
  if (state.isComplete) return state;
  if (state.filled[row][col]) return state;
  const target = activeColorId(state);
  if (target === null) return state;
  if (state.level.cells[row][col] !== target) return state;

  const filled = state.filled.map((r) => r.slice());
  filled[row][col] = true;

  const remainingInColor = { ...state.remainingInColor };
  remainingInColor[target] = Math.max(0, remainingInColor[target] - 1);

  const next: GameState = {
    ...state,
    filled,
    remainingInColor,
    placedCount: state.placedCount + 1,
    lastPlaced: { row, col },
  };

  return advanceColorIfDepleted(next);
}

function unfilledCellsOfColor(state: GameState, colorId: number): Array<[number, number]> {
  const cells: Array<[number, number]> = [];
  for (let r = 0; r < state.level.rows; r++) {
    for (let c = 0; c < state.level.cols; c++) {
      if (!state.filled[r][c] && state.level.cells[r][c] === colorId) cells.push([r, c]);
    }
  }
  return cells;
}

export function useTool(state: GameState, tool: ToolName): GameState {
  if (state.isComplete) return state;
  if (state.tools[tool] <= 0) return state;
  const target = activeColorId(state);
  if (target === null) return state;

  const candidates = unfilledCellsOfColor(state, target);
  if (candidates.length === 0) return state;

  let toFill: Array<[number, number]>;
  if (tool === "wand") {
    toFill = candidates.slice(0, 3);
  } else if (tool === "brush") {
    toFill = candidates.slice(0, Math.max(1, Math.ceil(candidates.length * 0.4)));
  } else {
    toFill = candidates;
  }

  let next = state;
  for (const [r, c] of toFill) {
    next = placeBead(next, r, c);
  }

  return {
    ...next,
    tools: { ...next.tools, [tool]: next.tools[tool] - 1 },
  };
}
