extends SceneTree
## Visible, unforced real-time loop. No manual stepping and no MovieMaker.
var out='res://../output/combat-readability-20261109/'
var failures=0
func _initialize():call_deferred('run')
func check(ok: bool,label: String):
	if not ok:failures+=1;push_error(label)
func capture(label: String):
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out+label+'.png')
func run():
	var args=OS.get_cmdline_user_args();var tag=args[0] if not args.is_empty() else 'after'
	out+=tag+'/live/'
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	Engine.max_fps=60;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-readability-live.cfg';root.add_child(app)
	await process_frame
	var t=load('res://scenes/tactical_trial.tscn').instantiate();t.app=app;t.rules=t.WhiteboardBattle.new(false)
	app.hide();root.add_child(t);app.sound.enabled=false
	t.combined_button.pressed.emit();t.refresh();t.set_camera(Vector2(640,1060))
	await capture('deployment')
	check(root.get_texture().get_image().get_size()==Vector2i(1280,720),'Actual output is 1280x720')
	t.start_button.pressed.emit()
	check(t.rules.strength('ally')+t.rules.strength('enemy')==114,'114 actual soldiers')
	t.rules.command(t.rules.alive('ally').map(func(u):return u.id),'auto',Vector2.ZERO)
	var frame_times=[];var cpu=[];var texture_bytes=0.;var static_bytes=0.
	var charge_issued=false;var charge_seen=false
	var start=Time.get_ticks_usec();var last=start;var stalls=0;var stall_times=[]
	while t.rules.phase=='battle' and (Time.get_ticks_usec()-start)<150000000:
		if not charge_issued and t.rules.elapsed>=1.:
			var r=t.rules
			for unit in r.alive('ally'):
				if unit.kind!='cavalry':continue
				var enemies=r.alive('enemy')
				enemies.sort_custom(func(a,b):return a.pos.distance_squared_to(unit.pos)<b.pos.distance_squared_to(unit.pos))
				unit.order='hold'
				charge_issued=r.Charges.issue(r,r.Soldiers.group_members([unit]),enemies[0].pos+Vector2(0,-200.))
		charge_seen=charge_seen or t.field.effects.any(func(e):return e.get('personal_charge',false))
		await process_frame
		var now=Time.get_ticks_usec();var frame_ms=(now-last)/1000.;last=now
		frame_times.append(frame_ms);cpu.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.)
		if frame_ms>50.:stalls+=1;stall_times.append({'at':(now-start)/1000000.,'ms':frame_ms})
		texture_bytes=maxf(texture_bytes,Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))
		static_bytes=maxf(static_bytes,Performance.get_monitor(Performance.MEMORY_STATIC))
	var wall=(Time.get_ticks_usec()-start)/1000000.
	var phase=t.rules.phase;var sim=t.rules.elapsed
	check(phase in ['victory','defeat'],'Battle reaches a natural result')
	check(charge_issued and charge_seen,'Live loop includes actual individual charge contacts')
	frame_times.sort();cpu.sort()
	var sum=0.
	for value in frame_times:sum+=value
	var report={'tag':tag,'charge_issued':charge_issued,'charge_seen':charge_seen,'phase':phase,'simulation_seconds':sim,'wall_seconds':wall,'output_pixels':root.get_texture().get_image().get_size(),
		'normal_process':t.is_processing(),'slow':t.slow,'soldiers':114,'fps_cap':60,'vsync':DisplayServer.window_get_vsync_mode(),
		'mean_frame_ms':sum/maxi(1,frame_times.size()),'p95_frame_ms':frame_times[int(frame_times.size()*.95)],'stall_times':stall_times,'over_50ms':stalls,'stalls_per_minute':stalls*60./wall,
		'p95_cpu_process_ms':cpu[int(cpu.size()*.95)],'peak_texture_bytes':texture_bytes,'peak_static_bytes':static_bytes,
		'limits':['Controlled seven-arm ordinary-field fixture, not economy opening','GPU time unavailable in this compatibility renderer; texture monitor is not total VRAM','Scripted UI activation, not system mouse input']}
	await capture('result')
	t.start_button.pressed.emit();await process_frame
	check(t.rules.phase=='deploy' and t.rules.units.size()==7,'Result button retries to initial deployment')
	check(t.rules.casualties.is_empty() and t.rules.volleys.is_empty() and t.rules.stones.is_empty() and t.field.effects.is_empty(),'Retry clears battle effects and casualties')
	check(t.rules.units.all(func(u):return u.soldiers.all(func(a):return not a.has('charge_run') and not a.has('gap_until') and not a.has('rider_contact'))),'Retry clears local charge states')
	await capture('retry')
	report.failures=failures
	FileAccess.open(out+'report.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))
	print('LIVE ',JSON.stringify(report))
	t.queue_free();app.queue_free();await process_frame;await process_frame
	quit(1 if failures else 0)
