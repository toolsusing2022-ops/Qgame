let ctx: AudioContext | null = null;
let ambientSource: AudioBufferSourceNode | null = null;
let ambientGain: GainNode | null = null;
let masterGain: GainNode | null = null;

let sfxEnabled = true;
let ambientEnabled = true;

function getCtx(): AudioContext {
  if (!ctx) {
    ctx = new AudioContext();
    masterGain = ctx.createGain();
    masterGain.gain.value = 0.9;
    masterGain.connect(ctx.destination);
  }
  return ctx;
}

export function unlockAudio() {
  const c = getCtx();
  if (c.state === "suspended") c.resume();
}

function now() {
  return getCtx().currentTime;
}

function noiseBuffer(c: AudioContext, duration: number, color: "white" | "brown" = "white") {
  const length = Math.floor(c.sampleRate * duration);
  const buffer = c.createBuffer(1, length, c.sampleRate);
  const data = buffer.getChannelData(0);
  if (color === "white") {
    for (let i = 0; i < length; i++) data[i] = Math.random() * 2 - 1;
  } else {
    let last = 0;
    for (let i = 0; i < length; i++) {
      const white = Math.random() * 2 - 1;
      last = (last + 0.02 * white) / 1.02;
      data[i] = last * 3.2;
    }
  }
  return buffer;
}

/** Soft "tok" — a bead clicking into its socket. Filtered noise burst + a short pitched blip. */
export function playBeadPlace(variation = 0) {
  if (!sfxEnabled) return;
  const c = getCtx();
  const t = now();

  const src = c.createBufferSource();
  src.buffer = noiseBuffer(c, 0.05, "white");
  const bp = c.createBiquadFilter();
  bp.type = "bandpass";
  bp.frequency.value = 1800 + variation * 60;
  bp.Q.value = 1.1;
  const noiseGain = c.createGain();
  noiseGain.gain.setValueAtTime(0.22, t);
  noiseGain.gain.exponentialRampToValueAtTime(0.001, t + 0.045);
  src.connect(bp).connect(noiseGain).connect(masterGain!);
  src.start(t);
  src.stop(t + 0.06);

  const osc = c.createOscillator();
  osc.type = "sine";
  osc.frequency.setValueAtTime(520 + variation * 18, t);
  osc.frequency.exponentialRampToValueAtTime(260, t + 0.07);
  const oscGain = c.createGain();
  oscGain.gain.setValueAtTime(0.12, t);
  oscGain.gain.exponentialRampToValueAtTime(0.001, t + 0.09);
  osc.connect(oscGain).connect(masterGain!);
  osc.start(t);
  osc.stop(t + 0.1);
}

/** Gentle bell chime for finishing a color. */
export function playColorComplete(step = 0) {
  if (!sfxEnabled) return;
  const c = getCtx();
  const t = now();
  const baseFreqs = [523.25, 587.33, 659.25, 783.99, 880.0];
  const freq = baseFreqs[step % baseFreqs.length];

  [1, 2.01, 3.0].forEach((mult, i) => {
    const osc = c.createOscillator();
    osc.type = "sine";
    osc.frequency.value = freq * mult;
    const gain = c.createGain();
    const peak = 0.16 / (i + 1);
    gain.gain.setValueAtTime(0.0001, t);
    gain.gain.exponentialRampToValueAtTime(peak, t + 0.02);
    gain.gain.exponentialRampToValueAtTime(0.0001, t + 0.9 + i * 0.1);
    osc.connect(gain).connect(masterGain!);
    osc.start(t);
    osc.stop(t + 1.1);
  });
}

/** Sparkly arpeggio for completing the whole picture. */
export function playPictureComplete() {
  if (!sfxEnabled) return;
  const freqs = [523.25, 659.25, 783.99, 1046.5, 1318.5];
  freqs.forEach((f, i) => {
    setTimeout(() => {
      const c = getCtx();
      const t = now();
      const osc = c.createOscillator();
      osc.type = "triangle";
      osc.frequency.value = f;
      const gain = c.createGain();
      gain.gain.setValueAtTime(0.0001, t);
      gain.gain.exponentialRampToValueAtTime(0.2, t + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.0001, t + 0.8);
      osc.connect(gain).connect(masterGain!);
      osc.start(t);
      osc.stop(t + 0.9);
    }, i * 90);
  });
}

/** Soft filtered noise sweep for using a help tool. */
export function playToolUse() {
  if (!sfxEnabled) return;
  const c = getCtx();
  const t = now();
  const src = c.createBufferSource();
  src.buffer = noiseBuffer(c, 0.5, "white");
  const bp = c.createBiquadFilter();
  bp.type = "bandpass";
  bp.frequency.setValueAtTime(400, t);
  bp.frequency.exponentialRampToValueAtTime(2600, t + 0.45);
  bp.Q.value = 0.8;
  const gain = c.createGain();
  gain.gain.setValueAtTime(0.0001, t);
  gain.gain.exponentialRampToValueAtTime(0.18, t + 0.08);
  gain.gain.exponentialRampToValueAtTime(0.0001, t + 0.5);
  src.connect(bp).connect(gain).connect(masterGain!);
  src.start(t);
  src.stop(t + 0.55);
}

export function startAmbient() {
  const c = getCtx();
  if (ambientSource) return;
  ambientSource = c.createBufferSource();
  ambientSource.buffer = noiseBuffer(c, 4, "brown");
  ambientSource.loop = true;
  const lp = c.createBiquadFilter();
  lp.type = "lowpass";
  lp.frequency.value = 500;
  ambientGain = c.createGain();
  ambientGain.gain.value = ambientEnabled ? 0.05 : 0;
  ambientSource.connect(lp).connect(ambientGain).connect(masterGain!);
  ambientSource.start();
}

export function setSfxEnabled(v: boolean) {
  sfxEnabled = v;
}

export function setAmbientEnabled(v: boolean) {
  ambientEnabled = v;
  if (ambientGain) ambientGain.gain.setTargetAtTime(v ? 0.05 : 0, now(), 0.2);
}

export function getAudioFlags() {
  return { sfxEnabled, ambientEnabled };
}
