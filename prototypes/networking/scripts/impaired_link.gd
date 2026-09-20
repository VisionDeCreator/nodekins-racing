class_name PrototypeImpairedLink
extends RefCounted
## Applies delay/loss only to outgoing movement/ping datagrams, never reliable setup.
var latency_ms: float = 0.0
var jitter_ms: float = 0.0
var loss: float = 0.0
var sent: int = 0
var dropped: int = 0
var queue: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()

func configure(delay: float, loss_fraction: float, jitter: float) -> void:
	latency_ms = clampf(delay,0,1000)
	loss = clampf(loss_fraction,0,.5)
	jitter_ms = clampf(jitter,0,100)

func enqueue(kind: StringName, peer: int, args: Array) -> void:
	sent += 1
	if rng.randf() < loss:
		dropped += 1
		return
	var due: float = Time.get_ticks_msec()+maxf(0,latency_ms+rng.randf_range(-jitter_ms,jitter_ms))
	if queue.size() < 256:
		queue.append({"due":due,"kind":kind,"peer":peer,"args":args})

func take_ready() -> Array[Dictionary]:
	var ready: Array[Dictionary] = []
	var now: int = Time.get_ticks_msec()
	for index in range(queue.size()-1,-1,-1):
		if queue[index].due <= now:
			ready.append(queue[index])
			queue.remove_at(index)
	ready.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.due < b.due)
	return ready
