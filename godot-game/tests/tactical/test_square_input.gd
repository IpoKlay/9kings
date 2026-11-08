extends SceneTree
var failures=0
func _initialize():call_deferred('run')
func check(ok: bool,note: String):
	if not ok:failures+=1;push_error(note)
func click(p: Vector2,shift: bool=false,button: MouseButton=MOUSE_BUTTON_LEFT,double: bool=false):
	for pressed in [true,false]:
		var e=InputEventMouseButton.new()
		e.position=p;e.global_position=p;e.button_index=button;e.pressed=pressed;e.shift_pressed=shift;e.double_click=double
		root.push_input(e,true)
func screen(t,point: Vector2) -> Vector2:return (t.field.project(point)-t.camera_offset)*t.zoom
func run():
	var main=load('res://scenes/main.tscn').instantiate()
	main.settings_path='/tmp/eagle-square-input.cfg'
	root.add_child(main)
	main.menu_view.get_node('%TacticalTrial').pressed.emit()
	var t=main.active_trial
	t.set_process(false)
	# Legacy authored-map fixture; default menu coverage lives in test_whiteboard_battle.gd.
	t.rules=t.SquareBattle.new();t.field.load_battlefield();t.reset_camera()
	t.combined_button.pressed.emit()
	t.start_button.pressed.emit()
	t.paused=true
	var r=t.rules
	t.zoom=.5
	t.set_camera(Vector2(-99999,-99999))
	check(t.camera_offset.x<0 and t.camera_offset.is_finite(),'Wide zoom centres the map when viewport exceeds scenery')
	t.reset_camera()
	var u=r.alive('ally').filter(func(a):return a.kind=='cavalry')[0]
	click(screen(t,u.pos),false,MOUSE_BUTTON_LEFT,true)
	check(t.squad_ids==[u.id] and t.selected=='route','Double click visible horse row selects the entire regiment')
	var first=Vector2(240,1400)
	var end=Vector2(460,1300)
	click(screen(t,first),true)
	check(t.draft_waypoints.size()==1,'Shift appends waypoint')
	click(screen(t,first),false,MOUSE_BUTTON_WHEEL_UP)
	check(t.zoom>.55 and t.draft_waypoints.size()==1,'Zoom preserves draft')
	click(screen(t,end))
	check(u.order=='move' and u.waypoints.size()==1,'Click after zoom commits complete route')
	var old: Vector2=u.pos
	t._process(1.)
	check(u.pos==old,'Paused order does not move')
	t.paused=false
	var reached=false
	for i in 650:
		t._process(1./60)
		if u.soldiers.all(func(s):return s.get('route_progress',0)>=1):reached=true
		if u.order in ['hold','idle']:break
	# Individual movement keeps intermediate stops exact and settles the final goal within 17 units.
	check(reached and u.soldiers.all(func(s):return s.position.distance_to(s.move_goal)<17. and s.path.is_empty()),'Every horse crosses its neutral waypoint and settles at its endpoint')
	click(screen(t,u.pos),false,MOUSE_BUTTON_LEFT,true)
	var enemy=r.alive('enemy')[0]
	click(screen(t,enemy.pos),false,MOUSE_BUTTON_RIGHT)
	check(u.order=='attack' and u.target_id==enemy.id,'Right click focuses visible enemy at new zoom')
	t.closed.emit();main.queue_free()
	await process_frame
	print('Square input failures: ',failures)
	quit(1 if failures else 0)
