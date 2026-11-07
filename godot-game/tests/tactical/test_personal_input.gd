extends SceneTree
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func click(p: Vector2,button: MouseButton=MOUSE_BUTTON_LEFT,shift=false,ctrl=false,double=false):
	for down in [true,false]:
		var e=InputEventMouseButton.new();e.position=p;e.global_position=p;e.button_index=button;e.pressed=down;e.shift_pressed=shift;e.ctrl_pressed=ctrl;e.double_click=double;root.push_input(e,true)
func key(code: Key):
	var e=InputEventKey.new();e.physical_keycode=code;e.pressed=true;root.push_input(e,true)
func foot(t,u,slot: int) -> Vector2:return (t.rules.Soldiers.point(t.rules,u,slot)-t.camera_offset)*t.zoom
func run():
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-personal-input.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	var r=t.rules;r.units.clear();r.spawn('legion','ally',Vector2(1000,1200));r.spawn('legion','enemy',Vector2(1800,400))
	for u in r.units:u.order='hold'
	var u=r.units[0];t.start_button.pressed.emit()
	t.set_camera(r.projection*Vector2(1050,1050)-Vector2(960,540)/t.zoom)
	click(foot(t,u,0)-Vector2(0,20))
	check(t.soldier_ids==[Vector2i(u.id,0)] and t.squad_ids.is_empty(),'Normal click selects one real soldier')
	var old=r.projection.affine_inverse()*r.Soldiers.point(r,u,0)
	var neighbour=r.Soldiers.point(r,u,1)
	var goal: Vector2=old+Vector2(0,-150)
	t.paused=true
	click((r.projection*goal-t.camera_offset)*t.zoom,MOUSE_BUTTON_RIGHT)
	check(u.soldiers[0].personal_order=='move','Right click sends the personal move order')
	t._process(.1)
	check((r.projection.affine_inverse()*r.Soldiers.point(r,u,0)).distance_to(old)<.01,'Paused personal input does not move the soldier')
	t.paused=false
	for tick in 160:t._process(1./60)
	check((r.projection.affine_inverse()*r.Soldiers.point(r,u,0)).distance_to(goal)<17.,'Actual input moves the chosen soldier to the destination')
	check(r.Soldiers.point(r,u,1)==neighbour,'Neighbour does not inherit the individual order')
	click(foot(t,u,0)-Vector2(0,20))
	check(t.soldier_ids==[Vector2i(u.id,0)],'Moved soldier is selectable at the new rendered position')
	click(foot(t,u,1)-Vector2(0,20),MOUSE_BUTTON_LEFT,true)
	check(t.soldier_ids.size()==2,'Shift click adds a second person')
	click(foot(t,u,2)-Vector2(0,20),MOUSE_BUTTON_LEFT,false,true)
	check(t.soldier_ids.size()==10,'Ctrl click selects every living soldier of the same kind')
	click(foot(t,u,2)-Vector2(0,20),MOUSE_BUTTON_LEFT,false,false,true)
	check(t.soldier_ids.is_empty() and t.squad_ids==[u.id],'Double click retains the existing regiment command workflow')
	key(KEY_H)
	check(u.soldiers[0].personal_order=='hold','Whole-regiment hold keeps the detached soldier at its actual position')
	for tick in 160:t._process(1./60)
	check(u.soldiers[0].position.distance_to(goal)<17.,'Holding never silently reforms the previous row')
	click(foot(t,u,0)-Vector2(0,20))
	key(KEY_X);click((r.projection*(old+Vector2(0,-100))-t.camera_offset)*t.zoom)
	check(u.soldiers[0].personal_order=='attack_move' and u.order=='hold','X applies only to selected soldier, leaving the group order unchanged')
	t.retry()
	check(t.soldier_ids.is_empty() and not t.rules.units.any(func(v):return v.get('personalized',false)),'Retry discards all personal selection and position state')
	var baseline=[]
	for fps in [30,60,120]:
		t.retry();r=t.rules;r.units.clear()
		r.spawn('legion','ally',Vector2(1000,1200));r.spawn('legion','enemy',Vector2(1800,400))
		for v in r.units:v.order='hold'
		u=r.units[0];r.start()
		var origin: Vector2=r.projection.affine_inverse()*r.Soldiers.point(r,u,0)
		r.Soldiers.command(r,[Vector2i(u.id,0),Vector2i(u.id,1)],'move',origin+Vector2(0,-350))
		for frame in fps*4:t._process(1./fps)
		var snapshot=[]
		for slot in 2:snapshot.append([r.Soldiers.point(r,u,slot),u.soldiers[slot].personal_order,u.soldiers[slot].hp])
		if baseline.is_empty():baseline=snapshot
		else:check(snapshot==baseline,'Personal movement is identical at '+str(fps)+' render FPS')
	t.closed.emit();app.queue_free();await process_frame
	print('Personal input: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)
