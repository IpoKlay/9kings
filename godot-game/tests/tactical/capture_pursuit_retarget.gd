extends SceneTree
const OUT='res://../output/sword-banner-reference/retarget/runtime/'
var failures=0
func _initialize():call_deferred('run')
func click(p: Vector2,button: MouseButton=MOUSE_BUTTON_LEFT):
	for down in [true,false]:
		var e=InputEventMouseButton.new();e.position=p;e.global_position=p;e.button_index=button;e.pressed=down;root.push_input(e,true)
func foot(t,u):return (t.rules.Soldiers.point(t.rules,u,0)-t.camera_offset)*t.zoom-Vector2(0,20)
func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-retarget-capture.cfg';root.add_child(app)
	await RenderingServer.frame_post_draw
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	var r=t.rules;r.units.clear();r.config.types.legion.files=1;r.config.types.legion.hp=100.
	r.spawn('legion','ally',Vector2(900,1400));r.spawn('legion','enemy',Vector2(900,750));r.spawn('legion','enemy',Vector2(965,1100))
	for u in r.units:
		u.order='hold'
		for i in u.soldiers.size():
			r.Charges.detach(r,u,i);var s=u.soldiers[i];s.position=u.pos;s.hp=s.max_hp if i==0 else 0.;s.cooldown=999. if u.side=='enemy' else 0.
		r.Soldiers.total(u)
	var a=r.units[0];var far=r.units[1];var near=r.units[2];var actor=a.soldiers[0]
	t.set_camera(r.projection*Vector2(1050,1050)-Vector2(960,540)/t.zoom)
	t.refresh();click(t.start_button.get_global_rect().get_center());r.enemy_director.active=false;t.refresh()
	var changes=[];var previous=-1;var first=-1
	var trace=FileAccess.open(OUT+'frames.jsonl',FileAccess.WRITE)
	for frame in 600:
		if frame==30:click(foot(t,a))
		if frame==60:
			click(foot(t,far),MOUSE_BUTTON_RIGHT)
			if actor.personal_order!='attack' or actor.focus_id!=far.id:failures+=1;push_error('Actual RMB did not explicitly focus distant soldier')
		if frame==61:root.gui_disable_input=true;t.set_process_input(false);t.set_process_unhandled_input(false)
		t._process(1./60)
		if actor.target_id!=previous:
			changes.append({'frame':frame,'target':actor.target_id,'position':actor.position,'velocity':actor.velocity,'timer':actor.retarget_timer})
			previous=actor.target_id
			if actor.target_id==near.id and first<0:first=frame
		trace.store_line(JSON.stringify({'frame':frame,'time':r.elapsed,'actor':actor,'near_hp':near.hp,'far_hp':far.hp}))
		await RenderingServer.frame_post_draw
		if frame in [90,210,360,510] or frame==first:root.get_texture().get_image().save_png(OUT+'frame-%04d.png'%frame)
	trace.close()
	if first<0 or near.hp>=near.soldiers[0].max_hp or far.hp!=far.soldiers[0].max_hp:failures+=1;push_error('Expected close-target switch and damage missing')
	t.retry();t.refresh()
	for frame in 30:await RenderingServer.frame_post_draw
	var clean: bool=t.rules.units.all(func(u):return u.soldiers.all(func(s):return s.target_id==-1 and s.retarget_timer>=0. and s.retarget_timer<=.15))
	if not clean:failures+=1
	FileAccess.open(OUT+'report.json',FileAccess.WRITE).store_string(JSON.stringify({'failures':failures,'fixture':'Normal menu, one player swordsman explicitly RMB focuses distant enemy; one nearer enemy stands beside pursuit route; enemy director and attacks disabled to isolate retargeting.', 'changes':changes,'first_retarget_frame':first,'near_final_hp':near.hp,'far_final_hp':far.hp,'retry_clean':clean,'expected_movie_frames':633,'normal_speed':true,'quiet':true},'\t'))
	print('Retarget capture: switch=',first,' near_hp=',near.hp,' far_hp=',far.hp,' failures=',failures)
	t.closed.emit();app.queue_free();await RenderingServer.frame_post_draw;quit(1 if failures else 0)
