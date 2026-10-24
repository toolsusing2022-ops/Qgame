interface Props {
  colorHex: string | null;
  remaining: number;
  justConsumed: boolean;
}

const MAX_SLOTS = 10;

export function BeadTray({ colorHex, remaining, justConsumed }: Props) {
  if (!colorHex) {
    return (
      <div className="bead-tray bead-tray--done">
        <span>Hoàn thành tất cả màu!</span>
      </div>
    );
  }

  const shown = Math.min(remaining, MAX_SLOTS);
  const overflow = remaining - shown;

  return (
    <div className="bead-tray">
      <div className="bead-tray__current" style={{ background: colorHex }} />
      <div className="bead-tray__slots">
        {Array.from({ length: MAX_SLOTS }).map((_, i) => {
          const active = i < shown;
          const isLast = justConsumed && i === shown;
          return (
            <div
              key={i}
              className={`bead-tray__slot ${active ? "bead-tray__slot--full" : ""} ${
                isLast ? "bead-tray__slot--pop" : ""
              }`}
              style={active ? { background: colorHex } : undefined}
            />
          );
        })}
      </div>
      {overflow > 0 && <span className="bead-tray__overflow">+{overflow}</span>}
    </div>
  );
}
