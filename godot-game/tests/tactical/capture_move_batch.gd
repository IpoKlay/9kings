extends SceneTree
const OUT='res://../output/sword-banner-reference/move-batch/'
func _initialize():call_deferred('run')
func key(code: Key):
	var e=InputEventKey.new();e.pressed=true;e.physical_keycode=code;root.push_input(e,true)
func click(point: Vector2,button: MouseButton=MOUSE_BUTTON_LEFT,double: bool=false,ctrl: bool=false):
	for down in [true,false]:
		var e=InputEventMouseButton.new();e.position=point;e.global_position=point;e.button_index=button;e.pressed=down;e.double_click=double;e.ctrl_pressed=ctrl;root.push_input(e,true)
func drag(from: Vector2,to: Vector2):
	var e=InputEventMouseButton.new();e.position=from;e.global_position=from;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=true;root.push_input(e,true)
	var motion=InputEventMouseMotion.new();motion.position=to;motion.global_position=to;motion.relative=to-from;motion.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(motion,true)
	e=InputEventMouseButton.new();e.position=to;e.global_position=to;e.button_index=MOUSE_BUTTON_LEFT;root.push_input(e,true)
func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-batch-capture.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false;t.field.clean_capture=true
	var r=t.rules;r.units.clear()
	r.spawn('legion','ally',Vector2(850,1100));r.spawn('legion','ally',Vector2(1150,1300));r.spawn('legion','enemy',Vector2(1850,200))
	for u in r.units:u.order='hold'
	t.set_camera(r.projection*Vector2(1000,1150)-Vector2(960,540)/t.zoom)
	t.refresh();t.start_button.pressed.emit()
	var screen=func(point: Vector2):return (r.projection*point-t.camera_offset)*t.zoom
	var report={};var trace=FileAccess.open(OUT+'frames.jsonl',FileAccess.WRITE)
	for frame in 600:
		if frame==24:click((r.Soldiers.point(r,r.units[0],4)-t.camera_offset)*t.zoom-Vector2(0,20),MOUSE_BUTTON_LEFT,false,true)
		if frame==48:
			report.selected=t.soldier_ids.size()
			click(screen.call(Vector2(1000,1200)),MOUSE_BUTTON_RIGHT)
		if frame==540:
			var settled=0;var chained=0
			for u in r.alive('ally'):
				for a in u.soldiers:
					if a.get('personal_order','')=='idle':settled+=1
					if a.get('settled_by_sibling',false):chained+=1
			report.settled=settled;report.sibling_stops=chained
		t._process(1./60)
		trace.store_line(JSON.stringify({'frame':frame,'time':r.elapsed,'units':r.alive('ally')}))
		await process_frame
		if frame in [40,120,240,540]:RenderingServer.force_draw();root.get_texture().get_image().save_png(OUT+'frame-%04d.png'%frame)
	report.time=r.elapsed
	FileAccess.open(OUT+'report.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))
	print('Batch native capture ',JSON.stringify(report))
	t.closed.emit();app.queue_free();await process_frame;quit(0 if report.selected==20 and report.settled==20 and report.sibling_stops>0 else 1)
