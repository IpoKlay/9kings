extends Control

var item = ''

func _draw():
	# Simple pixel illustrations keep each offer recognizable until final art exists.
	var center = size / 2.0
	draw_set_transform(center - Vector2(32, 24), 0.0, Vector2(2, 2))
	match item:
		'food':
			draw_rect(Rect2(3, 11, 25, 13), Color('#9c693f'))
			draw_rect(Rect2(6, 7, 19, 13), Color('#e1b976'))
			for x in [10, 16, 22]: draw_rect(Rect2(x, 8, 2, 7), Color('#a87b4c'))
		'ox':
			draw_rect(Rect2(4, 8, 19, 12), Color('#eee5cc'))
			draw_rect(Rect2(21, 10, 7, 8), Color('#eee5cc'))
			for x in [6, 18]: draw_rect(Rect2(x, 18, 3, 7), Color('#b6a994'))
			draw_rect(Rect2(24, 7, 2, 4), Color('#b6a994'))
		'gem':
			draw_colored_polygon(PackedVector2Array([Vector2(16, 3), Vector2(26, 10), Vector2(16, 25), Vector2(6, 10)]), Color('#a987c8'))
			draw_line(Vector2(16, 4), Vector2(11, 11), Color('#e0cbea'), 1)
			draw_line(Vector2(11, 11), Vector2(16, 24), Color('#e0cbea'), 1)
		'weapon':
			draw_line(Vector2(8, 22), Vector2(23, 5), Color('#e6dfc9'), 3)
			draw_line(Vector2(7, 17), Vector2(13, 23), Color('#c3954c'), 2)
			draw_line(Vector2(5, 25), Vector2(9, 21), Color('#a36c3e'), 3)
