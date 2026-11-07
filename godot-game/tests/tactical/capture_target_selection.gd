extends SceneTree
var out='res://../output/sword-banner-reference/target-selection/'
func _initialize():call_deferred('run')
func run():
	var mode='spear' if '--archer' not in OS.get_cmdline_user_args() else 'archer'
	if 'scan' in OS.get_cmdline_user_args():out='res://../output/sword-banner-reference/acquisition/'
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-target-capture.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false;t.field.clean_capture=true
	var r=t.rules;r.units.clear()
	r.spawn(mode,'ally',Vector2(1000,1300));r.spawn('legion','enemy',Vector2(1000,1150 if mode=='spear' else 1000))
	if mode=='spear':r.spawn('cavalry','enemy',Vector2(1320,1020))
	for u in r.units:u.order='hold'
	t.set_camera(r.projection*Vector2(1100,1140)-Vector2(960,540)/t.zoom)
	t.refresh();t.start_button.pressed.emit()
	var a=r.units[0]
	for u in r.units:
		for i in u.soldiers.size():u.soldiers[i].position=u.pos+Vector2((i-(u.soldiers.size()-1)*.5)*25.,0.)
	if 'scan' in OS.get_cmdline_user_args():
		for u in r.units:
			for i in u.soldiers.size():
				r.Charges.detach(r,u,i);u.soldiers[i].personal_order='hold';u.soldiers[i].cooldown=60.
	# Keep the defenders holding so the acquired destination stays legible.
	for u in r.units:
		if u.side=='enemy':
			for s in u.soldiers:s.cooldown=60.
	var report={'mode':mode,'first_targets':[],'acquired':[]};var seen={};var trace=FileAccess.open(out+mode+'-frames.jsonl',FileAccess.WRITE)
	for frame in 480:
		if frame==60:
			if 'scan' in OS.get_cmdline_user_args():
				for s in a.soldiers:s.cooldown=0.
			r.command([a.id],'auto',Vector2.ZERO)
		t._process(1./60)
		for i in a.soldiers.size():
			var s=a.soldiers[i]
			if frame>=60 and s.target_id>=0 and not seen.has(i):
				seen[i]=true;report.acquired.append({'slot':i,'frame':frame,'target':s.target_id,'target_slot':s.target_slot})
		if frame==61:
			for s in a.soldiers:report.first_targets.append([s.target_id,s.target_slot])
		trace.store_line(JSON.stringify({'frame':frame,'time':r.elapsed,'units':r.units.map(func(u):return {'id':u.id,'kind':u.kind,'soldiers':u.soldiers})}))
		await process_frame
		if frame in [59,90,240,479]:RenderingServer.force_draw();root.get_texture().get_image().save_png(out+mode+'-%04d.png'%frame)
	report.final_time=r.elapsed;report.final_hp=r.units.map(func(u):return {'kind':u.kind,'hp':u.hp})
	FileAccess.open(out+mode+'-report.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))
	print('Target selection native capture ',JSON.stringify(report))
	t.closed.emit();app.queue_free();await process_frame;quit()
