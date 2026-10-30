extends SceneTree
var app
var failures=0
var checks=0
func _init(): call_deferred('run')
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1; printerr('FAIL: '+message)
func find_name(node: Node,wanted: String):
	if node.name==wanted: return node
	for child in node.get_children():
		var found=find_name(child,wanted)
		if found!=null: return found
	return null
func capture(name: String):
	if DisplayServer.get_name()=='headless': return
	await process_frame
	RenderingServer.force_draw() # Deterministic capture even when the OS occludes this test window.
	var image=root.get_texture().get_image()
	image.save_png('res://tests/theater-'+name+'.png')
	return image
func check_menu_layout():
	var controls=app.menu_view.find_children('*','Control',true,false)
	for control in controls:
		if control is Button or control is Label:
			check(is_equal_approx(control.get_global_rect().get_center().x,app.menu_view.preset.menu_center_x),'Menu text/button shares the right-hand menu axis: '+control.name)
			var center=float(app.menu_view.preset.menu_center_x)
			check(control.position.x>=center-285 and control.get_rect().end.x<=center+285,'Menu fits its shaded UI panel: '+control.name)
			check(control.get_global_rect().end.y<1080,'Menu control fits vertically: '+control.name)
		if control is Label:
			for reveal in ['岩丘','北非','港口','ROCKY','SANDSTONE','HARBOR','三图','starting maps']:
				check(reveal not in control.text,'Menu does not reveal a theater: '+reveal)
func click(control: Control):
	var p=control.get_global_rect().get_center()
	for down in [true,false]:
		var event=InputEventMouseButton.new()
		event.position=p
		event.global_position=p
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=down
		root.push_input(event,true)
	await process_frame
func run():
	app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='res://../output/data-organization/test_menu_environments-settings.cfg'
	root.add_child(app)
	current_scene=app
	app.set_process(false)
	app.menu_view.set_process(false) # Freeze cursor animation for environment-independent captures.
	var saved=app.prefs.duplicate(true)
	app.language='zh'
	app.sound.enabled=false
	app.render_ui()
	check(app.main_menu and app.menu_view.visible and not app.ui.visible,'Boot enters main menu')
	check(app.world.menu_mode,'Menu omits live units and buildings')
	check(not app.battle_screen.visible and not app.expedition_map.visible,'Both battlefield and expedition map are hidden at boot')
	check(app.menu_view.background.get_image().detect_alpha()==Image.ALPHA_NONE,'Menu artwork is opaque')
	check(app.menu_view.cloth.get_image().detect_alpha()==Image.ALPHA_NONE,'Existing map-unroll backing remains available')
	check(find_name(app.menu_view,'ResumeGame')!=null and not app.menu_view.option_available(1),'Continue remains visible but unavailable before a run')
	check_menu_layout()
	var initial=app.campaign.g.duplicate(true)
	var environment_time=app.world.environment.clock
	app._process(.1)
	check(app.campaign.g==initial,'Menu never advances simulation')
	check(app.world.environment.clock==environment_time,'Hidden battlefield environment stays frozen')
	await capture('menu-zh')
	await click(find_name(app.menu_view,'MenuSettings'))
	check(app.dialog_kind=='settings','Settings accessible before starting')
	app.set_language('en')
	check(app.main_menu and app.menu_view.visible,'Language change stays on menu')
	check(find_name(app.menu_view,'StartGame').text=='Start Game','Main menu follows language')
	await capture('settings-en')
	var panel=app.modal.get_child(1)
	for child in panel.get_children():
		if child is HSlider:
			child.value=.35
			break
	check(is_equal_approx(app.sound.volume,.35),'Master volume applies immediately')
	var config=ConfigFile.new()
	check(config.load(app.settings_path)==OK and is_equal_approx(config.get_value('settings','volume'),.35),'Volume preference persists')
	app.close_dialog()
	check_menu_layout()
	await capture('menu-en')
	app.start_rng.seed=73
	await click(find_name(app.menu_view,'StartGame'))
	check(not app.main_menu and app.expedition_map.visible and app.has_run,'Start Game enters destination map')
	check(app.world.environment_act==app.expedition.stage_order[0],'Start environment matches rolled theater')
	check(app.campaign.g.phase=='prepare' and app.card_hand==null,'Opening cards wait for destination')
	var counts={1:0,2:0,3:0}
	for i in 120: counts[app.start_rng.randi_range(1,3)]+=1
	for id in counts: check(counts[id]>20,'All three opening theaters can be rolled')
	var menu_reference: Image
	for act in [1,2,3]:
		app.restart_expedition(act)
		app.language='zh'
		app.travel_to(app.expedition.destinations()[0])
		check(app.world.environment_act==act,'Camp switches to starting theater')
		await capture('camp-'+str(act))
		preload('res://tests/expedition_test_support.gd').deploy(app)
		check(app.campaign.g.phase=='battle' and app.world.environment_act==act,'Battle keeps matching environment')
		for i in 300: app._process(1.0/60)
		await capture('battle-'+str(act))
		var before=app.campaign.g.duplicate(true)
		var bag=app.starting_theaters.duplicate()
		app.return_to_menu()
		app._process(.1)
		check(app.main_menu and app.campaign.g==before,'Returning to menu suspends battle without resetting')
		check(not app.battle_screen.visible and not app.expedition_map.visible,'Current theater stays hidden on return to menu')
		check_menu_layout()
		var motion=InputEventMouseMotion.new()
		motion.position=Vector2(50,50)
		root.push_input(motion,true)
		await process_frame
		app.menu_view.set_selected(0,false)
		app.menu_view.render()
		var menu_image=await capture('menu-return-'+str(act))
		if menu_image!=null:
			if menu_reference==null: menu_reference=menu_image
			else: check(menu_image.get_data()==menu_reference.get_data(),'Rendered menu is identical after different theaters')
		await click(find_name(app.menu_view,'ResumeGame'))
		check(not app.main_menu and app.campaign.g==before,'Continue restores the same campaign')
		check(app.battle_screen.visible and app.starting_theaters==bag,'Continue restores battlefield without rerolling')
		app.world.tick_environment(.08)
		check(app.world.environment.clock>0,'Local environment animation advances independently')
	var image=load('res://assets/environments/trees.png').get_image()
	check(image.detect_alpha()!=Image.ALPHA_NONE,'Tree sprites have actual alpha')
	app.prefs=saved
	app.save_prefs()
	app.sound.stop()
	print('%d main-menu/environment checks, %d failures'%[checks,failures])
	quit(1 if failures else 0)
