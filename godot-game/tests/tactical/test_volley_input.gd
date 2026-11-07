extends SceneTree
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func key(code: Key):
	var e=InputEventKey.new();e.physical_keycode=code;e.pressed=true;root.push_input(e,true)
func click(t,p: Vector2,button: MouseButton=MOUSE_BUTTON_LEFT):
	var screen: Vector2=(t.rules.projection*p-t.camera_offset)*t.zoom
	for down in [true,false]:
		var e=InputEventMouseButton.new();e.position=screen;e.global_position=screen;e.button_index=button;e.pressed=down;root.push_input(e,true)
func setup(t):
	t.retry();t.refresh();t.archer_variant_button.pressed.emit();t.combined_button.pressed.emit()
	var r=t.rules
	r.units=r.units.filter(func(u):return u.side=='ally' and u.kind=='archer')
	var a=r.units[0]
	r.spawn('legion','enemy',Vector2(1050,1240))
	for u in r.units:
		u.order='hold'
		for i in u.soldiers.size():r.Charges.detach(r,u,i);u.soldiers[i].cooldown=999.
	t.set_camera(r.projection*Vector2(1050,1530)-Vector2(960,540)/t.zoom)
	t.refresh();t.start_button.pressed.emit();t.select_regiment(0);t.refresh()
	return a
func state(r) -> Array:
	return [r.elapsed,r.units.map(func(u):return u.soldiers.map(func(s):return [s.hp,s.get('volley_cooldown',0.)])),r.volleys.duplicate(true)]
func run():
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-volley-input.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	check(t.archer_variant_button.visible,'Normal battle entry exposes persistent loadout control')
	var a=setup(t);var r=t.rules;var target=Vector2(1050,1240)
	check(a.get('archetype','')=='longbowman' and t.roster[0].text.contains('长弓'),'Loadout button changes deployed archers and roster name')
	check(t.volley_button.visible and not t.volley_button.disabled,'Selecting longbow regiment exposes ready ability button')
	key(KEY_V);check(t.selected=='volley','V enters actual targeting mode')
	key(KEY_ESCAPE);check(t.selected=='' and not t.paused,'Escape cancels targeting without pausing')
	t.volley_button.pressed.emit();check(t.selected=='volley','Persistent button enters the same targeting mode')
	click(t,target,MOUSE_BUTTON_RIGHT);check(t.selected=='' and r.volleys.is_empty(),'Right click cancels without firing')
	key(KEY_V);t.paused=true;click(t,target)
	check(r.volleys.is_empty() and t.selected=='volley','Paused aiming cannot spend cooldown or spawn projectiles')
	t.paused=false;click(t,target);t.refresh()
	check(r.volleys.size()==30 and t.selected=='' and t.volley_button.disabled,'Actual ground click releases exactly one volley and displays cooldown')
	var frozen=state(r);t.paused=true;t._process(.2)
	check(state(r)==frozen,'Pause freezes all ability state')
	t.paused=false;key(KEY_V);check(t.selected!='volley','Keyboard cannot bypass cooling-down button')
	app.language='en';t.refresh()
	check(t.volley_button.text.contains('Volley') and t.roster[0].text.contains('Longbow'),'English labels reflect longbow variant and ability')
	app.language='zh';t.retry();t.refresh()
	check(t.rules.volleys.is_empty() and t.rules.ability_sounds.is_empty() and t.rules.archer_variant=='' and not t.volley_button.visible,'Retry resets arrows, sounds, variant choice and ability visibility')
	check(t.archer_variant_button.pressed.get_connections().size()==1 and t.volley_button.pressed.get_connections().size()==1,'Retry does not multiply fixed button signal connections')
	var baseline=[]
	for fps in [30,60,120]:
		a=setup(t);r=t.rules;key(KEY_V);click(t,target)
		for frame in fps*3:t._process(1./fps)
		check(r.volleys.is_empty() and r.units[1].hp<r.units[1].max_hp,'Volley lands through real input at '+str(fps)+' FPS')
		if baseline.is_empty():baseline=state(r)
		else:check(state(r)==baseline,'HP and cooldown match the fixed simulation at '+str(fps)+' FPS')
	a=setup(t);r=t.rules;key(KEY_V);click(t,target);t.slow=true
	for frame in 120:t._process(1./60)
	check(is_equal_approx(r.elapsed,1.) and is_equal_approx(a.soldiers[0].volley_cooldown,14.),'Half speed advances ability by one second over two real seconds')
	t.closed.emit();app.queue_free();await process_frame
	print('Volley input: ',checks,' checks, ',failures,' failures');quit(1 if failures else 0)
