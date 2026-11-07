extends SceneTree
const OUT='res://../output/sword-banner-reference/idle-arrival/'
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
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-idle-capture.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false;t.field.clean_capture=true
	var r=t.rules;r.units.clear()
	for x in [760.,1240.]:
		r.spawn('legion','ally',Vector2(x,1200));r.spawn('legion','enemy',Vector2(x,700))
	for u in r.units:u.order='hold'
	var left=r.units[0];var right=r.units[2]
	t.set_camera(r.projection*Vector2(1000,950)-Vector2(960,540)/t.zoom)
	t.refresh();t.start_button.pressed.emit()
	var screen=func(point: Vector2):return (r.projection*point-t.camera_offset)*t.zoom
	var report={'first_idle_pursuit':-1.};var held=[];var trace=FileAccess.open(OUT+'frames.jsonl',FileAccess.WRITE)
	for frame in 660:
		if frame==24:click((r.Soldiers.point(r,left,4)-t.camera_offset)*t.zoom-Vector2(0,20),MOUSE_BUTTON_LEFT,true)
		if frame==48:click(screen.call(Vector2(760,1000)),MOUSE_BUTTON_RIGHT)
		if frame==50:click((r.Soldiers.point(r,right,4)-t.camera_offset)*t.zoom-Vector2(0,20),MOUSE_BUTTON_LEFT,true)
		if frame==52:click(screen.call(Vector2(1240,1000)),MOUSE_BUTTON_RIGHT)
		if frame==240:
			key(KEY_H)
			for actor in right.soldiers:held.append(actor.position)
		t._process(1./60)
		if report.first_idle_pursuit<0. and left.soldiers.any(func(s):return s.get('personal_order','')=='idle' and s.target_id>=0):report.first_idle_pursuit=r.elapsed
		trace.store_line(JSON.stringify({'frame':frame,'time':r.elapsed,'left':left.soldiers,'right':right.soldiers}))
		await process_frame
		if frame in [220,300,540,659]:RenderingServer.force_draw();root.get_texture().get_image().save_png(OUT+'frame-%04d.png'%frame)
	var stable=true
	for i in right.soldiers.size():stable=stable and right.soldiers[i].position==held[i]
	report.right_hold_stable=stable;report.left_approached=left.pos.y<850.;report.final_time=r.elapsed
	FileAccess.open(OUT+'report.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))
	print('Idle native capture ',JSON.stringify(report))
	t.closed.emit();app.queue_free();await process_frame;quit(0 if stable and report.left_approached and report.first_idle_pursuit>0 else 1)
