extends SceneTree
const OUT='res://../output/sword-banner-reference/shield-columns/'
func _initialize():call_deferred('run')
func key(code: Key):
	var e=InputEventKey.new();e.pressed=true;e.physical_keycode=code;root.push_input(e,true)
func click(point: Vector2,button: MouseButton=MOUSE_BUTTON_LEFT,double: bool=false):
	for down in [true,false]:
		var e=InputEventMouseButton.new();e.position=point;e.global_position=point;e.button_index=button;e.pressed=down;e.double_click=double;root.push_input(e,true)
func drag(from: Vector2,to: Vector2):
	var e=InputEventMouseButton.new();e.position=from;e.global_position=from;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=true;root.push_input(e,true)
	var motion=InputEventMouseMotion.new();motion.position=to;motion.global_position=to;motion.relative=to-from;motion.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(motion,true)
	e=InputEventMouseButton.new();e.position=to;e.global_position=to;e.button_index=MOUSE_BUTTON_LEFT;root.push_input(e,true)
func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-wall-capture.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false;t.field.clean_capture=true
	var r=t.rules;r.units.clear()
	r.spawn('legion','ally',Vector2(965,1200));r.spawn('legion','enemy',Vector2(920,800));r.spawn('legion','enemy',Vector2(1850,200))
	for u in r.units:u.order='hold'
	var a=r.units[0];var b=r.units[1]
	for slot in b.soldiers.size():
		b.soldiers[slot].hp=10000. if slot<3 else 0.;b.soldiers[slot].max_hp=10000.
		if slot<3:
			r.Charges.detach(r,b,slot);b.soldiers[slot].position=Vector2(900+slot*20,800);b.soldiers[slot].cooldown=60.
	r.Soldiers.total(b)
	t.set_camera(r.projection*Vector2(965,930)-Vector2(960,540)/t.zoom)
	t.refresh();t.start_button.pressed.emit()
	var screen=func(point: Vector2):return (r.projection*point-t.camera_offset)*t.zoom
	var report={'first_lock':-1.,'free_wing':false,'reached_wall':false};var trace=FileAccess.open(OUT+'frames.jsonl',FileAccess.WRITE)
	for frame in 1080:
		if frame==24:click((r.Soldiers.point(r,a,4)-t.camera_offset)*t.zoom-Vector2(0,20),MOUSE_BUTTON_LEFT,true)
		if frame==48:key(KEY_F);drag(screen.call(Vector2(900,1000)),screen.call(Vector2(1030,1000)))
		if frame==420:
			report.reached_wall=a.soldiers.all(func(s):return s.get('shield_wall',false) and s.position.distance_to(s.wall_slot)<3.)
			click(screen.call(Vector2(965,700)),MOUSE_BUTTON_RIGHT)
		t._process(1./60)
		if not r.shield_walls.is_empty():
			var wall=r.shield_walls[0]
			if not wall.locks.is_empty():
				if report.first_lock<0.:report.first_lock=r.elapsed
				var low=INF;var high=-INF
				for actor in a.soldiers:low=minf(low,actor.position.y);high=maxf(high,actor.position.y)
				report.free_wing=report.free_wing or high-low>15.
		trace.store_line(JSON.stringify({'frame':frame,'time':r.elapsed,'people':a.soldiers,'walls':r.shield_walls}))
		await process_frame
		if frame in [400,660,900,1079]:RenderingServer.force_draw();root.get_texture().get_image().save_png(OUT+'frame-%04d.png'%frame)
	report.final_time=r.elapsed;report.shields_preserved=a.soldiers.all(func(s):return s.shield_wall)
	FileAccess.open(OUT+'report.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))
	print('Shield column native capture ',JSON.stringify(report))
	t.closed.emit();app.queue_free();await process_frame;quit(0 if report.first_lock>0 and report.free_wing and report.reached_wall and report.shields_preserved else 1)
