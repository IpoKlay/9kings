extends SceneTree
var failures=0
func _initialize():call_deferred('run')
func click(p: Vector2,double=false):
	for down in [true,false]:
		var e=InputEventMouseButton.new();e.position=p;e.global_position=p;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;e.double_click=double;root.push_input(e,true)
func run():
	var args=OS.get_cmdline_user_args();var mode=args[0] if args.size()>0 else 'side'
	var out='res://../output/sword-banner-reference/charge/'+mode+'/'
	if 'physics' in args:out='res://../output/sword-banner-reference/physics/'+mode+'/'
	if 'ground' in args:out='res://../output/sword-banner-reference/ground-combat/'+mode+'/'
	if 'timing' in args:out='res://../output/sword-banner-reference/attack-timing/'+mode+'/'
	if 'integration' in args:out='res://../output/sword-banner-reference/integration/'+mode+'/'
	if 'entry' in args:out='res://../output/sword-banner-reference/state-entry/'+mode+'/'
	if 'scan' in args:out='res://../output/sword-banner-reference/acquisition/'+mode+'/'
	if 'director' in args:out='res://../output/sword-banner-reference/director/'+mode+'/'
	if 'volley' in args:out='res://../output/sword-banner-reference/volley/'+mode+'/'
	if 'mounted' in args:out='res://../output/sword-banner-reference/mounted-archer/'+mode+'/'
	if 'retaliation' in args:out='res://../output/sword-banner-reference/retaliation/'+mode+'/'
	if 'retarget' in args:out='res://../output/sword-banner-reference/retarget/'+mode+'/'
	if 'human' in args:out='res://../output/sword-banner-reference/human-roster/'+mode+'/'
	if 'wraith' in args:out='res://../output/sword-banner-reference/wraith/'+mode+'/'
	if 'undead' in args:out='res://../output/sword-banner-reference/undead-roster/'+mode+'/'
	if 'goblin' in args:out='res://../output/sword-banner-reference/goblin-roster/'+mode+'/'
	if 'dragon' in args:out='res://../output/sword-banner-reference/dragon/'+mode+'/'
	if 'corpse-motion' in args:out='res://../output/sword-banner-reference/corpse-motion/'+mode+'/'
	if 'death-motion' in args:out='res://../output/sword-banner-reference/death-motion/'+mode+'/'
	if 'terminal' in args:out='res://../output/sword-banner-reference/terminal-attacks/'+mode+'/'
	if 'death' in args:out='res://../output/sword-banner-reference/death-lifecycle/'+mode+'/'
	if 'projectile' in args:out='res://../output/sword-banner-reference/projectile-motion/'+mode+'/'
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var frame_export='frames' in args
	if frame_export:DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out+'render/'))
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-charge-capture.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false;t.field.clean_capture=true
	var r=t.rules;r.units.clear()
	var center=Vector2(1050,900)
	var axis=Vector2(-.94,-.342).normalized() if mode=='side' else Vector2.UP
	r.spawn('legion' if mode in ['side','infantry'] else 'guard' if mode=='shield' else 'spear','enemy',center)
	r.spawn('legion' if mode=='infantry' else 'cavalry','ally',center-axis*440)
	var b=r.units[0];var a=r.units[1]
	b.heading=Vector2.UP if mode=='side' else Vector2.DOWN;b.formation_heading=b.heading;b.order='hold'
	a.heading=axis;a.formation_heading=axis;a.order='hold'
	if mode in ['shield','pikes']:
		for slot in b.soldiers.size():
			r.Charges.detach(r,b,slot);b.soldiers[slot].shield_wall=true;b.soldiers[slot].wall_heading=b.heading;b.soldiers[slot].heading=b.heading
	t.set_camera(r.projection*(center-axis*150)-Vector2(960,540)/t.zoom)
	t.refresh();t.start_button.pressed.emit()
	var records=[];var first=-1
	var trace=FileAccess.open(out+'frames.jsonl',FileAccess.WRITE)
	if trace==null:push_error('Cannot open capture trace: '+out);quit(1);return
	for frame in 600:
		if frame==24:click((r.Soldiers.point(r,a,3)-t.camera_offset)*t.zoom-Vector2(0,20),true)
		if frame==48:
			var e=InputEventKey.new();e.physical_keycode=KEY_C;e.pressed=true;root.push_input(e,true)
			click((r.projection*(center+axis*140)-t.camera_offset)*t.zoom)
			if not a.soldiers.all(func(s):return s.has('charge_run')):failures+=1;push_error('C input failed to charge all selected people')
		if frame==49:
			# The order was entered through the real UI; isolate the remaining fixed recording from desktop input.
			root.gui_disable_input=true;t.set_process_input(false);t.set_process_unhandled_input(false)
		t._process(1./60)
		for event in t.field.effects:
			if event.get('personal_charge',false) and event.age==0:
				if first<0:first=frame
				records.append({'frame':frame,'attacker_slot':event.attacker_slot,'target_slot':event.target_slot,'damage':event.damage,'speed_fraction':event.speed_fraction})
		t.field.effects.clear()
		trace.store_line(JSON.stringify({'frame':frame,'time':r.elapsed,'a':a.soldiers,'b':b.soldiers}))
		if frame_export:
			RenderingServer.force_draw();root.get_texture().get_image().save_png(out+'render/%04d.png'%frame)
		await process_frame
		if frame==40 or (first>=0 and frame in [first,first+10,first+60,first+150]):
			RenderingServer.force_draw();root.get_texture().get_image().save_png(out+'frame-%04d.png'%frame)
	trace.close()
	if records.is_empty():failures+=1;push_error('No personal charge contact was recorded')
	var ends=[]
	for actor in a.soldiers:ends.append(actor.get('charge_end',{}))
	FileAccess.open(out+'report.json',FileAccess.WRITE).store_string(JSON.stringify({'scenario':mode,'failures':failures,'first_frame':first,'contacts':records,'stops':ends,'zoom':t.zoom,'duration':10.,'normal_speed':true,'quiet':true},'\t'))
	print('Charge capture ',mode,': ',records.size(),' contacts, failures=',failures)
	t.closed.emit();app.queue_free();await process_frame;quit(1 if failures else 0)
