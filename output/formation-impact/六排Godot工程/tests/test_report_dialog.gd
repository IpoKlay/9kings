extends SceneTree

var scene
var checks = 0
var failures = 0

func _init(): call_deferred('run')

func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
		printerr('FAIL: ' + message)

func texts(node: Node) -> String:
	var result = node.text + '\n' if node is Label or node is Button else ''
	for child in node.get_children(): result += texts(child)
	return result

func no_report(context: String):
	check(not scene.ui.has_node('ReportButton'), context + ': no report button')
	scene.open_dialog('result')
	check(scene.dialog_kind == '' and not is_instance_valid(scene.modal), context + ': no empty modal')

func capture(id: String):
	if DisplayServer.get_name() == 'headless': return
	await process_frame
	RenderingServer.force_draw() # Deterministic capture even when the OS occludes this test window.
	root.get_texture().get_image().save_png('res://tests/' + id + '.png')

func run():
	scene = load('res://scenes/main.tscn').instantiate()
	scene.main_menu=false # Enter gameplay directly; boot menu has its own tests.
	root.add_child(scene)
	current_scene = scene
	scene.set_process(false)
	scene.sound.enabled = false
	for lang in ['zh','en']:
		scene.language = lang
		for outcome in ['win','loss','defeat']:
			scene.restart_expedition()
			no_report(lang + ' initial supply')
			scene.skip_supply()
			check(scene.campaign.g.phase == 'prepare', 'Initial preparation reached')
			no_report(lang + ' initial preparation')
			scene.open_dialog('settings')
			var settings = scene.modal
			scene.open_dialog('result')
			check(scene.modal == settings and scene.dialog_kind == 'settings', 'Invalid report preserves existing settings')
			scene.close_dialog()
			scene.ui.get_node('MapButton').pressed.emit()
			check(scene.expedition_map.visible, 'Preparation still opens map')
			scene.travel_to('246349')
			no_report(lang + ' opening deployment')
			if outcome == 'win': await capture('report-fix-camp-' + lang)
			preload('res://tests/expedition_test_support.gd').deploy(scene)
			check(scene.campaign.g.phase == 'battle', 'Real encounter started')
			no_report(lang + ' battle in progress')
			if outcome == 'defeat': scene.campaign.g.defense = 1
			if outcome == 'win':
				while scene.campaign.g.phase == 'battle': scene.campaign.step(1.0 / 60)
				check(scene.campaign.g.battle.report.won, 'Opening battle wins')
			else: scene.campaign.finish(false)
			scene.render_ui()
			check(scene.ui.has_node('ReportButton'), lang + ' ' + outcome + ': report button exists')
			scene.ui.get_node('ReportButton').pressed.emit()
			var content = texts(scene.modal)
			check(content.contains(scene.tr_text('ENEMY LOSSES')) and content.contains(scene.tr_text('SURVIVORS')), 'Report shows actual statistics')
			var title = ('远征结束' if outcome == 'defeat' else '城邦已夺取' if outcome == 'win' else '进攻失利') if lang == 'zh' else ('Campaign ended' if outcome == 'defeat' else 'City secured' if outcome == 'win' else 'Attack repelled')
			check(content.contains(title), 'Report has correct localized outcome')
			if outcome == 'win': await capture('report-fix-result-' + lang)
			scene.close_dialog()
			scene.open_dialog('result')
			check(texts(scene.modal).contains(title), 'Completed report can be reopened')
			scene.advance()
			check(scene.campaign.g.battle == null, 'Settlement clears battle')
			if scene.campaign.g.phase == 'reward': scene.skip_supply()
			scene.show_camp()
			no_report(lang + ' after settlement')
	scene.sound.stop()
	print('%d report dialog checks, %d failures' % [checks,failures])
	quit(1 if failures else 0)
