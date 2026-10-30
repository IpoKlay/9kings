extends SceneTree

var app
var checks = 0
var failures = 0
var routes: Array = []

func _init(): call_deferred('run')
func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
		printerr('FAIL: ' + message)
func paths(id: String, route: Array):
	var next = app.expedition.next(id)
	if next.is_empty(): routes.append(route); return
	for child in next: paths(child, route + [child])
func key(code: int):
	var event = InputEventKey.new()
	event.pressed = true
	event.keycode = code
	app._unhandled_input(event)
func by_text(node: Node, value: String):
	if (node is Label or node is Button) and node.text == value: return node
	for child in node.get_children():
		var found = by_text(child, value)
		if found != null: return found
	return null
func capture(id: String):
	if DisplayServer.get_name() == 'headless': return
	await process_frame
	RenderingServer.force_draw() # Deterministic capture even when the OS occludes this test window.
	root.get_texture().get_image().save_png('res://tests/' + id + '.png')
func supply():
	if app.dialog_kind=='event':
		app.modal.get_child(1).get_node('EventConfirm').pressed.emit()
	var opening=app.expedition.state.opening=='card'
	check(app.campaign.g.phase == 'reward', 'Supply offered exactly once')
	while app.campaign.g.expansion_credits>0 and not app.campaign.expansion_candidates().is_empty():
		check(app.campaign.expand(app.campaign.expansion_candidates()[0]),'Awarded expansion remains independent of supplies')
	var offers = app.campaign.offers()
	check(offers.size() == 3, 'Three choices')
	app.open_map()
	for id in app.expedition.next(app.expedition.state.current):
		app.expedition_map.select_city(id)
		check(app.expedition_map.travel_button.disabled, 'Unclaimed supplies block travel')
	app.show_camp()
	var picked = offers[0]
	check(app.campaign.choose(picked), 'Choose offered supply')
	app.render_ui()
	if app.campaign.g.phase == 'place':
		app.open_map()
		app.show_camp()
		check(app.campaign.g.pending == picked, 'Map round-trip retains pending building')
		var snapshot = app.campaign.g.duplicate(true)
		check(not app.campaign.place(-1) and app.campaign.g == snapshot, 'Invalid placement leaves state intact')
		var cell = -1
		for i in app.campaign.g.unlocked_cells:
			var building = app.campaign.building_at(i)
			if building == null or (building.type == picked and building.level < 3): cell = i; break
		check(app.campaign.place(cell), 'Place or upgrade reward')
		app.render_ui()
	check(app.campaign.g.phase == ('battle' if opening else 'prepare') and not app.expedition.state.reward_due, 'Supply completes into combat or camp')
	var before = app.campaign.g.duplicate(true)
	check(not app.campaign.choose(picked) and not app.campaign.skip(), 'Cannot claim or skip twice')
	check(before == app.campaign.g, 'Duplicate supply leaves state unchanged')
	app.open_map()

func run():
	app = load('res://scenes/main.tscn').instantiate()
	app.main_menu=false # Enter gameplay directly; boot menu has its own tests.
	app.settings_path='/private/tmp/eagle-camp-flow-test.cfg'
	root.add_child(app)
	current_scene = app
	app.set_process(false)
	app.prefs.music_volume=0;app.apply_prefs();app.sound.enabled=false
	paths('423025', [])
	check(routes.size() == 512, 'All 512 fixed-depth itineraries enumerated')
	var all_routes = routes.duplicate()
	routes.clear()
	# Eight representative itineraries exercise every branch and edge in both languages.
	for i in 8: routes.append(all_routes[i*73])
	var covered_edges = {}
	for route in routes:
		var previous = app.expedition.data.start
		for id in route:
			covered_edges[previous+'>'+id] = true
			previous = id
	check(covered_edges.size()==app.expedition.data.edges.size(),'Representative itineraries cover every graph edge')
	for lang in ['zh', 'en']:
		app.language = lang
		for route in routes:
			app.restart_expedition()
			app.campaign.reset(23)
			app.expedition.reset()
			app.render_ui()
			for id in route.slice(1):
				app.expedition_map.select_city(id)
				check(not app.expedition_map.travel_button.disabled, 'Next city is reachable: ' + id)
				var army = app.campaign.g.buildings.duplicate(true)
				var upgrades = app.campaign.g.upgrades.duplicate(true)
				var visited = app.expedition.state.visited.size()
				var opening=app.expedition.state.opening=='destination'
				app.expedition_map.travel_button.pressed.emit()
				preload('res://tests/expedition_test_support.gd').finish_departure(app)
				if opening: check(app.campaign.g.phase=='battle' and app.card_hand==null,'Opening has no free card')
				check(not app.expedition.travel(id), 'Repeated travel rejected')
				if app.campaign.g.phase == 'battle':
					app.toggle_pause()
					app.open_map()
					key(KEY_ESCAPE)
					check(app.paused and app.campaign.g.phase == 'battle', 'Map preserves manual pause')
					app.toggle_pause()
					app.open_dialog('settings')
					var time = app.campaign.g.battle.time
					app._process(.1)
					check(app.campaign.g.battle.time == time, 'Settings pause battle')
					key(KEY_ESCAPE)
					# Route coverage isolates transitions from balance; test_expedition runs real combat.
					app.campaign.finish(true)
					app.render_ui()
					app.ui.get_node('ReportButton').pressed.emit()
					check(app.modal.get_child(1).get_child_count() > 4, 'Report is populated')
					app.advance()
					var settled = app.campaign.g.duplicate(true)
					app.advance()
					check(app.campaign.g == settled, 'Duplicate settlement gives no reward or life')
				check(app.expedition.state.current == id and app.expedition.state.visited.size() == visited + (2 if opening else 1), 'Exactly one route step')
				check(app.campaign.g.buildings == army and app.campaign.g.upgrades == upgrades, 'Permanent army persists')
				if app.campaign.g.phase == 'reward': supply()
				await process_frame
			check(app.expedition.state.finished, 'Route reaches final victory')
			for goal in app.expedition.data.goals: check(goal in app.expedition.state.visited, 'All three theater objectives complete')
			app.expedition_map.content.get_node('SettingsButton').pressed.emit()
			var restart = by_text(app.modal, app.tx('开始新远征','New campaign'))
			check(restart != null, 'Victory offers restart through the gear')
			check(app.modal.get_child(1).get_global_rect().encloses(restart.get_global_rect()), 'Victory restart fits inside settings')
			app.close_dialog()
			if route == routes.back(): await capture('audit-victory-' + lang)
			app.show_camp()
			check(not app.ui.has_node('ReportButton'), 'No stale report after final settlement')
			app.open_map()
			app.expedition_map.content.get_node('SettingsButton').pressed.emit()
			restart = by_text(app.modal, app.tx('开始新远征','New campaign'))
			app.speed = 4
			app.world.selected_cell = 8
			restart.pressed.emit()
			check(app.speed == 1 and app.world.selected_cell == -1, 'Restart clears prior speed and selected building')
			check(app.campaign.g.defense == 3 and app.expedition.state.visited == ['423025'], 'Restart restores three lives and route')
	# Defeats, retry lock and reports recovered directly from the map.
	app.restart_expedition()
	preload('res://tests/expedition_test_support.gd').deploy(app)
	for attempt in 3:
		if attempt>0: app.travel_to('246349')
		app.campaign.finish(false)
		app.render_ui()
		app.open_map()
		await capture('audit-pending-report-' + str(attempt))
		app.expedition_map.content.get_node('SettingsButton').pressed.emit()
		var report_link = by_text(app.modal, app.tr_text('View report'))
		check(report_link != null, 'Map gear exposes pending report instead of an apparent dead end')
		if report_link != null:
			report_link.pressed.emit()
			check(app.dialog_kind == 'result', 'Map report button opens settlement')
		app.advance()
		if attempt < 2:
			check(app.campaign.g.defense == 2-attempt, 'One life lost per defeat')
			check(not app.expedition.can_travel('265849'), 'Defeat keeps branch locked')
			check(app.expedition.can_travel('246349'), 'Failed city can be retried')
		else:
			check(app.campaign.g.phase == 'prepare' and app.expedition.state.opening=='destination' and app.campaign.g.defense == 3, 'Third defeat restarts cleanly')
		await process_frame
	app.sound.stop();app.music.set_process(false)
	for i in 2:app.music.retire_slot(i)
	await create_timer(.1).timeout;app.queue_free();await process_frame;await process_frame
	print('%d expedition flow checks over %d routes in both languages, %d failures' % [checks, routes.size(), failures])
	quit(1 if failures else 0)
