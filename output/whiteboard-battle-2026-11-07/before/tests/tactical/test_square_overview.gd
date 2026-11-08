extends SceneTree
var failures=0
func _initialize():call_deferred('run')
func check(ok: bool,note: String):
	if not ok:failures+=1;push_error(note)
func key_tab():
	for down in [true,false]:
		var e=InputEventKey.new();e.physical_keycode=KEY_TAB;e.pressed=down
		root.push_input(e,true)
func click(p: Vector2,shift: bool=false):
	for down in [true,false]:
		var e=InputEventMouseButton.new();e.position=p;e.global_position=p;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;e.shift_pressed=shift
		root.push_input(e,true)
func run():
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-square-overview.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit()
	var t=app.active_trial;t.set_process(false);t.combined_button.pressed.emit()
	var r=t.rules
	check(t.zoom==1.,'Default deployment preserves original figure scale')
	var offset: Vector2=t.camera_offset
	t.start_button.pressed.emit();t.paused=true
	check(t.camera_offset==offset,'Begin preserves deployment camera')
	var horse=r.alive('ally').filter(func(u):return u.kind=='cavalry')[0]
	var direct: Array[Vector2]=[]
	r.march_route(horse.id,direct,Vector2(340,1500))
	click((r.projection*horse.pos-t.camera_offset)*t.zoom)
	click((r.projection*Vector2(220,1600)-t.camera_offset)*t.zoom,true)
	var selected=t.squad_ids.duplicate();var draft=t.draft_waypoints.duplicate();var destination: Vector2=horse.destination
	check(selected==[horse.id] and draft.size()==1,'Real selection and draft exist before overview')
	key_tab()
	check(t.zoom<.65,'Physical Tab opens overview')
	var viewport=Rect2(0,0,1920,1080)
	for corner in [r.bounds.position,Vector2(r.bounds.end.x,0),r.bounds.end,Vector2(0,r.bounds.end.y)]:
		check(viewport.has_point((r.projection*corner-t.camera_offset)*t.zoom),'All three equal map zones fit overview')
	check(t.squad_ids==selected and t.draft_waypoints==draft and horse.destination==destination and horse.order=='move','Overview preserves selection, draft and executing command')
	key_tab();check(t.zoom==1. and t.camera_offset==offset,'Physical Tab restores the exact previous camera')
	t.zoom=1.12;t.set_camera(offset+Vector2(100,-100));offset=t.camera_offset
	t.overview_button.pressed.emit();t.overview_button.pressed.emit()
	check(t.zoom==1.12 and t.camera_offset==offset,'Overview button restores a custom panned and zoomed view')
	var pos: Vector2=horse.pos;var time: float=r.elapsed
	for i in 60:t._process(1./60)
	check(horse.pos==pos and r.elapsed==time,'Overview and its button do not resume paused commands')
	t.closed.emit();app.queue_free();await process_frame
	print('Square overview failures: ',failures);quit(1 if failures else 0)
