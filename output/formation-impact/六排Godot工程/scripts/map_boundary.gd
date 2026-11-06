extends Control
## A repeating, flat-tipped pixel border clips the atlas and every route/marker together.
## Its shape is deterministic and never consumes gameplay or sea randomness.
const Catalog=preload('res://scripts/data/catalog.gd')
var preset: Dictionary=Catalog.presentation('atlas').boundary
var outline_only=false
var polygon=PackedVector2Array()

func _init(draw_outline: bool=false):
	outline_only=draw_outline
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	clip_children=CanvasItem.CLIP_CHILDREN_DISABLED if outline_only else CanvasItem.CLIP_CHILDREN_ONLY

func _ready():
	resized.connect(rebuild)
	rebuild()

func append_point(point: Vector2):
	point=point.snapped(Vector2.ONE*preset.pixel_step)
	if polygon.is_empty() or polygon[-1]!=point: polygon.append(point)

func edge(start: Vector2,end: Vector2,inward: Vector2):
	var direction=start.direction_to(end)
	var length=start.distance_to(end)
	var grid=float(preset.pixel_step)
	var period=float(preset.period)
	var waves=int(length/period)
	var lead=snappedf((length-waves*period)*.5,grid)
	var depth=float(preset.side_depth if inward.x!=0 else preset.horizontal_depth)
	var shoulder=int(preset.shoulder_steps)
	var crest=float(preset.crest_steps)*grid
	var straight=(period-shoulder*grid*2-crest)*.5
	append_point(start)
	append_point(start+direction*lead)
	# Long straight runs, short stepped shoulders and a flat tip match the reference.
	for wave in waves:
		var origin=lead+wave*period
		append_point(start+direction*(origin+straight))
		var previous_depth=0.0
		for tick in range(1,shoulder+1):
			var distance=origin+straight+tick*grid
			var next_depth=snappedf(float(tick)/shoulder*depth,grid)
			append_point(start+direction*distance+inward*previous_depth)
			append_point(start+direction*distance+inward*next_depth)
			previous_depth=next_depth
		var tip_end=origin+straight+shoulder*grid+crest
		append_point(start+direction*tip_end+inward*depth)
		for tick in range(1,shoulder+1):
			var distance=tip_end+tick*grid
			var next_depth=snappedf((1.0-float(tick)/shoulder)*depth,grid)
			append_point(start+direction*distance+inward*previous_depth)
			append_point(start+direction*distance+inward*next_depth)
			previous_depth=next_depth
		append_point(start+direction*(origin+period))
	append_point(end)

func corner(from: Vector2,to: Vector2,vertical_first: bool=false):
	# Horizontal/vertical steps keep the bevel pixel-sharp, never a smooth curve.
	var steps=4
	var delta=(to-from)/steps
	for i in range(1,steps+1):
		append_point(from+(Vector2(delta.x*(i-1),delta.y*i) if vertical_first else Vector2(delta.x*i,delta.y*(i-1))))
		append_point(from+delta*i)

func rebuild():
	polygon.clear()
	var inset=float(preset.inset)
	var bevel=float(preset.corner_size)
	var left=inset;var right=size.x-inset
	var top=inset;var bottom=size.y-inset
	edge(Vector2(left+bevel,top),Vector2(right-bevel,top),Vector2.DOWN)
	corner(Vector2(right-bevel,top),Vector2(right,top+bevel))
	edge(Vector2(right,top+bevel),Vector2(right,bottom-bevel),Vector2.LEFT)
	corner(Vector2(right,bottom-bevel),Vector2(right-bevel,bottom),true)
	edge(Vector2(right-bevel,bottom),Vector2(left+bevel,bottom),Vector2.UP)
	corner(Vector2(left+bevel,bottom),Vector2(left,bottom-bevel))
	edge(Vector2(left,bottom-bevel),Vector2(left,top+bevel),Vector2.RIGHT)
	corner(Vector2(left,top+bevel),Vector2(left+bevel,top),true)
	if polygon[-1]==polygon[0]: polygon.remove_at(polygon.size()-1)
	queue_redraw()

func contains_point(point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(point,polygon)

func label_bounds() -> Rect2:
	var margin=Vector2(preset.side_depth,preset.horizontal_depth)+Vector2.ONE*(preset.inset+preset.pixel_step*2)
	return Rect2(margin,size-margin*2)

func _draw():
	if polygon.size()<3: return
	if not outline_only:
		draw_colored_polygon(polygon,Color.WHITE)
		return
	var closed=polygon.duplicate()
	closed.append(closed[0])
	draw_polyline(closed,preset.ink_color,preset.ink_width,false)
	draw_polyline(closed,preset.edge_color,preset.edge_width,false)
