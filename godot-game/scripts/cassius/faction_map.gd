extends AspectRatioContainer

const ATLAS = preload('res://assets/expedition/atlas.png')
const MASK = preload('res://assets/expedition/shore_distance.png')
const TINT = preload('res://shaders/cassius_factions.gdshader')
const SITES = {
	'west': Vector2(.173, .36),
	'north': Vector2(.52, .12),
	'south': Vector2(.375, .70),
	'east': Vector2(.83, .45),
}
const INK = Color('#1a222c')
const READY = Color('#ffe3a1')
var journey
var overlay: Control

func _ready():
	ratio = float(ATLAS.get_width()) / ATLAS.get_height()
	stretch_mode = AspectRatioContainer.STRETCH_FIT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var texture = TextureRect.new()
	texture.texture = ATLAS
	texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tint = ShaderMaterial.new()
	tint.shader = TINT
	tint.set_shader_parameter('water_mask', MASK)
	for land in journey.spec.regions:
		tint.set_shader_parameter(land.id, Color(land.color))
	texture.material = tint
	add_child(texture)

	overlay = Control.new()
	overlay.name = 'FactionRoutes'
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	overlay.resized.connect(overlay.queue_redraw)
	add_child(overlay)

func _draw_overlay():
	var visits: Array = journey.state.visits
	for i in range(1, visits.size()):
		_draw_route(visits[i - 1], visits[i], Color('#e0c899'), false)
	var current: String = journey.state.region
	var available = journey.routes() if journey.state.choices.has(current) else []
	for land in available:
		_draw_route(current, land.id, READY, true)
	for land in journey.spec.regions:
		_draw_site(land, current, land in available, land.id in visits)

func _draw_route(from_id: String, to_id: String, color: Color, dashed: bool):
	var start: Vector2 = SITES[from_id] * overlay.size
	var finish: Vector2 = SITES[to_id] * overlay.size
	var line = finish - start
	var bend = line.orthogonal().normalized() * minf(line.length() * .105, 42.0)
	var control = (start + finish) * .5 + bend
	var steps = maxi(6, roundi(line.length() / 11.0))
	var points = PackedVector2Array()
	for i in range(steps + 1):
		var t = float(i) / steps
		points.append(start.lerp(control, t).lerp(control.lerp(finish, t), t).snapped(Vector2(2, 2)))
	for i in range(steps):
		if dashed and i % 2 != 0: continue
		overlay.draw_line(points[i], points[i + 1], INK, 7)
	for i in range(steps):
		if dashed and i % 2 != 0: continue
		overlay.draw_line(points[i], points[i + 1], color, 3)

func _draw_site(land: Dictionary, current: String, available: bool, visited: bool):
	var at: Vector2 = (SITES[land.id] * overlay.size).round()
	var active: bool = land.id == current
	var color = Color(land.color).lightened(.32)
	var marker = PackedVector2Array([at + Vector2(0,-13), at + Vector2(13,0),
		at + Vector2(0,13), at + Vector2(-13,0)])
	overlay.draw_colored_polygon(marker, INK)
	var inner = PackedVector2Array([at + Vector2(0,-8), at + Vector2(8,0),
		at + Vector2(0,8), at + Vector2(-8,0)])
	overlay.draw_colored_polygon(inner, READY if active or available else color)
	if active: overlay.draw_rect(Rect2(at - Vector2(3,3), Vector2(6,6)), INK)

	var font = get_theme_default_font()
	var title: String = land.name
	var detail: String = land.place + (' · 当前' if active else ' · 可前往' if available else ' · 已到访' if visited else '')
	var title_size = 25
	var detail_size = 18
	var width = maxf(font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x,
		font.get_string_size(detail, HORIZONTAL_ALIGNMENT_LEFT, -1, detail_size).x) + 20
	var pos = Vector2(clampf(at.x - width * .5, 4.0, maxf(4.0, overlay.size.x - width - 4.0)), at.y + 16).round()
	overlay.draw_rect(Rect2(pos, Vector2(width,56)), Color('#161d25e8'))
	overlay.draw_rect(Rect2(pos, Vector2(width,2)), color)
	overlay.draw_string(font, pos + Vector2(10,25), title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, color)
	overlay.draw_string(font, pos + Vector2(10,47), detail, HORIZONTAL_ALIGNMENT_LEFT, -1, detail_size, Color('#faf0db'))
