extends SceneTree
const DT=1./60
var failures=0
func _initialize():call_deferred('run')
func check(ok: bool,note: String):
	if not ok:failures+=1;push_error(note)
func run():
	var main=load('res://scenes/main.tscn').instantiate()
	main.settings_path='/tmp/eagle-single-rank.cfg'
	root.add_child(main)
	main.menu_view.get_node('%TacticalTrial').pressed.emit()
	var t=main.active_trial
	t.set_process(false)
	t.combined_button.pressed.emit()
	t.refresh()
	var r=t.rules
	for side in ['ally','enemy']:
		var army=r.alive(side)
		check(army.size()==7,'All seven arms deployed on '+side)
		for u in army:
			var feet: PackedVector2Array=r.contact_profiles[u.kind].feet
			check(feet.size()==r.Contact.count(u,r.config.types[u.kind]),'All visible slots use combat geometry')
			for i in feet.size():
				check(feet[i].y==0 and (i==0 or feet[i].x>feet[i-1].x),'Distinct feet on one baseline: '+u.kind)
	t.start_button.pressed.emit()
	check(r.phase=='battle','Official combined-arms battle started')
	await process_frame
	await process_frame
	if DisplayServer.get_name()!='headless':
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png('res://../output/single-rank/七兵种单排.png')
	t.closed.emit()
	main.queue_free()
	await process_frame
	print('Single rank failures: ',failures)
	quit(1 if failures else 0)
