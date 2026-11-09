extends SceneTree
var failures=0
func check(ok: bool,note: String):
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func click(point: Vector2,button=MOUSE_BUTTON_LEFT):
	for down in [true,false]:
		var e=InputEventMouseButton.new();e.position=point;e.global_position=point;e.button_index=button;e.pressed=down
		root.push_input(e,true)
func run():
	var main=load('res://scenes/main.tscn').instantiate()
	main.settings_path='/tmp/strategy-ui-settings.cfg'
	root.add_child(main);main.sound.enabled=false
	for i in 5:await process_frame
	click(main.menu_view.get_node('%TacticalTrial').get_global_rect().get_center())
	for i in 5:await process_frame
	var t=main.active_trial
	check(is_instance_valid(t),'Menu opens trial')
	if not is_instance_valid(t):quit(1);return
	t.set_process(false)
	check(t.rules.has_method('strategy_paths'),'Menu opens new strategy rules')
	check(t.field.pass_layout.get_script().resource_path.ends_with('strategy/field.gd'),'New terrain visible')
	var ui=t.get_children().filter(func(node):return node.get_script()!=null and node.get_script().resource_path.ends_with('strategy/interface.gd'))[0]
	check(ui.panel.is_visible_in_tree(),'Strategy panel visible')
	t.rules.start();t.selected='';t.refresh()
	var unit=t.rules.alive('ally')[0]
	var point=(t.field.project(unit.pos)-Vector2(0,20)-t.camera_offset)*t.zoom
	click(point)
	check(t.soldier_ids==[Vector2i(unit.id,0)],'Mouse selects exactly one person')
	var goal=unit.pos+Vector2(-100,-150)
	click((t.field.project(goal)-t.camera_offset)*t.zoom,MOUSE_BUTTON_RIGHT)
	check(unit.soldiers[0].personal_order=='move','Right-click sends move')
	for i in 180:t.rules.step(1./60)
	check(unit.pos.distance_to(goal)<30,'Selected person arrives')
	if DisplayServer.get_name()!='headless':
		t.field.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png('/tmp/strategy-ui.png')
	t.retry()
	check(t.rules.stock=={'food':100.,'wood':100.,'iron':100.},'Retry resets resources')
	check(t.rules.has_method('strategy_paths'),'Retry stays strategy mode')
	print('STRATEGY UI FAILURES=',failures)
	main.queue_free();t.queue_free()
	await process_frame
	quit(1 if failures else 0)
