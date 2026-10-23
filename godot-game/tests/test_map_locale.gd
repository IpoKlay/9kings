extends SceneTree
var checks=0
var failures=0
var scene
var han=RegEx.new()
func check(ok: bool,message: String):
	checks+=1
	if not ok:
		failures+=1
		printerr('FAIL: '+message)
func _init():
	han.compile('[\\x{4E00}-\\x{9FFF}]')
	call_deferred('run')
func inspect_english(node: Node):
	if node is Label or node is Button:
		check(han.search(node.text)==null,'English UI contains Chinese: '+node.text)
	if node is Control:
		check(han.search(node.tooltip_text)==null,'English tooltip contains Chinese')
	for child in node.get_children(): inspect_english(child)
func capture(id: String):
	if DisplayServer.get_name()=='headless': return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png('res://tests/'+id+'.png')
func run():
	scene=load('res://scenes/main.tscn').instantiate()
	root.add_child(scene)
	current_scene=scene
	scene.set_process(false)
	var saved=scene.prefs.duplicate(true)
	scene.sound.enabled=false
	scene.set_language('en')
	scene.close_dialog()
	scene.sound.enabled=false
	await create_timer(.45).timeout
	check(not scene.expedition_map.visible,'Start in camp')
	await capture('map-icon-en')
	var before=scene.campaign.g.duplicate(true)
	scene.ui.get_node('MapButton').pressed.emit()
	check(scene.expedition_map.visible,'Top-right icon opens map')
	check(scene.campaign.g==before,'Map opening preserves pending supply and army')
	check(not scene.card_hand.can_interact(),'Hidden cards cannot intercept map clicks')
	scene.expedition_map.select_city('148127')
	check(scene.expedition_map.travel_button.disabled,'Cannot bypass pending supplies through map')
	for n in scene.expedition.data.nodes:
		scene.expedition_map.select_city(n.id)
		scene.expedition_map.history_open=true
		scene.expedition_map.render()
		inspect_english(scene.expedition_map.content)
	var initial_phase=scene.campaign.g.phase
	scene.campaign.g.phase='prepare'
	for notice in ['assembly','visit','captured','victory','defeat']:
		scene.expedition.state.notice=notice
		scene.expedition.state.notice_city='314921'
		check(han.search(scene.expedition.notice_text())==null,'Dynamic notice must be translated: '+notice)
	for phase in ['reward','place','battle','result','defeat']:
		scene.campaign.g.phase=phase
		check(han.search(scene.expedition.notice_text())==null,'Phase notice must be translated: '+phase)
	scene.campaign.g.phase=initial_phase
	scene.expedition.state.notice='assembly'
	scene.expedition_map.select_city('314921')
	scene.expedition_map.history_open=true
	scene.expedition_map.render()
	await capture('expedition-map-en')
	var route=scene.expedition.state.duplicate(true)
	scene.set_language('zh')
	scene.close_dialog()
	check(scene.expedition.state==route,'Language switching preserves route')
	check(scene.expedition_map.selected=='314921' and scene.expedition_map.history_open,'Language switching preserves open intel')
	check(scene.expedition.node_text('423025')=='罗马','Chinese city name restored')
	await capture('expedition-map-zh')
	scene.set_language('en')
	scene.close_dialog()
	inspect_english(scene.expedition_map.content)
	scene.show_camp()
	scene.skip_supply()
	check(scene.ui.visible and not scene.expedition_map.visible,'Completing supply does not auto-open map')
	scene.ui.get_node('MapButton').pressed.emit()
	scene.travel_to('148127')
	scene.skip_supply()
	scene.open_map()
	scene.travel_to('246349')
	check(scene.campaign.g.phase=='battle','Route still launches combat')
	check(scene.year_text().begins_with('Tarraco'),'Battle title follows English setting')
	var time=scene.campaign.g.battle.time
	scene.ui.get_node('MapButton').pressed.emit()
	scene._process(.1)
	check(scene.campaign.g.battle.time==time,'Map pauses active battle')
	scene.show_camp()
	scene._process(.1)
	check(scene.campaign.g.battle.time>time,'Closing map resumes active battle')
	scene.prefs=saved
	scene.save_prefs()
	scene.sound.stop()
	print('%s map entry/localization checks, %s failures'%[checks,failures])
	quit(1 if failures else 0)
