extends SceneTree
const Wear=preload('res://scripts/map_paper_wear.gd')
var checks=0
var failures=0
var view: SubViewport
func _init(): call_deferred('run')
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1;printerr('FAIL: '+message)
func capture() -> Image:
	await process_frame;RenderingServer.force_draw()
	return view.get_texture().get_image()
func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path('res://../output/map-paper-wear'))
	seed(7927);var expected_random=randi();seed(7927)
	var texture=Wear.texture()
	check(randi()==expected_random,'Baking paper wear never consumes the gameplay random stream')
	check(texture==Wear.texture(),'All paper surfaces reuse a single cached texture')
	var pixels=texture.get_image()
	var marked=0;var central_max=0.0
	for y in pixels.get_height():
		for x in pixels.get_width():
			var alpha=pixels.get_pixel(x,y).a
			if alpha>0: marked+=1
			if x>20 and y>20 and x<pixels.get_width()-20 and y<pixels.get_height()-20: central_max=maxf(central_max,alpha)
	check(float(marked)/(pixels.get_width()*pixels.get_height())<.10,'More than ninety percent of the sheet remains untouched')
	check(central_max<.3,'Interior folds remain translucent and restrained')
	Wear.cached=null
	check(Wear.texture().get_image().get_data()==pixels.get_data(),'Rebuilding paper wear produces identical pixels')
	var host=Window.new();root.add_child(host)
	view=SubViewport.new();view.size=Vector2i(1920,1080)
	view.size_2d_override=Vector2i(1920,1080);view.size_2d_override_stretch=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;host.add_child(view)
	var app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/private/tmp/eagle-paper-wear-test.cfg';view.add_child(app)
	app.set_process(false);app.sound.enabled=false;app.starting_theaters.assign([1]);app.start_game()
	var map=app.expedition_map;map.settle_entry();map.atlas.set_process(false)
	var state=app.expedition.state.duplicate(true)
	check(map.content.get_parent()==map and not map.has_node('MapUnroll'),'Map paper appears directly without a scroll wrapper')
	for child in map.content.get_children():
		if child is Button or child is Panel: child.hide()
	var flat=await capture()
	flat.save_png('res://../output/map-paper-wear/test-resting.png')
	check(flat.get_data()==(await capture()).get_data(),'Resting creases and edge curls do not move or shimmer')
	var decorated=Wear.texture()
	var decorated_edges=Wear.edge_texture()
	var blank=Image.create(pixels.get_width(),pixels.get_height(),false,Image.FORMAT_RGBA8)
	Wear.cached=ImageTexture.create_from_image(blank)
	var edge=map.content.get_node('ParchmentBacking/PaperEdgeWear')
	edge.texture=Wear.cached;map.paper_surface.texture=Wear.cached
	var clean=await capture()
	clean.save_png('res://../output/map-paper-wear/test-clean.png')
	var icon_pixels_unchanged=true
	var opaque_pixels=0
	for button in map.city_buttons.values():
		if button.visible and button.modulate.a==1:
			var art=button.get_child(0)
			var mask=art.texture.get_image()
			var rect=Rect2i(art.get_global_rect()).intersection(Rect2i(Vector2i.ZERO,flat.get_size()))
			for y in range(rect.position.y,rect.end.y):
				for x in range(rect.position.x,rect.end.x):
					var uv=(Vector2(x+.5,y+.5)-art.global_position)/art.size
					var pixel=Vector2i(uv*Vector2(mask.get_size()))
					# Exclude sprite-edge rounding and genuinely translucent pixels.
					var opaque=pixel.x>0 and pixel.y>0 and pixel.x<mask.get_width()-1 and pixel.y<mask.get_height()-1
					if opaque:
						for offset in [Vector2i.ZERO,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]: opaque=opaque and mask.get_pixelv(pixel+offset).a==1
					if opaque:
						opaque_pixels+=1
						icon_pixels_unchanged=icon_pixels_unchanged and flat.get_pixel(x,y)==clean.get_pixel(x,y)
	check(icon_pixels_unchanged and opaque_pixels>100,'Paper folds never tint the city icon interiors')
	Wear.cached=decorated;edge.texture=decorated_edges;map.paper_surface.texture=decorated
	check(edge.mouse_filter==Control.MOUSE_FILTER_IGNORE,'Decorative paper does not intercept map clicks')
	map.atlas.focus_city('423025')
	var pos=map.city_buttons['423025'].get_global_rect().get_center()
	for down in [true,false]:
		var event=InputEventMouseButton.new();event.position=pos;event.global_position=pos
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;view.push_input(event,true)
	check(map.selected=='423025' and app.expedition.state==state,'City selection still works without changing campaign state')
	check(map.content.get_node('ParchmentBacking/PaperEdgeWear').texture==decorated_edges,'Rebuilding map UI keeps the same paper edge material')
	app.sound.stop();print('%d paper wear checks, %d failures'%[checks,failures]);quit(1 if failures else 0)
