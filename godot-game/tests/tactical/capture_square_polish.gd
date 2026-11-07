extends SceneTree
## Native menu, seven-arm deployment, overview and normal-speed live combat.
## Run Movie Maker at 60 FPS; -- absolute/output/path [baseline].
var failures=0
func _initialize():call_deferred('run')
func check(ok: bool,note: String):
	if not ok:failures+=1;push_error(note)
func snap(path: String):
	if DisplayServer.get_name()=='headless':return
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(path)
func widths(t) -> Array:
	var result=[]
	for u in t.rules.alive('ally'):
		var width: float=t.field.regiment_bounds(u).size.x*t.zoom
		result.append({'kind':u.kind,'figures':t.rules.config.types[u.kind].files,
			'logical_screen_width':width,'fraction_of_viewport_width':width/1920.,
			'pixels_at_1280_window':width*1280./1920.,'hp':u.hp,'max_hp':u.max_hp})
	return result
func run():
	var args=OS.get_cmdline_user_args()
	var out=args[0].trim_suffix('/')+'/' if not args.is_empty() else ProjectSettings.globalize_path('res://../output/square-polish/current/')
	var baseline=args.size()>1 and args[1]=='baseline'
	DirAccess.make_dir_recursive_absolute(out)
	var app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/tmp/eagle-square-polish-capture.cfg'
	root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit()
	var t=app.active_trial;t.set_process(false)
	t.combined_button.pressed.emit();t.refresh()
	var r=t.rules
	check(r.alive('ally').size()==7,'Seven arms deployed through the official menu')
	var initial_zoom: float=t.zoom
	var initial_offset: Vector2=t.camera_offset
	var measurements=widths(t)
	var initial_hp=r.units.map(func(u):return u.hp)
	var trace=FileAccess.open(out+'battle.jsonl',FileAccess.WRITE)
	var first_damage=-1
	for frame in 1800:
		var shot=''
		if frame==0:shot='01-default-deployment.png'
		if frame==120:
			if not baseline:t.toggle_overview()
			shot='02-overview-deployment.png'
		if frame==240:
			if not baseline:t.toggle_overview()
			check(t.zoom==initial_zoom and t.camera_offset==initial_offset,'Overview returns to the exact deployment camera')
		if frame==300:
			t.start_button.pressed.emit()
			check(t.zoom==initial_zoom and t.camera_offset==initial_offset,'Begin preserves the player camera')
			t.assault_button.pressed.emit()
		if frame==900:
			var front=r.units.filter(func(u):return u.hp>0 and u.engaged and u.kind in ['guard','legion','spear'])
			var center=Vector2.ZERO
			for u in front:center+=u.pos
			if not front.is_empty():t.set_camera(r.projection*(center/front.size())-Vector2(960,530)/t.zoom)
			shot='04-main-contact.png'
		t._process(1./60)
		if first_damage<0 and r.units.any(func(u):return u.hp<u.max_hp):
			first_damage=frame;shot='03-first-contact.png'
		if frame==1680:shot='05-normal-combat.png'
		if frame%15==0:
			trace.store_line(JSON.stringify({'frame':frame,'time':r.elapsed,'zoom':t.zoom,'offset':[t.camera_offset.x,t.camera_offset.y],
				'ally_strength':r.strength('ally'),'enemy_strength':r.strength('enemy'),
				'units':r.units.map(func(u):return {'id':u.id,'side':u.side,'kind':u.kind,'x':u.pos.x,'y':u.pos.y,'hp':u.hp,'morale':u.morale,'order':u.order})}))
		# Movie Maker must receive fresh frames even when another desktop window covers it.
		if DisplayServer.get_name()!='headless':RenderingServer.force_draw()
		await process_frame
		if not shot.is_empty():snap(out+shot)
	trace.close()
	check(r.units.any(func(u):return u.side=='ally' and u.hp<u.max_hp),'Enemy really damages the player')
	check(r.units.any(func(u):return u.side=='enemy' and u.hp<u.max_hp),'Player actually fights back')
	var summary={'frames':1800,'movie_fps':60,'simulation_seconds':r.elapsed,'default_zoom':initial_zoom,
		'default_camera':[initial_offset.x,initial_offset.y],'deployment_widths':measurements,
		'first_damage_frame':first_damage,'final_phase':r.phase,'initial_hp':initial_hp,
		'final_hp':r.units.map(func(u):return u.hp),'failures':failures}
	FileAccess.open(out+'summary.json',FileAccess.WRITE).store_string(JSON.stringify(summary,'\t'))
	print('Square polish capture: ',summary)
	t.closed.emit();app.queue_free();await process_frame
	quit(1 if failures else 0)
