extends SceneTree
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func key(code: Key):
	var e=InputEventKey.new();e.physical_keycode=code;e.pressed=true;root.push_input(e,true)
func click(t,p: Vector2):
	var screen: Vector2=(t.rules.projection*p-t.camera_offset)*t.zoom
	for down in [true,false]:
		var e=InputEventMouseButton.new();e.position=screen;e.global_position=screen;e.button_index=MOUSE_BUTTON_RIGHT;e.pressed=down;root.push_input(e,true)
func setup(t):
	t.retry();t.refresh();t.cavalry_variant_button.pressed.emit();t.combined_button.pressed.emit()
	var r=t.rules;r.units=r.units.filter(func(u):return u.side=='ally' and u.kind=='cavalry')
	var a=r.units[0];a.pos=Vector2(500,1200);a.heading=Vector2.RIGHT;a.formation_heading=Vector2.RIGHT
	r.spawn('guard','enemy',Vector2(1000,850))
	for u in r.units:
		u.order='hold'
		for i in u.soldiers.size():r.Charges.detach(r,u,i);u.soldiers[i].cooldown=999. if u.side=='enemy' else 0.
	t.set_camera(r.projection*Vector2(1050,1050)-Vector2(960,540)/t.zoom)
	t.refresh();t.start_button.pressed.emit();t.select_regiment(0);t.refresh();return a
func state(r) -> Array:
	return [r.elapsed,r.units.map(func(u):return u.soldiers.map(func(s):return [s.hp,s.cooldown,s.get('position',Vector2.ZERO),s.get('personal_order','')])),r.volleys.duplicate(true)]
func run():
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-mounted-input.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	check(t.cavalry_variant_button.visible,'Normal menu battle exposes mounted loadout control')
	var a=setup(t);var r=t.rules
	check(a.get('archetype','')=='mounted_archer' and t.roster[0].text.contains('骑射'),'Loadout changes actual deployment and roster identity')
	check(t.field.regiments.has('mounted_archer') and t.field.regiments.mounted_archer.ally.get_size()==Vector2(1088,512),'Native field loads dedicated 64px eight-bearing bow-and-horse atlas')
	t.selected='';key(KEY_C);check(t.selected!='charge','Real C key rejects mounted ranged variant')
	key(KEY_V);check(t.selected!='volley' and not t.volley_button.visible,'Real V key and HUD do not grant longbow ability')
	click(t,Vector2(1500,1200));check(a.soldiers.all(func(s):return s.personal_order=='move'),'Right click orders every selected horse to move')
	var start=a.soldiers.map(func(s):return s.position)
	for frame in 150:t._process(1./60)
	check(a.soldiers.all(func(s):return s.position.x>start[0].x+350.) and r.units[1].hp<r.units[1].max_hp,'Actual right-click movement continues while arrows damage enemies')
	check(r.events.is_empty(),'UI consumes projectile events without leaving duplicate audio/visual work')
	t.paused=true;var frozen=state(r);t._process(.5);check(frozen==state(r),'Pause freezes movement, bow cooldown and projectiles')
	t.paused=false;key(KEY_H)
	check(a.soldiers.all(func(s):return s.personal_order=='hold'),'H changes moving horse archers to stationary bow use')
	app.language='en';t.refresh();check(t.roster[0].text.contains('Horse archers'),'English roster identifies mounted ranged unit')
	app.language='zh';t.retry();t.refresh()
	check(t.rules.cavalry_variant=='' and t.rules.volleys.is_empty(),'Retry returns to ordinary cavalry choice and removes projectiles')
	check(t.cavalry_variant_button.pressed.get_connections().size()==1,'Retry leaves one loadout callback')
	var baseline=[]
	for fps in [30,60,120]:
		a=setup(t);r=t.rules;click(t,Vector2(1500,1200))
		for frame in fps*4:t._process(1./fps)
		check(r.units[1].hp<r.units[1].max_hp,'Mounted shooting deals damage at '+str(fps)+' FPS')
		if baseline.is_empty():baseline=state(r)
		else:check(state(r)==baseline,'Mounted positions, hits and cooldowns match at '+str(fps)+' FPS')
	a=setup(t);r=t.rules;click(t,Vector2(1500,1200));t.slow=true
	for frame in 120:t._process(1./60)
	check(is_equal_approx(r.elapsed,1.) and a.soldiers[0].position.x<700.,'Half speed keeps mounted movement and shooting on the same simulation clock')
	t.closed.emit();app.queue_free();await process_frame
	print('Mounted archer input: ',checks,' checks, ',failures,' failures');quit(1 if failures else 0)
