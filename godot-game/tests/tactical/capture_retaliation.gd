extends SceneTree
const OUT='res://../output/sword-banner-reference/retaliation/runtime/'
var failures=0
func _initialize():call_deferred('run')
func click(p: Vector2,button: MouseButton=MOUSE_BUTTON_LEFT):
	for down in [true,false]:
		var e=InputEventMouseButton.new();e.position=p;e.global_position=p;e.button_index=button;e.pressed=down;root.push_input(e,true)
func snapshot(name: String):root.get_texture().get_image().save_png(OUT+name+'.png')
func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-retaliation-capture.cfg';root.add_child(app)
	await RenderingServer.frame_post_draw
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	var r=t.rules;r.units.clear()
	for x in [650.,1450.]:r.spawn('legion','ally',Vector2(x,1200));r.spawn('archer','enemy',Vector2(x,850))
	for u in r.units:
		u.order='hold'
		for slot in u.soldiers.size():
			r.Charges.detach(r,u,slot);u.soldiers[slot].cooldown=2. if u.side=='enemy' else 0.
	t.set_camera(r.projection*Vector2(1050,1050)-Vector2(960,540)/t.zoom)
	t.refresh();click(t.start_button.get_global_rect().get_center());t.refresh()
	var mover=r.units[0];var holder=r.units[2];var prior_hp={};var changes=[];var first=-1
	for u in [mover,holder]:prior_hp[u.id]=u.hp
	var trace=FileAccess.open(OUT+'frames.jsonl',FileAccess.WRITE)
	for frame in 600:
		if frame==30:click(t.roster[0].get_global_rect().get_center())
		if frame==60:
			click((r.projection*Vector2(1000,1200)-t.camera_offset)*t.zoom,MOUSE_BUTTON_RIGHT)
			if not mover.soldiers.all(func(s):return s.personal_order=='move'):failures+=1;push_error('RMB moving order missing')
		if frame==61:root.gui_disable_input=true;t.set_process_input(false);t.set_process_unhandled_input(false)
		t._process(1./60)
		for u in [mover,holder]:
			if u.hp<prior_hp[u.id]:
				if first<0:first=frame
				changes.append({'frame':frame,'unit':u.id,'damage':prior_hp[u.id]-u.hp,'orders':u.soldiers.map(func(s):return s.personal_order),'targets':u.soldiers.map(func(s):return s.target_id)})
			prior_hp[u.id]=u.hp
		if frame%10==0:trace.store_line(JSON.stringify({'frame':frame,'time':r.elapsed,'movers':mover.soldiers,'holders':holder.soldiers}))
		await RenderingServer.frame_post_draw
		if frame in [90,240,360,510]:snapshot('frame-%04d'%frame)
	trace.close()
	var chased: bool=mover.soldiers.any(func(s):return s.get('last_attacker',Vector2i(-1,-1)).x==r.units[1].id and s.position.y<1100.)
	var held: bool=holder.soldiers.all(func(s):return s.personal_order=='hold')
	if not chased or not held:failures+=1;push_error('Retaliation movement/hold comparison failed')
	t.retry();t.refresh()
	for frame in 30:await RenderingServer.frame_post_draw
	var clean: bool=t.rules.units.all(func(u):return u.soldiers.all(func(s):return not s.has('last_attacker') and not s.has('resume_attack_move')))
	if not clean:failures+=1
	FileAccess.open(OUT+'report.json',FileAccess.WRITE).store_string(JSON.stringify({'failures':failures,'fixture':'Left infantry: actual RMB move; right infantry: H. Two stationary archer squads shoot both. Normal menu entry, controlled starting positions/cooldowns.', 'first_hit_frame':first,'changes':changes,'moving_infantry_chased':chased,'holding_infantry_held':held,'retry_clean':clean,'expected_movie_frames':633,'normal_speed':true,'quiet':true},'\t'))
	print('Retaliation capture: first=',first,' chased=',chased,' held=',held,' failures=',failures)
	t.closed.emit();app.queue_free();await RenderingServer.frame_post_draw;quit(1 if failures else 0)
