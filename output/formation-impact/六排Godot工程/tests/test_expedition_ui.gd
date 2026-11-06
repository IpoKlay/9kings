extends SceneTree
var checks=0
var failures=0
var scene
func check(value: bool,message: String):
	checks+=1
	if not value:
		failures+=1
		printerr('FAIL: '+message)
func _init(): call_deferred('run')
func capture(id: String):
	if DisplayServer.get_name()=='headless': return
	await process_frame
	RenderingServer.force_draw() # Deterministic capture even when the OS occludes this test window.
	root.get_texture().get_image().save_png('res://tests/'+id+'.png')
func supply():
	var choices=scene.campaign.offers()
	var id=choices[0]
	for preferred in ['guard','legion','archer','siege','spear','medic','cavalry']:
		if preferred in choices: id=preferred;break
	await scene.choose_card(id)
	if scene.campaign.g.phase=='place':
		var cell=-1
		for b in scene.campaign.g.buildings:
			if b.type==id and b.level<3: cell=int(b.cell);break
		if cell<0:
			for i in scene.campaign.g.unlocked_cells:
				if scene.campaign.building_at(i)==null: cell=i;break
		check(scene.campaign.place(cell),'Place reward in existing camp')
		scene.render_ui()
	check(not scene.expedition_map.visible and scene.ui.visible,'Reward stays in camp until map icon is clicked')
	scene.ui.get_node('MapButton').pressed.emit()
	check(scene.expedition_map.visible,'Map icon opens native map')
func run():
	scene=load('res://scenes/main.tscn').instantiate()
	scene.main_menu=false # Enter gameplay directly; boot menu has its own tests.
	root.add_child(scene)
	current_scene=scene
	scene.set_process(false)
	scene.sound.enabled=false
	scene.language='zh'
	scene.world.language='zh'
	scene.campaign.reset(23)
	scene.expedition.reset()
	scene.render_ui()
	check(scene.expedition_map.visible and scene.card_hand==null,'Opening chooses destination before any cards')
	scene.travel_to('246349')
	await create_timer(.45).timeout
	check(scene.card_hand==null and scene.campaign.g.phase=='battle','First city starts with infantry and no free card')
	scene.open_map()
	check(scene.expedition_map.city_buttons.size()==55,'All 55 locations share the geographic map')
	await capture('expedition-native-map')
	scene.expedition_map.select_city('727070')
	check(scene.expedition_map.travel_button.disabled,'Distant goal cannot be entered')
	scene.expedition_map.select_city('148127')
	check(scene.expedition_map.travel_button.disabled,'Departure port already passed without another card')
	for id in ['246349','246369']:
		scene.expedition_map.city_buttons[id].pressed.emit()
		check(scene.expedition_map.info.size.x<1920*.25,'City window occupies less than quarter screen width')
		await capture('expedition-native-intel-'+id)
		var buildings=scene.campaign.g.buildings.duplicate(true)
		var wave=scene.expedition.encounter(id)
		if id=='246349': scene.show_camp()
		else: scene.expedition_map.travel_button.pressed.emit()
		preload('res://tests/expedition_test_support.gd').finish_departure(scene)
		check(scene.campaign.g.phase=='battle' and not scene.expedition_map.visible,'City button starts original Godot battle')
		check(scene.campaign.g.battle.initialEnemies==wave.roster.size(),'Native intel matches combat roster')
		scene.open_dialog('settings')
		var before=scene.campaign.g.battle.time
		scene._process(.1)
		check(scene.campaign.g.battle.time==before,'Settings pause expedition battles')
		scene.close_dialog()
		for i in 420:
			scene.campaign.step(1.0/60)
			scene.world.tick(1.0/60)
			scene.world.events(scene.campaign.g.battle.events)
		scene.toast_label.text=''
		scene.elapsed_label.text='00:07'
		await capture('expedition-native-battle-'+id)
		while scene.campaign.g.phase=='battle': scene.campaign.step(1.0/60)
		check(scene.campaign.g.battle.report.won,'Real battle won: '+id)
		scene.render_ui()
		scene.open_dialog('result')
		await capture('expedition-native-result-'+id)
		scene.advance()
		check(scene.expedition.state.current==id,'Victory advances map')
		check(scene.campaign.g.buildings==buildings,'Scene transition keeps buildings and levels')
		check(scene.campaign.g.phase=='reward','Victory offers actual cards')
		await supply()
	scene.expedition_map.city_buttons['246349'].pressed.emit()
	check(scene.expedition_map.travel_button.disabled,'Visited battle cannot be replayed')
	scene.expedition_map.close_info()
	await capture('expedition-native-progress')
	scene.show_camp()
	check(scene.ui.visible and not scene.expedition_map.visible,'Camp can be inspected after return')
	scene.march()
	check(scene.expedition_map.visible,'Camp returns to same expedition')
	scene.restart_expedition()
	check(scene.expedition.state.current=='423025' and scene.campaign.g.phase=='prepare' and scene.expedition.state.mode=='map','Restart resets both map and campaign')
	check(scene.campaign.g.buildings.size()==1 and scene.campaign.g.defense==3,'New run starts clean')
	scene.sound.stop()
	print('%d native expedition UI checks, %d failures'%[checks,failures])
	quit(1 if failures else 0)
