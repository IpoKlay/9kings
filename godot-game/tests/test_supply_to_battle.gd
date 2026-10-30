extends SceneTree
## Actual pointer path: menu -> destination -> infantry combat -> reward -> next destination/combat.
var app
var checks=0
var failures=0
func _init(): call_deferred('run')
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1;printerr('FAIL: '+message)
func click(p: Vector2):
	Input.warp_mouse(root.get_final_transform()*p)
	await process_frame
	var motion=InputEventMouseMotion.new()
	motion.position=p;motion.global_position=p
	root.push_input(motion,true)
	for down in [true,false]:
		var event=InputEventMouseButton.new()
		event.position=p;event.global_position=p
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down
		root.push_input(event,true)
	await process_frame
func press(control: Control): await click(control.get_global_rect().get_center())
func use_card(hand):
	var point=hand.slots[0].origin+Vector2(120,130)
	for down in [true,false]:
		if not down: point.y-=hand.preset.drag_threshold+12
		Input.warp_mouse(root.get_final_transform()*point)
		await process_frame
		var motion=InputEventMouseMotion.new();motion.position=point;motion.global_position=point
		root.push_input(motion,true)
		var event=InputEventMouseButton.new();event.position=point;event.global_position=point
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down
		root.push_input(event,true)
	await process_frame
func capture(id: String):
	await process_frame
	RenderingServer.force_draw() # Deterministic capture even when the OS occludes this test window.
	root.get_texture().get_image().save_png('res://../output/camp-expansion-v1/flow-'+id+'.png')
func run():
	if DisplayServer.get_name()=='headless':
		printerr('This pointer test requires the native renderer.');quit(1);return
	root.size=Vector2i(1280,720)
	app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/private/tmp/eagle-camp-supply-test.cfg'
	root.add_child(app);current_scene=app
	app.set_process(false);app.prefs.music_volume=0;app.apply_prefs();app.sound.enabled=false
	for lang in ['zh','en']:
		app.language=lang
		for act in [1,2,3]:
			for first_card in ['legion','medic','shieldDrill','shield']:
				app.return_to_menu()
				app.starting_theaters.assign([act])
				await press(app.menu_view.get_node('StartGame'))
				check(app.expedition_map.visible and not app.battle_screen.visible,'Start Game first opens the map')
				check(app.card_hand==null and app.campaign.g.offered.is_empty(),'No cards drawn or shown before destination')
				check(app.campaign.g.phase=='prepare' and app.expedition.stage_order[0]==act,'Random start retained')
				app.show_camp()
				check(app.expedition_map.visible,'Cannot bypass destination selection through camp')
				var id=app.expedition.destinations()[0]
				var entry=app.expedition.departure_port()
				check(not app.expedition.can_travel(entry),'Departure port has no separate supply interaction')
				var button=app.expedition_map.city_buttons[id]
				# Focus the city with the existing camera to make pointer targeting deterministic.
				app.expedition_map.atlas.focus_city(id)
				await process_frame
				await press(button)
				check(app.expedition_map.selected==id and not app.expedition_map.travel_button.disabled,'Clicking city opens actionable intel')
				if first_card=='legion': await capture('destination-'+str(act)+'-'+lang)
				await press(app.expedition_map.travel_button)
				preload('res://tests/expedition_test_support.gd').finish_departure(app)
				check(app.campaign.g.phase=='battle' and app.card_hand==null,'Destination immediately opens infantry-only battle')
				check(app.world.environment_act==act and app.campaign.g.buildings.size()==1,'Correct environment and bare starting army')
				check(app.expedition.state.target==id and app.expedition.state.visited==[app.expedition.data.start,entry],'Transit recorded once; enemy city remains uncaptured')
				for i in 120: app._process(1.0/60)
				check(app.campaign.g.battle.time>1,'Actual battle advances before any card selection')
				# Result fixture isolates pointer UI; actual opening wins are tested in test_camp_expansion.
				app.campaign.finish(true);app.render_ui();app.advance()
				check(app.campaign.g.phase=='reward' and app.campaign.g.cities_captured==1,'Only victory creates the first card hand')
				app.campaign.g.offered=[first_card,'archer','siege']
				app.campaign.g.offerYear=app.campaign.g.round
				app.render_ui()
				await create_timer(.4).timeout
				var before=app.campaign.g.duplicate(true)
				app._process(.2)
				check(app.campaign.g==before,'Reward waits for player input')
				if first_card=='legion': await capture('cards-'+str(act)+'-'+lang)
				if first_card=='medic':
					app.open_map();app.return_to_menu();app.resume_game();app.show_camp()
					check(app.campaign.g==before and app.expedition.state.current==id,'Map and menu preserve conquered city and reward')
					await create_timer(.4).timeout
				await use_card(app.card_hand)
				await create_timer(.3).timeout
				check(app.campaign.g.chosen==first_card and not app.input_locked,'Upward drag chooses the first victory card')
				if app.campaign.g.phase=='place':
					check(app.campaign.g.battle==null and not app.ui.has_node('ContinueButton'),'Building waits for placement, with no second Battle step')
					check(not app.campaign.place(-1),'Invalid placement cannot launch battle')
					app.open_map();app.show_camp()
					check(app.campaign.g.pending==first_card,'Map preserves pending building')
					var cell=-1
					for i in app.campaign.g.unlocked_cells:
						var b=app.campaign.building_at(i)
						if b==null or (b.type==first_card and b.level<3): cell=i;break
					var p=app.world.center(cell)
					await click(app.world.project(p.x,p.y))
				check(app.campaign.g.phase=='prepare' and app.campaign.g.battle==null,'Reward placement returns to camp, not an already-conquered battle')
				check(app.card_hand==null and app.campaign.g.round==2,'First reward consumed exactly once')
				check(not app.expedition.travel(id) and not app.campaign.choose(first_card),'Cannot replay the city or claim the card twice')
				var after=app.campaign.g.duplicate(true)
				app.advance();check(app.campaign.g==after,'No duplicate reward settlement')
				app.continue_expedition()
				var next_id=app.expedition.destinations()[0]
				check(app.expedition_map.visible and app.expedition.can_travel(next_id),'Continue returns to the next destination')
				app.travel_to(next_id)
				check(app.campaign.g.phase=='battle' and app.card_hand==null,'Next city starts with earned army and no redundant card')

	app.sound.stop();app.music.set_process(false)
	for i in 2:app.music.retire_slot(i)
	await create_timer(.1).timeout;app.queue_free();await process_frame;await process_frame
	print('%d destination-first pointer checks, %d failures'%[checks,failures])
	quit(1 if failures else 0)
