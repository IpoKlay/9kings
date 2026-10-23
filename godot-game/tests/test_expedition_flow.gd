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
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png('res://tests/' + id + '.png')
func supply():
	check(app.campaign.g.phase == 'reward', 'Supply offered exactly once')
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
		for i in 12:
			var building = app.campaign.building_at(i)
			if building == null or (building.type == picked and building.level < 3): cell = i; break
		check(app.campaign.place(cell), 'Place or upgrade reward')
		app.render_ui()
	check(app.campaign.g.phase == 'prepare' and not app.expedition.state.reward_due, 'Supply completed in camp')
	var before = app.campaign.g.duplicate(true)
	check(not app.campaign.choose(picked) and not app.campaign.skip(), 'Cannot claim or skip twice')
	check(before == app.campaign.g, 'Duplicate supply leaves state unchanged')
	app.open_map()

func run():
	app = load('res://scenes/main.tscn').instantiate()
	root.add_child(app)
	current_scene = app
	app.set_process(false)
	app.sound.enabled = false
	paths('423025', [])
	check(routes.size() == 12, 'All twelve branching routes enumerated')
	for lang in ['zh', 'en']:
		app.language = lang
		for route in routes:
			app.restart_expedition()
			app.campaign.reset(23)
			app.render_ui()
			supply()
			for id in route:
				app.expedition_map.select_city(id)
				check(not app.expedition_map.travel_button.disabled, 'Next city is reachable: ' + id)
				var army = app.campaign.g.buildings.duplicate(true)
				var upgrades = app.campaign.g.upgrades.duplicate(true)
				var visited = app.expedition.state.visited.size()
				app.expedition_map.travel_button.pressed.emit()
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
				check(app.expedition.state.current == id and app.expedition.state.visited.size() == visited + 1, 'Exactly one route step')
				check(app.campaign.g.buildings == army and app.campaign.g.upgrades == upgrades, 'Permanent army persists')
				if app.campaign.g.phase == 'reward': supply()
				await process_frame
			check(app.expedition.state.finished, 'Route reaches final victory')
			for goal in app.expedition.data.goals: check(goal in app.expedition.state.visited, 'All four regional objectives complete')
			var restart = by_text(app.expedition_map.content, app.tx('开始新远征','New campaign'))
			check(restart != null, 'Victory offers restart')
			var goal_label = by_text(app.expedition_map.content, '◆ ' + app.tx('内海终章','The Inland Sea'))
			check(not restart.get_global_rect().intersects(goal_label.get_global_rect()), 'Victory restart does not overlap final objective')
			if route == routes.back(): await capture('audit-victory-' + lang)
			app.show_camp()
			check(not app.ui.has_node('ReportButton'), 'No stale report after final settlement')
			app.open_map()
			restart = by_text(app.expedition_map.content, app.tx('开始新远征','New campaign'))
			app.speed = 4
			app.world.selected_cell = 8
			restart.pressed.emit()
			check(app.speed == 1 and app.world.selected_cell == -1, 'Restart clears prior speed and selected building')
			check(app.campaign.g.defense == 3 and app.expedition.state.visited == ['423025'], 'Restart restores three lives and route')
	# Defeats, retry lock and reports recovered directly from the map.
	app.restart_expedition()
	app.skip_supply()
	app.travel_to('148127')
	app.skip_supply()
	for attempt in 3:
		app.travel_to('246349')
		app.campaign.finish(false)
		app.render_ui()
		app.open_map()
		await capture('audit-pending-report-' + str(attempt))
		var report_link = by_text(app.expedition_map.content, app.tr_text('View report'))
		check(report_link != null, 'Map exposes pending report instead of an apparent dead end')
		if report_link != null:
			report_link.pressed.emit()
			check(app.dialog_kind == 'result', 'Map report button opens settlement')
		app.advance()
		if attempt < 2:
			check(app.campaign.g.defense == 2-attempt, 'One life lost per defeat')
			check(not app.expedition.can_travel('265849'), 'Defeat keeps branch locked')
			check(app.expedition.can_travel('246349'), 'Failed city can be retried')
		else:
			check(app.campaign.g.phase == 'reward' and app.campaign.g.defense == 3, 'Third defeat restarts cleanly')
		await process_frame
	app.sound.stop()
	print('%d expedition flow checks over %d routes in both languages, %d failures' % [checks, routes.size(), failures])
	quit(1 if failures else 0)
