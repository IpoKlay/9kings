extends SceneTree
var app
var checks=0
var failures=0
var draws=0
func _init(): call_deferred('run')
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1;printerr('FAIL: '+message)
func capture() -> Image:
	await process_frame
	RenderingServer.force_draw()
	return root.get_texture().get_image()
func run():
	app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/private/tmp/eagle-cache-test.cfg'
	root.add_child(app);current_scene=app;app.sound.enabled=false
	app.restart_expedition(1);app.set_process(false)
	var atlas=app.expedition_map.atlas
	atlas.set_process(false)
	# Isolate sea caching from translucent paper's extra eight-bit rounding step.
	app.expedition_map.paper_surface.self_modulate.a=0
	atlas.draw.connect(func():draws+=1)
	var original=TextureRect.new()
	original.texture=atlas.sea_surface.texture;original.material=atlas.sea_surface.material
	original.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	original.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	original.show_behind_parent=true;original.mouse_filter=Control.MOUSE_FILTER_IGNORE
	app.expedition_map.map_layer.add_child(original);original.hide()
	for window_size in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(1200,900)]:
		root.size=window_size
		await process_frame
		for zoom in [atlas.minimum_zoom(),1.4]:
			atlas.zoom=zoom;atlas.center=atlas.WORLD*.5;atlas.layout()
			original.position=atlas.sea_surface.position;original.size=atlas.sea_surface.size
			app.expedition_map.sea.material.set_shader_parameter('sea_time',.875)
			atlas.sea_cache.refresh()
			var cached=await capture()
			atlas.sea_cache.hide();original.show()
			var direct=await capture()
			var label='%dx%d-%.2f'%[window_size.x,window_size.y,zoom]
			var a=cached.get_data();var b=direct.get_data()
			var changed=0;var largest=0
			for i in a.size():
				var difference=absi(int(a[i])-int(b[i]))
				if difference>0: changed+=1;largest=maxi(largest,difference)
			# The extra 8-bit render target can round translucent route blends by one value.
			check(largest<=1 and changed<float(a.size())*.0001,'Same geometry and palette; at most one rounding level: '+label)
			cached.save_png('res://../output/map-motion-performance/cached-'+label+'.png')
			direct.save_png('res://../output/map-motion-performance/direct-'+label+'.png')
			original.hide();atlas.sea_cache.show()
	draws=0
	for i in 120: atlas._process(1.0/120.0);await process_frame
	RenderingServer.force_draw()
	check(draws==0,'Idle sea and flag never rebuild the unchanged routes')
	check(atlas.sea_cache.buffer.render_target_update_mode!=SubViewport.UPDATE_ALWAYS,'Sea render target is never continuously redrawn')
	app.expedition_map.sea.clock=.51;app.expedition_map.sea.last_frame=6
	var revision=app.expedition_map.sea.revision
	app.expedition_map.sea.advance(.001)
	check(app.expedition_map.sea.revision==revision,'Empty wind arrays are not uploaded on a sub-frame tick')
	app.sound.stop()
	print('%d sea cache checks, %d failures'%[checks,failures]);quit(1 if failures else 0)
