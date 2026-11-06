extends Control
## Folded-map pixel glyph; follows the existing native HUD style.
func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw():
	draw_polygon(PackedVector2Array([Vector2(2,8),Vector2(14,4),Vector2(26,8),Vector2(38,4),Vector2(38,32),Vector2(26,36),Vector2(14,32),Vector2(2,36)]),PackedColorArray([Color('#e1ce94')]))
	draw_polygon(PackedVector2Array([Vector2(14,4),Vector2(26,8),Vector2(26,36),Vector2(14,32)]),PackedColorArray([Color('#a7986e')]))
	for p in [Vector2(7,25),Vector2(11,22),Vector2(15,19),Vector2(19,19),Vector2(23,16),Vector2(27,13)]:
		draw_rect(Rect2(p,Vector2(3,3)),Color('#53654c'))
	draw_rect(Rect2(28,10,6,6),Color('#8e4032'))
