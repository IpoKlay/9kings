extends SceneTree
var app
var checks=0
var failures=0
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1;printerr('FAIL: '+message)
func _init(): call_deferred('run')
func capture(name: String):
	if DisplayServer.get_name()=='headless': return
	await process_frame
	RenderingServer.force_draw() # Deterministic capture even when the OS occludes this test window.
	root.get_texture().get_image().save_png('res://tests/city-waves-'+name+'.png')
func run():
	app=load('res://scenes/main.tscn').instantiate()
	root.add_child(app);current_scene=app
	app.set_process(false)
	app.has_run=true;app.main_menu=false;app.language='zh'
	app.restart_expedition(1);app.sound.enabled=false
	# Select the first destination before choosing the opening card.
	app.open_map();app.expedition_map.select_city('246349')
	await capture('intel-zh')
	app.expedition_map.travel_button.pressed.emit()
	preload('res://tests/expedition_test_support.gd').finish_departure(app)
	preload('res://tests/expedition_test_support.gd').deploy(app)
	check(app.campaign.g.phase=='battle','Native city intel begins combat')
	check('1 / 3' in app.wave_label.text,'Current wave displayed immediately')
	for i in 480: app._process(1.0/60)
	await capture('battle-zh')
	var limit=5000
	while app.campaign.g.battle.rest_remaining<=0 and app.campaign.g.phase=='battle' and limit>0:
		app._process(1.0/60);limit-=1
	check(limit>0 and app.campaign.g.battle.rest_remaining>0,'Actual first-wave victory enters regroup')
	check(app.campaign.g.phase=='battle' and app.card_hand==null,'Regroup does not show cards')
	await capture('rest-zh')
	var before=app.campaign.g.battle.duplicate(true)
	app.toggle_pause();app._process(.1)
	check(before==app.campaign.g.battle,'Pause freezes regroup')
	app.toggle_pause();app.open_dialog('settings');app._process(.1)
	check(before==app.campaign.g.battle,'Settings freeze regroup')
	app.close_dialog();app.open_map();app._process(.1)
	check(before==app.campaign.g.battle,'Map freezes regroup')
	app.show_camp();app.return_to_menu();app._process(.1)
	check(before==app.campaign.g.battle,'Menu freezes regroup')
	app.resume_game()
	check(before==app.campaign.g.battle,'Continue preserves pending wave')
	app.language='en';app.render_ui()
	check('Regroup' in app.wave_label.text,'Regroup status is localized')
	await capture('rest-en')
	app.world.death_times[0]=0.0
	for i in 220: app._process(1.0/60)
	check(app.campaign.g.battle.wave_index==1,'Next wave auto-starts after rest')
	check(not app.world.death_times.has(0),'Reinforced squads lose stale death animation')
	check('2 / 3' in app.wave_label.text,'Counter updates without rebuilding screen')
	await capture('wave2-en')
	limit=15000
	while app.campaign.g.phase=='battle' and limit>0:
		app._process(1.0/60);limit-=1
	check(limit>0 and app.campaign.g.battle.report.won,'Actual city battle reaches victory')
	check(app.campaign.g.battle.report.wavesCleared==3,'Native report includes all waves')
	app.open_dialog('result')
	await capture('report-en')
	app.advance()
	check(app.campaign.g.phase=='reward' and app.card_hand!=null,'Capture opens original reward hand')
	check(app.expedition.state.current=='246349','Map advances only after city victory')
	app.skip_supply();app.continue_expedition()
	check(app.expedition_map.visible and app.expedition.can_travel('246369'),'Can march to next city')
	app.sound.stop()
	print('%d multiwave UI checks, %d failures'%[checks,failures])
	quit(1 if failures else 0)
