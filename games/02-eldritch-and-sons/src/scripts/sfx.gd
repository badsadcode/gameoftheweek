## sfx.gd : every sound is synthesized at startup (no audio files), like Frostline.
## Sfx.play("bell") from anywhere; Sfx.loop("hum") returns the player for volume control.
extends Node

const RATE := 22050
var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var volume := 0.8

func _ready() -> void:
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_build()

func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = samples.size()
	return w

func _render(dur: float, fn: Callable) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = fn.call(float(i) / RATE, float(i) / n)
	return out

func _build() -> void:
	var rng := RandomNumberGenerator.new()
	var lp := [0.0]
	# shop door bell: two bright partials, long ring
	_streams["bell"] = _wav(_render(1.2, func(t, u): return (sin(TAU * 1568 * t) * 0.5 + sin(TAU * 2350 * t) * 0.3 + sin(TAU * 3136 * t) * 0.15) * exp(-t * 4.0) * 0.5))
	# cash register: mechanical clunk + ding
	_streams["till"] = _wav(_render(0.7, func(t, u):
		var clunk := rng.randf_range(-1, 1) * exp(-t * 40.0) * 0.6
		var ding := sin(TAU * 2093 * t) * exp(-maxf(0.0, t - 0.12) * 6.0) * (0.0 if t < 0.12 else 0.45)
		return clunk + ding))
	# footstep on wood
	_streams["step"] = _wav(_render(0.12, func(t, u):
		lp[0] += 0.25 * (rng.randf_range(-1, 1) - lp[0])
		return (lp[0] * 2.5 + sin(TAU * 110 * t) * 0.4) * exp(-t * 35.0)))
	# cardboard box thump
	_streams["box"] = _wav(_render(0.3, func(t, u):
		lp[0] += 0.12 * (rng.randf_range(-1, 1) - lp[0])
		return (lp[0] * 3.0 + sin(TAU * (90.0 - 60.0 * t) * t) * 0.6) * exp(-t * 14.0)))
	# placing items on a shelf
	_streams["stock"] = _wav(_render(0.18, func(t, u): return (rng.randf_range(-1, 1) * 0.3 + sin(TAU * 700 * t) * 0.3) * exp(-t * 30.0)))
	# UI click / page flip
	_streams["click"] = _wav(_render(0.06, func(t, u): return sin(TAU * 1200 * t) * exp(-t * 70.0) * 0.4))
	_streams["page"] = _wav(_render(0.3, func(t, u):
		lp[0] += 0.4 * (rng.randf_range(-1, 1) - lp[0])
		return lp[0] * sin(PI * u) * 0.6))
	# knock knock knock
	_streams["knock"] = _wav(_render(1.3, func(t, u):
		var k := fmod(t, 0.38)
		if t > 1.14: return 0.0
		return (sin(TAU * 140 * k) * 0.8 + rng.randf_range(-1, 1) * 0.3) * exp(-k * 28.0)))
	# whispers: band-limited noise with a breathy wobble
	_streams["whisper"] = _wav(_render(2.5, func(t, u):
		lp[0] += 0.3 * (rng.randf_range(-1, 1) - lp[0])
		var env := sin(PI * u) * (0.5 + 0.5 * sin(t * 9.0 + sin(t * 3.0) * 2.0))
		return (rng.randf_range(-1, 1) - lp[0]) * env * 0.35))
	# low unsettling drone for weird moments
	_streams["drone"] = _wav(_render(3.0, func(t, u):
		var env := minf(1.0, t * 2.0) * minf(1.0, (3.0 - t) * 1.5)
		return (sin(TAU * 55 * t) * 0.5 + sin(TAU * 58.3 * t) * 0.4 + sin(TAU * 110.5 * t) * 0.15) * env * 0.5))
	# a wrong, detuned chime (rule broken)
	_streams["wrong"] = _wav(_render(1.6, func(t, u): return (sin(TAU * 440 * t) + sin(TAU * 466 * t) + sin(TAU * 311 * t) * 0.6) * exp(-t * 2.5) * 0.25))
	# good chime (reward / rule kept)
	_streams["good"] = _wav(_render(0.8, func(t, u):
		var f := 784.0 if t < 0.15 else 1175.0
		return sin(TAU * f * t) * exp(-fmod(t, 0.15) * 6.0) * 0.35))
	# coin
	_streams["coin"] = _wav(_render(0.35, func(t, u): return (sin(TAU * 1975 * t) + sin(TAU * 2637 * t) * 0.6) * exp(-t * 12.0) * 0.3))
	# ambient shop hum (looping)
	_streams["hum"] = _wav(_render(4.0, func(t, u):
		lp[0] += 0.02 * (rng.randf_range(-1, 1) - lp[0])
		return sin(TAU * 60 * t) * 0.05 + lp[0] * 0.8), true)
	# night wind (looping)
	_streams["wind"] = _wav(_render(4.0, func(t, u):
		lp[0] += 0.015 * (rng.randf_range(-1, 1) - lp[0])
		var edge := minf(1.0, minf(u * 20.0, (1.0 - u) * 20.0))
		return lp[0] * 4.0 * (0.7 + 0.3 * sin(TAU * t * 0.5)) * edge), true)

func play(name: String, vol := 1.0, pitch := 1.0) -> void:
	if not _streams.has(name): return
	for p in _pool:
		if not p.playing:
			p.stream = _streams[name]
			p.volume_db = linear_to_db(maxf(0.001, vol * volume))
			p.pitch_scale = pitch
			p.play()
			return

func loop(name: String, vol := 1.0) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	add_child(p)
	p.stream = _streams[name]
	p.volume_db = linear_to_db(maxf(0.001, vol * volume))
	p.play()
	return p
