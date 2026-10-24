interface Props {
  onRestart: () => void;
}

export function CompletionOverlay({ onRestart }: Props) {
  return (
    <div className="completion-overlay">
      <div className="completion-card">
        <div className="completion-card__sparkle">✨🦑✨</div>
        <h2>Hoàn thành!</h2>
        <p>Bạn đã đính xong bức tranh.</p>
        <button className="modal-btn" onClick={onRestart}>
          Chơi lại
        </button>
      </div>
    </div>
  );
}
