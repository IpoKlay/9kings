extends SceneTree
var checks=0
var failures=0
var app
func _init(): call_deferred('run')
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1;printerr('FAIL: '+message)
func mouse(p: Vector2,pressed: bool,button: int=MOUSE_BUTTON_LEFT):
	var event=InputEventMouseButton.new()
	event.position=p;event.global_position=p;event.pressed=pressed;event.button_index=button
	root.push_input(event,true)
func motion(p: Vector2):
	var event=InputEventMouseMotion.new()
	event.position=p;event.global_position=p;event.button_mask=MOUSE_BUTTON_MASK_LEFT
	root.push_input(event,true)
func run():
	app=load('res://scenes/main.tscn').instantiate()
	app.main_menu=false
	root.add_child(app);current_scene=app;app.set_process(false);app.sound.enabled=false
	app.open_map()
	var map=app.expedition_map
	var atlas=map.atlas
	var boundary=map.map_boundary
	var points: PackedVector2Array=boundary.polygon
	check(Geometry2D.triangulate_polygon(points).size()==(points.size()-2)*3,'Border is a complete triangulatable polygon')
	var orthogonal=true;var on_grid=true;var no_reversal=true
	for i in points.size():
		var previous=points[i]-points[(i+points.size()-1)%points.size()]
		var next=points[(i+1)%points.size()]-points[i]
		orthogonal=orthogonal and (next.x==0 or next.y==0)
		on_grid=on_grid and points[i]==points[i].snapped(Vector2.ONE*boundary.preset.pixel_step)
		no_reversal=no_reversal and previous.dot(next)>=0
	check(orthogonal and on_grid,'Every border edge follows the pixel grid')
	check(no_reversal,'Corners and wave joins have no backtracking spikes')
	check(points==map.content.get_node('PixelMapEdge').polygon,'Visible trim and clipping polygon agree')
	boundary.rebuild()
	check(points==boundary.polygon,'Rebuilding the map never changes the border pattern')
	# Every repeated tooth has exactly the same dimensions, with no random depths.
	var pitch=float(boundary.preset.period)
	for side in [Vector2.DOWN,Vector2.LEFT]:
		boundary.polygon.clear()
		var tangent=Vector2.RIGHT if side==Vector2.DOWN else Vector2.DOWN
		boundary.edge(Vector2.ZERO,tangent*pitch,side)
		var tooth=boundary.polygon.duplicate()
		boundary.polygon.clear()
		boundary.edge(tangent*pitch,tangent*pitch*2,side)
		var repeated=boundary.polygon.duplicate()
		for i in repeated.size(): repeated[i]-=tangent*pitch
		check(tooth==repeated,'Adjacent pixel teeth repeat at a fixed pitch')
	boundary.rebuild()
	atlas.overview()
	for id in atlas.buttons:
		var r: Rect2=atlas.buttons[id].get_rect().grow(2)
		var inside=true
		for point in [r.position,r.end,Vector2(r.position.x,r.end.y),Vector2(r.end.x,r.position.y)]:
			inside=inside and boundary.contains_point(point)
		check(inside,'Overview keeps entire city target within border: '+id)
	var image_rect=Rect2(atlas.sea_surface.position,atlas.sea_surface.size)
	check(Array(points).all(func(p):return image_rect.has_point(p)),'Map texture covers the entire clipped interior without blank bands')
	var zoom=atlas.zoom
	mouse(Vector2(6,400),true,MOUSE_BUTTON_WHEEL_UP)
	check(atlas.zoom==zoom,'Wheel outside border cannot zoom the map')
	var center=atlas.center
	mouse(Vector2(6,400),true);motion(Vector2(80,400));mouse(Vector2(80,400),false)
	check(atlas.center==center and not atlas.holding,'Drag beginning outside border cannot grab the map')
	var pan=InputEventPanGesture.new();pan.position=Vector2(6,400);pan.delta=Vector2(20,0)
	root.push_input(pan,true)
	check(atlas.center==center,'Trackpad gesture outside border cannot move the map')
	atlas.focus_city('423025')
	mouse(Vector2(900,400),true);motion(Vector2(6,400));mouse(Vector2(6,400),false)
	check(not atlas.holding,'Drag can end outside the border without becoming stuck')
	check(map.selected=='','Dragging through the border cannot select a city')
	check(points==boundary.polygon,'Zooming and panning preserve the fixed border')
	if DisplayServer.get_name()!='headless':
		atlas.overview()
		await process_frame
		RenderingServer.force_draw()
		var image=root.get_texture().get_image()
		image.save_png('res://tests/atlas-boundary.png')
		var paper=map.paper_texture().get_image()
		paper.convert(Image.FORMAT_RGBA8)
		var wear=map.PaperWear.edge_texture().get_image()
		paper.blend_rect(wear,Rect2i(Vector2i.ZERO,wear.get_size()),Vector2i.ZERO)
		check(map.paper_texture()==map.content.get_node('ParchmentBacking').texture,'Paper texture is cached across map updates')
		var pigments={}
		var leaked=false
		for x in range(2,image.get_width()-2,23):
			for y in [2,image.get_height()-3]:
				var color=image.get_pixel(x,y)
				var expected=paper.get_pixel(int((x+.5)*paper.get_width()/image.get_width()),int((y+.5)*paper.get_height()/image.get_height()))
				if not close_color(color,expected): leaked=true
				pigments[color.to_rgba32()]=true
		for y in range(2,image.get_height()-2,23):
			for x in [2,image.get_width()-3]:
				var color=image.get_pixel(x,y)
				var expected=paper.get_pixel(int((x+.5)*paper.get_width()/image.get_width()),int((y+.5)*paper.get_height()/image.get_height()))
				if not close_color(color,expected): leaked=true
		check(not leaked,'Native render clips terrain, routes and water at the outer frame')
		check(pigments.size()>=3,'Visible paper edge contains varied pigment rather than a solid fill')
	app.sound.stop()
	print('%d pixel map boundary checks, %d failures'%[checks,failures])
	quit(1 if failures else 0)

func close_color(a: Color,b: Color) -> bool:
	# CPU image blending and GPU alpha blending may round an eight-bit channel differently.
	return maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))<=1.01/255.0
