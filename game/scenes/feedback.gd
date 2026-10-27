# Sound and haptic feedback (gameplay spec section 11). Separate from analytics (GS-14.1).
# Sounds are optional: drop files into res://game/audio/<name>/ (wav or ogg) and they are picked up.
# Names: place (4-6 variants), wrong, lift, pick, color_complete, level_complete.
# Ambient beds (GS-11.3) live in res://game/audio/ambient/<name>.wav and loop; volume is separate from SFX.
extends Node

const Config := preload("res://game/core/config.gd")
const AUDIO_DIR := "res://game/audio"
const SOUND_NAMES := ["place", "wrong", "lift", "pick", "color_complete", "level_complete"]
const AMBIENT_NAMES := ["off", "sea", "rain"]
const AMBIENT_DB := -14.0

var sfx_enabled := true
var haptic_enabled := true

var _streams := {}               # name -> Array[AudioStream]
var _last_variant := {}          # name -> index
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _last_haptic_ms := -100000
var _rng := RandomNumberGenerator.new()
var _ambient: AudioStreamPlayer
var ambient_name := "off"

# Counters for tests (TC-11.9): how many times each feedback was requested.
var haptic_count := 0
var haptic_requests := 0
var sound_requests := {}


func _ready() -> void:
	_rng.randomize()
	for n in SOUND_NAMES:
		_streams[n] = _load_variants(n)
	for k in Config.SFX_VOICES_MAX:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_ambient = AudioStreamPlayer.new()
	_ambient.volume_db = AMBIENT_DB
	add_child(_ambient)


# GS-11.3: off / sea / rain. Separate from sfx_enabled.
func set_ambient(name: String) -> void:
	ambient_name = name if name in AMBIENT_NAMES else "off"
	if ambient_name == "off":
		_ambient.stop()
		return
	var path := AUDIO_DIR.path_join("ambient/%s.wav" % ambient_name)
	var s = load(path) if ResourceLoader.exists(path) else null
	if s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
	if s == null:
		return
	_ambient.stream = s
	_ambient.play()


# Lower the ambient bed briefly while the level-complete sound plays (GS-11.3).
func duck_ambient(seconds := 3.0) -> void:
	if not _ambient.playing:
		return
	var tw := create_tween()
	tw.tween_property(_ambient, "volume_db", AMBIENT_DB - 10.0, 0.2)
	tw.tween_interval(seconds)
	tw.tween_property(_ambient, "volume_db", AMBIENT_DB, 0.8)


func has_sound(name: String) -> bool:
	return not (_streams.get(name, []) as Array).is_empty()


func play(name: String, volume_db := 0.0) -> void:
	sound_requests[name] = int(sound_requests.get(name, 0)) + 1
	if not sfx_enabled:
		return
	var variants: Array = _streams.get(name, [])
	if variants.is_empty():
		return
	var idx := 0
	if variants.size() > 1:
		idx = _rng.randi_range(0, variants.size() - 2)
		if idx >= int(_last_variant.get(name, -1)):
			idx += 1                      # never repeat the previous variant (GS-11.1)
	_last_variant[name] = idx
	# GS-11.2: at most SFX_VOICES_MAX voices; a new sound replaces the oldest one.
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = variants[idx]
	p.volume_db = volume_db
	p.pitch_scale = _rng.randf_range(0.97, 1.03) if name == "place" else 1.0
	p.play()


# D-5 / GS-11.4: haptic only for a successful placement, rate-limited.
func haptic_place() -> void:
	haptic_requests += 1
	if not haptic_enabled:
		return
	var now := Time.get_ticks_msec()
	if now - _last_haptic_ms < Config.HAPTIC_MIN_INTERVAL_MS:
		return
	_last_haptic_ms = now
	haptic_count += 1
	Input.vibrate_handheld(10)


func _load_variants(name: String) -> Array:
	var out: Array = []
	var dir := AUDIO_DIR.path_join(name)
	if not DirAccess.dir_exists_absolute(dir):
		return out
	var files := DirAccess.get_files_at(dir)
	for f in files:
		var base := f.trim_suffix(".import").trim_suffix(".remap")
		if (base.ends_with(".wav") or base.ends_with(".ogg")) and not out.has(dir.path_join(base)):
			out.append(dir.path_join(base))
	var streams: Array = []
	for path in out:
		var s = load(path)
		if s is AudioStream:
			streams.append(s)
	return streams
