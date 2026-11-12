extends SceneTree
func _initialize():call_deferred('run')
func run():
	var args=OS.get_cmdline_user_args();var label=args[0] if not args.is_empty() else 'live'
	var out=args[1] if args.size()>1 else ProjectSettings.globalize_path('res://../output/sword-banner-reference/large-battle')
	var output_directory_error=DirAccess.make_dir_recursive_absolute(out)
	assert(output_directory_error==OK)
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-large-live.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	AudioServer.set_bus_mute(0,true)
	var r=t.rules;r.units.clear();r.next_id=0
	for side in ['enemy','ally']:
		for i in 50:
			var row=i/5;var col=i%5
			var y=1040.-row*40. if side=='enemy' else 1060.+row*40.
			r.spawn('archer' if i%5==0 else 'legion',side,Vector2(450.+col*300.,y))
	t.refresh();t.start_button.pressed.emit();r.command(r.alive('ally').map(func(u):return u.id),'auto',Vector2.ZERO)
	t.zoom=.55;t.set_camera(r.projection*r.bounds.get_center()-Vector2(960,530)/t.zoom)
	root.gui_disable_input=true;t.set_process_input(false);t.set_process_unhandled_input(false)
	await process_frame
	var start=Time.get_ticks_usec();var previous=start;var samples=[]
	t.set_process(true)
	while Time.get_ticks_usec()-start<10000000:
		await process_frame
		var now=Time.get_ticks_usec();samples.append((now-previous)/1000.);previous=now
	t.set_process(false)
	var duration=(Time.get_ticks_usec()-start)/1000000.
	var sorted=samples.duplicate();sorted.sort();var total=0.
	for value in samples:total+=value
	var report={'label':label,'live_production_process':true,'rendered':DisplayServer.get_name()!='headless','people_per_side':500,'frames':samples.size(),'real_seconds':duration,'simulation_seconds':r.elapsed,'mean_frame_ms':total/samples.size(),'p95_frame_ms':sorted[mini(sorted.size()-1,int(sorted.size()*.95))],'frame_ms':samples,'mean_observed_fps':samples.size()/duration,'scope':'Actual engine-driven trial._process(delta), unmodified accumulator and0.1s delta cap; no fixed-fps or movie recording. Ten wall-clock seconds. Outcomes differ with elapsed simulation; use fixed-step benchmark for correctness equivalence.'}
	RenderingServer.force_draw();root.get_texture().get_image().save_png(out+'/'+label+'.png')
	FileAccess.open(out+'/'+label+'.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))
	print('LIVE ',label,' frames=',samples.size(),' mean=',report.mean_frame_ms,' p95=',report.p95_frame_ms,' sim=',r.elapsed,' real=',duration)
	t.closed.emit();app.queue_free();await process_frame;quit()
