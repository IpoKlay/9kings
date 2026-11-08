@tool
extends Marker2D
@export var enemy: bool=false:
	set(value):
		enemy=value
		queue_redraw()
@export var phase: int=0:
	set(value):
		phase=value
		queue_redraw()
var clock=0.0

func animate_scenery(scenery):
	clock=scenery.clock
	queue_redraw()

func _draw():
	var root=Vector2.ZERO
	draw_rect(Rect2(root-Vector2(2,80),Vector2(4,80)),Color('#ae9060'))
	draw_rect(Rect2(root-Vector2(5,84),Vector2(10,6)),Color('#e9c878'))
	draw_rect(Rect2(root-Vector2(9,3),Vector2(21,4)),Color('#203c3b80'))
	for column in 12:
		var dy=roundf(sin(clock*2.2-column*.43+phase)*float(column)/8)*2
		var pos=root+Vector2(column*2,-76+dy)
		var cloth=Color('#ac503b') if column%3 else Color('#bc6545')
		if enemy:cloth=Color('#577e96') if column%3 else Color('#7296aa')
		draw_rect(Rect2(pos,Vector2(2,29)),cloth)
		draw_rect(Rect2(pos+Vector2(0,27),Vector2(2,2)),Color('#ddbd79'))
		if column in [4,5,6,7]: draw_rect(Rect2(pos+Vector2(0,8),Vector2(2,9)),Color('#e6cd87'))
