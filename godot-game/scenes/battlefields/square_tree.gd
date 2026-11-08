@tool
extends Marker2D
## The marker is the foot point; canopy size and wind phase are editable.
const OAK=preload('res://assets/environments/oak.png')
const Scenery=preload('res://scripts/battle_environment.gd')
@export_range(16,512,1) var canopy_size: float=180:
	set(value):
		canopy_size=value
		queue_redraw()
@export var wind_index: int=0:
	set(value):
		wind_index=value
		queue_redraw()
var environment=Scenery.new() if not Engine.is_editor_hint() else null

func animate_scenery(scenery):
	environment=scenery
	queue_redraw()

func _draw():
	var size=Vector2.ONE*canopy_size
	for strip in 16:
		var f=strip/16.0
		var sway=0.0 if environment==null else environment.tree_sway(1,posmod(wind_index,environment.wind_profiles[0].size()),f,environment.clock)
		var src=Rect2(0,OAK.get_height()*f,OAK.get_width(),OAK.get_height()/16.0)
		var dst=Rect2(-Vector2(size.x*.5,size.y)+Vector2(sway,size.y*f),Vector2(size.x,size.y/16.0+.5))
		draw_texture_rect_region(OAK,dst,src)
