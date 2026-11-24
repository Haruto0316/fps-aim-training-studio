extends RefCounted

var started_at := -1
var paused_at := -1
var paused_usec := 0


func start(now: int) -> void:
	started_at = now
	paused_at = -1
	paused_usec = 0


func pause(now: int) -> void:
	if started_at >= 0 and paused_at < 0:
		paused_at = now


func resume(now: int) -> void:
	if paused_at >= 0:
		paused_usec += now - paused_at
		paused_at = -1


func elapsed(now: int) -> int:
	if started_at < 0:
		return 0
	var until := paused_at if paused_at >= 0 else now
	return maxi(0, until - started_at - paused_usec)
