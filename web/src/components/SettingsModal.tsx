interface Props {
  sfxEnabled: boolean;
  ambientEnabled: boolean;
  onToggleSfx: () => void;
  onToggleAmbient: () => void;
  onRestart: () => void;
  onClose: () => void;
}

export function SettingsModal({
  sfxEnabled,
  ambientEnabled,
  onToggleSfx,
  onToggleAmbient,
  onRestart,
  onClose,
}: Props) {
  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-card" onClick={(e) => e.stopPropagation()}>
        <h2>Cài đặt</h2>
        <label className="modal-row">
          <span>Âm thanh đính hạt</span>
          <input type="checkbox" checked={sfxEnabled} onChange={onToggleSfx} />
        </label>
        <label className="modal-row">
          <span>Âm nền thư giãn</span>
          <input type="checkbox" checked={ambientEnabled} onChange={onToggleAmbient} />
        </label>
        <button className="modal-btn modal-btn--danger" onClick={onRestart}>
          Chơi lại từ đầu
        </button>
        <button className="modal-btn" onClick={onClose}>
          Đóng
        </button>
      </div>
    </div>
  );
}
