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
var graphs={}
var graph_builds=0
var wall_cells={}

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
	graphs.clear();wall_cells.clear()
	ROCKS=merge_obstacles(obstacles)
	for kind in extents:
		var half: Vector2=extents[kind]
		var walls: Array[Rect2]=[]
		for rock: Rect2 in ROCKS:walls.append(Rect2(rock.position-half,rock.size+half*2))
		clearances[kind]=walls

func clear_segment(kind: String, start: Vector2, finish: Vector2) -> bool:
	var a=basis*start
	var b=basis*finish
	if turning_rows and not (basis*bounds).encloses(Rect2(b-extents[kind],extents[kind]*2)):return false
	var walls: Array=nearby_walls(kind,a,b)
	for wall: Rect2 in walls:
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
	var graph: AStar2D
	if graphs.has(kind):graph=graphs[kind]
	else:
		graph=AStar2D.new();graph_builds+=1
		var seen={}
		for wall: Rect2 in clearances[kind]:
			var rect=wall.grow(2)
			for corner in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:
				var world: Vector2=inverse*corner
				if seen.has(world) or not bounds.has_point(world) or not clear_segment(kind,world,world):continue
				seen[world]=true;graph.add_point(graph.get_point_count()+2,world)
		var ids=graph.get_point_ids()
		for i in ids.size():
			for j in i:
				if clear_segment(kind,graph.get_point_position(ids[i]),graph.get_point_position(ids[j])):graph.connect_points(ids[i],ids[j])
		graphs[kind]=graph
	graph.add_point(0,start);graph.add_point(1,finish)
	for id in graph.get_point_ids():
		if id<2:continue
		var point=graph.get_point_position(id)
		if clear_segment(kind,start,point):graph.connect_points(0,id)
		if clear_segment(kind,finish,point):graph.connect_points(1,id)
	result.assign(graph.get_point_path(0,1).slice(1))
	graph.remove_point(0);graph.remove_point(1)
	return result

# Union only aligned rectangles: never fill an open gate or a concave corner.
func merge_obstacles(obstacles: Array) -> Array:
	var merged=obstacles.duplicate()
	var changed=true
	while changed:
		changed=false
		for i in merged.size():
			for j in range(i+1,merged.size()):
				var a: Rect2=merged[i];var b: Rect2=merged[j]
				var horizontal=is_equal_approx(a.position.y,b.position.y) and is_equal_approx(a.size.y,b.size.y) and a.position.x<=b.end.x and b.position.x<=a.end.x
				var vertical=is_equal_approx(a.position.x,b.position.x) and is_equal_approx(a.size.x,b.size.x) and a.position.y<=b.end.y and b.position.y<=a.end.y
				if horizontal or vertical:
					merged[i]=a.merge(b);merged.remove_at(j);changed=true;break
			if changed:break
	return merged

func touches_gate(kind: String, pos: Vector2) -> bool:
	var half: Vector2=extents[kind]
	return Rect2(SIDE_GATE.position-half,SIDE_GATE.size+half*2).has_point(basis*pos)

func nearby_walls(kind: String,a: Vector2,b: Vector2) -> Array:
	if a.distance_squared_to(b)>16384.:return clearances[kind]
	if not wall_cells.has(kind):
		var cells={}
		for wall: Rect2 in clearances[kind]:
			var low=Vector2i((wall.position/128.).floor());var high=Vector2i((wall.end/128.).floor())
			for x in range(low.x,high.x+1):
				for y in range(low.y,high.y+1):
					var key=Vector2i(x,y)
					if not cells.has(key):cells[key]=[]
					cells[key].append(wall)
		wall_cells[kind]=cells
	var low=Vector2i((a.min(b)/128.).floor());var high=Vector2i((a.max(b)/128.).floor())
	if low==high:return wall_cells[kind].get(low,[])
	var result=[]
	for x in range(low.x,high.x+1):
		for y in range(low.y,high.y+1):
			for wall in wall_cells[kind].get(Vector2i(x,y),[]):
				if wall not in result:result.append(wall)
	return result
