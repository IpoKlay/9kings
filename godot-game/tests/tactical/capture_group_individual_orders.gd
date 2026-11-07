extends SceneTree
const OUT='res://../output/sword-banner-reference/group-orders/'
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
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-group-capture.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	var r=t.rules;r.units.clear()
	r.spawn('legion','ally',Vector2(1000,1200));r.spawn('legion','enemy',Vector2(1000,500));r.spawn('legion','enemy',Vector2(1850,200))
	for u in r.units:u.order='hold'
	var a=r.units[0];var b=r.units[1]
	t.set_camera(r.projection*Vector2(1000,850)-Vector2(960,540)/t.zoom)
	t.refresh();t.start_button.pressed.emit()
	var screen=func(point: Vector2):return (r.projection*point-t.camera_offset)*t.zoom
	var held=[];var report={};var trace=FileAccess.open(OUT+'frames.jsonl',FileAccess.WRITE)
	for frame in 1200:
		if frame==24:click((r.Soldiers.point(r,a,4)-t.camera_offset)*t.zoom-Vector2(0,20),MOUSE_BUTTON_LEFT,true)
		if frame==48:click(screen.call(Vector2(1000,1000)),MOUSE_BUTTON_RIGHT)
		if frame==108:
			key(KEY_H)
			for actor in a.soldiers:held.append(actor.position)
		if frame==148:
			var stable=true
			for i in a.soldiers.size():stable=stable and a.soldiers[i].position==held[i]
			report.hold_at_actual_feet=stable
		if frame==150:key(KEY_F);drag(screen.call(Vector2(800,900)),screen.call(Vector2(1200,900)))
		if frame==600:report.shield_arrival=a.soldiers.all(func(s):return s.get('shield_wall',false) and s.personal_order=='hold' and absf(s.position.y-900.)<.1)
		if frame==660:click((r.Soldiers.point(r,b,4)-t.camera_offset)*t.zoom-Vector2(0,20),MOUSE_BUTTON_RIGHT)
		t._process(1./60)
		trace.store_line(JSON.stringify({'frame':frame,'time':r.elapsed,'order':a.order,'people':a.soldiers}))
		await process_frame
		if frame in [80,145,600,1000]:RenderingServer.force_draw();root.get_texture().get_image().save_png(OUT+'frame-%04d.png'%frame)
	report.focus_damage=b.hp<b.max_hp;report.final_time=r.elapsed
	FileAccess.open(OUT+'report.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))
	print('Group native capture ',JSON.stringify(report))
	t.closed.emit();app.queue_free();await process_frame;quit(0 if report.hold_at_actual_feet and report.shield_arrival and report.focus_damage else 1)
