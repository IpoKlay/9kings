@tool
extends Node2D
## Position and footprint are authored in the same projected ground plane as pass rocks.
@export var footprint=Rect2(-150,-12,300,24):
	set(value):footprint=value;queue_redraw()
@export var hits_to_breach=5
var hits=0:
	set(value):hits=value;queue_redraw()
func _draw():
	var left=footprint.position.x;var width=footprint.size.x
	if hits>=hits_to_breach:
		for i in 18:
			var x=left+float((i*47)%int(width))
			draw_rect(Rect2(x,-8+(i*7)%18,12+(i%3)*4,6),Color('#81725b'))
		return
	draw_rect(Rect2(left,footprint.end.y-7,width,14),Color('#403e35'))
	for row in 7:
		for col in ceili(width/24.)+1:
			var x=left+col*24.-(12. if row%2 else 0.)
			var a=maxf(left,x);var b=minf(left+width,x+22.)
			if b<=a:continue
			if hits>0 and (row*7+col*3)%17<hits*2 and row<4:continue
			var color=Color('#a99c7c') if (col+row)%3 else Color('#8d8168')
			draw_rect(Rect2(a,-60+row*10,b-a,8),color)
	for col in ceili(width/28.):
		if col%5<hits:continue
		draw_rect(Rect2(left+col*28,-70,16,14),Color('#b9ad8c'))
	if Engine.is_editor_hint():draw_rect(footprint,Color('#f4d587'),false,1.)
