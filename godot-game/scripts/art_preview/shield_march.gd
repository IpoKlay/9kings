extends Node2D

const SHEET = preload("res://assets/art_preview/shield_march.png")
const FIELD = preload("res://assets/environments/iberia-rts.png")
const LATIN = preload("res://assets/fonts/m5x7-eagle.ttf")
const HAN = preload("res://assets/fonts/fusion-pixel-12px-proportional-zh_hans.ttf")
const DIRECTIONS = ["南", "东南", "东", "东北", "北", "西北", "西", "西南"]
const BEARINGS = ["S", "SE", "E", "NE", "N", "NW", "W", "SW"]
const FILES = 10
const RANKS = 6
const BLOCKS := 3
# Typical visible silhouette in layout pixels; eight facings vary from 230 to 238 px.
const FORMATION_WIDTH := 234.0
const BLOCK_SPACING := 288.0
const LEG_TIME = 1.2
const PAPER = Color("#e5d9b8")
const GOLD = Color("#c8a966")
const MUTED = Color("#aca992")
const INK = Color("#1f2624")
var elapsed := 0.0
var paused := false
var close_view := false
var inspect_unit := false

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	assert(SHEET.get_size() == Vector2(512, 512))
	get_viewport().size_changed.connect(_fit)
	_fit()

func _fit() -> void:
	var size := get_viewport_rect().size
	scale = Vector2.ONE * minf(size.x / 960.0, size.y / 540.0)
	position = ((size - Vector2(960, 540) * scale) * 0.5).round()

func _process(delta: float) -> void:
	if not paused:
		elapsed = fposmod(elapsed + delta, LEG_TIME * 8)
	queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE: paused = not paused
			KEY_TAB: close_view = not close_view
			KEY_I: inspect_unit = not inspect_unit
			KEY_RIGHT: elapsed = fposmod((floor(elapsed / LEG_TIME) + 1) * LEG_TIME + 0.001, LEG_TIME * 8)
			KEY_LEFT: elapsed = fposmod((floor(elapsed / LEG_TIME) - 1) * LEG_TIME + 0.001, LEG_TIME * 8)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP: close_view = true
			MOUSE_BUTTON_WHEEL_DOWN: close_view = false

func label_at(p: Vector2, value: String, size: int, color: Color, font: Font = LATIN) -> void:
	draw_string(font, p, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func soldier(feet: Vector2, bearing: int, frame: int, zoom: float) -> void:
	var location := (feet - Vector2(32, 54) * zoom).round()
	draw_texture_rect_region(SHEET, Rect2(location, Vector2(64, 64) * zoom), Rect2(frame * 64, bearing * 64, 64, 64))

func course(leg: int) -> Vector2:
	var angle := leg * TAU / 8.0 - PI / 8.0
	return Vector2(cos(angle) * 74.0, sin(angle) * 50.0)

func _draw() -> void:
	var leg := floori(elapsed / LEG_TIME) % 8
	var bearing := posmod(-leg, 8)
	var beat := floori(elapsed * 10)
	var field := Rect2(18, 53, 640 if inspect_unit else 924, 425)
	var width_share := 0.25 if close_view else 0.15
	var troop_zoom := field.size.x * width_share / FORMATION_WIDTH
	var view_scale := troop_zoom * 0.5
	var travel := course(leg).lerp(course(leg + 1), fmod(elapsed, LEG_TIME) / LEG_TIME)
	var center := field.get_center() + (Vector2(0, 39) + travel) * view_scale
	var ground_size := field.size * 2.05 / troop_zoom
	ground_size *= minf(1.0, FIELD.get_height() / ground_size.y)
	var ground := Rect2((FIELD.get_size() - ground_size) * 0.5, ground_size)
	draw_rect(Rect2(0, 0, 960, 540), INK)
	label_at(Vector2(22, 32), "鹰旗之下", 24, PAPER, HAN)
	label_at(Vector2(145, 32), "/   CAMPUS MARTIUS", 32, GOLD)
	label_at(Vector2(728, 30), "军团演练场   /   01", 16, MUTED, HAN)
	draw_texture_rect_region(FIELD, field, ground)
	draw_rect(field, Color("#baa777"), false, 1)
	for block in BLOCKS:
		var block_center := center + Vector2((block - 1) * BLOCK_SPACING * troop_zoom, 0)
		draw_formation(block_center, bearing, beat, troop_zoom, block)
	draw_rect(Rect2(19, 54, 290, 25), INK)
	label_at(Vector2(28, 71), "%s  /  三个方阵  /  每阵 %d 人" % ["近景" if close_view else "全景", FILES * RANKS], 12, PAPER, HAN)

	if inspect_unit:
		draw_inspection(bearing, beat)
	draw_line(Vector2(18, 492), Vector2(942, 492), Color("#596050"))
	label_at(Vector2(21, 519), "空格  " + ("继续" if paused else "暂停") + "     ← →  切换方向     Tab  " + ("战场全景" if close_view else "查看近景") + "     I  单兵", 16, PAPER, HAN)
	label_at(Vector2(734, 520), "64 x 64  /  8 DIR", 20, GOLD)

func draw_inspection(bearing: int, beat: int) -> void:
	draw_rect(Rect2(674, 53, 268, 425), Color("#303630"))
	label_at(Vector2(694, 80), "I  /  SCUTATUS", 24, GOLD)
	label_at(Vector2(693, 113), "罗马盾兵", 24, PAPER, HAN)
	label_at(Vector2(694, 139), "行军", 16, MUTED, HAN)
	label_at(Vector2(835, 139), DIRECTIONS[bearing] + "  " + BEARINGS[bearing], 16, PAPER, HAN)
	draw_line(Vector2(694, 151), Vector2(922, 151), Color("#596050"))
	draw_ellipse(Vector2(808, 307), 25, 4, Color("#20251e"))
	soldier(Vector2(808, 306), bearing, beat % 8, 3)
	draw_line(Vector2(694, 328), Vector2(922, 328), Color("#596050"))
	label_at(Vector2(694, 343), "八向步态", 16, MUTED, HAN)
	for index in 8:
		var x := 694 + (index % 4) * 57
		var y := 355 + floori(index / 4.0) * 56
		if index == bearing:
			draw_rect(Rect2(x, y, 51, 54), Color("#474a39"))
			draw_rect(Rect2(x, y + 52, 51, 2), GOLD)
		soldier(Vector2(x + 25, y + 41), index, beat % 8, 1)
		label_at(Vector2(x + 16, y + 52), BEARINGS[index], 14, PAPER)

func draw_formation(center: Vector2, bearing: int, beat: int, troop_zoom: float, block: int) -> void:
	var view_scale := troop_zoom * 0.5
	for row in RANKS:
		for col in FILES:
			var file := col - (FILES - 1) * 0.5
			var rank := row - (RANKS - 1) * 0.5
			var feet := center + Vector2(file * 42 + rank * 8, rank * 36 + file * 1.4) * view_scale
			draw_ellipse(feet.round() + Vector2(0, -1), 14 * view_scale, 4 * view_scale, Color("#20251766"))
			var phase: int = [0, 1, 0, 7, 1, 2, 0][(row * 3 + col + block) % 7]
			soldier(feet, bearing, (beat + phase) % 8, troop_zoom)
