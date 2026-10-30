extends SceneTree
var app
var checks = 0
var failures = 0
func _init(): call_deferred('run')
func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
		printerr('FAIL: '+message)
func capture(id: String):
	if DisplayServer.get_name()=='headless': return
	await process_frame
	RenderingServer.force_draw() # Deterministic capture even when the OS occludes this test window.
	root.get_texture().get_image().save_png('res://../output/route-branches-v1/atlas-'+id+'.png')
func mouse(p: Vector2, pressed: bool, button: int=MOUSE_BUTTON_LEFT):
	var event=InputEventMouseButton.new()
	event.position=p
	event.global_position=p
	event.button_index=button
	event.pressed=pressed
	root.push_input(event,true)
func click(control: Control):
	var pos=control.get_global_rect().get_center()
	mouse(pos,true)
	mouse(pos,false)
	await process_frame
func motion(p: Vector2):
	var event=InputEventMouseMotion.new()
	event.position=p
	event.global_position=p
	event.button_mask=MOUSE_BUTTON_MASK_LEFT
	root.push_input(event,true)
func overlap_check():
	var buttons=app.expedition_map.city_buttons.values()
	check(buttons.size()==55,'All 55 geographic locations coexist')
	for i in buttons.size():
		for j in range(i+1,buttons.size()):
			check(not buttons[i].get_rect().intersects(buttons[j].get_rect()),'Click targets do not overlap')
	var map=app.expedition_map
	for label in map.atlas.names:
		if label.visible:
			check(not map.ui_obstacles().any(func(r):return r.intersects(label.get_rect())),'City label avoids floating map controls')
func run():
	app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/private/tmp/eagle-march-layout.cfg'
	app.main_menu=false # Enter gameplay directly; boot menu has its own tests.
	root.add_child(app)
	app.prefs.enabled=false;app.prefs.music_volume=0;app.apply_prefs()
	current_scene=app
	app.set_process(false)
	app.sound.enabled=false
	app.skip_supply()
	app.open_map()
	check(app.expedition_map.atlas.position==Vector2.ZERO and app.expedition_map.atlas.size==Vector2(1920,1080),'Map fills the removed top and bottom strips')
	check(not app.expedition_map.content.get_children().any(func(child):return child is Panel),'Header, legend and footer panels are absent')
	var gear=app.expedition_map.content.get_node('SettingsButton')
	check(gear.get_theme_stylebox('normal') is StyleBoxEmpty,'Only the gear icon remains at top right')
	await click(gear)
	check(app.dialog_kind=='settings','Floating gear still opens settings')
	app.close_dialog()
	for lang in ['zh','en']:
		app.language=lang
		app.render_ui()
		for act in range(1,4):
			await click(app.expedition_map.act_buttons[act-1])
			check(app.expedition_map.view_act==act,'Theater shortcut moves camera')
			overlap_check()
			await capture(lang+'-'+str(act))
		app.expedition_map.atlas.overview()
		overlap_check()
		await capture(lang+'-overview')
		for n in app.expedition.data.nodes:
			app.expedition_map.close_info()
			app.expedition_map.atlas.focus_city(n.id)
			await click(app.expedition_map.city_buttons[n.id])
			check(app.expedition_map.selected==n.id,'Geographic marker selects '+n.id)
			check(app.expedition_map.travel_button.disabled!=app.expedition.can_travel(n.id),'Intel action matches real route permissions')
		app.expedition_map.select_city('246349')
		await capture(lang+'-intel')
	# Dragging from a marker must not select or travel; movement survives rerender.
	app.expedition_map.close_info()
	app.expedition_map.atlas.focus_city('246349')
	for point in [Vector2(900,40),Vector2(900,1040)]:
		var previous_center=app.expedition_map.atlas.center
		mouse(point,true)
		motion(point+Vector2(80,0))
		mouse(point+Vector2(80,0),false)
		await process_frame
		check(app.expedition_map.atlas.center.distance_to(previous_center)>10,'Removed chrome area accepts map dragging')
	var atlas=app.expedition_map.atlas
	var before=atlas.center
	var route=app.expedition.state.duplicate(true)
	var start=app.expedition_map.city_buttons['246349'].get_global_rect().get_center()
	mouse(start,true)
	motion(start+Vector2(110,55))
	check(atlas.layout_pending,'Drag defers expensive marker layout until the next display frame')
	mouse(start+Vector2(110,55),false)
	await process_frame
	await process_frame
	check(not atlas.layout_pending,'Latest pointer position is laid out on the next frame')
	check(atlas.center.distance_to(before)>10,'Drag moves the camera')
	check(app.expedition_map.selected=='','Drag from marker does not select')
	check(app.expedition.state==route,'Drag never travels or changes run state')
	var after=atlas.center
	app.expedition_map.render()
	check(app.expedition_map.atlas.center==after,'Camera survives UI refresh')
	atlas=app.expedition_map.atlas
	var pointer=Vector2(910,440)
	var anchor=atlas.world_at(pointer)
	var zoom=atlas.zoom
	mouse(pointer+atlas.position,true,MOUSE_BUTTON_WHEEL_UP)
	await process_frame
	check(atlas.zoom>zoom,'Wheel zoom works')
	check(atlas.world_at(pointer).distance_to(anchor)<.1,'Zoom remains anchored under cursor')
	# Native battle/reward round trip through actual pointer events.
	app.show_camp()
	app.continue_expedition()
	for id in ['246349','246369','265883']:
		app.expedition_map.atlas.focus_city(id)
		await click(app.expedition_map.city_buttons[id])
		check(app.expedition_map.selected==id,'Mouse selects reachable stop')
		await click(app.expedition_map.travel_button)
		preload('res://tests/expedition_test_support.gd').finish_departure(app)
		check(app.expedition.state.current==id or app.expedition.state.target==id,'Pointer enters native encounter')
		if app.expedition.state.opening=='card':
			app.open_map()
			await click(app.expedition_map.content.get_node('SettingsButton'))
			var deployment_action=app.modal.get_child(1).get_node('MapContextAction')
			check(deployment_action.text==app.loc('expedition_map.back_to_deployment'),'Gear exposes Return to deployment')
			await capture('settings-deployment')
			await click(deployment_action)
			check(app.dialog_kind=='' and app.battle_screen.visible and app.expedition.state.opening=='card','Settings action returns to opening deployment')
			preload('res://tests/expedition_test_support.gd').deploy(app)
		if app.campaign.g.phase=='battle':
			var battle_before=app.campaign.g.battle.duplicate(true)
			app.open_map()
			await click(app.expedition_map.content.get_node('SettingsButton'))
			var battle_action=app.modal.get_child(1).get_node('MapContextAction')
			check(battle_action.text==app.loc('expedition_map.back_to_battle'),'Gear exposes Return to battle')
			await click(battle_action)
			check(app.dialog_kind=='' and app.expedition.state.mode=='battle' and app.campaign.g.battle==battle_before,'Gear restores battle without changing simulation')
			app.campaign.finish(true)
			app.advance()
		app.skip_supply()
		app.open_map()
	check(not app.expedition.can_travel('266021'),'Other fork arm closes')
	app.language='zh'; app.render_ui()
	await capture('zh-progress')
	while app.expedition.state.current!='256177':
		var id=app.expedition.next(app.expedition.state.current)[0]
		app.travel_to(id)
		if app.campaign.g.phase=='battle': app.campaign.finish(true); app.advance()
		if app.dialog_kind=='event': await click(app.modal.get_child(1).get_node('EventConfirm'))
		app.skip_supply()
		app.open_map()
	check(app.expedition_map.view_act==2,'Victory focuses next theater')
	check(app.expedition.can_travel('462503'),'Next theater preserves existing rules')
	await capture('zh-transition')
	app.expedition_map.show_act(3)
	app.restart_expedition()
	app.open_map()
	check(app.expedition_map.view_act==1 and app.expedition.state.current=='423025','Restart resets theater')
	app.sound.stop()
	print('%d atlas layout/pointer checks, %d failures'%[checks,failures])
	quit(1 if failures else 0)
