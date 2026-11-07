extends SceneTree
var failures=0
func _initialize():call_deferred('run')
func check(ok: bool,note: String):
	if not ok:failures+=1;push_error(note)
func button(p: Vector2,down: bool,which: MouseButton=MOUSE_BUTTON_LEFT,shift=false,double=false):
	var e=InputEventMouseButton.new();e.position=p;e.global_position=p;e.button_index=which;e.pressed=down;e.shift_pressed=shift;e.double_click=double;root.push_input(e,true)
func click(p: Vector2,which: MouseButton=MOUSE_BUTTON_LEFT,shift=false,double=false):button(p,true,which,shift,double);button(p,false,which,shift,double)
func key(code: Key):
	var e=InputEventKey.new();e.physical_keycode=code;e.pressed=true;root.push_input(e,true)
func screen(t,world: Vector2) -> Vector2:return (t.rules.projection*world-t.camera_offset)*t.zoom
func foot(t,u,slot: int) -> Vector2:return (t.rules.Soldiers.point(t.rules,u,slot)-t.camera_offset)*t.zoom
func run():
	var out='res://../output/sword-banner-reference/personal/'
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-personal-capture.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	var r=t.rules;r.units.clear();r.spawn('legion','ally',Vector2(1000,1200));r.spawn('legion','enemy',Vector2(1800,400))
	for unit in r.units:unit.order='hold'
	var u=r.units[0]
	var originals=[]
	for slot in u.soldiers.size():originals.append(r.Soldiers.point(r,u,slot))
	t.set_camera(r.projection*Vector2(1050,1080)-Vector2(960,540)/t.zoom)
	t.refresh();t.start_button.pressed.emit()
	var goal: Vector2=r.projection.affine_inverse()*originals[0]+Vector2(0,-180)
	for frame in 1380:
		if frame==12:click(foot(t,u,0)-Vector2(0,20))
		if frame==30:click(screen(t,goal),MOUSE_BUTTON_RIGHT)
		if frame==230:
			check((r.projection.affine_inverse()*r.Soldiers.point(r,u,0)).distance_to(goal)<.05,'Selected soldier arrived independently')
			check(r.Soldiers.point(r,u,1)==originals[1],'Neighbour remained in its original place')
		if frame==240:click(foot(t,u,1)-Vector2(0,20),MOUSE_BUTTON_LEFT,true)
		if frame==260:key(KEY_F)
		if frame==280:button(screen(t,Vector2(1030,950)),true)
		if frame in range(281,330):
			var e=InputEventMouseMotion.new();e.position=screen(t,Vector2(1030+(frame-280)*2.8,950));e.global_position=e.position;e.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(e,true)
		if frame==330:button(screen(t,Vector2(1170,950)),false)
		if frame==760:
			check(u.soldiers[0].get('shield_wall',false) and u.soldiers[1].get('shield_wall',false),'Two selected soldiers formed their own shield line')
			check(u.soldiers[1].position.distance_to(Vector2(1086,950))<.1,'Second soldier actually reached the shield line')
			check(r.Soldiers.point(r,u,2)==originals[2],'Unselected soldiers were not pulled into the new wall')
		if frame==800:click(foot(t,u,4)-Vector2(0,20),MOUSE_BUTTON_LEFT,false,true);key(KEY_H)
		t._process(1./60)
		await process_frame
		if frame in [190,310,740,1320]:
			RenderingServer.force_draw();root.get_texture().get_image().save_png(out+'frame-%04d.png'%frame)
	check(not u.soldiers[0].has('personal_order') and not u.soldiers[1].has('personal_order'),'Whole-regiment order returns both soldiers by walking')
	FileAccess.open(out+'report.json',FileAccess.WRITE).store_string(JSON.stringify({'failures':failures,'seconds':r.elapsed,'stages':{'single_move':.5,'two_person_wall':5.5,'regroup':13.3333}},'\t'))
	print('Personal capture failures: ',failures)
	t.closed.emit();app.queue_free();await process_frame;quit(1 if failures else 0)
