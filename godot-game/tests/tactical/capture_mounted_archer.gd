extends SceneTree
const OUT='res://../output/sword-banner-reference/mounted-archer/runtime/'
var failures=0
func _initialize():call_deferred('run')
func click(p: Vector2,button: MouseButton=MOUSE_BUTTON_LEFT):
	for down in [true,false]:
		var e=InputEventMouseButton.new();e.position=p;e.global_position=p;e.button_index=button;e.pressed=down;root.push_input(e,true)
func snapshot(name: String):root.get_texture().get_image().save_png(OUT+name+'.png')
func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-mounted-capture.cfg';root.add_child(app)
	await RenderingServer.frame_post_draw
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	var r=t.rules
	for frame in 30:await RenderingServer.frame_post_draw
	click(t.cavalry_variant_button.get_global_rect().get_center());t.refresh()
	await RenderingServer.frame_post_draw;snapshot('loadout')
	click(t.combined_button.get_global_rect().get_center())
	r.units=r.units.filter(func(u):return u.side=='ally' and u.kind=='cavalry')
	var a=r.units[0];a.pos=Vector2(500,1200);a.heading=Vector2.RIGHT;a.formation_heading=Vector2.RIGHT
	r.spawn('guard','enemy',Vector2(1000,850));var b=r.units[1]
	for u in r.units:
		u.order='hold'
		for i in u.soldiers.size():r.Charges.detach(r,u,i);u.soldiers[i].cooldown=999. if u.side=='enemy' else 0.
	t.set_camera(r.projection*Vector2(1050,1050)-Vector2(960,540)/t.zoom)
	t.refresh();click(t.start_button.get_global_rect().get_center());t.refresh()
	var releases=[];var impacts=[];var hp: float=b.hp
	var seen={};var trace=FileAccess.open(OUT+'frames.jsonl',FileAccess.WRITE)
	for frame in 600:
		if frame==30:click(t.roster[0].get_global_rect().get_center())
		if frame==120:
			click((r.projection*Vector2(1500,1200)-t.camera_offset)*t.zoom,MOUSE_BUTTON_RIGHT)
			if not a.soldiers.all(func(s):return s.personal_order=='move'):failures+=1;push_error('Actual RMB did not move horse archers')
		if frame==121:
			root.gui_disable_input=true;t.set_process_input(false);t.set_process_unhandled_input(false)
		t._process(1./60)
		for arrow in r.volleys:
			var id='%d:%.5f'%[arrow.get('attacker_slot',-1),r.elapsed-arrow.age]
			if seen.has(id):continue
			seen[id]=true
			releases.append({'frame':frame,'slot':arrow.attacker_slot,'from':arrow.from,'speed':a.soldiers[arrow.attacker_slot].get('velocity',Vector2.ZERO).length(),'order':a.soldiers[arrow.attacker_slot].personal_order})
		if b.hp<hp:impacts.append({'frame':frame,'damage':hp-b.hp});hp=b.hp
		if frame%15==0:trace.store_line(JSON.stringify({'frame':frame,'elapsed':r.elapsed,'riders':a.soldiers,'enemy_hp':b.hp}))
		await RenderingServer.frame_post_draw
		if frame in [90,210,270,360,510]:snapshot('frame-%04d'%frame)
	trace.close()
	var moving_shots=releases.filter(func(e):return e.order=='move' and e.speed>150.)
	if moving_shots.is_empty() or impacts.is_empty():failures+=1;push_error('Native mounted firing evidence missing')
	t.retry();t.refresh()
	for frame in 30:await RenderingServer.frame_post_draw
	var clean: bool=t.rules.volleys.is_empty() and t.rules.cavalry_variant==''
	if not clean:failures+=1
	snapshot('retry')
	var report={'failures':failures,'fixture':'Normal menu/loadout/combined deployment; controlled eight mounted archers moving past ten stationary guards; enemy attacks disabled',
		'normal_speed':true,'quiet':true,'zoom':t.zoom,'releases':releases,'moving_shots':moving_shots.size(),'impacts':impacts,'final_enemy_hp':hp,'retry_clean':clean,'expected_movie_frames':664}
	FileAccess.open(OUT+'report.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))
	print('Mounted capture: shots=',releases.size(),' moving=',moving_shots.size(),' damage=',b.max_hp-hp,' failures=',failures)
	t.closed.emit();app.queue_free();await RenderingServer.frame_post_draw;quit(1 if failures else 0)
