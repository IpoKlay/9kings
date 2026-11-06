@tool
extends Marker2D

@export var objective := false:
	set(value):
		objective=value
		queue_redraw()
var clock := 0.0

func _draw():
	if not objective:
		draw_pennant()
		return
	var foot:=Vector2.ZERO
	var top=foot-Vector2(0,147)
	draw_line(foot,top,Color('#493323'),8)
	draw_line(foot,top,Color('#c39a56'),4)
	draw_rect(Rect2(top+Vector2(-17,10),Vector2(36,44)),Color('#562d27'))
	draw_rect(Rect2(top+Vector2(-14,13),Vector2(30,37)),Color('#a44635'))
	draw_rect(Rect2(top+Vector2(-20,9),Vector2(41,4)),Color('#f3cb78'))
	draw_colored_polygon(PackedVector2Array([top+Vector2(-9,20),top+Vector2(0,24),top+Vector2(9,20),
		top+Vector2(6,28),top+Vector2(2,30),top+Vector2(0,35),top+Vector2(-3,30),top+Vector2(-7,27)]),Color('#f1ce7e'))
	draw_rect(Rect2(top+Vector2(-11,41),Vector2(24,3)),Color('#ddb261'))
	# The eagle finial has stepped wings and a raised head.
	var wing=PackedVector2Array([top+Vector2(-16,-5),top+Vector2(-8,-3),top+Vector2(-3,1),
		top+Vector2(-2,-7),top+Vector2(5,-7),top+Vector2(8,-4),top+Vector2(3,-3),
		top+Vector2(4,0),top+Vector2(16,-6),top+Vector2(12,2),top+Vector2(3,6),
		top+Vector2(3,9),top+Vector2(-2,9),top+Vector2(-3,6),top+Vector2(-12,2)])
	draw_colored_polygon(wing,Color('#f1ce7e'))

func draw_pennant():
	var root:=Vector2.ZERO
	var phase:=get_index()
	draw_rect(Rect2(root-Vector2(2,80),Vector2(4,80)),Color('#ae9060'))
	draw_rect(Rect2(root-Vector2(5,84),Vector2(10,6)),Color('#e9c878'))
	draw_rect(Rect2(root-Vector2(9,3),Vector2(21,4)),Color('#203c3b80'))
	for column in 12:
		var dy=roundf(sin(clock*2.2-column*.43+phase)*float(column)/8)*2
		var pos=root+Vector2(column*2,-76+dy)
		draw_rect(Rect2(pos,Vector2(2,29)),Color('#ac503b') if column%3 else Color('#bc6545'))
		draw_rect(Rect2(pos+Vector2(0,27),Vector2(2,2)),Color('#ddbd79'))
		if column in [4,5,6,7]: draw_rect(Rect2(pos+Vector2(0,8),Vector2(2,9)),Color('#e6cd87'))
