@tool
extends ReferenceRect

const ROCK_ART=preload('res://assets/environments/iberia-rts.png')

func _draw():
	# Outline sampled from the original Iberian rock bank. Rotate its long axis into the pass.
	var bank=PackedVector2Array([Vector2(8,50),Vector2(29,26),Vector2(61,17),Vector2(88,25),
		Vector2(107,52),Vector2(147,55),Vector2(179,36),Vector2(205,18),Vector2(232,14),
		Vector2(271,31),Vector2(294,37),Vector2(280,59),Vector2(248,70),Vector2(225,90),
		Vector2(185,99),Vector2(156,103),Vector2(128,101),Vector2(94,89),Vector2(60,85),
		Vector2(29,72),Vector2(15,69)])
	var rock_art=ROCK_ART
	var uv=PackedVector2Array()
	for vertex in bank:uv.append((Vector2(1950,245)+vertex)/rock_art.get_size())
	for flank in 2:
		var poly=PackedVector2Array()
		for vertex in bank:
			var along=(vertex.x-8)/286.0
			var across=(vertex.y-14)/89.0
			if flank==1:along=1.0-along
			poly.append((Vector2((flank*.30+across*.70)*size.x,along*size.y)).round())
		draw_polygon(poly,PackedColorArray([Color.WHITE]),uv,rock_art)
