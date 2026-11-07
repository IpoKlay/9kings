extends SceneTree
func _initialize():call_deferred('run')
func run():
	var main=load('res://scenes/main.tscn').instantiate()
	main.settings_path='/tmp/eagle-square-film.cfg'
	root.add_child(main)
	main.menu_view.get_node('%TacticalTrial').pressed.emit()
	var t=main.active_trial
	t.set_process(false)
	t.combined_button.pressed.emit()
	t.refresh()
	var trace=FileAccess.open('res://../output/high-view/battle-trace.jsonl',FileAccess.WRITE)
	for frame in 1200:
		if frame==60:t.start_button.pressed.emit()
		if frame==450:
			t.assault_button.pressed.emit()
		if frame==720:
			t.zoom=.85
			t.set_camera(t.rules.projection*Vector2(1050,1190)-Vector2(960,540)/t.zoom)
		if frame==1020:t.reset_camera()
		t._process(1./30)
		if frame%30==0:
			trace.store_line(JSON.stringify({'frame':frame,'seconds':t.rules.elapsed,'phase':t.rules.phase,
				'ally_strength':t.rules.strength('ally'),'enemy_strength':t.rules.strength('enemy'),
				'units':t.rules.units.map(func(u):return {'id':u.id,'side':u.side,'kind':u.kind,'x':u.pos.x,'y':u.pos.y,'hp':u.hp,'morale':u.morale})}))
		await process_frame
	trace.close()
	print('Square film: 1200 frames, both sides exchange real attacks; final ',t.rules.phase)
	quit()
