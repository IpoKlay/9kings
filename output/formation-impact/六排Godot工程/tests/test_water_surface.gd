extends SceneTree
const Scenery=preload('res://scripts/battle_environment.gd')
var checks=0
var failures=0
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1;printerr('FAIL: '+message)
func _init(): call_deferred('run')
func frame_image(vp: Viewport):
	await process_frame
	await process_frame
	RenderingServer.force_draw() # Deterministic capture even when the OS occludes this test window.
	return vp.get_texture().get_image()
func run():
	if DisplayServer.get_name()=='headless':
		printerr('Water shader requires a rendered window');quit(1);return
	var app=load('res://scenes/main.tscn').instantiate()
	root.add_child(app);current_scene=app;app.set_process(false)
	app.main_menu=false;app.has_run=true;app.language='zh';app.sound.enabled=false
	var viewport=SubViewport.new()
	viewport.size=Vector2i(960,540)
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var water=Sprite2D.new()
	water.centered=false;water.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	viewport.add_child(water)
	for act in [1,2,3]:
		app.restart_expedition(act);app.travel_to(app.expedition.destinations()[0])
		app.world.environment.clock=4.0
		app.world.refresh()
		water.texture=app.world.environment.surface.texture
		water.scale=Vector2(960,540)/water.texture.get_size()
		water.material=app.world.environment.surface.material.duplicate(true)
		water.material.set_shader_parameter('flow_time',0.0)
		var first=await frame_image(viewport)
		water.material.set_shader_parameter('flow_time',5.0)
		var later=await frame_image(viewport)
		var changed_water=0
		var changed_land=0
		var polygon=PackedVector2Array(Scenery.WATER_POLYGONS[act-1])
		for y in range(0,540,2):
			for x in range(0,960,2):
				if first.get_pixel(x,y)==later.get_pixel(x,y): continue
				if Geometry2D.is_point_in_polygon(Vector2(x*2,y*2),polygon): changed_water+=1
				else: changed_land+=1
		print('WATER act=',act,' animated samples=',changed_water,' changed land samples=',changed_land)
		check(changed_water>200,'Water visibly flows in theater '+str(act))
		check(changed_land==0,'Land and shore outside water footprint never move')
		check(app.world.environment.surface.material.get_shader_parameter('flow_speed')==Scenery.WATER_SPEEDS[act-1],'Each biome uses its own water speed')
		var screen=await frame_image(root)
		screen.save_png('res://tests/water-biome-'+str(act)+'.png')
		first.save_png('res://tests/water-surface-'+str(act)+'-a.png')
		later.save_png('res://tests/water-surface-'+str(act)+'-b.png')
	check(load('res://assets/environments/oak.png').get_image().detect_alpha()!=Image.ALPHA_NONE,'New oak has true transparency')
	check(app.world.environment.BACKGROUNDS==['environments/iberia-grass','environments/africa-sand','environments/east-coastal'],'The three regional terrains load in the correct order')
	viewport.queue_free();app.sound.stop()
	print('%d rendered water checks, %d failures'%[checks,failures])
	quit(1 if failures else 0)
