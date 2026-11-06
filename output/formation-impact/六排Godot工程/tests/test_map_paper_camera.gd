extends SceneTree
var view: SubViewport
var checks=0
var failures=0
func _init(): call_deferred('run')
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1;printerr('FAIL: '+message)
func capture() -> Image:
	await process_frame;RenderingServer.force_draw()
	return view.get_texture().get_image()
func mouse(p: Vector2,down: bool,button: int=MOUSE_BUTTON_LEFT):
	var event=InputEventMouseButton.new()
	event.position=p;event.global_position=p;event.pressed=down;event.button_index=button
	view.push_input(event,true)
func click(button: Button):
	var p=button.get_global_rect().get_center()
	mouse(p,true);mouse(p,false)
func paper_image(map) -> Image:
	# Isolate the actual paper draw pass; changing terrain beneath translucent ink is expected.
	var nodes=[map.atlas,map.atlas.sea_cache]
	if map.atlas.sea_cache.direct: nodes.append(map.atlas.sea_surface)
	for child in map.content.get_children():
		if child is Button or child is Panel: nodes.append(child)
	var visibility=[]
	for node in nodes: visibility.append(node.visible);node.hide()
	var pixels=await capture()
	for i in nodes.size(): nodes[i].visible=visibility[i]
	return pixels
func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path('res://../output/map-paper-world'))
	var host=Window.new();root.add_child(host)
	view=SubViewport.new();view.size=Vector2i(1280,720)
	view.size_2d_override=Vector2i(1920,1080);view.size_2d_override_stretch=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;host.add_child(view)
	var app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/private/tmp/eagle-paper-camera-test.cfg';view.add_child(app)
	app.set_process(false);app.sound.enabled=false;app.starting_theaters.assign([1]);app.start_game()
	var map=app.expedition_map;map.settle_entry()
	var atlas=map.atlas;atlas.set_process(false)
	var paper=map.paper_surface
	check(paper.get_parent()==map.map_layer and atlas.get_parent()==map.map_layer,'Terrain, paper and routes share a stable layer with independent draw order')
	check(paper.mouse_filter==Control.MOUSE_FILTER_IGNORE,'Paper does not intercept zoom or map dragging')
	var original_texture=paper.texture
	var probe_image=Image.create(640,360,false,Image.FORMAT_RGBA8)
	var pixel=Vector2i(atlas.world_at(Vector2(1200,600))/atlas.WORLD*Vector2(probe_image.get_size()))
	probe_image.fill_rect(Rect2i(pixel-Vector2i(1,1),Vector2i(3,3)),Color.WHITE)
	var probe_texture=ImageTexture.create_from_image(probe_image)
	var landmark_world=(Vector2(pixel)+Vector2(.5,.5))/Vector2(probe_image.get_size())*atlas.WORLD
	(await capture()).save_png('res://../output/map-paper-world/before.png')
	for action in ['plus','minus','wheel','magnify','drag','live_water','cached_water']:
		var zoom=atlas.zoom;var center=atlas.center
		var previous_rect=paper.get_global_rect()
		var previous_pixels=(await paper_image(map)).get_data()
		match action:
			'plus': click(map.content.get_node('ZoomIn'))
			'minus': click(map.content.get_node('ZoomOut'))
			'wheel': mouse(Vector2(800,400),true,MOUSE_BUTTON_WHEEL_UP)
			'magnify':
				var event=InputEventMagnifyGesture.new();event.position=Vector2(850,500);event.factor=1.5;view.push_input(event,true)
			'drag':
				mouse(Vector2(750,450),true)
				var event=InputEventMouseMotion.new();event.position=Vector2(1000,550);event.global_position=event.position;event.button_mask=MOUSE_BUTTON_MASK_LEFT
				view.push_input(event,true);mouse(event.position,false);atlas.layout()
			'live_water': atlas.sea_cache.refresh_if_needed(true)
			'cached_water': atlas.sea_cache.refresh_if_needed(false,true)
		if action in ['plus','minus','wheel','magnify']: check(atlas.zoom!=zoom,'Zoom input actually changes terrain scale: '+action)
		if action=='drag': check(atlas.center!=center,'Dragging actually changes the geographic camera')
		check(paper.get_global_rect()==atlas.sea_surface.get_global_rect() and paper.texture==original_texture,'Creases share the exact terrain position and extent without rebaking: '+action)
		var drawn=(await paper_image(map)).get_data()
		if action in ['live_water','cached_water']:
			check(paper.get_global_rect()==previous_rect and drawn==previous_pixels,'Sea render mode leaves the paper in place: '+action)
		else:
			check(paper.get_global_rect()!=previous_rect and drawn!=previous_pixels,'Rendered creases move and scale with the camera: '+action)
		paper.texture=probe_texture
		var probe=await paper_image(map)
		var screen=(landmark_world-atlas.center)*atlas.zoom+atlas.size*.5
		var sample=Vector2i(screen*Vector2(view.size)/atlas.size)
		check(Rect2i(Vector2i.ZERO,probe.get_size()).has_point(sample) and probe.get_pixelv(sample)==Color.WHITE,'A printed landmark stays registered to its world position: '+action)
		paper.texture=original_texture
		var rendered=await capture()
		rendered.save_png('res://../output/map-paper-world/'+action+'.png')
		var sea_pixels=0
		for y in range(110,rendered.get_height()-20,8):
			for x in range(20,rendered.get_width()-20,8):
				var color=rendered.get_pixel(x,y)
				if color.b>color.r*1.3 and color.b>.2: sea_pixels+=1
		check(sea_pixels>100,'Geography remains visible beneath the world-anchored paper: '+action)
	var remembered=paper.get_rect()
	map.render()
	check(map.paper_surface.get_rect()==remembered and map.paper_surface.texture==original_texture,'Opening map UI preserves the same world paper coordinates')
	check(map.atlas.sea_surface.get_parent()==map.atlas.sea_cache.buffer,'Live terrain returns to its cache without disturbing the paper layer')
	app.sound.stop();print('%d world paper camera checks, %d failures'%[checks,failures]);quit(1 if failures else 0)
