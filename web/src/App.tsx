import { useEffect, useMemo, useReducer, useRef, useState } from "react";
import "./App.css";
import { BeadBoard } from "./components/BeadBoard";
import { BeadTray } from "./components/BeadTray";
import { ToolDock } from "./components/ToolDock";
import { SettingsModal } from "./components/SettingsModal";
import { CompletionOverlay } from "./components/CompletionOverlay";
import { activeColorId, createInitialState, placeBead, useTool } from "./game/engine";
import type { GameState, LevelData, ToolName } from "./game/types";
import {
  playBeadPlace,
  playColorComplete,
  playPictureComplete,
  playToolUse,
  setAmbientEnabled,
  setSfxEnabled,
  startAmbient,
  unlockAudio,
} from "./audio/soundManager";

import levelEasy from "./data/level-easy.json";
import levelRelax from "./data/level-relax.json";
import levelChallenge from "./data/level-challenge.json";

type Difficulty = "easy" | "relax" | "challenge";

const LEVELS: Record<Difficulty, LevelData> = {
  easy: levelEasy as LevelData,
  relax: levelRelax as LevelData,
  challenge: levelChallenge as LevelData,
};

const DIFFICULTY_LABEL: Record<Difficulty, string> = {
  easy: "Dễ",
  relax: "Thư giãn",
  challenge: "Thử thách",
};

type Action =
  | { type: "TAP"; row: number; col: number }
  | { type: "TOOL"; tool: ToolName }
  | { type: "RESTART"; level: LevelData };

function reducer(state: GameState, action: Action): GameState {
  switch (action.type) {
    case "TAP":
      return placeBead(state, action.row, action.col);
    case "TOOL":
      return useTool(state, action.tool);
    case "RESTART":
      return createInitialState(action.level);
    default:
      return state;
  }
}

function App() {
  const [difficulty, setDifficulty] = useState<Difficulty>("relax");
  const [state, dispatch] = useReducer(reducer, LEVELS.relax, createInitialState);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [sfxOn, setSfxOn] = useState(true);
  const [ambientOn, setAmbientOn] = useState(true);
  const [justConsumedTick, setJustConsumedTick] = useState(0);

  const placedCountRef = useRef(state.placedCount);
  const activeIndexRef = useRef(state.activeIndex);
  const mountedRef = useRef(false);
  const audioStartedRef = useRef(false);

  const paletteMap = useMemo(() => {
    const m = new Map<number, string>();
    for (const p of state.level.palette) m.set(p.id, p.hex);
    return m;
  }, [state.level]);

  const activeId = activeColorId(state);
  const activeHex = activeId !== null ? paletteMap.get(activeId) ?? null : null;
  const remaining = activeId !== null ? state.remainingInColor[activeId] : 0;

  useEffect(() => {
    if (placedCountRef.current !== state.placedCount) {
      playBeadPlace(state.placedCount);
      placedCountRef.current = state.placedCount;
      setJustConsumedTick((t) => t + 1);
    }
  }, [state.placedCount]);

  useEffect(() => {
    if (mountedRef.current && activeIndexRef.current !== state.activeIndex) {
      playColorComplete(state.activeIndex);
    }
    activeIndexRef.current = state.activeIndex;
    mountedRef.current = true;
  }, [state.activeIndex]);

  useEffect(() => {
    if (state.isComplete) playPictureComplete();
  }, [state.isComplete]);

  function ensureAudio() {
    unlockAudio();
    if (!audioStartedRef.current) {
      startAmbient();
      audioStartedRef.current = true;
    }
  }

  function handleCellTap(row: number, col: number) {
    ensureAudio();
    dispatch({ type: "TAP", row, col });
  }

  function handleTool(tool: ToolName) {
    ensureAudio();
    if (state.tools[tool] <= 0) return;
    playToolUse();
    dispatch({ type: "TOOL", tool });
  }

  function handleRestart(nextDifficulty?: Difficulty) {
    const d = nextDifficulty ?? difficulty;
    setDifficulty(d);
    dispatch({ type: "RESTART", level: LEVELS[d] });
    setSettingsOpen(false);
  }

  function toggleSfx() {
    const next = !sfxOn;
    setSfxOn(next);
    setSfxEnabled(next);
  }

  function toggleAmbient() {
    const next = !ambientOn;
    setAmbientOn(next);
    setAmbientEnabled(next);
  }

  const progress = state.totalCount > 0 ? state.placedCount / state.totalCount : 0;

  return (
    <div className="app">
      <header className="app__header">
        <h1>Mực Biếc</h1>
        <div className="difficulty-switch">
          {(Object.keys(LEVELS) as Difficulty[]).map((d) => (
            <button
              key={d}
              className={`difficulty-switch__btn ${d === difficulty ? "difficulty-switch__btn--active" : ""}`}
              onClick={() => handleRestart(d)}
            >
              {DIFFICULTY_LABEL[d]}
            </button>
          ))}
        </div>
      </header>

      <div className="progress-bar">
        <div className="progress-bar__fill" style={{ width: `${progress * 100}%` }} />
      </div>

      <BeadBoard
        level={state.level}
        filled={state.filled}
        noiseColor={state.noiseColor}
        paletteMap={paletteMap}
        activeColorId={activeId}
        lastPlaced={state.lastPlaced}
        onCellTap={handleCellTap}
      />

      <BeadTray colorHex={activeHex} remaining={remaining} justConsumed={justConsumedTick > 0} />

      <ToolDock tools={state.tools} onUseTool={handleTool} onOpenSettings={() => setSettingsOpen(true)} />

      {settingsOpen && (
        <SettingsModal
          sfxEnabled={sfxOn}
          ambientEnabled={ambientOn}
          onToggleSfx={toggleSfx}
          onToggleAmbient={toggleAmbient}
          onRestart={() => handleRestart()}
          onClose={() => setSettingsOpen(false)}
        />
      )}

      {state.isComplete && <CompletionOverlay onRestart={() => handleRestart()} />}
    </div>
  );
}

export default App;
