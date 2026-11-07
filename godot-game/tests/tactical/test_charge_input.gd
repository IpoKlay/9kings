extends SceneTree
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func click(p: Vector2,button: MouseButton=MOUSE_BUTTON_LEFT,double=false):
	for down in [true,false]:
		var e=InputEventMouseButton.new();e.position=p;e.global_position=p;e.button_index=button;e.pressed=down;e.double_click=double;root.push_input(e,true)
func key(code: Key):
	var e=InputEventKey.new();e.physical_keycode=code;e.pressed=true;root.push_input(e,true)
func screen(t,p: Vector2) -> Vector2:return (t.rules.projection*p-t.camera_offset)*t.zoom
func setup(t):
	t.retry();var r=t.rules;r.units.clear()
	r.spawn('cavalry','ally',Vector2(1000,1200));r.spawn('legion','enemy',Vector2(1010,900))
	for u in r.units:u.order='hold'
	t.set_camera(r.projection*Vector2(1050,1050)-Vector2(960,540)/t.zoom)
	t.refresh();t.start_button.pressed.emit()
	var a=r.units[0]
	click((r.Soldiers.point(r,a,3)-t.camera_offset)*t.zoom-Vector2(0,20),MOUSE_BUTTON_LEFT,true)
	return a
func snapshot(r) -> Array:
	var state=[]
	for u in r.units:
		for slot in u.soldiers.size():
			var s=u.soldiers[slot]
			state.append([s.hp,r.Soldiers.point(r,u,slot),s.get('charge_cooldown',0.),s.get('personal_order',''),s.get('charge_end',{})])
	return state
func run():
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-charge-input.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	var a=setup(t);var r=t.rules
	key(KEY_C);check(t.selected=='charge','C enters charge targeting from the normal menu battle')
	key(KEY_ESCAPE);check(t.selected=='' and not t.paused,'Escape cancels targeting without pausing')
	key(KEY_C);t.paused=true;click(screen(t,Vector2(1000,700)))
	check(a.soldiers.all(func(s):return s.has('charge_run')),'A regiment selection expands to eight individual charge orders')
	var frozen=snapshot(r);t._process(.1)
	check(snapshot(r)==frozen,'A paused charge order waits without motion, damage or cooldown')
	t.paused=false
	for frame in 20:t._process(1./60)
	key(KEY_H)
	check(a.soldiers.all(func(s):return not s.has('charge_run') and s.charge_cooldown==8.),'H cancels all eight charges and starts each cooldown once')
	key(KEY_C);check(t.selected!='charge','C cannot bypass cooling down via a fresh targeting mode')
	t.retry();check(t.rules.units.all(func(u):return u.soldiers.all(func(s):return not s.has('charge_run') and s.get('charge_cooldown',0.)==0.)),'Retry clears every individual charge and cooldown')
	var baseline=[]
	for fps in [30,60,120]:
		a=setup(t);r=t.rules
		key(KEY_C);click(screen(t,Vector2(1000,700)))
		for frame in fps*4:t._process(1./fps)
		check(a.soldiers.all(func(s):return not s.has('charge_run')),'Every rider finishes its bounded charge at '+str(fps)+' FPS')
		check(r.units[1].hp<r.units[1].max_hp,'Actual C input deals local damage at '+str(fps)+' FPS')
		if baseline.is_empty():baseline=snapshot(r)
		else:check(snapshot(r)==baseline,'Positions, damage, cooldown and stopping points match at '+str(fps)+' FPS')
	a=setup(t);key(KEY_C);click(screen(t,Vector2(1000,700)));t.slow=true
	for frame in 120:t._process(1./60)
	check(is_equal_approx(t.rules.elapsed,1.) and a.soldiers.any(func(s):return s.has('charge_run')),'Half speed advances charge simulation by one second over two real seconds')
	t.closed.emit();app.queue_free();await process_frame
	print('Charge input: ',checks,' checks, ',failures,' failures');quit(1 if failures else 0)
