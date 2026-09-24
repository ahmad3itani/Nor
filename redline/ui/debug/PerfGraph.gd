class_name PerfGraph
extends CanvasLayer
## Performance overlay (bible §34): the last 240 real frame times as a bar
## graph with 16.7 ms (60 FPS) and 33.3 ms guide lines, plus avg/max.

const SAMPLES := 240
const SIZE := Vector2(240, 48)

var _times: PackedFloat32Array = []
var _last_usec: int = 0
var _canvas: Control


func _ready() -> void:
	layer = 101
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.position = Vector2(236, 4)
	_canvas.custom_minimum_size = SIZE
	_canvas.draw.connect(_draw_graph)
	add_child(_canvas)
	_last_usec = Time.get_ticks_usec()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	_times.append((now - _last_usec) / 1000.0)
	_last_usec = now
	if _times.size() > SAMPLES:
		_times = _times.slice(_times.size() - SAMPLES)
	_canvas.queue_redraw()


func _draw_graph() -> void:
	_canvas.draw_rect(Rect2(Vector2.ZERO, SIZE), Color(0.03, 0.02, 0.05, 0.75))
	var scale := SIZE.y / 50.0  # 50 ms full height
	for ms: float in [16.7, 33.3]:
		var y := SIZE.y - ms * scale
		_canvas.draw_line(Vector2(0, y), Vector2(SIZE.x, y), Color(1, 1, 1, 0.25))
	var total := 0.0
	var worst := 0.0
	for i in _times.size():
		var ms := _times[i]
		total += ms
		worst = maxf(worst, ms)
		var c := Color("7dff9a") if ms <= 17.5 else (Color("ffcf5a") if ms <= 34.0 else Color("ff3b4f"))
		var h := minf(ms * scale, SIZE.y)
		_canvas.draw_line(Vector2(i, SIZE.y), Vector2(i, SIZE.y - h), c)
	if not _times.is_empty():
		_canvas.draw_string(ThemeDB.fallback_font, Vector2(2, 9), "avg %.1f ms  max %.1f ms" % [total / _times.size(), worst], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
