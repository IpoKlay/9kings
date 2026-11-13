extends SceneTree
func _initialize():call_deferred('run')
func stats(values: Array) -> Dictionary:
	var sorted=values.duplicate();sorted.sort();var total=0.
	for v in values:total+=v
	return {'mean_ms':total/maxi(1,values.size())/1000.,'p95_ms':sorted[mini(sorted.size()-1,int(sorted.size()*.95))]/1000.,'samples':values.size()}
func run():
	var args=OS.get_cmdline_user_args();var label=args[0] if args.size()>0 else 'before';var count=int(args[1]) if args.size()>1 else 500
	var samples=int(args[2]) if args.size()>2 else 120
	var output='res://../output/sword-banner-reference/large-battle/'+label+'-'+str(count)
	if args.size()>3:output=args[3]+'/'+label+'-'+str(count)
	var output_directory_error=DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	assert(output_directory_error==OK)
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-large-battle.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	AudioServer.set_bus_mute(0,true)
	var r=t.rules;r.units.clear();r.next_id=0
	for side in ['enemy','ally']:
		for i in count/10:
			var row=i/5;var col=i%5
			var y=1040.-row*40. if side=='enemy' else 1060.+row*40.
			r.spawn('archer' if i%5==0 else 'legion',side,Vector2(450.+col*300.,y))
	t.refresh();t.start_button.pressed.emit()
	r.command(r.alive('ally').map(func(u):return u.id),'auto',Vector2.ZERO)
	t.zoom=.55;t.set_camera(r.projection*r.bounds.get_center()-Vector2(960,530)/t.zoom)
	root.gui_disable_input=true;t.set_process_input(false);t.set_process_unhandled_input(false)
	var simulation=[];var wall=[];var state=[];var first=Time.get_ticks_usec()
	for frame in samples:
		var begin=Time.get_ticks_usec();t._process(1./60.);simulation.append(Time.get_ticks_usec()-begin)
		if DisplayServer.get_name()!='headless':
			RenderingServer.force_draw()
			if frame in [0,samples-1]:root.get_texture().get_image().save_png(output+'-'+str(frame)+'.png')
		await process_frame
		wall.append(Time.get_ticks_usec()-begin)
	for u in r.units:
		for i in u.soldiers.size():
			var a=u.soldiers[i];state.append([u.id,i,a.hp,a.cooldown,a.get('target_id',-1),a.get('target_slot',-1),r.Soldiers.ground_position(r,u,i),a.get('personal_order','')])
	var report={'label':label,'people_per_side':count,'samples':samples,'simulation':stats(simulation),'wall_clock':stats(wall),'elapsed_real':(Time.get_ticks_usec()-first)/1000000.,'elapsed_simulation':r.elapsed,'phase':r.phase,'alive':{'ally':r.strength('ally'),'enemy':r.strength('enemy')},'state':state,'rendered':DisplayServer.get_name()!='headless','timing_scope':'Fixed60Hz combat input. Process timing includes rules/UI; wall-clock includes await render and OS scheduling, not an isolated GPU measure. Setup is20%archers/80%infantry, custom dense1000-person fixture, not source siegeAI.'}
	FileAccess.open(output+'.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))
	# Preserve native Vector2 and float precision; JSON display strings round positions.
	FileAccess.open(output+'.state',FileAccess.WRITE).store_var({'units':r.units,'repulsion_seed':r.repulsion_seed,'repulsion_time':r.repulsion_time,'elapsed':r.elapsed,'phase':r.phase})
	print('Large battle ',label,' ',count,'/side process=',report.simulation,' wall=',report.wall_clock)
	t.closed.emit();app.queue_free();await process_frame;quit()
