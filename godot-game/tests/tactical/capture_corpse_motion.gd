extends SceneTree
var failures=0
func _initialize():call_deferred('run')
func click(point:Vector2,double=false):
	for down in [true,false]:
		var e=InputEventMouseButton.new();e.position=point;e.global_position=point;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;e.double_click=double;root.push_input(e,true)
func run():
	var before='before' in OS.get_cmdline_user_args()
	var out='/Users/ip/Documents/ChatGPT/9kings/output/sword-banner-reference/corpse-motion/'+('before-runtime/' if before else 'runtime/')
	DirAccess.make_dir_recursive_absolute(out)
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-death-motion-capture.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false;t.field.clean_capture=true
	var r=t.rules;r.units.clear();var center=Vector2(1050,900);var axis=Vector2(-.94,-.342).normalized()
	r.spawn('legion','enemy',center);r.spawn('cavalry','ally',center-axis*440)
	var b=r.units[0];var a=r.units[1];b.heading=Vector2.UP;b.formation_heading=b.heading;b.order='hold'
	for actor in b.soldiers:actor.hp=1.
	r.Soldiers.total(b);a.heading=axis;a.formation_heading=axis;a.order='hold'
	t.set_camera(r.projection*(center-axis*150)-Vector2(960,540)/t.zoom);t.refresh();t.start_button.pressed.emit()
	var death_frames={};var body_frames={};var seen={};var first_death=-1;var first_body=-1;var max_shift=0.;var contacts=0
	var trace=FileAccess.open(out+'frames.jsonl',FileAccess.WRITE)
	for frame in 360:
		if frame==24:click((r.Soldiers.point(r,a,3)-t.camera_offset)*t.zoom-Vector2(0,20),true)
		if frame==48:
			var e=InputEventKey.new();e.physical_keycode=KEY_C;e.pressed=true;root.push_input(e,true)
			click((r.projection*(center+axis*140)-t.camera_offset)*t.zoom)
			if not a.soldiers.all(func(s):return s.has('charge_run')):failures+=1;push_error('Real C input failed')
		if frame==49:root.gui_disable_input=true;t.set_process_input(false);t.set_process_unhandled_input(false)
		t._process(1./60)
		for e in t.field.effects:
			if e.get('personal_charge',false) and e.age==0:contacts+=1
		for slot in b.soldiers.size():
			if b.soldiers[slot].hp<=0 and not death_frames.has(slot):
				death_frames[slot]={'frame':frame,'point':r.projection*r.Soldiers.ground_position(r,b,slot)}
				if first_death<0:first_death=frame
		for body in r.casualties:
			if body.unit_id!=b.id or seen.has(body.id):continue
			seen[body.id]=true;body_frames[body.slot]={'frame':frame,'foot':body.foot,'time':body.time}
			if first_body<0:first_body=frame
			if death_frames.has(body.slot):max_shift=maxf(max_shift,body.foot.distance_to(death_frames[body.slot].point))
		t.field.effects.clear()
		trace.store_line(JSON.stringify({'frame':frame,'time':r.elapsed,'phase':r.phase,'defenders':b.soldiers,'bodies':r.casualties}))
		RenderingServer.force_draw();await process_frame
		if frame==40 or frame==first_death or frame==first_body or frame==first_body+1 or frame in [130,140,160,180,210,250,300,359]:
			RenderingServer.force_draw();root.get_texture().get_image().save_png(out+'frame-%04d.png'%frame)
	trace.close()
	var correct=first_body==first_death+1 and max_shift>5.
	if first_death<0 or not correct or contacts==0:failures+=1;push_error('Corpse timing/position comparison failed')
	t.retry();t.refresh();var clean=t.rules.casualties.is_empty() and t.rules.units.all(func(u):return u.soldiers.all(func(s):return s.death_state==0))
	if not clean:failures+=1
	FileAccess.open(out+'report.json',FileAccess.WRITE).store_string(JSON.stringify({'failures':failures,'before':before,'fixture':'Normal main-menu entry;10 infantry explicitly wounded to1HP to exercise lethal charge.8 cavalry use actual selection and C click, ordinary charge speed/damage, default zoom, muted, hidden bars/particles. Local before/after, not original-game footage.','first_death_frame':first_death,'first_body_frame':first_body,'max_post_lethal_shift':max_shift,'death_frames':death_frames,'body_frames':body_frames,'contacts':contacts,'retry_clean':clean,'zoom':t.zoom},'\t'))
	print('Death motion capture: death=',first_death,' body=',first_body,' shift=',max_shift,' failures=',failures)
	t.closed.emit();app.queue_free();await process_frame;quit(1 if failures else 0)
