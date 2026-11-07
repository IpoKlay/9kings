extends RefCounted
const VIEW=preload('res://data/presentation/rts_view.tres').values

# Projected ground pixels, the same plane in which the ranks are drawn.
var ROCKS: Array
var SIDE_GATE: Rect2
var main_pass: Rect2
var basis: Transform2D
var inverse: Transform2D
var bounds: Rect2
var clearances={}
var extents={}
var turning_rows=false

# Single rank. Spread the old staggered frontage across the remaining files.
static func layout(kind: String,high_view: bool=false) -> Vector3:
	var result: Vector3
	match kind:
		'cavalry':result=Vector3(246.0/7,0,1.83)
		'siege':result=Vector3(90.5,0,2.0)
		'medic':result=Vector3(27,0,1.23)
		'spear':result=Vector3(259.0/9,0,1.86)
		_:result=Vector3(259.0/9,0,1.23)
	return result*Vector3(VIEW.frontage_scale,1,VIEW.figure_scale) if high_view else result

func _init(projection: Transform2D, area: Rect2, types: Dictionary, authored: Dictionary, high_view: bool=false):
	turning_rows=high_view
	ROCKS=authored.rocks
	SIDE_GATE=authored.SidePass
	main_pass=authored.MainPass
	basis=projection
	inverse=basis.affine_inverse()
	bounds=area
	for kind in types:
		var slots=layout(kind,high_view)
		var files=int(types[kind].files)
		# Boots and mounts occupy the ground; helmets and raised spears overhang it.
		# Reserve the full turning envelope, so planned corners are safe at every bearing.
		var aspect=Vector2(basis.x.y,basis.y.y).length()/Vector2(basis.x.x,basis.y.x).length()
		var half=Vector2(1,aspect)*(files-1)*slots.x*.5+Vector2(9,5)*slots.z
		extents[kind]=half
		var walls: Array[Rect2]=[]
		for rock in ROCKS:walls.append(Rect2(rock.position-half,rock.size+half*2))
		clearances[kind]=walls

func crosses(wall: Rect2, a: Vector2, b: Vector2) -> bool:
	var segment_box=Rect2(a,b-a).abs()
	var normal=(b-a).orthogonal()
	return wall.intersects(segment_box,true) and absf(normal.dot(a-wall.get_center()))<=normal.abs().dot(wall.size*.5)

func replace_rocks(obstacles: Array):
	ROCKS=obstacles
	for kind in extents:
		var half: Vector2=extents[kind]
		var walls: Array[Rect2]=[]
		for rock: Rect2 in ROCKS:walls.append(Rect2(rock.position-half,rock.size+half*2))
		clearances[kind]=walls

func clear_segment(kind: String, start: Vector2, finish: Vector2) -> bool:
	var a=basis*start
	var b=basis*finish
	if turning_rows and not (basis*bounds).encloses(Rect2(b-extents[kind],extents[kind]*2)):return false
	for wall: Rect2 in clearances[kind]:
		if crosses(wall,a,b):return false
	return true

func first_blocker(kind: String, start: Vector2, finish: Vector2) -> Vector2:
	var a=basis*start
	var b=basis*finish
	var nearest=b
	for wall: Rect2 in clearances[kind]:
		var corners=[wall.position,Vector2(wall.end.x,wall.position.y),wall.end,Vector2(wall.position.x,wall.end.y)]
		for i in 4:
			var hit=Geometry2D.segment_intersects_segment(a,b,corners[i],corners[(i+1)%4])
			if hit!=null and a.distance_squared_to(hit)<a.distance_squared_to(nearest):nearest=hit
	return inverse*nearest

# A visibility graph on the clearance corners gives exact straight legs around the rock faces.
func leg(kind: String, start: Vector2, finish: Vector2) -> Array[Vector2]:
	var result: Array[Vector2]=[]
	if not bounds.has_point(finish) or not clear_segment(kind,finish,finish):return result
	if clear_segment(kind,start,finish):
		result.append(finish)
		return result
	var graph=AStar2D.new()
	graph.add_point(0,start)
	graph.add_point(1,finish)
	for wall: Rect2 in clearances[kind]:
		var r=wall.grow(2)
		for corner in [r.position,Vector2(r.end.x,r.position.y),r.end,Vector2(r.position.x,r.end.y)]:
			var world: Vector2=inverse*corner
			if bounds.has_point(world) and clear_segment(kind,world,world):
				graph.add_point(graph.get_available_point_id(),world)
	var ids=graph.get_point_ids()
	for i in ids.size():
		for j in i:
			if clear_segment(kind,graph.get_point_position(ids[i]),graph.get_point_position(ids[j])):
				graph.connect_points(ids[i],ids[j])
	result.assign(graph.get_point_path(0,1).slice(1))
	return result

func touches_gate(kind: String, pos: Vector2) -> bool:
	var half: Vector2=extents[kind]
	return Rect2(SIDE_GATE.position-half,SIDE_GATE.size+half*2).has_point(basis*pos)
