extends SceneTree
var t
var r
var app
func _initialize():call_deferred('run')
func click(pos: Vector2,button=MOUSE_BUTTON_LEFT,shift=false):
	for down in [true,false]:
		var e=InputEventMouseButton.new()
		e.position=pos;e.global_position=pos;e.button_index=button;e.pressed=down;e.shift_pressed=shift
		root.push_input(e,true)
func key(code:Key):
	var e=InputEventKey.new()
	e.physical_keycode=code;e.pressed=true
	root.push_input(e,true)
func screen(world:Vector2) -> Vector2:return (r.projection*world-t.camera_offset)*t.zoom
func run():
	app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/tmp/eagle-breach-match.cfg'
	root.add_child(app)
	app.language='zh';app.render_ui()
	await process_frame
	if 'film' in OS.get_cmdline_user_args():
		for frame in 24:await process_frame
	click(app.menu_view.get_node('TacticalTrial').get_global_rect().get_center())
	await process_frame
	t=app.active_trial;t.set_process(false);r=t.rules
	click(t.combined_button.get_global_rect().get_center())
	t.refresh()
	if 'film' in OS.get_cmdline_user_args():
		for frame in 30:await process_frame
	click(t.start_button.get_global_rect().get_center())
	var horse:Dictionary=r.alive('ally').filter(func(u):return u.kind=='cavalry')[0]
	var events={};var flank=false;var wall=false;var focus=false
	var journal=[]
	var args=OS.get_cmdline_user_args()
	var filming='film' in args
	var ticks=0
	while r.phase=='battle' and ticks<11000:
		if ticks==60:
			key(KEY_SPACE)
			click(screen(horse.pos)-Vector2(0,35))
			t.set_camera(r.projection*Vector2(1750,1235)-Vector2(960,540))
			click(screen(Vector2(1400,1220)),MOUSE_BUTTON_LEFT,true)
			click(screen(Vector2(2100,1250)))
			if filming:
				for frame in 18:await process_frame
			journal.append(['route',t.paused,horse.order,horse.destination,horse.waypoints.size()])
			key(KEY_SPACE)
		if ticks==1200:
			var spawn_point=Vector2(593.5707,1172.081)
			t.set_camera(r.projection*spawn_point-Vector2(960,540))
			key(KEY_3);click(screen(spawn_point))
			var reserve:Dictionary=r.units.back()
			var enemy:Dictionary=r.units[0]
			journal.append(['reserve',reserve.kind,reserve.side,reserve.pos,spawn_point])
			key(KEY_SPACE)
			click(screen(reserve.pos)-Vector2(0,35))
			t.set_camera(r.projection*((reserve.pos+enemy.pos)*.5)-Vector2(960,540))
			click(screen(enemy.pos)-Vector2(0,35),MOUSE_BUTTON_RIGHT)
			if filming:
				for frame in 16:await process_frame
			journal.append(['focus',reserve.order,reserve.target_id,enemy.id,t.squad_ids])
			key(KEY_SPACE)
		t._process(1./60)
		for e in t.field.effects:
			if e.age!=0:continue
			events[e.kind]=events.get(e.kind,0)+1
			if e.get('mounted_contact',false):journal.append([r.elapsed,e.kind,e.sector,e.attacker,e.target])
			if e.kind=='flanking_charge':flank=true
		for u in r.units:
			if u.get('wall_files',{}).size()>0:wall=true
		if filming and ticks%2==0:await process_frame
		ticks+=1
	var ending=r.outcome
	print("MATCH ",journal," events ",events," flank ",flank," wall ",wall," result ",ending," time ",r.elapsed)
	t.refresh()
	if filming:
		for frame in 32:await process_frame
	click(t.start_button.get_global_rect().get_center())
	print('RETRY ',t.rules.phase,' cleared effects ',t.field.effects.is_empty(),' clean projectiles ',t.rules.stones.is_empty() and t.rules.volleys.is_empty(),' new cavalry ',t.rules.units.all(func(u):return not u.has('penetration') and not u.has('slot_states') and u.get('charge_id',0)==0))
	t.closed.emit();app.queue_free();await process_frame
	quit()
