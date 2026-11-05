extends SceneTree
var out='res://../output/myth-skills-complete/'
var failures=0
func _initialize():call_deferred('run')
func check(value: bool, message: String):
	if not value:
		failures+=1
		push_error(message)
func mouse(pos: Vector2):
	for pressed in [true,false]:
		var e=InputEventMouseButton.new()
		e.button_index=MOUSE_BUTTON_LEFT
		e.pressed=pressed
		e.position=pos
		e.global_position=pos
		root.push_input(e,true)
	await process_frame
func capture(id: String):
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(out+id+'.png')
func run():
	create_timer(60).timeout.connect(func():push_error('LIVE SKILL TEST TIMEOUT');quit(1))
	var main=load('res://scenes/main.tscn').instantiate()
	main.run_path_override='user://myth-live-verification-absent.json'
	root.add_child(main)
	await process_frame
	var before=main.campaign.g.duplicate(true)
	main.language='zh'
	main.open_tactical_trial()
	await process_frame
	var trial=root.get_child(root.get_child_count()-1)
	for row in trial.rules.characters:
		trial.retry()
		trial.rules.deploy('legion',Vector2(650,500))
		trial.rules.deploy('archer',Vector2(380,650))
		if row.id=='hydra':trial.rules.alive('ally')[0].hp=500
		trial.start_button.pressed.emit()
		trial.character_picker.item_selected.emit(trial.character_ids.find(row.id))
		var pos=Vector2(650,500) if row.id=='athena' else Vector2(1000,545) if row.id=='hydra' else Vector2(1160,545)
		await mouse(trial.field.project(pos))
		await create_timer(.55).timeout
		await capture(row.id+'-impact')
		await create_timer(.65).timeout
		trial.paused=true
		await capture(row.id+'-active')
		var r=trial.rules
		check(not trial.power_note.text.contains('预览'),row.id+' still labelled preview')
		check(not trial.power_note.text.contains('{') and not trial.character_picker.tooltip_text.contains('{'),row.id+' unexpanded tuning value')
		main.language='en';trial.refresh()
		check(not trial.character_picker.tooltip_text.contains('{'),row.id+' English tuning value')
		main.language='zh';trial.refresh()
		match row.id:
			'athena':check(r.alive('ally')[0].shield>0,'Shield missing')
			'artemis':check(r.units.any(func(u):return u.marked>0),'Mark missing')
			'hephaestus':check(r.powers.zones.size()==1,'Fire field missing')
			'demeter':check(r.units.any(func(u):return u.rooted>0),'Root missing')
			'odysseus':check(not r.powers.decoys.is_empty(),'Decoys missing')
			'medusa':check(r.units.any(func(u):return u.petrified>0),'Petrification missing')
			'hydra':check(r.alive('ally')[0].hp>500 and r.units.any(func(u):return u.poison>0),'Poison/regen missing')
			_:check(r.units.any(func(u):return u.side=='enemy' and u.hp<u.max_hp),row.id+' did no damage')
		var elapsed=r.elapsed
		var units=r.units.duplicate(true)
		var decoys=r.powers.decoys.duplicate(true)
		await create_timer(.08).timeout
		check(r.elapsed==elapsed and r.units==units and r.powers.decoys==decoys,row.id+' advanced while paused')
		print('LIVE PASS ',row.id,' input, actual effect, pause, rendered evidence')
	trial.retry()
	check(trial.rules.powers.pending.is_empty() and trial.rules.powers.decoys.is_empty() and trial.rules.powers.zones.is_empty(),'Retry leaked state')
	trial.closed.emit()
	await process_frame
	check(main.visible and main.campaign.g==before,'Campaign affected')
	main.queue_free()
	await process_frame
	print('NATIVE LIVE SKILLS: ',failures,' failures')
	quit(1 if failures else 0)
