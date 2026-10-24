import type { ToolCounts, ToolName } from "../game/types";

interface Props {
  tools: ToolCounts;
  onUseTool: (tool: ToolName) => void;
  onOpenSettings: () => void;
}

const TOOL_META: Array<{ name: ToolName; icon: string; label: string }> = [
  { name: "wand", icon: "🪄", label: "Đũa phép" },
  { name: "brush", icon: "🖌️", label: "Cọ" },
  { name: "magnet", icon: "🧲", label: "Nam châm" },
];

export function ToolDock({ tools, onUseTool, onOpenSettings }: Props) {
  return (
    <div className="tool-dock">
      {TOOL_META.map((t) => (
        <button
          key={t.name}
          className="tool-dock__btn"
          disabled={tools[t.name] <= 0}
          onClick={() => onUseTool(t.name)}
          aria-label={t.label}
        >
          <span className="tool-dock__icon">{t.icon}</span>
          <span className="tool-dock__badge">{tools[t.name]}</span>
        </button>
      ))}
      <button className="tool-dock__btn" onClick={onOpenSettings} aria-label="Cài đặt">
        <span className="tool-dock__icon">⚙️</span>
      </button>
    </div>
  );
}
