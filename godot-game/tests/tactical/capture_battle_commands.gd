extends SceneTree
var failures=0
func _initialize():call_deferred('run')
func check(ok: bool,note: String):
	if not ok:failures+=1;push_error(note)
func key(code: Key):
	var e=InputEventKey.new();e.physical_keycode=code;e.pressed=true;root.push_input(e,true)
func button(p: Vector2,down: bool,double: bool=false):
	var e=InputEventMouseButton.new();e.position=p;e.global_position=p;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;e.double_click=double;root.push_input(e,true)
func screen(t,p: Vector2) -> Vector2:return (t.rules.projection*p-t.camera_offset)*t.zoom
func run():
	var args=OS.get_cmdline_user_args();var mode=args[0] if not args.is_empty() else 'shield'
	var out='res://../output/sword-banner-reference/commands/'+mode+'/'
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-command-capture.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit()
	var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	var r=t.rules;r.units.clear()
	r.spawn('legion','ally',Vector2(1050,1150) if mode=='shield' else Vector2(700,1150))
	r.spawn('archer' if mode=='shield' else 'legion','enemy',Vector2(1050,650) if mode=='shield' else Vector2(900,1150))
	var a=r.units[0];var b=r.units[1]
	if mode=='attack_move':
		# Authored one-person opposing fixture; no damage or death is injected during play.
		for slot in b.soldiers.size():
			if slot!=5:b.soldiers[slot].hp=0.
		r.Soldiers.total(b);b.visible_slots=[5]
		r.spawn('medic','enemy',Vector2(1800,300));r.spawn('legion','enemy',Vector2(1800,300))
	for u in r.units:u.order='hold';u.heading=Vector2.UP if u.side=='ally' else Vector2.DOWN;u.formation_heading=u.heading
	t.set_camera(r.projection*Vector2(1030,960)-Vector2(960,540)/t.zoom)
	t.refresh();t.start_button.pressed.emit()
	var selected_point=screen(t,a.pos)-Vector2(0,20)
	button(selected_point,true,true);button(selected_point,false,true)
	check(t.squad_ids==[a.id],'Mouse selects the real unit')
	var camera: Vector2=t.camera_offset
	var report={'mode':mode,'events':{},'failures':0}
	var starting_enemy_hp: float=b.hp
	for frame in 1080:
		if frame==20:key(KEY_F if mode=='shield' else KEY_X)
		if mode=='shield':
			if frame==40:button(screen(t,Vector2(830,900)),true)
			if frame>=41 and frame<=90:
				var e=InputEventMouseMotion.new();e.position=screen(t,Vector2(830+(frame-40)*8.8,900));e.global_position=e.position;e.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(e,true)
			if frame==91:button(screen(t,Vector2(1270,900)),false)
		else:
			if frame==40:button(screen(t,Vector2(1250,1150)),true);button(screen(t,Vector2(1250,1150)),false)
		t._process(1./60)
		if a.engaged and not report.events.has('engaged'):report.events.engaged=frame/60.
		if b.hp<starting_enemy_hp and mode=='attack_move' and not report.events.has('damage'):report.events.damage=frame/60.
		if a.order=='hold' and frame>100 and not report.events.has('arrived'):report.events.arrived=frame/60.
		await process_frame
		if frame in [75,400,900]:
			RenderingServer.force_draw();root.get_texture().get_image().save_png(out+'frame-%04d.png'%frame)
	if mode=='shield':
		check(a.get('shield_wall',false) and a.pos.distance_to(Vector2(1050,900))<.01,'Wall arrives at authored drag line')
		check(t.camera_offset==camera,'Shield placement preserves camera')
	else:
		check(report.events.has('engaged') and b.hp<=0,'Attack move fights and defeats the intervening soldier naturally')
		check(a.order=='hold' and a.pos.distance_to(Vector2(1250,1150))<.01,'Attack move resumes to the original clicked point')
	report.failures=failures;report.hp=a.hp
	FileAccess.open(out+'report.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))
	print('Command capture ',JSON.stringify(report))
	t.closed.emit();app.queue_free();await process_frame;quit(1 if failures else 0)
