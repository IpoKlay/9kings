extends SceneTree
var out='res://../output/sword-banner-reference/autonomy/full/'
func _initialize():call_deferred('run')
func run():
	if 'director' in OS.get_cmdline_user_args():out='res://../output/sword-banner-reference/director/full/'
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/tmp/eagle-autonomous-battle-capture.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit()
	var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	t.combined_button.pressed.emit();t.start_button.pressed.emit()
	t.assault_button.pressed.emit()
	t.set_camera(t.rules.projection*Vector2(1050,1100)-Vector2(960,540)/t.zoom)
	var report={'events':{},'result':'','time':0.}
	var trace=FileAccess.open(out+'frames.jsonl',FileAccess.WRITE)
	var result_frame=-1
	var captured_steps=0
	root.gui_disable_input=true;t.set_process_input(false);t.set_process_unhandled_input(false)
	for frame in 10800:
		captured_steps+=1
		if frame==240:
			t.paused=true
			t.squad_ids=[t.rules.alive('ally').filter(func(u):return u.kind=='spear')[0].id]
			t.start_button.pressed.emit()
		if frame==300:t.paused=false;t.assault_button.pressed.emit()
		t._process(1./60)
		var r=t.rules
		if frame%30==0:trace.store_line(JSON.stringify({'frame':frame,'time':r.elapsed,'aggression':r.enemy_director.aggression,'tasks':r.enemy_director.cohorts,'units':r.units.map(func(u):return {'id':u.id,'kind':u.kind,'side':u.side,'hp':u.hp,'pos':u.pos})}))
		for effect in t.field.effects:
			if effect.get('damage',0.)>0 and r.units.any(func(u):return u.kind=='cavalry' and u.id==effect.get('attacker',-1)) and not report.events.has('cavalry'):report.events.cavalry=frame/60.
			if effect.kind=='stone_impact' and not report.events.has('stone'):report.events.stone=frame/60.
		if r.phase!='battle' and result_frame<0:
			result_frame=frame;report.result=r.phase;report.time=r.elapsed
		await RenderingServer.frame_post_draw
		if frame in [30,210,900] or frame==result_frame:
			root.get_texture().get_image().save_png(out+'frame-%04d.png'%frame)
		if result_frame>=0 and frame>result_frame+90:break
	trace.close();report.director_orders=t.rules.enemy_director.orders
	t.start_button.pressed.emit();t.refresh()
	report.retry=t.rules.phase=='deploy' and t.rules.casualties.is_empty() and t.rules.stones.is_empty()
	for frame in 30:await RenderingServer.frame_post_draw
	report.director_retry=not t.rules.enemy_director.active and t.rules.enemy_director.cohorts.is_empty() and t.rules.enemy_director.orders.is_empty()
	report.capture_steps=captured_steps;report.expected_movie_frames=captured_steps+31
	FileAccess.open(out+'report.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))
	print('Autonomous full battle capture result=',report.result,' time=',report.time,' retry=',report.retry,' director_retry=',report.director_retry,' orders=',report.director_orders.size(),' events=',report.events)
	var passed=report.result in ['victory','defeat'] and report.retry and report.director_retry and report.events.has('cavalry') and report.events.has('stone')
	t.closed.emit();app.queue_free();await process_frame;quit(0 if passed else 1)
