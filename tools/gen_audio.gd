## 构建期音频资产生成器（ADR-0012）：把参考实现的定频短爆点包络写成 WAV 资产入库。
##
## 用法（一次性，产物提交进仓库）：
##   godot --headless --path . -s tools/gen_audio.gd
##
## 生成六种音：枪声 155Hz、击中 200Hz、击杀 240ms 上行两音（660→990Hz），
## 刷新 240ms 下行两音（990→660Hz，与击杀音镜像对偶，ADR-0019），
## 以及计时会话的两个提示音——准备段逐秒预哔 660Hz、开始哔 990Hz（票 03）。
## 包络与参考实现逐字一致：约 30ms 时长、4ms 缓起音、陡衰减、无噪声瞬态。

extends SceneTree

const OUT_DIR := "res://assets/audio"
const MIX_RATE := 44100
const ATTACK := 0.004 ## 4ms 缓起音

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_write("shot.wav", _make_shot())
	_write("hit.wav", _make_hit())
	_write("kill.wav", _make_kill())
	_write("respawn.wav", _make_respawn())
	_write("pre_beep.wav", _make_pre_beep())
	_write("start_beep.wav", _make_start_beep())
	quit()

## 枪声 / 击中音：单频爆点，30ms、(1−p)^4 陡衰减、幅值 0.48。
func _burst(freq: float, duration := 0.03, amp := 0.48) -> PackedFloat32Array:
	var n := int(MIX_RATE * duration)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var t := float(i) / MIX_RATE
		var p := t / duration
		var attack := minf(1.0, t / ATTACK)
		out[i] = sin(TAU * freq * t) * pow(1.0 - p, 4.0) * attack * amp
	return out

func _make_shot() -> PackedFloat32Array:
	return _burst(155.0)

func _make_hit() -> PackedFloat32Array:
	return _burst(200.0)

## 击杀音：240ms、两段各 100ms 的上行纯五度（660Hz → 990Hz），基频 + 0.35 × 2 倍泛音、(1−p)^2 衰减，总幅 0.28。
func _make_kill() -> PackedFloat32Array:
	return _two_tone([[0.0, 660.0], [0.11, 990.0]])

## 刷新音（ADR-0019）：下行两音（990Hz → 660Hz），与击杀音镜像对偶——上行 = 杀死（奖励感），下行 = 出现（落定感）。
func _make_respawn() -> PackedFloat32Array:
	return _two_tone([[0.0, 990.0], [0.11, 660.0]])

## 两音框架（击杀 / 刷新共用）：240ms、两段各 100ms 的纯五度序列，
## 基频 + 0.35 × 2 倍泛音、(1−p)^2 衰减、总幅 0.28。
func _two_tone(tones: Array) -> PackedFloat32Array:
	var duration := 0.24
	var n := int(MIX_RATE * duration)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var t := float(i) / MIX_RATE
		var v := 0.0
		for tone in tones:
			var dt: float = t - float(tone[0])
			if dt < 0.0 or dt > 0.1:
				continue
			var p := dt / 0.1
			var f: float = tone[1]
			var attack := minf(1.0, dt / ATTACK)
			v += (sin(TAU * f * dt) + 0.35 * sin(TAU * 2.0 * f * dt)) * pow(1.0 - p, 2.0) * attack
		out[i] = v * 0.28
	return out

## 预哔：准备段逐秒提示音（660Hz），包络与枪声同款。
func _make_pre_beep() -> PackedFloat32Array:
	return _burst(660.0)

## 开始哔：游玩段起点的提示音（990Hz），包络与枪声同款。
func _make_start_beep() -> PackedFloat32Array:
	return _burst(990.0)

func _write(file_name: String, samples: PackedFloat32Array) -> void:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in range(samples.size()):
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = bytes
	var path := "%s/%s" % [OUT_DIR, file_name]
	var err := stream.save_to_wav(path)
	if err != OK:
		push_error("保存 %s 失败：%s" % [path, error_string(err)])
	else:
		print("已生成 %s（%d 采样）" % [path, samples.size()])