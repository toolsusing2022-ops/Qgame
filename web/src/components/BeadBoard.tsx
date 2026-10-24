import { useEffect, useRef } from "react";
import type { LevelData } from "../game/types";
import { shade } from "../game/color";

interface Props {
  level: LevelData;
  filled: boolean[][];
  noiseColor: number[][];
  paletteMap: Map<number, string>;
  activeColorId: number | null;
  lastPlaced: { row: number; col: number } | null;
  onCellTap: (row: number, col: number) => void;
}

interface PlacedAnim {
  row: number;
  col: number;
  start: number;
}

export function BeadBoard({
  level,
  filled,
  noiseColor,
  paletteMap,
  activeColorId,
  lastPlaced,
  onCellTap,
}: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const wrapRef = useRef<HTMLDivElement>(null);
  const cellPxRef = useRef(20);
  const animsRef = useRef<PlacedAnim[]>([]);
  const rafRef = useRef<number>(0);

  useEffect(() => {
    if (!lastPlaced) return;
    animsRef.current.push({ ...lastPlaced, start: performance.now() });
  }, [lastPlaced]);

  useEffect(() => {
    const canvas = canvasRef.current;
    const wrap = wrapRef.current;
    if (!canvas || !wrap) return;
    const ctx2d = canvas.getContext("2d");
    if (!ctx2d) return;

    function resize() {
      const dpr = window.devicePixelRatio || 1;
      const width = wrap!.clientWidth;
      const cellPx = width / level.cols;
      cellPxRef.current = cellPx;
      const height = cellPx * level.rows;
      canvas!.style.width = `${width}px`;
      canvas!.style.height = `${height}px`;
      canvas!.width = Math.round(width * dpr);
      canvas!.height = Math.round(height * dpr);
      ctx2d!.setTransform(dpr, 0, 0, dpr, 0, 0);
    }
    resize();
    const ro = new ResizeObserver(resize);
    ro.observe(wrap);
    return () => ro.disconnect();
  }, [level.cols, level.rows]);

  useEffect(() => {
    const canvas = canvasRef.current;
    const ctx2d = canvas?.getContext("2d");
    if (!canvas || !ctx2d) return;

    function draw(time: number) {
      const cellPx = cellPxRef.current;
      const width = canvas!.clientWidth;
      const height = canvas!.clientHeight;
      ctx2d!.clearRect(0, 0, width, height);

      animsRef.current = animsRef.current.filter((a) => time - a.start < 260);
      const animMap = new Map<string, number>();
      for (const a of animsRef.current) {
        animMap.set(`${a.row}:${a.col}`, time - a.start);
      }

      const shimmerPhase = time / 1400;

      for (let r = 0; r < level.rows; r++) {
        for (let c = 0; c < level.cols; c++) {
          const cx = c * cellPx + cellPx / 2;
          const cy = r * cellPx + cellPx / 2;
          const baseRadius = cellPx * 0.44;
          const isFilled = filled[r][c];
          const trueColor = level.cells[r][c];
          const animT = animMap.get(`${r}:${c}`);

          let radius = baseRadius;
          if (animT !== undefined) {
            const p = Math.min(1, animT / 260);
            const bounce = 1 + 0.35 * Math.sin(p * Math.PI) * (1 - p);
            radius = baseRadius * bounce;
          }

          if (isFilled) {
            const hex = paletteMap.get(trueColor) ?? "#888888";
            ctx2d!.beginPath();
            ctx2d!.arc(cx, cy, radius, 0, Math.PI * 2);
            ctx2d!.fillStyle = shade(hex, -0.18);
            ctx2d!.fill();

            ctx2d!.beginPath();
            ctx2d!.arc(cx, cy, radius * 0.82, 0, Math.PI * 2);
            ctx2d!.fillStyle = hex;
            ctx2d!.fill();

            ctx2d!.beginPath();
            ctx2d!.arc(cx, cy, radius * 0.34, 0, Math.PI * 2);
            ctx2d!.fillStyle = shade(hex, 0.22);
            ctx2d!.fill();
          } else {
            const noiseId = noiseColor[r][c];
            const hex = paletteMap.get(noiseId) ?? "#889";
            const isTarget = trueColor === activeColorId;

            if (isTarget) {
              const pulse = 0.5 + 0.5 * Math.sin(time / 420 + (r + c) * 0.6);
              ctx2d!.beginPath();
              ctx2d!.arc(cx, cy, radius * (1.0 + 0.1 * pulse), 0, Math.PI * 2);
              ctx2d!.strokeStyle = `rgba(255,255,255,${0.25 + 0.35 * pulse})`;
              ctx2d!.lineWidth = Math.max(1, cellPx * 0.06);
              ctx2d!.stroke();
            }

            const grad = ctx2d!.createRadialGradient(
              cx - radius * 0.3,
              cy - radius * 0.3,
              radius * 0.1,
              cx,
              cy,
              radius
            );
            const shimmer = 0.06 * Math.sin(shimmerPhase + r * 0.4 + c * 0.3);
            grad.addColorStop(0, shade(hex, 0.35 + shimmer));
            grad.addColorStop(0.6, hex);
            grad.addColorStop(1, shade(hex, -0.25));
            ctx2d!.beginPath();
            ctx2d!.arc(cx, cy, radius, 0, Math.PI * 2);
            ctx2d!.fillStyle = grad;
            ctx2d!.fill();
          }
        }
      }

      rafRef.current = requestAnimationFrame(draw);
    }

    rafRef.current = requestAnimationFrame(draw);
    return () => cancelAnimationFrame(rafRef.current);
  }, [level, filled, noiseColor, paletteMap, activeColorId]);

  function handlePointer(e: React.PointerEvent<HTMLCanvasElement>) {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const rect = canvas.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;
    const cellPx = cellPxRef.current;
    const col = Math.floor(x / cellPx);
    const row = Math.floor(y / cellPx);
    if (row >= 0 && row < level.rows && col >= 0 && col < level.cols) {
      onCellTap(row, col);
    }
  }

  return (
    <div ref={wrapRef} className="bead-board-wrap">
      <canvas ref={canvasRef} className="bead-board-canvas" onPointerDown={handlePointer} />
    </div>
  );
}
