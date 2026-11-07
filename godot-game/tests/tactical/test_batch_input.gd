extends SceneTree
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func click(point: Vector2,button: MouseButton,ctrl: bool=false):
	for down in [true,false]:
		var e=InputEventMouseButton.new();e.position=point;e.global_position=point;e.button_index=button;e.pressed=down;e.ctrl_pressed=ctrl;root.push_input(e,true)
func digest(r):
	var people=[]
	for u in r.alive('ally'):
		for a in u.soldiers:people.append([snappedf(a.position.x,.001),snappedf(a.position.y,.001),a.personal_order,a.move_batch.id,a.get('settled_by_sibling',false)])
	return people
func run():
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-batch-input.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	var baseline=[]
	for fps in [30,60,120]:
		t.retry();var r=t.rules;r.units.clear()
		r.spawn('legion','ally',Vector2(850,1100));r.spawn('legion','ally',Vector2(1150,1300));r.spawn('legion','enemy',Vector2(1850,200))
		for u in r.units:u.order='hold'
		t.set_camera(r.projection*Vector2(1000,1150)-Vector2(960,540)/t.zoom);t.start_button.pressed.emit();t.paused=true
		click((r.Soldiers.point(r,r.units[0],4)-t.camera_offset)*t.zoom-Vector2(0,20),MOUSE_BUTTON_LEFT,true)
		click((r.projection*Vector2(1000,1200)-t.camera_offset)*t.zoom,MOUSE_BUTTON_RIGHT)
		check(t.soldier_ids.size()==20 and r.move_batch_serial==1,'Ctrl selection and real right-click create one shared batch at '+str(fps)+'fps')
		var frozen=digest(r);t._process(1./fps)
		check(digest(r)==frozen,'Paused input preserves all positions and batch ids')
		t.paused=false
		for frame in fps*6:t._process(1./fps)
		check(r.alive('ally').all(func(u):return u.soldiers.all(func(a):return a.personal_order=='idle')),'All members settle from actual input')
		if baseline.is_empty():baseline=digest(r)
		else:check(baseline==digest(r),'Batch final positions and stop causes match30fps at '+str(fps)+'fps')
	t.retry()
	check(t.rules.move_batch_serial==0 and not t.rules.units.any(func(u):return u.soldiers.any(func(a):return a.has('move_batch'))),'Retry removes batch ids and settlement flags')
	t.closed.emit();app.queue_free();await process_frame
	print('Batch input: ',checks,' checks, ',failures,' failures');quit(1 if failures else 0)
