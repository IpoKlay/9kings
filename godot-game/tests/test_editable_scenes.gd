extends SceneTree

const PassScene=preload('res://scenes/battlefields/roman_pass.tscn')
const Terrain=preload('res://scripts/tactical/pass_terrain.gd')
var app
var checks=0
var failures=0

func _initialize():call_deferred('run')

func check(ok: bool,note: String):
	checks+=1
	if not ok:
		failures+=1
		push_error(note)

func mouse(point: Vector2,pressed: bool):
	var event=InputEventMouseButton.new()
	event.position=point
	event.global_position=point
	event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=pressed
	root.push_input(event,true)

func click(button: Control):
	var point=button.get_global_rect().get_center()
	mouse(point,true)
	mouse(point,false)
	await process_frame

func check_pass(r):
	var scene=PassScene.instantiate()
	var defaults=scene.settings(r.projection)
	check(defaults.rocks==r.terrain.ROCKS,'Headless rules and visible wall nodes share geometry')
	var rock=scene.get_node('Gameplay/RockWalls/MiddleRidge')
	rock.position+=Vector2(400,0)
	var flag=scene.get_node('Gameplay/EagleStandard')
	flag.position+=Vector2(100,-50)
	var spawn=scene.get_node('Spawns/InitialEnemy').get_child(0)
	spawn.position+=Vector2(80,40)
	var moved=scene.settings(r.projection)
	var terrain=Terrain.new(r.projection,r.bounds,r.config.types,moved)
	check((r.projection*moved.flag).distance_to(flag.position)<.01,'Moved flag defines the capture objective')
	check((r.projection*moved.InitialEnemy[0][1]).distance_to(spawn.position)<.01,'Moved spawn is inverse-projected once')
	for point in [Vector2(1023,796),Vector2(1423,796)]:
		var start=r.terrain.inverse*(point-Vector2(0,95))
		var finish=r.terrain.inverse*(point+Vector2(0,95))
		var old_blocked=not r.terrain.clear_segment('legion',start,finish)
		var new_blocked=not terrain.clear_segment('legion',start,finish)
		check(old_blocked!=new_blocked,'Moving the wall changes both the old and new route')
		check((terrain.leg('legion',start,finish).size()>1)==new_blocked,'Route corners follow the moved wall')
	scene.free()

func run():
	app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='user://editable-scenes-test-settings.cfg'
	app.run_path_override='user://editable-scenes-test-no-run.cfg'
	root.add_child(app)
	await process_frame
	app.sound.enabled=false
	var menu=app.menu_view
	var options=menu.options.duplicate()
	var row=menu.get_node('MenuOptions')
	var original_position: Vector2=row.position
	row.position+=Vector2(-80,24)
	row.add_theme_constant_override('separation',18)
	menu.cursor.position=Vector2(8,-4)
	for language in ['en','zh']:
		app.language=language
		app.render_ui()
		await process_frame
		check(options==menu.options,'Language refresh retains actual authored controls')
		check(row.position==original_position+Vector2(-80,24),'Menu group position survives refresh')
		check(is_equal_approx(options[1].position.y-options[0].position.y,92),'Menu row spacing comes from the container')
		check(menu.cursor.position==Vector2(8,-4),'Cursor artwork keeps its authored offset')
		check(options[0].pressed.get_connections().size()==1,'Menu callback connects once')
	row.position=original_position
	row.add_theme_constant_override('separation',6)
	await click(menu.get_node('%TacticalTrial'))
	var t=app.active_trial
	t.set_process(false)
	check(t.character_picker.item_count==t.character_ids.size(),'Live character list replaces the authored initial selection')
	var start_position: Vector2=t.start_button.position
	var start_size: Vector2=t.start_button.size
	t.start_button.position+=Vector2(-90,-140)
	for language in ['en','zh']:
		app.language=language
		t.refresh()
		check(t.start_button.position==start_position+Vector2(-90,-140),'Refresh keeps independent StartButton position')
		check(t.start_button.size==start_size,'Refresh keeps independent StartButton size')
	check_pass(t.rules)
	var help=t.get_node('BattleHUD/TopActions/HelpButton')
	await click(help)
	check(t.controls.visible and t.power_note.visible,'Help opens authored content')
	await click(help)
	check(not t.controls.visible and not t.power_note.visible,'Help closes authored content')
	await click(t.get_node('BattleHUD/TopActions/PauseButton'))
	check(t.paused,'Pause callback operates')
	await click(t.get_node('BattleHUD/TopActions/PauseButton'))
	check(not t.paused,'Pause resumes with one click')
	await click(t.pace_button)
	check(t.slow,'Half speed callback operates')
	# The empty lower strip must reach the battlefield despite several HUD groups.
	mouse(Vector2(1220,1035),true)
	check(t.gesture,'Transparent gap reaches battlefield input')
	var motion=InputEventMouseMotion.new()
	motion.position=Vector2(1170,1010)
	motion.relative=Vector2(-50,-25)
	motion.button_mask=MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion,true)
	mouse(motion.position,false)
	check(t.camera_offset!=Vector2.ZERO,'Dragging through transparent HUD space pans')
	for outcome in ['victory','defeat','timeout']:
		await click(t.combined_button)
		t.refresh()
		await click(t.start_button)
		check(t.rules.phase=='battle','Start transitions once to battle')
		t.refresh()
		await click(t.roster[0])
		t.refresh()
		await click(t.start_button)
		check(t.rules.alive('ally')[0].order=='hold','Same button holds the selected regiment')
		t.rules.phase=outcome
		t.refresh()
		check(t.result.visible,'Terminal phase uses authored result node')
		await click(t.start_button)
		check(t.rules.phase=='deploy' and t.rules.alive('ally').is_empty(),'Single retry resets once to deployment')
		check(t.start_button.pressed.get_connections().size()==1,'Retry keeps exactly one shared callback')
		check(t.camera_offset==Vector2.ZERO and t.field.effects.is_empty(),'Retry resets camera and temporary effects')
		check(t.start_button.position==start_position+Vector2(-90,-140),'Retry preserves edited StartButton position')
	await click(t.get_node('BattleHUD/TopActions/MenuButton'))
	check(app.main_menu and app.menu_view==menu,'Return keeps the persistent menu scene')
	app.queue_free()
	await process_frame
	print('%d editable-scene checks, %d failures'%[checks,failures])
	quit(1 if failures else 0)
