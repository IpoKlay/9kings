extends SceneTree
## Visible loss/retry/menu UI branch checks; loss is deliberately fixture-triggered.
var out='res://../output/combat-readability-20261109/result-ui/'
var failures=0
func _initialize():call_deferred('run')
func check(ok: bool,note: String):
	if not ok:failures+=1;push_error(note)
func capture(name: String):
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out+name+'.png')
func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-readability-results.cfg';root.add_child(app)
	var samples=[]
	for cycle in 3:
		app.menu_view.get_node('%TacticalTrial').pressed.emit()
		await process_frame
		var t=app.active_trial;var ui=t.get_meta('strategy_interface')
		t.rules.buildings[0].hp=0.;t.rules.resolve_battle(0.)
		await process_frame
		check(t.rules.phase=='defeat' and ui.result_panel.visible,'Defeat reaches the actual result panel')
		if cycle==0:await capture('defeat')
		ui.result_panel.get_child(0).get_child(1).pressed.emit();await process_frame;await RenderingServer.frame_post_draw
		check(t.rules.phase=='battle' and t.rules.population()==6 and not ui.result_panel.visible,'One retry returns to six villagers and hides result')
		if cycle==0:await capture('retry')
		t.closed.emit();await process_frame
		t=null;ui=null
		await create_timer(.15).timeout
		check(not is_instance_valid(app.active_trial) and app.visible,'Returning to menu releases the active battle')
		samples.append({'cycle':cycle,'nodes':Performance.get_monitor(Performance.OBJECT_NODE_COUNT),'objects':Performance.get_monitor(Performance.OBJECT_COUNT),'static_bytes':Performance.get_monitor(Performance.MEMORY_STATIC),'texture_bytes':Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)})
	await capture('menu')
	var report={'failures':failures,'samples':samples,'scope':'Loss branch deliberately triggered by town HP=0; three real scene-entry/retry/menu cycles. Not a naturally played losing match.'}
	FileAccess.open(out+'report.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'));print('RESULT UI ',JSON.stringify(report))
	app.queue_free();await process_frame;await create_timer(.15).timeout;quit(1 if failures else 0)
