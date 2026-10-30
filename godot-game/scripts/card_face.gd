extends Control
## Static 2-pixel card frame. Godot retains these draw commands between frames.
const Catalog=preload('res://scripts/data/catalog.gd')
const ART_RECT=Rect2(18,40,204,136)
const ICON_RECT=Rect2(56,44,128,128)
const TEXT_RECTS={
	'CardKind':Rect2(18,8,204,28),
	'CardTitle':Rect2(16,178,208,36),
	'CardImpact':Rect2(16,214,208,38),
	'CardDescription':Rect2(16,254,208,66)
}
var kind='Building'
var armed=false

func set_armed(value: bool):
	if armed==value: return
	armed=value
	queue_redraw()

func _init():
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST

func stepped_panel(rect: Rect2,color: Color):
	# Whole grid cells, including the clipped corners; no smooth bevel or gradient.
	draw_rect(Rect2(rect.position+Vector2(6,0),rect.size-Vector2(12,0)),color)
	draw_rect(Rect2(rect.position+Vector2(2,2),rect.size-Vector2(4,4)),color)
	draw_rect(Rect2(rect.position+Vector2(0,6),rect.size-Vector2(0,12)),color)

func _draw():
	var preset=Catalog.presentation('card_hand')
	var colors=preset.face_palette
	var bounds=Rect2(Vector2.ZERO,preset.card_size)
	stepped_panel(bounds,colors.ink)
	stepped_panel(bounds.grow(-2),colors.edge)
	stepped_panel(bounds.grow(-4),colors.body)
	stepped_panel(bounds.grow(-8),colors.highlight if armed else colors.brass)
	stepped_panel(bounds.grow(-10),colors.body)
	draw_rect(ART_RECT,colors.edge)
	draw_rect(ART_RECT.grow(-2),colors.ink)
	draw_rect(ART_RECT.grow(-4),preset.face_wells[kind])
	# The original Roman illustration stays separate from this decorative frame.
	draw_rect(Rect2(16,178,208,36),colors.name_band)
	draw_rect(Rect2(22,214,196,2),colors.edge)
	draw_rect(Rect2(34,252,172,2),colors.edge)
	for x in [14,222]:
		for y in [36,176,320]:
			draw_rect(Rect2(x,y,4,4),colors.brass)
	for x in [22,210]:
		draw_rect(Rect2(x,6,8,2),colors.highlight)
		draw_rect(Rect2(x,326,8,2),colors.edge)
	draw_rect(Rect2(92,324,20,2),colors.edge)
	draw_rect(Rect2(128,324,20,2),colors.edge)
	draw_rect(Rect2(118,322,4,6),colors.brass)
	draw_rect(Rect2(116,324,8,2),colors.brass)
