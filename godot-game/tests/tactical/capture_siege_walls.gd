extends SceneTree
var failures=0
func check(ok: bool,note: String):
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func click_ground(t,ground: Vector2):
	var point=(t.rules.projection*ground-t.camera_offset)*t.zoom
	check(Rect2(0,90,1920,720).has_point(point),'Command point is visibly inside the battlefield, away from HUD')
	for pressed in [true,false]:
		var e=InputEventMouseButton.new();e.position=point;e.global_position=point;e.button_index=MOUSE_BUTTON_RIGHT;e.pressed=pressed
		root.push_input(e,true)
func run():
	var args=OS.get_cmdline_user_args();var fps=int(args[0]) if not args.is_empty() else 60
	var controls=not 'normal' in args
	var out='res://../output/sword-banner-reference/siege-walls/fps-%d/'%fps
	if not controls:out='res://../output/sword-banner-reference/siege-walls/normal/'
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-siege-capture.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	t.siege_button.pressed.emit();var r=t.rules;var wall=r.structures[3]
	var engine=r.alive('ally').filter(func(u):return u.kind=='siege')[0]
	var infantry=r.alive('ally').filter(func(u):return u.kind=='legion')[0]
	var changes=[];var last_hits=0;var order_time=-1.;var breach=-1.;var passed=-1.;var snapshots=[]
	var trace=FileAccess.open(out+'frames.jsonl',FileAccess.WRITE)
	for frame in fps*24:
		if frame==fps:
			t.start_button.pressed.emit();t.squad_ids=[engine.id];t.selected=''
			click_ground(t,Vector2(1050,900))
			check(engine.soldiers.all(func(s):return s.get('personal_order','')=='bombard'),'Right-click accepted by all engines')
		if controls:
			if frame==fps*3:t.get_node('BattleHUD/TopActions/PauseButton').pressed.emit()
			if frame==fps*4:t.get_node('BattleHUD/TopActions/PauseButton').pressed.emit()
			if frame in [fps*4,fps*6]:t.pace_button.pressed.emit()
		if breach>0. and order_time<0. and r.elapsed>=breach+1.:
			t.squad_ids=[infantry.id];t.soldier_ids=[];t.selected=''
			click_ground(t,Vector2(1050,770));order_time=r.elapsed
			check(infantry.soldiers.all(func(s):return s.get('personal_order','')=='move'),'Normal right-click routes infantry through the breach')
		t._process(1./fps)
		if wall.hits!=last_hits:
			changes.append({'hits':wall.hits,'sample_time':r.elapsed,'impact_time':wall.last_hit,'frame':frame})
			last_hits=wall.hits
			if wall.hits==5:breach=wall.breached_at
		if order_time>0. and passed<0. and infantry.soldiers.all(func(s):return s.get('position',Vector2(0,2000)).y<860.):passed=r.elapsed
		if frame%fps==0:trace.store_line(JSON.stringify({'frame':frame,'elapsed':r.elapsed,'wall_hits':wall.hits,'stones':r.stones,'infantry':infantry.soldiers,'engines':engine.soldiers}))
		if frame in [fps-1,fps*2,fps*10,fps*22] and DisplayServer.get_name()!='headless':
			RenderingServer.force_draw();root.get_texture().get_image().save_png(out+'frame-%04d.png'%frame);snapshots.append(frame)
		RenderingServer.force_draw();await process_frame
	trace.close()
	check(wall.hits==5 and breach>0.,'Fifth actual hit breaches wall')
	check(passed>order_time and order_time>breach,'All infantry traverse after the breach, using actual input')
	check(is_equal_approx(r.elapsed,21. if controls else 23.),'Deployment, pause and half-speed account for the observed simulation time')
	var state={'hits':r.structures.map(func(s):return s.hits),'breach':breach,'infantry':infantry.soldiers.map(func(s):return [s.hp,s.get('position',Vector2.ZERO)]),'engines':engine.soldiers.map(func(s):return [s.hp,s.get('position',Vector2.ZERO)])}
	FileAccess.open(out+'report.json',FileAccess.WRITE).store_string(JSON.stringify({'fps':fps,'failures':failures,'elapsed':r.elapsed,'changes':changes,'breach':breach,'infantry_order':order_time,'all_crossed':passed,'state':state,'snapshots':snapshots},'\t'))
	print('Siege runtime fps=',fps,' failures=',failures,' breach=',breach,' crossed=',passed)
	t.closed.emit();app.queue_free();await process_frame;quit(1 if failures else 0)
