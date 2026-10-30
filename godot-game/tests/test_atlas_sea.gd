extends SceneTree
var checks=0
var failures=0
var app
func _init(): call_deferred('run')
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1;printerr('FAIL: '+message)
func frame_image(vp: Viewport) -> Image:
	# This test deliberately edits shader uniforms outside the live sea controller.
	app.expedition_map.atlas.sea_cache.refresh()
	await process_frame
	await process_frame
	RenderingServer.force_draw() # Deterministic capture even when the OS occludes this test window.
	return vp.get_texture().get_image()
func motion(p: Vector2):
	var event=InputEventMouseMotion.new()
	event.position=p;event.global_position=p
	root.push_input(event,true)
func new_water():
	var water=load('res://scripts/atlas_sea.gd').new()
	water.setup(app.expedition_map.tex('atlas'))
	return water
func speed_trace(center: Vector2,pointer_speed: float,frames: int):
	var water=new_water()
	water.move_pointer(center-Vector2(36,0),0.0)
	water.move_pointer(center+Vector2(36,0),72.0/pointer_speed)
	for i in frames:
		var previous: Vector2=water.gusts[0].position
		water.advance(1.0/frames)
		check(previous.distance_to(water.gusts[0].position)<=28.0/frames+.0005,'Wind advection respects the reduced speed ceiling')
	return water
func check_wind(center: Vector2):
	var slow=speed_trace(center,50.0,30)
	var medium=speed_trace(center,110.0,30)
	var fast=speed_trace(center,600.0,30)
	var extreme=speed_trace(center,6000.0,30)
	check(float(slow.gusts[0].travel)<float(medium.gusts[0].travel),'Slow mouse motion produces slower wind movement')
	check(float(medium.gusts[0].travel)<float(fast.gusts[0].travel),'Motion below the ceiling still responds proportionally')
	check(absf(float(fast.gusts[0].travel)-float(extreme.gusts[0].travel))<.001,'Ten times faster input above the ceiling cannot speed the water further')
	var high_fps=speed_trace(center,600.0,120)
	check(absf(float(high_fps.gusts[0].travel)-float(fast.gusts[0].travel))<.001,'30 and 120 frames produce the same one-second wind travel')
	var old=fast.gusts[0]
	var original_birth=old.born
	var original_position: Vector2=old.position
	fast.break_stroke()
	fast.move_pointer(center+Vector2(0,40),0.0)
	fast.move_pointer(center+Vector2(0,60),.05)
	check(fast.gusts.size()==2,'A new direction adds a wind patch without replacing old motion')
	check(old.born==original_birth and old.position==original_position,'New input cannot reset or teleport an older patch')
	var strength_before=fast.gust_strength(old)
	for i in 30: fast.advance(1.0/30.0)
	check(fast.gust_strength(old)<strength_before*.6,'Wind fades substantially within the next second')
	for i in 90: fast.advance(1.0/30.0)
	check(fast.gusts.is_empty(),'Wind clears in under three seconds after the last input')
	print('WIND SPEED: slow=%.2f, medium=%.2f, fast=%.2f, extreme=%.2f map pixels in one second'%[slow.gusts[0].travel,medium.gusts[0].travel,high_fps.gusts[0].travel,extreme.gusts[0].travel])

func run():
	if DisplayServer.get_name()=='headless':
		printerr('Atlas sea validation needs native GPU rendering');quit(1);return
	app=load('res://scenes/main.tscn').instantiate()
	app.main_menu=false
	root.add_child(app);current_scene=app;app.set_process(false);app.sound.enabled=false;app.language='zh'
	app.open_map()
	var atlas=app.expedition_map.atlas
	atlas.set_process(false)
	var sea=app.expedition_map.sea
	var state=app.expedition.state.duplicate(true)
	var vp=SubViewport.new()
	vp.size=Vector2i(960,420);vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var surface=TextureRect.new()
	surface.texture=app.expedition_map.tex('atlas');surface.material=sea.material
	surface.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	surface.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;surface.size=Vector2(960,420)
	vp.add_child(surface)
	sea.material.set_shader_parameter('sea_time',0.0)
	var first=await frame_image(vp)
	sea.material.set_shader_parameter('sea_time',.875)
	var later=await frame_image(vp)
	var changed_water=0
	var changed_land=0
	for y in 420:
		for x in 960:
			if first.get_pixel(x,y)==later.get_pixel(x,y): continue
			if not sea.is_water(Vector2(x*3+1,y*3+1)*2): changed_land+=1
			else: changed_water+=1
	check(changed_water>1000,'A connected irregular water pattern visibly flows over the sea')
	check(changed_land==0,'Animated texture leaves every sampled land pixel intact')
	sea.material.set_shader_parameter('coast_enabled',false)
	var no_coast=await frame_image(vp)
	sea.material.set_shader_parameter('coast_enabled',true)
	var with_coast=await frame_image(vp)
	var coast_pixels=0
	var coast_outside=0
	var coast_depths={}
	for y in 420:
		for x in 960:
			if no_coast.get_pixel(x,y)==with_coast.get_pixel(x,y): continue
			coast_pixels+=1
			var mask=sea.shore.get_pixel(x*3+1,y*3+1)
			if mask.g<.5 or mask.r>=.65: coast_outside+=1
			coast_depths[int(mask.r*16)]=true
	check(coast_pixels>100,'Pixel breakers still follow the coast')
	check(coast_outside==0,'Coastal breakers never paint land or deep sea')
	check(coast_depths.size()>=4,'Coastal approach and retreat remain asynchronous')
	with_coast.save_png('res://tests/atlas-sea-coast.png')
	check(not Input.use_accumulated_input,'Map continues to receive raw mouse motion')
	var center=Vector2.ZERO
	for y in range(850,1850,100):
		for x in range(1800,4200,120):
			var clear=sea.is_water(Vector2(x,y))
			for i in 32:
				if not sea.is_water(Vector2(x,y)+Vector2.from_angle(i*TAU/32.0)*230.0): clear=false;break
			if clear: center=Vector2(x,y);break
		if center!=Vector2.ZERO: break
	check(center!=Vector2.ZERO,'Broad open water found for wind feedback')
	atlas.center=center;atlas.zoom=1.4;atlas.clamp_camera();atlas.layout()
	sea.material.set_shader_parameter('wind_enabled',false)
	var still=await frame_image(root)
	still.save_png('res://tests/atlas-sea-still.png')
	sea.material.set_shader_parameter('wind_enabled',true)
	var before_clock=sea.clock
	motion((center-atlas.center)*atlas.zoom+atlas.size*.5+atlas.global_position)
	motion((center+Vector2(1,0)-atlas.center)*atlas.zoom+atlas.size*.5+atlas.global_position)
	var immediate=await frame_image(root)
	check(immediate.get_data()!=still.get_data() and sea.clock==before_clock,'A one-pixel slow move gives wind feedback without a clock delay')
	for i in 24:
		var world=center+Vector2(i*6,sin(i*.15)*26)
		motion((world-atlas.center)*atlas.zoom+atlas.size*.5+atlas.global_position)
		sea.advance(1.0/30.0)
	sea.material.set_shader_parameter('sea_time',.875)
	var wake=await frame_image(root)
	var isolated=await frame_image(vp)
	sea.material.set_shader_parameter('wind_enabled',false)
	var calm=await frame_image(vp)
	sea.material.set_shader_parameter('wind_enabled',true)
	var wind_palette={}
	var wind_brightest=0.0
	var changed_wind=0
	var wind_land=0
	for y in 420:
		for x in 960:
			if isolated.get_pixel(x,y)==calm.get_pixel(x,y): continue
			changed_wind+=1
			var color=isolated.get_pixel(x,y)
			wind_palette[color.to_html()]=true
			wind_brightest=maxf(wind_brightest,maxf(color.r,maxf(color.g,color.b)))
			if not sea.is_water(Vector2(x*3+1,y*3+1)*2): wind_land+=1
	check(changed_wind>100,'Pointer wind affects a broad visible water region')
	check(wind_land==0,'Wind never affects dry land')
	check(wind_palette.size()<=4,'Wind keeps a flat, limited pixel palette')
	check(wind_brightest<.60,'The reference animation uses the existing dark palette, without pale cyan highlights')
	check(app.expedition.state==state and app.expedition_map.selected=='','Wind hover never selects a city or advances the campaign')
	wake.save_png('res://tests/atlas-sea-wake.png')
	var original_clock=sea.clock
	app.dialog_kind='settings';atlas._process(.05)
	check(sea.clock==original_clock,'Settings pauses wind and ambient animation')
	app.dialog_kind='';app.expedition_map.hide();atlas._process(.05)
	check(sea.clock==original_clock,'Hidden map does not keep simulating')
	check(Input.use_accumulated_input==app.expedition_map.saved_accumulated_input,'Leaving the map restores mouse handling')
	app.expedition_map.show()
	var before=sea.gusts.duplicate(true)
	sea.move_pointer(Vector2(1900,300));sea.move_pointer(Vector2(1940,320))
	check(sea.gusts==before,'Moving on dry land emits no wind')
	atlas.zoom_at(atlas.size*.5,1.18)
	check(sea.pointer==Vector2.INF and sea.gusts==before,'Zoom interrupts input without teleporting existing water motion')
	for i in 90: sea.advance(1.0/30.0)
	check(sea.gusts.is_empty(),'Previous wind has cleared after three seconds')
	atlas.zoom=1.4;atlas.layout();sea.break_stroke()
	for i in 289:
		var world=center+Vector2.from_angle(i*TAU/72.0)*110.0
		motion((world-atlas.center)*atlas.zoom+atlas.size*.5+atlas.global_position)
		sea.advance(1.0/120.0)
	check(sea.gusts.size()>3 and sea.gusts.size()<=12,'Rapid circles create bounded broad wind patches, not cursor-path loops')
	var image=await frame_image(root)
	image.save_png('res://tests/atlas-sea-wind.png')
	image.save_png('res://tests/atlas-sea-circles.png')
	var energy=0.0
	for gust in sea.gusts: energy+=sea.gust_strength(gust)
	for i in 30: sea.advance(1.0/30.0)
	var remaining=0.0
	for gust in sea.gusts: remaining+=sea.gust_strength(gust)
	check(remaining>0.0 and remaining<energy*.65,'The whole wind region fades quickly without fragment dropout')
	(await frame_image(root)).save_png('res://tests/atlas-sea-wind-fading.png')
	for i in 60: sea.advance(1.0/30.0)
	check(sea.gusts.is_empty(),'All wind clears within three seconds of stopping')
	(await frame_image(root)).save_png('res://tests/atlas-sea-wind-settled.png')
	check_wind(center)
	print('PIXEL WIND: ocean animation=%d land=%d; wind=%d land=%d colors=%d brightest=%.3f; coast=%d outside=%d phases=%d'%[changed_water,changed_land,changed_wind,wind_land,wind_palette.size(),wind_brightest,coast_pixels,coast_outside,coast_depths.size()])
	app.sound.stop();vp.queue_free()
	print('%d atlas sea checks, %d failures'%[checks,failures])
	quit(1 if failures else 0)
